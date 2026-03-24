// GET /api/admin/settings/:key/reveal -- Reveal actual value of sensitive setting

import { NextRequest, NextResponse } from "next/server";
import { requirePermission } from "@/lib/auth";
import { prisma } from "@/lib/db";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ key: string }> },
) {
  await requirePermission("app_settings", "edit");
  const { key } = await params;

  const setting = await prisma.appSetting.findUnique({ where: { key } });
  if (!setting) {
    return NextResponse.json(
      { error: `Setting '${key}' not found` },
      { status: 404 },
    );
  }

  return NextResponse.json({ key: setting.key, value: setting.value });
}
