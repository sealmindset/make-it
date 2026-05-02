from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import AsyncIterator


@dataclass
class UsageStats:
    """Accumulated token and cost stats for a provider instance."""

    total_input_tokens: int = 0
    total_output_tokens: int = 0
    total_cost_usd: float = 0.0
    request_count: int = 0

    def record(self, input_tokens: int, output_tokens: int, cost: float) -> None:
        self.total_input_tokens += input_tokens
        self.total_output_tokens += output_tokens
        self.total_cost_usd += cost
        self.request_count += 1

    @property
    def total_tokens(self) -> int:
        return self.total_input_tokens + self.total_output_tokens


class AIProvider(ABC):
    """Abstract base class for AI providers.

    Concrete providers must implement ``complete`` and ``stream``.
    Optionally override ``estimate_cost`` to enable spend tracking.
    """

    def __init__(self) -> None:
        self.usage = UsageStats()

    @abstractmethod
    async def complete(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> str:
        ...

    @abstractmethod
    async def stream(
        self,
        system_prompt: str,
        user_prompt: str,
        model: str | None = None,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        ...

    def estimate_cost(self, input_tokens: int, output_tokens: int) -> float:
        """Return estimated cost in USD.  Default 0 (local/free providers)."""
        return 0.0
