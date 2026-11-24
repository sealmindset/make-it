#!/usr/bin/env bash
# The scaffolds keep local secrets out of images, and a worktree stays on its own database.
#   - Every scaffold .dockerignore excludes .env and .env.* (keeping .env.example): the backend image is one
#     stage with `COPY . .`, and Next's standalone output copies .env and .env.production into .next/standalone,
#     which the frontend's runner stage ships. A local build would otherwise bake the developer's secrets in.
#   - .env.example defines DB_PORT before DATABASE_URL, and DATABASE_URL uses ${DB_PORT}, so the port offset
#     scripts/worktree.sh gives a worktree reaches host-side migrations and tests, not the main checkout's database.
#   - worktree.sh updates a key in place (moving DB_PORT below DATABASE_URL would make ${DB_PORT} expand empty:
#     dotenv readers expand in file order), and the Compose project name is lowercase [a-z0-9_-] (Compose
#     refuses anything else, so a branch like feat/COM-123-Login failed to start).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
S="$root/.claude/make-it/scaffolds"
fail=0
check() { local name="$1"; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi; }

ignores() { [ -f "$1" ] && grep -qx '\.env' "$1" && grep -qx '\.env\.\*' "$1" && grep -qx '!\.env\.example' "$1"; }
# Every build context is read from the Compose files themselves (`context: <dir>` or `build: <dir>`, comments
# skipped), so a service added later is covered without editing this list.
contexts() { sed -nE 's/^[[:space:]]+(context|build):[[:space:]]*["'\'']?([^"'\''#[:space:]]+).*/\2/p' "$1"; }
n=0
while IFS= read -r compose; do
  dir="$(dirname "$compose")"; found=0
  while IFS= read -r ctx; do
    [ -n "$ctx" ] || continue
    found=1; n=$((n + 1))
    f="$dir/${ctx#./}"; [ "$ctx" = . ] && f="$dir"
    f="${f#"$S"/}/.dockerignore"
    check "$f keeps .env and .env.* out of the image, .env.example in" ignores "$S/$f"
  done < <(contexts "$compose")
  check "${compose#"$S"/} names at least one build context" test "$found" = 1
done < <(find "$S" -name 'docker-compose*.yml' | sort)
check "the Compose files name build contexts (found $n)" test "$n" -ge 5

port_first() {  # DB_PORT=[DB_PORT] comes before a DATABASE_URL that uses ${DB_PORT}
  awk '/^DB_PORT=\[DB_PORT\]$/ { p = NR } /^DATABASE_URL=.*@localhost:\$\{DB_PORT\}\// { u = NR } END { exit !(p && u && p < u) }' "$1"
}
for f in fastapi-nextjs/.env.example nextjs-fullstack/.env.example; do
  check "$f defines DB_PORT before the DATABASE_URL that uses it" port_first "$S/$f"
done

t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
for scaffold in fastapi-nextjs nextjs-fullstack; do
  repo="$t/$scaffold/MyApp"; mkdir -p "$repo/scripts"
  cp "$S/$scaffold/scripts/worktree.sh" "$repo/scripts/"
  printf 'services:\n  db:\n    ports:\n      - "${DB_PORT:-5500}:5432"\n  backend:\n    ports:\n      - "${BACKEND_PORT:-8100}:8000"\n' > "$repo/docker-compose.yml"
  printf 'POSTGRES_PASSWORD=pw\nDB_PORT=5500\nDATABASE_URL=postgresql://myapp:${POSTGRES_PASSWORD}@localhost:${DB_PORT}/myapp\nOTHER=1\n' > "$repo/.env"
  ( cd "$repo" && git init -q && git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init \
      && bash scripts/worktree.sh new feat/COM-123-Login >/dev/null 2>&1 )
  env="$t/$scaffold/MyApp-worktrees/feat_COM-123-Login/.env"
  in_place() { [ -f "$env" ] && awk -F= '$1 == "DB_PORT" { p = NR } $1 == "DATABASE_URL" { u = NR } END { exit !(p && u && p < u) }' "$env"; }
  offset() { local v; v="$(grep '^DB_PORT=' "$env" | cut -d= -f2)"; [ -n "$v" ] && [ "$v" != 5500 ] && [ "$(grep -c '^DB_PORT=' "$env")" = 1 ]; }
  project() { grep -qxE 'COMPOSE_PROJECT_NAME=[a-z0-9_-]+' "$env"; }
  check "$scaffold worktree.sh offsets DB_PORT and keeps it above DATABASE_URL" in_place
  check "$scaffold worktree.sh gives the worktree its own DB_PORT, once" offset
  check "$scaffold worktree.sh makes a lowercase Compose project name" project
done
exit "$fail"
