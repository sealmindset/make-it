// PUT /api/roles/:id/permissions -- Update role's permission assignments

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  await requirePermission("roles", "edit");
  const { id } = await params;

  const body = await request.json();
  const { permission_ids } = body as { permission_ids: string[] };

  // Replace all role permissions atomically
  await prisma.$transaction([
    prisma.rolePermission.deleteMany({ where: { roleId: id } }),
    prisma.rolePermission.createMany({
      data: permission_ids.map((permId) => ({
        roleId: id,
        permissionId: permId,
      })),
    }),
  ]);

  return NextResponse.json({ message: "Permissions updated" });
}
