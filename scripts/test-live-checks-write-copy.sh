#!/usr/bin/env bash
# E12-S6 (the owner's calls, 2026-11-24: "the write test runs only in a throwaway database; no clean-up of a real
# database, ever", then "every build uses the temporary copy, new or existing"). Build-verify's write steps never run
# on the app's own database: they run in a temporary copy of the app's stack, which is removed with its volume.
# What runs here: the "Write steps" bash block cut out of make-it.md (count, wt_stop, wt_run), with a stub `docker`
# first on the PATH that records every call and the Compose project it acts on. No real container is started.
# Contract these checks pin:
#   - the copy has its own project name and ports, derived the way the scaffold's scripts/worktree.sh derives them;
#   - every call that starts, stops or removes anything names the copy's project, exactly, never the person's;
#   - a copy left by a session that died is removed first: only the project with exactly the copy's name;
#   - the copy goes on every way out: done, a failed start, a failed test, out of time, the run killed mid-test;
#   - a copy that would share the database's storage, or no Docker, is NOT RUN and starts nothing;
#   - the count guard reads the PERSON'S database: a write step wired to it by mistake makes the counts differ;
#   - a brand-new build has no other path: there is no "fresh database" test left in make-it.md;
#   - nothing in Part B cleans up a database (the sweep and its helpers are gone).
# What /resume-it's live pass sends is pinned in test-live-checks-have-steps.sh, which reads its table.
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
check "the Write steps block defines count, wt_stop and wt_run" \
  '( for f in count wt_stop wt_run; do grep -E "^ *$f\(\) [{(]" "$TMPD/block.sh" >/dev/null || exit 1; done )'
check "a brand-new build has no other path: no fresh-database test is left, and every build uses the copy" \
  '! has "fresh-db" "$MK" && has "Every build, new or existing, and /retrofit-it run the write steps in a temporary copy" "$MK"'
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
# the write step, as a script (Part B runs the write steps as one script inside wt_run); and one wired to the person's
printf '%s\n' 'env > "$TMPDIR/kept.env"' 'printf "%s\n" "INSERT INTO notes VALUES (1)" | docker compose exec -T db sh -c psql' > "$TMPD/write.sh"
printf '%s\n' 'printf "%s\n" "INSERT INTO notes VALUES (1)" | env -u COMPOSE_PROJECT_NAME docker compose exec -T db sh -c psql' > "$TMPD/wired.sh"
# the run as Part B orders it: count, the write steps inside wt_run, count, compare
FLOW='count > "$TMPDIR/before"; wt_run bash "$WS"; echo "run=$?"; count > "$TMPDIR/after"; cmp -s "$TMPDIR/before" "$TMPDIR/after" && echo SAME || echo DIFFERENT; echo "wt=$WT env=$WTENV"; [ -e "$WTENV" ] && echo ENVLEFT'

# the way scripts/worktree.sh names a project and offsets ports, taken from the scaffold's own file
WT="$(printf '%s-%s' "My App" make-it-write-test | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_')"
eval "$(sed -n '/^offset_for() {/,/^}/p' "$WTSH")"; OFF="$(offset_for "$WT")"
# every call that starts, stops or removes something, with the project it acted on
acts() { grep -E ' :: .*\b(up|down|stop|restart|rm|run|kill|start|create)\b' "$1" | grep -v ' :: compose .*\bexec\b' || true; }
only_copy() { [ -n "$(acts "$1")" ] && ! acts "$1" | grep -v "^$WT :: compose -p $WT " >/dev/null; }

scenario good "WS=$TMPD/write.sh" "touch \"\$STUB/up.$WT\" \"\$STUB/up.${WT}2\" \"\$STUB/up.person-app\"; $FLOW"
check "the copy is named as worktree.sh names a worktree's project, and is not the person's" \
  'has "wt=$WT " "$TMPD/good.out" && has "run=0" "$TMPD/good.out" && grep -x "COMPOSE_PROJECT_NAME=$WT" "$TMPD/tmp/kept.env" >/dev/null'
check "the copy's ports are the compose defaults plus worktree.sh's offset for that name" \
  'grep -x "FRONTEND_PORT=$((3100 + OFF))" "$TMPD/tmp/kept.env" >/dev/null && grep -x "BACKEND_PORT=$((8100 + OFF))" "$TMPD/tmp/kept.env" >/dev/null && grep -x "DB_PORT=$((5532 + OFF))" "$TMPD/tmp/kept.env" >/dev/null'
check "a copy left by a session that died is removed first: exactly the copy's project, never one with a longer name or the person's" \
  '[ "$(acts "$TMPD/good.log" | head -1 | grep -c -- "^$WT :: compose -p $WT .*down -v")" = 1 ] && [ -e "$STUB/up.${WT}2" ] && [ -e "$STUB/up.person-app" ]'
check "the copy is started with its own project, migrated by its start, and seeded on its own ports" \
  'grep -E "^$WT :: compose -p $WT .*up -d --build --wait" "$TMPD/good.log" >/dev/null && has "seed project=$WT frontend=$((3100 + OFF))" "$STUB/seed"'
check "every call that starts, stops or removes anything names the copy, never the person's project" 'only_copy "$TMPD/good.log"'
check "the copy is removed with its volume, and only the copy: down -v after up, nothing left, the env file gone" \
  '[ "$(acts "$TMPD/good.log" | tail -1 | grep -c -- "^$WT :: compose -p $WT .*down -v")" = 1 ] && [ ! -e "$STUB/up.$WT" ] && ! has ENVLEFT "$TMPD/good.out"'
check "the write step ran in the copy, and the person's counts are the same before and after" \
  '[ "$(cat "$STUB/rows.$WT" 2>/dev/null)" = 4 ] && [ ! -e "$STUB/rows.person-app" ] && has SAME "$TMPD/good.out"'

scenario wired "WS=$TMPD/wired.sh" "$FLOW"
check "a write step wired to the person's database fails the count guard" 'has DIFFERENT "$TMPD/wired.out" && ! has SAME "$TMPD/wired.out"'

gone() { [ ! -e "$STUB/up.$WT" ] && only_copy "$TMPD/$1.log" && acts "$TMPD/$1.log" | tail -1 | grep -- "^$WT :: compose -p $WT .*down -v" >/dev/null; }
scenario upfail "STUB_UP_FAIL=1" 'wt_run touch "$STUB/ran"; echo "run=$?"; [ -e "$WTENV" ] && echo ENVLEFT'
check "a start that fails says NOT RUN with a reason, runs no write step, and removes the copy and its volume" \
  'has "NOT RUN: " "$TMPD/upfail.out" && has "run=1" "$TMPD/upfail.out" && [ ! -e "$STUB/ran" ] && ! has ENVLEFT "$TMPD/upfail.out" && gone upfail'

scenario testfail "X=1" 'wt_run bash -c "exit 3"; echo "run=$?"'
check "a write step that errors still removes the copy and its volume" 'has "run=3" "$TMPD/testfail.out" && gone testfail'

scenario timeout "WT_LIMIT=1" 'wt_run sleep 20; echo "run=$?"'
check "a write test that runs out of time is stopped, says NOT RUN, and the copy is removed" \
  'has "NOT RUN: the write test ran out of time" "$TMPD/timeout.out" && has "run=142" "$TMPD/timeout.out" && gone timeout'

scenario shared "STUB_SHARED=1" 'wt_run touch "$STUB/ran"; echo "run=$?"'
check "a copy that would share the database's storage is NOT RUN, and is never started" \
  'has "NOT RUN: " "$TMPD/shared.out" && has "run=1" "$TMPD/shared.out" && ! grep -E " :: .*\bup\b" "$TMPD/shared.log" >/dev/null'

scenario nodocker "STUB_NO_DOCKER=1" 'wt_run touch "$STUB/ran"; echo "run=$?"'
check "with no Docker the write steps are NOT RUN, and nothing is started or removed" \
  'has "NOT RUN: " "$TMPD/nodocker.out" && has "run=1" "$TMPD/nodocker.out" && [ -z "$(acts "$TMPD/nodocker.log")" ]'

# the run is killed: once while the copy is starting, once in the middle of the write steps
killed() {  # killed NAME ENV COMMAND WAIT-FOR-FILE
  rm -f "$STUB"/log "$STUB"/up.* "$STUB"/seed "$TMPD/$1.finished"; : > "$STUB/log"
  ( cd "$APPD" && exec env PATH="$STUB/bin:$PATH" STUB="$STUB" TMPDIR="$TMPD/tmp" $2 bash -c ". '$TMPD/block.sh'; $3; echo finished > '$TMPD/$1.finished'" ) > "$TMPD/$1.out" 2>&1 &
  local pid=$! n=0; until [ -e "$4" ] || [ $n -ge 50 ]; do perl -e 'select(undef,undef,undef,0.1)'; n=$((n + 1)); done
  local t0=$SECONDS; kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  cp "$STUB/log" "$TMPD/$1.log"; echo $((SECONDS - t0)) > "$TMPD/$1.secs"
}
killed int "STUB_UP_SLEEP=1" "wt_run true" "$STUB/up.$WT"
check "killed while the copy is starting: nothing is left, and the run stops" '[ ! -e "$TMPD/int.finished" ] && gone int'
killed mid "X=1" "wt_run sleep 30" "$STUB/seed"
check "killed in the middle of the write steps: the copy and its volume are removed at once, and the run stops" \
  '[ ! -e "$TMPD/mid.finished" ] && gone mid && [ "$(cat "$TMPD/mid.secs")" -lt 10 ]'

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
  check "(control) the removal at the end taken out: a finished run leaves the copy" \
    'opp "s/\n  wt_stop >\/dev\/null 2>&1; trap - EXIT INT TERM HUP; return/\n  trap - EXIT INT TERM HUP; return/" "the copy is removed with its volume, and only the copy"'
  check "(control) the trap removed: a killed run leaves the copy" \
    'opp "s/\n *trap \x27kill[^\n]*INT TERM HUP\n/\n/" "killed in the middle of the write steps"'
  check "(control) the time limit removed: a stuck write test never ends" \
    'opp "s/alarm shift; exec \@ARGV/shift; exec \@ARGV/" "a write test that runs out of time"'
  check "(control) the storage check removed: a shared volume is started on" \
    'opp "s/ \|\| no \"the copy would share your database.s storage\"//" "a copy that would share the database"'
  check "(control) the fresh-database path back: a new build writes to the app's own database" \
    'opp "s/(\n22\. \*\*Build and start containers:\*\*\n)/\$1    Prints fresh-db: yes when the database is new.\n/" "a brand-new build has no other path"'
  check "(control) the old sweep back in step 26 a" \
    'opp "s/(\n    b\. Verify 2xx response)/\n       sweep() { del x; }\$1/" "nothing in Part B cleans up a database"'
fi

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
