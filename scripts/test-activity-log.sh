#!/usr/bin/env bash
# test-activity-log.sh -- contract test for build-standards L09-L11, three faults in the fastapi-nextjs scaffold's logs.
#
# L09: RequestLoggingMiddleware filled user_sub and user_email from request.state.user and nothing set it, so the
#      Activity Logs page showed "-" for every user. get_current_user now puts the verified UserInfo there.
# L10: uvicorn's access log printed each request's query string, and the sign-in return route carries the one-time code
#      and state in it. A filter on uvicorn's own loggers now drops everything after the "?".
# L11: every event recorded the address of the proxy in front (the frontend), not the visitor's. X-Forwarded-For is now
#      believed only from proxies named in TRUSTED_PROXIES, uvicorn no longer reads it on its own, and the frontend
#      appends the address that connected to it (Next's rewrite proxy adds none).
#
# What this pins, by reading files: each fix in the scaffold, the scaffold tests that prove it, the three checks
# ([Tier 1, 5] [FIX], not [SECURITY FIX], with how an existing app is fixed), every activity-log range (L01-L11) and the
# governance count, and the build instructions for other stacks. Then planted defects, each in a throwaway copy (the
# real files are never edited): each must fail.
# Then, when python3 has pytest and the scaffold's packages, the scaffold's three test files run on the real tree (they
# must pass) and on copies with one fix taken out (each must fail for that fix). REQUIRE_SCAFFOLD_PYTEST=1 turns "not
# available" from a note into a failure; CI sets it. When node is installed, the frontend's preload runs in front of a
# plain node server, with a control run without it.
# A wording test is a tripwire, not a proof; the scaffold test runs are the proof.
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

SC=.claude/make-it/scaffolds/fastapi-nextjs
SB=$SC/backend
REL_AU=$SB/app/middleware/auth.py
REL_LG=$SB/app/middleware/logging.py
REL_UI=$SB/app/schemas/auth.py
REL_AL=$SB/app/access_log.py
REL_TP=$SB/app/middleware/trusted_proxies.py
REL_MA=$SB/app/main.py
REL_CF=$SB/app/config.py
REL_EP=$SB/entrypoint.sh
REL_DC=$SC/docker-compose.yml
REL_FD=$SC/frontend/Dockerfile
REL_FF=$SC/frontend/forwarded-for.mjs
REL_UT=$SB/tests/integration/test_activity_log_user.py
REL_CT=$SB/tests/integration/test_console_access_log.py
REL_VT=$SB/tests/integration/test_visitor_address.py
REL_BS=.claude/make-it/references/build-standards.md
REL_PT=.claude/make-it/references/prompt-templates.md
REL_DB=.claude/make-it/references/design-blueprint.md
REL_MK=.claude/commands/make-it.md
REL_RS=.claude/commands/resume-it.md
REL_RF=.claude/commands/retrofit-it.md
REL_GV=docs/AI-GOVERNANCE-HOMEGROWN.md
REL_PR=docs/PENTEST-READINESS.md
FILES="$REL_AU $REL_LG $REL_UI $REL_AL $REL_TP $REL_MA $REL_CF $REL_EP $REL_DC $REL_FD $REL_FF $REL_UT $REL_CT $REL_VT"
FILES="$FILES $REL_BS $REL_PT $REL_DB $REL_MK $REL_RS $REL_RF $REL_GV $REL_PR"

# line number of the first (or, with "last", the last) line of file $1 matching $2 (0 when none)
at() { awk -v a="$2" '$0 ~ a {print NR; f=1; exit} END {if (!f) print 0}' "$1"; }
last() { awk -v a="$2" '$0 ~ a {n=NR} END {print n+0}' "$1"; }
# has TEXT NEEDLE: TEXT contains NEEDLE, or say which is missing
has() { printf "%s" "$1" | gq -F -- "$2" || { echo "  missing: $2" | cut -c1-200; false; }; }

# verify ROOT: every check, against the tree at ROOT. Returns 1 when any fails.
verify() {
  local R="$1" AU="$1/$REL_AU" LG="$1/$REL_LG" UI="$1/$REL_UI" AL="$1/$REL_AL" TP="$1/$REL_TP" MA="$1/$REL_MA"
  local CF="$1/$REL_CF" EP="$1/$REL_EP" DC="$1/$REL_DC" FD="$1/$REL_FD" FF="$1/$REL_FF" UT="$1/$REL_UT" CT="$1/$REL_CT"
  local VT="$1/$REL_VT" BS="$1/$REL_BS" PT="$1/$REL_PT" DB="$1/$REL_DB" MK="$1/$REL_MK" RS="$1/$REL_RS" RF="$1/$REL_RF"
  local GV="$1/$REL_GV" PR="$1/$REL_PR" L09 L10 L11 f
  fail=0
  for f in $FILES; do check "found: $f" '[ -s "$R/$f" ]'; done
  L09="$(grep -E '^[*][*]L09[*][*] ' "$BS" || true)"
  L10="$(grep -E '^[*][*]L10[*][*] ' "$BS" || true)"
  L11="$(grep -E '^[*][*]L11[*][*] ' "$BS" || true)"

  # L09 -- the sign-in code puts the verified user on the request
  check "auth.py: get_current_user sets request.state.user = user, once" 'lines "$AU" "    request.state.user = user" 1'
  check "auth.py: it is set after the token is decoded and right before the user is returned" \
    '[ "$(at "$AU" "jwt[.]decode[(]")" -gt 0 ] && [ "$(at "$AU" "^    request[.]state[.]user = user$")" -gt "$(at "$AU" "jwt[.]decode[(]")" ] && [ "$(at "$AU" "^    return user$")" = "$(( $(at "$AU" "^    request[.]state[.]user = user$") + 1 ))" ]'
  check "auth.py: request.state is set in one place only" '[ "$(grep -c "request[.]state" "$AU")" = 1 ]'
  check "backend: no token or cookie is put on request.state" \
    '! grep -rnE "request[.]state[.][A-Za-z_]+ *=.*(token|cookie)|setattr[(] *request[.]state" "$R/$SB/app" >/dev/null'
  check "logging.py: the middleware reads sub and email, both UserInfo fields" \
    'lines "$LG" "            user_sub = getattr(user, \"sub\", None)" 1 && lines "$LG" "            user_email = getattr(user, \"email\", None)" 1 && lines "$UI" "    sub: str" 1 && lines "$UI" "    email: str" 1'
  check "L09 test: no override of get_current_user, a JWT in the token cookie, the seven cases" \
    'lines "$UT" "    assert get_current_user not in _fastapi_app.dependency_overrides" 1 && ! gq -F "dependency_overrides[get_current_user]" "$UT" && gq -F "cookies = {\"token\": token} if token else None" "$UT" && (for t in test_signed_in_request_logs_the_user test_permission_checked_request_logs_the_user test_refused_request_logs_who_was_refused test_request_without_a_token_logs_no_user test_token_with_a_wrong_signature_logs_no_user test_expired_token_logs_no_user test_the_log_never_holds_the_token; do lines "$UT" "async def $t(jwt_secret):" 1 || exit 1; done)'

  # L10 -- no query string in the console log
  check "access_log.py: the filter sits on uvicorn.access and uvicorn.error, and cuts at the ?" \
    'lines "$AL" "_LOGGERS = (\"uvicorn.access\", \"uvicorn.error\")" 1 && gq -F "arg.split(\"?\", 1)[0] if isinstance(arg, str) and arg.startswith(\"/\") and \"?\" in arg else arg" "$AL"'
  check "main.py: imports the filter and installs it once" \
    'lines "$MA" "from app.access_log import drop_query_strings_from_server_log" 1 && lines "$MA" "drop_query_strings_from_server_log()" 1'
  check "L10 test: a real uvicorn server, a callback with a code and state, and any other query string" \
    'gq -F "server = uvicorn.Server(uvicorn.Config(\"app.main:app\", proxy_headers=False))" "$CT" && lines "$CT" "async def test_sign_in_code_and_state_never_reach_the_console(capsys):" 1 && lines "$CT" "async def test_any_query_string_is_left_out(capsys):" 1'

  # L11 -- the visitor's address, believed only from a trusted proxy
  check "trusted_proxies.py: refuses *, and hands the header to uvicorn's ProxyHeadersMiddleware" \
    'gq -F "        if \"*\" in entries:" "$TP" && gq -F "from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware" "$TP" && [ "$(grep -c "ProxyHeadersMiddleware(" "$TP")" = 2 ]'
  check "main.py: the trusted-proxy wrap is the last, outermost, assignment of app" \
    '[ "$(last "$MA" "^app = ")" -gt 0 ] && [ "$(last "$MA" "^app = ")" = "$(at "$MA" "^app = TrustedProxyHeaders[(]app, settings[.]TRUSTED_PROXIES[)]")" ]'
  check "config.py: TRUSTED_PROXIES defaults to empty (trust no proxy)" 'lines "$CF" "    TRUSTED_PROXIES: str = \"\"" 1'
  check "entrypoint.sh: uvicorn is started with --no-proxy-headers" \
    'lines "$EP" "exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-proxy-headers" 1 && [ "$(grep -c "^exec uvicorn " "$EP")" = 1 ]'
  check "docker-compose.yml: the backend trusts the frontend by name" 'lines "$DC" "      - TRUSTED_PROXIES=\${TRUSTED_PROXIES:-frontend}" 1'
  check "frontend Dockerfile: copies the preload and starts the server with it" \
    'lines "$FD" "COPY --from=builder --chown=nextjs:nodejs /app/forwarded-for.mjs ./forwarded-for.mjs" 1 && lines "$FD" "CMD [\"node\", \"--import\", \"./forwarded-for.mjs\", \"server.js\"]" 1'
  check "forwarded-for.mjs: appends the connecting address after any earlier one" \
    'gq -F "req.headers[\"x-forwarded-for\"] = earlier ? \`\${earlier}, \${address}\` : address;" "$FF"'
  check "L11 test: trusted, untrusted, caller-written, network, host name, unresolvable, moved, *, and entrypoint parity" \
    '(for t in test_a_trusted_proxy_passes_on_the_visitor test_an_untrusted_caller_cannot_choose_its_address test_an_address_the_caller_wrote_before_the_proxy_appended_is_ignored test_a_proxy_network_can_be_trusted test_a_proxy_can_be_named_by_host_name test_a_name_that_does_not_resolve_trusts_no_one test_the_server_as_entrypoint_starts_it_does_not_believe_the_header_on_its_own; do lines "$VT" "async def $t():" 1 || exit 1; done) && lines "$VT" "async def test_a_named_proxy_that_moves_is_trusted_at_its_new_address(monkeypatch):" 1 && lines "$VT" "def test_trusting_everyone_is_refused():" 1'

  # the checks
  check "L09, L10 and L11 each exist once, [Tier 1, 5] [FIX], with their titles" \
    '[ "$(grep -cE "^[*][*]L(09|10|11)[*][*] " "$BS")" = 3 ] && has "$L09" "**L09** [Tier 1, 5] [FIX] **The activity log names the signed-in user** -- " && has "$L10" "**L10** [Tier 1, 5] [FIX] **The server'"'"'s console log prints no query string** -- " && has "$L11" "**L11** [Tier 1, 5] [FIX] **The activity log records the visitor, believed only from a trusted proxy** -- "'
  check "none of the three is a [SECURITY FIX]" '! printf "%s%s%s" "$L09" "$L10" "$L11" | gq -F "[SECURITY FIX]"'
  check "L09-L11 follow L08 in order, and L11 is the last activity-log check (11 of them)" \
    '[ "$(grep -oE "^[*][*]L[0-9]+[*][*]" "$BS" | tail -4 | tr "\n" " ")" = "**L08** **L09** **L10** **L11** " ] && [ "$(grep -cE "^[*][*]L[0-9]+[*][*]" "$BS")" = 11 ]'
  check "L09 names the line, the field names, the no-token case and its test" \
    'has "$L09" "(scaffold: \`request.state.user = user\`, after the token is decoded and before the return)" && has "$L09" "nothing is set when the token is missing, forged or expired, and the token and the cookie are never put on the request" && has "$L09" "\`backend/tests/integration/test_activity_log_user.py\` exists and passes: it signs in through the real cookie path with no override of \`get_current_user\`"'
  check "L09's fix: the scaffold's auth.py, or the change plus a watermark note" \
    'has "$L09" "Fix: if the app'"'"'s \`auth.py\` differs from the scaffold'"'"'s only by this fix, replace it with the scaffold'"'"'s copy, so the build record reads it as released (WM03); otherwise, in the app'"'"'s own \`get_current_user\`, put the verified user on \`request.state.user\` after the decode and before the return" && has "$L09" "\`watermark.py note backend/app/middleware/auth.py \"L09: the activity log names the signed-in user, <commit>\"\`"'
  check "L10 names the filter, both loggers, its test and what it does not cover" \
    'has "$L10" "keeps method, path and status and drops everything after the \`?\` (scaffold: \`backend/app/access_log.py\`, installed by \`drop_query_strings_from_server_log()\` in \`backend/app/main.py\`)" && has "$L10" "\`uvicorn.access\` and \`uvicorn.error\`" && has "$L10" "\`backend/tests/integration/test_console_access_log.py\` exists and passes" && has "$L10" "Not covered: logs already written keep what they hold."'
  check "L11 names the wrap, the flag, the compose value, the preload, its test, and the Kubernetes gap" \
    'has "$L11" "the right-most address that is not a trusted proxy is the visitor, and \`*\` is refused" && has "$L11" "starts uvicorn with \`--no-proxy-headers\`" && has "$L11" "\`TRUSTED_PROXIES=\${TRUSTED_PROXIES:-frontend}\`" && has "$L11" "\`node --import ./forwarded-for.mjs server.js\`" && has "$L11" "\`backend/tests/integration/test_visitor_address.py\` exists and passes" && has "$L11" "Not covered: the value for a Kubernetes deployment, which /argo-it does not set yet"'
  check "L11's fix: the scaffold's entrypoint.sh, or the flag plus a watermark note" \
    'has "$L11" "\`entrypoint.sh\` is a security file: if it differs from the scaffold'"'"'s only by this fix, replace it with the scaffold'"'"'s copy (WM03); otherwise add \`--no-proxy-headers\` to its \`exec uvicorn\` line and note it with \`watermark.py note backend/entrypoint.sh \"L11: uvicorn leaves X-Forwarded-For to TRUSTED_PROXIES, <commit>\"\`."'
  check "each of the three is offered to apps built before it by /resume-it's catch-up" \
    '(for c in "$L09" "$L10" "$L11"; do has "$c" "An app built before this check fails it; /resume-it'"'"'s catch-up offers it with the other activity-log gaps." || exit 1; done)'

  # ranges and counts
  check "no activity-log range stops short of L11 (skills, references, docs)" \
    '[ "$(cat "$MK" "$RS" "$RF" "$BS" "$GV" "$PR" | grep -cE "L01-L(0[1-9]|10)([^0-9]|\$)" || true)" = 0 ]'
  check "make-it, resume-it and retrofit-it list L01-L11" \
    '[ "$(grep -c "^- [*][*]L01-L11[*][*]: Activity logs " "$MK")" = 1 ] && [ "$(grep -c "^   - [*][*]Activity Logs (L01-L11):[*][*] " "$RS")" = 1 ] && lines "$RF" "- **L01-L11**: Activity logs" 1'
  check "resume-it's catch-up scan looks for all three" \
    'gq -F "(L09: \`request.state.user =\` in \`get_current_user\`)" "$RS" && gq -F "(L10: \`drop_query_strings_from_server_log\` in \`main.py\`)" "$RS" && gq -F "and the trusted-proxy wrap with \`--no-proxy-headers\` and the frontend'"'"'s \`forwarded-for.mjs\` (L11)" "$RS"'
  check "retrofit-it's entrypoint template starts uvicorn with --no-proxy-headers" \
    'lines "$RF" "       exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-proxy-headers" 1 && ! lines "$RF" "       exec uvicorn app.main:app --host 0.0.0.0 --port 8000" 1'
  check "the governance table counts 11 activity-log checks" 'lines "$GV" "| Activity Logs | L01-L11 | 11 | 1 (Web App) |" 1'

  # the build instructions, for every stack
  check "the prompt and the blueprint no longer make the user on the request optional, and require it (L09)" \
    '! gq -F "(if populated by auth middleware)" "$PT" && ! gq -F "(may be populated by auth middleware)" "$DB" && gq -F "that verifies the JWT MUST put it there (FastAPI: get_current_user sets" "$PT" && gq -F "where the auth code that verifies the JWT MUST put the verified user (FastAPI: \`get_current_user\` sets \`request.state.user\`; Express/NestJS: \`req.user\`)" "$DB"'
  check "the prompt and the blueprint say: no query string in the console log (L10), the visitor only from trusted proxies (L11)" \
    'gq -F "its query string: the sign-in callback carries the one-time code in it (L10)" "$PT" && gq -F "(Express: trust proxy set to those addresses, never true), and have the frontend" "$PT" && gq -F "because the sign-in callback carries the one-time code in it (build-standards L10)" "$DB" && gq -F "from X-Forwarded-For only when a proxy named in \`TRUSTED_PROXIES\` sent it, right-most untrusted address first" "$DB"'
  [ "$fail" = 0 ]
}

verify "$root" && real=0 || real=1

# Controls. Each plants one defect in a throwaway copy of the files and must make verify fail.
copy() { rm -rf "$TMPD/t"; for f in $FILES; do mkdir -p "$TMPD/t/$(dirname "$f")"; cp "$f" "$TMPD/t/$f"; done; }
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
plant "the user fix taken out of get_current_user" "$REL_AU" 's.replace("    request.state.user = user\n", "", 1)'
plant "the token put on the request instead of the user" "$REL_AU" 's.replace("    request.state.user = user\n", "    request.state.user = token\n", 1)'
plant "the user set before the token is checked" "$REL_AU" \
  's.replace("    request.state.user = user\n", "", 1).replace("    token = request.cookies.get(\"token\")\n", "    token = request.cookies.get(\"token\")\n    request.state.user = user\n", 1)'
plant "the middleware reading a name UserInfo does not have" "$REL_LG" 's.replace("getattr(user, \"email\", None)", "getattr(user, \"mail\", None)", 1)'
plant "the L09 test overriding get_current_user" "$REL_UT" \
  's.replace("    _fastapi_app.dependency_overrides.clear()\n", "    _fastapi_app.dependency_overrides.clear()\n    _fastapi_app.dependency_overrides[get_current_user] = lambda: ADMIN_USER\n", 1)'
plant "the console filter left off uvicorn.error" "$REL_AL" 's.replace("_LOGGERS = (\"uvicorn.access\", \"uvicorn.error\")", "_LOGGERS = (\"uvicorn.access\",)", 1)'
plant "the console filter not installed" "$REL_MA" 's.replace("\ndrop_query_strings_from_server_log()\n", "\n", 1)'
plant "the trusted-proxy wrap dropped" "$REL_MA" 's.replace("app = TrustedProxyHeaders(app, settings.TRUSTED_PROXIES)  # type: ignore[assignment]\n", "", 1)'
plant "a wrap added outside the trusted-proxy one" "$REL_MA" 's + "\napp = TrailingSlashASGI(app)  # type: ignore[assignment]\n"'
plant "* accepted" "$REL_TP" 's.replace("        if \"*\" in entries:", "        if False:", 1)'
plant "uvicorn left to read the header itself" "$REL_EP" 's.replace(" --port 8000 --no-proxy-headers\n", " --port 8000\n", 1)'
plant "every caller trusted in compose" "$REL_DC" 's.replace("TRUSTED_PROXIES=${TRUSTED_PROXIES:-frontend}", "TRUSTED_PROXIES=${TRUSTED_PROXIES:-*}", 1)'
plant "the frontend started without the preload" "$REL_FD" 's.replace("CMD [\"node\", \"--import\", \"./forwarded-for.mjs\", \"server.js\"]", "CMD [\"node\", \"server.js\"]", 1)'
plant "the preload overwriting the header instead of appending" "$REL_FF" \
  's.replace("req.headers[\"x-forwarded-for\"] = earlier ? `${earlier}, ${address}` : address;", "req.headers[\"x-forwarded-for\"] = earlier || address;", 1)'
plant "L10 downgraded to [WARN]" "$REL_BS" 's.replace("**L10** [Tier 1, 5] [FIX] ", "**L10** [Tier 1, 5] [WARN] ", 1)'
plant "L11 removed" "$REL_BS" 's[:s.index("**L11** ")] + s[s.index("\n", s.index("**L11** ")) + 1:]'
plant "L11 marked [SECURITY FIX]" "$REL_BS" 's.replace("**L11** [Tier 1, 5] [FIX] ", "**L11** [Tier 1, 5] [FIX] [SECURITY FIX] ", 1)'
plant "the watermark note dropped from L09's fix" "$REL_BS" 's.replace(", and note it with `watermark.py note backend/app/middleware/auth.py \"L09: the activity log names the signed-in user, <commit>\"`", "", 1)'
plant "the Kubernetes gap dropped from L11" "$REL_BS" 's.replace(" Not covered: the value for a Kubernetes deployment, which /argo-it does not set yet (with the compose value there, no proxy is believed and the address that connected is recorded, that of the ingress controller or a frontend pod, as before).", "", 1)'
plant "a stale L01-L09 range back in resume-it" "$REL_RS" 's.replace("**Activity Logs (L01-L11):**", "**Activity Logs (L01-L09):**", 1)'
plant "a stale L01-L10 range back in the pentest doc" "$REL_PR" 's.replace("(L01-L11) provide audit trail", "(L01-L10) provide audit trail", 1)'
plant "the governance count left at 9" "$REL_GV" 's.replace("| Activity Logs | L01-L11 | 11 |", "| Activity Logs | L01-L11 | 9 |", 1)'
plant "the retrofit entrypoint template without the flag" "$REL_RF" 's.replace("       exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-proxy-headers\n", "       exec uvicorn app.main:app --host 0.0.0.0 --port 8000\n", 1)'
plant "the optional wording back in the prompt" "$REL_PT" \
  's.replace("   - userEmail and userRole from the verified user on the request object.", "   - userEmail and userRole from JWT on request object (if populated by auth middleware)", 1)'

fail=0
[ "$real" = 0 ] || bad "the repository's own files pass every check above"

# The scaffold tests, when this machine can run them: on the real tree they must pass, and on a copy of the backend
# with one fix taken out the test for that fix must fail.
if (cd "$SB" && python3 -c "import pytest, pytest_asyncio, sqlalchemy, aiosqlite, fastapi, httpx, pydantic_settings, jwt, uvicorn" </dev/null 2>/dev/null); then
  TESTS="tests/integration/test_activity_log_user.py tests/integration/test_console_access_log.py tests/integration/test_visitor_address.py"
  check "the scaffold's three activity-log test files pass, every case run (16 + 2 + 10)" \
    '(cd "$SB" && PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider $TESTS </dev/null >"$TMPD/pytest.out" 2>&1) || { tail -n 25 "$TMPD/pytest.out"; false; }'
  check "  ... 28 passed, none skipped" 'gq -E "^28 passed" "$TMPD/pytest.out" && [ "$(grep -c "skipped" "$TMPD/pytest.out")" = 0 ]'
  red() {  # red NAME FILE-IN-BACKEND PYTHON-REPLACE-EXPR TESTFILE WANTED-SUMMARY
    local TF="$4" WANT="$5"
    rm -rf "$TMPD/b"; mkdir -p "$TMPD/b"; cp -R "$SB/." "$TMPD/b/"
    python3 -I - "$TMPD/b/$2" "$3" <<'PY'
# e is one of the fixed replace expressions written below in this script, never outside input.
import sys; p, e = sys.argv[1], sys.argv[2]; s = open(p).read(); n = eval(e, {"s": s})
assert n != s, "the fix was not found"; open(p, "w").write(n)
PY
    check "(control) $1: its test fails ($WANT)" \
      '! (cd "$TMPD/b" && PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider "$TF" </dev/null >"$TMPD/red.out" 2>&1) && gq -E "^$WANT in " "$TMPD/red.out" || { tail -n 5 "$TMPD/red.out"; false; }'
  }
  red "the user fix taken out" app/middleware/auth.py 's.replace("    request.state.user = user\n", "", 1)' tests/integration/test_activity_log_user.py "3 failed, 13 passed"
  red "the log takes the user from an X-User header" app/middleware/logging.py 's.replace("        user_sub = None\n        user_email = None\n", "        user_sub = request.headers.get(\"x-user\")\n        user_email = request.headers.get(\"x-user\")\n", 1)' tests/integration/test_activity_log_user.py "2 failed, 14 passed"
  red "auth signs in from an X-User header" app/middleware/auth.py 's.replace("    token = request.cookies.get(\"token\")\n", "    token = request.cookies.get(\"token\")\n    if request.headers.get(\"x-user\"):\n        request.state.user = UserInfo(sub=request.headers[\"x-user\"], email=request.headers[\"x-user\"], name=\"\", role_id=\"\", role_name=\"\", permissions=[])\n", 1)' tests/integration/test_activity_log_user.py "2 failed, 14 passed"
  red "the console filter not installed" app/main.py 's.replace("\ndrop_query_strings_from_server_log()\n", "\n", 1)' tests/integration/test_console_access_log.py "2 failed"
  red "the trusted-proxy wrap dropped" app/main.py 's.replace("app = TrustedProxyHeaders(app, settings.TRUSTED_PROXIES)  # type: ignore[assignment]\n", "", 1)' tests/integration/test_visitor_address.py "1 failed, 9 passed"
  red "uvicorn left to read the header itself" entrypoint.sh 's.replace(" --no-proxy-headers\n", "\n", 1)' tests/integration/test_visitor_address.py "1 failed, 9 passed"
  red "* accepted" app/middleware/trusted_proxies.py 's.replace("        if \"*\" in entries:", "        if False:", 1)' tests/integration/test_visitor_address.py "1 failed, 9 passed"
elif [ "${REQUIRE_SCAFFOLD_PYTEST:-}" = 1 ]; then
  bad "REQUIRE_SCAFFOLD_PYTEST is set, but python3 cannot import pytest and the scaffold's packages"
else
  echo "note the scaffold's pytest was NOT run here: python3 lacks pytest or the scaffold's packages"
fi

# The frontend's preload, in front of a plain node HTTP server (Next.js itself is not installed here).
if command -v node >/dev/null 2>&1; then
  mkdir -p "$TMPD/n"; cp "$REL_FF" "$TMPD/n/forwarded-for.mjs"
  cat >"$TMPD/n/echo.mjs" <<'JS'
import http from "node:http";
const server = http.createServer((req, res) => res.end(JSON.stringify(req.headers["x-forwarded-for"] ?? null)));
server.listen(0, "127.0.0.1", async () => {
  const url = `http://127.0.0.1:${server.address().port}/`;
  console.log(await (await fetch(url)).text());
  console.log(await (await fetch(url, { headers: { "x-forwarded-for": "6.6.6.6" } })).text());
  server.close();
});
JS
  check "preload: no header in -> the connecting address; a caller's 6.6.6.6 -> 6.6.6.6, then the connecting address" \
    '[ "$(cd "$TMPD/n" && node --import ./forwarded-for.mjs echo.mjs </dev/null 2>&1 | tr "\n" " ")" = "\"127.0.0.1\" \"6.6.6.6, 127.0.0.1\" " ]'
  check "(control) without it: no header in -> none out; the caller's own header passes unchanged" \
    '[ "$(cd "$TMPD/n" && node echo.mjs </dev/null 2>&1 | tr "\n" " ")" = "null \"6.6.6.6\" " ]'
else
  echo "note the frontend preload was NOT run here: node is not installed"
fi
[ "$planted" = 0 ] || bad "every planted defect is caught"
check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
