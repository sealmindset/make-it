"""Keep query strings out of the server's console log.

uvicorn prints each request as `"GET /path?query HTTP/1.1" 200`. The sign-in return route is
GET /api/auth/callback?code=...&state=..., so every sign-in's one-time code and state would land in
the console, and from there in whatever collects the container's output. This filter leaves the
method, path and status and drops everything after the `?`. It sits on uvicorn's own loggers, so it
holds however uvicorn is started (entrypoint.sh, a reload run, more workers).

A second filter masks full addresses in the two other lines that carry one (see MaskAddresses).
"""

import logging
import traceback

import httpx

from app.services.log_service import sanitize_text

# uvicorn.access: one line per HTTP request. uvicorn.error: also carries the WebSocket lines.
_LOGGERS = ("uvicorn.access", "uvicorn.error")
# uvicorn.error: also prints the traceback of an unhandled error. httpx: one line per outgoing call, at INFO.
_ADDRESS_LOGGERS = ("uvicorn.error", "httpx")


class DropQueryString(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.args, tuple) and record.args:
            record.args = tuple(
                arg.split("?", 1)[0] if isinstance(arg, str) and arg.startswith("/") and "?" in arg else arg
                for arg in record.args
            )
        return True


class MaskAddresses(logging.Filter):
    """Mask every full address (http://... or https://...) a line carries, the way the activity log does.

    Two lines carry one: httpx's own "HTTP Request: GET <address>" line, printed for every outgoing call
    once an app sets logging to INFO, and the traceback uvicorn prints for an unhandled error --
    `raise_for_status()` writes the whole address, query string included, into its message.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.args, tuple):
            record.args = tuple(
                sanitize_text(str(arg)) if isinstance(arg, str | httpx.URL) else arg for arg in record.args
            )
        if record.exc_info and record.exc_info[0] and not record.exc_text:
            # the formatter prints exc_text as it finds it
            record.exc_text = sanitize_text("".join(traceback.format_exception(*record.exc_info)).rstrip("\n"))
        return True


def drop_query_strings_from_server_log() -> None:
    """Install the filters once on each logger (safe to call again)."""
    for names, kind in ((_LOGGERS, DropQueryString), (_ADDRESS_LOGGERS, MaskAddresses)):
        for name in names:
            logger = logging.getLogger(name)
            if not any(isinstance(f, kind) for f in logger.filters):
                logger.addFilter(kind())
