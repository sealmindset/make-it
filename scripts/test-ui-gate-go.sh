#!/usr/bin/env bash
# E03-S16: the web-app build go (ui-gate.md, Part 1) asks through the approval block.
# Contract these checks pin (the change must satisfy it):
#   - The preview ask is also the go-ahead to build, and it says so: consequential, per approval-block.md.
#   - It is decision-ready: what a go starts, the evidence, what it touches and the undo, what is unusual, the one
#     thing to check. The go is an answer to that ask, never a bare yes taken as the go by itself.
#   - A /resume-it feature that changes who can see or do something the app already has is high-stakes: the user
#     names the screens and roles; a plain yes is not enough.
#   - No gate is lost: the preview loop (no cap), building to the preview, Part 2's built-screens review and its
#     approval line, fix-before-showing, and the Desktop route all stay.
#   - The learnings caller (Part 2, last step) matches learnings.md: one batched ask, numbered, each with its
#     evidence, sent on its own; never "plain yes/no".
#   - No bare yes/no anywhere in ui-gate.md.
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

UG=.claude/make-it/references/ui-gate.md
LE=.claude/make-it/references/learnings.md
sect() { awk -v h="$1" 'index($0,h)==1{on=1;next} on&&/^## /{exit} on' $UG | flat; }
P1="$(sect '## Part 1')"
P2="$(sect '## Part 2')"
BUILD="$(sect '## Build to the preview')"
DESK="$(sect '## Desktop')"
p1() { printf "%s" "$P1" | gq "$@"; }
p2() { printf "%s" "$P2" | gq "$@"; }

check "ui-gate.md has its Part 1, Build, Part 2 and Desktop sections" \
  '[ -n "$P1" ] && [ -n "$BUILD" ] && [ -n "$P2" ] && [ -n "$DESK" ]'

# 1. no bare yes/no
check "ui-gate.md: no (y/n), y/n, yes/no or 'On yes'" '! gq -iE "\(y/n\)|y/n\b|yes/no|On yes" $UG'
check "Part 1: no plain yes is the go by itself ('That yes is the go-ahead')" '! p1 -iE "that yes is the go"'

# 2. the go is tiered through the block
check "Part 1: the preview ask is the go-ahead to build" 'p1 -iE "go-ahead to build"'
check "Part 1: the go is consequential, per approval-block.md" \
  'p1 -iE "consequential[^.]{0,40}approval-block\.md"'

# 3. decision-ready: each of the five parts, by meaning
check "Part 1 ask: what a go starts (the whole build / the feature)" 'p1 -iE "what (a|the|their) (go|yes) starts[^.]*(whole build|build)"'
check "Part 1 ask: the evidence (the preview in front of them)" 'p1 -iE "evidence[^.]{0,80}preview"'
check "Part 1 ask: what it touches and the undo, for /make-it (a new folder, nothing published, remove it)" \
  'p1 -iE "new folder[^.]*nothing (is )?published" && p1 -iE "undo[^.]{0,80}remove (the folder|it)"'
check "Part 1 ask: what it touches and the undo, for /resume-it (taken back)" 'p1 -iE "/resume-it[^.]{0,120}taken back"'
check "Part 1 ask: what is unusual vs the plan they saw, or 'Nothing unusual'" \
  'p1 -iE "unusual[^.]{0,120}plan they saw" && p1 -F "Nothing unusual"'
check "Part 1 ask: the one thing to check is who sees each screen (roles per screen)" \
  'p1 -iE "one thing to check[^.]{0,40}who sees (each|which) screen" && p1 -iE "roles"'
check "Part 1 ask: closes with how to give the go ('build it') or ask for changes" 'p1 -iE "say .build it."'
check "Part 1: the approval line is set on their go, and only then" \
  'p1 -iE "on their go[^.]*Preview: approved <date> \(round <N>\)"'

# 4. high-stakes branch: changing access to what already exists
check "Part 1: a /resume-it change to who can see or do something existing is high-stakes" \
  'p1 -iE "high-stakes[^.]{0,40}/resume-it[^.]*who can see or do[^.]*already"'
check "Part 1: high-stakes go = the user names the screens and roles; a plain yes is not enough" \
  'p1 -iE "names? (those|the) screens and roles" && p1 -iE "plain .?yes.?[^.]{0,40}not enough"'

# 5. no gate lost
check "Part 1: the preview is opened, the user drives the rounds (no cap)" 'p1 -iE "\*\*Open it\*\*" && p1 -F "No cap"'
check "Part 1: the preview question stays word for word" \
  'p1 -F "\"I made a clickable preview of your app -- nothing is built yet. Click around. Does it look and work the way you pictured? Tell me anything you'"'"'d change.\""'
check "Build: screens are built to the approved preview; a deviation is agreed first" \
  'printf "%s" "$BUILD" | gq -iE "match the approved preview" && printf "%s" "$BUILD" | gq -iE "agree on the change"'
check "Part 2: a broken screen is fixed before the user sees anything" 'p2 -iE "never sees a broken screen"'
check "Part 2: the built-screens ask stays, and its yes sets the approval line" \
  'p2 -F "Does it look right?" && p2 -iE "Screens as built: approved"'
check "Desktop: Part 1 repeats until approved there; Part 2 runs in Claude Code" \
  'printf "%s" "$DESK" | gq -iE "until approved" && printf "%s" "$DESK" | gq -iE "Part 2 runs in Claude Code"'

# 6. the learnings caller matches learnings.md
LC="$(printf "%s" "$P2" | sed -nE 's/.*(6\. .*)$/\1/p')"
check "learnings.md still asks one batched, decision-ready ask" 'gq -F "## Ask first: one batched, decision-ready ask" $LE'
check "Part 2 learnings step points at learnings.md" 'printf "%s" "$LC" | gq -F "learnings.md"'
check "Part 2 learnings step: one batched ask, each numbered with its evidence, sent on its own" \
  'printf "%s" "$LC" | gq -iE "one batched[^.]*numbered[^.]*evidence[^.]*on its own"'
check "ui-gate.md: no 'plain yes/no' or 'want me to remember' learnings offer" '! gq -iE "plain yes/no|want me to remember" $UG'

# 7. both callers load the block that the go is tiered by
for f in .claude/commands/make-it.md .claude/commands/resume-it.md; do
  check "$f loads ui-gate.md and approval-block.md" \
    'gq -xF "@~/.claude/make-it/references/ui-gate.md" $f && gq -xF "@~/.claude/make-it/references/approval-block.md" $f'
done

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
