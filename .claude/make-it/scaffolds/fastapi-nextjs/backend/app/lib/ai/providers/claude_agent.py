"""Claude Agent SDK provider -- uses a Claude Code subscription, not an API key.

This is the DEFAULT provider for single-user apps that run locally (see the
"subscription by default" principle in design-blueprint.md). It drives the local
Claude Code CLI through the `claude-agent-sdk` package; authentication comes from
the CLI's own login (a long-lived CLAUDE_CODE_OAUTH_TOKEN from `claude setup-token`),
so no ANTHROPIC_API_KEY is needed and usage bills against the Claude Pro/Max
subscription instead of API credits.

Build-time requirements when this provider is selected (ai_providers.primary ==
"claude_agent"):
  - add `claude-agent-sdk>=0.2.186,<0.3` to requirements.txt
  - install the Claude Code CLI in the backend Dockerfile
    (RUN curl -fsSL https://claude.ai/install.sh | bash)
  - pass CLAUDE_CODE_OAUTH_TOKEN through .env and docker-compose

The package import is lazy (inside the methods) so this file is inert for builds
that use a different provider and don't install claude-agent-sdk.

TEXT-ONLY, AND IT MUST STAY THAT WAY. `user_prompt` is text typed by a user of the
app, and the CLI this drives is a coding agent that can run shell commands and read
and write files in this container, next to the app's secrets and the owner's sign-in
token. Three kinds of control, and what each can do:

  PREVENT   The options in `_options()` (layers 1-5): the model is given no tools and
            nothing is loaded from the container's disk. These are what keep a tool
            from running.
  STOP      `_session_problem()`: the CLI reports the session's tools, MCP servers
   BEFORE   and permission mode before the model runs. If that report shows any tool,
            any MCP server or a mode other than dontAsk, the call is ended there.
  DETECT    `_tool_activity()`: reads the reply for a sign of a tool. This does NOT
   AFTER    prevent anything. The CLI sends the message that holds a tool call and
            then runs the tool itself, so by the time this code reads the message a
            fast command may already have finished. It ends the call, keeps the rest
            from the user, and leaves a log line. It is the alarm, not the lock.

build-standards AI29 and tests/unit/test_claude_agent_text_only.py check all three. Do
not loosen one to "make it work" -- an app that needs tools needs a different,
sandboxed design.

DATA KEPT ON DISK. The CLI normally saves each session -- the system prompt (which can
hold the app's data), the user's prompt and the reply -- as a transcript under
~/.claude/projects/ in this container, kept for its cleanup period (30 days unless
settings say otherwise). `--no-session-persistence` turns that off; see layer 6 for
what was and was not confirmed about it.

SDK facts below were read from claude-agent-sdk 0.2.186 (its bundled CLI is 2.1.329,
and the SDK runs that bundled CLI before any `claude` on PATH) and from
code.claude.com/docs/en/agent-sdk/{python,permissions,agent-loop,hosting,
claude-code-features} and /docs/en/{cli-reference,tools-reference} on 2026-11-20.
requirements.txt pins the SDK to `>=0.2.186,<0.3` so a default cannot change under
these options unnoticed.
"""

import logging
import os
import tempfile
from contextlib import aclosing
from typing import AsyncIterator

from app.lib.ai.errors import AIToolActivityError, sanitize_ai_error
from app.lib.ai.model_tier import get_model
from app.lib.ai.provider import AIProvider

logger = logging.getLogger(__name__)


def _to_alias(model: str | None) -> str | None:
    """Map a tiered model id to a CLI-friendly alias (opus/sonnet/haiku)."""
    if not model:
        return None
    m = model.lower()
    if "opus" in m:
        return "opus"
    if "haiku" in m:
        return "haiku"
    if "sonnet" in m:
        return "sonnet"
    return model


# Every built-in tool in the CLI's tools reference, plus `Task` (the Agent tool's old
# name). `*` and `mcp__*` are the documented deny globs for "every tool" and "every MCP
# tool"; the names stay listed so the denial does not rest on glob support alone.
BUILTIN_TOOLS = (
    "Agent", "Artifact", "AskUserQuestion", "Bash", "CronCreate", "CronDelete", "CronList",
    "Edit", "EndConversation", "EnterPlanMode", "EnterWorktree", "ExitPlanMode", "ExitWorktree",
    "Glob", "Grep", "ListAgents", "ListMcpResourcesTool", "ListPlugins", "ListSkills", "LSP",
    "Monitor", "NotebookEdit", "PowerShell", "propose_skills", "PushNotification", "Read",
    "ReadMcpResourceTool", "RemoteTrigger", "ReportFindings", "ScheduleWakeup", "SearchPlugins",
    "SearchSkills", "SendFeedback", "SendMessage", "SendUserFile", "ShareOnboardingGuide", "Skill",
    "SubagentHandback", "SuggestPluginInstall", "SuggestSkills", "Task", "TaskCreate", "TaskGet",
    "TaskList", "TaskOutput", "TaskStop", "TaskUpdate", "TodoWrite", "ToolSearch",
    "WaitForMcpServers", "WebFetch", "WebSearch", "Workflow", "Write",
)
DISALLOWED_TOOLS = [*BUILTIN_TOOLS, "*", "mcp__*"]


async def _refuse_tool(input_data, tool_use_id, context):
    """PreToolUse hook: refuse every tool call before it runs."""
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "This assistant answers in text only. Tools are turned off.",
        }
    }


_workdir: str | None = None


def _empty_workdir() -> str:
    """An empty directory, made for the CLI to run in, that nothing else uses.

    With no tools nothing can write to it, so anything found in it stops the call.
    """
    global _workdir
    if _workdir is None or not os.path.isdir(_workdir):
        _workdir = tempfile.mkdtemp(prefix="claude-text-only-")
    if os.listdir(_workdir):
        logger.error("claude_agent: the text-only working directory %s is no longer empty", _workdir)
        raise AIToolActivityError("the text-only working directory is no longer empty")
    return _workdir


def _session_problem(data) -> str | None:
    """STOP BEFORE. What is wrong with the session the CLI reports in its `init` message; None when it is text-only.

    The CLI sends `init` at the start of the turn, before the model runs (SDK types.py,
    SystemInitData: `tools`, `mcp_servers`, `permissionMode`). A missing key counts as wrong.
    """
    if data.get("tools") != []:
        return f"tools in the session: {data.get('tools')!r:.300}"
    if data.get("mcp_servers") != []:
        return f"MCP servers in the session: {data.get('mcp_servers')!r:.300}"
    if data.get("permissionMode") != "dontAsk":
        return f"permission mode {data.get('permissionMode')!r:.80}"
    return None


def _tool_activity(message) -> str | None:
    """DETECT AFTER. Name the sign in `message` that a tool was asked for or ran; None for plain text.

    It reads what the CLI reports, not what the options asked for, so it still fires if a
    later SDK or CLI changes a default. What it sees: tool-use and tool-result blocks,
    server tool-use blocks, a tool result on a user message, a refused or deferred tool
    call on the result, and background-task messages.

    What it cannot see: the SDK's parser (message_parser.py) drops content blocks whose
    type it does not know before any caller sees them -- `mcp_tool_use`, the
    `*_tool_result` blocks of server tools, and whatever a later CLI adds. Nothing here
    catches a dropped block.
    """
    import claude_agent_sdk as sdk

    if isinstance(message, (sdk.AssistantMessage, sdk.UserMessage)):
        if not isinstance(message.content, str):
            for block in message.content:
                if not isinstance(block, (sdk.TextBlock, sdk.ThinkingBlock)):
                    return f"{type(block).__name__} {getattr(block, 'name', '')!r:.80}"
        if getattr(message, "tool_use_result", None) is not None:
            return "tool result"
    elif isinstance(message, sdk.ResultMessage):
        if getattr(message, "permission_denials", None):
            return "refused tool call"
        if getattr(message, "deferred_tool_use", None) is not None:
            return "deferred tool call"
    elif isinstance(
        message,
        (sdk.TaskStartedMessage, sdk.TaskProgressMessage, sdk.TaskNotificationMessage, sdk.TaskUpdatedMessage),
    ):
        return type(message).__name__
    return None


class ClaudeAgentProvider(AIProvider):
    def _options(self, system_prompt: str, model: str | None):
        """Options for one text-only call. Each layer, and what it rests on:

        1. No tools in the model's context. `tools=[]` becomes the CLI flag `--tools ""`
           ("Built-in tools to make available: "" for none"; subprocess_cli.py sends it for
           an empty list). `disallowed_tools` names every built-in tool: "A bare name such
           as "Bash" removes the tool from Claude's context", and a deny rule holds in
           every permission mode. `allowed_tools` is left empty: it only pre-approves
           ("This does not restrict Claude to only these tools").
        2. Never the bypass permission mode ("`allowed_tools` doesn't constrain this
           mode, and calls to tools you didn't list are approved too"). `dontAsk` turns every call
           that would prompt into a denial. It does NOT stop calls that need no approval
           (a file read inside the working directory, a read-only shell command, the
           Agent tool), which is why layer 1 removes the tools and layer 5 gives the CLI
           an empty directory.
        3. A PreToolUse hook that refuses every call. Hooks run before the rules and the
           mode, and a hook's deny holds in every mode. `on_failure="block"`: a hook that
           errors refuses too.
        4. `--restricted` (extra_args): the CLI drops the tools that run commands or code,
           keeps file tools inside the working directory, ignores settings files, and
           refuses to start in the bypass mode.
        5. Nothing loaded from disk: `setting_sources=[]` (unset, query() loads user,
           project and local settings, CLAUDE.md and .claude/ skills, agents and
           commands), `skills=[]`, `--disable-slash-commands`, no MCP servers with
           `strict_mcp_config`, auto memory and CLAUDE.md off by environment variable
           (both load regardless of setting_sources), and `cwd` an empty directory
           instead of the app's source.

        6. No transcript on disk: `--no-session-persistence` (extra_args; the Python SDK
           has no option of its own). Confirmed without a model call: the bundled CLI
           accepts the flag only in non-interactive mode and then turns transcript
           writes off (`if(o.sessionPersistence===!1){if(!K)return Ln("Error:
           --no-session-persistence only works with --print.");xOr(!0)}`), and it
           starts with the flag the way the SDK launches it. NOT confirmed: that no
           file is written during a real turn, which needs a live call to see.

        `max_turns=1` bounds cost. It is not a safety control: a turn includes running
        the tool calls made in it.

        NOT covered here: `env` is merged over this process's environment
        (subprocess_cli.py: `{**inherited_env, ..., **self._options.env}`), so the CLI
        process still holds every variable the backend has. The CLI also reads
        ~/.claude.json, and it needs network access to reach the model.
        """
        from claude_agent_sdk import ClaudeAgentOptions, HookMatcher

        return ClaudeAgentOptions(
            system_prompt=system_prompt,
            model=_to_alias(model or get_model("standard")),
            max_turns=1,
            tools=[],
            disallowed_tools=list(DISALLOWED_TOOLS),
            permission_mode="dontAsk",
            hooks={"PreToolUse": [HookMatcher(matcher=None, hooks=[_refuse_tool], on_failure="block")]},
            extra_args={"restricted": None, "disable-slash-commands": None, "no-session-persistence": None},
            setting_sources=[],
            skills=[],
            mcp_servers={},
            strict_mcp_config=True,
            cwd=_empty_workdir(),
            env={
                "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
                "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1",
                "ENABLE_CLAUDEAI_MCP_SERVERS": "false",
            },
        )

    async def _text_only(self, system_prompt: str, user_prompt: str, model: str | None):
        """The SDK's messages for one call. The only place this file calls query().

        Ends the call (leaving the `aclosing` block closes the SDK stream, which ends the
        CLI process) when the CLI's `init` report is not text-only, when a reply arrives
        before any `init` report (the docs put `init` first, so a reply without one is
        not a session this code has checked), or when a message shows a sign of a tool.
        A result with no `init` before it is passed on: no reply came with it, so it is
        the CLI's own error text. What the sign was goes to the log only; names chosen
        by the model stay out of the error.
        """
        from claude_agent_sdk import AssistantMessage, SystemMessage, UserMessage, query

        options = self._options(system_prompt, model)
        session_checked = False
        async with aclosing(query(prompt=user_prompt, options=options)) as messages:
            async for message in messages:
                if isinstance(message, SystemMessage) and message.subtype == "init":
                    session_checked = True
                    sign = _session_problem(message.data)
                elif not session_checked and isinstance(message, (AssistantMessage, UserMessage)):
                    sign = "a reply before the CLI reported its session"
                else:
                    sign = _tool_activity(message)
                if sign:
                    logger.error("claude_agent: stopped a text-only call: %s", sign)
                    raise AIToolActivityError("stopped a text-only call (the sign is in the log)")
                yield message

    async def complete(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> str:
        from claude_agent_sdk import AssistantMessage, ResultMessage, TextBlock

        parts: list[str] = []
        result_text: str | None = None
        try:
            async with aclosing(self._text_only(system_prompt, user_prompt, model)) as messages:
                async for message in messages:
                    if isinstance(message, AssistantMessage):
                        for block in message.content:
                            if isinstance(block, TextBlock):
                                parts.append(block.text)
                    elif isinstance(message, ResultMessage):
                        if getattr(message, "result", None):
                            result_text = message.result
                        usage = getattr(message, "usage", None) or {}
                        self.usage.record(
                            usage.get("input_tokens", 0),
                            usage.get("output_tokens", 0),
                            getattr(message, "total_cost_usd", 0.0) or 0.0,
                        )
        except AIToolActivityError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise sanitize_ai_error(exc) from exc
        return result_text if result_text is not None else "".join(parts)

    async def stream(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        from claude_agent_sdk import AssistantMessage, TextBlock

        try:
            async with aclosing(self._text_only(system_prompt, user_prompt, model)) as messages:
                async for message in messages:
                    if isinstance(message, AssistantMessage):
                        for block in message.content:
                            if isinstance(block, TextBlock):
                                yield block.text
        except AIToolActivityError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise sanitize_ai_error(exc) from exc
