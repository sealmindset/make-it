"""AI error sanitization.

Maps provider-specific exceptions to generic, client-safe error messages
so that internal details (API keys, endpoints, stack traces) are never
leaked to the frontend.
"""

import logging

logger = logging.getLogger(__name__)


class AIProviderError(Exception):
    """Base exception for AI provider errors."""

    def __init__(self, client_message: str, internal_message: str | None = None):
        self.client_message = client_message
        self.internal_message = internal_message or client_message
        super().__init__(self.client_message)


class AIRateLimitError(AIProviderError):
    def __init__(self, internal_message: str | None = None):
        super().__init__(
            client_message="AI service is temporarily busy. Please try again in a moment.",
            internal_message=internal_message,
        )


class AIAuthenticationError(AIProviderError):
    def __init__(self, internal_message: str | None = None):
        super().__init__(
            client_message="AI service is currently unavailable.",
            internal_message=internal_message,
        )


class AIContextLengthError(AIProviderError):
    def __init__(self, internal_message: str | None = None):
        super().__init__(
            client_message="The input is too long for the AI model. Please reduce the content and try again.",
            internal_message=internal_message,
        )


class AIServiceUnavailableError(AIProviderError):
    def __init__(self, internal_message: str | None = None):
        super().__init__(
            client_message="AI service is currently unavailable. Please try again later.",
            internal_message=internal_message,
        )


def sanitize_ai_error(exc: Exception) -> AIProviderError:
    """Convert a raw provider exception into a client-safe AIProviderError."""
    exc_type = type(exc).__name__
    exc_message = str(exc)

    logger.error("AI provider error [%s]: %s", exc_type, exc_message, exc_info=True)

    lower_msg = exc_message.lower()

    if "rate" in lower_msg or "429" in exc_message:
        return AIRateLimitError(internal_message=exc_message)

    if "auth" in lower_msg or "401" in exc_message or "403" in exc_message:
        return AIAuthenticationError(internal_message=exc_message)

    if "context" in lower_msg or "too long" in lower_msg or "token" in lower_msg:
        return AIContextLengthError(internal_message=exc_message)

    if "unavailable" in lower_msg or "503" in exc_message or "timeout" in lower_msg:
        return AIServiceUnavailableError(internal_message=exc_message)

    return AIProviderError(
        client_message="An unexpected AI error occurred. Please try again.",
        internal_message=exc_message,
    )
