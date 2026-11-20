#!/usr/bin/env bash
# E02-S58 (the owner's call, 2026-11-19): the security scan (build-verify-security.md) logs an AI-safety wiring finding
# to TODO.md and changes nothing in the app for it. The fix is SEMI-AUTO (fix-strategies.md, Strategy 8): /fix-it applies
# it, with an ask. The scan runs no NeMo test for such a finding.
# Contract these checks pin:
#   - Phase 3's item 4 is "logged, not fixed": none of the five old "Add missing ..." fixes is back, and Phase 3 no
#     longer says it fixes all findings.
#   - The log rule, whole: one TODO.md line under "## Security Improvements" with the finding, the file and who fixes it.
#   - The scan runs no NeMo Guardrails test and not the app's suite for such a finding; the scan file names
#     guardrails/tests/ in two pinned sentences only (that one, and /fix-it running it when it verifies a fix).
#   - The scan's rule is not the whole build's: Part A's [FIX] checks (AI02-AI07, AI10) add a missing control while the
#     app is being generated. The facts that sentence rests on are pinned too (make-it.md and retrofit-it.md auto-fix
#     [FIX] items; those checks are [FIX]).
#   - Phase 3, Phase 5, the summary, "What This Does NOT Replace" and the key constraint agree: every "AI safety wiring"
#     in the scan file is in one of five pinned sentences.
#   - Strategy 8 stays SEMI-AUTO, in its section and in the decision tree.
#   - The governance doc's two fix-order lines no longer list AI safety wiring as a fix.
# A wording test is a tripwire, not a proof: it catches these rules being dropped or reversed, not an agent ignoring
# them, and not the same claim made in other words or in a file it does not read.
# Usage: test-scan-ai-fixes-log-only.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on opposites.
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

REF=.claude/make-it/references
B=$REF/build-verify-security.md; FS=$REF/fix-strategies.md; BS=$REF/build-standards.md
MK=.claude/commands/make-it.md; RF=.claude/commands/retrofit-it.md; GOV=docs/AI-GOVERNANCE-HOMEGROWN.md
FILES="$B $FS $BS $MK $RF $GOV"
flat() { tr '\n' ' ' | tr -s ' '; }
# text of FILE from the first line matching A up to the next line matching B (awk reads the file itself: no pipe to break)
between() { awk -v a="$2" -v b="$3" 'on && $0 ~ b {exit} $0 ~ a {on=1} on' "$1"; }
# has TEXT 'whole sentence': the flattened text holds that exact sentence
has() { printf "%s" "$1" | gq -F -- "$2"; }
# row FILE LINE: the file holds exactly this line
row() { gq -xF -- "$2" "$1"; }

P3="$(between "$B" '^## Phase 3: ' '^## Phase 4: ' | flat)"
P5="$(between "$B" '^## Phase 5: ' '^## Phase 6: ' | flat)"
NOT="$(between "$B" '^## What This Does NOT Replace' '^## Severity Classification' | flat)"
KEY="$(between "$B" '^## Severity Classification' '^## NO SUCH HEADING' | flat)"
ALL="$(flat < "$B")"
S8="$(between "$FS" '^## Strategy 8: ' '^## Strategy 9: ')"

S_ITEM='4. **AI safety wiring** (if AI app) -- logged, not fixed. The fix is SEMI-AUTO (fix-strategies.md, Strategy 8), so the scan changes nothing in the app for it:'
S_TODO='- A Phase 2 finding that a safety control is missing or not wired in (a sanitizePromptInput() or validateAgentOutput() call, delimiter tags around user input in a prompt, rate limiting middleware on an AI route, the safety preamble on a managed prompt) gets one line in TODO.md under "## Security Improvements": the finding, the file, and "/fix-it applies this fix, with an ask, after a /nemo-it scan reports it".'
S_NEMO='- The scan runs no NeMo Guardrails test for such a finding, and does not run the app'"'"'s guardrail suite (guardrails/tests/).'
S_PARTA='- This rule is for the scan'"'"'s findings only. Before the scan, Part A'"'"'s checks complete the app being generated: a safety control that a [FIX] check in build-standards.md (AI02-AI07, AI10) finds missing is added then, as any [FIX] item is.'
S_P5='- **AI safety wiring findings (Phase 3, item 4):** logged to TODO.md under "## Security Improvements" in the first cycle, whatever their severity, and never fixed in any cycle. They do not start another cycle.'
S_SUM='  AI safety wiring findings logged to TODO.md, not fixed: [N]'
S_NOT='Part D applies AUTO-class fixes silently, plus Phase 6'"'"'s deep-audit fixes. An AI safety wiring finding from its scan is logged to TODO.md, not fixed: /fix-it applies that fix, with an ask.'
S_KEY='The key constraint: for scanner findings, only AUTO-class fixes from fix-strategies.md are applied silently; SEMI-AUTO and MANUAL ones are logged to TODO.md, AI safety wiring (Strategy 8) among them.'
S_FIXIT='/fix-it runs the app'"'"'s guardrail suite (guardrails/tests/) when it verifies a fix.'

# 1. Phase 3: item 4 is logged, not fixed
check "Phase 3 was found in build-verify-security.md" '[ -n "$P3" ]'
check "Phase 3 item 4: AI safety wiring is logged, not fixed, because its fix is SEMI-AUTO; the scan changes nothing in the app" \
  'has "$P3" "$S_ITEM"'
check "Phase 3 lists none of the five old silent AI-wiring fixes (Add missing ... / Wire safety preamble)" \
  '! printf "%s" "$ALL" | gq -iE "\b(add|adds|adding|wire|wires|wiring in) (the )?missing (sanitizePromptInput|validateAgentOutput|delimiter|rate limiting)|Wire safety preamble"'
check "Phase 3 no longer says it applies fixes for all findings" \
  'has "$P3" "Apply the fixes in the fix order below, following the priority order from fix-strategies.md." && ! printf "%s" "$ALL" | gq -iE "fix(es)? for (all|every) findings?"'

# 2. the log rule
check "the log rule, whole: one TODO.md line under Security Improvements -- the finding, the file, who fixes it" \
  'has "$P3" "$S_TODO"'

# 3. no NeMo test for such a finding
check "the scan runs no NeMo Guardrails test for such a finding, and not the app's suite" 'has "$P3" "$S_NEMO"'
check "the scan file names guardrails/tests/ in those two pinned sentences only (the scan does not run it; /fix-it does)" \
  'has "$ALL" "$S_FIXIT" && [ "$(printf "%s" "$ALL" | S1="$S_NEMO" S2="$S_FIXIT" perl -pe "s/\Q\$ENV{S1}\E//g; s/\Q\$ENV{S2}\E//g" | grep -ciE "guardrails/tests|guardrail suite")" = 0 ]'

# 4. the scan's rule is not the whole build's
check "the scan's rule is for the scan's findings only: Part A's [FIX] checks add a missing control while the app is generated" \
  'has "$P3" "$S_PARTA"'
check "nothing says Part A or the build's own checks log such a gap, or that a build never adds a missing control" \
  '! printf "%s" "$ALL" | gq -iE "Part A[^.]*(is|are) (logged|not added|never added|not fixed)|Part A[^.]*(logs?|never adds?|does not add)\b|builds? never (adds?|fix(es)?)"'
check "what that sentence rests on: /make-it and /retrofit-it auto-fix a failing [FIX] check; AI02-AI07 and AI10 are [FIX]" \
  'row "$MK" "- \`[FIX]\` items: auto-fix immediately" && row "$RF" "- \`[FIX]\` items: auto-fix immediately" && [ "$(grep -cE "^[*][*]AI(02|03|04|05|06|07|10)[*][*] \[AI\] \[FIX\] " "$BS")" = 7 ]'

# 5. the other places say the same
check "Phase 5: these findings are logged in the first cycle, never fixed, and start no further cycle" 'has "$P5" "$S_P5"'
check "the internal summary counts them on their own line" 'row "$B" "$S_SUM"'
check "What This Does NOT Replace: Part D logs the finding; /fix-it applies the fix, with an ask" 'has "$NOT" "$S_NOT"'
check "the key constraint, whole: only AUTO-class fixes are silent; SEMI-AUTO and MANUAL are logged, AI safety wiring among them" \
  'has "$KEY" "$S_KEY"'
check "nothing in the scan file applies a SEMI-AUTO or MANUAL fix silently" \
  '! printf "%s" "$ALL" | gq -iE "(SEMI-AUTO|MANUAL)[^.;]*(applied|fixed|made) (silently|without asking)|silently appl(y|ies)[^.;]*(SEMI-AUTO|MANUAL)"'
# five places, five pinned sentences: add a place, add its pin and raise this count with it
check "they agree: each of the 5 \"AI safety wiring\" in the scan file is in one of the five pinned sentences" \
  '[ "$(printf "%s" "$ALL" | grep -o "AI safety wiring" | grep -c .)" = 5 ] && has "$ALL" "$S_ITEM" && has "$ALL" "$S_P5" && has "$ALL" "${S_SUM# }" && has "$ALL" "$S_NOT" && has "$ALL" "$S_KEY"'

# 6. Strategy 8 stays SEMI-AUTO
check "Strategy 8 was found in fix-strategies.md" '[ -n "$S8" ]'
check "Strategy 8 is SEMI-AUTO in its section and in the decision tree, and AUTO in neither" \
  'printf "%s\n" "$S8" | gq -xF "### Fix Procedure (SEMI-AUTO)" && [ "$(printf "%s\n" "$S8" | grep -cE "^### Fix Procedure|[(]AUTO[)]")" = 1 ] && row "$FS" "      Yes -> SEMI-AUTO (Strategy 8)" && [ "$(grep -cE "Strategy 8[)]?\$" "$FS")" = 1 ]'

# 7. the governance doc
check "the governance doc: neither fix-order line lists AI safety wiring as a fix; both say it is logged" \
  'has "$(flat < "$GOV")" "Priority-ordered fix application: dependencies → config → code patterns → hardcoded secrets. AI safety wiring findings from the scan are logged to TODO.md, not fixed (/fix-it applies those, with an ask)." && row "$GOV" "  └─ Priority order: deps → config → code patterns → secrets" && row "$GOV" "  └─ AI safety wiring findings: logged to TODO.md, not fixed" && ! flat < "$GOV" | gq -E "code patterns → AI safety"'

# 8. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  check "(control) an unchanged copy passes, so each control below fails for its own edit" \
    'd="$TMPD/c"; mkdir -p "$d"; tar -cf - $FILES | tar -xf - -C "$d"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with item 4 back as a silent fix, and with one old fix added under the new item" \
    'opp "$B" "s/^4[.] \*\*AI safety wiring\*\*.*?(?=^5[.] )/4. **AI safety wiring** (if AI app):\n   - Add missing sanitizePromptInput() calls\n   - Add missing validateAgentOutput() calls\n/ms" && opp "$B" "s/^(5[.] \*\*Hardcoded secrets)/   - Add missing rate limiting middleware to AI routes\n\$1/m"'
  check "(control) fails with \"SEMI-AUTO fixes are applied silently\" in the key constraint, in place of it and added to it" \
    'opp "$B" "s/only AUTO-class fixes from fix-strategies.md are applied\s+silently; SEMI-AUTO and MANUAL ones are logged to TODO.md/AUTO-class and SEMI-AUTO fixes are applied silently; MANUAL ones are logged to TODO.md/" && opp "$B" "s/^(Critical and High are fixed by Strategy 13)/SEMI-AUTO fixes are applied silently when they are small. \$1/m"'
  check "(control) fails with the TODO rule removed, and with it reworded to \"fixed, then noted in TODO.md\"" \
    'opp "$B" "s/^   - A Phase 2 finding that a safety control.*?(?=^   - The scan runs no NeMo)//ms" && opp "$B" "s/gets one line in TODO.md/is fixed, then gets one line in TODO.md/"'
  check "(control) fails when the scan runs guardrails/tests/ after adding the calls, and with the no-NeMo sentence dropped" \
    'opp "$B" "s/^(5[.] \*\*Hardcoded secrets)/   - The scan runs guardrails\/tests\/ after adding the calls.\n\$1/m" && opp "$B" "s/^   - The scan runs no NeMo.*?(?=^   - This rule is for)//ms"'
  check "(control) fails with the Part A sentence reversed, and with \"the build never adds a missing control\" added" \
    'opp "$B" "s/finds missing is added then, as any \[FIX\] item is/finds missing is logged then, never added/" && opp "$B" "s/^(5[.] \*\*Hardcoded secrets)/   - A build never adds a missing safety control.\n\$1/m"'
  check "(control) fails with Strategy 8 reclassed AUTO: in its section, and in the decision tree" \
    'opp "$FS" "s/(## Strategy 8: .*?### Fix Procedure) \(SEMI-AUTO\)/\$1 (AUTO)/s" && opp "$FS" "s/Yes -> SEMI-AUTO \(Strategy 8\)/Yes -> AUTO (Strategy 8)/"'
  check "(control) fails when Phase 5 fixes them in a later cycle, when AI02 stops being a [FIX] check, and with the old governance row back" \
    'opp "$B" "s/and never fixed in any cycle/and fixed in the next cycle/" && opp "$BS" "s/^\*\*AI02\*\* \[AI\] \[FIX\]/**AI02** [AI] [WARN]/m" && opp "$GOV" "s/code patterns → hardcoded secrets[.]/code patterns → AI safety wiring → hardcoded secrets./"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
