"""
Settings service with in-memory cache and cascading precedence:
  DB value > .env value > code default

Cache TTL: 60 seconds. The app works without any DB settings rows
(.env is always the fallback).
"""

import os
import time
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.app_setting import AppSetting

# In-memory cache: { key: (value, value_type, timestamp) }
_cache: dict[str, tuple[str | None, str, float]] = {}
_CACHE_TTL = 60  # seconds


def _coerce(value: str | None, value_type: str) -> Any:
    if value is None:
        return None
    if value_type == "bool":
        return value.lower() in ("true", "1", "yes")
    if value_type == "int":
        try:
            return int(value)
        except ValueError:
            return 0
    return value


def _mask(value: str | None) -> str:
    return "********" if value else ""


async def get_setting(db: AsyncSession, key: str, default: Any = None) -> Any:
    """Get a setting value with cascading precedence: DB > env > default."""
    now = time.time()

    # Check cache first
    if key in _cache:
        cached_value, value_type, ts = _cache[key]
        if now - ts < _CACHE_TTL:
            return _coerce(cached_value, value_type) if cached_value is not None else (
                os.getenv(key, default)
            )

    # Query DB
    result = await db.execute(select(AppSetting).where(AppSetting.key == key))
    setting = result.scalar_one_or_none()

    if setting and setting.value is not None:
        _cache[key] = (setting.value, setting.value_type, now)
        return _coerce(setting.value, setting.value_type)

    # Fallback to env var, then code default
    env_val = os.getenv(key)
    if env_val is not None:
        vtype = setting.value_type if setting else "string"
        _cache[key] = (env_val, vtype, now)
        return _coerce(env_val, vtype)

    return default


def invalidate_cache(key: str | None = None) -> None:
    """Invalidate one key or the entire cache."""
    if key:
        _cache.pop(key, None)
    else:
        _cache.clear()


def mask_sensitive(value: str | None, is_sensitive: bool) -> str | None:
    """Mask sensitive values in API responses."""
    if is_sensitive:
        return _mask(value)
    return value
