// GET /api/admin/settings/audit-log -- List setting change audit logs

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET(request: NextRequest) {
  await requirePermission("app_settings", "view");

  const limit = parseInt(
    request.nextUrl.searchParams.get("limit") || "100",
    10,
  );

  const logs = await prisma.appSettingAuditLog.findMany({
    orderBy: { createdAt: "desc" },
    take: limit,
    include: { setting: true },
  });

  return NextResponse.json(
    logs.map((l) => ({
      id: l.id,
      setting_key: l.setting.key,
      old_value: l.oldValue,
      new_value: l.newValue,
      changed_by: l.changedBy,
      created_at: l.createdAt.toISOString(),
    })),
  );
}
