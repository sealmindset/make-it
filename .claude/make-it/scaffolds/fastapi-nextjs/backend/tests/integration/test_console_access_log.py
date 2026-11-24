"""The server's console log never prints a query string (build-standards L10).

The sign-in return route is GET /api/auth/callback?code=...&state=..., and uvicorn's access log
prints each request's path with its query string, so every sign-in's one-time code and state went
to the console -- and from there to whatever collects the container's output. These tests start a
real uvicorn server on the app, with uvicorn's own logging set-up, and read what it prints.
"""

import asyncio
import logging
import socket

import httpx
import pytest
import uvicorn

UVICORN_LOGGERS = ("uvicorn", "uvicorn.error", "uvicorn.access")


@pytest.fixture()
def _leave_uvicorn_logging_as_found():
    yield
    # uvicorn's set-up points its handlers at this test's captured stdout; detach them.
    for name in UVICORN_LOGGERS:
        logging.getLogger(name).handlers.clear()


async def _serve_and_get(*paths):
    """Run uvicorn on the app the way entrypoint.sh starts it, request each path, stop it."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config("app.main:app", proxy_headers=False))  # entrypoint.sh's flag
    task = asyncio.create_task(server.serve(sockets=[sock]))
    try:
        for _ in range(500):
            if server.started:
                break
            await asyncio.sleep(0.01)
        assert server.started, "uvicorn did not start"
        statuses = []
        async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{port}") as client:
            for path in paths:
                statuses.append((await client.get(path)).status_code)
        return statuses
    finally:
        server.should_exit = True
        await task
        sock.close()


@pytest.mark.asyncio
@pytest.mark.usefixtures("_leave_uvicorn_logging_as_found")
async def test_sign_in_code_and_state_never_reach_the_console(capsys):
    code, state = "one-time-code-4d1f9a", "state-value-77c2e0"
    statuses = await _serve_and_get(f"/api/auth/callback?code={code}&state={state}")
    assert statuses == [400]  # no oidc_state cookie: refused before any call to the provider
    out = capsys.readouterr()
    printed = out.out + out.err
    assert code not in printed
    assert state not in printed
    assert '"GET /api/auth/callback HTTP/1.1" 400' in printed  # method, path and status still logged


@pytest.mark.asyncio
@pytest.mark.usefixtures("_leave_uvicorn_logging_as_found")
async def test_any_query_string_is_left_out(capsys):
    statuses = await _serve_and_get("/api/health?token=abc123secret&next=%2Fadmin", "/api/health")
    assert statuses == [200, 200]
    out = capsys.readouterr()
    printed = out.out + out.err
    assert "abc123secret" not in printed
    assert "token=" not in printed
    assert printed.count('"GET /api/health HTTP/1.1" 200') == 2
