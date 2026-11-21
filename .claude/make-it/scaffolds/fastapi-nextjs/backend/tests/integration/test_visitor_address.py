"""The activity log records the visitor's address, not the proxy's (build-standards L11).

Every browser request reaches the backend through the same-origin frontend proxy (and, deployed,
through an ingress), so the address that connects is the proxy's. The visitor's address is in
X-Forwarded-For, which anyone can also write themselves. It is believed only when the request comes
from a proxy named in TRUSTED_PROXIES, and then the right-most address that is not a trusted proxy
is the visitor: an address the caller wrote in front of the one the proxy appended is never taken.
"""

import asyncio
import logging
import socket
from pathlib import Path

import httpx
import pytest
import uvicorn
from httpx import ASGITransport, AsyncClient

from app.main import TrailingSlashASGI, _fastapi_app
from app.main import app as served_app
from app.middleware import trusted_proxies
from app.middleware.trusted_proxies import TrustedProxyHeaders
from app.services.log_service import log_store

PROXY = "172.30.0.5"  # the frontend container, as compose addresses it
VISITOR = "203.0.113.7"
OTHER = "198.51.100.9"


@pytest.fixture(autouse=True)
def _empty_log():
    _fastapi_app.dependency_overrides.clear()
    log_store.clear()
    yield
    log_store.clear()


def _behind(trusted):
    """The served app's chain, as main.py builds it, with this trust list."""
    return TrustedProxyHeaders(TrailingSlashASGI(_fastapi_app), trusted)


async def _logged_address(app, peer, forwarded_for=None):
    log_store.clear()
    headers = {"x-forwarded-for": forwarded_for} if forwarded_for else {}
    transport = ASGITransport(app=app, client=(peer, 40000))
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        await client.get("/api/auth/me", headers=headers)
    events = [e for e in log_store.query(event_type="inbound", limit=100) if e["path"] == "/api/auth/me"]
    assert len(events) == 1
    return events[0]["ip"]


@pytest.mark.asyncio
async def test_the_served_app_checks_who_sent_the_header():
    assert isinstance(served_app, TrustedProxyHeaders)
    # The default trusts no proxy: the address that connected is the one recorded.
    assert await _logged_address(served_app, PROXY, VISITOR) == PROXY


@pytest.mark.asyncio
async def test_a_trusted_proxy_passes_on_the_visitor():
    assert await _logged_address(_behind(PROXY), PROXY, VISITOR) == VISITOR


@pytest.mark.asyncio
async def test_an_untrusted_caller_cannot_choose_its_address():
    assert await _logged_address(_behind(PROXY), OTHER, VISITOR) == OTHER


@pytest.mark.asyncio
async def test_an_address_the_caller_wrote_before_the_proxy_appended_is_ignored():
    assert await _logged_address(_behind(PROXY), PROXY, f"6.6.6.6, {VISITOR}") == VISITOR


@pytest.mark.asyncio
async def test_a_proxy_network_can_be_trusted():
    assert await _logged_address(_behind("172.30.0.0/16"), PROXY, VISITOR) == VISITOR


@pytest.mark.asyncio
async def test_a_proxy_can_be_named_by_host_name():
    app = _behind("localhost")  # how compose names the frontend: by service name
    assert await _logged_address(app, "127.0.0.1", VISITOR) == VISITOR
    assert await _logged_address(app, OTHER, VISITOR) == OTHER


@pytest.mark.asyncio
async def test_a_name_that_does_not_resolve_trusts_no_one():
    assert await _logged_address(_behind("no-such-proxy.invalid"), PROXY, VISITOR) == PROXY


@pytest.mark.asyncio
async def test_a_named_proxy_that_moves_is_trusted_at_its_new_address(monkeypatch):
    answers = iter([{"172.30.0.5"}, {"172.30.0.9"}])

    async def lookup(name):
        return next(answers)

    monkeypatch.setattr(trusted_proxies, "_lookup", lookup)
    monkeypatch.setattr(trusted_proxies, "REFRESH_SECONDS", 0)
    app = _behind("frontend")
    assert await _logged_address(app, "172.30.0.5", VISITOR) == VISITOR
    assert await _logged_address(app, "172.30.0.9", VISITOR) == VISITOR


def test_trusting_everyone_is_refused():
    with pytest.raises(ValueError):
        _behind("*")
    with pytest.raises(ValueError):
        _behind("frontend, *")


@pytest.mark.asyncio
async def test_the_server_as_entrypoint_starts_it_does_not_believe_the_header_on_its_own():
    # uvicorn reads X-Forwarded-For itself unless told not to, and trusts 127.0.0.1 by default:
    # entrypoint.sh must leave that to TrustedProxyHeaders, or a caller on the same machine (or a
    # sidecar) could choose the address the activity log records.
    entrypoint = (Path(__file__).resolve().parents[2] / "entrypoint.sh").read_text()
    start = [line for line in entrypoint.splitlines() if line.startswith("exec uvicorn ")]
    assert len(start) == 1
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    proxy_headers = "--no-proxy-headers" not in start[0]
    server = uvicorn.Server(uvicorn.Config("app.main:app", proxy_headers=proxy_headers, log_config=None))
    task = asyncio.create_task(server.serve(sockets=[sock]))
    try:
        for _ in range(500):
            if server.started:
                break
            await asyncio.sleep(0.01)
        assert server.started, "uvicorn did not start"
        async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{port}") as client:
            await client.get("/api/auth/me", headers={"x-forwarded-for": VISITOR})
    finally:
        server.should_exit = True
        await task
        sock.close()
        logging.getLogger("uvicorn.error").handlers.clear()
    events = [e for e in log_store.query(event_type="inbound", limit=100) if e["path"] == "/api/auth/me"]
    assert [e["ip"] for e in events] == ["127.0.0.1"]
