"""In-memory activity log service with circular buffer.

Captures inbound API requests and outbound HTTP calls for observability.
Buffer size configurable via LOG_BUFFER_SIZE env var (default 10000).
"""

import time
from collections import deque
from datetime import datetime, timezone
from typing import Any

from app.config import settings


class LogEvent:
    __slots__ = ("timestamp", "event_type", "method", "path", "status", "duration_ms", "service", "user_sub", "user_email")

    def __init__(
        self,
        event_type: str,
        method: str,
        path: str,
        status: int | None = None,
        duration_ms: float | None = None,
        service: str | None = None,
        user_sub: str | None = None,
        user_email: str | None = None,
    ):
        self.timestamp = datetime.now(timezone.utc).isoformat()
        self.event_type = event_type
        self.method = method
        self.path = path
        self.status = status
        self.duration_ms = duration_ms
        self.service = service
        self.user_sub = user_sub
        self.user_email = user_email

    def to_dict(self) -> dict[str, Any]:
        return {
            "timestamp": self.timestamp,
            "type": self.event_type,
            "method": self.method,
            "path": self.path,
            "status": self.status,
            "duration_ms": self.duration_ms,
            "service": self.service,
            "user_sub": self.user_sub,
            "user_email": self.user_email,
        }


class LogStore:
    """Circular buffer for log events. FIFO eviction when full."""

    def __init__(self, max_size: int | None = None):
        self._max_size = max_size or settings.LOG_BUFFER_SIZE
        self._buffer: deque[LogEvent] = deque(maxlen=self._max_size)
        self._total_received: int = 0
        self._start_time = time.time()

    def add(self, event: LogEvent) -> None:
        self._buffer.append(event)
        self._total_received += 1

    def query(
        self,
        event_type: str | None = None,
        service: str | None = None,
        method: str | None = None,
        since: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        results = []
        for event in reversed(self._buffer):
            if event_type and event.event_type != event_type:
                continue
            if service and event.service != service:
                continue
            if method and event.method.upper() != method.upper():
                continue
            if since and event.timestamp < since:
                continue
            results.append(event.to_dict())
            if len(results) >= limit:
                break
        return results

    def stats(self) -> dict[str, Any]:
        error_count = sum(1 for e in self._buffer if e.status and e.status >= 400)
        return {
            "buffer_size": self._max_size,
            "buffer_used": len(self._buffer),
            "total_received": self._total_received,
            "total_evicted": max(0, self._total_received - len(self._buffer)),
            "recent_errors": error_count,
            "uptime_seconds": round(time.time() - self._start_time),
        }

    def clear(self) -> None:
        self._buffer.clear()


# Singleton
log_store = LogStore()


# Sensitive param names to strip from URLs
_SENSITIVE_PARAMS = {"token", "key", "secret", "password", "auth", "api_key", "apikey"}


def sanitize_url(url: str) -> str:
    """Strip sensitive query params from a URL before logging."""
    if "?" not in url:
        return url
    base, query = url.split("?", 1)
    params = []
    for param in query.split("&"):
        name = param.split("=", 1)[0].lower()
        if name in _SENSITIVE_PARAMS:
            params.append(f"{param.split('=', 1)[0]}=***")
        else:
            params.append(param)
    return f"{base}?{'&'.join(params)}"
