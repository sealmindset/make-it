#!/usr/bin/env bash
# E02-S71 (the owner's call, 2026-11-20: "Retrofit logs too"): in /retrofit-it's Part A, a missing AI-safety control in
# code the app already had is logged to TODO.md for /fix-it (SEMI-AUTO, fix-strategies.md Strategy 8: /fix-it asks
# first), not added silently. Code this retrofit added is still completed by its [FIX] checks.
# Contract these checks pin:
#   - retrofit-it.md's Part A keeps its [FIX] rule and adds the exception, whole: which checks (AI02, AI03, AI04, AI10)
#     and which controls (the same four the build's scan logs, build-verify-security.md Phase 3 item 4), the line
#     between "already had" and "this retrofit added" (the file is or is not in the pre-retrofit snapshot), the TODO.md
#     line that names /fix-it, and that every other check -- AI29 included -- keeps the [FIX]/[BLOCK] rule.
#   - AI29 stays [BLOCK] [SECURITY FIX] in build-standards.md and is never in the logged set.
#   - /make-it's Part A rule is unchanged and carries no such exception.
#   - The places that said retrofit's build-verify is identical to /make-it's name the one difference.
# A wording test is a tripwire, not a proof: it catches these rules being dropped or reversed, not an agent ignoring
# them, and not the same claim made in other words or in a file it does not read.
# Usage: test-retrofit-ai-safety-logs.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# the whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise)
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

RF=.claude/commands/retrofit-it.md; MK=.claude/commands/make-it.md
BS=.claude/make-it/references/build-standards.md; CM=CLAUDE.md
FILES="$RF $MK $BS $CM"
flat() { tr '\n' ' ' | tr -s ' '; }
# text of FILE from the first line matching A up to the next line matching B (awk reads the file itself: no pipe to break)
between() { awk -v a="$2" -v b="$3" 'on && $0 ~ b {exit} $0 ~ a {on=1} on' "$1"; }
has() { printf "%s" "$1" | gq -F -- "$2"; }
row() { gq -xF -- "$2" "$1"; }

PA="$(between "$RF" '^[*][*]PART A: ' '^[*][*]PART B: ' | flat)"
EX="$(between "$RF" '^[*][*]A missing AI-safety control in code' '^Tell user: "Your app is retrofitted' | flat)"
MPA="$(between "$MK" '^[*][*]PART A: ' '^[*][*]PART B: ')"

S_HEAD='**A missing AI-safety control in code the app already had is logged, not added.** The `[FIX]` rule above does not apply to it.'
S_WHICH='When AI02, AI03, AI04 or AI10 finds one of these controls missing -- a sanitizePromptInput() or validateAgentOutput() call, delimiter tags around user input in a prompt, rate limiting middleware on an AI route, the safety preamble on a managed prompt -- look at the file it is missing from:'
S_OLD='- **The snapshot has the file** (own repo: `git cat-file -e "<tag>:<file>"` succeeds, with the tag `pre-retrofit-<app folder name>` the plan step made; nested app: `[BACKUP]/files/<file>` exists): it is code the app already had. Change nothing in it for this finding.'
S_TODO='Add one line to TODO.md under "## Security Improvements": the finding, the file, and "/fix-it applies this fix, with an ask, after a /nemo-it scan reports it".'
S_WHY='The fix is SEMI-AUTO (fix-strategies.md, Strategy 8): the user picks it in /fix-it.'
S_NEW='- **The snapshot does not have the file:** this retrofit added it. Auto-fix it, as any `[FIX]` item.'
S_REST='- Every other check follows the rule above, AI29 included: it is a hole open now, not a missing control.'
S_GATE='**Build-verify is a SILENT QUALITY GATE** identical to /make-it'"'"'s, except one rule in Part A: a missing AI-safety control in code the app already had is logged for /fix-it, not added.'
S_OVR='6. **Verify** -- Build-verify identical to /make-it, except that a missing AI-safety control in code the app already had is logged for /fix-it'
S_CM='6. **Verify** -- Build-verify identical to /make-it, plus preservation checks (existing features still work); a missing AI-safety control in code the app already had is logged for /fix-it, not added'

# 1. retrofit Part A: the [FIX] rule stays, the exception is whole
check "retrofit-it.md's Part A was found" '[ -n "$PA" ]'
check "the [FIX], [BLOCK] and [WARN] rules are still there, word for word" \
  'row "$RF" "- \`[FIX]\` items: auto-fix immediately" && row "$RF" "- \`[BLOCK]\` items: must pass before proceeding to Part B" && row "$RF" "- \`[WARN]\` items: note in TODO.md, continue"'
check "the exception's heading: a missing control in code the app already had is logged, not added" 'has "$PA" "$S_HEAD"'
check "which checks and which controls: AI02, AI03, AI04 or AI10, the four controls the build's scan logs" 'has "$PA" "$S_WHICH"'
check "code the app already had = the snapshot has the file; nothing in it is changed for the finding" 'has "$PA" "$S_OLD"'
check "the TODO.md line: the finding, the file, and /fix-it applying it with an ask" 'has "$PA" "$S_TODO"'
check "why: the fix is SEMI-AUTO (Strategy 8), the user picks it in /fix-it" 'has "$PA" "$S_WHY"'
check "code this retrofit added (not in the snapshot) is still auto-fixed" 'has "$PA" "$S_NEW"'
check "every other check, AI29 included, keeps the rule above" 'has "$PA" "$S_REST"'
check "the exception comes after the [WARN] rule and before the Part A tell-user line" \
  'printf "%s" "$PA" | perl -ne "exit(!/\Q- \`[WARN]\` items: note in TODO.md, continue\E.*\Q**A missing AI-safety control\E.*\QTell user: \"Your app is retrofitted!\E/)"'

# 2. must not appear
check "the exception names AI02, AI03, AI04, AI10 and AI29 only, and AI29 once (in the \"every other check\" line)" \
  '[ "$(printf "%s" "$EX" | grep -oE "AI[0-9]{2}" | sort -u | tr "\n" " ")" = "AI02 AI03 AI04 AI10 AI29 " ] && [ "$(printf "%s" "$EX" | grep -oE "AI29" | grep -c .)" = 1 ]'
check "nothing in Part A logs AI29 or sends it to TODO.md" '! printf "%s" "$PA" | gq -E "AI29[^.]*(logged|TODO)|(logged|TODO)[^.]*AI29"'
check "nothing in Part A auto-fixes, adds or wires a control in code the app already had" \
  '! printf "%s" "$PA" | gq -iE "already had[^.]*(auto-fix|add (it|the|a|one) (missing )?(control|call|tag|middleware|preamble)|wire)|(auto-fix|add|wire)[^.]*code the app already had"'
check "nothing in Part A says code this retrofit added is logged instead of fixed" \
  '! printf "%s" "$PA" | gq -iE "(retrofit added|does not have the file)[^.]*(log|TODO|change nothing)"'
check "AI29 is still [BLOCK] [SECURITY FIX] in build-standards.md" '[ "$(grep -c "^[*][*]AI29[*][*] \[AI\] \[BLOCK\] \[SECURITY FIX\] " "$BS")" = 1 ]'

# 3. /make-it unchanged
check "/make-it's Part A was found, and its rule is the three lines, unchanged, right before its tell-user line" \
  '[ -n "$MPA" ] && printf "%s\n" "$MPA" | perl -0ne "exit(!/\nFor each failing check:\n- \`\[FIX\]\` items: auto-fix immediately\n- \`\[BLOCK\]\` items: must pass before proceeding to Part B\n- \`\[WARN\]\` items: note in TODO.md, continue\n\nTell user: \"Your app is built!/)"'
check "make-it.md carries no such exception (no \"already had\", no pre-retrofit snapshot)" \
  '! gq -iE "already had|pre-retrofit|snapshot has the file" "$MK"'

# 4. the "identical to /make-it" statements name the difference
check "retrofit-it.md's Verify step and its overview name the one difference" 'has "$(flat < "$RF")" "$S_GATE" && row "$RF" "$S_OVR"'
check "CLAUDE.md's /retrofit-it Verify line names it too" 'row "$CM" "$S_CM"'
check "no bare \"identical to /make-it\" claim is left in those places" \
  '! gq -E "identical to /make-it('"'"'s)?[.]?\$" "$RF" && ! gq -E "identical to /make-it('"'"'s)?[.]?\$" "$CM" && ! gq -xF "6. **Verify** -- Build-verify identical to /make-it, plus preservation checks (existing features still work)" "$CM"'

# 5. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  check "(control) an unchanged copy passes, so each control below fails for its own edit" \
    'd="$TMPD/c"; mkdir -p "$d"; tar -cf - $FILES | tar -xf - -C "$d"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with the old rule back on existing code: the exception removed, and \"change nothing\" turned into an auto-fix" \
    'opp "$RF" "s/^\*\*A missing AI-safety control in code.*?(?=^Tell user: \"Your app is retrofitted)//ms" && opp "$RF" "s/Change\s+nothing in it for this finding[.]/Auto-fix it, as any \`[FIX]\` item./"'
  check "(control) fails with the TODO.md line dropped, and with it kept but made to follow an auto-fix" \
    'opp "$RF" "s/Add\s+one\s+line\s+to\s+TODO.md\s+under.*?reports it\"[.]\s*//s" && opp "$RF" "s/(it is code the app already had[.]) Change\s+nothing in it for this finding[.]/\$1 Add the control, then log it./"'
  check "(control) fails with /fix-it not named in the TODO line, and in the why" \
    'opp "$RF" "s/\"\/fix-it applies this fix,\s+with an ask,/\"this needs a fix,/" && opp "$RF" "s/the user picks it in \/fix-it[.]/the user picks it later./"'
  check "(control) fails with AI29 in the logged set, and with a sentence logging AI29" \
    'opp "$RF" "s/When AI02, AI03, AI04 or AI10 finds/When AI02, AI03, AI04, AI10 or AI29 finds/" && opp "$RF" "s/^(- Every other check follows the rule above)/- AI29 is logged to TODO.md the same way.\n\$1/m"'
  check "(control) fails with AI29 dropped from the \"every other check\" line, and with AI29 no longer [BLOCK] [SECURITY FIX]" \
    'opp "$RF" "s/, AI29 included: it is a hole open now, not a missing control[.]/./" && opp "$BS" "s/^\*\*AI29\*\* \[AI\] \[BLOCK\] \[SECURITY FIX\]/**AI29** [AI] [FIX]/m"'
  check "(control) fails with /make-it changed: its [FIX] rule reworded, and the exception copied into it" \
    'opp "$MK" "s/^(For each failing check:\n)- \`\[FIX\]\` items: auto-fix immediately/\$1- \`[FIX]\` items: auto-fix, except AI-safety controls/m" && opp "$MK" "s/^(- \`\[WARN\]\` items: note in TODO.md, continue\n)(\nTell user: \"Your app is built)/\$1\n**A missing AI-safety control in code the app already had is logged, not added.**\n\$2/m"'
  check "(control) fails when code this retrofit added is no longer completed, and with that line removed" \
    'opp "$RF" "s/this retrofit added it[.] Auto-fix it, as any \`\[FIX\]\` item[.]/this retrofit added it. Log it the same way./" && opp "$RF" "s/^- \*\*The snapshot does not have the file:\*\*.*?\n//m"'
  check "(control) fails with the snapshot line gone, and with the old \"identical\" claims back" \
    'opp "$RF" "s/ \(own repo: \`git cat-file.*?exists\)//s" && opp "$CM" "s/ \(existing features still work\); a missing AI-safety control.*\$/ (existing features still work)/m"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
