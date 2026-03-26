"""Business logic for AI prompt management.

Handles version diffing, audit logging, and test execution.
Simple CRUD stays in the router; this service handles complex operations.
"""

import difflib
import json
import re
import time
import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.managed_prompt import (
    ManagedPrompt,
    PromptAuditLog,
    PromptTag,
    PromptTestCase,
    PromptUsage,
    PromptVersion,
)
from app.schemas.prompt import PromptTestRunOut, PromptVersionDiffOut


# ---------------------------------------------------------------------------
# Audit logging
# ---------------------------------------------------------------------------


async def log_audit(
    db: AsyncSession,
    *,
    action: str,
    prompt: ManagedPrompt | None = None,
    prompt_id: uuid.UUID | None = None,
    prompt_slug: str | None = None,
    version: int | None = None,
    user_email: str | None = None,
    old_value: dict | None = None,
    new_value: dict | None = None,
) -> PromptAuditLog:
    """Append an entry to the immutable prompt audit log."""
    entry = PromptAuditLog(
        action=action,
        prompt_id=prompt.id if prompt else prompt_id,
        prompt_slug=prompt.slug if prompt else prompt_slug,
        version=version,
        user_id=user_email,
        user_email=user_email,
        old_value=old_value,
        new_value=new_value,
    )
    db.add(entry)
    return entry


# ---------------------------------------------------------------------------
# Version management
# ---------------------------------------------------------------------------


async def create_version(
    db: AsyncSession,
    *,
    prompt: ManagedPrompt,
    content: str,
    system_message: str | None = None,
    parameters: dict | None = None,
    model: str | None = None,
    change_summary: str | None = None,
    user_email: str,
) -> PromptVersion:
    """Create a new immutable version for a prompt."""
    new_version_num = prompt.current_version + 1

    version = PromptVersion(
        prompt_id=prompt.id,
        version=new_version_num,
        content=content,
        system_message=system_message,
        parameters=parameters,
        model=model,
        change_summary=change_summary,
        created_by=user_email,
    )
    db.add(version)

    prompt.current_version = new_version_num
    prompt.updated_by = user_email

    await log_audit(
        db,
        action="version_created",
        prompt=prompt,
        version=new_version_num,
        user_email=user_email,
        new_value={
            "content": content[:200],
            "system_message": (system_message or "")[:200],
            "change_summary": change_summary,
        },
    )

    return version


async def diff_versions(
    db: AsyncSession,
    prompt_id: uuid.UUID,
    version_a: int,
    version_b: int,
) -> PromptVersionDiffOut:
    """Generate a unified diff between two prompt versions."""
    stmt_a = select(PromptVersion).where(
        PromptVersion.prompt_id == prompt_id,
        PromptVersion.version == version_a,
    )
    stmt_b = select(PromptVersion).where(
        PromptVersion.prompt_id == prompt_id,
        PromptVersion.version == version_b,
    )

    va = (await db.execute(stmt_a)).scalar_one_or_none()
    vb = (await db.execute(stmt_b)).scalar_one_or_none()

    if not va or not vb:
        return PromptVersionDiffOut(
            version_a=version_a,
            version_b=version_b,
        )

    content_diff = _text_diff(
        va.content or "", vb.content or "",
        f"v{version_a}", f"v{version_b}",
    )
    system_diff = _text_diff(
        va.system_message or "", vb.system_message or "",
        f"v{version_a}", f"v{version_b}",
    )

    return PromptVersionDiffOut(
        version_a=version_a,
        version_b=version_b,
        content_diff=content_diff if content_diff else None,
        system_message_diff=system_diff if system_diff else None,
        parameters_a=va.parameters,
        parameters_b=vb.parameters,
    )


async def restore_version(
    db: AsyncSession,
    *,
    prompt: ManagedPrompt,
    target_version: int,
    user_email: str,
    change_summary: str | None = None,
) -> PromptVersion:
    """Restore a prompt to a previous version by creating a NEW version with old content."""
    stmt = select(PromptVersion).where(
        PromptVersion.prompt_id == prompt.id,
        PromptVersion.version == target_version,
    )
    old_version = (await db.execute(stmt)).scalar_one_or_none()
    if not old_version:
        raise ValueError(f"Version {target_version} not found")

    summary = change_summary or f"Restored from version {target_version}"

    return await create_version(
        db,
        prompt=prompt,
        content=old_version.content,
        system_message=old_version.system_message,
        parameters=old_version.parameters,
        model=old_version.model,
        change_summary=summary,
        user_email=user_email,
    )


# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------


async def run_test(
    db: AsyncSession,
    *,
    prompt: ManagedPrompt,
    input_data: dict | None = None,
) -> PromptTestRunOut:
    """Run a test against a prompt template.

    This is a scaffold placeholder. During the build phase, /make-it wires
    this to the actual AI provider configured for the app.

    [AI_PROVIDER_PLACEHOLDER] -- Replace the mock below with:
        from app.services.ai_provider import get_provider
        provider = get_provider()
        result = await provider.complete(rendered_content, system_message, parameters)
    """
    # Get the latest version content
    stmt = (
        select(PromptVersion)
        .where(PromptVersion.prompt_id == prompt.id)
        .order_by(PromptVersion.version.desc())
        .limit(1)
    )
    latest = (await db.execute(stmt)).scalar_one_or_none()
    if not latest:
        return PromptTestRunOut(
            output="No version found for this prompt.",
            success=False,
            error="No published version available",
        )

    # Interpolate variables into the template
    rendered = _render_template(latest.content, input_data or {})

    # [AI_PROVIDER_PLACEHOLDER] -- Mock response for scaffold testing
    start = time.monotonic()
    mock_output = (
        f"[Test Result] This is a simulated response for the prompt "
        f"'{prompt.name}'. In production, this will call your configured "
        f"AI provider ({prompt.provider or 'default'}) with model "
        f"({prompt.model or 'default'}).\n\n"
        f"Rendered prompt preview:\n{rendered[:500]}"
    )
    elapsed_ms = int((time.monotonic() - start) * 1000)

    await log_audit(
        db,
        action="tested",
        prompt=prompt,
        version=latest.version,
        user_email=None,
        new_value={"input_data": input_data, "rendered_length": len(rendered)},
    )

    return PromptTestRunOut(
        output=mock_output,
        tokens_in=len(rendered.split()),
        tokens_out=len(mock_output.split()),
        latency_ms=elapsed_ms,
        success=True,
    )


# ---------------------------------------------------------------------------
# Usage tracking
# ---------------------------------------------------------------------------


async def record_call(
    db: AsyncSession,
    *,
    prompt_slug: str,
    location: str,
    latency_ms: int | None = None,
    tokens_in: int | None = None,
    tokens_out: int | None = None,
    error: bool = False,
) -> None:
    """Record a runtime call to a prompt. Updates running averages."""
    stmt = (
        select(ManagedPrompt)
        .where(ManagedPrompt.slug == prompt_slug)
    )
    prompt = (await db.execute(stmt)).scalar_one_or_none()
    if not prompt:
        return

    # Find or create usage entry for this location
    usage_stmt = select(PromptUsage).where(
        PromptUsage.prompt_id == prompt.id,
        PromptUsage.location == location,
    )
    usage = (await db.execute(usage_stmt)).scalar_one_or_none()

    if not usage:
        usage = PromptUsage(
            prompt_id=prompt.id,
            usage_type="runtime_call",
            location=location,
            is_primary=False,
        )
        db.add(usage)

    old_count = usage.call_count
    usage.call_count = old_count + 1

    if latency_ms is not None:
        old_avg = usage.avg_latency_ms or 0.0
        usage.avg_latency_ms = (old_avg * old_count + latency_ms) / (old_count + 1)

    if tokens_in is not None:
        old_avg = usage.avg_tokens_in or 0
        usage.avg_tokens_in = int((old_avg * old_count + tokens_in) / (old_count + 1))

    if tokens_out is not None:
        old_avg = usage.avg_tokens_out or 0
        usage.avg_tokens_out = int((old_avg * old_count + tokens_out) / (old_count + 1))

    if error:
        usage.error_count = (usage.error_count or 0) + 1

    await db.commit()


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------


async def get_stats(db: AsyncSession) -> dict:
    """Aggregate stats for the prompt management dashboard."""
    total = (await db.execute(select(func.count(ManagedPrompt.id)))).scalar() or 0
    active = (
        await db.execute(
            select(func.count(ManagedPrompt.id)).where(ManagedPrompt.is_active.is_(True))
        )
    ).scalar() or 0
    versions_count = (
        await db.execute(select(func.count(PromptVersion.id)))
    ).scalar() or 0
    categories_count = (
        await db.execute(select(func.count(func.distinct(ManagedPrompt.category))))
    ).scalar() or 0

    return {
        "total": total,
        "active": active,
        "versions_count": versions_count,
        "categories_count": categories_count,
    }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _text_diff(text_a: str, text_b: str, label_a: str, label_b: str) -> str:
    """Generate a unified diff between two text blocks."""
    lines_a = text_a.splitlines(keepends=True)
    lines_b = text_b.splitlines(keepends=True)
    diff = difflib.unified_diff(lines_a, lines_b, fromfile=label_a, tofile=label_b)
    return "".join(diff)


def _render_template(template: str, variables: dict) -> str:
    """Render a prompt template by substituting {variable} placeholders.

    Uses simple string replacement. Variables are sanitized to prevent
    injection. Unknown variables are left as-is.
    """
    rendered = template
    for key, value in variables.items():
        safe_value = str(value).replace("{", "{{").replace("}", "}}")
        rendered = rendered.replace(f"{{{key}}}", safe_value)
    return rendered
