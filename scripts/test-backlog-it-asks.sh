#!/usr/bin/env bash
# E03-S7: /backlog-it asks through the approval block -- fewer asks, same gates.
# Contract these checks pin:
#   - backlog-it.md @-imports approval-block.md exactly once, inside <execution_context>.
#   - No bare yes/no ask in the skill or its reference (the E03-S5 grep).
#   - Every gate survives, checked by meaning: start runs only on the user's go and stays an edit
#     step; a high-stakes card is never auto-started or dispatched and start leads with the
#     alignment brief, then waits for an explicit go; drafts never run without the go; groom's
#     splits, deferrals and kills stay proposals; capture is card first; a blocking question goes
#     on the card as decision: + answers:; the green gate and the harm gate; shipping stays serial.
#   - Interview questions (clarify, capture) are untouched.
#   - Consequential asks are decision-ready (what changes, evidence, undo, what's unusual, the one
#     thing to check, named answers); high-stakes gates are active confirmation (the human picks or
#     types the specific, never a plain yes).
#   - No routine ask remains; the routine `undo` names what it reverted.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }   # reads all its input: no SIGPIPE under pipefail
has() { gq -F -- "$2" <<<"$1"; }        # has TEXT STRING
hasi() { gq -iE -- "$2" <<<"$1"; }      # has TEXT ERE (case-insensitive)
# any stderr fails the run; shown again on exit
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

CMD=.claude/commands/backlog-it.md
REF=.claude/make-it/references/backlog-board.md
flat() { tr '\n' ' ' | tr -s ' '; }
sub()  { awk -v h="$2" 'index($0,h)==1{on=1; print; next} /^```/{fence=!fence} on && !fence && /^###? /{exit} on' "$1" | flat; }   # a ### section (headings in code blocks don't end it), one line
CMDF="$(flat <"$CMD")"; REFF="$(flat <"$REF")"
START="$(sub "$REF" '### `start <id>`')"
HS="$(sub "$REF" '### High-stakes gate')"
PLANF="$(sub "$REF" '### Plan format')"
UNDO="$(sub "$REF" '### `undo`')"
# the preamble's two ship tracks, each one line
SAFE="$(awk '/^> - \*\*Safe/{on=1} /^> - \*\*Potentially/{exit} on' "$REF" | sed 's/^> *//' | flat)"
HARM="$(awk '/^> - \*\*Potentially/{on=1} on && !/^>/{exit} on' "$REF" | sed 's/^> *//' | flat)"

# a consequential ask is decision-ready: the five parts, and named answers (Name -- what happens)
ready() {
  hasi "$1" 'what (it|the plan|the pr|go) (changes|starts)' && hasi "$1" 'evidence|green run' &&
  hasi "$1" 'undo|roll(s)? it back|rollback' && hasi "$1" 'unusual' && hasi "$1" 'one thing to check' &&
  hasi "$1" '`[A-Z][a-z]+( [a-z]+)* -- [^`]+` *(\||or)'
}
# a high-stakes gate is active confirmation: the human picks or types the specific, never a plain yes
active() { hasi "$1" '(picks|types|names) (or (types|names) )?(the|which|one of)' && hasi "$1" 'never a plain (yes|go)'; }

# 1. the block is linked, once, from <execution_context>
EC="$(awk '/^<execution_context>/{on=1; next} /^<\/execution_context>/{on=0} on' "$CMD")"
check "approval-block.md @-imported exactly once in backlog-it.md" \
  [ "$(grep -c '^@~/\.claude/make-it/references/approval-block\.md$' "$CMD")" = 1 ]
check "... and that import is inside <execution_context>" \
  has "$EC" '@~/.claude/make-it/references/approval-block.md'

# 2. no bare yes/no ask
check "no (y/n) / yes/no in backlog-it.md"     bash -c '! grep -niE "\(y/n\)|y/n\b|yes/no" "$1"' _ "$CMD"
check "no (y/n) / yes/no in backlog-board.md"  bash -c '! grep -niE "\(y/n\)|y/n\b|yes/no" "$1"' _ "$REF"

# 3. every gate survives (by meaning)
check "start: runs only on the user's go"            hasi "$START" "on the user's \*\*go\*\*"
check "start: an edit step, not an approval gate"    has "$START" "This is an edit step, not an approval gate."
check "start: no risk gating, high-stakes still on the user's go" has "$START" "it still runs on the user's go"
check "cmd: start runs on the user's go"             has "$CMDF" "run on the user's go"
check "high-stakes: never auto-started or dispatched" has "$HS" "Never auto-started or dispatched."
check "high-stakes: start leads with the alignment brief" has "$HS" '`start` leads with an **alignment brief**'
check "high-stakes: then waits for an explicit go"   hasi "$HS" 'wait for an explicit go'
check "cmd: high-stakes cards never auto-picked"     has "$CMDF" "high-stakes cards are never auto-picked"
check "plan: held cards need the brief and an explicit go" has "$REFF" "it needs the alignment brief and an explicit go"
check "cmd: drafts never run without the go"         has "$CMDF" "Drafts never run without the user's go."
check "ref: drafts never run without the go"         has "$REFF" "Drafts never run without the user's go."
check "plan format: draft -> go -> approved"         bash -c 'grep -qF "status: draft" <<<"$1" && grep -qF "status: approved" <<<"$1"' _ "$PLANF"
check "dispatch: a subagent-it card waits for its plan's go" has "$REFF" "a \`subagent-it\` card still waits for its plan's go"
check "groom: splits, deferrals, kills stay proposals" has "$REFF" "**splits, deferrals, and kills are always proposals**"
check "groom strategy: splits and kills stay proposals" has "$REFF" "splits and kills stay proposals"
check "capture: card first (cmd)"                    has "$CMDF" "the card before any question"
check "capture: card first (ref)"                    has "$REFF" "Write the card -- no approval gate"
check "blocking question goes on the card (cmd)"     bash -c 'grep -qF "\`decision:\`" <<<"$1" && grep -qF "\`answers:\`" <<<"$1"' _ "$CMDF"
check "blocking question goes on the card (lanes)"   has "$REFF" 'also goes on it as `decision:` + `answers:`'
check "green gate holds"                             has "$REFF" "**100% green is the hard gate**"
check "harm gate holds: STOP before merge or deploy" bash -c 'grep -qF "STOP for" <<<"$1" && grep -qF "explicit human approval before merge or deploy" <<<"$1"' _ "$HARM"
check "harm gate: when in doubt, gate it"            has "$HARM" "When in doubt whether a change can cause harm, gate it"
check "shipping stays serial"                        has "$CMDF" "Shipping stays serial"

# 4. interview questions untouched
check "clarify: questions sized, one AskUserQuestion (cmd)" has "$CMDF" "ask first -- 1–2 questions for a task, 2–3 for a story, up to 4 for an epic, in one AskUserQuestion"
check "clarify: questions sized, one AskUserQuestion (ref)" has "$REFF" "**Ask clarifying questions** in one AskUserQuestion, sized to the item and never zero"
check "capture: every open question batched (ref)"  has "$REFF" "**every** open question batched in one AskUserQuestion, in plain words, only those whose answer changes the fix or its place in line."

# 5. consequential asks are decision-ready; high-stakes gates are active confirmation
check "start's go says what it starts, no bare OK"   bash -c 'grep -qiE "what \`?go\`? starts" <<<"$1" && grep -qiF "no bare" <<<"$1"' _ "$START"
check "plan go: one decision-ready ask"              ready "$PLANF"
check "safe track stop at the PR: one decision-ready ask" ready "$SAFE"
check "harm gate: decision-ready"                    ready "$HARM"
check "harm gate: active confirmation"               active "$HARM"
check "alignment brief go: active confirmation"      active "$HS"
check "subagent-it mode line asks the plan go as Plan format says" has "$START" "as [Plan format](#plan-format) says"

# 6. no routine ask remains; the routine undo is a note that names what it reverted
for f in "$CMD" "$REF"; do
  check "no routine ask in $f" bash -c '! grep -iE "want me to|shall I|should I (go|proceed|continue)|ok to proceed|proceed\?" "$1" | grep -viq "no bare"' _ "$f"
done
check "undo: no ask, names the commit it reverted"   has "$UNDO" 'Reverted the last board change: <'

# controls: the helpers must fail on a weakened text
active "${HARM//never a plain yes/a yes}" && bad "control: plain yes passed active" || ok "control: plain yes fails active"
ready "${PLANF//unusual/odd}" && bad "control: missing part passed ready" || ok "control: missing part fails ready"

[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
