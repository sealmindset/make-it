# PWA Scaffold Overlay

This overlay adds Progressive Web App (PWA) capabilities to the base `fastapi-nextjs` scaffold.

## What This Overlay Provides

### New Files

| File | Purpose |
|------|---------|
| `frontend/public/manifest.json` | Web app manifest with `[BRACKET_PLACEHOLDERS]` |
| `frontend/public/icons/.gitkeep` | Placeholder for generated app icons (192, 512, maskable) |
| `frontend/components/install-prompt.tsx` | "Add to Home Screen" banner using `beforeinstallprompt` |
| `frontend/components/offline-indicator.tsx` | Top banner shown when browser goes offline |
| `frontend/components/pull-to-refresh.tsx` | Touch gesture handler for mobile refresh |
| `frontend/lib/pwa.ts` | Service worker registration helpers |
| `frontend/lib/use-online-status.ts` | React hook for online/offline detection |
| `frontend/app/sw.ts` | Serwist service worker config (precaching + runtime caching + offline fallback) |
| `frontend/app/offline/page.tsx` | Offline fallback page |

### Base Scaffold Modifications (Applied During Build)

| Base File | Modification |
|-----------|-------------|
| `frontend/package.json` | Add `@serwist/next` and `serwist` to dependencies |
| `frontend/next.config.ts` | Wrap config with `withSerwist()` from `@serwist/next` |
| `frontend/app/layout.tsx` | Add viewport meta (viewport-fit=cover), theme-color, manifest link, Apple PWA meta tags |
| `frontend/app/(auth)/layout.tsx` | Add `<OfflineIndicator />` in header area, conditional `<InstallPrompt />` |
| `frontend/app/globals.css` | Add responsive touch utilities, safe-area-inset padding, tap-highlight override |

## PWA Library

Uses **Serwist** (`@serwist/next`) — the actively maintained successor to `next-pwa`.
- TypeScript-first, Next.js 15+ compatible
- Automatic precaching of build output
- Runtime caching with sensible defaults
- Navigation preload for faster page loads
- Offline fallback via the `/offline` route

## How It's Applied

During the Build phase (`make-it.md`, step h of Phase A):
1. Overlay files are copied into the project on top of the base scaffold
2. `[BRACKET_PLACEHOLDERS]` are replaced using the same app-context values
3. Base scaffold modifications are applied as instructions (not patches)
4. Placeholder icons are generated (colored square + app initial)

## Guardrail Checks (P01-P08)

See `build-standards.md` for the full list. Key checks:
- P02 [BLOCK]: Valid manifest.json with required fields
- P03 [BLOCK]: Service worker compiles and serves at /sw.js
- P04 [FIX]: Touch targets minimum 44x44px
- P06 [FIX]: Offline fallback page exists and is served
