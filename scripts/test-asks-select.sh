#!/usr/bin/env bash
# No make-it skill asks the user to type a confirmation, and a "no" is kept (owner, 2026-11-17; E03-S19).
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
A=.claude/make-it/references/approval-block.md
flat() { tr '\n' ' ' | tr -s ' '; }
has() { if [ "$(flat < "$2" | grep -cF -- "$1")" -gt 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
hasnt() { if [ "$(flat < "$2" | grep -ciE -- "$1")" -eq 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
has 'A select, never typing' "$A" "the shared rules: every ask is a select"
has 'Never ask the user to type a path, a name, a count or a set phrase' "$A" "the shared rules: nothing typed to confirm"
has 'one option per target' "$A" "the shared rules: a high-stakes pick still names the specific"
has 'A "no" or "not now" is kept' "$A" "the shared rules: a no is kept"
has 'A yes to an action is never kept' "$A" "the shared rules: a yes to an action is asked each time"
hasnt 'the human types them' "$A" "the shared rules no longer offer typing"
T=.claude/commands/try-it.md; M=.claude/commands/make-it.md
hasnt "type its name|only its name means go" "$T" "/try-it: stopping another program is a pick, not a typed name"
has '**Stop [PROGRAM]**' "$T" "/try-it: the pick names the program"
has '**Leave it running**' "$T" "/try-it: leaving it alone is offered"
for f in "$T" "$M"; do
  hasnt "tell me which tool you paused|name without how long|plus how long means go" "$f" "$f: pausing a security tool is a pick, with no typed name or time"
  has '**I paused [TOOL]**' "$f" "$f: the pick names the tool"
  has "every one of them must be picked before the build is retried" "$f" "$f: every named tool must be picked"
  has "a plain 'done' or 'ok' is not a pick" "$f" "$f: a plain done is not a pick"
done
D=.claude/commands/demo-it.md
hasnt '\(yes/no\)' "$D" "/demo-it: no bare yes/no before deleting a demo"
has "**Remove {firm_name}'s demo**" "$D" "/demo-it: the pick names the firm"
has 'NEVER skip the confirmation step for teardown' "$D" "/demo-it: the teardown gate stays"
W=.claude/commands/wrap-it.md
hasnt 'have them type the names' "$W" "/wrap-it: nothing typed"
has "'Keep them all' is remembered" "$W" "/wrap-it: 'keep them all' is remembered for copies"
has "ask only about labels that are not on it" "$W" "/wrap-it: and for labels"
exit $fail
