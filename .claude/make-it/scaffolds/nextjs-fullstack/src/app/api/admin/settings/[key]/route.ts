// /api/admin/settings/[key] -- Single setting operations

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

// PUT /api/admin/settings/:key -- Update a single setting
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ key: string }> },
) {
  const user = await requirePermission("app_settings", "edit");
  const { key } = await params;

  const body = await request.json();
  const { value } = body;

  const setting = await prisma.appSetting.findUnique({ where: { key } });
  if (!setting) {
    return NextResponse.json(
      { error: `Setting '${key}' not found` },
      { status: 404 },
    );
  }

  const oldValue = setting.value;

  const updated = await prisma.appSetting.update({
    where: { key },
    data: { value, updatedBy: user.email },
  });

  await prisma.appSettingAuditLog.create({
    data: {
      settingId: setting.id,
      oldValue: setting.isSensitive ? "********" : oldValue,
      newValue: setting.isSensitive ? "********" : value,
      changedBy: user.email,
    },
  });

  return NextResponse.json({
    id: updated.id,
    key: updated.key,
    value: updated.isSensitive ? "********" : updated.value,
    group_name: updated.groupName,
    display_name: updated.displayName,
    description: updated.description,
    value_type: updated.valueType,
    is_sensitive: updated.isSensitive,
    requires_restart: updated.requiresRestart,
    updated_by: updated.updatedBy,
  });
}
