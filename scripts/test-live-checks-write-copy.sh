#!/usr/bin/env bash
# E12-S6 (the owner's call, 2026-11-24: "the write test runs only in a throwaway database; no clean-up of a real
# database, ever"). Build-verify's write steps run on the app's own database only in a brand-new build; in an
# existing app (/retrofit-it) they run in a temporary copy of the app's stack, which is then removed with its volume.
# What runs here: the two bash blocks cut out of make-it.md -- step 22's "fresh database?" line and the "Write steps"
# block (count, wt_start, wt_stop) -- with a stub `docker` first on the PATH that records every call and the Compose
# project it acts on. No real container is started.
# Contract these checks pin:
#   - the copy has its own project name and ports, derived the way the scaffold's scripts/worktree.sh derives them;
#   - every call that starts, stops or removes anything names the copy's project, never the person's;
#   - `down -v` runs only on the copy; a start that fails removes the copy; so does an interrupted one (a trap);
#   - a copy that would share the database's storage, or no Docker, is NOT RUN and starts nothing;
#   - the count guard reads the PERSON'S database: a write step wired to it by mistake makes the counts differ;
#   - "fresh database" fails safe: only "no volume of this project yet" says yes; a volume, or no answer, says no;
#   - nothing in Part B cleans up a database any more (the sweep and its helpers are gone).
# A stub proves the commands and their order, not that Docker does what they ask: the real run is in the PR's proof.
# Usage: test-live-checks-write-copy.sh [MAKE-IT.MD]. With no argument it checks this repo, then proves the checks
# fail on opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
MK="${1:-$root/.claude/commands/make-it.md}"
WTSH="$root/.claude/make-it/scaffolds/fastapi-nextjs/scripts/worktree.sh"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
has() { grep -F -- "$1" "$2" >/dev/null; }

fence='on && /^ *```bash/{f=1; next} on && f && /^ *```/{f=0} on && f'
awk '/^\*\*Write steps run only/{on=1} /^21\. /{on=0} '"$fence" "$MK" | sed 's/<db>/db/g' > "$TMPD/block.sh" || true
awk '/^22\. \*\*Build and start/{on=1} /^22b\. /{on=0} '"$fence" "$MK" | grep -v '^ *docker ' | sed 's/<project>/person-app/g' > "$TMPD/fresh.sh" || true
check "the Write steps block defines count, wt_start and wt_stop, and step 22 has the fresh-database line" \
  '( for f in count wt_start wt_stop; do grep -E "^ *$f\(\) [{(]" "$TMPD/block.sh" >/dev/null || exit 1; done ) && has "fresh-db: yes" "$TMPD/fresh.sh"'
partb="$(awk '/^\*\*PART B: Live verification/{on=1} /^\*\*PART C: Fix cycle/{on=0} on' "$MK")"
check "nothing in Part B cleans up a database: no sweep, mark, left or mentions, and no DELETE statement" \
  '! printf "%s" "$partb" | grep -E "^ *(sweep|mark|left|mentions|del)\(\)|DELETE FROM|sweep" >/dev/null'

# the app: a folder with a compose file, a seed script, and the stub docker
APPD="$TMPD/My App"; STUB="$TMPD/stub"; mkdir -p "$APPD/scripts" "$STUB/bin" "$TMPD/tmp"
cat > "$APPD/docker-compose.yml" <<'YML'
name: ${COMPOSE_PROJECT_NAME:-person-app}
services:
  frontend: {ports: ["${FRONTEND_PORT:-3100}:3000"]}
  backend: {ports: ["${BACKEND_PORT:-8100}:8000"]}
  db: {ports: ["${DB_PORT:-5532}:5432"], volumes: ["postgres_data:/var/lib/postgresql/data"]}
volumes: {postgres_data: {}}
YML
printf '%s\n' '#!/usr/bin/env bash' 'echo "seed project=${COMPOSE_PROJECT_NAME:-} frontend=${FRONTEND_PORT:-}" >> "$STUB/seed"' > "$APPD/scripts/seed-mock-services.sh"
cat > "$STUB/bin/docker" <<'SH'
#!/usr/bin/env bash
# Records "<project> :: <args>". The project is -p's, else COMPOSE_PROJECT_NAME, else the person's (as their .env sets it).
a=("$@"); proj=""
for ((i = 0; i < ${#a[@]}; i++)); do [ "${a[i]}" = "-p" ] && proj="${a[i+1]}"; done
[ -n "$proj" ] || proj="${COMPOSE_PROJECT_NAME:-person-app}"
echo "$proj :: $*" >> "$STUB/log"
[ -z "${STUB_NO_DOCKER:-}" ] || exit 1
case " $* " in
  *" info "*) ;;
  *" volume ls "*) cat "$STUB/volumes" 2>/dev/null || true ;;
  *" config --format json "*)
    if [ -n "${STUB_SHARED:-}" ]; then vol='{"name": "fixed_data", "external": true}'; else vol="{\"name\": \"${proj}_postgres_data\"}"; fi
    echo "{\"name\": \"$proj\", \"volumes\": {\"postgres_data\": $vol}, \"services\": {\"db\": {\"volumes\": [{\"type\": \"volume\", \"source\": \"postgres_data\"}]}}}" ;;
  *" config "*) echo "name: $proj"; echo "services:" ;;
  *" up "*) touch "$STUB/up.$proj"; [ -z "${STUB_UP_SLEEP:-}" ] || sleep 2; [ -z "${STUB_UP_FAIL:-}" ] || exit 1 ;;
  *" down "*) rm -f "$STUB/up.$proj" ;;
  *" exec "*) in="$(cat)"; n="$(cat "$STUB/rows.$proj" 2>/dev/null || echo 3)"
    case "$in" in *INSERT*) echo $((n + 1)) > "$STUB/rows.$proj" ;; *) echo "notes|$n" ;; esac ;;
esac
SH
chmod +x "$STUB/bin/docker"

# scenario NAME "ENV=..." COMMANDS: a clean stub, then the commands in the app's folder with the block loaded
scenario() {
  rm -f "$STUB"/log "$STUB"/up.* "$STUB"/rows.* "$STUB"/seed "$TMPD"/tmp/*; : > "$STUB/log"
  ( cd "$APPD" && env PATH="$STUB/bin:$PATH" STUB="$STUB" TMPDIR="$TMPD/tmp" $2 bash -c ". '$TMPD/block.sh'; $3" ) > "$TMPD/$1.out" 2>&1 || true
  cp "$STUB/log" "$TMPD/$1.log"
}
WRITE='printf "%s\n" "INSERT INTO notes VALUES (1)" | docker compose exec -T db sh -c psql'
FLOW='count > "$TMPDIR/before"; wt_start; echo "start=$?"; cat "$WTENV" > "$TMPDIR/kept.env"; WRITESTEP; wt_stop; count > "$TMPDIR/after"; cmp -s "$TMPDIR/before" "$TMPDIR/after" && echo SAME || echo DIFFERENT; echo "wt=$WT env=$WTENV"; [ -e "$WTENV" ] && echo ENVLEFT'

# the way scripts/worktree.sh names a project and offsets ports, taken from the scaffold's own file
WT="$(printf '%s-%s' "My App" make-it-write-test | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_')"
eval "$(sed -n '/^offset_for() {/,/^}/p' "$WTSH")"; OFF="$(offset_for "$WT")"
# every call that starts, stops or removes something, with the project it acted on
acts() { grep -E ' :: .*\b(up|down|stop|restart|rm|run|kill|start|create)\b' "$1" | grep -v ' :: compose .*\bexec\b' || true; }
only_copy() { [ -n "$(acts "$1")" ] && ! acts "$1" | grep -v "^$WT :: compose -p $WT " >/dev/null; }

scenario good "X=1" "${FLOW/WRITESTEP/( . \"\$WTENV\"; $WRITE )}"
check "the copy is named as worktree.sh names a worktree's project, and is not the person's" \
  'has "wt=$WT " "$TMPD/good.out" && has "start=0" "$TMPD/good.out" && has "export COMPOSE_PROJECT_NAME=$WT" "$TMPD/tmp/kept.env"'
check "the copy's ports are the compose defaults plus worktree.sh's offset for that name" \
  'has "export FRONTEND_PORT=$((3100 + OFF))" "$TMPD/tmp/kept.env" && has "export BACKEND_PORT=$((8100 + OFF))" "$TMPD/tmp/kept.env" && has "export DB_PORT=$((5532 + OFF))" "$TMPD/tmp/kept.env"'
check "the copy is started with its own project, migrated by its start, and seeded on its own ports" \
  'grep -E "^$WT :: compose -p $WT .*up -d --build --wait" "$TMPD/good.log" >/dev/null && has "seed project=$WT frontend=$((3100 + OFF))" "$STUB/seed"'
check "every call that starts, stops or removes anything names the copy, never the person's project" 'only_copy "$TMPD/good.log"'
check "the copy is removed with its volume, and only the copy: down -v after up, nothing left, the env file gone" \
  '[ "$(acts "$TMPD/good.log" | tail -1 | grep -c -- "^$WT :: compose -p $WT .*down -v")" = 1 ] && [ ! -e "$STUB/up.$WT" ] && ! has ENVLEFT "$TMPD/good.out"'
check "the write step ran in the copy, and the person's counts are the same before and after" \
  '[ "$(cat "$STUB/rows.$WT" 2>/dev/null)" = 4 ] && [ ! -e "$STUB/rows.person-app" ] && has SAME "$TMPD/good.out"'

scenario wired "X=1" "${FLOW/WRITESTEP/( $WRITE )}"
check "a write step wired to the person's database fails the count guard" 'has DIFFERENT "$TMPD/wired.out" && ! has SAME "$TMPD/wired.out"'

scenario upfail "STUB_UP_FAIL=1" 'wt_start; echo "start=$?"; [ -e "$WTENV" ] && echo ENVLEFT'
check "a start that fails says NOT RUN with a reason, removes the copy and its volume, and touches nothing else" \
  'has "NOT RUN: " "$TMPD/upfail.out" && has "start=1" "$TMPD/upfail.out" && [ ! -e "$STUB/up.$WT" ] && ! has ENVLEFT "$TMPD/upfail.out" && only_copy "$TMPD/upfail.log" && acts "$TMPD/upfail.log" | tail -1 | grep -- "down -v" >/dev/null'

scenario shared "STUB_SHARED=1" 'wt_start; echo "start=$?"'
check "a copy that would share the database's storage is NOT RUN, and is never started" \
  'has "NOT RUN: " "$TMPD/shared.out" && has "start=1" "$TMPD/shared.out" && ! grep -E " :: .*\bup\b" "$TMPD/shared.log" >/dev/null'

scenario nodocker "STUB_NO_DOCKER=1" 'wt_start; echo "start=$?"'
check "with no Docker the write steps are NOT RUN, and nothing is started or removed" \
  'has "NOT RUN: " "$TMPD/nodocker.out" && has "start=1" "$TMPD/nodocker.out" && [ -z "$(acts "$TMPD/nodocker.log")" ]'

# interrupted while the copy is starting: the shell gets TERM, and the copy must be gone when it ends
rm -f "$STUB"/log "$STUB"/up.*; : > "$STUB/log"
( cd "$APPD" && exec env PATH="$STUB/bin:$PATH" STUB="$STUB" TMPDIR="$TMPD/tmp" STUB_UP_SLEEP=1 bash -c ". '$TMPD/block.sh'; wt_start; echo finished > '$TMPD/int.finished'" ) > "$TMPD/int.out" 2>&1 &
pid=$!; n=0; until grep -E ' :: .*\bup\b' "$STUB/log" >/dev/null 2>&1 || [ $n -ge 50 ]; do perl -e 'select(undef,undef,undef,0.1)'; n=$((n + 1)); done
kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
check "an interrupted start leaves nothing: the trap removes the copy and its volume, and the run stops" \
  '[ ! -e "$STUB/up.$WT" ] && [ ! -e "$TMPD/int.finished" ] && acts "$STUB/log" | tail -1 | grep -- "^$WT :: compose -p $WT .*down -v" >/dev/null && only_copy "$STUB/log"'

# step 22's "fresh database?" line
fresh() { ( cd "$APPD" && env PATH="$STUB/bin:$PATH" STUB="$STUB" $1 bash "$TMPD/fresh.sh" 2>&1 ) || true; }
rm -f "$STUB/volumes"
check "fresh database: no volume of this project yet says yes, and asks about this project only" \
  '[ "$(fresh X=1)" = "fresh-db: yes" ] && tail -1 "$STUB/log" | grep -F "label=com.docker.compose.project=person-app" >/dev/null'
echo "person-app_postgres_data" > "$STUB/volumes"
check "fresh database: a volume that is already there says no" '[ "$(fresh X=1)" = "fresh-db: no" ]'
rm -f "$STUB/volumes"
check "fresh database: no answer from Docker says no (it fails safe)" '[ "$(fresh STUB_NO_DOCKER=1)" = "fresh-db: no" ]'

# controls (this repo only): each opposite fails for its own reason
if [ -z "${1:-}" ]; then
  # opp PERL REASON: make-it.md with one edit must fail this script on the check named REASON
  opp() {
    cp "$MK" "$TMPD/m.md"; perl -0pi -e "$1" "$TMPD/m.md"; ! cmp -s "$MK" "$TMPD/m.md" || return 1
    local out; out="$(bash "$SELF" "$TMPD/m.md" 2>&1)" && return 1
    printf '%s\n' "$out" | grep -F "FAIL $2" >/dev/null
  }
  check "(control) the removal no longer names the copy: it would take the person's containers and volume" \
    'opp "s/(wt_stop\(\) \{.*?)docker compose -p \"\\\$WT\" --profile dev down/\$1docker compose --profile dev down/s" "every call that starts, stops or removes anything names the copy"'
  check "(control) a failed start no longer removes the copy" \
    'opp "s/\n[^\n]*\|\| wt_stop >\/dev\/null 2>&1\n/\n/" "a start that fails says NOT RUN"'
  check "(control) the trap removed: an interrupted start leaves the copy" \
    'opp "s/\n *trap \x27wt_stop[^\n]*INT TERM HUP\n/\n/" "an interrupted start leaves nothing"'
  check "(control) the storage check removed: a shared volume is started on" \
    'opp "s/ \|\| no \"the copy would share your database.s storage\"//" "a copy that would share the database"'
  check "(control) fresh database says yes when Docker gives no answer" \
    'opp "s/ 2>\/dev\/null \|\| echo unknown\)/ 2>\/dev\/null)/" "fresh database: no answer from Docker says no"'
  check "(control) the old sweep back in step 26 a" \
    'opp "s/(\n    b\. Verify 2xx response)/\n       sweep() { del x; }\$1/" "nothing in Part B cleans up a database"'
fi

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
