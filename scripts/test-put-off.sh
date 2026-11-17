#!/usr/bin/env bash
# /resume-it remembers a "not now" and never asks the user to type a confirmation (owner, 2026-11-17).
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
R=.claude/commands/resume-it.md
flat() { tr '\n' ' ' | tr -s ' '; }
has() { if [ "$(flat < "$2" | grep -cF -- "$1")" -gt 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
hasnt() { if [ "$(flat < "$2" | grep -ciE -- "$1")" -eq 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
has '## Put off by your choice' "$R" "resume-it defines the put-off record"
has 'Never asked or suggested again' "$R" "a put-off offer is not raised again"
has 'It approves nothing' "$R" "a put-off line never lets a change through"
has 'asked about the new items only' "$R" "a changed group is asked about its new items only"
has 'Every ask in this skill is a select' "$R" "asks are selects"
hasnt 'type exactly|tell me the number|exact phrase' "$R" "no typed confirmation is left in resume-it"
for f in "$R" .claude/commands/wrap-it.md; do
  has 'Put off by your choice -- if the file has this section now, keep it exactly as it is' "$f" "$f keeps the section when it rewrites the state file"
done
has 'Put off by your choice' .claude/make-it/references/learnings.md "a declined learning is remembered"
exit $fail
