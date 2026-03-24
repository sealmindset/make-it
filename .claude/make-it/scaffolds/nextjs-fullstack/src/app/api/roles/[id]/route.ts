// /api/roles/[id] -- Single role operations

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

// DELETE /api/roles/:id -- Delete a custom role
export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  await requirePermission("roles", "delete");
  const { id } = await params;

  const role = await prisma.role.findUnique({ where: { id } });
  if (!role) {
    return NextResponse.json({ error: "Role not found" }, { status: 404 });
  }
  if (role.isSystem) {
    return NextResponse.json(
      { error: "Cannot delete system roles" },
      { status: 400 },
    );
  }

  await prisma.role.delete({ where: { id } });
  return new NextResponse(null, { status: 204 });
}
