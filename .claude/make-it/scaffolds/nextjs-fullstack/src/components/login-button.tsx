"use client";

export function LoginButton() {
  return (
    <button
      onClick={() => {
        // Browser navigation -- NOT fetch. The API route returns an HTML page
        // with Set-Cookie + redirect to the OIDC provider.
        window.location.href = "/api/auth/login";
      }}
      className="inline-flex w-full items-center justify-center rounded-md px-6 py-3 text-sm font-medium shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-2"
      style={{
        backgroundColor: "var(--primary)",
        color: "var(--primary-foreground)",
      }}
    >
      Sign in with SSO
    </button>
  );
}
