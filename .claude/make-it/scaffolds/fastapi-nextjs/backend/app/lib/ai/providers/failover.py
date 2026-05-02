"""Failover provider -- decorator that wraps a primary and secondary provider.

On primary failure the call is retried against the secondary.  Once the
primary has failed, subsequent calls go straight to secondary until the
provider is reinstantiated.
"""

import logging
from typing import AsyncIterator

from app.lib.ai.provider import AIProvider

logger = logging.getLogger(__name__)


class FailoverProvider(AIProvider):
    def __init__(self, primary: AIProvider, secondary: AIProvider) -> None:
        super().__init__()
        self.primary = primary
        self.secondary = secondary
        self._primary_failed = False

    def estimate_cost(self, input_tokens: int, output_tokens: int) -> float:
        target = self.secondary if self._primary_failed else self.primary
        return target.estimate_cost(input_tokens, output_tokens)

    async def complete(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> str:
        if not self._primary_failed:
            try:
                return await self.primary.complete(
                    system_prompt, user_prompt, model, max_tokens
                )
            except Exception as exc:
                logger.warning(
                    "Failover: %s failed (%s), switching to %s",
                    self.primary.__class__.__name__,
                    exc,
                    self.secondary.__class__.__name__,
                )
                self._primary_failed = True

        return await self.secondary.complete(
            system_prompt, user_prompt, model, max_tokens
        )

    async def stream(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        if not self._primary_failed:
            try:
                async for chunk in self.primary.stream(
                    system_prompt, user_prompt, model, max_tokens
                ):
                    yield chunk
                return
            except Exception as exc:
                logger.warning(
                    "Failover: %s stream failed (%s), switching to %s",
                    self.primary.__class__.__name__,
                    exc,
                    self.secondary.__class__.__name__,
                )
                self._primary_failed = True

        async for chunk in self.secondary.stream(
            system_prompt, user_prompt, model, max_tokens
        ):
            yield chunk
