from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class AppSettingRead(BaseModel):
    id: UUID
    key: str
    value: str | None
    group_name: str
    display_name: str
    description: str | None
    value_type: str
    is_sensitive: bool
    requires_restart: bool
    updated_by: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class AppSettingUpdate(BaseModel):
    value: str | None


class AppSettingBulkUpdate(BaseModel):
    settings: list["AppSettingUpdateItem"]


class AppSettingUpdateItem(BaseModel):
    key: str
    value: str | None


class AppSettingReveal(BaseModel):
    key: str
    value: str | None


class AppSettingAuditLogRead(BaseModel):
    id: UUID
    setting_id: UUID
    old_value: str | None
    new_value: str | None
    changed_by: str
    created_at: datetime

    model_config = {"from_attributes": True}
