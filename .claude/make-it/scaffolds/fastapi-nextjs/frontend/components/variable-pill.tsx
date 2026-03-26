"use client";

interface VariablePillProps {
  name: string;
  description?: string;
}

/**
 * Renders a {variable} as a friendly inline pill with tooltip.
 * Non-technical users see these as clickable labels instead of raw curly braces.
 */
export function VariablePill({ name, description }: VariablePillProps) {
  const tooltip =
    description || `This is replaced with dynamic content when the AI runs`;

  return (
    <span
      className="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium cursor-help"
      style={{
        backgroundColor: "color-mix(in oklch, var(--primary) 15%, transparent)",
        color: "var(--primary)",
      }}
      title={tooltip}
    >
      {name}
    </span>
  );
}

/**
 * Extracts {variable_name} patterns from a prompt template string.
 */
export function extractVariables(template: string): string[] {
  const matches = template.match(/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/g);
  if (!matches) return [];
  return [...new Set(matches.map((m) => m.slice(1, -1)))];
}
