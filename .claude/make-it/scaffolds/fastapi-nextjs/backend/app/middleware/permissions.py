from fastapi import Depends, HTTPException, status

from app.middleware.auth import get_current_user
from app.schemas.auth import UserInfo


def require_permission(resource: str, action: str):
    """Returns a FastAPI dependency that checks the user has the required permission.

    Usage:
        @router.get("/items", dependencies=[Depends(require_permission("items", "view"))])
        async def list_items(...):
            ...
    """

    async def _check_permission(
        current_user: UserInfo = Depends(get_current_user),
    ) -> UserInfo:
        required = f"{resource}.{action}"
        if required not in current_user.permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Permission denied: {required}",
            )
        return current_user

    return _check_permission
