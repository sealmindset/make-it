#!/usr/bin/env python3
"""The make-it build record and its check. Spec: references/watermark.md.

Usage: watermark.py seal   [--app DIR] [--framework DIR] --skill NAME [--results FILE] [--restart WHY]
       watermark.py write  [--app DIR] [--framework DIR] [--results FILE]
       watermark.py note   [--app DIR] [--framework DIR] <security file> <why it changed>
       watermark.py verify [--app DIR] [--framework DIR] [--base-ref SHA] [--allow-unlisted] [--json]
       watermark.py hook    (a Claude Code hook: event JSON on stdin; silent, never fails)

`seal` is what a make-it skill runs when it has finished and checked its work: it fingerprints the
project's code and adds an entry to .make-it/ledger/, chained to the one before. Code that no longer
matches a seal was changed outside make-it. A seal attests; it does not prove (anyone can run this).
`write` records what make-it did in .make-it/manifest.json. The record is a claim, not proof.
`verify` is the proof: it recomputes everything from the code and never trusts the record.
Exit: 0 pass, 1 fail, 3 needs security review (a security file changed, or nothing could be checked).

Everything under --app is hostile input: it is read as data, only as plain files of bounded size,
never followed through a link, and never run, imported or installed.
"""
import ast
import datetime
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile

RECORD = os.path.join(".make-it", "manifest.json")
CAP = 1 << 20  # no file this reads from an app is bigger than 1 MB
BIG = 64 << 20  # ...except when fingerprinting, where a lock file can be large
LEDGER = os.path.join(".make-it", "ledger")
SEALED = os.path.join(".make-it", "sealed-files.txt")
STAMP = os.path.join("backend", "make-it-stamp.json")
READABLE = "MAKE-IT.md"
NEVER_SEALED = "This project has never been sealed by make-it. Run /resume-it in this project, then push again."
NO_RECORD = ("This project has no make-it build record (.make-it/manifest.json). "
             "Run /resume-it in this project, then push again.")
METHODS = {"get", "post", "put", "patch", "delete", "head", "options", "api_route", "websocket"}
REGISTER = {"add_api_route", "add_route", "add_websocket_route", "mount"}


def read_plain(path, cap=CAP):
    """Bytes of a plain file, or None: a link, a pipe, a device, a folder, too big or unreadable."""
    try:
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode) or st.st_size > cap:
            return None
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as f:
            return f.read(cap + 1)[:cap]
    except OSError:
        return None


def sha_of(data):
    return hashlib.sha256(data).hexdigest()


def load_json(path):
    data = read_plain(path)
    if data is None:
        return None
    try:
        d = json.loads(data)
    except (ValueError, RecursionError):
        return None
    return d if isinstance(d, dict) else None


def clean(text, limit=200):
    """One printable line: nothing a terminal or a CI log would act on."""
    return "".join(c for c in " ".join(str(text).split()) if c.isprintable())[:limit]


class Framework:
    """A make-it install (~/.claude/make-it) or checkout (<repo>/.claude/make-it). Trusted."""

    def __init__(self, d):
        self.dir = d
        with open(self._top("VERSION")) as f:
            self.version = f.read().strip()
        with open(self._top("CONTENT_MANIFEST"), "rb") as f:
            raw = f.read()
        self.digest = sha_of(raw)
        self.canonical = {}
        for line in raw.decode().splitlines():
            want, _, rel = line.partition("  ")
            if want and rel:
                self.canonical[rel] = want

    def _top(self, name):  # installed: beside the references; checkout: at the repo root
        for p in (os.path.join(self.dir, name), os.path.join(self.dir, "..", "..", name)):
            if os.path.isfile(p):
                return p
        sys.exit(f"watermark: {name} not found for the framework at {self.dir}")

    def scaffolds(self):
        d = os.path.join(self.dir, "watermark")
        return sorted(n[len("protected-"):-4] for n in (os.listdir(d) if os.path.isdir(d) else [])
                      if n.startswith("protected-") and n.endswith(".txt"))

    def protected(self, scaffold):
        if not isinstance(scaffold, str) or not re.fullmatch(r"[a-z0-9-]+", scaffold):
            return []
        p = os.path.join(self.dir, "watermark", f"protected-{scaffold}.txt")
        if not os.path.isfile(p):
            return []
        with open(p) as f:
            return [l.strip() for l in f if l.strip() and not l.startswith("#")]

    def expected(self, scaffold, rel):
        return self.canonical.get(f"make-it/scaffolds/{scaffold}/{rel}")

    def scaffold_dir(self, scaffold):
        return os.path.join(self.dir, "scaffolds", scaffold)


def detect_scaffold(app, fw, claimed=None):
    """The scaffold whose security files this code holds. A claim can add a scaffold, never remove one."""
    for s in fw.scaffolds():
        if any(os.path.lexists(os.path.join(app, rel)) for rel in fw.protected(s)):
            return s
    return claimed if fw.protected(claimed) else None


# ---------------------------------------------------------------- the record (write, note, hook)

def scalars(d, keys=20):
    """Counts and states only: short keys, scalar values. Anything else is dropped."""
    out = {}
    for k, v in (d.items() if isinstance(d, dict) else []):
        if len(out) >= keys or not isinstance(k, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,39}", k):
            continue
        if isinstance(v, bool) or v is None or (isinstance(v, int) and abs(v) < 10**9):
            out[k] = v
        elif isinstance(v, str):
            out[k] = clean(v)
    return out


def build_record(app, fw, results=None):
    ctx = load_json(os.path.join(app, ".make-it", "app-context.json")) or {}
    old = load_json(os.path.join(app, RECORD)) or {}
    old_files = old.get("security_files") if isinstance(old.get("security_files"), list) else []
    notes = {e.get("path"): e.get("note") for e in old_files
             if isinstance(e, dict) and isinstance(e.get("path"), str) and e.get("note")}
    claimed = ctx.get("scaffold") if isinstance(ctx.get("scaffold"), str) else None
    scaffold = detect_scaffold(app, fw, claimed)
    files = []
    for rel in fw.protected(scaffold):
        entry = {"path": rel, "expected": fw.expected(scaffold, rel)}  # always the release's hash
        data = read_plain(os.path.join(app, rel))
        if data is None:
            entry["state"] = "missing"
        else:
            entry["sha256"] = sha_of(data)
            entry["state"] = "match" if entry["sha256"] == entry["expected"] else "changed"
        if entry["state"] == "changed" and rel in notes:
            entry["note"] = clean(notes[rel])
        files.append(entry)
    tiers = ctx.get("active_tiers")
    ptype = ctx.get("project_type")
    return {
        "schema": 1,
        "framework": {"version": fw.version, "content_manifest_sha256": fw.digest},
        "project": {
            "type": clean(ptype, 40) if isinstance(ptype, str) else None,
            "tiers": [t for t in tiers if isinstance(t, int) and not isinstance(t, bool)][:10] if isinstance(tiers, list) else None,
            "scaffold": scaffold,
        },
        "security_files": files,
        "security_results": scalars(results if results is not None else old.get("security_results")),
    }


def can_write_inside(app, rel):
    """May this file be written inside the project? False: a link on the way, something there that is not a plain
    file, or a folder that cannot be written to."""
    path, d, folder = os.path.join(app, rel), app, app
    for part in os.path.dirname(rel).split(os.sep):
        if part:
            d = os.path.join(d, part)
            if os.path.islink(d) or (os.path.lexists(d) and not os.path.isdir(d)):
                return False
            if os.path.isdir(d):
                folder = d  # the deepest folder that exists: the file, or the folders still to make, go in it
    if os.path.islink(path) or (os.path.lexists(path) and not os.path.isfile(path)):
        return False
    return os.access(folder, os.W_OK | os.X_OK)


def write_inside(app, rel, text):
    """Write one file inside the project and nowhere else. False: refused (see can_write_inside)."""
    if not can_write_inside(app, rel):
        return False
    path = os.path.join(app, rel)
    folder = os.path.dirname(path) or app
    os.makedirs(folder, exist_ok=True)
    data = text.encode("utf-8", "surrogateescape")
    if read_plain(path, BIG) == data:
        return True
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".wm-", suffix=".tmp")  # a new file, never a planted link
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    return True


def save_record(app, rec):
    """Write the record inside the project and nowhere else. False: refused."""
    return write_inside(app, RECORD, json.dumps(rec, indent=2, sort_keys=True) + "\n")  # sorted, no time


def cmd_write(app, fw, opts):
    results = None
    if opts.get("--results"):
        results = load_json(opts["--results"])
        if results is None:
            sys.exit(f"watermark: {opts['--results']} is not a plain file holding a JSON object")
    rec = build_record(app, fw, results)
    if not save_record(app, rec):
        sys.exit("watermark: refused: .make-it or its manifest.json is a link or not a plain file")
    off = [e["path"] for e in rec["security_files"] if e["state"] != "match"]
    print(f"record written: {len(rec['security_files'])} security files, {len(off)} not as released")
    for p in off:
        print(f"  {p}")
    return 0


def cmd_note(app, fw, args):
    if len(args) != 2:
        sys.exit(__doc__)
    rel, text = args[0], clean(args[1])
    rec = build_record(app, fw)
    entry = next((e for e in rec["security_files"] if e["path"] == rel), None)
    if entry is None:
        sys.exit(f"watermark: {clean(rel)} is not a security file of this project")
    if entry["state"] != "changed":
        sys.exit(f"watermark: {rel} is {entry['state']}, not changed; nothing to note")
    entry["note"] = text
    if not save_record(app, rec):
        sys.exit("watermark: refused: .make-it or its manifest.json is a link or not a plain file")
    print(f"noted: {rel}")
    return 0


def cmd_hook(fw_dir):
    """Keep the record current after a turn. Any failure is swallowed: a hook must never break a session."""
    try:
        d = os.path.abspath((json.load(sys.stdin) or {}).get("cwd") or ".")
        while True:
            folder = os.path.join(d, ".make-it")
            if not os.path.islink(folder) and read_plain(os.path.join(folder, "app-context.json")) is not None:
                save_record(d, build_record(d, Framework(fw_dir)))
                break
            parent = os.path.dirname(d)
            if parent == d:
                break
            d = parent
    except BaseException:
        pass
    return 0


# ---------------------------------------------------------------- the seal (seal, and its part of verify)

def git_dir_ok(app):
    """True when `app` sits in a real git work tree: a .git folder at or above it, or a worktree's .git file
    pointing outside the project.

    Files named HEAD/objects/config in a project, or a .git file pointing back into it, are never treated as a repository.
    """
    d = app
    while True:
        dot = os.path.join(d, ".git")
        if os.path.lexists(dot):
            break
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent
    if os.path.islink(dot):
        return False
    if os.path.isdir(dot):
        return True
    data = read_plain(dot, 4096)
    if not data or not data.startswith(b"gitdir:"):
        return False
    target = os.path.realpath(os.path.join(d, data[7:].decode(errors="replace").strip()))
    return os.path.isdir(target) and not (target + os.sep).startswith(os.path.realpath(app) + os.sep)


def git(app, *args):
    """Run git reading only. A project's own git settings must not make it fetch, prompt or run a helper.

    Two guards against fetching a missing object on demand, each enough alone: GIT_NO_LAZY_FETCH (an older git
    does not know it) and GIT_ALLOW_PROTOCOL, set to no protocol at all. It is the environment, not
    `-c protocol.allow=never`, because the project's own `protocol.<name>.allow = always` overrides that.
    """
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}  # a caller's GIT_DIR names another repository
    env.update(GIT_NO_LAZY_FETCH="1", GIT_ALLOW_PROTOCOL="", GIT_TERMINAL_PROMPT="0", GIT_OPTIONAL_LOCKS="0")
    return subprocess.run(["git", "--no-replace-objects", "-c", "safe.bareRepository=explicit",
                           "-c", "core.fsmonitor=false", "-C", app, *args],
                          capture_output=True, env=env)


def sealed_path(rel):
    """Does this file count toward the seal? Docs and make-it's own records do not."""
    return not (rel.lower().endswith(".md") or rel.startswith(".make-it/") or rel == STAMP.replace(os.sep, "/"))


def stream_hash(path):
    h = hashlib.sha256()
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    with os.fdopen(fd, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def file_mark(app, rel):
    """A short, stable description of one file's content. Never blocks, and never reads outside the project."""
    path, d = os.path.join(app, rel), app
    if os.path.isabs(rel) or ".." in rel.split("/"):
        return "outside"  # a hand-made git index can name a file outside the project: never opened
    for part in rel.split("/")[:-1]:
        d = os.path.join(d, part)
        if os.path.islink(d):
            return "under-link"  # reached through a linked folder: its content is not this project's
    try:
        st = os.lstat(path)
        if stat.S_ISLNK(st.st_mode):
            text = sha_of(os.readlink(path).encode("utf-8", "surrogateescape"))
            real, root = os.path.realpath(path), os.path.realpath(app)
            if not (real + os.sep).startswith(root + os.sep):
                return "link-out:" + text  # never hashed: it is somebody else's file
            if os.path.isfile(real):
                return f"link:{text}:{stream_hash(real)}"  # what it points at counts, even a file the seal skips
            if os.path.isdir(real):
                return "link-dir:" + text  # what is behind it would not count: seal refuses it, verify fails
            return "link:" + text
        if not stat.S_ISREG(st.st_mode):
            return "special"
        return ("x:" if st.st_mode & 0o100 else "") + stream_hash(path)
    except OSError:
        return "unreadable"


SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__"}


def walk_files(base):
    """Files under `base`, for a project (or a nested folder) git cannot list. Dependency folders and .env files are left out."""
    for root, dirs, names in os.walk(base, followlinks=False):
        links = [d for d in dirs if os.path.islink(os.path.join(root, d))]
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and d not in links]
        for n in [n for n in names if not n.startswith(".env")] + links:  # a linked folder is listed whatever its name
            yield os.path.relpath(os.path.join(root, n), base).replace(os.sep, "/")


def listed(app):
    """{path: None, or a submodule's mark} for every path the seal looks at.

    With git: every tracked file plus new ones git would add. A submodule counts by the commit it points at,
    and a nested repository by its files.
    """
    marks = None
    if git_dir_ok(app):
        tracked, others = git(app, "ls-files", "-s", "-z"), git(app, "ls-files", "-o", "--exclude-standard", "-z")
        if tracked.returncode == 0 and others.returncode == 0:
            marks = {}
            for item in tracked.stdout.split(b"\0"):
                meta, tab, raw = item.partition(b"\t")
                if tab:
                    mode, blob = meta.split()[:2]
                    marks[raw.decode("utf-8", "surrogateescape")] = ("gitlink:" + blob.decode()) if mode == b"160000" else None
            for raw in others.stdout.split(b"\0"):
                rel = raw.decode("utf-8", "surrogateescape")
                if rel.endswith("/"):
                    for sub in walk_files(os.path.join(app, rel)):
                        marks[rel + sub] = None
                elif rel:
                    marks[rel] = None
    if marks is None:
        marks = {rel: None for rel in walk_files(app)}
    return marks


def folder_links(app):
    """Links that lead to a folder, in the project or out of it. The files behind one would not count, so it is never sealed.

    Decided by what the entry is, never by its name: a link named like a document, or one under .make-it, is still a link.
    """
    return sorted(rel for rel in listed(app) if os.path.islink(os.path.join(app, rel))
                  and os.path.isdir(os.path.join(app, rel)))


def code_listing(app):
    """`mark  path` for every file that counts, sorted: what a seal fingerprints."""
    marks = listed(app)
    lines = []
    for rel in sorted(marks):
        if sealed_path(rel) and (marks[rel] or os.path.lexists(os.path.join(app, rel))):
            name = rel.replace("\\", "\\\\").replace("\n", "\\n")  # one line per file, and no two names alike
            lines.append(f"{marks[rel] or file_mark(app, rel)}  {name}\n")
    return "".join(lines)


def digest(text):
    return sha_of(text.encode("utf-8", "surrogateescape"))


ATTRS = ["* -text", "MAKE-IT.md merge=union", ".make-it/sealed-files.txt merge=union", "backend/make-it-stamp.json merge=union"]


def git_steady_text(app):
    """What .gitattributes must hold for the seal: no line-ending rewriting (it would change every fingerprint), and
    generated files that merge without a conflict (the next seal rewrites them).

    The whole new text; "" when nothing is missing; None when the file cannot be read, or would pass 1 MB and
    so could not be read by the next seal. Nothing is written here.
    """
    path = os.path.join(app, ".gitattributes")
    raw = read_plain(path)
    if raw is None and os.path.lexists(path):
        return None  # over 1 MB or unreadable: never replaced by a file holding only the seal's lines
    have = (raw or b"").decode("utf-8", "surrogateescape")  # written back byte for byte
    missing = [a for a in ATTRS if a not in have.splitlines()]
    if not missing:
        return ""
    head = "" if not have or have.endswith("\n") else "\n"
    text = have + head + "# make-it seal\n" + "\n".join(missing) + "\n"
    return text if len(text.encode("utf-8", "surrogateescape")) <= CAP else None


def load_ledger(app):
    """(entries by hash, problems). An entry is trusted only as far as its own bytes and name agree."""
    folder, entries, problems = os.path.join(app, LEDGER), {}, []
    if os.path.islink(folder) or os.path.islink(os.path.dirname(folder)):
        return {}, ["the seal history folder is a link"]
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if name.startswith("."):
            continue  # a .DS_Store or a leftover temp file is not history
        m = re.fullmatch(r"(\d{4,})-([0-9a-f]{12})\.json", name)
        data = read_plain(os.path.join(folder, name))
        e = None
        if m and data is not None:
            try:
                e = json.loads(data)
            except (ValueError, RecursionError):
                e = None
        ok = (isinstance(e, dict) and e.get("schema") == 1 and isinstance(e.get("n"), int)
              and isinstance(e.get("fingerprint"), str) and isinstance(e.get("before"), list)
              and all(isinstance(b, str) for b in e["before"]) and isinstance(e.get("make_it"), dict)
              and sha_of(data).startswith(m.group(2)) and e["n"] == int(m.group(1)))
        if not ok:
            problems.append(f"{clean(name, 60)} is not a seal entry, or was edited after it was written")
            continue
        e["_hash"] = sha_of(data)
        entries[e["_hash"]] = e
    return entries, problems


def heads_of(entries):
    used = {b for e in entries.values() for b in e["before"]}
    return [e for h, e in entries.items() if h not in used]


def cell(text, limit=80):
    """Project text for MAKE-IT.md: one line, with nothing that makes a table cell, a link, code or HTML."""
    return "".join(" " if c in "|<>[]`*_#" else c for c in clean(text, limit))


def count(value):
    return value if isinstance(value, int) and not isinstance(value, bool) else "?"


def readable(entries, rec):
    """MAKE-IT.md: the seal, for a person."""
    order = sorted(entries.values(), key=lambda e: (e["n"], e["_hash"]))
    last = order[-1]
    files = rec.get("security_files", [])
    off = [e for e in files if e.get("state") != "match"]
    if not files:
        security = "- **Sign-in and permission code:** not checked for this project type"
    elif off:
        security = f"- **Sign-in and permission code:** {len(off)} of {len(files)} files differ from the release"
    else:
        security = f"- **Sign-in and permission code:** all {len(files)} files exactly as the release shipped them"
    scaffold = rec["project"].get("scaffold")
    out = ["# Built with make-it", "",
           "This project was built and is maintained with the make-it framework. "
           f"make-it last checked and sealed it on **{cell(last.get('date'), 12)}** "
           f"(/{cell(last.get('skill'), 30)}, make-it {cell(last['make_it'].get('version'), 20)}).", "",
           "This file is written by make-it. Do not edit it by hand: it is rebuilt at every seal.", "",
           "## What the seal says", "",
           f"- **Framework:** make-it {cell(rec['framework']['version'], 20)}" + (f", scaffold {cell(scaffold, 40)}" if scaffold else ""),
           f"- **Code:** {count(last.get('files'))} files fingerprinted. Any change made outside make-it breaks the seal.",
           security]
    for e in off:
        out.append(f"  - {cell(e['path'], 200)} ({cell(e['state'], 12)})" + (f": {cell(e['note'], 200)}" if e.get("note") else ""))
    res = rec.get("security_results") or {}
    if res:
        out.append("- **Last security step:** " + ", ".join(f"{cell(k.replace('_', ' '), 40)}: {cell(v, 60)}" for k, v in sorted(res.items())))
    out += ["", "## Every make-it run", "", "| # | Date | Skill | make-it | Files | Note |", "|---|---|---|---|---|---|"]
    for e in order:
        note = ""
        if e.get("restart"):
            note = "history restarted: " + cell(e["restart"], 80)
        elif len(e["before"]) > 1:
            note = "joins two lines of work"
        out.append(f"| {e['n']} | {cell(e.get('date'), 12)} | /{cell(e.get('skill'), 30)} | "
                   f"{cell(e['make_it'].get('version'), 20)} | {count(e.get('files'))} | {note} |")
    out += ["", "## Check it yourself", "", "```bash",
            'python3 -I "$HOME/.claude/make-it/scripts/watermark.py" verify', "```", "",
            "A pass means the code is what make-it last sealed, the history is unbroken, and the sign-in and "
            "permission code is as released. The seal attests that make-it was used; it is not proof against "
            "someone who sets out to fake it.", ""]
    return "\n".join(out)


def cmd_seal(app, fw, opts):
    skill = (opts.get("--skill") or "").lstrip("/")
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,29}", skill):
        sys.exit("watermark: seal needs --skill <name>, e.g. --skill resume-it")
    results = None
    if opts.get("--results"):
        results = load_json(opts["--results"])
        if results is None:
            sys.exit(f"watermark: {opts['--results']} is not a plain file holding a JSON object")
    refused = ("watermark: refused: a folder or file the seal writes to is a link, is not a plain file, "
               "or cannot be written. Nothing was sealed.")
    rec = build_record(app, fw, results if results is not None else {})  # never what an older record claimed
    backend = {e["path"][len("backend/"):]: e["expected"] for e in rec["security_files"]
               if e["path"].startswith("backend/") and e.get("expected")}
    backend_dir = os.path.join(app, "backend")
    stamped = bool(backend) and os.path.isdir(backend_dir) and not os.path.islink(backend_dir)
    in_git = git_dir_ok(app)
    targets = [RECORD, os.path.join(LEDGER, "entry"), SEALED, READABLE] + [STAMP] * stamped + [".gitattributes"] * in_git
    # Every refusal comes before the first write: a refused seal leaves the project as it was.
    if not all(can_write_inside(app, rel) for rel in targets):
        sys.exit(refused)
    attrs = git_steady_text(app) if in_git else ""
    if attrs is None:
        sys.exit("watermark: refused: .gitattributes cannot be read, or is (or would become) over 1 MB, "
                 "so it was left as it is. Nothing was sealed.")
    entries, problems = load_ledger(app)
    restart = clean(opts["--restart"], 120) if opts.get("--restart") else None
    if problems and not restart:
        sys.exit("watermark: the seal history is damaged (" + "; ".join(problems[:3]) + "). "
                 "Nothing was sealed. Only the owner can go on: seal again with --restart \"<why>\".")
    links = folder_links(app)
    if links:
        sys.exit("watermark: refused: a link to a folder cannot be sealed, because the files behind it would not count: "
                 + ", ".join(clean(rel, 200) for rel in links[:10]) + ". Put the folder itself there, or remove the link. "
                 "Nothing was sealed.")
    if (attrs and not write_inside(app, ".gitattributes", attrs)) or not save_record(app, rec):
        sys.exit(refused)
    listing = code_listing(app)
    fp = digest(listing)
    same = [e for e in heads_of(entries)
            if e["fingerprint"] == fp and e["make_it"].get("content_manifest_sha256") == fw.digest]
    if same and not restart:
        entry = max(same, key=lambda e: e["n"])
        said = f"already sealed: nothing changed since /{clean(entry.get('skill'), 30)} sealed it"
    else:
        heads = [] if restart else heads_of(entries)
        entry = {
            "schema": 1,
            "n": max([e["n"] for e in entries.values()], default=0) + 1,
            "skill": skill,
            "date": datetime.date.today().isoformat(),
            "make_it": {"version": fw.version, "content_manifest_sha256": fw.digest},
            "fingerprint": fp,
            "files": listing.count("\n"),
            "security": {st: [e["path"] for e in rec["security_files"] if e["state"] == st] for st in ("changed", "missing")},
            "results": rec["security_results"],
            "before": sorted(e["_hash"] for e in heads),
        }
        if restart:
            entry["restart"] = restart
        text = json.dumps(entry, indent=2, sort_keys=True) + "\n"
        entry["_hash"] = digest(text)
        if not write_inside(app, os.path.join(LEDGER, f"{entry['n']:04d}-{entry['_hash'][:12]}.json"), text):
            sys.exit(refused)
        entries[entry["_hash"]] = entry
        said = f"sealed: run {entry['n']} by /{skill}, {entry['files']} files"
    # only what the release fixes: two branches at the same release write the same stamp, so merges don't clash
    stamp = {"schema": 1, "make_it_version": fw.version, "scaffold": rec["project"]["scaffold"], "security_files": backend}
    ok = write_inside(app, SEALED, listing) and write_inside(app, READABLE, readable(entries, rec))
    if stamped:
        ok = ok and write_inside(app, STAMP, json.dumps(stamp, indent=2, sort_keys=True) + "\n")
    if not ok:
        sys.exit(refused)
    print(said)  # only once everything is written
    return 0


def listing_map(text):
    out = {}
    for line in text.split("\n"):  # never splitlines(): a name may hold a carriage return, and would read as a second line
        mark, sep, rel = line.partition("  ")
        if sep:
            out[rel] = mark
    return out


def seal_fails(app, rec):
    """Why the code is not what make-it sealed. Empty: it is."""
    entries, problems = load_ledger(app)
    if problems:
        return ["The seal history was changed by hand: " + "; ".join(problems[:5]) + "."]
    if not entries:
        return [NEVER_SEALED]
    dirs = folder_links(app)  # asked directly: the listing leaves documents out by name
    if dirs:
        return ["A link in the project points at a folder, so the files behind it are not sealed: "
                + ", ".join(clean(rel, 200) for rel in dirs[:10]) + ". Put the folder itself there, or remove the link."]
    listing = code_listing(app)
    out = sorted(rel for rel, mark in listing_map(listing).items() if mark.startswith("link-out:"))
    if out:
        return ["A link in the project points outside it, so its content cannot be sealed: " + ", ".join(out[:10]) + "."]
    fp = digest(listing)
    match = [e for e in heads_of(entries) if e["fingerprint"] == fp]  # an older seal is not the current one
    if not match:
        last = max(entries.values(), key=lambda e: (e["n"], e["_hash"]))
        when = f"/{clean(last.get('skill'), 30)} sealed it on {clean(last.get('date'), 12)}"
        old = read_plain(os.path.join(app, SEALED), BIG)
        names = []
        if old is not None and sha_of(old) == last["fingerprint"]:
            was, now = listing_map(old.decode("utf-8", "surrogateescape")), listing_map(listing)
            names = sorted(k for k in set(was) | set(now) if was.get(k) != now.get(k))
        if names:
            what = (f"{len(names)} file(s) changed outside make-it since {when}: " + ", ".join(clean(n, 200) for n in names[:20])
                    + (" ..." if len(names) > 20 else "") + ".")
        else:
            what = f"The code is not what make-it sealed ({when})."
        return [what + " Run /resume-it in this project, then push again."]
    entry = max(match, key=lambda e: e["n"])
    seen, todo = set(), [entry]
    while todo:  # the history behind this seal must be whole, back to its start or a declared restart
        e = todo.pop()
        if e["_hash"] in seen or e.get("restart"):
            continue
        seen.add(e["_hash"])
        for b in e["before"]:
            if b not in entries:
                return [f"The seal history is broken: an entry before run {e['n']} is missing."]
            todo.append(entries[b])
    framework = rec.get("framework") if isinstance(rec.get("framework"), dict) else {}
    if rec and framework.get("content_manifest_sha256") != entry["make_it"].get("content_manifest_sha256"):
        return ["The build record and the seal name different make-it releases. Run /resume-it in this project."]
    return []


# ---------------------------------------------------------------- the check (verify)

def py_files(base):
    """(relative path, bytes or None) for every .py under base. No folder is skipped: code can live anywhere.

    A linked folder, and a compiled file Python could import with no source, come back as None.
    """
    for root, dirs, names in os.walk(base, followlinks=False):
        dirs.sort()
        for d in list(dirs):
            if os.path.islink(os.path.join(root, d)):
                dirs.remove(d)
                yield os.path.relpath(os.path.join(root, d), base).replace(os.sep, "/"), None
        for n in sorted(names):
            p = os.path.join(root, n)
            rel = os.path.relpath(p, base).replace(os.sep, "/")
            if n.endswith(".py"):
                yield rel, read_plain(p)
            elif n.endswith((".pyc", ".pyo", ".so", ".pyd", ".pth")):
                yield rel, None


GUARDS = {"require_permission": "app.middleware.permissions", "Depends": "fastapi"}
DYNAMIC = {"exec", "eval", "compile", "__import__", "globals", "locals", "vars", "delattr"}
ROUTE_OBJECTS = {"APIRoute", "Route", "Mount", "WebSocketRoute", "APIWebSocketRoute"}
ODD_ATTRS = {"routes", "middleware", "add_middleware", "exception_handler", "add_exception_handler",
             "dependency_overrides", "__dict__", "__globals__", "__builtins__"}


def is_guard(node):
    """Exactly Depends(require_permission(...)): nothing wrapped around it, nothing in between."""
    return (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "Depends"
            and len(node.args) == 1 and isinstance(node.args[0], ast.Call)
            and isinstance(node.args[0].func, ast.Name) and node.args[0].func.id == "require_permission")


def code_findings(base, skip=()):
    """What the Python under `base` does that the rules care about: a count of (file, kind, what).

    kind "fail": a route with no permission check, or the check itself tampered with.
    kind "review": code this cannot be sure about (built at run time, routes or request filters added
    another way, the app's own modules reached into). Only plain route code passes on its own.
    Parsed, never text-matched, and never run.
    """
    from collections import Counter
    out = Counter()
    for rel, data in py_files(base):
        if rel in skip:
            continue
        if data is None:
            out[(rel, "fail", "is a link, a compiled file, not a plain file, or over 1 MB")] += 1
            continue
        try:
            tree = ast.parse(data)  # bytes: an encoding line in the file is honored, as Python would
        except (SyntaxError, ValueError, RecursionError, MemoryError):
            out[(rel, "fail", "could not be read as Python")] += 1
            continue
        in_tests = rel.startswith("tests/")
        add = lambda kind, what: out.update([(rel, kind, what)])
        parent = {c: n for n in ast.walk(tree) for c in ast.iter_child_nodes(n)}
        decorators = {id(d) for fn in ast.walk(tree) if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef))
                      for d in fn.decorator_list}
        ok_import, modules, routers, makers = set(), set(), set(), set()
        for node in tree.body:  # a guard counts only when imported plainly, at the top of the file
            if isinstance(node, ast.ImportFrom) and not node.level:
                for a in node.names:
                    if a.name in GUARDS and a.asname in (None, a.name) and node.module == GUARDS[a.name]:
                        ok_import.add((id(a), a.name))
        ok_names = {n for _, n in ok_import}
        ok_ids = {i for i, _ in ok_import}
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                mod = getattr(node, "module", None) or ""
                for a in node.names:
                    bound = (a.asname or a.name).split(".")[0]
                    full = a.name if isinstance(node, ast.Import) else f"{mod}.{a.name}"
                    if bound in GUARDS and id(a) not in ok_ids:
                        add("fail", f"takes {bound} from somewhere other than {GUARDS[bound]}, or not at the top of the file")
                    if a.name == "*":
                        add("review", "imports * (any name could be replaced)")
                    if full.split(".")[0] in ("importlib", "runpy", "imp", "pkgutil", "ctypes", "marshal", "pickle"):
                        add("review", f"imports {full.split('.')[0]} (can load code this check cannot see)")
                    if (full == "tests" or full.startswith("tests.")) and not in_tests:
                        add("fail", "imports the test folder into the app")
                    if isinstance(node, ast.Import) or full.startswith("app.middleware") and a.name in ("auth", "permissions", "middleware"):
                        modules.add(bound)
                        if full.startswith("app.middleware"):
                            add("review", "takes a sign-in module as an object (it could be changed from here)")
                    if mod.split(".")[0] in ("fastapi", "starlette") and a.name in ("APIRouter", "FastAPI", "Starlette", "Router"):
                        makers.add(a.asname or a.name)
                    if a.name in ROUTE_OBJECTS or (a.asname or "") in ROUTE_OBJECTS:
                        add("review", f"uses {a.name} (a route built without a decorator)")
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
                f = node.value.func
                if (isinstance(f, ast.Name) and f.id in makers) or \
                   (isinstance(f, ast.Attribute) and f.attr in ("APIRouter", "FastAPI") and isinstance(f.value, ast.Name)):
                    routers |= {t.id for t in node.targets if isinstance(t, ast.Name)}
        for node in ast.walk(tree):
            if isinstance(node, ast.arg) and node.arg in GUARDS:
                add("fail", f"uses {node.arg} as a parameter name, hiding the real one")
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.name in GUARDS:
                add("fail", f"defines its own {node.name}")
            elif isinstance(node, ast.ExceptHandler) and node.name in GUARDS:
                add("fail", f"replaces {node.name}")
            elif isinstance(node, ast.Name):
                if node.id in GUARDS and not isinstance(node.ctx, ast.Load):
                    add("fail", f"replaces {node.id}")
                elif node.id in DYNAMIC:
                    add("review", f"uses {node.id}() (code or names built while running)")
                elif node.id in ROUTE_OBJECTS:
                    add("review", f"uses {node.id} (a route built without a decorator)")
                elif node.id in routers and isinstance(node.ctx, ast.Load):
                    up = parent.get(node)
                    call = parent.get(up)
                    plain = isinstance(up, ast.Attribute) and isinstance(call, ast.Call) and call.func is up and \
                        (id(call) in decorators or up.attr == "include_router")
                    if not plain:
                        add("review", f"uses the router `{node.id}` other than to decorate a route")
            elif isinstance(node, ast.Attribute):
                if not isinstance(node.ctx, ast.Load) and (node.attr in GUARDS or node.attr == "get_current_user"
                                                           or (isinstance(node.value, ast.Name) and node.value.id in modules)):
                    add("fail", f"replaces `{node.attr}` on another module")
                elif node.attr == "dependency_overrides":
                    if not in_tests:
                        add("fail", "overrides a dependency (dependency_overrides), which can switch sign-in off")
                elif node.attr in ODD_ATTRS:
                    add("review", f"uses .{node.attr} (routes or request filters changed outside a decorator)")
                elif node.attr == "modules" and isinstance(node.value, ast.Name) and node.value.id == "sys":
                    add("review", "uses sys.modules (a module could be swapped)")
                elif node.attr in REGISTER:
                    add("fail", f"registers a route with {node.attr}() instead of a decorator")
                elif node.attr in METHODS and not (isinstance(parent.get(node), ast.Call) and parent[node].func is node):
                    add("review", f"takes .{node.attr} as a value instead of calling it as a decorator")
            elif isinstance(node, ast.Call):
                f = node.func
                if isinstance(f, ast.Call) and isinstance(f.func, ast.Attribute) and f.func.attr in METHODS:
                    add("fail", "registers a route by calling the decorator directly")
                elif isinstance(f, ast.Name) and f.id in ("getattr", "setattr") and node.args and \
                        isinstance(node.args[0], ast.Name) and node.args[0].id in (modules | routers):
                    add("review", f"uses {f.id}() on a module or router")
                if any(k.arg == "routes" for k in node.keywords):
                    add("review", "passes routes= (routes built without a decorator)")
        aliases = {t.id for n in ast.walk(tree) if isinstance(n, ast.Assign) and isinstance(n.value, ast.Call)
                   and isinstance(n.value.func, ast.Attribute) and n.value.func.attr in METHODS
                   for tt in n.targets for t in ast.walk(tt) if isinstance(t, ast.Name)}
        for fn in ast.walk(tree):
            if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            route_calls = [d for d in fn.decorator_list
                           if isinstance(d, ast.Call) and isinstance(d.func, ast.Attribute) and d.func.attr in METHODS]
            if not route_calls and not any(isinstance(d, ast.Name) and d.id in aliases for d in fn.decorator_list):
                continue
            a = fn.args
            in_params = any(is_guard(d) for d in [*a.defaults, *a.kw_defaults] if d is not None)
            in_decorator = any(is_guard(e) for d in route_calls for k in d.keywords if k.arg == "dependencies"
                               and isinstance(k.value, (ast.List, ast.Tuple)) for e in k.value.elts)
            if not (ok_names >= set(GUARDS) and (in_params or in_decorator)):
                same = sha_of(ast.dump(fn).encode())[:12]  # the release's own open routes pass only if identical
                add("fail", f"route `{fn.name}` has no permission check of its own: Depends(require_permission(...)) [{same}]")
    return out


def tables(versions_dir):
    """(created, dropped) table names, from real op.create_table / op.drop_table calls."""
    made, dropped = set(), set()
    for rel, data in py_files(versions_dir):
        if data is None or not rel.endswith(".py"):
            continue
        try:
            tree = ast.parse(data)
        except (SyntaxError, ValueError, RecursionError, MemoryError):
            continue
        called = any(isinstance(n, ast.Name) and n.id == "downgrade" and isinstance(n.ctx, ast.Load) for n in ast.walk(tree))
        undo = set() if called else {id(n) for fn in ast.walk(tree) if isinstance(fn, ast.FunctionDef)
                                     and fn.name == "downgrade" for n in ast.walk(fn)}  # the undo path doesn't count
        for node in ast.walk(tree):
            if id(node) in undo or not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
                continue
            attr = node.func.attr
            name = node.args[0] if node.args else next((k.value for k in node.keywords if k.arg in ("table_name", "name")), None)
            if attr == "create_table" and isinstance(name, ast.Constant) and isinstance(name.value, str):
                made.add(name.value)
            elif attr == "drop_table":
                dropped.add(name.value if isinstance(name, ast.Constant) and isinstance(name.value, str) else "*")
            elif attr == "execute":
                for c in ast.walk(node):
                    if isinstance(c, ast.Constant) and isinstance(c.value, str) and re.search(r"(?i)\bdrop\s+table\b", c.value):
                        dropped |= set(re.findall(r"\w+", c.value)) | {"*"}
    return made, dropped


def structure_fastapi_nextjs(app, fw, protected):
    """Rules the code must keep whatever the record says. The release's own scaffold sets the baseline."""
    fails = []
    ref = fw.scaffold_dir("fastapi-nextjs")
    need, _ = tables(os.path.join(ref, "backend", "alembic", "versions"))
    made, dropped = tables(os.path.join(app, "backend", "alembic", "versions"))
    for t in sorted(need - made):
        fails.append(f"no migration creates the `{t}` table (roles and permissions must live in the database)")
    _, ref_dropped = tables(os.path.join(ref, "backend", "alembic", "versions"))
    for t in sorted((need & dropped) | ({"a table it does not name"} if "*" in dropped - ref_dropped else set())):
        fails.append(f"a migration drops `{t}`")
    skip = {p[len("backend/"):] for p in protected if p.startswith("backend/")}  # pinned by hash instead
    allowed = code_findings(os.path.join(ref, "backend"), skip)  # what the release itself does, counted
    review = []
    for (rel, kind, what), n in sorted((code_findings(os.path.join(app, "backend"), skip) - allowed).items()):
        (fails if kind == "fail" else review).append(f"backend/{rel} {what}" + (f" ({n} times)" if n > 1 else ""))
    return fails, review


STRUCTURE = {"fastapi-nextjs": structure_fastapi_nextjs}


def base_blob(app, ref, rel):
    """Hash of `rel` at a base commit. Only a full commit id is accepted: a branch or tag name could be the PR's own."""
    if not re.fullmatch(r"[0-9a-f]{40}", ref or ""):
        return None
    if not git_dir_ok(app):
        return None  # files named HEAD, objects/ and config in the project are never read as a repository
    r = git(app, "show", f"{ref}:{rel}")
    return sha_of(r.stdout) if r.returncode == 0 else None


def check(app, fw, opts):
    fails, changed, accepted, notes, review = [], [], [], [], []
    rec = load_json(os.path.join(app, RECORD))
    if rec is None:
        fails.append(NO_RECORD)
        rec = {}
    framework = rec.get("framework") if isinstance(rec.get("framework"), dict) else {}
    recorded = framework.get("content_manifest_sha256")
    if rec and recorded != fw.digest:  # one condition; only the words depend on what differs
        if framework.get("version") != fw.version:
            fails.append("The build record names a different make-it release than the one it is checked against "
                         f"(record: {clean(framework.get('version'), 20)}, check: {fw.version}).")
        elif not isinstance(recorded, str) or not recorded:
            fails.append("The build record does not say which make-it content built it (it has no content digest). "
                         "Run /resume-it in this project, then push again.")
        else:
            fails.append(f"The version numbers are the same ({fw.version}) but the content differs "
                         f"(record: {clean(recorded, 12)}, check: {fw.digest[:12]}): it was sealed by another build of "
                         "make-it, or the record was edited. If your organization ships its own build of make-it, "
                         "check it against that reviewed build (see watermark.md, \"Checking against your own build of make-it\").")
    old_files = rec.get("security_files") if isinstance(rec.get("security_files"), list) else []
    noted = {e.get("path"): clean(e.get("note") or "") for e in old_files
             if isinstance(e, dict) and isinstance(e.get("path"), str)}
    project = rec.get("project") if isinstance(rec.get("project"), dict) else {}
    claimed = project.get("scaffold") if isinstance(project.get("scaffold"), str) else None
    scaffold = detect_scaffold(app, fw, claimed)
    protected = fw.protected(scaffold)
    if not protected:
        line = "No make-it security files were found in this project, so its security code could not be checked."
        (notes if "--allow-unlisted" in opts else review).append(line)
    for rel in protected:
        data = read_plain(os.path.join(app, rel))
        if data is None:
            fails.append(f"Security file missing or not a plain file: {rel}")
            continue
        got = sha_of(data)
        if got == fw.expected(scaffold, rel):
            continue
        if base_blob(app, opts.get("--base-ref"), rel) == got:
            accepted.append(rel)
        else:
            changed.append({"path": rel, "note": noted.get(rel, "")})
    fails += seal_fails(app, rec)
    if scaffold in STRUCTURE:
        more_fails, more_review = STRUCTURE[scaffold](app, fw, set(protected))
        fails += more_fails
        review += more_review
    result = "fail" if fails else "review" if (changed or review) else "pass"
    return {"result": result, "scaffold": scaffold, "fails": fails, "changed": changed,
            "accepted": accepted, "review": review, "notes": notes}


def cmd_verify(app, fw, opts):
    try:
        out = check(app, fw, opts)
    except Exception as e:  # anything unexpected is a fail, never a pass
        out = {"result": "fail", "scaffold": None, "fails": [f"The check could not finish ({type(e).__name__})."],
               "changed": [], "accepted": [], "review": [], "notes": []}
    if "--json" in opts:
        print(json.dumps(out, indent=2))
    else:
        for line in out["fails"]:
            print(f"FAIL  {clean(line, 400)}")
        for c in out["changed"]:
            print(f"REVIEW  {c['path']} differs from the make-it release" + (f" -- {c['note']}" if c["note"] else ""))
        for line in out["review"]:
            print(f"REVIEW  {clean(line, 400)}")
        for rel in out["accepted"]:
            print(f"accepted  {rel} (already on the base branch)")
        for line in out["notes"]:
            print(f"note  {line}")
        print({"pass": "make-it check: pass", "review": "make-it check: security review needed",
               "fail": "make-it check: fail"}[out["result"]])
    return {"pass": 0, "fail": 1, "review": 3}[out["result"]]


def main(argv):
    opts, args = {}, []
    it = iter(argv)
    for a in it:
        if a in ("--app", "--framework", "--results", "--base-ref", "--skill", "--restart"):
            opts[a] = next(it, None) or sys.exit(f"watermark: {a} needs a value")
        elif a in ("--json", "--allow-unlisted"):
            opts[a] = True
        else:
            args.append(a)
    fw_dir = os.path.abspath(opts.get("--framework") or os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if args[:1] == ["hook"]:
        return cmd_hook(fw_dir)
    if not args or args[0] not in ("seal", "write", "note", "verify"):
        sys.exit(__doc__)
    app = os.path.abspath(opts.get("--app") or ".")
    fw = Framework(fw_dir)
    if args[0] == "seal":
        return cmd_seal(app, fw, opts)
    if args[0] == "write":
        return cmd_write(app, fw, opts)
    if args[0] == "note":
        return cmd_note(app, fw, args[1:])
    return cmd_verify(app, fw, opts)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
