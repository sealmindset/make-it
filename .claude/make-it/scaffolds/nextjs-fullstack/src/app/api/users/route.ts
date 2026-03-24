// =============================================================================
// /api/users -- User management API routes
// =============================================================================

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

// GET /api/users -- List all users
export async function GET() {
  await requirePermission("users", "view");

  const users = await prisma.user.findMany({
    include: { role: true },
    orderBy: { displayName: "asc" },
  });

  return NextResponse.json(
    users.map((u) => ({
      id: u.id,
      oidc_subject: u.oidcSubject,
      email: u.email,
      display_name: u.displayName,
      is_active: u.isActive,
      role_id: u.roleId,
      role_name: u.role.name,
      created_at: u.createdAt.toISOString(),
      updated_at: u.updatedAt.toISOString(),
    })),
  );
}

// POST /api/users -- Provision a new user from OIDC directory
export async function POST(request: NextRequest) {
  await requirePermission("users", "create");

  const body = await request.json();
  const { oidc_subject, email, display_name, role_id } = body;

  if (!oidc_subject || !email || !display_name || !role_id) {
    return NextResponse.json(
      { error: "Missing required fields" },
      { status: 400 },
    );
  }

  const user = await prisma.user.create({
    data: {
      oidcSubject: oidc_subject,
      email,
      displayName: display_name,
      roleId: role_id,
    },
    include: { role: true },
  });

  return NextResponse.json(
    {
      id: user.id,
      oidc_subject: user.oidcSubject,
      email: user.email,
      display_name: user.displayName,
      is_active: user.isActive,
      role_id: user.roleId,
      role_name: user.role.name,
      created_at: user.createdAt.toISOString(),
      updated_at: user.updatedAt.toISOString(),
    },
    { status: 201 },
  );
}
