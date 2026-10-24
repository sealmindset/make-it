#!/usr/bin/env bash
# E02-S19: catch-up (S10-S13) keeps a CLAUDE.md's intro text together with its title.
# Contract these checks pin (build-standards.md S10-S13, as an agent reads them):
#   - S13 puts the canary directly before the file's first `## ` heading (at the end of the file if it has none),
#     so a `/init`-style intro under the `#` title stays with the title.
#   - The end layout is the same in every order -- S13 first or last, S10-S12 in any order: title, intro text,
#     canary, muddy-water, keep-the-human, `## Learnings`, then the file's other sections in their old order.
#   - A second run changes nothing.
# How the checks are modelled: the script reads each check's placement wording from build-standards.md and maps
# it to one insertion rule; wording it doesn't recognise fails, so a reworded check is re-modelled, never assumed.
# The S13-last orders model an agent that runs S10-S12 before S13 although S13 says to run it first: while the
# file has no canary yet, "the canary's heading" is read as the spot S13's wording gives the canary.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
# The whole run's stderr is caught; the last check fails on any of it (a Python error reads as a pass otherwise).
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT
fail=0

python3 - .claude/make-it/references/build-standards.md .claude/commands/make-it.md \
  .claude/make-it/references/muddy-water.md .claude/make-it/references/human-in-the-loop.md <<'PY' || fail=1
import itertools, re, sys
bs_path, makeit_path, muddy_path, human_path = sys.argv[1:5]
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        if why: print("  " + why)

bs = open(bs_path, encoding="utf-8").read().splitlines()
def para(cid):
    hits = [l for l in bs if l.startswith(f"**{cid}** ")]
    return hits[0] if len(hits) == 1 else ""
S10, S11, S12, S13 = (para(c) for c in ("S10", "S11", "S12", "S13"))

def copy_block(path):  # the fenced block under "## Section -- copy exactly"
    L = open(path, encoding="utf-8").read().splitlines()
    i = L.index("## Section -- copy exactly")
    a = L.index("```markdown", i) + 1
    return L[a:L.index("```", a)]
MUDDY, HUMAN = copy_block(muddy_path), copy_block(human_path)
mk = open(makeit_path, encoding="utf-8").read().splitlines()
a = mk.index("      ## Canary — instruction-drift check (highest priority)")
b = mk.index("      [MUDDY_WATER_SECTION]", a)
CANARY = [l[6:] for l in mk[a:b]]
while CANARY and not CANARY[-1]: CANARY.pop()
CANARY = [l.replace("[BUILDER_NAME]", "Sam") for l in CANARY]
LEARN = ["## Learnings", "", "@LEARNINGS.md"]
CH, MH, HH = CANARY[0], MUDDY[0], HUMAN[0]

# --- read the placement wording ---
m = re.search(r"`CLAUDE\.md` without the canary → (.*?), or move it there if it sits lower down", S13)
clause = m.group(1) if m else ""
if clause == "insert that section right after the file's `#` title (at the very top if it has none)":
    S13_RULE = "after-title"
elif ("directly before the file's first `## ` heading" in clause
      and "(at the end of the file if it has no `## ` heading)" in clause):
    S13_RULE = "before-first-h2"
else:
    S13_RULE = None
check("S13's placement wording is one the model knows", S13_RULE is not None, f"S13 clause: {clause!r}")
NEXT = "the next `## ` heading after the canary's heading"
known = (NEXT in S11 and "(at the end of the file if there is none)" in S11
         and NEXT + ", stepping past the muddy-water heading if it comes first," in S12
         and "That heading is the next `## ` heading after the canary's heading, stepping past the muddy-water "
             "heading if it comes first and then past the keep-the-human heading if it comes next." in S10
         and "A block that S10-S12 move takes the blank line before it along" in S13)
check("S10-S12's placement wording (next heading after the canary's) is the one the model knows", known)
if S13_RULE is None or not known:
    sys.exit(1)

# --- the four checks, as modelled ---
def heads(L): return [i for i, l in enumerate(L) if l.startswith("## ")]
def remove(L, head):  # every copy of the section, and the blank line before it
    while head in L:
        i = L.index(head)
        j = next((k for k in heads(L) if k > i), len(L))
        while j > i + 1 and not L[j - 1]: j -= 1
        if i > 0 and not L[i - 1]: i -= 1
        L = L[:i] + L[j:]
    return L
def insert_before(L, i, block):
    if i is None:  # the end of the file
        while L and not L[-1]: L = L[:-1]
        return L + ([""] if L else []) + block
    return L[:i] + block + [""] + L[i:]
def s13_spot(L):
    if S13_RULE == "after-title":
        t = next((k for k, l in enumerate(L) if l.startswith("# ")), None)
        return 0 if t is None else t + 1
    h = heads(L)
    return h[0] if h else None
def anchor(L, skip):  # the next ## heading after the canary's, stepping past `skip` in order
    if CH in L: start = L.index(CH) + 1
    else:
        sp = s13_spot(L); start = len(L) if sp is None else sp
    i = next((k for k in heads(L) if k >= start), None)
    for s in skip:
        if i is not None and L[i] == s: i = next((k for k in heads(L) if k > i), None)
    return i
def s13(L):
    h = heads(L)
    if h and L[h[0]] == CH and L.count(CH) == 1: return L
    L = remove(L, CH)
    sp = s13_spot(L)
    if S13_RULE == "after-title" and sp:  # right after the title line
        return L[:sp] + [""] + CANARY + L[sp:]
    if S13_RULE == "after-title":
        return CANARY + [""] + L
    return insert_before(L, sp, CANARY)
def section_check(head, block, skip):
    def run(L):
        i = anchor(L, skip)
        if i is not None and L[i] == head and L.count(head) == 1: return L
        L = remove(L, head)
        return insert_before(L, anchor(L, skip), block)
    return run
s11 = section_check(MH, MUDDY, [])
s12 = section_check(HH, HUMAN, [MH])
def s10(L):
    i = anchor(L, [MH, HH])
    if i is not None and L[i:i + 3] == LEARN and L.count("@LEARNINGS.md") == 1 and L.count("## Learnings") == 1: return L
    L = [l for l in remove(L, "## Learnings") if l != "@LEARNINGS.md"]
    return insert_before(L, anchor(L, [MH, HH]), LEARN)
CHECKS = {"S10": s10, "S11": s11, "S12": s12, "S13": s13}
ORDERS = [("S13",) + p for p in itertools.permutations(("S10", "S11", "S12"))] + \
         [p + ("S13",) for p in itertools.permutations(("S10", "S11", "S12"))]
def run(L, order):
    for c in order: L = CHECKS[c](L)
    return L
def first_diff(got, want):
    for k, (g, w) in enumerate(zip(got, want)):
        if g != w: return f"line {k + 1}: got {g[:70]!r}, want {w[:70]!r}"
    return f"length: got {len(got)} lines, want {len(want)}"

# --- fixtures: start file, and the layout every order must end in ---
TITLE = ["# CLAUDE.md", ""]
INTRO = ["This file provides guidance to Claude Code (claude.ai/code) when working with code in this",
         "repository.", ""]
OLD = ["## Commands", "", "- `npm test` runs the tests.", "", "## Architecture", "",
       "A Next.js frontend over a FastAPI backend."]
NEW = CANARY + [""] + MUDDY + [""] + HUMAN + [""] + LEARN
OLD_CANARY = OLD[:4] + CANARY + [""] + OLD[4:]  # an older catch-up left the canary between two old sections
LAYOUT = "title, intro, canary, muddy-water, keep-the-human, Learnings, then ## Commands and ## Architecture"
FIXTURES = [
    ("a /init-style file (title, 2-line intro, ## Commands, ## Architecture)", TITLE + INTRO + OLD,
     TITLE + INTRO + NEW + [""] + OLD, LAYOUT, ORDERS),
    ("a file with no intro under its title", TITLE + OLD, TITLE + NEW + [""] + OLD,
     "title, canary, muddy-water, keep-the-human, Learnings, then ## Commands and ## Architecture", ORDERS),
    ("a title and intro with no ## heading", TITLE + INTRO[:2], TITLE + INTRO + NEW,
     "title, intro, canary, muddy-water, keep-the-human, Learnings", ORDERS),
    ("a /init-style file whose canary sits lower down", TITLE + INTRO + OLD_CANARY,
     TITLE + INTRO + NEW + [""] + OLD, LAYOUT, ORDERS[:6]),  # a canary already there anchors S10-S12: S13 runs first
]

L = s13(TITLE + INTRO + OLD)
check("S13 alone on a /init-style file: title, intro, then the canary before ## Commands",
      L == TITLE + INTRO + CANARY + [""] + OLD, first_diff(L, TITLE + INTRO + CANARY + [""] + OLD))
for name, start, want, layout, orders in FIXTURES:
    for order in orders:
        got = run(start, order)
        check(f"{name}, order {'-'.join(order)}: {layout}", got == want, first_diff(got, want))
        again = run(got, order)
        check(f"{name}, order {'-'.join(order)}: a second run changes nothing", again == got, first_diff(again, got))
sys.exit(1 if failed else 0)
PY

if [ -s "$ERRF" ]; then echo "FAIL the whole run wrote nothing to stderr"; sed "s/^/  stderr: /" "$ERRF"; fail=1
else echo "ok   the whole run wrote nothing to stderr"; fi
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
