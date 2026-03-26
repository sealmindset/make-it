"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowLeft,
  Sparkles,
  CheckCircle2,
  Layers,
  ClipboardList,
} from "lucide-react";
import { apiGet } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatRelative } from "@/lib/utils";
import type {
  ManagedPromptListItem,
  PromptStats,
  PromptAuditLogEntry,
} from "@/lib/types";

export default function PromptAnalyticsPage() {
  const router = useRouter();
  const { hasPermission } = useAuth();

  const [stats, setStats] = useState<PromptStats | null>(null);
  const [prompts, setPrompts] = useState<ManagedPromptListItem[]>([]);
  const [recentChanges, setRecentChanges] = useState<PromptAuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchData = useCallback(async () => {
    try {
      const [s, p, a] = await Promise.all([
        apiGet<PromptStats>("/admin/prompts/stats"),
        apiGet<ManagedPromptListItem[]>("/admin/prompts/"),
        apiGet<PromptAuditLogEntry[]>("/admin/prompts/audit?limit=10"),
      ]);
      setStats(s);
      setPrompts(p);
      setRecentChanges(a);
    } catch (err) {
      console.error("Failed to load analytics:", err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  // Group prompts by category
  const categoryBreakdown = prompts.reduce<Record<string, number>>(
    (acc, p) => {
      acc[p.category] = (acc[p.category] || 0) + 1;
      return acc;
    },
    {}
  );

  if (loading) {
    return (
      <div className="space-y-4">
        <div
          className="h-8 w-48 animate-pulse rounded"
          style={{ backgroundColor: "var(--muted)" }}
        />
        <div
          className="h-64 animate-pulse rounded-xl border"
          style={{
            backgroundColor: "var(--card)",
            borderColor: "var(--border)",
          }}
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <button
          onClick={() => router.push("/admin/prompts")}
          className="mb-2 inline-flex items-center gap-1 text-sm transition-colors"
          style={{ color: "var(--muted-foreground)" }}
        >
          <ArrowLeft className="h-4 w-4" />
          Back to AI Instructions
        </button>
        <h1 className="text-2xl font-bold tracking-tight">Analytics</h1>
        <p style={{ color: "var(--muted-foreground)" }}>
          Overview of your AI instructions usage and activity.
        </p>
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {[
            { icon: Sparkles, label: "Total", value: stats.total },
            {
              icon: CheckCircle2,
              label: "Active",
              value: stats.active,
              color: "var(--success)",
            },
            { icon: Layers, label: "Versions", value: stats.versions_count },
            {
              icon: ClipboardList,
              label: "Categories",
              value: stats.categories_count,
            },
          ].map((s) => (
            <div
              key={s.label}
              className="rounded-xl border p-4"
              style={{
                backgroundColor: "var(--card)",
                borderColor: "var(--border)",
              }}
            >
              <div className="flex items-center gap-3">
                <div
                  className="flex h-10 w-10 items-center justify-center rounded-lg"
                  style={{
                    backgroundColor: `color-mix(in oklch, ${s.color || "var(--primary)"} 12%, transparent)`,
                  }}
                >
                  <s.icon
                    className="h-5 w-5"
                    style={{ color: s.color || "var(--primary)" }}
                  />
                </div>
                <div>
                  <p className="text-2xl font-bold">{s.value}</p>
                  <p
                    className="text-xs font-medium"
                    style={{ color: "var(--muted-foreground)" }}
                  >
                    {s.label}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Category breakdown */}
        <div
          className="rounded-xl border p-5"
          style={{
            backgroundColor: "var(--card)",
            borderColor: "var(--border)",
          }}
        >
          <h3 className="text-sm font-semibold mb-4">By Category</h3>
          {Object.entries(categoryBreakdown).length === 0 ? (
            <p
              className="text-sm"
              style={{ color: "var(--muted-foreground)" }}
            >
              No data yet.
            </p>
          ) : (
            <div className="space-y-3">
              {Object.entries(categoryBreakdown)
                .sort(([, a], [, b]) => b - a)
                .map(([category, count]) => {
                  const maxCount = Math.max(
                    ...Object.values(categoryBreakdown)
                  );
                  const pct = maxCount > 0 ? (count / maxCount) * 100 : 0;
                  return (
                    <div key={category}>
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-sm font-medium capitalize">
                          {category}
                        </span>
                        <span
                          className="text-xs"
                          style={{ color: "var(--muted-foreground)" }}
                        >
                          {count}
                        </span>
                      </div>
                      <div
                        className="h-2 rounded-full"
                        style={{
                          backgroundColor:
                            "color-mix(in oklch, var(--primary) 15%, transparent)",
                        }}
                      >
                        <div
                          className="h-2 rounded-full transition-all"
                          style={{
                            width: `${pct}%`,
                            backgroundColor: "var(--primary)",
                          }}
                        />
                      </div>
                    </div>
                  );
                })}
            </div>
          )}
        </div>

        {/* Recent changes */}
        <div
          className="rounded-xl border p-5"
          style={{
            backgroundColor: "var(--card)",
            borderColor: "var(--border)",
          }}
        >
          <h3 className="text-sm font-semibold mb-4">Recent Changes</h3>
          {recentChanges.length === 0 ? (
            <p
              className="text-sm"
              style={{ color: "var(--muted-foreground)" }}
            >
              No changes yet.
            </p>
          ) : (
            <div className="space-y-2">
              {recentChanges.map((entry) => (
                <div
                  key={entry.id}
                  className="flex items-center gap-3 rounded-lg px-3 py-2"
                  style={{
                    backgroundColor:
                      "color-mix(in oklch, var(--foreground) 3%, transparent)",
                  }}
                >
                  <span
                    className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize"
                    style={{
                      backgroundColor:
                        "color-mix(in oklch, var(--primary) 15%, transparent)",
                      color: "var(--primary)",
                    }}
                  >
                    {entry.action.replace(/_/g, " ")}
                  </span>
                  <span className="text-sm font-medium truncate">
                    {entry.prompt_slug}
                  </span>
                  <span
                    className="ml-auto shrink-0 text-xs"
                    style={{ color: "var(--muted-foreground)" }}
                  >
                    {formatRelative(entry.created_at)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
