"""OpenAI provider (GPT-4o, GPT-5, o-series reasoning models).

Supports both standard and reasoning models with appropriate parameter
handling (max_completion_tokens vs max_tokens, system role restrictions).
"""

import logging
from typing import AsyncIterator

from app.config import settings
from app.lib.ai.errors import sanitize_ai_error
from app.lib.ai.model_tier import get_model
from app.lib.ai.provider import AIProvider

logger = logging.getLogger(__name__)

PRICING_PER_K = {
    "gpt-4-turbo": {"input": 0.01, "output": 0.03},
    "gpt-4o": {"input": 0.005, "output": 0.015},
    "gpt-4o-mini": {"input": 0.00015, "output": 0.0006},
    "gpt-5": {"input": 0.01, "output": 0.03},
}

_REASONING_PREFIXES = ("o1", "o3", "gpt-5")


def _is_reasoning_model(model: str) -> bool:
    lower = model.lower()
    return any(lower.startswith(p) or p in lower for p in _REASONING_PREFIXES)


class OpenAIProvider(AIProvider):
    def __init__(self) -> None:
        super().__init__()
        try:
            from openai import AsyncOpenAI
        except ImportError as exc:
            raise ImportError(
                "openai package not installed. Install with: pip install openai"
            ) from exc

        self._client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

    def estimate_cost(self, input_tokens: int, output_tokens: int) -> float:
        model = get_model("standard")
        pricing = PRICING_PER_K.get(model, PRICING_PER_K["gpt-4o"])
        return (input_tokens / 1_000) * pricing["input"] + (
            output_tokens / 1_000
        ) * pricing["output"]

    def _build_params(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str,
        max_tokens: int,
    ) -> dict:
        reasoning = _is_reasoning_model(model)

        if reasoning:
            messages = [
                {
                    "role": "user",
                    "content": f"System: {system_prompt}\n\nUser: {user_prompt}",
                }
            ]
            return {
                "model": model,
                "messages": messages,
                "max_completion_tokens": max_tokens,
            }

        return {
            "model": model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "max_tokens": max_tokens,
            "temperature": 0.3,
        }

    async def complete(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> str:
        resolved_model = model or get_model("standard")
        params = self._build_params(system_prompt, user_prompt, resolved_model, max_tokens)
        try:
            response = await self._client.chat.completions.create(**params)
            content = response.choices[0].message.content or ""
            usage = response.usage
            if usage:
                cost = self.estimate_cost(usage.prompt_tokens, usage.completion_tokens)
                self.usage.record(usage.prompt_tokens, usage.completion_tokens, cost)
            return content
        except Exception as exc:
            raise sanitize_ai_error(exc) from exc

    async def stream(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        resolved_model = model or get_model("standard")
        params = self._build_params(system_prompt, user_prompt, resolved_model, max_tokens)
        params["stream"] = True
        try:
            response = await self._client.chat.completions.create(**params)
            async for chunk in response:
                delta = chunk.choices[0].delta if chunk.choices else None
                if delta and delta.content:
                    yield delta.content
        except Exception as exc:
            raise sanitize_ai_error(exc) from exc
