"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ChevronRight, Home } from "lucide-react";
import { cn } from "@/lib/utils";

// Human-readable labels for URL segments.
// Scaffold defaults are listed first; app-specific labels are added during build.
const segmentLabels: Record<string, string> = {
  // Scaffold pages (always present)
  dashboard: "Dashboard",
  admin: "Admin",
  users: "Users",
  roles: "Roles",
  settings: "Settings",
  logs: "Activity Logs",
  prompts: "AI Instructions",
  analytics: "Analytics",
  audit: "Audit Log",
  // [SEGMENT_LABELS] -- app-specific labels added by /make-it, e.g.:
  // projects: "Projects",
  // forecasts: "Forecasts",
};

function formatSegment(segment: string): string {
  if (segmentLabels[segment]) return segmentLabels[segment];
  // Convert kebab-case or snake_case to Title Case
  return segment
    .replace(/[-_]/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export function Breadcrumbs() {
  const pathname = usePathname();
  const segments = pathname.split("/").filter(Boolean);

  if (segments.length === 0) return null;

  const crumbs = segments.map((segment, index) => {
    const href = "/" + segments.slice(0, index + 1).join("/");
    const isLast = index === segments.length - 1;
    // UUIDs and numeric IDs are shown as-is (could be enhanced to fetch entity names)
    const isId =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        segment,
      ) || /^\d+$/.test(segment);
    const label = isId ? segment.slice(0, 8) + "..." : formatSegment(segment);

    return { href, label, isLast };
  });

  return (
    <nav aria-label="Breadcrumb" className="flex items-center text-sm">
      <Link
        href="/dashboard"
        className="text-muted-foreground transition-colors hover:text-foreground"
      >
        <Home className="h-4 w-4" />
      </Link>
      {crumbs.map((crumb) => (
        <span key={crumb.href} className="flex items-center">
          <ChevronRight className="mx-1.5 h-3.5 w-3.5 text-muted-foreground/50" />
          {crumb.isLast ? (
            <span className="font-medium text-foreground">{crumb.label}</span>
          ) : (
            <Link
              href={crumb.href}
              className={cn(
                "text-muted-foreground transition-colors hover:text-foreground",
              )}
            >
              {crumb.label}
            </Link>
          )}
        </span>
      ))}
    </nav>
  );
}
