#!/usr/bin/env bash
# /deadcode-it: dead code is proven unused, graded, removed in verified batches, and logged.
# Contract these checks pin (behaviour, not phrasing, where a regex can tell the difference):
#   - The skill loads deadcode.md, which defines the keep-list, every evidence tool, the grades,
#     the batch-verify-rollback cadence, the CAUTION ask, the deletion log and the Q15 line.
#   - Never: delete DANGER/keep-list/untracked items, delete on red, check against an old build,
#     delete a branch, push, merge into the default branch, weaken a check.
#   - Owner's calls (2026-10-31, third review): Q14/Q15 are report-only everywhere; Docker apps
#     are rebuilt before every check; branches are never deleted (drop = rename).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }   # reads all its input: no SIGPIPE under pipefail
none() { [ "$(cat "${@:2}" | grep -cE "$1")" = 0 ]; }
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

CMD=.claude/commands/deadcode-it.md
REF=.claude/make-it/references/deadcode.md
BS=.claude/make-it/references/build-standards.md
row() { grep -E "^\| \*\*$1\*\* \|" "$2"; }                    # a grade row of the §4 table
tools() { local t; for t in knip depcheck ts-prune tsc eslint ruff vulture deptry; do gq -E "^\| [^|]+ \| $t \|" "$1" || return 1; done; }
grades() { local g; for g in SAFE CAUTION DANGER; do gq -E "^\| \*\*$g\*\* \|" "$1" || return 1; done; }
danger_never() { [ "$(row DANGER "$1" | grep -c '| Never deleted\.')" = 1 ]; }
safe_narrow() { [ "$(row SAFE "$1" | grep -ciE 'whole file|page|route|confirm')" = 0 ] && [ "$(row SAFE "$1" | grep -cF 'ts-prune and vulture never count on their own')" = 1 ]; }
untracked_never() { gq -E '^4\. \*\*Untracked\*\*' "$1" && gq -F "Never a candidate, never edited" "$1"; }
batch20() { gq -F 'At most ~20 items per batch' "$1"; }
q_report_only() { local q; for q in Q14 Q15; do [ "$(grep -E "^\*\*$q\*\* \[Tier 0\] \[WARN\]" "$1" | grep -c 'report-only')" = 1 ] || return 1; done
                  [ "$(grep -E '^\*\*Q1[45]\*\*' "$1" | grep -cE -- '--fix|\[FIX\]')" = 0 ]; }
before() { [ "$(grep -n -F "$2" "$1" | head -1 | cut -d: -f1)" -lt "$(grep -n -F "$3" "$1" | head -1 | cut -d: -f1)" ]; }

# --- the reference defines the whole contract
check "the skill loads deadcode.md"            gq -F "@~/.claude/make-it/references/deadcode.md" "$CMD"
check "every evidence tool is listed"          tools "$REF"
check "all three grades are defined"           grades "$REF"
check "DANGER is never deleted"                danger_never "$REF"
check "SAFE: no files/routes, never ts-prune/vulture alone" safe_narrow "$REF"
check "untracked files are never candidates"   untracked_never "$REF"
check "batches are at most ~20 items"          batch20 "$REF"
check "scaffold keep-list only in make-it apps" gq -F 'only when `.make-it/app-context.json` exists' "$REF"
check "kept decisions read from every branch"  gq -F "on **any local branch**, dropped cleanups included" "$REF"
check "a tool not run is never 'no findings'"  gq -F 'never as "no findings"' "$REF"
check "tools run on the host"                  gq -F "**on the host** (a container can't" "$REF"
check "report-only callers never install"      gq -F "use **existing installs only**" "$REF"
check "deptry sees the project's packages"     gq -F "uvx --with-requirements requirements.txt deptry" "$REF"
check "deptry pyproject form writes nothing into the project" gq -F "uv pip compile pyproject.toml -q -o <scratch>/req.txt" "$REF"
check "eslint only when installed + matching config" gq -F 'only when `node_modules/.bin/eslint` exists' "$REF"
check "effect imports are never SAFE"          gq -F "**Imported for its effect**" "$REF"
check "__init__.py imports are re-exports"     gq -F '**any import in an `__init__.py`** is a re-export' "$REF"
check "ruff --fix is never applied"            gq -F "ruff's fix is never applied" "$REF"
check "an export used in its own file is kept" gq -F "**Used in its own file**" "$REF"
check "Next.js metadata/proxy files are conventions" gq -F '`twitter-image`), `middleware.*`, `proxy.*`' "$REF"
check "platform-loaded deps are a §3.5 class"  gq -F 'may live only in `.env` or the hosting platform' "$REF"
check "deps SAFE only with a production-like start" gq -F "only when the §5.1 verify set starts the app the way production does" "$REF"
check "vulture 100% items are never deleted"   gq -F "are refactors, not dead code: candidates, never deleted" "$REF"
check "a weak verify set narrows SAFE"         gq -F "**Weak verify set.**" "$REF"
check "a call on the right of a local is kept" gq -F "delete only the binding and keep the expression" "$REF"
# --- where checks run (owner's call: rebuild before every check)
check "Docker apps rebuild before every verify" gq -F 'before **every** verify, `docker compose up -d --build --wait' "$REF"
check "never exec into an old container"       gq -F 'Never `exec` into a container that' "$REF"
check "settings must point at this machine"    gq -F "Your app's settings point at <host>, so I won't start it" "$REF"
check "release steps are never run"            gq -F "Never run a step that releases, deploys," "$REF"
check "audits aren't part of the baseline"     gq -F "a newly published advisory isn't a broken" "$REF"
check "red baseline deletes nothing"           gq -F "Nothing is deleted on a red baseline" "$REF"
# --- cadence and rollback
check "rollback covers the whole repo"         gq -F 'git restore --staged --worktree -- :/' "$REF"
check "a rolled-back dep batch reinstalls"     gq -F "reinstalls from the restored" "$REF"
check "a red batch's culprit is in use, never offered" gq -F "never offer it for removal" "$REF"
check "the project's package manager is used"  gq -F '| `pnpm-lock.yaml` | `pnpm install` |' "$REF"
check "stage only the batch's paths"           gq -F 'never `git add -A`' "$REF"
check "commit hooks: file taken out, never ignored" gq -F 'Never `--no-verify`, never add an' "$REF"
check "no weakening a check to pass"           gq -F "Never make a check pass by weakening it" "$REF"
check "log rows only after a green verify"     gq -F "rows are written only now, never before a green" "$REF"
# --- the ask
check "a dismissed ask keeps nothing for good" gq -F "If the ask is dismissed or skipped, nothing was chosen" "$REF"
check "every multi-item question can keep all" gq -F '"Keep all of these"' "$REF"
check "a one-item ask is single-select"        gq -F '(`multiSelect: false`) with' "$REF"
# --- the Q15 line
check "one marked Q15 line, replaced not added" gq -F "replaces the existing marker line rather than adding another" "$REF"
# --- the skill: preconditions and branch lifecycle (owner's call: never delete a branch)
check "no branch deletion anywhere"            none 'branch -[dD]( |$)|branch --delete' "$CMD" "$REF"
check "no push, clean or hard reset anywhere"  none 'git push|gh pr create|git clean|reset --hard' "$CMD" "$REF"
check "drop renames to -dropped"               gq -F 'branch -m <cleanup branch> <cleanup branch>-dropped' "$CMD"
check "drop refuses a branch with the user's work" gq -F "also has your own work on it" "$CMD"
check "keep never merges into the default branch" gq -F "never merge into the default branch" "$CMD"
check "keep is a fast-forward only"            gq -F "git merge --ff-only <cleanup" "$CMD"
check "detached HEAD stops the run"            gq -F "not on a branch right now" "$CMD"
check "an interrupted batch is rolled back, never saved" gq -F "(It is never" "$CMD"
check "any waiting cleanup stops the run"      gq -F "There's an earlier cleanup still waiting" "$CMD"
check "a squash-merged cleanup isn't waiting"  gq -F "a /ship-it squash-merge" "$CMD"
check "rollback precedes the save offer"       before "$CMD" "**An unfinished cleanup.**" "**Saved work.**"
check "cleanup branch made only after a green baseline" gq -F 'Green → create the cleanup branch from HEAD' "$CMD"
check "nothing is fetched or pulled"           gq -F "Nothing is fetched or pulled" "$CMD"
check "untracked files don't block the run"    gq -F -- "--untracked-files=no" "$CMD"
check "no tool ran is not 'nothing to clean'"  gq -F "I couldn't check your code" "$CMD"
check "the report says you're on the cleanup"  gq -F "You're on the cleanup now" "$CMD"
# --- framework wiring (owner's call: Q14/Q15 report-only everywhere)
check "Q14 and Q15 are report-only WARNs, never --fix" q_report_only "$BS"
check "Q14/Q15 N/A in the first /make-it build" gq -F "N/A in /make-it's first build-verify" "$BS"
check "make-it build-verify lists Q01-Q15"     gq -F "**Q01-Q15**" .claude/commands/make-it.md
check "retrofit Q14/Q15 report-only"           gq -F "Q14 and Q15 are report-only: nothing is deleted from the existing" .claude/commands/retrofit-it.md
check "retrofit Discovery never installs"      gq -F 'never `npm ci`, a venv install or any other install' .claude/commands/retrofit-it.md
check "resume-it reuses the dated Q15 line"    gq -F 'reuse it while no tracked code changed since its date' .claude/commands/resume-it.md
check "resume-it suggests /deadcode-it"        gq -F "(routes to /deadcode-it)" .claude/commands/resume-it.md
check "CLAUDE.md: culprit in use, never offered" gq -F "the culprit is logged in use and never offered" CLAUDE.md
check "desktop bundles carry deadcode.md"      bash -c 'for f in desktop/skills/make-it/refs.txt desktop/skills/guardrails/refs.txt; do [ "$(grep -cxF ".claude/make-it/references/deadcode.md" "$f")" = 1 ] || exit 1; done'
check "install.sh describes it"                gq -F "deadcode-it) desc=" install.sh
check "install.ps1 describes it"               gq -F '"deadcode-it" {' install.ps1
# --- controls: the behavioural checks must fail on real regressions
danger_never <(sed -E 's/\| Never deleted\./| Deleted after a confirm./' "$REF") && bad "control: DANGER deleted passed" || ok "control: DANGER 'deleted' fails"
untracked_never <(sed 's/Never a candidate, never edited/Candidates like any file/' "$REF") && bad "control: untracked candidate passed" || ok "control: untracked candidate fails"
batch20 <(sed 's/At most ~20 items/At most ~200 items/' "$REF") && bad "control: batch 200 passed" || ok "control: batch 200 fails"
safe_narrow <(sed -E 's/^(\| \*\*SAFE\*\* \|)/\1 whole files;/' "$REF") && bad "control: widened SAFE passed" || ok "control: widened SAFE fails"
q_report_only <(sed -E 's/^(\*\*Q14\*\* \[Tier 0\]) \[WARN\]/\1 [FIX]/' "$BS") && bad "control: Q14 FIX passed" || ok "control: Q14 FIX fails"
tools <(grep -v "| vulture |" "$REF") && bad "control: missing tool passed" || ok "control: missing tool fails"
none 'branch -[dD]( |$)' <(printf 'git branch -D x\n') && bad "control: branch -D passed" || ok "control: branch -D fails"
before "$CMD" "**Saved work.**" "**An unfinished cleanup.**" && bad "control: order check passed reversed" || ok "control: reversed order fails"

[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
