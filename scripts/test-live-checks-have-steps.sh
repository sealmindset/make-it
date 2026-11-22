#!/usr/bin/env bash
# E12-S6 (the owner's call, 2026-11-21: "/resume-it starts the app and runs the live checks: yes, after a relevant
# change"): a rulebook row whose method is checking the running app is checked on the running app.
# Contract these checks pin:
#   - build-standards.md says once what `[LIVE]` means, and every row in the floor below still carries it (a row whose
#     method is the running app is never relabelled to make the claim easier).
#   - The mapping is read from the two files, never from a list kept here: every `[LIVE]` row is named in the title of
#     exactly one step of /make-it's build-verify Part B, every row a Part B step names is a `[LIVE]` row, a step that
#     names several rows has its own unit for each, and every step's text is an action on the running app (a request,
#     a browser action, an upload, a docker command), not a file read.
#   - Each new live unit says who it runs as, what to expect and what counts as a fail, and the added text is pinned
#     whole, unit by unit.
# A wording test is a tripwire, not a proof: it catches a step dropped, renamed away or turned into a file read, not
# an agent skipping a step it read, and not a step that does the wrong thing in the right words.
# Usage: test-live-checks-have-steps.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on
# opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# the whole run's stderr is caught; the last check fails on any of it (a Python error reads as a pass otherwise)
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

BS=.claude/make-it/references/build-standards.md; MK=.claude/commands/make-it.md
FILES="$BS $MK"

# The rows whose method is checking the running app on 2026-11-22 (E12-S6 step 0). A floor, not the mapping: a row
# may gain [LIVE]; none of these may lose it.
FLOOR="V02 V03 V04 V05 V06 V07 V08 V10 V11 V12 V13 V14 V16 F09 F10 F11 F14 AI01a AI01b AI01d AI11 AI12 AI13 AI14
AI20 AI21 AI22 AI25 AI26 AI27 BN03 BN04 BN05 BN06 BN09 BN10 BN11 BN13 BNV01 BNV02 BNV03 AC02 AC04 AC05 AC07 AC08
AC09 AC10 AC11 AC12 AC13 AC14 AC15 ACV01 ACV02 ACV03 P03"

# The text E12-S6 added, pinned whole, unit by unit (a unit starts at a list item, a numbered step or a bold lead).
cat > "$TMPD/bs.pin" <<'PIN'
- `[LIVE]` after the severity = the check's method is checking the running app: a request, a browser
  action, an upload, a restart with one setting changed, or a command in a running container. /make-it's
  build-verify Part B has a step that names it.
PIN
cat > "$TMPD/mk.pin" <<'PIN'
23. **Wait for all services to be healthy (V02)** -- poll health endpoints for each service

24. **Run the mock service seed script (V03):**

25. **Test the auth flow end-to-end for EACH role (V04):**

26. **Test every API endpoint (V05):**

27. **Test every page (V06):**

28. **Test permission boundaries (V07):**
    For each role, signed in as in step 25, verify:

29. **Test Activity Logs (V08) (web-app and api-service only):**

30. **Test Notifications (V10) (web-app and api-service only):**

    g. In a browser, as User: open the dashboard and click the mode toggle twice. Expect: the
       `<html>` class switches between `light` and `dark`, localStorage `theme` holds the choice,
       and the choice stays after a reload. Fail: the class doesn't change, or a page keeps one
       theme.

33. **Test File Upload (V11) (if app has Documents page or upload feature):**

33a. **Test brain layer (BNV01-BNV03)** -- Skip if brain_features.enabled != true

**Rows checked on the running app.** Each step in Part B names, in its title, the rulebook rows
it checks, and every row marked `[LIVE]` in `build-standards.md` is named by one of them. A row
whose feature the app doesn't have is N/A. A check that could not run goes in TODO.md as NOT RUN
with its reason, never as passed. "As User" means signed in as that role's test user, the way
step 25 signs in.

**The changed-setting run** (steps 33c, 33d, 33f and 33g use it): stop the backend (`docker
compose stop backend`; `backend` is the scaffold's service name), start it with one setting
changed -- `docker compose run -d --rm --service-ports --name live-check -e <SETTING>=<value>
backend` -- run the check, then put it back: `docker rm -f live-check && docker compose
--profile dev up -d backend`, and wait for its health check. Never edit `.env` for it. "The AI
address unreachable" means `http://127.0.0.1:9` in the variable the AI provider reads
(`config.py` names it).

33c. **Test upload failures, AI analysis and file layouts (F09, F10, F14)** -- Skip a row whose
    feature the app doesn't have (F10 needs file upload and AI features).
    - **F09** -- As the lowest role allowed to upload: POST an empty file, then a corrupt PDF (`head -c 2048 /dev/urandom >
      bad.pdf`), to the upload endpoint. Expect: 400 for the empty file and 422 for the corrupt
      one, each with a plain message. Fail: any 500, or a body naming a library, a stack trace
      or a file path.
    - **F10** -- As the lowest role allowed to upload: upload a small PDF that has text. Expect: the stored document has its
      extracted text and, kept apart from it, an AI analysis. Then, in the changed-setting run
      with the AI address unreachable, upload it again. Expect: the upload succeeds and the
      document is saved with its text and no analysis. Fail: no analysis while the AI is up, the
      text overwritten by the analysis, or the upload refused while the AI is down.
    - **F14** -- As the lowest role allowed to import: import the same CSV three times, with 0, 3 and 7 lines above its header
      row. Expect: all three succeed with the same row count. Fail: any of them fails or counts a
      different number of rows.

33d. **Test the AI with a changed setting (F11, AI01a, AI01b, AI01d, AI21)** -- Skip unless
    ai_features.needed = true.
    - **F11** -- No sign-in: start the backend in the foreground with the AI address unreachable
      and pre-flight on (`docker compose stop backend`, then `docker compose run --rm
      --service-ports -e <AI address>=http://127.0.0.1:9 backend`). Expect: within 10 seconds it
      logs which pre-flight check failed and exits non-zero, and the port never answers. Fail:
      `/health` answers, or it exits 0. Put the backend back as the changed-setting run does.
    - **AI01a** -- As User, in the changed-setting run with `AI_MODEL_STANDARD=llama3`: send one
      chat message. Expect: a reply, and a correction warning in the backend log (`docker logs
      live-check`) naming the model used instead. Fail: an error to the user, no warning, or
      `llama3` sent to the provider.
    - **AI01b** -- Only when `AI_FAILOVER_PROVIDER` is set. As User, in the changed-setting run
      with the primary provider's address unreachable: send one chat message. Expect: a reply
      from the failover provider, and the log shows the switch. Fail: an error to the user.
    - **AI01d** -- Only when `ai_providers.primary` is `claude_agent`. No sign-in: run `docker
      compose exec backend claude --version` and `docker compose exec backend python -c "import
      claude_agent_sdk"`. Then as User, in the changed-setting run with
      `CLAUDE_CODE_OAUTH_TOKEN=` (empty): send one chat message. Expect: a version line, a clean
      import, and the friendly "run `claude setup-token`" message (available: false). Fail:
      either command fails, or a 500 or a crash without the token.
    - **AI21** -- As User, in the changed-setting run with the AI address unreachable: trigger an
      agent with `rule_based_fallback: true`, then one without it. Expect: the first gives a
      useful answer ("AI is temporarily unavailable. Please try again shortly." from a
      conversational agent, a job that ends `completed_without_ai` from a batch one); the second
      gives a plain error. Fail: the first one errors, or either shows a stack trace.

33e. **Test chat: streaming, history, privacy and the chat screen (V14, AI11, AI12, AI13, AI14)**
    -- Skip unless the app has conversational AI.
    - **AI11** -- As User: POST a message to `/api/ai/conversations/{id}/messages` with `Accept:
      text/event-stream` (`curl -N`). Expect: 200, `Content-Type: text/event-stream`, `data:`
      token events arriving over time, and a last event with `"done": true`. Fail: another
      content type, the whole reply in one burst, or no done event.
    - **AI12** -- As User: create a conversation, send two messages, then GET
      `/api/ai/conversations/{id}`. Expect: both messages and both replies. Then as Manager (a
      different person): GET the same id. Expect: 404, and the conversation isn't in that
      person's list. Fail: missing history, or the second person gets it.
    - **AI13** -- In a browser, as User: open the chat page and send a message. Expect: the reply
      appears as it is written, the conversation shows in the sidebar at once, and it is still
      there after a reload. Fail: the reply appears only when finished, or the sidebar misses it.
    - **AI14** -- As User: POST the same message with `Accept: application/json`. Expect: 200 and
      the whole reply as one JSON object. Then in a browser, start a streamed reply and cut it
      (DevTools: Offline for 3 seconds, then back). Expect: it retries and the full reply
      appears. Fail: an error on the JSON request, or a lost reply after the cut.
    - **V14** -- As User: ask for a long answer and watch the stream (`curl -N`). Expect:
      `{"heartbeat": true}` events while it runs; V14's other items are AI11-AI14 above. Fail: no
      heartbeat in a reply that runs longer than `AI_SSE_HEARTBEAT_INTERVAL_SECONDS`.

33f. **Test agent routing and the agent patterns (V16, AI20, AI22, AI25, AI26, AI27)** -- Skip
    unless the app has more than one agent; AI25-AI27 only for an agent that uses that pattern.
    - **V16** -- As User: for each conversational agent, create a conversation with its
      `agent_slug` and send a message. As Admin: POST `/api/ai/agents/{slug}/run` for each batch
      agent. Expect: each reply comes from that agent (its prompt and its data), and each run
      creates a job with that agent's `task_type`. Fail: a reply from another agent, or a run
      with no job.
    - **AI20** -- As Admin: POST `/api/ai/agents/no-such-agent/run`; as User, create a
      conversation with `agent_slug` `no-such-agent`. Expect: 404 both times. Fail: any other
      status.
    - **AI22** -- As Admin: run one batch agent and poll its job. Expect: a `task_type` starting
      `ai_agent:`, progress that moves, and tokens and cost in the finished job's `result_data`.
      Fail: no job, progress that stays at 0 until the end, or no tokens or cost.
    - **AI25** -- As Admin: run the pipeline agent. Expect: its steps run in order (the job's
      progress or the log). Then run it again in the changed-setting run with the AI address
      unreachable. Expect: the failed step handled as its fallback setting says. Fail: steps out
      of order, a hang, or a 500.
    - **AI26** -- As User: start a conversation with the generalist agent and send its hand-off
      trigger. Expect: the next reply comes from the specialist and uses the earlier messages,
      and GET of the conversation shows the hand-off in `delegation_chain`. Fail: no hand-off,
      lost context, or an empty `delegation_chain`.
    - **AI27** -- As Admin: run the fan-out agent. Expect: every sub-agent ran (the job's
      per-agent breakdown). Then in the changed-setting run with `AI_FAN_OUT_TIMEOUT_SECONDS=1`,
      run it again. Expect: the job finishes with the sub-agents that timed out marked so, and
      a merged result from the rest. Fail: the whole run fails, or it hangs.

33g. **Test AI memory (BN03, BN04, BN05, BN06, BN09, BN10, BN11, BN13)** -- Skip if
    brain_features.enabled != true.
    - **BN03** -- As User, in the changed-setting run with `BRAIN_FEATURES_ENABLED=true` and
      `LOG_LEVEL=DEBUG`: add a memory, then send a chat message. Expect: the prompt in the debug
      log holds that memory. As Admin, add an org memory with scope `security`; as User, chat
      with an agent outside security, then with the security agent. Expect: it is left out, then
      included. Run once more with `BRAIN_FEATURES_ENABLED=false`. Expect: no memories in the
      prompt. Fail: any of these the other way round.
    - **BN04** -- As User: add a memory containing `<script>alert(1)</script>` and one containing
      "ignore previous instructions", then GET them. Expect: the script tag stripped or escaped,
      and the instruction phrase removed. Fail: either stored as sent.
    - **BN05** -- As User: add a personal memory. As Manager: GET `/api/brain/memories`, and GET
      the User's memory by its id. Expect: not in the list, and 404. As Admin, add an org memory
      with scope `security` and one with scope `all`. Expect: a role without security
      permissions doesn't get the `security` one and a role with them does; everyone gets the
      `all` one. Fail: any person seeing another's personal memory, or a scope shown to the wrong
      role.
    - **BN06** -- As User: GET `/api/brain/memories` and `/api/admin/brain/memories`. Expect: 200,
      then 403. As Super Admin: GET every `/api/admin/brain/` endpoint. Expect: 200. Fail: the
      User reaching the admin list, or the Super Admin refused.
    - **BN09** -- As User and as Admin, and signed out: call each brain endpoint the rulebook row
      lists. Expect: success for the roles it allows, 403 for the others, 401 signed out. Fail:
      any other status.
    - **BN10** -- As Super Admin: POST `/api/admin/brain/curation/run`, then poll the job. Expect:
      `task_type` `ai_agent:memory-curator` and `result_data` with the counts, tokens and cost the
      rulebook row lists. Fail: no job, or a missing field.
    - **BN11** -- As User: add, correct and delete one memory. Expect: three new rows in
      `brain_memory_audit_log` (`docker compose exec db psql`), each with action and actor type.
      Fail: fewer than three, or a missing field.
    - **BN13** -- In a browser, as User and as Manager: open `/settings/ai-memory`. Expect: each
      sees their own memories, and the two lists differ. As Admin: open `/admin/ai-memory`.
      Expect: memories from several users. Fail: an empty list, or the same list for both.

33h. **Test AI accounting (AC02, AC04, AC05, AC07, AC08, AC09, AC10, AC11, AC12, AC13, AC14, AC15)**
    -- Skip if ai_features.needed != true. Put every setting you change back afterwards.
    - **AC02** -- As Admin: count `ai_usage_events` rows (`docker compose exec db psql`), trigger
      one agent, count again. Expect: exactly one new row, with all four token counts filled.
      Fail: no row, more than one, or an empty token count.
    - **AC04** -- As Admin: end the price row of the model in use (set its end date to yesterday),
      trigger one agent. Expect: the new row has `priced = false` and no cost, and AI Spend's
      unpriced count went up by one. Add the price back. Expect: the row is priced. Fail: a cost
      of 0, or `priced = true` with no price.
    - **AC05** -- As Admin: change the light tier's model on the Control Plane, then trigger a
      light agent. Expect: its new ledger row has the new model, with no restart. Fail: the old
      model.
    - **AC07** -- Only when escalation is on for a light agent. As Admin: trigger it with an input
      whose answer can't meet its schema. Expect: one standard call follows, with
      `escalated_from = light`, and no third call. Fail: no step up, or a second one.
    - **AC08** -- As Admin: lower an agent's tier with no replay. Expect: refused with a plain
      message. Run the replay on seed tasks, then lower it again. Expect: the replay's result
      and cost in `control_audit_log`, then the change allowed. Fail: lowered with no replay.
    - **AC09** -- As Manager (or a role that acts on AI results): approve one seeded AI result
      unchanged and edit another. Expect: an `accepted` and a `corrected` row in `ai_outcomes`.
      Fail: either missing.
    - **AC10** -- In a browser, as Admin: open the page that shows ROI. Expect: it equals the
      formula worked by hand from the seed rows (`docker compose exec db psql`). Fail: any
      difference over 1 cent.
    - **AC11** -- As User: GET and PATCH the Control Plane API. Expect: 403 both times. As Admin:
      make one change. Expect: exactly one new `control_audit_log` row with before and after.
      Set an agent `off` and trigger it. Expect: no provider call and no `ok` ledger row. Fail:
      the User gets in, no audit row, or the agent still calls the AI.
    - **AC12** -- As Admin: set that agent's day cap below today's seed spend, then trigger it.
      Expect: a `refused_budget` row with cost 0, no provider call, the agent's fallback answer,
      and the admins' 100% notice. Fail: an `ok` row, a provider call, or no fallback.
    - **AC13** -- As Admin, with `INFRA_COST_SOURCE=mock`: run the infra collector twice for the
      same days. Expect: one row per day, source, service and cost center. On Infra Spend, a
      source that isn't connected says "not connected". Fail: duplicate rows, or $0 for a
      source that isn't connected.
    - **AC14** -- As Admin: issue two statements at once (two POSTs in parallel). Expect:
      consecutive numbers, both saved. Change a seed price. Expect: an issued statement's total
      doesn't change. Fail: a gap or a repeat, or a changed total.
    - **AC15** -- In a browser, as Admin: open the seven AI and spend pages. Expect: each renders
      with seed data. As User: open them. Expect: refused. As Admin: edit a published prompt
      without publishing, trigger its agent. Expect: the call still uses the published text.
      Fail: an empty or broken page, the User let in, or the draft used.

33i. **Run the variant's live checks (P03)** -- Only when ACTIVE_VARIANT is set: run every item
    under `### Live checks (Part B)` in the variant's definition file.
    - **P03** -- No sign-in: `curl -sI http://localhost:[FRONTEND_PORT]/sw.js`. Expect: 200 with a
      JavaScript content type. Fail: any other status, or an HTML page.
PIN

python3 -I - "$BS" "$MK" "$TMPD/bs.pin" "$TMPD/mk.pin" "$FLOOR" <<'PY' || fail=1
import re, sys
bs_path, mk_path, bs_pin, mk_pin, floor = sys.argv[1:6]
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        if why: print("  " + why)
flat = lambda s: re.sub(r"\s+", " ", s).strip()
ID = r"[A-Z]{1,3}V?[0-9]{2}[a-z]?"

def expand(text):
    """IDs in a list like 'V14, AI11-AI14' or 'BNV01-BNV03', ranges expanded."""
    out = []
    for part in re.split(r",\s*|\s+and\s+", text.strip()):
        m = re.fullmatch(rf"({ID})-({ID})", part)
        if m:
            a, b = m.groups()
            pa, na = re.match(r"([A-Z]+)([0-9]+)", a).groups()
            pb, nb = re.match(r"([A-Z]+)([0-9]+)", b).groups()
            if pa != pb or int(nb) < int(na): return None
            out += [f"{pa}{n:0{len(na)}d}" for n in range(int(na), int(nb) + 1)]
        elif re.fullmatch(ID, part):
            out.append(part)
        else:
            return None
    return out

def units(path):
    us, cur = [], []
    for line in open(path, encoding="utf-8").read().splitlines():
        if not line.strip() or re.match(r"\s*(- \*\*|[0-9]+[a-z]?\. \*\*|\*\*|[a-z]\. )", line):
            if cur: us.append(flat(" ".join(cur)))
            cur = [] if not line.strip() else [line]
        else:
            cur.append(line)
    if cur: us.append(flat(" ".join(cur)))
    return us

bs = open(bs_path, encoding="utf-8").read()
mk = open(mk_path, encoding="utf-8").read()

# 1. the rulebook: [LIVE] defined once, the floor kept
rows = {}
for m in re.finditer(rf"^\*\*({ID})\*\* \[[^\]]*\] \[[^\]]*\]((?: \[[A-Z ]+\])*) \*\*", bs, re.M):
    rows.setdefault(m.group(1), []).append(m.group(2))
live = {i for i, tags in rows.items() if any("[LIVE]" in t for t in tags)}
fl = floor.split()
check("build-standards.md says once what [LIVE] means", flat(bs).count("- `[LIVE]` after the severity = ") == 1)
for u in units(bs_pin):
    check(f"build-standards.md has the [LIVE] definition, whole: {u[:60]}...", u in flat(bs))
check("every row in the floor exists once in build-standards.md",
      all(len(rows.get(i, [])) == 1 for i in fl), "missing or repeated: " + " ".join(i for i in fl if len(rows.get(i, [])) != 1))
lost = [i for i in fl if i not in live]
check("no row whose method is the running app lost its [LIVE] mark", not lost, "not [LIVE]: " + " ".join(lost))

# 2. /make-it Part B: every [LIVE] row named by exactly one step, and every named row is [LIVE]
lines = mk.splitlines()
try:
    a = next(n for n, l in enumerate(lines) if l.startswith("**PART B: Live verification"))
    b = next(n for n, l in enumerate(lines) if n > a and l.startswith("**PART C: Fix cycle"))
except StopIteration:
    a = b = 0
check("make-it.md has Part B followed by Part C", b > a)
partb = lines[a:b]
steps, cur = [], None
for l in partb:
    m = re.match(r"([0-9]+[a-z]?)\. \*\*(.+?)\*\*", l)
    if m:
        cur = {"n": m.group(1), "title": m.group(2), "body": [l]}
        steps.append(cur)
    elif cur is not None:
        if l.startswith("**") and not l.startswith("    "):
            cur = None
        else:
            cur["body"].append(l)
named = {}
for s in steps:
    ids = []
    for g in re.findall(r"\(([^()]*)\)", s["title"]):
        e = expand(g)
        if e: ids += e
    s["ids"] = ids
    for i in ids: named.setdefault(i, []).append(s["n"])
nostep = sorted(i for i in live | set(fl) if i not in named)
check("every [LIVE] row (and every floor row) is named by a Part B step", not nostep, "no step: " + " ".join(nostep))
twice = sorted(i for i, ns in named.items() if len(ns) > 1)
check("no row is named by two Part B steps", not twice, "twice: " + " ".join(twice))
stray = sorted(i for i in named if i not in live)
check("every row a Part B step names is a [LIVE] row in build-standards.md", not stray, "not [LIVE]: " + " ".join(stray))

# 3. each step is an action on the running app; several rows -> a unit for each
ACT = re.compile(r"curl|\b(GET|POST|PATCH|PUT|DELETE)\b|docker (compose|exec|logs)|[Ii]n a browser|[Uu]pload|"
                 r"[Nn]avigate|login flow|signed in|valid JWT|[Rr]equest the page|[Ff]etch the page|poll health|"
                 r"seed-mock-services|changed-setting run|[Tt]rigger")
noact = [s["n"] for s in steps if s["ids"] and not ACT.search(" ".join(s["body"]))]
check("every Part B step that names a row acts on the running app", not noact, "no action in step(s): " + " ".join(noact))
nounit = [f'{s["n"]}:{i}' for s in steps if len(s["ids"]) > 1 for i in s["ids"]
          if not re.search(rf"\*\*{i}\b", "\n".join(s["body"][1:]))]
check("a step that names several rows has a unit for each", not nounit, "no unit: " + " ".join(nounit))
ROLE = re.compile(r"\b[Aa]s (User|Manager|Admin|Super Admin|the lowest role)|No sign-in")
badunit = []
for s in steps:
    text = "\n".join(s["body"])
    for m in re.finditer(r"^\s*- \*\*(" + ID + r")\*\* -- (.*?)(?=^\s*- \*\*|\Z)", text, re.M | re.S):
        u = flat(m.group(2))
        if not (ROLE.search(u) and "Expect: " in u and "Fail: " in u):
            badunit.append(m.group(1))
check("every live unit says who it runs as, what to expect and what fails", not badunit, "incomplete: " + " ".join(badunit))

# 4. the added text, whole
fb = flat("\n".join(partb))
missing = [u for u in units(mk_pin) if u not in fb]
check("the text E12-S6 added to Part B is there, whole, unit by unit", not missing,
      "missing: " + " | ".join(x[:80] for x in missing[:5]))
sys.exit(1 if failed else 0)
PY

# 5. controls (this repo only): each opposite fails the checks above, for its own reason
if [ -z "${1:-}" ]; then
  # opp FILE PERL REASON: a copy of the files with one edit must fail this script, on the check named REASON
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" || return 1
    local out; out="$(bash "$SELF" "$d" 2>&1)" && return 1
    printf "%s\n" "$out" | grep -F "FAIL $3" >/dev/null
  }
  check "(control) an unchanged copy passes, so each control below fails for its own edit" \
    'd="$TMPD/c"; mkdir -p "$d"; tar -cf - $FILES | tar -xf - -C "$d"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) a [LIVE] row with no step: AC12 dropped from step 33h's title" \
    'opp "$MK" "s/AC11, AC12, AC13/AC11, AC13/" "every [LIVE] row (and every floor row) is named by a Part B step"'
  check "(control) a step whose row was removed: V16 no longer [LIVE] in the rulebook" \
    'opp "$BS" "s/^(\*\*V16\*\* \[AI\] \[BLOCK\]) \[LIVE\]/\$1/m" "every row a Part B step names is a [LIVE] row"'
  check "(control) a relabelled row: BN05 loses [LIVE] in the rulebook" \
    'opp "$BS" "s/^(\*\*BN05\*\* \[AI\+Brain\] \[BLOCK\]) \[LIVE\]/\$1/m" "no row whose method is the running app lost its [LIVE] mark"'
  check "(control) a step reworded to read the file: step 27 checks the page source instead" \
    'opp "$MK" "s/(27\. \*\*Test every page \(V06\):\*\*\n).*?(?=\n28\. )/\$1    For each page, read its .tsx file and confirm it renders content./s" "every Part B step that names a row acts on the running app"'
  check "(control) a unit with no fail rule: AC12 loses its Fail" \
    'opp "$MK" "s/ Fail: an \`ok\` row, a provider call, or no fallback\.//" "every live unit says who it runs as"'
  check "(control) a row named by two steps: BN05 added to the brain step" \
    'opp "$MK" "s/Test brain layer \(BNV01-BNV03\)/Test brain layer (BNV01-BNV03, BN05)/" "no row is named by two Part B steps"'
  check "(control) a multi-row step missing a row's unit: the BN05 unit removed" \
    'opp "$MK" "s/^    - \*\*BN05\*\* --.*?(?=^    - \*\*BN06)//ms" "a step that names several rows has a unit for each"'
  check "(control) the [LIVE] definition removed" \
    'opp "$BS" "s/^- \`\[LIVE\]\` after the severity = .*?(?=^- )//ms" "build-standards.md says once what [LIVE] means"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
