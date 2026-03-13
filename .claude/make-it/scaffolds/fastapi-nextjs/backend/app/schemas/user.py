import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    oidc_subject: str
    email: str
    display_name: str
    is_active: bool
    role_id: uuid.UUID
    role_name: str | None = None
    created_at: datetime
    updated_at: datetime


class UserCreate(BaseModel):
    oidc_subject: str
    email: str
    display_name: str
    role_id: uuid.UUID


class UserUpdate(BaseModel):
    email: str | None = None
    display_name: str | None = None
    is_active: bool | None = None
    role_id: uuid.UUID | None = None
