"""Local Ollama provider.

Uses httpx to call the Ollama REST API for both synchronous completions
and streaming responses. Cost tracking returns 0 (local/free).
"""

import json
from typing import AsyncIterator

import httpx

from app.config import settings
from app.lib.ai.errors import sanitize_ai_error
from app.lib.ai.model_tier import get_model
from app.lib.ai.provider import AIProvider


class OllamaProvider(AIProvider):
    def __init__(self) -> None:
        super().__init__()
        self._base_url = settings.OLLAMA_BASE_URL.rstrip("/")

    async def complete(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> str:
        resolved_model = model or get_model("standard")
        prompt = f"{system_prompt}\n\n{user_prompt}"
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self._base_url}/api/generate",
                    json={
                        "model": resolved_model,
                        "prompt": prompt,
                        "stream": False,
                        "options": {"num_predict": max_tokens},
                    },
                )
                response.raise_for_status()
                return response.json()["response"]
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
        prompt = f"{system_prompt}\n\n{user_prompt}"
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                async with client.stream(
                    "POST",
                    f"{self._base_url}/api/generate",
                    json={
                        "model": resolved_model,
                        "prompt": prompt,
                        "stream": True,
                        "options": {"num_predict": max_tokens},
                    },
                ) as response:
                    response.raise_for_status()
                    async for line in response.aiter_lines():
                        if line:
                            data = json.loads(line)
                            if chunk := data.get("response", ""):
                                yield chunk
        except Exception as exc:
            raise sanitize_ai_error(exc) from exc
