# SECTION 5: TECHNOLOGY STACK

---

## Slide 31 -- Technology Stack Overview

**Gemini Image Prompt:**
```
Plain white background, 16:9. A layered stack diagram (horizontal layers, viewed
slightly from the side). Six layers from bottom to top, each a different color
with icons and labels:

Bottom (slate): "Infrastructure" -- Docker icon, Kubernetes icon, Terraform icon
Layer 2 (coral): "Database" -- PostgreSQL icon, cylinder
Layer 3 (blue): "Backend" -- FastAPI/Python icon, API bracket
Layer 4 (green): "Frontend" -- Next.js/React icon, browser
Layer 5 (purple): "Security" -- Lock icon, OIDC, RBAC
Top (amber): "Your Features" -- star icon, sparkle

Each layer has small technology labels: Docker Compose, PostgreSQL 16,
FastAPI + Python 3.12, Next.js 15 + React + Tailwind, OIDC + JWT + RBAC

The stack reads bottom-to-top: infrastructure holds everything, your features
sit on top of a solid foundation.
```

**Slide Text:**
### The technology stack -- what powers your app

| Layer | Technology | Why this choice |
|---|---|---|
| **Frontend** | Next.js + React + Tailwind CSS | Fast, modern, great developer ecosystem |
| **UI Components** | shadcn/ui | Beautiful, accessible, customizable |
| **Backend** | FastAPI (Python 3.12) | Fast, automatic API docs, type-safe |
| **Database** | PostgreSQL 16 | Industry standard, reliable, powerful |
| **ORM** | SQLAlchemy + Alembic | Mature, handles migrations safely |
| **Authentication** | OIDC (your provider) | Enterprise standard single sign-on |
| **Local Auth** | mock-oidc (Python) | Test without real identity provider |
| **Containers** | Docker + Docker Compose | Runs the same everywhere |
| **Infrastructure** | Terraform (generated) | DevOps handoff artifact |
| **Deployment** | Kubernetes + Argo CD | Cloud-native, GitOps |

**You don't choose any of this.** /make-it selects the right stack based on your requirements.

---

## Slide 32 -- Frontend: What Users See

**Gemini Image Prompt:**
```
Plain white background, 16:9. A web app mockup showing the key UI elements, each
labeled with a callout line:

- Sidebar with navigation items → "Sidebar (permission-based)"
- Breadcrumb trail at top → "Breadcrumbs (auto-generated)"
- Search bar → "Quick Search (Cmd+K)"
- Sun/moon icon → "Dark/Light Mode"
- Bell icon with red badge → "Notifications (3 unread)"
- Data table with sort/filter icons → "DataTable (sort, filter, paginate)"
- Dashboard cards with numbers → "Dashboard Widgets"
- User avatar with role badge → "User Profile (role display)"

The mockup should look polished and modern. Each callout identifies a standard
component that comes free with every app.
```

**Slide Text:**
### Every app gets a polished, modern interface

**Standard components included in every web app:**

| Component | What it does |
|---|---|
| **Sidebar** | Navigation that shows/hides items based on your permissions |
| **Breadcrumbs** | Always know where you are in the app |
| **Quick Search** | Press Cmd+K to jump to any page instantly |
| **Dark/Light Mode** | One-click theme toggle with oklch color system |
| **DataTable** | Every list is sortable, filterable, paginated -- like Excel |
| **Notification Bell** | Unread badge, dropdown panel, color-coded by type |
| **Dashboard** | Metric cards, charts, at-a-glance overview |

**Design principle:** System fonts only (no external font CDNs). Works behind corporate firewalls and SSL-inspecting proxies.

---

## Slide 33 -- Backend: The API Layer

**Gemini Image Prompt:**
```
Plain white background, 16:9. A horizontal diagram showing the backend request flow.

Left: "Browser" icon → Arrow → "Same-Origin Proxy" (next.js rewrites /api/* to backend)
→ Arrow → "FastAPI Backend" box containing:
  - "Permission Check" (require_permission on every route)
  - "Business Logic"
  - "Database Query" (SQLAlchemy)
→ Arrow → "PostgreSQL" cylinder

Below the main flow, small detail callouts:
- "Automatic API docs at /docs (Swagger)"
- "Input validation on every endpoint"
- "Parameterized queries (no SQL injection)"
- "Activity log middleware (every request captured)"

The flow shows a secure, well-structured request path.
```

**Slide Text:**
### Backend: secure by default at every layer

**Every API request passes through:**
1. **Same-origin proxy** -- Frontend and backend share a domain (no cross-origin issues)
2. **Authentication** -- JWT cookie verified on every request
3. **Permission check** -- `require_permission(resource, action)` on every route
4. **Input validation** -- Pydantic schemas validate all incoming data
5. **Parameterized queries** -- SQL injection is impossible
6. **Activity logging** -- Every request captured (who, what, when, how long)

**Automatic API documentation** at /docs (Swagger UI) -- every endpoint documented.

---

## Slide 34 -- Database: The Data Layer

**Gemini Image Prompt:**
```
Plain white background, 16:9. An entity-relationship diagram showing the core
tables that every app gets. Clean, minimal style with boxes and relationship lines.

Core tables (blue):
- users (id, email, name, oidc_subject, primary_role_id)
- roles (id, name, is_system)
- permissions (id, resource, action)
- role_permissions (role_id, permission_id)
- user_roles (user_id, role_id)

Relationship lines: users → roles (primary), users ↔ user_roles ↔ roles (many-to-many)
roles ↔ role_permissions ↔ permissions (many-to-many)

A dashed box labeled "Your Domain Tables" (green outline) sits below, suggesting
app-specific tables are added on top.

Title: "5 RBAC tables. Every app. Automatically."
```

**Slide Text:**
### Database: enterprise permission model built in

**5 tables power the permission system (created automatically):**

| Table | Purpose |
|---|---|
| **users** | Your app's users (linked to login system) |
| **roles** | Named roles: Super Admin, Admin, Manager, User + custom |
| **permissions** | What actions exist: `projects.read`, `projects.create`, etc. |
| **role_permissions** | Which role has which permissions (the matrix) |
| **user_roles** | Which users have which roles (many-to-many) |

**Key design:**
- Users can have **multiple roles** (Manager + Project Lead)
- Permissions are the **union** across all roles (if any role grants it, you have it)
- Roles come from the **database**, not the login provider (you control them)
- 4 system roles seeded automatically, custom roles created via admin UI
- **Migrations and seed data** generated -- database is ready to use immediately

---

## Slide 35 -- Authentication Flow

**Gemini Image Prompt:**
```
Plain white background, 16:9. A sequence diagram showing the login flow:

1. User clicks "Log In" → Browser sends request to backend
2. Backend generates secure state token, redirects to OIDC Provider
3. User authenticates with OIDC Provider (company login)
4. OIDC Provider redirects back with authorization code
5. Backend exchanges code for user info
6. Backend looks up user in database, gets all roles + permissions
7. Backend creates JWT cookie: {email, name, roles, permissions}
8. Browser receives cookie, redirects to dashboard

Each step is a minimal box with an arrow. Steps 5-7 are highlighted (blue
background) labeled "The magic: roles and permissions come from YOUR database"

Below: "Your company's login. Your app's permissions. Seamless."
```

**Slide Text:**
### Authentication: your company login, your app's permissions

**The login flow (invisible to users):**
1. User clicks "Log In"
2. Redirected to your company's identity provider (Azure AD, Okta, etc.)
3. User authenticates with their normal credentials
4. Redirected back to your app with proof of identity
5. **Your app looks up their roles and permissions in its own database**
6. A secure token is created with their identity + permissions
7. They're in -- seeing exactly what their role allows

**Why this matters:**
- Single sign-on: users use their existing company credentials
- **You control the permissions** -- roles come from your app's database, not IT
- Multi-role support: one person can be both "Manager" and "Project Lead"
- Logout is secure (POST request, cookie cleared)

---

## Slide 36 -- Docker: Your Development Environment

**Gemini Image Prompt:**
```
Plain white background, 16:9. A docker-compose service diagram showing containers
as rounded boxes connected by arrows:

Main containers:
- "Frontend" (green, port 3000) -- Next.js
- "Backend" (blue, port 8000) -- FastAPI
- "Database" (amber, port 5432) -- PostgreSQL

Dev-only container (dashed border):
- "mock-oidc" (slate, port 10090) -- Mock login server

Arrows show connections: Frontend → Backend → Database, Backend → mock-oidc

Labels: "docker compose up" starts everything, "docker compose --profile dev up"
adds mock services

Below: "Your app runs identically on every machine. No 'works on my machine' problems."
```

**Slide Text:**
### Docker: consistent environment, zero setup headaches

Every /make-it app runs in Docker containers:

| Container | What it does | Port |
|---|---|---|
| **Frontend** | Your app's user interface (Next.js) | 3000 |
| **Backend** | Your app's API and business logic (FastAPI) | 8000 |
| **Database** | Your app's data (PostgreSQL) | 5432 |
| **mock-oidc** | Fake login server for local development | 10090 |

**What this means for you:**
- `docker compose up` -- your entire app starts with one command
- Works identically on every machine (Mac, Windows, Linux)
- Mock login server lets you test without connecting to real identity systems
- Test users pre-configured: Admin, Manager, User (one click to switch roles)
- Health checks verify every container is running correctly

---

## Slide 37 -- Mock Services: Test Without Dependencies

**Gemini Image Prompt:**
```
Plain white background, 16:9. A comparison diagram.

LEFT side "Production": Your App → real arrows to → "Azure AD" (identity),
"Jira" (tickets), "GitHub" (code), "Tempo" (time)

RIGHT side "Local Dev": Your App → arrows to → "mock-oidc", "mock-jira",
"mock-github", "mock-tempo" -- each mock is a small container icon with
a dashed border.

Between the two sides, text: "Same code. Same behavior. No external dependencies."

Below: "Switch between real and mock with one environment variable."
```

**Slide Text:**
### Mock services: develop without external dependencies

Your app talks to real services in production. Locally, it talks to **mock versions** that behave identically.

| Real Service | Mock Version | What it simulates |
|---|---|---|
| Azure AD / Okta / Auth0 | **mock-oidc** | Login flow with test users |
| Jira, GitHub, Tempo | **mock-[service]** | API responses matching real contracts |

**Why mocks matter:**
- **No VPN required** for local development
- **No credentials** for external systems needed
- **No rate limits** or API quotas while developing
- **Test data is predictable** (same users, same responses every time)
- **One environment variable** switches between mock and real

The mock-oidc server is the most stable component -- **copied from a battle-tested template, never regenerated**.
