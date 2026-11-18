#!/usr/bin/env python3
"""Look for code built to attack the computer that runs it, BEFORE anything in the project runs.

Reads files as data: never imports or runs them. It calls git only in a folder the user marked as
their own project (--mine), and then with everything a repo's own git settings could use to run a
command switched off; in any other folder git is never called. Standard library only. Output carries file paths, line numbers and fixed
wording, never file contents, so a hostile file can't talk to whoever reads the report.

    python3 -I hostile-code-check.py <folder> [--json]
    python3 -I hostile-code-check.py <folder> --clear <relative path>   # only on the user's word
    python3 -I hostile-code-check.py <folder> --mine | --not-mine       # only on the user's word
    python3 -I hostile-code-check.py <folder> --remember-stop | --look-again

Exit: 0 nothing found, 1 stop, 2 could not finish (not a clean result), 3 a weakness in the
user's own code to fix before carrying on (only in a folder marked --mine).
Finding nothing does not prove a project is safe: see references/hostile-code.md.
"""
import argparse
import ast
import collections
import datetime
import hashlib
import json
import math
import os
import re
import secrets
import struct
import subprocess
import sys
import unicodedata
import warnings

MAX_BYTES = 20 * 1024 * 1024
ALWAYS_SKIP = {".git"}
INSTALLED = {"node_modules", ".venv", "venv", "site-packages", "__pycache__", ".next", ".tox", ".mypy_cache"}
RUN_NAMES = {"exec", "eval", "compile"}
DECODERS = {"decompress", "b64decode", "b32decode", "b85decode", "a85decode", "urlsafe_b64decode",
            "decodebytes", "unhexlify", "a2b_base64", "fromhex"}
RUN_DOTTED = {"marshal.loads", "types.FunctionType", "types.CodeType", "runpy.run_path", "runpy.run_module"}
NATIVE_RUN = {"VirtualAlloc", "VirtualAllocEx", "CreateRemoteThread", "WriteProcessMemory", "RtlMoveMemory"}
NET_MODULES = {"requests", "httpx", "aiohttp", "urllib3", "urllib.request", "http.client", "socket"}
FILE_READ_ATTRS = {"read_text", "read_bytes", "get_data"}
LAUNCHERS = {"Popen", "run", "call", "check_call", "check_output", "system"}
STARTUP = re.compile(r"UserInit" + r"MprLogonScript|CurrentVersion\\+Run", re.I)
PROGRAM_B64 = ("TVqQ", "TVpQ", "TVro", "TVoA", "f0VMRg")
BLOB_LEN = 2000
BLOB_INTS = 1024  # across a file: a carrier splits its payload into several small arrays
INT_TABLE_MIN = 64
PROGRAM_LEN = 1000
HOOK_DANGER = re.compile(r"curl|wget|https?://|powershell|invoke-|\biwr\b|base64|node\s+-e|python3?\s+-c|\beval\b"
                         r"|bash\s+-c|\|\s*(sh|bash)\b", re.I)
NPM_OUTSIDE = re.compile(r"^(git\+|git:|github:|gitlab:|bitbucket:|https?:|ssh:|[\w.-]+/[\w.-]+(#.*)?$)")
PIP_OUTSIDE = re.compile(r"(^|\s|@\s*)(git|hg|svn)\+|@\s*https?://|^\s*https?://|--(extra-)?index-url", re.M)
TOML_OUTSIDE = re.compile(r"\bgit\s*=\s*[\"']|(git|hg|svn)\+https?://|@\s*https?://")
FOLDER_OPEN = re.compile(r"\"runOn\"\s*:\s*\"folderOpen\"")

WHY = {
    "decode-then-run": "unpacks hidden data and can run it as code",
    "read-then-run": "reads another file and can run it as code",
    "hidden-run": "hides the name of Python's run-this-code command",
    "download-then-run": "can download something and run it as code",
    "embedded-program": "carries a whole program inside a text value",
    "startup-entry": "names a Windows start-at-login setting",
    "runs-on-import": "starts a flagged file just by being loaded",
    "install-hook": "runs a command when packages are installed",
    "runs-on-folder-open": "runs a command when the folder is opened in VS Code",
    "encoded-data": "holds a large encoded value and unpacks it",
    "large-blob": "holds a large unreadable value",
    "outside-dependency": "installs code from outside the package registry",
    "program-file": "is a program file committed to the project",
    "unreadable": "could not be read as Python",
    "link-not-followed": "is a link to something outside the project, which was not read",
}
# Shapes an attacker uses. These stop in every project, the owner's own included.
# read-then-run is the one shape honest code shares: a test loading the code it checks, or a
# careless loader in the owner's own code. It is softened only in a project marked as the owner's.
SOFT = {"read-then-run"}
# Files that run on their own (pytest, pip and Python load them unasked) are never softened.
AUTO_RUN = {"conftest.py", "setup.py", "sitecustomize.py", "usercustomize.py"}


def entropy(sample):
    total = len(sample)
    return -sum(n / total * math.log2(n / total) for n in collections.Counter(sample).values())


def is_blob(value):
    data = value if isinstance(value, bytes) else value.encode("utf-8", "replace")
    if len(data) < BLOB_LEN:
        return False
    head = data[:4096]
    return sum(chr(b).isspace() for b in head) / len(head) < 0.02 and entropy(head) >= 3.9


def dotted(node, aliases):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "__import__" \
            and node.args and isinstance(node.args[0], ast.Constant):
        parts.append(str(node.args[0].value))
    elif isinstance(node, ast.Name):
        parts.append(aliases.get(node.id, node.id))
    else:
        return ""
    return ".".join(reversed(parts))


class PySignals:
    def __init__(self):
        self.first = {}  # kind -> first line
        self.named = []  # (path, line): a .py file named in open(); harmless only if this tool read it

    def hit(self, kind, line):
        self.first.setdefault(kind, line or 1)

    def __contains__(self, kind):
        return kind in self.first


def read_tree(tree):
    """One pass over a parsed file. ast.walk is iterative, so deep nesting can't overflow it."""
    s = PySignals()
    aliases, bound, nodes = {}, set(), list(ast.walk(tree))
    for n in nodes:
        if isinstance(n, ast.Import):
            for a in n.names:
                aliases[(a.asname or a.name).split(".")[0]] = a.name if a.asname else a.name.split(".")[0]
                if a.name in NET_MODULES:
                    s.hit("net", n.lineno)
                if a.name == "subprocess":
                    s.hit("launch", n.lineno)
                if a.name in ("winreg", "_winreg"):
                    s.hit("registry", n.lineno)
        elif isinstance(n, ast.ImportFrom):
            mod = n.module or ""
            if mod in NET_MODULES:
                s.hit("net", n.lineno)
            if mod == "subprocess":
                s.hit("launch", n.lineno)
            if mod in ("winreg", "_winreg"):
                s.hit("registry", n.lineno)
            for a in n.names:
                aliases[a.asname or a.name] = f"{mod}.{a.name}"
                if mod != "builtins":
                    bound.add(a.asname or a.name)
                elif a.name in RUN_NAMES:
                    s.hit("run", n.lineno)
        elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            bound.add(n.name)
    used = {n.id for n in nodes if isinstance(n, ast.Name)}
    for name, full in aliases.items():
        if name in used and full.rsplit(".", 1)[-1] in DECODERS:
            s.hit("decode", 1)
    handled = set()  # the Name inside a call already judged by read_call
    int_total = 0
    for n in nodes:
        if isinstance(n, ast.Call):
            read_call(n, aliases, bound, s, handled)
    for n in nodes:
        line = getattr(n, "lineno", 1)
        if isinstance(n, ast.Name):
            if n.id in RUN_NAMES and n.id not in bound and id(n) not in handled:
                s.hit("run", line)  # passed around rather than called: `q = exec`
        elif isinstance(n, ast.Attribute):
            name = dotted(n, aliases)
            if n.attr in NATIVE_RUN:
                s.hit("run", line)
            if n.attr in DECODERS or name == "codecs.decode":
                s.hit("decode", line)
            if n.attr in ("urlopen", "urlretrieve"):
                s.hit("net", line)
            if name == "os.system":
                s.hit("launch", line)
        elif isinstance(n, ast.BinOp) and isinstance(n.op, ast.Add) and all(
                isinstance(x, ast.Constant) and isinstance(x.value, str) and len(x.value) < 8
                for x in (n.left, n.right)):
            s.hit("built-name", line)  # 'ex' + 'ec'
        elif isinstance(n, (ast.ListComp, ast.GeneratorExp, ast.SetComp)):
            if any(isinstance(c, ast.BinOp) and isinstance(c.op, ast.BitXor) for c in ast.walk(n)):
                s.hit("decode", line)
                s.hit("xor", line)
        elif isinstance(n, ast.Subscript):
            read_subscript(n, aliases, s, line)
        elif isinstance(n, ast.Constant) and isinstance(n.value, (str, bytes)):
            read_constant(n.value, s, line)
        elif isinstance(n, (ast.List, ast.Tuple)) and len(n.elts) >= INT_TABLE_MIN:
            int_total += read_int_table(n.elts, s, line)
    if int_total >= BLOB_INTS:
        s.hit("blob", 1)
    return s, aliases


def run_key(key, s, line):
    """A builtin looked up by a value. A plain variable is how interpreters work, so it needs company."""
    if isinstance(key, ast.Constant):
        if key.value in RUN_NAMES:
            s.hit("run", line)
    elif isinstance(key, ast.Name):
        s.hit("dynamic-import", line)
    else:
        s.hit("hidden", line)


def has_decoder(node):
    return any(isinstance(c, ast.Attribute) and c.attr in DECODERS or isinstance(c, ast.BinOp)
               and isinstance(c.op, ast.BitXor) for c in ast.walk(node))


def reads_a_file(node):
    return any(isinstance(c, ast.Attribute) and c.attr in FILE_READ_ATTRS | {"read"} for c in ast.walk(node))


def settle(s, rel, known, root=None):
    """A .py file named in open() counts as a read unless it is one of the files this tool read.
    Python finds the name from wherever it is run, which this tool can't know, so the name is
    looked up beside the file that names it and from the project's top folder: at least one must
    be a file that was read, and neither may be something else. A name that climbs out of a
    folder ("..") is never trusted."""
    here = os.path.dirname(rel)
    for name, line in s.named:
        tries = [os.path.normpath(os.path.join(here, name)), os.path.normpath(name)]
        climbs = os.path.isabs(name) or ".." in name.replace("\\", "/").split("/")
        other = any(t not in known and root is not None and os.path.lexists(os.path.join(root, t)) for t in tries)
        if climbs or other or not any(t in known for t in tries):
            s.hit("read", line)
    return s


def names_python_file(args):
    return bool(args) and isinstance(args[0], ast.Constant) and str(args[0].value).endswith((".py", ".pyw"))


def read_call(n, aliases, bound, s, handled):
    """A fixed string can't hide anything, so exec/compile/eval on one don't count."""
    f, line = n.func, n.lineno
    # A payload can sit in a file this tool never reads. A .py file named outright usually does get
    # read, but not always (a link, a .git folder, a skipped folder): settle() decides, per file.
    if dotted(f, aliases) in ("open", "io.open", "codecs.open"):
        if names_python_file(n.args):
            s.named.append((str(n.args[0].value), line))
        else:
            s.hit("read", line)
    if isinstance(f, ast.Attribute) and f.attr in FILE_READ_ATTRS:
        if isinstance(f.value, ast.Call) and names_python_file(f.value.args):
            s.named.append((str(f.value.args[0].value), line))
        else:
            s.hit("read", line)
    if isinstance(f, ast.Name) and f.id in RUN_NAMES and f.id not in bound:
        handled.add(id(f))
        if n.args and not isinstance(n.args[0], ast.Constant):
            if f.id != "eval" or has_decoder(n.args[0]) or reads_a_file(n.args[0]):
                s.hit("run", line)
            else:
                s.hit("weak-run", line)  # eval(x): only counts with a payload or XOR nearby
    elif dotted(f, aliases) in RUN_DOTTED:
        s.hit("run", line)
    if isinstance(f, ast.Name) and f.id == "getattr" and len(n.args) >= 2 \
            and dotted(n.args[0], aliases) in ("builtins", "__builtins__"):
        run_key(n.args[1], s, line)
    if (dotted(f, aliases) in ("__import__", "importlib.import_module")) and n.args \
            and not isinstance(n.args[0], ast.Constant):
        s.hit("dynamic-import", line)  # ordinary plugin loading, unless the file also decodes


def read_subscript(n, aliases, s, line):
    base = n.value
    if (isinstance(base, ast.Attribute) and base.attr == "__dict__" and dotted(base.value, aliases) == "builtins") or (
            isinstance(base, ast.Call) and isinstance(base.func, ast.Name) and base.func.id == "vars"
            and base.args and dotted(base.args[0], aliases) == "builtins") or (
            isinstance(base, ast.Name) and base.id == "__builtins__"):
        run_key(n.slice, s, line)


def read_constant(value, s, line):
    if isinstance(value, str) and STARTUP.search(value):
        s.hit("startup", line)
    if isinstance(value, str) and len(value) >= PROGRAM_LEN and value.startswith(PROGRAM_B64):
        s.hit("program", line)
    if isinstance(value, bytes) and len(value) >= PROGRAM_LEN and value[:2] == b"MZ":
        s.hit("program", line)
    if isinstance(value, bytes) and len(value) >= PROGRAM_LEN and value[:4] == b"\x7fELF":
        s.hit("program", line)
    if is_blob(value):
        s.hit("blob", line)


def read_int_table(elts, s, line):
    """The table's length if it is all byte values, else 0."""
    ints = [e.value for e in elts if isinstance(e, ast.Constant) and type(e.value) is int and 0 <= e.value <= 255]
    if len(ints) != len(elts):
        return 0
    if len(ints) >= PROGRAM_LEN and ints[:2] == [77, 90]:
        s.hit("program", line)
    return len(ints)


def verdicts(s):
    """(signal, line, is_stop) for one Python file. Combinations, because honest code uses exec."""
    out = []

    def add(signal, kind, stop=True):
        out.append((signal, s.first.get(kind), stop))
    if "hidden" in s:
        add("hidden-run", "hidden")
    elif "dynamic-import" in s and ("decode" in s or "built-name" in s):
        add("hidden-run", "dynamic-import")
    if "run" in s and ("decode" in s or "blob" in s):
        add("decode-then-run", "run")
    elif "weak-run" in s and ("blob" in s or "xor" in s):
        add("decode-then-run", "weak-run")
    elif "blob" in s and "decode" in s and ("net" in s or "launch" in s):
        add("decode-then-run", "blob")
    if "run" in s and "read" in s:
        add("read-then-run", "run")
    if "run" in s and "net" in s:
        add("download-then-run", "run")
    if "program" in s:
        add("embedded-program", "program")
    if "startup" in s:  # security tools name these keys all the time; writing one is the attack
        add("startup-entry", "startup", "registry" in s or "launch" in s)
    if not any(stop for _, _, stop in out) and "blob" in s:
        add("encoded-data" if "decode" in s else "large-blob", "blob", False)
    return out


def text_verdicts(raw):
    """A file Python can't parse here (too new, too old, deliberately broken) still gets a text read."""
    text = raw.decode("utf-8", "replace")

    def line(pattern):
        m = re.search(pattern, text)
        return text.count("\n", 0, m.start()) + 1 if m else None
    run = line(r"\b(exec|eval)\s*\(")
    out = []
    if run and line(r"decompress|b64decode|fromhex|unhexlify"):
        out.append(("decode-then-run", run, True))
    if run and line(r"urlopen|requests\.(get|post)"):
        out.append(("download-then-run", run, True))
    if line(STARTUP.pattern):
        out.append(("startup-entry", line(STARTUP.pattern), bool(line(r"winreg|subprocess|os\.system"))))
    return out


def module_level(tree):
    """Every node that runs when the file is loaded: nothing inside a function."""
    stack = list(tree.body)
    while stack:
        n = stack.pop()
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            continue
        yield n
        stack.extend(ast.iter_child_nodes(n))


def import_time_targets(tree, rel, known):
    """Project files this one starts at import, by calling into them or launching them."""
    here = os.path.dirname(rel)
    local = {}

    def bind(name, candidates):
        for cand in candidates:
            cand = os.path.normpath(cand)
            if cand in known:
                local[name] = cand
                return

    nodes = list(module_level(tree))
    for n in nodes:
        if isinstance(n, ast.ImportFrom):
            base = here
            for _ in range(max(n.level - 1, 0)):
                base = os.path.dirname(base)
            mod = (n.module or "").replace(".", "/")
            for a in n.names:
                bind(a.asname or a.name, [os.path.join(base, mod, a.name + ".py"), os.path.join(base, mod + ".py"),
                                          os.path.join(mod, a.name + ".py"), mod + ".py"])
        elif isinstance(n, ast.Import):
            for a in n.names:
                mod = a.name.replace(".", "/") + ".py"
                bind(a.asname or a.name.split(".")[0], [os.path.join(here, mod), mod])
    targets = {}
    for n in nodes:
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        base = f.value if isinstance(f, ast.Attribute) else f
        if isinstance(base, ast.Name) and base.id in local:
            targets.setdefault(local[base.id], n.lineno)
        if (f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")) in LAUNCHERS:
            for c in ast.walk(n):
                if isinstance(c, ast.Constant) and isinstance(c.value, str) and c.value.endswith(".py"):
                    for cand in (os.path.normpath(c.value), os.path.normpath(os.path.join(here, c.value))):
                        if cand in known:
                            targets.setdefault(cand, n.lineno)
    return list(targets.items())


def parse(raw):
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            return ast.parse(raw)
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return None


def check_package_json(raw):
    data = json.loads(raw.decode("utf-8", "replace"))
    out = []
    if not isinstance(data, dict):
        return out
    scripts = data.get("scripts")
    for hook in ("preinstall", "install", "postinstall", "prepare"):
        body = scripts.get(hook) if isinstance(scripts, dict) else None
        if isinstance(body, str):
            out.append(("install-hook", 1, bool(HOOK_DANGER.search(body))))
    for group in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        deps = data.get(group)
        if isinstance(deps, dict) and any(isinstance(v, str) and NPM_OUTSIDE.match(v) for v in deps.values()):
            out.append(("outside-dependency", 1, False))
            break
    return out


def is_worktree_of(root, folder):
    """True only when git on this computer registered `folder` as another working copy of root's
    project: the folder points into root's registry and the registry points back at the folder.
    A clone cannot bring either side with it (git never tracks a `.git` entry)."""
    marker = os.path.join(folder, ".git")
    try:
        if os.path.islink(marker) or not os.path.isfile(marker) or os.path.getsize(marker) > 4096:
            return False
        with open(marker, encoding="utf-8") as f:
            text = f.read().strip()
        if not text.startswith("gitdir:"):
            return False
        entry = os.path.realpath(os.path.join(folder, text[7:].strip()))
        if os.path.dirname(entry) != os.path.realpath(os.path.join(root, ".git", "worktrees")):
            return False
        with open(os.path.join(entry, "gitdir"), encoding="utf-8") as f:
            back = f.read(4096).strip()
        return os.path.realpath(os.path.join(entry, back)) == os.path.realpath(marker)
    except (OSError, ValueError):
        return False


def fold(name):
    """A file name as a file system that ignores case and letter form sees it."""
    return unicodedata.normalize("NFKC", name).casefold()


def is_test(rel):
    """A test file, by the usual names. conftest.py is not one here: pytest runs it on its own,
    which is exactly where a fake project puts a payload."""
    rel = rel.replace(os.sep, "/")
    base = fold(rel.rsplit("/", 1)[-1])
    if base in AUTO_RUN:
        return False
    return bool(re.search(r"(^|/)tests?/", fold(rel))) or base.startswith("test_") \
        or base.endswith(("_test.py", "_test.pyw"))


def owner_home(root):
    """(project root, its .git folder) for the project this folder belongs to, or None when it is
    not a git project. A registered working copy belongs to its main project."""
    dot = os.path.join(root, ".git")
    if os.path.isdir(dot) and not os.path.islink(dot):
        return os.path.realpath(root), dot
    try:
        if os.path.islink(dot) or not os.path.isfile(dot) or os.path.getsize(dot) > 4096:
            return None
        with open(dot, encoding="utf-8") as f:
            text = f.read().strip()
        entry = os.path.realpath(os.path.join(root, text[7:].strip())) if text.startswith("gitdir:") else ""
        common = os.path.dirname(os.path.dirname(entry))
        main = os.path.dirname(common)
        if entry and os.path.basename(common) == ".git" and is_worktree_of(main, root):
            return main, common
    except (OSError, ValueError):
        pass
    return None


def owner_token(gitdir):
    """The mark the user's --mine left inside the project's .git folder. git never tracks anything
    in there, so a clone, a download or a folder made again cannot bring a matching one."""
    path = os.path.join(gitdir, "make-it-owner")
    try:
        if os.path.islink(path) or not os.path.isfile(path) or os.path.getsize(path) > 128:
            return ""
        with open(path, encoding="ascii") as f:
            return f.read().strip()
    except (OSError, ValueError):
        return ""


def is_mine(root, projects):
    home = owner_home(root)
    if not home:
        return False
    rec = (projects or {}).get(home[0])
    token = rec.get("token") if isinstance(rec, dict) and rec.get("mine") else ""
    return bool(token) and isinstance(token, str) and owner_token(home[1]) == token


def git_exe(root):
    """An absolute path to git that the project cannot supply: PATH entries that are relative, or
    inside the project, are skipped."""
    home = owner_home(root)
    bases = {os.path.realpath(root)} | ({home[0]} if home else set())

    def inside(path):
        real = os.path.realpath(path)
        return any(real == b or real.startswith(b + os.sep) for b in bases)

    for d in os.environ.get("PATH", "").split(os.pathsep):
        exe = os.path.join(d, "git")
        if os.path.isabs(d) and not inside(d) and os.path.isfile(exe) and os.access(exe, os.X_OK) \
                and not inside(exe):  # a link named git that points into the project is the project's git
            return exe
    return None


def run_git(exe, root, *args, stdin=None):
    """git, for a project its owner marked as their own, and never otherwise. Plumbing commands
    only, with everything a repository's own settings could use to run a command switched off:
    no fetch of missing objects, no prompts, no pager, no file monitor, no hooks, no replaced
    objects, and the user's and the system's git settings left out. Bytes, or None on any failure:
    a failure must never read as an empty, harmless answer."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_NO_LAZY_FETCH="1", GIT_TERMINAL_PROMPT="0", GIT_OPTIONAL_LOCKS="0", GIT_PAGER="cat",
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_ASKPASS="true")
    cmd = [exe, "-C", root, "--no-pager", "--no-replace-objects",
           "-c", "protocol.allow=never", "-c", "core.fsmonitor=false", "-c", "safe.bareRepository=explicit",
           "-c", "core.alternateRefsCommand=", "-c", "core.hooksPath=" + os.devnull,
           "-c", "log.showSignature=false", "-c", "core.pager=cat", *args]
    try:
        r = subprocess.run(cmd, input=stdin, stdin=None if stdin is not None else subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20, env=env, cwd=os.sep)
        return r.stdout if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def passes(base, raw):
    """True when this content, read on its own, has nothing that stops and can be read."""
    try:
        if not base.lower().endswith((".py", ".pyw")):
            return not any(stop for _, _, stop in check_config(base, raw))
        tree = parse(raw)
        # judged alone, with no other file known to have been read
        return tree is not None and not any(stop for _, _, stop in verdicts(settle(read_tree(tree)[0], base, set())))
    except (ValueError, RecursionError, MemoryError):
        return False


def stale_copies(root, gitsha):
    """{file: commit} for each file here that is an old copy. All of these must hold:
    this checkout is behind the main line (it forked from a commit that is not the main line's
    newest); the file is byte for byte what that fork commit had; the main line has a different
    file at that path now; and that newer file passes the check. A file the main line deleted, a
    file changed since the fork, and a checkout that is level with the main line are never old
    copies: a downloaded payload is current, not old."""
    root = os.path.realpath(root)  # git is started from the top folder, never from inside the project
    exe = git_exe(root)
    if not exe:
        return {}
    # Before 2.45 git ignores GIT_NO_LAZY_FETCH, and a repository set up to fetch missing objects on
    # demand could then run its own command. Older git: no lookup, so nothing is softened.
    try:
        v = subprocess.run([exe, "--version"], cwd=os.sep, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=20).stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return {}
    m = re.search(r"(\d+)\.(\d+)", v)
    if not m or (int(m.group(1)), int(m.group(2))) < (2, 45):
        return {}

    def one(*args):
        out = run_git(exe, root, *args)
        return out.decode("utf-8", "replace").strip() if out else ""

    ref = one("symbolic-ref", "-q", "refs/remotes/origin/HEAD")
    for cand in ("refs/remotes/origin/main", "refs/remotes/origin/master", "refs/heads/main", "refs/heads/master"):
        if ref:
            break
        if one("rev-parse", "-q", "--verify", cand + "^{commit}"):
            ref = cand
    tip = one("rev-parse", "-q", "--verify", ref + "^{commit}") if ref else ""
    head = one("rev-parse", "-q", "--verify", "HEAD^{commit}")
    fork = one("merge-base", head, tip) if head and tip else ""
    if not fork or fork == tip:
        return {}
    prefix = run_git(exe, root, "rev-parse", "--show-prefix")
    if prefix is None:
        return {}
    prefix = prefix.decode("utf-8", "replace").strip()
    out = {}
    for rel, ours in gitsha.items():
        path = prefix + rel.replace(os.sep, "/")
        if "\n" in path or path.startswith(":"):  # a leading colon is git's own path syntax
            continue
        def plain_file(commit):
            """The blob at this path in this commit, only when it is an ordinary file (not a link,
            a folder or another repository)."""
            line = one("ls-tree", commit, "--", path)
            meta = line.split("\t", 1)[0].split(" ")
            return meta[2] if len(meta) == 3 and meta[0].startswith("100") and meta[1] == "blob" else ""

        if plain_file(fork) != ours:
            continue
        now = plain_file(tip)
        if not now or now == ours:
            continue
        raw = run_git(exe, root, "cat-file", "blob", now)
        if raw is None or not passes(os.path.basename(rel), raw):
            continue
        commit = one("rev-list", "-1", tip, "--", path)
        if commit:
            out[rel] = commit[:8]
    return out


def tracked_folders(raw):
    """Every folder name that holds a file git tracks, read from a git index (versions 2 to 4), or
    None when the index can't be read exactly. Looking for a folder's name anywhere in the file is
    not enough: version 4 stores each path as what it shares with the one before, and a file that
    only starts like an index proves nothing."""
    try:
        if raw[:4] != b"DIRC":
            return None
        version, count = struct.unpack(">II", raw[4:12])
        if version not in (2, 3, 4):
            return None
        pos, prev, names = 12, b"", set()
        for _ in range(count):
            flags = struct.unpack(">H", raw[pos + 60:pos + 62])[0]
            start = pos + 62 + (2 if flags & 0x4000 and version >= 3 else 0)
            if version == 4:
                byte = raw[start]
                strip, start = byte & 0x7F, start + 1
                while byte & 0x80:
                    byte = raw[start]
                    strip, start = ((strip + 1) << 7) | (byte & 0x7F), start + 1
                end = raw.index(b"\0", start)
                if strip > len(prev):
                    return None
                path, pos = prev[:len(prev) - strip] + raw[start:end], end + 1
            else:
                end = raw.index(b"\0", start)
                path, pos = raw[start:end], pos + ((end - pos + 8) & ~7)  # padded to a multiple of 8
            names.update(path.split(b"/")[:-1])
            prev = path
        while pos + 8 <= len(raw) - 20:  # the extensions that follow, then a 20-byte checksum
            name, size = raw[pos:pos + 4], struct.unpack(">I", raw[pos + 4:pos + 8])[0]
            if name == b"link":
                return None  # a split index keeps most paths in another file
            pos += 8 + size
        return names if pos == len(raw) - 20 else None
    except (struct.error, ValueError, IndexError):
        return None


def walk(root, skipped, worktrees, mine=False, nested=None):
    try:
        with open(os.path.join(root, ".git", "index"), "rb") as f:
            tracked = tracked_folders(f.read())
    except OSError:
        tracked = None  # no git record, as in a zip download: a folder's name proves nothing
    for folder, dirs, files in os.walk(root):
        keep = []
        for d in dirs:
            if d in ALWAYS_SKIP:
                continue
            if os.path.islink(os.path.join(folder, d)):
                # never walked into; scan() reports one that leaves the project
                yield os.path.join(folder, d), os.path.relpath(os.path.join(folder, d), root)
                continue
            # Another working copy of this project is checked when work happens there, not from here:
            # a project with dozens of them would otherwise be read dozens of times over. Only in a
            # project the user marked as their own: a downloaded archive can carry both halves of a
            # working copy's registration, and would hide a folder from the check that way.
            sub = os.path.join(folder, d)
            if is_worktree_of(root, sub):
                worktrees.add(os.path.relpath(sub, root))
                if mine:
                    continue
            elif nested is not None and os.path.lexists(os.path.join(sub, ".git")):
                nested.add(os.path.relpath(sub, root))  # somebody else's repository inside this one
            # A committed folder is project code whatever its name: only a real install is skipped.
            if d in INSTALLED and tracked is not None and d.encode() not in tracked:
                skipped.add(d)
                continue
            keep.append(d)
        dirs[:] = keep
        for name in files:
            path = os.path.join(folder, name)
            if os.path.isfile(path):  # a link to a file is yielded too: scan() decides what it is
                yield path, os.path.relpath(path, root)


def check_config(base, raw):
    text = raw.decode("utf-8", "replace")
    if base == "package.json":
        return check_package_json(raw)
    if base == "tasks.json":
        return [("runs-on-folder-open", 1, True)] if FOLDER_OPEN.search(text) else []
    pattern = TOML_OUTSIDE if base == "pyproject.toml" else PIP_OUTSIDE
    return [("outside-dependency", 1, False)] if pattern.search(text) else []


def scan(root, cleared, projects=None):
    report = {"status": "clear", "stop": [], "fix": [], "notes": [], "cleared": [], "not_checked": [],
              "skipped": [], "worktrees": [], "checked": 0, "mine": False, "stopped_earlier": None}
    if not os.path.isdir(root):
        report.update(status="incomplete", not_checked=[root])
        return report
    skipped, found, trees, hashes, gitsha = set(), collections.defaultdict(list), {}, {}, {}
    worktrees, nested = set(), set()
    record = (projects or {}).get(os.path.realpath(root))
    record = record if isinstance(record, dict) else {}
    mine = is_mine(root, projects)
    report["mine"] = mine

    def foreign(rel):
        """Under a repository of its own inside this project: not the owner's word to give."""
        return any(rel == n or rel.startswith(n + os.sep) for n in nested)
    entries = list(walk(root, skipped, worktrees, mine, nested))
    report["worktrees"] = sorted(worktrees) if mine else []
    report["worktrees_read"] = 0 if mine else len(worktrees)
    top = os.path.realpath(root)

    def leaves(path):
        """A link whose target is not inside this project."""
        real = os.path.realpath(path)
        return os.path.islink(path) and real != top and not real.startswith(top + os.sep)
    known = {rel for path, rel in entries if rel.endswith((".py", ".pyw")) and not leaves(path)}

    for path, rel in entries:
        base = os.path.basename(rel)
        is_py = rel.endswith((".py", ".pyw"))
        is_config = base in ("package.json", "pyproject.toml") or re.fullmatch(r"requirements.*\.txt", base) \
            or rel.replace(os.sep, "/").endswith(".vscode/tasks.json")
        if os.path.islink(path):
            # Python runs what a link points at. One that stays inside the project is read through
            # below: a download can ship the target under a harmless name. One that leaves the
            # project points at files the project did not bring, so it is never opened; a code file
            # linked that way is a note. Linked folders are not walked: one inside the project is
            # read where it really is, and one outside is usually a tool's cache.
            if os.path.isdir(path) or not (is_py or is_config):
                continue
            if leaves(path):
                found[rel].append(("link-not-followed", 1, False))
                continue
        try:
            with open(path, "rb") as f:
                head = f.read(4)
            if head[:2] == b"MZ" or head == b"\x7fELF" or base.lower().endswith((".exe", ".dll", ".scr")):
                found[rel].append(("program-file", 1, False))
            if not (is_py or is_config):
                continue
            if os.path.getsize(path) > MAX_BYTES:
                report["not_checked"].append(rel)
                continue
            with open(path, "rb") as f:
                raw = f.read()
            hashes[rel] = hashlib.sha256(raw).hexdigest()
            gitsha[rel] = hashlib.sha1(b"blob %d\0" % len(raw) + raw).hexdigest()
            report["checked"] += 1
            if not is_py:
                found[rel].extend(check_config(base, raw))
                continue
            tree = parse(raw)
            if tree is None:
                report["not_checked"].append(rel)
                found[rel].extend(text_verdicts(raw))
            else:
                trees[rel] = tree
                found[rel].extend(verdicts(settle(read_tree(tree)[0], rel, known, root)))
        except (OSError, ValueError, RecursionError, MemoryError):
            report["not_checked"].append(rel)

    def is_cleared(rel):
        return hashes.get(rel) in cleared

    flagged = {rel for rel, items in found.items() if not is_cleared(rel) and any(
        stop or sig == "encoded-data" for sig, _, stop in items)}
    # Old copies, looked up in git only for a project its owner marked as their own.
    held = {rel for rel in set(report["not_checked"]) | {r for r in flagged if any(st for _, _, st in found[r])}
            if rel in gitsha and not is_cleared(rel) and not foreign(rel)}
    stale = stale_copies(root, {rel: gitsha[rel] for rel in held}) if mine and held else {}
    # An old copy stays in `flagged`: a file that starts it on import is still a stop.
    extras = {}
    for rel, tree in trees.items():
        stubs = sum(1 for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
                    and len(n.body) == 1 and (isinstance(n.body[0], ast.Pass) or (
                        isinstance(n.body[0], ast.Expr) and getattr(n.body[0].value, "value", 0) is Ellipsis)))
        for target, line in import_time_targets(tree, rel, known):
            if target in flagged and target != rel:
                found[rel].append(("runs-on-import", line, True))
                extras[(rel, line)] = {"target": target, "empty_functions": stubs}

    unread = set(report["not_checked"])
    for rel in sorted(set(found) | unread):
        items = sorted(set(found.get(rel, ())))
        if rel in unread and rel in hashes:
            items = items or [("unreadable", 1, False)]
        if items and is_cleared(rel):
            report["cleared"].append({"file": rel, "signals": sorted({i[0] for i in items})})
            unread.discard(rel)
            continue
        for sig, line, stop in items:
            entry = {"file": rel, "line": line, "signal": sig, "why": WHY[sig]}
            if sig == "runs-on-import":
                entry.update(extras[(rel, line)])
            kind = "stop" if stop else "notes"
            if rel in stale and (sig in SOFT or sig == "unreadable" or not stop) \
                    and fold(os.path.basename(rel)) not in AUTO_RUN:
                # only the soft findings: code shaped like an attack stops even as an old copy
                kind, entry["reason"] = "notes", f"old copy: the main line replaced it in {stale[rel]}"
            elif sig == "unreadable":
                continue  # reported under not_checked
            elif mine and stop and sig in SOFT and fold(os.path.basename(rel)) not in AUTO_RUN \
                    and not foreign(rel):
                if is_test(rel):
                    kind, entry["reason"] = "notes", "a test in your own project that loads code to check it"
                else:
                    kind = "fix"
            report[kind].append(entry)
        if rel in stale:
            unread.discard(rel)
    report["skipped"] = sorted(skipped)
    report["not_checked"] = sorted(unread)
    held = sorted({f["file"] for f in report["stop"]} | unread)
    # A file with no hash (too large, unreadable) can't be told from its next version, so a result
    # that holds one is never remembered.
    report["fingerprint"] = hashlib.sha256(json.dumps(
        [(rel, hashes[rel]) for rel in held]).encode()).hexdigest() if held and all(r in hashes for r in held) else ""
    earlier = record.get("stopped")
    if held and isinstance(earlier, dict) and earlier.get("fingerprint") == report["fingerprint"]:
        report["stopped_earlier"] = str(earlier.get("date", ""))
    if report["stop"]:
        report["status"] = "stop"
    elif report["not_checked"]:
        report["status"] = "incomplete"
    elif report["fix"]:
        report["status"] = "fix"
    elif not report["checked"]:
        report["status"] = "nothing-to-check"
    return report


def safe(path):
    return json.dumps(path)[1:-1]  # ASCII, one line: a hostile file name can't forge report lines


def show(r):
    if r["stopped_earlier"]:
        print(f"STOPPED EARLIER -- you chose to stop here on {safe(r['stopped_earlier'])} and nothing has "
              "changed since. Say 'look again' to go through it again.")
    if r["status"] == "stop":
        print("STOP -- do not install or run this project yet:")
    elif r["status"] == "incomplete":
        print("COULD NOT FINISH -- this is not a clean result.")
    elif r["status"] == "fix":
        print(f"FIX FIRST -- nothing found that attacks this computer in {r['checked']} files, but your own "
              "code has a weakness to fix before carrying on:")
    elif r["status"] == "nothing-to-check":
        print("Nothing to check: no Python files, package.json, requirements or VS Code tasks here.")
    else:
        print(f"Nothing found in {r['checked']} files. That does not prove the project is safe.")
    for f in r["stop"]:
        extra = f" -> {safe(f['target'])}" if "target" in f else ""
        print(f"  {safe(f['file'])}:{f['line']} {f['signal']}: {f['why']}{extra}")
    for f in r["fix"]:
        print(f"  fix {safe(f['file'])}:{f['line']} {f['signal']}: {f['why']}")
    for f in r["notes"]:
        reason = f" ({f['reason']})" if "reason" in f else ""
        print(f"  note {safe(f['file'])}:{f['line']} {f['signal']}: {f['why']}{reason}")
    for path in r["not_checked"]:
        print(f"  not checked: {safe(path)}")
    for f in r["cleared"]:
        print(f"  cleared by the user earlier: {safe(f['file'])}")
    if r["skipped"]:
        print("  not read (installed packages): " + ", ".join(r["skipped"]))
    if r["worktrees"]:
        names = ", ".join(safe(w) for w in r["worktrees"][:3]) + (", ..." if len(r["worktrees"]) > 3 else "")
        print(f"  not read ({len(r['worktrees'])} other working copies of this project, each checked "
              f"when work happens there): {names}")
    if r.get("worktrees_read"):
        print(f"  read {r['worktrees_read']} other working copies of this project too. In a project marked "
              "as your own they are left out, which is much faster.")


def load_cleared(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError, RecursionError):
        return {}


def save(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


def remember(projects_file, root, **change):
    """Set (or, with None, forget) answers for this folder. Kept outside every project."""
    data = load_cleared(projects_file)
    key = os.path.realpath(root)
    rec = data.get(key) if isinstance(data.get(key), dict) else {}
    for name, value in change.items():
        if value is None:
            rec.pop(name, None)
        else:
            rec[name] = value
    data[key] = rec
    save(projects_file, data)


def mark_mine(projects_file, root, today):
    """--mine: a fresh random mark inside the project's .git folder, and the same mark kept outside.
    Both must match for the folder to count as the user's own."""
    home = owner_home(root)
    if not home:
        print("Not marked: only a git project can be marked as your own.")
        return 2
    token = secrets.token_hex(16)
    path = os.path.join(home[1], "make-it-owner")
    if os.path.lexists(path) and (os.path.islink(path) or not os.path.isfile(path)):
        print("Not marked: the mark's place inside .git is not an ordinary file.")
        return 2
    with open(path, "w", encoding="ascii") as f:
        f.write(token + "\n")
    remember(projects_file, home[0], mine=today, token=token)
    print("Remembered: this folder is your own project.")
    return 0


def clear(root, rel, cleared_file):
    base = os.path.realpath(root)
    path = os.path.realpath(os.path.join(root, rel))
    if not path.startswith(base + os.sep) or not os.path.isfile(path):
        print(f"Not cleared: {safe(rel)} is not a file inside this project.")
        return 2
    if os.path.getsize(path) > MAX_BYTES:
        print(f"Not cleared: {safe(rel)} is too large to check, so it can't be told from a changed copy.")
        return 2
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    data = load_cleared(cleared_file)
    data[digest] = os.path.relpath(path, base)
    save(cleared_file, data)
    print(f"Cleared {safe(rel)} as it is now. Any change to the file flags it again.")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Look for code built to attack the computer that runs it.")
    ap.add_argument("folder")
    ap.add_argument("--json", action="store_true")
    one = ap.add_mutually_exclusive_group()
    one.add_argument("--clear", metavar="RELATIVE_PATH")
    # Kept outside every project: a list inside a repo could clear that repo's own malware.
    ap.add_argument("--cleared-file", default=os.path.join(
        os.path.expanduser("~"), ".claude", "make-it", "hostile-code-cleared.json"))
    # The owner's answers about a folder: also outside every project, for the same reason.
    ap.add_argument("--projects-file", default=os.path.join(
        os.path.expanduser("~"), ".claude", "make-it", "hostile-code-projects.json"))
    one.add_argument("--mine", action="store_true", help="the user said this folder is their own project")
    one.add_argument("--not-mine", action="store_true")
    one.add_argument("--remember-stop", action="store_true", help="the user chose to stop on this result")
    one.add_argument("--look-again", action="store_true")
    args = ap.parse_args()
    try:
        os.nice(19)  # a check, never a reason for the computer to feel slow
    except (AttributeError, OSError):
        pass
    if args.clear:
        return clear(args.folder, args.clear, args.cleared_file)
    today = datetime.date.today().isoformat()
    if args.mine:
        return mark_mine(args.projects_file, args.folder, today)
    if args.not_mine:
        home = owner_home(args.folder)
        if home:
            remember(args.projects_file, home[0], mine=None, token=None)
        print("Forgotten: this folder is no longer marked as your own project.")
        return 0
    if args.look_again and os.path.isdir(args.folder):
        remember(args.projects_file, args.folder, stopped=None)
    report = scan(args.folder, load_cleared(args.cleared_file), load_cleared(args.projects_file))
    if args.remember_stop and report["fingerprint"]:
        remember(args.projects_file, args.folder, stopped={"fingerprint": report["fingerprint"], "date": today})
        report["stopped_earlier"] = today
    if args.json:
        print(json.dumps(report, indent=1))
    else:
        show(report)
    return {"stop": 1, "incomplete": 2, "fix": 3}.get(report["status"], 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # a crash must never read as exit 1 (stop) or as clean
        print(f"COULD NOT FINISH ({type(e).__name__}) -- this is not a clean result.")
        sys.exit(2)
