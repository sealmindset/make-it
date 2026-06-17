"""Claude Agent SDK provider -- uses a Claude Code subscription, not an API key.

This is the DEFAULT provider for single-user apps that run locally (see the
"subscription by default" principle in design-blueprint.md). It drives the local
Claude Code CLI through the `claude-agent-sdk` package; authentication comes from
the CLI's own login (a long-lived CLAUDE_CODE_OAUTH_TOKEN from `claude setup-token`),
so no ANTHROPIC_API_KEY is needed and usage bills against the Claude Pro/Max
subscription instead of API credits.

Build-time requirements when this provider is selected (ai_providers.primary ==
"claude_agent"):
  - add `claude-agent-sdk` to requirements.txt
  - install the Claude Code CLI in the backend Dockerfile
    (RUN curl -fsSL https://claude.ai/install.sh | bash)
  - pass CLAUDE_CODE_OAUTH_TOKEN through .env and docker-compose

The package import is lazy (inside the methods) so this file is inert for builds
that use a different provider and don't install claude-agent-sdk.

Used in single-shot, no-tools mode so it behaves like a plain system+user
completion -- no file access, no agent loop.
"""

import logging
from typing import AsyncIterator

from app.lib.ai.errors import sanitize_ai_error
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


class ClaudeAgentProvider(AIProvider):
    def _options(self, system_prompt: str, model: str | None):
        from claude_agent_sdk import ClaudeAgentOptions

        return ClaudeAgentOptions(
            system_prompt=system_prompt,
            model=_to_alias(model or get_model("standard")),
            max_turns=1,
            allowed_tools=[],  # pure text completion -- no tools, no file access
            permission_mode="bypassPermissions",
        )

    async def complete(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> str:
        from claude_agent_sdk import (
            AssistantMessage,
            ResultMessage,
            TextBlock,
            query,
        )

        options = self._options(system_prompt, model)
        parts: list[str] = []
        result_text: str | None = None
        try:
            async for message in query(prompt=user_prompt, options=options):
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
        from claude_agent_sdk import AssistantMessage, TextBlock, query

        options = self._options(system_prompt, model)
        try:
            async for message in query(prompt=user_prompt, options=options):
                if isinstance(message, AssistantMessage):
                    for block in message.content:
                        if isinstance(block, TextBlock):
                            yield block.text
        except Exception as exc:  # noqa: BLE001
            raise sanitize_ai_error(exc) from exc
