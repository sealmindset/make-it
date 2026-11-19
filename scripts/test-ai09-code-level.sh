#!/usr/bin/env bash
# E02-S56 (the owner's call, 2026-11-19): check AI09 is code-level only. The build reads the files to confirm the NeMo
# guardrails are present and wired; it runs no NeMo test, makes no AI call and has no fix-and-retest loop for them. A
# code-level result is never a behavioral PASS. Every behavioral run is left to /nemo-it (the test files are still
# generated at build, by Prompt #10d).
# Contract these checks pin:
#   - AI09 names what it reads (config.yml, the five rails, the six test files, the dev dependency, the README) and says,
#     in whole sentences, that nothing is run, that its result is never a behavioral PASS, and whose the run is.
#   - Every place that used to say the build ran "the basic suite (18 tests)" now says the same thing as AI09.
#   - None of them says it the old way again: an 18-test or "basic" suite, the build running a NeMo or behavioral test
#     (with or without a provider), a code-level result called a PASS, a NeMo fix-and-retest loop at build.
#   - /nemo-it's own claims stay: the 60 tests, and "Code-level results are never a PASS".
# A tripwire, not a proof: it reads wording, one sentence or table cell at a time. Version history is not scanned.
# Usage: test-ai09-code-level.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on six opposites.
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
FILES="$BS $GR $BVS $SG $BP $RF $AT $GOV README.md docs/DEVOPS-GUIDE.md docs/PENTEST-READINESS.md .claude/commands/make-it.md $REF/prompt-templates.md $REF/fix-strategies.md"

# one line per file, whitespace flattened: a sentence that wraps still matches
flat() { tr '\n' ' ' | tr -s ' '; }
# has FILE SENTENCE: the flattened file holds the whole sentence
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# units FILE...: file<TAB>unit, a unit being one sentence, list item or table cell; sections under a version-history heading are
# dropped (README.md's release notes quote the old wording as history)
units() {
  local f
  for f in "$@"; do
    awk '/^##+ /{h = ($0 ~ /^##+ (v[0-9]|.*(Version History|Changelog))/)} h {next} /^[[:space:]]*([-*+] |[0-9]+[.] |#|$)/{print "<BR>"} {print}' "$f" | flat |
      perl -pe 's/<BR>|\|/\n/g; s/([.!?]["\x27)]?) (?=\S)/$1\n/g' | awk -v f="$f" 'NF {print f "\t" $0}'
  done
}
U="$(units $FILES)"
# never NAME REGEX [EXCEPT]: no unit matches (case ignored), but the units that match EXCEPT
never() { local m; m="$(printf "%s\n" "$U" | { grep -iE -- "$2" || true; } | { grep -viE -- "${3:-^$}" || true; })"; [ -z "$m" ] || { printf "%s\n" "$m" | cut -c1-200 | sed "s/^/  $1: /"; false; }; }

# 1. AI09 itself
AI09="$(grep -E '^[*][*]AI09[*][*] ' "$BS" || true)"
a9() { printf "%s\n" "$AI09" | gq -F -- "$1" || { echo "  missing in AI09: $1"; false; }; }
check "AI09 is one check, a [FIX], named as the code-level wiring check" \
  '[ "$(printf "%s\n" "$AI09" | grep -c .)" = 1 ] && a9 "**AI09** [AI] [FIX] **NeMo Guardrails wiring (code-level)** -- Checked by reading the files."'
check "AI09 runs nothing: no NeMo test, no AI call; the test files are generated and not run" \
  'a9 "No NeMo test is run and no AI call is made at build." && a9 "they are generated here and not run."'
check "AI09 names what it reads: config.yml and what it references, the five rails, the six test files, the dev dependency, the README" \
  'a9 "\`guardrails/config.yml\` exists, names the app'"'"'s AI model and references every rail file in \`guardrails/rails/\`." && ( for x in input_safety.co output_safety.co topic_control.co pii_protection.co factuality.co test_prompt_injection.py test_jailbreak.py test_toxicity_bias.py test_topic_boundaries.py test_pii_leakage.py test_hallucination.py; do a9 "\`$x\`" || exit 1; done ) && a9 "with at least 10 cases each" && a9 "\`nemoguardrails\` is a dev dependency" && a9 "\`guardrails/README.md\` gives the command that runs the suite."'
check "AI09's result is never a behavioral PASS, and every behavioral run is left to /nemo-it" \
  'a9 "A code-level result is never reported as a behavioral PASS: every behavioral run is left to /nemo-it."'

# 2. every other place says the same
check "guardrails.md: build-verify runs no NeMo test, the run is /nemo-it's, and there is no fix-and-retest loop at build" \
  'has "$GR" "Build-verify runs no NeMo test and makes no AI call: check AI09 is code-level." && has "$GR" "that result is never a behavioral PASS" && has "$GR" "every behavioral run is left to /nemo-it" && has "$GR" "No fix-and-retest loop at build-verify: no test is run there, so there is nothing to retest." && has "$GR" "No NeMo test is run at build-verify: every behavioral run is left to /nemo-it" && has "$GR" "Build-verify runs no NeMo test against any model (check AI09 is code-level)."'
check "build-verify-security.md: Part D and check AI09 are both code-level, neither a behavioral PASS; the file calls itself Part D throughout" \
  'has "$BVS" "Part D does code-level verification only, and so does Part A'"'"'s check AI09 (the guardrails are present and wired)." && has "$BVS" "A code-level result is never a behavioral PASS." && has "$BVS" "Every behavioral run is left to /nemo-it." && [ "$(head -1 "$BVS")" = "# Build-Verify Part D: Automatic Security Scan" ] && ! gq -E "Part C (runs|does|applies|is|provides)" "$BVS"'
check "ship-it-guide.md, design-blueprint.md, retrofit-it.md: no NeMo test at build, the wiring is checked in code" \
  'has "$SG" "build-verify runs no NeMo Guardrails test: check AI09 confirms in code that the guardrails are present and wired, and that result is never a behavioral PASS." && has "$SG" "Every behavioral run is left to /nemo-it: it runs the full suite" && has "$BP" "| Build-verify | During /make-it build | Code-level wiring check (AI09): files read, no test run, never a behavioral PASS | 0 |" && has "$BP" "**Remediation flow (none at build-verify: no test is run there, so there is nothing to retest):**" && has "$BP" "NeMo Guardrails wiring checked in code during build-verify (check AI09; no test is run, never a behavioral PASS)" && has "$RF" "No NeMo Guardrails test is run after this step: check AI09 confirms in code that the guardrails are present and wired, and every behavioral run is left to /nemo-it."'
check "what a GRC reviewer reads (attestation template, governance doc): generated at build, run only by /nemo-it, 0 behavioral tests at build" \
  'has "$AT" "| NeMo Guardrails test suite | Yes -- 60 tests generated at build and the wiring checked in code (check AI09); run only by /nemo-it, never at build | [PRESENT / ABSENT] |" && has "$GOV" "At build no behavioral test runs: check AI09 confirms in code that the guardrails are present and wired, and that result is never a behavioral PASS |" && has "$GOV" "| **Total** | | **0 behavioral tests** | **60 tests** |" && has "$GOV" "No behavioral test runs at build, so the build has no fix-and-retest loop for these." && has "$GOV" "| No pass rate at build; /nemo-it failures are reported, not fixed |" && has "$GOV" "| AI behavioral | 0 (code-level wiring only) |" && has "$GOV" "| **No AI behavioral testing at build** | Low | Build checks the guardrail wiring in code (check AI09, 0 behavioral tests); /nemo-it runs the 60 tests before deploy |"'
check "README.md, DEVOPS-GUIDE.md, PENTEST-READINESS.md: no NeMo test at build" \
  'has README.md "No NeMo test runs during build-verify: check AI09 confirms in code that the guardrails are present and wired, never a behavioral PASS" && has README.md "No fix-and-retest loop at build-verify (no test is run there); /nemo-it reports its failures and fixes nothing" && has docs/DEVOPS-GUIDE.md "Build-verify checks the wiring in code only (check AI09) and runs no test |" && has docs/PENTEST-READINESS.md "NeMo Guardrails runs 60 tests across 6 categories in /nemo-it, and none at build (the wiring is checked in code)"'
check "/nemo-it's own claims stay: the 60 tests, a code-level result is never a PASS, and Prompt #10d still generates the tests" \
  'has "$GR" "/nemo-it runs the FULL suite (minimum 10 test cases per category = 60 tests) before /ship-it" && has "$NM" "Code-level results are never a PASS: the behavioral tests did not run." && has "$REF/prompt-templates.md" "Create test cases (minimum 10 per category for the full suite):" && has "$GOV" "60 tests, run by /nemo-it before deploy."'

# 3. nobody says it the old way
OLD18='\b18\+? (basic |NeMo )?tests?\b|\b18 test cases\b|\b18 \(build\)|\(18\+? tests\)'
BASIC='\bbasic (test )?suite\b|\bBASIC checks\b|\bbasic checks\b|\bNeMo basic\b|\(basic\)|\b3 basic\b|\(18 basic|\bbasic \(smoke test\)'
# only a run of something is a claim: a unit that says "no NeMo test" or "no behavioral test" is the rule itself
NORUN='\bno (NeMo|behaviou?ral)( Guardrails)? tests?\b'
RUNS='(build-verify|\bbuild\b|part [ad]\b)[^.]{0,80}\bruns? (the |its |a |all |those |these |[0-9]+ )?(NeMo|behaviou?ral|guardrails? test)|(NeMo|behaviou?ral) (tests?|suite)[^.]{0,40}\b(run|runs|ran|pass|passes) (at|during|in) (the )?build|\btests?\b[^.]{0,30}\b(at|in) build-verify, [0-9]'
LOOP='self-healing at build|100% at build|self-healing remediation|remediation flow \(self-healing|self-healing loop retests|self-healing retests|fix(es)? what fails'
check "no file says an 18-test or \"basic\" NeMo suite" 'never "old claim" "	.*($OLD18)" && never "old claim" "	.*($BASIC)"'
check "no file says the build runs a NeMo or behavioral test (with a provider or without)" 'never "build run" "	.*($RUNS)" "	.*($NORUN)"'
check "no file gives the build a NeMo fix-and-retest loop, or a pass rate" 'never "build loop" "	.*($LOOP)"'
# a unit that says "behavioral PASS", or "code-level" and "PASS" together, says "never"
CLP="$(printf "%s\n" "$U" | { grep -E "	.*(behaviou?ral PASS|[Cc]ode-level.*\bPASS\b|\bPASS\b.*[Cc]ode-level)" || true; } | { grep -viE "	.*\bnever\b" || true; })"
check "no file calls a code-level result a PASS" '[ -z "$CLP" ] || { printf "%s\n" "$CLP" | cut -c1-200 | sed "s/^/  pass: /"; false; }'

# 4. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the scanned files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES "$NM" | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  check "(control) fails with the old AI09 line back" \
    'opp "$BS" "s/^\*\*AI09\*\* [^\n]*/**AI09** [AI] [FIX] **NeMo Guardrails** -- guardrails\/ directory, config.yml, Colang rails. Basic suite (18 tests) passes./m"'
  check "(control) fails with the claim back in the governance doc only (the totals row)" \
    'opp "$GOV" "s/\*\*0 behavioral tests\*\*/**18 tests**/"'
  check "(control) fails with a code-level result made a PASS" \
    'opp "$BS" "s/A code-level result is never reported as a behavioral PASS/A code-level result is reported as a behavioral PASS/"'
  check "(control) fails when the build runs the behavioral tests once a provider is set" \
    'opp "$GR" "s/(- No NeMo test is run at build-verify[^\n]*\n)/\$1- When an AI provider is set, build-verify runs the behavioral tests too\n/"'
  check "(control) fails with the \"left to /nemo-it\" sentence dropped from AI09" \
    'opp "$BS" "s/: every behavioral run is left to \/nemo-it\././"'
  check "(control) fails with the 18 build tests back in the attestation template, and with \"Part C\" back in the security scan" \
    'opp "$AT" "s/run only by \/nemo-it, never at build/18 tests in build-verify, 60 in \/nemo-it/" && opp "$BVS" "s/Part D runs whatever checks/Part C runs whatever checks/"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
