#!/usr/bin/env python3
"""Look for code built to attack the computer that runs it, BEFORE anything in the project runs.

Reads files as data: never imports or runs them, and never calls git (a repo's own git settings
can run commands). Standard library only. Output carries file paths, line numbers and fixed
wording, never file contents, so a hostile file can't talk to whoever reads the report.

    python3 -I hostile-code-check.py <folder> [--json]
    python3 -I hostile-code-check.py <folder> --clear <relative path>   # only on the user's word

Exit: 0 nothing found, 1 stop, 2 could not finish (not a clean result).
Finding nothing does not prove a project is safe: see references/hostile-code.md.
"""
import argparse
import ast
import collections
import hashlib
import json
import math
import os
import re
import sys
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
}


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


def names_python_file(args):
    return bool(args) and isinstance(args[0], ast.Constant) and str(args[0].value).endswith((".py", ".pyw"))


def read_call(n, aliases, bound, s, handled):
    """A fixed string can't hide anything, so exec/compile/eval on one don't count."""
    f, line = n.func, n.lineno
    # A payload can sit in a file this tool never reads. A .py file named outright does get read.
    if dotted(f, aliases) in ("open", "io.open", "codecs.open") and not names_python_file(n.args):
        s.hit("read", line)
    if isinstance(f, ast.Attribute) and f.attr in FILE_READ_ATTRS and not (
            isinstance(f.value, ast.Call) and names_python_file(f.value.args)):
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


def walk(root, skipped):
    try:
        with open(os.path.join(root, ".git", "index"), "rb") as f:
            index = f.read()
    except OSError:
        index = None  # no git record, as in a zip download: a folder's name proves nothing
    for folder, dirs, files in os.walk(root):
        keep = []
        for d in dirs:
            if d in ALWAYS_SKIP:
                continue
            # A committed folder is project code whatever its name: only a real install is skipped.
            if d in INSTALLED and index is not None and (d.encode() + b"/") not in index:
                skipped.add(d)
                continue
            keep.append(d)
        dirs[:] = keep
        for name in files:
            path = os.path.join(folder, name)
            if not os.path.islink(path) and os.path.isfile(path):
                yield path, os.path.relpath(path, root)


def check_config(base, raw):
    text = raw.decode("utf-8", "replace")
    if base == "package.json":
        return check_package_json(raw)
    if base == "tasks.json":
        return [("runs-on-folder-open", 1, True)] if FOLDER_OPEN.search(text) else []
    pattern = TOML_OUTSIDE if base == "pyproject.toml" else PIP_OUTSIDE
    return [("outside-dependency", 1, False)] if pattern.search(text) else []


def scan(root, cleared):
    report = {"status": "clear", "stop": [], "notes": [], "cleared": [], "not_checked": [], "skipped": [],
              "checked": 0}
    if not os.path.isdir(root):
        report.update(status="incomplete", not_checked=[root])
        return report
    skipped, found, trees, hashes = set(), collections.defaultdict(list), {}, {}
    entries = list(walk(root, skipped))
    known = {rel for _, rel in entries if rel.endswith((".py", ".pyw"))}

    for path, rel in entries:
        base = os.path.basename(rel)
        is_py = rel.endswith((".py", ".pyw"))
        is_config = base in ("package.json", "pyproject.toml") or re.fullmatch(r"requirements.*\.txt", base) \
            or rel.replace(os.sep, "/").endswith(".vscode/tasks.json")
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
                found[rel].extend(verdicts(read_tree(tree)[0]))
        except (OSError, ValueError, RecursionError, MemoryError):
            report["not_checked"].append(rel)

    def is_cleared(rel):
        return hashes.get(rel) in cleared

    flagged = {rel for rel, items in found.items() if not is_cleared(rel) and any(
        stop or sig == "encoded-data" for sig, _, stop in items)}
    extras = {}
    for rel, tree in trees.items():
        stubs = sum(1 for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
                    and len(n.body) == 1 and (isinstance(n.body[0], ast.Pass) or (
                        isinstance(n.body[0], ast.Expr) and getattr(n.body[0].value, "value", 0) is Ellipsis)))
        for target, line in import_time_targets(tree, rel, known):
            if target in flagged and target != rel:
                found[rel].append(("runs-on-import", line, True))
                extras[(rel, line)] = {"target": target, "empty_functions": stubs}

    for rel in sorted(found):
        items = sorted(set(found[rel]))
        if items and is_cleared(rel):
            report["cleared"].append({"file": rel, "signals": sorted({i[0] for i in items})})
            continue
        for sig, line, stop in items:
            entry = {"file": rel, "line": line, "signal": sig, "why": WHY[sig]}
            if sig == "runs-on-import":
                entry.update(extras[(rel, line)])
            report["stop" if stop else "notes"].append(entry)
    report["skipped"] = sorted(skipped)
    report["not_checked"] = sorted(set(report["not_checked"]))
    if report["stop"]:
        report["status"] = "stop"
    elif report["not_checked"]:
        report["status"] = "incomplete"
    elif not report["checked"]:
        report["status"] = "nothing-to-check"
    return report


def safe(path):
    return json.dumps(path)[1:-1]  # ASCII, one line: a hostile file name can't forge report lines


def show(r):
    if r["status"] == "stop":
        print("STOP -- do not install or run this project yet:")
    elif r["status"] == "incomplete":
        print("COULD NOT FINISH -- this is not a clean result.")
    elif r["status"] == "nothing-to-check":
        print("Nothing to check: no Python files, package.json, requirements or VS Code tasks here.")
    else:
        print(f"Nothing found in {r['checked']} files. That does not prove the project is safe.")
    for f in r["stop"]:
        extra = f" -> {safe(f['target'])}" if "target" in f else ""
        print(f"  {safe(f['file'])}:{f['line']} {f['signal']}: {f['why']}{extra}")
    for f in r["notes"]:
        print(f"  note {safe(f['file'])}:{f['line']} {f['signal']}: {f['why']}")
    for path in r["not_checked"]:
        print(f"  not checked: {safe(path)}")
    for f in r["cleared"]:
        print(f"  cleared by the user earlier: {safe(f['file'])}")
    if r["skipped"]:
        print("  not read (installed packages): " + ", ".join(r["skipped"]))


def load_cleared(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError, RecursionError):
        return {}


def clear(root, rel, cleared_file):
    base = os.path.realpath(root)
    path = os.path.realpath(os.path.join(root, rel))
    if not path.startswith(base + os.sep) or not os.path.isfile(path):
        print(f"Not cleared: {safe(rel)} is not a file inside this project.")
        return 2
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    data = load_cleared(cleared_file)
    data[digest] = os.path.relpath(path, base)
    os.makedirs(os.path.dirname(cleared_file) or ".", exist_ok=True)
    tmp = cleared_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(tmp, cleared_file)
    print(f"Cleared {safe(rel)} as it is now. Any change to the file flags it again.")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Look for code built to attack the computer that runs it.")
    ap.add_argument("folder")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--clear", metavar="RELATIVE_PATH")
    # Kept outside every project: a list inside a repo could clear that repo's own malware.
    ap.add_argument("--cleared-file", default=os.path.join(
        os.path.expanduser("~"), ".claude", "make-it", "hostile-code-cleared.json"))
    args = ap.parse_args()
    if args.clear:
        return clear(args.folder, args.clear, args.cleared_file)
    report = scan(args.folder, load_cleared(args.cleared_file))
    if args.json:
        print(json.dumps(report, indent=1))
    else:
        show(report)
    return {"stop": 1, "incomplete": 2}.get(report["status"], 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # a crash must never read as exit 1 (stop) or as clean
        print(f"COULD NOT FINISH ({type(e).__name__}) -- this is not a clean result.")
        sys.exit(2)
