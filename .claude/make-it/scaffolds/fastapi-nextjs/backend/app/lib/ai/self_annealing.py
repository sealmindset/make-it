"""Model self-annealing for Anthropic providers.

Detects invalid model names from API errors and auto-corrects them
to prevent cascading failures when config drifts or typos occur.
"""

import logging

logger = logging.getLogger(__name__)

VALID_MODEL_PREFIXES = (
    "claude-3-",
    "claude-sonnet-",
    "claude-haiku-",
    "claude-opus-",
    "cogdep-aifoundry",
)

DEFAULT_MODEL = "claude-sonnet-4-20250514"

_INVALID_PATTERNS = ["llama", "gpt-", "mistral", "gemma", "phi-", "qwen"]


def validate_model(model: str) -> str:
    """Return *model* if it looks like a valid Claude model, else DEFAULT_MODEL."""
    lower = (model or "").lower()
    if any(lower.startswith(p) for p in VALID_MODEL_PREFIXES):
        return model
    logger.warning(
        "Self-annealing: '%s' is not a recognised Claude model, correcting to '%s'",
        model,
        DEFAULT_MODEL,
    )
    return DEFAULT_MODEL


def detect_model_error(error_message: str) -> bool:
    lower = error_message.lower()
    if "not_found_error" in lower and "model" in lower:
        return True
    for pat in _INVALID_PATTERNS:
        if pat in lower:
            return True
    return False


def extract_corrected_model(error_message: str, current_model: str) -> str:
    """When an API call fails with a model error, return a safe fallback."""
    logger.warning(
        "Self-annealing: API error suggests invalid model '%s', correcting to '%s'. Error: %s",
        current_model,
        DEFAULT_MODEL,
        error_message[:200],
    )
    return DEFAULT_MODEL
