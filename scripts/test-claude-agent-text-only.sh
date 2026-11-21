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
#   - nothing is loaded from disk, and the CLI runs in an empty directory;
#   - the tripwire: query() is called in one place, behind _tool_activity, and complete() and stream() both read it;
#   - every build step that adds claude-agent-sdk pins it;
#   - build-standards AI29 exists, is [BLOCK], and the AI check ranges include it.
# Then five planted defects, each in a throwaway copy (the real files are never edited): each must fail.
# A wording test is a tripwire, not a proof. It reads files; it makes no model call and needs no sign-in token. What
# the options do to a live assistant is covered by the scaffold's own pytest (a fake stream) and by the live check in
# AI29, not here.
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
FILES="$REL_PF $REL_UT $REL_MK $REL_RS $REL_BS $REL_PT $REL_DB $REL_GR"

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
  local WANT OPT TXT CPL STR AI29 f
  fail=0
  for f in $FILES; do check "found: $f" '[ -s "$R/$f" ]'; done
  WANT="$(printf "%s\n" $TOOLS | LC_ALL=C sort)"
  OPT="$(between "$PF" '^    def _options[(]' '^    async def _text_only[(]')"
  TXT="$(between "$PF" '^    async def _text_only[(]' '^    async def complete[(]')"
  CPL="$(between "$PF" '^    async def complete[(]' '^    async def stream[(]')"
  STR="$(from "$PF" '^    async def stream[(]')"
  AI29="$(grep -E '^[*][*]AI29[*][*] ' "$BS" || true)"

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
    'printf "%s\n" "$OPT" | gq -xF "            hooks={\"PreToolUse\": [HookMatcher(matcher=None, hooks=[_refuse_tool], on_failure=\"block\")]}," && gq -xF "            \"permissionDecision\": \"deny\"," "$PF"'
  check "provider options: the CLI runs restricted, with skills and commands off" \
    'printf "%s\n" "$OPT" | gq -xF "            extra_args={\"restricted\": None, \"disable-slash-commands\": None},"'

  # 3. nothing loaded from disk
  for f in 'setting_sources=[],' 'skills=[],' 'mcp_servers={},' 'strict_mcp_config=True,' 'cwd=_empty_workdir(),'; do
    check "provider options: $f" 'printf "%s\n" "$OPT" | gq -xF "            $f"'
  done
  check "provider options: auto memory and CLAUDE.md are off" \
    'printf "%s\n" "$OPT" | gq -xF "                \"CLAUDE_CODE_DISABLE_AUTO_MEMORY\": \"1\"," && printf "%s\n" "$OPT" | gq -xF "                \"CLAUDE_CODE_DISABLE_CLAUDE_MDS\": \"1\","'
  check "provider: the working directory is made for the purpose and must be empty" \
    'lines "$PF" "        _workdir = tempfile.mkdtemp(prefix=\"claude-text-only-\")" 1 && lines "$PF" "    if os.listdir(_workdir):" 1'
  check "provider options: no directory, plugin, agent or settings file is added" \
    '[ "$(printf "%s\n" "$OPT" | grep -cE "^ +(add_dirs|plugins|agents|settings)=")" = 0 ]'

  # 4. the tripwire
  check "provider: query() is called with arguments in exactly one place" '[ "$(grep -cE "query[(][^)]" "$PF")" = 1 ]'
  check "tripwire: that one call is in _text_only, closed on the way out" \
    'printf "%s\n" "$TXT" | gq -xF "        async with aclosing(query(prompt=user_prompt, options=options)) as messages:"'
  check "tripwire: every message is checked and a sign of a tool raises before the message is handed on" \
    '[ "$(printf "%s\n" "$TXT" | grep -nxF -e "                sign = _tool_activity(message)" -e "                    raise ToolActivityError(f\"stopped a text-only call: the reply showed {sign}\")" -e "                yield message" | cut -d: -f2- | tr -s " " | tr "\n" "|")" = " sign = _tool_activity(message)| raise ToolActivityError(f\"stopped a text-only call: the reply showed {sign}\")| yield message|" ]'
  check "tripwire: only text and thinking blocks pass" \
    'lines "$PF" "                if not isinstance(block, (sdk.TextBlock, sdk.ThinkingBlock)):" 1'
  check "tripwire: a tool result, a refused call and a task message are signs too" \
    'lines "$PF" "        if getattr(message, \"tool_use_result\", None) is not None:" 1 && lines "$PF" "        if getattr(message, \"permission_denials\", None):" 1 && lines "$PF" "        (sdk.TaskStartedMessage, sdk.TaskProgressMessage, sdk.TaskNotificationMessage, sdk.TaskUpdatedMessage)," 1'
  check "complete() reads the stream through the tripwire, and no other way" \
    '[ "$(printf "%s\n" "$CPL" | grep -cxF -- "$GUARDED")" = 1 ] && [ "$(printf "%s\n" "$CPL" | grep -c "async for ")" = 1 ]'
  check "stream() reads the stream through the tripwire, and no other way" \
    '[ "$(printf "%s\n" "$STR" | grep -cxF -- "$GUARDED")" = 1 ] && [ "$(printf "%s\n" "$STR" | grep -c "async for ")" = 1 ]'
  check "both methods still raise through the sanitised error path" \
    '[ "$(grep -cxF "            raise sanitize_ai_error(exc) from exc" "$PF")" = 2 ]'

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
  check "prompt-templates no longer says single-shot/no-tools; it names the real controls" \
    '[ "$(grep -c "single-shot/no-tools" "$PT")" = 0 ] && lines "$PT" "    │     dontAsk (never bypassPermissions), nothing loaded from disk, and the call stops on" 1'
  check "guardrails: an empty allowed_tools list is not a restriction" \
    '[ "$(grep -c "no-tools mode" "$GR")" = 0 ] && gq -F "(build-standards AI29). An empty \`allowed_tools\` list is not a restriction." "$GR"'
  check "design-blueprint: the provider rule stays, with the text-only sentence after it" \
    'lines "$DB" "       do NOT default a multi-user app to claude_agent]" 1 && tr "\n" " " < "$DB" | tr -s " " | gq -F "do NOT default a multi-user app to claude_agent] The claude_agent provider is configured text-only (no tools, nothing loaded from the container), and build check AI29 verifies it."'

  # 7. the build check
  check "build-standards: AI29 exists once, is [BLOCK], and is this check" \
    '[ "$(grep -cE "^[*][*]AI29[*][*] " "$BS")" = 1 ] && [ "$(grep -cE "^[*][*]AI29[*][*] \[AI\] \[BLOCK\] [*][*]Claude-subscription provider is text-only \(claude_agent\)[*][*] -- " "$BS")" = 1 ]'
  check "AI29 fails an app on the bypass mode, a missing tool denial, a missing tripwire and a missing pin" \
    'printf "%s" "$AI29" | gq -F "(1) \`bypassPermissions\` appears anywhere in the file, or \`permission_mode\` is not \`\"dontAsk\"\`;" && printf "%s" "$AI29" | gq -F "\`disallowed_tools\` does not name every built-in tool in the scaffold'"'"'s \`BUILTIN_TOOLS\`" && printf "%s" "$AI29" | gq -F "(4) the file calls \`query(\` anywhere but inside the tripwire" && printf "%s" "$AI29" | gq -F "(5) \`backend/requirements.txt\` does not pin \`$PIN\` (one exact version inside that range also passes; the bare name fails);"'
  check "AI29 says how an app built before it is fixed, and what it does not cover" \
    'printf "%s" "$AI29" | gq -F "An app built before this check fails it; /resume-it'"'"'s catch-up applies the same fix." && printf "%s" "$AI29" | gq -F "the CLI process still inherits the backend'"'"'s environment" && printf "%s" "$AI29" | gq -F "no check here makes a model call"'
  check "AI29 is the last AI check, and nothing still says the range ends at AI28" \
    '[ "$(grep -oE "^[*][*]AI[0-9]+[a-d]?[*][*]" "$BS" | tail -1)" = "**AI29**" ] && [ "$(cat "$MK" "$RS" | grep -c "AI01-AI28")" = 0 ] && [ "$(grep -c "^- [*][*]AI01-AI29[*][*]: " "$MK")" = 1 ] && [ "$(grep -c "^   - [*][*]AI (AI01-AI29):[*][*] " "$RS")" = 1 ]'
  check "resume-it's catch-up reads the provider for AI29" \
    'gq -F "a text-only Claude-subscription provider (AI29: read \`lib/ai/providers/claude_agent.py\`; an app built before the check fails it and is fixed from the scaffold'"'"'s copy)" "$RS"'
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
plant "one tool (Bash) dropped from the disallowed list" "$REL_PF" 's.replace("\"AskUserQuestion\", \"Bash\", ", "\"AskUserQuestion\", ", 1)'
plant "the tripwire removed from the streaming method only" "$REL_PF" \
  's[:s.index("    async def stream(")] + s[s.index("    async def stream("):].replace("aclosing(self._text_only(system_prompt, user_prompt, model))", "aclosing(query(prompt=user_prompt, options=self._options(system_prompt, model)))", 1)'
plant "the SDK pin removed from the build step" "$REL_MK" 's.replace("a. Add `claude-agent-sdk>=0.2.186,<0.3` to", "a. Add `claude-agent-sdk` to", 1)'
plant "the check downgraded to [WARN]" "$REL_BS" 's.replace("**AI29** [AI] [BLOCK] ", "**AI29** [AI] [WARN] ", 1)'

fail=0
[ "$real" = 0 ] || bad "the repository's own files pass every check above"
[ "$planted" = 0 ] || bad "every planted defect is caught"
check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
