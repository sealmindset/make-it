// =============================================================================
// GET /api/auth/callback -- OIDC callback handler
// =============================================================================
// Exchanges authorization code for tokens, looks up user in database,
// signs JWT, sets httpOnly cookie, and redirects to dashboard.
//
// Key patterns:
//   - OIDC state validation (RFC 6749 Section 10.12)
//   - Cookie Secure from NEXTAUTH_URL protocol (NOT NODE_ENV)
//   - Redirect to NEXTAUTH_URL/dashboard (NOT request.url)
//   - Next.js 16 Set-Cookie workaround (HTML page, not redirect)
// =============================================================================

import { NextRequest, NextResponse } from "next/server";
import { exchangeCode, signJwt, getCookieOptions } from "@/lib/auth";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const state = searchParams.get("state");

  if (!code) {
    return NextResponse.json(
      { error: "Missing authorization code" },
      { status: 400 },
    );
  }

  // Validate OIDC state parameter
  const storedState = request.cookies.get("oidc_state")?.value;
  if (!state || !storedState || state !== storedState) {
    return NextResponse.json(
      { error: "Invalid state parameter. Please try logging in again." },
      { status: 400 },
    );
  }

  try {
    // Exchange code for user info, look up in database
    const authMe = await exchangeCode(code);

    // Sign JWT with user info + permissions
    const token = await signJwt(authMe);

    // Build redirect URL from config (NOT request.url)
    const nextauthUrl = process.env.NEXTAUTH_URL || "http://localhost:[APP_PORT]";
    const dashboardUrl = `${nextauthUrl}/dashboard`;

    // Next.js 16 strips Set-Cookie from redirect responses.
    // Return HTML page with Set-Cookie header + meta-refresh redirect.
    const html = `<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0;url=${dashboardUrl}">
</head>
<body>
  <p>Signing you in...</p>
  <script>window.location.href="${dashboardUrl}";</script>
</body>
</html>`;

    const cookieOpts = getCookieOptions();

    const response = new NextResponse(html, {
      status: 200,
      headers: { "Content-Type": "text/html" },
    });

    // Set auth JWT cookie
    response.cookies.set(cookieOpts.name, token, {
      httpOnly: cookieOpts.httpOnly,
      sameSite: cookieOpts.sameSite,
      secure: cookieOpts.secure,
      path: cookieOpts.path,
      maxAge: cookieOpts.maxAge,
    });

    // Clear the OIDC state cookie
    response.cookies.delete("oidc_state");

    return response;
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Authentication failed";
    return NextResponse.json({ error: message }, { status: 403 });
  }
}
