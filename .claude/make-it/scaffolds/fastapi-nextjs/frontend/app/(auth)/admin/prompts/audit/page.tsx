"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { apiGet } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatRelative, formatDateTime } from "@/lib/utils";
import type { PromptAuditLogEntry } from "@/lib/types";

const actionOptions = [
  "created",
  "updated",
  "version_created",
  "activated",
  "deactivated",
  "locked",
  "unlocked",
  "tested",
  "restored",
];

const actionColors: Record<string, string> = {
  created: "var(--success)",
  updated: "var(--primary)",
  version_created: "var(--primary)",
  activated: "var(--success)",
  deactivated: "var(--muted-foreground)",
  locked: "var(--warning)",
  unlocked: "var(--success)",
  tested: "var(--primary)",
  restored: "var(--warning)",
};

export default function PromptAuditPage() {
  const router = useRouter();
  const { hasPermission } = useAuth();

  const [entries, setEntries] = useState<PromptAuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionFilter, setActionFilter] = useState("");
  const [slugFilter, setSlugFilter] = useState("");

  const fetchData = useCallback(async () => {
    try {
      const params = new URLSearchParams();
      if (actionFilter) params.set("action", actionFilter);
      if (slugFilter) params.set("prompt_slug", slugFilter);
      params.set("limit", "100");
      const qs = params.toString();
      const data = await apiGet<PromptAuditLogEntry[]>(
        `/admin/prompts/audit${qs ? `?${qs}` : ""}`
      );
      setEntries(data);
    } catch (err) {
      console.error("Failed to load audit log:", err);
    } finally {
      setLoading(false);
    }
  }, [actionFilter, slugFilter]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

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
        <h1 className="text-2xl font-bold tracking-tight">Audit Log</h1>
        <p style={{ color: "var(--muted-foreground)" }}>
          Complete history of all changes to AI instructions.
        </p>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        <select
          value={actionFilter}
          onChange={(e) => setActionFilter(e.target.value)}
          className="rounded-md border px-3 py-2 text-sm"
          style={{
            borderColor: "var(--input)",
            backgroundColor: "var(--background)",
            color: "var(--foreground)",
          }}
        >
          <option value="">All actions</option>
          {actionOptions.map((a) => (
            <option key={a} value={a}>
              {a.replace(/_/g, " ")}
            </option>
          ))}
        </select>
        <input
          type="text"
          value={slugFilter}
          onChange={(e) => setSlugFilter(e.target.value)}
          placeholder="Filter by instruction name..."
          className="rounded-md border px-3 py-2 text-sm"
          style={{
            borderColor: "var(--input)",
            backgroundColor: "var(--background)",
            color: "var(--foreground)",
          }}
        />
      </div>

      {/* Timeline */}
      {entries.length === 0 ? (
        <div
          className="rounded-xl border p-12 text-center"
          style={{
            backgroundColor: "var(--card)",
            borderColor: "var(--border)",
          }}
        >
          <p style={{ color: "var(--muted-foreground)" }}>
            No audit entries match your filters.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {entries.map((entry) => {
            const color = actionColors[entry.action] || "var(--muted-foreground)";
            return (
              <div
                key={entry.id}
                className="flex items-center gap-4 rounded-lg border px-4 py-3"
                style={{
                  backgroundColor: "var(--card)",
                  borderColor: "var(--border)",
                }}
              >
                {/* Action badge */}
                <span
                  className="inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize"
                  style={{
                    backgroundColor: `color-mix(in oklch, ${color} 15%, transparent)`,
                    color,
                  }}
                >
                  {entry.action.replace(/_/g, " ")}
                </span>

                {/* Prompt slug as link */}
                {entry.prompt_slug ? (
                  <button
                    onClick={() =>
                      router.push(`/admin/prompts/${entry.prompt_slug}`)
                    }
                    className="text-sm font-medium truncate transition-colors"
                    style={{ color: "var(--primary)" }}
                  >
                    {entry.prompt_slug}
                  </button>
                ) : (
                  <span
                    className="text-sm truncate"
                    style={{ color: "var(--muted-foreground)" }}
                  >
                    (deleted)
                  </span>
                )}

                {/* Version */}
                {entry.version != null && (
                  <span
                    className="shrink-0 text-xs"
                    style={{ color: "var(--muted-foreground)" }}
                  >
                    v{entry.version}
                  </span>
                )}

                {/* Spacer */}
                <div className="flex-1" />

                {/* User */}
                <span
                  className="shrink-0 text-xs truncate max-w-[150px]"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  {entry.user_email || "System"}
                </span>

                {/* Time */}
                <span
                  className="shrink-0 text-xs"
                  style={{ color: "var(--muted-foreground)" }}
                  title={formatDateTime(entry.created_at)}
                >
                  {formatRelative(entry.created_at)}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
