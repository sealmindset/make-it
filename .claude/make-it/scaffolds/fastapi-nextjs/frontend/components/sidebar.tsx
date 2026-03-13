"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  ChevronLeft,
  ChevronRight,
  LogOut,
  LayoutDashboard,
  Users,
  Shield,
  // [NAV_ICONS] -- import additional icons for app-specific pages
} from "lucide-react";
import { useAuth } from "@/lib/auth";
import { cn } from "@/lib/utils";

interface NavItem {
  label: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  permission?: { resource: string; action: string };
}

// Base nav items every app gets. [NAV_ITEMS] are added below.
const navItems: NavItem[] = [
  {
    label: "Dashboard",
    href: "/dashboard",
    icon: LayoutDashboard,
  },
  // [NAV_ITEMS] -- app-specific pages inserted here, e.g.:
  // { label: "Projects", href: "/projects", icon: FolderKanban, permission: { resource: "projects", action: "view" } },
  {
    label: "Users",
    href: "/admin/users",
    icon: Users,
    permission: { resource: "users", action: "view" },
  },
  {
    label: "Roles",
    href: "/admin/roles",
    icon: Shield,
    permission: { resource: "roles", action: "view" },
  },
];

export function Sidebar() {
  const { authMe, hasPermission, logout } = useAuth();
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);

  const visibleItems = navItems.filter((item) => {
    if (!item.permission) return true;
    return hasPermission(item.permission.resource, item.permission.action);
  });

  return (
    <aside
      className={cn(
        "flex h-screen flex-col border-r border-border bg-card transition-all duration-200",
        collapsed ? "w-16" : "w-60",
      )}
    >
      {/* Header */}
      <div className="flex h-14 items-center gap-2 border-b border-border px-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-primary text-primary-foreground text-sm font-bold">
          {/* [APP_ICON] -- replace with app initial or icon */}
          A
        </div>
        {!collapsed && (
          <span className="truncate text-sm font-semibold">
            {/* [APP_NAME] */}
            [APP_NAME]
          </span>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto p-2">
        <ul className="space-y-1">
          {visibleItems.map((item) => {
            const isActive =
              pathname === item.href || pathname.startsWith(`${item.href}/`);
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className={cn(
                    "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors",
                    isActive
                      ? "bg-accent text-accent-foreground font-medium"
                      : "text-muted-foreground hover:bg-accent/50 hover:text-accent-foreground",
                    collapsed && "justify-center px-0",
                  )}
                  title={collapsed ? item.label : undefined}
                >
                  <item.icon className="h-4 w-4 shrink-0" />
                  {!collapsed && <span className="truncate">{item.label}</span>}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      {/* Footer */}
      <div className="border-t border-border p-2">
        {/* User info */}
        {authMe && !collapsed && (
          <div className="mb-2 px-3 py-1">
            <p className="truncate text-sm font-medium">{authMe.name}</p>
            <p className="truncate text-xs text-muted-foreground">
              {authMe.role_name}
            </p>
          </div>
        )}

        {/* Logout */}
        <button
          onClick={logout}
          className={cn(
            "flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive",
            collapsed && "justify-center px-0",
          )}
          title={collapsed ? "Sign out" : undefined}
        >
          <LogOut className="h-4 w-4 shrink-0" />
          {!collapsed && <span>Sign out</span>}
        </button>

        {/* Collapse toggle */}
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="mt-1 flex w-full items-center justify-center rounded-md py-1.5 text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground"
        >
          {collapsed ? (
            <ChevronRight className="h-4 w-4" />
          ) : (
            <ChevronLeft className="h-4 w-4" />
          )}
        </button>
      </div>
    </aside>
  );
}

export function SidebarTrigger({
  onClick,
}: {
  onClick?: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="inline-flex h-9 w-9 items-center justify-center rounded-md border border-input bg-background text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground lg:hidden"
    >
      <ChevronRight className="h-4 w-4" />
      <span className="sr-only">Toggle sidebar</span>
    </button>
  );
}
