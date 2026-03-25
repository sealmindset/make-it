"""
Admin Settings API -- RBAC-protected endpoints for managing app_settings.

Permissions required:
  - admin.settings.read: list settings, view audit logs
  - admin.settings.update: update settings, reveal sensitive values
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.permissions import require_permission
from app.models.app_setting import AppSetting, AppSettingAuditLog
from app.schemas.app_setting import (
    AppSettingAuditLogRead,
    AppSettingBulkUpdate,
    AppSettingRead,
    AppSettingReveal,
    AppSettingUpdate,
)
from app.schemas.auth import UserInfo
from app.services.settings_service import invalidate_cache, mask_sensitive

router = APIRouter(prefix="/api/admin/settings", tags=["settings"])


@router.get("", response_model=list[AppSettingRead])
async def list_settings(
    current_user: UserInfo = Depends(require_permission("admin.settings", "read")),
    db: AsyncSession = Depends(get_db),
):
    """List all settings, grouped by group_name. Sensitive values are masked."""
    result = await db.execute(
        select(AppSetting).order_by(AppSetting.group_name, AppSetting.key)
    )
    rows = result.scalars().all()
    return [
        AppSettingRead(
            **{
                **s.__dict__,
                "value": mask_sensitive(s.value, s.is_sensitive),
            }
        )
        for s in rows
    ]


@router.put("/{key}", response_model=AppSettingRead)
async def update_setting(
    key: str,
    body: AppSettingUpdate,
    current_user: UserInfo = Depends(require_permission("admin.settings", "update")),
    db: AsyncSession = Depends(get_db),
):
    """Update a single setting value."""
    result = await db.execute(select(AppSetting).where(AppSetting.key == key))
    setting = result.scalar_one_or_none()
    if not setting:
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")

    old_value = setting.value
    setting.value = body.value
    setting.updated_by = current_user.email

    # Audit log
    audit = AppSettingAuditLog(
        setting_id=setting.id,
        old_value="********" if setting.is_sensitive else old_value,
        new_value="********" if setting.is_sensitive else body.value,
        changed_by=current_user.email,
    )
    db.add(audit)
    await db.commit()
    await db.refresh(setting)

    invalidate_cache(key)

    return AppSettingRead(
        **{
            **setting.__dict__,
            "value": mask_sensitive(setting.value, setting.is_sensitive),
        }
    )


@router.put("", response_model=list[AppSettingRead])
async def bulk_update_settings(
    body: AppSettingBulkUpdate,
    current_user: UserInfo = Depends(require_permission("admin.settings", "update")),
    db: AsyncSession = Depends(get_db),
):
    """Bulk update multiple settings at once."""
    updated = []
    for item in body.settings:
        result = await db.execute(
            select(AppSetting).where(AppSetting.key == item.key)
        )
        setting = result.scalar_one_or_none()
        if not setting:
            continue

        old_value = setting.value
        setting.value = item.value
        setting.updated_by = current_user.email

        audit = AppSettingAuditLog(
            setting_id=setting.id,
            old_value="********" if setting.is_sensitive else old_value,
            new_value="********" if setting.is_sensitive else item.value,
            changed_by=current_user.email,
        )
        db.add(audit)
        updated.append(setting)

    await db.commit()
    invalidate_cache()

    return [
        AppSettingRead(
            **{
                **s.__dict__,
                "value": mask_sensitive(s.value, s.is_sensitive),
            }
        )
        for s in updated
    ]


@router.get("/{key}/reveal", response_model=AppSettingReveal)
async def reveal_setting(
    key: str,
    current_user: UserInfo = Depends(require_permission("admin.settings", "update")),
    db: AsyncSession = Depends(get_db),
):
    """Reveal the actual value of a sensitive setting. Requires update permission."""
    result = await db.execute(select(AppSetting).where(AppSetting.key == key))
    setting = result.scalar_one_or_none()
    if not setting:
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")
    return AppSettingReveal(key=setting.key, value=setting.value)


@router.get("/audit-log", response_model=list[AppSettingAuditLogRead])
async def list_audit_logs(
    current_user: UserInfo = Depends(require_permission("admin.settings", "read")),
    db: AsyncSession = Depends(get_db),
    limit: int = 100,
):
    """List recent setting change audit logs."""
    result = await db.execute(
        select(AppSettingAuditLog)
        .order_by(AppSettingAuditLog.created_at.desc())
        .limit(limit)
    )
    return result.scalars().all()
