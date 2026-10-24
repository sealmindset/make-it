#!/usr/bin/env bash
# E02-S6: the ship hand-off never switches AI billing on its own -- the user picks the mode by name.
# Contract these checks pin (the change must satisfy it):
#   - The billing ask lives once, in ship-it-guide.md (which /make-it, /resume-it and /retrofit-it all load); each
#     skill's ship-handoff step points at it and doesn't restate it.
#   - It is a high-stakes ask (approval-block.md): who pays and how, the evidence, the undo, what's unusual, the one
#     thing to check; three options picked by name; a plain yes is not a pick; no bare (y/n).
#   - Nothing switches before the pick. "Keep it local" switches nothing and records the open question in
#     .make-it-state.md under "## Before sharing", a section /resume-it and /wrap-it keep.
#   - After a key pick, app-context.json and .env.example change; the builder's own .env stays claude_agent; the key
#     and AI_PROVIDER go where the shared app runs (their DevOps team or hosting settings); they're told what changed.
#   - The personal CLAUDE_CODE_OAUTH_TOKEN warning stays.
#   - No skill, reference or template tells an agent to switch the provider on ship without the pick.
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

# A switch instruction, two ways: a verb on the setting or a paid provider's value, in any case (SWI); or a switch
# verb, then a paid provider's name, in the same sentence (SW: a dot inside a name like .env doesn't end it).
SWI="(set|flip|switch|change|move|write|update)[a-z ]{0,12}(ai_providers\.primary|AI_PROVIDER)|AI_PROVIDER=(anthropic|openai|ollama)"
SW='\b([Ss]et|[Ff]lip|[Ss]witch|[Cc]hange|[Mm]ove|[Mm]oving|[Mm]oved|[Ww]rite|[Uu]pdate)(s|es|ed|ing)?\b([^.]|\.[^ ]){0,40}(anthropic|enterprise|openai|ollama)'
switch_lines() { local t; t="$(cat)"; printf "%s\n" "$t" | grep -iE "$SWI" || true; printf "%s\n" "$t" | grep -iE "$SW" || true; }
switches() { [ -n "$(switch_lines)" ]; }

GUIDE=.claude/make-it/references/ship-it-guide.md
# the billing ask: the "### The billing ask" section of the guide, up to the next heading
BLK="$(awk '/^### The billing ask/{on=1;next} on&&/^##/{exit} on' $GUIDE)"
F="$(printf "%s\n" "$BLK" | flat)"
check "ship-it-guide has the billing ask section, for an app on the claude_agent provider" \
  '[ -n "$BLK" ] && printf "%s" "$F" | gq -F "**If the app uses the claude_agent provider"'
check "the billing ask comes first at every ship hand-off: /make-it, /resume-it and /retrofit-it" \
  'printf "%s" "$F" | gq -iE "/make-it, /resume-it and /retrofit-it[^.]*first"'
# the words the user sees: the first quoted span before the wait for the pick (the post-pick steps repeat option names)
PRE="${F%%\*\*Wait for their pick.\*\**}"
POST="${F#*\*\*Wait for their pick.\*\*}"
ASK="$(printf "%s" "$PRE" | sed -nE 's/^[^"]*"([^"]*)".*/\1/p')"
check "the ask the user sees comes before the wait and asks them to pick by name" 'printf "%s" "$ASK" | gq -F "Pick one by name"'

# 1. one ask, every hand-off reaches it: each skill's ship-handoff points at the guide's ask and doesn't restate it
step() { awk '/^<step name="ship-handoff">/{on=1} on; on&&/^<\/step>/{exit}' "$1" | flat; }
for f in .claude/commands/make-it.md .claude/commands/resume-it.md .claude/commands/retrofit-it.md; do
  check "$f ship-handoff: the billing ask in ship-it-guide.md comes first" \
    'step $f | gq -iE "claude_agent provider[^.]*billing ask in ship-it-guide\.md comes first"'
  # the pointer sits before the hand-off's go-live text (its first **/ship-it**), and the skill loads the guide
  check "$f ship-handoff: the pointer comes before the first **/ship-it**, and the skill loads ship-it-guide.md" \
    'p="$(step $f | grep -obF "billing ask in ship-it-guide.md comes first" | head -1 | cut -d: -f1 || true)"
     g="$(step $f | grep -obF "**/ship-it**" | head -1 | cut -d: -f1 || true)"
     [ -n "$p" ] && [ -n "$g" ] && [ "$p" -lt "$g" ] && gq -xF "@~/.claude/make-it/references/ship-it-guide.md" $f'
done
check "make-it ship-handoff doesn't restate the ask or switch anything itself" \
  '[ -n "$(step .claude/commands/make-it.md)" ] && ! step .claude/commands/make-it.md | gq -F "Pick one by name" && ! step .claude/commands/make-it.md | switches'

# 2. it asks before switching, as a high-stakes ask
check "the paragraph is a high-stakes ask per the approval block" 'printf "%s" "$F" | gq -iE "high-stakes[^.]*approval block"'
check "the paragraph waits for the pick" 'printf "%s" "$F" | gq -F "**Wait for their pick.**"'

# 3. the user picks the option by name; a plain yes is not a pick; no bare (y/n)
for o in "Use an Anthropic API key (pay per use)" "Use my organization's provider" "Keep it local, don't ship to others yet"; do
  check "option offered by name in the ask: $o" 'printf "%s" "$ASK" | gq -F "**$o**"'
done
check "a plain yes is not a pick (and nowhere counts as one)" \
  'printf "%s" "$F" | gq -iE "plain \"?yes\"?[^.]*is not a pick" && ! printf "%s" "$F" | gq -iE "plain \"?yes\"?[^.]*(is|counts as) (a pick|an answer|fine|enough)"'
check "no bare y/n or 'OK to proceed?' anywhere in the billing ask" \
  '! printf "%s" "$F" | gq -iE "y/n|ok to (proceed|continue|switch)\?"'

# 4. the ask is decision-ready: who pays and how, the evidence, the undo, what is unusual, the one thing to check
check "the ask names who pays and how: per use on an API key, or the organization's account" \
  'printf "%s" "$ASK" | gq -iE "who pays" && printf "%s" "$ASK" | gq -iE "billed per use" && printf "%s" "$ASK" | gq -iE "organization.s account"'
check "the ask says the copy on this computer stays on the subscription either way" \
  'printf "%s" "$ASK" | gq -iE "your copy on this computer stays on your subscription either way"'
check "the ask names a way to cap the cost: a monthly limit in the provider's account settings, where it offers one" \
  'printf "%s" "$ASK" | gq -iE "to cap the cost[^.]*monthly limit in the provider.s account settings, where it offers one"'
check "the ask gives the evidence: the subscription setting it saw, in plain words, and that it is single-user" \
  'printf "%s" "$ASK" | gq -F "AI_PROVIDER=claude_agent" && printf "%s" "$ASK" | gq -F "your settings file (.env)" && printf "%s" "$ASK" | gq -iE "just for you[^.]*can.t be (shared|given) "'
check "the ask names the undo: switching back changes the same places again, deleting the key stops the charges, billed use can't be taken back" \
  'printf "%s" "$ASK" | gq -iE "undo: switching back means changing the same places again" && printf "%s" "$ASK" | gq -iE "deleting the key is what stops the charges" && printf "%s" "$ASK" | gq -iE "already billed can.t be taken back"'
check "the undo says who deletes the key for the organization pick: their IT team" \
  'printf "%s" "$ASK" | gq -iE "deleting the key is what stops the charges[^.]*organization.s provider[^.]*IT team removes it"'
check "the ask says who puts the key where the shared app runs: their DevOps team, or their hosting settings" \
  'printf "%s" "$ASK" | gq -iE "where the shared app runs[^.]*DevOps team[^.]*hosting settings"'
check "the ask names what is unusual" 'printf "%s" "$ASK" | gq -iE "what.s unusual:"'
check "the ask names the one thing to check" 'printf "%s" "$ASK" | gq -iE "the one thing to check:"'

# 5. nothing switches before the pick: the wait comes before every switch instruction, and "keep it local" changes nothing
# byte offsets in the flat paragraph: the first switch instruction of either kind
w="$(printf "%s" "$F" | grep -obF "**Wait for their pick.**" | head -1 | cut -d: -f1 || true)"
s="$({ printf "%s" "$F" | grep -obiE "$SWI" || true; printf "%s" "$F" | grep -obiE "$SW" || true; } | cut -d: -f1 | sort -n | head -1)"
check "every switch instruction comes after the wait for the pick" '[ -n "$w" ] && [ -n "$s" ] && [ "$w" -lt "$s" ]'
check "it says nothing switches before the pick" 'printf "%s" "$F" | gq -iE "nothing switches (before|until) (the|their) pick"'
check "keep it local changes nothing" 'printf "%s" "$F" | gq -iE "\*\*Keep it local[^*]*\*\* -> change nothing"'
k='**Keep it local, don'"'"'t ship to others yet** ->'
KEEP="${POST#*"$k"}"; KEEP="${KEEP%%Whatever they pick*}"
check "the keep-it-local branch switches nothing" '[ "$KEEP" != "$POST" ] && ! printf "%s" "$KEEP" | switches'
check "keep it local: /ship-it save backs up to GitHub as a draft, without putting the app live for anyone" \
  'printf "%s" "$KEEP" | gq -iE "/ship-it save\` backs up their work to GitHub as a draft, without putting the app live for anyone" && ! printf "%s" "$F" | gq -iE "without sharing it"'
check "keep it local records the open question in .make-it-state.md, under Before sharing" \
  'printf "%s" "$KEEP" | gq -F ".make-it-state.md" && printf "%s" "$KEEP" | gq -F "## Before sharing"'
check "a pick of a way to pay takes that line out, outside the keep-it-local branch" \
  'A="${POST#*Whatever they pick}"; [ "$A" != "$POST" ] && printf "%s" "$A" | gq -iE "when they pick a way to pay[^.]*take the \`- Open: who pays for the AI\` line out of \`## Before sharing\`"'
for f in .claude/commands/resume-it.md .claude/commands/wrap-it.md; do
  check "$f save-state keeps the Before sharing section as it is" 'flat < $f | gq -iE "## Before sharing[^]]*keep it exactly as it is"'
done

# 6. where the switch lands: the project's files, not the builder's own .env; the key goes where the shared app runs
check "API-key pick: ai_providers.primary in app-context.json, AI_PROVIDER in .env.example" \
  'printf "%s" "$POST" | gq -F "set ai_providers.primary to \"anthropic\" in app-context.json and \`AI_PROVIDER=anthropic\` in \`.env.example\`"'
check "API-key pick: their own .env stays claude_agent" \
  'printf "%s" "$POST" | gq -F "Leave their own \`.env\` alone: it stays \`AI_PROVIDER=claude_agent\`"'
check "after the pick, no switch sentence lands in the builder's own .env" \
  '! printf "%s" "$POST" | sed "s/\([.!?]\) /\1\n/g" | switch_lines | gq -E "(\`|[ ])\.env(\`|[ ,;:]|\.$|$)"'
check "API-key pick: they're told which files changed, and the key and AI_PROVIDER go where the shared app runs, never committed" \
  'printf "%s" "$POST" | gq -iE "tell them in one line which files changed" && printf "%s" "$POST" | gq -iE "where the shared app runs[^.]*(DevOps team|hosting settings)[^.]*never in a committed file"'

# 7. the personal-token warning stays
check "the token warning stays: never commit or ship the personal token; only in .env (gitignored)" \
  'printf "%s" "$F" | gq -F "NEVER to commit or ship their personal CLAUDE_CODE_OAUTH_TOKEN" && printf "%s" "$F" | gq -F "only in .env (gitignored)"'

# 8. no other place makes the same switch without asking
check "no skill, reference or template tells an agent to flip the AI provider" \
  '! grep -rniE "\bflip" .claude/commands .claude/make-it/references .claude/make-it/templates | gq -iE "claude_agent|anthropic|provider"'
# every sentence outside the billing ask that switches to a paid provider names the pick
OFF="$(for f in $(git ls-files '.claude/commands/*.md' '.claude/make-it/references/*.md' '.claude/make-it/templates/*.md' 'desktop/skills/*.md'); do
  if [ "$f" = "$GUIDE" ]; then awk '/^### The billing ask/{on=1;next} on&&/^##/{on=0} !on' "$f"; else cat "$f"; fi | flat \
    | sed 's/\([.!?]\) /\1\n/g' | { grep -E "$SW" || true; } | { grep -viE "picks? the billing mode|billing ask" || true; } | sed "s|^|$f: |"
done)"
check "no sentence anywhere else switches to a paid provider without the pick" '[ -z "$OFF" ] || { printf "%s\n" "$OFF" | cut -c1-200 | sed "s/^/  /"; false; }'
check "ship-it-guide: no 'should switch off claude_agent'" '! gq -iE "should switch off claude_agent" $GUIDE'
DESIGN="$(awk '/AI Provider \(PRINCIPLE/{on=1} /AI Prompt Management: Classify/{on=0} on' .claude/commands/make-it.md | flat)"
check "make-it Design: the ship-time switch names the pick" 'printf "%s" "$DESIGN" | gq -F "picks the billing mode by name"'
for f in $GUIDE .claude/make-it/references/guardrails.md \
         .claude/make-it/references/design-blueprint.md .claude/make-it/references/build-standards.md \
         .claude/make-it/templates/app-context.md; do
  check "$f: the ship-time switch names the pick" 'flat < $f | gq -iE "picks the billing mode by name"'
done

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
