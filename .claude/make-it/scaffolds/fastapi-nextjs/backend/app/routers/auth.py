import urllib.parse
from datetime import datetime, timedelta, timezone

import httpx
import jwt
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import settings
from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.permission import RolePermission
from app.models.user import User
from app.schemas.auth import LogoutResponse, UserInfo

router = APIRouter(prefix="/api/auth", tags=["auth"])


async def _get_oidc_discovery() -> dict:
    """Fetch OIDC discovery document from issuer."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{settings.OIDC_ISSUER_URL}/.well-known/openid-configuration"
        )
        resp.raise_for_status()
        return resp.json()


@router.get("/login")
async def login():
    """Redirect to OIDC provider authorization endpoint."""
    discovery = await _get_oidc_discovery()
    authorization_endpoint = discovery["authorization_endpoint"]

    params = {
        "client_id": settings.OIDC_CLIENT_ID,
        "response_type": "code",
        "scope": "openid email profile",
        "redirect_uri": f"{settings.FRONTEND_URL}/api/auth/callback",
    }
    auth_url = f"{authorization_endpoint}?{urllib.parse.urlencode(params)}"
    return RedirectResponse(url=auth_url, status_code=302)


@router.get("/callback")
async def callback(
    code: str = Query(...),
    db: AsyncSession = Depends(get_db),
):
    """Exchange authorization code for tokens, look up user, issue JWT."""
    discovery = await _get_oidc_discovery()
    token_endpoint = discovery["token_endpoint"]
    userinfo_endpoint = discovery["userinfo_endpoint"]

    # Exchange code for tokens
    async with httpx.AsyncClient() as client:
        token_resp = await client.post(
            token_endpoint,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": f"{settings.FRONTEND_URL}/api/auth/callback",
                "client_id": settings.OIDC_CLIENT_ID,
                "client_secret": settings.OIDC_CLIENT_SECRET,
            },
        )
        token_resp.raise_for_status()
        tokens = token_resp.json()

        # Get user info from OIDC provider
        userinfo_resp = await client.get(
            userinfo_endpoint,
            headers={"Authorization": f"Bearer {tokens['access_token']}"},
        )
        userinfo_resp.raise_for_status()
        userinfo = userinfo_resp.json()

    # Look up user by oidc_subject (NOT email)
    oidc_subject = userinfo.get("sub")
    stmt = (
        select(User)
        .where(User.oidc_subject == oidc_subject)
        .options(selectinload(User.role))
    )
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User not provisioned. Contact your administrator.",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account deactivated. Contact your administrator.",
        )

    # Load role permissions from database
    role = user.role
    perm_stmt = (
        select(RolePermission)
        .where(RolePermission.role_id == role.id)
        .options(selectinload(RolePermission.permission))
    )
    perm_result = await db.execute(perm_stmt)
    role_perms = perm_result.scalars().all()
    permissions = [
        f"{rp.permission.resource}.{rp.permission.action}" for rp in role_perms
    ]

    # Sign JWT
    payload = {
        "sub": user.oidc_subject,
        "email": user.email,
        "name": user.display_name,
        "role_id": str(user.role_id),
        "role_name": role.name,
        "permissions": permissions,
        "exp": datetime.now(timezone.utc) + timedelta(hours=8),
        "iat": datetime.now(timezone.utc),
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")

    # Set httpOnly cookie and redirect to dashboard
    response = RedirectResponse(
        url=f"{settings.FRONTEND_URL}/dashboard", status_code=302
    )
    response.set_cookie(
        key="token",
        value=token,
        httponly=True,
        samesite="lax",
        secure=False,  # Set to True in production with HTTPS
        path="/",
    )
    return response


@router.get("/me", response_model=UserInfo)
async def me(current_user: UserInfo = Depends(get_current_user)):
    """Return the current authenticated user's info from JWT."""
    return current_user


@router.post("/logout", response_model=LogoutResponse)
async def logout(current_user: UserInfo = Depends(get_current_user)):
    """Log out by deleting the token cookie. Must be POST, not GET."""
    response = LogoutResponse(message="Logged out successfully")
    from fastapi.responses import JSONResponse

    json_response = JSONResponse(content=response.model_dump())
    json_response.delete_cookie(key="token", path="/")
    return json_response
