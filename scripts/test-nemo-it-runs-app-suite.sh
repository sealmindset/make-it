#!/usr/bin/env bash
# E02-S59 (the owner's call, 2026-11-19): "Run both. /nemo-it runs the app's generated tests and rails, and its own
# cases, and the attestation shows each." A /make-it build writes a guardrail suite into each AI app (Prompt #10d:
# guardrails/config.yml, guardrails/rails/, guardrails/tests/). /nemo-it used to write its own cases and never touch
# that suite, while its result went into the AI-safety attestation.
# Contract these checks pin:
#   - nemo-it.md has a step (Phase 3, step 7b) that runs the app's suite with pytest, between its own six categories
#     and the step that compiles the results. The two suites are two blocks, never merged.
#   - The suite runs only with a live AI provider, PASSIVE_ONLY exactly false, a clean hostile-code check and the tools
#     already installed. Nothing is installed in that step.
#   - What ran is read from the test runner's result file. A suite that could not run is NOT TESTED with the reason:
#     never a PASS, never a FAIL. A test that ran and failed is a FAIL.
#   - /nemo-it never edits a generated test, a rail or any project file, and keeps pytest's own files out of the project.
#   - The overall AI-safety result is the worst of all the blocks.
#   - The attestation template has the second block and a NOT TESTED status word.
#   - The documents that said "/nemo-it does not use it" say the new sentence, whole, and none says the old one.
# A tripwire, not a proof: it reads wording, it does not run /nemo-it. It cannot catch a rule that is written whole and
# contradicted elsewhere in words the must-not patterns do not name.
# Usage: test-nemo-it-runs-app-suite.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it.
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

REF=.claude/make-it/references
BS=$REF/build-standards.md; GR=$REF/guardrails.md; BVS=$REF/build-verify-security.md; SG=$REF/ship-it-guide.md
BP=$REF/design-blueprint.md; RF=.claude/commands/retrofit-it.md; AT=.claude/make-it/templates/nemo-it-attestation.md
GOV=docs/AI-GOVERNANCE-HOMEGROWN.md; NM=.claude/commands/nemo-it.md
if [ -z "${1:-}" ]; then FILES="$(git ls-files '*.md')"; else FILES="$(find . -name '*.md' | sed 's|^[.]/||' | sort)"; fi
FILES="$(printf "%s\n" "$FILES" | grep -vE '(^|/)(CHANGELOG|TODO)[.]md$')"

flat() { tr '\n' ' ' | tr -s ' '; }
# has FILE SENTENCE: the flattened file holds the whole sentence
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# step 7b of nemo-it.md, flattened: from its heading to the heading of step 8 (awk reads the whole file, no early exit)
S7="$(awk '/^\*\*7b[.] Run the app.s own generated guardrail suite/{on=1} on && /^\*\*8[.] Compile AI safety results/{on=0} on' "$NM" | flat)"
sen() { printf "%s" "$S7" | gq -F -- "$1" || { echo "  missing in step 7b: $1"; false; }; }
no7() { ! printf "%s" "$S7" | gq -iE -- "$1" || { echo "  must not be in step 7b: $1"; false; }; }

# 1. the step exists, where it belongs
check "nemo-it.md has step 7b, after its own six categories and before the results are compiled" \
  '[ -n "$S7" ] && [ "$(grep -cE "^\*\*7b[.] Run the app.s own generated guardrail suite" "$NM")" = 1 ] && [ "$(grep -nE "^\*\*7[.] Test Category 6" "$NM" | cut -d: -f1)" -lt "$(grep -nE "^\*\*7b[.] " "$NM" | cut -d: -f1)" ]'
check "step 7b: two blocks, never merged, and every number says which suite it came from" \
  'sen "The two are never merged: each has its own block, its own per-category results and its own counts, and every number says which suite it came from." && sen "the counts of the two suites are never added together" && no7 "merged into one|one combined|(sum|total)s? (of|across) (the|both) (two )?(suites|blocks)"'
check "step 7b: the app's suite runs once, not once per model, and says why" \
  'sen "**Once, not once per model.**" && sen "they do not go through the running app, so restarting the app onto its fallback (step 0b) changes nothing for them"'

# 2. when it runs
check "step 7b: it runs only when all five conditions hold, each written whole" \
  'sen "**Run it only when all of these hold.** Otherwise nothing is run and the block is NOT TESTED with the first reason that applies:" && sen "\`guardrails/tests/\` holds at least one \`test_*.py\` file and \`guardrails/config.yml\` exists" && sen "step 0 chose behavioral tests: the AI provider is configured and reachable" && sen "\`PASSIVE_ONLY=false\`" && sen "the hostile-code check found nothing" && sen "\`python -m pytest\` and \`nemoguardrails\` both load in that python"'
check "step 7b: no provider, a live system, no suite, missing files and missing tools each have their NOT TESTED reason" \
  'sen "\"No reachable AI provider.\"" && sen "\"Production detected.\"" && sen "\"This project has no generated guardrail suite (no \`guardrails/tests/\`).\"" && sen "\"\`guardrails/config.yml\` is missing.\"" && sen "is not installed.\"" && sen "\"The hostile-code check found something, so I did not run the project'"'"'s test code.\""'
check "step 7b: nothing is installed there, and never from the project's requirements files" \
  'sen "Nothing is installed in this step: the only installs are the ones picked in preflight step 7'"'"'s ask (guardrail 9), and nothing is ever installed from the project'"'"'s own requirements files." && no7 "pip3? install|npm install|-r [^ ]*requirements"'
check "nemo-it.md: the pytest run is guarded by PASSIVE_ONLY exactly false, keeps its files out of the project, and one broken file does not stop the rest" \
  'L="$(grep -F "python -m pytest guardrails/tests/" "$NM" | grep -vF "\`")" && [ "$(printf "%s\n" "$L" | grep -c .)" = 1 ] && printf "%s\n" "$L" | gq -F "[ \"\$PASSIVE_ONLY\" = \"false\" ] && PYTHONDONTWRITEBYTECODE=1 python -m pytest guardrails/tests/ -v -p no:cacheprovider --continue-on-collection-errors" && gq -F -- "--junitxml=/tmp/nemo-it-app-suite/results.xml" "$NM"'
check "nemo-it.md: preflight step 7 checks the tools the app's suite needs, so the one existing ask covers them" \
  'gq -E "^\[ -d guardrails/tests \] && .*python -m pytest --version.*MISSING: pytest.*import nemoguardrails.*MISSING: nemoguardrails" "$NM"'

# 3. what counts as run, pass, fail and not tested
check "step 7b: what ran comes from the test runner's own result file, and no result file counts as 0" \
  'sen "What ran is read from the test runner'"'"'s own result file, never from the command having been issued (guardrail 11)." && gq -F "|| echo \"APP_SUITE_RAN=0\"" "$NM" && sen "\`APP_SUITE_RAN=0\`: the whole block is NOT TESTED"'
check "step 7b: a suite, file or case that could not run is NOT TESTED with the reason, never a PASS and never a FAIL" \
  'sen "**A suite that could not run is NOT TESTED with the reason, never a PASS and never a FAIL.**" && sen "FAIL means the test ran and the guardrail failed; NOT TESTED means the test could not run." && sen "an \`error\` (the file could not be loaded, a module is missing, a fixture broke) is NOT TESTED" && sen "A provider error is not a result." && no7 "(recorded|counted|reported|listed) as (a )?(PASS|FAIL|passed|failed)\b"'
check "step 7b: a category is PASS only when its file ran and every case passed" \
  'sen "PASS only when its file ran at least one case and every case passed" && sen "One of the six files missing: that category is NOT TESTED"'
check "step 7b: /nemo-it never edits a generated test, a rail or a project file, and never reruns with tests left out" \
  'sen "**Report only.** Never edit, fix, skip, rename or delete a generated test, a rail, \`guardrails/config.yml\` or any other project file" && sen "It can be the test'"'"'s own fault; /nemo-it does not judge or change it." && sen "The suite is not rerun with tests left out." && no7 "--deselect|--lf\b|may (be )?(edit|fix|chang|rewrit)|(edit|fix|rewrite|repair)s? the (failing |generated |broken )?test"'
check "step 7b: the project is checked against its state before the run, and anything the run wrote is listed, not removed" \
  'sen "git status --porcelain --untracked-files=all > /tmp/nemo-it-app-suite/before.txt" && sen "Any difference: list each path in the block" && sen "They are left in place: nothing is deleted or reverted here."'
check "step 7b: the overall AI-safety result is the worst of all the blocks, and a NOT TESTED block never counts as a pass" \
  'sen "The overall AI-safety result is the worst of all the blocks: the primary'"'"'s, the fallback'"'"'s (step 0b) and the app'"'"'s suite." && sen "A block that is NOT TESTED never counts as a pass" && no7 "(better|best) of"'
check "step 7b: JSON and JUnit keep the suites apart, and a NOT TESTED case is skipped, never passed or failed" \
  'sen "\`\"suite\": \"app-generated\"\`" && sen "\`\"suite\": \"nemo-it-own\"\`" && sen "<testsuite name=\"AI Safety -- app'"'"'s generated suite (guardrails/tests/)\">" && sen "\`<skipped message=\"[reason]\"/>\`, never a pass and never a \`<failure>\`"'
check "nemo-it.md outside the step: the phase header, the attestation outline and reminder 10 say the app's suite needs a live provider and is otherwise NOT TESTED" \
  'has "$NM" "**The app'"'"'s generated guardrail suite (step 7b) sends prompts to the AI service too: with no reachable AI provider, or PASSIVE_ONLY=true, it is not run and its block is NOT TESTED with that reason -- never a PASS**" && has "$NM" "Then one more block, always present when AI features were detected: \"App'"'"'s generated suite (guardrails/tests/)\"" && has "$NM" "The app'"'"'s generated suite (Phase 3, step 7b) needs the live provider too: without one it is NOT TESTED, never a PASS."'

# 4. the attestation template
check "attestation template: the app's suite has its own section and dashboard row, apart from /nemo-it's own six" \
  'gq -E "^### 1[.]7 The app.s generated guardrail suite \(NEMO-APP\)" "$AT" && gq -E "^\| 24 \| NeMo Guardrails AI Safety +\| App.s generated suite \(guardrails/tests/\) +\| NEMO-APP +\| \[PASS/FAIL/NO FINDINGS/NOT TESTED/NA\]" "$AT" && has "$AT" "Sections 1.1 to 1.6 are /nemo-it'"'"'s own cases. This section is the app'"'"'s own suite, generated at build. The two are never merged, and no count here is added to a count above." && [ "$(grep -cE "^\| (Prompt Injection|Jailbreak|Toxicity / Bias|Topic Boundaries|PII Leakage|Hallucination) +\| \`guardrails/tests/test_[a-z_]+[.]py\` +\| \[PASS / FAIL / NO FINDINGS / NOT TESTED\]" "$AT")" = 6 ]'
check "attestation template: true in every case -- both ran, the app's suite NOT TESTED, no provider" \
  'has "$AT" "- **Block status:** [PASS / FAIL / NO FINDINGS / NOT TESTED]" && has "$AT" "- **If NOT TESTED, why:** [REASON" && has "$AT" "- **Overall AI-safety result (the worst of all the blocks: /nemo-it'"'"'s own cases per model, and this one):**" && has "$AT" "| NOT TESTED | The app'"'"'s generated suite, one of its files or one of its cases could not run (no suite, a missing file or tool, no reachable AI provider, read-only scan, a provider error); the reason is stated. Not a pass, and not a fail |" && has "$AT" "| NeMo Guardrails test suite | Yes -- 60 or more tests generated at build in guardrails/tests/; check AI09 confirms they exist and runs none of them; /fix-it runs them when it verifies a fix. /nemo-it runs them too when it has a live AI provider: this attestation shows them in their own block (section 1.7), apart from /nemo-it'"'"'s own cases. With no reachable AI provider, or read-only against a live system, /nemo-it'"'"'s own cases are code-level checks (never a pass) and the generated tests are NOT TESTED | [PRESENT / ABSENT] |"'

# 5. the documents tell the same story, in the same words
OWN="/nemo-it runs it too: with a live AI provider it runs the app's suite and its own 60 or more cases, and the attestation shows each in its own block"
SKIP="The app's suite is then NOT TESTED, as it is whenever it cannot run: the reason is given, and it is never a PASS or a FAIL"
NOPROV="With no reachable AI provider, or read-only against a live system, /nemo-it's AI-safety checks are code-level only, never a PASS"
check "AI09, the guardrails rule, the security scan, the ship-it guide, /retrofit-it and the governance doc say /nemo-it runs the app's suite too, with the provider condition" \
  '( for f in "$BS" "$GR" "$BVS" "$SG" "$RF" "$GOV"; do has "$f" "$OWN" || exit 1; done )'
check "the same five say what happens with no provider or a suite that cannot run: code-level only, and the app's suite NOT TESTED" \
  '( for f in "$BS" "$GR" "$BVS" "$SG" "$GOV"; do has "$f" "$NOPROV. $SKIP" || exit 1; done )'
check "the blueprint, README.md, the governance rows, DEVOPS-GUIDE.md and PENTEST-READINESS.md name both suites and the provider condition" \
  'has "$BP" "With a live AI provider /nemo-it also runs the app'"'"'s guardrail suite (guardrails/tests/), in its own block; it never edits a generated test" && has "$BP" "| Its own suite, written each run, and the app'"'"'s guardrails/tests/, each in its own block; both need a live AI provider |" && has README.md "and with a live AI provider \`/nemo-it\` runs them too, in their own block of the attestation" && has "$GOV" "/fix-it runs it when it verifies a fix, and /nemo-it runs it too when it has a live AI provider, in its own block of the attestation." && has "$GOV" "/nemo-it runs its own 60 or more cases and the app'"'"'s generated suite, each in its own block, when someone runs /nemo-it with a live AI provider" && has "$GOV" "With a live AI provider it runs /nemo-it'"'"'s own cases and the app'"'"'s suite, each in its own block |" && has docs/DEVOPS-GUIDE.md "\`/nemo-it\` (its own 60 or more cases and, in a separate block, the app'"'"'s generated \`guardrails/tests/\`; both need a live AI provider)" && has docs/PENTEST-READINESS.md "and runs the app'"'"'s generated suite in a separate block, when it is run with a live AI provider"'
# the old story, anywhere outside version history (a section under a version-history heading is dropped)
OLD='/nemo-it`? does not use (it|them)\b|it does not use the app.s guardrails/tests|not the app.s generated|no attestation is based on|and uses /nemo-it.s own cases|the attestation is based on those'
LIVE="$(for f in $FILES; do awk -v f="$f" '/^##+ /{h = ($0 ~ /^##+ (v[0-9]|.*(Version History|Changelog))/)} h {next} {print f ":" $0}' "$f"; done)"
check "no document still says /nemo-it does not use the app's suite, or that no attestation is based on it" \
  'M="$(printf "%s\n" "$LIVE" | { grep -iE -- "$OLD" || true; })"; [ -z "$M" ] || { printf "%s\n" "$M" | cut -c1-200 | sed "s/^/  old: /"; false; }'
check "what stays: the build runs no NeMo test, /fix-it still runs the suite, and step 0b keeps its two-model rule" \
  'has "$BS" "Checked by reading the files: AI09 runs no NeMo Guardrails test." && has .claude/commands/fix-it.md "pytest guardrails/tests/ -v" && has "$NM" "The overall AI-safety result is the worse of the two blocks." && has "$NM" "Code-level results are never a PASS: the behavioral tests did not run."'

# 6. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the Markdown files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  check "(control) passes on an untouched copy" \
    'd="$TMPD/c"; mkdir -p "$d" && tar -cf - $FILES | tar -xf - -C "$d" && bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with the app-suite step removed, and with its pytest line removed" \
    'opp "$NM" "s/^\*\*7b[.] Run the app.s own generated.*?(?=^\*\*8[.] Compile)//ms" && opp "$NM" "s/^\[ [^\n]*python -m pytest guardrails\/tests\/[^\n]*\n//m"'
  check "(control) fails with the two blocks merged into one count" \
    'opp "$NM" "s/The two are never merged: each has its own block, its own per-category results and its own counts/The two are merged into one block with one count per category/" && opp "$NM" "s/the counts of the two suites are never added together/the counts of the two suites are added together/" && opp "$AT" "s/The two are never merged, and no count here is added to a count above[.]/Its counts are added to the counts above./"'
  check "(control) fails with \"cannot run\" recorded as PASS, and as FAIL" \
    'opp "$NM" "s/\*\*A suite that could not run is NOT TESTED with the reason, never a PASS and never a FAIL[.]\*\*/**A suite that could not run is recorded as PASS.**/" && opp "$NM" "s/\*\*A suite that could not run is NOT TESTED with the reason, never a PASS and never a FAIL[.]\*\*/**A suite that could not run is recorded as FAIL.**/" && opp "$NM" "s/an \`error\` \(the file could not be loaded, a module is missing, a fixture broke\) is NOT TESTED/an \`error\` (the file could not be loaded, a module is missing, a fixture broke) is a FAIL/" && opp "$AT" "s/Not a pass, and not a fail \|/Counted as a pass |/"'
  check "(control) fails with the app's suite run with no provider, and on a live system" \
    'opp "$NM" "s/  2[.] step 0 chose behavioral tests: the AI provider is configured and reachable[^\n]*\n//" && opp "$NM" "s/\[ \"\\\$PASSIVE_ONLY\" = \"false\" \] && PYTHONDONTWRITEBYTECODE=1/PYTHONDONTWRITEBYTECODE=1/" && opp "$NM" "s/it is not run and its block is NOT TESTED with that reason -- never a PASS\*\*/it still runs**/"'
  check "(control) fails when /nemo-it edits a failing generated test, installs the missing package, or leaves a test out" \
    'opp "$NM" "s/\*\*Report only[.]\*\* Never edit, fix, skip, rename or delete a generated test/**Report only.** A generated test that fails for its own fault may be fixed and rerun; never delete a generated test/" && opp "$NM" "s/(\*\*Report only[.]\*\*)/When nemoguardrails is missing, run pip install nemoguardrails first. \$1/" && opp "$NM" "s/The suite is not rerun with tests left out[.]/A test that is plainly wrong is left out with --deselect and the suite is rerun./"'
  check "(control) fails with the overall result taken from the better block, and with a NOT TESTED block counted as a pass" \
    'opp "$NM" "s/is the worst of all the blocks: the primary/is the best of all the blocks: the primary/" && opp "$NM" "s/A block that is NOT TESTED never counts as a pass/A block that is NOT TESTED counts as a pass/" && opp "$AT" "s/the worst of all the blocks: \/nemo-it.s own cases/the better of the blocks: \/nemo-it\x27s own cases/"'
  check "(control) fails with the old \"does not use it\" sentence back in one compliance document (the governance doc, then PENTEST-READINESS.md, then a file nobody listed)" \
    'opp "$GOV" "s/\/nemo-it runs it too: with a live AI provider it runs the app.s suite and its own 60 or more cases, and the attestation shows each in its own block[.]/\/nemo-it does not use it: with a live AI provider it writes and runs its own 60 or more cases, and the attestation is based on those./" && opp docs/PENTEST-READINESS.md "s/, and runs the app.s generated suite in a separate block, when it is run/ (not the app\x27s generated suite) when it is run/" && opp CLAUDE.md "s/\z/\n\/nemo-it does not use them.\n/"'
  check "(control) fails with the result read from the command instead of the runner's file, and with the template's block or status word gone" \
    'opp "$NM" "s/What ran is read from the test runner.s own result file, never from the command having been issued/What ran is taken from the command having been issued/" && opp "$AT" "s/^### 1[.]7 The app.s generated guardrail suite[^\n]*\n//m" && opp "$AT" "s/^\| NOT TESTED [^\n]*\n//m"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
