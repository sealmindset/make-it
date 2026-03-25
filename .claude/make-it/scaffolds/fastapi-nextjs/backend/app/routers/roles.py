import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.middleware.permissions import require_permission
from app.models.permission import Permission, RolePermission
from app.models.role import Role
from app.schemas.auth import UserInfo
from app.schemas.role import (
    PermissionAssignment,
    PermissionOut,
    RoleCreate,
    RoleOut,
    RoleUpdate,
    RoleWithPermissions,
)

router = APIRouter(prefix="/api/roles", tags=["roles"])


def _role_to_out(role: Role, include_permissions: bool = False):
    """Convert Role model to response schema."""
    if include_permissions:
        permissions = [
            PermissionOut(
                id=rp.permission.id,
                resource=rp.permission.resource,
                action=rp.permission.action,
                description=rp.permission.description,
            )
            for rp in role.permissions
            if rp.permission
        ]
        return RoleWithPermissions(
            id=role.id,
            name=role.name,
            description=role.description,
            is_system=role.is_system,
            created_at=role.created_at,
            updated_at=role.updated_at,
            permissions=permissions,
        )
    return RoleOut(
        id=role.id,
        name=role.name,
        description=role.description,
        is_system=role.is_system,
        created_at=role.created_at,
        updated_at=role.updated_at,
    )


@router.get("/")
async def list_roles(
    include_permissions: bool = Query(False),
    current_user: UserInfo = Depends(require_permission("admin.roles", "read")),
    db: AsyncSession = Depends(get_db),
):
    """List all roles, optionally including their permissions."""
    stmt = select(Role).order_by(Role.name)
    if include_permissions:
        stmt = stmt.options(
            selectinload(Role.permissions).selectinload(RolePermission.permission)
        )
    result = await db.execute(stmt)
    roles = result.scalars().all()
    return [_role_to_out(r, include_permissions) for r in roles]


@router.post("/", response_model=RoleOut, status_code=status.HTTP_201_CREATED)
async def create_role(
    data: RoleCreate,
    current_user: UserInfo = Depends(require_permission("admin.roles", "create")),
    db: AsyncSession = Depends(get_db),
):
    """Create a custom role."""
    existing = await db.execute(select(Role).where(Role.name == data.name))
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Role with this name already exists",
        )

    role = Role(name=data.name, description=data.description, is_system=False)
    db.add(role)
    await db.commit()
    await db.refresh(role)
    return _role_to_out(role)


@router.put("/{role_id}", response_model=RoleOut)
async def update_role(
    role_id: uuid.UUID,
    data: RoleUpdate,
    current_user: UserInfo = Depends(require_permission("admin.roles", "update")),
    db: AsyncSession = Depends(get_db),
):
    """Update a role's name or description."""
    result = await db.execute(select(Role).where(Role.id == role_id))
    role = result.scalar_one_or_none()
    if not role:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Role not found"
        )

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(role, field, value)

    await db.commit()
    await db.refresh(role)
    return _role_to_out(role)


@router.delete("/{role_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_role(
    role_id: uuid.UUID,
    current_user: UserInfo = Depends(require_permission("admin.roles", "delete")),
    db: AsyncSession = Depends(get_db),
):
    """Delete a custom role. System roles cannot be deleted."""
    result = await db.execute(select(Role).where(Role.id == role_id))
    role = result.scalar_one_or_none()
    if not role:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Role not found"
        )
    if role.is_system:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="System roles cannot be deleted",
        )

    await db.delete(role)
    await db.commit()


@router.put("/{role_id}/permissions", response_model=RoleWithPermissions)
async def update_role_permissions(
    role_id: uuid.UUID,
    data: PermissionAssignment,
    current_user: UserInfo = Depends(require_permission("admin.roles", "update")),
    db: AsyncSession = Depends(get_db),
):
    """Replace all permissions for a role (permission matrix save)."""
    stmt = (
        select(Role)
        .where(Role.id == role_id)
        .options(
            selectinload(Role.permissions).selectinload(RolePermission.permission)
        )
    )
    result = await db.execute(stmt)
    role = result.scalar_one_or_none()
    if not role:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Role not found"
        )

    # Remove existing permissions
    for rp in list(role.permissions):
        await db.delete(rp)

    # Add new permissions
    for perm_id in data.permission_ids:
        perm = await db.execute(
            select(Permission).where(Permission.id == perm_id)
        )
        if not perm.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Permission {perm_id} not found",
            )
        db.add(RolePermission(role_id=role_id, permission_id=perm_id))

    await db.commit()

    # Reload with permissions
    result = await db.execute(stmt)
    role = result.scalar_one_or_none()
    return _role_to_out(role, include_permissions=True)
