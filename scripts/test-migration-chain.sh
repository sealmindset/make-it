#!/usr/bin/env bash
# E02-S23: a broken Alembic chain fails build-verify Part A (and the /resume-it catch-up), not the backend container
# when it runs `alembic upgrade head`.
# Contract these checks pin (build-standards.md D06, as an agent reads it):
#   - D06 is the check entry right after D05: [Tier 1] [BLOCK], and it names the three breaks -- two files declaring
#     the same `revision`, a `down_revision` naming a revision no file declares, and not exactly one head.
#   - The static read of versions/ is required and decides; `alembic heads` is an extra that never clears a failure.
#   - Applied to fixtures: the shipped scaffold passes; a duplicate 002, a second head and a dangling down_revision
#     fail, each for its own reason; a merge revision joining two heads passes. Each fixture's plain opposite (one
#     value changed) gets the other verdict, so every verdict comes from the one value seeded.
#   - Every list that names the D range (D's skip line, make-it Part A, retrofit-it verify, resume-it catch-up)
#     reaches the last D check, and the catch-up's Database line asks for the one head.
# How the check is modelled: each of the three rules is on only while D06 carries its wording, so a check that is
# missing or reworded turns its fixtures red instead of being assumed.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
# The whole run's stderr is caught; the last check fails on any of it (a Python error reads as a pass otherwise).
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT
fail=0

python3 - .claude/make-it/references/build-standards.md \
  .claude/make-it/scaffolds/fastapi-nextjs/backend/alembic/versions \
  .claude/commands/make-it.md .claude/commands/retrofit-it.md .claude/commands/resume-it.md <<'PY' || fail=1
import ast, os, re, sys
bs_path, vdir, *lists = sys.argv[1:]
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        if why: print("  " + why)

# --- the wording ---
bs = open(bs_path, encoding="utf-8").read().splitlines()
entries = [(i, m.group(1)) for i, l in enumerate(bs) if (m := re.match(r"\*\*([A-Z]+\d+[a-z]?)\*\* ", l))]
ids = [c for _, c in entries]
check("D06 is defined once", ids.count("D06") == 1, f"D06 count: {ids.count('D06')}")
check("D06 is the check entry right after D05", "D05" in ids and ids[ids.index("D05") + 1:][:1] == ["D06"])
D06 = next((bs[i] for i, c in entries if c == "D06"), "")
check("D06 is [Tier 1] [BLOCK]", D06.startswith("**D06** [Tier 1] [BLOCK] **"), f"D06 starts: {D06[:40]!r}")
RULES = {
    "duplicate": "two files declare the same `revision`",
    "dangling": "a `down_revision` names a revision no file declares",
    "heads": "exactly one head, and a head is a revision that no file's `down_revision` names",
}
for k, phrase in RULES.items():
    check(f"D06 names the {k} break: {phrase!r}", phrase in D06)
ON = {k: phrase in D06 for k, phrase in RULES.items()}
check("D06 reads `down_revision` as a string, `None`, or a tuple for a merge",
      "a string, `None`, or a tuple of strings for a merge revision" in D06)
check("D06: the static read is required and decides; `alembic heads` never clears a static failure",
      "the static read is required and decides" in D06
      and "a clean `alembic heads` never clears a static failure" in D06)

# --- the rule, as worded ---
def values(src):
    got = {}
    for n in ast.parse(src).body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
            name, val = n.targets[0].id, n.value
        elif isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name) and n.value is not None:
            name, val = n.target.id, n.value
        else:
            continue
        if name in ("revision", "down_revision"):
            got[name] = ast.literal_eval(val)
    return got.get("revision"), got.get("down_revision")
def breaks(files):  # {file name: source} -> the breaks found, by kind
    revs, downs = [], []
    for name, src in files.items():
        if name == "__init__.py": continue
        rev, down = values(src)
        revs.append(rev)
        downs += [] if down is None else [down] if isinstance(down, str) else list(down)
    found = {}
    dup = sorted({r for r in revs if revs.count(r) > 1})
    if ON["duplicate"] and dup: found["duplicate"] = dup
    dangling = sorted(set(downs) - set(revs))
    if ON["dangling"] and dangling: found["dangling"] = dangling
    heads = sorted(set(revs) - set(downs))
    if ON["heads"] and len(heads) != 1: found["heads"] = heads
    return found

# --- fixtures: (name, files, the break it must show or None to pass) ---
SCAFFOLD = {n: open(os.path.join(vdir, n), encoding="utf-8").read() for n in sorted(os.listdir(vdir)) if n.endswith(".py")}
check("the scaffold ships its chain 001 -> 002 -> 003", [values(s) for s in SCAFFOLD.values()]
      == [("001", None), ("002", "001"), ("003", "002")], f"scaffold: {[values(s) for s in SCAFFOLD.values()]}")
def mig(rev, down):
    return f'"""fixture"""\nrevision: str = {rev!r}\ndown_revision = {down!r}\n\n\ndef upgrade() -> None:\n    pass\n'
def plus(extra): return {**SCAFFOLD, **extra}
CASES = [  # each fixture, then its plain opposite
    ("the shipped scaffold", SCAFFOLD, None),
    ("its opposite: the scaffold's 003 on 001 (002 and 003 both heads)", plus({"003_prompt_management.py": mig("003", "001")}), "heads"),
    ("a seeded duplicate 002 (same revision id, on 001)", plus({"002_domain_schema.py": mig("002", "001")}), "duplicate"),
    ("its opposite: that file renumbered 004, on 003 (the fix D06 gives)", plus({"004_domain_schema.py": mig("004", "003")}), None),
    ("a second head (004 and 005 both on 003)", plus({"004_domain_schema.py": mig("004", "003"), "005_seed_data.py": mig("005", "003")}), "heads"),
    ("its opposite: 005 on 004", plus({"004_domain_schema.py": mig("004", "003"), "005_seed_data.py": mig("005", "004")}), None),
    ("a down_revision naming nothing (004 on '003_prompt_management')", plus({"004_domain_schema.py": mig("004", "003_prompt_management")}), "dangling"),
    ("its opposite: 004 on '003'", plus({"004_domain_schema.py": mig("004", "003")}), None),
    ("a merge revision (006 on ('004', '005'), joining two heads)", plus({"004_domain_schema.py": mig("004", "003"), "005_seed_data.py": mig("005", "003"), "006_merge_heads.py": mig("006", ("004", "005"))}), None),
    ("its opposite: no merge revision", plus({"004_domain_schema.py": mig("004", "003"), "005_seed_data.py": mig("005", "003")}), "heads"),
]
for name, files, want in CASES:
    found = breaks(files)
    if want is None:
        check(f"PASS {name}", not found, f"found: {found}")
    else:
        check(f"FAIL {name}, as a {want} break", want in found, f"found: {found}")

# --- the lists that name the D range ---
last = max(int(c[1:]) for c in ids if re.fullmatch(r"D\d+", c))
for path in [bs_path] + lists:
    ranges = re.findall(r"\bD01-D(\d+)", open(path, encoding="utf-8").read())
    check(f"{path} names the D range up to D{last:02d}", ranges and all(int(r) == last for r in ranges),
          f"ranges: {['D01-D' + r for r in ranges]}")
resume = open(lists[2], encoding="utf-8").read()
db = next((l for l in resume.splitlines() if "**Database (D01-" in l), "")
check("the /resume-it catch-up's Database line asks for one Alembic head (D06)", "one Alembic head" in db and "D06" in db,
      f"line: {db.strip()!r}")
sys.exit(1 if failed else 0)
PY

if [ -s "$ERRF" ]; then echo "FAIL the whole run wrote nothing to stderr"; sed "s/^/  stderr: /" "$ERRF"; fail=1
else echo "ok   the whole run wrote nothing to stderr"; fi
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
