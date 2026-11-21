#!/usr/bin/env bash
# E10-S2 and E10-S3 (the owner's call, 2026-11-21): the build's security pass (build-verify Part D) runs its scanners
# from pinned container images on every build, whatever is installed on the computer -- always the image, even when
# the tool is installed, so every machine gives the same result. Every node step of the deep code audit runs from the
# pinned node image, so a computer with no node still gets the audit.
# Contract these checks pin (fix round 1 added the second half of the list):
#   - Phase 0 no longer asks what is installed: no `command -v` for a scanner or for node, no "use what exists".
#   - Every image is pinned by its multi-architecture digest, and every `docker run` uses one of those pins.
#   - The project is mounted read-only; reports and each tool's error output go to a folder outside the project,
#     the same folder each time for the same project, emptied at the start of each scan.
#   - Every code block of Phase 0, Phase 1 and 6b is exactly as pinned below, whole: a changed command fails.
#   - The file list comes from the disk, not from git (a first build has nothing committed).
#   - pip-audit gets only the requirements file, read-only, never the project (owner, decision A); npm audit runs in
#     each folder with a package-lock.json; Trivy runs from / so the project's trivy.yaml is not loaded (decision B).
#   - 1e prints one line per scanner from a fixed list, with each tool's own "ran" test; nothing to scan is its own
#     line, never clean; an empty report folder fails loudly.
#   - One that cannot run keeps today's outcome (skipped, the build not blocked, never clean) and the report says why.
#     What the build does about it is E10-S4, not pinned here.
#   - 6a: a missing node is no longer a reason for NOT RUN; the security-audit files missing still is. 6b: every node
#     step the vendored audit names runs from the node pin.
#   - The governance doc and the desktop guardrails skill say the same.
# A tripwire, not a proof: it reads the words and command shapes, it does not run Docker. The real run is the
# evidence on the pull request and, later, E10-S6. Its controls (section 9) mutate a copy and must fail.
# Usage: test-security-pass-in-docker.sh [ROOT]. With no ROOT it checks this repo and runs the controls; a ROOT is a
# copy (the controls use that).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

B=.claude/make-it/references/build-verify-security.md
GOV=docs/AI-GOVERNANCE-HOMEGROWN.md
DSK=desktop/skills/guardrails/SKILL.md
flat() { tr '\n' ' ' | tr -s ' '; }
# sec FILE START: the lines from the heading matching START to the next "## " heading
sec() { awk -v s="$2" 'on && /^## /{exit} $0 ~ s {on=1} on' "$1"; }
P0="$(sec "$B" '^## Phase 0: ')"
P1="$(sec "$B" '^## Phase 1: ')"
P6="$(sec "$B" '^## Phase 6: ')"
P7="$(sec "$B" '^## Phase 7: ')"
# has TEXT SENTENCE: the flattened text holds the whole sentence
has() { printf "%s\n" "$1" | flat | gq -F -- "$2" || { echo "  missing: $2"; false; }; }
# row TEXT LINE: the text holds exactly this line
row() { printf "%s\n" "$1" | gq -xF -- "$2" || { echo "  no such line: $2"; false; }; }
# none TEXT REGEX: no line matches (case ignored)
none() { local m; m="$(printf "%s\n" "$1" | { grep -niE -- "$2" || true; })"; [ -z "$m" ] || { printf "%s\n" "$m" | cut -c1-200 | sed 's/^/  found: /'; false; }; }
# blk START: the first ```bash block after the line matching START
blk() { awk -v s="$1" '$0 ~ s {on=1} on && /^```bash$/ {c=1; next} c && /^```$/ {exit} c' "$B"; }
# pin START EXPECTED: that block is exactly EXPECTED, every line
pin() { local d; d="$(diff <(printf "%s" "$2") <(blk "$1") || true)"; [ -z "$d" ] || { printf "%s\n" "$d" | head -12 | sed 's/^/  diff: /'; false; }; }

check "Phase 0, 1, 6 and 7 were found" '[ -n "$P0" ] && [ -n "$P1" ] && [ -n "$P6" ] && [ -n "$P7" ]'

# 1. Phase 0 runs the images, never asks what is installed
check "every scanner runs from a pinned image on every build, even when the tool is installed" \
  'has "$P0" "Every scanner runs from a pinned container image on every build, whatever is installed on the computer -- even when the tool is installed, so every machine gives the same result."'
check "no command -v, no 'use what exists', no installed tool used instead (the whole file)" \
  'none "$(cat "$B")" "command -v (semgrep|bandit|trivy|pip-audit|npm|node)" && none "$(cat "$B")" "HAVE_(SEMGREP|BANDIT|TRIVY|PIP_AUDIT|NPM)" && none "$(cat "$B")" "use what exists|If a tool is missing, skip that scan category|not already installed" && none "$(cat "$B")" "(run|use) the installed|installed (one|copy|tool|scanner|binary)[^.]*instead"'

# 2. the pins
check "each digest is said to be the multi-architecture one" \
  'has "$P0" "Each digest is the multi-architecture index, so the same pin runs on arm64 and amd64 computers."'
check "no image is named without its digest (the whole file)" \
  'none "$(grep -E "(semgrep/semgrep|aquasec/trivy|pycqa/bandit|node:[0-9]|python:[0-9])" "$B" | grep -vE "@sha256:[0-9a-f]{64}" || true)" "."'
check "every docker run uses one of the pins, and none is handed the Docker socket" \
  '[ "$(grep -c "docker run" "$B")" -ge 8 ] && none "$(grep "docker run" "$B" | grep -vE "\"[$](SEMGREP|BANDIT|TRIVY|NODE|PYTHON)_IMAGE\"" || true)" "." && none "$(cat "$B")" "docker[.]sock"'

# 3. every code block, whole
IFS= read -r -d '' P0SET <<'PINEOF' || true
PROJECT="$(pwd)"  # the project root
REPORT_DIR="${TMPDIR:-/tmp}"; REPORT_DIR="${REPORT_DIR%/}/make-it-security-$(printf '%s' "$PROJECT" | cksum | cut -d ' ' -f 1)"  # outside the project, the same folder for this project every time
SEMGREP_IMAGE="semgrep/semgrep:1.85.0@sha256:b4c2272e0a2e59ca551ff96d3bbae657bd2b7356e339af557b27a96d9e751544"
BANDIT_IMAGE="ghcr.io/pycqa/bandit/bandit@sha256:b405a808f5d50156aee921a77fb17c044d69d90ecef6499447a037678967c936"  # 1.9.4; it publishes no version tags
TRIVY_IMAGE="aquasec/trivy:0.68.2@sha256:05d0126976bdedcd0782a0336f77832dbea1c81b9cc5e4b3a5ea5d2ec863aca7"
NODE_IMAGE="node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a"
PYTHON_IMAGE="python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b"  # pip-audit has no public image
PINEOF
IFS= read -r -d '' P1START <<'PINEOF' || true
rm -rf "${REPORT_DIR:?}" && mkdir -p "$REPORT_DIR"
(cd "$PROJECT" && find . \( -name node_modules -o -name .venv -o -name venv -o -name .git \) -prune -o -type f -print) | sed 's|^[.]/||' > "$REPORT_DIR/files.txt"
PINEOF
IFS= read -r -d '' B1B <<'PINEOF' || true
docker run --rm -v "$PROJECT":/src:ro -w /src "$SEMGREP_IMAGE" \
  semgrep scan --config p/owasp-top-ten --config p/security-audit \
  --json \
  --exclude="node_modules" --exclude=".venv" --exclude="__pycache__" \
  . > "$REPORT_DIR/semgrep.json" 2> "$REPORT_DIR/semgrep.err" < /dev/null
PINEOF
IFS= read -r -d '' B1C <<'PINEOF' || true
grep -E '[.]py$' "$REPORT_DIR/files.txt" > "$REPORT_DIR/bandit-files.txt" || echo "no Python code found" > "$REPORT_DIR/bandit.none"
[ -f "$REPORT_DIR/bandit.none" ] || docker run --rm -v "$PROJECT":/src:ro -w /src "$BANDIT_IMAGE" \
  -r . -f json \
  --exclude=".venv,venv,node_modules,__pycache__,tests" \
  --quiet > "$REPORT_DIR/bandit.json" 2> "$REPORT_DIR/bandit.err" < /dev/null
PINEOF
IFS= read -r -d '' B1D <<'PINEOF' || true
# npm audit: in each folder with a package-lock.json (the project root may have none)
grep -E '(^|/)package-lock[.]json$' "$REPORT_DIR/files.txt" > "$REPORT_DIR/npm-locks.txt" || echo "no package-lock.json found" > "$REPORT_DIR/npm-audit.none"
while read -r lock; do
  name="npm-audit--$(printf '%s' "$lock" | sed 's/%/%25/g; s|/|%2F|g')"
  docker run --rm -v "$PROJECT":/src:ro -w "/src/$(dirname "$lock")" "$NODE_IMAGE" \
    npm audit --json > "$REPORT_DIR/$name.json" 2> "$REPORT_DIR/$name.err" < /dev/null
done < "$REPORT_DIR/npm-locks.txt"

# pip-audit: on each requirements file. Only that file is mounted, read-only: never the project,
# so a line such as "-e ./something" cannot run the project's code, and the .env is out of reach.
grep -E '(^|/)requirements[^/]*[.]txt$' "$REPORT_DIR/files.txt" > "$REPORT_DIR/pip-reqs.txt" || echo "no requirements file found" > "$REPORT_DIR/pip-audit.none"
while read -r req; do
  name="pip-audit--$(printf '%s' "$req" | sed 's/%/%25/g; s|/|%2F|g')"
  docker run --rm -v "$PROJECT/$req":/req/requirements.txt:ro -w /req "$PYTHON_IMAGE" \
    sh -c 'pip install -q --root-user-action=ignore pip-audit==2.9.0 >&2 && pip-audit --format=json -r requirements.txt' \
    > "$REPORT_DIR/$name.json" 2> "$REPORT_DIR/$name.err" < /dev/null
done < "$REPORT_DIR/pip-reqs.txt"

# trivy filesystem scan, run from / so it never loads the project's own trivy.yaml or
# .trivyignore; its database is kept in a named volume between runs
docker run --rm -v "$PROJECT":/src:ro -w / -v make-it-trivy-cache:/root/.cache/trivy "$TRIVY_IMAGE" \
  fs --format json --quiet \
  --skip-dirs node_modules --skip-dirs .venv \
  /src > "$REPORT_DIR/trivy.json" 2> "$REPORT_DIR/trivy.err" < /dev/null
PINEOF
IFS= read -r -d '' B1E <<'PINEOF' || true
docker run --rm -v "$REPORT_DIR":/r:ro "$NODE_IMAGE" node -e '
const fs = require("fs"); const all = fs.readdirSync("/r");
if (!all.includes("files.txt")) { console.log("NO FILE LIST in this folder: Phase 1 did not start here"); process.exit(1); }
const len = (a) => (Array.isArray(a) ? a.length : -1);
const tests = {
  semgrep: (r) => len(r.paths.scanned) > 0 && r.errors.every((e) => String(e.type).startsWith("PartialParsing")) && `${r.results.length} findings, ${r.paths.scanned.length} files, ${r.errors.length} partly parsed`,
  bandit: (r) => len(r.errors) === 0 && r.metrics._totals.loc > 0 && `${r.results.length} findings, ${r.metrics._totals.loc} lines`,
  "npm-audit": (r) => !("error" in r) && `${r.metadata.vulnerabilities.total} vulnerabilities`,
  "pip-audit": (r) => len(r.dependencies) >= 0 && `${r.dependencies.length} packages, ${r.dependencies.filter((d) => len(d.vulns) > 0).length} vulnerable`,
  trivy: (r) => r.SchemaVersion === 2 && r.ArtifactName === "/src" && `${len(r.Results || [])} files, ${(r.Results || []).reduce((n, x) => n + len(x.Vulnerabilities || []), 0)} vulnerabilities`,
};
let seen = 0;
for (const [t, test] of Object.entries(tests)) {
  if (all.includes(t + ".none")) { seen++; console.log(t + ": nothing to audit (" + fs.readFileSync("/r/" + t + ".none", "utf8").trim() + ")"); continue; }
  const reports = all.filter((f) => f === t + ".json" || (f.startsWith(t + "--") && f.endsWith(".json")));
  const parts = reports.map((f) => { let s = false; try { s = test(JSON.parse(fs.readFileSync("/r/" + f, "utf8"))); } catch (e) {} return s ? [true, f + ": " + s] : [false, f + ": see " + f.slice(0, -5) + ".err"]; });
  seen += reports.length;
  const bad = parts.filter((x) => !x[0]).length;
  if (!reports.length) console.log(t + ": NOT RUN (no report: its step did not run)");
  else console.log(t + ": " + (bad ? "NOT RUN for " + bad + " of " + reports.length : "ran") + " (" + parts.map((x) => x[1]).join("; ") + ")");
}
if (!seen) { console.log("NO REPORTS in this folder: the scan did not run here"); process.exit(1); }' < /dev/null
PINEOF
IFS= read -r -d '' B6B <<'PINEOF' || true
docker run --rm -v "$AUDIT_DIR":/audit:ro -v "<run>":/audit-run:ro "$NODE_IMAGE" node /audit/validate-findings.cjs /audit-run/findings.json
docker run --rm -v "$AUDIT_DIR":/audit:ro -v "<run>":/audit-run:ro "$NODE_IMAGE" node /audit/validate-coverage-ledger.cjs /audit-run/coverage-ledger.json
PINEOF

check "the whole block is exactly as pinned -- the shared setup: the project, the report folder (the same every time, outside the project) and the five pins by digest" 'pin "^## Phase 0: " "$P0SET"'
check "the whole block is exactly as pinned -- each scan starts with an empty report folder and a file list read from the disk, not from git" 'pin "^## Phase 1: " "$P1START"'
check "the whole block is exactly as pinned -- Semgrep: its pin, the project read-only, report and errors kept, no --quiet" 'pin "^### 1b[.]" "$B1B"'
check "the whole block is exactly as pinned -- Bandit: the Python code that is there (not backend/ only), or no Python code found" 'pin "^### 1c[.]" "$B1C"'
check "the whole block is exactly as pinned -- npm audit per package-lock.json, pip-audit with only the requirements file mounted read-only, Trivy from / (no project trivy.yaml), names that cannot collide" 'pin "^### 1d[.]" "$B1D"'
check "the whole block is exactly as pinned -- 1e: a fixed list, one line per scanner, a per-tool ran test, loud on an empty folder" 'pin "^### 1e[.]" "$B1E"'
check "the whole block is exactly as pinned -- 6b: both final checkers from the node pin, the audit and run folders read-only" 'pin "^### 6b[.]" "$B6B"'

# 4. what the blocks must never go back to
check "the project is mounted read-only and the report folder is outside it, the same each time" \
  'has "$P0" "The project is mounted read-only, so a scanner never writes into the project." && has "$P0" "It gives the same values each time for the same project, \`REPORT_DIR\` included:" && none "$P0$P1" "mktemp"'
check "no scanner or checker throws its error output away (Phases 0, 1 and 6)" \
  'none "$P0$P1$P6" "2>/dev/null|2>&1|>/dev/null"'
# a command that starts with the tool's own name, not continuing a "docker run ... \\" line
starts() { printf "%s\n" "$1" | awk '/^[[:space:]]*(semgrep|bandit|trivy|pip-audit|npm audit|npx|node)[[:space:]]/ && prev !~ /[\\]$/ {print} {prev = $0}'; }
check "no scanner or checker runs from the computer (a command starting with the tool's own name)" \
  'none "$(starts "$P1$P6")" "."'
check "the file list is read from the disk, never from git, and report names cannot collide" \
  'none "$P1" "git (-C [^ ]+ )?ls-files" && none "$P1" "tr ./[.]. .__." && has "$P1" "read from the disk (not from git), so a first build with nothing committed is scanned in full" && has "$P1" "Report names encode the file'"'"'s path (\`%\` becomes \`%25\`, \`/\` becomes \`%2F\`), so two files never share a report."'
check "pip-audit sees only its requirements file; a file that names others is NOT RUN with pip's reason" \
  'has "$P1" "Only that file is mounted, read-only: never the project," && has "$P1" "A requirements file that names another file (\`-r\`, \`-c\`) or a local path (\`-e ./x\`) cannot be resolved with only that file mounted: its report is NOT RUN, with pip'"'"'s reason."'
check "Trivy never loads the project's trivy.yaml" 'none "$P1" "trivy[.]yaml[^#]*--config|--config[^|]*trivy" && has "$P1" "run from / so it never loads the project'"'"'s own trivy.yaml"'

# 5. what "ran" means, and what a scanner that cannot run leaves
check "a scanner ran only if its report exists and passes its own test, never on its exit code alone" \
  'has "$P0" "A scanner ran only if its report file exists and parses, never on its exit code alone: Bandit exits 1 when it has findings, and Semgrep with no network exits 2 with empty output." && has "$P0" "A report that parses can still be a failure, so each tool has its own test (1e):" && none "$(cat "$B")" "exits? (with )?(code )?0[^.]*counts? as ran|counts? as ran[^.]*exits? (with )?(code )?0"'
check "one that cannot run is skipped with its reason, the build not blocked, never clean" \
  'has "$P0" "A scanner whose report is missing or fails its test is NOT RUN: it is skipped, the build is not blocked, and the internal report lists it with the reason from its \`.err\` file (for example, the image could not be pulled, or no network) -- never as clean or as no findings."'
check "nothing to scan is its own line, never clean" \
  'has "$P0" "A scanner with nothing to scan (no Python code, no \`package-lock.json\`, no requirements file) gets that line instead, never \"clean\"." && has "$P1" "Every scanner in the fixed list gets exactly one line: ran, NOT RUN with the report to read for the reason, or nothing to audit. A folder with no report at all fails loudly (exit 1): the scan did not run there."'
check "the scanner config gap is said once, as accepted" \
  'has "$P0" "A config file committed in the project (\`.semgrepignore\`, \`.bandit\`) can still narrow what Semgrep or Bandit scans: an accepted gap, not checked."'
check "Semgrep runs without --quiet, and says why" 'has "$P1" "Semgrep runs without \`--quiet\`, so a failed run leaves its reason in \`semgrep.err\`."'
check "the internal report names what ran from which image, and what did not and why" \
  'has "$P7" "Scanners run: [each scanner whose report parses, with its image]" && has "$P7" "Scanners NOT RUN: [each, with the reason from its .err file]" && none "$P7" "Tools (used|skipped)"'

# 6. the audit needs no node on the computer, at any step
check "6a: a missing node is no longer a NOT RUN; the security-audit files still are" \
  'none "$P6" "MISSING: node" && none "$(cat "$B")" "(without|no|missing) node[^.]*NOT RUN" && row "$P6" "[ -f \"\$AUDIT_DIR/SKILL.md\" ] || echo \"MISSING: the security-audit files\"" && has "$P6" "If the security-audit files are missing, the deep code audit is NOT RUN." && has "$P6" "Node is not needed on the computer: every node step of the audit runs from the pinned node image (\`NODE_IMAGE\`, Phase 0; see 6b)."'
check "6b: every node step the audit's own files name runs from the node pin" \
  'has "$P6" "wherever the audit'"'"'s own files say to run \`node <skill-dir>/X.cjs <output-dir>/<file>\` (the coverage-ledger check after seeding, after every parent update and before its Phase 6, and the two final checks below), run it from the pinned node image instead, with the audit folder and the run folder (its output directory) mounted read-only:" && has "$P6" "\`docker run --rm -v \"\$AUDIT_DIR\":/audit:ro -v \"<run>\":/audit-run:ro \"\$NODE_IMAGE\" node /audit/X.cjs /audit-run/<file>\`. Node on the computer is never used for it." && none "$P6" "(^|[\` ])node \"[$]AUDIT_DIR"'

# 7. the governance doc says the same
check "governance doc: Phase 0 runs the images, never 'detect available tools'" \
  'none "$(cat "$GOV")" "Detect available tools|missing tools skip that scan" && row "$(cat "$GOV")" "Phase 0: Scanner Images (silent)" && row "$(cat "$GOV")" "  └─ Every scanner runs from a pinned container image, whatever is installed"'
check "governance doc: no scanner row says 'if installed', and a scanner that cannot run is said to be NOT RUN" \
  'none "$(grep -E "Build-verify Part D Phase 1[bcd]" "$GOV")" "If installed|graceful skip" && [ "$(grep -cE "Build-verify Part D Phase 1[bcd] [|] Every build, from a pinned image" "$GOV")" = 5 ] && has "$(cat "$GOV")" "A scanner in Part D that cannot run on a build (its image cannot be pulled, or there is no network) is recorded as NOT RUN with its reason, never as clean."'
check "governance doc: the roadmap asks for Docker and the pinned images, not installed scanners" \
  'none "$(cat "$GOV")" "Semgrep \+ Bandit installed" && has "$(cat "$GOV")" "Ensure every dev machine runs Docker and can pull the pinned scanner images"'

# 8. the desktop skill (no Docker in its sandbox) defers the scanners
check "desktop guardrails: the sandbox runs Phase 1a only; Phase 1b-1e is DEFERRED, never 'if the tool is present'" \
  'none "$(cat "$DSK")" "only if the tool is present" && has "$(cat "$DSK")" "\`references/build-verify-security.md\` Phase 1a (the code pattern scan) and the Phase 2a AI wiring checks" && has "$(cat "$DSK")" "\`build-verify-security.md\` Phase 1b-1e (the scanners run only from Docker images)"'

# the controls: name<TAB>file<TAB>old<TAB>new (\n is a new line in old and new)
IFS= read -r -d '' CTRLS <<'CTRL_EOF' || true
Phase 0 keyed on command -v semgrep again	B	PROJECT="$(pwd)"  # the project root	HAVE_SEMGREP=$(command -v semgrep 2>/dev/null && echo "true" || echo "false")\nPROJECT="$(pwd)"  # the project root
the image only when the tool is not installed	B	even when the tool is installed, so every machine gives the same result	only when the tool is not installed
pip-audit with no target	B	pip-audit --format=json -r requirements.txt	pip-audit --format=json
npm audit from the project root	B	-w "/src/$(dirname "$lock")"	-w /src
Semgrep error output thrown away	B	2> "$REPORT_DIR/semgrep.err"	2>/dev/null
Semgrep image by tag only	B	semgrep/semgrep:1.85.0@sha256:b4c2272e0a2e59ca551ff96d3bbae657bd2b7356e339af557b27a96d9e751544	semgrep/semgrep:1.85.0
node pin moved to another digest	B	sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a	sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402
a docker run with a literal, unpinned image	B	-w /src "$BANDIT_IMAGE"	-w /src ghcr.io/pycqa/bandit/bandit:latest
the project mounted writable for Semgrep	B	-v "$PROJECT":/src:ro -w /src "$SEMGREP_IMAGE"	-v "$PROJECT":/src -w /src "$SEMGREP_IMAGE"
Semgrep back to --quiet	B	--json \	--json --quiet \
the Trivy database not kept	B	 -v make-it-trivy-cache:/root/.cache/trivy	
ran means exit code 0	B	never on its exit\ncode alone	when it exits 0
an error-only npm report counted as ran	B	!("error" in r) && 	
a NOT RUN scanner recorded as clean	B	-- never as clean or as	-- recorded as clean or as
the report template back to Tools skipped	B	Scanners NOT RUN: [each, with the reason from its .err file]	Tools skipped: [list of tools not installed]
6a: MISSING: node back	B	[ -f "$AUDIT_DIR/SKILL.md" ] || echo "MISSING: the security-audit files"	[ -f "$AUDIT_DIR/SKILL.md" ] || echo "MISSING: the security-audit files"\ncommand -v node || echo "MISSING: node"
6b: a final checker on host node	B	docker run --rm -v "$AUDIT_DIR":/audit:ro -v "<run>":/audit-run:ro "$NODE_IMAGE" node /audit/validate-findings.cjs /audit-run/findings.json	node "$AUDIT_DIR/validate-findings.cjs" <run>/findings.json
6a: missing security-audit files no longer a NOT RUN	B	If the security-audit files are missing, the deep code audit is NOT RUN.	If the security-audit files are missing, the deep code audit still runs.
governance: the Semgrep row back to If installed	GOV	| Build-verify Part D Phase 1b | Every build, from a pinned image |	| Build-verify Part D Phase 1b | If installed; graceful skip if not |
governance: Phase 0 back to detecting tools	GOV	  └─ Every scanner runs from a pinned container image, whatever is installed	  └─ Detect available tools: semgrep, bandit, trivy, pip-audit, npm
review: pip-audit's mount not read-only	B	/req/requirements.txt:ro	/req/requirements.txt
review: pip-audit given the Docker socket	B	-w /req "$PYTHON_IMAGE"	-w /req -v /var/run/docker.sock:/var/run/docker.sock "$PYTHON_IMAGE"
review: 1e counts every report as ran	B	[false, f + ": see " + f.slice(0, -5) + ".err"]	[true, f + ": parses"]
review: run the installed scanner instead	B	so the same pin runs on arm64 and amd64 computers.	so the same pin runs on arm64 and amd64 computers. When a scanner is already installed on the computer, run the installed one instead.
review: a scanner that exits 0 counts as ran (Phase 7)	B	  Scanners NOT RUN: [each, with the reason from its .err file]	  Scanners NOT RUN: [each, with the reason from its .err file]\n  A scanner that exits 0 counts as ran.
review: no node is a NOT RUN again (6a)	B	If the security-audit files are missing, the deep code audit is NOT RUN.	If the security-audit files are missing, the deep code audit is NOT RUN. Without node on the computer it is NOT RUN as well.
review: Trivy given the project's trivy.yaml	B	fs --format json --quiet \	fs --config trivy.yaml --format json --quiet \
A: pip-audit sees the project again	B	-v "$PROJECT/$req":/req/requirements.txt:ro	-v "$PROJECT":/src:ro -v "$PROJECT/$req":/req/requirements.txt:ro
B: Trivy run from the project folder (loads its trivy.yaml)	B	-w / -v make-it-trivy-cache	-w /src -v make-it-trivy-cache
B: Semgrep that scanned nothing counts as ran	B	len(r.paths.scanned) > 0 && 	
B: Bandit that read no code counts as ran	B	 && r.metrics._totals.loc > 0	
B: the accepted config gap no longer said	B	an accepted gap, not checked	handled
1: the file list from git again	B	(cd "$PROJECT" && find . \( -name node_modules -o -name .venv -o -name venv -o -name .git \) -prune -o -type f -print) | sed 's|^[.]/||' > "$REPORT_DIR/files.txt"	git -C "$PROJECT" ls-files > "$REPORT_DIR/files.txt"
1: no lockfile leaves no line	B	 || echo "no package-lock.json found" > "$REPORT_DIR/npm-audit.none"	
1: a scanner with no report gets no line	B	if (!reports.length) console.log(t + ": NOT RUN (no report: its step did not run)");	
7: an empty report folder exits 0	B	if (!seen) { console.log("NO REPORTS in this folder: the scan did not run here"); process.exit(1); }	if (!seen) { console.log("no reports"); }
7: a fresh mktemp folder each time	B	REPORT_DIR="${TMPDIR:-/tmp}"; REPORT_DIR="${REPORT_DIR%/}/make-it-security-$(printf '%s' "$PROJECT" | cksum | cut -d ' ' -f 1)"	REPORT_DIR="$(mktemp -d)"
7: old reports not cleared at the start	B	rm -rf "${REPORT_DIR:?}" && mkdir -p "$REPORT_DIR"	mkdir -p "$REPORT_DIR"
7: 1e without the file-list guard	B	if (!all.includes("files.txt")) { console.log("NO FILE LIST in this folder: Phase 1 did not start here"); process.exit(1); }	
8: report names that can collide	B	sed 's/%/%25/g; s|/|%2F|g'	tr '/.' '__'
2: Bandit hard-coded to backend/	B	-r . -f json	-r backend/ -f json
2: no Python code leaves no line	B	 || echo "no Python code found" > "$REPORT_DIR/bandit.none"	
3: the audit's own node steps left on host node	B	run it from the pinned node image instead	run it with node
5: desktop back to 'if the tool is present'	DSK	Phase 1a (the code pattern scan) and the Phase 2a AI	Phase 1 (code pattern scan always; semgrep, bandit, and dependency audits only if the tool is present) and the Phase 2a AI
5: desktop no longer defers the scanners	DSK	Phase 1b-1e (the	Phase 1a (the
6: governance: NOT RUN sentence turned into 'always runs'	GOV	is recorded as NOT RUN with its reason, never as clean.	always runs.
6: governance roadmap back to installed scanners	GOV	Ensure every dev machine runs Docker and can pull the pinned scanner images	Ensure Semgrep + Bandit installed on all dev machines
CTRL_EOF

# 9. controls (this repo only): each opposite, made in a copy, must fail the checks above
if [ -z "${1:-}" ]; then
  # opp FILE OLD NEW: a copy with the first OLD replaced by NEW (\n is a new line in both) must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - "$B" "$GOV" "$DSK" | tar -xf - -C "$d"
    O="$2" N="$3" perl -0pi -e '($o, $n) = ($ENV{O}, $ENV{N}); s/\\n/\n/g for ($o, $n); s/\Q$o\E/$n/' "$d/$1"
    ! cmp -s "$1" "$d/$1" || { echo "  control did not change $1: $2"; return 1; }
    ! bash "$SELF" "$d" < /dev/null > /dev/null 2>&1 || { echo "  control passed (should fail): $2 -> $3"; return 1; }
  }
  check "(control) an unchanged copy passes" \
    'd="$TMPD/same"; mkdir -p "$d"; tar -cf - "$B" "$GOV" "$DSK" | tar -xf - -C "$d"; bash "$SELF" "$d" < /dev/null > /dev/null 2>&1'
  n=0; caught=0; missed=""
  while IFS='	' read -r name f old new; do
    [ -n "$name" ] || continue
    n=$((n+1))
    if opp "${!f}" "$old" "$new"; then caught=$((caught+1)); else missed="$missed
  missed: $name"; fi
  done <<< "$CTRLS"
  check "(control) every one of the $n opposites fails this script ($caught caught)" '[ "$caught" = "$n" ] || { printf "%s\n" "$missed"; false; }'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
