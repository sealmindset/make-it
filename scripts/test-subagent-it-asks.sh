#!/usr/bin/env bash
# E03-S9: /subagent-it asks through the approval block -- fewer asks, same gates.
# Contract these checks pin (.claude/commands/subagent-it.md, as the /subagent-it agent reads it):
#   - approval-block.md is @-imported exactly once, inside <execution_context>; no bare yes/no ask, no typed confirmation.
#   - Routine: no check-in between tasks; a clean pre-flight proceeds silently.
#   - Consequential: pre-flight findings are ONE batched question; learnings are one message answered per item;
#     every ask is written to the ledger first and is readable cold (named answers, a high-stakes item never batched).
#   - Every stop for the human stays: a draft plan, a disclosed safeguard weakening the plan didn't decide, the same root
#     cause three rounds running, an ungrounded or plan-conflicting counterexample, open round-3 counterexamples.
#   - Every gate stays: never main/master, sequential only, the Stop hook, the red check, tests untouched and green,
#     all three verdicts, an undisclosed weakening undone, the final review.
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

F=.claude/commands/subagent-it.md
LINK='@~/.claude/make-it/references/approval-block.md'
flat() { tr '\n' ' ' | tr -s ' '; }
CTX="$(awk '/^<execution_context>/{on=1} /^<\/execution_context>/{on=0} on' "$F")"
HEAD="$(awk 'NR>1 && /^---$/{exit} {print}' "$F")"
ALL="$(flat < "$F")"
# has "<name>" "<exact sentence>": the sentence is in the skill, line wraps ignored
has() { WANT="$2"; check "$1" 'printf "%s" "$ALL" | gq -F -- "$WANT"'; }

# 1. the block is linked once, in <execution_context>, as the other skills link it
check "approval-block.md is @-imported exactly once" '[ "$(grep -cF -- "$LINK" "$F")" = 1 ]'
check "that one import is inside <execution_context>" 'printf "%s\n" "$CTX" | gq -xF -- "$LINK"'

# 2. no bare yes/no ask, no typed confirmation, and the select tool is allowed
check "grep -niE '\\(y/n\\)|y/n\\b|yes/no' prints nothing" '[ "$(grep -ciE "\(y/n\)|y/n\b|yes/no" "$F")" = 0 ]'
check "no ask to type something to confirm" \
  '! printf "%s" "$ALL" | gq -iE "\b(type|types|typing|typed)\b[^.]{0,60}\b(confirm|name|count|phrase|path)"'
check "AskUserQuestion is an allowed tool (asks are selects)" 'printf "%s\n" "$HEAD" | gq -xF -- "  - AskUserQuestion"'

# 3. routine: no check-in between tasks; a clean pre-flight says nothing
has "no pause to check in between tasks" "Don't pause to check in between tasks — run the whole plan;"
has "it stops only for a block, a blocking ambiguity, or completion" \
  "stop only for an unresolvable BLOCKED, genuine blocking ambiguity, or completion."
has "a clean pre-flight proceeds silently" "Clean → proceed silently."

# 4. consequential: batched, readable cold, written down first
has "pre-flight findings are one batched question, finding beside plan text" \
  'present all findings as ONE batched question (finding beside plan text, "which governs?").'
has "the ledger line is written before the user is asked anything" "write AWAITING_HUMAN before asking the user anything"
has "an ask is readable cold: title, what waits, named answers; high-stakes never batched" \
  'ask it readable cold: its title, what waits and why, 2-4 named answers, a batch as one grouped line, a high-stakes item never batched (`approval-block.md`, A list of asks).'
has "learnings are offered only after the run is done" 'after `STATUS: DONE`, offer learnings'
has "learnings: one message, evidence per item, the user answers per item" \
  "one message, each numbered with its evidence and what it would change; the user answers per item."

# 5. every stop for the human stays
has "a draft plan is not approved: the user's go comes first" \
  "isn't approved: get the user's go, then mark it \`status: approved\`"
has "a disclosed weakening the plan didn't decide is the human's call; an undisclosed one is undone" \
  "an undisclosed weakening is undone; a disclosed one is undone too, unless that changes behavior the plan didn't decide -- then the human's call;"
has "the same root cause three rounds running stops for a decision-ready design choice" \
  'three consecutive rounds on the same root cause: stop patching and write `STATUS: AWAITING_HUMAN` with a decision-ready design choice'
has "an ungrounded or plan-conflicting counterexample goes to the human" "(ungrounded or plan-conflicting → the human; unsure severity → Important)"
has "open round-3 counterexamples stop for the human, and are not fixed" \
  "round 3's are not fixed -- open Critical/Important → \`STATUS: AWAITING_HUMAN\`, Minor only → accept and log;"
has "the human's answer doesn't reset the round count" "after the human answers, the count doesn't reset"

# 6. every gate stays
has "never works on main/master" "branch/worktree, never main/master.**"
has "implementers never run in parallel" "**Sequential only** — never run implementers in parallel"
has "it needs an approved plan" "**Needs an approved plan as input**"
has "the Stop hook refuses to let the run end without a STATUS line" \
  'then refuses to let the run end until you append `STATUS: DONE | BLOCKED <why> | AWAITING_HUMAN <what>`'
has "red check: the tests must fail first" "run its tests, they must fail for the missing behavior"
has "the implementer may not change the tests" "it may not change the tests;"
has "tests untouched and green, run by the coordinator, none skipped" \
  "you run them yourself, all passing, none skipped (again after every fix)"
has "the fix loop runs until all three verdicts are clean" \
  "fix-subagent loop for Critical/Important until spec ✅, quality approved, and safeguards ✅"
has "all three verdicts required; a re-review is never skipped" \
  "All three verdicts (spec, quality, safeguards) are required; never skip a re-review."
has "an undisclosed weakened safeguard is undone, never kept" \
  'undisclosed weakened safeguard is undone, never kept (`approval-block.md`).'
has "findings are never pre-judged" "Never pre-judge findings or tell a reviewer what not to flag."
has "the final whole-branch review runs on the most capable model" \
  '**Final review** — `/code-review` on the most capable model'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
