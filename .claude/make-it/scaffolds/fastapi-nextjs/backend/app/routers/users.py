import uuid

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.middleware.permissions import require_permission
from app.models.user import User
from app.schemas.auth import UserInfo
from app.schemas.user import UserCreate, UserOut, UserUpdate

router = APIRouter(prefix="/api/users", tags=["users"])


def _user_to_out(user: User) -> UserOut:
    """Convert User model to UserOut schema with computed role_name."""
    return UserOut(
        id=user.id,
        oidc_subject=user.oidc_subject,
        email=user.email,
        display_name=user.display_name,
        is_active=user.is_active,
        role_id=user.role_id,
        role_name=user.role.name if user.role else None,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )


@router.get("/directory")
async def search_directory(
    q: str = Query(..., min_length=2),
    current_user: UserInfo = Depends(require_permission("users", "create")),
):
    """
    Search the OIDC directory for users to provision.

    In local dev, queries mock-oidc's admin API.
    In production, replace with your OIDC provider's directory/SCIM API.
    """
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{settings.OIDC_ISSUER_URL}/api/users")
        resp.raise_for_status()
        all_users = resp.json()

    query = q.lower()
    results = [
        {
            "oidc_subject": u["sub"],
            "email": u["email"],
            "display_name": u["name"],
        }
        for u in all_users
        if query in u.get("name", "").lower() or query in u.get("email", "").lower()
    ]
    return results


@router.get("/", response_model=list[UserOut])
async def list_users(
    current_user: UserInfo = Depends(require_permission("users", "view")),
    db: AsyncSession = Depends(get_db),
):
    """List all users."""
    result = await db.execute(select(User).order_by(User.display_name))
    users = result.scalars().all()
    return [_user_to_out(u) for u in users]


@router.post("/", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def create_user(
    data: UserCreate,
    current_user: UserInfo = Depends(require_permission("users", "create")),
    db: AsyncSession = Depends(get_db),
):
    """Create a new user (provision from OIDC directory)."""
    # Check for existing user by oidc_subject or email
    existing = await db.execute(
        select(User).where(
            (User.oidc_subject == data.oidc_subject) | (User.email == data.email)
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User with this OIDC subject or email already exists",
        )

    user = User(**data.model_dump())
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return _user_to_out(user)


@router.get("/{user_id}", response_model=UserOut)
async def get_user(
    user_id: uuid.UUID,
    current_user: UserInfo = Depends(require_permission("users", "view")),
    db: AsyncSession = Depends(get_db),
):
    """Get a single user by ID."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
        )
    return _user_to_out(user)


@router.put("/{user_id}", response_model=UserOut)
async def update_user(
    user_id: uuid.UUID,
    data: UserUpdate,
    current_user: UserInfo = Depends(require_permission("users", "edit")),
    db: AsyncSession = Depends(get_db),
):
    """Update a user's details."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
        )

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(user, field, value)

    await db.commit()
    await db.refresh(user)
    return _user_to_out(user)


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: uuid.UUID,
    current_user: UserInfo = Depends(require_permission("users", "delete")),
    db: AsyncSession = Depends(get_db),
):
    """Delete a user."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
        )

    await db.delete(user)
    await db.commit()
