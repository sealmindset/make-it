#!/usr/bin/env bash
# The deep code audit and its fixes run inside every build -- nobody has to come back with /nemo-it and
# /fix-it to find and fix logic flaws.
# Contract these checks pin:
#   - build-verify-security.md Phase 6 is the one spec: it follows the vendored SKILL.md in full audit mode,
#     profile quick, the whole project the first time and only what changed after that; it is silent and only
#     reads; not run is recorded with its reason and never read as clean.
#   - Every confirmed Critical and High is fixed without asking, in place, by Strategy 13 (failing test first,
#     fresh agent's re-check, one commit per finding, two failed tries -> reverted). needs_validation, left-out
#     items and the go-live record are never fixed. A serious finding left unfixed is said to the user.
#   - build-standards.md V17 carries it, so /make-it, /retrofit-it and /resume-it's catch-up all see it.
#   - /make-it and /retrofit-it run the security spec as a named step before handoff; /resume-it runs the audit
#     at the start of a session and again before the /ship-it handoff, when the code changed.
#   - Strategy 13 says where each caller fixes: /fix-it on its branch, a build in place.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

B=.claude/make-it/references/build-verify-security.md
BS=.claude/make-it/references/build-standards.md
S=.claude/make-it/references/fix-strategies.md
M=.claude/commands/make-it.md
RF=.claude/commands/retrofit-it.md
RS=.claude/commands/resume-it.md
flat() { tr '\n' ' ' | tr -s ' '; }
P6="$(awk '/^## Phase 6: Deep Code Audit and Fix/{on=1;print;next} on && /^## /{exit} on' "$B" | flat)"
V17="$({ grep -E '^\*\*V17\*\* ' "$BS" || true; } | flat)"
S13="$(awk '/^## Strategy 13: /{on=1;print;next} on && /^## /{exit} on' "$S" | flat)"
MK="$(awk '/^\*\*Security hardening \(silent, automatic/{on=1} on && /^\*\*PART D/{exit} on' "$M" | flat)"
RK="$(awk '/^\*\*Security hardening \(silent, automatic/{on=1} on && /^\*\*PART D/{exit} on' "$RF" | flat)"
R6="$(awk '/^\*\*6c\. Deep code audit/{on=1} on && /^\*\*7\. /{exit} on' "$RS" | flat)"
RREM="$(awk '/<step name="security-scanner-remediation">/{on=1} on && /^<\/step>/{exit} on' "$RS" | flat)"
RSH="$(awk '/<step name="ship-handoff">/{on=1} on && /^<\/step>/{exit} on' "$RS" | flat)"

# 1. the one spec
check "Phase 6 was found in build-verify-security.md" '[ -n "$P6" ]'
check "it follows the vendored SKILL.md in full audit mode" \
  'printf "%s" "$P6" | gq -F ".claude/make-it/security-audit" && printf "%s" "$P6" | gq -iE "SKILL\.md[^.]*full audit mode"'
check "profile is quick, and said to be partial coverage" 'printf "%s" "$P6" | gq -iE "\`quick\`[^.]*partial"'
check "whole project the first time, only what changed after" \
  'printf "%s" "$P6" | gq -iE "first[^.]*whole project" && printf "%s" "$P6" | gq -iE "only[^.]*changed since"'
check "it is silent: the user is asked nothing" 'printf "%s" "$P6" | gq -iE "asked nothing"'
check "it only reads: nothing run without the sandbox, nothing installed, nothing sent" \
  'printf "%s" "$P6" | gq -iE "no such sandbox[^.]*nothing[^.]*(run|executed)" && printf "%s" "$P6" | gq -iE "nothing is installed" && printf "%s" "$P6" | gq -iE "no request goes to"'
check "not run is recorded with its reason, never as clean" \
  'printf "%s" "$P6" | gq -F "NOT RUN" && printf "%s" "$P6" | gq -iE "never[^.]*(as clean|no findings)"'
check "it ran only if both checkers pass" \
  'printf "%s" "$P6" | gq -F "validate-findings.cjs" && printf "%s" "$P6" | gq -F "validate-coverage-ledger.cjs"'

# 2. the fixes
check "every confirmed Critical and High is fixed without asking" \
  'printf "%s" "$P6" | gq -iE "every confirmed critical and high[^.]*without asking"'
check "by Strategy 13, in place, one commit per finding" \
  'printf "%s" "$P6" | gq -F "Strategy 13" && printf "%s" "$P6" | gq -iE "in place" && printf "%s" "$P6" | gq -iE "(one|its own) commit"'
check "the live tests run again after the fixes" 'printf "%s" "$P6" | gq -iE "re-run[^.]*live (tests|verification)"'
check "needs_validation is never fixed" 'printf "%s" "$P6" | gq -iE "needs_validation[^.]*never fixed"'
check "left-out items and the go-live record are never fixed" \
  'printf "%s" "$P6" | gq -iE "left-out item.{0,60}never fixed" && printf "%s" "$P6" | gq -iE "go-live record.{0,40}never fixed"'
check "a serious finding left unfixed is said to the user in one plain line" \
  'printf "%s" "$P6" | gq -iE "could not fix[^\"]*to-do list"'
check "Phase 3 still forbids logic changes, with this one exception named" \
  'gq -iE "Never change application logic[^.]*except[^.]*Phase 6" "$B"'
check "the old 'come back with /nemo-it + /fix-it' fallback for a remaining Critical is gone" \
  '! gq -iE "user can run /nemo-it \+ /fix-it standalone for a deeper pass" "$B"'

# 3. the standards check
check "V17 exists, Tier 0, FIX" 'printf "%s" "$V17" | gq -E "^\*\*V17\*\* \[Tier 0\] \[FIX\]"'
check "V17 points at the spec and names the three proofs" \
  'printf "%s" "$V17" | gq -F "build-verify-security.md" && printf "%s" "$V17" | gq -iE "never[^.;]*clean" && printf "%s" "$V17" | gq -iE "failed first" && printf "%s" "$V17" | gq -iE "fresh agent"'

# 4. every build runs it
for pair in "make-it:$MK" "retrofit-it:$RK"; do
  n="${pair%%:*}"; t="${pair#*:}"
  check "/$n: the security step was found, before Part D" '[ -n "$t" ]'
  check "/$n: it runs build-verify-security.md start to finish, V15 and V17" \
    'printf "%s" "$t" | gq -F "build-verify-security.md" && printf "%s" "$t" | gq -F "V15" && printf "%s" "$t" | gq -F "V17"'
  check "/$n: Phase 6 is not skipped to save time" 'printf "%s" "$t" | gq -iE "(do not|never) skip Phase 6"'
done
check "/resume-it: step 6c was found" '[ -n "$R6" ]'
check "/resume-it: 6c runs Phase 6 when the code changed, before the user's work" \
  'printf "%s" "$R6" | gq -F "build-verify-security.md" && printf "%s" "$R6" | gq -iE "changed since" && printf "%s" "$R6" | gq -iE "before[^.]*(user|work)"'
check "/resume-it: the remediation step fixes audit findings by Strategy 13" \
  'printf "%s" "$RREM" | gq -iE "deep-audit findings" && printf "%s" "$RREM" | gq -F "Strategy 13"'
check "/resume-it: left-out and go-live rules cover audit findings too" \
  'printf "%s" "$RREM" | gq -iE "deep-audit finding in a left-out item.{0,80}same rules as a scanner finding"'
check "/resume-it: the audit runs again before the /ship-it handoff" \
  'printf "%s" "$RSH" | gq -iE "deep code audit" && printf "%s" "$RSH" | gq -F "6c"'
check "/resume-it: the user never hears 'vulnerability' for it" 'printf "%s" "$R6" | gq -iE "NEVER say"'

# 5. Strategy 13 says where each caller fixes
check "Strategy 13: /fix-it on its branch, a build in place" \
  'printf "%s" "$S13" | gq -iE "/fix-it commits only on its .fix-it/\[date\]. branch" && printf "%s" "$S13" | gq -iE "a build .{0,60}fixes in place"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
