"""AI prompt management tables

Revision ID: 003
Revises: 002
Create Date: 2025-01-01 00:00:00.000000

This migration is the SCAFFOLD -- it creates the prompt management infrastructure.
Seed data for prompts is generated per-app in subsequent migrations.

Tables: managed_prompts, prompt_versions, prompt_usages, prompt_tags,
        prompt_test_cases, prompt_audit_log
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

# revision identifiers, used by Alembic.
revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # --- managed_prompts ---
    op.create_table(
        "managed_prompts",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("slug", sa.String(100), unique=True, nullable=False, index=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("category", sa.String(100), nullable=False, server_default="general", index=True),
        sa.Column("provider", sa.String(50), nullable=True),
        sa.Column("model", sa.String(100), nullable=True),
        sa.Column("current_version", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true"), index=True),
        sa.Column("is_locked", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("locked_by", sa.String(255), nullable=True),
        sa.Column("locked_reason", sa.String(500), nullable=True),
        sa.Column("source_file", sa.String(500), nullable=True),
        sa.Column("created_by", sa.String(255), nullable=False),
        sa.Column("updated_by", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # --- prompt_versions ---
    op.create_table(
        "prompt_versions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("prompt_id", UUID(as_uuid=True), sa.ForeignKey("managed_prompts.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("system_message", sa.Text(), nullable=True),
        sa.Column("parameters", JSONB(), nullable=True),
        sa.Column("model", sa.String(100), nullable=True),
        sa.Column("change_summary", sa.String(500), nullable=True),
        sa.Column("created_by", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("prompt_id", "version", name="uq_prompt_version"),
    )

    # --- prompt_usages ---
    op.create_table(
        "prompt_usages",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("prompt_id", UUID(as_uuid=True), sa.ForeignKey("managed_prompts.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("usage_type", sa.String(50), nullable=False, server_default="page"),
        sa.Column("location", sa.String(500), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("call_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("avg_latency_ms", sa.Float(), nullable=True),
        sa.Column("avg_tokens_in", sa.Integer(), nullable=True),
        sa.Column("avg_tokens_out", sa.Integer(), nullable=True),
        sa.Column("error_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # --- prompt_tags ---
    op.create_table(
        "prompt_tags",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("prompt_id", UUID(as_uuid=True), sa.ForeignKey("managed_prompts.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("tag", sa.String(100), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("prompt_id", "tag", name="uq_prompt_tag"),
    )

    # --- prompt_test_cases ---
    op.create_table(
        "prompt_test_cases",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("prompt_id", UUID(as_uuid=True), sa.ForeignKey("managed_prompts.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("input_data", JSONB(), nullable=True),
        sa.Column("expected_output", sa.Text(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # --- prompt_audit_log ---
    # Note: prompt_id is NOT a FK -- audit entries must survive prompt deletion
    op.create_table(
        "prompt_audit_log",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("action", sa.String(50), nullable=False, index=True),
        sa.Column("prompt_id", UUID(as_uuid=True), nullable=True, index=True),
        sa.Column("prompt_slug", sa.String(100), nullable=True),
        sa.Column("version", sa.Integer(), nullable=True),
        sa.Column("user_id", sa.String(255), nullable=True),
        sa.Column("user_email", sa.String(255), nullable=True),
        sa.Column("old_value", JSONB(), nullable=True),
        sa.Column("new_value", JSONB(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False, index=True),
    )


def downgrade() -> None:
    op.drop_table("prompt_audit_log")
    op.drop_table("prompt_test_cases")
    op.drop_table("prompt_tags")
    op.drop_table("prompt_usages")
    op.drop_table("prompt_versions")
    op.drop_table("managed_prompts")
