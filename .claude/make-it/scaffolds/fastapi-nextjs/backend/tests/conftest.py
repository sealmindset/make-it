"""Shared test fixtures for [APP_NAME] backend tests.

Uses an in-memory SQLite database so tests run fast without Docker/PostgreSQL.
Auth is bypassed by overriding the get_current_user dependency.
"""

import uuid
from datetime import datetime, timezone

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import String, event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.base import Base
from app.schemas.auth import UserInfo

# ---------------------------------------------------------------------------
# SQLite UUID compatibility
# ---------------------------------------------------------------------------
# PostgreSQL UUID columns don't work with SQLite. Override the dialect-level
# compilation so UUID is stored as CHAR(36) in SQLite.

from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.dialects import sqlite as sqlite_dialect


@pytest.fixture(autouse=True)
def _patch_uuid_for_sqlite():
    """Make PostgreSQL UUID columns work with SQLite by rendering as CHAR(36)."""
    from sqlalchemy.ext.compiler import compiles

    @compiles(PG_UUID, "sqlite")
    def _compile_uuid_sqlite(type_, compiler, **kw):
        return "CHAR(36)"

    yield


# ---------------------------------------------------------------------------
# Test users
# ---------------------------------------------------------------------------
# These match the 4 system roles and the mock-oidc seed users.
# Permissions should be updated to match the app's seed data.

ADMIN_USER = UserInfo(
    sub="mock-admin",
    user_id="00000000-0000-0000-0000-000000000001",
    email="admin@[APP_SLUG].local",
    name="Admin User",
    role_id="00000000-0000-0000-0000-000000000010",
    role_name="Super Admin",
    permissions=[
        "users.create", "users.read", "users.update", "users.delete",
        "roles.create", "roles.read", "roles.update", "roles.delete",
        "admin.logs.read", "admin.logs.delete",
        "admin.settings.read", "admin.settings.update",
        "admin.prompts.create", "admin.prompts.read", "admin.prompts.update", "admin.prompts.delete",
        # [ADMIN_PERMISSIONS] -- add app-specific permissions here
    ],
)

REGULAR_USER = UserInfo(
    sub="mock-user",
    user_id="00000000-0000-0000-0000-000000000003",
    email="user@[APP_SLUG].local",
    name="Regular User",
    role_id="00000000-0000-0000-0000-000000000040",
    role_name="User",
    permissions=[
        # [USER_PERMISSIONS] -- add app-specific permissions here
    ],
)

VIEWER_USER = UserInfo(
    sub="mock-viewer",
    user_id="00000000-0000-0000-0000-000000000004",
    email="viewer@[APP_SLUG].local",
    name="Viewer User",
    role_id="00000000-0000-0000-0000-000000000050",
    role_name="Viewer",
    permissions=[
        # [VIEWER_PERMISSIONS] -- add app-specific read permissions here
    ],
)

# ---------------------------------------------------------------------------
# Database fixtures
# ---------------------------------------------------------------------------

TEST_DB_URL = "sqlite+aiosqlite:///:memory:"


@pytest.fixture()
async def db_engine():
    engine = create_async_engine(TEST_DB_URL, echo=False)

    # SQLite needs PRAGMA foreign_keys = ON per connection
    @event.listens_for(engine.sync_engine, "connect")
    def _set_sqlite_pragma(dbapi_conn, _record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    yield engine

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest.fixture()
async def db_session(db_engine):
    session_factory = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as session:
        yield session


# ---------------------------------------------------------------------------
# Seed helpers
# ---------------------------------------------------------------------------

async def seed_user(db: AsyncSession, user_info: UserInfo) -> None:
    """Insert a Role + User matching a UserInfo fixture into the test DB."""
    from app.models.role import Role
    from app.models.user import User

    role_id = uuid.UUID(user_info.role_id)
    user_id = uuid.UUID(user_info.user_id)

    from sqlalchemy import select
    existing_role = (await db.execute(select(Role).where(Role.id == role_id))).scalar_one_or_none()
    if not existing_role:
        db.add(Role(id=role_id, name=user_info.role_name, description=f"{user_info.role_name} role", is_system=True))

    existing_user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not existing_user:
        db.add(User(
            id=user_id,
            oidc_subject=user_info.sub,
            email=user_info.email,
            display_name=user_info.name,
            is_active=True,
            role_id=role_id,
        ))

    await db.commit()


# ---------------------------------------------------------------------------
# HTTP client fixtures
# ---------------------------------------------------------------------------

def _make_client(db_session: AsyncSession, user: UserInfo):
    """Build an httpx AsyncClient with auth and DB overrides."""
    from app.main import _fastapi_app as app

    async def _override_db():
        yield db_session

    async def _override_user():
        return user

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = _override_user

    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


@pytest.fixture()
async def admin_client(db_session):
    """HTTP client authenticated as admin."""
    await seed_user(db_session, ADMIN_USER)
    async with _make_client(db_session, ADMIN_USER) as client:
        yield client
    from app.main import _fastapi_app as app
    app.dependency_overrides.clear()


@pytest.fixture()
async def user_client(db_session):
    """HTTP client authenticated as regular user."""
    await seed_user(db_session, ADMIN_USER)
    await seed_user(db_session, REGULAR_USER)
    async with _make_client(db_session, REGULAR_USER) as client:
        yield client
    from app.main import _fastapi_app as app
    app.dependency_overrides.clear()


@pytest.fixture()
async def viewer_client(db_session):
    """HTTP client authenticated as viewer (read-only)."""
    await seed_user(db_session, ADMIN_USER)
    await seed_user(db_session, VIEWER_USER)
    async with _make_client(db_session, VIEWER_USER) as client:
        yield client
    from app.main import _fastapi_app as app
    app.dependency_overrides.clear()
