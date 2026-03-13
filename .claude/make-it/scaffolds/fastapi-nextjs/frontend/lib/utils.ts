import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Merge Tailwind CSS classes with clsx.
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/**
 * Format a date string as a short date (e.g. "Mar 13, 2026").
 */
export function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

/**
 * Format a date string with time (e.g. "Mar 13, 2026 2:30 PM").
 */
export function formatDateTime(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/**
 * Format a date string as a relative time (e.g. "3 days ago", "in 2 hours").
 */
export function formatRelative(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSecs = Math.floor(Math.abs(diffMs) / 1000);
  const diffMins = Math.floor(diffSecs / 60);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);
  const isFuture = diffMs < 0;

  const wrap = (value: number, unit: string) => {
    const label = `${value} ${unit}${value === 1 ? "" : "s"}`;
    return isFuture ? `in ${label}` : `${label} ago`;
  };

  if (diffSecs < 60) return "just now";
  if (diffMins < 60) return wrap(diffMins, "minute");
  if (diffHours < 24) return wrap(diffHours, "hour");
  if (diffDays < 30) return wrap(diffDays, "day");
  return formatDate(dateString);
}

/**
 * Return the number of days until a date (negative if past).
 */
export function daysUntil(dateString: string): number {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = date.getTime() - now.getTime();
  return Math.ceil(diffMs / (1000 * 60 * 60 * 24));
}
