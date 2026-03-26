import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


# ---------------------------------------------------------------------------
# Managed Prompt
# ---------------------------------------------------------------------------


class ManagedPromptCreate(BaseModel):
    slug: str
    name: str
    description: str | None = None
    category: str = "general"
    provider: str | None = None
    model: str | None = None
    content: str
    system_message: str | None = None
    parameters: dict | None = None
    source_file: str | None = None
    tags: list[str] | None = None
    change_summary: str | None = None


class ManagedPromptUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    category: str | None = None
    provider: str | None = None
    model: str | None = None
    content: str | None = None
    system_message: str | None = None
    parameters: dict | None = None
    source_file: str | None = None
    change_summary: str | None = None


class ManagedPromptOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    slug: str
    name: str
    description: str | None = None
    category: str
    provider: str | None = None
    model: str | None = None
    current_version: int
    is_active: bool
    is_locked: bool
    locked_by: str | None = None
    locked_reason: str | None = None
    source_file: str | None = None
    created_by: str
    updated_by: str | None = None
    created_at: datetime
    updated_at: datetime
    tags: list[str] = []
    primary_usage_location: str | None = None
    version_count: int = 0
    usage_count: int = 0


class ManagedPromptListOut(BaseModel):
    """Lighter version for the card grid registry."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    slug: str
    name: str
    description: str | None = None
    category: str
    provider: str | None = None
    model: str | None = None
    current_version: int
    is_active: bool
    is_locked: bool
    updated_at: datetime
    tags: list[str] = []
    primary_usage_location: str | None = None


# ---------------------------------------------------------------------------
# Prompt Version
# ---------------------------------------------------------------------------


class PromptVersionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    prompt_id: uuid.UUID
    version: int
    content: str
    system_message: str | None = None
    parameters: dict | None = None
    model: str | None = None
    change_summary: str | None = None
    created_by: str
    created_at: datetime


class PromptVersionDiffOut(BaseModel):
    version_a: int
    version_b: int
    content_diff: str | None = None
    system_message_diff: str | None = None
    parameters_a: dict | None = None
    parameters_b: dict | None = None


# ---------------------------------------------------------------------------
# Prompt Usage
# ---------------------------------------------------------------------------


class PromptUsageCreate(BaseModel):
    usage_type: str = "page"
    location: str
    description: str | None = None
    is_primary: bool = False


class PromptUsageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    prompt_id: uuid.UUID
    usage_type: str
    location: str
    description: str | None = None
    is_primary: bool
    call_count: int
    avg_latency_ms: float | None = None
    avg_tokens_in: int | None = None
    avg_tokens_out: int | None = None
    error_count: int
    created_at: datetime
    updated_at: datetime


# ---------------------------------------------------------------------------
# Prompt Tag
# ---------------------------------------------------------------------------


class PromptTagOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    tag: str
    count: int = 0


class PromptTagAdd(BaseModel):
    tag: str


# ---------------------------------------------------------------------------
# Prompt Test Case
# ---------------------------------------------------------------------------


class PromptTestCaseCreate(BaseModel):
    name: str
    input_data: dict | None = None
    expected_output: str | None = None
    notes: str | None = None


class PromptTestCaseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    prompt_id: uuid.UUID
    name: str
    input_data: dict | None = None
    expected_output: str | None = None
    notes: str | None = None
    created_by: str | None = None
    created_at: datetime
    updated_at: datetime


class PromptTestRunOut(BaseModel):
    """Result of running a test against a prompt."""

    output: str
    tokens_in: int | None = None
    tokens_out: int | None = None
    latency_ms: int | None = None
    success: bool = True
    error: str | None = None


# ---------------------------------------------------------------------------
# Prompt Audit Log
# ---------------------------------------------------------------------------


class PromptAuditLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    action: str
    prompt_id: uuid.UUID | None = None
    prompt_slug: str | None = None
    version: int | None = None
    user_id: str | None = None
    user_email: str | None = None
    old_value: dict | None = None
    new_value: dict | None = None
    created_at: datetime


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------


class PromptStatsOut(BaseModel):
    total: int = 0
    active: int = 0
    versions_count: int = 0
    categories_count: int = 0
