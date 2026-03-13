# Design Pattern Blueprint Reference

This is the internal reference extracted from the AI Vibe Coded Design Pattern Guide.
The /make-it skill uses this to determine WHAT questions to ask and HOW to map answers to implementation decisions. This file is NEVER shown to the user directly.

**Guardrail tiers:** See `guardrails.md` for the tiered guardrail system. Tier 0 (universal) applies to every project. The design patterns below are primarily Tier 1 (web-app). During the Design phase, classify the project type first, then apply only the relevant patterns.

---

## Decision Framework

For each design pattern area below, the skill must gather enough information from the user's natural language answers to make the right architectural choice. The user does NOT need to understand these patterns -- the skill infers them.

### Step 0: Classify Project Type

Before applying any design patterns, classify the project:

| Type | Tiers | Signals |
|------|-------|---------|
| `web-app` | 0, 1 | Frontend + backend, browser-based, login, dashboards, CRUD |
| `extension` | 0, 2 | IDE plugin, browser extension, editor tooling |
| `cli` | 0, 3 | Command-line tool, terminal-based, no GUI |
| `library` | 0, 4 | Importable package, no standalone runtime |
| `api-service` | 0, 5 | Backend only, no frontend, serves other systems |

Record `project_type` and `active_tiers` in app-context.json. Only apply design patterns from active tiers. Document skipped patterns in `skipped_guardrails`.

**Sections 1-11 below are primarily Tier 1 (web-app) patterns.** For non-web projects, reference the appropriate tier in `guardrails.md` instead.

---

## 1. Authentication (OIDC / Azure AD SSO)

**What we need to know from the user:**
- Will people need to log in?
- Is this for people inside your company or outside (public)?
- Do you already have a login system (Google, Microsoft, Okta)?

**Decision rules:**
- If login required + enterprise/internal -> Azure AD (Entra ID) via OIDC
- If login required + public users -> Support multiple providers (Google, GitHub, etc.)
- If no login needed -> Skip auth entirely (rare for business apps)

**Stack mapping:**
| Stack | Library |
|-------|---------|
| Next.js (full-stack) | NextAuth.js |
| NestJS / Express | openid-client v5 |
| FastAPI / Python | authlib |
| .NET | Microsoft.Identity.Web |

**Implementation generates:** Three endpoints: /auth/login, /auth/callback, /auth/me
**Key principle:** Azure AD handles AUTHENTICATION. The app handles AUTHORIZATION. Never mix them.

---

## 2. Authorization (Database-Driven RBAC with User Management)

**What we need to know from the user:**
- What types of users will use this app? (e.g., admins, managers, regular users)
- What can each type of user do? What should they NOT be able to do?
- Are there any sensitive actions only certain people should perform?
- Do you need to control what different people can do within the app? (e.g., some
  can view data but only certain people can change it)

**Decision rules:**
- ALWAYS implement database-driven RBAC with admin UI (this is standard for every app)
- Single-role apps (just authenticated vs. not) -> still use RBAC, just with fewer roles
- Default system roles: Super Admin, Admin, Manager, User (4 predefined, cannot be deleted)
- Super Admin can create custom roles with any permission combination
- Permission granularity defaults to page-level CRUD (view, create, edit, delete per resource)
- Permissions, roles, and role-permission mappings live in the DATABASE (not code config)
- Admins can modify role permissions via the UI without code deploys

**Database schema (4 tables):**
1. `roles` -- id, name, description, is_system (true for predefined roles), is_active, created_by, timestamps
2. `permissions` -- id, resource (page/feature name), action (view, create, edit, delete), description
3. `role_permissions` -- role_id, permission_id (many-to-many junction table)
4. `users` table gets a `role_id` foreign key to `roles` (one role per user)

**User provisioning:**
- Admin adds users to the app by email or OIDC lookup (person must exist in Entra ID)
- Admin assigns a role to the new user
- User logs in via SSO and their role + permissions are loaded from the database
- Users who don't exist in Entra ID need an IT ticket first -- the app does NOT support
  separate login methods or email-based invites

**Admin UI pages (generated for every app):**
- **User Management** -- List users, add new user (by email), assign/change role, deactivate
- **Role Management** -- List roles, create custom roles (Super Admin only), edit role permissions
- **Permission matrix** -- Visual grid of roles × permissions with toggle controls

**API endpoints (generated for every app):**
- GET/POST /admin/users -- list and add users
- GET/PUT/DELETE /admin/users/{id} -- get, update role, deactivate
- GET/POST /admin/roles -- list and create roles (create = Super Admin only)
- GET/PUT/DELETE /admin/roles/{id} -- get, update permissions, delete (custom roles only)
- GET /admin/permissions -- list all available permissions

**Runtime permission checking:**
- `has_permission(user, resource, action)` queries the database (with in-memory cache)
- Cache invalidated when roles or role-permissions are modified via admin API
- Middleware/dependency: `require_permission(resource, action)` for route protection
- Anti-pattern to avoid: `if (user.role === 'admin')` -- always use `has_permission()`

**Seed data:**
- 4 system roles with default permission mappings
- Permissions auto-generated from app pages (one set of view/create/edit/delete per page)
- Super Admin gets all permissions
- Admin gets all except user/role management
- Manager gets view + limited create/edit
- User gets view-only

**Implementation generates:** Database tables, migration, seed data, admin API, admin UI,
runtime permission loader with caching, middleware for route protection

---

## 3. Technology Stack

**What we need to know from the user:**
- What kind of app? (internal business tool, AI/ML app, data pipeline, API service)
- Web app, mobile app, or both?
- Any special features? (real-time chat, file uploads, AI, dashboards)
- How many users expected?
- Any compliance needs? (HIPAA, SOC2)

**Decision tree:**
```
Internal business tool (CRUD + dashboards)
  -> Next.js + Tailwind + PostgreSQL
  -> Backend: Next.js API routes (simplest) or separate NestJS/FastAPI

AI/ML application
  -> Next.js frontend + FastAPI backend (Python)
  -> Why: Python ecosystem for AI (LangChain, OpenAI SDK, pandas)

Data pipeline / automation
  -> FastAPI or Azure Functions (Python)
  -> Frontend only if needed

High-traffic API service
  -> NestJS or FastAPI
  -> Consider Azure Container Apps for scaling
```

**Stack options:**
| Layer | Option A (Node.js) | Option B (Python) |
|-------|-------------------|------------------|
| Frontend | Next.js + Tailwind | Next.js + Tailwind |
| Backend | NestJS | FastAPI |
| Database | PostgreSQL | PostgreSQL |
| ORM/Driver | Prisma or pg | SQLAlchemy or asyncpg |
| Auth | openid-client | authlib |
| Validation | Zod | Pydantic |
| Sessions | express-session + Redis | Redis-backed sessions |

---

## 4. Multi-Tenancy

**What we need to know from the user:**
- Is this for one company/team, or will multiple organizations use it?
- Does each organization need their own separate data?
- Is this a product you'll sell to other companies (B2B SaaS)?

**Decision rules:**
- Single org / internal tool -> Skip multi-tenancy
- Multiple orgs sharing deployment -> Shared-schema with tenant_id + RLS
- B2B SaaS product -> Required, use tenant_id on every table

**Implementation generates:** tenant_id UUID column, PostgreSQL RLS policies

---

## 5. Security Essentials

**Always implemented (Tier 1 - Day One):**
- Input validation (Pydantic for Python, Zod for Node.js)
- Parameterized queries (never string concatenation for SQL)
- HTTPS in production

**Before production (Tier 2):**
- Security headers (X-Frame-Options, CSP, HSTS, X-Content-Type-Options)
- Audit logging (login/logout, user management, settings changes, API key ops)
- Secrets in Azure Key Vault (not .env files)

**Production hardening (Tier 3):**
- Rate limiting on API endpoints
- CORS policy configuration
- AI prompt injection protection (if using LLMs)
- Zero Trust networking

---

## 6. Infrastructure as Code

**What we need to know from the user:**
- Where will this be hosted? (Azure is default)
- Is this a prototype/first version, or production from day one?

**Decision rules:**
- Always generate Terraform as part of the build -- it's a handoff artifact for DevOps
- The user never runs Terraform. DevOps owns provisioning and deployment.
- First deploy / prototype -> Terraform still generated (DevOps applies it)
- All environments in a single Azure subscription ({AZURE_SUBSCRIPTION}), separated by resource groups

**Environment model:**
| Environment | Resource Group | Applied By |
|-------------|----------------|------------|
| Dev | `rg-{app-name}-dev` | DevOps BOT / DevOps team |
| Staging | `rg-{app-name}-staging` | DevOps team |
| Prod | `rg-{app-name}-prod` | DevOps team (with approval gate) |

**State backend:** Azure Storage Account (configured in backend.tf, managed by DevOps)

**Implementation generates:** infrastructure/ directory with main.tf, variables.tf, outputs.tf, versions.tf, backend.tf, environments/

**DevOps handoff:** Terraform is included in the /ship-it PR. The DevOps BOT validates it (`terraform validate`, `terraform plan`), posts the plan as a PR comment, and the DevOps team reviews before applying. See ship-it-guide.md for the full lifecycle.

---

## 7. Containerization

**What we need to know from the user:**
- (Inferred from stack choice -- user doesn't need to answer this directly)

**Decision tree:**
```
Single runtime (just Node.js OR just Python)?
  Yes -> Azure App Service (no container needed)
  No (e.g., Python backend + Node.js frontend)
    -> Docker Compose for local dev
    -> Azure Container Apps for production
```

**Always generate:** Docker Compose for local development (even if deploying without containers)
**Dockerfile pattern:** Multi-stage builds, non-root user, Alpine base images, copy package files first

---

## 8. M.A.C.H. Architecture

**Applied by default for all apps (no user questions needed):**
- **A (API-first):** Define API contract before building UI. Frontend calls backend API -- no business logic in React.
- **C (Cloud-native):** Use managed services (PostgreSQL Flexible Server, Redis Cache)
- **H (Headless):** Backend returns JSON, not HTML
- **M (Microservices):** Start as monolith with clear module boundaries. Extract later only when needed.

---

## 9. AI Prompt Management

**What we need to know from the user:**
- (Inferred from features -- does the app use AI/LLM features?)
- How many distinct AI behaviors/prompts does the app need?
- Who needs to edit/tune prompts? (developers only, or product/business users too?)
- How often will prompts change?

**Decision rules -- AI usage level classification:**
```
AI features mentioned?
  No  -> ai_usage_level = "none", skip prompt management entirely
  Yes -> Classify by signals:

  Minimal (Tier 1): 1-3 prompts, developers manage, rarely change
    -> Prompts in code with env var override
    -> Single file: lib/prompts.py or lib/prompts.ts

  Moderate (Tier 2): 4-10 prompts, product team edits, change weekly/monthly
    -> Database-stored prompts with basic admin UI
    -> 3 tables: managed_prompts, managed_prompt_versions, prompt_audit_log
    -> 6 API routes + admin editor page
    -> Runtime loader with code fallback

  Heavy (Tier 3): 10+ prompts, AI-native app, multiple agents/models
    -> Full prompt management platform (auditgithub reference)
    -> 6 tables with usage tracking, tagging, test cases
    -> 30+ API routes
    -> 5 frontend pages (registry, detail, editor, analytics, audit)
    -> 3-tier runtime: Redis cache -> DB -> seed fallback
```

**Signals that push toward a higher tier:**
- "Non-technical people need to edit prompts" -> at least Tier 2
- "Multiple AI models or providers" -> at least Tier 2
- "AI personas, agents, or evaluators" -> likely Tier 3
- "Prompts will change frequently" -> at least Tier 2
- "Need analytics on AI usage" -> Tier 3

**Implementation generates:**
- Tier 1: lib/prompts.py with named constants + env var overrides
- Tier 2: Schema (3 tables), API (6 routes), admin UI, runtime loader with fallback
- Tier 3: Schema (6 tables), API (30+ routes), 5 frontend pages, 3-tier caching, seed system, RBAC (4 permission scopes)

---

## 10. Mock Services & Local Development

**What we need to know from the user:**
- (Mostly inferred -- user doesn't need to answer this directly)
- What external systems does the app integrate with? (detected from features)

**Decision rules:**
```
Auth needed?
  Yes -> ALWAYS include mock-oidc in docker-compose.yml
  No  -> Skip mock-oidc

Jira integration?
  Yes -> Include mock-jira (Jira REST API v2/v3)
  No  -> Skip mock-jira

Tempo integration (time tracking, worklogs)?
  Yes -> Include mock-tempo (requires mock-jira for shared seed data)
  No  -> Skip mock-tempo

GitHub integration or /ship-it CI/CD?
  Yes -> Include mock-github for local testing
  No  -> Skip mock-github

Structured logging / audit trail?
  Yes -> Include mock-cribl for log ingestion testing
  No  -> Skip mock-cribl

Other external integrations? (Salesforce, ServiceNow, Oracle, etc.)
  Yes -> Generate a custom mock service per integration using the mock-apisrvr pattern
  No  -> Skip custom mocks
```

**Mock service catalog (from mocksvcs repo):**

| Service | What It Mocks | Docker Port | When to Include |
|---------|--------------|-------------|-----------------|
| mock-oidc | Azure AD / Entra ID (full OIDC flow, Python/FastAPI) | 3007 (host) → 10090 (container) | Always (when auth needed) |
| mock-github | GitHub REST API (repos, PRs, checks, actions) | 3006 | When app integrates with GitHub |
| mock-cribl | Cribl Stream HTTP Source (log ingestion) | 3005 | When app has structured logging |
| mock-jira | Jira Software REST API v2/v3 (issues, projects, users, transitions, role assignments) | 8443 | When app integrates with Jira |
| mock-tempo | Tempo Timesheets API v4 (worklogs, accounts, teams, plans) | 8444 | When app integrates with Tempo (shares seed data with mock-jira) |
| Custom mock | Any external API the app depends on | 9000+ | Per integration (auto-generated) |

**Pre-seeded test data (mock-oidc):**

| Subject | Email | Name | Use For |
|---------|-------|------|---------|
| mock-admin | admin@app.local | Mock Admin | Testing admin flows |
| mock-analyst | analyst@app.local | Mock Analyst | Testing read-only flows |
| mock-user | user@app.local | Mock User | Testing regular user flows |

Default OIDC client: `mock-oidc-client` / `mock-oidc-secret`

**mock-oidc architecture:**
- Python 3.12 + FastAPI (NO Java -- see guardrails.md Tier 0 no-Java policy)
- Built-in internal/external URL split: discovery document returns browser-facing
  endpoints (authorization) with MOCK_OIDC_EXTERNAL_BASE_URL and server-to-server
  endpoints (token, userinfo, JWKS) with MOCK_OIDC_INTERNAL_BASE_URL
- Apps do NOT need OIDC_INTERNAL_URL or URL rewriting -- mock-oidc handles it natively
- Health check: GET /health (standard Python image, no distroless issues)
- Container port: 10090, host-mapped to 3007 (configurable)

**The decoupling pattern (environment-based service switching):**

All external service URLs are configured via environment variables. The application code
never branches on `NODE_ENV` or checks whether it's running locally vs production.
The same code path runs in both environments -- only the URL changes.

```
# .env (local development -- points to mock services in Docker)
OIDC_ISSUER_URL=http://localhost:3007
OIDC_CLIENT_ID=mock-oidc-client
OIDC_CLIENT_SECRET=mock-oidc-secret
JIRA_BASE_URL=http://localhost:8443
TEMPO_BASE_URL=http://localhost:8444
GITHUB_API_URL=http://localhost:3006

# .env.production (real services)
OIDC_ISSUER_URL=https://login.microsoftonline.com/{tenant_id}/v2.0
OIDC_CLIENT_ID=<real-client-id>
OIDC_CLIENT_SECRET=<from-key-vault>
JIRA_BASE_URL=https://jira.company.com
TEMPO_BASE_URL=https://api.tempo.io
GITHUB_API_URL=https://api.github.com
```

**Service client abstraction:**

Every external dependency gets a client class/module that reads its base URL from
environment variables. No hardcoded URLs anywhere in the codebase.

```python
# Python pattern
class JiraClient:
    def __init__(self):
        self.base_url = os.getenv("JIRA_BASE_URL")  # mock or real -- code doesn't care
```

```typescript
// TypeScript pattern
const jiraClient = new JiraClient({
  baseUrl: process.env.JIRA_BASE_URL,  // mock or real -- code doesn't care
});
```

**Custom mock generation (for app-specific integrations):**

When the app integrates with an external API (Jira, Oracle EBS, Tempo, Salesforce, etc.),
generate a lightweight mock service using the mock-apisrvr pattern:

1. Create `mock_{service_name}/` directory with FastAPI app
2. Implement the specific endpoints the app actually calls (not the entire API)
3. Pre-seed with realistic test data matching the app's domain
4. Add to docker-compose.yml with health check
5. Add lifecycle scripts (start/restart/shutdown)

**Implementation generates:**
- mock-oidc service in docker-compose.yml (when auth needed)
- Custom mock services for each external integration
- Environment variables pointing to mock URLs in .env
- Environment variables pointing to real URLs in .env.example (commented, for production)
- Service client classes that read base URLs from environment

**Key principles:**
- Mock services run as Docker containers alongside the app -- `docker-compose up` starts everything
- The app code is identical in dev and production -- only .env values change
- Mock services use in-memory storage (data resets on container restart)
- Each mock has a health check endpoint for Docker readiness
- Pre-seeded test data lets developers test immediately without manual setup
- No `if (isDevelopment)` branches in application code -- ever

---

## 11. Standard UI Components (Built-In Defaults)

**Applied by default for all apps (no user questions needed).**

Every app generated by /make-it includes four standard UI components that provide a polished, production-ready experience out of the box. The user can customize or replace any of these after the build is completed.

**Header bar layout pattern (authenticated layout):**

```
Header Bar (h-14, border-b, bg-muted/40)
├── SidebarTrigger (expand/collapse sidebar button)
├── Breadcrumbs (auto-generated from URL path)
├── Spacer (flex-1)
├── QuickSearch (⌘K / Ctrl+K command palette)
└── ModeToggle (light/dark/system theme toggle)
```

**Component 1: Breadcrumb Navigation**

Auto-generated breadcrumbs from the current URL path. Positioned in the header bar to the right of the sidebar trigger.

- Uses `usePathname()` to parse URL segments into breadcrumb items
- SEGMENT_LABELS map for human-readable names (populated from the app's pages)
- Home icon as first breadcrumb (links to dashboard)
- ChevronRight separators between items
- Last item styled as current page (not clickable)
- UUID/ID segments auto-detected and truncated
- Kebab-case and snake_case auto-converted to Title Case
- Hidden on the dashboard/home page
- ARIA support: `aria-label="Breadcrumb"`, `aria-current="page"`
- Component: `components/breadcrumbs.tsx`

**Component 2: DataTable with Excel-Style Filters**

Reusable paginated DataTable built on TanStack React Table v8 with Excel-style column filter popovers.

- Multi-select filtering with checkbox lists and value counts
- Comparison filtering for dates/numbers (>=, <=, >, <, =, !=)
- Column sorting (A→Z, Z→A) via header popover
- Global search across all columns
- Column visibility toggle
- Row grouping with expandable groups
- Pagination with configurable page size (10/20/30/40/50)
- LocalStorage persistence for filters, sorting, visibility, and page size
- Hover actions on filter values: "Select Only" and "Select All Except"
- Active filter count badge in toolbar
- Reset button to clear all customizations
- Dependencies: `@tanstack/react-table` v8
- Components: `components/data-table.tsx`, `components/data-table-column-header.tsx`, `components/data-table-toolbar.tsx`, `components/data-table-pagination.tsx`
- Every list page in the app uses this DataTable component instead of plain HTML tables

**Component 3: Navigation Search (Command Palette)**

Quick search / command palette accessible via ⌘K (Mac) or Ctrl+K (Windows). Positioned in the header bar upper-right area.

- Trigger button with search icon and keyboard shortcut hint
- Modal dialog with search input and results list
- Fuzzy search across page titles, descriptions, and keywords
- Keyboard navigation: Arrow keys, Enter to select, Escape to close, Tab to cycle
- Grouped results by category (Navigation, Settings, Actions)
- Recent searches stored in localStorage
- Instant page navigation on selection
- NAVIGATION_ITEMS populated from the app's page list during build
- SETTINGS_ITEMS and ACTION_ITEMS populated from the app's features
- Component: `components/quick-search.tsx`

**Component 4: Theme Toggle (Light/Dark/System)**

Light/dark/system theme toggle using `next-themes`. Positioned as the rightmost item in the header bar.

- Dropdown menu with Light, Dark, and System options
- Animated Sun/Moon icon transition
- `suppressHydrationWarning` on `<html>` and `<body>` to prevent mismatches
- `mounted` state pattern to prevent server/client rendering conflicts
- Persists theme choice in localStorage across sessions
- Respects OS `prefers-color-scheme` preference when set to System
- oklch CSS variables for both light and dark color schemes
- Dependencies: `next-themes`
- Components: `components/theme-provider.tsx`, `components/mode-toggle.tsx`
- ThemeProvider wraps the entire app in the root layout

**Implementation generates:**

| Component | Files | Dependencies |
|-----------|-------|-------------|
| Breadcrumbs | `components/breadcrumbs.tsx` | lucide-react |
| DataTable | `components/data-table.tsx`, `data-table-column-header.tsx`, `data-table-toolbar.tsx`, `data-table-pagination.tsx` | @tanstack/react-table v8 |
| QuickSearch | `components/quick-search.tsx` | shadcn dialog, input, button |
| ModeToggle | `components/theme-provider.tsx`, `components/mode-toggle.tsx` | next-themes |

---

## Quick-Start Checklist (used to verify completeness)

### Before Writing Code
- [ ] OIDC provider identified
- [ ] Stack chosen (latest stable versions -- no outdated majors)
- [ ] Roles and permissions defined
- [ ] Git repo with .gitignore
- [ ] .env.example created with all required env vars
- [ ] .env copied from .env.example for local dev (gitignored)

### During Development
- [ ] OIDC authentication fully implemented (not stubs -- complete token exchange flow)
- [ ] Permission-based access control
- [ ] Input validation on all endpoints
- [ ] Parameterized database queries
- [ ] Database migrations generated (Alembic or Prisma -- not just models)
- [ ] Docker Compose for local dev (includes mock services)
- [ ] mock-oidc included in docker-compose.yml (if auth needed) -- testable login on day one
- [ ] Custom mock services generated for each external integration
- [ ] Service clients read base URLs from environment variables (no hardcoded URLs)
- [ ] .env points to mock service URLs for local dev
- [ ] .env for local secrets (never committed)
- [ ] Frontend uses service/API layer for data (no hardcoded mock data in components)
- [ ] One shared authenticated layout (no duplicate sidebar/nav per page)
- [ ] Header bar includes: SidebarTrigger, Breadcrumbs, Spacer, QuickSearch, ModeToggle
- [ ] Breadcrumbs auto-generated from URL path with SEGMENT_LABELS for all pages
- [ ] DataTable component used for all list pages (not plain HTML tables)
- [ ] QuickSearch (⌘K) populated with all navigation items and app actions
- [ ] ThemeProvider wraps app, ModeToggle in header, oklch CSS variables for light/dark
- [ ] CHANGELOG.md and TODO.md maintained
- [ ] AI prompts externalized (not hardcoded in business logic) -- if using AI
- [ ] Prompt management tier determined and implemented -- if using AI
- [ ] AI prompt seed data generated (Tier 2/3 -- database must not start empty) -- if using AI

### Before Production (DevOps-owned -- user does NOT do these)
- [ ] Mock services excluded from production deployment (docker-compose.override.yml or profiles)
- [ ] All service client base URLs configured for production endpoints
- [ ] Production .env / secrets store has real service URLs (no mock references)
- [ ] Security headers configured
- [ ] Audit logging for auth and admin actions
- [ ] Secrets in Azure Key Vault
- [ ] Terraform applied by DevOps (infrastructure/ directory in repo)
- [ ] HTTPS enforced
- [ ] Session timeout enforcement
- [ ] DevOps BOT preflight scan passed
- [ ] AuditGithub findings resolved
- [ ] Prompt version history enabled (Tier 2+) -- if using AI
- [ ] Prompt audit logging active (Tier 2+) -- if using AI
- [ ] Prompt testing capability available (Tier 2+) -- if using AI

### Production Hardening
- [ ] Rate limiting on public endpoints
- [ ] CORS policy configured
- [ ] Monitoring and alerting
- [ ] Runbook documentation
- [ ] Prompt usage analytics and performance monitoring (Tier 3) -- if using AI
- [ ] Prompt caching strategy implemented (Tier 3) -- if using AI
