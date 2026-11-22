#!/usr/bin/env bash
# E12-S6 proof run (2026-11-22): the scaffolds' scripts/seed-mock-services.sh had its host ports baked in at build
# time, so in a worktree or a copy with its own ports it seeded ANOTHER app's mock sign-in service (users written and
# deleted, redirect URIs replaced). Contract these checks pin:
#   - Each scaffold's seed script takes every host port from the same variable docker-compose.yml uses (the
#     environment first, then the project's .env), with the build's port only as the default; no URL in it has a
#     literal port. Proven by running the script's port lines, not by reading them: a built copy (placeholders filled
#     in) seeds the .env's ports, an environment variable beats the .env, and with neither it falls back to the default.
#   - Check M02 says so (so /resume-it's catch-up fixes apps already built), the catch-up's M line looks for it, and
#     the prompt that generates a seed script for other stacks says the same.
# A wording test is a tripwire, not a proof: it can't see a generated app's own script, only the scaffold and the rules.
# Usage: test-seed-script-ports.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

SC=.claude/make-it/scaffolds; FN="$SC/fastapi-nextjs/scripts/seed-mock-services.sh"; NF="$SC/nextjs-fullstack/scripts/seed-mock-services.sh"
BS=.claude/make-it/references/build-standards.md; PT=.claude/make-it/references/prompt-templates.md; RS=.claude/commands/resume-it.md
FILES="$FN $NF $BS $PT $RS"

# ports SCRIPT APPVAR: build a throwaway project from SCRIPT (placeholders filled as a build fills them), then print
# the two URLs its port lines produce in three cases: .env only, environment over .env, neither.
ports() {
  local d="$TMPD/p$RANDOM"; mkdir -p "$d/scripts"
  sed -e 's/\[MOCK_OIDC_PORT\]/10190/g' -e 's/\[FRONTEND_PORT\]/3100/g' -e 's/\[APP_PORT\]/3100/g' "$1" > "$d/scripts/seed.sh"
  awk '/^# Config/{on=1} on && /^MAX_RETRIES=/{exit} on' "$d/scripts/seed.sh" > "$d/scripts/ports.sh"
  printf 'MOCK_OIDC_PORT=10460\n%s="3460"   # this copy'"'"'s port\n' "$2" > "$d/.env"
  local show='echo "$MOCK_OIDC_URL ${FRONTEND_URL:-${APP_URL:-}}"'
  ( cd /; unset MOCK_OIDC_PORT FRONTEND_PORT APP_PORT; bash -c "set -u; . '$d/scripts/ports.sh'; $show" )
  ( cd /; unset FRONTEND_PORT APP_PORT; MOCK_OIDC_PORT=10999 bash -c "set -u; . '$d/scripts/ports.sh'; $show" )
  rm "$d/.env"; ( cd /; unset MOCK_OIDC_PORT FRONTEND_PORT APP_PORT; bash -c "set -u; . '$d/scripts/ports.sh'; $show" )
}
W_FN='http://localhost:10460 http://localhost:3460
http://localhost:10999 http://localhost:3460
http://localhost:10190 http://localhost:3100'

for s in "$FN:FRONTEND_PORT" "$NF:APP_PORT"; do
  f="${s%%:*}"; v="${s##*:}"
  check "$f: no URL has a literal or build-time port" '! grep -nE "localhost:(\[[A-Z_]+\]|[0-9]+)" "$f" >/dev/null'
  check "$f: a built copy seeds the .env's ports, the environment wins over .env, and the build's port is only the default" \
    '[ "$(ports "$f" "$v")" = "$W_FN" ]'
done

S_M02='**M02** [Tier 1, 5] [FIX] **Seed script exists** -- scripts/seed-mock-services.sh registers users (one per role), removes non-app users, updates redirect URIs. It takes every host port from the same variables docker-compose.yml uses (`MOCK_OIDC_PORT`, and `FRONTEND_PORT` or `APP_PORT`, from the environment or the project'"'"'s `.env`), with the build'"'"'s port only as the default -- never a literal port in a URL -- so in a worktree or a copy with its own ports it seeds that project'"'"'s own services. Fix: replace the script'"'"'s literal-port lines with these (the scaffold'"'"'s own; a Next.js full-stack app uses `APP_PORT` and `APP_URL` in place of `FRONTEND_PORT` and `FRONTEND_URL`), with the build'"'"'s ports as the defaults and `ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` above them:'
S_PT='- The seed script takes every host port from the same variables docker-compose.yml uses (from the environment or the project'"'"'s .env, with the build'"'"'s port only as the default), never a literal, so in a worktree or copy with its own ports it seeds that project'"'"'s own services (check M02)'
S_RS='- **Mock Services (M01-M04):** Check for mock-oidc/, seed-mock-services.sh, and that the seed script reads its ports from `MOCK_OIDC_PORT` and `FRONTEND_PORT` (or `APP_PORT`) instead of a literal port (M02; an app built before that is fixed with the lines M02 quotes)'
check "check M02 says the seed script takes its ports from the compose variables, whole" 'grep -xF -- "$S_M02" "$BS" >/dev/null'
# M02's fenced block is the scaffold's own helper, byte for byte, so an installed copy can fix an older app on its own
m02_block() { awk '/^[*][*]M02[*][*] /{on=1; next} on && /^```bash$/{inb=1; next} inb && /^```$/{exit} inb' "$BS"; }
fn_block() { awk '/^env_port\(\) \{/{on=1} on; on && /^FRONTEND_URL=/{exit}' "$FN"; }
check "M02 quotes the scaffold's env_port helper and port lines exactly" '[ -n "$(m02_block)" ] && [ "$(m02_block)" = "$(fn_block)" ]'
check "the prompt that generates a seed script says the same" 'tr "\n" " " < "$PT" | tr -s " " | grep -F -- "$S_PT" >/dev/null'
check "/resume-it's catch-up looks for it (M02)" 'grep -xF -- "   $S_RS" "$RS" >/dev/null'

if [ -z "${1:-}" ]; then
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" || return 1
    local out; out="$(bash "$SELF" "$d" 2>&1)" && return 1
    printf "%s\n" "$out" | grep -F "FAIL $3" >/dev/null
  }
  check "(control) an unchanged copy passes" 'd="$TMPD/c"; mkdir -p "$d"; tar -cf - $FILES | tar -xf - -C "$d"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) the old literal mock-oidc URL back in the fastapi-nextjs script" \
    'opp "$FN" "s/^MOCK_OIDC_URL=.*\$/MOCK_OIDC_URL=\"http:\/\/localhost:[MOCK_OIDC_PORT]\"/m" "$FN: no URL has a literal"'
  check "(control) the .env no longer read (only the default used)" \
    'opp "$NF" "s/\[ -f \"\\\$ROOT_DIR\/\.env\" \]/false/" "$NF: a built copy seeds the .env"'
  check "(control) M02's quoted helper no longer the scaffold's (it stops reading .env)" \
    'opp "$BS" "s/(\n```bash\nenv_port.*?)\[ -f \"\\\$ROOT_DIR\/\.env\" \]/\$1false/s" "M02 quotes the scaffold"'
  check "(control) M02 back to its old text" \
    'opp "$BS" "s/ It takes every host port from the same variables.*?literal ports\.//" "check M02 says"'
fi

check "the whole run wrote nothing to stderr" '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
