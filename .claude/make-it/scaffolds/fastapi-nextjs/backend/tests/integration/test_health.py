"""Integration tests for health check endpoints."""

import pytest


@pytest.mark.asyncio
async def test_health(admin_client):
    resp = await admin_client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_api_health(admin_client):
    resp = await admin_client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}
