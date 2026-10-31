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
check "vulture alone can't block a ruff/tsc import"   gq -F "vulture's confidence doesn't matter then" "$REF"
check "proven-in-use items are dropped, not graded"  gq -F "**In use (not graded).**" "$REF"
check "manifests are judged per dependency"     gq -F "judged per entry, not by path" "$REF"
check "eslint only runs with an eslint config"  gq -F 'not run: no eslint config' "$REF"
check "CI build/test commands are verified"   gq -F "plus the build/test commands CI runs" "$REF"
check "audits aren't part of the baseline"     gq -F "a newly published advisory isn't a broken app" "$REF"
check "dep batches verify on a fresh install"   gq -F "verified on a fresh install from the manifest" "$REF"
check "a one-item ask still has two options"    gq -F '"Remove it" / "Keep it"' "$REF"
check "log hashes are filled in at the end"     gq -F "replaces those with the short hashes" "$REF"
check "deptry sees the project's packages"      gq -F "uvx --with-requirements requirements.txt deptry" "$REF"
check "deps are removed by hand, not npm uninstall" gq -F '`npm uninstall` reformats `package.json`' "$REF"
check "side-effect imports are never SAFE"     gq -F "**Imported for its effect**" "$REF"
check "an export used in its own file is kept"  gq -F "**Used in its own file**" "$REF"
check "Q14 never runs ruff --fix"               gq -E '^\*\*Q14\*\*.*never `--fix`' "$BS"
check "Q14 eslint fixes directives only"        gq -F -- "--fix --fix-type directive" "$BS"
check "untracked files don't block the run"     gq -F -- "--untracked-files=no" "$CMD"
check "no tool ran is not 'nothing to clean'"   gq -F "I couldn't check your code" "$CMD"
check "no push, clean or hard reset anywhere"   bash -c '! grep -nE "git push|gh pr create|git clean|reset --hard" "$1" "$2"' _ "$CMD" "$REF"
saferow() { [ "$(grep -E '^\| \*\*SAFE\*\* \|' "$1" | grep -ciE 'whole file|page|route')" = 0 ]; }
check "the SAFE row never covers files/routes"  saferow "$REF"
check "a call on the right of a local is kept"  gq -F "delete only the binding and keep the expression" "$REF"
check "framework-read exports are DANGER"      gq -F '`generateStaticParams`' "$REF"
check "one weak tool alone is never SAFE"      gq -F "ts-prune alone or vulture alone (below 100%) is never" "$REF"
check "rollback covers the whole repo"         gq -F 'git restore --staged --worktree -- :/' "$REF"
check "a rolled-back dep batch reinstalls"     gq -F "reinstalls from the restored" "$REF"
check "scaffold keep-list only in make-it apps" gq -F 'only when `.make-it/app-context.json` exists' "$REF"
check "a one-item ask is single-select"        gq -F '(`multiSelect: false`) with the options' "$REF"
check "cleanup branch made from HEAD after a green baseline" gq -F 'Green → create the cleanup branch from HEAD' "$CMD"
check "no branch exists before the baseline"   gq -F "No branch yet -- it is made only after the baseline is green." "$CMD"
check "an old cleanup branch is never continued" gq -F "There's an earlier cleanup still waiting" "$CMD"
check "the report names the starting branch"   gq -F '`<starting branch>`' "$CMD"
check "resume-it doesn't re-run Q15 tools each time" gq -F "re-run the \`deadcode.md\` §2 tools only when there is none" .claude/commands/resume-it.md
check "retrofit evidence pass is best effort"  gq -F "Best effort: an app that won't install yet" .claude/commands/retrofit-it.md
check "stdlib imports are ordinary unused imports" gq -F "Standard-library modules" "$REF"
check "release steps are never run"            gq -F "Never run a step that releases, deploys, publishes" "$REF"
check "a dismissed ask keeps nothing for good" gq -F "If the ask is dismissed or skipped, nothing was chosen" "$REF"
check "keep/drop the cleanup have procedures"  gq -F "git merge --ff-only" "$CMD"
check "keep never merges into the default branch" gq -F "never merge into the default branch" "$CMD"
check "branch -D appears once, in drop only"   bash -c '[ "$(grep -c -F "branch -D" "$1")" = 1 ] && [ "$(grep -F "branch -D" "$1" | grep -c -F "drop the cleanup")" = 1 ]' _ "$CMD"
check "untracked files are never candidates"   gq -F '**Untracked** -- anything `git ls-files --others --exclude-standard` lists' "$REF"
check "last in-project import is CAUTION"      gq -F "when it is the only import of that" "$REF"
check "a commit hook's edits are re-verified"  gq -F "is unverified again" "$REF"
check "log rows only after a green verify"     gq -F "rows are written only now, never before a green" "$REF"
check "every multi-item question can keep all" gq -F '"Keep all of these"' "$REF"
check "Q14 re-runs the tests"                  gq -E '^\*\*Q14\*\*.*the project.s tests \(T01\)' "$BS"
check "Q14 is report-only in a retrofit"       gq -F "during a retrofit **Q14 is report-only**" .claude/commands/retrofit-it.md
check "the Q15 TODO line is kept current"      gq -F "Q15 dead-code line" "$CMD"
check "kept decisions are read from every branch" gq -F "on **any local branch**" "$REF"
check "a red batch's culprit is in use, never offered" gq -F "never offer it for removal" "$REF"
check "run-time commands are a dynamic shape"   gq -F "commands built at run time" "$REF"
check "waiting-cleanup message fits its start"  gq -F "if it started from the default branch" "$CMD"
check "keep/drop reinstall changed deps"        gq -F "so what's installed matches it again" "$CMD"
check "install.sh describes it"                gq -F "deadcode-it) desc=" install.sh
# controls: a dropped tool or grade, or a widened SAFE row, must fail
saferow <(sed -E 's/^(\| \*\*SAFE\*\* \|)/\1 whole files;/' "$REF") && bad "control: widened SAFE row passed" || ok "control: widened SAFE row fails saferow"
tools <(grep -v "| vulture |" "$REF") && bad "control: missing tool passed" || ok "control: missing tool fails tools"
grades <(sed 's/\*\*DANGER\*\*/DANGER/' "$REF") && bad "control: missing grade passed" || ok "control: missing grade fails grades"

[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
