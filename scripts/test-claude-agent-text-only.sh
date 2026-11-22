#!/usr/bin/env bash
# test-claude-agent-text-only.sh -- contract test for board card E02-S70.
#
# The scaffold's Claude-subscription provider (claude_agent.py) sends text typed by an app's users to the Claude
# Code CLI, a coding agent. It used to pass allowed_tools=[] with permission_mode="bypassPermissions" and call that
# "no tools". The Agent SDK documents allowed_tools as a pre-approval list ("This does not restrict Claude to only
# these tools") and says of the bypass mode that "calls to tools you didn't list are approved too".
#
# What this pins:
#   - the provider never names the bypass mode, and asks for dontAsk;
#   - tools=[] and a disallowed list naming every built-in tool (this script's own copy of the list, the provider's
#     and the scaffold unit test's must be the same NTOOLS names), plus the * and mcp__* globs;
#   - nothing is loaded from disk or saved to it (--no-session-persistence), and the CLI runs in an empty directory;
#   - query() is called in one place; there the CLI's session report is checked before any reply is read, and every
#     message is checked for a sign of a tool; complete() and stream() both read that one place;
#   - a stopped call is its own error, which the failover provider does not retry;
#   - every build step that adds claude-agent-sdk pins it;
#   - build-standards AI29 exists, is [BLOCK] and [SECURITY FIX], says which part prevents and which only detects, and
#     applies its pin and test conditions only to an app that uses the provider; /resume-it presents it first and
#     "Not now" does not put it off; the AI check ranges include it.
# Then planted defects, each in a throwaway copy (the real files are never edited): each must fail.
# Last, when Python has pytest and the scaffold's packages, the scaffold's own test file is run (with the real SDK
# if it is installed). REQUIRE_SCAFFOLD_PYTEST=1 turns "not available" from a note into a failure; CI sets it.
# A wording test is a tripwire, not a proof. It reads files; it makes no model call and needs no sign-in token. What
# the options do to a live assistant is covered by the live check in AI29, not here.
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

PIN='claude-agent-sdk>=0.2.186,<0.3'
REL_PF=.claude/make-it/scaffolds/fastapi-nextjs/backend/app/lib/ai/providers/claude_agent.py
REL_UT=.claude/make-it/scaffolds/fastapi-nextjs/backend/tests/unit/test_claude_agent_text_only.py
REL_MK=.claude/commands/make-it.md
REL_RS=.claude/commands/resume-it.md
REL_BS=.claude/make-it/references/build-standards.md
REL_PT=.claude/make-it/references/prompt-templates.md
REL_DB=.claude/make-it/references/design-blueprint.md
REL_GR=.claude/make-it/references/guardrails.md
REL_ER=.claude/make-it/scaffolds/fastapi-nextjs/backend/app/lib/ai/errors.py
REL_FO=.claude/make-it/scaffolds/fastapi-nextjs/backend/app/lib/ai/providers/failover.py
REL_RQ=.claude/make-it/scaffolds/fastapi-nextjs/backend/requirements.txt
REL_RF=.claude/commands/retrofit-it.md
REL_GV=docs/AI-GOVERNANCE-HOMEGROWN.md
FILES="$REL_PF $REL_UT $REL_MK $REL_RS $REL_BS $REL_PT $REL_DB $REL_GR $REL_ER $REL_FO $REL_RQ $REL_RF $REL_GV"

# This script's own copy of the built-in tool names (the CLI's tools reference, plus Task, the Agent tool's old name).
NTOOLS=54
TOOLS="Agent Artifact AskUserQuestion Bash CronCreate CronDelete CronList Edit EndConversation EnterPlanMode
EnterWorktree ExitPlanMode ExitWorktree Glob Grep ListAgents ListMcpResourcesTool ListPlugins ListSkills LSP Monitor
NotebookEdit PowerShell propose_skills PushNotification Read ReadMcpResourceTool RemoteTrigger ReportFindings
ScheduleWakeup SearchPlugins SearchSkills SendFeedback SendMessage SendUserFile ShareOnboardingGuide Skill
SubagentHandback SuggestPluginInstall SuggestSkills Task TaskCreate TaskGet TaskList TaskOutput TaskStop TaskUpdate
TodoWrite ToolSearch WaitForMcpServers WebFetch WebSearch Workflow Write"

# the names in a Python file's BUILTIN_TOOLS, one per line, sorted (a tuple of strings, or a """...""".split())
tools_in() {
  python3 -I - "$1" <<'PY'
import ast, sys
for node in ast.walk(ast.parse(open(sys.argv[1]).read())):
    if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "BUILTIN_TOOLS" for t in node.targets):
        v = node.value
        names = ast.literal_eval(v.func.value).split() if isinstance(v, ast.Call) else ast.literal_eval(v)
        print("\n".join(sorted(names)))
PY
}
# text between the first line matching $2 and the next line matching $3 in file $1 (start line included)
between() { awk -v a="$2" -v b="$3" 'on && $0 ~ b {on=0} $0 ~ a {on=1} on' "$1"; }
# the lines of file $1 from the first line matching $2 to the end
from() { awk -v a="$2" '$0 ~ a {on=1} on' "$1"; }

GUARDED='            async with aclosing(self._text_only(system_prompt, user_prompt, model)) as messages:'

# verify ROOT: every check, against the tree at ROOT. Returns 1 when any fails.
verify() {
  local R="$1" PF="$1/$REL_PF" UT="$1/$REL_UT" MK="$1/$REL_MK" RS="$1/$REL_RS" BS="$1/$REL_BS" PT="$1/$REL_PT" DB="$1/$REL_DB" GR="$1/$REL_GR"
  local ER="$1/$REL_ER" FO="$1/$REL_FO" RQ="$1/$REL_RQ" RF="$1/$REL_RF" GV="$1/$REL_GV"
  local WANT OPT TXT CPL STR AI29 HOOK SEC f
  fail=0
  for f in $FILES; do check "found: $f" '[ -s "$R/$f" ]'; done
  WANT="$(printf "%s\n" $TOOLS | LC_ALL=C sort)"
  OPT="$(between "$PF" '^    def _options[(]' '^    async def _text_only[(]')"
  TXT="$(between "$PF" '^    async def _text_only[(]' '^    async def complete[(]')"
  CPL="$(between "$PF" '^    async def complete[(]' '^    async def stream[(]')"
  STR="$(from "$PF" '^    async def stream[(]')"
  AI29="$(grep -E '^[*][*]AI29[*][*] ' "$BS" || true)"
  HOOK="$(between "$PF" '^async def _refuse_tool[(]' '^_workdir: ')"
  SEC="$(between "$RS" '^[*][*]A security fix comes first, on its own[.][*][*]' '^[*][*]When standards gaps are found' | tr '\n' ' ' | tr -s ' ')"

  # 1. the permission mode
  check "provider: the bypass mode is named nowhere in the file" '[ "$(grep -c "bypassPermissions" "$PF")" = 0 ]'
  check "provider: the mode is set once, to dontAsk" \
    '[ "$(grep -c "permission_mode=" "$PF")" = 1 ] && lines "$PF" "            permission_mode=\"dontAsk\"," 1'
  check "provider: nothing skips permissions another way" '[ "$(grep -ciE "dangerously|skip-permissions|acceptEdits" "$PF")" = 0 ]'

  # 2. no tools in the model's context
  check "this script lists $NTOOLS built-in tool names, no duplicates" \
    '[ "$(printf "%s\n" "$WANT" | grep -c .)" = "$NTOOLS" ] && [ "$(printf "%s\n" "$WANT" | uniq -d | grep -c .)" = 0 ]'
  check "provider: BUILTIN_TOOLS is exactly those $NTOOLS names" '[ "$(tools_in "$PF")" = "$WANT" ]'
  check "scaffold unit test: its own BUILTIN_TOOLS is the same $NTOOLS names" '[ "$(tools_in "$UT")" = "$WANT" ]'
  check "provider: the disallowed list is every built-in tool plus the * and mcp__* globs" \
    'lines "$PF" "DISALLOWED_TOOLS = [*BUILTIN_TOOLS, \"*\", \"mcp__*\"]" 1'
  check "provider options: tools=[] and that disallowed list" \
    'printf "%s\n" "$OPT" | gq -xF "            tools=[]," && printf "%s\n" "$OPT" | gq -xF "            disallowed_tools=list(DISALLOWED_TOOLS),"'
  check "provider: no allowed_tools option is passed (it pre-approves, it does not restrict)" \
    '[ "$(grep -cE "(^|[^s])allowed_tools *=" "$PF")" = 0 ]'
  check "provider options: a hook refuses every tool call and fails closed" \
    'printf "%s\n" "$OPT" | gq -xF "            hooks={\"PreToolUse\": [HookMatcher(matcher=None, hooks=[_refuse_tool], on_failure=\"block\")]},"'
  check "the hook has one way out, and it is a denial" \
    '[ "$(printf "%s\n" "$HOOK" | grep -c "return")" = 1 ] && printf "%s\n" "$HOOK" | gq -xF "    return {" && printf "%s\n" "$HOOK" | gq -xF "            \"permissionDecision\": \"deny\","'
  check "provider options: the CLI runs restricted, with skills and commands off, and saves no transcript" \
    'printf "%s\n" "$OPT" | gq -xF "            extra_args={\"restricted\": None, \"disable-slash-commands\": None, \"no-session-persistence\": None},"'

  # 3. nothing loaded from disk
  for f in 'setting_sources=[],' 'skills=[],' 'mcp_servers={},' 'strict_mcp_config=True,' 'cwd=_empty_workdir(),'; do
    check "provider options: $f" 'printf "%s\n" "$OPT" | gq -xF "            $f"'
  done
  check "provider options: auto memory, CLAUDE.md and claude.ai connectors are off" \
    'printf "%s\n" "$OPT" | gq -xF "                \"CLAUDE_CODE_DISABLE_AUTO_MEMORY\": \"1\"," && printf "%s\n" "$OPT" | gq -xF "                \"CLAUDE_CODE_DISABLE_CLAUDE_MDS\": \"1\"," && printf "%s\n" "$OPT" | gq -xF "                \"ENABLE_CLAUDEAI_MCP_SERVERS\": \"false\","'
  check "provider: the working directory is made for the purpose and must be empty" \
    'lines "$PF" "        _workdir = tempfile.mkdtemp(prefix=\"claude-text-only-\")" 1 && lines "$PF" "    if os.listdir(_workdir):" 1'
  check "provider options: no directory, plugin, agent or settings file is added" \
    '[ "$(printf "%s\n" "$OPT" | grep -cE "^ +(add_dirs|plugins|agents|settings)=")" = 0 ]'

  # 4. the tripwire
  check "provider: query() is called with arguments in exactly one place" '[ "$(grep -cE "query[(][^)]" "$PF")" = 1 ]'
  check "provider: query is imported once, under its own name, and the SDK module under one alias" \
    '[ "$(grep -cE "import.*query" "$PF")" = 1 ] && lines "$PF" "        from claude_agent_sdk import AssistantMessage, SystemMessage, UserMessage, query" 1 && [ "$(grep -cE "claude_agent_sdk.* as " "$PF")" = 1 ] && lines "$PF" "    import claude_agent_sdk as sdk" 1 && [ "$(grep -c "sdk[.]query" "$PF")" = 0 ]'
  check "tripwire: that one call is in _text_only, closed on the way out" \
    'printf "%s\n" "$TXT" | gq -xF "        async with aclosing(query(prompt=user_prompt, options=options)) as messages:"'
  check "session check: the CLI's report is read first, and a reply with no report before it ends the call" \
    '[ "$(printf "%s\n" "$TXT" | grep -nxF -e "                if isinstance(message, SystemMessage) and message.subtype == \"init\":" -e "                    sign = _session_problem(message.data)" -e "                elif not session_checked and isinstance(message, (AssistantMessage, UserMessage)):  # noqa: UP038 -- AI29'"'"'s provider, left as written (follow-up card)" -e "                    sign = _tool_activity(message)" -e "                    raise AIToolActivityError(\"stopped a text-only call (the sign is in the log)\")" -e "                yield message" | grep -c .)" = 6 ] && [ "$(printf "%s\n" "$TXT" | grep -nxF -e "                    sign = _tool_activity(message)" -e "                    raise AIToolActivityError(\"stopped a text-only call (the sign is in the log)\")" -e "                yield message" | cut -d: -f2- | tr -s " " | tr "\n" "|")" = " sign = _tool_activity(message)| raise AIToolActivityError(\"stopped a text-only call (the sign is in the log)\")| yield message|" ]'
  check "session check: any tool, any MCP server, or a mode other than dontAsk is a problem" \
    'lines "$PF" "    if data.get(\"tools\") != []:" 1 && lines "$PF" "    if data.get(\"mcp_servers\") != []:" 1 && lines "$PF" "    if data.get(\"permissionMode\") != \"dontAsk\":" 1'
  check "tripwire: only text and thinking blocks pass" \
    'lines "$PF" "                if not isinstance(block, (sdk.TextBlock, sdk.ThinkingBlock)):  # noqa: UP038 -- AI29'"'"'s provider, left as written (follow-up card)" 1'
  check "tripwire: a tool result, a refused call, a deferred call and a task message are signs too" \
    'lines "$PF" "        if getattr(message, \"tool_use_result\", None) is not None:" 1 && lines "$PF" "        if getattr(message, \"permission_denials\", None):" 1 && lines "$PF" "        if getattr(message, \"deferred_tool_use\", None) is not None:" 1 && lines "$PF" "        (sdk.TaskStartedMessage, sdk.TaskProgressMessage, sdk.TaskNotificationMessage, sdk.TaskUpdatedMessage)," 1'
  check "complete() reads the stream through the tripwire, and no other way" \
    '[ "$(printf "%s\n" "$CPL" | grep -cxF -- "$GUARDED")" = 1 ] && [ "$(printf "%s\n" "$CPL" | grep -c "async for ")" = 1 ]'
  check "stream() reads the stream through the tripwire, and no other way" \
    '[ "$(printf "%s\n" "$STR" | grep -cxF -- "$GUARDED")" = 1 ] && [ "$(printf "%s\n" "$STR" | grep -c "async for ")" = 1 ]'
  check "both methods still raise other errors through the sanitised error path, and a stopped call as itself" \
    '[ "$(grep -cxF "            raise sanitize_ai_error(exc) from exc" "$PF")" = 2 ] && [ "$(grep -cxF "        except AIToolActivityError:" "$PF")" = 2 ]'
  check "a stopped call is its own error with the generic message, and failover does not retry it" \
    'lines "$ER" "class AIToolActivityError(AIProviderError):" 1 && [ "$(grep -cxF "            except AIToolActivityError:" "$FO")" = 2 ] && [ "$(grep -cxF "                raise  # a security stop, not an outage: no second provider, primary stays in use" "$FO")" = 2 ]'
  check "the file says which control prevents and which only detects, and that prompts can be kept on disk" \
    'lines "$PF" "  DETECT    \`_tool_activity()\`: reads the reply for a sign of a tool. This does NOT" 1 && lines "$PF" "            from the user, and leaves a log line. It is the alarm, not the lock." 1 && lines "$PF" "DATA KEPT ON DISK. The CLI normally saves each session -- the system prompt (which can" 1 && lines "$PF" "    catches a dropped block." 1'
  check "the unit test no longer claims an unknown block type is caught" \
    '[ "$(grep -c "BlockFromALaterSdk\|does not know\"" "$UT")" = 0 ] && lines "$UT" "def test_a_block_type_the_real_parser_does_not_know_is_dropped_before_the_tripwire_can_see_it():" 1'

  # 5. the SDK is pinned wherever a build step adds it
  check "make-it Design step: the build adds the pinned SDK" \
    'lines "$MK" "    -> When chosen, the Build phase must add \`$PIN\` to requirements, install the" 1'
  check "make-it step 9a: the build adds the pinned SDK, never the bare name" \
    'lines "$MK" "     a. Add \`$PIN\` to backend/requirements.txt -- pinned, never bare: the provider'"'"'s" 1'
  check "make-it step 9b says why the provider must keep tools off" \
    'tr "\n" " " < "$MK" | tr -s " " | gq -F "This CLI is a coding agent that can run commands and read files in the container, and the prompts it gets are typed by the app'"'"'s users, so the provider must keep every tool off (build-standards AI29)."'
  check "prompt-templates, design-blueprint, guardrails and AI01d name the pinned SDK" \
    'lines "$PT" "    │   - When selected: add $PIN to requirements, install the Claude Code" 1 && lines "$DB" "1. Add \`$PIN\` to \`backend/requirements.txt\`." 1 && [ "$(grep -cF "add \`$PIN\` to requirements" "$GR")" = 1 ] && [ "$(grep -E "^[*][*]AI01d[*][*] " "$BS" | grep -cF "(1) add \`$PIN\` to \`backend/requirements.txt\` (pinned, never bare);")" = 1 ]'
  check "the provider's own header names the pinned SDK" 'lines "$PF" "  - add \`$PIN\` to requirements.txt" 1'
  check "no build step adds the bare package" \
    '[ "$(cat "$MK" "$PT" "$DB" "$GR" "$BS" "$PF" | grep -ciE "add \`?claude-agent-sdk\`? to")" = 0 ]'

  # 6. the documents say what is true
  check "prompt-templates no longer says single-shot/no-tools; it names the real controls, and that the reply check only detects" \
    '[ "$(grep -c "single-shot/no-tools" "$PT")" = 0 ] && lines "$PT" "    │     dontAsk (never bypassPermissions), nothing loaded from disk or saved to it. The CLI'"'"'s" 1 && lines "$PT" "    │     ends the call, which detects but does not prevent (build-standards AI29)" 1'
  check "guardrails: an empty allowed_tools list is not a restriction" \
    '[ "$(grep -c "no-tools mode" "$GR")" = 0 ] && tr "\n" " " < "$GR" | tr -s " " | gq -F "a reply that shows a tool ends the call, which detects but does not prevent (build-standards AI29). An empty \`allowed_tools\` list is not a restriction."'
  check "design-blueprint: the provider rule stays, with the text-only sentence after it" \
    'lines "$DB" "       do NOT default a multi-user app to claude_agent]" 1 && tr "\n" " " < "$DB" | tr -s " " | gq -F "do NOT default a multi-user app to claude_agent] The claude_agent provider is configured text-only (no tools, nothing loaded from the container), and build check AI29 verifies it."'

  # 7. the build check
  has29() { printf "%s" "$AI29" | gq -F -- "$1"; }
  check "build-standards: AI29 exists once, is [BLOCK] and [SECURITY FIX], and is this check" \
    '[ "$(grep -cE "^[*][*]AI29[*][*] " "$BS")" = 1 ] && [ "$(grep -cE "^[*][*]AI29[*][*] \[AI\] \[BLOCK\] \[SECURITY FIX\] [*][*]Claude-subscription provider is text-only \(claude_agent\)[*][*] -- " "$BS")" = 1 ]'
  check "build-standards says once what [SECURITY FIX] means" \
    'lines "$BS" "- \`[SECURITY FIX]\` after the severity = the check closes a hole that is open now in apps already built." 1'
  check "AI29 part 1 applies whenever the file exists, and fails on the bypass mode" \
    'has29 "**Part 1, the provider file** -- applies whenever the app has \`lib/ai/providers/claude_agent.py\`, whichever provider is selected:" && has29 "(1) \`bypassPermissions\` appears anywhere in the file, or \`permission_mode\` is not \`\"dontAsk\"\`;"'
  check "AI29 (2) requires tools=[]" 'has29 "(2) the options do not set \`tools=[]\`, or"'
  check "AI29 (2) requires every built-in tool and both globs" \
    'has29 "\`disallowed_tools\` does not name every built-in tool in the scaffold'"'"'s \`BUILTIN_TOOLS\` plus \`\"*\"\` and \`\"mcp__*\"\` -- an \`allowed_tools\` list, empty or not, only pre-approves and is not a restriction;"'
  check "AI29 (3) requires nothing loaded from disk or saved to it" \
    'has29 "(3) the options do not set \`setting_sources=[]\`, \`skills=[]\`, \`strict_mcp_config=True\`, \`--restricted\` and \`--no-session-persistence\`, or they name an MCP server, or \`cwd\` is not an empty directory made for the purpose;"'
  check "AI29 (4) requires the one guarded reader, the session check and the reply check" \
    'has29 "(4) the file calls \`query(\` anywhere but inside \`_text_only\`, or \`complete()\` or \`stream()\` reads the SDK'"'"'s stream another way, or \`_text_only\` does not end the call in each of these cases: the CLI'"'"'s \`init\` report shows a tool, an MCP server or a permission mode other than \`dontAsk\`; a reply arrives before any \`init\` report; a message shows a tool-use block, a tool result, a task message, or a refused or deferred tool call."'
  check "AI29 part 2 applies only to an app that uses the provider, and says how that is read" \
    'has29 "**Part 2, the app that uses it** -- applies only when the provider is selected or its SDK is declared, which is any one of: \`ai_providers.primary\` is \`\"claude_agent\"\` in \`app-context.json\`; \`AI_PROVIDER=claude_agent\` in \`.env\`, \`.env.example\` or the backend service of \`docker-compose.yml\`; \`claude-agent-sdk\` appears in \`backend/requirements.txt\`. Otherwise (5) and (6) are N/A, and an app on another provider passes AI29 on Part 1 alone."'
  check "AI29 (5) the pin and (6) the test" \
    'has29 "(5) \`backend/requirements.txt\` does not pin \`$PIN\` (one exact version inside that range also passes; the bare name fails);" && has29 "(6) \`tests/unit/test_claude_agent_text_only.py\` is missing or does not pass."'
  check "the scaffold as shipped is such an app: it declares no SDK, so only part 1 applies to it (and part 1 is checked above)" \
    '[ "$(grep -ci "claude-agent-sdk" "$RQ")" = 0 ]'
  check "AI29 says which part prevents and that the reply check only detects" \
    'has29 "What each part can do: the options in (1)-(3) prevent a tool from running. The \`init\` check can end a call before the model'"'"'s reply is read. The check of the reply only detects: the CLI runs a tool itself right after it sends the message that holds the call, so a fast command can finish before the call is ended; that check limits what follows and leaves a log line."'
  check "AI29 states the data-retention limit, the inherited environment, the dropped blocks and that nothing here is a live call" \
    'has29 "(a) data kept on disk -- without \`--no-session-persistence\` the CLI saves each call'"'"'s system prompt, user prompt and reply in plaintext under \`~/.claude/projects/\` in the backend container, for 30 days by default; the flag was confirmed to be accepted the way the SDK starts the CLI and to turn transcript writes off in the CLI'"'"'s own code, and was not observed during a live call;" && has29 "(b) the CLI process still inherits the backend'"'"'s environment" && has29 "(c) the SDK'"'"'s parser drops content blocks of a type it does not know before the provider sees them" && has29 "(d) no check here makes a model call"'
  check "AI29 says how an app built before it is fixed" \
    'has29 "An app built before this check fails it; /resume-it'"'"'s catch-up presents it first, as a security fix."'
  # E02-S66 moved this pin: AI30 now follows AI29. It still proves AI29 is there, right before the last AI check, and
  # that no range is stale (AI01-AI0x to AI01-AI29 included).
  check "AI29 is followed only by AI30, the last AI check, and every range reads AI01-AI30" \
    '[ "$(grep -oE "^[*][*]AI[0-9]+[a-d]?[*][*]" "$BS" | tail -2 | tr "\n" " ")" = "**AI29** **AI30** " ] && [ "$(grep -cE "^[*][*]AI[0-9]+[a-d]?[*][*]" "$BS")" = 34 ] && [ "$(cat "$MK" "$RS" "$RF" "$GV" | grep -cE "AI01-AI([0-9]|1[0-9]|2[0-9])\b")" = 0 ] && [ "$(grep -c "^- [*][*]AI01-AI30[*][*]: " "$MK")" = 1 ] && [ "$(grep -c "^   - [*][*]AI (AI01-AI30):[*][*] " "$RS")" = 1 ] && lines "$RF" "- **AI01-AI30**: AI features (if ai_features.needed = true; AI30 runs on every app)" 1 && lines "$GV" "| AI Features | AI01-AI30 (incl. AI01a-AI01d) | 34 | AI (any type); AI30: 0 (Universal) |" 1'
  check "resume-it's catch-up reads the provider for AI29" \
    'gq -F "a text-only Claude-subscription provider (AI29: read \`lib/ai/providers/claude_agent.py\`; an app built before the check fails it and is fixed from the scaffold'"'"'s copy)" "$RS"'
  # 8. /resume-it: a security fix is not an offer
  check "resume-it: a [SECURITY FIX] gap is kept out of the groups and comes first, on its own" \
    'lines "$RS" "   - **Security fixes** (a GAP on a check marked \`[SECURITY FIX]\`, AI29 for example): not in any of" 1 && [ -n "$SEC" ] && printf "%s" "$SEC" | gq -F "is a security finding, not an offer: something in the app is open now. It is not in [N], the counts, the must-do or improvements groups, or their ask. Say it before the suggestions above and before the catch-up ask, one finding at a time"'
  check "resume-it: the ask says what is exposed, that a local app is exposed too, the evidence, the fix, the undo and the one thing to check" \
    'printf "%s" "$SEC" | gq -F "\"Before anything else: your app has a security problem that is open right now. What is exposed: [" && printf "%s" "$SEC" | gq -F "This applies even while the app only runs on this computer. What I saw: [" && printf "%s" "$SEC" | gq -F "The fix: [" && printf "%s" "$SEC" | gq -F "Undo: it is one saved change, and I can take it back. The one thing to check: after the fix, ask the AI a question and see that it still answers.\""'
  check "resume-it: two named options, and the recommended one carries its catch" \
    'printf "%s" "$SEC" | gq -F "Two named options: \"Fix it now (Recommended -- the catch: your app restarts)\" and \"Not now\"."'
  check "resume-it: Not now lets the session go on and nothing else -- never put off, never left out, asked first every session, still blocks the handoff" \
    'printf "%s" "$SEC" | gq -F "the user carries on with other work this session. That is all it does. A security finding is never put off (approval-block.md), so: it is not written under \`## Put off by your choice\` or \`## Left out by your choice\` (the record \`~/.claude/make-it/references/left-out-record.md\` defines); it cannot be left out as \"set up that way on purpose\"; the check runs again and this same ask comes first in every session until the check passes; the status summary and the session'"'"'s last message each say it is still open; and it still holds what a \`[BLOCK]\` holds -- no handoff to /ship-it and no other deploy step while it is open."'
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
plant "the bypass mode back" "$REL_PF" 's.replace("permission_mode=\"dontAsk\"", "permission_mode=\"bypassPermissions\"", 1)'
plant "one tool (Bash) dropped from the disallowed list" "$REL_PF" 's.replace("    \"AskUserQuestion\",\n    \"Bash\",\n", "    \"AskUserQuestion\",\n", 1)'
plant "the tripwire removed from the streaming method only" "$REL_PF" \
  's[:s.index("    async def stream(")] + s[s.index("    async def stream("):].replace("aclosing(self._text_only(system_prompt, user_prompt, model))", "aclosing(query(prompt=user_prompt, options=self._options(system_prompt, model)))", 1)'
plant "the SDK pin removed from the build step" "$REL_MK" 's.replace("a. Add `claude-agent-sdk>=0.2.186,<0.3` to", "a. Add `claude-agent-sdk` to", 1)'
plant "the check downgraded to [WARN]" "$REL_BS" 's.replace("**AI29** [AI] [BLOCK] ", "**AI29** [AI] [WARN] ", 1)'
plant "the security-fix marker dropped" "$REL_BS" 's.replace("**AI29** [AI] [BLOCK] [SECURITY FIX] ", "**AI29** [AI] [BLOCK] ", 1)'
plant "the claude.ai connectors switch removed" "$REL_PF" 's.replace("                \"ENABLE_CLAUDEAI_MCP_SERVERS\": \"false\",\n", "", 1)'
plant "the no-transcript flag removed" "$REL_PF" 's.replace(", \"no-session-persistence\": None}", "}", 1)'
plant "a second query call under an import alias, mid-file" "$REL_PF" \
  's.replace("    async def complete(", "    async def _other(self, p, o):\n        from claude_agent_sdk import query as q\n\n        async for m in q(prompt=p, options=o):\n            yield m\n\n    async def complete(", 1)'
plant "the hook returning {} first" "$REL_PF" 's.replace("    \"\"\"PreToolUse hook: refuse every tool call before it runs.\"\"\"\n", "    \"\"\"PreToolUse hook: refuse every tool call before it runs.\"\"\"\n    if input_data:\n        return {}\n", 1)'
plant "the session check removed" "$REL_PF" 's.replace("                    sign = _session_problem(message.data)\n", "                    sign = None\n", 1)'
plant "a reply with no session report let through" "$REL_PF" 's.replace("                elif not session_checked and isinstance(message, (AssistantMessage, UserMessage)):  # noqa: UP038 -- AI29'"'"'s provider, left as written (follow-up card)\n                    sign = \"a reply before the CLI reported its session\"\n", "", 1)'
plant "a tool in the session report tolerated" "$REL_PF" 's.replace("    if data.get(\"tools\") != []:", "    if data.get(\"tools\") is None:", 1)'
plant "the deferred tool call unchecked" "$REL_PF" 's.replace("        if getattr(message, \"deferred_tool_use\", None) is not None:\n            return \"deferred tool call\"\n", "", 1)'
plant "failover retrying a stopped stream" "$REL_FO" 's[:s.index("    async def stream(")] + s[s.index("    async def stream("):].replace("            except AIToolActivityError:\n                raise  # a security stop, not an outage: no second provider, primary stays in use\n", "", 1)'
plant "AI29 without the globs requirement" "$REL_BS" 's.replace(" plus `\"*\"` and `\"mcp__*\"` -- an `allowed_tools` list", " -- an `allowed_tools` list", 1)'
plant "AI29 without the tools=[] requirement" "$REL_BS" 's.replace("(2) the options do not set `tools=[]`, or `disallowed_tools`", "(2) `disallowed_tools`", 1)'
plant "AI29 with condition 3 deleted" "$REL_BS" 's[:s.index("(3) the options do not set `setting_sources=[]`")] + s[s.index("(4) the file calls `query(`"):]'
plant "AI29 with condition 6 deleted" "$REL_BS" 's.replace("(6) `tests/unit/test_claude_agent_text_only.py` is missing or does not pass. ", "", 1)'
plant "AI29 failing every app on the pin again" "$REL_BS" 's.replace("applies only when the provider is selected or its SDK is declared, which is any one of:", "applies to every app:", 1)'
plant "Not now putting the security fix off" "$REL_RS" 's.replace("it is not written under `## Put off by your choice` or `## Left out by your choice` (the record", "it is written under `## Put off by your choice` (the record", 1)'
plant "the stale AI range back in retrofit-it" "$REL_RF" 's.replace("- **AI01-AI30**: AI features", "- **AI01-AI29**: AI features", 1)'

fail=0
[ "$real" = 0 ] || bad "the repository's own files pass every check above"

# The scaffold's own unit tests, when this machine can run them. They import the scaffold's packages (its conftest
# loads the app), so "pytest is installed" is not enough.
SB=.claude/make-it/scaffolds/fastapi-nextjs/backend
if (cd "$SB" && python3 -c "import pytest, pytest_asyncio, sqlalchemy, aiosqlite, fastapi, httpx, pydantic_settings" </dev/null 2>/dev/null); then
  SDKV="$(python3 -c "import claude_agent_sdk as s; print(s.__version__)" </dev/null 2>/dev/null || echo "not installed")"
  check "the scaffold's test_claude_agent_text_only.py passes (claude-agent-sdk: $SDKV)" \
    '(cd "$SB" && PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests/unit/test_claude_agent_text_only.py </dev/null >"$TMPD/pytest.out" 2>&1) || { tail -n 25 "$TMPD/pytest.out"; false; }'
  if [ "${REQUIRE_SCAFFOLD_PYTEST:-}" = 1 ]; then
    check "REQUIRE_SCAFFOLD_PYTEST: the real SDK is installed, so no test was skipped" \
      '[ "$SDKV" != "not installed" ] && [ "$(grep -c "skipped" "$TMPD/pytest.out")" = 0 ]'
  fi
elif [ "${REQUIRE_SCAFFOLD_PYTEST:-}" = 1 ]; then
  bad "REQUIRE_SCAFFOLD_PYTEST is set, but python3 cannot import pytest and the scaffold's packages"
else
  echo "note the scaffold's pytest was NOT run here: python3 lacks pytest or the scaffold's packages"
fi
[ "$planted" = 0 ] || bad "every planted defect is caught"
check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
