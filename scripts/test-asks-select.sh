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
# the rules themselves, not only their headings (second review, 2026-11-17: nine mutants survived)
has 'A stop, a failed check, a security finding or a gate is never put off' "$A" "a security stop or a gate can never be put off"
has 'is asked again whenever that step is blocked again' "$A" "an ask a blocked step needs comes back when it is blocked again"
has "don't raise it again unless the user asks or what it covers has changed" "$A" "a kept no comes back when the user asks or it changed"
has 'A skill that rewrites that file keeps the section' "$A" "the kept answers survive a rewrite of the state file"
has 'Free text is only for information you can' "$A" "free text is only for information"
has 'a paused security tool is asked each time it comes up' "$A" "a yes to pausing a security tool is never kept"
has 'No "all of them" option' "$A" "several targets are never one pick"
hasnt 'states or picks the specific' "$A" "the tier table no longer offers stating"
has 'Only "Stop [PROGRAM]" means go: stop that one process ([PID]), nothing else' "$T" "/try-it: only that pick, and only that one process"
for f in "$T" "$M"; do
  has 'Do NOT retry Docker builds while the tool is active' "$f" "$f: no retry while the tool is still on"
  has 'then it is a stop' "$f" "$f: 'not sure' beside 'I paused' is a stop"
  hasnt "don't have one'" "$f" "$f: the old option name is gone"
done
has "If they pick \"Remove {firm_name}'s demo\":" "$D" "/demo-it: teardown runs only on that pick"
has 'kept in an archive for 90 days' "$D" "/demo-it: the ask states the real undo"
has "write one line naming them under" "$W" "/wrap-it: the kept answer is written down"
hasnt "name them, or say|picks or names each|counts only with the number" "$W" "/wrap-it: no typed names or counts"
for f in .claude/commands/fix-it.md .claude/commands/demo-it.md; do
  has 'approval-block.md' "$f" "$f reads the shared rules"
done
hasnt 'Ready to proceed\?"' .claude/commands/fix-it.md "/fix-it: no bare 'ready to proceed?'"
hasnt 'picks or types' .claude/make-it/references/backlog-board.md "the board's gates are picks, not typing"
# the same stop twice (the owner's brief, rule 4), and the last named-answer asks
has "The same stop twice is make-it's fault, and is said so" "$A" "a repeated stop is reported as make-it's fault"
has 'a repeat never turns a stop into a go' "$A" "a repeated stop stays stopped"
has 'this never applies to approving an action' "$A" "a repeated approval of an action is still asked"
hasnt '\(name the files\)|names which files|names what to move' .claude/commands/argo-it.md "/argo-it: files and secrets are picked, not named"
has 'a second select with one option per file' .claude/commands/argo-it.md "/argo-it: replacing some files is one pick per file"
hasnt 'by item number' .claude/commands/retrofit-it.md "/retrofit-it: items are picked from the list"
exit $fail
