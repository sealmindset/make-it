/**
 * PWA service worker registration utility.
 *
 * Serwist handles the service worker lifecycle automatically via its Next.js
 * integration (`@serwist/next`). This module provides helpers for checking
 * registration status and triggering manual updates.
 */

export async function getRegistration(): Promise<
  ServiceWorkerRegistration | undefined
> {
  if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) {
    return undefined;
  }
  return navigator.serviceWorker.getRegistration();
}

export async function checkForUpdates(): Promise<void> {
  const registration = await getRegistration();
  if (registration) {
    await registration.update();
  }
}

export function isServiceWorkerSupported(): boolean {
  return (
    typeof navigator !== "undefined" && "serviceWorker" in navigator
  );
}

export function isStandalone(): boolean {
  if (typeof window === "undefined") return false;
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    (window.navigator as Navigator & { standalone?: boolean }).standalone ===
      true
  );
}
