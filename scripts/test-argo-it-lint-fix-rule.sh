#!/usr/bin/env bash
# E02-S11: /argo-it's pre-send lint fix and its "never touch the app" guardrail must agree (owner, 2026-10-18).
# Contract these checks pin:
#   - Step 3a applies only the linters' safe automatic fixes (formatting, imports): ruff with unsafe fixes
#     switched off, eslint limited to layout fixes. No bare `ruff check --fix` or `eslint --fix` anywhere,
#     and unsafe fixes are never switched on.
#   - Before step 4 saves, 3a tells the user each file the fixes changed -- a note, not a question.
#   - The guardrail: docker-compose.yml is never modified (unchanged), and argo-it never changes how the
#     app behaves. The old "NEVER modify ... application source code" wording is gone, here and in the guide.
# A tripwire for the wording, not a proof of behavior: whether a real redeploy keeps to this is the card's live check.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT
A=.claude/commands/argo-it.md
G=docs/ARGO-IT-GUIDE.md
flat() { tr '\n' ' ' | tr -s ' '; }
FA="$(flat < "$A")"; FG="$(flat < "$G")"
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
# has TEXT FLATTENED LABEL: the whole sentence is there, once whitespace is flattened
has()   { if [ "$(printf '%s\n' "$2" | grep -cF -- "$1")" -gt 0 ]; then ok "$3"; else bad "$3"; fi; }
# hasnt REGEX FLATTENED LABEL: nothing matches (grep -o counts every match, the flattened text is one line)
hasnt() { if [ "$(printf '%s\n' "$2" | grep -oiE -- "$1" | grep -c . || true)" -eq 0 ]; then ok "$3"; else bad "$3"; fi; }
# line TEXT FILE LABEL: exactly one line of the file is exactly TEXT
line()  { if [ "$(grep -cxF -- "$1" "$2")" -eq 1 ]; then ok "$3"; else bad "$3"; fi; }
# count REGEX: how many times it matches in argo-it.md
count() { printf '%s\n' "$FA" | grep -oE -- "$1" | grep -c . || true; }

# must-not-appear patterns (each probed on its own in the controls at the end)
OLD_GUARD='NEVER modify.{0,40}application (source )?code'
OLD_PERSONA='Modify the user.s docker-compose[.]yml or application code'
OLD_FIXABLE='auto-fix what.s fixable'
UNSAFE_ON='(^|[^-o])-?-?unsafe-fixes|[^n]o-unsafe-fixes|unsafe[- ]fixes *= *true'
WIDE_ESLINT='fix-type[ =][a-z,]*(suggestion|problem|directive)'

# --- step 3a: safe fixes only
has 'If lint/type errors are found: apply only the linters'"'"' safe automatic fixes -- formatting and imports (`ruff check --fix --no-unsafe-fixes`, `eslint --fix --fix-type layout`).' "$FA" \
  "3a applies only the linters' safe automatic fixes, with the flags that keep them safe"
has 'Never turn on a linter'"'"'s unsafe fixes, and never run eslint'"'"'s fix without `--fix-type layout`: those rewrite what the code does.' "$FA" \
  "3a says never to turn on unsafe fixes or run eslint's fix unrestricted"
if [ "$(count 'ruff check --fix')" -gt 0 ] && [ "$(count 'ruff check --fix')" = "$(count 'ruff check --fix --no-unsafe-fixes')" ]; then
  ok "every ruff fix command switches unsafe fixes off"; else bad "every ruff fix command switches unsafe fixes off"; fi
if [ "$(count 'eslint --fix')" -gt 0 ] && [ "$(count 'eslint --fix')" = "$(count 'eslint --fix --fix-type layout')" ]; then
  ok "every eslint fix command is limited to layout fixes"; else bad "every eslint fix command is limited to layout fixes"; fi
hasnt "$UNSAFE_ON" "$FA" "unsafe fixes are never switched on"
hasnt "$WIDE_ESLINT" "$FA" "eslint's fix is never widened past layout"
hasnt "$OLD_FIXABLE" "$FA" "the old \"auto-fix what's fixable\" wording is gone"
hasnt 'lint --fix[,)]' "$FA" "no bare \"lint --fix\" shorthand is left in the rules"

# --- step 3a: the changed files are listed before saving, as a note
has 'Then tell the user each file the fixes changed, in one plain line before step 4 saves anything -- a note, not a question' "$FA" \
  "3a tells the user each file the fixes changed, before step 4 saves, as a note"
has 'compare `git hash-object` of each one before and after the fix to know which the fix changed' "$FA" \
  "3a says how to tell which files the fix changed"
has '**If ALL checks pass:** proceed to step 4 with no ask -- the user hears nothing about the review beyond 3a'"'"'s list of changed files, if there is one.' "$FA" \
  "a clean review still shows 3a's list of changed files, and adds no ask"
hasnt 'the user never knows the review happened' "$FA" "the old \"user never knows the review happened\" wording is gone"

# --- the guardrail
line '- NEVER modify docker-compose.yml' "$A" "guardrail: docker-compose.yml is never modified (its own line, once)"
line '- NEVER change how the app behaves -- on its own, argo-it touches application source code only for step 3a'"'"'s safe automatic fixes (formatting, imports), and lists each file it changed; any other change to the code waits for the user'"'"'s pick (the 3e gate, the ask at the end of step 3)' "$A" \
  "guardrail: argo-it never changes how the app behaves"
line '- Modify the user'"'"'s docker-compose.yml, or change how their app behaves' "$A" "persona: the never-do list says the same"
line '- Auto-fix only what'"'"'s safe (3a'"'"'s safe automatic fixes -- formatting, imports -- and auto-add untracked migrations), and list each file 3a changed before saving; secrets move only through the 3e gate (`secret-scan.py`; anything but a clean exit 0 or 1 sends nothing) -- the user picks which' "$A" \
  "pre-push rules: auto-fix only what's safe, list the files, secrets through the 3e gate"
hasnt "$OLD_GUARD" "$FA" "the old \"NEVER modify ... application source code\" guardrail is gone"
hasnt "$OLD_PERSONA" "$FA" "the old persona line is gone"

# --- the guide says the same
line '- Modify Docker Compose files, or change how your app behaves (before sending an update it may apply the linters'"'"' safe automatic fixes -- formatting, imports -- and it lists each file it changed)' "$G" \
  "ARGO-IT-GUIDE: the does-NOT-do list says the same"
hasnt 'Modify application code' "$FG" "ARGO-IT-GUIDE: the old \"Modify application code\" line is gone"

# --- controls: each must-not pattern fires on the wording it is there to catch, and not on the allowed wording
ctl() { if [ "$(printf '%s\n' "$2" | grep -oiE -- "$1" | grep -c . || true)" "$3" 0 ]; then ok "(control) $4"; else bad "(control) $4"; fi; }
ctl "$OLD_GUARD"   '- NEVER modify docker-compose.yml or application source code' -gt "the old guardrail is caught"
ctl "$OLD_GUARD"   '- NEVER modify docker-compose.yml - NEVER change how the app behaves -- on its own, argo-it touches application source code only for' -eq "the new guardrail is not"
ctl "$OLD_PERSONA" "- Modify the user's docker-compose.yml or application code" -gt "the old persona line is caught"
ctl "$OLD_FIXABLE" "- Auto-fix what's fixable (lint --fix" -gt "the old auto-fix wording is caught"
ctl "$UNSAFE_ON"   'ruff check --fix --unsafe-fixes' -gt "--unsafe-fixes is caught"
ctl "$UNSAFE_ON"   'set unsafe-fixes = true' -gt "the unsafe-fixes setting is caught"
ctl "$UNSAFE_ON"   'ruff check --fix --no-unsafe-fixes' -eq "--no-unsafe-fixes is allowed"
ctl "$WIDE_ESLINT" 'eslint --fix --fix-type layout,suggestion' -gt "a widened eslint fix is caught"
ctl "$WIDE_ESLINT" 'eslint --fix --fix-type layout' -eq "the layout-only eslint fix is allowed"

if [ -s "$ERRF" ]; then bad "the whole run wrote nothing to stderr"; sed 's/^/  stderr: /' "$ERRF"; else ok "the whole run wrote nothing to stderr"; fi
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
