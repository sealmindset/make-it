"""The Claude-subscription provider is text-only: no tools, nothing loaded from disk, and it stops on tool activity.

No network and no sign-in token. `claude_agent_sdk` is replaced by a fake whose `query()` replays a scripted
stream, so these tests run whether or not the real package is installed. The tests at the end use the real
package when it is there: they read the command line the SDK itself builds, and feed raw messages through the
SDK's own parser, so what the provider checks is what the parser really hands on.
"""

import asyncio
import os
import sys
import types
from dataclasses import dataclass, field
from pathlib import Path

import pytest

from app.lib.ai.errors import AIProviderError, AIToolActivityError
from app.lib.ai.provider import AIProvider
from app.lib.ai.providers import claude_agent
from app.lib.ai.providers.claude_agent import ClaudeAgentProvider
from app.lib.ai.providers.failover import FailoverProvider

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
EXTRA_ARGS = {"restricted": None, "disable-slash-commands": None, "no-session-persistence": None}
# The fields ClaudeAgentOptions has in claude-agent-sdk 0.2.186. The fake refuses any other keyword, so a
# misspelled option fails here instead of being swallowed; a test below checks this list against the real class.
OPTION_FIELDS = frozenset(
    """
tools allowed_tools system_prompt mcp_servers strict_mcp_config permission_mode continue_conversation resume
session_id max_turns max_budget_usd disallowed_tools model fallback_model betas permission_prompt_tool_name cwd
cli_path settings add_dirs env extra_args max_buffer_size debug_stderr stderr can_use_tool hooks user
include_partial_messages include_hook_events forward_subagent_text verbatim_prompts fork_session
resume_session_at resume_drops_turn agents setting_sources skills sandbox plugins max_thinking_tokens thinking
effort output_format enable_file_checkpointing session_store session_store_flush load_timeout_ms task_budget
client_app
""".split()
)
# What the CLI's `init` message reports for a text-only session (SDK types.py, SystemInitData).
INIT_OK = {"tools": [], "mcp_servers": [], "permissionMode": "dontAsk"}


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
    data: dict = field(default_factory=lambda: dict(INIT_OK))


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
    deferred_tool_use: object = None
    subtype: str = "success"


@dataclass
class HookMatcher:
    matcher: str | None = None
    hooks: list = field(default_factory=list)
    timeout: float | None = None
    on_failure: str | None = None


class ClaudeAgentOptions:
    def __init__(self, **fields):
        unknown = sorted(set(fields) - OPTION_FIELDS)
        if unknown:
            raise TypeError(f"ClaudeAgentOptions has no field {unknown}")
        self.__dict__.update(fields)


@pytest.fixture
def sdk(monkeypatch):
    """A fake claude_agent_sdk: `script` is the stream to replay, `calls` records what each query() was given."""
    fake = types.ModuleType("claude_agent_sdk")
    for cls in (
        TextBlock,
        ThinkingBlock,
        ToolUseBlock,
        ToolResultBlock,
        ServerToolUseBlock,
        ServerToolResultBlock,
        AssistantMessage,
        UserMessage,
        SystemMessage,
        TaskStartedMessage,
        TaskProgressMessage,
        TaskNotificationMessage,
        TaskUpdatedMessage,
        ResultMessage,
        HookMatcher,
        ClaudeAgentOptions,
    ):
        setattr(fake, cls.__name__, cls)
    fake.script, fake.calls, fake.closed, fake.handed_on = [], [], 0, 0

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
                if isinstance(message, Exception):
                    raise message
                fake.handed_on += 1
                yield message
        finally:
            fake.closed += 1

    fake.query = query
    monkeypatch.setitem(sys.modules, "claude_agent_sdk", fake)
    return fake


def _text(*chunks, result=None):
    return (
        [SystemMessage()]
        + [AssistantMessage([TextBlock(c)]) for c in chunks]
        + [ResultMessage(result=result, usage={"input_tokens": 3, "output_tokens": 5}, total_cost_usd=0.0)]
    )


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

    assert o.extra_args == EXTRA_ARGS
    assert o.env["ENABLE_CLAUDEAI_MCP_SERVERS"] == "false"

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


async def test_a_misspelled_option_is_refused_by_the_fake_as_the_real_class_would(sdk):
    with pytest.raises(TypeError):
        sdk.ClaudeAgentOptions(setting_source=[])


async def test_the_streaming_method_asks_for_the_same_options(sdk):
    sdk.script = _text("hi")
    await _drain(ClaudeAgentProvider(), [])
    o = sdk.calls[0]["options"]
    assert (o.tools, o.permission_mode, o.setting_sources) == ([], "dontAsk", [])
    assert "Bash" in o.disallowed_tools


# the session check: stop before the model's reply is read ----------------------------------------------------

NOT_TEXT_ONLY = {
    "a tool in the session": {**INIT_OK, "tools": ["Bash"]},
    "an MCP server in the session": {**INIT_OK, "mcp_servers": [{"name": "files", "status": "connected"}]},
    "the bypass mode": {**INIT_OK, "permissionMode": "bypassPermissions"},
    "the default mode": {**INIT_OK, "permissionMode": "default"},
    "no tool list in the report": {"mcp_servers": [], "permissionMode": "dontAsk"},
    "no MCP list in the report": {"tools": [], "permissionMode": "dontAsk"},
    "no mode in the report": {"tools": [], "mcp_servers": []},
}


@pytest.mark.parametrize("report", NOT_TEXT_ONLY)
async def test_a_session_report_that_is_not_text_only_ends_the_call_before_any_reply_is_read(sdk, report):
    sdk.script = [SystemMessage(data=NOT_TEXT_ONLY[report]), *_text("LEAK", result="LEAK")[1:]]
    chunks: list[str] = []

    with pytest.raises(AIToolActivityError):
        await ClaudeAgentProvider().complete("system", "hello")
    with pytest.raises(AIToolActivityError):
        await _drain(ClaudeAgentProvider(), chunks)

    assert chunks == []
    assert (sdk.handed_on, sdk.closed) == (2, 2)  # each call read the report and nothing after it


async def test_a_reply_with_no_session_report_before_it_ends_the_call(sdk):
    sdk.script = _text("LEAK", result="LEAK")[1:]
    chunks: list[str] = []

    with pytest.raises(AIToolActivityError):
        await ClaudeAgentProvider().complete("system", "hello")
    with pytest.raises(AIToolActivityError):
        await _drain(ClaudeAgentProvider(), chunks)

    assert chunks == []


async def test_every_session_report_in_one_call_is_checked(sdk):
    sdk.script = [*_text("before")[:-1], SystemMessage(data={**INIT_OK, "tools": ["Read"]}), *_text("LEAK")[1:]]
    chunks: list[str] = []
    with pytest.raises(AIToolActivityError):
        await _drain(ClaudeAgentProvider(), chunks)
    assert chunks == ["before"]


async def test_a_result_with_no_reply_and_no_report_is_the_clis_own_text_and_is_passed_on(sdk):
    sdk.script = [ResultMessage(result="Not logged in", subtype="success")]
    assert await ClaudeAgentProvider().complete("system", "hello") == "Not logged in"


# (b) (c) the tripwire: it detects after the fact -------------------------------------------------------------

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
    "a deferred tool call": ResultMessage(
        result="LEAK", deferred_tool_use={"id": "tool-1", "name": "Bash", "input": {}}
    ),
}


@pytest.mark.parametrize("sign", TOOL_ACTIVITY)
async def test_complete_raises_and_returns_no_text_on_tool_activity(sdk, sign):
    sdk.script = [*_text("before")[:-1], TOOL_ACTIVITY[sign], *_text("LEAK", result="LEAK")[1:]]
    provider = ClaudeAgentProvider()

    answer = None
    with pytest.raises(AIToolActivityError) as raised:
        answer = await provider.complete("system", "hello")

    assert answer is None
    assert "LEAK" not in raised.value.client_message and "appuser" not in raised.value.client_message
    assert sdk.closed == 1  # the SDK stream was closed, which ends the CLI process
    assert provider.usage.request_count == 0


@pytest.mark.parametrize("sign", TOOL_ACTIVITY)
async def test_stream_raises_and_leaks_nothing_from_the_tool_message_on(sdk, sign):
    sdk.script = [*_text("before")[:-1], TOOL_ACTIVITY[sign], *_text("LEAK", result="LEAK")[1:]]
    chunks: list[str] = []

    with pytest.raises(AIToolActivityError):
        await _drain(ClaudeAgentProvider(), chunks)

    assert chunks == ["before"]
    assert sdk.closed == 1


async def test_a_tool_name_chosen_by_the_model_stays_out_of_the_error(sdk):
    # sanitize_ai_error picks its message by keyword; a tool named like this would be reported as a rate limit
    sdk.script = [*_text("before")[:-1], AssistantMessage([ToolUseBlock(name="rate_limit_token_auth_429")])]
    with pytest.raises(AIProviderError) as raised:
        await ClaudeAgentProvider().complete("system", "hello")
    assert type(raised.value) is AIToolActivityError
    assert raised.value.client_message == "An unexpected AI error occurred. Please try again."
    assert "rate_limit_token_auth_429" not in raised.value.internal_message


class _Secondary(AIProvider):
    def __init__(self):
        super().__init__()
        self.calls = 0

    async def complete(self, system_prompt, user_prompt, model=None, max_tokens=4096):
        self.calls += 1
        return "from the second provider"

    async def stream(self, system_prompt, user_prompt, model=None, max_tokens=4096):
        self.calls += 1
        yield "from the second provider"


async def test_a_stopped_call_is_not_retried_on_the_failover_provider(sdk):
    sdk.script = [*_text("before")[:-1], AssistantMessage([ToolUseBlock()])]
    secondary = _Secondary()
    both = FailoverProvider(ClaudeAgentProvider(), secondary)
    chunks: list[str] = []

    with pytest.raises(AIToolActivityError):
        await both.complete("system", "hello")
    with pytest.raises(AIToolActivityError):
        async for chunk in both.stream("system", "hello"):
            chunks.append(chunk)

    assert chunks == ["before"]  # nothing from a second provider after the stop
    assert secondary.calls == 0
    assert both._primary_failed is False


async def test_an_ordinary_failure_still_fails_over(sdk):
    sdk.script = [RuntimeError("connection reset")]
    secondary = _Secondary()
    both = FailoverProvider(ClaudeAgentProvider(), secondary)
    assert await both.complete("system", "hello") == "from the second provider"
    assert secondary.calls == 1


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
    sdk.script = [SystemMessage(), AssistantMessage([ThinkingBlock("hm"), TextBlock("Hel")]), *_text("lo")[1:]]
    assert await ClaudeAgentProvider().complete("system", "hello") == "Hello"


async def test_stream_yields_each_text_block_unchanged(sdk):
    sdk.script = [SystemMessage(), UserMessage("hello"), *_text("Hel", "lo", result="Hello")[1:]]
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
    assert "--no-session-persistence" in argv
    assert asyncio.iscoroutinefunction(options.hooks["PreToolUse"][0].hooks[0])


def test_the_fakes_option_fields_are_real_fields():
    real = pytest.importorskip("claude_agent_sdk")
    import dataclasses

    assert OPTION_FIELDS <= {f.name for f in dataclasses.fields(real.ClaudeAgentOptions)}


def _parsed(raw):
    from claude_agent_sdk._internal.message_parser import parse_message

    return parse_message(raw)


_RESULT = {
    "type": "result",
    "subtype": "success",
    "duration_ms": 1,
    "duration_api_ms": 1,
    "is_error": False,
    "num_turns": 1,
    "session_id": "s",
    "result": "hi",
}
_TOOL_USE = {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "id"}}
RAW_TOOL_ACTIVITY = {
    "a tool call": {"type": "assistant", "message": {"model": "m", "content": [_TOOL_USE]}},
    "a server tool call": {
        "type": "assistant",
        "message": {
            "model": "m",
            "content": [{"type": "server_tool_use", "id": "s1", "name": "web_search", "input": {}}],
        },
    },
    "a tool result": {
        "type": "user",
        "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "content": "uid=1000"}]},
    },
    "a tool result summary": {"type": "user", "message": {"content": "x"}, "tool_use_result": {"stdout": "uid=1000"}},
    "a background task": {
        "type": "system",
        "subtype": "task_started",
        "task_id": "k",
        "description": "d",
        "uuid": "u",
        "session_id": "s",
    },
    "a refused tool call": {**_RESULT, "permission_denials": [{"tool_name": "Bash"}]},
    "a deferred tool call": {**_RESULT, "deferred_tool_use": _TOOL_USE},
}


@pytest.mark.parametrize("sign", RAW_TOOL_ACTIVITY)
def test_through_the_real_parser_each_sign_of_a_tool_is_seen(sign):
    pytest.importorskip("claude_agent_sdk")
    assert claude_agent._tool_activity(_parsed(RAW_TOOL_ACTIVITY[sign]))


def test_through_the_real_parser_plain_text_and_a_clean_result_pass():
    pytest.importorskip("claude_agent_sdk")
    text = {"type": "assistant", "message": {"model": "m", "content": [{"type": "text", "text": "hi"}]}}
    assert claude_agent._tool_activity(_parsed(text)) is None
    assert claude_agent._tool_activity(_parsed(_RESULT)) is None


def test_through_the_real_parser_the_session_report_is_read():
    real = pytest.importorskip("claude_agent_sdk")
    init = {
        "type": "system",
        "subtype": "init",
        "uuid": "u",
        "session_id": "s",
        "cwd": "/tmp/x",  # noqa: S108 -- test data: a path string in a fake message, no file is made
        "model": "m",
        "tools": [],
        "mcp_servers": [],
        "permissionMode": "dontAsk",
        "slash_commands": [],
        "skills": [],
    }
    ok = _parsed(init)
    assert isinstance(ok, real.SystemMessage) and ok.subtype == "init"
    assert claude_agent._session_problem(ok.data) is None
    assert claude_agent._session_problem(_parsed({**init, "tools": ["Bash", "Read"]}).data)
    assert claude_agent._session_problem(_parsed({**init, "mcp_servers": [{"name": "x", "status": "connected"}]}).data)
    assert claude_agent._session_problem(_parsed({**init, "permissionMode": "bypassPermissions"}).data)


def test_a_block_type_the_real_parser_does_not_know_is_dropped_before_the_tripwire_can_see_it():
    # A known limit, kept visible: the parser has no catch-all, so `mcp_tool_use` never reaches the provider.
    # If a later SDK hands the block on, the tripwire must then fire on it.
    pytest.importorskip("claude_agent_sdk")
    message = _parsed(
        {
            "type": "assistant",
            "message": {
                "model": "m",
                "content": [
                    {"type": "mcp_tool_use", "id": "m1", "name": "files__read", "server_name": "files", "input": {}}
                ],
            },
        }
    )
    assert message.content == [] or claude_agent._tool_activity(message)
