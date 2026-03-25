"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { apiGet, apiDelete } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatDateTime } from "@/lib/utils";
import {
  Activity, RefreshCw, Trash2, Filter, Search,
  ArrowDownCircle, ArrowUpCircle, Clock, AlertCircle,
} from "lucide-react";

interface LogEvent {
  timestamp: string;
  type: string;
  method: string;
  path: string;
  url: string | null;
  status: number | null;
  duration_ms: number | null;
  service: string | null;
  user_sub: string | null;
  user_email: string | null;
  ip: string | null;
  user_agent: string | null;
  error: string | null;
}

interface LogStats {
  buffer_size: number;
  buffer_used: number;
  total_received: number;
  total_evicted: number;
  recent_errors: number;
  uptime_seconds: number;
  events_by_type: Record<string, number>;
  events_by_service: Record<string, number>;
  events_by_status: Record<string, number>;
}

export default function ActivityLogsPage() {
  const { hasPermission } = useAuth();
  const [events, setEvents] = useState<LogEvent[]>([]);
  const [stats, setStats] = useState<LogStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const [typeFilter, setTypeFilter] = useState<string>("");
  const [methodFilter, setMethodFilter] = useState<string>("");
  const [searchQuery, setSearchQuery] = useState<string>("");
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  const canDelete = hasPermission("admin.logs", "delete");

  const fetchData = useCallback(async () => {
    try {
      const params = new URLSearchParams();
      if (typeFilter) params.set("type", typeFilter);
      if (methodFilter) params.set("method", methodFilter);
      if (searchQuery.trim()) params.set("q", searchQuery.trim());
      params.set("limit", "200");

      const [eventsData, statsData] = await Promise.all([
        apiGet<LogEvent[]>(`/admin/logs/events?${params}`),
        apiGet<LogStats>("/admin/logs/stats"),
      ]);
      setEvents(eventsData);
      setStats(statsData);
    } catch (err) {
      console.error("Failed to load logs:", err);
    } finally {
      setLoading(false);
    }
  }, [typeFilter, methodFilter, searchQuery]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  useEffect(() => {
    if (autoRefresh) {
      intervalRef.current = setInterval(fetchData, 5000);
    } else if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [autoRefresh, fetchData]);

  const handleClear = async () => {
    if (!confirm("Clear all activity logs?")) return;
    try {
      await apiDelete("/admin/logs/events");
      fetchData();
    } catch (err) {
      console.error("Failed to clear logs:", err);
    }
  };

  const formatUptime = (seconds: number) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Activity Logs</h1>
          <p style={{ color: "var(--muted-foreground)" }}>
            Real-time API request and outbound call monitoring.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setAutoRefresh(!autoRefresh)}
            className={`inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm ${autoRefresh ? "font-medium" : ""}`}
            style={{
              borderColor: autoRefresh ? "var(--primary)" : "var(--input)",
              backgroundColor: autoRefresh ? "color-mix(in oklch, var(--primary) 10%, transparent)" : "var(--background)",
              color: autoRefresh ? "var(--primary)" : "var(--foreground)",
            }}
          >
            <RefreshCw className={`h-4 w-4 ${autoRefresh ? "animate-spin" : ""}`} />
            {autoRefresh ? "Auto-refresh ON" : "Auto-refresh"}
          </button>
          {canDelete && (
            <button
              onClick={handleClear}
              className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm"
              style={{ borderColor: "var(--destructive)", color: "var(--destructive)" }}
            >
              <Trash2 className="h-4 w-4" />
              Clear Buffer
            </button>
          )}
        </div>
      </div>

      {/* Stats cards */}
      {stats && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {[
            { label: "Buffer Usage", value: `${stats.buffer_used} / ${stats.buffer_size}`, icon: Activity, color: "var(--primary)" },
            { label: "Total Events", value: stats.total_received.toLocaleString(), icon: ArrowDownCircle, color: "var(--muted-foreground)" },
            { label: "Recent Errors", value: stats.recent_errors, icon: AlertCircle, color: stats.recent_errors > 0 ? "var(--destructive)" : "var(--success, var(--primary))" },
            { label: "Uptime", value: formatUptime(stats.uptime_seconds), icon: Clock, color: "var(--muted-foreground)" },
          ].map(({ label, value, icon: Icon, color }) => (
            <div
              key={label}
              className="rounded-xl border p-4"
              style={{ backgroundColor: "var(--card)", borderColor: "var(--border)" }}
            >
              <div className="flex items-center justify-between">
                <p className="text-xs font-medium" style={{ color: "var(--muted-foreground)" }}>{label}</p>
                <Icon className="h-4 w-4" style={{ color }} />
              </div>
              <p className="mt-1 text-xl font-bold">{value}</p>
            </div>
          ))}
        </div>
      )}

      {/* Status breakdown mini-bar (when data exists) */}
      {stats && Object.keys(stats.events_by_status).length > 0 && (
        <div className="flex items-center gap-4 text-xs" style={{ color: "var(--muted-foreground)" }}>
          <span className="font-medium">Status:</span>
          {(["2xx", "3xx", "4xx", "5xx"] as const).map((bucket) => {
            const count = stats.events_by_status[bucket] || 0;
            if (count === 0) return null;
            return (
              <span key={bucket} className="inline-flex items-center gap-1">
                <span
                  className="inline-block h-2 w-2 rounded-full"
                  style={{
                    backgroundColor:
                      bucket === "2xx" ? "var(--success, var(--primary))" :
                      bucket === "3xx" ? "var(--primary)" :
                      bucket === "4xx" ? "var(--warning, var(--destructive))" :
                      "var(--destructive)",
                  }}
                />
                {bucket}: {count}
              </span>
            );
          })}
          {Object.keys(stats.events_by_type).length > 0 && (
            <>
              <span className="font-medium">|</span>
              {Object.entries(stats.events_by_type).map(([t, c]) => (
                <span key={t}>{t}: {c}</span>
              ))}
            </>
          )}
        </div>
      )}

      {/* Filters */}
      <div className="flex items-center gap-3 flex-wrap">
        <Filter className="h-4 w-4" style={{ color: "var(--muted-foreground)" }} />
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="rounded-md border px-3 py-1.5 text-sm"
          style={{ borderColor: "var(--input)", backgroundColor: "var(--background)", color: "var(--foreground)" }}
        >
          <option value="">All Types</option>
          <option value="inbound">Inbound</option>
          <option value="outbound">Outbound</option>
        </select>
        <select
          value={methodFilter}
          onChange={(e) => setMethodFilter(e.target.value)}
          className="rounded-md border px-3 py-1.5 text-sm"
          style={{ borderColor: "var(--input)", backgroundColor: "var(--background)", color: "var(--foreground)" }}
        >
          <option value="">All Methods</option>
          <option value="GET">GET</option>
          <option value="POST">POST</option>
          <option value="PUT">PUT</option>
          <option value="DELETE">DELETE</option>
        </select>
        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2" style={{ color: "var(--muted-foreground)" }} />
          <input
            type="text"
            placeholder="Search path, email, service..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="rounded-md border pl-8 pr-3 py-1.5 text-sm w-64"
            style={{ borderColor: "var(--input)", backgroundColor: "var(--background)", color: "var(--foreground)" }}
          />
        </div>
        <button
          onClick={fetchData}
          className="rounded-md border px-3 py-1.5 text-sm"
          style={{ borderColor: "var(--input)", backgroundColor: "var(--background)" }}
        >
          Refresh
        </button>
      </div>

      {/* Events table */}
      <div className="rounded-md border overflow-x-auto" style={{ borderColor: "var(--border)" }}>
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b" style={{ borderColor: "var(--border)" }}>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Timestamp</th>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Type</th>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Method</th>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Path / URL</th>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Status</th>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Duration</th>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Service</th>
              <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>User</th>
            </tr>
          </thead>
          <tbody>
            {events.length === 0 ? (
              <tr>
                <td colSpan={8} className="h-24 text-center" style={{ color: "var(--muted-foreground)" }}>
                  {loading ? "Loading..." : "No events recorded yet."}
                </td>
              </tr>
            ) : (
              events.map((event, i) => (
                <tr key={i} className="border-b transition-colors hover:bg-muted/50" style={{ borderColor: "var(--border)" }}>
                  <td className="px-3 py-2 font-mono text-xs" style={{ color: "var(--muted-foreground)" }}>
                    {formatDateTime(event.timestamp)}
                  </td>
                  <td className="px-3 py-2">
                    <span className="flex items-center gap-1">
                      {event.type === "inbound" ? (
                        <ArrowDownCircle className="h-3 w-3" style={{ color: "var(--primary)" }} />
                      ) : (
                        <ArrowUpCircle className="h-3 w-3" style={{ color: "var(--warning, var(--primary))" }} />
                      )}
                      <span className="text-xs">{event.type}</span>
                    </span>
                  </td>
                  <td className="px-3 py-2">
                    <span
                      className="rounded px-1.5 py-0.5 font-mono text-xs font-medium"
                      style={{
                        backgroundColor:
                          event.method === "GET" ? "color-mix(in oklch, var(--primary) 10%, transparent)" :
                          event.method === "POST" ? "color-mix(in oklch, var(--primary) 15%, transparent)" :
                          event.method === "PUT" ? "color-mix(in oklch, var(--primary) 12%, transparent)" :
                          "color-mix(in oklch, var(--destructive) 10%, transparent)",
                        color:
                          event.method === "DELETE" ? "var(--destructive)" : "var(--primary)",
                      }}
                    >
                      {event.method}
                    </span>
                  </td>
                  <td className="px-3 py-2 font-mono text-xs max-w-[300px] truncate" title={event.url || event.path}>
                    {event.type === "outbound" && event.url ? event.url : event.path}
                  </td>
                  <td className="px-3 py-2">
                    <span
                      className="font-mono text-xs font-medium"
                      style={{
                        color: event.status && event.status >= 500 ? "var(--destructive)" :
                               event.status && event.status >= 400 ? "var(--warning, var(--destructive))" :
                               event.status && event.status >= 300 ? "var(--muted-foreground)" :
                               "var(--success, var(--primary))",
                      }}
                    >
                      {event.status || "-"}
                    </span>
                  </td>
                  <td className="px-3 py-2 font-mono text-xs" style={{ color: "var(--muted-foreground)" }}>
                    {event.duration_ms != null ? `${event.duration_ms}ms` : "-"}
                  </td>
                  <td className="px-3 py-2 text-xs" style={{ color: "var(--muted-foreground)" }}>
                    {event.service || "-"}
                  </td>
                  <td className="px-3 py-2 text-xs truncate max-w-[150px]" style={{ color: "var(--muted-foreground)" }} title={event.user_email || undefined}>
                    {event.user_email || "-"}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
