"""The Claude-subscription provider is text-only: no tools, nothing loaded from disk, and it stops on tool activity.

No network and no sign-in token. `claude_agent_sdk` is replaced by a fake whose `query()` replays a scripted
stream, so these tests run whether or not the real package is installed. The last test uses the real package
when it is there, and reads the command line the SDK itself would build.
"""

import asyncio
import os
import sys
import types
from dataclasses import dataclass, field
from pathlib import Path

import pytest

from app.lib.ai.errors import AIProviderError
from app.lib.ai.providers.claude_agent import ClaudeAgentProvider

# This test's own copy of the built-in tool names (code.claude.com/docs/en/tools-reference, read 2026-11-20),
# plus `Task`, the Agent tool's old name. Kept apart from the provider's list on purpose: a name dropped there
# fails here.
BUILTIN_TOOLS = """
Agent Artifact AskUserQuestion Bash CronCreate CronDelete CronList Edit EndConversation EnterPlanMode
EnterWorktree ExitPlanMode ExitWorktree Glob Grep ListAgents ListMcpResourcesTool ListPlugins ListSkills LSP
Monitor NotebookEdit PowerShell propose_skills PushNotification Read ReadMcpResourceTool RemoteTrigger
ReportFindings ScheduleWakeup SearchPlugins SearchSkills SendFeedback SendMessage SendUserFile
ShareOnboardingGuide Skill SubagentHandback SuggestPluginInstall SuggestSkills Task TaskCreate TaskGet TaskList
TaskOutput TaskStop TaskUpdate TodoWrite ToolSearch WaitForMcpServers WebFetch WebSearch Workflow Write
""".split()
WILDCARDS = ["*", "mcp__*"]
APP_ROOT = Path(__file__).resolve().parents[2]


@dataclass
class TextBlock:
    text: str


@dataclass
class ThinkingBlock:
    thinking: str = ""
    signature: str = ""


@dataclass
class ToolUseBlock:
    id: str = "tool-1"
    name: str = "Bash"
    input: dict = field(default_factory=dict)


@dataclass
class ToolResultBlock:
    tool_use_id: str = "tool-1"
    content: object = None
    is_error: bool | None = None


@dataclass
class ServerToolUseBlock:
    id: str = "srv-1"
    name: str = "web_search"
    input: dict = field(default_factory=dict)


@dataclass
class ServerToolResultBlock:
    tool_use_id: str = "srv-1"
    content: object = None


@dataclass
class BlockFromALaterSdk:
    payload: str = "?"


@dataclass
class AssistantMessage:
    content: list
    model: str = "fake"


@dataclass
class UserMessage:
    content: object
    tool_use_result: dict | None = None


@dataclass
class SystemMessage:
    subtype: str = "init"
    data: dict = field(default_factory=dict)


class TaskStartedMessage(SystemMessage):
    pass


class TaskProgressMessage(SystemMessage):
    pass


class TaskNotificationMessage(SystemMessage):
    pass


class TaskUpdatedMessage(SystemMessage):
    pass


@dataclass
class ResultMessage:
    result: str | None = None
    usage: dict | None = None
    total_cost_usd: float | None = None
    permission_denials: list | None = None
    subtype: str = "success"


@dataclass
class HookMatcher:
    matcher: str | None = None
    hooks: list = field(default_factory=list)
    timeout: float | None = None
    on_failure: str | None = None


class ClaudeAgentOptions:
    def __init__(self, **fields):
        self.__dict__.update(fields)


@pytest.fixture
def sdk(monkeypatch):
    """A fake claude_agent_sdk: `script` is the stream to replay, `calls` records what each query() was given."""
    fake = types.ModuleType("claude_agent_sdk")
    for cls in (
        TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock, ServerToolUseBlock, ServerToolResultBlock,
        AssistantMessage, UserMessage, SystemMessage, TaskStartedMessage, TaskProgressMessage,
        TaskNotificationMessage, TaskUpdatedMessage, ResultMessage, HookMatcher, ClaudeAgentOptions,
    ):
        setattr(fake, cls.__name__, cls)
    fake.script, fake.calls, fake.closed = [], [], 0

    async def query(*, prompt, options=None):
        cwd = getattr(options, "cwd", None)
        fake.calls.append(
            {
                "prompt": prompt,
                "options": options,
                # read while the call is live: the directory may be removed afterwards
                "cwd_is_dir": bool(cwd) and os.path.isdir(cwd),
                "cwd_entries": os.listdir(cwd) if cwd and os.path.isdir(cwd) else None,
            }
        )
        try:
            for message in fake.script:
                yield message
        finally:
            fake.closed += 1

    fake.query = query
    monkeypatch.setitem(sys.modules, "claude_agent_sdk", fake)
    return fake


def _text(*chunks, result=None):
    return [SystemMessage()] + [AssistantMessage([TextBlock(c)]) for c in chunks] + [
        ResultMessage(result=result, usage={"input_tokens": 3, "output_tokens": 5}, total_cost_usd=0.0)
    ]


async def _drain(provider, out):
    async for chunk in provider.stream("system", "hello"):
        out.append(chunk)


# (a) what the provider asks the SDK for ---------------------------------------------------------------------

async def test_the_options_turn_every_tool_off_and_load_nothing_from_disk(sdk):
    sdk.script = _text("hi", result="hi")
    await ClaudeAgentProvider().complete("system", "hello")
    call = sdk.calls[0]
    o = call["options"]

    assert o.tools == []
    missing = [name for name in BUILTIN_TOOLS + WILDCARDS if name not in o.disallowed_tools]
    assert missing == []
    assert not getattr(o, "allowed_tools", None)

    assert o.permission_mode == "dontAsk"

    assert o.extra_args == {"restricted": None, "disable-slash-commands": None}

    assert o.setting_sources == []
    assert o.skills == []
    assert not getattr(o, "mcp_servers", None)
    assert o.strict_mcp_config is True
    assert o.env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] == "1"
    for loads_from_disk in ("add_dirs", "plugins", "agents", "settings"):
        assert not getattr(o, loads_from_disk, None)

    assert call["cwd_is_dir"] and call["cwd_entries"] == []
    cwd = Path(o.cwd).resolve()
    assert cwd != Path.cwd().resolve()
    assert cwd != APP_ROOT and APP_ROOT not in cwd.parents and cwd not in APP_ROOT.parents


async def test_the_options_carry_a_hook_that_refuses_every_tool_call(sdk):
    sdk.script = _text("hi", result="hi")
    await ClaudeAgentProvider().complete("system", "hello")
    matchers = sdk.calls[0]["options"].hooks["PreToolUse"]

    assert [m.matcher for m in matchers] == [None]  # no matcher: every tool
    assert matchers[0].on_failure == "block"
    answer = await matchers[0].hooks[0]({"tool_name": "Bash", "tool_input": {"command": "id"}}, "tool-1", None)
    assert answer["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
    assert answer["hookSpecificOutput"]["permissionDecision"] == "deny"


async def test_the_streaming_method_asks_for_the_same_options(sdk):
    sdk.script = _text("hi")
    await _drain(ClaudeAgentProvider(), [])
    o = sdk.calls[0]["options"]
    assert (o.tools, o.permission_mode, o.setting_sources) == ([], "dontAsk", [])
    assert "Bash" in o.disallowed_tools


# (b) (c) the tripwire ---------------------------------------------------------------------------------------

TOOL_ACTIVITY = {
    "a tool call": AssistantMessage([ToolUseBlock()]),
    "a tool call after text in one message": AssistantMessage([TextBlock("LEAK"), ToolUseBlock()]),
    "a server tool call": AssistantMessage([ServerToolUseBlock()]),
    "a server tool result": AssistantMessage([ServerToolResultBlock()]),
    "a tool result": UserMessage([ToolResultBlock(content="uid=1000(appuser)")]),
    "a tool result summary": UserMessage("", tool_use_result={"stdout": "uid=1000(appuser)"}),
    "a background task": TaskStartedMessage(subtype="task_started"),
    "a task notification": TaskNotificationMessage(subtype="task_notification"),
    "a refused tool call": ResultMessage(result="LEAK", permission_denials=[{"tool_name": "Bash"}]),
    "a block type this version does not know": AssistantMessage([BlockFromALaterSdk()]),
}


@pytest.mark.parametrize("sign", TOOL_ACTIVITY)
async def test_complete_raises_and_returns_no_text_on_tool_activity(sdk, sign):
    sdk.script = [AssistantMessage([TextBlock("before")]), TOOL_ACTIVITY[sign], *_text("LEAK", result="LEAK")]
    provider = ClaudeAgentProvider()

    answer = None
    with pytest.raises(AIProviderError) as raised:
        answer = await provider.complete("system", "hello")

    assert answer is None
    assert "LEAK" not in raised.value.client_message and "appuser" not in raised.value.client_message
    assert sdk.closed == 1  # the SDK stream was closed, which ends the CLI process
    assert provider.usage.request_count == 0


@pytest.mark.parametrize("sign", TOOL_ACTIVITY)
async def test_stream_raises_and_leaks_nothing_from_the_tool_message_on(sdk, sign):
    sdk.script = [AssistantMessage([TextBlock("before")]), TOOL_ACTIVITY[sign], *_text("LEAK", result="LEAK")]
    chunks: list[str] = []

    with pytest.raises(AIProviderError):
        await _drain(ClaudeAgentProvider(), chunks)

    assert chunks == ["before"]
    assert sdk.closed == 1


async def test_a_working_directory_that_is_no_longer_empty_stops_the_call_before_it_starts(sdk):
    sdk.script = _text("hi", result="hi")
    provider = ClaudeAgentProvider()
    await provider.complete("system", "hello")
    Path(sdk.calls[0]["options"].cwd, "written-by-a-tool").write_text("x")
    try:
        with pytest.raises(AIProviderError):
            await provider.complete("system", "hello")
        assert len(sdk.calls) == 1
    finally:
        Path(sdk.calls[0]["options"].cwd, "written-by-a-tool").unlink()


# (d) a normal text answer is unchanged ----------------------------------------------------------------------

async def test_complete_returns_the_result_text_unchanged(sdk):
    sdk.script = _text("Hel", "lo", result="Hello")
    provider = ClaudeAgentProvider()
    assert await provider.complete("system", "hello") == "Hello"
    assert sdk.calls[0]["prompt"] == "hello"
    assert sdk.calls[0]["options"].system_prompt == "system"
    assert (provider.usage.total_input_tokens, provider.usage.total_output_tokens) == (3, 5)


async def test_complete_joins_the_text_blocks_when_the_result_carries_no_text(sdk):
    sdk.script = [AssistantMessage([ThinkingBlock("hm"), TextBlock("Hel")]), *_text("lo")]
    assert await ClaudeAgentProvider().complete("system", "hello") == "Hello"


async def test_stream_yields_each_text_block_unchanged(sdk):
    sdk.script = [UserMessage("hello"), *_text("Hel", "lo", result="Hello")]
    chunks: list[str] = []
    await _drain(ClaudeAgentProvider(), chunks)
    assert chunks == ["Hel", "lo"]


# with the real package: the command line the SDK itself builds ----------------------------------------------

def test_the_real_sdk_turns_these_options_into_tool_free_cli_flags():
    pytest.importorskip("claude_agent_sdk")
    from claude_agent_sdk._internal.transport.subprocess_cli import SubprocessCLITransport

    options = ClaudeAgentProvider()._options("system", None)
    transport = SubprocessCLITransport(prompt="hello", options=options)
    transport._cli_path = "claude"
    argv = transport._build_command()

    def value(flag):
        return argv[argv.index(flag) + 1]

    assert value("--tools") == ""
    assert value("--permission-mode") == "dontAsk"
    denied = value("--disallowedTools").split(",")
    assert [name for name in BUILTIN_TOOLS + WILDCARDS if name not in denied] == []
    assert "--setting-sources=" in argv
    assert "--strict-mcp-config" in argv
    assert "--restricted" in argv and "--disable-slash-commands" in argv
    assert "--allowedTools" not in argv and "--mcp-config" not in argv and "--add-dir" not in argv
    assert "bypassPermissions" not in argv and "--dangerously-skip-permissions" not in argv
    assert asyncio.iscoroutinefunction(options.hooks["PreToolUse"][0].hooks[0])
