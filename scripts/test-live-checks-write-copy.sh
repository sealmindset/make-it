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
#   - every check runs BEFORE anything is started or removed: a refused copy starts nothing and issues no `down`
#     at all (`down -v` removes a volume with a fixed name whatever project it is given); the only Docker calls a
#     refusal makes are the two that read: `info` and `compose config`;
#   - the copy is used only on a set-up make-it's BUILD PRODUCES (the owner's calls, 2026-11-24): an allow-list in
#     .claude/make-it/scripts/stack-check.py, not a list of unsafe shapes. The scaffolds' services and the mock
#     services the build generates (mock-<name>, dev profile, built from ./mock-services/mock-<name>), using only
#     the options those use; one project-scoped network; project-scoped volumes; no folder of this computer
#     mounted; the address settings the scaffolds know, each read for certain and pointing at the copy's own
#     services or its own published port; any other setting that holds an address only when it points at a
#     generated mock; no cloud storage named by keys. Anything else is refused with one plain sentence: the first
#     reason, a host or a setting's NAME at most, never a value;
#   - the copy is started with every AI-provider address and key setting EMPTIED, so a set AI key or address never
#     refuses an app, and the copy can never call a paid or outside AI service;
#   - the skill's OWN blocks (make-it's wt_check, /resume-it's settings line) read the configuration with the
#     profile the build starts the app with: without it the one-service scaffold's configuration can't be read;
#   - the stock list, through the skill's own wt_check on real `docker compose config`: both scaffolds as generated,
#     a scripts/worktree.sh copy, the PWA overlay, an AI app with a key set, a file-upload app, an app with
#     integration and logging mocks, the foundry provider, ollama: every one is used;
#     the allow-list's sets are exactly what the scaffolds' own files define;
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
SC="${STACK_CHECK:-$root/.claude/make-it/scripts/stack-check.py}"   # STACK_CHECK, RESUME_MD: changed copies, for the controls
RS="${RESUME_MD:-$root/.claude/commands/resume-it.md}"
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
  | sed "s#\$HOME/.claude/make-it/scripts/stack-check.py#$SC#g" > "$TMPD/block.sh" || true
awk '/^2\. \*\*Only when it can start here/{on=1} /^3\. /{on=0} '"$fence" "$RS" \
  | sed "s#\$HOME/.claude/make-it/scripts/stack-check.py#$SC#g" > "$TMPD/rsblock.sh" || true
# the profile the build starts the app with (make-it step 22, /resume-it step 3): the blocks must read with the same one
P22="$(awk '/^22\. \*\*Build and start/{on=1} /^22b\. /{on=0} on' "$MK" | sed -n 's/.*docker compose \(--profile [a-z]*\) up -d.*/\1/p' | head -1)"
P3="$(awk '/^3\. \*\*Start it/{on=1} /^4\. /{on=0} on' "$RS" | sed -n 's/.*docker compose \(--profile [a-z]*\) up -d.*/\1/p' | head -1)"
check "the blocks read and start the stack with the profile the build starts the app with (make-it step 22, /resume-it step 3)" \
  '[ -n "$P22" ] && [ -n "$P3" ] && ! grep -E "docker compose .*\b(config|up|down)\b" "$TMPD/block.sh" | grep -v -- "$P22 " >/dev/null && [ -s "$TMPD/rsblock.sh" ] && ! grep "docker compose" "$TMPD/rsblock.sh" | grep -v -- "$P3 config" >/dev/null'
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
# STUB_REAL=<the real docker>: `compose ... config` is the real, parse-only one; everything else stays recorded
if [ -n "${STUB_REAL:-}" ]; then case " $* " in *" config "*) exec "$STUB_REAL" "$@" ;; *" info "*) exit 0 ;; esac; fi
# as the one-service scaffold does: without the dev profile the app depends on a service that isn't there
case " $* " in *" config "*) case " $* " in *" --profile dev "*) ;; *) echo 'service "app" depends on undefined service "mock-oidc"' >&2; exit 1 ;; esac ;; esac
case " $* " in
  *" info "*) ;;
  *" volume ls "*) cat "$STUB/volumes" 2>/dev/null || true ;;
  *" config --format json "*) python3 -I - "$proj" <<'PY'
# make-it's standard set-up (the fastapi-nextjs scaffold's shape), then one change when STUB_CASE names it
import json, os, sys
p, e = sys.argv[1], os.environ.get
fp, bp, dp, case, pw = e("FRONTEND_PORT", "3100"), e("BACKEND_PORT", "8100"), e("DB_PORT", "5532"), e("STUB_CASE", ""), e("PW", "")
net = {"app-network": None}
benv = {"DATABASE_URL": "postgresql+asyncpg://app:" + pw + "@db:5432/app", "FRONTEND_URL": "http://localhost:" + fp,
        "BACKEND_URL": "http://localhost:" + bp, "OIDC_ISSUER_URL": "http://mock-oidc:10090", "TRUSTED_PROXIES": "frontend",
        "CRIBL_STREAM_URL": "", "WORKERS": e("WORKERS", "4"), "JWT_SECRET": pw}
c = {"name": p, "networks": {"app-network": {"name": p + "_app-network"}}, "volumes": {"postgres_data": {"name": p + "_postgres_data"}},
     "services": {"frontend": {"networks": dict(net), "ports": [{"published": fp, "target": 3000}], "environment": {"BACKEND_INTERNAL_URL": "http://backend:8000"}},
                  "backend": {"networks": dict(net), "ports": [{"published": bp, "target": 8000}], "environment": benv},
                  "mock-oidc": {"networks": dict(net)},
                  "db": {"networks": dict(net), "ports": [{"published": dp, "target": 5432}], "volumes": [{"type": "volume", "source": "postgres_data", "target": "/var/lib/postgresql/data"}]}}}
b = c["services"]["backend"]
# what a build adds that the bare scaffold doesn't have: plain settings of its own
benv.update(AI_PROVIDER="claude_agent", AI_MODEL_HEAVY="claude-sonnet-4-20250514", DOCUMENTS_PATH="/app/data/documents", AI_ALLOWED_MODELS="a,b")
def setting(n, person):   # as Compose resolves ${NAME:-}: the caller's environment wins, even when empty; else the person's .env
    return os.environ[n] if n in os.environ else person
def mock(n, port): return {"networks": dict(net), "profiles": ["dev"], "build": {"context": "/apps/My App/mock-services/" + n, "dockerfile": "Dockerfile"}, "ports": [{"published": port, "target": int(port)}]}
if case == "aikey": benv["ANTHROPIC_API_KEY"] = setting("ANTHROPIC_API_KEY", pw)
if case == "foundry": benv.update(AI_PROVIDER="anthropic_foundry", AZURE_AI_FOUNDRY_ENDPOINT=setting("AZURE_AI_FOUNDRY_ENDPOINT", "https://team.services.ai.azure.com"), AZURE_AI_FOUNDRY_API_KEY=setting("AZURE_AI_FOUNDRY_API_KEY", pw))
if case == "ollama": benv.update(AI_PROVIDER="ollama", OLLAMA_BASE_URL=setting("OLLAMA_BASE_URL", "http://host.docker.internal:11434"))
if case == "ailiteral": benv["OLLAMA_BASE_URL"] = "http://host.docker.internal:11434"
if case == "mocks":
    c["services"].update({"mock-jira": mock("mock-jira", "8443"), "mock-cribl": mock("mock-cribl", "3005")})
    benv.update(JIRA_BASE_URL="http://mock-jira:8443", JIRA_AUTH_TOKEN="mock-jira-token", CRIBL_STREAM_URL="http://mock-cribl:3005")
if case == "upload":
    c["volumes"]["documents_data"] = {"name": p + "_documents_data"}; b["volumes"] = [{"type": "volume", "source": "documents_data", "target": "/app/data/documents"}]
if case == "fakemock": c["services"]["mock-backdoor"] = {"networks": dict(net), "image": "busybox"}
if case == "volfrom": b["volumes_from"] = ["db"]
if case == "privileged": b["privileged"] = True
if case == "hostlike": benv["REDIS"] = "cache.example.com:6379"
if case == "mongo": benv["MONGO_HOSTS"] = "a.example.com,b.example.com"
if case == "addsvc": c["services"]["worker"] = {"networks": dict(net)}
if case == "extnet": c["networks"]["app-network"] = {"name": "corp-net", "external": True}
if case == "fixednet": c["networks"]["app-network"] = {"name": "shared-net"}
if case == "extranet": c["networks"]["other"] = {"name": p + "_other"}; b["networks"]["other"] = None
if case == "hostmode": b["network_mode"] = "host"
if case == "extrahosts": b["extra_hosts"] = ["db.internal=10.0.0.5"]
if case == "extvol": c["volumes"]["postgres_data"] = {"name": "pgdata", "external": True}
if case == "fixedvol": c["volumes"]["postgres_data"] = {"name": "fixed_data"}
if case == "bind": b["volumes"] = [{"type": "bind", "source": "/Users/someone/uploads", "target": "/app/uploads"}]
if case == "knownout": benv["DATABASE_URL"] = "postgresql://app:" + pw + "@prod-db.example.com:5432/app"
if case == "hostdb": benv["DATABASE_URL"] = "postgresql://app:" + pw + "@host.docker.internal:5432/app"
if case == "unknown": benv["REDIS_URL"] = "redis://db:6379/0"
if case == "unparse1": benv["DATABASE_URL"] = "redis://:" + pw[:4] + "," + pw[4:] + "@cache.example.com"
if case == "unparse2": benv["DATABASE_URL"] = "postgresql://app:" + pw[:4] + "/" + pw[4:] + "@db:5432/app"
if case == "cloud": benv.update(S3_BUCKET="team-files", AWS_ACCESS_KEY_ID=pw.upper(), AWS_SECRET_ACCESS_KEY=pw)
print(json.dumps(c))
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

# not standard: every check runs first, so nothing is started and nothing removed. The only Docker calls are the two
# that read (`info`, `compose config`): no `up`, and no `down` at all, even from a wt_stop afterwards.
SAID="your app's set-up isn't one make-it's build produces"
SO="so I did not run the test that creates, changes and deletes a record"
reads_only() { ! grep -v -E ' :: (info|compose( -p [^ ]+)?( --profile dev)? config( --format json)?)$' "$1" >/dev/null; }
notstd() {  # notstd CASE REASON: the one sentence with this reason; nothing started or removed; nothing of a value shown
  scenario "$1" "STUB_CASE=$1" 'wt_run touch "$STUB/ran"; echo "run=$?"; wt_stop; echo "stop=$?"'
  has "NOT RUN: $SAID ($2), $SO" "$TMPD/$1.out" && [ "$(grep -c "NOT RUN" "$TMPD/$1.out")" = 1 ] && has "run=1" "$TMPD/$1.out" && has "stop=1" "$TMPD/$1.out" \
    && [ ! -e "$STUB/ran" ] && reads_only "$TMPD/$1.log" && ! has "$PW" "$TMPD/$1.out" && ! has "${PW%?????}" "$TMPD/$1.out" && ! has "${PW#????}" "$TMPD/$1.out"
}
check "not standard: a service make-it's build doesn't produce" 'notstd addsvc "it has a service make-it'"'"'s build doesn'"'"'t produce: worker"'
check "not standard: a service named mock-... that isn't one the build generates (no dev profile, not built from ./mock-services)" \
  'notstd fakemock "it has a service make-it'"'"'s build doesn'"'"'t produce: mock-backdoor"'
check "not standard: a service option the build doesn't use (volumes_from)" 'notstd volfrom "its backend service sets volumes_from"'
check "not standard: a service option the build doesn't use (privileged)" 'notstd privileged "its backend service sets privileged"'
check "not standard: a setting the build doesn't produce whose value names another machine (REDIS=host:port); the name only is shown" \
  'notstd hostlike "it has a setting make-it'"'"'s build doesn'"'"'t produce that holds an address: REDIS" && ! has "example.com" "$TMPD/hostlike.out"'
check "not standard: a setting the build doesn't produce that lists hosts (MONGO_HOSTS)" 'notstd mongo "it has a setting make-it'"'"'s build doesn'"'"'t produce that holds an address: MONGO_HOSTS"'
check "not standard: an AI provider address written into the Compose file, so the copy can't empty it" 'notstd ailiteral "its AI provider setting OLLAMA_BASE_URL can'"'"'t be emptied for the copy"'
check "not standard: an external network" 'notstd extnet "it uses an outside network"'
check "not standard: a network with a fixed name" 'notstd fixednet "it uses an outside network"'
check "not standard: an extra network on one service" 'notstd extranet "it uses more than one network"'
check "not standard: network_mode: host" 'notstd hostmode "its backend service sets network_mode"'
check "not standard: extra_hosts" 'notstd extrahosts "its backend service sets extra_hosts"'
check "not standard: an external volume" 'notstd extvol "it keeps data in a volume that is not the app'"'"'s own"'
check "not standard: a volume with a fixed name (down -v would remove it by that name)" 'notstd fixedvol "it keeps data in a volume that is not the app'"'"'s own"'
check "not standard: a folder of this computer mounted into a service" 'notstd bind "a folder of this computer is mounted into its backend service"'
check "not standard: a known address setting pointing outside; only the host is shown" 'notstd knownout "DATABASE_URL points at prod-db.example.com, outside the app"'
check "not standard: a known address setting pointing at the person's own machine" 'notstd hostdb "DATABASE_URL points at host.docker.internal, outside the app"'
check "not standard: an address setting make-it's build doesn't produce, even one that names the copy's own database" 'notstd unknown "it has a setting make-it'"'"'s build doesn'"'"'t produce that holds an address: REDIS_URL"'
check "not standard: an address that can't be read for certain (a comma in the password part); nothing of it is shown" \
  'notstd unparse1 "the address in DATABASE_URL can'"'"'t be read for certain" && ! has "example.com" "$TMPD/unparse1.out"'
check "not standard: an address that can't be read for certain (a slash in the password part); nothing of it is shown" 'notstd unparse2 "the address in DATABASE_URL can'"'"'t be read for certain"'
check "not standard: cloud storage named by a bucket and keys" 'notstd cloud "it names cloud storage or an outside service by its keys: S3_BUCKET"'
# what make-it's build produces is used (stub): its plain settings, its mocks, a file-upload volume, and an AI
# provider's key or address, which the copy empties
AI_NAMES="$(python3 -I "$SC" ai-settings 2>/dev/null | tr '\n' ' ')"
emptied() { [ -n "$AI_NAMES" ] && for n in $AI_NAMES; do grep -x "$n=" "$1" >/dev/null || return 1; done; }
used() {  # used CASE: the write steps ran in the copy, the copy was removed, and every AI-provider setting was empty in it
  scenario "$1" "STUB_CASE=$1 WS=$TMPD/write.sh" 'wt_run bash "$WS"; echo "run=$?"'
  has "run=0" "$TMPD/$1.out" && ! has "NOT RUN" "$TMPD/$1.out" && has "copy removed: $WT" "$TMPD/$1.out" && [ "$(cat "$STUB/rows.$WT" 2>/dev/null)" = 4 ] && emptied "$TMPD/tmp/kept.env"
}
check "stack-check.py names the AI-provider address and key settings the copy empties (eight of them)" '[ "$(printf "%s\n" $AI_NAMES | wc -l | tr -d " ")" = 8 ]'
check "used: an AI app with a key set (the copy runs with it emptied)" 'used aikey'
check "used: an app set to the foundry provider, its address and key set (emptied in the copy)" 'used foundry'
check "used: an app set to ollama, its address set (emptied in the copy)" 'used ollama'
check "used: an app with the integration and logging mocks the build generates, and their address settings" 'used mocks'
check "used: a file-upload app with its own named volume" 'used upload'
( cd "$APPD" && env PATH="$STUB/bin:$PATH" STUB="$STUB" bash "$TMPD/rsblock.sh" ) > "$TMPD/rs.out" 2>&1 && echo "rc=0" >> "$TMPD/rs.out" || echo "rc=1" >> "$TMPD/rs.out"
check "/resume-it's own settings line reads the configuration (with the profile) and passes a build's set-up" '[ "$(cat "$TMPD/rs.out")" = "rc=0" ]'

scenario nodocker "STUB_NO_DOCKER=1" 'wt_run touch "$STUB/ran"; echo "run=$?"; wt_stop; echo "stop=$?"'
check "Docker isn't running: NOT RUN, nothing started or removed" 'has "NOT RUN: Docker isn" "$TMPD/nodocker.out" && has "run=1" "$TMPD/nodocker.out" && [ -z "$(acts "$TMPD/nodocker.log")" ]'

# stack-check.py's other caller: /resume-it's live pass, `local` mode, unchanged
sc() { python3 -I -c 'import json, sys; print(json.dumps({"name": "x", "services": {"db": {}, "cache": {}, "backend": {"environment": json.loads(sys.argv[1])}}}))' "$2" | python3 -I "$SC" $1; }
LOCAL_OK="{\"DATABASE_URL\": \"postgresql://u:${PW}@localhost:5432/x\", \"REDIS_URL\": \"redis://cache\", \"AI_URL\": \"https://api.example.com\"}"
LOCAL_OUT="{\"DATABASE_URL\": \"postgresql://u:${PW}@prod-db.example.com/x\"}"
check "stack-check local (/resume-it's rule, unchanged): this machine and compose services pass, an outside database is refused with its host only, an outside web API is not its business" \
  'o="$(sc local "$LOCAL_OK")" && [ -z "$o" ] && o="$(sc local "$LOCAL_OUT" || true)" && [ "$o" = "your settings point at prod-db.example.com" ]'
check "stack-check copy: settings that can't be read at all are not standard" \
  '! printf "not json" | python3 -I "$SC" copy x >/dev/null && ! python3 -I "$SC" copy x </dev/null >/dev/null'

# the allow-list is what the scaffolds' own files define: services, folders they bind, address settings
python3 -I - "$SC" "$root/.claude/make-it/scaffolds" "$MK" <<'PY' || fail=1
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("stack_check", sys.argv[1]); sc = importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)
services, binds, names, allpairs = set(), set(), set(), []
for s in ("fastapi-nextjs", "nextjs-fullstack"):
    comp = [l for l in open(f"{sys.argv[2]}/{s}/docker-compose.yml", encoding="utf-8").read().splitlines() if not l.lstrip().startswith("#")]
    a = comp.index("services:"); b = next(n for n in range(a + 1, len(comp)) if re.match(r"[a-z]", comp[n]))
    services |= {m.group(1) for l in comp[a:b] if (m := re.fullmatch(r"  ([a-z][a-z0-9-]*):", l))}
    binds |= {m.group(1) for l in comp if (m := re.fullmatch(r"\s+- [\"']?(?:\.|/|~)[^:]*:([^:\"']+).*", l)) and "=" not in l}
    pairs = [m.groups() for l in comp if (m := re.fullmatch(r"\s+- ([A-Z0-9_]+)=(.*)", l))]
    pairs += [m.groups() for l in open(f"{sys.argv[2]}/{s}/.env.example", encoding="utf-8").read().splitlines() if (m := re.fullmatch(r"([A-Z0-9_]+)=(.*)", l))]
    names |= {n for n, v in pairs if sc.ADDRESS_NAME.search(n) or "://" in v}; allpairs += pairs
ok = True
plain = {n for n, v in allpairs} - names
cfgpy = open(f"{sys.argv[2]}/fastapi-nextjs/backend/app/config.py", encoding="utf-8").read()
ai = set(re.findall(r"^    ([A-Z0-9_]+(?:ENDPOINT|BASE_URL|API_KEY|TOKEN)): str", cfgpy[cfgpy.index("# AI Provider"):cfgpy.index("# AI Safety")], re.M))
mk = open(sys.argv[3], encoding="utf-8").read()
m = re.search(r'"The AI address unreachable" means(.*?)instead\.', mk, re.S)
ai |= set(re.findall(r"`([A-Z0-9_]+(?:ENDPOINT|BASE_URL|TOKEN))=?`", m.group(1) if m else ""))
for what, got, want in (("services", sc.SCAFFOLD_SERVICES, services), ("folders the scaffolds bind", sc.SCAFFOLD_BINDS, binds), ("address settings", sc.KNOWN_ADDRESSES, names),
                        ("other settings", sc.SCAFFOLD_PLAIN, plain), ("AI-provider address and key settings (config.py, and the ones make-it.md names)", sc.AI_SETTINGS, ai)):
    same = set(got) == want
    print(("ok   " if same else "FAIL ") + f"the allow-list's {what} are exactly what both scaffolds' files define")
    if not same: ok = False; print("  allow-list only: " + " ".join(sorted(set(got) - want)) + " | scaffolds only: " + " ".join(sorted(want - set(got))))
sys.exit(0 if ok else 1)
PY

# both stock scaffolds, as generated, and a copy made by scripts/worktree.sh: all standard (real `docker compose config`;
# it needs the docker CLI, not a running Docker)
# The stock list, through the skill's OWN blocks, on real `docker compose config` (it needs the docker CLI, not a
# running Docker: only `config` goes to the real docker, everything else stays the recording stub).
if [ -n "${1:-}" ]; then :   # a control's child run: the stub cases above are what it is for
elif docker compose version >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  REAL="$(command -v docker)"
  inst() {  # inst SCAFFOLD DIR: the scaffold with its placeholders filled, and its .env from .env.example
    mkdir -p "$2"; cp -R "$root/.claude/make-it/scaffolds/$1/." "$2"
    ( cd "$2" && sed -i.bak -e 's/\[APP_SLUG\]/stock-app/g' -e 's/\[APP_NAME\]/Stock App/g' -e 's/\[FRONTEND_PORT\]/3100/g' -e 's/\[APP_PORT\]/3100/g' \
        -e 's/\[BACKEND_PORT\]/8100/g' -e 's/\[DB_PORT\]/5500/g' -e 's/\[MOCK_OIDC_PORT\]/10190/g' docker-compose.yml .env.example scripts/*.sh && rm -f ./*.bak scripts/*.bak && cp .env.example .env )
  }
  # vary DIR KIND: what the build adds to the fastapi-nextjs scaffold for that kind of app (its Compose file and .env)
  vary() { python3 -I - "$1" "$2" "$PW" <<'PY'
import sys
d, kind, pw = sys.argv[1:4]
c = open(d + "/docker-compose.yml", encoding="utf-8").read(); env = ""
def put(marker, text):
    global c
    assert c.count(marker) == 1, marker; c = c.replace(marker, text + marker)
AI = "".join(f"      - {n}=${{{n}:-}}\n" for n in ("AI_PROVIDER", "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "AZURE_AI_FOUNDRY_ENDPOINT", "AZURE_AI_FOUNDRY_API_KEY", "OLLAMA_BASE_URL")) \
     + "      - AI_MODEL_HEAVY=claude-sonnet-4-20250514\n      - AI_ALLOWED_MODELS=claude-sonnet-4-20250514,claude-haiku-4-5-20251001\n"
URLS = "      # [ADDITIONAL_SERVICE_URLS]\n"
if kind in ("aikey", "foundry", "ollama"): put(URLS, AI)
if kind == "aikey": env = f"AI_PROVIDER=anthropic\nANTHROPIC_API_KEY={pw}\n"
if kind == "foundry": env = f"AI_PROVIDER=anthropic_foundry\nAZURE_AI_FOUNDRY_ENDPOINT=https://team.services.ai.azure.com\nAZURE_AI_FOUNDRY_API_KEY={pw}\n"
if kind == "ollama": env = "AI_PROVIDER=ollama\nOLLAMA_BASE_URL=http://host.docker.internal:11434\n"
if kind == "upload":
    put(URLS, "      - DOCUMENTS_PATH=/app/data/documents\n      - UPLOAD_CACHE_PATH=/app/data/cache\n")
    a = c.index("\n  backend:"); h = c.index("\n    healthcheck:", a)
    c = c[:h] + "\n    volumes:\n      - documents_data:/app/data/documents" + c[h:]
    c = c.replace("\nvolumes:\n  postgres_data:\n", "\nvolumes:\n  postgres_data:\n  documents_data:\n")
if kind == "mocks":
    put(URLS, "      - JIRA_BASE_URL=http://mock-jira:8443\n      - JIRA_AUTH_TOKEN=mock-jira-token\n      - CRIBL_STREAM_URL=http://mock-cribl:3005\n")
    mock = lambda n, port: (f"  {n}:\n    build:\n      context: ./mock-services/{n}\n      dockerfile: Dockerfile\n    ports:\n      - \"{port}:{port}\"\n"
                            f"    profiles:\n      - dev\n    healthcheck:\n      test: [\"CMD\", \"wget\", \"--spider\", \"http://127.0.0.1:{port}/health\"]\n    networks:\n      - app-network\n\n")
    put("  # [ADDITIONAL_MOCK_SERVICES]\n", mock("mock-jira", 8443) + mock("mock-cribl", 3005))
open(d + "/docker-compose.yml", "w", encoding="utf-8").write(c)
if env: open(d + "/.env", "a", encoding="utf-8").write(env)
PY
  }
  # own DIR: make-it's own wt_check there says the copy may be used, with every AI setting emptied for it; and
  # /resume-it's own settings line passes. Nothing is started: `up` and `down` never appear.
  own() {
    : > "$STUB/log"
    ( cd "$1" && env PATH="$STUB/bin:$PATH" STUB="$STUB" STUB_REAL="$REAL" TMPDIR="$TMPD/tmp" bash -c ". '$TMPD/block.sh'; wt_check; echo \"check=\$?\"; cat \"\$WTENV\"" ) > "$TMPD/own.out" 2>&1
    ( cd "$1" && env PATH="$STUB/bin:$PATH" STUB="$STUB" STUB_REAL="$REAL" bash "$TMPD/rsblock.sh" ) > "$TMPD/ownrs.out" 2>&1 && echo "rc=0" >> "$TMPD/ownrs.out" || echo "rc=1" >> "$TMPD/ownrs.out"
    has "check=0" "$TMPD/own.out" && ! has "NOT RUN" "$TMPD/own.out" && [ -z "$(acts "$STUB/log")" ] && [ "$(cat "$TMPD/ownrs.out")" = "rc=0" ] \
      && for n in $AI_NAMES; do grep -x "export $n=" "$TMPD/own.out" >/dev/null || return 1; done
  }
  why() { { grep -h "NOT RUN\|check=" "$TMPD/own.out"; cat "$TMPD/ownrs.out"; } | cut -c1-220; false; }
  inst fastapi-nextjs "$TMPD/stock-app"; inst nextjs-fullstack "$TMPD/stock-full"
  check "stock, used: the fastapi-nextjs scaffold as generated (make-it's wt_check and /resume-it's line, both)" 'own "$TMPD/stock-app" || why'
  check "stock, used: the nextjs-fullstack scaffold as generated (its sign-in service exists only in the dev profile)" 'own "$TMPD/stock-full" || why'
  ( cd "$TMPD/stock-app" && git init -q -b main . && git add -A >/dev/null 2>&1 && git -c user.name=t -c user.email=t@example.invalid commit -q --no-gpg-sign -m stock >/dev/null 2>&1 \
      && bash scripts/worktree.sh new feat/try >/dev/null 2>&1 ) || true
  WTC="$TMPD/stock-app-worktrees/feat_try"
  check "stock, used: a copy made by the scaffold's scripts/worktree.sh (its own project name and offset ports)" \
    '[ -f "$WTC/.env" ] && grep "^COMPOSE_PROJECT_NAME=stock-app-feat_try" "$WTC/.env" >/dev/null && { own "$WTC" || why; }'
  inst fastapi-nextjs "$TMPD/stock-pwa"; cp -R "$root/.claude/make-it/scaffolds/overlays/pwa/." "$TMPD/stock-pwa/"
  check "stock, used: the PWA overlay on the scaffold" 'own "$TMPD/stock-pwa" || why'
  for k in aikey upload mocks foundry ollama; do inst fastapi-nextjs "$TMPD/stock-$k"; vary "$TMPD/stock-$k" "$k"; done
  check "stock, used: an AI app with a key set in .env" 'own "$TMPD/stock-aikey" || why'
  check "stock, used: a file-upload app with its named volume" 'own "$TMPD/stock-upload" || why'
  check "stock, used: an app with integration and logging mocks (mock-jira, mock-cribl)" 'own "$TMPD/stock-mocks" || why'
  check "stock, used: an app set to the foundry provider, address and key set in .env" 'own "$TMPD/stock-foundry" || why'
  check "stock, used: an app set to ollama, its address set in .env" 'own "$TMPD/stock-ollama" || why'
  # the service options the allow-list has are the ones the scaffolds' resolved configurations use
  keys="$( for d in stock-app stock-full stock-mocks stock-upload; do ( cd "$TMPD/$d" && docker compose --profile dev config --format json 2>/dev/null ); done \
    | python3 -I -c 'import json, sys
dec, s, i, ks = json.JSONDecoder(), sys.stdin.read(), 0, set()
while i < len(s):
    while i < len(s) and s[i].isspace(): i += 1
    if i >= len(s): break
    c, i = dec.raw_decode(s, i)
    for svc in c["services"].values(): ks |= {k for k, v in svc.items() if v}
print(" ".join(sorted(ks)))' )"
  check "the allow-list's service options are exactly the ones the scaffolds and the build's generated services use" \
    '[ "$keys" = "$(python3 -I -c "import importlib.util as u, sys; s = u.spec_from_file_location(\"sc\", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m); print(\" \".join(sorted(m.SERVICE_KEYS)))" "$SC")" ] || { echo "  real: $keys"; false; }'
else
  echo "skip the stock list on real docker compose config: no docker CLI or git here (the stub cases above still ran)"
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
  check "(control) the standard-set-up check no longer refuses: a copy that connects outside is started" \
    'opp "s/\n    \|\| \{ echo \"NOT RUN: [^\n]*return 1; \}\n/\n    || true\n/" "not standard: a known address setting pointing outside"'
  # opp2 PERL REASON: stack-check.py with one edit must fail this script on the check named REASON
  opp2() {
    cp "$SC" "$TMPD/sc.py"; perl -0pi -e "$1" "$TMPD/sc.py"; ! cmp -s "$SC" "$TMPD/sc.py" || return 1
    local out; out="$(STACK_CHECK="$TMPD/sc.py" bash "$SELF" "$MK" 2>&1)" && return 1
    printf '%s\n' "$out" | grep -F "FAIL $2" >/dev/null
  }
  check "(control) the network check removed: an outside network passes" 'opp2 "s/\n *check_networks\(cfg, services, project\)\n/\n/" "not standard: an external network"'
  check "(control) a setting the build doesn't produce that holds an address treated as fine" \
    'opp2 "s/refuse\(f\"it has a setting make-it.s build doesn.t produce that holds an address: \{name\}\"\)/continue/" "not standard: an address setting make-it'"'"'s build doesn'"'"'t produce, even one"'
  check "(control) a host-like value in a setting the build doesn't produce allowed (only its name is looked at)" \
    'opp2 "s/elif ADDRESS_NAME\.search\(name\) or HOST_LIKE\.search\(value\):/elif ADDRESS_NAME.search(name):/" "not standard: a setting the build doesn'"'"'t produce whose value names another machine"'
  check "(control) a generated mock treated as an unknown service: an app the build made is refused" \
    'opp2 "s/ and not generated_mock\(key, svc\):/:/" "used: an app with the integration and logging mocks the build generates"'
  check "(control) any service named mock-... taken for a generated one" \
    'opp2 "s/ and svc\.get\(\"profiles\"\) == \[\"dev\"\]\n\s+and context\[-2:\] == \[\"mock-services\", key\]\)/)/" "not standard: a service named mock-... that isn'"'"'t one the build generates"'
  check "(control) volumes_from allowed as a service option" \
    'opp2 "s/\"profiles\",\n\s+\"volumes\"\}/\"profiles\", \"volumes\", \"volumes_from\"}/" "not standard: a service option the build doesn'"'"'t use (volumes_from)"'
  check "(control) an unparseable address treated as fine" \
    'opp2 "s/\n            if hosts is None:\n[^\n]*\n/\n            if hosts is None:\n                continue\n/" "not standard: an address that can'"'"'t be read for certain (a comma"'
  check "(control) wt_stop no longer waits for the checks: a refused copy still gets down -v" \
    'opp "s/wt_stop\(\) \{ \[ -n \"\\\$wt_ok\" \] && /wt_stop() { /" "not standard: a volume with a fixed name"'
  check "(control) every numeric default offset again: WORKERS becomes a port number" \
    'opp "s/\[A-Z0-9_\]\*PORT:-/[A-Z0-9_]+:-/" "only variables whose name ends in PORT are offset"'
  check "(control) the counters dropped from count: a create-then-delete passes the guard" \
    'opp "s/; printf [^\n]*pg_stat_user_tables[^\n]*\| q; \}/; }/" "a create-then-delete wired to the person"'
  check "(control) \"copy removed\" said whatever the removal did" \
    'opp "s/if wt_stop >\/dev\/null 2>&1; then echo \"copy removed: \\\$WT\"; else echo \"COPY LEFT: \\\$WT\"; fi/wt_stop >\/dev\/null 2>&1; echo \"copy removed: \\\$WT\"/" "when the removal fails it says COPY LEFT"'
  check "(control) make-it's block reads the configuration without the profile again" \
    'opp "s/docker compose --profile dev config 2>\/dev\/null \| sed/docker compose config 2>\/dev\/null | sed/" "the blocks read and start the stack with the profile"'
  check "(control) an AI setting left filled in the copy: a set key is used by the copy, or refuses the app" \
    'opp "s/\n[^\n]*stack-check\.py\" ai-settings \| while read[^\n]*\n/\n/" "used: an AI app with a key set"'
  # opp3 PERL REASON: resume-it.md with one edit must fail this script on the check named REASON
  opp3() {
    cp "$RS" "$TMPD/r.md"; perl -0pi -e "$1" "$TMPD/r.md"; ! cmp -s "$RS" "$TMPD/r.md" || return 1
    local out; out="$(RESUME_MD="$TMPD/r.md" bash "$SELF" "$MK" 2>&1)" && return 1
    printf '%s\n' "$out" | grep -F "FAIL $2" >/dev/null
  }
  check "(control) /resume-it's settings line without the profile again: the one-service scaffold can't be read" \
    'opp3 "s/docker compose --profile dev config --format json \| python3/docker compose config --format json | python3/" "/resume-it'"'"'s own settings line reads the configuration"'
  check "(control) the fresh-database path back: a new build writes to the app's own database" \
    'opp "s/(\n22\. \*\*Build and start containers:\*\*\n)/\$1    Prints fresh-db: yes when the database is new.\n/" "a brand-new build has no other path"'
  check "(control) the old sweep back in step 26 a" \
    'opp "s/(\n    b\. Verify 2xx response)/\n       sweep() { del x; }\$1/" "nothing in Part B cleans up a database"'
fi

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
