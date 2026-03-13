"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/lib/auth";

interface SearchItem {
  label: string;
  href: string;
  keywords?: string[];
  permission?: { resource: string; action: string };
}

// [NAVIGATION_ITEMS] -- searchable pages
const navigationItems: SearchItem[] = [
  { label: "Dashboard", href: "/dashboard", keywords: ["home", "overview"] },
  // [NAVIGATION_ITEMS] -- app-specific pages, e.g.:
  // { label: "Projects", href: "/projects", keywords: ["project", "list"], permission: { resource: "projects", action: "view" } },
  {
    label: "User Management",
    href: "/admin/users",
    keywords: ["users", "admin", "people"],
    permission: { resource: "users", action: "view" },
  },
  {
    label: "Role Management",
    href: "/admin/roles",
    keywords: ["roles", "permissions", "admin"],
    permission: { resource: "roles", action: "view" },
  },
];

export function QuickSearch() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const router = useRouter();
  const { hasPermission } = useAuth();

  const filteredItems = navigationItems
    .filter((item) => {
      if (item.permission) {
        return hasPermission(item.permission.resource, item.permission.action);
      }
      return true;
    })
    .filter((item) => {
      if (!query) return true;
      const q = query.toLowerCase();
      return (
        item.label.toLowerCase().includes(q) ||
        item.href.toLowerCase().includes(q) ||
        item.keywords?.some((k) => k.includes(q))
      );
    });

  const navigate = useCallback(
    (href: string) => {
      setOpen(false);
      setQuery("");
      router.push(href);
    },
    [router],
  );

  // Cmd+K / Ctrl+K to open
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setOpen((prev) => !prev);
      }
      if (e.key === "Escape") {
        setOpen(false);
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, []);

  // Focus input when opened
  useEffect(() => {
    if (open) {
      setTimeout(() => inputRef.current?.focus(), 50);
      setQuery("");
      setSelectedIndex(0);
    }
  }, [open]);

  // Keyboard nav in list
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIndex((i) => Math.min(i + 1, filteredItems.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter" && filteredItems[selectedIndex]) {
      navigate(filteredItems[selectedIndex].href);
    }
  };

  return (
    <>
      {/* Trigger button */}
      <button
        onClick={() => setOpen(true)}
        className="inline-flex h-9 items-center gap-2 rounded-md border border-input bg-background px-3 text-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground"
      >
        <Search className="h-4 w-4" />
        <span className="hidden sm:inline">Search...</span>
        <kbd className="pointer-events-none hidden select-none rounded border border-border bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground sm:inline">
          {typeof navigator !== "undefined" &&
          navigator.platform?.includes("Mac")
            ? "\u2318K"
            : "Ctrl+K"}
        </kbd>
      </button>

      {/* Modal overlay */}
      {open && (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center pt-[20vh] bg-black/50"
          onClick={() => setOpen(false)}
        >
          <div
            className="w-full max-w-lg rounded-xl border border-border bg-card shadow-lg"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Search input */}
            <div className="flex items-center gap-2 border-b border-border px-4 py-3">
              <Search className="h-4 w-4 text-muted-foreground" />
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setSelectedIndex(0);
                }}
                onKeyDown={onKeyDown}
                placeholder="Search pages..."
                className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
              />
            </div>

            {/* Results */}
            <ul className="max-h-72 overflow-y-auto p-2">
              {filteredItems.length === 0 && (
                <li className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No results found.
                </li>
              )}
              {filteredItems.map((item, i) => (
                <li key={item.href}>
                  <button
                    onClick={() => navigate(item.href)}
                    className={cn(
                      "flex w-full items-center rounded-md px-3 py-2 text-sm transition-colors",
                      i === selectedIndex
                        ? "bg-accent text-accent-foreground"
                        : "text-foreground hover:bg-accent/50",
                    )}
                  >
                    {item.label}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </>
  );
}
