"""Inbound request logging middleware."""

import time

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.services.log_service import LogEvent, log_store

# Paths to exclude from logging
_EXCLUDED_PREFIXES = ("/health", "/api/health", "/_next", "/favicon")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        path = request.url.path
        if any(path.startswith(prefix) for prefix in _EXCLUDED_PREFIXES):
            return await call_next(request)

        start = time.time()
        response = await call_next(request)
        duration_ms = round((time.time() - start) * 1000, 2)

        # Try to get user info from the request state
        user_sub = None
        user_email = None
        if hasattr(request.state, "user"):
            user = request.state.user
            user_sub = getattr(user, "sub", None)
            user_email = getattr(user, "email", None)

        event = LogEvent(
            event_type="inbound",
            method=request.method,
            path=path,
            status=response.status_code,
            duration_ms=duration_ms,
            service="[APP_SLUG]-api",
            user_sub=user_sub,
            user_email=user_email,
        )
        log_store.add(event)

        return response
