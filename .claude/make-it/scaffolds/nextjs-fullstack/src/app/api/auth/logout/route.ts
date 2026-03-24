// POST /api/auth/logout -- Clear the token cookie (must be POST, not GET)

import { NextResponse } from "next/server";

export async function POST() {
  const response = NextResponse.json({ message: "Logged out successfully" });
  response.cookies.delete("token");
  return response;
}
