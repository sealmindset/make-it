#!/usr/bin/env bash
# E12-S6 (the owner's calls, 2026-11-21 "/resume-it starts the app and runs the live checks: yes, after a relevant
# change", and 2026-11-22 D1 "Split: must-pass now", D2 "/resume-it: free and reversible checks only"): a must-pass
# rulebook row whose method is checking the running app is checked on the running app.
# Contract these checks pin:
#   - build-standards.md says once what `[LIVE]` means; every row in the floor (the 32 must-pass live rows) carries it.
#   - The mapping is read from the files, never from a list kept here: every `[LIVE]` row is named in the title of
#     exactly one step of /make-it's build-verify Part B and every row a step names is `[LIVE]` (ACV03 is the one
#     exception: 33b names it and it is deferred, unmarked); a step that names several rows has a unit for each; each
#     row has an item that acts on the running app, item by item, not a file read anywhere in the step.
#   - The whole of Part B is pinned, unit by unit, as an exact list: a reworded, added or dropped unit fails.
#   - /make-it's "no reachable AI provider" rows are exactly the rows /resume-it's table does not run because they call
#     the AI provider; the table covers every `[LIVE]` row once; the live pass is pinned whole.
#   - /retrofit-it's Part B is /make-it's by reference; the skill tables say how live rows run.
# A wording test is a tripwire, not a proof: it catches a step dropped, renamed away, turned into a file read or
# loosened, not an agent skipping a step it read, and not a step that does the wrong thing in the right words.
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

BS=.claude/make-it/references/build-standards.md; MK=.claude/commands/make-it.md; RS=.claude/commands/resume-it.md
RF=.claude/commands/retrofit-it.md; CM=CLAUDE.md
FILES="$BS $MK $RS $RF $CM"

# The 32 must-pass rows whose method is checking the running app (E12-S6 step 0, split by D1). A floor, not the
# mapping: a row may gain [LIVE]; none of these may lose it.
FLOOR="V02 V03 V04 V05 V06 V07 V11 V12 V13 V14 V16 F09 F10 F11 F14 AI01d AI11 AI12 AI13 BN03 BN04 BN05 BNV01 BNV02
BNV03 AC02 AC04 AC11 AC12 ACV01 ACV02 P03"

cat > "$TMPD/bs.pin" <<'PIN'
- `[LIVE]` after the severity = the check's method is checking the running app: a request, a browser
  action, an upload, a restart with one setting changed, or a command in a running container. /make-it's
  build-verify Part B has a step that names it; /resume-it runs that step in its live pass after a
  change that touches the check's area, when the check calls no paid AI provider and leaves no test
  records (its live-pass table says which).
PIN
cat > "$TMPD/partb.pin" <<'PIN'
**PART B: Live verification (start the app and test it)**

**Rows checked on the running app.** Each step in Part B names, in its title, the rulebook rows
it checks, and every row marked `[LIVE]` in `build-standards.md` is named by one of them. A row
whose feature the app doesn't have is N/A. A check that could not run goes in TODO.md as NOT RUN
with its reason, never as passed. "As User" means signed in as that role's test user, the way
step 25 signs in.

21. **SSL-inspecting proxy check** -- Before any Docker build or pull, learn which security
    tools are running (the pause ask below matches /try-it step 1's ask and answers, apart from
    the stop message):
    ```bash
    # Check each common SSL-inspecting proxy separately, so every running one is named.
    # Bracketed first letter: the pattern can never match its own shell's command line.
    for p in '[Z]scaler' '[N]etskope' '[G]lobalProtect'; do
      pgrep -f "$p" >/dev/null 2>&1 && echo "$(echo "$p" | tr -d '[]') running"
    done
    ```
    A tool found running is only a name so far: try the build (step 22) first, and ask only
    when a build or pull fails with a TLS/certificate error. Then the user has to pause the tool
    themselves, and this is a high-stakes stop (per the approval block): they are turning off a
    security tool on their own computer, so they pick the specific tool -- never a plain "done".
    Fill `[TOOL]` with every name the check printed (Zscaler, Netskope or GlobalProtect; all of
    them if more than one matched). If the check found nothing, use "your network security tool
    (often Zscaler, Netskope or GlobalProtect)" and the 'I don't have a tool like this' option.

    Tell user: "Before I can put your app together, I need you to pause [TOOL] for a little
    while. The download just failed in the way these tools make it fail[if detected: ', and I
    can see [TOOL] running on your computer']. While it's paused, that tool isn't checking your
    computer's internet traffic -- nothing about your app or your files changes. If it offers a
    time limit, it turns itself back on when that runs out; either way, I'll remind you to turn
    it back on as soon as I'm done downloading, whether or not everything worked. Normally I
    handle everything myself; this is the one thing I can't do for you.
    The one thing to check: it's your company's tool and you're allowed to pause it. If you're
    not sure, pick 'Not sure, or I can't' and I'll stop here instead.
    [Only when the check found nothing: 'If you don't have a tool like this, pick 'I don't have a tool
    like this' and I'll keep working on the download problem myself.']
    To pause it: find [TOOL] in your menu bar or system tray, choose 'Disable' or 'Pause,' and
    if it asks, pick a time long enough for the downloads. Then pick what you did:
    - **I paused [TOOL]** [one option per tool the check named]
    - **Not sure, or I can't** -- I'll stop here.
    [Only when the check found nothing: - **I don't have a tool like this**]"

    **Wait for their pick.** "I paused [TOOL]" means go, unless "Not sure, or I can't" is picked with it: then it is a stop. When `[TOOL]` names more than one tool,
    every one of them must be picked before the build is retried; ask about the ones still
    missing. If they say how long they paused it for, note it as that tool's `[TIME]`; it is not
    asked for. "Not sure, or I can't" means stop; "I don't have a tool like this" (offered only
    when the check found nothing) means the tool wasn't the cause -- go back to step 22's normal diagnosis
    and keep fixing, and don't offer this pause again this run (a later certificate error gets the
    normal diagnosis, not this ask); a plain 'done' or 'ok' is not a pick -- show the options
    again. Do NOT retry Docker builds while the tool is active. On stop: if they already said
    they paused any tool, give it the reminder below first; then tell them in a few lines that
    their app can't be put together on this network [if detected: 'while [only the tools still
    running] is running' / otherwise: 'while something is blocking the downloads']; to ask
    whoever manages their computer to allow Docker image downloads; that their project files are
    saved in [PROJECT_DIR] so nothing is lost; and that once the downloads are allowed, they open
    that folder, run /resume-it and say "finish building my app". Before stopping, add one line
    to TODO.md: "Finish the build: read ~/.claude/commands/make-it.md and its
    <execution_context>, then run build-verify from Part B (step 21) in this folder." (Agent
    note: no `.make-it-state.md` exists yet; /resume-it reads app-context.json and scans the
    folder instead.)

    Only if the user actually paused a tool: once the downloading is over -- the builds and
    pulls worked, or you've stopped trying -- remind the user, naming every tool they said they
    paused: "All done with the heavy lifting! You can turn [TOOL] back on now[if a time was
    given: ' -- no need to wait out the [TIME] you gave it']." No pause (never asked, or 'I don't
    have a tool like this'), no reminder.

22. **Build and start containers:**
    ```bash
    docker compose --profile dev build 2>&1
    docker compose --profile dev up -d 2>&1
    ```
    If build fails, diagnose silently, fix, and retry (up to 3 attempts). A TLS/certificate
    error is the one exception: that is step 21's security-tool ask, then retry.
    If port conflicts occur on `up`, remap conflicting ports and retry.

23. **Wait for all services to be healthy (V02)** -- poll health endpoints for each service
    (timeout 120s per service). If a service fails, read logs, fix, restart.

24. **Run the mock service seed script (V03):**
    ```bash
    bash scripts/seed-mock-services.sh
    ```
    If the script fails, diagnose and fix. The mock services must have the correct users
    and data before any testing begins.

25. **Test the auth flow end-to-end for EACH role (V04):**
    For each role defined in app-context.json:
    a. Navigate to the app URL
    b. Follow the login flow through mock-oidc (use login_hint for the role's test user)
    c. Verify the callback completes and a JWT cookie is set
    d. Verify /auth/me returns the correct role from the DATABASE (not just "user")
    e. Verify the dashboard loads with content
    f. Test logout (POST to /auth/logout, verify JWT cookie is cleared, verify 401 after)

    If ANY role gets the wrong permissions (e.g., admin shows as "user"), this means the
    auth callback is not reading roles from the database. Fix the callback code and retest.

26. **Test every API endpoint (V05):**
    For each API route in the app (with a valid JWT):
    a. Call the endpoint
    b. Verify 2xx response
    c. Verify response is valid JSON with expected structure
    d. Verify list endpoints return NON-EMPTY arrays (seed data must exist)
    e. Verify permission-protected endpoints return 403 for unauthorized roles

27. **Test every page (V06):**
    For each page defined in app-context.json (with a valid JWT):
    a. Request the page URL
    b. Verify it loads (200)
    c. Verify it has meaningful content (not empty tables, not "no data found")

28. **Test permission boundaries (V07):**
    For each role, signed in as in step 25, verify:
    a. Can access pages/endpoints they SHOULD access
    b. Gets rejected (403 or redirect) from pages/endpoints they should NOT access

29. **Test Activity Logs (web-app and api-service only):**
    a. Verify GET /api/admin/logs/stats returns valid stats (buffer_size, total_received, etc.)
    b. Verify GET /api/admin/logs/events returns non-empty results (after app has handled requests)
    c. Verify DELETE /api/admin/logs/events returns 403 for non-admin roles
    d. Verify the Admin UI Activity Logs tab loads with stats cards and event table

30. **Test Notifications (web-app and api-service only):**
    a. Verify GET /api/notifications/count returns valid { unreadCount } for authenticated user
    b. Verify GET /api/notifications returns notifications scoped to the logged-in user
    c. Verify PATCH /api/notifications with { ids: [...] } marks a notification as read
    d. Verify the bell badge shows correct unread count per role (different users see different counts)
    e. Verify notifications reference real seeded entity IDs (relatedEntityId is not null for at least some)

31. **Test DataTable features on every list page (V12):**
    For each page that displays tabular data:
    a. Fetch the page HTML and verify it contains DataTable markup:
       - Pagination text (e.g., "Page 1 of") and page size selector
       - Column header buttons (not plain `<th>` text)
       - Toolbar area with search input and/or filter buttons
    b. Verify data rows exist (seed data must populate -- no empty "No results" state)
    c. Verify the page source imports from `@/components/data-table` (read the page .tsx file)
    d. Verify column definitions use `DataTableColumnHeader` (provides Excel filtering + sorting)
    e. Verify `storageKey` prop is set (enables state persistence)
    f. Grep all page files for raw `<table` usage -- any match outside the DataTable
       component files themselves is a U06 violation. Fix by replacing with DataTable.

32. **Test theme toggle (V13):**
    a. Verify `<ModeToggle />` appears in the authenticated layout header (read the layout file)
    b. Verify `<ThemeProvider>` wraps the app in root layout
    c. Verify `globals.css` has both `:root` and `.dark` CSS variable blocks
    d. Verify `tailwind.config.ts` has `darkMode: "class"`
    e. Grep all `.tsx` page files (under `app/(auth)/`) for hardcoded colors:
       - Pattern: `#[0-9a-fA-F]{3,8}` or `rgb(` or `hsl(` or `oklch(`
       - Any match in a page file is a U09 violation (colors must use CSS variables or
         Tailwind semantic classes so they respond to the theme toggle)
       - Fix by replacing with `var(--*)` CSS variables or Tailwind classes
    f. Verify the ModeToggle component uses the `mounted` state pattern (prevents hydration errors)
    g. In a browser, as User: open the dashboard and click the mode toggle twice. Expect: the
       `<html>` class switches between `light` and `dark`, localStorage `theme` holds the choice,
       and the choice stays after a reload. Fail: the class doesn't change, or a page keeps one
       theme.

33. **Test File Upload (V11) (if app has Documents page or upload feature):**
    a. Upload a valid PDF via the upload API endpoint -- verify 200 with extracted text
    b. Upload an image -- verify 200 with base64 content
    c. Upload an oversized file (> MAX_FILE_SIZE) -- verify 413 rejection
    d. Verify Docker volume mount exists: `docker exec {container} ls /app/data/documents`
    e. **CRITICAL**: Grep source for `from 'pdf-parse'` or `import('pdf-parse')` -- if found,
       this is F03 violation. Must use `require('pdf-parse/lib/pdf-parse')` instead.
       The default import crashes in production Docker with ENOENT on test data file.
    f. Verify DOCUMENTS_PATH and UPLOAD_CACHE_PATH in docker-compose.yml environment block

**The changed-setting run** (steps 33c, 33d, 33f and 33g use it). `<backend>` is the app's
backend service as its `docker-compose.yml` names it (`backend` in the scaffold). `<run>` is
`<project>-live-check`, where `<project>` is the `name` in `docker compose config --format json`,
so two worktrees never share one. In this order:
    1. `docker rm -f <run>` (a leftover from an earlier run), then `docker compose stop <backend>`.
    2. `docker compose run -d --service-ports --use-aliases --name <run> -e <SETTING>=<value>
       <backend>`. Without `--use-aliases` the frontend can't find the backend by its service
       name, and every request through the app fails.
    3. Wait at most 60 seconds, reading `docker inspect -f '{{.State.Status}} {{.State.ExitCode}}'
       <run>` and the backend's health URL once a second, then run the check.
    4. **Put it back, always** -- whether the check passed, failed, was cut off or errored:
       `docker rm -f <run>`, then `docker compose --profile dev up -d --wait <backend>`, then one
       request through the app's frontend that reaches the backend. Write in the results that the
       normal backend is back, healthy and reached through the frontend; if it isn't, fix that
       before any other check.
    Never edit `.env` for it, and never leave `<run>` behind. "The AI address unreachable" means
    `http://127.0.0.1:9` in the setting the provider reads: `AZURE_AI_FOUNDRY_ENDPOINT`
    (anthropic_foundry), `ANTHROPIC_BASE_URL` (anthropic, read by the Anthropic SDK),
    `OPENAI_BASE_URL` (openai, read by the OpenAI SDK), `OLLAMA_BASE_URL` (ollama). claude_agent
    has none: use `CLAUDE_CODE_OAUTH_TOKEN=` (empty) instead.

**No reachable AI provider** (steps 33a-33h). A default build may have none: `claude_agent` ships
with an empty token, and the scaffold has no mock AI provider. Before these steps, read the
provider's key in the backend (`docker compose exec <backend> printenv <KEY>`, with `<KEY>` one of
`AZURE_AI_FOUNDRY_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`;
ollama has no key) and, as User, send one chat message or trigger one agent. An empty key, or an
answer that says the AI is unavailable, means there is no reachable provider. Then these rows are
NOT RUN with the reason "no AI key yet" -- never FAIL, and never fixed: V14, V16, F10, AI11, AI12,
AI13, BN03, BNV01, BNV02, AC02, AC04, ACV01. These need no provider and run either way: F11,
AI01d, BN04, BN05, BNV03, AC11, AC12, ACV02.

33a. **Test brain layer (BNV01-BNV03)** -- Skip if brain_features.enabled != true
    a. **BNV01: Brain context influences AI responses** -- With BRAIN_FEATURES_ENABLED=true
       and seed memories in place, send a chat message to an AI agent. Verify the response
       reflects memory context (e.g., if seed memory says "prefers bullet points", response
       should use bullet format). Disable brain features, send same message, verify response
       format differs.
    b. **BNV02: Curation produces memories** -- Trigger MemoryCuratorAgent via admin API
       (POST /api/admin/brain/curation/run). Verify job record created in DI03 table.
       Verify job completes. If unprocessed conversations with memory signals exist,
       verify at least one new memory created in brain_memories.
    c. **BNV03: Memory isolation** -- Login as user A, GET /api/brain/memories, note
       user-type memories. Login as user B, GET /api/brain/memories, confirm user A's
       user-type memories are NOT returned. Confirm org-type memories with scope 'all'
       ARE visible to both users. Try to access user A's memory by ID as user B -- verify 404.

33b. **Test AI accounting (ACV01-ACV03)** -- Skip if ai_features.needed != true
    a. **ACV01: One call, one priced row** -- trigger one agent; exactly one new ledger row
       with agent, feature, tier, model, tokens and a cost that matches the price row.
    b. **ACV02: A cap refuses before spending** -- set the agent's day cap to $0.000001 on the
       Control Plane, trigger it: no provider call, one refused_budget row, the fallback shown
       in plain words. Put the cap back.
    c. **ACV03: Pages agree with the ledger** -- AI Spend's total for today equals the sum of
       today's ledger rows; a 30-day statement's AI total equals the same sum for its period.

33c. **Test upload failures, AI analysis and file layouts (F09, F10, F14)** -- Skip a row whose
    feature the app doesn't have (F10 needs file upload and AI features).
    - **F09** -- As the lowest role allowed to upload: POST an empty file, then a corrupt PDF
      (`head -c 2048 /dev/urandom > bad.pdf`), to the upload endpoint. Expect: 400 for the
      empty file and 422 for the corrupt one, each with a plain message. Fail: any 500, or a body
      naming a library, a stack trace or a file path.
    - **F10** -- As the lowest role allowed to upload: upload a small PDF that has text. Expect:
      the stored document has its extracted text and, kept apart from it, an AI analysis. Then,
      in the changed-setting run with the AI address unreachable, upload it again. Expect: the
      upload succeeds and the document is saved with its text and no analysis. Fail: no analysis
      while the AI is up, the text overwritten by the analysis, or the upload refused while the
      AI is down.
    - **F14** -- As the lowest role allowed to import: import the same CSV three times, with 0, 3
      and 7 lines above its header row. Expect: all three succeed with the same row count. Fail:
      any of them fails or counts a different number of rows.

33d. **Test the AI with a changed setting (F11, AI01d)** -- Skip unless ai_features.needed = true.
    - **F11** -- No sign-in: the changed-setting run with the AI address unreachable and
      pre-flight on (the app's config names the switch: `AI_PREFLIGHT_CHECK` in the scaffold).
      Expect: within 10 seconds `docker inspect` shows `exited` with a non-zero code, `docker logs
      <run>` names the pre-flight check that failed, and the health URL never answered. Fail:
      still `running` at 60 seconds, the health URL answers, or exit code 0. The put-back runs
      either way.
    - **AI01d** -- Only when `ai_providers.primary` is `claude_agent`. No sign-in: run `docker
      compose exec <backend> claude --version` and `docker compose exec <backend> python -c
      "import claude_agent_sdk"`. Then as User, in the changed-setting run with
      `CLAUDE_CODE_OAUTH_TOKEN=` (empty): send one chat message. Expect: a version line, a clean
      import, and the friendly "run `claude setup-token`" message (available: false). Fail:
      either command fails, or a 500 or a crash without the token.

33e. **Test chat: streaming, history, privacy and the chat screen (V14, AI11, AI12, AI13)** --
    Skip unless the app has conversational AI.
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
    - **V14** -- As User: ask for a long answer and watch the stream (`curl -N`). Expect:
      `{"heartbeat": true}` events while it runs. Then POST the same message with `Accept:
      application/json`. Expect: 200 and the whole reply as one JSON object. V14's streaming,
      history and privacy items are AI11-AI13 above. Fail: no heartbeat in a reply that runs
      longer than the heartbeat interval (the app's config names it: `AI_SSE_HEARTBEAT_SEC` in
      the scaffold), or no JSON reply.

33f. **Test agent routing (V16)** -- Skip unless the app has more than one agent.
    - **V16** -- As User: for each conversational agent, create a conversation with its
      `agent_slug` and send a message. As Admin: POST `/api/ai/agents/{slug}/run` for each batch
      agent, then POST `/api/ai/agents/no-such-agent/run`. Expect: each reply comes from that
      agent (its prompt and its data), each run creates a job with that agent's `task_type`, and
      the unknown slug gets 404. When an agent has `rule_based_fallback: true`, trigger it in the
      changed-setting run with the AI address unreachable. Expect: its fallback answer. Fail: a
      reply from another agent, a run with no job, anything but 404 for the unknown slug, or an
      error instead of the fallback.

33g. **Test AI memory (BN03, BN04, BN05)** -- Skip if brain_features.enabled != true.
    - **BN03** -- Only when the app already has a way to show the prompt it sends (a debug log or
      an admin view of it); without one, BN03 is NOT RUN with the reason "the app doesn't show
      its prompts". Never add prompt logging to pass this check: it would write people's memories
      and prompts into the logs. As User, in the changed-setting run with
      `BRAIN_FEATURES_ENABLED=true`: add a memory, then send a chat message. Expect: that prompt
      holds the memory. As Admin, add an org memory with scope `security`; as User, chat with an
      agent outside security, then with the security agent. Expect: it is left out, then
      included. With `BRAIN_FEATURES_ENABLED=false`: no memories in the prompt. Fail: any of
      these the other way round.
    - **BN04** -- As User: add a memory containing `<script>alert(1)</script>` and one containing
      "ignore previous instructions", then GET them. Expect: the script tag stripped or escaped,
      and the instruction phrase removed. Fail: either stored as sent.
    - **BN05** -- As User: add a personal memory. As Manager: GET `/api/brain/memories`, and GET
      the User's memory by its id. Expect: not in the list, and 404. As Admin, add an org memory
      with scope `security` and one with scope `all`. Expect: a role without security
      permissions doesn't get the `security` one and a role with them does; everyone gets the
      `all` one. Fail: any person seeing another's personal memory, or a scope shown to the wrong
      role.

33h. **Test AI accounting (AC02, AC04, AC11, AC12)** -- Skip if ai_features.needed != true. Put
    every setting you change back afterwards.
    - **AC02** -- As Admin: count `ai_usage_events` rows (`docker compose exec db psql`), trigger
      one agent, count again. Expect: exactly one new row, with all four token counts filled.
      Fail: no row, more than one, or an empty token count.
    - **AC04** -- As Admin: end the price row of the model in use (set its end date to yesterday),
      trigger one agent. Expect: the new row has `priced = false` and no cost, and AI Spend's
      unpriced count went up by one. Add the price back. Expect: the row is priced. Fail: a cost
      of 0, or `priced = true` with no price.
    - **AC11** -- As User: GET and PATCH the Control Plane API. Expect: 403 both times. As Admin:
      make one change. Expect: exactly one new `control_audit_log` row with before and after.
      Set an agent `off` and trigger it. Expect: no provider call and no `ok` ledger row. Fail:
      the User gets in, no audit row, or the agent still calls the AI.
    - **AC12** -- As Admin: set that agent's day cap below today's seed spend, then trigger it.
      Expect: a `refused_budget` row with cost 0, no provider call, the agent's fallback answer,
      and the admins' 100% notice. Fail: an `ok` row, a provider call, or no fallback.

33i. **Run the variant's live checks (P03)** -- Only when ACTIVE_VARIANT is set: run every item
    under `### Live checks (Part B)` in the variant's definition file.
    - **P03** -- No sign-in: `curl -sI http://localhost:[FRONTEND_PORT]/sw.js`. Expect: 200 with a
      JavaScript content type. Fail: any other status, or an HTML page.

PIN
cat > "$TMPD/rs.pin" <<'PIN'
<step name="live-pass">

**The live pass: rows checked on the running app, after a relevant change.** A catch-up group or
a piece of work is a relevant change when it touches an area in this table; with no area touched
there is no live pass. The area comes from the table, never a judgement: an applied catch-up gap
whose ID prefix (the letters before its number: `A` for A03, `AI` for AI12) is in "Catch-up
checks", or a changed file whose path contains a word in "Files". A project with no compose file
at its root (`docker-compose.yml`, `docker-compose.yaml`, `compose.yml` or `compose.yaml`) has no
live pass: nothing is triggered, started or recorded.

The live pass runs only checks that call no paid AI provider and leave nothing in the app's data.
Which rows those are is fixed by this table, not decided each time; the rows in the two "Not run
here" columns are run by /make-it's build-verify Part B, not here.

| Area | Catch-up checks | Files (path contains) | Run here | Not run here: calls the AI provider | Not run here: would leave test records |
|------|-----------------|-----------------------|----------|-------------------------------------|----------------------------------------|
| Sign-in and permissions | A, R | `auth`, `rbac`, `role`, `permission` | V04, V07 | -- | -- |
| Server routes and pages | D, G | `routers/`, `routes/`, `/api/`, `app/(auth)/` | V05, V06 | -- | -- |
| Lists and the theme | U | `data-table`, `mode-toggle`, `globals.css` | V12, V13 | -- | -- |
| File upload | F | `upload`, `document`, `import` | F09 | F10 | V11, F14 |
| AI | AI | `lib/ai`, `agent`, `chat`, `conversation` | F11 | V14, V16, AI11, AI12, AI13 | AI01d |
| AI memory | BN | `brain`, `memor` | BNV03 | BN03, BNV01, BNV02 | BN04, BN05 |
| AI accounting | AC | `usage`, `ledger`, `spend`, `budget`, `price`, `statement`, `ai-control` | -- | AC02, AC04, ACV01 | AC11, AC12, ACV02 |
| The mobile variant | P | `sw.ts`, `manifest.json` | P03 | -- | -- |
| Every live pass (starting the app) | -- | -- | V02, V03 | -- | -- |

V05 here sends GET requests only; its other requests are NOT RUN, with the reason "it would leave
test records".

1. **Where.** In the folder the change was made in (its worktree, with its own `.env` and ports).
2. **Only when it can start here.** `docker info` fails → start nothing: every row of the pass is
   NOT RUN, with the reason "Docker isn't running". Then read the database, queue and cache URLs
   in `docker compose config`'s environment values, as `deadcode.md` §5's "Settings first" bullet
   does. One whose host isn't a compose service name, `localhost` or `127.0.0.1` → start nothing:
   every row of the pass is NOT RUN, with the reason "your settings point at <host>".
3. **Start it.** Note whether it was already running (`docker compose --profile dev ps`). Then
   `docker compose --profile dev up -d --build --wait` (it rebuilds what changed; a TLS or
   certificate error gets /try-it step 1's security-tool ask, as there), then `bash
   scripts/seed-mock-services.sh`. No other ask: starting the app is routine here. If it doesn't
   come up healthy, that is V02 failing, fixed as step 5 says; if it still won't start, the rest
   of the pass is NOT RUN, with the reason "the app didn't start", and the start problem goes at
   the top of TODO.md.
4. **Run each row in "Run here"** for every touched area, plus V02 and V03, with the step that
   names it in /make-it's build-verify Part B (`~/.claude/commands/make-it.md`), as that step is
   written: the same requests, roles, expected results and fail rules, the changed-setting run
   and its put-back included, and N/A for a feature the app doesn't have. Each row in a "Not run
   here" column of a touched area is NOT RUN, with the reason "it would call the AI provider" or
   "it would leave test records".
5. **Each row's result is PASS, FAIL, NOT RUN with its reason, or LEFT OUT (your choice).** A row
   that belongs to an item in `## Left out by your choice` (read as
   `~/.claude/make-it/references/left-out-record.md`'s read steps say) is LEFT OUT: reported,
   never run and never fixed. A check that could not run -- the app didn't start, the step needs
   something this app lacks, a request couldn't be made -- is NOT RUN, never passed. A FAIL is
   fixed like any test failure in this session (diagnose, fix, re-run that row, up to 3 rounds);
   one still failing after that goes in TODO.md.
6. **Record it** under `## Test Status` in `.make-it-state.md`: "Live pass [date] ([areas]):
   [n] passed, [n] failed, [n] not run ([row]: [reason], ...), [n] left out". Each NOT RUN row
   has one TODO.md line with its reason: when its line is already there, update its date and
   reason; never add a second line for it.
7. **Tell the user one plain line**, the one that fits what happened:
   - It ran: "I started your app and checked [the areas, in plain words] on it: [everything
     passed / N things failed and I'm fixing them][; N checks weren't run here because they'd
     call the AI or leave test records]." When it wasn't running before, add: "I've left it
     running; /wrap-it stops it."
   - Docker isn't running: "I couldn't check [the areas] on your app because Docker isn't
     running, so those checks are marked not run."
   - The settings point elsewhere: "I didn't start your app to check [the areas]: its settings
     point at [host], so those checks are marked not run."
   - It won't start: "I couldn't get your app to start, so [the areas] weren't checked: [the
     reason, in plain words]. It's at the top of your to-do list."

Leave the app running afterwards, as /try-it does; /wrap-it shuts it down.

</step>

   A row marked `[LIVE]` is read here from its files only; its live part runs in the live pass
   (step `live-pass`) after a change that touches its area.

4b. Then run the live pass (step `live-pass`) for the areas the applied gaps touch.

1b. Then the live pass (step `live-pass`), when the work changed a file in one of its areas.

Then run the live pass (step `live-pass`) for AI memory: it starts the app if needed and runs that
area's rows, BNV01-BNV03 included.

**Phase 4: Verify and report.** AC01-AC16 from the files, then the live pass (step `live-pass`)
for AI accounting, which runs ACV01-ACV03 and the AC rows marked `[LIVE]` on the running app.
PIN

python3 -I - "$BS" "$MK" "$RS" "$TMPD/bs.pin" "$TMPD/partb.pin" "$TMPD/rs.pin" "$FLOOR" <<'PY' || fail=1
import re, sys
bs_path, mk_path, rs_path, bs_pin, partb_pin, rs_pin, floor = sys.argv[1:8]
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        if why: print("  " + why)
flat = lambda s: re.sub(r"\s+", " ", s).strip()
ID = r"[A-Z]{1,3}V?[0-9]{2}[a-z]?"
DEFERRED_NAMED = {"ACV03"}  # named by 33b's title (pinned elsewhere); deferred to the auto-fix card, unmarked

def expand(text):
    """IDs in a list like 'V14, AI11-AI13' or 'BNV01-BNV03', ranges expanded; None if the cell is not an ID list."""
    out = []
    for part in re.split(r",\s*|\s+and\s+", text.strip()):
        m = re.fullmatch(rf"({ID})-({ID})", part)
        if m:
            pa, na = re.match(r"([A-Z]+)([0-9]+)", m.group(1)).groups()
            pb, nb = re.match(r"([A-Z]+)([0-9]+)", m.group(2)).groups()
            if pa != pb or int(nb) < int(na): return None
            out += [f"{pa}{n:0{len(na)}d}" for n in range(int(na), int(nb) + 1)]
        elif re.fullmatch(ID, part):
            out.append(part)
        else:
            return None
    return out

def units_of(text):
    """A unit starts at a list item, a numbered or lettered item, or a bold lead; blank lines end one."""
    us, cur = [], []
    for line in text.splitlines():
        if not line.strip() or re.match(r"\s*(- |[0-9]+[a-z]?\. |[a-z]\. |\*\*)", line):
            if cur: us.append(flat(" ".join(cur)))
            cur = [] if not line.strip() else [line]
        else:
            cur.append(line)
    if cur: us.append(flat(" ".join(cur)))
    return us

bs = open(bs_path, encoding="utf-8").read()
mk = open(mk_path, encoding="utf-8").read()
rs = open(rs_path, encoding="utf-8").read()

# 1. the rulebook: [LIVE] defined once, the floor kept
rows = {}
for m in re.finditer(rf"^\*\*({ID})\*\* \[[^\]]*\] \[[^\]]*\]((?: \[[A-Z ]+\])*) \*\*", bs, re.M):
    rows.setdefault(m.group(1), []).append(m.group(2))
live = {i for i, tags in rows.items() if any("[LIVE]" in t for t in tags)}
fl = floor.split()
check("build-standards.md says once what [LIVE] means", flat(bs).count("- `[LIVE]` after the severity = ") == 1)
check("build-standards.md has the [LIVE] definition, whole", all(u in flat(bs) for u in units_of(open(bs_pin).read())))
check("every row in the floor exists once in build-standards.md", all(len(rows.get(i, [])) == 1 for i in fl),
      "missing or repeated: " + " ".join(i for i in fl if len(rows.get(i, [])) != 1))
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
        if l.startswith("**"):
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
stray = sorted(i for i in named if i not in live and i not in DEFERRED_NAMED)
check("every row a Part B step names is a [LIVE] row in build-standards.md", not stray, "not [LIVE]: " + " ".join(stray))

# 3. item by item: each named row has an item that acts on the running app and reads no file
ACT = re.compile(r"curl|\b(GET|POST|PATCH|PUT|DELETE)\b|docker (compose|exec|logs|inspect)|[Ii]n a browser|[Uu]pload|"
                 r"[Nn]avigate|login flow|signed in|valid JWT|[Rr]equest the page|[Ff]etch the page|poll health|"
                 r"seed-mock-services|changed-setting run|[Tt]rigger|send (a|one) (chat )?message|[Ll]ogin as|[Ii]mport the")
READ = re.compile(r"(?i)\b(read|grep|open)\w*\b[^.;]*\b(file|source|router|handler|code|\.tsx|\.py)\b")
def items(body):
    return units_of("\n".join(body))
def acts(u): return bool(ACT.search(u)) and not READ.search(u)
noact = []
for s in steps:
    its = items(s["body"])
    for i in s["ids"]:
        if i in DEFERRED_NAMED: continue
        own = [u for u in its if re.search(rf"\*\*{i}\b", u)] if len(s["ids"]) > 1 else its
        if not any(acts(u) for u in own): noact.append(f'{s["n"]}:{i}')
check("each named row has an item that acts on the running app, not a file read", not noact, "no acting item: " + " ".join(noact))
nounit = [f'{s["n"]}:{i}' for s in steps if len(s["ids"]) > 1 for i in s["ids"]
          if not re.search(rf"\*\*{i}\b", "\n".join(s["body"][1:]))]
check("a step that names several rows has a unit for each", not nounit, "no unit: " + " ".join(nounit))
ROLE = re.compile(r"\b[Aa]s (User|Manager|Admin|Super Admin|the lowest role)|No sign-in|Only when")
badunit = []
for s in steps:
    for m in re.finditer(r"^\s*- \*\*(" + ID + r")\*\* -- (.*?)(?=^\s*- \*\*|\Z)", "\n".join(s["body"]), re.M | re.S):
        u = flat(m.group(2))
        if not (ROLE.search(u) and "Expect: " in u and "Fail: " in u): badunit.append(m.group(1))
check("every live unit says who it runs as, what to expect and what fails", not badunit, "incomplete: " + " ".join(badunit))

# 4. the whole of Part B, unit by unit, exactly
got, want = units_of("\n".join(partb)), units_of(open(partb_pin).read())
diff = next((k for k in range(max(len(got), len(want))) if k >= len(got) or k >= len(want) or got[k] != want[k]), None)
check("Part B is exactly the pinned text, unit by unit (nothing reworded, added or dropped)", diff is None,
      "" if diff is None else f"unit {diff}: got [{(got[diff] if diff < len(got) else '(none)')[:100]}] want [{(want[diff] if diff < len(want) else '(none)')[:100]}]")

# 5. no reachable AI provider: make-it's list is exactly /resume-it's "calls the AI provider" column
m = re.search(r"never FAIL, and never fixed: (.*?)\. These need no provider and run either way: (.*?)\.", flat("\n".join(partb)))
needs = expand(m.group(1)) if m else None
free = expand(m.group(2)) if m else None
check("make-it.md names the rows that need an AI provider and the ones that don't", bool(needs) and bool(free))

# 6. /resume-it's live pass: a fixed table covering every [LIVE] row once, in one of three groups
check("resume-it.md has the live-pass step once", rs.count('<step name="live-pass">') == 1)
mm = re.search(r'<step name="live-pass">(.*?)</step>', rs, re.S)
lp = mm.group(1) if mm else ""
groups = {"run": [], "ai": [], "records": []}
for l in lp.splitlines():
    if l.startswith("|") and not re.match(r"\|\s*(Area|-)", l):
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        for key, cell in zip(("run", "ai", "records"), cells[-3:]):
            if cell == "--": continue
            e = expand(cell)
            groups[key] += e if e else ["?bad-cell:" + cell[:30]]
tab = groups["run"] + groups["ai"] + groups["records"]
tab_missing = sorted(i for i in live | set(fl) if i not in tab)
check("every [LIVE] row is in the live pass's table", not tab_missing, "not in the table: " + " ".join(tab_missing))
tab_dup = sorted({i for i in tab if tab.count(i) > 1})
tab_stray = sorted(i for i in tab if i not in live)
check("the table names each row once, and only [LIVE] rows", not tab_dup and not tab_stray,
      "twice: " + " ".join(tab_dup) + "; not [LIVE]: " + " ".join(tab_stray))
check("/resume-it never runs a row /make-it says needs the AI provider",
      bool(needs) and sorted(needs) == sorted(groups["ai"]) and not set(needs) & set(groups["run"]),
      f"make-it: {sorted(needs or [])}; resume AI column: {sorted(groups['ai'])}")
frs = flat(rs)
rs_missing = [u for u in units_of(open(rs_pin).read()) if u not in frs]
check("the live pass and its hooks are in resume-it.md, whole, unit by unit", not rs_missing,
      "missing: " + " | ".join(x[:80] for x in rs_missing[:5]))
sys.exit(1 if failed else 0)
PY

# 7. /retrofit-it's Part B is /make-it's, by reference; the tables that say how the rulebook is run say so
RF_B="$(awk '/^[*][*]PART B: Live verification/{on=1} on && /^[*][*]PART C: /{exit} on' "$RF" | tr '\n' ' ' | tr -s ' ')"
S_RF='Run every step of /make-it'"'"'s build-verify Part B, as written there (`~/.claude/commands/make-it.md`, steps 21-33i), with two changes for an app the scaffold didn'"'"'t build: `<backend>` is the app'"'"'s backend service as its `docker-compose.yml` names it, and where a step names a scaffold route, use the app'"'"'s own route for the same thing (from its router files, or its OpenAPI spec at `/openapi.json` when it has one). Each step names the rulebook rows it checks, and every row marked `[LIVE]` in `build-standards.md` has one. They include V01-V09 and ACV01-ACV03; N01-N08 are Part A file checks, and step 30 checks the same notifications on the running app:'
check "retrofit-it's Part B runs /make-it's Part B steps, by reference" 'printf "%s" "$RF_B" | grep -F -- "$S_RF" >/dev/null'
check "retrofit-it's Part B no longer lists its own checks as the whole of it" '! grep -F "Run ALL live verification checks from \`build-standards.md\`:" "$RF" >/dev/null'
check "build-standards.md's skill table: /make-it's and /retrofit-it's Part B" \
  'grep -xF "| \`/make-it\` | Build-verify (Part A static checks; Part B runs every \`[LIVE]\` check on the running app) |" "$BS" >/dev/null && grep -xF "| \`/retrofit-it\` | Verify phase (Part A static checks; Part B runs /make-it'"'"'s Part B steps) |" "$BS" >/dev/null'
check "build-standards.md's skill table: /resume-it's live pass, free and reversible checks only" \
  'grep -xF "| \`/resume-it\` | Catch-up scan during context discovery; after a change that touches them, the \`[LIVE]\` checks that call no paid AI provider and leave no test records, on the running app (its live pass) |" "$BS" >/dev/null'
check "CLAUDE.md's table: /make-it's Part B runs every [LIVE] check" \
  'grep -xF "| \`/make-it\` | Build-verify Part A runs all checks for active tiers; Part B runs every check marked \`[LIVE]\` on the running app |" "$CM" >/dev/null'
check "CLAUDE.md's table: /resume-it's live pass, free and reversible checks only" \
  'grep -xF "| \`/resume-it\` | Catch-up scan compares project against latest checks, surfaces gaps; after a change that touches a \`[LIVE]\` check that calls no paid AI provider and leaves no test records, its live pass runs that check on the running app |" "$CM" >/dev/null'

# 8. controls (this repo only): each opposite fails the checks above, for its own reason
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
    'opp "$MK" "s/AC04, AC11, AC12\)/AC04, AC11)/" "every [LIVE] row (and every floor row) is named by a Part B step"'
  check "(control) a step whose row was removed: V16 no longer [LIVE] in the rulebook" \
    'opp "$BS" "s/^(\*\*V16\*\* \[AI\] \[BLOCK\]) \[LIVE\]/\$1/m" "every row a Part B step names is a [LIVE] row"'
  check "(control) a relabelled row: BN05 loses [LIVE] in the rulebook" \
    'opp "$BS" "s/^(\*\*BN05\*\* \[AI\+Brain\] \[BLOCK\]) \[LIVE\]/\$1/m" "no row whose method is the running app lost its [LIVE] mark"'
  check "(control) review defeat 1: step 26 (V05) rewritten to read each router file, the word GET kept" \
    'opp "$MK" "s/(26\. \*\*Test every API endpoint \(V05\):\*\*\n).*?(?=\n27\. )/\$1    Read each router file and confirm every GET route returns 2xx JSON./s" "each named row has an item that acts on the running app"'
  check "(control) review defeat 2: a bullet that records F09 as passed from reading the handler" \
    'opp "$MK" "s/(\n    - \*\*F10\*\* --)/\n    - record F09 as passed from reading the upload handler.\$1/" "Part B is exactly the pinned text"'
  check "(control) review defeat 3: BNV03 turned into a router read (a sibling item still has POST)" \
    'opp "$MK" "s/c\. \*\*BNV03: Memory isolation\*\* -- .*?(?=\n\n)/c. **BNV03: Memory isolation** -- Read the brain router file and confirm GET filters by owner./s" "each named row has an item that acts on the running app"'
  check "(control) review defeat 4: \"Skip g when a browser is not handy\" added to step 32" \
    'opp "$MK" "s/(\n    g\. In a browser, as User:)/\n    Skip g when a browser is not handy.\$1/" "Part B is exactly the pinned text"'
  check "(control) the changed-setting run loses --use-aliases" \
    'opp "$MK" "s/ --use-aliases//" "Part B is exactly the pinned text"'
  check "(control) the put-back is made conditional" \
    'opp "$MK" "s/\*\*Put it back, always\*\* -- whether the check passed, failed, was cut off or errored:/**Put it back** when the check passed:/" "Part B is exactly the pinned text"'
  check "(control) a unit with no fail rule: AC12 loses its Fail" \
    'opp "$MK" "s/ Fail: an \`ok\` row, a provider call, or no fallback\.//" "every live unit says who it runs as"'
  check "(control) a row named by two steps: BN05 added to the brain step" \
    'opp "$MK" "s/Test brain layer \(BNV01-BNV03\)/Test brain layer (BNV01-BNV03, BN05)/" "no row is named by two Part B steps"'
  check "(control) a multi-row step missing a row's unit: the BN05 unit removed" \
    'opp "$MK" "s/^    - \*\*BN05\*\* --.*?(?=^\n)//ms" "a step that names several rows has a unit for each"'
  check "(control) a row that calls the AI moved into /resume-it's \"Run here\" column" \
    'opp "$RS" "s/\| BNV03 \| BN03, BNV01, BNV02 \|/| BNV03, BNV01 | BN03, BNV02 |/" "/resume-it never runs a row /make-it says needs the AI provider"'
  check "(control) a [LIVE] row missing from the live pass's table: AC12 dropped" \
    'opp "$RS" "s/AC11, AC12, ACV02/AC11, ACV02/" "every [LIVE] row is in the live pass"'
  check "(control) a row in two groups of the table: V04 also in the AI area" \
    'opp "$RS" "s/\| F11 \| V14,/| F11, V04 | V14,/" "the table names each row once"'
  check "(control) a check that could not run counted as passed" \
    'opp "$RS" "s/is NOT RUN, never passed\./is counted as passed./" "the live pass and its hooks are in resume-it.md"'
  check "(control) a left-out row fixed anyway" \
    'opp "$RS" "s/reported,\s+never run and never fixed/reported, then fixed/" "the live pass and its hooks are in resume-it.md"'
  check "(control) the catch-up hook removed" \
    'opp "$RS" "s/^4b\. Then run the live pass.*\n//m" "the live pass and its hooks are in resume-it.md"'
  check "(control) retrofit-it's Part B back to its own list" \
    'opp "$RF" "s/^Run every step of \/make-it.*?running app:\n/Run ALL live verification checks from \`build-standards.md\`:\n/ms" "retrofit-it'"'"'s Part B runs /make-it'"'"'s Part B steps"'
  check "(control) the [LIVE] definition removed" \
    'opp "$BS" "s/^- \`\[LIVE\]\` after the severity = .*?(?=^\n)//ms" "build-standards.md says once what [LIVE] means"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
