#!/usr/bin/env bash
# /deadcode-it: dead code is proven unused, graded, removed in verified batches, and logged.
# Contract these checks pin:
#   - The skill loads deadcode.md, and deadcode.md defines the keep-list, every evidence tool, the three
#     grades, the batch-verify-rollback cadence, the CAUTION ask and the deletion log.
#   - The skill never deletes DANGER or keep-list items, never on a red baseline, never pushes.
#   - Build-standards Q14 (lint-level FIX) and Q15 (report-only WARN) exist, and make-it, resume-it
#     and retrofit-it reach them (the owner's 2026-10-31 call: build-verify fixes unused imports only).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }   # reads all its input: no SIGPIPE under pipefail
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

CMD=.claude/commands/deadcode-it.md
REF=.claude/make-it/references/deadcode.md
BS=.claude/make-it/references/build-standards.md
tools() { local t; for t in knip depcheck ts-prune tsc eslint ruff vulture deptry; do gq -E "^\| [^|]+ \| $t \|" "$1" || return 1; done; }
grades() { local g; for g in SAFE CAUTION DANGER; do gq -E "^\| \*\*$g\*\* \|" "$1" || return 1; done; }

check "the skill loads deadcode.md"            gq -F "@~/.claude/make-it/references/deadcode.md" "$CMD"
check "every evidence tool is listed"          tools "$REF"
check "a tool not run is never 'no findings'"  gq -F 'never as "no findings"' "$REF"
check "all three grades are defined"           grades "$REF"
check "scaffold-owned paths are kept"          gq -F "~/.claude/make-it/scaffolds/fastapi-nextjs/" "$REF"
check "user-kept items are never re-asked"     gq -F "Never ask about it again" "$REF"
check "red baseline stops the run"             gq -F "Nothing is deleted on a red baseline" "$REF"
check "a red batch is rolled back and split"   gq -F "split the batch in halves" "$REF"
check "no weakening a check to pass"           gq -F "Never make a check pass by weakening it" "$REF"
check "the log is docs/DELETION_LOG.md"        gq -F "## 7. Deletion log -- \`docs/DELETION_LOG.md\`" "$REF"
check "the skill never deletes DANGER"         gq -F "Delete anything graded DANGER" "$CMD"
check "the skill never pushes"                 gq -F "Push, merge, or open a PR" "$CMD"
check "Q14 is a FIX limited to imports"        gq -E '^\*\*Q14\*\* \[Tier 0\] \[FIX\].*only the unused \*\*import\*\* specifiers' "$BS"
check "Q15 is a report-only WARN"              gq -E '^\*\*Q15\*\* \[Tier 0\] \[WARN\].*\*\*report-only\*\*' "$BS"
check "make-it build-verify runs Q01-Q15"      gq -F "**Q01-Q15**" .claude/commands/make-it.md
check "resume-it scans Q01-Q15"                gq -F "**Code Quality (Q01-Q15):**" .claude/commands/resume-it.md
check "resume-it suggests /deadcode-it"        gq -F "(routes to /deadcode-it)" .claude/commands/resume-it.md
check "retrofit-it Discovery counts dead code" gq -F "Evidence pass, report-only" .claude/commands/retrofit-it.md
check "install.sh describes it"                gq -F "deadcode-it) desc=" install.sh
# controls: a dropped tool or grade must fail
tools <(grep -v "| vulture |" "$REF") && bad "control: missing tool passed" || ok "control: missing tool fails tools"
grades <(sed 's/\*\*DANGER\*\*/DANGER/' "$REF") && bad "control: missing grade passed" || ok "control: missing grade fails grades"

[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
