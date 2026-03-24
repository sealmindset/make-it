// GET /api/users/directory?q=<search> -- Search OIDC directory for user provisioning

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";

export async function GET(request: NextRequest) {
  await requirePermission("users", "create");

  const q = request.nextUrl.searchParams.get("q");
  if (!q || q.length < 2) {
    return NextResponse.json([]);
  }

  // In local dev, search mock-oidc users via its API
  // In production, this would search the OIDC provider's directory (e.g., Microsoft Graph)
  const oidcIssuerUrl = process.env.OIDC_ISSUER_URL || "http://localhost:[MOCK_OIDC_PORT]";

  try {
    const resp = await fetch(`${oidcIssuerUrl}/api/users`);
    if (!resp.ok) return NextResponse.json([]);

    const users = await resp.json();
    const filtered = users
      .filter(
        (u: { name: string; email: string }) =>
          u.name.toLowerCase().includes(q.toLowerCase()) ||
          u.email.toLowerCase().includes(q.toLowerCase()),
      )
      .map((u: { sub: string; email: string; name: string }) => ({
        oidc_subject: u.sub,
        email: u.email,
        display_name: u.name,
      }));

    return NextResponse.json(filtered);
  } catch {
    return NextResponse.json([]);
  }
}
