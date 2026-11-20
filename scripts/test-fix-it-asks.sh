#!/usr/bin/env bash
# E03-S10: /fix-it asks through the approval block -- fewer asks, same gates.
# Contract these checks pin (.claude/commands/fix-it.md, as the /fix-it agent reads it):
#   - approval-block.md is @-linked exactly once, inside <execution_context>; no bare yes/no ask is left.
#   - The full rollback is high-stakes: its own ask, never batched, never a plain yes, never the Recommended option. It
#     carries the evidence, what is discarded, what happens to the user's own earlier work, the undo that is true, what
#     is unusual and the one thing to check, and two named outcomes. Nothing is rolled back unless that outcome is picked.
#   - SEMI-AUTO fixes are one ask per step: one multi-select, each fix its own pick with its diff, no "all" option, never
#     one ask per fix. An unpicked fix is reverted, goes on the manual list, and is not asked about again in the run; a
#     dismissed ask keeps nothing.
#   - Every /fix-it gate stays: approval before any change, the git strategy pick with its "not now", the audit branch
#     never merged or pushed, the ten guardrails, the never-do list, per-fix revert before any full rollback.
# A wording test is a tripwire, not a proof: it catches these rules being dropped or reversed, not an agent ignoring them.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# the whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise)
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

F=.claude/commands/fix-it.md
LINK='@~/.claude/make-it/references/approval-block.md'
flat() { tr '\n' ' ' | tr -s ' '; }
# text between the first line matching $1 and the next line matching $2 (start line included)
between() { awk -v a="$1" -v b="$2" 'on && $0 ~ b {exit} $0 ~ a {on=1} on' "$F"; }
# has SECTION 'whole sentence': the flattened section holds that exact text
has() { printf "%s" "$1" | gq -F -- "$2"; }

CTX="$(between '^<execution_context>' '^</execution_context>')"
TRI="$(between '<step name="triage">' '^</step>' | flat)"
FIX="$(between '<step name="fix">' '^</step>' | flat)"
# bracket forms, not backslashes: gawk warns about "\*" in a -v string, and this test fails on any stderr
SA="$(between '^[*][*]SEMI-AUTO fixes: one ask per step' '^[*][*]Step 1: ' | flat)"
RB="$(between '^<rollback-strategy>' '^</rollback-strategy>' | flat)"
GUARD="$(between '^<guardrails>' '^</guardrails>' | flat)"
PERSONA="$(between '^<persona>' '^</persona>' | flat)"
ERRH="$(between '^<error-handling>' '^</error-handling>' | flat)"
ALL="$(flat < "$F")"

# 1. the block is linked once, in <execution_context>
check "the approval-block.md @-import appears exactly once in fix-it.md" '[ "$(grep -cF "$LINK" "$F")" = 1 ]'
check "that one link is inside <execution_context>" 'printf "%s\n" "$CTX" | gq -xF -- "$LINK"'

# 2. no bare yes/no ask, no leftover open offer
check "grep -niE '\\(y/n\\)|y/n\\b|yes/no' prints nothing" '[ "$(grep -ciE "\(y/n\)|y/n\b|yes/no" "$F")" = 0 ]'
check "no open-ended offer is left (would you like / do you want / shall I / ok to proceed)" \
  '! printf "%s" "$ALL" | gq -iE "would you like|do you want|shall I|should I|ok to proceed|okay to proceed|ready to proceed"'
check "no implicit approval is left (a fix kept unless the user objects)" \
  '! printf "%s" "$ALL" | gq -iE "if the user objects|unless the user objects|let the user confirm|implicit approval"'

# 3. the full rollback: high-stakes, its own ask, decision-ready, two named outcomes
check "rollback: the section was found" '[ -n "$RB" ]'
check "rollback: it is high-stakes, its own ask, never batched, never a plain yes" \
  'has "$RB" "Rolling back is high-stakes: it discards work, and part of that cannot be brought back. It is its own ask, never batched with another, and never a plain yes: the user picks the named outcome."'
check "rollback: the agent looks at git before asking, so the ask is what it saw" \
  'has "$RB" "Look before asking -- \`git diff --stat pre-fix-it\`, \`git log --oneline pre-fix-it..HEAD\`, \`git status --short\` and \`git stash list\` -- so every line of the ask is what you saw, not what you assume."'
check "rollback ask: what has happened so far, and that nothing is rolled back yet" \
  'has "$RB" "\"Verification is still failing after [N] rounds of fixing. Nothing has been rolled back yet."'
check "rollback ask: the evidence -- the failing check, the fixes that pass on their own, the ones that do not" \
  'has "$RB" "What I saw: [which check fails, and its error in one line]. [K] fixes pass on their own: [names]. [M] do not: [names]."'
check "rollback ask: the blast radius -- every change since the snapshot, files named or counted, the passing fixes included, the command shown" \
  'has "$RB" "What a rollback discards: every change since the \`pre-fix-it\` snapshot -- [N] files ([names, or the count and the first few]) and [C] commits -- the fixes that pass included. I would run: [the exact command]."'
check "rollback ask: what happens to the work the user had before the run (the stash is not put back)" \
  'has "$RB" "Your own work from before this run: [none was uncommitted / it is in git'"'"'s stash (\`[stash entry]\`). A rollback does not touch it and nothing in this run puts it back: \`git stash pop\` does.]"'
check "rollback ask: the undo that is true -- committed fixes can come back, uncommitted changes cannot" \
  'has "$RB" "Undo: fixes already committed can be brought back from commit \`[SHA]\`. Changes not committed ([list, or \"none\"]) cannot: no undo."'
check "rollback ask: what is unusual" \
  'has "$RB" "What is unusual: [what differs from an ordinary failed fix, or \"nothing\"]."'
check "rollback ask: the one thing to check" \
  'has "$RB" "The one thing to check: [the single fact, such as whether \`[failing check]\` passed before this run]."'
check "rollback ask: the first named outcome keeps the fixes that pass" \
  'has "$RB" "- **Keep the [K] fixes that pass** -- the [M] that fail are reverted one at a time and go on the manual list. Nothing else is discarded."'
check "rollback ask: the second named outcome is the rollback, with its count and what it costs" \
  'has "$RB" "- **Roll back all [N] files to \`pre-fix-it\`** -- every fix is discarded, the [K] that pass included, and all [K+M] findings stay open.\""'
check "rollback: never the Recommended option, and done only on that pick" \
  'has "$RB" "The rollback is never the Recommended option. Roll back only when that outcome is picked."'
check "rollback: nothing else in the section is marked Recommended" \
  '[ "$(printf "%s" "$RB" | sed "s/The rollback is never the Recommended option\.//" | grep -ci "recommended")" = 0 ]'
check "rollback: a dismissed ask rolls nothing back and stops" \
  'has "$RB" "If the ask is dismissed or left unanswered, roll nothing back and change nothing more: stop, and say in the report that verification is still failing."'
check "rollback: a pick is used once" 'has "$RB" "A pick is used once: a later failure is asked again."'
check "rollback: nothing says a rollback can simply be undone" \
  '! printf "%s" "$RB" | gq -iE "rollback (can|could) (always |easily |later )?be (undone|reversed|taken back)|rollback is reversible|undo: (yes|none needed|a rollback can)"'
check "rollback: nothing says the stashed work is put back by the run" \
  '! printf "%s" "$RB" | gq -iE "(rollback|I|this run) (restores?|puts? back|pops?) (your|the) (own |earlier |stashed )?(work|stash)"'
check "rollback: no numbered 1./2. menu and no bare question is left" \
  '! printf "%s" "$RB" | gq -iE "roll back\?|[0-9]\. Roll back all changes"'
check "gate: a rollback point is still made before any change" \
  'has "$RB" "**Before any changes, create a rollback point:**" && has "$RB" "git tag -f pre-fix-it -m \"Snapshot before /fix-it changes\""'
check "gate: one broken fix is reverted on its own, not everything" \
  'has "$RB" "1. Revert the specific fix (not all changes) 2. Move the finding to the MANUAL list 3. Continue with remaining fixes 4. Document the revert reason in the report"'

# 4. SEMI-AUTO fixes: one batched multi-select per step
check "SEMI-AUTO ask: the paragraph was found" '[ -n "$SA" ]'
check "SEMI-AUTO ask: one ask per step for all of that step's SEMI-AUTO fixes, before the step's changes are committed" \
  'has "$SA" "**SEMI-AUTO fixes: one ask per step, after the step'"'"'s fixes are made.** A step that made SEMI-AUTO fixes (Steps 1, 4, 5, 6 and 7) ends with one ask for all of them, before anything from that step is committed."'
check "SEMI-AUTO ask: one multi-select, each fix its own pick, no 'all' option, never one ask per fix" \
  'has "$SA" "It is one multi-select and each fix is its own pick. There is no \"all of them\" option. Never one ask per fix."'
check "SEMI-AUTO ask: each item shows what changes and its diff" \
  'has "$SA" "Each item shows what changes, in plain words, and its diff (the changed lines, not the whole file)."'
check "SEMI-AUTO ask: says the fixes are made but not committed, and asks for picks" \
  'has "$SA" "\"I made [N] fixes in this step that change how your app'"'"'s code works. They are in your files and not committed yet. Pick the ones to keep."'
check "SEMI-AUTO ask: the item form carries the diff" \
  'has "$SA" "- **[Finding title] ([file])** -- [what changes, in plain words] [diff: the changed lines]"'
check "SEMI-AUTO ask: the evidence" \
  'has "$SA" "What I checked: [the tests and checks run after these fixes, and what they showed]."'
check "SEMI-AUTO ask: blast radius and undo" \
  'has "$SA" "What a pick touches: only the lines shown. To take one back later: \`git revert\` its commit."'
check "SEMI-AUTO ask: what is unusual, and the one thing to check" \
  'has "$SA" "What is unusual: [what differs from a routine fix, or \"nothing\"]." && has "$SA" "The one thing to check: [the one behaviour most likely to have changed, such as \"search still returns the same rows\"].\""'
check "SEMI-AUTO ask: an unpicked fix is reverted, goes on the manual list and in the report, and is not asked about again" \
  'has "$SA" "A fix that is not picked is reverted, goes on the manual list and in the report, and is not asked about again in this run."'
check "SEMI-AUTO ask: a dismissed ask keeps nothing" \
  'has "$SA" "If the ask is dismissed or left unanswered, no fix is picked: revert every one of them the same way. Only a picked fix is kept."'
check "SEMI-AUTO ask: a pick is not kept for the next step" \
  'has "$SA" "A pick covers that fix only: the next step'"'"'s fixes are asked in that step'"'"'s own ask."'
check "SEMI-AUTO ask: in Step 7 an unpicked fix is reverted by its commit, and the CRITICAL/HIGH audit fixes are not in the ask" \
  'has "$SA" "In Step 7 each finding is already its own commit, so there the ask comes after the last finding and an unpicked fix is reverted with \`git revert\`; the CRITICAL and HIGH audit fixes are not in it."'
check "SEMI-AUTO ask: no option (a list item led by a bold name) holds the word 'all'" \
  '! between "<step name=\"fix\">" "^</step>" | gq -iE "^ *- \*\*[^*]*\ball\b[^*]*\*\*"'
check "SEMI-AUTO ask: no 'all' pick is offered in any other words" \
  '! printf "%s" "$FIX" | sed "s/There is no \"all of them\" option\.//" | gq -iE "(keep|apply|pick|select|accept|approve) (them )?all\b|all of (them|the above)|\beverything\b[^.]{0,20}\b(option|pick)"'
check "SEMI-AUTO ask: nothing in the fix step asks fix by fix" \
  '! printf "%s" "$FIX" | sed "s/Never one ask per fix\.//" | gq -iE "one ask per fix|(ask|confirm|approve)[^.]{0,60}\b(each|every) fix\b[^.]{0,30}(in turn|one at a time|one by one|separately|before the next)|after each fix[^.]{0,30}\b(ask|confirm)"'
check "SEMI-AUTO ask: nothing keeps or applies fixes on a dismissed ask" \
  '! printf "%s" "$ALL" | gq -iE "(dismissed|unanswered|no answer)[^.]{0,80}\b(keep (them|every|all)|kept|apply|applied|go ahead|proceed)"'
check "SEMI-AUTO ask: nothing raises an unpicked fix again later in the run" \
  '! printf "%s" "$ALL" | gq -iE "(not picked|unpicked)[^.]{0,120}\b(asked|offered|raised) (about )?again (later|at the end|in the report|before)|ask (about )?(it|them) again (later|at the end)"'
check "Step 4 sends its fixes to the one ask" \
  'has "$FIX" "Then this step'"'"'s one SEMI-AUTO ask (above): every fix of the step with its diff, each its own pick."'
check "Step 5 sends its diffs to the one ask" \
  'has "$FIX" "6. Keep its diff for this step'"'"'s one SEMI-AUTO ask (above)"'
check "guardrail 7: SEMI-AUTO fixes are kept only when picked, diff shown in the one ask" \
  'has "$GUARD" "7. **SEMI-AUTO fixes are kept only when picked.** Do not silently apply complex changes. Show each fix'"'"'s diff in its step'"'"'s one SEMI-AUTO ask (Phase 2); a fix that is not picked is reverted and goes on the manual list."'

# 5. the two small asks named with options
check "a risky or ambiguous fix is asked with named options" \
  'has "$PERSONA" "- If a fix is risky or ambiguous, explain the trade-off and ask, with named options to pick from"'
check "an unreadable attestation: two named options, and 'not now' changes nothing" \
  'has "$ERRH" "- Offer two named options: **Run /nemo-it now** -- a fresh scan that writes a new attestation -- or **Not now** -- nothing is changed"'

# 6. every /fix-it gate stays
check "gate: approval before any change" 'has "$TRI" "**Wait for user approval before making any changes.**"'
check "gate: the git strategy is a pick of four named options, with a 'not now'" \
  'has "$TRI" "1. Create a new \`fix-it/[date]\` branch 2. Work on the current branch, one commit for everything 3. Work on the current branch, one commit per fix category 4. Not now -- nothing is changed Pick one.\""'
check "gate: with an audit finding in scope everything goes on a new branch, and the user's uncommitted work is not committed" \
  'has "$TRI" "Uncommitted changes already in the project are left as they are and never committed by this run; if a fix has to touch one of those files, that finding is MANUAL."'
check "gate: the audit branch is never merged, pushed or deleted by the skill" \
  'has "$FIX" "- Never merge the \`fix-it/[date]\` branch, push it, or delete it. Keeping or dropping it is the user'"'"'s call in the report."'
check "gate: keeping or dropping the branch is two named options in the report" \
  'has "$ALL" "- **Keep it:** merge \`fix-it/[date]\` into [original branch] (or pick '"'"'Keep it'"'"' and I will)." && has "$ALL" "- **Drop it:** \`git checkout [original branch]\`. The branch stays, untouched, until you delete it."'
check "gate: the never-do list" \
  'has "$PERSONA" "- Skip verification after applying fixes - Apply a fix that you cannot verify - Silently swallow errors during fix application - Delete code without understanding what it does - Force-push or rewrite git history - Modify test files to make failing tests pass (fix the code, not the tests)"'
for g in \
  '1. **Never fix a finding you do not understand.**' \
  '2. **Verify after every fix category.**' \
  '3. **Preserve existing behavior.**' \
  '4. **Do not modify test files to make tests pass.**' \
  '5. **Respect the user'"'"'s git strategy choice.** Do not commit without permission. Do not create branches without permission.' \
  '6. **Log every change.**' \
  '8. **Major dependency upgrades need verification.**' \
  '9. **Never remove security controls to fix a finding.**' \
  '10. **AI safety wiring must preserve the existing LLM call'"'"'s behavior.**'; do
  check "gate: guardrail ${g%%\*\**}stays" 'has "$GUARD" "$g"'
done
check "gate: a fix that still fails after 3 cycles is reverted and becomes MANUAL" \
  'has "$ALL" "If after 3 cycles verification still fails: - Revert the problematic fix - Move it from AUTO/SEMI-AUTO to MANUAL - Continue with remaining verification"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
