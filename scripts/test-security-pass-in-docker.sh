#!/usr/bin/env bash
# E10-S2 and E10-S3 (the owner's call, 2026-11-21): the build's security pass (build-verify Part D) runs its scanners
# from pinned container images on every build, whatever is installed on the computer -- always the image, even when
# the tool is installed, so every machine gives the same result. The deep code audit's two checkers run from the
# pinned node image, so a computer with no node still gets the audit.
# Contract these checks pin:
#   - Phase 0 no longer asks what is installed: no `command -v` for a scanner or for node, no "use what exists".
#   - Every image is pinned by its multi-architecture digest, and every `docker run` uses one of those pins.
#   - The project is mounted read-only; reports and each tool's error output go to a folder outside the project.
#   - pip-audit is pointed at each tracked requirements file (bare `pip-audit --format=json` audits the computer's
#     own Python); npm audit runs in each folder with a tracked package-lock.json (the root has none: ENOLOCK);
#     no scanner line throws its error output away (`2>/dev/null`).
#   - A scanner ran only if its report file exists and parses, never on its exit code alone.
#   - One that cannot run keeps today's outcome (skipped, the build not blocked, never clean) and the report says why.
#     What the build does about it is E10-S4, not pinned here.
#   - 6a: a missing node is no longer a reason for NOT RUN; the security-audit files missing still is.
#   - The governance doc's Part D pipeline and tool table say the same.
# A tripwire, not a proof: it reads the words and command shapes, it does not run Docker. The real run is the
# evidence on the pull request and, later, E10-S6.
# Usage: test-security-pass-in-docker.sh [ROOT]. With no ROOT it checks this repo; a ROOT is a copy (for mutants).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

B=.claude/make-it/references/build-verify-security.md
GOV=docs/AI-GOVERNANCE-HOMEGROWN.md
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
# none TEXT REGEX: no line matches
none() { local m; m="$(printf "%s\n" "$1" | { grep -nE -- "$2" || true; })"; [ -z "$m" ] || { printf "%s\n" "$m" | sed 's/^/  found: /'; false; }; }

# 1. Phase 0 runs the images, never asks what is installed
check "Phase 0 and Phase 1 were found" '[ -n "$P0" ] && [ -n "$P1" ] && [ -n "$P6" ] && [ -n "$P7" ]'
check "every scanner runs from a pinned image on every build, even when the tool is installed" \
  'has "$P0" "Every scanner runs from a pinned container image on every build, whatever is installed on the computer -- even when the tool is installed, so every machine gives the same result."'
check "Phase 0 no longer keys on command -v or 'use what exists' (the whole file)" \
  'none "$(cat "$B")" "command -v (semgrep|bandit|trivy|pip-audit|npm|node)" && none "$(cat "$B")" "HAVE_(SEMGREP|BANDIT|TRIVY|PIP_AUDIT|NPM)" && none "$(cat "$B")" "use what exists" && none "$(cat "$B")" "If a tool is missing, skip that scan category"'
check "the intro no longer says it skips tools not already installed" \
  'none "$(cat "$B")" "not already installed"'

# 2. every image is pinned by its multi-arch digest; every docker run uses a pin
check "the five pins, each by digest" \
  'row "$P0" "SEMGREP_IMAGE=\"semgrep/semgrep:1.85.0@sha256:b4c2272e0a2e59ca551ff96d3bbae657bd2b7356e339af557b27a96d9e751544\"" && row "$P0" "BANDIT_IMAGE=\"ghcr.io/pycqa/bandit/bandit@sha256:b405a808f5d50156aee921a77fb17c044d69d90ecef6499447a037678967c936\"  # 1.9.4; it publishes no version tags" && row "$P0" "TRIVY_IMAGE=\"aquasec/trivy:0.68.2@sha256:05d0126976bdedcd0782a0336f77832dbea1c81b9cc5e4b3a5ea5d2ec863aca7\"" && row "$P0" "NODE_IMAGE=\"node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a\"" && row "$P0" "PYTHON_IMAGE=\"python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b\"  # pip-audit has no public image"'
check "each digest is said to be the multi-architecture one" \
  'has "$P0" "Each digest is the multi-architecture index, so the same pin runs on arm64 and amd64 computers."'
check "no image is named without its digest (the whole file)" \
  'none "$(grep -E "(semgrep/semgrep|aquasec/trivy|pycqa/bandit|node:[0-9]|python:[0-9])" "$B" | grep -vE "@sha256:[0-9a-f]{64}" || true)" "."'
check "every docker run uses one of the pins" \
  '[ "$(grep -c "docker run" "$B")" -ge 7 ] && none "$(grep "docker run" "$B" | grep -vE "\"[$](SEMGREP|BANDIT|TRIVY|NODE|PYTHON)_IMAGE\"" || true)" "."'

# 3. read-only project, reports outside it, nothing thrown away
check "the project is mounted read-only and reports go to a folder outside it" \
  'has "$P0" "The project is mounted read-only, so a scanner never writes into the project." && row "$P0" "REPORT_DIR=\"\$(mktemp -d)\"  # outside the project; keep the printed path"'
check "no scanner or checker throws its error output away (Phases 0, 1 and 6)" \
  'none "$P0$P1$P6" "2>/dev/null|2>&1|>/dev/null"'
check "each scanner keeps its error output beside its report" \
  '[ "$(printf "%s\n" "$P1" | grep -cF "2> \"\$REPORT_DIR/")" -ge 5 ]'
# a command that starts with the tool's own name, not continuing a "docker run ... \\" line
starts() { printf "%s\n" "$1" | awk '/^[[:space:]]*(semgrep|bandit|trivy|pip-audit|npm audit|npx|node)[[:space:]]/ && prev !~ /[\\]$/ {print} {prev = $0}'; }
check "no scanner or checker runs from the computer (a command starting with the tool's own name)" \
  'none "$(starts "$P1$P6")" "."'

# 4. the exact command shapes
check "Semgrep runs from its pin, project read-only, report and errors kept" \
  'row "$P1" "docker run --rm -v \"\$PROJECT\":/src:ro -w /src \"\$SEMGREP_IMAGE\" \\" && row "$P1" "  . > \"\$REPORT_DIR/semgrep.json\" 2> \"\$REPORT_DIR/semgrep.err\" < /dev/null"'
check "Semgrep runs without --quiet, so a failed run leaves its reason (with --quiet and no network its error output is empty)" \
  'row "$P1" "  --json \\" && none "$P1" "^  --json --quiet"'
check "Bandit runs from its pin" \
  'row "$P1" "docker run --rm -v \"\$PROJECT\":/src:ro -w /src \"\$BANDIT_IMAGE\" \\" && row "$P1" "  --quiet > \"\$REPORT_DIR/bandit.json\" 2> \"\$REPORT_DIR/bandit.err\" < /dev/null"'
check "npm audit runs in each folder with a tracked package-lock.json, never from the root alone" \
  'row "$P1" "git -C \"\$PROJECT\" ls-files \"*package-lock.json\" | while read -r lock; do" && row "$P1" "  docker run --rm -v \"\$PROJECT\":/src:ro -w \"/src/\$dir\" \"\$NODE_IMAGE\" \\"'
check "pip-audit is pointed at each tracked requirements file" \
  'row "$P1" "git -C \"\$PROJECT\" ls-files \"*requirements*.txt\" | while read -r req; do" && has "$P1" "pip-audit --format=json -r \"\$1\"" && none "$(cat "$B")" "pip-audit --format[= ]json[^-]*$"'
check "pip-audit is installed at a pinned version inside the image, never on the computer" \
  'has "$P1" "pip install -q --root-user-action=ignore pip-audit==2.9.0"'
check "Trivy keeps its database in a named volume between runs" \
  'row "$P1" "docker run --rm -v \"\$PROJECT\":/src:ro -w /src -v make-it-trivy-cache:/root/.cache/trivy \"\$TRIVY_IMAGE\" \\"'

# 5. what "ran" means, and what a scanner that cannot run leaves
check "a scanner ran only if its report file exists and parses, never on its exit code alone" \
  'has "$P0" "A scanner ran only if its report file exists and parses, never on its exit code alone: Bandit exits 1 when it has findings, and Semgrep with no network exits 2 with empty output." && has "$P1" "JSON.parse" && has "$P0" "A report that is only an error is NOT RUN too: npm audit with no network writes its failure as JSON with an \`error\` key." && has "$P1" ".error) throw 0"'
check "one that cannot run is skipped with its reason, the build not blocked, never clean" \
  'has "$P0" "A scanner whose report is missing or does not parse is NOT RUN: it is skipped, the build is not blocked, and the internal report lists it with the reason from its \`.err\` file (for example, the image could not be pulled, or no network) -- never as clean or as no findings."'
check "the internal report names what ran from which image, and what did not and why" \
  'has "$P7" "Scanners run: [each scanner whose report parses, with its image]" && has "$P7" "Scanners NOT RUN: [each, with the reason from its .err file]" && none "$P7" "Tools (used|skipped)"'

# 6. the audit needs no node on the computer
check "6a: a missing node is no longer a NOT RUN; the security-audit files still are" \
  'none "$P6" "MISSING: node" && row "$P6" "[ -f \"\$AUDIT_DIR/SKILL.md\" ] || echo \"MISSING: the security-audit files\"" && has "$P6" "If the security-audit files are missing, the deep code audit is NOT RUN." && has "$P6" "Node is not needed on the computer: the audit'"'"'s two checkers run from the pinned node image (\`NODE_IMAGE\`, Phase 0)."'
check "6b: both checkers run from the node image, the audit and run folders read-only" \
  'row "$P6" "docker run --rm -v \"\$AUDIT_DIR\":/audit:ro -v \"<run>\":/audit-run:ro \"\$NODE_IMAGE\" node /audit/validate-findings.cjs /audit-run/findings.json" && row "$P6" "docker run --rm -v \"\$AUDIT_DIR\":/audit:ro -v \"<run>\":/audit-run:ro \"\$NODE_IMAGE\" node /audit/validate-coverage-ledger.cjs /audit-run/coverage-ledger.json" && none "$P6" "(^|[\` ])node \"[$]AUDIT_DIR"'

# 7. the governance doc says the same
check "governance doc: Phase 0 runs the images, never 'detect available tools'" \
  'none "$(cat "$GOV")" "Detect available tools|missing tools skip that scan" && row "$(cat "$GOV")" "Phase 0: Scanner Images (silent)" && row "$(cat "$GOV")" "  └─ Every scanner runs from a pinned container image, whatever is installed"'
check "governance doc: no scanner row says 'if installed'" \
  'none "$(grep -E "Build-verify Part D Phase 1[bcd]" "$GOV")" "If installed|graceful skip" && [ "$(grep -cE "Build-verify Part D Phase 1[bcd] [|] Every build, from a pinned image" "$GOV")" = 5 ]'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
