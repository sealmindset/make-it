#!/usr/bin/env bash
# test-activity-log-user.sh -- contract test for build-standards L09: the activity log names the signed-in user.
#
# The fastapi-nextjs scaffold's RequestLoggingMiddleware filled user_sub and user_email from request.state.user, and
# nothing in the scaffold ever set it, so every event's user was None and the Activity Logs page showed "-" in its User
# column. get_current_user now puts the verified UserInfo there.
#
# What this pins:
#   - get_current_user sets request.state.user = user once, after the token is decoded and before it returns; nothing
#     in the backend puts a token or a cookie on request.state;
#   - the names the middleware reads (sub, email) are UserInfo fields;
#   - the scaffold test signs in through the real path (no override of get_current_user) and covers a signed-in, a
#     permission-checked and a refused request, and no user for a missing, forged or expired token;
#   - L09 exists once, right after L08, [Tier 1, 5] [FIX], not [SECURITY FIX], and says how an existing app is fixed
#     (the scaffold's copy, or the one line plus a watermark note) and that /resume-it's catch-up offers it;
#   - every activity-log range reads L01-L09, and the governance table counts 9;
#   - the build instructions no longer say the user is on the request only "if populated by auth middleware".
# Then planted defects, each in a throwaway copy (the real files are never edited): each must fail.
# Last, when python3 has pytest and the scaffold's packages, the scaffold's test file is run on the real tree (it must
# pass) and on a copy with the fix taken out (it must fail). REQUIRE_SCAFFOLD_PYTEST=1 turns "not available" from a
# note into a failure; CI sets it.
# A wording test is a tripwire, not a proof; the scaffold test run is the proof that the middleware sees the user.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# whole-line pin: FILE holds exactly N lines equal to TEXT
lines() { [ "$(grep -cxF -- "$2" "$1")" = "$3" ]; }
# the whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise)
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

SB=.claude/make-it/scaffolds/fastapi-nextjs/backend
REL_AU=$SB/app/middleware/auth.py
REL_LG=$SB/app/middleware/logging.py
REL_UI=$SB/app/schemas/auth.py
REL_UT=$SB/tests/integration/test_activity_log_user.py
REL_BS=.claude/make-it/references/build-standards.md
REL_PT=.claude/make-it/references/prompt-templates.md
REL_DB=.claude/make-it/references/design-blueprint.md
REL_MK=.claude/commands/make-it.md
REL_RS=.claude/commands/resume-it.md
REL_RF=.claude/commands/retrofit-it.md
REL_GV=docs/AI-GOVERNANCE-HOMEGROWN.md
REL_PR=docs/PENTEST-READINESS.md
FILES="$REL_AU $REL_LG $REL_UI $REL_UT $REL_BS $REL_PT $REL_DB $REL_MK $REL_RS $REL_RF $REL_GV $REL_PR"

# line number of the first line of file $1 matching $2 (0 when none)
at() { awk -v a="$2" '$0 ~ a {print NR; f=1; exit} END {if (!f) print 0}' "$1"; }

# verify ROOT: every check, against the tree at ROOT. Returns 1 when any fails.
verify() {
  local R="$1" AU="$1/$REL_AU" LG="$1/$REL_LG" UI="$1/$REL_UI" UT="$1/$REL_UT" BS="$1/$REL_BS" PT="$1/$REL_PT"
  local DB="$1/$REL_DB" MK="$1/$REL_MK" RS="$1/$REL_RS" RF="$1/$REL_RF" GV="$1/$REL_GV" PR="$1/$REL_PR"
  local L09 f
  fail=0
  for f in $FILES; do check "found: $f" '[ -s "$R/$f" ]'; done
  L09="$(grep -E '^[*][*]L09[*][*] ' "$BS" || true)"

  # 1. the sign-in code puts the verified user on the request
  check "auth.py: get_current_user sets request.state.user = user, once" 'lines "$AU" "    request.state.user = user" 1'
  check "auth.py: it is set after the token is decoded and before the user is returned" \
    '[ "$(at "$AU" "jwt[.]decode[(]")" -gt 0 ] && [ "$(at "$AU" "^    request[.]state[.]user = user$")" -gt "$(at "$AU" "jwt[.]decode[(]")" ] && [ "$(at "$AU" "^    return user$")" = "$(( $(at "$AU" "^    request[.]state[.]user = user$") + 1 ))" ]'
  check "auth.py: request.state is set in one place only" '[ "$(grep -c "request[.]state" "$AU")" = 1 ]'
  check "backend: no token or cookie is put on request.state" \
    '! grep -rnE "request[.]state[.][A-Za-z_]+ *=.*(token|cookie)|setattr[(] *request[.]state" "$R/$SB/app" >/dev/null'
  # 2. the names match
  check "logging.py: the middleware reads sub and email from request.state.user" \
    'lines "$LG" "            user = request.state.user" 1 && lines "$LG" "            user_sub = getattr(user, \"sub\", None)" 1 && lines "$LG" "            user_email = getattr(user, \"email\", None)" 1'
  check "schemas/auth.py: sub and email are UserInfo fields" 'lines "$UI" "    sub: str" 1 && lines "$UI" "    email: str" 1'
  # 3. the scaffold test goes through the real path
  check "scaffold test: proves no override of get_current_user is in place, and sets none" \
    'lines "$UT" "    assert get_current_user not in _fastapi_app.dependency_overrides" 1 && ! gq -F "dependency_overrides[get_current_user]" "$UT"'
  check "scaffold test: signs in with a JWT in the token cookie, signed with the app's secret" \
    'gq -F "cookies = {\"token\": token} if token else None" "$UT" && gq -F "monkeypatch.setattr(settings, \"JWT_SECRET\", secret)" "$UT"'
  check "scaffold test: a signed-in, a permission-checked and a refused request each name the user" \
    '(for t in test_signed_in_request_logs_the_user test_permission_checked_request_logs_the_user test_refused_request_logs_who_was_refused; do lines "$UT" "async def $t(jwt_secret):" 1 || exit 1; done)'
  check "scaffold test: a missing, forged or expired token names no user, and the token is never in the log" \
    '(for t in test_request_without_a_token_logs_no_user test_token_with_a_wrong_signature_logs_no_user test_expired_token_logs_no_user test_the_log_never_holds_the_token; do lines "$UT" "async def $t(jwt_secret):" 1 || exit 1; done)'
  # 4. the check
  check "L09 exists once, is [Tier 1, 5] [FIX], and is this check" \
    '[ "$(grep -cE "^[*][*]L09[*][*] " "$BS")" = 1 ] && printf "%s" "$L09" | gq -F "**L09** [Tier 1, 5] [FIX] **The activity log names the signed-in user** -- "'
  check "L09 is not a [SECURITY FIX]" '! printf "%s" "$L09" | gq -F "[SECURITY FIX]"'
  check "L09 comes right after L08 and is the last activity-log check (9 of them)" \
    '[ "$(grep -oE "^[*][*]L[0-9]+[*][*]" "$BS" | tail -2 | tr "\n" " ")" = "**L08** **L09** " ] && [ "$(grep -cE "^[*][*]L[0-9]+[*][*]" "$BS")" = 9 ]'
  check "L09 names the line, the field names, the no-token case and the test file" \
    'printf "%s" "$L09" | gq -F "(scaffold: \`request.state.user = user\`, after the token is decoded and before the return)" && printf "%s" "$L09" | gq -F "(scaffold: \`sub\` and \`email\` in \`backend/app/middleware/logging.py\`, both fields of \`UserInfo\`)" && printf "%s" "$L09" | gq -F "nothing is set when the token is missing, forged or expired, and the token and the cookie are never put on the request" && printf "%s" "$L09" | gq -F "\`backend/tests/integration/test_activity_log_user.py\` exists and passes: it signs in through the real cookie path with no override of \`get_current_user\`"'
  check "L09 says how an existing app is fixed, and the watermark note for a changed auth.py" \
    'printf "%s" "$L09" | gq -F "Fix: if the app'"'"'s \`auth.py\` differs from the scaffold'"'"'s only by the lines this fix adds, replace it with the scaffold'"'"'s copy, so the build record reads it as released (WM03)" && printf "%s" "$L09" | gq -F "\`watermark.py note backend/app/middleware/auth.py \"L09: the activity log names the signed-in user, <commit>\"\`" && printf "%s" "$L09" | gq -F "An app built before this check fails it; /resume-it'"'"'s catch-up offers it with the other activity-log gaps."'
  # 5. ranges and counts
  check "no activity-log range stops short of L09 (skills, references, docs)" \
    '[ "$(cat "$MK" "$RS" "$RF" "$BS" "$GV" "$PR" | grep -cE "L01-L0[1-8]([^0-9]|\$)" || true)" = 0 ]'
  check "make-it, resume-it and retrofit-it list L01-L09" \
    '[ "$(grep -c "^- [*][*]L01-L09[*][*]: Activity logs " "$MK")" = 1 ] && [ "$(grep -c "^   - [*][*]Activity Logs (L01-L09):[*][*] " "$RS")" = 1 ] && lines "$RF" "- **L01-L09**: Activity logs" 1'
  check "resume-it's catch-up scan looks for the user on the request (L09)" \
    'gq -F "(L09: \`request.state.user =\` in \`get_current_user\`)" "$RS"'
  check "the governance table counts 9 activity-log checks" 'lines "$GV" "| Activity Logs | L01-L09 | 9 | 1 (Web App) |" 1'
  # 6. the build instructions say the user must be put there
  check "the prompt and the blueprint no longer make the user on the request optional" \
    '! gq -F "(if populated by auth middleware)" "$PT" && ! gq -F "(may be populated by auth middleware)" "$DB"'
  check "the prompt and the blueprint say the auth code puts the verified user there (L09)" \
    'gq -F "that verifies the JWT MUST put it there (FastAPI: get_current_user sets" "$PT" && gq -F "where the auth code that verifies the JWT MUST put the verified user (FastAPI: \`get_current_user\` sets \`request.state.user\`; Express/NestJS: \`req.user\`)" "$DB"'
  [ "$fail" = 0 ]
}

verify "$root" && real=0 || real=1

# Controls. Each plants one defect in a throwaway copy of the files and must make verify fail.
copy() { rm -rf "$TMPD/t"; for f in $FILES; do mkdir -p "$TMPD/t/$(dirname "$f")"; cp "$f" "$TMPD/t/$f"; done; mkdir -p "$TMPD/t/$SB/app"; }
plant() {  # plant NAME FILE PYTHON-REPLACE-EXPR
  copy
  python3 -I - "$TMPD/t/$2" "$3" <<'PY'
# e is one of the fixed replace expressions written below in this script, never outside input.
import sys; p, e = sys.argv[1], sys.argv[2]; s = open(p).read(); n = eval(e, {"s": s})
assert n != s, "plant changed nothing"; open(p, "w").write(n)
PY
  if (verify "$TMPD/t" >/dev/null); then echo "FAIL control: $1 was not caught"; planted=1; else echo "ok   control: $1 is caught"; fi
}
planted=0
copy
if (verify "$TMPD/t" >/dev/null); then echo "ok   control: an unchanged copy passes"; else echo "FAIL control: an unchanged copy does not pass"; planted=1; fi
plant "the fix taken out of get_current_user" "$REL_AU" 's.replace("    request.state.user = user\n", "", 1)'
plant "the token put on the request instead of the user" "$REL_AU" 's.replace("    request.state.user = user\n", "    request.state.user = token\n", 1)'
plant "the user set before the token is checked" "$REL_AU" \
  's.replace("    request.state.user = user\n", "", 1).replace("    token = request.cookies.get(\"token\")\n", "    token = request.cookies.get(\"token\")\n    request.state.user = user\n", 1)'
plant "the middleware reading a name UserInfo does not have" "$REL_LG" 's.replace("getattr(user, \"email\", None)", "getattr(user, \"mail\", None)", 1)'
plant "the scaffold test overriding get_current_user" "$REL_UT" \
  's.replace("    _fastapi_app.dependency_overrides.clear()\n", "    _fastapi_app.dependency_overrides.clear()\n    _fastapi_app.dependency_overrides[get_current_user] = lambda: ADMIN_USER\n", 1)'
plant "the refused-request case dropped from the scaffold test" "$REL_UT" 's.replace("async def test_refused_request_logs_who_was_refused(jwt_secret):", "async def _refused(jwt_secret):", 1)'
plant "L09 downgraded to [WARN]" "$REL_BS" 's.replace("**L09** [Tier 1, 5] [FIX] ", "**L09** [Tier 1, 5] [WARN] ", 1)'
plant "L09 removed" "$REL_BS" 's[:s.index("**L09** ")] + s[s.index("\n", s.index("**L09** ")) + 1:]'
plant "the watermark note dropped from L09's fix" "$REL_BS" 's.replace(", and note it with `watermark.py note backend/app/middleware/auth.py \"L09: the activity log names the signed-in user, <commit>\"`", "", 1)'
plant "the stale L01-L08 range back in resume-it" "$REL_RS" 's.replace("**Activity Logs (L01-L09):**", "**Activity Logs (L01-L08):**", 1)'
plant "the stale L01-L08 range back in the pentest doc" "$REL_PR" 's.replace("(L01-L09) provide audit trail", "(L01-L08) provide audit trail", 1)'
plant "the governance count left at 8" "$REL_GV" 's.replace("| Activity Logs | L01-L09 | 9 |", "| Activity Logs | L01-L09 | 8 |", 1)'
plant "the optional wording back in the prompt" "$REL_PT" \
  's.replace("   - userEmail and userRole from the verified user on the request object.", "   - userEmail and userRole from JWT on request object (if populated by auth middleware)", 1)'

fail=0
[ "$real" = 0 ] || bad "the repository's own files pass every check above"

# The scaffold test, when this machine can run it: on the real tree it must pass, and on a copy of the backend with
# the fix taken out it must fail -- the proof that the middleware sees what get_current_user sets.
if (cd "$SB" && python3 -c "import pytest, pytest_asyncio, sqlalchemy, aiosqlite, fastapi, httpx, pydantic_settings, jwt" </dev/null 2>/dev/null); then
  T=tests/integration/test_activity_log_user.py
  check "the scaffold's test_activity_log_user.py passes" \
    '(cd "$SB" && PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider "$T" </dev/null >"$TMPD/pytest.out" 2>&1) || { tail -n 25 "$TMPD/pytest.out"; false; }'
  check "it ran every case, none skipped" \
    'gq -E "^8 passed" "$TMPD/pytest.out" && [ "$(grep -c "skipped" "$TMPD/pytest.out")" = 0 ]'
  rm -rf "$TMPD/b"; mkdir -p "$TMPD/b"; cp -R "$SB/." "$TMPD/b/"
  python3 -I - "$TMPD/b/app/middleware/auth.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); n = s.replace("    request.state.user = user\n", "", 1)
assert n != s, "the fix line was not found"; open(p, "w").write(n)
PY
  check "(control) with the fix taken out, the scaffold test fails on the user, 3 cases" \
    '! (cd "$TMPD/b" && PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider "$T" </dev/null >"$TMPD/pytest-red.out" 2>&1) && gq -E "^3 failed, 5 passed" "$TMPD/pytest-red.out" && gq -F "assert None == " "$TMPD/pytest-red.out"'
elif [ "${REQUIRE_SCAFFOLD_PYTEST:-}" = 1 ]; then
  bad "REQUIRE_SCAFFOLD_PYTEST is set, but python3 cannot import pytest and the scaffold's packages"
else
  echo "note the scaffold's pytest was NOT run here: python3 lacks pytest or the scaffold's packages"
fi
[ "$planted" = 0 ] || bad "every planted defect is caught"
check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
