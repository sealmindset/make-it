"""
Admin Settings API -- RBAC-protected endpoints for managing app_settings.

Permissions required:
  - app_settings.view: list settings, view audit logs
  - app_settings.edit: update settings, reveal sensitive values
"""

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.app_setting import AppSetting, AppSettingAuditLog
from app.schemas.app_setting import (
    AppSettingAuditLogRead,
    AppSettingBulkUpdate,
    AppSettingRead,
    AppSettingReveal,
    AppSettingUpdate,
)
from app.services.settings_service import invalidate_cache, mask_sensitive

# [SETTINGS_ROUTER_DEPS] -- replaced during build with require_permission imports

router = APIRouter(prefix="/api/admin/settings", tags=["settings"])


@router.get("", response_model=list[AppSettingRead])
async def list_settings(
    # user: Annotated[CurrentUser, Depends(require_permission("app_settings", "view"))],
    db: AsyncSession = Depends(get_db),
):
    """List all settings, grouped by group_name. Sensitive values are masked."""
    result = await db.execute(
        select(AppSetting).order_by(AppSetting.group_name, AppSetting.key)
    )
    settings = result.scalars().all()
    return [
        AppSettingRead(
            **{
                **s.__dict__,
                "value": mask_sensitive(s.value, s.is_sensitive),
            }
        )
        for s in settings
    ]


@router.put("/{key}", response_model=AppSettingRead)
async def update_setting(
    key: str,
    body: AppSettingUpdate,
    # user: Annotated[CurrentUser, Depends(require_permission("app_settings", "edit"))],
    db: AsyncSession = Depends(get_db),
):
    """Update a single setting value."""
    result = await db.execute(select(AppSetting).where(AppSetting.key == key))
    setting = result.scalar_one_or_none()
    if not setting:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")

    old_value = setting.value
    setting.value = body.value
    # setting.updated_by = user.email  # [UNCOMMENT_AFTER_AUTH_WIRING]

    # Audit log
    audit = AppSettingAuditLog(
        setting_id=setting.id,
        old_value="********" if setting.is_sensitive else old_value,
        new_value="********" if setting.is_sensitive else body.value,
        changed_by="system",  # [REPLACE_WITH_USER_EMAIL]
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
    # user: Annotated[CurrentUser, Depends(require_permission("app_settings", "edit"))],
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
        # setting.updated_by = user.email  # [UNCOMMENT_AFTER_AUTH_WIRING]

        audit = AppSettingAuditLog(
            setting_id=setting.id,
            old_value="********" if setting.is_sensitive else old_value,
            new_value="********" if setting.is_sensitive else item.value,
            changed_by="system",  # [REPLACE_WITH_USER_EMAIL]
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
    # user: Annotated[CurrentUser, Depends(require_permission("app_settings", "edit"))],
    db: AsyncSession = Depends(get_db),
):
    """Reveal the actual value of a sensitive setting. Requires edit permission."""
    result = await db.execute(select(AppSetting).where(AppSetting.key == key))
    setting = result.scalar_one_or_none()
    if not setting:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")
    return AppSettingReveal(key=setting.key, value=setting.value)


@router.get("/audit-log", response_model=list[AppSettingAuditLogRead])
async def list_audit_logs(
    # user: Annotated[CurrentUser, Depends(require_permission("app_settings", "view"))],
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
