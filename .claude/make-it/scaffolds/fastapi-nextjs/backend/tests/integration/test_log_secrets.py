"""No secret reaches anything the app writes, and a failed outgoing call is recorded (build-standards L03, L04).

Each test starts a real uvicorn server on the app, the way entrypoint.sh does, with one extra route that
makes outgoing calls through `attach_outbound_logging` to a small HTTP server standing in for the far
side. Secrets ride in on every road (query string, form body, JSON body, headers, a redirect address,
the address's own user:password and path), and then the test reads everything the app wrote: the log
store itself, what the logs API returns to the admin page (events and stats), and the console.
Every secret value is made at run time, so none is written in this file.
"""

import asyncio
import base64
import contextlib
import logging
import secrets
import socket
import threading
import time
from datetime import UTC, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import httpx
import jwt
import pytest
import uvicorn
from starlette.requests import Request
from starlette.responses import RedirectResponse

from app.config import settings
from app.main import _fastapi_app
from app.services.log_service import attach_outbound_logging, log_store, sanitize_url
from tests.conftest import ADMIN_USER

UVICORN_LOGGERS = ("uvicorn", "uvicorn.error", "uvicorn.access")

# Names a secret travels under, and one that is on nobody's list: masking must not depend on the name.
SECRET_NAMES = (
    "access_token",
    "refresh_token",
    "id_token",
    "client_secret",
    "code",
    "password",
    "X-Amz-Signature",
    "api_key",
    "token",
    "state",
    "zz_on_nobodys_list",
)


class Minted(dict):
    """Every secret value a test made, by a label that says where it was put."""

    def new(self, label: str) -> str:
        self[label] = secrets.token_hex(16)
        return self[label]

    def named(self, where: str) -> dict[str, str]:
        return {name: self.new(f"{name} in {where}") for name in SECRET_NAMES}


@pytest.fixture()
def minted():
    return Minted()


@pytest.fixture()
def jwt_secret(monkeypatch):
    secret = secrets.token_hex(32)
    monkeypatch.setattr(settings, "JWT_SECRET", secret)
    return secret


@pytest.fixture(autouse=True)
def _real_auth_empty_log_and_uvicorn_logging_as_found():
    _fastapi_app.dependency_overrides.clear()
    log_store.clear()
    yield
    log_store.clear()
    # uvicorn's set-up points its handlers at this test's captured output; detach them.
    for name in UVICORN_LOGGERS:
        logging.getLogger(name).handlers.clear()


class _FarSide(BaseHTTPRequestHandler):
    """The far side of an outgoing call. It is not the app, so it prints nothing."""

    def _answer(self):
        self.rfile.read(int(self.headers.get("content-length") or 0))
        path = self.path.split("?")[0]
        if path == "/redirect":
            self.send_response(302)
            self.send_header("Location", self.server.redirect_to)  # type: ignore[attr-defined]
        elif path == "/refuse":
            self.send_response(401)
        elif path == "/slow":
            time.sleep(1.5)
            self.send_response(200)
        else:
            self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_GET = do_POST = _answer  # noqa: N815 -- the names http.server calls

    def log_message(self, *args):
        pass


@pytest.fixture()
def far_side():
    server = ThreadingHTTPServer(("127.0.0.1", 0), _FarSide)
    server.daemon_threads = True
    server.redirect_to = "/landed"  # type: ignore[attr-defined]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield server
    server.shutdown()
    server.server_close()


def _url(server) -> str:
    return f"http://127.0.0.1:{server.server_address[1]}"


@pytest.fixture()
def probe():
    """A route on the real app that makes the outgoing calls a test hands it, through the logging hooks."""
    todo = {}

    async def handler(request: Request):
        await request.body()
        async with httpx.AsyncClient(follow_redirects=True, timeout=0.5) as client:
            attach_outbound_logging(client, "far-side")
            answer = await todo["calls"](client) if "calls" in todo else None
        return answer or {"ok": True}

    _fastapi_app.add_api_route("/api/probe", handler, methods=["GET", "POST"], response_model=None)
    route = _fastapi_app.router.routes[-1]
    yield todo
    _fastapi_app.router.routes.remove(route)


@contextlib.asynccontextmanager
async def _served():
    """Run uvicorn on the app the way entrypoint.sh starts it; yields its address."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    server = uvicorn.Server(uvicorn.Config("app.main:app", proxy_headers=False))  # entrypoint.sh's flag
    task = asyncio.create_task(server.serve(sockets=[sock]))
    try:
        for _ in range(500):
            if server.started:
                break
            await asyncio.sleep(0.01)
        assert server.started, "uvicorn did not start"
        yield f"http://127.0.0.1:{sock.getsockname()[1]}"
    finally:
        server.should_exit = True
        await task
        sock.close()


async def _what_the_admin_sees(base: str, jwt_secret: str) -> dict:
    """The logs API, as the Activity Logs page calls it, signed in through the real cookie path."""
    now = datetime.now(UTC)
    claims = {**ADMIN_USER.model_dump(), "iat": now, "exp": now + timedelta(hours=1)}
    cookies = {"token": jwt.encode(claims, jwt_secret, algorithm="HS256")}
    async with httpx.AsyncClient(base_url=base, cookies=cookies) as admin:
        events = await admin.get("/api/admin/logs/events", params={"limit": 1000})
        stats = await admin.get("/api/admin/logs/stats")
    assert events.status_code == 200 and stats.status_code == 200
    store = repr([[getattr(e, slot) for slot in e.__slots__] for e in log_store._buffer])
    return {"events": events.json(), "stats": stats.json(), "texts": [store, events.text, stats.text]}


def _assert_no_secret(minted: Minted, seen: dict, capsys) -> str:
    """Call after the server has stopped. Returns the console text."""
    out = capsys.readouterr()
    console = out.out + out.err
    wrote = dict(zip(("the log store", "the logs API's events", "the logs API's stats"), seen["texts"], strict=True))
    wrote["the console"] = console
    assert minted, "the test made no secret"
    for where, text in wrote.items():
        for label, value in minted.items():
            assert value not in text, f"the value of [{label}] is in {where}"
    return console


def _outbound(seen: dict) -> list[dict]:
    return [e for e in seen["events"] if e["type"] == "outbound"]


@pytest.mark.asyncio
async def test_no_secret_in_a_request_reaches_anything_the_app_writes(minted, jwt_secret, probe, capsys):
    async def answer_with_a_redirect(_client):
        return RedirectResponse(f"/elsewhere?code={minted.new('code in the redirect the app answers with')}")

    probe["calls"] = answer_with_a_redirect
    headers = {
        "Authorization": f"Bearer {minted.new('Authorization header')}",
        "Cookie": f"session={minted.new('Cookie header')}",
        "X-Api-Key": minted.new("X-Api-Key header"),
    }
    async with _served() as base:
        async with httpx.AsyncClient(base_url=base, headers=headers) as caller:
            in_query = minted.named("the query string")
            assert (await caller.get("/api/probe", params=in_query)).status_code == 307
            assert (await caller.post("/api/probe", data=minted.named("a form body"))).status_code == 307
            assert (await caller.post("/api/probe", json=minted.named("a JSON body"))).status_code == 307
            callback = {"code": minted.new("sign-in code"), "state": minted.new("sign-in state")}
            assert (await caller.get("/api/auth/callback", params=callback)).status_code == 400
            searched = {"q": minted.new("a search of the log itself")}
            assert (await caller.get("/api/admin/logs/events", params=searched)).status_code == 401
        seen = await _what_the_admin_sees(base, jwt_secret)
    console = _assert_no_secret(minted, seen, capsys)
    assert '"GET /api/probe HTTP/1.1" 307' in console  # method, path and status are still printed
    assert '"GET /api/auth/callback HTTP/1.1" 400' in console
    assert sum(1 for e in seen["events"] if e["path"] == "/api/probe") == 3  # and still recorded


@pytest.mark.asyncio
async def test_no_secret_in_an_outgoing_call_reaches_anything_the_app_writes(
    minted, jwt_secret, probe, far_side, capsys
):
    there = _url(far_side)
    far_side.redirect_to = (
        f"/landed?access_token={minted.new('access_token in a redirect address')}"
        f"&code={minted.new('code in a redirect address')}"
    )
    user_password = minted.new("password in the address (user:password@host)")
    minted["the same password as a Basic header"] = base64.b64encode(f"svc:{user_password}".encode()).decode()

    async def calls(client):
        headers = {
            "Authorization": f"Bearer {minted.new('outgoing Authorization header')}",
            "Cookie": f"session={minted.new('outgoing Cookie header')}",
        }
        await client.get(f"{there}/items", params={**minted.named("an outgoing query string"), "page": "2"})
        await client.get(f"{there}/items?{minted.new('a bare value with no name')}", headers=headers)
        await client.post(f"{there}/token", data=minted.named("an outgoing form body"))
        await client.post(f"{there}/token", json=minted.named("an outgoing JSON body"))
        await client.get(f"{there.replace('://', f'://svc:{user_password}@')}/basic")
        await client.get(f"{there}/redirect")
        await client.post(f"{there}/hooks/{minted.new('a secret in the path')}/send")
        await client.get(f"{there}/refuse", params={"api_key": minted.new("api_key the far side refused")})

    probe["calls"] = calls
    async with _served() as base:
        async with httpx.AsyncClient(base_url=base) as caller:
            assert (await caller.post("/api/probe")).status_code == 200
        seen = await _what_the_admin_sees(base, jwt_secret)
    _assert_no_secret(minted, seen, capsys)

    urls = [e["url"] for e in _outbound(seen)]
    assert len(urls) == 9  # eight calls, and the redirect's second hop
    first = next(u for u in urls if "page=" in u)
    assert "page=2" in first  # a name known to be safe keeps its value
    for name in SECRET_NAMES:
        assert f"{name}=***" in first  # every other name is kept, its value masked
    assert f"{there}/landed?access_token=***&code=***" in urls
    assert f"{there}/basic" in urls
    assert f"{there}/hooks/***/send" in urls
    refused = next(e for e in _outbound(seen) if e["path"] == "/refuse")
    assert (refused["status"], refused["error"]) == (401, "401")


@pytest.mark.asyncio
async def test_an_error_raised_from_a_refused_outgoing_call_prints_no_secret(
    minted, jwt_secret, probe, far_side, capsys
):
    # raise_for_status() writes the whole address into its message; unhandled, uvicorn prints it.
    async def calls(client):
        params = minted.named("the address of a call that was refused and raised")
        (await client.get(f"{_url(far_side)}/refuse", params=params)).raise_for_status()

    probe["calls"] = calls
    async with _served() as base:
        async with httpx.AsyncClient(base_url=base) as caller:
            assert (await caller.post("/api/probe")).status_code == 500
        seen = await _what_the_admin_sees(base, jwt_secret)
    console = _assert_no_secret(minted, seen, capsys)
    assert "HTTPStatusError" in console  # the error itself is still printed
    assert "/refuse?access_token=***" in console


@pytest.mark.asyncio
@pytest.mark.parametrize("how", ["nothing is listening", "no answer in time"])
async def test_a_failed_outgoing_call_leaves_an_entry_that_says_it_failed(
    how, minted, jwt_secret, probe, far_side, capsys
):
    if how == "nothing is listening":
        closed = socket.socket()
        closed.bind(("127.0.0.1", 0))
        there, path, error = f"http://127.0.0.1:{closed.getsockname()[1]}", "/items", "ConnectError"
        closed.close()
    else:
        there, path, error = _url(far_side), "/slow", "ReadTimeout"

    async def calls(client):
        await client.get(f"{there}{path}", params=minted.named("the address of a call that failed"))

    probe["calls"] = calls
    async with _served() as base:
        async with httpx.AsyncClient(base_url=base) as caller:
            assert (await caller.post("/api/probe")).status_code == 500
        seen = await _what_the_admin_sees(base, jwt_secret)
    console = _assert_no_secret(minted, seen, capsys)
    assert error in console  # the unhandled error is still printed

    assert len(_outbound(seen)) == 1
    entry = _outbound(seen)[0]
    assert entry["error"] == error
    assert entry["status"] is None
    assert (entry["method"], entry["path"], entry["service"]) == ("GET", path, "far-side")
    assert entry["url"].startswith(f"{there}{path}?access_token=***")
    assert entry["duration_ms"] is not None
    # the page's "recent errors" counts it, though it has no status (the route's own crash is not an event)
    assert seen["stats"]["recent_errors"] == 1


@pytest.mark.asyncio
async def test_with_httpx_logging_turned_up_the_console_still_prints_no_secret(
    minted, jwt_secret, probe, far_side, capsys
):
    # An app that sets logging to INFO makes httpx print one line per outgoing call, address included.
    async def calls(client):
        await client.get(f"{_url(far_side)}/items", params=minted.named("an outgoing query string"))

    probe["calls"] = calls
    httpx_logger = logging.getLogger("httpx")
    handler, level = logging.StreamHandler(), httpx_logger.level
    httpx_logger.addHandler(handler)
    httpx_logger.setLevel(logging.INFO)
    try:
        async with _served() as base:
            async with httpx.AsyncClient(base_url=base) as caller:
                in_query = minted.named("the query string")
                assert (await caller.post("/api/probe", params=in_query)).status_code == 200
            seen = await _what_the_admin_sees(base, jwt_secret)
    finally:
        httpx_logger.removeHandler(handler)
        httpx_logger.setLevel(level)
    console = _assert_no_secret(minted, seen, capsys)
    assert "HTTP Request: GET " in console and "/items?access_token=***" in console


def test_an_address_keeps_only_what_is_known_to_be_safe():
    s = secrets.token_hex(16)
    uuid = "0b9f3c1e-7a52-4d0e-9c41-5e2f8a6b7d10"
    for raw, safe in [
        ("https://api.example.com/v1/items", "https://api.example.com/v1/items"),
        (f"https://h/p?page=2&limit=50&access_token={s}", "https://h/p?page=2&limit=50&access_token=***"),
        (f"https://h/p?PAGE=3&Client_Secret={s}", "https://h/p?PAGE=3&Client_Secret=***"),
        (f"https://h/p?anything_else={s}", "https://h/p?anything_else=***"),
        ("https://h/p?short=1", "https://h/p?short=***"),  # not known to be safe, so masked, however short
        (f"https://h/p?page={s}", "https://h/p?page=***"),  # a safe name with a long value is not believed
        (f"https://h/p?{s}", "https://h/p?***"),  # no name at all
        (f"https://h/p?a={s}&&b=", "https://h/p?a=***&b=***"),
        (f"https://user:{s}@h:8443/p", "https://h:8443/p"),
        (f"https://h/p#access_token={s}", "https://h/p"),
        (f"https://h/hooks/{s}/send", "https://h/hooks/***/send"),
        (f"https://h/items/{uuid}/notes", f"https://h/items/{uuid}/notes"),  # an id stays readable
        (f"/relative?token={s}", "/relative?token=***"),
        (f"http://[not-an-address/?token={s}", "***"),  # cannot be read as an address: nothing is kept
    ]:
        assert sanitize_url(raw) == safe
