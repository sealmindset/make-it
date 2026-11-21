"""The activity log names the signed-in user (build-standards L09).

Every request here goes through the real sign-in path: a JWT signed with the app's secret, sent in
the `token` cookie, decoded by get_current_user. No dependency override stands in for it, so these
tests fail if the user resolved there never reaches RequestLoggingMiddleware.
"""

import secrets
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from httpx import ASGITransport, AsyncClient

from app.config import settings
from app.main import _fastapi_app
from app.main import app as served_app  # the wrapped app, as uvicorn serves it
from app.middleware.auth import get_current_user
from app.services.log_service import log_store
from tests.conftest import ADMIN_USER, REGULAR_USER


@pytest.fixture()
def jwt_secret(monkeypatch):
    secret = secrets.token_hex(32)
    monkeypatch.setattr(settings, "JWT_SECRET", secret)
    return secret


@pytest.fixture(autouse=True)
def _real_auth_and_empty_log():
    # The other fixtures replace get_current_user; these tests need the real one.
    _fastapi_app.dependency_overrides.clear()
    log_store.clear()
    yield
    log_store.clear()


def _token(user, secret):
    now = datetime.now(timezone.utc)
    claims = {**user.model_dump(), "iat": now, "exp": now + timedelta(hours=1)}
    return jwt.encode(claims, secret, algorithm="HS256")


def _client(token=None):
    cookies = {"token": token} if token else None
    return AsyncClient(transport=ASGITransport(app=served_app), base_url="http://test", cookies=cookies)


def _event(path):
    found = [e for e in log_store.query(event_type="inbound", limit=1000) if e["path"] == path]
    assert len(found) == 1, f"expected one inbound log event for {path}, got {len(found)}"
    return found[0]


@pytest.mark.asyncio
async def test_real_auth_path_is_in_use():
    assert get_current_user not in _fastapi_app.dependency_overrides


@pytest.mark.asyncio
async def test_signed_in_request_logs_the_user(jwt_secret):
    async with _client(_token(ADMIN_USER, jwt_secret)) as client:
        resp = await client.get("/api/auth/me")
    assert resp.status_code == 200
    event = _event("/api/auth/me")
    assert event["user_sub"] == ADMIN_USER.sub
    assert event["user_email"] == ADMIN_USER.email


@pytest.mark.asyncio
async def test_permission_checked_request_logs_the_user(jwt_secret):
    async with _client(_token(ADMIN_USER, jwt_secret)) as client:
        resp = await client.get("/api/admin/logs/stats")
    assert resp.status_code == 200
    event = _event("/api/admin/logs/stats")
    assert event["user_sub"] == ADMIN_USER.sub
    assert event["user_email"] == ADMIN_USER.email


@pytest.mark.asyncio
async def test_refused_request_logs_who_was_refused(jwt_secret):
    async with _client(_token(REGULAR_USER, jwt_secret)) as client:
        resp = await client.get("/api/admin/logs/stats")
    assert resp.status_code == 403
    event = _event("/api/admin/logs/stats")
    assert event["user_sub"] == REGULAR_USER.sub
    assert event["user_email"] == REGULAR_USER.email


@pytest.mark.asyncio
async def test_request_without_a_token_logs_no_user(jwt_secret):
    # A signed-in request first, so a user left over from it would show up on the next one.
    async with _client(_token(ADMIN_USER, jwt_secret)) as client:
        assert (await client.get("/api/auth/me")).status_code == 200
    async with _client() as client:
        resp = await client.post("/api/auth/logout")
    assert resp.status_code == 401
    event = _event("/api/auth/logout")
    assert event["user_sub"] is None
    assert event["user_email"] is None


@pytest.mark.asyncio
async def test_token_with_a_wrong_signature_logs_no_user(jwt_secret):
    forged = _token(ADMIN_USER, secrets.token_hex(32))
    async with _client(forged) as client:
        resp = await client.get("/api/auth/me")
    assert resp.status_code == 401
    event = _event("/api/auth/me")
    assert event["user_sub"] is None
    assert event["user_email"] is None


@pytest.mark.asyncio
async def test_expired_token_logs_no_user(jwt_secret):
    past = datetime.now(timezone.utc) - timedelta(hours=2)
    expired = jwt.encode(
        {**ADMIN_USER.model_dump(), "iat": past, "exp": past + timedelta(hours=1)},
        jwt_secret,
        algorithm="HS256",
    )
    async with _client(expired) as client:
        resp = await client.get("/api/auth/me")
    assert resp.status_code == 401
    event = _event("/api/auth/me")
    assert event["user_sub"] is None
    assert event["user_email"] is None


@pytest.mark.asyncio
async def test_the_log_never_holds_the_token(jwt_secret):
    token = _token(ADMIN_USER, jwt_secret)
    async with _client(token) as client:
        assert (await client.get("/api/auth/me")).status_code == 200
    event = _event("/api/auth/me")
    assert token not in repr(event)
    assert jwt_secret not in repr(event)
