# SECTION 7: THE SCAFFOLD (98 FILES)

---

## Slide 45 -- The Scaffold: What's Inside

**Gemini Image Prompt:**
```
Plain white background, 16:9. Center: large translucent rounded rectangle with
"98" in huge bold navy text. Below the number: "files" in small light text.

From the center, 6 groups float outward in exploded-view arrangement:

Top-left (blue): "Backend" -- Auth, RBAC, API, Models, Migrations, Logs
Top-right (green): "Frontend" -- Login, DataTable, Sidebar, Search, Admin
Mid-left (amber): "Auth" -- OIDC, JWT, Mock, Multi-Role, Permissions
Mid-right (purple): "AI" -- Tables, Routes, Pages, Editing, Versions
Bot-left (coral): "Infrastructure" -- Docker, Health, Entrypoint, Config
Bot-right (teal): "Quality" -- pytest, Playwright, Fixtures, E2E

Thin lines connect each group to center. The groups float like an Apple
product teardown -- precision instrument with every component laid out.

Bottom: "Every file exists because a real bug taught us it should."
```

**Slide Text:**
### The scaffold: 98 pre-built, pre-verified files

| Group | Files include | Why it matters |
|---|---|---|
| **Backend** | Auth flow, RBAC middleware, API routes, models, migrations | Secure API from the start |
| **Frontend** | Login page, DataTable, sidebar, search, admin pages | Polished UI immediately |
| **Auth** | OIDC integration, JWT handling, mock server, multi-role | Enterprise login works day one |
| **AI Management** | 6 tables, ~25 routes, 4 pages, 5 components | AI prompt editing for non-technical users |
| **Infrastructure** | Docker Compose, health checks, entrypoint scripts | Runs anywhere, consistently |
| **Quality** | pytest config, fixtures, health tests, Playwright setup | Testing infrastructure ready |

**Every file was debugged once and never regenerated.** The scaffold is the accumulated knowledge of every app built before yours.

---

## Slide 46 -- The Scaffold: Why 98 Files?

**Gemini Image Prompt:**
```
Plain white background, 16:9. A timeline/journey showing how the scaffold evolved.

Left side (coral, "Before scaffold"): Scattered bug icons, retry arrows, and
frustrated emoji-free indicators. Labels: "Auth bug #1", "Docker IPv6 issue",
"Cookie not setting", "Permission mismatch", "Empty pages", "Port conflict"

Center: A thick vertical line labeled "Lessons encoded"

Right side (green, "After scaffold"): A clean stack of organized file icons,
all with green checkmarks. Labels: "Pre-verified auth", "Health checks on
127.0.0.1", "Same-origin proxy", "Permission seed alignment", "Seed data
ready", "Port availability check"

Bottom: "Every bug became a file. Every fix became permanent."
```

**Slide Text:**
### Why 98 files? Because every bug became a permanent fix.

**Real problems that are now solved forever in the scaffold:**

| Bug we hit | File that prevents it |
|---|---|
| Docker health checks fail on IPv6 | Health checks hardcoded to 127.0.0.1 |
| Auth cookies blocked by cross-origin | Same-origin proxy in next.config.ts |
| Logout via GET link (browser prefetch triggers it) | POST-only logout endpoint |
| External fonts blocked by corporate proxy | System font stack, no CDN |
| Empty pages after deploy | Seed data in migrations + entrypoint.sh |
| Permission names mismatched across stack | Consistent naming enforced in 5 locations |
| Multiple roles not granting combined permissions | user_roles junction table + union logic |
| FastAPI redirects leaking Docker hostnames | Trailing-slash ASGI middleware |
| Next.js 16 stripping Set-Cookie on redirect | HTML response with meta-refresh workaround |

**The scaffold doesn't just build your app. It prevents every known failure mode.**

---

## Slide 47 -- The Scaffold: What It Provides vs What It Generates

**Gemini Image Prompt:**
```
Plain white background, 16:9. Two columns side by side.

LEFT column (blue border) "Scaffold provides (pre-built)":
A stack of items with blue dots:
- Authentication flow
- RBAC (5 tables, 4 roles)
- Standard UI components
- Docker Compose
- mock-oidc server
- Activity logs
- Notifications
- App settings
- AI prompt management
- Test infrastructure

RIGHT column (green border) "Generated fresh (per app)":
A stack of items with green dots:
- Domain models (your data)
- Database migrations (your tables)
- API routes (your endpoints)
- Frontend pages (your screens)
- Dashboard widgets (your metrics)
- Seed data (your test data)
- External mock services (your integrations)

Center divider line labeled "Foundation vs Features"

The left is universal. The right is unique to your app.
```

**Slide Text:**
### Foundation (universal) vs Features (unique to you)

**Scaffold provides (same for every app):**
- Authentication flow (OIDC → JWT → cookie → /me → logout)
- RBAC (5 tables, 4 system roles, permission middleware)
- Standard UI (DataTable, sidebar, search, breadcrumbs, dark mode)
- Docker environment (Compose, health checks, entrypoint)
- Mock login server (copied as-is, battle-tested)
- Activity logs, notifications, app settings
- Test infrastructure (pytest + Playwright scaffolding)

**Generated fresh (unique to your app):**
- Your domain models and database tables
- Your API endpoints and business logic
- Your frontend pages and dashboards
- Your seed data and test scenarios
- Your external service mocks
- Your Terraform infrastructure

**95% foundation. 5% your idea. 100% production-ready.**

---

## Slide 48 -- Activity Logs: Who Did What

**Gemini Image Prompt:**
```
Plain white background, 16:9. A log viewer mockup showing a clean admin page.

Header: "Activity Logs" with stat cards:
- "1,247 events" (total)
- "342 today" (today's count)
- "12ms avg" (response time)

Filter bar: Type dropdown, Service dropdown, Method dropdown, Search box

Table below with columns: Time, User, Method, Path, Status, Duration
Sample rows:
10:23:15 | admin@test.com | GET | /api/projects | 200 | 8ms
10:23:12 | manager@test.com | POST | /api/requests | 201 | 45ms
10:23:08 | user@test.com | GET | /api/dashboard | 200 | 12ms

Bottom: auto-refresh toggle, "Clear Buffer" button

Clean, functional, real-looking admin interface.
```

**Slide Text:**
### Activity logs: complete audit trail, zero configuration

Every /make-it web app captures:

| What's logged | Details |
|---|---|
| **Every inbound request** | Who, what URL, method, status, duration, IP |
| **Every outbound call** | Which external service, URL (sanitized), status, duration |
| **Skipped automatically** | Health checks and static assets (no noise) |

**Features:**
- 10,000-event circular buffer (configurable via LOG_BUFFER_SIZE)
- Admin UI with real-time stats, filters, and auto-refresh
- URL sanitization strips tokens, keys, and passwords before logging
- REST API for programmatic access
- RBAC-gated: admin.logs.read to view, admin.logs.delete to clear
- Ready for external log shipping (Cribl Stream placeholder included)

---

## Slide 49 -- Notifications: In-App Alerts

**Gemini Image Prompt:**
```
Plain white background, 16:9. Two parts:

TOP: A header bar mockup showing a bell icon with a red "3" badge. An open
dropdown panel below it shows:
- "Notifications" header + "Mark all read" link
- Three notification items:
  1. Red left border: "ESCALATION: Request #42 overdue" / "2m ago" / unread dot
  2. Orange left border: "APPROVAL: New request from Sarah" / "1h ago" / unread dot
  3. Blue left border: "INFO: Monthly report ready" / "3h ago" / no dot (read)
- Each has a small category icon

BOTTOM: A simple diagram showing notification flow:
"Backend event" → "Creates notification" → "Bell badge updates" → "User sees alert"

Clean, realistic, shows the feature working.
```

**Slide Text:**
### Notifications: the right people see the right alerts

**Built into every web app:**
- **Bell icon** with unread badge (updates every 30 seconds)
- **Dropdown panel** with notification list and "Mark all read"
- **Color-coded by type** (red = urgent, orange = action needed, blue = info)
- **Click to navigate** -- each notification links to the relevant page
- **Scoped per user** -- you only see notifications meant for you

**How notifications are created:**
- Server-side only (no public API for creating notifications)
- Created by backend logic when events happen (approval needed, status changed, etc.)
- Broadcast (everyone sees it) or targeted (specific user)
- 5+ seed notifications included for immediate demo

---

## Slide 50 -- App Settings: Admin-Configurable

**Gemini Image Prompt:**
```
Plain white background, 16:9. An admin settings page mockup.

Left sidebar tabs: "General", "Authentication", "Notifications", "Integrations"

Main area shows settings cards:
- "Application Name" -- text input with "Training Tracker" value
- "Session Timeout" -- dropdown showing "30 minutes"
- "OIDC Client ID" -- masked field showing "••••••••" with "Reveal" link
- "Log Buffer Size" -- number input showing "10000"
- "Notification Polling" -- toggle switch (ON)

Below settings: "Last modified by admin@test.com, 2 hours ago" audit note

Clean, professional admin interface. The masked field shows security awareness.
```

**Slide Text:**
### App settings: change behavior without touching code

Every web app gets an admin settings page where authorized users can:

| Capability | How it works |
|---|---|
| **View all settings** | Grouped by category, sensitive values masked |
| **Edit settings** | Inline editing, changes take effect immediately |
| **Reveal secrets** | Click to unmask (logged in audit trail) |
| **Audit trail** | Every change recorded: who, when, old value, new value |

**Cascading precedence:** Database setting > .env file > code default

**Security:**
- RBAC-gated (admin.settings.read and admin.settings.update)
- Sensitive values masked by default
- Graceful fallback (app works even with empty settings table)
- All .env variables seeded into the database with descriptions
