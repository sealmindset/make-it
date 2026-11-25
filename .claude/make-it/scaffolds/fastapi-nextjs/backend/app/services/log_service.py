"""In-memory activity log service with circular buffer.

Captures inbound API requests and outbound HTTP calls (answered or not) for observability.
Buffer size configurable via LOG_BUFFER_SIZE env var (default 10000).
"""

import re
import time
from collections import Counter, deque
from datetime import UTC, datetime
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx

from app.config import settings


class LogEvent:
    __slots__ = (
        "timestamp",
        "event_type",
        "method",
        "path",
        "url",
        "status",
        "duration_ms",
        "service",
        "user_sub",
        "user_email",
        "ip",
        "user_agent",
        "error",
    )

    def __init__(
        self,
        event_type: str,
        method: str,
        path: str,
        *,
        url: str | None = None,
        status: int | None = None,
        duration_ms: float | None = None,
        service: str | None = None,
        user_sub: str | None = None,
        user_email: str | None = None,
        ip: str | None = None,
        user_agent: str | None = None,
        error: str | None = None,
    ):
        self.timestamp = datetime.now(UTC).isoformat()
        self.event_type = event_type
        self.method = method
        self.path = path
        self.url = url
        self.status = status
        self.duration_ms = duration_ms
        self.service = service
        self.user_sub = user_sub
        self.user_email = user_email
        self.ip = ip
        self.user_agent = user_agent
        self.error = error

    def to_dict(self) -> dict[str, Any]:
        return {
            "timestamp": self.timestamp,
            "type": self.event_type,
            "method": self.method,
            "path": self.path,
            "url": self.url,
            "status": self.status,
            "duration_ms": self.duration_ms,
            "service": self.service,
            "user_sub": self.user_sub,
            "user_email": self.user_email,
            "ip": self.ip,
            "user_agent": self.user_agent,
            "error": self.error,
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
        path: str | None = None,
        status_min: int | None = None,
        status_max: int | None = None,
        user_email: str | None = None,
        q: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        results = []
        skipped = 0
        q_lower = q.lower() if q else None

        for event in reversed(self._buffer):
            if event_type and event.event_type != event_type:
                continue
            if service and event.service != service:
                continue
            if method and event.method.upper() != method.upper():
                continue
            if since and event.timestamp < since:
                continue
            if (
                path
                and path.lower() not in (event.path or "").lower()
                and path.lower() not in (event.url or "").lower()
            ):
                continue
            if status_min is not None and (event.status is None or event.status < status_min):
                continue
            if status_max is not None and (event.status is None or event.status > status_max):
                continue
            if user_email and user_email.lower() not in (event.user_email or "").lower():
                continue
            if q_lower and not _matches_free_text(event, q_lower):
                continue

            if skipped < offset:
                skipped += 1
                continue

            results.append(event.to_dict())
            if len(results) >= limit:
                break
        return results

    def stats(self) -> dict[str, Any]:
        # an outbound call that got no response has an error and no status
        error_count = sum(1 for e in self._buffer if e.error or (e.status and e.status >= 400))

        by_type: Counter[str] = Counter()
        by_service: Counter[str] = Counter()
        by_status: Counter[str] = Counter()
        for e in self._buffer:
            by_type[e.event_type] += 1
            if e.service:
                by_service[e.service] += 1
            if e.status is not None:
                if e.status < 300:
                    by_status["2xx"] += 1
                elif e.status < 400:
                    by_status["3xx"] += 1
                elif e.status < 500:
                    by_status["4xx"] += 1
                else:
                    by_status["5xx"] += 1

        return {
            "buffer_size": self._max_size,
            "buffer_used": len(self._buffer),
            "total_received": self._total_received,
            "total_evicted": max(0, self._total_received - len(self._buffer)),
            "recent_errors": error_count,
            "uptime_seconds": round(time.time() - self._start_time),
            "events_by_type": dict(by_type),
            "events_by_service": dict(by_service),
            "events_by_status": dict(by_status),
        }

    def clear(self) -> None:
        self._buffer.clear()


def _matches_free_text(event: LogEvent, q: str) -> bool:
    """Check if any searchable field contains the query string."""
    for val in (event.path, event.url, event.error, event.user_email, event.service):
        if val and q in val.lower():
            return True
    return False


# Singleton
log_store = LogStore()


# ---------------------------------------------------------------------------
# URL sanitization
# ---------------------------------------------------------------------------
# An allow-list, not a list of bad names: a query value is kept only when its name is one of these
# (and the value is short). Every other value is written as ***, whatever it is called, so the next
# secret-carrying name nobody thought of is masked too. Add a name here only if it never carries a secret.
_SAFE_QUERY_PARAMS = frozenset(
    {
        "page",
        "per_page",
        "page_size",
        "limit",
        "offset",
        "sort",
        "sort_by",
        "order",
        "order_by",
        "format",
        "lang",
        "locale",
        "version",
        "api-version",
        "api_version",
    }
)
# A path segment or a "safe" value this long could be a key (a webhook address carries one in its path).
_LONG = 20
_UUID = re.compile(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", re.IGNORECASE)
_ADDRESS = re.compile(r"https?://[^\s'\"<>]+")


def sanitize_url(url: str) -> str:
    """An address that is safe to log: no user:password, no fragment, query values masked unless known safe.

    A path segment of 20 or more characters that is not a UUID is masked too. That part is a guess, not a
    proof: a shorter secret in a path is not caught.
    """
    try:
        parts = urlsplit(url)
    except ValueError:
        return "***"
    path = "/".join(
        "***" if len(segment) >= _LONG and not _UUID.fullmatch(segment) else segment
        for segment in parts.path.split("/")
    )
    query = "&".join(
        f"{name}={value}"
        if name.lower() in _SAFE_QUERY_PARAMS and len(value) < _LONG
        else (f"{name}=***" if has_value else "***")
        for name, has_value, value in (param.partition("=") for param in parts.query.split("&") if param)
    )
    return urlunsplit((parts.scheme, parts.netloc.rpartition("@")[2], path, query, ""))


def sanitize_text(text: str) -> str:
    """The same masking for every http(s) address inside a longer text (an error message, a traceback)."""
    return _ADDRESS.sub(lambda found: sanitize_url(found.group()), text)


# ---------------------------------------------------------------------------
# Outbound HTTP logging -- httpx event hooks
# ---------------------------------------------------------------------------


def attach_outbound_logging(client: httpx.AsyncClient, service_name: str) -> httpx.AsyncClient:
    """Attach logging to an httpx.AsyncClient: one entry per outbound call, answered or not.

    Usage in service clients:
        client = httpx.AsyncClient(base_url=settings.JIRA_BASE_URL)
        attach_outbound_logging(client, "jira")
    """

    def _record(request: httpx.Request, status: int | None, error: str | None) -> None:
        start = request.extensions.get("log_start")
        safe_url = sanitize_url(str(request.url))
        log_store.add(
            LogEvent(
                event_type="outbound",
                method=request.method,
                path=urlsplit(safe_url).path,
                url=safe_url,
                status=status,
                duration_ms=round((time.time() - start) * 1000, 2) if start else None,
                service=service_name,
                error=error,
            )
        )

    async def _on_request(request: httpx.Request) -> None:
        request.extensions["log_start"] = time.time()

    async def _on_response(response: httpx.Response) -> None:
        status = response.status_code
        _record(response.request, status, str(status) if status >= 400 else None)

    # httpx has no hook for a call that got no response (refused, timed out, name not found), so the
    # client's send is wrapped. The entry carries the error's type only: its text can hold the address.
    send = client.send

    async def _send(request: httpx.Request, *args: Any, **kwargs: Any) -> httpx.Response:
        try:
            return await send(request, *args, **kwargs)
        except Exception as exc:
            try:
                failed = exc.request  # type: ignore[attr-defined]  # the hop that failed, after a redirect
            except (AttributeError, RuntimeError):
                failed = request
            _record(failed, None, type(exc).__name__)
            raise

    client.send = _send  # type: ignore[method-assign]
    client.event_hooks["request"].append(_on_request)
    client.event_hooks["response"].append(_on_response)
    return client
