import logging

from app.config import settings
from app.lib.ai.provider import AIProvider

logger = logging.getLogger(__name__)


def _build_provider(name: str) -> AIProvider:
    """Instantiate a single provider by name."""
    if name == "anthropic_foundry":
        from app.lib.ai.providers.anthropic_foundry import AnthropicFoundryProvider

        return AnthropicFoundryProvider()
    elif name == "anthropic":
        from app.lib.ai.providers.anthropic_direct import AnthropicDirectProvider

        return AnthropicDirectProvider()
    elif name == "openai":
        from app.lib.ai.providers.openai_provider import OpenAIProvider

        return OpenAIProvider()
    elif name == "ollama":
        from app.lib.ai.providers.ollama import OllamaProvider

        return OllamaProvider()
    else:
        raise ValueError(f"Unknown AI provider: {name}")


def get_ai_provider() -> AIProvider:
    """Build the configured AI provider, optionally wrapped in failover."""
    primary = _build_provider(settings.AI_PROVIDER.lower())

    failover_name = getattr(settings, "AI_FAILOVER_PROVIDER", "").lower()
    if failover_name:
        from app.lib.ai.providers.failover import FailoverProvider

        secondary = _build_provider(failover_name)
        logger.info(
            "AI failover enabled: %s -> %s",
            primary.__class__.__name__,
            secondary.__class__.__name__,
        )
        return FailoverProvider(primary, secondary)

    return primary
