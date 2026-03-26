"use client";

interface SafetyIndicatorProps {
  level: "safe" | "caution";
  label?: string;
}

const config = {
  safe: {
    color: "var(--success)",
    text: "Safe to edit",
  },
  caution: {
    color: "var(--warning)",
    text: "Affects AI behavior",
  },
};

export function SafetyIndicator({ level, label }: SafetyIndicatorProps) {
  const { color, text } = config[level];
  const displayLabel = label || text;

  return (
    <span className="inline-flex items-center gap-1.5 text-xs font-medium">
      <span
        className="h-2 w-2 rounded-full"
        style={{ backgroundColor: color }}
      />
      <span style={{ color }}>{displayLabel}</span>
    </span>
  );
}
