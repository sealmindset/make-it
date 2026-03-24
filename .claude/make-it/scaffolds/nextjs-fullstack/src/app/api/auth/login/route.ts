// =============================================================================
// GET /api/auth/login -- Redirect to OIDC provider
// =============================================================================
// Key pattern: Next.js 16 Set-Cookie workaround.
// Next.js 16 strips Set-Cookie headers from redirect responses (307/302).
// So we return a 200 HTML page that:
//   1. Sets the OIDC state cookie via Set-Cookie header
//   2. Redirects via meta-refresh + JS fallback
//
// OIDC state parameter per RFC 6749 Section 10.12:
//   Login generates random state, stores in httpOnly cookie, passes to
//   authorization URL. Callback validates the match to prevent CSRF.
// =============================================================================

import { NextResponse } from "next/server";
import { getAuthorizationUrl } from "@/lib/auth";

export async function GET() {
  // Generate random state for CSRF protection
  const state = crypto.randomUUID();

  // Build OIDC authorization URL
  const authUrl = await getAuthorizationUrl(state);

  // Return HTML page that sets state cookie then redirects
  // This works around Next.js 16 stripping Set-Cookie from redirects
  const html = `<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0;url=${authUrl}">
</head>
<body>
  <p>Redirecting to sign in...</p>
  <script>window.location.href="${authUrl}";</script>
</body>
</html>`;

  const response = new NextResponse(html, {
    status: 200,
    headers: { "Content-Type": "text/html" },
  });

  // Set state in httpOnly cookie for callback validation
  response.cookies.set("oidc_state", state, {
    httpOnly: true,
    sameSite: "lax",
    secure: (process.env.NEXTAUTH_URL || "").startsWith("https"),
    path: "/",
    maxAge: 600, // 10 minutes
  });

  return response;
}
