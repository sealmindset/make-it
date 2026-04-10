# Variant: Mobile (PWA)

## Metadata

- **Name:** mobile
- **Base project type:** web-app
- **Scaffold overlay:** overlays/pwa/
- **Extends tiers:** 0, 1
- **Composable with:** none (standalone)

---

## Ideation Additions

These questions are woven into the standard ideation conversation — NOT asked as a separate block. They should feel natural, like follow-ups to the user's description of their app.

1. **Offline capability:** "Will people need to use this app when they don't have an internet connection? For example, on a plane or in an area with bad signal?"
   - Follow-up if yes: "What parts should work offline — just viewing existing data, or should they be able to make changes that sync later?"
   - Maps to: `variant_config.offline_support`
   - Values: `"none"` (app shell caching only) | `"read-only"` (cache API responses, show stale data) | `"full-sync"` (queue mutations offline, sync when back online)
   - Default if user is unsure: `"read-only"`

2. **Push notifications:** "Should the app be able to send alerts to people's phones, even when they're not using it?"
   - Follow-up if yes: "What kinds of things should trigger an alert?"
   - Maps to: `variant_config.push_notifications`
   - Values: `true` | `false`
   - Default: `false` (can be added later via /resume-it)

3. **Install experience:** "Do you want people to be able to install this as an app on their phone's home screen, so it feels like a regular app?"
   - This is usually just confirmed, not a deep question
   - Maps to: `variant_config.installable`
   - Values: `true` | `false`
   - Default: `true` (this is the main value proposition of the mobile variant)

4. **Primary device:** "Will most people use this on their phone, on a computer, or both equally?"
   - Maps to: `variant_config.primary_device`
   - Values: `"mobile-first"` | `"desktop-first"` | `"equal"`
   - Default: `"mobile-first"` (user chose the mobile variant, so this is likely)
   - Affects: responsive breakpoint strategy, touch target sizing, layout defaults

---

## Design Additions

These decisions are made silently during the Design phase. The user never sees them.

- **PWA library selection:** Always use `@serwist/next` (Serwist). Rationale: `next-pwa` is unmaintained (last release 2022). Serwist is its actively maintained successor with Next.js 15+ support, TypeScript-first, and explicit service worker control. Manual service workers are too error-prone for generated code. → Records `variant_config.pwa_library: "serwist"`

- **Responsive strategy:** Based on `variant_config.primary_device`:
  - `"mobile-first"` → Use `min-width` breakpoints in Tailwind. Touch-first interactions. Default mobile layout with progressive desktop enhancement.
  - `"desktop-first"` → Use `max-width` breakpoints (this is the existing scaffold default). Mobile is responsive but not the primary design target.
  - `"equal"` → Use `min-width` breakpoints (mobile-first) with explicit desktop enhancements at `md:` and `lg:` breakpoints.

- **Offline caching strategy:** Based on `variant_config.offline_support`:
  - `"none"` → Cache app shell only (HTML, CSS, JS). All API calls are network-only. The service worker exists for install + performance only.
  - `"read-only"` → Cache API GET responses with stale-while-revalidate strategy. When offline, show cached data. Mutations fail gracefully with a user-visible message.
  - `"full-sync"` → Same as read-only, plus: IndexedDB queue for POST/PUT/DELETE. When online resumes, replay the queue in order. Conflict resolution: last-write-wins with user notification. Requires a `/api/sync` endpoint on the backend.

- **Service worker dev mode:** Configure Serwist's dev options to disable the service worker in development (prevents caching stale dev builds). Only enable in production builds.

- **Icon generation:** During Build, generate placeholder icons:
  - 192x192 PNG (colored square with app initial in white, using theme_color as background)
  - 512x512 PNG (same design, larger)
  - 512x512 maskable PNG (same with safe-zone padding)
  - Add "Replace placeholder icons with branded versions" to TODO.md
  - Records `variant_config.icons_generated: false` (set to true after real icons are provided)

- **App colors:** Extract from the scaffold's oklch theme:
  - `variant_config.app_theme_color` → the primary color from CSS variables, converted to hex for manifest.json
  - `variant_config.app_background_color` → "#ffffff" (light mode default)

---

## App-Context Additions

```json
{
  "variant": "mobile",
  "variant_config": {
    "offline_support": "read-only",
    "push_notifications": false,
    "installable": true,
    "primary_device": "mobile-first",
    "pwa_library": "serwist",
    "service_worker_strategy": "stale-while-revalidate",
    "icons_generated": false,
    "app_theme_color": "#3b82f6",
    "app_background_color": "#ffffff"
  }
}
```

---

## Scaffold Overlay

### New files (from `overlays/pwa/` directory)

These files are copied into the project after the base scaffold:

| File | Purpose |
|------|---------|
| `frontend/public/manifest.json` | PWA manifest with [BRACKET_PLACEHOLDERS] for name, icons, colors |
| `frontend/public/icons/.gitkeep` | Placeholder for app icons (192, 512, maskable) |
| `frontend/components/install-prompt.tsx` | "Add to Home Screen" banner component |
| `frontend/components/offline-indicator.tsx` | Top banner showing offline/online status |
| `frontend/components/pull-to-refresh.tsx` | Pull-to-refresh gesture handler for mobile |
| `frontend/lib/pwa.ts` | Service worker registration and status helpers |
| `frontend/lib/use-online-status.ts` | React hook for online/offline detection |
| `frontend/app/sw.ts` | Serwist service worker configuration |
| `frontend/app/offline/page.tsx` | Offline fallback page |

### Base scaffold modifications

Instructions for modifying existing base scaffold files during Build:

| Base File | What to Change |
|-----------|---------------|
| `frontend/package.json` | Add `"@serwist/next": "^9"` and `"serwist": "^9"` to `dependencies` |
| `frontend/next.config.ts` | Import `withSerwist` from `@serwist/next`. Wrap the existing config: `export default withSerwist({ swSrc: "app/sw.ts", swDest: "public/sw.js", disable: process.env.NODE_ENV === "development" })(existingConfig)` |
| `frontend/app/layout.tsx` | In the `<head>` or metadata, add: `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`, `<meta name="theme-color" content="[APP_THEME_COLOR]">`, `<link rel="manifest" href="/manifest.json">`, `<meta name="apple-mobile-web-app-capable" content="yes">`, `<meta name="apple-mobile-web-app-status-bar-style" content="default">`, `<link rel="apple-touch-icon" href="/icons/icon-192x192.png">` |
| `frontend/app/(auth)/layout.tsx` | Add `<OfflineIndicator />` in the header area (import from `@/components/offline-indicator`). Add `<InstallPrompt />` at the bottom of the layout (import from `@/components/install-prompt`). |
| `frontend/app/globals.css` | Add: `html { -webkit-tap-highlight-color: transparent; }`, `body { padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); }`, and ensure all interactive elements have `min-height: 44px; min-width: 44px;` via a utility class `.touch-target { min-height: 2.75rem; min-width: 2.75rem; }` |

---

## Guardrail Additions

These checks use the `P` prefix (for PWA) and are qualified with `[Tier 1+mobile]` so they only activate when the mobile variant is in use.

| ID | Tier+Variant | Severity | Check | Description |
|----|-------------|----------|-------|-------------|
| P01 | [Tier 1+mobile] | [FIX] | Viewport meta tag | `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">` present in root layout. `viewport-fit=cover` enables safe-area-inset for notched devices (iPhone, etc.). |
| P02 | [Tier 1+mobile] | [BLOCK] | Web app manifest | `public/manifest.json` exists with required fields: `name`, `short_name`, `start_url: "/"`, `display: "standalone"`, `background_color`, `theme_color`, `icons` array with at least 192x192 and 512x512 entries. All referenced icon files must exist. |
| P03 | [Tier 1+mobile] | [BLOCK] | Service worker compiles | `app/sw.ts` exists, `@serwist/next` is in `package.json` dependencies, and the built app serves `/sw.js` as a JavaScript file at runtime. |
| P04 | [Tier 1+mobile] | [FIX] | Touch targets 44px minimum | All interactive elements (buttons, links, form controls) have minimum 44x44px touch target. Use Tailwind `min-h-11 min-w-11` or the `.touch-target` utility. Grep page files for `h-6`, `h-8`, `w-6`, `w-8` on interactive elements as potential violations. |
| P05 | [Tier 1+mobile] | [FIX] | No horizontal overflow | No page causes horizontal scroll on a 375px viewport. `overflow-x: hidden` on body as safeguard, but root cause must be proper responsive layout. Check for fixed-width elements wider than 375px. |
| P06 | [Tier 1+mobile] | [FIX] | Offline fallback page | `app/offline/page.tsx` exists. Service worker config in `sw.ts` includes a navigation fallback to `/offline`. When the app is offline, navigating to any page shows the fallback instead of the browser's default error. |
| P07 | [Tier 1+mobile] | [WARN] | PWA installable | The app meets Lighthouse PWA installability criteria: valid manifest, registered service worker, served over HTTPS (or localhost for dev). Document in TODO.md if not passing — this is informational, not blocking. |
| P08 | [Tier 1+mobile] | [FIX] | Apple PWA meta tags | `<meta name="apple-mobile-web-app-capable" content="yes">`, `<meta name="apple-mobile-web-app-status-bar-style" content="default">`, and `<link rel="apple-touch-icon" href="/icons/icon-192x192.png">` present in root layout. Required for iOS home screen app experience. |

---

## Build-Verify Additions

### Static checks (Part A)

These can be verified by reading files without running the app:

- **P01**: Grep root layout (`app/layout.tsx`) for `viewport-fit=cover` in a viewport meta tag
- **P02**: Read `public/manifest.json`, validate it has `name`, `short_name`, `start_url`, `display: "standalone"`, `background_color`, `theme_color`, and `icons` with 192 and 512 entries. Verify each icon file in `public/icons/` exists.
- **P03**: Verify `app/sw.ts` exists. Verify `@serwist/next` is in `package.json` dependencies. Verify `next.config.ts` imports and uses `withSerwist`.
- **P04**: Grep all `.tsx` files under `app/(auth)/` for interactive elements (`<button`, `<Button`, `<a `, `<Link`) that use size classes smaller than 44px (`h-6`, `h-7`, `h-8`, `w-6`, `w-7`, `w-8`). Flag potential violations.
- **P05**: Grep for fixed-width classes wider than mobile (`w-[400px]`, `min-w-[400px]`, etc.) in page files.
- **P06**: Verify `app/offline/page.tsx` exists. Read `sw.ts` and verify it has a navigation fallback entry pointing to `/offline`.
- **P08**: Grep root layout for `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, and `apple-touch-icon`.

### Live checks (Part B)

These require the app to be running in Docker:

- **P02 (live)**: `curl http://localhost:[FRONTEND_PORT]/manifest.json` — verify it returns valid JSON with `Content-Type: application/manifest+json` (or `application/json`)
- **P03 (live)**: `curl -sI http://localhost:[FRONTEND_PORT]/sw.js` — verify it returns 200 with JavaScript content type
- **P07**: Note in build-verify output that Lighthouse PWA audit should be run manually (requires browser). Add to TODO.md if not yet done.

---

## Build Standards Additions

These check IDs should be added to `build-standards.md` under a new "PWA / Mobile" category:

| ID | Tier+Variant | Severity | Check | Description |
|----|-------------|----------|-------|-------------|
| P01 | [Tier 1+mobile] | [FIX] | Viewport meta | Root layout has `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`. |
| P02 | [Tier 1+mobile] | [BLOCK] | Manifest valid | `public/manifest.json` has name, short_name, start_url="/", display="standalone", background_color, theme_color, icons (192+512 with existing files). |
| P03 | [Tier 1+mobile] | [BLOCK] | Service worker compiles | `app/sw.ts` exists, `@serwist/next` in deps, `/sw.js` served at runtime. |
| P04 | [Tier 1+mobile] | [FIX] | Touch targets 44px+ | All interactive elements meet minimum 44x44px touch target size. |
| P05 | [Tier 1+mobile] | [FIX] | No horizontal overflow | No page causes horizontal scroll at 375px viewport width. |
| P06 | [Tier 1+mobile] | [FIX] | Offline fallback | `app/offline/page.tsx` exists and service worker serves it when network unavailable. |
| P07 | [Tier 1+mobile] | [WARN] | Lighthouse PWA | App passes Lighthouse installability check. Document in TODO.md. |
| P08 | [Tier 1+mobile] | [FIX] | Apple PWA meta | apple-mobile-web-app-capable, apple-touch-icon present in root layout. |
