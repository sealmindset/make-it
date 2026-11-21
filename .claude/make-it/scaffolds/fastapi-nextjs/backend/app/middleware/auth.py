import jwt
from fastapi import HTTPException, Request, status

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
        user = UserInfo(**payload)
    except jwt.ExpiredSignatureError:
        raise HTTPException(  # noqa: B904 -- kept as is: "from" would change the error chain (follow-up card)
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        )
    except (jwt.InvalidTokenError, Exception):
        raise HTTPException(  # noqa: B904 -- kept as is: "from" would change the error chain (follow-up card)
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
    # The activity log names the user from here: RequestLoggingMiddleware reads .sub and .email
    # after the response. Only the verified claims are kept, never the token or the cookie.
    request.state.user = user
    return user
