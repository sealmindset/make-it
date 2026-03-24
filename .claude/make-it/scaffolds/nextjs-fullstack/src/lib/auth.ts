// =============================================================================
// Server-side Auth -- JWT signing, cookie management, getCurrentUser
// =============================================================================
// Key patterns encoded:
//   - ENFORCE_SECRETS: Use dedicated env var, NOT NODE_ENV (always "production" in Docker)
//   - Runtime-deferred assertions: validate secrets in functions, not at module scope
//     (Next.js evaluates modules during build when env vars aren't available)
//   - Cookie Secure from URL protocol: secure = NEXTAUTH_URL.startsWith("https")
//   - OIDC state parameter per RFC 6749 Section 10.12
// =============================================================================

import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import { prisma } from "./db";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface AuthMe {
  sub: string;
  email: string;
  name: string;
  role_id: string;
  role_name: string;
  permissions: string[];
}

// ---------------------------------------------------------------------------
// Config -- runtime-deferred (never accessed at module scope)
// ---------------------------------------------------------------------------

function getConfig() {
  const jwtSecret = process.env.JWT_SECRET;
  const oidcIssuerUrl = process.env.OIDC_ISSUER_URL;
  const oidcClientId = process.env.OIDC_CLIENT_ID;
  const oidcClientSecret = process.env.OIDC_CLIENT_SECRET;
  const nextauthUrl = process.env.NEXTAUTH_URL;

  // ENFORCE_SECRETS gates fatal assertions. Docker always builds with
  // NODE_ENV=production, so we need a separate flag for this.
  if (process.env.ENFORCE_SECRETS === "true") {
    if (!jwtSecret) throw new Error("JWT_SECRET is required");
    if (!oidcIssuerUrl) throw new Error("OIDC_ISSUER_URL is required");
    if (!oidcClientId) throw new Error("OIDC_CLIENT_ID is required");
    if (!oidcClientSecret) throw new Error("OIDC_CLIENT_SECRET is required");
    if (!nextauthUrl) throw new Error("NEXTAUTH_URL is required");
  }

  return {
    jwtSecret: jwtSecret || "dev-secret-change-me",
    oidcIssuerUrl: oidcIssuerUrl || "http://localhost:[MOCK_OIDC_PORT]",
    oidcClientId: oidcClientId || "mock-oidc-client",
    oidcClientSecret: oidcClientSecret || "mock-oidc-secret",
    nextauthUrl: nextauthUrl || "http://localhost:[APP_PORT]",
  };
}

// ---------------------------------------------------------------------------
// JWT helpers
// ---------------------------------------------------------------------------

const JWT_EXPIRY = "8h";
const COOKIE_NAME = "token";

function getSecretKey() {
  return new TextEncoder().encode(getConfig().jwtSecret);
}

export async function signJwt(payload: AuthMe): Promise<string> {
  return new SignJWT({ ...payload })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime(JWT_EXPIRY)
    .sign(getSecretKey());
}

export async function verifyJwt(token: string): Promise<AuthMe> {
  const { payload } = await jwtVerify(token, getSecretKey());
  return payload as unknown as AuthMe;
}

// ---------------------------------------------------------------------------
// Cookie helpers
// ---------------------------------------------------------------------------

export function getCookieOptions() {
  const config = getConfig();
  return {
    name: COOKIE_NAME,
    httpOnly: true,
    sameSite: "lax" as const,
    // Secure from URL protocol, NOT NODE_ENV
    secure: config.nextauthUrl.startsWith("https"),
    path: "/",
    maxAge: 8 * 60 * 60, // 8 hours in seconds
  };
}

// ---------------------------------------------------------------------------
// Get current user from JWT cookie (server-side)
// ---------------------------------------------------------------------------

export async function getCurrentUser(): Promise<AuthMe | null> {
  try {
    const cookieStore = await cookies();
    const token = cookieStore.get(COOKIE_NAME);
    if (!token?.value) return null;
    return await verifyJwt(token.value);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Require permission -- throws 403 if user lacks permission
// ---------------------------------------------------------------------------

export async function requirePermission(
  resource: string,
  action: string,
): Promise<AuthMe> {
  const user = await getCurrentUser();
  if (!user) {
    throw new Response("Unauthorized", { status: 401 });
  }
  if (!user.permissions.includes(`${resource}.${action}`)) {
    throw new Response("Forbidden", { status: 403 });
  }
  return user;
}

// ---------------------------------------------------------------------------
// OIDC helpers
// ---------------------------------------------------------------------------

interface OidcDiscovery {
  authorization_endpoint: string;
  token_endpoint: string;
  userinfo_endpoint: string;
}

function isTrustedUrl(url: string, issuerUrl: string): boolean {
  try {
    const parsed = new URL(url);
    const issuer = new URL(issuerUrl);
    return (
      (parsed.protocol === "http:" || parsed.protocol === "https:") &&
      parsed.hostname === issuer.hostname
    );
  } catch {
    return false;
  }
}

export async function getOidcDiscovery(): Promise<OidcDiscovery> {
  const config = getConfig();
  const resp = await fetch(
    `${config.oidcIssuerUrl}/.well-known/openid-configuration`,
  );
  if (!resp.ok) {
    throw new Error(`OIDC discovery failed: ${resp.status}`);
  }
  return resp.json();
}

export async function getAuthorizationUrl(state: string): Promise<string> {
  const config = getConfig();
  const discovery = await getOidcDiscovery();

  if (!isTrustedUrl(discovery.authorization_endpoint, config.oidcIssuerUrl)) {
    throw new Error("OIDC discovery returned untrusted authorization endpoint");
  }

  const params = new URLSearchParams({
    client_id: config.oidcClientId,
    response_type: "code",
    scope: "openid email profile",
    redirect_uri: `${config.nextauthUrl}/api/auth/callback`,
    state,
  });

  return `${discovery.authorization_endpoint}?${params.toString()}`;
}

export async function exchangeCode(code: string): Promise<AuthMe> {
  const config = getConfig();
  const discovery = await getOidcDiscovery();

  if (!isTrustedUrl(discovery.token_endpoint, config.oidcIssuerUrl)) {
    throw new Error("OIDC discovery returned untrusted token endpoint");
  }
  if (!isTrustedUrl(discovery.userinfo_endpoint, config.oidcIssuerUrl)) {
    throw new Error("OIDC discovery returned untrusted userinfo endpoint");
  }

  // Exchange code for tokens
  const tokenResp = await fetch(discovery.token_endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: `${config.nextauthUrl}/api/auth/callback`,
      client_id: config.oidcClientId,
      client_secret: config.oidcClientSecret,
    }),
  });

  if (!tokenResp.ok) {
    throw new Error(`Token exchange failed: ${tokenResp.status}`);
  }

  const tokens = await tokenResp.json();

  // Get user info from OIDC provider
  const userinfoResp = await fetch(discovery.userinfo_endpoint, {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
  });

  if (!userinfoResp.ok) {
    throw new Error(`Userinfo failed: ${userinfoResp.status}`);
  }

  const userinfo = await userinfoResp.json();
  const oidcSubject = userinfo.sub;

  // Look up user by oidc_subject in database (NOT email)
  const dbUser = await prisma.user.findUnique({
    where: { oidcSubject: oidcSubject },
    include: {
      role: {
        include: {
          permissions: {
            include: { permission: true },
          },
        },
      },
    },
  });

  if (!dbUser) {
    throw new Error("User not provisioned. Contact your administrator.");
  }

  if (!dbUser.isActive) {
    throw new Error("Account deactivated. Contact your administrator.");
  }

  // Build flat AuthMe payload
  const permissions = dbUser.role.permissions.map(
    (rp) => `${rp.permission.resource}.${rp.permission.action}`,
  );

  return {
    sub: dbUser.oidcSubject,
    email: dbUser.email,
    name: dbUser.displayName,
    role_id: dbUser.roleId,
    role_name: dbUser.role.name,
    permissions,
  };
}
