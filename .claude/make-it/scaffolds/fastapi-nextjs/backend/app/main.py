from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.middleware.logging import RequestLoggingMiddleware
from app.routers import auth, logs, permissions, roles, users
from app.routers import settings as settings_router

app = FastAPI(title="[APP_SLUG]", version="0.1.0")

# Middleware
app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.FRONTEND_URL],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check endpoints
@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/api/health")
async def api_health():
    return {"status": "ok"}


# Core routers (auth, RBAC, admin)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(roles.router)
app.include_router(permissions.router)
app.include_router(settings_router.router)
app.include_router(logs.router)

# [DOMAIN_ROUTERS] -- add app-specific routers here


# --------------------------------------------------------------------------
# Trailing-slash ASGI wrapper
# --------------------------------------------------------------------------
# FastAPI registers list endpoints with trailing slash (e.g., /api/rfcs/).
# Behind a reverse proxy, requests arrive without it (/api/rfcs).
# FastAPI's built-in redirect leaks the internal Docker hostname.
# This wrapper silently rewrites matching requests.
# --------------------------------------------------------------------------
from starlette.routing import Match  # noqa: E402
from starlette.types import ASGIApp, Receive, Scope, Send  # noqa: E402


_fastapi_app = app  # Save reference before wrapping


class TrailingSlashASGI:
    """Add trailing slash only to paths that have a registered route with one."""

    def __init__(self, inner: ASGIApp):
        self.inner = inner

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] == "http":
            path = scope["path"]
            if path.startswith("/api/") and not path.endswith("/"):
                test_scope = {**scope, "path": path + "/"}
                for route in _fastapi_app.routes:
                    match, _ = route.matches(test_scope)
                    if match == Match.FULL:
                        scope["path"] = path + "/"
                        break
        await self.inner(scope, receive, send)


app = TrailingSlashASGI(_fastapi_app)  # type: ignore[assignment]
