"""Direct Anthropic API provider.

Uses ANTHROPIC_API_KEY from settings for simple api_key authentication
against the Anthropic API without any Azure intermediary.
Includes self-annealing for model errors and cost tracking.
"""

import logging
from typing import AsyncIterator

import anthropic

from app.config import settings
from app.lib.ai.errors import sanitize_ai_error
from app.lib.ai.model_tier import get_model
from app.lib.ai.provider import AIProvider
from app.lib.ai.self_annealing import detect_model_error, extract_corrected_model, validate_model

logger = logging.getLogger(__name__)

PRICING_PER_M = {
    "claude-sonnet-4-20250514": {"input": 3.00, "output": 15.00},
    "claude-haiku-4-5-20251001": {"input": 0.80, "output": 4.00},
    "claude-opus-4-5-20251101": {"input": 15.00, "output": 75.00},
}


class AnthropicDirectProvider(AIProvider):
    def __init__(self) -> None:
        super().__init__()
        self._client = anthropic.AsyncAnthropic(
            api_key=settings.ANTHROPIC_API_KEY,
        )

    def estimate_cost(self, input_tokens: int, output_tokens: int) -> float:
        model = get_model("standard")
        pricing = PRICING_PER_M.get(model, {"input": 3.00, "output": 15.00})
        return (input_tokens / 1_000_000) * pricing["input"] + (
            output_tokens / 1_000_000
        ) * pricing["output"]

    async def complete(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> str:
        resolved_model = validate_model(model or get_model("standard"))
        try:
            message = await self._client.messages.create(
                model=resolved_model,
                max_tokens=max_tokens,
                system=system_prompt,
                messages=[{"role": "user", "content": user_prompt}],
            )
            cost = self.estimate_cost(
                message.usage.input_tokens, message.usage.output_tokens
            )
            self.usage.record(
                message.usage.input_tokens, message.usage.output_tokens, cost
            )
            return message.content[0].text
        except Exception as exc:
            if detect_model_error(str(exc)):
                corrected = extract_corrected_model(str(exc), resolved_model)
                message = await self._client.messages.create(
                    model=corrected,
                    max_tokens=max_tokens,
                    system=system_prompt,
                    messages=[{"role": "user", "content": user_prompt}],
                )
                cost = self.estimate_cost(
                    message.usage.input_tokens, message.usage.output_tokens
                )
                self.usage.record(
                    message.usage.input_tokens, message.usage.output_tokens, cost
                )
                return message.content[0].text
            raise sanitize_ai_error(exc) from exc

    async def stream(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        resolved_model = validate_model(model or get_model("standard"))
        try:
            async with self._client.messages.stream(
                model=resolved_model,
                max_tokens=max_tokens,
                system=system_prompt,
                messages=[{"role": "user", "content": user_prompt}],
            ) as resp:
                async for text in resp.text_stream:
                    yield text
                final = await resp.get_final_message()
                cost = self.estimate_cost(
                    final.usage.input_tokens, final.usage.output_tokens
                )
                self.usage.record(
                    final.usage.input_tokens, final.usage.output_tokens, cost
                )
        except Exception as exc:
            raise sanitize_ai_error(exc) from exc
