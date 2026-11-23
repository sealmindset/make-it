#!/usr/bin/env python3
"""adoption-scan.py -- sort an organisation's GitHub repositories by make-it use. Read-only.

Usage: adoption-scan.py --org NAME | --user NAME  [--limit N] [--page-size N] [--trailers]
                        [--ci-pattern TEXT] [--out DIR]

Uses the `gh` CLI the administrator is already signed in with: it never takes, reads or prints a
token. Every call is a read: GraphQL queries (a mutation is refused before gh runs) and REST GETs to
the two search endpoints. No clones; default branches only. Spec: references/adoption-scan.md.

Exit: 0 every repository scanned; 3 finished, but some repositories could not be scanned or a search
failed (the summary says which: they are never counted as "no signal"); 2 could not scan at all
(gh missing or signed out, no such organisation, a refused output folder, a bad argument).
Everything a repository holds is untrusted data: sizes are capped, nothing is run, and nothing a
repository supplies reaches a shell. Standard library only.
"""
import argparse
import csv
import datetime
import io
import json
import os
import re
import subprocess
import sys
import time

LOGIN = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})")
REPO = re.compile(r"[A-Za-z0-9._-]{1,100}")
MUTATION = re.compile(r"\bmutation\b", re.I)
SEARCH_PATHS = ("search/code", "search/commits")
TOKEN = re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}")
LEDGER_NAME = re.compile(r"\d{4,}-[0-9a-f]{12}\.json")
SKILL = re.compile(r"[a-z][a-z0-9-]{1,29}")
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
MANIFEST_CAP = 1 << 20        # as watermark.py: no record is bigger than 1 MB
ENTRY_CAP = 64 << 10          # a real ledger entry is about 1 KB
WORKFLOW_CAP = 256 << 10
ENTRIES_READ = 2000           # per repository; more are counted, not read
RESPONSE_CAP = 256 << 20      # ponytail: whole answer held in memory; a bigger one fails the batch and shrinks it
CALL_TIMEOUT = 120
TRIES = 4
PACE = {"search/code": 6.5, "search/commits": 2.1}  # GitHub: 10 and 30 search requests a minute
CLASSES = ["make-it", "make-it, no build record", "Claude Code, no make-it", "no signal", "not scanned"]
LABEL = "ship-it-managed"
TRAILER = '"Co-Authored-By: Claude"'
_last = {}
SLEEP = time.sleep  # the test records waits here instead of sleeping


class GhFailed(Exception):
    """gh or GitHub could not answer. `retry_smaller`: a timeout or an oversized answer."""

    def __init__(self, why, retry_smaller=False, status=None):
        super().__init__(why)
        self.retry_smaller, self.status = retry_smaller, status


def clean(text, limit=200):
    """One printable line, never token-shaped: repository text is untrusted."""
    s = "".join(c for c in " ".join(str(text).split()) if c.isprintable())[:limit]
    return TOKEN.sub("[removed]", s)


# ---------------------------------------------------------------- gh: reads only

def run_gh(args):
    """(status, headers, body). gh's own messages are never printed: only the HTTP answer is used."""
    try:
        p = subprocess.run(["gh", "api", "-i", *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           stdin=subprocess.DEVNULL, timeout=CALL_TIMEOUT)
    except FileNotFoundError:
        raise GhFailed("The GitHub CLI (gh) is not installed or not on PATH.")
    except subprocess.TimeoutExpired:
        raise GhFailed("GitHub did not answer in time.", retry_smaller=True)
    out = p.stdout
    if len(out) > RESPONSE_CAP:
        raise GhFailed("GitHub's answer was too large.", retry_smaller=True)
    text = out.decode("utf-8", "replace")
    m = re.match(r"HTTP/[\d.]+ (\d{3})[^\n]*\n(.*?)\r?\n\r?\n(.*)\Z", text, re.S)
    if not m:
        raise GhFailed("gh gave no answer from GitHub. Is gh signed in? Check with: gh auth status")
    headers = {}
    for line in m.group(2).splitlines():
        k, _, v = line.partition(":")
        headers[k.strip().lower()] = v.strip()
    return int(m.group(1)), headers, m.group(3)


def wait_for(status, headers, body, attempt):
    """Seconds to wait before retrying, as GitHub documents, or None if this is not a rate limit."""
    limited = status == 429 or (status == 403 and ("retry-after" in headers or headers.get("x-ratelimit-remaining") == "0"
                                                   or "rate limit" in body.lower()))
    if not limited:
        return None
    if headers.get("retry-after", "").isdigit():
        return int(headers["retry-after"])
    if headers.get("x-ratelimit-remaining") == "0" and headers.get("x-ratelimit-reset", "").isdigit():
        return max(1, int(headers["x-ratelimit-reset"]) - int(time.time()) + 1)
    return 60 * 2 ** attempt  # no header: at least a minute, then longer


def call(args, pace_key=None):
    for attempt in range(TRIES):
        if pace_key:
            gap = PACE[pace_key] - (time.monotonic() - _last.get(pace_key, -1e9))
            if gap > 0:
                SLEEP(gap)
            _last[pace_key] = time.monotonic()
        status, headers, body = run_gh(args)
        wait = wait_for(status, headers, body, attempt)
        if wait is None:
            return status, headers, body
        if wait >= 30:
            print(f"Waiting {wait} s: GitHub asked this scan to slow down.", file=sys.stderr)
        SLEEP(wait)
    raise GhFailed("GitHub's rate limit held after several waits.")


def gh_graphql(query, variables):
    if MUTATION.search(query) or not query.lstrip().startswith("query"):
        raise RuntimeError("refused: this scan sends GraphQL queries only, never a mutation")
    args = ["graphql", "-f", "query=" + query]
    for k, v in variables.items():
        args += ["-f", f"{k}={v}"]  # -f: a raw string, so a value is never read as @file
    for attempt in range(TRIES):
        status, headers, body = call(args)
        if status >= 500:
            raise GhFailed("GitHub timed out.", retry_smaller=True, status=status)
        if status != 200:
            raise GhFailed(f"GitHub refused the query (HTTP {status}).", status=status)
        try:
            doc = json.loads(body)
        except (ValueError, RecursionError):
            raise GhFailed("GitHub's answer was not readable.", retry_smaller=True)
        if not isinstance(doc, dict):
            raise GhFailed("GitHub's answer was not readable.", retry_smaller=True)
        errors = doc.get("errors") if isinstance(doc.get("errors"), list) else []
        if not any(isinstance(e, dict) and e.get("type") == "RATE_LIMITED" for e in errors):
            break
        SLEEP(60 * 2 ** attempt)  # GraphQL's own rate-limit answer: wait at least a minute, then longer
    else:
        raise GhFailed("GitHub's rate limit held after several waits.")
    remaining, reset = headers.get("x-ratelimit-remaining", ""), headers.get("x-ratelimit-reset", "")
    if remaining.isdigit() and int(remaining) < 50 and reset.isdigit():
        SLEEP(max(0, int(reset) - int(time.time()) + 1))  # primary limit nearly used: wait for the reset
    return doc


def gh_get(path, params, pace=True):
    if path not in SEARCH_PATHS:
        raise RuntimeError("refused: this scan only reads GitHub's search endpoints")
    args = ["-X", "GET", path]
    for k, v in params.items():
        args += ["-f", f"{k}={v}"]
    status, _, body = call(args, path if pace else None)
    if status != 200:
        raise GhFailed(f"GitHub refused the search (HTTP {status}).", status=status)
    try:
        doc = json.loads(body)
    except (ValueError, RecursionError):
        raise GhFailed("GitHub's search answer was not readable.")
    if not isinstance(doc, dict):
        raise GhFailed("GitHub's search answer was not readable.")
    return doc


# ---------------------------------------------------------------- listing and content

LIST_QUERY = """query($login: String!, $after: String) {
  repositoryOwner(login: $login) {
    __typename login
    repositories(first: 100, after: $after, ownerAffiliations: OWNER, orderBy: {field: NAME, direction: ASC}) {
      pageInfo { hasNextPage endCursor }
      nodes { name nameWithOwner isArchived isFork }
    }
  }
}"""

BLOB = "... on Blob { byteSize isTruncated text }"
TREE = "... on Tree { entries { name type object { " + BLOB + " } } }"
REPO_FIELDS = """r{i}: repository(owner: $o, name: $n{i}) {
    ctx: object(expression: "HEAD:.make-it/app-context.json") { __typename }
    rootctx: object(expression: "HEAD:app-context.json") { __typename }
    state: object(expression: "HEAD:.make-it-state.md") { __typename }
    manifest: object(expression: "HEAD:.make-it/manifest.json") { __typename BLOB }
    ledger: object(expression: "HEAD:.make-it/ledger") { __typename TREE }
    readable: object(expression: "HEAD:MAKE-IT.md") { __typename }
    claudemd: object(expression: "HEAD:CLAUDE.md") { __typename }
    claudedir: object(expression: "HEAD:.claude") { __typename }
    shipit: pullRequests(labels: ["LABEL"], first: 1, orderBy: {field: CREATED_AT, direction: DESC}) { totalCount nodes { createdAt } }
    WORKFLOWS
  }""".replace("BLOB", BLOB).replace("TREE", TREE).replace("LABEL", LABEL)
WORKFLOWS = 'workflows: object(expression: "HEAD:.github/workflows") { __typename ' + TREE + " }"


def list_repos(login, want_type, limit):
    repos, after = [], None
    while True:
        v = {"login": login}
        if after:
            v["after"] = after
        doc = gh_graphql(LIST_QUERY, v)
        owner = (doc.get("data") or {}).get("repositoryOwner")
        if not isinstance(owner, dict):
            raise SystemExit(f"No organisation or account named {login} is visible to the account gh is signed in with.")
        if owner.get("__typename") != want_type:
            if want_type == "Organization":
                raise SystemExit(f"{login} is a personal account, not an organisation. "
                                 f"To scan its repositories, run with --user {login}")
            raise SystemExit(f"{login} is an organisation. Run with --org {login}")
        conn = owner.get("repositories") or {}
        for n in conn.get("nodes") or []:
            if isinstance(n, dict) and isinstance(n.get("nameWithOwner"), str):
                repos.append(n)
                if limit and len(repos) >= limit:
                    return repos
        page = conn.get("pageInfo") or {}
        if not page.get("hasNextPage") or not page.get("endCursor"):
            return repos
        after = page["endCursor"]


def content_query(n, workflows):
    head = "query($o: String!" + "".join(f", $n{i}: String!" for i in range(n)) + ") {\n  "
    body = "\n  ".join(REPO_FIELDS.replace("{i}", str(i)).replace("WORKFLOWS", WORKFLOWS if workflows else "")
                       for i in range(n))
    return head + body + "\n}"


def fetch(login, names, workflows, results):
    """Fill results[name] with GitHub's object, or the reason it could not be read.

    A timeout, or an error that names no repository, halves the batch and tries again, down to one.
    An error that names a repository tries that repository once more on its own."""
    def smaller(why):
        if len(names) == 1:
            results[names[0]] = why
            return
        half = len(names) // 2
        fetch(login, names[:half], workflows, results)
        fetch(login, names[half:], workflows, results)

    try:
        doc = gh_graphql(content_query(len(names), workflows), {"o": login, **{f"n{i}": n for i, n in enumerate(names)}})
    except GhFailed as e:
        if e.retry_smaller:
            smaller(str(e))
        else:
            for n in names:
                results[n] = str(e)
        return
    data = doc.get("data") if isinstance(doc.get("data"), dict) else {}
    errors = [e for e in doc.get("errors") or [] if isinstance(e, dict)] if isinstance(doc.get("errors"), list) else []
    named = [e["path"][0] for e in errors if isinstance(e.get("path"), list) and e["path"]]
    if len(named) < len(errors):  # a timeout or a resource limit: nothing in this answer is trusted
        smaller("GitHub returned an error for this repository.")
        return
    for i, n in enumerate(names):
        got = data.get(f"r{i}")
        if f"r{i}" not in named and isinstance(got, dict):
            results[n] = got
        elif len(names) == 1:
            results[n] = "GitHub returned an error for this repository."
        else:
            fetch(login, [n], workflows, results)


# ---------------------------------------------------------------- reading what a repository holds

def blob_text(obj, cap):
    if not isinstance(obj, dict) or obj.get("isTruncated") or not isinstance(obj.get("text"), str):
        return None
    size = obj.get("byteSize")
    if not isinstance(size, int) or size > cap or len(obj["text"]) > cap:
        return None
    return obj["text"]


def parse_json(text):
    try:
        d = json.loads(text)
    except (ValueError, RecursionError):
        return None
    return d if isinstance(d, dict) else None


def read_manifest(obj):
    out = {"ma1_build_record": isinstance(obj, dict), "ma1_readable": False,
           "ma1_version": None, "ma1_type": None, "ma1_scaffold": None}
    rec = parse_json(blob_text(obj, MANIFEST_CAP) or "") if out["ma1_build_record"] else None
    if rec is not None:
        fw = rec.get("framework") if isinstance(rec.get("framework"), dict) else {}
        pr = rec.get("project") if isinstance(rec.get("project"), dict) else {}
        out.update(ma1_readable=True,
                   ma1_version=clean(fw["version"], 20) if isinstance(fw.get("version"), str) else None,
                   ma1_type=clean(pr["type"], 40) if isinstance(pr.get("type"), str) else None,
                   ma1_scaffold=clean(pr["scaffold"], 40) if isinstance(pr.get("scaffold"), str) else None)
    return out


def read_ledger(obj):
    """Every entry is counted; only well-formed ones (watermark.py's shape) are broken down."""
    entries = [e for e in (obj.get("entries") if isinstance(obj, dict) and isinstance(obj.get("entries"), list) else [])
               if isinstance(e, dict) and e.get("type") == "blob" and isinstance(e.get("name"), str)
               and not e["name"].startswith(".")]
    skills, dates, versions, bad = {}, [], set(), 0
    for i, e in enumerate(entries):
        d = None
        if i < ENTRIES_READ and LEDGER_NAME.fullmatch(e["name"]):
            d = parse_json(blob_text(e.get("object"), ENTRY_CAP) or "")
        mi = d.get("make_it") if d else None
        if not (d and isinstance(d.get("skill"), str) and SKILL.fullmatch(d["skill"])
                and isinstance(d.get("date"), str) and DATE.fullmatch(d["date"])
                and isinstance(mi, dict) and isinstance(mi.get("version"), str)):
            bad += 1
            continue
        skills[d["skill"]] = skills.get(d["skill"], 0) + 1
        dates.append(d["date"])
        versions.add(clean(mi["version"], 20))
    return {"ma2_ledger_entries": len(entries), "ma2_unreadable": bad, "ma2_skills": dict(sorted(skills.items())),
            "ma2_latest": max(dates) if dates else None, "ma2_versions": sorted(versions)}


def ci_refs(obj, pattern):
    refs = []
    for e in (obj.get("entries") or []) if isinstance(obj, dict) and isinstance(obj.get("entries"), list) else []:
        if not (isinstance(e, dict) and isinstance(e.get("name"), str) and e["name"].endswith((".yml", ".yaml"))):
            continue
        text = blob_text(e.get("object"), WORKFLOW_CAP)
        for m in re.finditer(re.escape(pattern) + r"[^@\s\"']*@([^\s\"'#]{1,100})", text or ""):
            refs.append(clean(m.group(1), 100))
    return sorted(set(refs))


def signals(c, hits, trailers, pattern):
    where = [label for key, label in (("ctx", ".make-it/app-context.json"), ("rootctx", "app-context.json"),
                                      ("state", ".make-it-state.md")) if isinstance(c.get(key), dict)]
    for p in hits:  # the code search sees the default branch too; a hit is a decision file wherever it is
        label = p if p in (".make-it/app-context.json", "app-context.json") else "app-context.json elsewhere (code search)"
        if label not in where:
            where.append(label)
    ship = c.get("shipit") if isinstance(c.get("shipit"), dict) else {}
    nodes = ship.get("nodes") if isinstance(ship.get("nodes"), list) else []
    latest = nodes[0].get("createdAt") if nodes and isinstance(nodes[0], dict) else None
    s = {"ma0_decision_file": bool(where), "ma0_where": where}
    s.update(read_manifest(c.get("manifest")))
    s.update(read_ledger(c.get("ledger")))
    s.update({
        "ma3_make_it_md": isinstance(c.get("readable"), dict),
        "ma4_ci_refs": ci_refs(c.get("workflows"), pattern) if pattern else None,
        "ma5_ship_it_prs": ship.get("totalCount") if isinstance(ship.get("totalCount"), int) else 0,
        "ma5_latest": latest[:10] if isinstance(latest, str) and DATE.match(latest) else None,
        "ma6_claude_files": isinstance(c.get("claudemd"), dict) or isinstance(c.get("claudedir"), dict),
        "ma7_trailer_commits": trailers,
    })
    return s


def classify(s):
    if s is None:
        return "not scanned"
    if s["ma1_build_record"]:
        return "make-it"
    if s["ma0_decision_file"] or s["ma2_ledger_entries"] or s["ma3_make_it_md"]:
        return "make-it, no build record"
    if s["ma6_claude_files"] or s["ma7_trailer_commits"]:
        return "Claude Code, no make-it"
    return "no signal"


# ---------------------------------------------------------------- searches

def search(path, q, notes):
    """{repository full name (lower case): [paths]} and the total, or None if the search failed."""
    found, seen, total = {}, 0, 0
    for page in range(1, 11):  # GitHub returns at most 1,000 results: 10 pages of 100
        try:
            doc = gh_get(path, {"q": q, "per_page": "100", "page": str(page)})
        except GhFailed:
            return None, 0
        items = doc.get("items") if isinstance(doc.get("items"), list) else []
        total = doc.get("total_count") if isinstance(doc.get("total_count"), int) else 0
        if doc.get("incomplete_results"):
            notes.add(f"GitHub said the {path} results may be incomplete (it ran out of time).")
        for it in items:
            repo = (it.get("repository") or {}).get("full_name") if isinstance(it, dict) else None
            if isinstance(repo, str):
                found.setdefault(repo.lower(), []).append(it.get("path") if isinstance(it.get("path"), str) else "")
        seen += len(items)
        if not items or seen >= total:
            break
    return found, total


# ---------------------------------------------------------------- output

def out_dir(given):
    """The folder to write to, checked before anything is asked of GitHub. Exits 2 with the reason."""
    if given:
        path = os.path.abspath(given)
    else:
        base = os.path.abspath(f"adoption-scan-{datetime.datetime.now():%Y-%m-%d-%H%M%S}")
        path, n = base, 1
        while os.path.lexists(path):
            n += 1
            path = f"{base}-{n}"
    if os.path.islink(path) or (os.path.lexists(path) and not os.path.isdir(path)):
        raise SystemExit(f"Refused: {path} is a link or not a folder.")
    for name in ("adoption-scan.json", "adoption-scan.csv"):
        if os.path.lexists(os.path.join(path, name)):
            raise SystemExit(f"Refused: {os.path.join(path, name)} already exists. Pick a new folder.")
    probe = path
    while not os.path.exists(probe):
        probe = os.path.dirname(probe)
    real = os.path.join(os.path.realpath(probe), os.path.relpath(path, probe))  # a linked parent can't hide a project
    top = os.path.realpath(probe)
    while top != os.path.dirname(top) and not os.path.lexists(os.path.join(top, ".git")):
        top = os.path.dirname(top)
    if os.path.lexists(os.path.join(top, ".git")):
        why = (f"Refused: {path} is inside a git project ({top}) and git does not ignore it. The files hold the "
               "organisation's repository names, and a commit could publish them. Pick a folder outside any project, "
               "or add it to that project's .gitignore.")
        for name in ("adoption-scan.json", "adoption-scan.csv"):
            try:
                p = subprocess.run(["git", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=" + os.devnull,
                                    "-C", top, "check-ignore", "-q", "--", os.path.relpath(os.path.join(real, name), top)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            except (OSError, subprocess.TimeoutExpired):
                raise SystemExit(why)
            if p.returncode != 0:
                raise SystemExit(why)
    return path


def csv_cell(v):
    if v is None:
        s = ""
    elif isinstance(v, bool):
        s = "yes" if v else "no"
    elif isinstance(v, dict):
        s = ";".join(f"{k}:{n}" for k, n in v.items())
    elif isinstance(v, list):
        s = ";".join(str(x) for x in v)
    else:
        s = str(v)
    s = clean(s, 2000)
    return "'" + s if s[:1] in ("=", "+", "-", "@", "\t", "\r") else s  # a spreadsheet never reads it as a formula


def write_file(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "w", newline="") as f:
        f.write(text)


def write_outputs(path, report):
    os.makedirs(path, mode=0o700, exist_ok=True)
    write_file(os.path.join(path, "adoption-scan.json"), json.dumps(report, indent=2) + "\n")
    rows = report["repositories"]
    cols = list(rows[0].keys()) if rows else ["repository"]
    buf = io.StringIO()
    w = csv.writer(buf, quoting=csv.QUOTE_ALL)
    w.writerow(cols)
    for r in rows:
        w.writerow([csv_cell(r.get(c)) for c in cols])
    write_file(os.path.join(path, "adoption-scan.csv"), buf.getvalue())


def summary(report, path):
    rows = [r for r in report["repositories"] if not r["archived"]]
    archived = [r["repository"] for r in report["repositories"] if r["archived"]]
    scanned = [r for r in rows if r["class"] != "not scanned"]
    secs = report["seconds"]
    out = [f"Adoption scan of {report['owner']} ({report['owner_kind']}), default branches only. "
           f"Took {int(secs // 60)} min {int(secs % 60)} s.",
           f"{len(report['repositories'])} repositories looked at: {len(rows)} active, {len(archived)} archived "
           "(archived ones are listed apart and not in the counts below).", "", "Active repositories by class:"]
    for c in CLASSES:
        out.append(f"  {c:<26}{report['counts'][c]:>6}")
    if report["counts"]["not scanned"]:
        out.append(f"  The {report['counts']['not scanned']} not scanned could not be read: they are NOT counted as "
                   '"no signal". Run the scan again later to fill them in.')
    early = report["counts"]["make-it, no build record"]
    if early:
        out += ["", f"Found through the decision file alone: {early} have make-it's decision file but no build record. "
                "A scan for the build record alone would miss them."]
    n = lambda key: sum(1 for r in scanned if r[key])
    out += ["", f"Seals present: {n('ma1_build_record')} have a build record, {n('ma2_ledger_entries')} a seal history, "
            f"{n('ma3_make_it_md')} a MAKE-IT.md. Present is not the same as intact: this scan does not check any "
            "seal. watermark.py verify does that, in each repository's merge gate."]
    skills, entries, bad, versions = {}, 0, 0, {}
    for r in scanned:
        entries += r["ma2_ledger_entries"]
        bad += r["ma2_unreadable"]
        for k, v in r["ma2_skills"].items():
            skills[k] = skills.get(k, 0) + v
        for v in r["ma2_versions"]:
            versions[v] = versions.get(v, 0) + 1
    if entries:
        out.append(f"make-it steps in the seal histories: {entries} entries"
                   + (f" ({bad} could not be read: counted, not broken down)" if bad else "") + ": "
                   + ", ".join(f"/{k} {v}" for k, v in sorted(skills.items(), key=lambda kv: -kv[1])) + ".")
        out.append("make-it releases seen in them: " + ", ".join(f"{k} ({v})" for k, v in sorted(versions.items())) + ".")
    if report["ci_pattern"] is not None:
        refs = {}
        for r in scanned:
            for ref in r["ma4_ci_refs"] or []:
                refs[ref] = refs.get(ref, 0) + 1
        callers = sum(1 for r in scanned if r["ma4_ci_refs"])
        out.append(f"Reusable CI ({clean(report['ci_pattern'], 100)}): {callers} repositories call it"
                   + (": by ref " + ", ".join(f"{k} ({v})" for k, v in sorted(refs.items())) if refs else "") + ".")
    ship = [r for r in scanned if r["ma5_ship_it_prs"]]
    latest = max((r["ma5_latest"] for r in ship if r["ma5_latest"]), default=None)
    out.append(f"/ship-it: {len(ship)} repositories have pull requests labelled {LABEL}, "
               f"{sum(r['ma5_ship_it_prs'] for r in ship)} requests in all" + (f", latest {latest}" if latest else "") + ".")
    if report["trailers"]:
        t = [r for r in scanned if r["ma7_trailer_commits"]]
        out.append(f"Claude co-author trailers: {len(t)} repositories, {sum(r['ma7_trailer_commits'] for r in t)} commits "
                   "found. A lower bound: GitHub's search returns at most 1,000 results.")
    for note in report["notes"]:
        out.append("Note: " + note)
    if archived:
        out += ["", "Archived (not counted): " + ", ".join(archived[:20])
                + (f", and {len(archived) - 20} more (see the files)" if len(archived) > 20 else "")]
    out += ["", f"Written: {os.path.join(path, 'adoption-scan.json')} and adoption-scan.csv beside it. They list the "
            "organisation's repository names: keep them internal."]
    return "\n".join(out)


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Sort an organisation's GitHub repositories by make-it use. It is read-only: it uses the gh CLI "
                    "you are signed in with, sends GraphQL queries and search GETs only, and never writes to GitHub.",
        epilog="Exit: 0 every repository scanned; 3 finished, but some repositories could not be scanned or a search "
               "failed (never counted as \"no signal\"); 2 could not scan (gh missing or signed out, no such "
               "organisation, a refused output folder, a bad argument).")
    who = ap.add_mutually_exclusive_group(required=True)
    who.add_argument("--org", help="the organisation to scan")
    who.add_argument("--user", help="a personal account to scan instead (its own repositories)")
    ap.add_argument("--limit", type=int, help="scan only the first N repositories, by name")
    ap.add_argument("--page-size", type=int, default=20, help="repositories per query, 1-100 (default 20)")
    ap.add_argument("--trailers", action="store_true", help='also search commits for "Co-Authored-By: Claude"')
    ap.add_argument("--ci-pattern", help="text a workflow's uses: line holds when it calls your reusable CI")
    ap.add_argument("--out", help="folder for the JSON and CSV (default: a new dated folder here)")
    a = ap.parse_args(argv)
    login = a.org or a.user
    if not LOGIN.fullmatch(login or ""):
        ap.error("the organisation or account name is not a valid GitHub login")
    if not 1 <= a.page_size <= 100:
        ap.error("--page-size must be between 1 and 100")
    if a.limit is not None and a.limit < 1:
        ap.error("--limit must be 1 or more")
    if a.ci_pattern is not None and not (0 < len(a.ci_pattern) <= 200 and a.ci_pattern.isprintable()):
        ap.error("--ci-pattern must be 1-200 printable characters")
    kind, qual = ("Organization", "org") if a.org else ("User", "user")
    started = time.monotonic()
    try:
        path = out_dir(a.out)
        repos = list_repos(login, kind, a.limit)
    except SystemExit as e:
        print(e.code, file=sys.stderr)
        return 2
    except GhFailed as e:
        tip = "" if "gh auth status" in str(e) else " Check gh's sign-in with: gh auth status"
        print(f"Could not list the repositories: {e}{tip}", file=sys.stderr)
        return 2
    notes, partial = set(), False
    hits, _ = search("search/code", f"{qual}:{login} filename:app-context.json", notes)
    if hits is None:
        partial, hits = True, {}
        notes.add("The code search failed: decision files outside .make-it/ and the root were not looked for.")
    trailers = None
    if a.trailers:
        trailers, total = search("search/commits", f"{qual}:{login} {TRAILER}", notes)
        if trailers is None:
            partial = True
            notes.add("The commit search failed: no trailer counts.")
        else:
            notes.add(f"Trailer commits: {total} found by GitHub; it returns at most 1,000, so counts are a lower bound.")
    valid = [r["name"] for r in repos if isinstance(r.get("name"), str) and REPO.fullmatch(r["name"])
             and r.get("nameWithOwner", "").lower() == f"{login}/{r['name']}".lower()]
    results = {}
    for i in range(0, len(valid), a.page_size):
        fetch(login, valid[i:i + a.page_size], a.ci_pattern is not None, results)
    rows = []
    for r in repos:
        name = clean(r.get("nameWithOwner"), 140)
        got = results.get(r.get("name"))
        s = None
        if isinstance(got, dict):
            key = r["nameWithOwner"].lower()
            t = len(trailers.get(key, [])) if trailers is not None else None
            s = signals(got, hits.get(key, []), t, a.ci_pattern)
        row = {"repository": name, "archived": bool(r.get("isArchived")), "fork": bool(r.get("isFork")),
               "class": classify(s),
               "not_scanned_reason": None if s else (got if isinstance(got, str) else "Its name is not one GitHub allows, so it was not queried.")}
        for k in ("ma0_decision_file", "ma0_where", "ma1_build_record", "ma1_readable", "ma1_version", "ma1_type",
                  "ma1_scaffold", "ma2_ledger_entries", "ma2_unreadable", "ma2_skills", "ma2_latest", "ma2_versions",
                  "ma3_make_it_md", "ma4_ci_refs", "ma5_ship_it_prs", "ma5_latest", "ma6_claude_files",
                  "ma7_trailer_commits"):
            row[k] = s[k] if s else None
        rows.append(row)
    counts = {c: sum(1 for r in rows if not r["archived"] and r["class"] == c) for c in CLASSES}
    report = {"owner": login, "owner_kind": "organisation" if a.org else "personal account",
              "scanned_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
              "seconds": round(time.monotonic() - started, 1), "ci_pattern": a.ci_pattern, "trailers": a.trailers,
              "counts": counts, "notes": sorted(notes), "repositories": rows}
    try:
        write_outputs(path, report)
    except OSError as e:
        print(f"Refused: could not write the results to {path} ({type(e).__name__}).", file=sys.stderr)
        return 2
    print(summary(report, path))
    return 3 if partial or counts["not scanned"] or any(r["archived"] and r["class"] == "not scanned" for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
