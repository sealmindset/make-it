"use client";

import { useOnlineStatus } from "@/lib/use-online-status";
import { WifiOff } from "lucide-react";

export function OfflineIndicator() {
  const isOnline = useOnlineStatus();

  if (isOnline) return null;

  return (
    <div
      role="status"
      className="flex items-center gap-2 rounded-md bg-destructive/10 px-3 py-1.5 text-xs font-medium text-destructive"
    >
      <WifiOff className="h-3.5 w-3.5" />
      <span>You&apos;re offline. Some features may be unavailable.</span>
    </div>
  );
}
