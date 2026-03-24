// /api/users/[id] -- Single user operations

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

// PUT /api/users/:id -- Update user (role, active status)
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  await requirePermission("users", "edit");
  const { id } = await params;

  const body = await request.json();
  const data: Record<string, unknown> = {};
  if (body.role_id !== undefined) data.roleId = body.role_id;
  if (body.is_active !== undefined) data.isActive = body.is_active;

  const user = await prisma.user.update({
    where: { id },
    data,
    include: { role: true },
  });

  return NextResponse.json({
    id: user.id,
    oidc_subject: user.oidcSubject,
    email: user.email,
    display_name: user.displayName,
    is_active: user.isActive,
    role_id: user.roleId,
    role_name: user.role.name,
    created_at: user.createdAt.toISOString(),
    updated_at: user.updatedAt.toISOString(),
  });
}

// DELETE /api/users/:id -- Delete user
export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  await requirePermission("users", "delete");
  const { id } = await params;

  await prisma.user.delete({ where: { id } });
  return new NextResponse(null, { status: 204 });
}
