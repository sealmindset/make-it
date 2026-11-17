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
hasnt "type exactly|tell me the number|exact phrase|(^|[^a-z])type '|to replace it anyway, type" "$R" "no typed confirmation is left in resume-it"
has 'it never lets a change through' "$R" "the record never lets a change through, in those words"
has "goes under \`## Put off by your choice\` instead, naming its items" "$R" "a catch-up group the user did not pick is written to the record"
has "On 'Not now' or 'Keep what I have', write the put-off line" "$R" "the prompt-management upgrade writes the record"
has 'name them in one line here' "$R" "must-do updates put off are named before the hand-off to ship"
has 'Must-do updates among them are named on that line every session' "$R" "must-do updates put off are named in every status"
hasnt 'passes over to pick something else twice' "$R" "passing over a suggestion is not a refusal"
for f in "$R" .claude/commands/wrap-it.md; do
  has 'Put off by your choice -- if the file has this section now, keep it exactly as it is' "$f" "$f keeps the section when it rewrites the state file"
done
has 'Put off by your choice' .claude/make-it/references/learnings.md "a declined learning is remembered"
exit $fail
