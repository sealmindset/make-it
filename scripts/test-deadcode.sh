#!/usr/bin/env bash
# /deadcode-it: dead code is proven unused, graded, removed in verified batches, and logged.
# Contract these checks pin (behaviour, not phrasing, where a regex can tell the difference):
#   - The skill loads deadcode.md, which defines the keep-list, every evidence tool, the grades,
#     the batch-verify-rollback cadence, the CAUTION ask, the deletion log and the Q14 reminder.
#   - Never: delete DANGER/keep-list/untracked items, delete on red, check against an old build,
#     delete a branch, push, merge into the default branch, weaken a check, undo the user's work.
#   - Owner's calls (2026-10-31): Docker apps are rebuilt before every check; branches are never
#     deleted (drop = rename); nothing is undone automatically and earlier cleanups never block a
#     run; Q14 is a tool-free upkeep reminder (Q15 retired); the scaffold lint script is fixed.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }   # reads all its input: no SIGPIPE under pipefail
none() { local re="$1"; shift; [ "$(cat "$@" | grep -cE -- "$re")" = 0 ]; }
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

CMD=.claude/commands/deadcode-it.md
REF=.claude/make-it/references/deadcode.md
BS=.claude/make-it/references/build-standards.md
row() { grep -E "^\| \*\*$1\*\* \|" "$2" || true; }              # a grade row of the §4 table
tools() { local t; for t in knip depcheck ts-prune tsc eslint ruff vulture deptry; do gq -E "^\| [^|]+ \| $t \|" "$1" || return 1; done; }
grades() { local g; for g in SAFE CAUTION DANGER; do gq -E "^\| \*\*$g\*\* \|" "$1" || return 1; done; }
danger_never() { local r; r="$(row DANGER "$1")"; [ "$(grep -c '| Never deleted\.' <<<"$r")" = 1 ] && [ "$(grep -ciE 'deleted after|deleted as well|except|unless the user|when asked' <<<"$r")" = 0 ]; }
safe_narrow() { local r; r="$(row SAFE "$1")"; [ "$(grep -ciE 'whole file|page|route|confirm|component|shared utilit' <<<"$r")" = 0 ] && [ "$(grep -cF 'ts-prune and vulture never count on their own' <<<"$r")" = 1 ]; }
untracked_never() { gq -E '^4\. \*\*Untracked\*\*' "$1" && gq -F "Never a candidate, never edited" "$1"; }
batch20() { gq -F 'At most ~20 items per batch' "$1" && [ "$(grep -F 'items per batch' "$1" | grep -cE '200|or more|in a hurry')" = 0 ]; }
q14_no_tools() { local l; l="$(grep -E '^\*\*Q14\*\* \[Tier 0\] \[WARN\]' "$1" || true)"; [ -n "$l" ] && [ "$(grep -c 'Runs no tools' <<<"$l")" = 1 ] && [ "$(grep -cE 'ruff|tsc|knip|vulture|deptry|uvx|npx|--fix|\[FIX\]' <<<"$l")" = 0 ] && none '^\*\*Q15\*\*' "$1"; }
no_branch_delete() { none 'branch[[:space:]]+-[a-zA-Z]*[dD][a-zA-Z]*([^a-zA-Z]|$)|branch[[:space:]]+--delete' "$@"; }
add_all_only_forbidden() { [ "$(cat "$@" | grep -F 'git add -A' | grep -vcF 'never `git add -A`' || true)" = 0 ]; }
before() { local a b; a="$(grep -n -F -- "$2" "$1" | head -1 | cut -d: -f1)"; b="$(grep -n -F -- "$3" "$1" | head -1 | cut -d: -f1)"; [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }

# --- the reference defines the whole contract
check "the skill loads deadcode.md"            gq -F "@~/.claude/make-it/references/deadcode.md" "$CMD"
check "every evidence tool is listed"          tools "$REF"
check "all three grades are defined"           grades "$REF"
check "DANGER is never deleted, no exceptions" danger_never "$REF"
check "SAFE: no files/routes/components, never ts-prune/vulture alone" safe_narrow "$REF"
check "untracked files are never candidates"   untracked_never "$REF"
check "batches are at most ~20 items"          batch20 "$REF"
check "scaffold-owned is judged by content, not path" gq -F "Judged **by content, not by path**" "$REF"
check "unused imports/locals are never scaffold-owned" gq -F "**unused import or local is never scaffold-owned**" "$REF"
check "unchecked areas are CAUTION at most"    gq -F "your checks run this file, so I can't confirm" "$REF"
check "keep from the default branch has wording" gq -F "so I don't add it there directly" "$CMD"
check "scaffold keep-list only in make-it apps" gq -F 'only when `.make-it/app-context.json` exists' "$REF"
check "kept decisions read from every branch"  gq -F "on **any local branch**, dropped cleanups included" "$REF"
check "honoured decisions copied into this log" gq -F "so the decision survives if that branch is ever removed" "$REF"
check "a tool not run is never 'no findings'"  gq -F 'never as "no findings"' "$REF"
check "tools run on the host"                  gq -F "**on the host** (a container can't" "$REF"
check "only /deadcode-it runs the tools"       gq -F "Only \`/deadcode-it\` runs it." "$REF"
check "deptry sees the project's packages"     gq -F "uvx --with-requirements requirements.txt deptry" "$REF"
check "deptry pyproject form writes nothing into the project" gq -F "uv pip compile pyproject.toml -q -o <scratch>/req.txt" "$REF"
check "tsc runs from the project's install, no emit" gq -F 'node_modules/.bin/tsc --noEmit --noUnusedLocals --incremental false' "$REF"
check "no 'npx --no tsc' command"              none '^\| JS/TS \| tsc \| `npx' "$REF"
check "eslint only when installed + matching config" gq -F 'only when `node_modules/.bin/eslint` exists' "$REF"
check "ruff leaves no cache in the project"    gq -F "uvx ruff check --no-cache" "$REF"
check "Python deps can be SAFE via deptry"     gq -F "knip, depcheck or deptry (ts-prune and vulture never count" "$REF"
# --- grading traps
check "effect imports are never SAFE"          gq -F "**Imported for its effect**" "$REF"
check "__init__.py imports are re-exports"     gq -F '**any import in an `__init__.py`** is a re-export' "$REF"
check "ruff --fix is never applied"            gq -F "ruff's fix is never applied" "$REF"
check "an export used in its own file is kept" gq -F "**Used in its own file**" "$REF"
check "rest-destructuring names never candidates" gq -F 'const { password, ...safe } = user' "$REF"
check "F811 on def/class is never SAFE"        gq -F 'A ruff F811 redefinition of a `def` or `class` is never SAFE' "$REF"
check "Next.js metadata/proxy files are conventions" gq -F '`twitter-image`), `middleware.*`, `proxy.*`' "$REF"
check "platform-loaded deps are a §3.5 class"  gq -F 'may live only in `.env` or the hosting platform' "$REF"
check "deps SAFE only with a production-like start" gq -F "only when the §5.1 verify set starts the app the way production does" "$REF"
check "vulture 100% items are never deleted"   gq -F "are refactors, not dead code: candidates, never deleted" "$REF"
check "a weak verify set narrows SAFE"         gq -F "**Weak verify set.**" "$REF"
check "a call on the right of a local is kept" gq -F "delete only the binding and keep the expression" "$REF"
# --- where checks run
check "settings checked wherever checks run"   gq -F "**Settings first, wherever the checks run.**" "$REF"
check "a non-local datastore stops the run"    gq -F "Your app's settings point at <host>, so I" "$REF"
check "Docker apps rebuild before every verify" gq -F 'before **every** verify,' "$REF"
check "the rebuild command waits for health"   gq -F 'docker compose up -d --build --wait <app services>' "$REF"
check "never exec into an old container"       gq -F 'Never `exec` into a container that was built before the batch' "$REF"
check "frontend lint/type-check run on the host" gq -F "Steps the images can't run" "$REF"
check "CI's commands are the verify set"       gq -F "the commands CI runs for these when CI defines them" "$REF"
check "release steps are never run"            gq -F "Never run a step that releases, deploys," "$REF"
check "audits aren't part of the baseline"     gq -F "a newly published advisory isn't a broken" "$REF"
check "red baseline deletes nothing"           gq -F "Nothing is deleted on a red baseline" "$REF"
check "only gates stop at the baseline"        gq -F "**A gate red at the baseline → stop.**" "$REF"
check "gates are tests and build"              gq -F "**Gates -- tests and build**" "$REF"
check "lint/type/format are ratcheted"         gq -F "**Ratcheted -- lint, type-check, format**" "$REF"
check "ratchet compares findings, not lines"   gq -F "never line numbers, which shift as code is deleted" "$REF"
check "a new ratcheted finding is red"         gq -F "A new finding is red," "$REF"
check "tests run without report-only flags"    gq -F "Run tests without flags that only write reports" "$REF"
check "every tsc runs with --incremental false" none 'tsc --noEmit`|tsc --noEmit,|tsc --noEmit\)' "$REF"
# --- cadence and rollback
check "rollback restores only the batch's paths" gq -F "only the batch's own paths, so nothing else the user touched" "$REF"
check "no whole-repo restore anywhere"         none 'restore[^`]*-- :/' "$CMD" "$REF"
check "a flaky red is re-run before bisecting" gq -F "re-run the same verify once on the same code" "$REF"
check "a rolled-back dep batch reinstalls"     gq -F "reinstalls from the restored" "$REF"
check "a red batch's culprit is in use, never offered" gq -F "never offer it for removal" "$REF"
check "the project's package manager is used"  gq -F '| `pnpm-lock.yaml` | `pnpm install` |' "$REF"
check "Poetry 2 commands"                      gq -F '`poetry sync`' "$REF"
check "stage only the batch's paths"           gq -F 'never `git add -A`' "$REF"
check "git add -A appears only as forbidden"   add_all_only_forbidden "$CMD" "$REF"
check "commit hooks: file taken out, never ignored" gq -F 'Never `--no-verify`, never add an' "$REF"
check "no weakening a check to pass"           gq -F "Never make a check pass by weakening it" "$REF"
check "log rows only after a green verify"     gq -F "rows are written only now, never before a green" "$REF"
# --- the ask
check "a dismissed ask keeps nothing for good" gq -F "If the ask is dismissed or skipped, nothing was chosen" "$REF"
check "every multi-item question can keep all" gq -F '"Keep all of these"' "$REF"
check "a one-item ask is single-select"        gq -F '(`multiSelect: false`) with' "$REF"
# --- the skill: preconditions and branch lifecycle
check "no branch deletion anywhere"            no_branch_delete "$CMD" "$REF"
check "no stash, no automatic undo in the skill" none 'git stash|git restore' "$CMD"
check "no loosening phrases anywhere"          none "carry on anyway|drop it anyway|commit the batch as is|deleted as well|regardless of the verify" "$CMD" "$REF"
check "no push, clean or hard reset anywhere"  none 'git push|gh pr create|git clean|reset --hard' "$CMD" "$REF"
check "nothing is undone automatically"        gq -F "Nothing here is ever undone automatically, and an" "$CMD"
check "uncommitted changes: ask, never undo"   gq -F "stop, never undo them. One ask" "$CMD"
check "earlier cleanups never block, report names them" gq -F "They don't stop the run; the report mentions them." "$CMD"
check "a run on a cleanup branch stops"        gq -F "You're on an earlier" "$CMD"
check "branch checks precede the save ask"     before "$CMD" "**Not on a cleanup.**" "**Saved work.**"
check "detached HEAD stops the run"            gq -F "not on a branch right now" "$CMD"
check "a red gate stops in the skill"          gq -F "A gate (tests or build) red → stop, on the starting branch with nothing changed" "$CMD"
check "lint debt never stops the run"          gq -F "Lint, type-check or format findings alone never stop the run" "$CMD"
check "keep/drop with no cleanup has wording"  gq -F "There's no cleanup to keep or" "$CMD"
check "cleanup branch made only after a green baseline" gq -F 'Green → create the cleanup branch from HEAD' "$CMD"
check "nothing is fetched or pulled"           gq -F "Nothing is fetched or pulled" "$CMD"
check "drop renames to -dropped"               gq -F 'branch -m <cleanup branch> <cleanup branch>-dropped' "$CMD"
check "drop refuses a branch with the user's work" gq -F "also has your own work on it" "$CMD"
check "keep never merges into the default branch" gq -F "never merge into the default branch" "$CMD"
check "keep is a fast-forward only"            gq -F "git merge --ff-only <cleanup" "$CMD"
check "keep handles a vanished start branch"   gq -F "The branch this cleanup" "$CMD"
check "keep/drop rebuild a Docker app"         gq -F "containers are rebuilt from the branch you're now on" "$CMD"
check "no tool ran is not 'nothing to clean'"  gq -F "I couldn't check your code" "$CMD"
check "the report says you're on the cleanup"  gq -F "You're on the cleanup now" "$CMD"
# --- framework wiring
check "Q14 runs no tools, Q15 is gone"         q14_no_tools "$BS"
check "Q14 N/A in the first /make-it build"    gq -F "N/A in /make-it's first build-verify" "$BS"
check "no Q15 left anywhere"                   none 'Q15' "$CMD" "$REF" "$BS" .claude/commands/make-it.md .claude/commands/resume-it.md .claude/commands/retrofit-it.md CLAUDE.md README.md
check "make-it build-verify lists Q01-Q14"     gq -F "**Q01-Q14**" .claude/commands/make-it.md
check "retrofit runs no dead-code tools"       gq -F "not measured here (no tools run on an app" .claude/commands/retrofit-it.md
check "resume-it reads only log dates for Q14" gq -F "it runs no tools and writes nothing, just reads the dates" .claude/commands/resume-it.md
check "resume-it suggests /deadcode-it"        gq -F "(routes to /deadcode-it)" .claude/commands/resume-it.md
check "scaffold lint no longer uses next lint" gq -F '"lint": "eslint . && prettier --check .",' .claude/make-it/scaffolds/fastapi-nextjs/frontend/package.json
check "fullstack scaffold lint no longer uses next lint" gq -F '"lint": "eslint . && prettier --check .",' .claude/make-it/scaffolds/nextjs-fullstack/package.json
check "scaffold ruff never auto-deletes imports" gq -F 'unfixable = ["F401", "F841"]' .claude/make-it/scaffolds/fastapi-nextjs/pyproject.toml
check "recent work is never removed or offered" gq -F "**Recent work** -- code whose lines were last changed in the past 14 days" "$REF"
check "only effectful in-project modules make an import CAUTION" gq -F "A module that only defines things" "$REF"
check "no eslint dependency = not applicable"   gq -F "no \`eslint\` in the project's dependencies → not applicable" "$REF"
check "Q14 counts only cleanups on this branch" gq -F "**on the current branch**" "$REF"
check "Q14 flags a waiting cleanup"            gq -F "waiting to be kept or dropped\". The caller" "$REF"
check "two cleanups never remove the same thing" gq -F "two cleanups never remove the same thing" "$CMD"
check "keep/drop check unsaved changes first"  gq -F "both first check for uncommitted changes to" "$CMD"
check "'Leave them' has its stop message"      gq -F "OK -- I've left your changes as" "$CMD"
check "scaffold test fixture keeps ids off UserInfo" gq -F "SEED_USER_IDS[user_info.sub]" .claude/make-it/scaffolds/fastapi-nextjs/backend/tests/conftest.py
check "scaffold images never get the host's installs" bash -c 'for f in .claude/make-it/scaffolds/fastapi-nextjs/frontend/.dockerignore .claude/make-it/scaffolds/fastapi-nextjs/backend/.dockerignore .claude/make-it/scaffolds/nextjs-fullstack/.dockerignore; do [ "$(grep -cE "^(node_modules|\.venv)$" "$f")" -ge 1 ] || exit 1; done'
check "CLAUDE.md: culprit in use, never offered" gq -F "the culprit is logged in use and never offered" CLAUDE.md
check "desktop bundles carry deadcode.md"      bash -c 'for f in desktop/skills/make-it/refs.txt desktop/skills/guardrails/refs.txt; do [ "$(grep -cxF ".claude/make-it/references/deadcode.md" "$f")" = 1 ] || exit 1; done'
check "install.sh describes it"                gq -F "deadcode-it) desc=" install.sh
check "install.ps1 describes it"               gq -F '"deadcode-it" {' install.ps1
# --- controls: the behavioural checks must fail on real regressions (mutants go to temp files:
#     the helpers read their input more than once, which a <(...) pipe can't serve)
MUTD="$(mktemp -d)"
mut() { local src="$1" f; shift; f="$(mktemp "$MUTD/m.XXXXXX")"; sed "$@" "$src" > "$f"; echo "$f"; }
txt() { local f; f="$(mktemp "$MUTD/t.XXXXXX")"; printf '%s\n' "$1" > "$f"; echo "$f"; }
danger_never "$(mut "$REF" -E 's/\| Never deleted\./| Deleted after a confirm./')" && bad "control: DANGER deleted passed" || ok "control: DANGER 'deleted' fails"
danger_never "$(mut "$REF" -E 's/(\| Never deleted\.)/\1 Deleted as well when asked./')" && bad "control: DANGER exception passed" || ok "control: DANGER exception fails"
untracked_never "$(mut "$REF" 's/Never a candidate, never edited/Candidates like any file/')" && bad "control: untracked candidate passed" || ok "control: untracked candidate fails"
batch20 "$(mut "$REF" 's/At most ~20 items/At most ~200 items/')" && bad "control: batch 200 passed" || ok "control: batch 200 fails"
batch20 "$(mut "$REF" 's/At most ~20 items per batch/At most ~20 items per batch, or 200 in a hurry/')" && bad "control: batch loophole passed" || ok "control: batch loophole fails"
safe_narrow "$(mut "$REF" -E 's/^(\| \*\*SAFE\*\* \|)/\1 whole files;/')" && bad "control: widened SAFE passed" || ok "control: widened SAFE fails"
safe_narrow "$(mut "$REF" -E 's/^(\| \*\*SAFE\*\* \|)/\1 components, shared utilities;/')" && bad "control: SAFE components passed" || ok "control: SAFE components fails"
q14_no_tools "$(mut "$BS" -E 's/Runs no tools/Runs `uvx ruff`/')" && bad "control: Q14 tools passed" || ok "control: Q14 running tools fails"
tools "$(mut "$REF" '/| vulture |/d')" && bad "control: missing tool passed" || ok "control: missing tool fails"
add_all_only_forbidden "$(txt 'Stage with `git add -A` for speed')" && bad "control: git add -A passed" || ok "control: git add -A fails"
no_branch_delete "$(txt 'git branch -D x')" && bad "control: branch -D passed" || ok "control: branch -D fails"
no_branch_delete "$(txt 'delete it with `git branch -D`')" && bad "control: backticked -D passed" || ok "control: backticked -D fails"
no_branch_delete "$(txt 'git branch -Df x')" && bad "control: -Df passed" || ok "control: -Df fails"
no_branch_delete "$(txt 'git branch -m a b')" && ok "control: branch -m allowed" || bad "control: branch -m wrongly flagged"
before "$CMD" "**Saved work.**" "**Not on a cleanup.**" && bad "control: order check passed reversed" || ok "control: reversed order fails"

rm -rf "$MUTD"
[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
