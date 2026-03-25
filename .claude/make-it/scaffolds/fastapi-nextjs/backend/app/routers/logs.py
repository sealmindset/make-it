"""Activity log API endpoints for admin observability."""

from fastapi import APIRouter, Depends, Query

from app.middleware.permissions import require_permission
from app.schemas.auth import UserInfo
from app.services.log_service import log_store

router = APIRouter(prefix="/api/admin/logs", tags=["activity-logs"])


@router.get("/events")
async def get_log_events(
    type: str | None = Query(None),
    service: str | None = Query(None),
    method: str | None = Query(None),
    since: str | None = Query(None),
    path: str | None = Query(None, description="Substring match on path or URL"),
    status_min: int | None = Query(None, ge=100, le=599),
    status_max: int | None = Query(None, ge=100, le=599),
    user_email: str | None = Query(None, description="Substring match on user email"),
    q: str | None = Query(None, description="Free-text search across path, URL, error, email, service"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    current_user: UserInfo = Depends(require_permission("admin.logs", "read")),
):
    """Query activity log events with filtering and pagination."""
    return log_store.query(
        event_type=type,
        service=service,
        method=method,
        since=since,
        path=path,
        status_min=status_min,
        status_max=status_max,
        user_email=user_email,
        q=q,
        limit=limit,
        offset=offset,
    )


@router.get("/stats")
async def get_log_stats(
    current_user: UserInfo = Depends(require_permission("admin.logs", "read")),
):
    """Get activity log buffer statistics with breakdowns."""
    return log_store.stats()


@router.delete("/events")
async def clear_log_events(
    current_user: UserInfo = Depends(require_permission("admin.logs", "delete")),
):
    """Clear all events from the activity log buffer."""
    log_store.clear()
    return {"message": "Activity log buffer cleared"}
