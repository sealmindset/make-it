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
    limit: int = Query(100, ge=1, le=1000),
    current_user: UserInfo = Depends(require_permission("admin.logs", "read")),
):
    """Query activity log events."""
    return log_store.query(
        event_type=type,
        service=service,
        method=method,
        since=since,
        limit=limit,
    )


@router.get("/stats")
async def get_log_stats(
    current_user: UserInfo = Depends(require_permission("admin.logs", "read")),
):
    """Get activity log buffer statistics."""
    return log_store.stats()


@router.delete("/events")
async def clear_log_events(
    current_user: UserInfo = Depends(require_permission("admin.logs", "delete")),
):
    """Clear all events from the activity log buffer."""
    log_store.clear()
    return {"message": "Activity log buffer cleared"}
