"""Keep query strings out of the server's console log.

uvicorn prints each request as `"GET /path?query HTTP/1.1" 200`. The sign-in return route is
GET /api/auth/callback?code=...&state=..., so every sign-in's one-time code and state would land in
the console, and from there in whatever collects the container's output. This filter leaves the
method, path and status and drops everything after the `?`. It sits on uvicorn's own loggers, so it
holds however uvicorn is started (entrypoint.sh, a reload run, more workers).
"""

import logging

# uvicorn.access: one line per HTTP request. uvicorn.error: also carries the WebSocket lines.
_LOGGERS = ("uvicorn.access", "uvicorn.error")


class DropQueryString(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.args, tuple) and record.args:
            record.args = tuple(
                arg.split("?", 1)[0] if isinstance(arg, str) and arg.startswith("/") and "?" in arg else arg
                for arg in record.args
            )
        return True


def drop_query_strings_from_server_log() -> None:
    """Install the filter once on each uvicorn logger (safe to call again)."""
    for name in _LOGGERS:
        logger = logging.getLogger(name)
        if not any(isinstance(f, DropQueryString) for f in logger.filters):
            logger.addFilter(DropQueryString())
