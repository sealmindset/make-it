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
#   - every check runs BEFORE anything is started or removed: a refused copy (shared storage, a folder mounted into
#     any service, a setting whose host is outside the copy, no Docker) starts nothing and issues no `down` at all,
#     because `down -v` removes a volume with a fixed name whatever project it is given;
#   - where the app CONNECTS is checked by .claude/make-it/scripts/stack-check.py (shared with /resume-it's "settings
#     point at this machine" rule): the copy's own services pass; an outside host, localhost, 127.0.0.1 and
#     host.docker.internal are refused; unknown is refused; only the host is printed, never a value;
#   - only variables whose name ends in PORT are offset (WORKERS:-4 stays 4);
#   - the count guard reads the PERSON'S database, rows and the database's own insert/update/delete counters: a write
#     step wired to it by mistake makes them differ, even a create-then-delete that nets zero rows;
#   - "copy removed" is printed only when the removal succeeded; otherwise "COPY LEFT";
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
SC="$root/.claude/make-it/scripts/stack-check.py"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
has() { grep -F -- "$1" "$2" >/dev/null; }
# a made-up password for the settings fixtures, put together here so no file holds a password inside a URL
PW="fixture"; PW="${PW}pw"; export PW

fence='on && /^ *```bash/{f=1; next} on && f && /^ *```/{f=0} on && f'
awk '/^\*\*Write steps run only/{on=1} /^21\. /{on=0} '"$fence" "$MK" | sed 's/<db>/db/g' \
  | sed "s#\$HOME/.claude/make-it/scripts#$root/.claude/make-it/scripts#g" > "$TMPD/block.sh" || true
check "the Write steps block defines count, wt_check, wt_stop and wt_run" \
  '( for f in count wt_check wt_stop wt_run; do grep -E "^ *$f\(\) [{(]" "$TMPD/block.sh" >/dev/null || exit 1; done )'
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
  backend: {ports: ["${BACKEND_PORT:-8100}:8000"], environment: {WORKERS: "${WORKERS:-4}"}}
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
  *" config --format json "*) python3 -I - "$proj" <<'PY'
import json, os, sys
p, e = sys.argv[1], os.environ.get
fp, bp, dp = e("FRONTEND_PORT", "3100"), e("BACKEND_PORT", "8100"), e("DB_PORT", "5532")
pw = e("PW", "")   # a made-up password, set by the test: it must never show in what the block prints
benv = {"DATABASE_URL": e("STUB_DBURL", "postgresql+asyncpg://app:" + pw + "@db:5432/app"), "FRONTEND_URL": "http://localhost:" + fp,
        "OIDC_ISSUER_URL": "http://mock-oidc:10090", "WORKERS": e("WORKERS", "4"), "JWT_SECRET": pw}
if e("STUB_DBHOST"): benv.update(DB_HOST=e("STUB_DBHOST"), DB_PORT="5432")
print(json.dumps({"name": p,
    "volumes": {"postgres_data": {"name": "fixed_data" if e("STUB_FIXED") else p + "_postgres_data"}},
    "services": {"frontend": {"ports": [{"published": fp, "target": 3000}]},
                 "backend": {"environment": benv, "ports": [{"published": bp, "target": 8000}],
                             "volumes": [{"type": "bind", "source": "/Users/someone/uploads", "target": "/app/uploads"}] if e("STUB_BIND") else []},
                 "mock-oidc": {},
                 "db": {"ports": [{"published": dp, "target": 5432}], "volumes": [{"type": "volume", "source": "postgres_data"}]}}}))
PY
    ;;
  *" config "*) echo "name: $proj"; echo "services:" ;;
  *" up "*) touch "$STUB/up.$proj"; [ -z "${STUB_UP_SLEEP:-}" ] || sleep 2; [ -z "${STUB_UP_FAIL:-}" ] || exit 1 ;;
  *" down "*) [ -z "${STUB_DOWN_FAIL:-}" ] || exit 1; rm -f "$STUB/up.$proj" ;;
  *" exec "*) in="$(cat)"; n="$(cat "$STUB/rows.$proj" 2>/dev/null || echo 3)"; k="$(cat "$STUB/ins.$proj" 2>/dev/null || echo 0)"
    case "$in" in
      *INSERT*) echo $((n + 1)) > "$STUB/rows.$proj"; echo $((k + 1)) > "$STUB/ins.$proj" ;;
      *"DELETE FROM"*) echo $((n - 1)) > "$STUB/rows.$proj" ;;
      *pg_stat_user_tables*) echo "notes|$k|0|0" ;;
      *) echo "notes|$n" ;;
    esac ;;
esac
SH
chmod +x "$STUB/bin/docker"

# scenario NAME "ENV=..." COMMANDS: a clean stub, then the commands in the app's folder with the block loaded
scenario() {
  rm -f "$STUB"/log "$STUB"/up.* "$STUB"/rows.* "$STUB"/ins.* "$STUB"/seed "$STUB"/ran "$TMPD"/tmp/*; : > "$STUB/log"
  ( cd "$APPD" && env PATH="$STUB/bin:$PATH" STUB="$STUB" TMPDIR="$TMPD/tmp" $2 bash -c ". '$TMPD/block.sh'; $3" ) > "$TMPD/$1.out" 2>&1 || true
  cp "$STUB/log" "$TMPD/$1.log"
}
# the write step, as a script (Part B runs the write steps as one script inside wt_run); and one wired to the person's
printf '%s\n' 'env > "$TMPDIR/kept.env"' 'printf "%s\n" "INSERT INTO notes VALUES (1)" | docker compose exec -T db sh -c psql' > "$TMPD/write.sh"
printf '%s\n' 'printf "%s\n" "INSERT INTO notes VALUES (1)" | env -u COMPOSE_PROJECT_NAME docker compose exec -T db sh -c psql' > "$TMPD/wired.sh"
printf '%s\n' 'x() { printf "%s\n" "$1" | env -u COMPOSE_PROJECT_NAME docker compose exec -T db sh -c psql; }' 'x "INSERT INTO notes VALUES (1)"; x "DELETE FROM notes WHERE id = 1"' > "$TMPD/wired2.sh"
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
check "only variables whose name ends in PORT are offset: WORKERS (default 4) is left alone" \
  '! grep "^WORKERS=" "$TMPD/tmp/kept.env" >/dev/null && ! grep "WORKERS" "$TMPD/good.out" >/dev/null'
check "a copy left by a session that died is removed first: exactly the copy's project, never one with a longer name or the person's" \
  '[ "$(acts "$TMPD/good.log" | head -1 | grep -c -- "^$WT :: compose -p $WT .*down -v")" = 1 ] && [ -e "$STUB/up.${WT}2" ] && [ -e "$STUB/up.person-app" ]'
check "the copy is started with its own project, migrated by its start, and seeded on its own ports" \
  'grep -E "^$WT :: compose -p $WT .*up -d --build --wait" "$TMPD/good.log" >/dev/null && has "seed project=$WT frontend=$((3100 + OFF))" "$STUB/seed"'
check "every call that starts, stops or removes anything names the copy, never the person's project" 'only_copy "$TMPD/good.log"'
check "the copy is removed with its volume, and only the copy: down -v after up, nothing left, the env file gone" \
  '[ "$(acts "$TMPD/good.log" | tail -1 | grep -c -- "^$WT :: compose -p $WT .*down -v")" = 1 ] && [ ! -e "$STUB/up.$WT" ] && ! has ENVLEFT "$TMPD/good.out"'
check "the write step ran in the copy, and the person's counts are the same before and after" \
  '[ "$(cat "$STUB/rows.$WT" 2>/dev/null)" = 4 ] && [ ! -e "$STUB/rows.person-app" ] && has SAME "$TMPD/good.out"'
check "\"copy removed\" is said when the removal succeeded" 'has "copy removed: $WT" "$TMPD/good.out" && ! has "COPY LEFT" "$TMPD/good.out"'
scenario downfail "STUB_DOWN_FAIL=1" 'wt_run true; echo "run=$?"'
check "when the removal fails it says COPY LEFT with the copy's name, never \"copy removed\"" \
  'has "COPY LEFT: $WT" "$TMPD/downfail.out" && ! has "copy removed" "$TMPD/downfail.out"'

scenario wired "WS=$TMPD/wired.sh" "$FLOW"
check "a write step wired to the person's database fails the count guard" 'has DIFFERENT "$TMPD/wired.out" && ! has SAME "$TMPD/wired.out"'
scenario wired2 "WS=$TMPD/wired2.sh" "$FLOW"
check "a create-then-delete wired to the person's database nets zero rows and still fails the guard (the database's own counters moved)" \
  '[ "$(cat "$STUB/rows.person-app")" = 3 ] && has DIFFERENT "$TMPD/wired2.out" && ! has SAME "$TMPD/wired2.out"'

gone() { [ ! -e "$STUB/up.$WT" ] && only_copy "$TMPD/$1.log" && acts "$TMPD/$1.log" | tail -1 | grep -- "^$WT :: compose -p $WT .*down -v" >/dev/null; }
scenario upfail "STUB_UP_FAIL=1" 'wt_run touch "$STUB/ran"; echo "run=$?"; [ -e "$WTENV" ] && echo ENVLEFT'
check "a start that fails says NOT RUN with a reason, runs no write step, and removes the copy and its volume" \
  'has "NOT RUN: " "$TMPD/upfail.out" && has "run=1" "$TMPD/upfail.out" && [ ! -e "$STUB/ran" ] && ! has ENVLEFT "$TMPD/upfail.out" && gone upfail'

scenario testfail "X=1" 'wt_run bash -c "exit 3"; echo "run=$?"'
check "a write step that errors still removes the copy and its volume" 'has "run=3" "$TMPD/testfail.out" && gone testfail'

scenario timeout "WT_LIMIT=1" 'wt_run sleep 20; echo "run=$?"'
check "a write test that runs out of time is stopped, says NOT RUN, and the copy is removed" \
  'has "NOT RUN: the write test ran out of time" "$TMPD/timeout.out" && has "run=142" "$TMPD/timeout.out" && gone timeout'

# refused: every check runs first, so nothing is started and NO `down` is issued at all (down -v would remove a
# volume with a fixed name, whatever project it is given)
refused() { has "NOT RUN: $2" "$TMPD/$1.out" && has "run=1" "$TMPD/$1.out" && [ ! -e "$STUB/ran" ] && [ -z "$(acts "$TMPD/$1.log")" ] && ! has "$PW" "$TMPD/$1.out"; }
TRY='wt_run touch "$STUB/ran"; echo "run=$?"; wt_stop; echo "stop=$?"'
scenario fixed "STUB_FIXED=1" "$TRY"
check "refused, nothing started, no down: the database's volume has a fixed name (the copy would share it)" 'refused fixed "the copy would share your app'"'"'s storage"'
scenario bind "STUB_BIND=1" "$TRY"
check "refused, nothing started, no down: a folder on this computer is mounted into a service that isn't the database" 'refused bind "the copy would share your app'"'"'s storage"'
scenario outside "STUB_DBURL=postgresql://app:${PW}@prod-db.example.com:5432/app" "$TRY"
check "refused, nothing started, no down: DATABASE_URL points outside the copy; only the host is shown" \
  'refused outside "your settings point at prod-db.example.com, which is not part of this app'"'"'s own copy"'
scenario hostdb "STUB_DBURL=postgresql://app:${PW}@host.docker.internal:5432/app" "$TRY"
check "refused, nothing started, no down: DATABASE_URL points at the person's own machine" 'refused hostdb "your settings point at host.docker.internal, which"'
scenario split "STUB_DBHOST=10.0.0.7" "$TRY"
check "refused, nothing started, no down: a split DB_HOST points outside the copy" 'refused split "your settings point at 10.0.0.7, which"'
scenario nodocker "STUB_NO_DOCKER=1" "$TRY"
check "refused, nothing started, no down: Docker isn't running" 'refused nodocker "Docker isn"'

# stack-check.py itself: sc MODE '{"NAME": "value", ...}' -> the backend's settings in a copy that publishes port 5900
sc() { python3 -I -c 'import json, sys; print(json.dumps({"name": "copy", "volumes": {"d": {"name": "copy_d"}}, "services": {"db": {}, "cache": {}, "backend": {"environment": json.loads(sys.argv[1]), "ports": [{"published": "5900", "target": 3000}]}}}))' "$2" | python3 -I "$SC" $1; }
yes_() { [ -z "$(sc "$1" "$2")" ]; }                                   # allowed: exit 0, nothing printed
no_() { local o; o="$(sc "$1" "$2")" && return 1; printf '%s' "$o" | grep -F -- "$3" >/dev/null && ! printf '%s' "$o" | grep -F "$PW" >/dev/null; }
check "stack-check copy: the copy's own services, its own published port, a file database, a bind address and a path are allowed" \
  'yes_ "copy copy" "{\"DATABASE_URL\": \"postgresql://u:${PW}@db:5432/x\", \"REDIS_URL\": \"redis://cache:6379/0\", \"FRONTEND_URL\": \"http://localhost:5900\", \"SQLITE_URL\": \"sqlite:///./a.db\", \"HOST\": \"0.0.0.0\", \"API_URL\": \"/api\", \"DB_HOST\": \"db\", \"EMPTY_URL\": \"\"}"'
check "stack-check copy: an outside database host is refused, and only the host is printed" \
  'no_ "copy copy" "{\"DATABASE_URL\": \"postgresql://u:${PW}@prod-db.example.com:5432/x\"}" "your settings point at prod-db.example.com, which is not part of this app'"'"'s own copy"'
check "stack-check copy: localhost, 127.0.0.1 and host.docker.internal are the person's own machine: refused" \
  'no_ "copy copy" "{\"DATABASE_URL\": \"postgresql://u:${PW}@localhost:5432/x\"}" "point at localhost" && no_ "copy copy" "{\"REDIS_URL\": \"redis://127.0.0.1:6379\"}" "point at 127.0.0.1" && no_ "copy copy" "{\"DATABASE_URL\": \"mysql://u:${PW}@host.docker.internal/x\"}" "point at host.docker.internal"'
check "stack-check copy: split forms (a HOST variable, a host=... string), a queue, a storage address and any other outside service are refused" \
  'no_ "copy copy" "{\"DB_HOST\": \"prod-db.internal\", \"DB_PORT\": \"5432\"}" "point at prod-db.internal" && no_ "copy copy" "{\"DATABASE_DSN\": \"host=pg.corp dbname=x password=${PW}\"}" "point at pg.corp" && no_ "copy copy" "{\"AMQP_URL\": \"amqp://u:${PW}@mq.corp\"}" "point at mq.corp" && no_ "copy copy" "{\"S3_ENDPOINT\": \"https://s3.amazonaws.com\"}" "point at s3.amazonaws.com"'
check "stack-check copy: an address that can't be read, or settings that can't be read, are refused" \
  'no_ "copy copy" "{\"DATABASE_URL\": \"${PW} not an address\"}" "DATABASE_URL" && ! printf "not json" | python3 -I "$SC" copy copy >/dev/null && ! python3 -I "$SC" copy copy </dev/null >/dev/null'
check "stack-check local (the rule /resume-it's live pass uses): this machine and compose services pass, an outside database is refused, an outside web API is not its business" \
  'yes_ local "{\"DATABASE_URL\": \"postgresql://u:${PW}@localhost:5432/x\", \"REDIS_URL\": \"redis://cache\", \"AI_URL\": \"https://api.example.com\"}" && no_ local "{\"DATABASE_URL\": \"postgresql://u:${PW}@prod-db.example.com/x\"}" "your settings point at prod-db.example.com"'
# a URL in .env and a URL in the Compose file itself: what `docker compose config` gives stack-check (needs the docker CLI only)
if docker compose version >/dev/null 2>&1; then
  for where in env file; do
    d="$TMPD/real-$where"; mkdir -p "$d"
    if [ "$where" = env ]; then v='${DATABASE_URL}'; echo "DATABASE_URL=postgresql://u:${PW}@prod-db.example.com:5432/x" > "$d/.env"; else v="postgresql://u:${PW}@prod-db.example.com:5432/x"; fi
    printf '%s\n' 'services:' '  db: {image: postgres}' '  backend:' '    image: busybox' '    environment:' "      DATABASE_URL: \"$v\"" > "$d/docker-compose.yml"
    ( cd "$d" && docker compose -p copy config --format json 2>/dev/null | python3 -I "$SC" copy copy ) > "$TMPD/real-$where.out" 2>&1 || true
  done
  check "stack-check copy on real \`docker compose config\`: an outside DATABASE_URL set in .env, or in the Compose file, is refused" \
    'has "your settings point at prod-db.example.com" "$TMPD/real-env.out" && has "your settings point at prod-db.example.com" "$TMPD/real-file.out" && ! has "$PW" "$TMPD/real-env.out"'
else
  echo "skip the .env / Compose-file case: no docker CLI here"
fi

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
    'opp "s/\n  if wt_stop >\/dev\/null 2>&1; then echo \"copy removed/\n  if true; then echo \"copy removed/" "the copy is removed with its volume, and only the copy"'
  check "(control) the trap removed: a killed run leaves the copy" \
    'opp "s/\n *trap \x27kill[^\n]*INT TERM HUP\n/\n/" "killed in the middle of the write steps"'
  check "(control) the time limit removed: a stuck write test never ends" \
    'opp "s/alarm shift; exec \@ARGV/shift; exec \@ARGV/" "a write test that runs out of time"'
  check "(control) the storage and address check no longer refuses: a copy that connects outside is started" \
    'opp "s/\n    \|\| \{ echo \"NOT RUN: \\\$\{why:-[^\n]*return 1; \}\n/\n    || true\n/" "refused, nothing started, no down: DATABASE_URL points outside the copy"'
  check "(control) wt_stop no longer waits for the checks: a refused copy still gets down -v" \
    'opp "s/wt_stop\(\) \{ \[ -n \"\\\$wt_ok\" \] && /wt_stop() { /" "refused, nothing started, no down: the database'"'"'s volume has a fixed name"'
  check "(control) every numeric default offset again: WORKERS becomes a port number" \
    'opp "s/\[A-Z0-9_\]\*PORT:-/[A-Z0-9_]+:-/" "only variables whose name ends in PORT are offset"'
  check "(control) the counters dropped from count: a create-then-delete passes the guard" \
    'opp "s/; printf [^\n]*pg_stat_user_tables[^\n]*\| q; \}/; }/" "a create-then-delete wired to the person"'
  check "(control) \"copy removed\" said whatever the removal did" \
    'opp "s/if wt_stop >\/dev\/null 2>&1; then echo \"copy removed: \\\$WT\"; else echo \"COPY LEFT: \\\$WT\"; fi/wt_stop >\/dev\/null 2>&1; echo \"copy removed: \\\$WT\"/" "when the removal fails it says COPY LEFT"'
  check "(control) the fresh-database path back: a new build writes to the app's own database" \
    'opp "s/(\n22\. \*\*Build and start containers:\*\*\n)/\$1    Prints fresh-db: yes when the database is new.\n/" "a brand-new build has no other path"'
  check "(control) the old sweep back in step 26 a" \
    'opp "s/(\n    b\. Verify 2xx response)/\n       sweep() { del x; }\$1/" "nothing in Part B cleans up a database"'
fi

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
