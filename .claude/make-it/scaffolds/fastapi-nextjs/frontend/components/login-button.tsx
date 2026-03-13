"use client";

export function LoginButton() {
  return (
    <button
      onClick={() => {
        // Browser navigation -- NOT fetch. The backend returns a 302 redirect
        // to the OIDC provider, which must happen in the browser's address bar.
        window.location.href = "/api/auth/login";
      }}
      className="inline-flex w-full items-center justify-center rounded-md px-6 py-3 text-sm font-medium shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-2"
      style={{
        backgroundColor: "var(--primary)",
        color: "var(--primary-foreground)",
        // ring uses --ring variable
      }}
    >
      Sign in with SSO
    </button>
  );
}
