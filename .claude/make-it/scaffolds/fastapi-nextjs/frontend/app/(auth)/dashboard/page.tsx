"use client";

import { useEffect, useState } from "react";
import { apiGet } from "@/lib/api";
import { useAuth } from "@/lib/auth";

interface DashboardStats {
  // [DASHBOARD_STATS] -- app-specific stat fields
  [key: string]: number | string;
}

export default function DashboardPage() {
  const { authMe } = useAuth();
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiGet<DashboardStats>("/dashboard")
      .then(setStats)
      .catch((err) => console.error("Failed to load dashboard:", err))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Dashboard</h1>
        <p style={{ color: "var(--muted-foreground)" }}>
          Welcome to [APP_NAME]{authMe?.name ? `, ${authMe.name}` : ""}.
        </p>
      </div>

      {/* Stats grid */}
      {loading ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="h-28 animate-pulse rounded-xl border"
              style={{
                backgroundColor: "var(--card)",
                borderColor: "var(--border)",
              }}
            />
          ))}
        </div>
      ) : stats ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {/* [DASHBOARD_CONTENT] -- app-specific dashboard widgets inserted here */}
          {Object.entries(stats).map(([key, value]) => (
            <div
              key={key}
              className="rounded-xl border p-6"
              style={{
                backgroundColor: "var(--card)",
                borderColor: "var(--border)",
                color: "var(--card-foreground)",
              }}
            >
              <p
                className="text-sm font-medium capitalize"
                style={{ color: "var(--muted-foreground)" }}
              >
                {key.replace(/_/g, " ")}
              </p>
              <p className="mt-2 text-2xl font-bold">{value}</p>
            </div>
          ))}
        </div>
      ) : (
        <p style={{ color: "var(--muted-foreground)" }}>
          Failed to load dashboard data.
        </p>
      )}
    </div>
  );
}
