#!/usr/bin/env bash
# E02-S56 (the owner's call, 2026-11-19): check AI09 is code-level only. It reads the files to confirm the NeMo guardrails
# are present and wired, and runs no NeMo Guardrails test. A code-level result is never a behavioral PASS. There are two
# suites, never to be merged: the app's (guardrails/tests/, generated at build by Prompt #10d, checked for existence by
# AI09, run by /fix-it when it verifies a fix) and /nemo-it's own (60 cases it writes each run). Since E02-S59 (the
# owner's call, 2026-11-19) /nemo-it runs both when it has a live AI provider, and its attestation shows each in its own
# block; an app suite that cannot run is NOT TESTED, never a PASS or a FAIL. A /nemo-it run is recommended before each production deploy and nothing
# in make-it enforces it. (The build's AI endpoint probe is a separate, smaller check: this test does not say the build
# makes no AI call.)
# Contract these checks pin:
#   - AI09 is exactly the line below: what it reads, that it runs no NeMo test, that its result is never a behavioral
#     PASS, and who runs the suite.
#   - The governance doc's table of NeMo categories is exactly the eight rows below (0 by check AI09, 10 by /nemo-it).
#   - Each place that used to say the build ran "the basic suite (18 tests)" holds the true sentence, whole.
#   - Every sentence, list item or table cell in any tracked Markdown file that names the build (build-verify, "build",
#     AI09, Part A or D) together with a NeMo suite (NeMo, guardrails/tests, a behavioral test or PASS, 60 tests), or a
#     code-level result together with a pass, is one of the exact units listed below. A new such sentence fails until a
#     person adds it to the list, which is the point: the list is the review.
#   - None of the old or disproved wordings is back: an 18-test or "basic" suite, a NeMo loop or pass rate at build,
#     "no AI call at build", "every behavioral run is left to /nemo-it", "run only by /nemo-it", "/nemo-it before deploy", "/nemo-it does not use" the app's suite.
#   - Every unit outside /nemo-it's own pages that says /nemo-it runs or uses the app's generated suite is a listed
#     sentence too: each one carries the live-provider condition.
# A tripwire, not a proof, and no rule is added per bypass. It cannot catch: a claim split across two sentences; another
# word for the build ("the pipeline", "before handoff") or for a pass ("green", "cleared"); a claim in a file that is not
# Markdown; a true-looking listed sentence moved somewhere it is false; anything under a version-history heading. Every
# listed sentence is pinned, so an unrelated rewording of one means editing the list.
# /nemo-it's own pages (the skill, its template, the desktop skill) are not checked for the code-level-and-pass rule or
# the listed-sentence rule for the app's suite: those are theirs. The user-facing page (confluence-docs/08-nemo-it.md) is
# checked like any other document. The app-suite pattern is case-sensitive and knows only "runs" and "uses": an accepted limit.
# Usage: test-ai09-code-level.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on its opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

REF=.claude/make-it/references
BS=$REF/build-standards.md; GR=$REF/guardrails.md; BVS=$REF/build-verify-security.md; SG=$REF/ship-it-guide.md
BP=$REF/design-blueprint.md; RF=.claude/commands/retrofit-it.md; AT=.claude/make-it/templates/nemo-it-attestation.md
GOV=docs/AI-GOVERNANCE-HOMEGROWN.md; NM=.claude/commands/nemo-it.md
# every tracked Markdown file but the two logs of finished work (an untracked local file can't fail a run); a ROOT given
# on the command line is a plain copy with no git, so its files are found
if [ -z "${1:-}" ]; then FILES="$(git ls-files '*.md')"; else FILES="$(find . -name '*.md' | sed 's|^[.]/||' | sort)"; fi
FILES="$(printf "%s\n" "$FILES" | grep -vE '(^|/)(CHANGELOG|TODO)[.]md$')"

# one line per file, whitespace flattened: a sentence that wraps still matches
flat() { tr '\n' ' ' | tr -s ' '; }
# has FILE SENTENCE: the flattened file holds the whole sentence
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# row FILE LINE: the file holds exactly this line
row() { gq -xF -- "$2" "$1" || { echo "  no such line in $1: $2"; false; }; }
# units FILE...: file<TAB>unit, a unit being one sentence, list item, table cell or line of a code block; sections under
# a version-history heading are dropped (README.md's release notes quote the old wording as history)
units() {
  local f
  for f in "$@"; do
    awk '/^##+ /{h = ($0 ~ /^##+ (v[0-9]|.*(Version History|Changelog))/)} h {next} /^[[:space:]]*```/{c = !c} c || /^[[:space:]]*([-*+] |[0-9]+[.] |#|```|$)/{print "<BR>"} {print}' "$f" | flat |
      perl -pe 's/<BR>|\|/\n/g; s/([.!?]["\x27)]?) (?=\S)/$1\n/g' | sed -E 's/^ +//; s/ +$//' | awk -v f="$f" 'NF {print f "\t" $0}'
  done
}
U="$(units $FILES)"
# never NAME REGEX: no unit matches (case ignored)
never() { local m; m="$(printf "%s\n" "$U" | { grep -iE -- "$2" || true; })"; [ -z "$m" ] || { printf "%s\n" "$m" | cut -c1-200 | sed "s/^/  $1: /"; false; }; }

# 1. AI09 itself, the whole line
IFS= read -r AI09 <<'AI09_EOF' || true
**AI09** [AI] [FIX] **NeMo Guardrails files present and referenced (code-level)** -- Checked by reading the files: AI09 runs no NeMo Guardrails test. (1) `guardrails/config.yml` exists, names the app's AI model and references every rail file in `guardrails/rails/`. (2) The five Colang rails exist: `input_safety.co`, `output_safety.co`, `topic_control.co`, `pii_protection.co`, `factuality.co`. (3) The six test files exist in `guardrails/tests/` (`test_prompt_injection.py`, `test_jailbreak.py`, `test_toxicity_bias.py`, `test_topic_boundaries.py`, `test_pii_leakage.py`, `test_hallucination.py`), with at least 10 cases each; the build generates them and AI09 does not run them. (4) `nemoguardrails` is a dev dependency (`requirements-dev.txt`, or `guardrails/requirements.txt` for a Node app). (5) `guardrails/README.md` gives the command that runs the suite. Where a document says the guardrails are "wired", it means only this: the guardrail files exist and the config references every rail. Nothing make-it generates loads the rails at run time (not a runtime filter). A code-level result is never reported as a behavioral PASS. /fix-it runs the app's guardrail suite (guardrails/tests/) when it verifies a fix. With a live AI provider /nemo-it runs its own 60 or more cases, and the app's suite too when you pick it in /nemo-it's preflight ask; the attestation shows each in its own block (nemo-it.md, step 7b, lists when the app's suite cannot run). With no reachable AI provider, or read-only against a live system, /nemo-it's AI-safety checks are code-level only, never a PASS. The app's suite is then NOT TESTED, as it is whenever it is not picked or cannot run: the reason is given, and it is never a PASS or a FAIL. It can be NOT TESTED on an app that works: its tests need the AI provider's key, and /nemo-it gives them none.
AI09_EOF
check "AI09 is one check, and it is exactly the code-level wiring check: it runs no NeMo test, is never a behavioral PASS, and names who runs the suite" \
  '[ "$(grep -cE "^[*][*]AI09[*][*] " "$BS")" = 1 ] && row "$BS" "$AI09"'
check "AI09 names what it reads: config.yml, the five rails, the six test files, the dev dependency, the README" \
  '( for x in guardrails/config.yml input_safety.co output_safety.co topic_control.co pii_protection.co factuality.co test_prompt_injection.py test_jailbreak.py test_toxicity_bias.py test_topic_boundaries.py test_pii_leakage.py test_hallucination.py nemoguardrails guardrails/README.md; do printf "%s\n" "$AI09" | gq -F -- "\`$x\`" || { echo "  AI09 does not name $x"; exit 1; }; done )'

# 2. the governance doc's NeMo table, row by row
check "governance doc 5.5: each category is 0 tests by check AI09 and 10 by /nemo-it; the totals are 0 NeMo tests and 60" \
  'row "$GOV" "| Category | What It Tests | Build check AI09 (code-level) | /nemo-it (its own cases, minimum) |" && row "$GOV" "| 1. Prompt Injection Resistance | Adversarial input cannot override system instructions | 0 tests | 10 tests |" && row "$GOV" "| 2. Jailbreak Resistance | Role-play, encoding tricks, multi-turn escalation blocked | 0 tests | 10 tests |" && row "$GOV" "| 3. Toxicity / Bias Detection | AI outputs free of toxic, offensive, or biased content | 0 tests | 10 tests |" && row "$GOV" "| 4. Topic Boundary Enforcement | AI stays within defined domain scope | 0 tests | 10 tests |" && row "$GOV" "| 5. PII Leakage Prevention | AI does not reveal PII, secrets, or internal system details | 0 tests | 10 tests |" && row "$GOV" "| 6. Hallucination Detection | AI does not fabricate facts or present unverified claims | 0 tests | 10 tests |" && row "$GOV" "| **Total** | | **0 NeMo tests** | **60 tests** |" && [ "$(grep -cE "^[|] [1-6][.] .*[|] [0-9]+ tests [|] [0-9]+ tests [|]$" "$GOV")" = 6 ]'
check "governance doc: the stage table gives the NeMo suite to no stage, and the risk row is rated Medium (the owner's call)" \
  'row "$GOV" "| AI behavioral (NeMo suite) | 0 in build-verify'"'"'s checks (AI09 is code-level) | None | None | None |" && has "$GOV" "None of these stages'"'"' own checks runs a NeMo suite." && has "$GOV" "| **Build-verify'"'"'s checks run no NeMo Guardrails test** | Medium | Build checks the guardrail wiring in code (check AI09) and probes the AI endpoints with 3 payloads; /nemo-it runs its own 60 or more cases and, when picked, the app'"'"'s generated suite, each in its own block, when someone runs /nemo-it with a live AI provider | Run /nemo-it with a live AI provider before each production deploy: recommended, and nothing in make-it enforces it |" && ! gq -E "Full NeMo|60 NeMo tests [|]" "$GOV"'

# 3. every other place holds the true sentence, whole
FIXIT="/fix-it runs the app's guardrail suite (guardrails/tests/) when it verifies a fix"
OWN="With a live AI provider /nemo-it runs its own 60 or more cases, and the app's suite too when you pick it in /nemo-it's preflight ask; the attestation shows each in its own block (nemo-it.md, step 7b, lists when the app's suite cannot run)"
SKIP="The app's suite is then NOT TESTED, as it is whenever it is not picked or cannot run: the reason is given, and it is never a PASS or a FAIL. It can be NOT TESTED on an app that works: its tests need the AI provider's key, and /nemo-it gives them none"
NOPROV="With no reachable AI provider, or read-only against a live system, /nemo-it's AI-safety checks are code-level only, never a PASS"
NOENF="recommended before each production deploy, and nothing in make-it enforces it"
check "two suites: /fix-it runs the app's generated one; with a live AI provider /nemo-it runs it too, beside its own 60 cases, each in its own block; an app suite that cannot run is NOT TESTED" \
  '( for f in "$BS" "$BVS" "$SG" "$RF"; do has "$f" "$FIXIT" || exit 1; done ) && ( for f in "$BS" "$GR" "$BVS" "$GOV" "$SG"; do has "$f" "$OWN" && has "$f" "$NOPROV. $SKIP" || exit 1; done ) && has "$GR" "The build generates the app'"'"'s guardrail suite (guardrails/tests/) and AI09 checks it exists; AI09 does not run it. /fix-it runs it when it verifies a fix." && has "$GOV" "The build generates the app'"'"'s guardrail suite (guardrails/tests/) and AI09 checks it exists; AI09 does not run it. /fix-it runs it when it verifies a fix." && has "$RF" "$OWN." && has "$AT" "| NeMo Guardrails test suite | Yes -- 60 or more tests generated at build in guardrails/tests/; check AI09 confirms they exist and runs none of them; /fix-it runs them when it verifies a fix. /nemo-it runs them too when it has a live AI provider and the user picks it in that run: this attestation shows them in their own block (section 1.7), apart from /nemo-it'"'"'s own cases. With no reachable AI provider, or read-only against a live system, /nemo-it'"'"'s own cases are code-level checks (never a pass). Generated tests that were not picked or could not run are NOT TESTED | [PRESENT / ABSENT] |" && has "$BP" "/nemo-it writes and runs its own NeMo Guardrails cases and reports what fails; it fixes nothing" && has "$BP" "/fix-it fixes its findings and runs the app'"'"'s guardrail suite (guardrails/tests/) to verify a fix." && has README.md "these are \`/nemo-it\`'"'"'s own cases, written each run, not the generated files in the table above"'
check "a /nemo-it run is recommended and not enforced (guardrails, the ship-it guide, the governance doc, README.md, DEVOPS-GUIDE.md)" \
  '( for f in "$GR" "$SG" "$GOV" README.md; do has "$f" "$NOENF" || exit 1; done ) && has docs/DEVOPS-GUIDE.md "recommended before each production deploy, and nothing in make-it enforces a \`/nemo-it\` run" && has "$GOV" "60 or more cases that /nemo-it writes itself and runs when someone runs /nemo-it with a live AI provider: $NOENF." && has "$GOV" "| The app'"'"'s suite is generated for every AI app. A /nemo-it run is recommended, not enforced. With a live AI provider it runs /nemo-it'"'"'s own cases, and the app'"'"'s suite when picked, each in its own block |"'
check "build-verify's own checks run no NeMo test, and AI09 has no fix-and-retest loop (guardrails, the security scan, the ship-it guide, the blueprint, /retrofit-it, README.md)" \
  'has "$GR" "Build-verify'"'"'s own checks run no NeMo Guardrails test: check AI09 is code-level." && has "$GR" "Check AI09 has no fix-and-retest loop: it runs no test, so there is nothing to retest." && has "$BVS" "The probe is not a NeMo suite and gives no NeMo pass count." && has "$BVS" "Uses **code-level verification**, plus the 2b endpoint probe when the app is running" && has "$BVS" "A code-level result is never a behavioral PASS." && [ "$(head -1 "$BVS")" = "# Build-Verify Part D: Automatic Security Scan" ] && ! gq -E "Part C (runs|does|applies|is|provides)" "$BVS" && has "$SG" "build-verify'"'"'s own checks run no NeMo Guardrails test: check AI09 confirms in code that the guardrail files exist and the config references every rail, and that result is never a behavioral PASS." && has "$BP" "**Remediation flow (none in check AI09: it runs no test, so there is nothing to retest):**" && has "$RF" "No NeMo Guardrails test is run after this step: check AI09 confirms in code that the guardrail files exist and the config references every rail." && has README.md "Check AI09 has no fix-and-retest loop (it runs no test); /nemo-it reports its failures and fixes nothing."'
check "what stays: /nemo-it's 60 tests, its rule that a code-level result is never a PASS, and Prompt #10d generating the tests" \
  'has "$GR" "/nemo-it writes and runs its own FULL suite (minimum 10 test cases per category = 60 cases) before /ship-it" && has "$NM" "Code-level results are never a PASS: the behavioral tests did not run." && has "$REF/prompt-templates.md" "### Prompt #10d: NeMo Guardrails -- AI Safety Tests (always generated if AI features exist)" && has "$REF/prompt-templates.md" "Create test cases (minimum 10 per category for the full suite):" && has "$BP" "guardrails/requirements.txt for a Node app"'

# 4. a unit that names the build with the NeMo suite, or a code-level result with a pass, is one of these exact units
cat > "$TMPD/allow" <<'ALLOW_EOF'
- [ ] NeMo Guardrails files checked in code during build-verify: the guardrail files exist and the config references every rail (check AI09 runs no NeMo test; never a behavioral PASS) -- if using AI
- **AI safety** (if the app has AI features): build-verify's own checks run no NeMo Guardrails test: check AI09 confirms in code that the guardrail files exist and the config references every rail, and that result is never a behavioral PASS.
- Build-verify's own checks run no NeMo Guardrails test (check AI09 is code-level)
- Build-verify's own checks run no NeMo Guardrails test against any model.
- Build-verify's own checks run no NeMo Guardrails test: check AI09 confirms in code that the guardrail files exist and the config references every rail, never a behavioral PASS
- Build-verify's own checks run no NeMo Guardrails test: check AI09 is code-level.
- No NeMo Guardrails test is run after this step: check AI09 confirms in code that the guardrail files exist and the config references every rail.
- The build generates the app's guardrail suite (guardrails/tests/) and AI09 checks it exists; AI09 does not run it.
(3) The six test files exist in `guardrails/tests/` (`test_prompt_injection.py`, `test_jailbreak.py`, `test_toxicity_bias.py`, `test_topic_boundaries.py`, `test_pii_leakage.py`, `test_hallucination.py`), with at least 10 cases each; the build generates them and AI09 does not run them.
**AI09** [AI] [FIX] **NeMo Guardrails files present and referenced (code-level)** -- Checked by reading the files: AI09 runs no NeMo Guardrails test.
**Build-verify's checks run no NeMo Guardrails test**
/nemo-it writes and runs its own 60 or more NeMo Guardrails cases across 6 categories, and runs the app's generated suite in a separate block when picked (nemo-it.md, step 7b, lists when the suite cannot run), when it is run with a live AI provider; build-verify's check AI09 confirms in code that the guardrail files exist and the config references every rail, and runs none
A code-level result is never a behavioral PASS.
A code-level result is never reported as a behavioral PASS.
Build checks the guardrail wiring in code (check AI09) and probes the AI endpoints with 3 payloads; /nemo-it runs its own 60 or more cases and, when picked, the app's generated suite, each in its own block, when someone runs /nemo-it with a live AI provider
Build-verify's check AI09 confirms in code that the guardrail files exist and the config references every rail, and runs no NeMo test
Build-verify's own checks run no NeMo Guardrails test: check AI09 confirms in code that the guardrail files exist and the config references every rail, and that result is never a behavioral PASS.
Build-verify's own checks run no NeMo Guardrails test.
Check AI09 confirms in code that the guardrail files exist and the config references every rail; that result is never a behavioral PASS.
Code-level check (AI09) that the guardrail files exist and the config references every rail: files read, no NeMo test run by the check, never a behavioral PASS
NeMo Guardrails behavioral testing (6 categories) is run by /nemo-it on its own cases, not by build-verify's checks
sanitizePromptInput() strips injection patterns; `<user_input>` delimiter tags; system prompt anti-injection instructions; jailbreak resistance instructions; NeMo Guardrails prompt injection tests (10 of /nemo-it's own cases; none run by build-verify's checks)
The build generates a separate suite in the app (guardrails/tests/): check AI09 confirms it exists and does not run it, /fix-it runs it when it verifies a fix, and /nemo-it runs it too when it has a live AI provider and the user picks it, in its own block of the attestation (nemo-it.md, step 7b, lists when it cannot).
The build generates the app's guardrail suite (guardrails/tests/) and AI09 checks it exists; AI09 does not run it.
The build's AI endpoint probe (3 payloads, section 6.1 Phase 2b) is a separate, smaller check: it is not a NeMo suite and gives no NeMo pass count
The build's AI endpoint probe (3 payloads, section 6.1 Phase 2b) is a separate, smaller check: it is not a NeMo suite and gives no NeMo pass count.
Uses **code-level verification**, plus the 2b endpoint probe when the app is running (not a NeMo behavioral suite -- that requires a live AI provider which may not be configured during build).
With no reachable AI provider, or read-only against a live system, /nemo-it's AI-safety checks are code-level only, never a PASS.
With a live AI provider /nemo-it runs its own 60 or more cases, and the app's suite too when you pick it in /nemo-it's preflight ask; the attestation shows each in its own block (nemo-it.md, step 7b, lists when the app's suite cannot run).
With a live AI provider, and when you pick it, /nemo-it also runs the app's guardrail suite (guardrails/tests/), in its own block (nemo-it.md, step 7b, lists when it cannot); it never edits a generated test
60 or more of /nemo-it's own cases per model when someone runs /nemo-it with a live AI provider, and, when picked, the app's generated suite counted separately in the same run; none in build-verify's checks (AI09 is code-level wiring only)
/nemo-it runs its own 60 or more cases and, when picked, the app's generated suite, each in its own block, when someone runs /nemo-it with a live AI provider: recommended before each production deploy, and nothing in make-it enforces it.
Yes -- 60 or more tests generated at build in guardrails/tests/; check AI09 confirms they exist and runs none of them; /fix-it runs them when it verifies a fix.
ALLOW_EOF
NEMOW='NeMo|guardrails/tests|[Bb]ehaviou?ral (tests?|suite|testing|PASS|runs?)|[Ss]ix (NeMo )?categories|\b60\+? (or more )?(tests|cases)\b|guardrail suite'
BUILDW='[Bb]uild-verify|\b[Bb]uilds?\b|\bAI09\b|\bPart [AD]\b'
# unlisted LIST: the units of LIST (file<TAB>unit) that are not in the allow list, as file<TAB>unit
unlisted() { printf "%s\n" "$1" | awk -F'\t' 'NR == FNR {a[$0] = 1; next} NF && !(substr($0, length($1) + 2) in a)' "$TMPD/allow" -; }
BN="$(unlisted "$(printf "%s\n" "$U" | { grep -E "	.*($NEMOW)" || true; } | { grep -E "	.*($BUILDW)" || true; })")"
check "every unit that names the build together with the NeMo suite is a listed, reviewed sentence" \
  '[ -z "$BN" ] || { printf "%s\n" "$BN" | cut -c1-220 | sed "s/^/  not listed: /"; false; }'
NEMOPAGES='^([.]claude/commands/nemo-it[.]md|[.]claude/make-it/templates/nemo-it-attestation[.]md|desktop/skills/nemo-it/SKILL[.]md)	'
CP="$(unlisted "$(printf "%s\n" "$U" | { grep -vE "$NEMOPAGES" || true; } | { grep -iE "	.*(code-level|\bAI09\b|wiring checks?)" || true; } | { grep -iE "	.*\bpass(ed|es|ing)?\b" || true; })")"
check "every unit outside /nemo-it's own pages that names a code-level result (or AI09) together with a pass is a listed, reviewed sentence" \
  '[ -z "$CP" ] || { printf "%s\n" "$CP" | cut -c1-220 | sed "s/^/  not listed: /"; false; }'
check "the list has no dead entry: each listed unit is in a file" \
  'D="$(printf "%s\n" "$U" | cut -f2- | awk "NR == FNR {a[\$0] = 1; next} !(\$0 in a)" - "$TMPD/allow")"; [ -z "$D" ] || { printf "%s\n" "$D" | cut -c1-200 | sed "s/^/  dead: /"; false; }'

# 5. nobody says it the old way, in any Markdown file
OLD18='\b18\+? (basic |NeMo )?tests?\b|\b18 test cases\b|\b18 \(build\)|\(18\+? tests\)'
BASIC='\bbasic (test )?suite\b|\bBASIC checks\b|\bbasic checks\b|\bNeMo basic\b|\(basic\)|\b3 basic\b|\(18 basic|\bbasic \(smoke test\)'
LOOP='self-healing at build|100% at build|self-healing remediation|remediation flow \(self-healing|self-healing loop retests|self-healing retests|fix(es)? what fails'
DISPROVED='no AI call is made at build|makes no AI call|every behaviou?ral run is left to|run only by /nemo-it|\bnever at build\b|/nemo-it before deploy|run by /nemo-it before deploy|no behaviou?ral test runs at build|run by /nemo-it, and by /fix-it|tests are generated at build and run when someone runs /nemo-it|runs (the suite|guardrails/tests/) again\b'
check "no file says an 18-test or \"basic\" NeMo suite" 'never "old claim" "	.*($OLD18)" && never "old claim" "	.*($BASIC)"'
check "no file gives the build a NeMo fix-and-retest loop, or a pass rate" 'never "build loop" "	.*($LOOP)"'
# Since E02-S59 /nemo-it runs the app's generated suite too, when it has a live AI provider. A unit outside /nemo-it's
# own pages that says it runs or uses that suite is one of the listed units (each carries the condition); a unit that
# says it does not, or that no attestation is based on that suite, is the old story.
NEMOGEN='/nemo-it[^.|]{0,60}\b(runs|uses)\b[^.|]{0,40}(guardrails/tests|the app.s (guardrail |generated )?suite|generated)|(guardrails/tests|generated)[^.|]{0,40}\brun by /nemo-it'
GN="$(unlisted "$(printf "%s\n" "$U" | { grep -vE "$NEMOPAGES" || true; } | { grep -E "	.*($NEMOGEN)" || true; })")"
check "every unit outside /nemo-it's own pages that says /nemo-it runs or uses the app's generated suite is a listed, reviewed sentence" \
  '[ -z "$GN" ] || { printf "%s\n" "$GN" | cut -c1-220 | sed "s/^/  not listed: /"; false; }'
NEMONOT='/nemo-it`? (does not|doesn.t|never) (use|run)s? (it|them|the app|guardrails/tests|the generated)|it does not use the app.s guardrails/tests|not the app.s generated|no attestation is based on|and uses /nemo-it.s own cases|the attestation is based on those'
check "no file says /nemo-it does not use the app's generated suite, or that no attestation is based on it" 'never "old story" "	.*($NEMONOT)"'
check "no file says what round 1 of review disproved: no AI call at build, every run left to /nemo-it, /nemo-it as a step before deploy" 'never "disproved" "	.*($DISPROVED)"'

# 6. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the Markdown files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  # add FILE AFTER LINE: the same, with LINE added after the first line that starts with AFTER
  add() { A="$2" L="$3" opp "$1" 's/^(\Q$ENV{A}\E[^\n]*\n)/$1$ENV{L}\n/m'; }
  check "(control) fails with the old AI09 line back, and with \"recorded as passed\" added to AI09" \
    'opp "$BS" "s/^\*\*AI09\*\* [^\n]*/**AI09** [AI] [FIX] **NeMo Guardrails** -- guardrails\/ directory, config.yml, Colang rails. Basic suite (18 tests) passes./m" && opp "$BS" "s/^(\*\*AI09\*\* [^\n]*)/\$1 When all five hold, AI09 is recorded as passed for AI safety./m"'
  check "(control) fails with the claim back in the governance doc only: 3 tests per category with the totals left alone, and the old totals row" \
    'opp "$GOV" "s/\| 0 tests \| 10 tests \|/| 3 tests | 10 tests |/g" && opp "$GOV" "s/\*\*0 NeMo tests\*\*/**18 tests**/"'
  check "(control) fails with the old claim in a file nobody listed (CLAUDE.md), and reworded with no old phrase in it, with and without a hyphen after NeMo (guardrails.md)" \
    'add CLAUDE.md "- The user NEVER needs" "- Build-verify runs the NeMo Guardrails basic suite (18 tests) and fixes what fails" && add "$GR" "- 6 test categories" "- Build-verify also exercises the six NeMo categories against the primary model, three prompts each, and repairs whatever fails" && add "$GR" "- 6 test categories" "- Build-verify runs the NeMo-Guardrails suite and fixes failures before handoff"'
  check "(control) fails when the build runs the suite once a provider or key is set (the ship-it guide, guardrails.md)" \
    'add "$SG" "### What make-it runs before /ship-it" "When an AI key is set, build-verify launches pytest guardrails/tests/ and loops on failures up to three times." && add "$GR" "- 6 test categories" "- Build-verify runs no NeMo test unless an AI provider is set; then it runs the behavioral suite"'
  check "(control) fails with a code-level result made a PASS: in AI09, and in a sentence that also says \"never\"" \
    'opp "$BS" "s/is never reported as a behavioral PASS/is reported as a behavioral PASS/" && add "$BVS" "**When this runs:**" "Build-verify treats it as a behavioral PASS anyway when every wiring check is green, and never asks /nemo-it."'
  check "(control) fails with /nemo-it's two suites dropped from AI09, with the generated tests \"run by /nemo-it\" and no provider condition in the attestation template, and with the not-enforced sentence dropped from the governance doc" \
    'opp "$BS" "s/ With a live AI provider \/nemo-it runs its own 60 or more cases, and the app.s suite too when you pick it in \/nemo-it.s preflight ask; the attestation shows each in its own block \(nemo-it[.]md, step 7b, lists when the app.s suite cannot run\)\.//" && opp "$AT" "s/\/fix-it runs them when it verifies a fix\. \/nemo-it runs them too when it has a live AI provider and the user picks it in that run: [^|]*/run by \/nemo-it, and by \/fix-it when it verifies a fix /" && opp "$GOV" "s/60 or more cases that \/nemo-it writes itself and runs when someone runs \/nemo-it with a live AI provider: recommended before each production deploy, and nothing in make-it enforces it\./60 tests, run by \/nemo-it before deploy./"'
  check "(control) fails when /nemo-it's use of the app's suite is said with no provider condition (an unlisted sentence), and with the old \"does not use it\" back" \
    'add "$GR" "- 6 test categories" "- /nemo-it runs the app'"'"'s guardrail suite on every scan" && add "$GR" "- 6 test categories" "- /nemo-it does not use the app'"'"'s suite: it has its own" && add "$GOV" "None of these stages" "No attestation is based on the suite in the app."'
  check "(control) fails with \"no AI call\" back, with /nemo-it's 60 made 30, and with \"Part C\" back in the security scan" \
    'opp "$GR" "s/own checks run no NeMo Guardrails test: check AI09 is code-level\./own checks run no NeMo Guardrails test and make no AI call: check AI09 is code-level./" && opp "$GR" "s/= 60 cases\) before/= 30 cases) before/" && opp "$BVS" "s/Part D provides a/Part C provides a/"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
