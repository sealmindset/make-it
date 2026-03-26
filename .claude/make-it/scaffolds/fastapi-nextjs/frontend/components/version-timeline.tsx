"use client";

import { useState } from "react";
import { RotateCcw, GitCompare } from "lucide-react";
import { formatRelative } from "@/lib/utils";
import type { PromptVersion } from "@/lib/types";

interface VersionTimelineProps {
  versions: PromptVersion[];
  currentVersion: number;
  onRestore: (version: number) => void;
  onDiff: (v1: number, v2: number) => void;
}

export function VersionTimeline({
  versions,
  currentVersion,
  onRestore,
  onDiff,
}: VersionTimelineProps) {
  const [compareA, setCompareA] = useState<number | null>(null);
  const [compareB, setCompareB] = useState<number | null>(null);

  const handleCompareToggle = (version: number) => {
    if (compareA === version) {
      setCompareA(null);
    } else if (compareB === version) {
      setCompareB(null);
    } else if (compareA === null) {
      setCompareA(version);
    } else if (compareB === null) {
      setCompareB(version);
    } else {
      // Replace the oldest selection
      setCompareA(compareB);
      setCompareB(version);
    }
  };

  const canCompare = compareA !== null && compareB !== null;

  return (
    <div className="space-y-4">
      {/* Compare button */}
      {canCompare && (
        <div className="flex items-center gap-2">
          <button
            onClick={() => onDiff(compareA!, compareB!)}
            className="inline-flex items-center gap-2 rounded-md px-3 py-1.5 text-sm font-medium"
            style={{
              backgroundColor: "var(--primary)",
              color: "var(--primary-foreground)",
            }}
          >
            <GitCompare className="h-4 w-4" />
            Compare v{compareA} with v{compareB}
          </button>
          <button
            onClick={() => {
              setCompareA(null);
              setCompareB(null);
            }}
            className="text-sm"
            style={{ color: "var(--muted-foreground)" }}
          >
            Clear selection
          </button>
        </div>
      )}

      {/* Timeline */}
      <div className="relative">
        {/* Vertical line */}
        <div
          className="absolute left-3 top-3 bottom-3 w-0.5"
          style={{ backgroundColor: "var(--border)" }}
        />

        <div className="space-y-0">
          {versions.map((version) => {
            const isCurrent = version.version === currentVersion;
            const isSelected =
              compareA === version.version || compareB === version.version;

            return (
              <div key={version.id} className="relative flex gap-4 py-3">
                {/* Dot */}
                <div className="relative z-10 flex shrink-0">
                  <button
                    onClick={() => handleCompareToggle(version.version)}
                    className="h-6 w-6 rounded-full border-2 transition-colors"
                    style={{
                      backgroundColor: isCurrent
                        ? "var(--primary)"
                        : isSelected
                          ? "color-mix(in oklch, var(--primary) 40%, transparent)"
                          : "var(--background)",
                      borderColor: isCurrent || isSelected
                        ? "var(--primary)"
                        : "var(--border)",
                    }}
                    title={`${isSelected ? "Deselect" : "Select"} for comparison`}
                  />
                </div>

                {/* Content */}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold">
                      Version {version.version}
                    </span>
                    {isCurrent && (
                      <span
                        className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
                        style={{
                          backgroundColor:
                            "color-mix(in oklch, var(--success) 15%, transparent)",
                          color: "var(--success)",
                        }}
                      >
                        Current
                      </span>
                    )}
                  </div>

                  {version.change_summary && (
                    <p
                      className="mt-0.5 text-sm"
                      style={{ color: "var(--muted-foreground)" }}
                    >
                      {version.change_summary}
                    </p>
                  )}

                  <div
                    className="mt-1 flex items-center gap-3 text-xs"
                    style={{ color: "var(--muted-foreground)" }}
                  >
                    <span>{version.created_by}</span>
                    <span>{formatRelative(version.created_at)}</span>
                  </div>

                  {/* Restore button (not shown for current version) */}
                  {!isCurrent && (
                    <button
                      onClick={() => onRestore(version.version)}
                      className="mt-2 inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium transition-colors"
                      style={{
                        backgroundColor:
                          "color-mix(in oklch, var(--primary) 10%, transparent)",
                        color: "var(--primary)",
                      }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.backgroundColor =
                          "color-mix(in oklch, var(--primary) 20%, transparent)";
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.backgroundColor =
                          "color-mix(in oklch, var(--primary) 10%, transparent)";
                      }}
                    >
                      <RotateCcw className="h-3 w-3" />
                      Restore this version
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
