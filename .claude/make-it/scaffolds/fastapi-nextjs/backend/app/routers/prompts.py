"""AI prompt management API routes.

Provides CRUD, versioning, tagging, testing, usage tracking, and audit
for database-managed AI prompt templates.

IMPORTANT: Static routes (/stats, /tags, /audit) MUST be registered
before the /{slug} catch-all to prevent FastAPI route shadowing.
"""

import re
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.middleware.permissions import require_permission
from app.models.managed_prompt import (
    ManagedPrompt,
    PromptAuditLog,
    PromptTag,
    PromptTestCase,
    PromptUsage,
    PromptVersion,
)
from app.schemas.auth import UserInfo
from app.schemas.prompt import (
    ManagedPromptCreate,
    ManagedPromptListOut,
    ManagedPromptOut,
    ManagedPromptUpdate,
    PromptAuditLogOut,
    PromptStatsOut,
    PromptTagAdd,
    PromptTagOut,
    PromptTestCaseCreate,
    PromptTestCaseOut,
    PromptTestRunOut,
    PromptUsageOut,
    PromptVersionDiffOut,
    PromptVersionOut,
)
from app.services import prompt_service

router = APIRouter(prefix="/api/admin/prompts", tags=["prompts"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _slugify(name: str) -> str:
    """Generate a URL-safe slug from a name."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def _prompt_to_out(prompt: ManagedPrompt) -> ManagedPromptOut:
    """Convert ManagedPrompt model to full output schema."""
    tags = [t.tag for t in prompt.tags] if prompt.tags else []
    primary_usage = next(
        (u.location for u in (prompt.usages or []) if u.is_primary), None
    )
    version_count = len(prompt.versions) if prompt.versions else 0
    usage_count = sum(u.call_count for u in (prompt.usages or []))

    return ManagedPromptOut(
        id=prompt.id,
        slug=prompt.slug,
        name=prompt.name,
        description=prompt.description,
        category=prompt.category,
        provider=prompt.provider,
        model=prompt.model,
        current_version=prompt.current_version,
        is_active=prompt.is_active,
        is_locked=prompt.is_locked,
        locked_by=prompt.locked_by,
        locked_reason=prompt.locked_reason,
        source_file=prompt.source_file,
        created_by=prompt.created_by,
        updated_by=prompt.updated_by,
        created_at=prompt.created_at,
        updated_at=prompt.updated_at,
        tags=tags,
        primary_usage_location=primary_usage,
        version_count=version_count,
        usage_count=usage_count,
    )


def _prompt_to_list_out(prompt: ManagedPrompt) -> ManagedPromptListOut:
    """Convert ManagedPrompt model to lighter list output."""
    tags = [t.tag for t in prompt.tags] if prompt.tags else []
    primary_usage = next(
        (u.location for u in (prompt.usages or []) if u.is_primary), None
    )
    return ManagedPromptListOut(
        id=prompt.id,
        slug=prompt.slug,
        name=prompt.name,
        description=prompt.description,
        category=prompt.category,
        provider=prompt.provider,
        model=prompt.model,
        current_version=prompt.current_version,
        is_active=prompt.is_active,
        is_locked=prompt.is_locked,
        updated_at=prompt.updated_at,
        tags=tags,
        primary_usage_location=primary_usage,
    )


def _check_not_locked(prompt: ManagedPrompt) -> None:
    """Raise 409 if the prompt is locked."""
    if prompt.is_locked:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Prompt '{prompt.slug}' is locked: {prompt.locked_reason or 'No reason given'}",
        )


async def _get_prompt_or_404(
    slug: str, db: AsyncSession
) -> ManagedPrompt:
    """Fetch a prompt by slug or raise 404."""
    stmt = select(ManagedPrompt).where(ManagedPrompt.slug == slug)
    prompt = (await db.execute(stmt)).scalar_one_or_none()
    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Prompt '{slug}' not found",
        )
    return prompt


# ===========================================================================
# STATIC ROUTES -- must be registered BEFORE /{slug} to avoid shadowing
# ===========================================================================


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------


@router.get("/stats", response_model=PromptStatsOut)
async def get_stats(
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """Aggregate stats for the AI Instructions dashboard."""
    stats = await prompt_service.get_stats(db)
    return PromptStatsOut(**stats)


# ---------------------------------------------------------------------------
# Tags (system-wide)
# ---------------------------------------------------------------------------


@router.get("/tags", response_model=list[PromptTagOut])
async def list_all_tags(
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """List all unique tags with usage counts."""
    stmt = (
        select(PromptTag.tag, func.count(PromptTag.id).label("count"))
        .group_by(PromptTag.tag)
        .order_by(func.count(PromptTag.id).desc())
    )
    rows = (await db.execute(stmt)).all()
    return [PromptTagOut(tag=row.tag, count=row.count) for row in rows]


# ---------------------------------------------------------------------------
# Audit (system-wide)
# ---------------------------------------------------------------------------


@router.get("/audit", response_model=list[PromptAuditLogOut])
async def list_audit_log(
    action: str | None = None,
    prompt_slug: str | None = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """System-wide audit log for all prompt management actions."""
    stmt = select(PromptAuditLog).order_by(PromptAuditLog.created_at.desc())
    if action:
        stmt = stmt.where(PromptAuditLog.action == action)
    if prompt_slug:
        stmt = stmt.where(PromptAuditLog.prompt_slug == prompt_slug)
    stmt = stmt.offset(skip).limit(limit)
    rows = (await db.execute(stmt)).scalars().all()
    return [PromptAuditLogOut.model_validate(r) for r in rows]


# ===========================================================================
# CRUD ROUTES
# ===========================================================================


@router.get("/", response_model=list[ManagedPromptListOut])
async def list_prompts(
    search: str | None = None,
    category: str | None = None,
    is_active: bool | None = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """List all AI instructions with optional filtering."""
    stmt = select(ManagedPrompt).order_by(ManagedPrompt.updated_at.desc())

    if search:
        pattern = f"%{search}%"
        stmt = stmt.where(
            ManagedPrompt.name.ilike(pattern)
            | ManagedPrompt.description.ilike(pattern)
            | ManagedPrompt.slug.ilike(pattern)
        )
    if category:
        stmt = stmt.where(ManagedPrompt.category == category)
    if is_active is not None:
        stmt = stmt.where(ManagedPrompt.is_active.is_(is_active))

    stmt = stmt.offset(skip).limit(limit)
    prompts = (await db.execute(stmt)).scalars().all()
    return [_prompt_to_list_out(p) for p in prompts]


@router.post("/", response_model=ManagedPromptOut, status_code=status.HTTP_201_CREATED)
async def create_prompt(
    body: ManagedPromptCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "create")),
):
    """Create a new AI instruction with its initial version."""
    slug = body.slug or _slugify(body.name)

    # Check for slug collision
    existing = (
        await db.execute(select(ManagedPrompt).where(ManagedPrompt.slug == slug))
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"An AI instruction with slug '{slug}' already exists",
        )

    prompt = ManagedPrompt(
        slug=slug,
        name=body.name,
        description=body.description,
        category=body.category,
        provider=body.provider,
        model=body.model,
        current_version=1,
        source_file=body.source_file,
        created_by=current_user.email,
    )
    db.add(prompt)
    await db.flush()

    # Create initial version
    version = PromptVersion(
        prompt_id=prompt.id,
        version=1,
        content=body.content,
        system_message=body.system_message,
        parameters=body.parameters,
        change_summary=body.change_summary or "Initial version",
        created_by=current_user.email,
    )
    db.add(version)

    # Add tags
    if body.tags:
        for tag_str in body.tags:
            db.add(PromptTag(prompt_id=prompt.id, tag=tag_str.strip()))

    await prompt_service.log_audit(
        db,
        action="created",
        prompt=prompt,
        version=1,
        user_email=current_user.email,
        new_value={"name": body.name, "slug": slug, "category": body.category},
    )

    await db.commit()
    await db.refresh(prompt)
    return _prompt_to_out(prompt)


# ===========================================================================
# SLUG-BASED ROUTES -- registered AFTER static routes
# ===========================================================================


@router.get("/{slug}", response_model=ManagedPromptOut)
async def get_prompt(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """Get a single AI instruction by slug."""
    prompt = await _get_prompt_or_404(slug, db)
    return _prompt_to_out(prompt)


@router.put("/{slug}", response_model=ManagedPromptOut)
async def update_prompt(
    slug: str,
    body: ManagedPromptUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Update an AI instruction. Creates a new version if content changed."""
    prompt = await _get_prompt_or_404(slug, db)
    _check_not_locked(prompt)

    # Track what changed for audit
    changes = {}
    data = body.model_dump(exclude_unset=True)

    # Update metadata fields
    for field in ("name", "description", "category", "provider", "model", "source_file"):
        if field in data:
            old_val = getattr(prompt, field)
            new_val = data[field]
            if old_val != new_val:
                changes[field] = {"old": old_val, "new": new_val}
                setattr(prompt, field, new_val)

    prompt.updated_by = current_user.email

    # Create new version if content fields changed
    content_changed = any(k in data for k in ("content", "system_message", "parameters"))
    if content_changed:
        # Get current version for defaults
        current = (
            await db.execute(
                select(PromptVersion)
                .where(
                    PromptVersion.prompt_id == prompt.id,
                    PromptVersion.version == prompt.current_version,
                )
            )
        ).scalar_one_or_none()

        await prompt_service.create_version(
            db,
            prompt=prompt,
            content=data.get("content", current.content if current else ""),
            system_message=data.get("system_message", current.system_message if current else None),
            parameters=data.get("parameters", current.parameters if current else None),
            model=data.get("model", current.model if current else None),
            change_summary=data.get("change_summary", "Updated"),
            user_email=current_user.email,
        )

    if changes:
        await prompt_service.log_audit(
            db,
            action="updated",
            prompt=prompt,
            version=prompt.current_version,
            user_email=current_user.email,
            old_value={k: v["old"] for k, v in changes.items()},
            new_value={k: v["new"] for k, v in changes.items()},
        )

    await db.commit()
    await db.refresh(prompt)
    return _prompt_to_out(prompt)


@router.delete("/{slug}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_prompt(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "delete")),
):
    """Soft-delete (deactivate) an AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    prompt.is_active = False
    prompt.updated_by = current_user.email

    await prompt_service.log_audit(
        db,
        action="deactivated",
        prompt=prompt,
        user_email=current_user.email,
    )
    await db.commit()


@router.post("/{slug}/activate", response_model=ManagedPromptOut)
async def activate_prompt(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Re-activate a deactivated AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    prompt.is_active = True
    prompt.updated_by = current_user.email

    await prompt_service.log_audit(
        db,
        action="activated",
        prompt=prompt,
        user_email=current_user.email,
    )
    await db.commit()
    await db.refresh(prompt)
    return _prompt_to_out(prompt)


# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------


@router.post("/{slug}/lock", response_model=ManagedPromptOut)
async def lock_prompt(
    slug: str,
    reason: str = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Lock an AI instruction to prevent edits."""
    prompt = await _get_prompt_or_404(slug, db)
    prompt.is_locked = True
    prompt.locked_by = current_user.email
    prompt.locked_reason = reason

    await prompt_service.log_audit(
        db,
        action="locked",
        prompt=prompt,
        user_email=current_user.email,
        new_value={"reason": reason},
    )
    await db.commit()
    await db.refresh(prompt)
    return _prompt_to_out(prompt)


@router.post("/{slug}/unlock", response_model=ManagedPromptOut)
async def unlock_prompt(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Unlock an AI instruction to allow edits."""
    prompt = await _get_prompt_or_404(slug, db)
    old_locked_by = prompt.locked_by
    prompt.is_locked = False
    prompt.locked_by = None
    prompt.locked_reason = None

    await prompt_service.log_audit(
        db,
        action="unlocked",
        prompt=prompt,
        user_email=current_user.email,
        old_value={"locked_by": old_locked_by},
    )
    await db.commit()
    await db.refresh(prompt)
    return _prompt_to_out(prompt)


# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------


@router.get("/{slug}/versions", response_model=list[PromptVersionOut])
async def list_versions(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """List all versions of an AI instruction (newest first)."""
    prompt = await _get_prompt_or_404(slug, db)
    stmt = (
        select(PromptVersion)
        .where(PromptVersion.prompt_id == prompt.id)
        .order_by(PromptVersion.version.desc())
    )
    versions = (await db.execute(stmt)).scalars().all()
    return [PromptVersionOut.model_validate(v) for v in versions]


@router.get("/{slug}/versions/diff", response_model=PromptVersionDiffOut)
async def diff_versions(
    slug: str,
    v1: int = Query(..., description="First version number"),
    v2: int = Query(..., description="Second version number"),
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """Compare two versions of an AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    return await prompt_service.diff_versions(db, prompt.id, v1, v2)


@router.get("/{slug}/versions/{version}", response_model=PromptVersionOut)
async def get_version(
    slug: str,
    version: int,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """Get a specific version of an AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    stmt = select(PromptVersion).where(
        PromptVersion.prompt_id == prompt.id,
        PromptVersion.version == version,
    )
    ver = (await db.execute(stmt)).scalar_one_or_none()
    if not ver:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Version {version} not found for '{slug}'",
        )
    return PromptVersionOut.model_validate(ver)


@router.post("/{slug}/versions/{version}/restore", response_model=ManagedPromptOut)
async def restore_version(
    slug: str,
    version: int,
    change_summary: str = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Restore an AI instruction to a previous version (creates a new version with old content)."""
    prompt = await _get_prompt_or_404(slug, db)
    _check_not_locked(prompt)

    try:
        await prompt_service.restore_version(
            db,
            prompt=prompt,
            target_version=version,
            user_email=current_user.email,
            change_summary=change_summary,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))

    await db.commit()
    await db.refresh(prompt)
    return _prompt_to_out(prompt)


# ---------------------------------------------------------------------------
# Tags (per-prompt)
# ---------------------------------------------------------------------------


@router.get("/{slug}/tags", response_model=list[str])
async def list_prompt_tags(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """List tags for a specific AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    return [t.tag for t in prompt.tags]


@router.post("/{slug}/tags", response_model=list[str])
async def add_tag(
    slug: str,
    body: PromptTagAdd,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Add a tag to an AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    _check_not_locked(prompt)

    # Check if tag already exists
    existing = (
        await db.execute(
            select(PromptTag).where(
                PromptTag.prompt_id == prompt.id,
                PromptTag.tag == body.tag.strip(),
            )
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Tag '{body.tag}' already exists on this prompt",
        )

    db.add(PromptTag(prompt_id=prompt.id, tag=body.tag.strip()))
    await db.commit()
    await db.refresh(prompt)
    return [t.tag for t in prompt.tags]


@router.delete("/{slug}/tags/{tag}", response_model=list[str])
async def remove_tag(
    slug: str,
    tag: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Remove a tag from an AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    _check_not_locked(prompt)

    stmt = select(PromptTag).where(
        PromptTag.prompt_id == prompt.id,
        PromptTag.tag == tag,
    )
    tag_obj = (await db.execute(stmt)).scalar_one_or_none()
    if not tag_obj:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Tag '{tag}' not found on this prompt",
        )

    await db.delete(tag_obj)
    await db.commit()
    await db.refresh(prompt)
    return [t.tag for t in prompt.tags]


# ---------------------------------------------------------------------------
# Test Cases
# ---------------------------------------------------------------------------


@router.get("/{slug}/tests", response_model=list[PromptTestCaseOut])
async def list_test_cases(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """List saved test cases for an AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    stmt = (
        select(PromptTestCase)
        .where(PromptTestCase.prompt_id == prompt.id)
        .order_by(PromptTestCase.created_at.desc())
    )
    cases = (await db.execute(stmt)).scalars().all()
    return [PromptTestCaseOut.model_validate(c) for c in cases]


@router.post("/{slug}/tests", response_model=PromptTestCaseOut, status_code=status.HTTP_201_CREATED)
async def create_test_case(
    slug: str,
    body: PromptTestCaseCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "create")),
):
    """Save a new test case for an AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    case = PromptTestCase(
        prompt_id=prompt.id,
        name=body.name,
        input_data=body.input_data,
        expected_output=body.expected_output,
        notes=body.notes,
        created_by=current_user.email,
    )
    db.add(case)
    await db.commit()
    await db.refresh(case)
    return PromptTestCaseOut.model_validate(case)


@router.post("/{slug}/tests/run", response_model=PromptTestRunOut)
async def run_test(
    slug: str,
    input_data: dict | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "update")),
):
    """Run a test against an AI instruction with the given input data."""
    prompt = await _get_prompt_or_404(slug, db)
    result = await prompt_service.run_test(db, prompt=prompt, input_data=input_data)
    await db.commit()
    return result


@router.delete("/{slug}/tests/{test_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_test_case(
    slug: str,
    test_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "delete")),
):
    """Delete a saved test case."""
    prompt = await _get_prompt_or_404(slug, db)
    stmt = select(PromptTestCase).where(
        PromptTestCase.id == test_id,
        PromptTestCase.prompt_id == prompt.id,
    )
    case = (await db.execute(stmt)).scalar_one_or_none()
    if not case:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test case not found")
    await db.delete(case)
    await db.commit()


# ---------------------------------------------------------------------------
# Usages
# ---------------------------------------------------------------------------


@router.get("/{slug}/usages", response_model=list[PromptUsageOut])
async def list_usages(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """List where an AI instruction is used in the application."""
    prompt = await _get_prompt_or_404(slug, db)
    stmt = (
        select(PromptUsage)
        .where(PromptUsage.prompt_id == prompt.id)
        .order_by(PromptUsage.is_primary.desc(), PromptUsage.call_count.desc())
    )
    usages = (await db.execute(stmt)).scalars().all()
    return [PromptUsageOut.model_validate(u) for u in usages]


# ---------------------------------------------------------------------------
# Audit (per-prompt)
# ---------------------------------------------------------------------------


@router.get("/{slug}/audit", response_model=list[PromptAuditLogOut])
async def list_prompt_audit(
    slug: str,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: UserInfo = Depends(require_permission("admin.prompts", "read")),
):
    """Audit log for a specific AI instruction."""
    prompt = await _get_prompt_or_404(slug, db)
    stmt = (
        select(PromptAuditLog)
        .where(PromptAuditLog.prompt_id == prompt.id)
        .order_by(PromptAuditLog.created_at.desc())
        .offset(skip)
        .limit(limit)
    )
    entries = (await db.execute(stmt)).scalars().all()
    return [PromptAuditLogOut.model_validate(e) for e in entries]
