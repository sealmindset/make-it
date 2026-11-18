"""Fail if an attack path built from small findings claims more than its evidence.

  python3 -I check_paths.py <project dir>

Reads data/derived/paths.json: {"findings": [...], "paths": [...]} (references/finding-chains.md).
Rule 1: every finding points at a non-empty evidence file under data/raw/ or data/curated/ in this project.
        A finding that came from a tool or a dropped report ("origin": "reported") is only a lead until
        "confirmed_by" names a second evidence file from this run.
Rule 2: a "path" has two or more links, each a different confirmed finding with what it gives the attacker;
        anything with an unconfirmed link must be a "lead".
Rule 3: status is "not exercised" unless a person's test record under data/raw/tests/ is named.
Rule 4: every path names where it starts, what it reaches, the cheapest break, and a test plan whose steps
        each carry action, expect, signal, detection and stop.
Rule 5: briefing.md, technical.md and test-plan.md never mention a path without its status on some line.
"""
import json
import os
import re
import sys

STEP = ("action", "expect", "signal", "detection", "stop")
TESTED = ("confirmed by test", "disproved by test")


def evidence(root, rel, under=("data/raw", "data/curated")):
    """The file exists, is not empty, and really is inside one of this project's evidence folders."""
    if not isinstance(rel, str) or not rel or os.path.isabs(rel):
        return False
    real = os.path.realpath(os.path.join(root, rel))
    inside = any(real.startswith(os.path.realpath(os.path.join(root, u)) + os.sep) for u in under)
    return inside and os.path.isfile(real) and os.path.getsize(real) > 0


def check(root):
    root, fail = os.path.realpath(root), []
    with open(os.path.join(root, "data/derived/paths.json"), encoding="utf-8") as f:
        doc = json.load(f)
    confirmed = {}
    for fi in doc.get("findings", []):
        fid = fi.get("id")
        if not fid or fid in confirmed:
            fail.append(f"finding id missing or repeated: {fid!r}")
            continue
        confirmed[fid] = False
        if not evidence(root, fi.get("evidence")):
            fail.append(f"{fid}: evidence is not a non-empty file under data/raw or data/curated")
        elif fi.get("origin") == "collected":
            confirmed[fid] = True
        elif fi.get("origin") == "reported":
            by = fi.get("confirmed_by")
            if by and (by == fi["evidence"] or not evidence(root, by, ("data/raw",))):
                fail.append(f"{fid}: confirmed_by must be a second evidence file under data/raw")
            confirmed[fid] = bool(by)  # a bad confirmed_by already failed the run above
        else:
            fail.append(f"{fid}: origin must be 'collected' or 'reported'")
    for p in doc.get("paths", []):
        pid, links = p.get("id") or "(no id)", p.get("links") or []
        used = [l.get("finding") for l in links]
        if p.get("kind") not in ("path", "lead"):
            fail.append(f"{pid}: kind must be 'path' or 'lead'")
        if len(links) < 2 or len(set(used)) != len(used):
            fail.append(f"{pid}: needs two or more links, each a different finding")
        for l in links:
            if l.get("finding") not in confirmed:
                fail.append(f"{pid}: link names a finding that is not listed: {l.get('finding')!r}")
            elif p.get("kind") == "path" and not confirmed[l["finding"]]:
                fail.append(f"{pid}: {l['finding']} is not confirmed by this run, so this is a lead, not a path")
            if not l.get("gain"):
                fail.append(f"{pid}: link {l.get('finding')!r} does not say what it gives the attacker")
        status = p.get("status")
        if status in TESTED:
            if not evidence(root, p.get("test_record"), ("data/raw/tests",)):
                fail.append(f"{pid}: '{status}' needs a test record under data/raw/tests")
        elif status != "not exercised":
            fail.append(f"{pid}: status must be 'not exercised' (or a tested status with its record)")
        for k in ("start", "objective", "break"):
            if not p.get(k):
                fail.append(f"{pid}: missing {k}")
        plan = p.get("test_plan") or []
        if not plan or any(not s.get(k) for s in plan for k in STEP):
            fail.append(f"{pid}: every test-plan step needs {', '.join(STEP)}")
        for name in ("briefing.md", "technical.md", "test-plan.md"):
            path = os.path.join(root, name)
            if not os.path.isfile(path) or not status:
                continue
            lines = [ln for ln in open(path, encoding="utf-8") if re.search(rf"\b{re.escape(pid)}\b", ln)]
            if lines and not any(status in ln for ln in lines):
                fail.append(f"{pid}: {name} mentions it without its status ('{status}')")
    return fail


if __name__ == "__main__":
    problems = check(sys.argv[1])
    for line in problems:
        print("FAIL", line)
    if problems:
        sys.exit(1)
    print("check_paths: OK")
