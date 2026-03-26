"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import {
  ArrowLeft,
  Lock,
  Unlock,
  Save,
  Play,
  MapPin,
  Clock,
  AlertCircle,
} from "lucide-react";
import { apiGet, apiPost, apiPut } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatDateTime, formatRelative } from "@/lib/utils";
import { PromptEditor } from "@/components/prompt-editor";
import { VersionTimeline } from "@/components/version-timeline";
import type {
  ManagedPrompt,
  PromptVersion,
  PromptVersionDiff,
  PromptUsage,
  PromptTestCase,
  PromptTestRun,
  PromptAuditLogEntry,
} from "@/lib/types";

type TabId = "content" | "versions" | "tryit" | "usage" | "audit";

const tabs: { id: TabId; label: string }[] = [
  { id: "content", label: "Content" },
  { id: "versions", label: "Versions" },
  { id: "tryit", label: "Try It" },
  { id: "usage", label: "Where Used" },
  { id: "audit", label: "Audit" },
];

export default function PromptDetailPage() {
  const params = useParams();
  const searchParams = useSearchParams();
  const router = useRouter();
  const slug = params.slug as string;

  const { hasPermission } = useAuth();
  const canEdit = hasPermission("admin.prompts", "update");

  const initialTab = (searchParams.get("tab") as TabId) || "content";
  const [activeTab, setActiveTab] = useState<TabId>(initialTab);

  const [prompt, setPrompt] = useState<ManagedPrompt | null>(null);
  const [versions, setVersions] = useState<PromptVersion[]>([]);
  const [usages, setUsages] = useState<PromptUsage[]>([]);
  const [auditLog, setAuditLog] = useState<PromptAuditLogEntry[]>([]);
  const [testCases, setTestCases] = useState<PromptTestCase[]>([]);
  const [loading, setLoading] = useState(true);

  // Editor state
  const [editContent, setEditContent] = useState("");
  const [editSystemMessage, setEditSystemMessage] = useState("");
  const [editParameters, setEditParameters] = useState<Record<string, unknown> | null>(null);
  const [changeSummary, setChangeSummary] = useState("");
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);

  // Test state
  const [testInput, setTestInput] = useState("{}");
  const [testResult, setTestResult] = useState<PromptTestRun | null>(null);
  const [testing, setTesting] = useState(false);

  // Diff modal
  const [diffData, setDiffData] = useState<PromptVersionDiff | null>(null);

  // Restore confirm
  const [restoreVersion, setRestoreVersion] = useState<number | null>(null);

  const fetchPrompt = useCallback(async () => {
    try {
      const p = await apiGet<ManagedPrompt>(`/admin/prompts/${slug}`);
      setPrompt(p);
    } catch (err) {
      console.error("Failed to load prompt:", err);
    }
  }, [slug]);

  const fetchVersions = useCallback(async () => {
    try {
      const v = await apiGet<PromptVersion[]>(`/admin/prompts/${slug}/versions`);
      setVersions(v);
      // Initialize editor with latest version
      if (v.length > 0) {
        const latest = v[0];
        setEditContent(latest.content);
        setEditSystemMessage(latest.system_message || "");
        setEditParameters(latest.parameters);
      }
    } catch (err) {
      console.error("Failed to load versions:", err);
    }
  }, [slug]);

  const fetchUsages = useCallback(async () => {
    try {
      setUsages(await apiGet<PromptUsage[]>(`/admin/prompts/${slug}/usages`));
    } catch (err) {
      console.error("Failed to load usages:", err);
    }
  }, [slug]);

  const fetchAudit = useCallback(async () => {
    try {
      setAuditLog(
        await apiGet<PromptAuditLogEntry[]>(`/admin/prompts/${slug}/audit`)
      );
    } catch (err) {
      console.error("Failed to load audit log:", err);
    }
  }, [slug]);

  const fetchTestCases = useCallback(async () => {
    try {
      setTestCases(
        await apiGet<PromptTestCase[]>(`/admin/prompts/${slug}/tests`)
      );
    } catch (err) {
      console.error("Failed to load test cases:", err);
    }
  }, [slug]);

  useEffect(() => {
    Promise.all([fetchPrompt(), fetchVersions()]).then(() =>
      setLoading(false)
    );
  }, [fetchPrompt, fetchVersions]);

  // Lazy-load tab data
  useEffect(() => {
    if (activeTab === "usage") fetchUsages();
    if (activeTab === "audit") fetchAudit();
    if (activeTab === "tryit") fetchTestCases();
  }, [activeTab, fetchUsages, fetchAudit, fetchTestCases]);

  const handleEditorChange = (
    field: "content" | "system_message" | "parameters",
    value: unknown
  ) => {
    setDirty(true);
    if (field === "content") setEditContent(value as string);
    else if (field === "system_message") setEditSystemMessage(value as string);
    else setEditParameters(value as Record<string, unknown>);
  };

  const handleSave = async () => {
    if (!prompt) return;
    setSaving(true);
    try {
      await apiPut(`/admin/prompts/${slug}`, {
        content: editContent,
        system_message: editSystemMessage,
        parameters: editParameters,
        change_summary: changeSummary || "Updated via admin UI",
      });
      setDirty(false);
      setChangeSummary("");
      await Promise.all([fetchPrompt(), fetchVersions()]);
    } catch (err) {
      console.error("Failed to save:", err);
    } finally {
      setSaving(false);
    }
  };

  const handleRestore = async (version: number) => {
    try {
      await apiPost(`/admin/prompts/${slug}/versions/${version}/restore`);
      setRestoreVersion(null);
      await Promise.all([fetchPrompt(), fetchVersions()]);
    } catch (err) {
      console.error("Failed to restore:", err);
    }
  };

  const handleDiff = async (v1: number, v2: number) => {
    try {
      const diff = await apiGet<PromptVersionDiff>(
        `/admin/prompts/${slug}/versions/diff?v1=${v1}&v2=${v2}`
      );
      setDiffData(diff);
    } catch (err) {
      console.error("Failed to load diff:", err);
    }
  };

  const handleLockToggle = async () => {
    if (!prompt) return;
    try {
      if (prompt.is_locked) {
        await apiPost(`/admin/prompts/${slug}/unlock`);
      } else {
        await apiPost(`/admin/prompts/${slug}/lock`);
      }
      await fetchPrompt();
    } catch (err) {
      console.error("Failed to toggle lock:", err);
    }
  };

  const handleRunTest = async () => {
    setTesting(true);
    setTestResult(null);
    try {
      let inputData: Record<string, unknown> | undefined;
      try {
        inputData = JSON.parse(testInput);
      } catch {
        inputData = {};
      }
      const result = await apiPost<PromptTestRun>(
        `/admin/prompts/${slug}/tests/run`,
        inputData
      );
      setTestResult(result);
    } catch (err) {
      console.error("Failed to run test:", err);
    } finally {
      setTesting(false);
    }
  };

  if (loading || !prompt) {
    return (
      <div className="space-y-4">
        <div
          className="h-8 w-64 animate-pulse rounded"
          style={{ backgroundColor: "var(--muted)" }}
        />
        <div
          className="h-96 animate-pulse rounded-xl border"
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
      <div className="flex items-start justify-between gap-4">
        <div>
          <button
            onClick={() => router.push("/admin/prompts")}
            className="mb-2 inline-flex items-center gap-1 text-sm transition-colors"
            style={{ color: "var(--muted-foreground)" }}
          >
            <ArrowLeft className="h-4 w-4" />
            Back to AI Instructions
          </button>
          <h1 className="text-2xl font-bold tracking-tight">{prompt.name}</h1>
          {prompt.description && (
            <p
              className="mt-1"
              style={{ color: "var(--muted-foreground)" }}
            >
              {prompt.description}
            </p>
          )}
          <div
            className="mt-2 flex items-center gap-3 text-sm"
            style={{ color: "var(--muted-foreground)" }}
          >
            <span>v{prompt.current_version}</span>
            <span>Updated {formatRelative(prompt.updated_at)}</span>
            {prompt.is_locked && (
              <span
                className="inline-flex items-center gap-1"
                style={{ color: "var(--warning)" }}
              >
                <Lock className="h-3.5 w-3.5" />
                Locked
              </span>
            )}
          </div>
        </div>

        {/* Actions */}
        {canEdit && (
          <div className="flex items-center gap-2">
            <button
              onClick={handleLockToggle}
              className="inline-flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium transition-colors"
              style={{
                borderColor: "var(--border)",
                color: "var(--muted-foreground)",
              }}
            >
              {prompt.is_locked ? (
                <>
                  <Unlock className="h-4 w-4" />
                  Unlock
                </>
              ) : (
                <>
                  <Lock className="h-4 w-4" />
                  Lock
                </>
              )}
            </button>
          </div>
        )}
      </div>

      {/* Tabs */}
      <div
        className="flex gap-0 border-b"
        style={{ borderColor: "var(--border)" }}
      >
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className="px-4 py-2.5 text-sm font-medium transition-colors"
            style={{
              borderBottom: `2px solid ${
                activeTab === tab.id ? "var(--primary)" : "transparent"
              }`,
              color:
                activeTab === tab.id
                  ? "var(--primary)"
                  : "var(--muted-foreground)",
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {activeTab === "content" && (
        <div className="space-y-4">
          <PromptEditor
            content={editContent}
            systemMessage={editSystemMessage}
            parameters={editParameters}
            onChange={handleEditorChange}
            readOnly={prompt.is_locked || !canEdit}
          />

          {/* Save bar */}
          {canEdit && !prompt.is_locked && (
            <div
              className="flex items-center gap-3 rounded-lg border p-4"
              style={{
                backgroundColor: "var(--card)",
                borderColor: dirty ? "var(--primary)" : "var(--border)",
              }}
            >
              <input
                type="text"
                value={changeSummary}
                onChange={(e) => setChangeSummary(e.target.value)}
                placeholder="Describe what you changed (optional)"
                className="flex-1 rounded-md border px-3 py-1.5 text-sm"
                style={{
                  borderColor: "var(--input)",
                  backgroundColor: "var(--background)",
                  color: "var(--foreground)",
                }}
              />
              <button
                onClick={handleSave}
                disabled={!dirty || saving}
                className="inline-flex items-center gap-2 rounded-md px-4 py-1.5 text-sm font-medium disabled:opacity-50"
                style={{
                  backgroundColor: "var(--primary)",
                  color: "var(--primary-foreground)",
                }}
              >
                <Save className="h-4 w-4" />
                {saving ? "Saving..." : "Save & Publish"}
              </button>
            </div>
          )}
        </div>
      )}

      {activeTab === "versions" && (
        <VersionTimeline
          versions={versions}
          currentVersion={prompt.current_version}
          onRestore={(v) => setRestoreVersion(v)}
          onDiff={handleDiff}
        />
      )}

      {activeTab === "tryit" && (
        <div className="space-y-6">
          <div
            className="rounded-xl border p-5"
            style={{
              backgroundColor: "var(--card)",
              borderColor: "var(--border)",
            }}
          >
            <h3 className="text-sm font-semibold mb-3">Test Input</h3>
            <p
              className="text-xs mb-3"
              style={{ color: "var(--muted-foreground)" }}
            >
              Enter test values for the dynamic variables in your instruction.
              Use JSON format: {`{"variable_name": "test value"}`}
            </p>
            <textarea
              value={testInput}
              onChange={(e) => setTestInput(e.target.value)}
              rows={4}
              className="w-full rounded-md border px-3 py-2 text-sm font-mono"
              style={{
                borderColor: "var(--input)",
                backgroundColor: "var(--background)",
                color: "var(--foreground)",
              }}
              placeholder='{"user_input": "test query"}'
            />
            <button
              onClick={handleRunTest}
              disabled={testing}
              className="mt-3 inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
              style={{
                backgroundColor: "var(--primary)",
                color: "var(--primary-foreground)",
              }}
            >
              <Play className="h-4 w-4" />
              {testing ? "Running..." : "Try It"}
            </button>
          </div>

          {/* Test result */}
          {testResult && (
            <div
              className="rounded-xl border p-5"
              style={{
                backgroundColor: "var(--card)",
                borderColor: testResult.success
                  ? "var(--success)"
                  : "var(--destructive)",
              }}
            >
              <h3 className="text-sm font-semibold mb-2">Result</h3>
              <pre
                className="whitespace-pre-wrap rounded-md p-3 text-sm"
                style={{
                  backgroundColor: "var(--background)",
                  color: "var(--foreground)",
                }}
              >
                {testResult.output}
              </pre>
              <div
                className="mt-3 flex items-center gap-4 text-xs"
                style={{ color: "var(--muted-foreground)" }}
              >
                {testResult.tokens_in != null && (
                  <span>Input: {testResult.tokens_in} tokens</span>
                )}
                {testResult.tokens_out != null && (
                  <span>Output: {testResult.tokens_out} tokens</span>
                )}
                {testResult.latency_ms != null && (
                  <span>{testResult.latency_ms}ms</span>
                )}
              </div>
              {testResult.error && (
                <p
                  className="mt-2 text-sm"
                  style={{ color: "var(--destructive)" }}
                >
                  {testResult.error}
                </p>
              )}
            </div>
          )}

          {/* Saved test cases */}
          {testCases.length > 0 && (
            <div>
              <h3 className="text-sm font-semibold mb-3">Saved Test Cases</h3>
              <div className="space-y-2">
                {testCases.map((tc) => (
                  <div
                    key={tc.id}
                    className="flex items-center justify-between rounded-lg border px-4 py-2.5"
                    style={{
                      backgroundColor: "var(--card)",
                      borderColor: "var(--border)",
                    }}
                  >
                    <div>
                      <span className="text-sm font-medium">{tc.name}</span>
                      {tc.notes && (
                        <p
                          className="text-xs"
                          style={{ color: "var(--muted-foreground)" }}
                        >
                          {tc.notes}
                        </p>
                      )}
                    </div>
                    <button
                      onClick={() =>
                        setTestInput(
                          JSON.stringify(tc.input_data || {}, null, 2)
                        )
                      }
                      className="rounded-md px-3 py-1 text-xs font-medium transition-colors"
                      style={{
                        backgroundColor:
                          "color-mix(in oklch, var(--primary) 10%, transparent)",
                        color: "var(--primary)",
                      }}
                    >
                      Load
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {activeTab === "usage" && (
        <div className="space-y-3">
          {usages.length === 0 ? (
            <div
              className="rounded-xl border p-8 text-center"
              style={{
                backgroundColor: "var(--card)",
                borderColor: "var(--border)",
              }}
            >
              <MapPin
                className="mx-auto h-8 w-8 mb-2"
                style={{ color: "var(--muted-foreground)" }}
              />
              <p style={{ color: "var(--muted-foreground)" }}>
                No usage data recorded yet. Usage appears here once the app
                starts calling this AI instruction.
              </p>
            </div>
          ) : (
            usages.map((usage) => (
              <div
                key={usage.id}
                className="flex items-center justify-between rounded-lg border px-5 py-4"
                style={{
                  backgroundColor: "var(--card)",
                  borderColor: usage.is_primary
                    ? "var(--primary)"
                    : "var(--border)",
                }}
              >
                <div className="flex items-center gap-3">
                  <MapPin
                    className="h-4 w-4 shrink-0"
                    style={{
                      color: usage.is_primary
                        ? "var(--primary)"
                        : "var(--muted-foreground)",
                    }}
                  />
                  <div>
                    <p className="text-sm font-medium">{usage.location}</p>
                    {usage.description && (
                      <p
                        className="text-xs"
                        style={{ color: "var(--muted-foreground)" }}
                      >
                        {usage.description}
                      </p>
                    )}
                  </div>
                </div>
                <div
                  className="flex items-center gap-4 text-xs"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  <span>{usage.call_count} calls</span>
                  {usage.avg_latency_ms != null && (
                    <span>{Math.round(usage.avg_latency_ms)}ms avg</span>
                  )}
                  {usage.error_count > 0 && (
                    <span
                      className="flex items-center gap-1"
                      style={{ color: "var(--destructive)" }}
                    >
                      <AlertCircle className="h-3 w-3" />
                      {usage.error_count} errors
                    </span>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {activeTab === "audit" && (
        <div className="space-y-2">
          {auditLog.length === 0 ? (
            <p style={{ color: "var(--muted-foreground)" }}>
              No audit entries yet.
            </p>
          ) : (
            auditLog.map((entry) => (
              <div
                key={entry.id}
                className="flex items-center gap-4 rounded-lg border px-4 py-3"
                style={{
                  backgroundColor: "var(--card)",
                  borderColor: "var(--border)",
                }}
              >
                <ActionBadge action={entry.action} />
                <div className="min-w-0 flex-1">
                  <p className="text-sm">
                    {entry.user_email || "System"}
                    {entry.version != null && (
                      <span
                        className="ml-1"
                        style={{ color: "var(--muted-foreground)" }}
                      >
                        (v{entry.version})
                      </span>
                    )}
                  </p>
                </div>
                <span
                  className="shrink-0 text-xs"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  {formatRelative(entry.created_at)}
                </span>
              </div>
            ))
          )}
        </div>
      )}

      {/* Restore confirmation modal */}
      {restoreVersion !== null && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div
            className="mx-4 w-full max-w-sm rounded-xl border p-6 shadow-lg"
            style={{
              backgroundColor: "var(--card)",
              borderColor: "var(--border)",
            }}
          >
            <h3 className="text-lg font-semibold">Restore Version?</h3>
            <p
              className="mt-2 text-sm"
              style={{ color: "var(--muted-foreground)" }}
            >
              This will create a new version with the content from version{" "}
              {restoreVersion}. Your current version is not lost -- it stays in
              the history.
            </p>
            <div className="mt-4 flex justify-end gap-2">
              <button
                onClick={() => setRestoreVersion(null)}
                className="rounded-md border px-4 py-2 text-sm font-medium"
                style={{
                  borderColor: "var(--border)",
                  color: "var(--muted-foreground)",
                }}
              >
                Cancel
              </button>
              <button
                onClick={() => handleRestore(restoreVersion)}
                className="rounded-md px-4 py-2 text-sm font-medium"
                style={{
                  backgroundColor: "var(--primary)",
                  color: "var(--primary-foreground)",
                }}
              >
                Restore
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Diff modal */}
      {diffData && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div
            className="mx-4 w-full max-w-2xl rounded-xl border p-6 shadow-lg"
            style={{
              backgroundColor: "var(--card)",
              borderColor: "var(--border)",
            }}
          >
            <h3 className="text-lg font-semibold">
              Comparing v{diffData.version_a} with v{diffData.version_b}
            </h3>

            {diffData.content_diff ? (
              <div className="mt-4">
                <h4 className="text-sm font-medium mb-2">
                  Instructions Changes
                </h4>
                <pre
                  className="max-h-80 overflow-auto whitespace-pre-wrap rounded-md p-3 text-xs font-mono"
                  style={{
                    backgroundColor: "var(--background)",
                    color: "var(--foreground)",
                  }}
                >
                  {diffData.content_diff}
                </pre>
              </div>
            ) : (
              <p
                className="mt-4 text-sm"
                style={{ color: "var(--muted-foreground)" }}
              >
                No differences in instructions.
              </p>
            )}

            {diffData.system_message_diff && (
              <div className="mt-4">
                <h4 className="text-sm font-medium mb-2">
                  AI Behavior Changes
                </h4>
                <pre
                  className="max-h-40 overflow-auto whitespace-pre-wrap rounded-md p-3 text-xs font-mono"
                  style={{
                    backgroundColor: "var(--background)",
                    color: "var(--foreground)",
                  }}
                >
                  {diffData.system_message_diff}
                </pre>
              </div>
            )}

            <div className="mt-6 flex justify-end">
              <button
                onClick={() => setDiffData(null)}
                className="rounded-md border px-4 py-2 text-sm font-medium"
                style={{
                  borderColor: "var(--border)",
                  color: "var(--muted-foreground)",
                }}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Action Badge
// ---------------------------------------------------------------------------

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

function ActionBadge({ action }: { action: string }) {
  const color = actionColors[action] || "var(--muted-foreground)";
  const label = action.replace(/_/g, " ");
  return (
    <span
      className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize"
      style={{
        backgroundColor: `color-mix(in oklch, ${color} 15%, transparent)`,
        color,
      }}
    >
      {label}
    </span>
  );
}
