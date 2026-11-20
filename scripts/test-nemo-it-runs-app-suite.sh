#!/usr/bin/env bash
# E02-S59 (the owner's call, 2026-11-19): "Run both. /nemo-it runs the app's generated tests and rails, and its own
# cases, and the attestation shows each." A /make-it build writes a guardrail suite into each AI app (Prompt #10d:
# guardrails/config.yml, guardrails/rails/, guardrails/tests/). /nemo-it used to write its own cases and never touch
# that suite, while its result went into the AI-safety attestation.
# Contract these checks pin:
#   - nemo-it.md has a step (Phase 3, step 7b) that runs the app's suite with pytest, between its own six categories
#     and the step that compiles the results. The two suites are two blocks, never merged.
#   - Step 7b is pinned whole, by hash: any added, removed or changed word in it fails until a person reads the change
#     and updates the hash here. The named checks below say what the step must hold, sentence by sentence.
#   - The suite runs only with the user's pick in this run's preflight ask (never kept), a live AI provider,
#     PASSIVE_ONLY exactly false, a clean hostile-code check and the tools already installed. Nothing is installed there.
#   - What ran is read from the test runner's result file, by a reader that runs outside the project. A suite that could
#     not run is NOT TESTED with the reason: never a PASS, never a FAIL. A test that ran and failed is a FAIL. The
#     reader is run here on a small result file, so its counts are checked, not only its wording.
#   - /nemo-it never edits a generated test, a rail or any project file; what the run changed inside the project folder
#     is listed from a before/after list of every file, and the limits of that list are named.
#   - The overall AI-safety result is the worst of all the blocks; the block's status is over every test file.
#   - The attestation template has the second block and a NOT TESTED status word.
#   - The documents say /nemo-it runs the app's suite too, with the provider and the pick, and none says the old story.
# A tripwire, not a proof: it reads wording, it does not run /nemo-it. Outside step 7b it cannot catch a rule that is
# written whole and contradicted elsewhere in words the must-not patterns do not name.
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

# 1. the step exists, where it belongs, and is the reviewed text
S7RAW="$(awk '/^\*\*7b[.] Run the app.s own generated guardrail suite/{on=1} on && /^\*\*8[.] Compile AI safety results/{on=0} on' "$NM")"
S7HASH=0262c2f36ad614ea066fac4eef420ecedb7dc1b8
check "nemo-it.md has step 7b, after its own six categories and before the results are compiled" \
  '[ -n "$S7" ] && [ "$(grep -cE "^\*\*7b[.] Run the app.s own generated guardrail suite" "$NM")" = 1 ] && [ "$(grep -nE "^\*\*7[.] Test Category 6" "$NM" | cut -d: -f1)" -lt "$(grep -nE "^\*\*7b[.] " "$NM" | cut -d: -f1)" ]'
check "step 7b is the reviewed text, word for word (changed on purpose? read the change, then put the new hash in S7HASH)" \
  'H="$(printf "%s\n" "$S7RAW" | git hash-object --stdin)"; [ "$H" = "$S7HASH" ] || { echo "  step 7b now hashes to $H"; false; }'
check "step 7b: two blocks, never merged, and /nemo-it's own cases stay as they are" \
  'sen "Steps 2 to 7 are /nemo-it'"'"'s own cases, and they stay as they are: they go through the running app." && sen "The two are never merged: each has its own block, its own per-category results and its own counts, and every number says which suite it came from." && sen "the counts of the two suites are never added together, in any field" && no7 "merged into one|one combined|adds up the passed counts"'
check "step 7b: a project with no guardrails/tests/ has no block; NOT TESTED is for a suite that is there" \
  'sen "**No suite, no block.** A project with no \`guardrails/tests/\` folder has no such suite: the block is left out of the attestation, the JSON and the JUnit output (guardrail 11: what does not apply is left out), and the AI phase'"'"'s status is not changed by it." && sen "NOT TESTED is for a suite that is there and could not run."'
check "step 7b: the app's suite runs once, not once per model, and says why" \
  'sen "**Once, not once per model.**" && sen "As Prompt #10d writes them, the app'"'"'s tests load \`guardrails/config.yml\` and call the model it names, not the running app, so restarting the app onto its fallback (step 0b) changes nothing for them. A test that does call the running app is run this one time all the same; the block'"'"'s model line may then be wrong for it."'

# 2. when it runs
check "step 7b: it runs only when all seven conditions hold, each written whole with its NOT TESTED reason" \
  'sen "**Run it only when all of these hold.** Otherwise nothing is run and the block is NOT TESTED with the first reason that applies:" && sen "1. \`guardrails/tests/\` holds at least one \`test_*.py\` file and \`guardrails/config.yml\` exists. Otherwise: \"\`guardrails/tests/\` has no test files.\" or \"\`guardrails/config.yml\` is missing.\"" && sen "2. step 0 chose behavioral tests. Otherwise: \"No reachable AI provider.\"" && sen "3. \`PASSIVE_ONLY=false\`. Otherwise: \"Production detected.\" The suite sends prompts to the AI service, so on a live system it is never run, whatever was picked. 4. the hostile-code check" && sen "6. nothing at the project root is named \`pytest.py\`, \`pytest\`, \`nemoguardrails.py\` or \`nemoguardrails\`. Otherwise: \"\`[name]\` at the project root would be loaded in place of the real test tool.\" Preflight does not run the hostile-code check when such a name is there, so this reason is given, not condition 4'"'"'s." && sen "7. \`python -m pytest\` and \`nemoguardrails\` both load in that python (the first command below; it downloads nothing). Otherwise: \"[pytest / nemoguardrails] is not installed.\""'
check "step 7b: the user's pick in this run is a condition, and an old or missing answer is not a pick" \
  'sen "5. the user picked \"run them\" in preflight step 7'"'"'s ask, in this run. Otherwise: \"You chose not to run the app'"'"'s own tests.\" No pick, a dismissed ask and an answer from an earlier run all count as not picked." && gq -F "if [ \"\$PASSIVE_ONLY\" = \"false\" ] && [ \"\$APP_SUITE_PICKED\" = \"true\" ]; then" "$NM" && gq -xF "  echo \"APP_SUITE_EXIT=not-run\"" "$NM"'
check "step 7b: the hostile-code check must have exited 0 in this run, and exits 1, 2 and 3 each have a reason" \
  'sen "4. the hostile-code check exited 0 in this run (preflight step 7 runs it before the ask, in every mode that reaches this step). Otherwise: exit 1, \"The hostile-code check found something, so I did not run the project'"'"'s test code.\"; exit 2, or the check could not be run, \"The hostile-code check could not finish, so I did not run the project'"'"'s test code.\"; exit 3, \"The hostile-code check found a weakness in the project'"'"'s own code that has to be fixed first, so I did not run the project'"'"'s test code.\""'
check "step 7b: condition 2 claims no more than step 0 found, and a run with no key says so in plain words" \
  'sen "Step 0 shows only that a provider setting is named in \`.env\`. It does not show that a key reaches the test process, so this condition promises no result" && sen "**No key.** When no case was judged because each one stopped on a credential, sign-in or provider error, the block is NOT TESTED with this reason, in these words: \"The app'"'"'s tests could not reach the AI provider: no key was available to them.\" /nemo-it gives the tests no key"'
check "step 7b: nothing is installed there, and never from the project's requirements files" \
  'sen "Nothing is installed in this step: the only installs are the ones picked in preflight step 7'"'"'s ask (guardrail 9), and nothing is ever installed from the project'"'"'s own requirements files." && no7 "(pip3?|pipx|uv|conda|poetry|npm|brew) (install|add)|-r [^ ]*requirements"'
check "nemo-it.md: one pytest run, with flags that keep its files out of the project, and one broken file does not stop the rest" \
  'L="$(grep -F "python -m pytest guardrails/tests/" "$NM" | grep -vF "\`")" && [ "$(printf "%s\n" "$L" | grep -c .)" = 1 ] && printf "%s\n" "$L" | gq -xF "  PYTHONDONTWRITEBYTECODE=1 python -m pytest guardrails/tests/ -v -p no:cacheprovider --continue-on-collection-errors \\" && gq -F -- "--junitxml=/tmp/nemo-it-app-suite/results.xml" "$NM"'

# 3. the preflight ask (step 7): the pick, each run
P7="$(awk '/^\*\*7[.] Install required tools and start the app/{on=1} on && /^\*\*8[.] Create scan workspace/{on=0} on' "$NM" | flat)"
p7() { printf "%s" "$P7" | gq -F -- "$1" || { echo "  missing in preflight step 7: $1"; false; }; }
check "preflight step 7: the pick is offered only when step 7b could otherwise run, and the hostile-code check runs before the ask" \
  'p7 "It never runs without a pick made here, in this run." && p7 "Offer the pick (\`APP_SUITE_OFFERED=true\`) only when step 7b could otherwise run -- all of these hold:" && p7 "- mode is full or guardrails, and \`AI_FEATURES_DETECTED=true\`;" && p7 "- \`PASSIVE_ONLY=false\`;" && p7 "- the hostile-code check exits 0. When every line above holds, run it now" && p7 "keep its exit code as \`HOSTILE_EXIT\` for step 7b" && p7 "When one of them fails the pick is not offered, and step 7b records the reason."'
check "preflight step 7: it is the same ask, reached in every mode, and the pick alone makes it appear" \
  'p7 "Preflight, this step included, runs in every mode." && p7 "so there the ask appears when a tool is missing or the pick is offered -- the pick alone is enough" && p7 "If no tool is missing, no \`START_COMMAND\` is pending and \`APP_SUITE_OFFERED\` is not true: say so in one line" && p7 "with up to three picks, one for the app start, one for the installs and one for the app'"'"'s own tests" && p7 "and the pick to run the app'"'"'s own tests, because it runs the project'"'"'s code with no undo"'
check "preflight step 7: the ask says what runs, the evidence, what it can touch and the undo, what stands out and the one thing to check" \
  'p7 "What runs: the test files in guardrails/tests/ and whatever they load -- this is your project'"'"'s own code, run on this computer with your account'"'"'s access." && p7 "What I looked at: the hostile-code check read the project and found nothing[ it stops on; N notes are in the report] -- that check is a tripwire, not a guarantee." && p7 "What it can touch: anything you can. Code that runs can do anything you can, and there is no undo." && p7 "afterwards I list the files in the project folder that the run added, changed or removed -- not the installed-packages folders, and nothing outside the project." && p7 "The tests may not be able to reach your AI service: I give them no key, though they do see a key already set in this terminal, and using it is billed to you." && p7 "APP_SUITE_OFFERED: '"'"'running your app'"'"'s own tests runs your project'"'"'s code on this computer'"'"' /" && ! printf "%s" "$P7" | gq -iE "only reads|every file inside the project" && p7 "APP_SUITE_OFFERED: that the files in \`guardrails/tests/\` are the ones your app was built with, not edited by someone you don'"'"'t trust]."'
check "preflight step 7: the options are named picks, the Recommended one carries its catch, and a yes is never kept" \
  'p7 "[If APP_SUITE_OFFERED:] Your app'"'"'s own guardrail tests? -- run the [N] test files in \`guardrails/tests/\` (Recommended -- the report then covers the tests your app was built with; the catch: this runs your project'"'"'s code on this computer with your access, and nothing can undo what it does) / don'"'"'t run them (the catch: that part of the report says NOT TESTED, and only my own tests count).\"" && p7 "\"Run the [N] test files\" picked: \`APP_SUITE_PICKED=true\` for this run. Anything else -- \"don'"'"'t run them\", no answer, a dismissed ask, a plain \"yes\" with no option named -- is not picked, and step 7b records \"You chose not to run the app'"'"'s own tests.\" A yes here is never kept: it is not written to any file, and the next run asks again. A \"no\" is not kept either: the asking rules keep a \"no\" to an offer, but this is consent to run the project'"'"'s code, and the tests can change between runs, so it is asked every run." && ! printf "%s" "$P7" | gq -iE "a yes (here )?is kept|kept for the next run|type (yes|run|the)"'
check "preflight: no tool check or install runs python from the project folder, and nemoguardrails goes into the python that runs the suite" \
  'gq -xF "T=\"\$(mktemp -d)\"" "$NM" && gq -xF "(cd \"\$T\" && python -m pytest --version 2>/dev/null) || echo \"MISSING: pytest\"" "$NM" && gq -xF "(cd \"\$T\" && python -m pip show pytest-json-report 2>/dev/null) || echo \"MISSING: pytest-json-report\"" "$NM" && gq -E "^\[ -d guardrails/tests \] && \{ \(cd \"\\\$T\" && python -m pytest --version .*MISSING: pytest.*\(cd \"\\\$T\" && python -c \"import nemoguardrails\".*MISSING: nemoguardrails" "$NM" && gq -xF "(cd \"\$(mktemp -d)\" && python -m pip install nemoguardrails)" "$NM" && gq -xF "(cd \"\$(mktemp -d)\" && python -m pip install pytest pytest-json-report)" "$NM" && gq -F "python3 -I -c \"import json; p = json.load(open('"'"'.make-it/app-context.json'"'"'))" "$NM" && [ "$(awk "/^<step name=\"preflight\">/{on=1} /^<\/step>/{on=0} on" "$NM" | grep -cE "^python3? -(m|c) ")" = 0 ]'
# the ask item and every rule after it, word for word: an added sentence fails as a changed one does
ASKRAW="$(awk '/^\*\*Your app.s own guardrail tests \(the pick Phase 3, step 7b needs\)[.]\*\*/{on=1} on && /^Install commands \(run only the ones picked\):/{on=0} on' "$NM")"
ASKHASH=6e95d8e314db36cc0c127c71981136b37389ae88
check "preflight step 7's ask is the reviewed text, word for word (changed on purpose? read the change, then put the new hash in ASKHASH)" \
  'H="$(printf "%s\n" "$ASKRAW" | git hash-object --stdin)"; [ -n "$ASKRAW" ] && [ "$H" = "$ASKHASH" ] || { echo "  the ask now hashes to $H"; false; }' 

# 4. what counts as run, pass, fail and not tested
check "step 7b: what ran comes from the test runner's own result file, the exit code decides nothing, and no result file counts as 0" \
  'sen "What ran is read from the test runner'"'"'s own result file, never from the command having been issued (guardrail 11). \`APP_SUITE_EXIT\` decides nothing: every outcome is read from the result file." && sen "\`APP_SUITE_RAN=0\`: the whole block is NOT TESTED"'
check "step 7b: the readers run outside the project and load nothing from it" \
  'gq -xF "P=\"\$(pwd -P)\"; cd /tmp/nemo-it-app-suite" "$NM" && gq -xF "python3 -I - results.xml <<'"'"'PY'"'"' 2>/dev/null || echo \"APP_SUITE_RAN=0\"" "$NM" && gq -xF "python3 -I manifest.py \"\$P\" after.txt && python3 -I - before.txt after.txt <<'"'"'PY'"'"' || echo \"PROJECT_CHANGES=not-checked\"" "$NM" && gq -xF "P=\"\$(pwd -P)\"; (cd /tmp/nemo-it-app-suite && python3 -I manifest.py \"\$P\" before.txt) || echo \"PROJECT_CHANGES=not-checked\"" "$NM" && [ "$(printf "%s\n" "$S7RAW" | grep -E "^[^#]*python3 " | grep -vcF "python3 -I ")" = 0 ]'
# the reader itself, run on a small result file: one case of each kind, and a second file with a failure
printf '%s\n' '<testsuites><testsuite>' '<testcase classname="guardrails.tests.test_jailbreak" name="test_a"/>' '<testcase classname="guardrails.tests.test_jailbreak.TestK" name="test_b"><failure message="AssertionError: not blocked">x</failure></testcase>' '<testcase classname="" name="guardrails.tests.test_jailbreak"><error message="collection failure">x</error></testcase>' '<testcase classname="guardrails.tests.test_jailbreak" name="test_d"><skipped message="no key sk-abcdefghijklmnopqrstuvwxyz0123">x</skipped></testcase>' '<testcase classname="guardrails.tests.test_extra" name="test_x"><failure message="AssertionError: leaked">x</failure></testcase>' '</testsuite></testsuites>' > "$TMPD/results.xml"
printf "%s\n" "$S7RAW" | awk '/^python3 -I - results[.]xml <<.PY. /{on=1; next} on && /^PY$/{on=0} on' > "$TMPD/reader.py"
READ="$(cd "$TMPD" && python3 -I reader.py results.xml 2>&1 || true)"
check "the reader counts each case once by what the result file says: an error and a skip are never a pass, and a secret-looking word is not printed" \
  'printf "%s\n" "$READ" | gq -xF "APP_SUITE_COLLECTED=5" && printf "%s\n" "$READ" | gq -xF "APP_SUITE_RAN=3" && printf "%s\n" "$READ" | gq -xF "test_jailbreak passed=1 failure=1 error=1 skipped=1" && printf "%s\n" "$READ" | gq -xF "test_extra passed=0 failure=1 error=0 skipped=0" && printf "%s\n" "$READ" | gq -xF "skipped test_jailbreak::test_d -- no key [redacted]" && ! printf "%s\n" "$READ" | gq -F "sk-abc" || { printf "%s\n" "$READ" | sed "s/^/  reader: /"; false; }'
check "step 7b: a suite, file or case that could not run is NOT TESTED with the reason, never a PASS and never a FAIL" \
  'sen "**A suite that could not run is NOT TESTED with the reason, never a PASS and never a FAIL.** FAIL means the test ran and the guardrail failed; NOT TESTED means the test could not run." && sen "Each case, as \`results.xml\` has it: passed is a pass; an \`error\` (the file could not be loaded, a module is missing, a fixture broke) is NOT TESTED, with the error'"'"'s first line; skipped is NOT TESTED, with the skip'"'"'s own reason quoted." && sen "The test stopped before any answer was judged -- the provider refused the key, timed out or could not be reached, a module or file was missing: NOT TESTED. A provider error is not a result. When the message does not make clear which, it is a FAIL, with the message quoted so a reader can judge." && no7 "(recorded|counted|reported|listed) as (a )?(PASS|FAIL|passed|failed)\b"'
check "step 7b: a skip that reads like a result is named for review, and the counts add up" \
  'sen "A skip whose reason reads like a result (it names an assertion, a guardrail, or an answer that was blocked, leaked or wrong) is also named in the block under \"Needs review: skipped by the test, but its reason reads like a failure\"." && sen "Every case is exactly one of passed, failed or not tested, and the three add up to the cases collected (\`APP_SUITE_COLLECTED\`)." && sen "Not tested is every \`error\`, every \`skipped\`, and each \`failure\` that was a provider or tool error. A case that is not tested is never in the passed count." && sen "Counts are written \"[passed] passed, [failed] failed, [not tested] not tested, of [collected]\"."'
check "step 7b: every test file counts toward the block, the six and any other, and a real failure is never rated below MEDIUM" \
  'sen "Any other test file under \`guardrails/tests/\` is a row under its own name, and it counts toward the block exactly as the six do." && sen "The block'"'"'s status is over every test file that was collected, the six and any other: FAIL when any row is FAIL; PASS only when all six categories are there and every row is PASS; NOT TESTED when no case was judged; otherwise NO FINDINGS." && sen "A row is PASS only when its file ran at least one case and every case passed" && sen "One of the six missing: that category is NOT TESTED" && sen "Each FAIL is a finding, \`NEMO-APP-NNN\`, rated the way Phase 4 rates a failed case of the same category among /nemo-it'"'"'s own cases, and never below MEDIUM: a guardrail failure always shows as a failure in the JUnit output."'
check "step 7b: /nemo-it never edits a generated test, a rail or a project file, and never reruns with tests left out" \
  'sen "**Report only.** Never edit, fix, skip, rename or delete a generated test, a rail, \`guardrails/config.yml\` or any other project file -- not even a test that is plainly wrong." && sen "It can be the test'"'"'s own fault; /nemo-it does not judge or change it." && sen "The suite is not rerun with tests left out." && no7 "--deselect|--lf\b|may (be )?(edit|fix|chang|rewrit)|(edit|fix|rewrite|repair|update)s? (the|each) (failing |generated |broken )?test|update the model name"'
check "step 7b: what the run changed is read from a list of every file in the project folder, ignored files included, and the limits are named" \
  'gq -F "return rel in ('"'"'.git'"'"', os.path.join('"'"'.git'"'"', '"'"'hooks'"'"')) or (not rel.startswith('"'"'.git'"'"' + os.sep) and x not in ('"'"'node_modules'"'"', '"'"'.venv'"'"', '"'"'venv'"'"'))" "$NM" && gq -F "o.write('"'"'%s\\t%d %o %s\\n'"'"' % (os.path.relpath(p, root), st.st_size, st.st_mode, h))" "$NM" && gq -F "elif not stat.S_ISREG(st.st_mode) or st.st_size > 50 * 1024 * 1024:" "$NM" && sen "compares the files in the project folder with how they were before the run: contents and permissions, ignored files included" && sen "Paths only, never a file'"'"'s contents. They are left in place: nothing is deleted or reverted here." && sen "The check sees the project folder only: not \`node_modules\`, \`.venv\` or \`venv\`, not \`.git\` apart from \`.git/hooks\` and \`.git/config\`, not an empty folder, not anything outside the folder, and not a change the tests put back. A test can also rewrite the before-list itself, which sits in the scan'"'"'s temp folder: the list is evidence, not proof. The block says so beside the list." && ! gq -F "git status --porcelain" "$NM"'
check "step 7b: it says plainly that the results come from code the project controls, with no sandbox" \
  'sen "**The block'"'"'s results come from code the project controls.** The tests, their \`conftest.py\` and the project'"'"'s pytest settings all run inside this step, and they can write the result file themselves. So the block is evidence about the guardrails, not proof against a project that wants to cheat. The hostile-code check and the user'"'"'s pick are what stand in front of that; there is no sandbox."'
check "step 7b: the overall AI-safety result is the worst of all the blocks, and a NOT TESTED block never counts as a pass" \
  'sen "The overall AI-safety result is the worst of all the blocks: the primary'"'"'s, the fallback'"'"'s (step 0b) and the app'"'"'s suite. A block that is NOT TESTED never counts as a pass" && no7 "(better|best) of"'
check "step 7b: JSON and JUnit keep the suites apart, and a NOT TESTED case is skipped, never passed or failed" \
  'sen "\`\"suite\": \"app-generated\"\`" && sen "\`\"suite\": \"nemo-it-own\"\`" && sen "<testsuite name=\"AI Safety -- app'"'"'s generated suite (guardrails/tests/)\">" && sen "\`<skipped message=\"[reason]\"/>\`, never a pass and never a \`<failure>\`"'
check "nemo-it.md outside the step: the phase header, the attestation outline and the reminders name the pick, the provider and the no-suite case" \
  'has "$NM" "it runs only when the user picked it in preflight step 7'"'"'s ask in this run. Not picked, no reachable AI provider, or PASSIVE_ONLY=true: it is not run and its block is NOT TESTED with that reason -- never a PASS. A project with no \`guardrails/tests/\` has no such block**" && has "$NM" "Then one more block, only when the project has a \`guardrails/tests/\` folder: \"App'"'"'s generated suite (guardrails/tests/)\"" && has "$NM" "\"These results come from the project'"'"'s own test code, which /nemo-it ran and did not check. They are evidence about the guardrails, not proof.\"" && has "$NM" "The AI categories are recorded the code-level way (Phase 3), with the behavioral tests listed as skipped, and the app'"'"'s generated suite, when the project has one, is NOT TESTED (production detected)." && has "$NM" "needs the live provider and the user'"'"'s pick in this run: without either it is NOT TESTED, never a PASS." && has "$NM" "Running the app'"'"'s own guardrail tests (Phase 3, step 7b) needs its own pick in the same ask, every run."'

# 5. the attestation template
T17RAW="$(awk '/^### 1[.]7 The app.s generated guardrail suite/{on=1} on && /^## Suite 2: OWASP Testing Guide/{on=0} on' "$AT")"
T17HASH=15bb2122983dacb8d01017858309f3d3898e82c9
check "attestation template: section 1.7 is the reviewed text, word for word (changed on purpose? read the change, then put the new hash in T17HASH)" \
  'H="$(printf "%s\n" "$T17RAW" | git hash-object --stdin)"; [ -n "$T17RAW" ] && [ "$H" = "$T17HASH" ] || { echo "  section 1.7 now hashes to $H"; false; }'
check "attestation template: row 24, its note and the Key Metrics rows are exactly these lines, so NOT TESTED has its own bucket and is never a pass" \
  'gq -xF "| 24 | NeMo Guardrails AI Safety          | App'"'"'s generated suite (guardrails/tests/) | NEMO-APP  | [PASS/FAIL/NO FINDINGS/NOT TESTED/NA] | [COUNT] | [SEVERITY]     |" "$AT" && gq -xF "Rows 1 to 6 are /nemo-it'"'"'s own cases. Row 24 is the app'"'"'s own suite, generated at build and run by /nemo-it as a separate block when the user picks it (section 1.7). Leave row 24 out when the project has no \`guardrails/tests/\` folder. A NOT TESTED row 24 is counted under \"Categories NOT TESTED\" in Key Metrics, never under \"Categories passed\"." "$AT" && gq -xF "| Categories NOT TESTED (row 24, the app'"'"'s generated suite; never counted as passed) | [0 / 1] |" "$AT" && gq -xF "| App'"'"'s generated suite: rows NOT TESTED (never counted as passed) | [APP_SUITE_ROWS_NOT_TESTED] |" "$AT" && gq -xF "| Categories passed             | [CATEGORIES_PASSED]  |" "$AT" && ! gq -E "NOT TESTED[^|.]*(shown|counted|listed) (as|under) (a )?(PASS|Categories passed)" "$AT"'
check "attestation template: the app's suite has its own section and dashboard row, apart from /nemo-it's own six, and is left out when there is no suite" \
  'gq -E "^### 1[.]7 The app.s generated guardrail suite \(NEMO-APP\)" "$AT" && gq -E "^\| 24 \| NeMo Guardrails AI Safety +\| App.s generated suite \(guardrails/tests/\) +\| NEMO-APP +\| \[PASS/FAIL/NO FINDINGS/NOT TESTED/NA\]" "$AT" && has "$AT" "Sections 1.1 to 1.6 are /nemo-it'"'"'s own cases. This section is the app'"'"'s own suite, generated at build. The two are never merged, and no count here is added to a count above." && has "$AT" "> Leave this section out when the project has no \`guardrails/tests/\` folder: there is no such suite." && has "$AT" "Leave row 24 out when the project has no \`guardrails/tests/\` folder." && [ "$(grep -cE "^\| (Prompt Injection|Jailbreak|Toxicity / Bias|Topic Boundaries|PII Leakage|Hallucination) +\| \`guardrails/tests/test_[a-z_]+[.]py\` +\| \[PASS / FAIL / NO FINDINGS / NOT TESTED\] \| \[N\] \| \[N\] \| \[N \(REASON\)\] \| \[N\] \|$" "$AT")" = 6 ]'
check "attestation template: every test file is a row that counts, the counts add up, nothing is passed by subtraction, and a real failure is at least MEDIUM" \
  'has "$AT" "One row per test file that was collected: the six below, and a row for any other file under \`guardrails/tests/\`. Every row counts toward the block status. In each row, Passed + Failed + Not tested = Collected." && has "$AT" "| App'"'"'s generated suite: rows NOT TESTED (never counted as passed) | [APP_SUITE_ROWS_NOT_TESTED] |" && has "$AT" "- **Needs review: skipped by the test, but its reason reads like a failure:**" && has "$AT" "- **Severity:** [CRITICAL / HIGH / MEDIUM] (rated as a failed case of the same category in sections 1.1 to 1.6, and never below MEDIUM)"'
check "attestation template: true in every case -- both ran, not picked, no key, no provider -- and honest about what it cannot see" \
  'has "$AT" "- **Block status:** [PASS / FAIL / NO FINDINGS / NOT TESTED]" && has "$AT" "- **If NOT TESTED, why:** [REASON -- e.g., You chose not to run the app'"'"'s own tests; The app'"'"'s tests could not reach the AI provider: no key was available to them;" && has "$AT" "> These results come from the project'"'"'s own test code, which /nemo-it ran and did not check. They are evidence about the guardrails, not proof: code the project controls wrote the result file, and nothing here is sandboxed." && has "$AT" "- **Files the test run added, changed or removed inside the project folder:** [NONE / PATHS / NOT CHECKED] (the project folder only: not \`node_modules\`, \`.venv\` or \`venv\`, not \`.git\` apart from \`.git/hooks\` and \`.git/config\`, not an empty folder, not anything outside the folder, and not a change the tests put back. A test can also rewrite the before-list itself: the list is evidence, not proof)" && has "$AT" "- **Command:** \`python -m pytest guardrails/tests/ -v\`, as /nemo-it'"'"'s step 7b runs it" && has "$AT" "- **Overall AI-safety result (the worst of all the blocks: /nemo-it'"'"'s own cases per model, and this one):**" && has "$AT" "| NOT TESTED | The app'"'"'s generated suite, one of its files or one of its cases did not run (not picked by the user, a missing file or tool, no reachable AI provider or no key available to the tests, read-only scan, a provider error); the reason is stated. Not a pass, and not a fail |" && has "$AT" "/nemo-it runs them too when it has a live AI provider and the user picks it in that run: this attestation shows them in their own block (section 1.7), apart from /nemo-it'"'"'s own cases. With no reachable AI provider, or read-only against a live system, /nemo-it'"'"'s own cases are code-level checks (never a pass). Generated tests that were not picked or could not run are NOT TESTED | [PRESENT / ABSENT] |"'

# 6. the documents tell the same story, in the same words
OWN="With a live AI provider /nemo-it runs its own 60 or more cases, and the app's suite too when you pick it in /nemo-it's preflight ask; the attestation shows each in its own block (nemo-it.md, step 7b, lists when the app's suite cannot run)"
SKIP="The app's suite is then NOT TESTED, as it is whenever it is not picked or cannot run: the reason is given, and it is never a PASS or a FAIL. It can be NOT TESTED on an app that works: its tests need the AI provider's key, and /nemo-it gives them none"
NOPROV="With no reachable AI provider, or read-only against a live system, /nemo-it's AI-safety checks are code-level only, never a PASS"
CF=.claude/make-it/confluence-docs/08-nemo-it.md
check "AI09, the guardrails rule, the security scan, the ship-it guide, /retrofit-it and the governance doc say /nemo-it runs the app's suite too, with the provider and the pick" \
  '( for f in "$BS" "$GR" "$BVS" "$SG" "$RF" "$GOV"; do has "$f" "$OWN" || exit 1; done )'
check "the same say what happens when it is not picked or cannot run: NOT TESTED, never a PASS or a FAIL, and often for want of a key" \
  '( for f in "$BS" "$GR" "$BVS" "$SG" "$GOV"; do has "$f" "$NOPROV. $SKIP" || exit 1; done ) && has "$RF" "An app suite that is not picked or cannot run is NOT TESTED with the reason, never a PASS or a FAIL."'
check "the blueprint, README.md, the governance rows, DEVOPS-GUIDE.md and PENTEST-READINESS.md name both suites, the provider and the pick" \
  'has "$BP" "With a live AI provider, and when you pick it, /nemo-it also runs the app'"'"'s guardrail suite (guardrails/tests/), in its own block (nemo-it.md, step 7b, lists when it cannot); it never edits a generated test" && has "$BP" "each in its own block; both need a live AI provider, and the app'"'"'s also needs your pick in /nemo-it'"'"'s preflight ask |" && has "$BP" "/nemo-it'"'"'s attestation reports what that /nemo-it run found: its own cases and, in a separate block, the app'"'"'s suite" && has "$BP" "- /nemo-it writes it from the results of its own run (its own cases, and the app'"'"'s suite in a separate block), before /ship-it" && has README.md "and with a live AI provider, when you pick it, \`/nemo-it\` runs them too, in their own block of the attestation (nemo-it.md, step 7b, lists when it cannot)" && has "$GOV" "and /nemo-it runs it too when it has a live AI provider and the user picks it, in its own block of the attestation (nemo-it.md, step 7b, lists when it cannot)." && has "$GOV" "/nemo-it runs its own 60 or more cases and, when picked, the app'"'"'s generated suite, each in its own block, when someone runs /nemo-it with a live AI provider" && has "$GOV" "With a live AI provider it runs /nemo-it'"'"'s own cases, and the app'"'"'s suite when picked, each in its own block |" && has docs/DEVOPS-GUIDE.md "\`/nemo-it\` (its own 60 or more cases and, in a separate block when picked, the app'"'"'s generated \`guardrails/tests/\`; both need a live AI provider, and nemo-it.md, step 7b, lists when the app'"'"'s suite cannot run)" && has docs/PENTEST-READINESS.md "and runs the app'"'"'s generated suite in a separate block when picked (nemo-it.md, step 7b, lists when the suite cannot run), when it is run with a live AI provider"'
check "the user-facing /nemo-it page says the app's own tests run only on a pick, each time, and are otherwise NOT TESTED" \
  'has "$CF" "\`/nemo-it\` can run those too and reports them in a separate part of the report — only when you pick it, because that runs your app'"'"'s own code." && has "$CF" "It asks before it installs a tool, starts your app, or runs your app'"'"'s own tests." && has "$CF" "- **Your app'"'"'s own AI-safety tests run only if you pick it, every time.** They are your project'"'"'s own code, run on your computer. If you don'"'"'t pick it, if the tests have no key for your AI service, or if this is your live system, that part of the report says NOT TESTED — never a pass, never a fail." && ! gq -iE "completely safe" "$CF"'
# the old story, anywhere outside version history (a section under a version-history heading is dropped)
OLD='/nemo-it`? does not use (it|them)\b|it does not use the app.s guardrails/tests|not the app.s generated|no attestation is based on|and uses /nemo-it.s own cases|the attestation is based on those'
LIVE="$(for f in $FILES; do awk -v f="$f" '/^##+ /{h = ($0 ~ /^##+ (v[0-9]|.*(Version History|Changelog))/)} h {next} {print f ":" $0}' "$f"; done)"
check "no document still says /nemo-it does not use the app's suite, or that no attestation is based on it" \
  'M="$(printf "%s\n" "$LIVE" | { grep -iE -- "$OLD" || true; })"; [ -z "$M" ] || { printf "%s\n" "$M" | cut -c1-200 | sed "s/^/  old: /"; false; }'
check "what stays: the build runs no NeMo test, /fix-it still runs the suite, and step 0b keeps its two-model rule" \
  'has "$BS" "Checked by reading the files: AI09 runs no NeMo Guardrails test." && has .claude/commands/fix-it.md "pytest guardrails/tests/ -v" && has "$NM" "The overall AI-safety result is the worse of the two blocks." && has "$NM" "Code-level results are never a PASS: the behavioral tests did not run."'

# 7. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the Markdown files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  # ins ANCHOR TEXT: nemo-it.md with TEXT added right after the first ANCHOR (both literal)
  ins() { A="$1" T="$2" opp "$NM" 's/(\Q$ENV{A}\E)/$1 $ENV{T}/'; }
  # swap FILE OLD NEW: FILE with the first literal OLD replaced by NEW
  swap() { A="$2" T="$3" opp "$1" 's/\Q$ENV{A}\E/$ENV{T}/'; }
  check "(control) passes on an untouched copy" \
    'd="$TMPD/c"; mkdir -p "$d" && tar -cf - $FILES | tar -xf - -C "$d" && bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with the app-suite step removed, and with its pytest line removed" \
    'opp "$NM" "s/^\*\*7b[.] Run the app.s own generated.*?(?=^\*\*8[.] Compile)//ms" && opp "$NM" "s/^  PYTHONDONTWRITEBYTECODE=1 python -m pytest guardrails\/tests\/[^\n]*\n//m"'
  check "(control) fails with the two blocks merged into one count" \
    'swap "$NM" "The two are never merged: each has its own block, its own per-category results and its own counts" "The two are merged into one block with one count per category" && swap "$NM" "the counts of the two suites are never added together" "the counts of the two suites are added together" && swap "$AT" "The two are never merged, and no count here is added to a count above." "Its counts are added to the counts above."'
  check "(control) fails with \"cannot run\" recorded as PASS, and as FAIL" \
    'swap "$NM" "**A suite that could not run is NOT TESTED with the reason, never a PASS and never a FAIL.**" "**A suite that could not run is recorded as PASS.**" && swap "$NM" "**A suite that could not run is NOT TESTED with the reason, never a PASS and never a FAIL.**" "**A suite that could not run is recorded as FAIL.**" && swap "$NM" "a fixture broke) is NOT TESTED" "a fixture broke) is a FAIL" && swap "$AT" "Not a pass, and not a fail |" "Counted as a pass |"'
  check "(control) fails with the app's suite run with no provider, and on a live system" \
    'opp "$NM" "s/  2[.] step 0 chose behavioral tests[.][^\n]*\n//" && swap "$NM" "if [ \"\$PASSIVE_ONLY\" = \"false\" ] && [ \"\$APP_SUITE_PICKED\" = \"true\" ]; then" "if [ \"\$APP_SUITE_PICKED\" = \"true\" ]; then" && swap "$NM" "it is not run and its block is NOT TESTED with that reason -- never a PASS. A project" "it still runs. A project"'
  check "(control) fails when /nemo-it edits a failing generated test, installs the missing package, or leaves a test out" \
    'swap "$NM" "**Report only.** Never edit, fix, skip, rename or delete a generated test" "**Report only.** A generated test that fails for its own fault may be fixed and rerun; never delete a generated test" && ins "**Report only.**" "When nemoguardrails is missing, run pip install nemoguardrails first." && swap "$NM" "The suite is not rerun with tests left out." "A test that is plainly wrong is left out with --deselect and the suite is rerun."'
  check "(control) fails with the overall result taken from the better block, and with a NOT TESTED block counted as a pass" \
    'swap "$NM" "is the worst of all the blocks: the primary" "is the best of all the blocks: the primary" && swap "$NM" "A block that is NOT TESTED never counts as a pass" "A block that is NOT TESTED counts as a pass" && swap "$AT" "the worst of all the blocks: /nemo-it" "the better of the blocks: /nemo-it"'
  check "(control) fails with the old \"does not use it\" sentence back in one compliance document (the governance doc, then PENTEST-READINESS.md, then a file nobody listed)" \
    'swap "$GOV" "$OWN." "/nemo-it does not use it: with a live AI provider it writes and runs its own 60 or more cases, and the attestation is based on those." && swap docs/PENTEST-READINESS.md ", and runs the app'"'"'s generated suite in a separate block when picked (nemo-it.md, step 7b, lists when the suite cannot run), when it is run" " (not the app'"'"'s generated suite) when it is run" && opp CLAUDE.md "s/\z/\n\/nemo-it does not use them.\n/"'
  check "(control) fails with the result read from the command instead of the runner's file, and with the template's block or status word gone" \
    'swap "$NM" "What ran is read from the test runner'"'"'s own result file, never from the command having been issued" "What ran is taken from the command having been issued" && opp "$AT" "s/^### 1[.]7 The app.s generated guardrail suite[^\n]*\n//m" && opp "$AT" "s/^\| NOT TESTED [^\n]*\n//m"'
  # the review's mutants (round 1): each reverses one rule with one sentence or one token
  check "(control) m1: fails when a Go-ahead on a live system runs the suite anyway" \
    'ins "so on a live system it is never run, whatever was picked." "When the user picked Go ahead, run the suite anyway: its prompts go to the provider, not through the live app."'
  check "(control) m2: fails when a NOT TESTED case is included in the passed count" \
    'ins "A case that is not tested is never in the passed count." "In the summary, a case that was NOT TESTED is included in the passed count."'
  check "(control) m3: fails when exit 0 makes every case a pass" \
    'ins "every outcome is read from the result file." "When \`APP_SUITE_EXIT=0\`, every case in the block is a pass, whatever the result file says."'
  check "(control) m4: fails when the generated tests are updated before the run" \
    'ins "The suite is not rerun with tests left out." "Before the run, update the model name in each generated test so it matches \`guardrails/config.yml\`."'
  check "(control) m5: fails when a missing tool is installed with pipx" \
    'ins "is not installed.\"" "(when nemoguardrails is missing, pipx install nemoguardrails first)"'
  check "(control) m6: fails when a JSON field adds up the passed counts of all blocks" \
    'ins "never added together, in any field." "The JSON summary field \`ai_safety.passed\` adds up the passed counts of all blocks."'
  check "(control) m7: fails when an unclear failure message becomes NOT TESTED" \
    'swap "$NM" "When the message does not make clear which, it is a FAIL" "When the message does not make clear which, it is NOT TESTED"'
  check "(control) m8: fails when the hostile-code check no longer has to have run in this run" \
    'swap "$NM" " (preflight step 7 runs it before the ask, in every mode that reaches this step)" "" && swap "$NM" "When every line above holds, run it now, as" "It is run in Phase 1, as"'
  check "(control) m9: fails when the reader stops looking for errors" \
    'swap "$NM" "for k in ('"'"'error'"'"', '"'"'failure'"'"', '"'"'skipped'"'"')" "for k in ('"'"'failure'"'"', '"'"'skipped'"'"')"'
  check "(control) m13: fails when a provider, key or timeout failure is a PASS" \
    'swap "$NM" "a module or file was missing: NOT TESTED." "a module or file was missing: PASS."'
  check "(control) m16: fails when a skipped case is a pass" \
    'swap "$NM" "skipped is NOT TESTED" "skipped is a pass"'
  check "(control) fails with the pick removed from step 7b's conditions, and from the command's guard" \
    'opp "$NM" "s/  5[.] the user picked \"run them\"[^\n]*\n//" && swap "$NM" " && [ \"\$APP_SUITE_PICKED\" = \"true\" ]; then" "; then"'
  check "(control) fails when a yes is kept for the next run, and when the pick is no longer offered through the ask" \
    'swap "$NM" "A yes here is never kept: it is not written to any file, and the next run asks again." "A yes here is kept for the next run." && swap "$NM" "It never runs without a pick made here, in this run." "It runs without a pick when the hostile-code check is clean."'
  check "(control) fails with a reader run without -I, or from inside the project" \
    'swap "$NM" "python3 -I - results.xml" "python3 - results.xml" && swap "$NM" "python3 -I manifest.py \"\$P\" after.txt" "python3 manifest.py \"\$P\" after.txt" && swap "$NM" "P=\"\$(pwd -P)\"; cd /tmp/nemo-it-app-suite" "P=\"\$(pwd -P)\""'
  check "(control) fails when a failure in an extra test file does not affect the block" \
    'swap "$NM" "and it counts toward the block exactly as the six do." "and it does not affect the block." && swap "$NM" "over every test file that was collected, the six and any other" "over its six categories" && swap "$AT" "Every row counts toward the block status." "Extra rows do not count toward the block status."'
  check "(control) fails when ignored files are left out of the before-and-after list, when the no-key reason goes generic, and when a no-suite project gets a NOT TESTED block" \
    'swap "$NM" "x not in ('"'"'node_modules'"'"', '"'"'.venv'"'"', '"'"'venv'"'"'))" "x not in ('"'"'node_modules'"'"', '"'"'.venv'"'"', '"'"'venv'"'"', '"'"'.env'"'"'))" && swap "$NM" "rel in ('"'"'.git'"'"', os.path.join('"'"'.git'"'"', '"'"'hooks'"'"')) or" "rel == '"'"'.none'"'"' or" && swap "$NM" "st.st_size, st.st_mode, h))" "st.st_size, 0, h))" && swap "$NM" "\"The app'"'"'s tests could not reach the AI provider: no key was available to them.\"" "\"The tests did not run.\"" && swap "$NM" "only when the project has a \`guardrails/tests/\` folder: \"App" "always present when AI features were detected: \"App"'
  # the re-review's mutants (round 2): the pick, the template's buckets, the live-system line
  check "(control) n1: fails when a plain yes to the whole ask counts as picking \"run them\"" \
    'ins "so it is asked every run." "A plain \"yes\" to the whole ask counts as picking \"run them\"."'
  check "(control) n2: fails when the pick is written to .make-it-state.md so later runs do not ask" \
    'ins "so it is asked every run." "Once picked, write \`APP_SUITE_PICKED=true\` to \`.make-it-state.md\` so later runs do not ask again."'
  check "(control) n3: fails when a pick that would be the only thing asked is taken as picked" \
    'ins "the pick alone is enough." "When the pick would be the only thing asked, take it as picked and go on without asking."'
  check "(control) n9: fails when the template shows a NOT TESTED block as PASS in row 24, in the row note, in Key Metrics or in section 1.7" \
    'N9="(a NOT TESTED block is shown as PASS in row 24 and counted under Categories passed)"; A="never under \"Categories passed\"." T="$N9" opp "$AT" "s/(\Q\$ENV{A}\E)/\$1 \$ENV{T}/" && A="| [COUNT] | [SEVERITY]     |" T="$N9" opp "$AT" "s/(\Q\$ENV{A}\E)/\$1 \$ENV{T}/" && A="- **Block status:** [PASS / FAIL / NO FINDINGS / NOT TESTED]" T="$N9" opp "$AT" "s/(\Q\$ENV{A}\E)/\$1 \$ENV{T}/" && A="| [CATEGORIES_PASSED]  |" T="$N9" opp "$AT" "s/(\Q\$ENV{A}\E)/\$1 \$ENV{T}/"'
  check "(control) n10: fails when the app's suite still runs on a live system" \
    'swap "$NM" "when the project has one, is NOT TESTED (production detected)" "when the project has one, when picked, still runs"'
  check "(control) fails when a preflight tool check runs python from the project folder again, or the ask claims the scan only reads the code" \
    'swap "$NM" "(cd \"\$T\" && python -m pytest --version 2>/dev/null) || echo" "python -m pytest --version 2>/dev/null || echo" && swap "$NM" "python3 -I -c \"import json; p = json.load" "python3 -c \"import json; p = json.load" && swap "$NM" "runs your project'"'"'s code on this computer'"'"' /" "runs your project'"'"'s code on this computer; the rest of this scan only reads your code'"'"' /"'
  check "(control) fails when the user-facing page drops the pick" \
    'swap "$CF" " — only when you pick it, because that runs your app'"'"'s own code." "." && swap "$CF" "run only if you pick it, every time." "run on every scan."'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
