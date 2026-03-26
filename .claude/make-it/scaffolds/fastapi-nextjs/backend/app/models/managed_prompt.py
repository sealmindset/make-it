import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class ManagedPrompt(Base):
    """Registry of AI prompt templates managed through the admin UI."""

    __tablename__ = "managed_prompts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    slug: Mapped[str] = mapped_column(
        String(100), unique=True, index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str] = mapped_column(
        String(100), index=True, nullable=False, default="general"
    )
    provider: Mapped[str | None] = mapped_column(String(50), nullable=True)
    model: Mapped[str | None] = mapped_column(String(100), nullable=True)
    current_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, index=True, nullable=False
    )
    is_locked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    locked_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    locked_reason: Mapped[str | None] = mapped_column(String(500), nullable=True)
    source_file: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_by: Mapped[str] = mapped_column(String(255), nullable=False)
    updated_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relationships
    versions: Mapped[list["PromptVersion"]] = relationship(
        back_populates="prompt",
        cascade="all, delete-orphan",
        lazy="selectin",
        order_by="PromptVersion.version.desc()",
    )
    usages: Mapped[list["PromptUsage"]] = relationship(
        back_populates="prompt",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    tags: Mapped[list["PromptTag"]] = relationship(
        back_populates="prompt",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    test_cases: Mapped[list["PromptTestCase"]] = relationship(
        back_populates="prompt",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class PromptVersion(Base):
    """Immutable version history for prompt content changes."""

    __tablename__ = "prompt_versions"
    __table_args__ = (
        UniqueConstraint("prompt_id", "version", name="uq_prompt_version"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    prompt_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("managed_prompts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    system_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    parameters: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    model: Mapped[str | None] = mapped_column(String(100), nullable=True)
    change_summary: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_by: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    prompt: Mapped["ManagedPrompt"] = relationship(
        back_populates="versions", lazy="selectin"
    )


class PromptUsage(Base):
    """Tracks where a prompt is used in the application."""

    __tablename__ = "prompt_usages"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    prompt_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("managed_prompts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    usage_type: Mapped[str] = mapped_column(
        String(50), nullable=False, default="page"
    )
    location: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    call_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    avg_latency_ms: Mapped[float | None] = mapped_column(Float, nullable=True)
    avg_tokens_in: Mapped[int | None] = mapped_column(Integer, nullable=True)
    avg_tokens_out: Mapped[int | None] = mapped_column(Integer, nullable=True)
    error_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relationships
    prompt: Mapped["ManagedPrompt"] = relationship(
        back_populates="usages", lazy="selectin"
    )


class PromptTag(Base):
    """Flexible tagging for prompt categorization."""

    __tablename__ = "prompt_tags"
    __table_args__ = (
        UniqueConstraint("prompt_id", "tag", name="uq_prompt_tag"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    prompt_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("managed_prompts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    tag: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    prompt: Mapped["ManagedPrompt"] = relationship(
        back_populates="tags", lazy="selectin"
    )


class PromptTestCase(Base):
    """Saved test cases for regression testing prompts."""

    __tablename__ = "prompt_test_cases"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    prompt_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("managed_prompts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    input_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    expected_output: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relationships
    prompt: Mapped["ManagedPrompt"] = relationship(
        back_populates="test_cases", lazy="selectin"
    )


class PromptAuditLog(Base):
    """Append-only audit trail for all prompt management actions.

    Note: prompt_id is NOT a foreign key so audit entries survive prompt deletion.
    """

    __tablename__ = "prompt_audit_log"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    action: Mapped[str] = mapped_column(
        String(50), index=True, nullable=False
    )
    prompt_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True
    )
    prompt_slug: Mapped[str | None] = mapped_column(String(100), nullable=True)
    version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    user_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    user_email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    old_value: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    new_value: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )
