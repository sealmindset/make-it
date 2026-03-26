"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Sparkles,
  Plus,
  Search,
  BarChart3,
  ClipboardList,
  Layers,
  CheckCircle2,
} from "lucide-react";
import { apiGet, apiPost } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PromptCard } from "@/components/prompt-card";
import type {
  ManagedPromptListItem,
  PromptStats,
} from "@/lib/types";

export default function PromptsPage() {
  const router = useRouter();
  const { hasPermission } = useAuth();
  const canCreate = hasPermission("admin.prompts", "create");
  const canEdit = hasPermission("admin.prompts", "update");

  const [prompts, setPrompts] = useState<ManagedPromptListItem[]>([]);
  const [stats, setStats] = useState<PromptStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");

  // Create modal state
  const [showCreate, setShowCreate] = useState(false);
  const [createForm, setCreateForm] = useState({
    name: "",
    slug: "",
    description: "",
    category: "general",
    content: "",
  });
  const [createError, setCreateError] = useState("");

  const fetchData = useCallback(async () => {
    try {
      const params = new URLSearchParams();
      if (search) params.set("search", search);
      if (categoryFilter) params.set("category", categoryFilter);
      if (statusFilter === "active") params.set("is_active", "true");
      if (statusFilter === "inactive") params.set("is_active", "false");
      const qs = params.toString();

      const [promptList, promptStats] = await Promise.all([
        apiGet<ManagedPromptListItem[]>(
          `/admin/prompts/${qs ? `?${qs}` : ""}`
        ),
        apiGet<PromptStats>("/admin/prompts/stats"),
      ]);
      setPrompts(promptList);
      setStats(promptStats);
    } catch (err) {
      console.error("Failed to load AI instructions:", err);
    } finally {
      setLoading(false);
    }
  }, [search, categoryFilter, statusFilter]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const handleCreate = async () => {
    setCreateError("");
    try {
      const slug =
        createForm.slug ||
        createForm.name
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/^-|-$/g, "");

      await apiPost("/admin/prompts/", {
        ...createForm,
        slug,
        content: createForm.content || `You are a helpful AI assistant for [APP_NAME].\n\nYour task: ${createForm.name}\n\n{user_input}`,
      });
      setShowCreate(false);
      setCreateForm({
        name: "",
        slug: "",
        description: "",
        category: "general",
        content: "",
      });
      fetchData();
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Failed to create";
      setCreateError(message);
    }
  };

  if (loading) {
    return (
      <div className="space-y-4">
        <div
          className="h-8 w-48 animate-pulse rounded"
          style={{ backgroundColor: "var(--muted)" }}
        />
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((i) => (
            <div
              key={i}
              className="h-24 animate-pulse rounded-xl border"
              style={{
                backgroundColor: "var(--card)",
                borderColor: "var(--border)",
              }}
            />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">
            AI Instructions
          </h1>
          <p style={{ color: "var(--muted-foreground)" }}>
            Manage how your AI features behave. Edit instructions, test changes,
            and track versions.
          </p>
        </div>
        {canCreate && (
          <button
            onClick={() => setShowCreate(true)}
            className="inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-medium shadow-sm"
            style={{
              backgroundColor: "var(--primary)",
              color: "var(--primary-foreground)",
            }}
          >
            <Plus className="h-4 w-4" />
            Add AI Instruction
          </button>
        )}
      </div>

      {/* Stats cards */}
      {stats && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            icon={Sparkles}
            label="Total"
            value={stats.total}
          />
          <StatCard
            icon={CheckCircle2}
            label="Active"
            value={stats.active}
            color="var(--success)"
          />
          <StatCard
            icon={Layers}
            label="Versions"
            value={stats.versions_count}
          />
          <StatCard
            icon={ClipboardList}
            label="Categories"
            value={stats.categories_count}
          />
        </div>
      )}

      {/* Search + filters */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search
            className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2"
            style={{ color: "var(--muted-foreground)" }}
          />
          <input
            type="text"
            placeholder="Search AI instructions..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-md border py-2 pl-9 pr-3 text-sm"
            style={{
              borderColor: "var(--input)",
              backgroundColor: "var(--background)",
              color: "var(--foreground)",
            }}
          />
        </div>
        <select
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="rounded-md border px-3 py-2 text-sm"
          style={{
            borderColor: "var(--input)",
            backgroundColor: "var(--background)",
            color: "var(--foreground)",
          }}
        >
          <option value="">All categories</option>
          <option value="analysis">Analysis</option>
          <option value="generation">Generation</option>
          <option value="classification">Classification</option>
          <option value="extraction">Extraction</option>
          <option value="general">General</option>
        </select>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-md border px-3 py-2 text-sm"
          style={{
            borderColor: "var(--input)",
            backgroundColor: "var(--background)",
            color: "var(--foreground)",
          }}
        >
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
      </div>

      {/* Navigation links */}
      <div className="flex items-center gap-4">
        <button
          onClick={() => router.push("/admin/prompts/analytics")}
          className="inline-flex items-center gap-1.5 text-sm font-medium transition-colors"
          style={{ color: "var(--primary)" }}
        >
          <BarChart3 className="h-4 w-4" />
          Analytics
        </button>
        <button
          onClick={() => router.push("/admin/prompts/audit")}
          className="inline-flex items-center gap-1.5 text-sm font-medium transition-colors"
          style={{ color: "var(--primary)" }}
        >
          <ClipboardList className="h-4 w-4" />
          Audit Log
        </button>
      </div>

      {/* Card grid */}
      {prompts.length === 0 ? (
        <div
          className="rounded-xl border p-12 text-center"
          style={{
            backgroundColor: "var(--card)",
            borderColor: "var(--border)",
          }}
        >
          <Sparkles
            className="mx-auto h-12 w-12 mb-4"
            style={{ color: "var(--muted-foreground)" }}
          />
          <h3 className="text-lg font-semibold">No AI instructions yet</h3>
          <p
            className="mt-1 text-sm"
            style={{ color: "var(--muted-foreground)" }}
          >
            {canCreate
              ? "Create your first AI instruction to get started."
              : "No AI instructions have been configured for this app."}
          </p>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {prompts.map((prompt) => (
            <PromptCard
              key={prompt.id}
              prompt={prompt}
              canEdit={canEdit}
              onEdit={(slug) => router.push(`/admin/prompts/${slug}`)}
              onTryIt={(slug) =>
                router.push(`/admin/prompts/${slug}?tab=tryit`)
              }
              onHistory={(slug) =>
                router.push(`/admin/prompts/${slug}?tab=versions`)
              }
            />
          ))}
        </div>
      )}

      {/* Create modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div
            className="mx-4 w-full max-w-lg rounded-xl border p-6 shadow-lg"
            style={{
              backgroundColor: "var(--card)",
              borderColor: "var(--border)",
            }}
          >
            <h2 className="text-lg font-semibold">
              Add AI Instruction
            </h2>
            <p
              className="mt-1 text-sm"
              style={{ color: "var(--muted-foreground)" }}
            >
              Create a new set of instructions for an AI feature in your app.
            </p>

            <div className="mt-4 space-y-3">
              <div>
                <label className="block text-sm font-medium mb-1">Name</label>
                <input
                  type="text"
                  value={createForm.name}
                  onChange={(e) =>
                    setCreateForm({ ...createForm, name: e.target.value })
                  }
                  placeholder="e.g., Document Analysis"
                  className="w-full rounded-md border px-3 py-2 text-sm"
                  style={{
                    borderColor: "var(--input)",
                    backgroundColor: "var(--background)",
                    color: "var(--foreground)",
                  }}
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">
                  Description
                </label>
                <textarea
                  value={createForm.description}
                  onChange={(e) =>
                    setCreateForm({
                      ...createForm,
                      description: e.target.value,
                    })
                  }
                  placeholder="What does this AI instruction do? (shown on the card)"
                  rows={2}
                  className="w-full rounded-md border px-3 py-2 text-sm"
                  style={{
                    borderColor: "var(--input)",
                    backgroundColor: "var(--background)",
                    color: "var(--foreground)",
                  }}
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">
                  Category
                </label>
                <select
                  value={createForm.category}
                  onChange={(e) =>
                    setCreateForm({ ...createForm, category: e.target.value })
                  }
                  className="w-full rounded-md border px-3 py-2 text-sm"
                  style={{
                    borderColor: "var(--input)",
                    backgroundColor: "var(--background)",
                    color: "var(--foreground)",
                  }}
                >
                  <option value="general">General</option>
                  <option value="analysis">Analysis</option>
                  <option value="generation">Generation</option>
                  <option value="classification">Classification</option>
                  <option value="extraction">Extraction</option>
                </select>
              </div>

              {createError && (
                <p className="text-sm" style={{ color: "var(--destructive)" }}>
                  {createError}
                </p>
              )}
            </div>

            <div className="mt-6 flex justify-end gap-2">
              <button
                onClick={() => setShowCreate(false)}
                className="rounded-md border px-4 py-2 text-sm font-medium"
                style={{
                  borderColor: "var(--border)",
                  color: "var(--muted-foreground)",
                }}
              >
                Cancel
              </button>
              <button
                onClick={handleCreate}
                disabled={!createForm.name}
                className="rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
                style={{
                  backgroundColor: "var(--primary)",
                  color: "var(--primary-foreground)",
                }}
              >
                Create
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Stat Card
// ---------------------------------------------------------------------------

function StatCard({
  icon: Icon,
  label,
  value,
  color,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: number;
  color?: string;
}) {
  const iconColor = color || "var(--primary)";
  return (
    <div
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
            backgroundColor: `color-mix(in oklch, ${iconColor} 12%, transparent)`,
          }}
        >
          <Icon className="h-5 w-5" style={{ color: iconColor }} />
        </div>
        <div>
          <p className="text-2xl font-bold">{value}</p>
          <p
            className="text-xs font-medium"
            style={{ color: "var(--muted-foreground)" }}
          >
            {label}
          </p>
        </div>
      </div>
    </div>
  );
}
