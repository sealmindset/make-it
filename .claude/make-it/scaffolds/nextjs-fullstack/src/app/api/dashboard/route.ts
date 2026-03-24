// GET /api/dashboard -- Dashboard stats

import { NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET() {
  await requirePermission("dashboard", "view");

  const [totalUsers, activeUsers, totalRoles] = await Promise.all([
    prisma.user.count(),
    prisma.user.count({ where: { isActive: true } }),
    prisma.role.count(),
  ]);

  return NextResponse.json({
    total_users: totalUsers,
    active_users: activeUsers,
    total_roles: totalRoles,
    // [DASHBOARD_STATS] -- app-specific stats added here
  });
}
