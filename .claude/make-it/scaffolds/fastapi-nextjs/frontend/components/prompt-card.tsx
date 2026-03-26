"use client";

import { Pencil, Play, History, Lock, MapPin } from "lucide-react";
import { formatRelative } from "@/lib/utils";
import type { ManagedPromptListItem } from "@/lib/types";

interface PromptCardProps {
  prompt: ManagedPromptListItem;
  canEdit: boolean;
  onEdit: (slug: string) => void;
  onTryIt: (slug: string) => void;
  onHistory: (slug: string) => void;
}

const categoryColors: Record<string, string> = {
  analysis: "var(--primary)",
  generation: "var(--success)",
  classification: "var(--warning)",
  extraction: "var(--destructive)",
  general: "var(--muted-foreground)",
};

export function PromptCard({
  prompt,
  canEdit,
  onEdit,
  onTryIt,
  onHistory,
}: PromptCardProps) {
  const categoryColor = categoryColors[prompt.category] || "var(--primary)";

  return (
    <div
      className="group relative flex flex-col rounded-xl border p-5 transition-shadow hover:shadow-md"
      style={{
        backgroundColor: "var(--card)",
        borderColor: "var(--border)",
      }}
    >
      {/* Header: name + status */}
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-sm font-semibold">{prompt.name}</h3>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {prompt.is_locked && (
            <Lock
              className="h-3.5 w-3.5"
              style={{ color: "var(--warning)" }}
              title="Locked"
            />
          )}
          <span
            className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
            style={{
              backgroundColor: prompt.is_active
                ? "color-mix(in oklch, var(--success) 15%, transparent)"
                : "color-mix(in oklch, var(--muted-foreground) 15%, transparent)",
              color: prompt.is_active
                ? "var(--success)"
                : "var(--muted-foreground)",
            }}
          >
            {prompt.is_active ? "Active" : "Inactive"}
          </span>
        </div>
      </div>

      {/* Description */}
      {prompt.description && (
        <p
          className="mt-1.5 line-clamp-2 text-sm"
          style={{ color: "var(--muted-foreground)" }}
        >
          {prompt.description}
        </p>
      )}

      {/* Where used breadcrumb */}
      {prompt.primary_usage_location && (
        <div
          className="mt-3 flex items-center gap-1.5 text-xs"
          style={{ color: "var(--muted-foreground)" }}
        >
          <MapPin className="h-3 w-3 shrink-0" />
          <span className="truncate">
            Used in: {prompt.primary_usage_location}
          </span>
        </div>
      )}

      {/* Tags + category */}
      <div className="mt-3 flex flex-wrap items-center gap-1.5">
        <span
          className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
          style={{
            backgroundColor: `color-mix(in oklch, ${categoryColor} 12%, transparent)`,
            color: categoryColor,
          }}
        >
          {prompt.category}
        </span>
        {prompt.tags.slice(0, 3).map((tag) => (
          <span
            key={tag}
            className="inline-flex items-center rounded-full px-2 py-0.5 text-xs"
            style={{
              backgroundColor:
                "color-mix(in oklch, var(--foreground) 8%, transparent)",
              color: "var(--muted-foreground)",
            }}
          >
            {tag}
          </span>
        ))}
        {prompt.tags.length > 3 && (
          <span
            className="text-xs"
            style={{ color: "var(--muted-foreground)" }}
          >
            +{prompt.tags.length - 3} more
          </span>
        )}
      </div>

      {/* Footer: version + updated + actions */}
      <div className="mt-4 flex items-center justify-between border-t pt-3" style={{ borderColor: "var(--border)" }}>
        <div
          className="flex items-center gap-3 text-xs"
          style={{ color: "var(--muted-foreground)" }}
        >
          <span>v{prompt.current_version}</span>
          <span>{formatRelative(prompt.updated_at)}</span>
        </div>

        <div className="flex items-center gap-1">
          {canEdit && (
            <button
              onClick={() => onEdit(prompt.slug)}
              className="rounded p-1.5 transition-colors"
              style={{ color: "var(--muted-foreground)" }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = "var(--accent)";
                e.currentTarget.style.color = "var(--accent-foreground)";
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = "transparent";
                e.currentTarget.style.color = "var(--muted-foreground)";
              }}
              title="Edit"
            >
              <Pencil className="h-3.5 w-3.5" />
            </button>
          )}
          <button
            onClick={() => onTryIt(prompt.slug)}
            className="rounded p-1.5 transition-colors"
            style={{ color: "var(--muted-foreground)" }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = "var(--accent)";
              e.currentTarget.style.color = "var(--accent-foreground)";
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = "transparent";
              e.currentTarget.style.color = "var(--muted-foreground)";
            }}
            title="Try It"
          >
            <Play className="h-3.5 w-3.5" />
          </button>
          <button
            onClick={() => onHistory(prompt.slug)}
            className="rounded p-1.5 transition-colors"
            style={{ color: "var(--muted-foreground)" }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = "var(--accent)";
              e.currentTarget.style.color = "var(--accent-foreground)";
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = "transparent";
              e.currentTarget.style.color = "var(--muted-foreground)";
            }}
            title="Version History"
          >
            <History className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
    </div>
  );
}
