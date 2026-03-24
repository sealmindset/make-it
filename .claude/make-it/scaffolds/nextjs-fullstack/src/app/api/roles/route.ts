// /api/roles -- Role management API routes

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

// GET /api/roles -- List all roles (optionally with permissions)
export async function GET(request: NextRequest) {
  await requirePermission("roles", "view");

  const includePerms =
    request.nextUrl.searchParams.get("include_permissions") === "true";

  const roles = await prisma.role.findMany({
    include: includePerms
      ? { permissions: { include: { permission: true } } }
      : undefined,
    orderBy: { name: "asc" },
  });

  return NextResponse.json(
    roles.map((r) => ({
      id: r.id,
      name: r.name,
      description: r.description,
      is_system: r.isSystem,
      created_at: r.createdAt.toISOString(),
      updated_at: r.updatedAt.toISOString(),
      ...(includePerms && {
        permissions: r.permissions?.map((rp) => ({
          id: rp.permission.id,
          resource: rp.permission.resource,
          action: rp.permission.action,
          description: rp.permission.description,
        })),
      }),
    })),
  );
}

// POST /api/roles -- Create a custom role
export async function POST(request: NextRequest) {
  await requirePermission("roles", "create");

  const body = await request.json();
  const { name, description, permission_ids } = body;

  if (!name) {
    return NextResponse.json(
      { error: "Name is required" },
      { status: 400 },
    );
  }

  const role = await prisma.role.create({
    data: {
      name,
      description: description || null,
      isSystem: false,
      permissions: {
        create: (permission_ids || []).map((permId: string) => ({
          permissionId: permId,
        })),
      },
    },
    include: {
      permissions: { include: { permission: true } },
    },
  });

  return NextResponse.json(
    {
      id: role.id,
      name: role.name,
      description: role.description,
      is_system: role.isSystem,
      created_at: role.createdAt.toISOString(),
      updated_at: role.updatedAt.toISOString(),
      permissions: role.permissions.map((rp) => ({
        id: rp.permission.id,
        resource: rp.permission.resource,
        action: rp.permission.action,
        description: rp.permission.description,
      })),
    },
    { status: 201 },
  );
}
