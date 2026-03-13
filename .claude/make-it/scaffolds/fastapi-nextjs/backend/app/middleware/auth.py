import jwt
from fastapi import Depends, HTTPException, Request, status

from app.config import settings
from app.schemas.auth import UserInfo


async def get_current_user(request: Request) -> UserInfo:
    """FastAPI dependency: decode JWT from httpOnly cookie and return UserInfo."""
    token = request.cookies.get("token")
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
        )
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
        return UserInfo(**payload)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        )
    except (jwt.InvalidTokenError, Exception):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
