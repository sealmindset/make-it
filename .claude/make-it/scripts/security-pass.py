#!/usr/bin/env python3
"""Build-verify Part D's scanners, from pinned images. Spec: references/build-verify-security.md (Phase 1b, 6b).

Usage: security-pass.py scan <project>                         run the five scanners, print one line each
       security-pass.py audit-check <findings|coverage-ledger> <file>   run one of the audit's node checks

`scan` lists the project's files from the disk (no git), runs Semgrep, Bandit, npm audit, pip-audit and Trivy
from images pinned by digest with the project mounted read-only, and decides for each scanner one of: ran,
NOT RUN (with the reason the tool gave), nothing to audit (with what it looked for). Reports go to a private
folder, ~/.cache/make-it-security/<project>/<run>/, with result.json beside them.
Exit: 0 the pass completed (whatever the lines say); 2 it could not do its job. `audit-check` exits with the
checker's own code. Standard library only. Everything in the project is read as data, never run here.
"""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.parse

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
NOTHING = {"bandit": "no Python code found", "npm-audit": "no package-lock.json found",
           "pip-audit": "no requirements file found (requirements*.txt)"}
BASE = os.path.join(os.path.expanduser("~"), ".cache", "make-it-security")
AUDIT_DIR = os.path.join(os.path.expanduser("~"), ".claude", "make-it", "security-audit")
KEEP_DAYS = 7
TIMEOUT = 1800


class PassError(Exception):
    pass


def discover(project):
    """The files to audit, read from the disk: no git, no links followed, installed and built folders skipped."""
    found = {"py": [], "locks": [], "reqs": [], "venvs": []}
    for top, dirs, files in os.walk(project, followlinks=False):
        rel_top = os.path.relpath(top, project)
        rel = (lambda n: n) if rel_top == "." else (lambda n: rel_top + "/" + n)
        if "pyvenv.cfg" in files:  # a virtualenv, whatever its name
            found["venvs"].append(rel_top); dirs[:] = []; continue
        dirs[:] = [d for d in dirs if d not in PRUNE and not os.path.islink(os.path.join(top, d))]
        for f in files:
            p = os.path.join(top, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            if f.endswith(".py") and "tests" not in rel(f).split("/")[:-1]:
                found["py"].append(rel(f))
            elif f == "package-lock.json":
                found["locks"].append(rel(f))
            elif f.startswith("requirements") and f.endswith(".txt"):
                found["reqs"].append(rel(f))
    return {k: sorted(v) for k, v in found.items()}


def refused(text):
    """Why pip must not see this requirements file, or None. pip would fetch or read beyond the one file."""
    lines = text.replace("\\\n", " ").splitlines()
    for line in lines:
        words = line.split("#", 1)[0].split()
        for w in words:
            opt = w.split("=", 1)[0]
            if opt in ("-r", "--requirement", "-c", "--constraint"):
                return f"includes another file ({opt}), so pip-audit was not run on it"
            if opt in ("-e", "--editable"):
                return f"names a local or editable package ({opt}), so pip-audit was not run on it"
            if opt in ("-i", "--index-url", "--extra-index-url", "-f", "--find-links", "--trusted-host", "--no-index"):
                return f"names a package index or host ({opt}), so pip-audit was not run on it"
            for scheme in ("git+", "hg+", "svn+", "bzr+", "https://", "http://", "file:"):
                if w.startswith(scheme) or (scheme.endswith("://") and scheme in w):
                    return f"names a package by URL ({scheme}), so pip-audit was not run on it"
        if words and words[0].startswith((".", "/")):
            return f"names a local or editable package ({words[0]}), so pip-audit was not run on it"
    return None


def private_dir(path, uid=None):
    """Make (mode 0700) or accept a folder only if it is a real folder, this user's, and no one else's to read."""
    uid = os.getuid() if uid is None else uid
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    except OSError as e:
        raise PassError(f"could not make the report folder {path}: {e.strerror}")
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
        raise PassError(f"the report folder {path} is a link or not a folder: refused")
    if st.st_uid != uid or stat.S_IMODE(st.st_mode) & 0o077:
        raise PassError(f"the report folder {path} is not private to this user (owner {st.st_uid}, mode "
                        f"{oct(stat.S_IMODE(st.st_mode))}): refused")
    return path


def new_run(project, base=BASE):
    """A fresh run folder for this project; runs older than KEEP_DAYS are removed first. Loud on any failure."""
    os.makedirs(os.path.dirname(base), exist_ok=True)
    private_dir(base)
    proj = private_dir(os.path.join(base, hashlib.sha256(os.path.realpath(project).encode()).hexdigest()[:16]))
    for old in os.listdir(proj):
        p = os.path.join(proj, old)
        if old.startswith("run-") and time.time() - os.lstat(p).st_mtime > KEEP_DAYS * 86400:
            try:
                shutil.rmtree(p)
            except OSError as e:
                raise PassError(f"could not remove the old report folder {p}: {e.strerror}")
    return tempfile.mkdtemp(prefix=time.strftime("run-%Y%m%d-%H%M%S-"), dir=proj)  # mode 0700


def commands(project, found):
    """(report name, docker argv) for every scanner run. Nothing but the project (read-only) or one file goes in."""
    src = ["-v", f"{project}:/src:ro", "-w", "/src"]
    run = ["docker", "run", "--rm"]
    excl = [f"--exclude={n}" for n in sorted(PRUNE)] + [f"--exclude={v}" for v in found["venvs"]]
    out = [("semgrep", run + src + [IMAGES["semgrep"], "semgrep", "scan", "--config", "p/owasp-top-ten", "--config",
                                    "p/security-audit", "--json"] + excl + ["."])]
    if found["py"]:
        out.append(("bandit", run + src + [IMAGES["bandit"], "-f", "json", "-q"] + found["py"]))
    for lock in found["locks"]:
        out.append((part("npm-audit", lock), run + ["-v", f"{project}:/src:ro", "-w", "/src/" + os.path.dirname(lock)]
                     + [IMAGES["node"], "npm", "audit", "--json"]))
    for req in found["reqs"]:
        out.append((part("pip-audit", req), run + ["-v", f"{project}/{req}:/req/requirements.txt:ro", "-w", "/req",
                     IMAGES["python"], "sh", "-c", "pip install -q --root-user-action=ignore pip-audit==2.9.0 >&2 && "
                     "pip-audit --format=json -r requirements.txt"]))
    out.append(("trivy", run + ["-v", f"{project}:/src:ro", "-w", "/", "-v", "make-it-trivy-cache:/root/.cache/trivy",
                                IMAGES["trivy"], "fs", "--format", "json", "--quiet", "--skip-dirs", "node_modules",
                                "--skip-dirs", ".venv", "/src"]))
    return out


def part(scanner, path):
    return f"{scanner}--{urllib.parse.quote(path, safe='')}"


def audit_cmd(kind, path, audit_dir=AUDIT_DIR):
    if kind not in ("findings", "coverage-ledger"):
        raise PassError(f"audit-check takes findings or coverage-ledger, not {kind!r}")
    return ["docker", "run", "--rm", "--network", "none", "-v", f"{audit_dir}:/audit:ro", "-v",
            f"{os.path.dirname(path)}:/audit-run:ro", IMAGES["node"], "node", f"/audit/validate-{kind}.cjs",
            f"/audit-run/{os.path.basename(path)}"]


# ---- deciding: each takes the parsed report and returns (summary, None, warnings) or (None, reason, 0) ----

def _semgrep(r):
    fatal = [e for e in r["errors"] if e.get("level") == "error"]
    if fatal:
        return None, fatal[0].get("message", "a fatal error").splitlines()[0], 0
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
    s += f", {len(errs)} file not parsed (first: {name(errs[0])})" if errs else ""
    return s, None, len(errs)


def _npm(r):
    if "error" in r:
        e = r["error"] if isinstance(r["error"], dict) else {}
        return None, r.get("message") or e.get("summary") or e.get("detail") or "npm audit reported an error", 0
    return f"{r['metadata']['vulnerabilities']['total']} vulnerabilities", None, 0


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
    lines = [l.strip() for l in (err or "").splitlines() if l.strip()]
    marked = [l for l in lines if any(w in l.lower() for w in ("error", "fatal", "failed", "denied"))
              and "complete log of this run" not in l]
    if marked or lines:
        return (marked or lines)[-1][:300]
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
    except (TypeError, ValueError, KeyError, AttributeError, IndexError):
        return False, _stderr_reason(err, code), 0
    return (True, summary, warnings) if summary else (False, reason, 0)


def collect(run_dir):
    """Every scanner in ORDER gets exactly one state. A marker beside a report is an inconsistent folder: loud."""
    names = os.listdir(run_dir)
    out = {}
    for s in ORDER:
        marker = _read(os.path.join(run_dir, s + ".none"))
        reports = sorted({n.rsplit(".", 1)[0] for n in names if (n.startswith(s + "--") or n.rsplit(".", 1)[0] == s)
                          and n.rsplit(".", 1)[-1] in ("json", "err", "exit", "refused")})
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
            label = urllib.parse.unquote(n.split("--", 1)[1]) if "--" in n else None
            res["parts"].append({"file": label, "ran": ok, "text": text})
            res["warnings"] += warnings
        bad = [p for p in res["parts"] if not p["ran"]]
        res["state"] = "NOT RUN" if bad else "ran"
        res["counts"] = "; ".join(p["text"] for p in res["parts"] if p["ran"])
        res["reason"] = "; ".join(p["text"] for p in bad)
        out[s] = res
    return out


def line(s, res):
    if res["state"] == "nothing to audit":
        return f"{s}: nothing to audit -- {res['reason']}"
    parts = res["parts"]
    if not parts:
        return f"{s}: NOT RUN -- {res['reason']}"
    text = "; ".join((f"{p['file']}: " if p["file"] else "") + p["text"] for p in parts)
    bad = sum(1 for p in parts if not p["ran"])
    if not bad:
        return f"{s}: ran -- {text}"
    return f"{s}: NOT RUN -- {text}" if len(parts) == 1 else f"{s}: NOT RUN for {bad} of {len(parts)} -- {text}"


def scan(project):
    if not os.path.isdir(project):
        raise PassError(f"no such project folder: {project}")
    project = os.path.realpath(project)
    run_dir = new_run(project)
    found = discover(project)
    for s, key in (("bandit", "py"), ("npm-audit", "locks"), ("pip-audit", "reqs")):
        if not found[key]:
            with open(os.path.join(run_dir, s + ".none"), "w") as f:
                f.write(NOTHING[s] + "\n")
    for req in found["reqs"]:
        why = refused(_read(os.path.join(project, req)) or "")
        if why:
            with open(os.path.join(run_dir, part("pip-audit", req) + ".refused"), "w") as f:
                f.write(why + "\n")
    for name, argv in commands(project, found):
        if os.path.exists(os.path.join(run_dir, name + ".refused")):
            continue
        try:
            p = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, timeout=TIMEOUT)
            out, err, code = p.stdout, p.stderr, p.returncode
        except FileNotFoundError:
            out, err, code = b"", b"docker: not found on this computer\n", 127
        except subprocess.TimeoutExpired:
            out, err, code = b"", f"timed out after {TIMEOUT} seconds\n".encode(), 124
        for ext, data in (("json", out), ("err", err), ("exit", f"{code}\n".encode())):
            with open(os.path.join(run_dir, f"{name}.{ext}"), "wb") as f:
                f.write(data)
    res = collect(run_dir)
    with open(os.path.join(run_dir, "result.json"), "w") as f:
        json.dump({"project": project, "run_dir": run_dir, "scanners": res}, f, indent=1)
    for s in ORDER:
        print(line(s, res[s]))
    print(f"result: {os.path.join(run_dir, 'result.json')}")
    return 0


def main(argv):
    try:
        if argv[:1] == ["scan"] and len(argv) == 2:
            return scan(argv[1])
        if argv[:1] == ["audit-check"] and len(argv) == 3:
            return subprocess.run(audit_cmd(argv[1], os.path.abspath(argv[2])), stdin=subprocess.DEVNULL).returncode
    except (PassError, OSError) as e:
        print(f"security-pass: {e}", file=sys.stderr)
        return 2
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
