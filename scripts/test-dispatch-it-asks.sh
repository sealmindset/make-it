#!/usr/bin/env bash
# E03-S14: /dispatch-it asks through the approval block -- fewer asks, same gates.
# Contract these checks pin (.claude/commands/dispatch-it.md and references/parallel-dispatch.md, as the agent reads them):
#   - approval-block.md is @-linked exactly once, inside <execution_context>; no bare yes/no ask is left.
#   - The skill has no stop-and-wait ask: picking each lane's persona asks nothing, and nothing else waits on the user.
#   - What the lanes leave for the human is ONE list in the approval block's short form (readable cold, 2-4 named
#     answers, a batch as one line, a high-stakes item never batched) -- in the skill and in the reference.
#   - Every gate stays: related failures are not dispatched, writers are isolated in worktrees, board lanes are capped
#     and never take a critical card, every lane returns a SAFEGUARDS line, the full suite and the safeguards match run
#     before integrating, an undisclosed weakening rejects the lane and a second one goes to the human.
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

F=.claude/commands/dispatch-it.md
R=.claude/make-it/references/parallel-dispatch.md
LINK='@~/.claude/make-it/references/approval-block.md'
flat() { tr '\n' ' ' | tr -s ' '; }
# text of file $3 between the first line matching $1 and the next line matching $2 (start line included)
between() { awk -v a="$1" -v b="$2" 'on && $0 ~ b {exit} $0 ~ a {on=1} on' "$3"; }

CTX="$(between '^<execution_context>' '^</execution_context>' "$F")"
PERSONA="$(between '^<expert_persona>' '^</expert_persona>' "$F" | flat)"
S1="$(between '^## Step 1 ' '^## Step 2 ' "$F" | flat)"
S2="$(between '^## Step 2 ' '^## Step 3 ' "$F" | flat)"
S3="$(between '^## Step 3 ' '^## Step 4 ' "$F" | flat)"
S4="$(between '^## Step 4 ' '^## Step 5 ' "$F" | flat)"
S6="$(between '^## Step 6 ' '^---' "$F" | flat)"
RPAT="$(between '^## The pattern' '^---' "$R" | flat)"
RVER="$(between '^## Verification' '^## zzz' "$R" | flat)"
ALL="$(flat < "$F")"
# the short form of a list of asks, as approval-block.md ("A list of asks") gives it
LIST='in one list, each item readable cold: its title, what waits and why, 2-4 named answers, a batch as one grouped line, a high-stakes item never batched (`approval-block.md`, A list of asks)'

# 1. the block is linked once, in <execution_context>, as the other skills link it
check "the approval-block.md @-import appears exactly once in dispatch-it.md" '[ "$(grep -cF "$LINK" "$F")" = 1 ]'
check "that one link is inside <execution_context>" 'printf "%s\n" "$CTX" | gq -xF "$LINK"'

# 2. no bare yes/no ask, in the skill or its doctrine
for f in "$F" "$R"; do
  check "grep -niE '\\(y/n\\)|y/n\\b|yes/no' prints nothing on $f" '[ "$(grep -ciE "\(y/n\)|y/n\b|yes/no" "$f")" = 0 ]'
done

# 3. no stop-and-wait ask: the skill never waits on the user before it dispatches or integrates
check "picking each lane's persona asks the user nothing" 'printf "%s" "$PERSONA" | gq -F "No user prompt."'
for f in "$F" "$R"; do
  check "no instruction in $f waits on the user (ask / confirm with / wait for / an offer)" \
    '! flat < "$f" | gq -iE "(want me to|should I|shall I|ok to proceed|okay to|do you want)[^?]{0,80}\?|\b(ask|confirm with|check with|wait for) (the )?(user|human|owner)\b|wait for (approval|confirmation|an answer)"'
done

# 4. what the lanes leave for the human: one list, the approval block's short form
check "Step 6 was found" '[ -n "$S6" ]'
check "Step 6: what the lanes leave for the human goes in one list, in the block's short form" \
  'printf "%s" "$S6" | gq -F "What the lanes leave for the human goes $LIST"'
check "the reference says the same, and never passes a lane's ids or shorthand on as-is" \
  'printf "%s" "$RPAT" | gq -F "What the lanes leave for the human goes $LIST -- never a lane'"'"'s ids or shorthand passed on as-is."'

# 5. every gate stays
check "gate: related failures are not dispatched -- the shared cause is found first" \
  'printf "%s" "$S1" | gq -F "Do NOT dispatch when:" && printf "%s" "$S1" | gq -F "**Failures are related** — fixing one may fix others. Find the shared cause first (\`/debug-it\`)."'
check "gate: unknown or full-system problems are not dispatched; unsure means investigate first" \
  'printf "%s" "$S1" | gq -F "**You don'"'"'t yet know what'"'"'s broken** — scout first, then dispatch." && printf "%s" "$S1" | gq -F "**You need full-system context**" && printf "%s" "$S1" | gq -F "If unsure the problems are independent, they probably aren'"'"'t — investigate before fanning out."'
check "gate: board lanes share no files or data, are capped, and never take a critical card" \
  'printf "%s" "$S2" | gq -F "no shared files or data between lanes, at most \`lane_cap\` lanes (default 3), one lane per \`serial\` category, never a \`stakes: critical\` card."'
check "gate: isolation is the safety gate -- every writer gets its own worktree" \
  'printf "%s" "$S3" | gq -F "## Step 3 -- Decide isolation (the safety gate)" && printf "%s" "$S3" | gq -F "**Writers** (agents edit files) → give each its own git worktree so they can'"'"'t collide"'
check "gate: every lane's prompt asks for the SAFEGUARDS line and says what NOT to touch" \
  'printf "%s" "$S4" | gq -F "root cause + exact changes + the SAFEGUARDS line from \`approval-block.md\`" && printf "%s" "$S4" | gq -F "what NOT to touch"'
check "gate: conflicts, the FULL suite, a spot-check and the safeguards match all come before integrating" \
  'printf "%s" "$S6" | gq -E "check for conflicts \(same file touched twice\?\) → run the FULL test suite → spot-check \(agents make systematic errors\) → match every weakened safeguard in each lane.s diff to its SAFEGUARDS line \(Verification step 5 in the reference\)\. Then integrate\."'
check "gate (reference): a weakening on no SAFEGUARDS line rejects the lane; hidden again goes to the human" \
  'printf "%s" "$RVER" | gq -F "One on no line rejects the lane: undo it and re-run the lane once with the finding in its prompt; hidden again → the human."'
check "gate (reference): a disclosed weakening goes in the summary for the human" \
  'printf "%s" "$RVER" | gq -F "A disclosed one goes in your summary for the human."'
check "gate (reference): every agent prompt ends with the SAFEGUARDS line; undisclosed is a rejected lane" \
  'flat < "$R" | gq -F "Every agent prompt ends with that **SAFEGUARDS** line (\`approval-block.md\`): disclosed is not approved, but undisclosed is a rejected lane."'
check "the doctrine is still always loaded" 'gq -xF "@~/.claude/make-it/references/parallel-dispatch.md" "$F"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
