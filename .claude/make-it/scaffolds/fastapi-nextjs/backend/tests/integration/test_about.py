"""Integration tests for the about (make-it stamp) endpoint."""

import hashlib
import json

import pytest

from app.routers import about


@pytest.mark.asyncio
async def test_about_without_stamp(admin_client, tmp_path, monkeypatch):
    monkeypatch.setattr(about, "STAMP_PATH", tmp_path / "make-it-stamp.json")
    resp = await admin_client.get("/api/admin/about")
    assert resp.status_code == 200
    assert resp.json() == {"stamp": "missing"}


@pytest.mark.asyncio
async def test_about_requires_permission(user_client):
    resp = await user_client.get("/api/admin/about")
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_about_checks_security_files(admin_client, tmp_path, monkeypatch):
    (tmp_path / "same.py").write_bytes(b"same")
    (tmp_path / "edited.py").write_bytes(b"edited")
    (tmp_path.parent / "outside.py").write_bytes(b"outside")
    stamp = {
        "make_it_version": "1.60.0",
        "sealed_by": "x" * 500,
        "runs": "3",
        "ledger_head": "ab12cd34ef56",
        "security_files": {
            "same.py": hashlib.sha256(b"same").hexdigest(),
            "edited.py": hashlib.sha256(b"original").hexdigest(),
            "gone.py": hashlib.sha256(b"gone").hexdigest(),
            "../outside.py": hashlib.sha256(b"outside").hexdigest(),
            "not-a-hash.py": 5,
        },
    }
    (tmp_path / "make-it-stamp.json").write_text(json.dumps(stamp))
    monkeypatch.setattr(about, "BACKEND_ROOT", tmp_path.resolve())
    monkeypatch.setattr(about, "STAMP_PATH", tmp_path / "make-it-stamp.json")

    resp = await admin_client.get("/api/admin/about")
    assert resp.status_code == 200
    assert resp.json() == {
        "stamp": "present",
        "make_it_version": "1.60.0",
        "scaffold": None,
        "sealed_by": "x" * 60,
        "sealed_on": None,
        "runs": None,
        "security_files": {
            "total": 4,
            "as_released": 1,
            "changed": ["edited.py"],
            "missing": ["gone.py", "../outside.py"],
        },
    }
