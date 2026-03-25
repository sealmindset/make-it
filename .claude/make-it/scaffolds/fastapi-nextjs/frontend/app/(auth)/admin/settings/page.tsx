"use client";

import { useEffect, useState, useCallback } from "react";
import { apiGet, apiPut, apiDelete } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatDateTime } from "@/lib/utils";
import {
  Settings, Save, Eye, EyeOff, RefreshCw, History,
  AlertTriangle,
} from "lucide-react";

interface AppSetting {
  id: string;
  key: string;
  value: string | null;
  group_name: string;
  display_name: string;
  description: string | null;
  value_type: string;
  is_sensitive: boolean;
  requires_restart: boolean;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

interface AuditLog {
  id: string;
  setting_id: string;
  old_value: string | null;
  new_value: string | null;
  changed_by: string;
  created_at: string;
}

type Tab = "settings" | "audit";

export default function SettingsPage() {
  const { hasPermission } = useAuth();
  const canEdit = hasPermission("admin.settings", "update");

  const [settings, setSettings] = useState<AppSetting[]>([]);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [tab, setTab] = useState<Tab>("settings");
  const [edits, setEdits] = useState<Record<string, string | null>>({});
  const [revealed, setRevealed] = useState<Record<string, string>>({});
  const [revealing, setRevealing] = useState<Record<string, boolean>>({});

  const fetchSettings = useCallback(async () => {
    try {
      const data = await apiGet<AppSetting[]>("/admin/settings");
      setSettings(data);
    } catch (err) {
      console.error("Failed to load settings:", err);
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchAuditLogs = useCallback(async () => {
    try {
      const data = await apiGet<AuditLog[]>("/admin/settings/audit-log");
      setAuditLogs(data);
    } catch (err) {
      console.error("Failed to load audit logs:", err);
    }
  }, []);

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  useEffect(() => {
    if (tab === "audit") fetchAuditLogs();
  }, [tab, fetchAuditLogs]);

  // Group settings by group_name
  const groups = settings.reduce<Record<string, AppSetting[]>>((acc, s) => {
    (acc[s.group_name] ||= []).push(s);
    return acc;
  }, {});

  const handleEdit = (key: string, value: string | null) => {
    setEdits((prev) => ({ ...prev, [key]: value }));
  };

  const hasEdits = (groupName: string) => {
    return groups[groupName]?.some((s) => s.key in edits && edits[s.key] !== s.value);
  };

  const saveGroup = async (groupName: string) => {
    const groupSettings = groups[groupName];
    if (!groupSettings) return;

    const changes = groupSettings
      .filter((s) => s.key in edits && edits[s.key] !== s.value)
      .map((s) => ({ key: s.key, value: edits[s.key] ?? null }));

    if (changes.length === 0) return;

    setSaving(true);
    try {
      await apiPut("/admin/settings", { settings: changes });
      // Clear edits for this group and refresh
      const clearedEdits = { ...edits };
      for (const s of groupSettings) delete clearedEdits[s.key];
      setEdits(clearedEdits);
      setRevealed({});
      await fetchSettings();
    } catch (err) {
      console.error("Failed to save settings:", err);
    } finally {
      setSaving(false);
    }
  };

  const revealValue = async (key: string) => {
    setRevealing((prev) => ({ ...prev, [key]: true }));
    try {
      const data = await apiGet<{ key: string; value: string | null }>(
        `/admin/settings/${encodeURIComponent(key)}/reveal`
      );
      setRevealed((prev) => ({ ...prev, [key]: data.value ?? "" }));
    } catch (err) {
      console.error("Failed to reveal setting:", err);
    } finally {
      setRevealing((prev) => ({ ...prev, [key]: false }));
    }
  };

  const hideValue = (key: string) => {
    setRevealed((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
  };

  const getDisplayValue = (s: AppSetting): string => {
    if (s.key in edits) return edits[s.key] ?? "";
    if (s.is_sensitive && s.key in revealed) return revealed[s.key];
    return s.value ?? "";
  };

  const renderInput = (s: AppSetting) => {
    const value = getDisplayValue(s);
    const isEdited = s.key in edits && edits[s.key] !== s.value;

    if (s.value_type === "bool") {
      const checked = (edits[s.key] ?? s.value ?? "false").toLowerCase() === "true";
      return (
        <div className="flex items-center gap-3">
          <button
            onClick={() => canEdit ? handleEdit(s.key, checked ? "false" : "true") : undefined}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${!canEdit ? "opacity-50 cursor-not-allowed" : "cursor-pointer"}`}
            style={{
              backgroundColor: checked ? "var(--primary)" : "var(--muted)",
            }}
            disabled={!canEdit}
          >
            <span
              className="inline-block h-4 w-4 rounded-full bg-white transition-transform"
              style={{ transform: checked ? "translateX(22px)" : "translateX(4px)" }}
            />
          </button>
          <span className="text-sm">{checked ? "Enabled" : "Disabled"}</span>
        </div>
      );
    }

    return (
      <div className="flex items-center gap-2">
        <input
          type={s.is_sensitive && !(s.key in revealed) ? "password" : "text"}
          value={value}
          onChange={(e) => canEdit ? handleEdit(s.key, e.target.value) : undefined}
          readOnly={!canEdit}
          className={`flex-1 rounded-md border px-3 py-1.5 text-sm font-mono ${isEdited ? "ring-2" : ""} ${!canEdit ? "opacity-70" : ""}`}
          style={{
            borderColor: isEdited ? "var(--primary)" : "var(--input)",
            backgroundColor: "var(--background)",
            color: "var(--foreground)",
            ringColor: "var(--primary)",
          }}
        />
        {s.is_sensitive && canEdit && (
          <button
            onClick={() => s.key in revealed ? hideValue(s.key) : revealValue(s.key)}
            className="inline-flex h-8 w-8 items-center justify-center rounded-md border transition-colors hover:bg-accent"
            style={{ borderColor: "var(--input)" }}
            disabled={revealing[s.key]}
          >
            {revealing[s.key] ? (
              <RefreshCw className="h-3.5 w-3.5 animate-spin" style={{ color: "var(--muted-foreground)" }} />
            ) : s.key in revealed ? (
              <EyeOff className="h-3.5 w-3.5" style={{ color: "var(--muted-foreground)" }} />
            ) : (
              <Eye className="h-3.5 w-3.5" style={{ color: "var(--muted-foreground)" }} />
            )}
          </button>
        )}
      </div>
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Settings</h1>
          <p style={{ color: "var(--muted-foreground)" }}>
            Manage application configuration.
          </p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b" style={{ borderColor: "var(--border)" }}>
        {([
          { id: "settings" as Tab, label: "Configuration", icon: Settings },
          { id: "audit" as Tab, label: "Change History", icon: History },
        ]).map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`inline-flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-medium transition-colors ${tab === id ? "" : "border-transparent"}`}
            style={{
              borderBottomColor: tab === id ? "var(--primary)" : "transparent",
              color: tab === id ? "var(--foreground)" : "var(--muted-foreground)",
            }}
          >
            <Icon className="h-4 w-4" />
            {label}
          </button>
        ))}
      </div>

      {/* Settings tab */}
      {tab === "settings" && (
        <div className="space-y-6">
          {loading ? (
            <p style={{ color: "var(--muted-foreground)" }}>Loading settings...</p>
          ) : Object.keys(groups).length === 0 ? (
            <p style={{ color: "var(--muted-foreground)" }}>No settings configured yet.</p>
          ) : (
            Object.entries(groups).map(([groupName, groupSettings]) => (
              <div
                key={groupName}
                className="rounded-xl border"
                style={{ borderColor: "var(--border)", backgroundColor: "var(--card)" }}
              >
                {/* Group header */}
                <div className="flex items-center justify-between border-b px-5 py-3" style={{ borderColor: "var(--border)" }}>
                  <h2 className="text-sm font-semibold">{groupName}</h2>
                  {canEdit && hasEdits(groupName) && (
                    <button
                      onClick={() => saveGroup(groupName)}
                      disabled={saving}
                      className="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium text-white transition-colors"
                      style={{ backgroundColor: "var(--primary)" }}
                    >
                      <Save className="h-3 w-3" />
                      {saving ? "Saving..." : "Save Changes"}
                    </button>
                  )}
                </div>

                {/* Settings rows */}
                <div className="divide-y" style={{ borderColor: "var(--border)" }}>
                  {groupSettings.map((s) => (
                    <div key={s.key} className="grid gap-1 px-5 py-4 sm:grid-cols-[1fr_1fr]">
                      <div>
                        <div className="flex items-center gap-2">
                          <label className="text-sm font-medium">{s.display_name}</label>
                          {s.requires_restart && (
                            <span
                              className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium"
                              style={{
                                backgroundColor: "color-mix(in oklch, var(--destructive) 10%, transparent)",
                                color: "var(--destructive)",
                              }}
                            >
                              <AlertTriangle className="h-2.5 w-2.5" />
                              Restart required
                            </span>
                          )}
                          {s.is_sensitive && (
                            <span
                              className="rounded-full px-2 py-0.5 text-[10px] font-medium"
                              style={{
                                backgroundColor: "color-mix(in oklch, var(--primary) 10%, transparent)",
                                color: "var(--primary)",
                              }}
                            >
                              Sensitive
                            </span>
                          )}
                        </div>
                        {s.description && (
                          <p className="mt-0.5 text-xs" style={{ color: "var(--muted-foreground)" }}>
                            {s.description}
                          </p>
                        )}
                        <p className="mt-1 font-mono text-[10px]" style={{ color: "var(--muted-foreground)" }}>
                          {s.key}
                        </p>
                      </div>
                      <div className="flex items-start">
                        {renderInput(s)}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Audit log tab */}
      {tab === "audit" && (
        <div className="rounded-md border overflow-x-auto" style={{ borderColor: "var(--border)" }}>
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b" style={{ borderColor: "var(--border)" }}>
                <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>When</th>
                <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Who</th>
                <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Setting</th>
                <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>Old Value</th>
                <th className="h-10 px-3 text-left font-medium" style={{ color: "var(--muted-foreground)" }}>New Value</th>
              </tr>
            </thead>
            <tbody>
              {auditLogs.length === 0 ? (
                <tr>
                  <td colSpan={5} className="h-24 text-center" style={{ color: "var(--muted-foreground)" }}>
                    No changes recorded yet.
                  </td>
                </tr>
              ) : (
                auditLogs.map((log) => {
                  const setting = settings.find((s) => s.id === log.setting_id);
                  return (
                    <tr key={log.id} className="border-b transition-colors hover:bg-muted/50" style={{ borderColor: "var(--border)" }}>
                      <td className="px-3 py-2 text-xs" style={{ color: "var(--muted-foreground)" }}>
                        {formatDateTime(log.created_at)}
                      </td>
                      <td className="px-3 py-2 text-xs">{log.changed_by}</td>
                      <td className="px-3 py-2 text-xs font-mono">
                        {setting?.display_name || log.setting_id.slice(0, 8)}
                      </td>
                      <td className="px-3 py-2 text-xs font-mono" style={{ color: "var(--muted-foreground)" }}>
                        {log.old_value ?? "-"}
                      </td>
                      <td className="px-3 py-2 text-xs font-mono">
                        {log.new_value ?? "-"}
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
