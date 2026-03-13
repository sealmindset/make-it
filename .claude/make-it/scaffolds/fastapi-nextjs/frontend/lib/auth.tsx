"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";
import { apiGet, apiPost, ApiError } from "./api";
import type { AuthMe } from "./types";

interface AuthContextValue {
  authMe: AuthMe | null;
  loading: boolean;
  hasPermission: (resource: string, action: string) => boolean;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [authMe, setAuthMe] = useState<AuthMe | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchMe = useCallback(async () => {
    try {
      const me = await apiGet<AuthMe>("/auth/me");
      setAuthMe(me);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setAuthMe(null);
      } else {
        console.error("Failed to fetch auth state:", err);
        setAuthMe(null);
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchMe();
  }, [fetchMe]);

  const hasPermission = useCallback(
    (resource: string, action: string): boolean => {
      if (!authMe) return false;
      return authMe.permissions.includes(`${resource}.${action}`);
    },
    [authMe],
  );

  const logout = useCallback(async () => {
    try {
      await apiPost("/auth/logout");
    } catch {
      // Logout may return non-JSON; ignore errors
    }
    setAuthMe(null);
    window.location.href = "/";
  }, []);

  const refresh = useCallback(async () => {
    setLoading(true);
    await fetchMe();
  }, [fetchMe]);

  return (
    <AuthContext.Provider
      value={{ authMe, loading, hasPermission, logout, refresh }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return ctx;
}
