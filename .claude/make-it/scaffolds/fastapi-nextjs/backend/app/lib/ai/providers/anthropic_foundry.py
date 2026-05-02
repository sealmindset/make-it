"""Azure AI Foundry provider using the Anthropic SDK with dual-mode auth.

If AZURE_AI_FOUNDRY_API_KEY is set, it is used directly as the api_key.
Otherwise, falls back to DefaultAzureCredential for managed-identity auth.
Includes self-annealing for model configuration errors and cost tracking.
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


def _apim_headers() -> dict[str, str]:
    headers: dict[str, str] = {}
    if settings.APIM_PROJECT_ID:
        headers["X-Project-Id"] = settings.APIM_PROJECT_ID
    if settings.APIM_SN_PROJECT:
        headers["X-SN-Project"] = settings.APIM_SN_PROJECT
    if settings.APIM_SN_PRODUCT:
        headers["X-SN-Product"] = settings.APIM_SN_PRODUCT
    return headers


def _build_client() -> anthropic.AsyncAnthropic:
    """Construct an AsyncAnthropic client with the appropriate auth mode."""
    api_key = settings.AZURE_AI_FOUNDRY_API_KEY

    if not api_key:
        from azure.identity import DefaultAzureCredential

        credential = DefaultAzureCredential()
        token = credential.get_token("https://cognitiveservices.azure.com/.default")
        api_key = token.token

    return anthropic.AsyncAnthropic(
        api_key=api_key,
        base_url=settings.AZURE_AI_FOUNDRY_ENDPOINT or None,
        default_headers=_apim_headers(),
    )


class AnthropicFoundryProvider(AIProvider):
    def __init__(self) -> None:
        super().__init__()
        self._client = _build_client()

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
