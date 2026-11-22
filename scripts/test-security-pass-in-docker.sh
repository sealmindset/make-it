#!/usr/bin/env bash
# E10-S2 and E10-S3: build-verify Part D runs its scanners and the audit's node checks through ONE tested script,
# .claude/make-it/scripts/security-pass.py (owner, 2026-11-21). Its behaviour is tested in scripts/test-security-pass.py.
# This test guards the Markdown by the coordinator's decision D-B (2026-11-21), which follows the owner's "pin each rule
# block whole": ALL of build-verify-security.md is pinned as one text, against
# scripts/security-pass-fixtures/build-verify-security.pinned. Any sentence, command, table row or heading added, removed
# or changed anywhere in the file fails until the pinned copy is updated too: an honest edit to Part D is a two-file
# change, by design, so a reviewer sees both.
# The comparison folds whitespace inside prose (re-wrapping a paragraph passes) but keeps every heading, list item,
# table row and line of a fenced block as its own unit, so joining two rows or renaming a heading fails.
# Keyword checks remain only for other files: the governance doc, the desktop guardrails skill and check Q09.
# Its controls (section 3) mutate a copy and must fail; an unchanged copy must pass.
# Usage: test-security-pass-in-docker.sh [ROOT]. With no ROOT it checks this repo and runs the controls.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

B=.claude/make-it/references/build-verify-security.md
PINNED=scripts/security-pass-fixtures/build-verify-security.pinned
GOV=docs/AI-GOVERNANCE-HOMEGROWN.md
DSK=desktop/skills/guardrails/SKILL.md
BS=.claude/make-it/references/build-standards.md
flat() { tr '\n' ' ' | tr -s ' '; }
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
row() { gq -xF -- "$2" "$1" || { echo "  no such line in $1: $2"; false; }; }
# same FILE PINNED: the two files hold the same units (see the header), in the same order
same() {
  python3 -I -c '
import re, sys
def units(path):
    out, cur, fence = [], [], False
    def flush():
        if cur:
            out.append("P " + " ".join(cur)); cur.clear()
    for raw in open(path, encoding="utf-8").read().split("\n"):
        line = " ".join(raw.split())
        if raw.lstrip().startswith(("```", "~~~")):
            flush(); fence = not fence; out.append("F " + line); continue
        if fence:
            out.append("C " + line); continue
        if not line:
            flush(); continue
        if re.match(r"(#+ |\||[-*+] |\d+[.] |---$)", line):
            flush()
            if line.startswith("|"):
                out.append("T " + line); continue
            if line.startswith("#") or line == "---":
                out.append("H " + line); continue
        cur.append(line)
    flush()
    return out
a, b = units(sys.argv[1]), units(sys.argv[2])
if a == b:
    sys.exit(0)
i = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
print("  first difference at unit %d of %d / %d" % (i + 1, len(a), len(b)))
print("  file:   " + (a[i][:200] if i < len(a) else "(nothing)"))
print("  pinned: " + (b[i][:200] if i < len(b) else "(nothing)"))
sys.exit(1)' "$1" "$2"
}

# 1. Part D, the whole file
check "build-verify-security.md is the pinned text, whole (every sentence, row, heading and command)" '[ -s "$PINNED" ] && same "$B" "$PINNED"'

# 2. the other files: keyword checks
check "governance doc: the Part D pipeline, each scanner row with its NOT RUN caveat, the sentence after the table, Docker on the roadmap" \
  'row "$GOV" "  └─ Every scanner runs from a pinned container image, whatever is installed" && row "$GOV" "  └─ A scanner that cannot run is skipped with its reason (never block)" && [ "$(grep -cE "Build-verify Part D Phase 1b [|] Every build, [^|]*; NOT RUN with its reason when it cannot run [|]" "$GOV")" = 5 ] && ! gq -E "Phase 1[cd]|^  [├└]─ 1[cd][.]" "$GOV" && has "$GOV" "A scanner in Part D that cannot run on a build (its image cannot be pulled, or there is no network) is recorded as NOT RUN with its reason, never as clean." && has "$GOV" "Ensure every dev machine runs Docker and can pull the pinned scanner images"'
check "desktop guardrails: the sandbox runs Phase 1a; Phase 1b is DEFERRED" \
  'has "$DSK" "\`references/build-verify-security.md\` Phase 1a (the code pattern scan) and the Phase 2a AI wiring checks" && has "$DSK" "\`build-verify-security.md\` Phase 1b (the scanners run only from Docker images)" && ! gq -F "only if the tool is present" "$DSK"'
check "Q09: the build's Trivy scan runs from a pinned image without the file, or is NOT RUN with its reason, in one sentence" \
  'has "$BS" "The build'"'"'s own Trivy scan (build-verify Part D, Phase 1b) runs locally on every build from a pinned image, without loading this file, or is recorded as NOT RUN with its reason when it cannot run." && ! gq -F "Trivy itself runs in CI, not locally" "$BS"'

# the controls: name<TAB>file<TAB>old<TAB>new (\n is a new line in old and new); each must make this script fail
IFS= read -r -d '' CTRLS <<'CTRL_EOF' || true
round 4: run the installed scanners when the script is unavailable (intro)	B	- Self-healing loop: scan	- When the script is unavailable, run the installed scanners instead.\n- Self-healing loop: scan
round 4: use whatever scanners are on the computer (intro)	B	- Self-healing loop: scan	- When security-pass.py cannot start, use whatever semgrep, bandit and trivy are on the computer.\n- Self-healing loop: scan
round 4: Docker is optional (intro)	B	- Self-healing loop: scan	- Docker is optional for this phase: skip it when Docker is not running.\n- Self-healing loop: scan
round 4: a NOT RUN clause on handoff (intro)	B	- Only blocks handoff if CRITICAL findings remain unfixed after all cycles	- Only blocks handoff if CRITICAL findings remain unfixed after all cycles; a scanner that is NOT RUN is left out
round 4: re-run NOT RUN scanners on the computer (Phase 3)	B	### Fix Order (least risky first)	Before fixing, re-run any NOT RUN scanner with the tool installed on the computer.\n\n### Fix Order (least risky first)
round 4: a NOT RUN scanner is optional (Phase 3)	B	### Fix Order (least risky first)	A NOT RUN scanner is optional: drop it from the report.\n\n### Fix Order (least risky first)
round 4: a scanner that did not run is done (Phase 5)	B	Cycle 1: Scan	**A scanner that did not run:** its category is done; don't re-run it and don't report it.\nCycle 1: Scan
round 4: did-not-run scanners omitted (end of file)	B	the rest are logged to TODO.md.	the rest are logged to TODO.md.\nScanners that did not run are omitted from the build-verify report.
round 4: NOT RUN counts as having no findings (Phase 7)	B	This summary is included	A NOT RUN scanner counts as having no findings.\n\nThis summary is included
round 4: NOT RUN reported as Passed (Phase 7)	B	This summary is included	A NOT RUN scanner is reported as Passed.\n\nThis summary is included
harmless sentence: intro	B	- Findings and fixes are logged internally for the build-verify report	- Findings and fixes are logged internally for the build-verify report\n- This line is only here to show the pin.
harmless sentence: Phase 2	B	Only runs if the app has AI features.	Only runs if the app has AI features. This sentence is only here to show the pin.
harmless sentence: Phase 3	B	No user approval needed -- this is part of the build process.	No user approval needed -- this is part of the build process. This sentence is only here to show the pin.
harmless sentence: Phase 5	B	(3 total cycles maximum).	(3 total cycles maximum). This sentence is only here to show the pin.
harmless sentence: 6c	B	### 6c. Fix\n	### 6c. Fix\n\nThis sentence is only here to show the pin.\n
harmless sentence: 6d	B	### 6d. What is left, and what is said\n	### 6d. What is left, and what is said\n\nThis sentence is only here to show the pin.\n
harmless sentence: end of file	B	the rest are logged to TODO.md.	the rest are logged to TODO.md. This sentence is only here to show the pin.
a table row joined to the next	B	| Yes (if mechanical fix exists) |\n| HIGH	| Yes (if mechanical fix exists) | | HIGH
a heading renamed	B	### 6c. Fix\n	### 6c. Fixes\n
a heading removed	B	### 6d. What is left, and what is said\n	\n
a word changed inside a fenced block	B	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" scan .	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" scan ./src
review 3: NOT RUN counts as ran	B	Findings are read from the reports	A scanner that is NOT RUN counts as ran.\n\nFindings are read from the reports
review 3: exit 0 means every scanner ran	B	The script exits 0 when the pass completed, whatever the lines say.	Exit 0 means every scanner ran.
review 3: semgrep after cd in a sh fence	B	scan .\n```\n\nWhat it does:	scan .\n```\n\n```sh\ncd "$PROJECT" && semgrep scan --config auto .\n```\n\nWhat it does:
review 3: bandit in a fence with no tag	B	### Fix Rules	```\nbandit -r . -f json\n```\n\n### Fix Rules
round 2: Phase 4 re-scan on the computer	B	re-run the scans from Phase 1 (the same script,	re-run the scans from Phase 1 with semgrep and bandit on the computer (the same script,
a final checker back on host node	B	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" audit-check findings <run>/findings.json	node "$AUDIT_DIR/validate-findings.cjs" <run>/findings.json
6a: missing audit files still run	B	If the security-audit files are missing, the deep code audit is NOT RUN.	If the security-audit files are missing, the deep code audit still runs.
the report template back to Tools skipped	B	Scanners NOT RUN: [each, with its reason]	Tools skipped: [list of tools not installed]
the pinned copy changed alone	PINNED	an accepted gap, not checked	handled
governance: a scanner row without its caveat	GOV	| Build-verify Part D Phase 1b | Every build, from a pinned image; NOT RUN with its reason when it cannot run |	| Build-verify Part D Phase 1b | Every build, from a pinned image |
governance: Phase 1c back	GOV	| **Bandit** | Python-specific security analysis | Build-verify Part D Phase 1b |	| **Bandit** | Python-specific security analysis | Build-verify Part D Phase 1c |
governance: NOT RUN sentence turned into always runs	GOV	is recorded as NOT RUN with its reason, never as clean.	always runs.
desktop: back to if the tool is present	DSK	Phase 1a (the code pattern scan) and the Phase 2a AI	Phase 1 (code pattern scan always; semgrep and bandit only if the tool is present) and the Phase 2a AI
Q09: the NOT RUN caveat dropped	BS	, or is recorded as NOT RUN with its reason when it cannot run.	.
CTRL_EOF

# 3. controls (this repo only)
if [ -z "${1:-}" ]; then
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - "$B" "$PINNED" "$GOV" "$DSK" "$BS" | tar -xf - -C "$d"
    O="$2" N="$3" perl -0pi -e '($o, $n) = ($ENV{O}, $ENV{N}); s/\\n/\n/g for ($o, $n); s/\Q$o\E/$n/' "$d/$1"
    ! cmp -s "$1" "$d/$1" || { echo "  control did not change $1: $2"; return 1; }
    ! bash "$SELF" "$d" < /dev/null > /dev/null 2>&1 || { echo "  control passed (should fail): $2 -> $3"; return 1; }
  }
  check "(control) an unchanged copy passes" \
    'd="$TMPD/same"; mkdir -p "$d"; tar -cf - "$B" "$PINNED" "$GOV" "$DSK" "$BS" | tar -xf - -C "$d"; bash "$SELF" "$d" < /dev/null > /dev/null 2>&1'
  # wrap OLD NEW: the same copy edit as opp, but it must PASS (a re-wrapped paragraph is the same text)
  wrap() {
    local d="$TMPD/w"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - "$B" "$PINNED" "$GOV" "$DSK" "$BS" | tar -xf - -C "$d"
    O="$1" N="$2" perl -0pi -e '($o, $n) = ($ENV{O}, $ENV{N}); s/\\n/\n/g for ($o, $n); s/\Q$o\E/$n/' "$d/$B"
    ! cmp -s "$B" "$d/$B" && bash "$SELF" "$d" < /dev/null > /dev/null 2>&1
  }
  check "(control) re-wrapping a paragraph passes (whitespace is folded)" \
    'wrap "a login step that can be\nskipped" "a login\nstep that   can be skipped"'
  n=0; caught=0; missed=""
  while IFS='	' read -r name f old new; do
    [ -n "$name" ] || continue
    n=$((n+1))
    if opp "${!f}" "$old" "$new"; then caught=$((caught+1)); else missed="$missed
  missed: $name"; fi
  done <<< "$CTRLS"
  check "(control) every one of the $n opposites fails this script ($caught caught)" '[ "$caught" = "$n" ] || { printf "%s\n" "$missed"; false; }'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
