"use client";

import { useRouter } from "next/navigation";
import { AuthProvider, useAuth } from "@/lib/auth-context";
import { Sidebar, SidebarTrigger } from "@/components/layout/sidebar";
import { Breadcrumbs } from "@/components/breadcrumbs";
import { QuickSearch } from "@/components/quick-search";
import { ModeToggle } from "@/components/mode-toggle";

function AuthenticatedShell({ children }: { children: React.ReactNode }) {
  const { authMe, loading } = useAuth();
  const router = useRouter();

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <div
          className="h-8 w-8 animate-spin rounded-full border-4 border-t-transparent"
          style={{ borderColor: "var(--primary)", borderTopColor: "transparent" }}
        />
      </div>
    );
  }

  if (!authMe) {
    router.replace("/login");
    return null;
  }

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar />
      <div className="flex flex-1 flex-col overflow-hidden">
        <header
          className="flex h-14 shrink-0 items-center gap-3 border-b px-4"
          style={{
            backgroundColor: "var(--background)",
            borderColor: "var(--border)",
          }}
        >
          <SidebarTrigger />
          <Breadcrumbs />
          <div className="flex-1" />
          <QuickSearch />
          <ModeToggle />
        </header>

        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <AuthProvider>
      <AuthenticatedShell>{children}</AuthenticatedShell>
    </AuthProvider>
  );
}
