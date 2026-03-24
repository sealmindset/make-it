// =============================================================================
// /api/admin/settings -- Application settings management
// =============================================================================

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

function maskSensitive(value: string | null, isSensitive: boolean): string | null {
  if (!isSensitive || !value) return value;
  return "********";
}

// GET /api/admin/settings -- List all settings (sensitive values masked)
export async function GET() {
  await requirePermission("app_settings", "view");

  const settings = await prisma.appSetting.findMany({
    orderBy: [{ groupName: "asc" }, { key: "asc" }],
  });

  return NextResponse.json(
    settings.map((s) => ({
      id: s.id,
      key: s.key,
      value: maskSensitive(s.value, s.isSensitive),
      group_name: s.groupName,
      display_name: s.displayName,
      description: s.description,
      value_type: s.valueType,
      is_sensitive: s.isSensitive,
      requires_restart: s.requiresRestart,
      updated_by: s.updatedBy,
    })),
  );
}

// PUT /api/admin/settings -- Bulk update settings
export async function PUT(request: NextRequest) {
  const user = await requirePermission("app_settings", "edit");

  const body = await request.json();
  const { settings: updates } = body as {
    settings: { key: string; value: string }[];
  };

  const results = [];
  for (const item of updates) {
    const setting = await prisma.appSetting.findUnique({
      where: { key: item.key },
    });
    if (!setting) continue;

    const oldValue = setting.value;

    await prisma.appSetting.update({
      where: { key: item.key },
      data: {
        value: item.value,
        updatedBy: user.email,
      },
    });

    await prisma.appSettingAuditLog.create({
      data: {
        settingId: setting.id,
        oldValue: setting.isSensitive ? "********" : oldValue,
        newValue: setting.isSensitive ? "********" : item.value,
        changedBy: user.email,
      },
    });

    results.push(setting);
  }

  return NextResponse.json({ message: `Updated ${results.length} settings` });
}
