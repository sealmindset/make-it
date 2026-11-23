"""
Mock OIDC Provider for local development.

A complete OpenID Connect provider that runs in Docker alongside the app.
Ships as-is with every /make-it app -- no regeneration needed.

Features:
- RSA key pair generated on startup for JWT signing
- OIDC discovery with internal/external URL split (eliminates URL rewriting)
- Login form with user list or auto-approve via login_hint
- Admin API for seed script integration
- Case-insensitive Bearer token validation

Config via environment variables:
- MOCK_OIDC_PORT (default 10090)
- MOCK_OIDC_EXTERNAL_BASE_URL (default http://localhost:10090) -- browser-facing
- MOCK_OIDC_INTERNAL_BASE_URL (default http://mock-oidc:10090) -- Docker internal
- MOCK_OIDC_CLIENT_ID (default mock-oidc-client)
- MOCK_OIDC_CLIENT_SECRET (default mock-oidc-secret)
- MOCK_OIDC_ACCESS_CODE (optional) -- when set, the sign-in page asks for this code before it shows
  anyone or signs anyone in (a shared code, for a practice sign-in someone else can reach)
- MOCK_OIDC_REQUIRE_ACCESS_CODE (optional, "true" on a cluster) -- refuse to start without an access code
  of at least 16 characters
Unset, both leave local development exactly as it was.
"""

import asyncio
import base64
import hashlib
import hmac
import html as html_mod
import json
import os
import secrets
import sys
import time
import uuid
from typing import Optional
from urllib.parse import urlencode, urlparse, parse_qs

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import FastAPI, Form, Header, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PORT = int(os.getenv("MOCK_OIDC_PORT", "10090"))
EXTERNAL_BASE = os.getenv("MOCK_OIDC_EXTERNAL_BASE_URL", f"http://localhost:{PORT}")
INTERNAL_BASE = os.getenv("MOCK_OIDC_INTERNAL_BASE_URL", f"http://mock-oidc:{PORT}")
CLIENT_ID = os.getenv("MOCK_OIDC_CLIENT_ID", "mock-oidc-client")
CLIENT_SECRET = os.getenv("MOCK_OIDC_CLIENT_SECRET", "mock-oidc-secret")
ACCESS_CODE = os.getenv("MOCK_OIDC_ACCESS_CODE", "")
if os.getenv("MOCK_OIDC_REQUIRE_ACCESS_CODE", "").lower() == "true" and len(ACCESS_CODE) < 16:
    # Fail closed: a practice sign-in someone else can reach never runs without its access code.
    print("mock-oidc: not starting: MOCK_OIDC_REQUIRE_ACCESS_CODE is true and MOCK_OIDC_ACCESS_CODE is "
          "missing or shorter than 16 characters", file=sys.stderr, flush=True)
    sys.exit(1)

# Access code: a correct code is remembered for that browser in a signed cookie for ACCESS_TTL seconds.
# Wrong codes are counted per client address, in memory (a restart clears them): after ACCESS_MAX_FAILS
# within ACCESS_WINDOW seconds, every try is refused until the window passes; each wrong try waits 1 second.
ACCESS_COOKIE = "mock_oidc_access"
ACCESS_TTL = 15 * 60
ACCESS_MAX_FAILS = 5
ACCESS_WINDOW = 5 * 60
_access_key = secrets.token_bytes(32)
_access_fails: dict[str, list[float]] = {}

# ---------------------------------------------------------------------------
# RSA key pair (generated once on startup)
# ---------------------------------------------------------------------------

_rsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_private_pem = _rsa_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)
_public_key = _rsa_key.public_key()
_public_numbers = _public_key.public_numbers()
_kid = hashlib.sha256(_private_pem).hexdigest()[:16]


def _int_to_base64url(n: int) -> str:
    """Convert a large integer to Base64url-encoded string (no padding)."""
    byte_length = (n.bit_length() + 7) // 8
    raw = n.to_bytes(byte_length, byteorder="big")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


# ---------------------------------------------------------------------------
# In-memory storage
# ---------------------------------------------------------------------------

# Users: {sub: {sub, email, name}}
_users: dict[str, dict] = {}

# Auth codes: {code: {sub, redirect_uri, client_id, expires_at, nonce}}
_auth_codes: dict[str, dict] = {}

# Tokens: {access_token: {sub, email, name}}
_tokens: dict[str, dict] = {}

# Client config: {client_id: {redirect_uris: [...]}}
_clients: dict[str, dict] = {
    CLIENT_ID: {"redirect_uris": []},
}

# Auth code expiry in seconds
AUTH_CODE_TTL = 300  # 5 minutes

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(title="Mock OIDC Provider", version="1.0.0")


def _validate_redirect_uri(client_id: str, redirect_uri: str) -> None:
    """Reject redirect_uri values not registered for the client."""
    client = _clients.get(client_id)
    if not client or redirect_uri not in client.get("redirect_uris", []):
        raise HTTPException(
            400, f"redirect_uri not registered for client: {redirect_uri}"
        )


# ---------------------------------------------------------------------------
# OIDC Discovery
# ---------------------------------------------------------------------------


@app.get("/.well-known/openid-configuration")
async def openid_configuration():
    """
    OIDC discovery document.

    Browser-facing endpoints (authorization) use EXTERNAL_BASE.
    Server-to-server endpoints (token, userinfo, jwks) use INTERNAL_BASE.
    This native split eliminates the need for OIDC_INTERNAL_URL or URL rewriting.
    """
    return {
        "issuer": INTERNAL_BASE,
        "authorization_endpoint": f"{EXTERNAL_BASE}/authorize",
        "token_endpoint": f"{INTERNAL_BASE}/token",
        "userinfo_endpoint": f"{INTERNAL_BASE}/userinfo",
        "jwks_uri": f"{INTERNAL_BASE}/jwks",
        "response_types_supported": ["code"],
        "subject_types_supported": ["public"],
        "id_token_signing_alg_values_supported": ["RS256"],
        "scopes_supported": ["openid", "profile", "email"],
        "token_endpoint_auth_methods_supported": ["client_secret_post"],
        "claims_supported": ["sub", "email", "name", "iss", "aud", "exp", "iat"],
    }


# ---------------------------------------------------------------------------
# JWKS
# ---------------------------------------------------------------------------


@app.get("/jwks")
async def jwks():
    """Return public key in JWK format for token verification."""
    return {
        "keys": [
            {
                "kty": "RSA",
                "use": "sig",
                "alg": "RS256",
                "kid": _kid,
                "n": _int_to_base64url(_public_numbers.n),
                "e": _int_to_base64url(_public_numbers.e),
            }
        ]
    }


# ---------------------------------------------------------------------------
# Access code (only when MOCK_OIDC_ACCESS_CODE is set)
# ---------------------------------------------------------------------------


def _access_token(expires: int) -> str:
    sig = hmac.new(_access_key, str(expires).encode(), hashlib.sha256).hexdigest()
    return f"{expires}.{sig}"


def _has_access(request: Request) -> bool:
    """True when no access code is set, or the browser holds a valid, unexpired access cookie."""
    if not ACCESS_CODE:
        return True
    raw = request.cookies.get(ACCESS_COOKIE, "")
    expires, _, _sig = raw.partition(".")
    if not expires.isdigit() or int(expires) < time.time():
        return False
    return hmac.compare_digest(raw, _access_token(int(expires)))


def _client(request: Request) -> str:
    return request.client.host if request.client else "?"


def _render_code_page(query: str, message: str = "") -> HTMLResponse:
    """The sign-in page when an access code is set: a code field only, no names."""
    esc = html_mod.escape
    note = f'<p style="color:#b00;">{esc(message)}</p>' if message else ""
    return HTMLResponse(content=f"""<!DOCTYPE html>
<html><head><title>Practice sign-in - Access code</title></head>
<body style="font-family:sans-serif;display:flex;justify-content:center;margin-top:80px;">
  <form method="POST" action="/authorize" style="max-width:360px;">
    <h2>Practice sign-in</h2>
    <p>Enter the access code your team gave you.</p>{note}
    <input type="hidden" name="return_query" value="{esc(query, quote=True)}">
    <input type="password" name="access_code" autocomplete="off" required style="width:100%;padding:8px;">
    <button type="submit" style="margin-top:12px;padding:8px 16px;">Continue</button>
  </form>
</body></html>""", status_code=401 if message else 200)


async def _check_code(request: Request, code: str, return_query: str):
    """A code submitted from the code page: right -> set the cookie and go back to the sign-in page."""
    who, now = _client(request), time.time()
    recent = [t for t in _access_fails.get(who, []) if now - t < ACCESS_WINDOW]
    _access_fails[who] = recent
    if len(recent) >= ACCESS_MAX_FAILS:
        return _render_code_page(return_query, "Too many wrong codes. Wait a few minutes and try again.")
    if not hmac.compare_digest(code.encode(), ACCESS_CODE.encode()):
        recent.append(now)
        await asyncio.sleep(1)
        return _render_code_page(return_query, "That code isn't right.")
    _access_fails.pop(who, None)
    expires = int(now) + ACCESS_TTL
    secure = EXTERNAL_BASE.startswith("https://") or request.headers.get("x-forwarded-proto") == "https"
    resp = RedirectResponse(url="/authorize?" + return_query.lstrip("?"), status_code=303)
    resp.set_cookie(ACCESS_COOKIE, _access_token(expires), max_age=ACCESS_TTL, httponly=True,
                    secure=secure, samesite="lax", path="/authorize")
    return resp


# ---------------------------------------------------------------------------
# Authorization
# ---------------------------------------------------------------------------


def _generate_auth_code(
    sub: str, redirect_uri: str, client_id: str, nonce: Optional[str] = None
) -> str:
    """Generate and store an authorization code."""
    code = secrets.token_urlsafe(32)
    _auth_codes[code] = {
        "sub": sub,
        "redirect_uri": redirect_uri,
        "client_id": client_id,
        "nonce": nonce,
        "expires_at": time.time() + AUTH_CODE_TTL,
    }
    return code


def _build_redirect(redirect_uri: str, code: str, state: Optional[str]) -> str:
    """Build the redirect URL with code and optional state."""
    params = {"code": code}
    if state:
        params["state"] = state
    separator = "&" if "?" in redirect_uri else "?"
    return f"{redirect_uri}{separator}{urlencode(params)}"


def _render_login_page(
    redirect_uri: str,
    client_id: str,
    state: Optional[str],
    nonce: Optional[str],
) -> HTMLResponse:
    """Render HTML login form showing registered users."""
    esc = html_mod.escape
    user_buttons = ""
    for sub, user in _users.items():
        user_buttons += f"""
        <button type="submit" name="sub" value="{esc(sub, quote=True)}"
                style="display:block;width:100%;padding:12px 16px;margin:8px 0;
                       font-size:16px;cursor:pointer;border:1px solid #ccc;
                       border-radius:6px;background:#fff;text-align:left;">
            <strong>{esc(user['name'])}</strong><br>
            <small style="color:#666;">{esc(user['email'])}</small>
        </button>
        """

    if not user_buttons:
        user_buttons = "<p style='color:#999;'>No users registered. Run the seed script first.</p>"

    page_html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Mock OIDC - Sign In</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
               display: flex; justify-content: center; align-items: center;
               min-height: 100vh; margin: 0; background: #f5f5f5; }}
        .card {{ background: #fff; padding: 32px; border-radius: 12px;
                 box-shadow: 0 2px 8px rgba(0,0,0,0.1); max-width: 400px; width: 100%; }}
        h2 {{ margin-top: 0; color: #333; }}
        .subtitle {{ color: #666; margin-bottom: 24px; }}
    </style>
</head>
<body>
    <div class="card">
        <h2>Sign In</h2>
        <p class="subtitle">Mock OIDC Provider - Select a user:</p>
        <form method="POST" action="/authorize">
            <input type="hidden" name="redirect_uri" value="{esc(redirect_uri, quote=True)}">
            <input type="hidden" name="client_id" value="{esc(client_id, quote=True)}">
            <input type="hidden" name="state" value="{esc(state or '', quote=True)}">
            <input type="hidden" name="nonce" value="{esc(nonce or '', quote=True)}">
            {user_buttons}
        </form>
    </div>
</body>
</html>"""
    return HTMLResponse(content=page_html)


@app.get("/authorize")
async def authorize_get(
    request: Request,
    response_type: str = Query("code"),
    client_id: str = Query(...),
    redirect_uri: str = Query(...),
    scope: str = Query("openid"),
    state: Optional[str] = Query(None),
    nonce: Optional[str] = Query(None),
    login_hint: Optional[str] = Query(None),
):
    """
    Authorization endpoint (GET).

    If login_hint is provided and matches a registered user sub,
    auto-approve and redirect with code. Otherwise show login form.
    """
    if response_type != "code":
        raise HTTPException(400, "Only response_type=code is supported")

    # Validate redirect_uri against registered URIs to prevent open redirect
    _validate_redirect_uri(client_id, redirect_uri)

    # With an access code set, nothing below (not even login_hint) happens without it
    if not _has_access(request):
        return _render_code_page(request.url.query)

    # If login_hint matches a known user, auto-approve
    if login_hint and login_hint in _users:
        code = _generate_auth_code(login_hint, redirect_uri, client_id, nonce)
        return RedirectResponse(
            url=_build_redirect(redirect_uri, code, state), status_code=302
        )

    # Show login form
    return _render_login_page(redirect_uri, client_id, state, nonce)


@app.post("/authorize")
async def authorize_post(
    request: Request,
    sub: Optional[str] = Form(None),
    redirect_uri: Optional[str] = Form(None),
    client_id: Optional[str] = Form(None),
    state: str = Form(""),
    nonce: str = Form(""),
    access_code: Optional[str] = Form(None),
    return_query: str = Form(""),
):
    """Authorization endpoint (POST) -- the access code form, or a user picked on the login page."""
    if access_code is not None and ACCESS_CODE:
        return await _check_code(request, access_code, return_query)
    if not _has_access(request):
        raise HTTPException(403, "The access code is needed first.")
    if not sub or not redirect_uri or not client_id:
        raise HTTPException(422, "sub, redirect_uri and client_id are required")
    if sub not in _users:
        raise HTTPException(400, f"Unknown user: {sub}")

    # Validate redirect_uri against registered URIs to prevent open redirect
    _validate_redirect_uri(client_id, redirect_uri)

    code = _generate_auth_code(
        sub, redirect_uri, client_id, nonce if nonce else None
    )
    return RedirectResponse(
        url=_build_redirect(redirect_uri, code, state if state else None),
        status_code=302,
    )


# ---------------------------------------------------------------------------
# Token
# ---------------------------------------------------------------------------


def _create_jwt(payload: dict) -> str:
    """Sign a JWT with the RSA private key."""
    return jwt.encode(payload, _private_pem, algorithm="RS256", headers={"kid": _kid})


@app.post("/token")
async def token(
    grant_type: str = Form(...),
    code: str = Form(...),
    redirect_uri: str = Form(...),
    client_id: str = Form(...),
    client_secret: str = Form(...),
):
    """
    Token endpoint -- exchange authorization code for tokens.

    Validates client_id, client_secret, redirect_uri, and code.
    Returns JWT access_token and id_token signed with RSA key.
    """
    # Validate client credentials
    if client_id != CLIENT_ID:
        raise HTTPException(401, "Invalid client_id")
    if client_secret != CLIENT_SECRET:
        raise HTTPException(401, "Invalid client_secret")
    if grant_type != "authorization_code":
        raise HTTPException(400, "Only grant_type=authorization_code is supported")

    # Validate and consume auth code
    auth_code = _auth_codes.pop(code, None)
    if not auth_code:
        raise HTTPException(400, "Invalid or expired authorization code")
    if auth_code["expires_at"] < time.time():
        raise HTTPException(400, "Authorization code expired")
    if auth_code["redirect_uri"] != redirect_uri:
        raise HTTPException(400, "redirect_uri mismatch")
    if auth_code["client_id"] != client_id:
        raise HTTPException(400, "client_id mismatch")

    # Look up user
    user = _users.get(auth_code["sub"])
    if not user:
        raise HTTPException(400, f"User {auth_code['sub']} no longer exists")

    now = int(time.time())

    # Create access token
    access_payload = {
        "sub": user["sub"],
        "email": user["email"],
        "name": user["name"],
        "iss": INTERNAL_BASE,
        "aud": client_id,
        "iat": now,
        "exp": now + 3600,
        "jti": str(uuid.uuid4()),
    }
    access_token = _create_jwt(access_payload)

    # Create ID token
    id_payload = {
        "sub": user["sub"],
        "email": user["email"],
        "name": user["name"],
        "iss": INTERNAL_BASE,
        "aud": client_id,
        "iat": now,
        "exp": now + 3600,
        "nonce": auth_code.get("nonce"),
    }
    id_token = _create_jwt(id_payload)

    # Store token for userinfo lookups
    _tokens[access_token] = {
        "sub": user["sub"],
        "email": user["email"],
        "name": user["name"],
    }

    return {
        "access_token": access_token,
        "id_token": id_token,
        "token_type": "Bearer",
        "expires_in": 3600,
    }


# ---------------------------------------------------------------------------
# Userinfo
# ---------------------------------------------------------------------------


def _extract_bearer_token(authorization: Optional[str]) -> str:
    """Extract token from Authorization header (case-insensitive Bearer prefix)."""
    if not authorization:
        raise HTTPException(401, "Missing Authorization header")
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Authorization header must use Bearer scheme")
    return authorization[7:]  # len("bearer ") == 7


@app.get("/userinfo")
async def userinfo(authorization: Optional[str] = Header(None)):
    """Return {sub, email, name} from access token."""
    token_str = _extract_bearer_token(authorization)

    user = _tokens.get(token_str)
    if not user:
        raise HTTPException(401, "Invalid or expired token")

    return {
        "sub": user["sub"],
        "email": user["email"],
        "name": user["name"],
    }


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Admin API (for seed script)
# ---------------------------------------------------------------------------


@app.get("/api/users")
async def list_users():
    """List all registered users."""
    return list(_users.values())


@app.post("/api/users")
async def register_user(request: Request):
    """Register a user. Body: {sub, email, name}."""
    body = await request.json()
    sub = body.get("sub")
    if not sub:
        raise HTTPException(400, "sub is required")

    user = {
        "sub": sub,
        "email": body.get("email", f"{sub}@example.com"),
        "name": body.get("name", sub),
    }
    _users[sub] = user
    return user


@app.delete("/api/users/{sub}")
async def delete_user(sub: str):
    """Remove a user by sub."""
    if sub not in _users:
        raise HTTPException(404, f"User {sub} not found")
    del _users[sub]
    return {"deleted": sub}


@app.put("/api/clients/{client_id}/redirect_uris")
async def update_redirect_uris(client_id: str, request: Request):
    """Update allowed redirect URIs for a client. Body: {redirect_uris: [...]}."""
    if client_id not in _clients:
        _clients[client_id] = {"redirect_uris": []}

    body = await request.json()
    _clients[client_id]["redirect_uris"] = body.get("redirect_uris", [])
    return _clients[client_id]
