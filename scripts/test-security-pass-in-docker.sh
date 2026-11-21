#!/usr/bin/env bash
# E10-S2 and E10-S3: the build's security pass (build-verify Part D) runs its scanners and the audit's node checks
# from pinned images, through ONE tested script (owner, 2026-11-21): .claude/make-it/scripts/security-pass.py.
# Its behaviour is tested in scripts/test-security-pass.py (fixtures, no Docker). This test pins the Markdown:
#   - Part D calls the script for the scanners and for every audit node check, and holds no scanner, node or
#     docker command of its own, whatever the line starts with.
#   - No sentence lets NOT RUN or "nothing to audit" read as clean, no findings or passed; no "node on the
#     computer"; no report with errors counted as ran; Phase 4's re-scan is the script again.
#   - Phase 0 no longer asks what is installed; 6a: a missing node is no longer a NOT RUN.
#   - The accepted gap (a committed .semgrepignore or .bandit) is said once; the governance doc and the desktop
#     guardrails skill say the same as round 1.
# A tripwire, not a proof: it reads words. Its controls (section 6) mutate a copy and must fail.
# Usage: test-security-pass-in-docker.sh [ROOT]. With no ROOT it checks this repo and runs the controls.
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
RUN='python3 -I "$HOME/.claude/make-it/scripts/security-pass.py"'
flat() { tr '\n' ' ' | tr -s ' '; }
sec() { awk -v s="$2" 'on && /^## /{exit} $0 ~ s {on=1} on' "$1"; }
P0="$(sec "$B" '^## Phase 0: ')"; P1="$(sec "$B" '^## Phase 1: ')"; P4="$(sec "$B" '^## Phase 4: ')"
P6="$(sec "$B" '^## Phase 6: ')"; P7="$(sec "$B" '^## Phase 7: ')"
has() { printf "%s\n" "$1" | flat | gq -F -- "$2" || { echo "  missing: $2"; false; }; }
row() { printf "%s\n" "$1" | gq -xF -- "$2" || { echo "  no such line: $2"; false; }; }
none() { local m; m="$(printf "%s\n" "$1" | { grep -niE -- "$2" || true; })"; [ -z "$m" ] || { printf "%s\n" "$m" | cut -c1-200 | sed 's/^/  found: /'; false; }; }
# code: every line of a ```bash block (the commands); prose: every line outside fenced blocks
code() { awk '/^[[:space:]]*```bash/{c=1; next} /^[[:space:]]*```/{c=0; next} c' "$1"; }
prose() { awk '/^[[:space:]]*```/{c=!c; next} !c' "$1"; }
# spans: every `inline code` span in the prose; sentences: the prose flattened, one sentence per line
spans() { prose "$1" | flat | perl -ne 'print "$1\n" while /`([^`]+)`/g'; }
sentences() { prose "$1" | flat | perl -pe 's/([.!?]["\x27)]?) (?=\S)/$1\n/g'; }
# a sentence that runs node or a scanner "on the computer" (a sentence saying "never" or "not needed" is exempt)
ONCOMP='\b(use|using|run|with)\b[^.]{0,20}\b(node|semgrep|bandit|trivy|pip-audit|npm)\b[^.]{0,40}\bon the computer|installed one instead'
TOOLS='(^|[^a-z_./-])(semgrep|bandit|trivy|pip-audit|pip install|npm (audit|ci|install)|npx|node|docker run)([^a-z_.-]|$)'

check "the sections were found" '[ -n "$P0" ] && [ -n "$P1" ] && [ -n "$P4" ] && [ -n "$P6" ] && [ -n "$P7" ]'

# 1. Part D calls the script, and nothing else runs a scanner or node
check "1b runs the script, from the project root" 'row "$P1" "$RUN scan ."'
check "6b's two final checks run through the script" \
  'row "$P6" "$RUN audit-check findings <run>/findings.json" && row "$P6" "$RUN audit-check coverage-ledger <run>/coverage-ledger.json"'
check "6b: every node check the audit's own files name runs through the script, never node on the computer" \
  'has "$P6" "wherever the audit'"'"'s own files say to run one of its \`.cjs\` checkers with node (the coverage-ledger check after seeding, after every parent update and before its Phase 6, and the two final checks below), run \`$RUN audit-check <kind> <output-dir>/<file>\` instead, with \`<kind>\` \`findings\` or \`coverage-ledger\`." && has "$P6" "Node on the computer is never used for it."'
check "no code line or inline command in Part D runs a scanner, node or docker except the script, whatever it starts with" \
  'none "$( { code "$B"; spans "$B"; } | grep -vF "security-pass.py" || true)" "$TOOLS"'

# 2. what the states mean, and what they may never be read as
check "Phase 0: every scanner from a pinned image, even when installed; one script; python3 already used" \
  'has "$P0" "Every scanner runs from a pinned container image on every build, whatever is installed on the computer -- even when the tool is installed, so every machine gives the same result." && has "$P0" "One script shipped with make-it does all of it, \`security-pass.py\` (Phase 1b)."'
check "ran, NOT RUN and nothing to audit are each defined, and neither of the last two is ever clean" \
  'has "$P1" "**NOT RUN:** with the reason the tool gave" && has "$P1" "It is skipped, the build is not blocked, and the internal report lists it with that reason -- never as clean or as no findings." && has "$P1" "**nothing to audit:** with what it looked for (no Python code, no \`package-lock.json\`, no requirements file) -- never \"clean\"."'
check "no sentence lets NOT RUN or nothing to audit read as clean, no findings or passed (unless it says never)" \
  'none "$(sentences "$B" | grep -iE "NOT RUN|nothing to audit" | grep -iE "clean|no findings|passed" | grep -viE "\bnever\b" || true)" "."'
check "no report that lists errors is counted as ran; no exit code means ran" \
  'none "$(sentences "$B")" "still count(ed|s) as ran|errors[^.]*count(ed|s) as ran|exits? (with )?(code )?0[^.]*count(ed|s) as ran"'
check "no node, and no scanner, 'on the computer' as a way to run them" \
  'none "$(sentences "$B" | grep -iE "$ONCOMP" | grep -viE "\bnever\b|not needed" || true)" "."'
check "Phase 4 re-scans with the script again" \
  'has "$P4" "After fixes are applied and containers rebuilt, re-run the scans from Phase 1 (the same script, from its pinned images) and Phase 2 to verify fixes were effective." && none "$P4" "on the computer|installed"'
check "the accepted gap is said once" \
  'has "$P1" "A config file committed in the project (\`.semgrepignore\`, \`.bandit\`) can still narrow what Semgrep or Bandit scans: an accepted gap, not checked."'
check "Phase 0 never asks what is installed; 6a: a missing node is no longer a NOT RUN" \
  'none "$(cat "$B")" "command -v|use what exists|not already installed|MISSING: node|(without|no|missing) node[^.]*NOT RUN" && has "$P6" "If the security-audit files are missing, the deep code audit is NOT RUN." && has "$P6" "Node is not needed on the computer: every node step of the audit runs from the pinned node image through \`security-pass.py audit-check\` (6b)."'
check "the internal report: what ran, what did not and why, what had nothing to audit" \
  'has "$P7" "Scanners run: [each line that says ran, with its image]" && has "$P7" "Scanners NOT RUN: [each, with its reason]" && has "$P7" "Nothing to audit: [each, with what was looked for]" && none "$P7" "Tools (used|skipped)"'

# 3. the governance doc and the desktop skill
check "governance doc: images, NOT RUN said, Docker on the roadmap" \
  'none "$(cat "$GOV")" "Detect available tools|missing tools skip that scan|Semgrep \+ Bandit installed" && row "$(cat "$GOV")" "  └─ Every scanner runs from a pinned container image, whatever is installed" && [ "$(grep -cE "Build-verify Part D Phase 1[bcd] [|] Every build, from a pinned image" "$GOV")" = 5 ] && has "$(cat "$GOV")" "A scanner in Part D that cannot run on a build (its image cannot be pulled, or there is no network) is recorded as NOT RUN with its reason, never as clean." && has "$(cat "$GOV")" "Ensure every dev machine runs Docker and can pull the pinned scanner images"'
check "desktop guardrails: the sandbox runs Phase 1a; Phase 1b is DEFERRED" \
  'none "$(cat "$DSK")" "only if the tool is present" && has "$(cat "$DSK")" "\`references/build-verify-security.md\` Phase 1a (the code pattern scan) and the Phase 2a AI wiring checks" && has "$(cat "$DSK")" "\`build-verify-security.md\` Phase 1b (the scanners run only from Docker images)"'

# the controls: name<TAB>file<TAB>old<TAB>new (\n is a new line in old and new)
IFS= read -r -d '' CTRLS <<'CTRL_EOF' || true
review: a new block running semgrep after cd	B	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" scan .\n```	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" scan .\n```\n\n```bash\ncd "$PROJECT" && semgrep scan --config auto .\n```
review: a block installing and running pip-audit	B	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" scan .\n```	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" scan .\n```\n\n```bash\npip install pip-audit && pip-audit --format=json\n```
review: a NOT RUN one recorded as no findings	B	**nothing to audit:**	A NOT RUN one is recorded as no findings.\n- **nothing to audit:**
review: nothing to audit recorded as clean	B	**nothing to audit:**	A scanner with nothing to audit is recorded as clean.\n- **nothing to audit:**
review: use node on the computer	B	Node on the computer is never used for it.	Node on the computer is never used for it. If Docker cannot start, use node on the computer for these checks.
review: a report that lists errors still counted as ran	B	**nothing to audit:**	A Bandit or Semgrep report that lists errors is still counted as ran.\n- **nothing to audit:**
review: Phase 4 re-scan on the computer	B	re-run the scans from Phase 1 (the same script,	re-run the scans from Phase 1 with semgrep and bandit on the computer (the same script,
review: NOT RUN treated as passed	B	**nothing to audit:**	A scanner that is NOT RUN is treated as passed for the self-healing loop.\n- **nothing to audit:**
the script call removed from 1b	B	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" scan .	echo scan
a final checker back on host node	B	python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" audit-check findings <run>/findings.json	node "$AUDIT_DIR/validate-findings.cjs" <run>/findings.json
an inline docker command in prose	B	Node on the computer is never used for it.	Node on the computer is never used for it. Or run `docker run --rm node:22 node x.cjs`.
the audit's own node steps left to node	B	`python3 -I "$HOME/.claude/make-it/scripts/security-pass.py" audit-check <kind> <output-dir>/<file>`	them as written
command -v back in Phase 0	B	Every scanner runs from a pinned container image on every build	Check `command -v semgrep` first. Every scanner runs from a pinned container image on every build
the image only when not installed	B	even when the tool is installed, so every machine gives the same result	only when the tool is not installed
6a: MISSING: node back	B	[ -f "$AUDIT_DIR/SKILL.md" ] || echo "MISSING: the security-audit files"	[ -f "$AUDIT_DIR/SKILL.md" ] || echo "MISSING: the security-audit files"\ncommand -v node || echo "MISSING: node"
6a: missing audit files still run	B	If the security-audit files are missing, the deep code audit is NOT RUN.	If the security-audit files are missing, the deep code audit still runs.
6a: no node a NOT RUN again	B	If the security-audit files are missing, the deep code audit is NOT RUN.	If the security-audit files are missing, the deep code audit is NOT RUN. Without node on the computer it is NOT RUN as well.
the NOT RUN never-clean sentence weakened	B	-- never as clean or as no findings.	-- recorded as clean.
the accepted gap no longer said	B	an accepted gap, not checked	handled
the report template back to Tools skipped	B	Scanners NOT RUN: [each, with its reason]	Tools skipped: [list of tools not installed]
governance: the Semgrep row back to If installed	GOV	| Build-verify Part D Phase 1b | Every build, from a pinned image |	| Build-verify Part D Phase 1b | If installed; graceful skip if not |
governance: NOT RUN sentence turned into always runs	GOV	is recorded as NOT RUN with its reason, never as clean.	always runs.
governance: roadmap back to installed scanners	GOV	Ensure every dev machine runs Docker and can pull the pinned scanner images	Ensure Semgrep + Bandit installed on all dev machines
desktop: back to if the tool is present	DSK	Phase 1a (the code pattern scan) and the Phase 2a AI	Phase 1 (code pattern scan always; semgrep and bandit only if the tool is present) and the Phase 2a AI
desktop: the scanners no longer deferred	DSK	Phase 1b (the	Phase 1a (the
CTRL_EOF

# 6. controls (this repo only): each opposite, made in a copy, must fail the checks above
if [ -z "${1:-}" ]; then
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
