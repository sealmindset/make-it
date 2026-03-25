from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.permissions import require_permission
from app.models.permission import Permission
from app.schemas.auth import UserInfo
from app.schemas.role import PermissionOut

router = APIRouter(prefix="/api/permissions", tags=["permissions"])


@router.get("/", response_model=list[PermissionOut])
async def list_permissions(
    current_user: UserInfo = Depends(require_permission("admin.roles", "read")),
    db: AsyncSession = Depends(get_db),
):
    """List all available permissions (used by role permission matrix UI)."""
    result = await db.execute(
        select(Permission).order_by(Permission.resource, Permission.action)
    )
    permissions = result.scalars().all()
    return [
        PermissionOut(
            id=p.id,
            resource=p.resource,
            action=p.action,
            description=p.description,
        )
        for p in permissions
    ]
