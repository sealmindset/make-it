"""
About API -- read-only view of this build's make-it stamp.

Reports which make-it version built the app and whether the sign-in and
permission files still match the hashes recorded in make-it-stamp.json.
The hashes are recomputed on every request; nothing from the stamp is trusted
beyond the short fields returned here.

Permissions required:
  - admin.settings.read: view the stamp summary
"""

import hashlib
import json
import os
import stat
from pathlib import Path

from fastapi import APIRouter, Depends

from app.middleware.permissions import require_permission
from app.schemas.auth import UserInfo

router = APIRouter(prefix="/api/admin/about", tags=["about"])

# Parent of the app package: backend/ in the repo, /app in the container
BACKEND_ROOT = Path(__file__).resolve().parents[2]
STAMP_PATH = BACKEND_ROOT / "make-it-stamp.json"

MAX_FILE_BYTES = 1024 * 1024
MAX_SECURITY_FILES = 100
MAX_PATH_CHARS = 200
MAX_TEXT_CHARS = 60


def _read_regular_file(path: Path) -> bytes | None:
    """Read a regular file of at most MAX_FILE_BYTES. Symlinks and anything else give None."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except (OSError, ValueError, RecursionError):
        return None
    with os.fdopen(fd, "rb") as fh:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        data = fh.read(MAX_FILE_BYTES + 1)
    return data if len(data) <= MAX_FILE_BYTES else None


def _read_security_file(rel_path: str) -> bytes | None:
    """Read a file named by the stamp, only if it really lives under the backend root."""
    rel = Path(rel_path)
    if rel.is_absolute() or ".." in rel.parts:
        return None
    path = BACKEND_ROOT / rel
    try:
        # A symlink anywhere along the path makes the resolved path differ
        if path.resolve() != path:
            return None
    except (OSError, ValueError, RuntimeError):
        return None
    return _read_regular_file(path)


def _short_text(value: object) -> str | None:
    return value[:MAX_TEXT_CHARS] if isinstance(value, str) else None


@router.get("")
async def get_about(
    current_user: UserInfo = Depends(require_permission("admin.settings", "read")),
):
    """Summarise the make-it stamp and re-check the security files against it."""
    raw = _read_regular_file(STAMP_PATH)
    if raw is None:
        return {"stamp": "missing"}
    try:
        stamp = json.loads(raw)
    except (ValueError, RecursionError):
        return {"stamp": "missing"}
    if not isinstance(stamp, dict):
        return {"stamp": "missing"}

    security_files = stamp.get("security_files")
    if not isinstance(security_files, dict):
        security_files = {}
    expected = [
        (path, digest)
        for path, digest in security_files.items()
        if isinstance(path, str) and isinstance(digest, str) and len(path) <= MAX_PATH_CHARS
    ][:MAX_SECURITY_FILES]

    changed: list[str] = []
    missing: list[str] = []
    for path, digest in expected:
        data = _read_security_file(path)
        if data is None:
            missing.append(path)
        elif hashlib.sha256(data).hexdigest() != digest.lower():
            changed.append(path)

    runs = stamp.get("runs")
    return {
        "stamp": "present",
        "make_it_version": _short_text(stamp.get("make_it_version")),
        "scaffold": _short_text(stamp.get("scaffold")),
        "sealed_by": _short_text(stamp.get("sealed_by")),
        "sealed_on": _short_text(stamp.get("sealed_on")),
        "runs": runs if isinstance(runs, int) and not isinstance(runs, bool) else None,
        "security_files": {
            "total": len(expected),
            "as_released": len(expected) - len(changed) - len(missing),
            "changed": changed,
            "missing": missing,
        },
    }
