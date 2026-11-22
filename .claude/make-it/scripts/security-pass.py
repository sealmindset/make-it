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
import secrets
import shutil
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
NOTHING = {"bandit": "no Python code found", "npm-audit": "no package-lock.json found",
           "pip-audit": "no requirements file found (requirements*.txt)"}
HARDEN = ["--cap-drop=ALL", "--security-opt", "no-new-privileges"]
NOBODY = ["--user", "65534:65534"]
PIP_CMD = "pip install -q --root-user-action=ignore pip-audit==2.9.0 >&2 && pip-audit --format=json -r requirements.txt"
PIP_ALLOWED = {"--hash", "--pre", "--prefer-binary", "--only-binary", "--no-binary", "--require-hashes"}
PIP_FILES = {"-r": "--requirement", "-c": "--constraint"}
PIP_LOCAL = {"-e": "--editable"}
PIP_HOSTS = {"-i": "--index-url", "-f": "--find-links"}
PIP_LONG = ["--requirement", "--constraint", "--editable", "--index-url", "--extra-index-url", "--find-links",
            "--trusted-host", "--no-index"] + sorted(PIP_ALLOWED)
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
            audited = f == "package-lock.json" or (f.startswith("requirements") and f.endswith(".txt"))
            if os.path.islink(p):
                if audited:
                    found["linked"].append(rel(f))
                continue
            if not os.path.isfile(p):
                continue
            if f.endswith(".py") and "tests" not in rel(f).split("/")[:-1]:
                found["py"].append(rel(f))
            elif f == "package-lock.json":
                found["locks"].append(rel(f))
            elif audited:
                found["reqs"].append(rel(f))
    return {k: sorted(v) for k, v in found.items()}


def _option(word):
    """A pip option word as its long name (abbreviations and -rFILE included), or None if it is not an option."""
    if not word.startswith("-"):
        return None
    name = word.split("=", 1)[0]
    if name.startswith("--"):
        hits = [o for o in PIP_LONG if o.startswith(name)] if len(name) > 2 else []
        if name in hits:
            return name
        risky = [o for o in hits if o not in PIP_ALLOWED]  # an abbreviation that could mean a refused option is that one
        return (risky or hits or [name])[0]
    short = name[:2]
    return {**PIP_FILES, **PIP_LOCAL, **PIP_HOSTS}.get(short, short)


def refused(text):
    """Why pip must not see this requirements file, or None. pip would fetch or read beyond the one file."""
    for line in text.replace("\\\n", " ").splitlines():
        words = line.split("#", 1)[0].split()
        for w in words:
            short = w.split("=", 1)[0][:2] if not w.startswith("--") else None
            opt = _option(w)
            shown = short if short in {**PIP_FILES, **PIP_LOCAL, **PIP_HOSTS} else opt
            if opt in ("--requirement", "--constraint"):
                return f"includes another file ({shown}), so pip-audit was not run on it"
            if opt == "--editable":
                return f"names a local or editable package ({shown}), so pip-audit was not run on it"
            if opt in ("--index-url", "--extra-index-url", "--find-links", "--trusted-host", "--no-index"):
                return f"names a package index or host ({shown}), so pip-audit was not run on it"
            if opt is not None and opt not in PIP_ALLOWED:
                return f"uses a pip option this pass does not allow ({w.split('=', 1)[0][:40]}), so pip-audit was not run on it"
            if "://" in w or w.startswith(("git+", "hg+", "svn+", "bzr+", "file:")) or "@file:" in w:
                return "names a package by URL, so pip-audit was not run on it"
        if words and words[0].startswith((".", "/", "~")):
            return f"names a local or editable package ({words[0][:40]}), so pip-audit was not run on it"
    return None


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


def commands(project, found):
    """(scanner, label, argv-after-name, refusal) for every container. The project goes in read-only, or one or two
    files of it do; nothing else. A refusal means it is never run."""
    src = ["-v", f"{project}:/src:ro", "-w", "/src"]
    excl = [f"--exclude={n}" for n in sorted(PRUNE)] + [f"--exclude={v}" for v in found["venvs"] if not GLOB & set(v)]
    bad = unmountable(project)
    out = [("semgrep", None, HARDEN + src + [IMAGES["semgrep"], "semgrep", "scan", "--config", "p/owasp-top-ten", "--config",
                                             "p/security-audit", "--json", "--metrics=off"] + excl + ["."], bad)]
    for chunk in _chunks(found["py"]):
        out.append(("bandit", None, HARDEN + NOBODY + src + [IMAGES["bandit"], "-f", "json", "-q", "--"] + chunk, bad))
    for lock in found["locks"] + [l for l in found["linked"] if l.endswith("package-lock.json")]:
        folder = os.path.dirname(lock)
        pkg = os.path.join(folder, "package.json") if folder else "package.json"
        why = ("it is a link, which this pass never follows" if lock in found["linked"] else
               "there is no package.json beside it" if not os.path.isfile(os.path.join(project, pkg)) or os.path.islink(os.path.join(project, pkg))
               else unmountable(f"{project}/{pkg}", f"{project}/{lock}"))
        out.append(("npm-audit", lock, HARDEN + ["--user", "node", "-v", f"{project}/{pkg}:/app/package.json:ro", "-v",
                    f"{project}/{lock}:/app/package-lock.json:ro", "-w", "/app", IMAGES["node"], "npm", "audit", "--json"], why))
    for req in found["reqs"] + [r for r in found["linked"] if not r.endswith("package-lock.json")]:
        if req in found["linked"]:
            why = "it is a link, which this pass never follows"
        else:
            with open(os.path.join(project, req), encoding="utf-8", errors="replace") as f:
                why = unmountable(f"{project}/{req}") or refused(f.read(1_000_000))
        out.append(("pip-audit", req, HARDEN + ["-v", f"{project}/{req}:/req/requirements.txt:ro", "-w", "/req",
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
    if marked or lines:
        return (marked or lines)[-1]
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


def _merge_bandit(outs):
    """Bandit chunks into one report, or None if any chunk did not give one."""
    merged = {"errors": [], "metrics": {"_totals": {"loc": 0}}, "results": []}
    for out in outs:
        try:
            r = json.loads(out)
            merged["errors"] += r["errors"]; merged["results"] += r["results"]
            for k, v in r["metrics"].items():
                if k == "_totals":
                    merged["metrics"]["_totals"]["loc"] += v["loc"]
                else:
                    merged["metrics"][k] = v
        except Exception:
            return None
    return json.dumps(merged).encode()


def _run(argv, name, deadline):
    """Run one container; on timeout remove it. Returns (stdout, stderr, code)."""
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
        try:
            subprocess.run(["docker", "rm", "-f", name], stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
        except Exception:
            pass
        return b"", f"timed out after {int(min(TIMEOUT, left))} seconds; the container was removed\n".encode(), 124


def _write(run_dir, base, ext, data):
    with open(os.path.join(run_dir, f"{base}.{ext}"), "wb" if isinstance(data, bytes) else "w") as f:
        f.write(data)


def scan(project):
    if not os.path.isdir(project):
        raise PassError(f"no such project folder: {q(project)}")
    project = os.path.realpath(project)
    run_dir = new_run(project)
    found = discover(project)
    linked_locks = [l for l in found["linked"] if l.endswith("package-lock.json")]
    for s, have in (("bandit", found["py"]), ("npm-audit", found["locks"] + linked_locks),
                    ("pip-audit", found["reqs"] + [l for l in found["linked"] if l not in linked_locks])):
        if not have:
            _write(run_dir, s, "none", NOTHING[s] + "\n")
    token, deadline = secrets.token_hex(6), time.monotonic() + BUDGET
    index, bandit = {}, []
    for i, (s, label, argv, why) in enumerate(commands(project, found), 1):
        base = s
        if label is not None:
            index[s] = index.get(s, 0) + 1
            base = f"{s}--{index[s]}"
            _write(run_dir, base, "label", json.dumps(label) + "\n")
        if why:
            _write(run_dir, base, "refused", why + "\n")
            continue
        if s == "bandit" and bandit and bandit[-1][2] not in (0, 1):
            continue  # a chunk already failed: its report stands
        try:
            out, err, code = _run(argv, f"make-it-sp-{token}-{i}", deadline)
        except Exception as e:  # one scanner's failure never erases another's
            out, err, code = b"", f"could not start: {type(e).__name__}: {e}\n".encode(), "?"
        if s == "bandit":
            bandit.append((out, err, code))
            continue
        _write(run_dir, base, "json", out); _write(run_dir, base, "err", err); _write(run_dir, base, "exit", f"{code}\n")
    if bandit:
        failed = [b for b in bandit if b[2] not in (0, 1)]
        merged = None if failed else _merge_bandit([b[0] for b in bandit])
        out, err, code = (merged, b"".join(b[1] for b in bandit), max(b[2] for b in bandit)) if merged else (failed or bandit)[0]
        _write(run_dir, "bandit", "json", out); _write(run_dir, "bandit", "err", err); _write(run_dir, "bandit", "exit", f"{code}\n")
    res = collect(run_dir)
    with open(os.path.join(run_dir, "result.json"), "w") as f:
        json.dump({"project": project, "run_dir": run_dir, "scanners": res}, f, indent=1)
    for s in ORDER:
        print(line(s, res[s]))
    print(f"result: {q(os.path.join(run_dir, 'result.json'), 10_000)[1:-1]}")
    return 0


def main(argv):
    try:
        if argv[:1] == ["scan"] and len(argv) == 2:
            return scan(argv[1])
        if argv[:1] == ["audit-check"] and len(argv) == 3:
            return subprocess.run(audit_cmd(argv[1], os.path.abspath(argv[2])), stdin=subprocess.DEVNULL).returncode
    except PassError as e:
        print(f"security-pass: {e}", file=sys.stderr)
        return 2
    except Exception as e:
        print(f"security-pass: unexpected error: {type(e).__name__}: {e}", file=sys.stderr)
        return 2
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
