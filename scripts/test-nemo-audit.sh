#!/usr/bin/env bash
# The deep code audit in /nemo-it, and /fix-it fixing its Critical and High findings without asking.
# Contract these checks pin:
#   - .claude/make-it/security-audit/ is an unmodified, pinned copy of cloudflare/security-audit-skill
#     (commit named, licence kept, every file matches SHA256SUMS, its own tests pass).
#   - /nemo-it: the audit runs in the default (full) mode and alone as `audit`; it follows the vendored
#     SKILL.md in full audit mode; it only reads (nothing run without the sandbox, nothing installed,
#     nothing sent); it is NOT RUN unless both validators pass; only `confirmed` records become AUDIT-
#     findings with a severity; `needs_validation` is listed with no severity; /nemo-it still fixes nothing.
#   - /fix-it: AUDIT Critical and High are fixed without asking, on a fix-it branch only, test first,
#     re-checked by a fresh agent; two failed tries -> reverted and MANUAL; `needs_validation` is never
#     fixed; the branch is never merged by the skill.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

V=.claude/make-it/security-audit
N=.claude/commands/nemo-it.md
X=.claude/commands/fix-it.md
S=.claude/make-it/references/fix-strategies.md
T=.claude/make-it/templates/nemo-it-attestation.md
flat() { tr '\n' ' ' | tr -s ' '; }
step() { awk -v a="<step name=\"$2\">" 'on && /^<\/step>/ {exit} index($0,a) {on=1} on' "$1" | flat; }
AUD="$(step "$N" deep_code_audit)"
FIX="$(awk '/^\*\*Step 7: Deep-audit findings/{on=1} on && /^\*\*Step 8: /{exit} on' "$X" | flat)"
TRI="$(step "$X" triage)"

# 1. the vendored copy is pinned and untouched
check "VENDORED.md names the source commit" 'gq -F "c1c8a8c1471069fb0e188eeaff69b8e8db6564a8" "$V/VENDORED.md"'
check "the MIT licence ships with the copy" 'gq -F "Cloudflare, Inc." "$V/LICENSE"'
check "every vendored file matches SHA256SUMS" '( cd "$V" && shasum -a 256 -c SHA256SUMS >/dev/null )'
check "SHA256SUMS covers every vendored file" \
  '[ "$(ls "$V" | grep -v -x -e VENDORED.md -e SHA256SUMS | wc -l | tr -d " ")" = "$(wc -l < "$V/SHA256SUMS" | tr -d " ")" ]'
if command -v node >/dev/null; then
  check "the vendored validators pass their own tests" '( cd "$V" && node --test >/dev/null 2>&1 )'
else
  echo "skip the vendored validators' tests (no node here)"
fi

# 2. /nemo-it runs it by default, and alone
check "/nemo-it parses the audit mode" 'gq -E "^  /nemo-it audit +--> mode = \"audit\"" "$N"'
check "the audit step was found" '[ -n "$AUD" ]'
check "it runs in the default full mode and in audit mode" 'printf "%s" "$AUD" | gq -F "**Run when mode is: full, audit**"'
check "it follows the vendored SKILL.md in full audit mode" \
  'printf "%s" "$AUD" | gq -F ".claude/make-it/security-audit" && printf "%s" "$AUD" | gq -iE "SKILL\.md[^.]*full audit mode"'
check "it only reads: nothing run without the sandbox, nothing installed, nothing sent" \
  'printf "%s" "$AUD" | gq -iE "no such sandbox[^.]*nothing[^.]*(run|executed)" && printf "%s" "$AUD" | gq -iE "nothing is installed" && printf "%s" "$AUD" | gq -iE "no request goes to"'
check "it is NOT RUN unless both validators pass" \
  'printf "%s" "$AUD" | gq -F "validate-findings.cjs" && printf "%s" "$AUD" | gq -F "validate-coverage-ledger.cjs" && printf "%s" "$AUD" | gq -F "NOT RUN"'
check "only confirmed records become AUDIT- findings" 'printf "%s" "$AUD" | gq -E "\`confirmed\`[^.]*AUDIT-"'
check "needs_validation carries no severity and is not a finding" \
  'printf "%s" "$AUD" | gq -iE "\`needs_validation\`[^.]*no severity" && printf "%s" "$AUD" | gq -iE "never (counted|offered)"'
check "an unfinished audit is never reported as no findings" 'printf "%s" "$AUD" | gq -iE "incomplete[^.]*never NO FINDINGS"'
check "/nemo-it still never changes code" 'gq -F "**This skill NEVER modifies application code.**" "$N"'
check "the attestation template has the audit row and suite" \
  'gq -E "^\| 23 \|.*\| AUDIT +\|" "$T" && gq -E "^## Suite 5: Deep Code Audit" "$T" && gq -iE "^### .*Needs validation" "$T"'

# 3. /fix-it fixes audit Critical and High without asking -- on a branch, test first, re-checked
check "the audit fix step was found" '[ -n "$FIX" ]'
check "triage: AUDIT is its own class, fixed without asking" 'printf "%s" "$TRI" | gq -E "\*\*AUDIT\*\*" && printf "%s" "$TRI" | gq -iE "without asking"'
check "triage: the branch is not a choice when audit findings are in scope" \
  'printf "%s" "$TRI" | gq -iE "fix-it/\[date\][^.]*(not asked|no question|without asking)"'
check "the test comes first and must fail before the fix" 'printf "%s" "$FIX" | gq -iE "test[^.]*fail[^.]*before"'
check "a fresh agent re-checks each fix" 'printf "%s" "$FIX" | gq -iE "fresh agent" && printf "%s" "$FIX" | gq -iE "never the (one|agent) that wrote"'
check "two failed tries: reverted and MANUAL" 'printf "%s" "$FIX" | gq -iE "second try also fails, (revert|undo)[^.]*MANUAL"'
check "needs_validation is never fixed" 'printf "%s" "$FIX" | gq -iE "needs_validation[^.]*never fixed"'
check "the skill never merges the branch" 'printf "%s" "$FIX" | gq -iE "never merge"'
check "a weakened or edited existing test is refused" 'printf "%s" "$FIX" | gq -iE "existing test[^.]*(never|not) (changed|edited|weakened)"'
check "fix-strategies.md has the audit strategy" 'gq -E "^## Strategy 13: Deep-Audit Findings" "$S"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
