#!/usr/bin/env bash
# E02-S92: /fix-it's counts, its "tests pass" and its "still builds" say what really happened.
# Three faults this pins shut, each by RUNNING the commands fix-it.md tells the AI to run, taken out of fix-it.md
# itself, against a stand-in for /fix-it's outside world (scripts/fix-it-fixtures/: a small project with a
# backend/ pytest suite and a frontend/ build and test, plus a first report and a re-scan report):
#   (a) Counts. "Fixed" used to be findings-before minus findings-after, so a finding whose scanner did not run the
#       second time counted as fixed. Now each in-scope finding has one recorded outcome -- fixed / changed, not
#       re-checked / failed / needs a person / not attempted -- and the five counts add up to the findings in scope.
#   (b) Tests. `pytest 2>/dev/null || npm test 2>/dev/null || echo "No test suite found"` turned a red suite into
#       "No test suite found" and exit 0. Now the result is passed / failed / not run from the real exit status and
#       output: missing tool, zero tests, red suite and timeout are never "passed".
#   (c) Build. `cd src/web-ui && npm run build 2>/dev/null` built nothing in an app whose build is in frontend/.
#       Now the build runs where the build is; a broken build is failed, no build is "not checked".
# The closing sentences /fix-it says are printed by the same record, and are checked word for word here.
# Review round: "fixed" needs the SCANNER that found the finding to have run again (a FAIL row only says something
# was found); "ready to ship" is about the whole new report, not the findings in scope; any failed count or non-zero
# exit is a failed test run; every folder with its own tests is run; a re-scan that is the first report is refused;
# a pass never covers a fail under the same check name; an unsaved fix and an unrecorded verdict are said as such.
# No Docker, no network, no scanner: `docker` is a two-line stub, and the fixture's "build" is one node file.
# Needs git, python3 with pytest, node and npm (CI has them; a missing one fails the first check, it does not skip).
# Usage: test-fix-it-true-results.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="$(cd "${1:-$root}" && pwd)"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; [ -z "${FIRST_FAIL_STOPS:-}" ] || exit 1; }   # the controls stop at the first failure
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it.
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

F=.claude/commands/fix-it.md; PY=.claude/make-it/scripts/fix-it-results.py; FX=scripts/fix-it-fixtures
flat() { tr '\n' ' ' | tr -s ' '; }
has() { flat < "$F" | gq -F -- "$1" || { echo "  missing in fix-it.md: $1"; false; }; }
hasnt() { ! gq -F -- "$1" "$F" || { echo "  still in fix-it.md: $1"; false; }; }

check "the tools this test needs are here: git, python3 with pytest, node, npm" \
  'command -v git >/dev/null && python3 -m pytest --version >/dev/null 2>&1 && command -v node >/dev/null && command -v npm >/dev/null'

# ---- the commands, taken out of fix-it.md ------------------------------------------------------------------
# "$HOME/.claude/make-it/..." in the blocks is the installed copy; here HOME is a folder whose copy is this tree's.
mkdir -p "$TMPD/home/.claude" "$TMPD/stub"; ln -s "$R/.claude/make-it" "$TMPD/home/.claude/make-it"
BLK="$TMPD/blocks"; mkdir -p "$BLK"
awk -v d="$BLK" '/^```bash/{n++; on=1; next} on && /^```/{on=0; close(f); next} on{f = sprintf("%s/%03d.sh", d, n); print > f}' "$F"
# line PATTERN: the one command line in fix-it.md's bash blocks that matches (a fixed string)
line() { awk -v p="$1" 'index($0, p) && !n++' "$BLK"/*.sh; }
# block PATTERN: the whole bash block that holds a line ending in PATTERN (a block is run as it is written)
block() { local b; for b in "$BLK"/*.sh; do if gq -E -- "$1\$" "$b"; then cat "$b"; return 0; fi; done; }
# fill LINE VALUE...: each [placeholder] in turn becomes the next value, quoted for the shell
fill() { local l="$1" v; shift; for v in "$@"; do l="$(printf '%s\n' "$l" | V="$v" perl -pe 's/"?\[[^\]]*\]"?/"\x27" . ($ENV{V} =~ s{\x27}{\x27\\\x27\x27}gr) . "\x27"/e')"; done; printf '%s\n' "$l"; }
L_START="$(line 'fix-it-results.py" start ')"; L_SCOPE="$(line 'fix-it-results.py" scope ')"
L_REC="$(line 'fix-it-results.py" record "[ID]" [event]')"; L_LINT="$(line 'fix-it-results.py" check lint-python -- ')"; L_RESCAN="$(line 'fix-it-results.py" rescan ')"
L_GONE="$(line 'fix-it-results.py" record "[ID]" gone')"; L_STILL="$(line 'fix-it-results.py" record "[ID]" still')"
L_OWN="$(line 'fix-it-results.py" check tests --in ')"; L_DOCKER="$(line 'fix-it-results.py" check docker-build -- docker compose build')"
B_TESTS="$(block 'fix-it-results[.]py" check tests')"; B_BUILD="$(block 'fix-it-results[.]py" check build')"
B_SUM="$(block 'fix-it-results[.]py" summary')"
check "fix-it.md has each command as a line to run: start, scope, record, rescan, gone, still, check tests, check build, summary" \
  '( for v in "$L_START" "$L_SCOPE" "$L_REC" "$L_RESCAN" "$L_GONE" "$L_STILL" "$L_OWN" "$L_DOCKER" "$L_LINT" "$B_TESTS" "$B_BUILD" "$B_SUM"; do [ -n "$v" ] || exit 1; done )'

# at NAME 'commands': run them in that project, output kept. proj NAME: a fresh copy of the fixture project, as a git
# project, with this run's record started (fix-it.md's own start line).
at() { (cd "$TMPD/$1" && unset CI && HOME="$TMPD/home" PATH="${STUBPATH:-$PATH}" FIXIT_CHECK_TIMEOUT="${TO:-120}" bash -c "$2") > "$TMPD/out" 2>&1; }
proj() { rm -rf "${TMPD:?}/$1"; mkdir -p "$TMPD/$1"; cp -R "$FX/project/." "$TMPD/$1/"; (cd "$TMPD/$1" && git init -q . 2>/dev/null) && at "$1" "$(fill "$L_START" "$R/$FX/report-before.md")"; }
out() { gq -xF -- "$1" "$TMPD/out" || { echo "  not printed: $1"; sed 's/^/    | /' "$TMPD/out" | tail -n 25; false; }; }
noout() { ! gq -E -- "$1" "$TMPD/out" || { echo "  must not be printed: $1"; grep -E -- "$1" "$TMPD/out" | sed 's/^/    | /'; false; }; }
PASSWORDS='Tests: passed|Build: the app still builds|every check I ran passed|is fixed and nothing failed|lists no critical or high'
# the scanner behind each row of the first report, as its sections name them
scanner() { case "$1" in DEP-NPM-*) echo "npm audit";; DEP-PIP-*) echo pip-audit;; DEP-TRIVY-*) echo Trivy;; SAST-SEMGREP-*) echo Semgrep;; SAST-LINT-*) echo Bandit;; *) echo Playwright;; esac; }
# pj DIR SCRIPTS: a package.json there with these scripts (JSON, as written)
pj() { mkdir -p "$TMPD/$1"; printf '{"scripts":{%s}}\n' "$2" > "$TMPD/$1/package.json"; }
# begin NAME: start the record and put the first report's eight findings in scope (the commands are fix-it.md's)
begin() {
  local id sev title
  while IFS='|' read -r id sev title; do at "$1" "$(fill "$L_SCOPE" "$id" "$sev" "$(scanner "$id")" "$title")" || return 1; done < <(
    awk '/^##### /{sub(/^##### /, ""); id = $0; sub(/:.*/, "", id); t = $0; sub(/^[^:]*: /, "", t)} /^- \*\*Severity:\*\* /{print id "|" $3 "|" t}' "$FX/report-before.md")
}
rec() { at "$1" "$(fill "$L_REC" "$2" "$3" "$4")"; }
gone() { at "$1" "$(fill "$L_GONE" "$2")"; }
still() { at "$1" "$(fill "$L_STILL" "$2")"; }
# rescan NAME REPORT: a fresh copy of that fixture report (a re-scan is written after the fixes), then fix-it.md's rescan line
rescan() { cp "$FX/$2" "$TMPD/$1.rescan.md" && at "$1" "$(fill "$L_RESCAN" "$TMPD/$1.rescan.md")"; }

# ---- (a) the counts ----------------------------------------------------------------------------------------
# Eight findings. Two fixed and confirmed; one changed, but Trivy did not run the second time; one changed and still
# reported; one tried and reverted; one for a person; two never touched (one of them a Trivy finding that the re-scan
# no longer lists). The old subtraction said 8 - 4 = 4 fixed.
scenario_a() {
  proj a && begin a || return 1
  rec a DEP-NPM-001 changed "upgraded next" && rec a DEP-PIP-001 changed "upgraded requests" && rec a DEP-TRIVY-001 changed "newer base image" \
    && rec a SAST-SEMGREP-001 changed "query takes parameters" && rec a SAST-SEMGREP-002 failed "it broke the tests and was reverted" \
    && rec a OTG-AUTHZ-001 person "a business rule" && rescan a report-after.md \
    && gone a DEP-NPM-001 && gone a DEP-PIP-001 && gone a DEP-TRIVY-001 && still a SAST-SEMGREP-001
}
check "(a) the scenario records through fix-it.md's own commands" 'scenario_a || { cat "$TMPD/out"; false; }'
check "(a) the old subtraction on the two fixture reports says 4 fixed (8 before, 4 after): the fault this replaces" \
  '[ "$(( $(grep -c "^##### " "$FX/report-before.md") - $(grep -c "^##### " "$FX/report-after.md") ))" = 4 ]'
check "(a) a finding that was never changed cannot be marked gone, and no event can set 'fixed' directly" \
  '! gone a DEP-TRIVY-002 && out "fix-it-results: DEP-TRIVY-002 has no kept change (it is \"not attempted\"), so the re-scan does not change its outcome" && ! rec a SAST-LINT-001 fixed "said so" && ! rec a NOT-IN-SCOPE-001 changed "x"'
at a "$B_SUM" || true; cp "$TMPD/out" "$TMPD/sum-a"
check "(a) the counts are what happened: 2 fixed, 1 changed but not re-checked, 2 failed, 1 needs a person, 2 not attempted, of 8" \
  'out "| **Total** | 8 | 2 | 1 | 2 | 1 | 2 |" && out "| CRITICAL | 1 | 1 | 0 | 0 | 0 | 0 |" && out "| HIGH | 7 | 1 | 1 | 2 | 1 | 2 |"'
check "(a) every row of the count table adds up to its findings in scope" \
  '[ "$(grep -cE "^\| (CRITICAL|HIGH|\*\*Total\*\*) \|" "$TMPD/out")" = 3 ] && grep -E "^\| (CRITICAL|HIGH|\*\*Total\*\*) \|" "$TMPD/out" | awk -F"|" "{ if (\$3 + 0 != \$4 + \$5 + \$6 + \$7 + \$8) bad = 1 } END { exit bad }"'
check "(a) each of the eight findings is listed once, with one outcome" \
  '[ "$(grep -cE "^- [A-Z-]+-[0-9]+ \((CRITICAL|HIGH)\) .* -- (FIXED|CHANGED, NOT RE-CHECKED|FAILED|NEEDS A PERSON|NOT ATTEMPTED)(: |$)" "$TMPD/out")" = 8 ] && [ "$(grep -oE "^- [A-Z-]+-[0-9]+ " "$TMPD/out" | sort -u | grep -c .)" = 8 ]'
check "(a) Trivy did not run the second time: its changed finding is 'not re-checked', its untouched one 'not attempted', neither is fixed" \
  'out "- DEP-TRIVY-001 (HIGH) Known flaw in the base image (openssl) -- CHANGED, NOT RE-CHECKED: newer base image; the new scan did not run Trivy" && out "- DEP-TRIVY-002 (HIGH) Known flaw in the base image (zlib) -- NOT ATTEMPTED" && out "- SAST-SEMGREP-001 (HIGH) SQL built from user input in the search route -- FAILED: query takes parameters; the new scan still reports it"'
check "(a) the sentences for the person say those counts, in plain words" \
  'out "Of the 8 findings I set out to fix, 2 are fixed: for each, the change is kept, and the scanner that found it ran in the new scan and no longer reports it." && out "1 was changed but not re-checked: the new report does not show that the scanner that found it ran, so I can'"'"'t say it is fixed. (DEP-TRIVY-001)" && out "2 are not fixed: I tried, and the fix did not work or the new scan still reports the problem. (SAST-SEMGREP-001, SAST-SEMGREP-002)" && out "1 needs a person: I did not fix it, and it is on the manual list. (OTG-AUTHZ-001)" && out "2 were not attempted: nothing was changed for them. (DEP-TRIVY-002, SAST-LINT-001)" && out "Of the 8 critical and high findings I set out to fix: 6 not confirmed fixed (DEP-TRIVY-001, DEP-TRIVY-002, SAST-SEMGREP-001, SAST-SEMGREP-002, OTG-AUTHZ-001, SAST-LINT-001)." && out "The new report still lists 0 critical and 4 high findings, counting any I did not set out to fix: this is not ready to ship."'
check "(a) with no check run, the summary says tests and build were not run, and the bottom line is not an all-clear" \
  'out "Tests: not run. I did not run your app'"'"'s tests, so I can'"'"'t say they pass." && out "Build: not checked. I did not build your app, so I can'"'"'t say it still builds." && out "Bottom line: this is not finished -- 6 findings are not confirmed fixed; the build was not checked; no tests ran; the new report still lists 4 critical or high findings." && noout "$PASSWORDS"'
# no re-scan at all: a kept change is not "fixed"
check "(a) with no re-scan, a changed finding stays 'changed, not re-checked', and 'gone' is refused" \
  'proj a2 && begin a2 && rec a2 DEP-NPM-001 changed "upgraded next" && ! gone a2 DEP-NPM-001 && { at a2 "$B_SUM" || true; } && out "- DEP-NPM-001 (CRITICAL) Remote code execution in the web framework (next) -- CHANGED, NOT RE-CHECKED: upgraded next; no new scan has checked it" && out "Of the 8 findings I set out to fix, none is confirmed fixed." && out "1 was changed but not re-checked: no new scan ran after the change, so I can'"'"'t say it is fixed. (DEP-NPM-001)" && out "No new scan was recorded, so I can'"'"'t say how many critical and high findings are left." && out "| **Total** | 8 | 0 | 1 | 0 | 0 | 7 |"'
check "(a) a re-scan report with no table of what ran records nothing, and says so" \
  'printf "# no table here\n" > "$TMPD/empty.md" && ! at a2 "$(fill "$L_RESCAN" "$TMPD/empty.md")" && out "fix-it-results: I could not read which checks ran from $TMPD/empty.md (no Category Breakdown rows with ID and Status). Nothing is recorded, so every changed finding stays \"changed, not re-checked\"."'
check "(a) the record lives inside .git: the project's files show nothing new" \
  '[ -s "$TMPD/a/.git/fix-it-run/ledger.jsonl" ] && [ "$(cd "$TMPD/a" && git status --porcelain | sort | tr "\n" " ")" = "?? backend/ ?? frontend/ " ]'

# all fixed, every check green: the one case that may sound like a success
all_fixed() {
  proj ok || return 1
  at ok "$(fill "$L_SCOPE" DEP-NPM-001 CRITICAL "npm audit" "Remote code execution in the web framework (next)")" \
    && at ok "$(fill "$L_SCOPE" DEP-PIP-001 HIGH pip-audit "Known flaw in the HTTP library (requests)")" \
    && rec ok DEP-NPM-001 changed "upgraded next" && rec ok DEP-PIP-001 changed "upgraded requests" \
    && at ok "$B_TESTS" && at ok "$B_BUILD" && rescan ok report-clean.md && gone ok DEP-NPM-001 && gone ok DEP-PIP-001 && at ok "$B_SUM"
}
check "(all fixed) both findings fixed, tests and build green: the sentences say so, and name what ran" \
  'all_fixed && out "All 2 findings I set out to fix are fixed: for each, the change is kept, and the scanner that found it ran in the new scan and no longer reports it." && out "Tests: passed in backend/ (\`python3 -m pytest -q -p no:cacheprovider\`: 2 passed)." && out "Tests: passed in frontend/ (\`npm test\`: 1 passed)." && out "Build: the app still builds (\`npm run build\` in frontend/ finished without an error)." && out "Of the 2 critical and high findings I set out to fix: all 2 are fixed." && out "The new report lists no critical or high finding." && out "Bottom line: everything I set out to fix is fixed, and every check I ran passed." || { cat "$TMPD/out"; false; }'
check "(all fixed) the checks left no cache or bytecode files in the project" \
  '[ -z "$(find "$TMPD/ok" -name __pycache__ -o -name .pytest_cache -o -name "*.pyc")" ]'

# ---- (b) the tests -----------------------------------------------------------------------------------------
# tests NAME: run fix-it.md's test block there, keep its exit status, then print the summary
tests() { local rc=0; at "$1" "$B_TESTS" || rc=$?; cp "$TMPD/out" "$TMPD/run"; at "$1" "$B_SUM" || true; return "$rc"; }
check "(b) a red pytest suite in backend/ is 'did NOT pass', with the counts, and the block exits non-zero" \
  'proj b1 && sed "s/== 5/== 6/" "$FX/project/backend/tests/test_app.py" > "$TMPD/b1/backend/tests/test_app.py" && ! tests b1 && out "Tests: did NOT pass in backend/ (\`python3 -m pytest -q -p no:cacheprovider\`: 1 failed, 1 passed)." && out "Tests: passed in frontend/ (\`npm test\`: 1 passed)." && noout "Tests: passed in backend|No test suite found|every check I ran passed" && gq -F "the tests did not pass" "$TMPD/out"'
check "(b) a red suite at the project root (the old fall-through case) is 'did NOT pass in the project folder'" \
  'rm -rf "$TMPD/b1r" && mkdir "$TMPD/b1r" && cp -R "$FX/project/backend/." "$TMPD/b1r/" && sed "s/== 5/== 6/" "$FX/project/backend/tests/test_app.py" > "$TMPD/b1r/tests/test_app.py" && (cd "$TMPD/b1r" && git init -q . 2>/dev/null) && at b1r "$(fill "$L_START" x)" && ! tests b1r && out "Tests: did NOT pass in the project folder (\`python3 -m pytest -q -p no:cacheprovider\`: 1 failed, 1 passed)." && noout "$PASSWORDS|No test suite found"'
check "(b) a test command whose tool is not installed is 'no tests ran', never a pass" \
  'proj b2 && rm -rf "$TMPD/b2/backend" && sed "s/node --test/no-such-test-tool-e02s92/" "$FX/project/frontend/package.json" > "$TMPD/b2/frontend/package.json" && ! tests b2 && out "Tests: no tests ran in frontend/ (\`npm test\`: the command could not be started (exit status 127: a tool it needs is not installed)). That is not a pass." && noout "Tests: passed|every check I ran passed"'
check "(b) pytest not installed: the backend suite is 'no tests ran', never a pass" \
  'proj b3 && rm -rf "$TMPD/b3/frontend" && printf "%s\n" "#!/bin/sh" "case \" \$* \" in *\" -m pytest \"*) echo \"No module named pytest\" >&2; exit 1;; esac" "exec \"$(command -v python3)\" \"\$@\"" > "$TMPD/stub/python3" && cp "$TMPD/stub/python3" "$TMPD/stub/python" && chmod +x "$TMPD/stub/python3" "$TMPD/stub/python" && ! STUBPATH="$TMPD/stub:$PATH" tests b3 && out "Tests: no tests ran in backend/ (\`python3 -m pytest -q -p no:cacheprovider\`: the command could not be started (exit status 127: a tool it needs is not installed)). That is not a pass." && noout "Tests: passed"; rc=$?; rm -f "$TMPD/stub/python3" "$TMPD/stub/python"; [ "$rc" = 0 ]'
check "(b) a suite that collects zero tests, and a test script that runs none, are 'no tests ran'" \
  'proj b4 && printf "x = 1\n" > "$TMPD/b4/backend/tests/test_app.py" && sed "s/node --test/node -e 0/" "$FX/project/frontend/package.json" > "$TMPD/b4/frontend/package.json" && ! tests b4 && out "Tests: no tests ran in backend/ (\`python3 -m pytest -q -p no:cacheprovider\`: the test command ran but found no tests). That is not a pass." && out "Tests: no tests ran in frontend/ (\`npm test\`: the test command finished without an error, but its output does not show a test that ran). That is not a pass." && noout "Tests: passed|every check I ran passed"'
check "(b) a project with no test suite is 'no tests ran', and the block exits non-zero" \
  'proj b5 && rm -rf "$TMPD/b5/backend/tests" "$TMPD/b5/backend/pytest.ini" "$TMPD/b5/frontend/app.test.js" && sed "/\"test\":/d; s/\"node build.js\",/\"node build.js\"/" "$FX/project/frontend/package.json" > "$TMPD/b5/frontend/package.json" && ! tests b5 && out "Tests: no tests ran. I found no test suite in this project. That is not a pass." && noout "Tests: passed"'
check "(b) a test run that does not finish is stopped and is 'did NOT pass', never a pass" \
  'proj b6 && rm -rf "$TMPD/b6/backend" && sed "s/node --test/sleep 60/" "$FX/project/frontend/package.json" > "$TMPD/b6/frontend/package.json" && ! TO=3 tests b6 && out "Tests: did NOT pass in frontend/ (\`npm test\`: it did not finish within 3 seconds, so I stopped it)." && noout "Tests: passed"'
check "(b) the project's own test command goes through the same record: red is red, a missing folder is not run" \
  'proj b7 && ! at b7 "$(fill "$L_OWN" backend false)" && out "CHECK tests | backend/ | false | FAILED | exit status 1" && ! at b7 "$(fill "$L_OWN" no-such-folder "true")" && { at b7 "$B_SUM" || true; } && noout "Tests: passed"'
check "(b) a later green run replaces an earlier red one (the self-healing loop reports the code as it now is)" \
  'cp "$FX/project/backend/tests/test_app.py" "$TMPD/b1/backend/tests/test_app.py" && tests b1 && out "Tests: passed in backend/ (\`python3 -m pytest -q -p no:cacheprovider\`: 2 passed)." && noout "did NOT pass"'

# ---- (c) the build -----------------------------------------------------------------------------------------
build() { local rc=0; at "$1" "$B_BUILD" || rc=$?; cp "$TMPD/out" "$TMPD/run"; at "$1" "$B_SUM" || true; return "$rc"; }
check "(c) the build in frontend/ is found and run there" \
  'proj c1 && build c1 && out "Build: the app still builds (\`npm run build\` in frontend/ finished without an error)."'
check "(c) a broken build in frontend/ is 'does NOT build', and the block exits non-zero" \
  'proj c2 && echo "throw new Error(\"build broken\")" >> "$TMPD/c2/frontend/build.js" && ! build c2 && out "Build: the app does NOT build (\`npm run build\` in frontend/ failed: exit status 1)." && noout "Build: the app still builds|every check I ran passed" && gq -F "the app does not build" "$TMPD/out"'
check "(c) a build two folders down (src/web-ui/) and one in backend/ are both found" \
  'proj c3 && mkdir "$TMPD/c3/src" && mv "$TMPD/c3/frontend" "$TMPD/c3/src/web-ui" && cp "$FX/project/frontend/package.json" "$FX/project/frontend/build.js" "$TMPD/c3/backend/" && echo "process.exit(3)" >> "$TMPD/c3/backend/build.js" && ! build c3 && out "Build: the app still builds (\`npm run build\` in src/web-ui/ finished without an error)." && out "Build: the app does NOT build (\`npm run build\` in backend/ failed: exit status 3)."'
check "(c) a project with no build step is 'not checked', never 'still builds'" \
  'proj c4 && rm -rf "$TMPD/c4/frontend" && ! build c4 && out "Build: not checked. I don'"'"'t know how to build this project: I found no \`build\` script in a package.json and no \`build\` target in a Makefile. I can'"'"'t say the app still builds." && noout "Build: the app still builds"'
check "(c) a build whose tool is not installed is 'not checked', never 'still builds'" \
  'proj c5 && sed "s/node build.js/no-such-build-tool-e02s92 build/" "$FX/project/frontend/package.json" > "$TMPD/c5/frontend/package.json" && ! build c5 && out "Build: not checked in frontend/ (\`npm run build\`: the command could not be started (exit status 127: a tool it needs is not installed)). I can'"'"'t say the app still builds." && noout "Build: the app still builds"'
# the Docker build line, with a stand-in for docker (it is never the real one: the stub is first on PATH)
printf '%s\n' '#!/bin/sh' 'exit "${DOCKER_STUB_EXIT:-0}"' > "$TMPD/stub/docker"; chmod +x "$TMPD/stub/docker"
check "(c) the Docker build line reports the command's own exit status: failed when it fails, passed when it passes" \
  'proj c6 && ! DOCKER_STUB_EXIT=1 STUBPATH="$TMPD/stub:$PATH" at c6 "$L_DOCKER" && out "CHECK docker-build | (project folder) | docker compose build | FAILED | exit status 1" && STUBPATH="$TMPD/stub:$PATH" at c6 "$L_DOCKER" && out "CHECK docker-build | (project folder) | docker compose build | PASSED | it finished without an error"'
check "(tests not run) everything fixed and the build green, but no tests ran: the bottom line is not an all-clear" \
  'proj d && rm -rf "$TMPD/d/backend/tests" "$TMPD/d/backend/pytest.ini" "$TMPD/d/frontend/app.test.js" && sed "/\"test\":/d; s/\"node build.js\",/\"node build.js\"/" "$FX/project/frontend/package.json" > "$TMPD/d/frontend/package.json" && at d "$(fill "$L_SCOPE" DEP-NPM-001 CRITICAL "npm audit" "Remote code execution in the web framework (next)")" && rec d DEP-NPM-001 changed "upgraded next" && { at d "$B_TESTS" || true; } && at d "$B_BUILD" && rescan d report-clean.md && gone d DEP-NPM-001 && at d "$B_SUM" && out "The 1 finding I set out to fix is fixed: the change is kept, and the scanner that found it ran in the new scan and no longer reports it." && out "Tests: no tests ran. I found no test suite in this project. That is not a pass." && out "Bottom line: everything I set out to fix is fixed and nothing failed, but not every check ran (see above), so this is not a full all-clear." && noout "every check I ran passed|Tests: passed"'

# ---- the review round ----------------------------------------------------------------------------------------
# (1) "fixed" needs the scanner that found the finding to have run. report-partial.md: Bandit is under "Not run:"
# but its row is FAIL (ESLint found something); pip-audit's row is NO FINDINGS and it is not in "Tools used:"; the
# npm audit row is missing; Trivy's row is PASS.
partial() {
  proj r1 && begin r1 || return 1
  rec r1 SAST-LINT-001 changed "checking is on again" && rec r1 DEP-PIP-001 changed "upgraded requests" && rec r1 DEP-NPM-001 changed "upgraded next" \
    && rec r1 DEP-TRIVY-001 changed "newer base image" && at r1 "$(fill "$L_SCOPE" SAST-LINT-007 HIGH ESLint "Use of eval in the settings page")" \
    && rec r1 SAST-LINT-007 changed "eval removed" && rescan r1 report-partial.md \
    && gone r1 SAST-LINT-001 && gone r1 DEP-PIP-001 && gone r1 DEP-NPM-001 && gone r1 DEP-TRIVY-001 && gone r1 SAST-LINT-007 && at r1 "$B_SUM"
}
check "(1) a FAIL row is not 'the scanner ran': Bandit is under 'Not run:', so its finding is 'changed, not re-checked', not fixed" \
  'partial && out "- SAST-LINT-001 (HIGH) Certificate checking switched off (verify=False) -- CHANGED, NOT RE-CHECKED: checking is on again; the new scan did not run Bandit" || { cat "$TMPD/out"; false; }'
check "(1) a NO FINDINGS row whose scanner is not among the tools that ran, and a missing row, are 'not re-checked' too" \
  'out "- DEP-PIP-001 (HIGH) Known flaw in the HTTP library (requests) -- CHANGED, NOT RE-CHECKED: upgraded requests; the new report does not say pip-audit ran (DEP-PIP: NO FINDINGS)" && out "- DEP-NPM-001 (CRITICAL) Remote code execution in the web framework (next) -- CHANGED, NOT RE-CHECKED: upgraded next; the new report has no row for DEP-NPM"'
check "(1) a PASS row, and a FAIL row whose scanner is named in 'Tools used:', do count: those two are fixed, and only those" \
  'out "- DEP-TRIVY-001 (HIGH) Known flaw in the base image (openssl) -- FIXED: newer base image" && out "- SAST-LINT-007 (HIGH) Use of eval in the settings page -- FIXED: eval removed" && out "| **Total** | 9 | 2 | 3 | 0 | 0 | 4 |" && out "3 were changed but not re-checked: the new report does not show that the scanner that found them ran, so I can'"'"'t say they are fixed. (DEP-NPM-001, DEP-PIP-001, SAST-LINT-001)"'

# (2) /fix-it critical: the one CRITICAL in scope is fixed and every check is green, but the new report still lists 4 HIGH
critical_only() {
  proj s1 && at s1 "$(fill "$L_SCOPE" DEP-NPM-001 CRITICAL "npm audit" "Remote code execution in the web framework (next)")" && rec s1 DEP-NPM-001 changed "upgraded next" \
    && at s1 "$B_TESTS" && at s1 "$B_BUILD" && rescan s1 report-after.md && gone s1 DEP-NPM-001 && at s1 "$B_SUM"
}
check "(2) /fix-it critical with highs left in the new report: the sentences say 'the 1 I set out to fix', count what is left, and are not an all-clear" \
  'critical_only && out "The 1 finding I set out to fix is fixed: the change is kept, and the scanner that found it ran in the new scan and no longer reports it." && out "Of the 1 critical or high finding I set out to fix: it is fixed." && out "The new report still lists 0 critical and 4 high findings, counting any I did not set out to fix: this is not ready to ship." && out "Bottom line: everything I set out to fix is fixed, and every check I ran passed, but the new report still lists 4 critical or high findings, so this is not ready to ship." && noout "lists no critical or high|Critical and high findings: all" || { cat "$TMPD/out"; false; }'
check "(2) a new report whose critical and high counts cannot be read is not 'none left'" \
  'proj s2 && at s2 "$(fill "$L_SCOPE" DEP-NPM-001 CRITICAL "npm audit" "x")" && rec s2 DEP-NPM-001 changed "y" && sed "/^| Critical /d" "$FX/report-clean.md" > "$TMPD/s2.nocount.md" && at s2 "$(fill "$L_RESCAN" "$TMPD/s2.nocount.md")" && gone s2 DEP-NPM-001 && at s2 "$B_SUM" && out "I could not read from the new report how many critical and high findings it lists, so I can'"'"'t say none are left." && noout "lists no critical or high"'
check "(2) fix-it.md: the /ship-it line needs the whole new report to list no critical or high finding" \
  'has "[Only if the summary printed \"The new report lists no critical or high finding.\" and no check FAILED -- the whole new report, not only the findings this run set out to fix:]" && has "[Otherwise -- never the line above, and never \"your critical and high findings are fixed\":]" && hasnt "Your critical and high-severity findings are fixed."'

# (3) a red test run is red, whatever else its output says
check "(3) output with 'No tests found' AND '3 failed, 2 passed', exit 1: did NOT pass (not 'no tests ran')" \
  'proj t1 && rm -rf "$TMPD/t1/backend" && pj t1/frontend "\"test\":\"echo No tests found, exiting with code 1; echo Tests: 3 failed, 2 passed, 5 total; exit 1\"" && ! tests t1 && out "Tests: did NOT pass in frontend/ (\`npm test\`: 3 failed, 2 passed)." && noout "no tests ran in|Tests: passed"'
check "(3) '3 failed, 2 passed' with exit 0 (the script swallowed the failure): did NOT pass (not passed)" \
  'proj t2 && rm -rf "$TMPD/t2/backend" && pj t2/frontend "\"test\":\"echo Tests: 3 failed, 2 passed, 5 total\"" && ! tests t2 && out "Tests: did NOT pass in frontend/ (\`npm test\`: 3 failed, 2 passed; exit status 0)." && noout "Tests: passed|nothing failed"'
check "(3) the runner's own no-tests signal with no count at all (exit 1) is 'no tests ran', not a failure and not a pass" \
  'proj t3 && rm -rf "$TMPD/t3/backend" && pj t3/frontend "\"test\":\"echo No tests found, exiting with code 1; exit 1\"" && ! tests t3 && out "Tests: no tests ran in frontend/ (\`npm test\`: the test command ran but found no tests). That is not a pass." && noout "did NOT pass|Tests: passed"'

# (4) every folder with its own tests is run: a green suite at the root does not hide a red one in backend/
nested() {
  proj n1 && rm -rf "$TMPD/n1/frontend" && mkdir "$TMPD/n1/tests" && printf "[pytest]\ntestpaths = tests\n" > "$TMPD/n1/pytest.ini" \
    && printf "def test_root():\n    assert True\n" > "$TMPD/n1/tests/test_root.py" && sed "s/== 5/== 6/" "$FX/project/backend/tests/test_app.py" > "$TMPD/n1/backend/tests/test_app.py"
}
check "(4) a green root suite and a red backend/ suite: both are run and named, and the tests are red" \
  'nested && ! tests n1 && out "Tests: passed in the project folder (\`python3 -m pytest -q -p no:cacheprovider --ignore=backend\`: 1 passed)." && out "Tests: did NOT pass in backend/ (\`python3 -m pytest -q -p no:cacheprovider\`: 1 failed, 1 passed)." && gq -F "the tests did not pass" "$TMPD/out" && noout "every check I ran passed|nothing failed" || { cat "$TMPD/run" "$TMPD/out"; false; }'

# (a) a "re-scan" that is the first report, a copy of it, or older than the first fix is refused
check "(a) the first report given back as the re-scan (the same file, or the same content) is refused, and nothing becomes fixed" \
  'proj ra && begin ra && rec ra DEP-NPM-001 changed "upgraded next" && ! at ra "$(fill "$L_RESCAN" "$R/$FX/report-before.md")" && out "fix-it-results: $R/$FX/report-before.md is the report this run started from, not a new scan. Nothing is recorded, so every changed finding stays \"changed, not re-checked\"." && cp "$FX/report-before.md" "$TMPD/ra.copy.md" && ! at ra "$(fill "$L_RESCAN" "$TMPD/ra.copy.md")" && ! gone ra DEP-NPM-001 && { at ra "$B_SUM" || true; } && out "| **Total** | 8 | 0 | 1 | 0 | 0 | 7 |"'
check "(a) a report written before this run's first fix is refused" \
  'cp "$FX/report-clean.md" "$TMPD/ra.old.md" && touch -t 200001010000 "$TMPD/ra.old.md" && ! at ra "$(fill "$L_RESCAN" "$TMPD/ra.old.md")" && out "fix-it-results: $TMPD/ra.old.md was written before the first fix of this run, so it cannot have checked any fix. Nothing is recorded, so every changed finding stays \"changed, not re-checked\"."'

# (b) a pass never covers a fail under the same check name
check "(b) a check that failed, then a different command under the same name that passes: both are kept, and it is not an all-clear" \
  'proj rb && ! at rb "${L_LINT%% -- *} -- false" && at rb "${L_LINT%% -- *} -- true" && { at rb "$B_SUM" || true; } && out "Check \"lint-python\": FAILED in the project folder (\`false\`: exit status 1)." && out "Check \"lint-python\": passed in the project folder (\`true\`)." && gq -F "the check \"lint-python\" failed" "$TMPD/out" && noout "every check I ran passed|nothing failed"'
check "(b) fix-it.md gives each linter its own name" 'has "check lint-python -- ruff check [changed files]" && has "check lint-js --in [folder] -- npx --no-install eslint [changed files]" && has "A different command under the same name is kept beside the first one: a pass never covers a fail."'

# (c) each sentence says what happened
check "(c) a re-scan that ran with no result recorded for a changed finding says so (not 'no new scan ran')" \
  'proj rc && begin rc && rec rc DEP-NPM-001 changed "upgraded next" && rescan rc report-clean.md && at rc "$B_SUM" && out "1 was changed but not re-checked: the new scan ran, but I did not record what it says about it, so I can'"'"'t say it is fixed. (DEP-NPM-001)" && noout "no new scan ran"'
check "(c) a fix that could not be saved is worded as that, never 'I did not fix it'" \
  'rec rc DEP-PIP-001 unsaved "the commit failed" && at rc "$B_SUM" && out "1 has a fix in your files that could not be saved: it needs a person to save it, and it is not fixed until it is saved and scanned again. (DEP-PIP-001)" && noout "I did not fix" && has "| \`unsaved\` | the fix is in the files but could not be saved (the commit failed, or \`HOOKS OFF\`): it needs a person to save it |"'

# (d) a Makefile build
check "(d) a project built by 'make build' is built that way, and a red one is 'does NOT build'" \
  'proj rd && rm -rf "$TMPD/rd/frontend" && printf "build:\n\tfalse\n" > "$TMPD/rd/Makefile" && ! build rd && gq -E "^Build: the app does NOT build \(\`make build\` in the project folder failed: exit status [0-9]+\)\.$" "$TMPD/out" && printf "build:\n\ttrue\n" > "$TMPD/rd/Makefile" && build rd && out "Build: the app still builds (\`make build\` in the project folder finished without an error)."'

# (e) the reviewer's other surviving mutants
check "(e) start begins a fresh record: nothing of an earlier run is left in it" \
  'at a "$(fill "$L_START" "$R/$FX/report-before.md")" && at a "$B_SUM" && out "| **Total** | 0 | 0 | 0 | 0 | 0 | 0 |" && out "No findings were in scope, so nothing was fixed." && [ "$(grep -c . "$TMPD/a/.git/fix-it-run/ledger.jsonl")" = 1 ]'
check "(e) a test run that hangs is stopped with everything it started, at once" \
  'proj re && rm -rf "$TMPD/re/backend" && pj re/frontend "\"test\":\"sleep 41 & sleep 42 & wait\"" && T0="$(date +%s)" && ! TO=3 tests re && [ "$(( $(date +%s) - T0 ))" -lt 25 ] && [ "$(pgrep -f "^sleep 4[12]$" | grep -c . || true)" = 0 ] && out "Tests: did NOT pass in frontend/ (\`npm test\`: it did not finish within 3 seconds, so I stopped it)."'

# not a git project; and CI is not forced onto a build
check "outside a git project nothing is recorded, the command stops, and fix-it.md has the sentence for the person" \
  'mkdir -p "$TMPD/nogit" && ! (cd "$TMPD/nogit" && GIT_CEILING_DIRECTORIES="$TMPD" HOME="$TMPD/home" bash -c "$(fill "$L_START" x)") > "$TMPD/out" 2>&1 && out "fix-it-results: this folder is not inside a git project, so there is nowhere to keep the record" && has "\"This folder is not a git project, so I have nowhere to keep a record of what gets fixed and no way to undo a fix. I changed nothing, and nothing is fixed. Run \`git init\` here (or /resume-it), then run /fix-it again.\" Report nothing as fixed."'
check "a build is not run with CI=true forced on (some builds turn warnings into errors under CI); a test run is" \
  'proj ci && rm -rf "$TMPD/ci/backend" && pj ci/frontend "\"build\":\"node -e \\\"process.exit(process.env.CI ? 1 : 0)\\\"\",\"test\":\"node -e \\\"console.log(process.env.CI ? 1 : 0, String.fromCharCode(112,97,115,115,101,100))\\\"\"" && build ci && out "Build: the app still builds (\`npm run build\` in frontend/ finished without an error)." && tests ci && out "Tests: passed in frontend/ (\`npm test\`: 1 passed)."'

# ---- the words in fix-it.md --------------------------------------------------------------------------------
# the bash blocks of the verify step
VER="$(awk '/^<step name="verify">/{on=1} on && /^<\/step>/{on=0} on && /^```bash/{b=1; next} b && /^```/{b=0} on && b' "$F")"
check "fix-it.md: the old fall-through test line, the wrong build folder and the subtraction are gone" \
  'hasnt "|| echo \"No test suite found\"" && hasnt "cd src/web-ui" && hasnt "delta = original_count - new_count" && hasnt "All tests still pass" && hasnt "All fixes verified" && hasnt "| Severity      | Before | After | Fixed | Remaining |"'
check "fix-it.md: no check in the verify step hides its errors or falls through to another command" \
  '[ -n "$VER" ] && [ "$(printf "%s\n" "$VER" | grep -cE "2>/dev/null|\|\| *(echo|true|:)")" = 0 ]'
check "fix-it.md: the three results, and 'not run' is never a pass" \
  'has "**Every check has one of three results: PASSED, FAILED or NOT RUN.** The result is the one the check command prints, taken from the real command'"'"'s exit status and output." && has "NOT RUN (no test suite, no build step, a tool that is not installed, a folder that is not there) is never a pass and is never worded as one." && has "For NOT RUN, say \"the build was not checked\", never \"the app still builds\"."'
check "fix-it.md: counts come from the record, one outcome per finding, never from subtraction" \
  'has "Every count and every result /fix-it reports later comes from this record, never from memory and never from subtracting one report'"'"'s totals from another'"'"'s." && has "**Never work a \"fixed\" count out by subtracting the new report'"'"'s totals from the old one'"'"'s.**" && has "\`changed\` is not \"fixed\". Nothing is called fixed before the re-scan (Phase 4). A finding with no line stays \"not attempted\", and is reported that way." && has "A finding is **fixed** only when the scanner that found it ran in the re-scan and no longer reports it:" && has "A FAIL row alone is not enough: it only says something was found, perhaps by another scanner in the same row." && has "**Every in-scope finding has exactly one outcome:** fixed / changed, not re-checked / failed / needs a person / not attempted. The five counts add up to the findings in scope."'
check "fix-it.md: the report says the summary's sentences and never a better result" \
  'has "**Say the sentences under \"SAY THIS TO THE PERSON\" as they are printed.**" && has "You may not turn a result into a better one: \"not re-checked\" is never \"fixed\", \"no tests ran\" and \"not checked\" are never \"pass\" or \"still builds\", and a failed check is never left out." && has "11. **Report what happened, not what was hoped.**"'

# ---- controls (this repo only): a copy with the old behaviour back must fail the checks above ---------------
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of fix-it.md, the results script and the fixtures with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - "$F" "$PY" "$FX" | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! FIRST_FAIL_STOPS=1 bash "$SELF" "$d" >/dev/null 2>&1
  }
  check "(control) passes on an untouched copy" \
    'd="$TMPD/c"; mkdir -p "$d" && tar -cf - "$F" "$PY" "$FX" | tar -xf - -C "$d" && bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control, fault a) fails when a finding the re-scan did not check counts as fixed (the old subtraction)" \
    'opp "$PY" "s/                if ran:\n/                if True:\n/"'
  check "(control, fault a) fails when a finding nobody touched starts out as fixed" \
    'opp "$PY" "s/r\[3\], .not attempted., /r[3], \x27changed\x27, /"'
  check "(control, fault b) fails with the old test line back in fix-it.md" \
    'opp "$F" "s/^[^\n]*fix-it-results[.]py\" check tests\n/pytest 2>\/dev\/null || npm test 2>\/dev\/null || echo \"No test suite found\"\n/m"'
  check "(control, fault b) fails when 'no tests ran' is recorded as passed, and when a timeout is" \
    'opp "$PY" "s/return .not run., .the test command ran but found no tests./return \x27passed\x27, \x27ok\x27/" && opp "$PY" "s/return .failed., .it did not finish/return \x27passed\x27, \x27it did not finish/"'
  check "(control, fault c) fails with the old build lines back in fix-it.md" \
    'opp "$F" "s/^[^\n]*fix-it-results[.]py\" check build\n/cd src\/web-ui && npm run build 2>\/dev\/null\n/m"'
  check "(control, fault c) fails when a build that exits non-zero is passed, and when 'no build step' is worded as still builds" \
    'opp "$PY" "s/if rc == 0 else \(.failed., .exit status %d. % rc\)/if True else 0/" && opp "$PY" "s/.no tests ran. if name == .tests. else .not checked./\x27no tests ran\x27 if name == \x27tests\x27 else \x27the app still builds\x27/"'
  # the review round's mutants: each puts one reviewed fault back
  check "(control, 1) fails when a FAIL or NO FINDINGS row alone counts as 'the scanner ran'" \
    'opp "$PY" "s/    if st == .PASS.:/    if st in (\x27PASS\x27, \x27FAIL\x27, \x27NO FINDINGS\x27):/"'
  check "(control, 1) fails when a missing row counts as ran, and when the 'Not run:' list is not read" \
    'opp "$PY" "s/\.get\(cat\)\n/.get(cat, \x27PASS\x27)\n/" && opp "$PY" "s/    if named\(scanner, facts\.get\(.notrun., ..\)\):/    if False:/"'
  check "(control, 2) fails when the ship line looks only at the findings in scope" \
    'opp "$PY" "s/        if left == 0:/        if not open_urgent:/"'
  check "(control, 3) fails when a failed count with exit 0 passes, and when the no-tests rule ignores the counts" \
    'opp "$PY" "s/    if failed or rc != 0:/    if rc != 0:/" && opp "$PY" "s/    if not passed and not failed and \(rc == 5 or/    if (rc == 5 or/"'
  check "(control, 3) fails when the no-tests wording rule is removed" \
    'opp "$PY" "s/\(rc == 5 or re\.search\(r.no tests ran[^\n]*\n/(rc == 5):\n/"'
  check "(control, 4) fails when only the top folder's test suite is run" \
    'opp "$PY" "s/suites = \[d for d in dirs if has_pytest_suite/suites = [d for d in dirs[:1] if has_pytest_suite/"'
  check "(control, a, b) fails when the first report is accepted as the re-scan, and when a later pass replaces a fail" \
    'opp "$PY" "s/        if os\.path\.abspath\(args\[0\]\) == first\[1\] or /        if False and /" && opp "$PY" "s/\[\(r\[2\], r\[3\]\)\] = \(r\[4\], r\[5\]\)/[(r[2], \x27\x27)] = (r[4], r[5])/"'
  check "(control, e) fails when start adds to an old record, and when only the parent process is stopped on a time-out" \
    'opp "$PY" "s/with open\(ledger, .w./with open(ledger, \x27a\x27/" && opp "$PY" "s/            os\.killpg\(p\.pid, signal\.SIGKILL\)[^\n]*\n/            p.kill()\n/"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
