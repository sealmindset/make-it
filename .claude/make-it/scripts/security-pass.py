#!/usr/bin/env python3
"""Build-verify Part D's scanners, from pinned images. Spec: references/build-verify-security.md (Phase 1b, 6b).

Usage: security-pass.py scan <project>                         run the five scanners, print one line each
       security-pass.py audit-check <findings|coverage-ledger> <file>   run one of the audit's node checks

`scan` lists the project's files from the disk (no git), runs Semgrep, Bandit, npm audit, pip-audit and Trivy
from images pinned by digest (pip-audit itself is installed in its image at run time), and decides for each
scanner one of: ran, NOT RUN (with the reason the tool gave), nothing to audit (with what it looked for).
Reports go to a private folder, ~/.cache/make-it-security/<project>/<run>/, with result.json beside them.
Anything printed that came from the project or a tool is JSON-quoted: data, never a line of its own.
Exit: 0 the pass completed (whatever the lines say); 2 it could not do its job. `audit-check` exits with the
checker's own code. Standard library only. Everything in the project is read as data, never run here.
Not for Windows yet: it exits 2 there.
"""
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

IMAGES = {  # the one place the pins live; each is the multi-architecture index digest
    "semgrep": "semgrep/semgrep:1.85.0@sha256:b4c2272e0a2e59ca551ff96d3bbae657bd2b7356e339af557b27a96d9e751544",
    "bandit": "ghcr.io/pycqa/bandit/bandit@sha256:b405a808f5d50156aee921a77fb17c044d69d90ecef6499447a037678967c936",  # 1.9.4
    "trivy": "aquasec/trivy:0.68.2@sha256:05d0126976bdedcd0782a0336f77832dbea1c81b9cc5e4b3a5ea5d2ec863aca7",
    "node": "node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a",
    "python": "python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b",  # pip-audit has none
}
IMAGE_OF = {"semgrep": "semgrep", "bandit": "bandit", "npm-audit": "node", "pip-audit": "python", "trivy": "trivy"}
ORDER = ["semgrep", "bandit", "npm-audit", "pip-audit", "trivy"]
PRUNE = {"node_modules", ".git", ".tox", "site-packages", "__pycache__", ".next", "dist", "build", ".turbo",
         ".mypy_cache", ".pytest_cache", ".ruff_cache"}
LOCKS = ("package-lock.json", "npm-shrinkwrap.json")
NOTHING = {"bandit": "no Python code found", "npm-audit": "no package-lock.json or npm-shrinkwrap.json found",
           "pip-audit": "no requirements file found (requirements*.txt)"}
HARDEN = ["--cap-drop=ALL", "--security-opt", "no-new-privileges"]
NOBODY = ["--user", "65534:65534"]
PIP_CMD = "pip install -q --root-user-action=ignore pip-audit==2.9.0 >&2 && pip-audit --format=json -r requirements.txt"
LIMIT = 1_000_000  # bytes of one requirements file; a bigger file is NOT RUN, never partly read
WHY = ", so pip-audit was not run on this file"
NAME = r"[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?"
SPEC = r"(?:~=|===|==|!=|<=|>=|<|>)\s*[A-Za-z0-9.*+!_-]+"
REQ = re.compile(rf"^({NAME})\s*(?:\[\s*({NAME}(?:\s*,\s*{NAME})*)\s*\])?\s*({SPEC}(?:\s*,\s*{SPEC})*)?\s*$")
MARKER_VARS = {"python_version", "python_full_version", "os_name", "sys_platform", "platform_release", "platform_system",
               "platform_version", "platform_machine", "platform_python_implementation", "implementation_name",
               "implementation_version", "extra", "and", "or", "in", "not"}
MTOK = re.compile(r"""\s*(\(|\)|===|==|!=|<=|>=|~=|<|>|"[A-Za-z0-9._ *+!-]*"|'[A-Za-z0-9._ *+!-]*'|[A-Za-z_]+)""")
COMMENT = re.compile(r"(^|\s+)#.*$")  # pip's own rule: "#" starts a comment at line start or after whitespace
HASH = re.compile(r"^(sha256|sha384|sha512):[0-9a-fA-F]+$")
BINVAL = re.compile(rf"^(:all:|:none:|{NAME}(?:,{NAME})*)$")
FLAGS = {"--pre", "--prefer-binary", "--require-hashes"}  # kept as they are: they change no host and read no file
BINARY = {"--only-binary", "--no-binary"}  # kept with a checked value
INCLUDE, EDIT, INDEX, OTHER = ("a file include (-r or -c)", "an editable package (-e)", "a package index or host option",
                               "another pip option")
LONG = [("--requirement", INCLUDE), ("--constraint", INCLUDE), ("--editable", EDIT), ("--index-url", INDEX),
        ("--extra-index-url", INDEX), ("--find-links", INDEX), ("--trusted-host", INDEX), ("--no-index", INDEX)]
GLOB = set("*?[]{}!\\")
BASE = os.path.join(os.path.expanduser("~"), ".cache", "make-it-security")
AUDIT_DIR = os.path.join(os.path.expanduser("~"), ".claude", "make-it", "security-audit")
KEEP_DAYS = 7
TIMEOUT = 15 * 60  # one container
BUDGET = 45 * 60  # the whole pass
ARG_BUDGET = 100_000  # characters of file names on one Bandit command line


class PassError(Exception):
    pass


def q(text, limit=300):
    """Project or tool text as one quoted, escaped token: it can never start a line or read as ours."""
    text = str(text)
    return json.dumps(text if len(text) <= limit else text[:limit] + "...")


def _is_venv(path):
    if not os.path.isfile(os.path.join(path, "pyvenv.cfg")):
        return False
    for sub in ("bin", "Scripts"):
        d = os.path.join(path, sub)
        if os.path.isdir(d) and any(n.startswith("python") for n in os.listdir(d)):
            return True
    for lib in ("lib", "Lib"):
        d = os.path.join(path, lib)
        if os.path.isdir(os.path.join(d, "site-packages")):
            return True
        if os.path.isdir(d) and any(os.path.isdir(os.path.join(d, n, "site-packages")) for n in os.listdir(d) if n.startswith("python")):
            return True
    return False


def discover(project):
    """The files to audit, read from the disk: no git, no links followed, installed and built folders skipped."""
    found = {"py": [], "locks": [], "reqs": [], "venvs": [], "linked": []}
    for top, dirs, files in os.walk(project, followlinks=False):
        rel_top = os.path.relpath(top, project)
        rel = (lambda n: n) if rel_top == "." else (lambda n: rel_top + "/" + n)
        if rel_top != "." and _is_venv(top):  # a virtualenv, whatever its name; never the project root
            found["venvs"].append(rel_top); dirs[:] = []; continue
        dirs[:] = [d for d in dirs if d not in PRUNE and not os.path.islink(os.path.join(top, d))]
        for f in files:
            p = os.path.join(top, f)
            audited = f in LOCKS or (f.startswith("requirements") and f.endswith(".txt"))
            if os.path.islink(p):
                if audited:
                    found["linked"].append(rel(f))
                continue
            if not os.path.isfile(p):
                continue
            if f.endswith(".py") and "tests" not in rel(f).split("/")[:-1]:
                found["py"].append(rel(f))
            elif f in LOCKS:
                found["locks"].append(rel(f))
            elif audited:
                found["reqs"].append(rel(f))
    return {k: sorted(v) for k, v in found.items()}


def _kind(tok):
    """What a pip option is, in any spelling: -rFILE, --req (pip takes abbreviations), --INDEX-URL."""
    name = tok.split("=", 1)[0].lower()
    if not name.startswith("--"):
        return {"r": INCLUDE, "c": INCLUDE, "e": EDIT, "i": INDEX, "f": INDEX}.get(name[1:2], OTHER)
    return next((kind for full, kind in LONG if len(name) > 2 and full.startswith(name)), OTHER)


def _requirement(req):
    """A plain requirement re-written from its parsed pieces, or the kind of line it is."""
    spec, _, marker = req.partition(";")
    if "://" in req or re.match(r"^\s*(git|hg|svn|bzr)\+", req) or "@" in spec:
        return None, "a URL or VCS requirement"
    if spec.lstrip().startswith((".", "/", "~")):
        return None, "a local path requirement"
    m = REQ.match(spec)
    if not m:
        return None, "not a plain package requirement"
    out = m.group(1)
    if m.group(2):
        out += "[" + ",".join(x.strip() for x in m.group(2).split(",")) + "]"
    if m.group(3):
        out += ",".join(op + v for op, v in re.findall(r"(~=|===|==|!=|<=|>=|<|>)\s*([A-Za-z0-9.*+!_-]+)", m.group(3)))
    if _:
        toks, pos = [], 0
        while pos < len(marker.rstrip()):
            t = MTOK.match(marker, pos)
            if not t or (t.group(1)[0].isalpha() and t.group(1) not in MARKER_VARS):
                return None, "an environment marker this pass does not accept"
            toks.append('"' + t.group(1)[1:-1] + '"' if t.group(1)[0] in "'\"" else t.group(1)); pos = t.end()
        if not toks:
            return None, "an environment marker this pass does not accept"
        out += " ; " + " ".join(toks)
    return out, None


def _line(line):
    """One logical line: (the line the script writes, None) or (None, the kind of line it refused)."""
    tokens = line.split(" ")  # pip's own split: the requirement ends at the first word that starts with "-"
    cut = next((i for i, t in enumerate(tokens) if t.startswith("-")), len(tokens))
    req, opts = " ".join(t for t in tokens[:cut] if t), [t for t in tokens[cut:] if t]
    flags = [t for t in opts if t.startswith("-")]
    for kind in (INCLUDE, EDIT, INDEX):  # the ones that reach another file or host are named first
        if any(t not in FLAGS | BINARY and _kind(t) == kind for t in flags):
            return None, kind
    out, hashes, i = [], [], 0
    while i < len(opts):
        t = opts[i]; name, eq, val = t.partition("=")
        takes = name in BINARY or name == "--hash"
        if takes and not eq:
            i += 1; val = opts[i] if i < len(opts) else ""
        if name == "--hash":
            if not req:
                return None, "a --hash with no package"
            if not HASH.match(val):
                return None, "a --hash that is not algorithm:hex"
            hashes.append(val)
        elif req or not ((t in FLAGS) or (name in BINARY and BINVAL.match(val))):
            return None, OTHER
        else:
            out.append(t if t in FLAGS else f"{name}={val}")
        i += 1
    if not req:
        return "\n".join(out), None
    text, why = _requirement(req)
    return (text + "".join(f" --hash={h}" for h in hashes), None) if text else (None, why)


def sanitise(raw):
    """D-A: the requirements file pip will see, written by this script from parsed pieces, or (None, why not).
    A file is used whole or not at all: too big, not UTF-8, a NUL byte or one line off the grammar makes it NOT RUN."""
    if len(raw) > LIMIT:
        return None, f"the file is larger than {LIMIT:,} bytes{WHY}"
    if b"\0" in raw:
        return None, "the file has a NUL byte" + WHY
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None, "the file is not UTF-8" + WHY
    lines = text.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n").split("\n")
    logical, buf, start = [], [], 0
    for n, line in enumerate(lines, 1):  # pip's join_lines: a trailing backslash continues the line
        if not line.endswith("\\") or COMMENT.match(line):
            line = " " + line if COMMENT.match(line) else line
            if buf:
                logical.append((start, "".join(buf + [line]))); buf = []
            else:
                logical.append((n, line))
        else:
            start = start if buf else n
            buf.append(line.strip("\\"))
    if buf:
        logical.append((start, "".join(buf)))
    out = []
    for n, line in logical:
        line = COMMENT.sub("", line).strip()
        if line:
            text, kind = _line(line)
            if text is None:
                return None, f"line {n}: {kind}{WHY}"
            out.append(text)
    return "".join(l + "\n" for l in out), None


def private_dir(path, uid=None):
    """Make (mode 0700) or accept a folder only if it is a real folder, this user's, and no one else's to read."""
    if not hasattr(os, "getuid"):
        raise PassError("this script does not run on Windows yet")
    uid = os.getuid() if uid is None else uid
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    except OSError as e:
        raise PassError(f"could not make the report folder {path}: {e}")
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
        raise PassError(f"the report folder {path} is a link or not a folder: refused")
    if st.st_uid != uid or stat.S_IMODE(st.st_mode) & 0o077:
        raise PassError(f"the report folder {path} is not private to this user (owner {st.st_uid}, mode "
                        f"{oct(stat.S_IMODE(st.st_mode))}): refused")
    return path


def new_run(project, base=None):
    """A fresh run folder for this project; entries older than KEEP_DAYS are removed first, never followed."""
    base = base or BASE
    os.makedirs(os.path.dirname(base), exist_ok=True)
    private_dir(base)
    proj = private_dir(os.path.join(base, hashlib.sha256(os.path.realpath(project).encode("utf-8", "surrogateescape")).hexdigest()[:16]))
    for old in os.listdir(proj):
        p = os.path.join(proj, old)
        st = os.lstat(p)
        if old.startswith("run-") and time.time() - st.st_mtime > KEEP_DAYS * 86400:
            try:
                shutil.rmtree(p) if stat.S_ISDIR(st.st_mode) else os.unlink(p)
            except OSError as e:
                raise PassError(f"could not remove the old report folder {p}: {e}")
    return tempfile.mkdtemp(prefix=time.strftime("run-%Y%m%d-%H%M%S-"), dir=proj)  # mode 0700


def unmountable(*paths):
    """Why Docker cannot take this path in a -v spec, or None."""
    for p in paths:
        bad = sorted({c for c in p if c == ":" or ord(c) < 32 or ord(c) == 127})
        if bad:
            return f"its path has a character Docker cannot mount ({q(''.join(bad))[1:-1]}), so it was not run"
    return None


def _chunks(files):
    out, cur, size = [], [], 0
    for f in files:
        if cur and size + len(f) + 1 > ARG_BUDGET:
            out.append(cur); cur, size = [], 0
        cur.append(f); size += len(f) + 1
    return out + ([cur] if cur else [])


def commands(project, found, pip_inputs):
    """(scanner, label, argv-after-name, refusal) for every container. The project goes in read-only, or one or two
    files of it do, or for pip-audit only the requirements file the script wrote itself; nothing else. A refusal means
    it is never run. pip_inputs: requirements file -> (the script's own copy, or None, and why not)."""
    src = ["-v", f"{project}:/src:ro", "-w", "/src"]
    # a virtualenv is left out only by an anchored path ("a/b"): a bare name would hide that name at any depth
    excl = [f"--exclude={n}" for n in sorted(PRUNE)] + [f"--exclude={v}" for v in found["venvs"] if "/" in v and not GLOB & set(v)]
    bad = unmountable(project)
    out = [("semgrep", None, HARDEN + src + [IMAGES["semgrep"], "semgrep", "scan", "--config", "p/owasp-top-ten", "--config",
                                             "p/security-audit", "--json", "--metrics=off"] + excl + ["."], bad)]
    for chunk in _chunks(found["py"]):
        out.append(("bandit", None, HARDEN + NOBODY + src + [IMAGES["bandit"], "-f", "json", "-q", "--"] + chunk, bad))
    for lock in found["locks"] + [l for l in found["linked"] if os.path.basename(l) in LOCKS]:
        folder = os.path.dirname(lock)
        pkg = os.path.join(folder, "package.json") if folder else "package.json"
        why = ("it is a link, which this pass never follows" if lock in found["linked"] else
               "there is no package.json beside it" if not os.path.isfile(os.path.join(project, pkg)) or os.path.islink(os.path.join(project, pkg))
               else unmountable(f"{project}/{pkg}", f"{project}/{lock}"))
        out.append(("npm-audit", lock, HARDEN + ["--user", "node", "-v", f"{project}/{pkg}:/app/package.json:ro", "-v",
                    f"{project}/{lock}:/app/{os.path.basename(lock)}:ro", "-w", "/app", IMAGES["node"], "npm", "audit", "--json"], why))
    for req in found["reqs"] + [r for r in found["linked"] if os.path.basename(r) not in LOCKS]:
        copy, why = pip_inputs[req]
        out.append(("pip-audit", req, HARDEN + ["-v", f"{copy}:/req/requirements.txt:ro", "-w", "/req",
                                                IMAGES["python"], "sh", "-c", PIP_CMD], why))
    out.append(("trivy", None, HARDEN + ["-v", f"{project}:/src:ro", "-w", "/", "-v", "make-it-trivy-cache:/root/.cache/trivy",
                                         IMAGES["trivy"], "fs", "--format", "json", "--quiet", "--skip-dirs", "node_modules",
                                         "--skip-dirs", ".venv", "/src"], bad))
    return out


def audit_cmd(kind, path, audit_dir=None):
    if kind not in ("findings", "coverage-ledger"):
        raise PassError(f"audit-check takes findings or coverage-ledger, not {q(kind)}")
    if not os.path.isfile(path) or os.path.islink(path):
        raise PassError(f"audit-check: no such file {q(path)}")
    why = unmountable(os.path.dirname(path), audit_dir or AUDIT_DIR)
    if why:
        raise PassError(f"audit-check: {why}")
    return ["docker", "run", "--rm", "--network", "none"] + HARDEN + NOBODY + [
        "-v", f"{audit_dir or AUDIT_DIR}:/audit:ro", "-v", f"{os.path.dirname(path)}:/audit-run:ro", IMAGES["node"], "node",
        f"/audit/validate-{kind}.cjs", f"/audit-run/{os.path.basename(path)}"]


# ---- deciding: each takes the parsed report and returns (summary, None, warnings) or (None, reason, 0) ----

def _semgrep(r):
    fatal = [e for e in r["errors"] if e.get("level") == "error"]
    if fatal:
        return None, (fatal[0].get("message") or "a fatal error").splitlines()[0], 0
    scanned = len(r["paths"]["scanned"])
    if not scanned:
        return None, "scanned no files", 0
    failed = {e.get("path") for e in r["errors"] if "PartialParsing" not in str(e.get("type"))}
    if len(failed) >= scanned:
        return None, f"every scanned file failed to parse or timed out ({len(failed)} of {scanned} files)", 0
    s = f"{len(r['results'])} findings, {scanned} files"
    s += f", {len(r['errors'])} file warnings" if r["errors"] else ""
    s += f", {len(r['skipped_rules'])} rules skipped" if r.get("skipped_rules") else ""
    return s, None, len(r["errors"])


def _bandit(r):
    files = [k for k in r["metrics"] if k != "_totals"]
    loc, errs = r["metrics"]["_totals"]["loc"], r["errors"]
    name = lambda e: e["filename"][2:] if e["filename"].startswith("./") else e["filename"]
    if not files or loc <= 0:
        return None, "read no lines of code", 0
    if len(errs) >= len(files):
        return None, f"could not parse any file (first: {name(errs[0])}: {errs[0].get('reason', '')})", 0
    s = f"{len(r['results'])} findings, {len(files)} files, {loc} lines"
    s += f", {len(errs)} file not parsed (first: {q(name(errs[0]), 200)})" if errs else ""
    return s, None, len(errs)


def _npm(r):
    if "error" in r:
        e = r["error"] if isinstance(r["error"], dict) else {}
        return None, r.get("message") or e.get("summary") or e.get("detail") or "npm audit reported an error", 0
    deps = r["metadata"].get("dependencies", {})
    total = deps.get("total") if isinstance(deps, dict) else deps
    return f"{r['metadata']['vulnerabilities']['total']} vulnerabilities in {int(total)} dependencies", None, 0


def _pip(r):
    deps = r["dependencies"]
    if not isinstance(deps, list):
        raise ValueError
    return f"{len(deps)} packages, {sum(1 for d in deps if d.get('vulns'))} vulnerable", None, 0


def _trivy(r):
    if r.get("SchemaVersion") != 2 or r.get("ArtifactName") != "/src":
        return None, f"the report is not for the project folder (target {r.get('ArtifactName')})", 0
    res = r.get("Results") or []
    return f"{len(res)} files, {sum(len(x.get('Vulnerabilities') or []) for x in res)} vulnerabilities", None, 0


DECIDE = {"semgrep": _semgrep, "bandit": _bandit, "npm-audit": _npm, "pip-audit": _pip, "trivy": _trivy}


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return None


def _stderr_reason(err, code):
    lines = [l.strip() for l in (err or "").splitlines() if l.strip() and not l.strip().startswith(("Run 'docker", "See 'docker"))]
    marked = [l for l in lines if (l.lower().startswith("docker:") or any(w in l.lower() for w in ("error", "fatal", "failed", "denied")))
              and "complete log of this run" not in l]
    useful = [l for l in marked if "pip_audit._cli:Failed to install packages" not in l]  # pip-audit's wrapper says less than pip
    if marked or lines:
        return (useful or marked or lines)[-1]
    return f"no report and no error output (exit {code})"


def decide(run_dir, name, scanner):
    """One report: (True, summary, warnings) or (False, reason, 0). The reason is from the JSON when it gives one,
    else from stderr, else the exit code: never an empty file."""
    refusal = _read(os.path.join(run_dir, name + ".refused"))
    if refusal is not None:
        return False, refusal.strip(), 0
    text, err = _read(os.path.join(run_dir, name + ".json")), _read(os.path.join(run_dir, name + ".err"))
    code = (_read(os.path.join(run_dir, name + ".exit")) or "?").strip()
    try:
        summary, reason, warnings = DECIDE[scanner](json.loads(text))
    except Exception:
        return False, _stderr_reason(err, code), 0
    return (True, summary, warnings) if summary else (False, reason, 0)


def collect(run_dir):
    """Every scanner in ORDER gets exactly one state. A marker beside a report is an inconsistent folder: loud."""
    names = os.listdir(run_dir)
    out = {}
    for s in ORDER:
        marker = _read(os.path.join(run_dir, s + ".none"))
        bases = {n.rsplit(".", 1)[0] for n in names if n.rsplit(".", 1)[-1] in ("json", "err", "exit", "refused")}
        reports = sorted((b for b in bases if b == s or (b.startswith(s + "--") and b[len(s) + 2:].isdigit())),
                         key=lambda b: int(b[len(s) + 2:]) if "--" in b else 0)
        res = {"image": IMAGES[IMAGE_OF[s]], "counts": "", "warnings": 0, "reason": "", "parts": []}
        if marker is not None:
            if reports:
                raise PassError(f"{run_dir}: {s} has both a nothing-to-audit marker and a report")
            out[s] = dict(res, state="nothing to audit", reason=marker.strip())
            continue
        if not reports:
            out[s] = dict(res, state="NOT RUN", reason="no report: its step did not run")
            continue
        for n in reports:
            ok, text, warnings = decide(run_dir, n, s)
            label = None
            if "--" in n:
                raw = _read(os.path.join(run_dir, n + ".label"))
                if raw is None:
                    raise PassError(f"{run_dir}: {n} has no label")
                label = json.loads(raw)
            res["parts"].append({"file": label, "ran": ok, "text": text})
            res["warnings"] += warnings
        bad = [p for p in res["parts"] if not p["ran"]]
        res["state"] = "NOT RUN" if bad else "ran"
        res["counts"] = "; ".join(p["text"] for p in res["parts"] if p["ran"])
        res["reason"] = "; ".join(p["text"] for p in bad)
        out[s] = res
    return out


def line(s, res):
    """One line, with everything from the project or a tool quoted."""
    if res["state"] == "nothing to audit":
        return f"{s}: nothing to audit -- {res['reason']}"
    parts = res["parts"]
    if not parts:
        return f"{s}: NOT RUN -- {q(res['reason'])}"
    text = "; ".join((f"{q(p['file'])}: " if p["file"] is not None else "") + (p["text"] if p["ran"] else q(p["text"])) for p in parts)
    bad = sum(1 for p in parts if not p["ran"])
    if not bad:
        return f"{s}: ran -- {text}"
    return f"{s}: NOT RUN -- {text}" if len(parts) == 1 else f"{s}: NOT RUN for {bad} of {len(parts)} -- {text}"


class Stopped(Exception):
    """The script was told to stop (a kill or Ctrl-C)."""


def _stop(signum, frame):
    raise Stopped()


def _remove(name):
    try:
        subprocess.run(["docker", "rm", "-f", name], stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
    except Exception:
        pass


def _run(argv, name, deadline):
    """Run one container; on timeout, a kill or Ctrl-C remove it. Returns (stdout, stderr, code)."""
    left = deadline - time.monotonic()
    if left <= 0:
        return b"", f"the pass's time budget ({BUDGET} seconds) ran out before it started\n".encode(), "budget"
    try:
        p = subprocess.run(["docker", "run", "--rm", "--name", name] + argv, stdin=subprocess.DEVNULL, capture_output=True,
                           timeout=min(TIMEOUT, left))
        return p.stdout, p.stderr, p.returncode
    except FileNotFoundError:
        return b"", b"docker: not found on this computer\n", 127
    except subprocess.TimeoutExpired:
        _remove(name)
        return b"", f"timed out after {int(min(TIMEOUT, left))} seconds; the container was removed\n".encode(), 124
    except (Stopped, KeyboardInterrupt):
        _remove(name)
        raise Stopped("the running container was removed")


def _write(run_dir, base, ext, data):
    with open(os.path.join(run_dir, f"{base}.{ext}"), "wb" if isinstance(data, bytes) else "w") as f:
        f.write(data)


def _bandit_report(out, code):
    """A batch's report if it gave one: exit 0 or 1 and Bandit's own JSON."""
    if code not in (0, 1):
        return None
    try:
        r = json.loads(out)
        return r if isinstance(r.get("errors"), list) and isinstance(r.get("results"), list) and "_totals" in r["metrics"] else None
    except Exception:
        return None


def scan(project):
    if not os.path.isdir(project):
        raise PassError(f"no such project folder: {q(project)}")
    project = os.path.realpath(project)
    run_dir = new_run(project)
    found = discover(project)
    linked_locks = [l for l in found["linked"] if os.path.basename(l) in LOCKS]
    linked_reqs = [l for l in found["linked"] if l not in linked_locks]
    for s, have in (("bandit", found["py"]), ("npm-audit", found["locks"] + linked_locks), ("pip-audit", found["reqs"] + linked_reqs)):
        if not have:
            _write(run_dir, s, "none", NOTHING[s] + "\n")
    pip_inputs = {}
    for n, req in enumerate(found["reqs"] + linked_reqs, 1):  # D-A: pip only ever sees the script's own copy
        copy = os.path.join(run_dir, f"pip-audit--{n}.req.txt")
        if req in linked_reqs:
            pip_inputs[req] = (copy, "it is a link, which this pass never follows"); continue
        try:
            with open(os.path.join(project, req), "rb") as f:
                text, why = sanitise(f.read(LIMIT + 1))
        except OSError:
            text, why = None, "the file could not be read" + WHY
        why = why or unmountable(copy)
        if text is not None and not why:
            _write(run_dir, f"pip-audit--{n}", "req.txt", text)
        pip_inputs[req] = (copy, why)
    token, deadline = secrets.token_hex(6), time.monotonic() + BUDGET
    cmds = commands(project, found, pip_inputs)
    batches = sum(1 for c in cmds if c[0] == "bandit")
    index, bandit, k = {}, [], 0
    for i, (s, label, argv, why) in enumerate(cmds, 1):
        base = s
        if label is not None:
            index[s] = index.get(s, 0) + 1
            base = f"{s}--{index[s]}"
            _write(run_dir, base, "label", json.dumps(label) + "\n")
        if why:
            _write(run_dir, base, "refused", why + "\n")
            continue
        if s == "bandit" and bandit is None:
            continue  # a batch already failed: Bandit is NOT RUN, the rest is not started
        try:
            out, err, code = _run(argv, f"make-it-sp-{token}-{i}", deadline)
        except Stopped:
            raise
        except Exception as e:  # one scanner's failure never erases another's
            out, err, code = b"", f"could not start: {type(e).__name__}: {e}\n".encode(), "?"
        if s == "bandit":
            k += 1
            report = _bandit_report(out, code)
            if report is None:  # never another batch's report in its place
                _write(run_dir, "bandit", "json", out); _write(run_dir, "bandit", "err", err); _write(run_dir, "bandit", "exit", f"{code}\n")
                _write(run_dir, "bandit", "refused", f"batch {k} of {batches}: {_stderr_reason(err.decode('utf-8', 'replace'), code)}\n")
                bandit = None
            else:
                bandit.append(report)
            continue
        _write(run_dir, base, "json", out); _write(run_dir, base, "err", err); _write(run_dir, base, "exit", f"{code}\n")
    if bandit:
        merged = {"errors": [], "metrics": {"_totals": {"loc": 0}}, "results": []}
        for r in bandit:
            merged["errors"] += r["errors"]; merged["results"] += r["results"]
            for key, v in r["metrics"].items():
                if key == "_totals":
                    merged["metrics"]["_totals"]["loc"] += v["loc"]
                else:
                    merged["metrics"][key] = v
        _write(run_dir, "bandit", "json", json.dumps(merged)); _write(run_dir, "bandit", "err", ""); _write(run_dir, "bandit", "exit", "0\n")
    res = collect(run_dir)
    with open(os.path.join(run_dir, "result.json"), "w") as f:
        json.dump({"project": project, "run_dir": run_dir, "scanners": res}, f, indent=1)
    for s in ORDER:
        print(line(s, res[s]))
    print(f"result: {q(os.path.join(run_dir, 'result.json'), 10_000)[1:-1]}")
    return 0


def main(argv):
    signal.signal(signal.SIGTERM, _stop)
    try:
        if argv[:1] == ["scan"] and len(argv) == 2:
            return scan(argv[1])
        if argv[:1] == ["audit-check"] and len(argv) == 3:
            return subprocess.run(audit_cmd(argv[1], os.path.abspath(argv[2])), stdin=subprocess.DEVNULL).returncode
    except PassError as e:
        print(f"security-pass: {e}", file=sys.stderr)
        return 2
    except (Stopped, KeyboardInterrupt) as e:
        print("security-pass: stopped by a signal" + (f"; {e}" if str(e) else ""), file=sys.stderr)
        return 2
    except Exception as e:
        print(f"security-pass: unexpected error: {type(e).__name__}: {e}", file=sys.stderr)
        return 2
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
