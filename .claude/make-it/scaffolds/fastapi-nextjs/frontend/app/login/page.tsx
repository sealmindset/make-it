"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { apiGet, ApiError } from "@/lib/api";
import { LoginButton } from "@/components/login-button";
import type { AuthMe } from "@/lib/types";

export default function LoginPage() {
  const router = useRouter();
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    // Check for existing session -- if already logged in, redirect to dashboard
    apiGet<AuthMe>("/auth/me")
      .then(() => {
        router.replace("/dashboard");
      })
      .catch((err) => {
        // 401 is expected when not logged in -- show login UI
        if (err instanceof ApiError && err.status === 401) {
          setChecking(false);
          return;
        }
        // Other errors: still show login page
        console.error("Session check failed:", err);
        setChecking(false);
      });
  }, [router]);

  if (checking) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <div
          className="h-8 w-8 animate-spin rounded-full border-4 border-t-transparent"
          style={{ borderColor: "var(--primary)", borderTopColor: "transparent" }}
        />
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-8 p-4">
      {/* App identity */}
      <div className="text-center">
        <div className="mb-4 flex justify-center">
          <div
            className="flex h-16 w-16 items-center justify-center rounded-2xl text-2xl font-bold"
            style={{ backgroundColor: "var(--primary)", color: "var(--primary-foreground)" }}
          >
            {/* [APP_ICON] */}
            A
          </div>
        </div>
        <h1 className="text-3xl font-bold tracking-tight">
          [APP_NAME]
        </h1>
        <p className="mt-2" style={{ color: "var(--muted-foreground)" }}>
          [APP_TAGLINE]
        </p>
      </div>

      {/* Sign-in card */}
      <div
        className="w-full max-w-sm rounded-xl border p-6 shadow-sm"
        style={{
          backgroundColor: "var(--card)",
          borderColor: "var(--border)",
          color: "var(--card-foreground)",
        }}
      >
        <div className="space-y-4">
          <div className="space-y-2 text-center">
            <h2 className="text-lg font-semibold">Welcome</h2>
            <p className="text-sm" style={{ color: "var(--muted-foreground)" }}>
              Sign in with your organization account to continue.
            </p>
          </div>
          <LoginButton />
        </div>
      </div>

      {/* [APP_FEATURES] -- optional feature highlights below the sign-in card */}
      <div className="grid max-w-2xl gap-4 sm:grid-cols-3">
        {/* [FEATURE_CARDS] */}
      </div>
    </div>
  );
}
