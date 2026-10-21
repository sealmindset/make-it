#!/usr/bin/env bash
# E02-S6: make-it's ship hand-off never switches AI billing on its own -- the user picks the mode by name.
# Contract these checks pin (the change must satisfy it):
#   - The claude_agent paragraph of the ship-handoff step is a high-stakes ask (approval-block.md): who pays and how,
#     the evidence, the undo, what's unusual, the one thing to check; three options picked by name; a plain yes is not a pick.
#   - Nothing switches before the pick: every switch instruction comes after "Wait for their pick".
#   - The personal CLAUDE_CODE_OAUTH_TOKEN warning stays.
#   - No skill, reference or template tells an agent to flip the provider on ship; each place that states the
#     ship-time switch names the pick.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT
flat() { tr '\n' ' ' | tr -s ' '; }

MK=.claude/commands/make-it.md
# the claude_agent paragraph of the ship-handoff step (up to the next paragraph, the missing-prerequisites one)
BLK="$(awk '/^<step name="ship-handoff">/{s=1} s&&/^\*\*If the app uses the claude_agent provider/{on=1} on&&/^\*\*If prerequisites are missing/{on=0} on' $MK)"
F="$(printf "%s\n" "$BLK" | flat)"
check "ship-handoff has the claude_agent paragraph" '[ -n "$BLK" ]'
# the words the user sees: the first quoted span before the wait for the pick (the post-pick steps repeat option names)
PRE="${F%%\*\*Wait for their pick.\*\**}"
ASK="$(printf "%s" "$PRE" | sed -nE 's/^[^"]*"([^"]*)".*/\1/p')"
check "the ask the user sees comes before the wait and asks them to pick by name" 'printf "%s" "$ASK" | gq -F "Pick one by name"'

# 1. it asks before switching, as a high-stakes ask
check "the paragraph is a high-stakes ask per the approval block" 'printf "%s" "$F" | gq -iE "high-stakes[^.]*approval block"'
check "the paragraph waits for the pick" 'printf "%s" "$F" | gq -F "**Wait for their pick.**"'

# 2. the user picks the option by name; a plain yes is not a pick
for o in "Use an Anthropic API key (pay per use)" "Use my organization's provider" "Keep it local, don't ship to others yet"; do
  check "option offered by name in the ask: $o" 'printf "%s" "$ASK" | gq -F "**$o**"'
done
check "a plain yes is not a pick (and nowhere counts as one)" \
  'printf "%s" "$F" | gq -iE "plain \"?yes\"?[^.]*is not a pick" && ! printf "%s" "$F" | gq -iE "plain \"?yes\"?[^.]*(is|counts as) (a pick|an answer|fine|enough)"'

# 3. the ask is decision-ready: who pays and how, the evidence, the undo, what is unusual, the one thing to check
check "the ask names who pays and how: per use on an API key, or the organization's account" \
  'printf "%s" "$ASK" | gq -iE "who pays" && printf "%s" "$ASK" | gq -iE "billed per use" && printf "%s" "$ASK" | gq -iE "organization.s account"'
check "the ask gives the evidence: the subscription setting it saw, and that it is single-user" \
  'printf "%s" "$ASK" | gq -F "AI_PROVIDER=claude_agent" && printf "%s" "$ASK" | gq -iE "just for you[^.]*can.t be (shared|given) "'
check "the ask names the undo: the one-line switch back, and billed use can't be taken back" \
  'printf "%s" "$ASK" | gq -iE "undo:[^.]*AI_PROVIDER=claude_agent" && printf "%s" "$ASK" | gq -iE "already billed can.t be taken back"'
check "the ask names what is unusual" 'printf "%s" "$ASK" | gq -iE "what.s unusual:"'
check "the ask names the one thing to check" 'printf "%s" "$ASK" | gq -iE "the one thing to check:"'

# 4. nothing switches before the pick: the wait comes before every switch instruction, and "keep it local" changes nothing
# byte offsets in the flat paragraph; a switch instruction is a verb on the setting, or the new value itself
w="$(printf "%s" "$F" | grep -obF "**Wait for their pick.**" | head -1 | cut -d: -f1 || true)"
s="$(printf "%s" "$F" | grep -obE "(set|flip|switch|change)[a-z ]{0,12}(ai_providers\.primary|AI_PROVIDER)|AI_PROVIDER=anthropic" | head -1 | cut -d: -f1 || true)"
check "every switch instruction comes after the wait for the pick" '[ -n "$w" ] && [ -n "$s" ] && [ "$w" -lt "$s" ]'
check "it says nothing switches before the pick" 'printf "%s" "$F" | gq -iE "nothing switches (before|until) (the|their) pick"'
check "keep it local changes nothing" 'printf "%s" "$F" | gq -iE "\*\*Keep it local[^*]*\*\* -> change nothing"'

# 5. the personal-token warning stays
check "the token warning stays: never commit or ship the personal token; only in .env (gitignored)" \
  'printf "%s" "$F" | gq -F "NEVER to commit or ship their personal CLAUDE_CODE_OAUTH_TOKEN" && printf "%s" "$F" | gq -F "only in .env (gitignored)"'

# 6. no other place makes the same switch without asking
check "no skill, reference or template tells an agent to flip the AI provider" \
  '! grep -rniE "\bflip" .claude/commands .claude/make-it/references .claude/make-it/templates | gq -iE "claude_agent|anthropic|provider"'
check "ship-it-guide: no 'should switch off claude_agent'" '! gq -iE "should switch off claude_agent" .claude/make-it/references/ship-it-guide.md'
DESIGN="$(awk '/AI Provider \(PRINCIPLE/{on=1} /AI Prompt Management: Classify/{on=0} on' $MK | flat)"
check "make-it Design: the ship-time switch names the pick" 'printf "%s" "$DESIGN" | gq -F "picks the billing mode by name"'
for f in .claude/make-it/references/ship-it-guide.md .claude/make-it/references/guardrails.md \
         .claude/make-it/references/design-blueprint.md .claude/make-it/references/build-standards.md \
         .claude/make-it/templates/app-context.md; do
  check "$f: the ship-time switch names the pick" 'flat < $f | gq -iE "picks the billing mode by name"'
done

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
