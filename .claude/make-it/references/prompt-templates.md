# Prompt Templates Reference

These are the 14 Claude Code prompts that /make-it generates BEHIND THE SCENES based on the user's answers. The user never sees or writes these prompts -- the skill fills in all [BRACKETS] automatically from the conversation context.

The skill executes these in order, skipping any that don't apply.

---

## Prompt #1: Start a New Project

```
Create a new SaaS project called [PROJECT_NAME].

Purpose: [PURPOSE]
Main features: [FEATURES_LIST]
Users: [USER_DESCRIPTION]

Set up the project structure with:
- Frontend [FRONTEND_FRAMEWORK]
- Backend [BACKEND_FRAMEWORK]
- Mock services (for local development testing)
- Infrastructure [Terraform]
- Documentation

Also create:
- CHANGELOG.md with an initial "## [0.1.0] - [DATE]" entry listing the project setup
- TODO.md with high/medium/low priority sections (populate during build)
- .env.example with all required environment variables (commented with descriptions)
- Copy .env.example to .env for local development (this file is gitignored)

Dependency version rules:
- Always use the LATEST STABLE version of every dependency
- For Next.js, use the latest 15.x release (not 14.x)
- For React, use the version required by the chosen Next.js version
- Check for known CVEs before pinning any version
```

**Required context:** project name, purpose, features, users, stack choice
**Always runs:** Yes

---

## Prompt #2: Design the User Interface

```
Design a modern web interface for [PROJECT_NAME].

Pages needed:
- Login page
- Dashboard (main page after login)
[CUSTOM_PAGES]
- Admin panel
- User profile

Make it responsive and easy to use on mobile and browser.

Layout rules:
- Create ONE shared authenticated layout with sidebar navigation (not per-page layouts)
- All authenticated pages share this layout via a route group like (authenticated)/layout.tsx
- Do NOT duplicate the sidebar/layout in individual page directories
- The authenticated layout MUST include a header bar with this exact structure:
    Header Bar (h-14, border-b, bg-muted/40, px-6)
    ├── SidebarTrigger (expand/collapse sidebar)
    ├── Breadcrumbs (auto-generated from URL path)
    ├── Spacer (flex-1)
    ├── QuickSearch (⌘K command palette trigger button)
    └── ModeToggle (light/dark/system theme toggle)

Standard UI components (built into every app -- see Prompt #14 for details):
- Breadcrumbs: auto-generated from URL path, with SEGMENT_LABELS for all app pages
- DataTable: TanStack React Table v8 with Excel-style column filters -- use for ALL list pages
- QuickSearch: ⌘K/Ctrl+K command palette with all pages and app actions searchable
- ModeToggle: light/dark/system theme toggle with next-themes

Font rules:
- NEVER use external font CDNs (Google Fonts, Adobe Fonts, Typekit, etc.)
- Enterprise environments use SSL inspection proxies (Zscaler) that block external
  font downloads during Docker builds, causing build failures
- ALWAYS use system font stacks:
    --font-sans: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    --font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
- Do NOT import from next/font/google or any Google Fonts URL
- Configure font-sans and font-mono as CSS custom properties in globals.css

Data fetching rules:
- Each page must fetch data from the backend API using the API client (lib/api.ts)
- Do NOT use hardcoded mock data in page components
- If the backend is not yet connected, create a mock API service layer that returns
  sample data through the same API client interface, so swapping to real data later
  requires changing only the service layer, not every page
```

**Required context:** project name, custom pages from features
**Always runs:** Yes

---

## Prompt #3: Choose Technology Stack

```
Recommend the best technology stack for [PROJECT_NAME].

Requirements:
- Type: [APP_TYPE]
- Users: [USER_COUNT_ESTIMATE]
- Security: [COMPLIANCE_NEEDS]
- Special features: [SPECIAL_FEATURES]

Suggest similar technologies to PULSE:
- Next.js frontend
- Azure Functions backend
- PostgreSQL database
- Azure cloud services

Version policy: Always use the latest stable release of each dependency.
Do NOT pin to older major versions (e.g., Next.js 14 when 15 is stable).
```

**Required context:** app type, user count, compliance, special features
**Always runs:** Yes (validates/confirms stack decision from Phase 2)

---

## Prompt #4: Design the Architecture

```
Design the system architecture for [PROJECT_NAME] using M.A.C.H. principles.

Key features:
[FEATURES_LIST]

Show me:
- How services should be separated
- What APIs are needed
- How frontend and backend connect
- Cloud services to use

Database setup:
- If using Python + SQLAlchemy: initialize Alembic (`alembic init alembic`),
  configure alembic.ini and env.py to use the async engine, and generate
  the initial migration from the models (`alembic revision --autogenerate -m "initial schema"`)
- If using Node + Prisma: initialize Prisma schema and generate the initial migration
- The database must be usable immediately after `docker-compose up` without manual steps
```

**Required context:** features list, stack choice
**Always runs:** Yes

---

## Prompt #5: Create Cloud Infrastructure

```
Create Terraform configuration for [PROJECT_NAME] on Azure.

Services needed:
- Web app for frontend
- Functions for backend
- [DATABASE_TYPE] database
- File storage
[AI_SERVICES_LINE]

Security requirements:
- Private networking (no public access)
- All secrets in Azure Key Vault
- Encryption everywhere
```

**Required context:** database type, whether AI services needed
**Runs when:** User wants cloud deployment (not just local prototype)

---

## Prompt #6: Add Docker Support

```
Create Docker containers for [PROJECT_NAME].

Components to containerize:
- [FRONTEND_FRAMEWORK]
- [BACKEND_FRAMEWORK]

Mock services to include in docker-compose.yml for local development:
[MOCK_SERVICES_LIST]

Each mock service should:
- Have a health check endpoint
- Be on a shared Docker network with the app services
- Use environment variables from .env for configuration

Use Docker Compose profiles to separate mock services from production services:
- Default profile: app services only (frontend, backend, database, redis)
- "dev" profile: adds all mock services
- Local development runs: docker-compose --profile dev up
- Production deploys: docker-compose up (no mock services included)

Make containers secure and optimized for production.
```

**Required context:** stack choice, mock services list
**Runs when:** Multi-runtime stack OR user wants containers

---

## Prompt #7: Add Multi-Tenant Support

```
Make [PROJECT_NAME] support multiple organizations (multi-tenant).

Tenant type: [TENANT_TYPE]

Each tenant should have:
- Their own users
- Separate data
- Custom branding [optional]
- Different subscription levels [if needed]

Use shared database with tenant_id column.
```

**Required context:** tenant type (B2B/B2C/Both)
**Runs when:** Multi-tenancy needed (B2B SaaS, multiple orgs)

---

## Prompt #8: Add User Login

```
Add user authentication to [PROJECT_NAME] using Open Identity Connect (OIDC).

Login provider: [AUTH_PROVIDER]
Session length: [SESSION_LENGTH]
Auth library: [AUTH_LIBRARY] (e.g., authlib for Python, next-auth for Next.js)

Users should:
- Sign in with SSO (single sign-on)
- Stay logged in securely
- Automatically be created on first login

Implementation requirements:
- Generate the COMPLETE auth flow, not stubs or placeholders
- /auth/login must redirect to the OIDC provider authorization endpoint
- /auth/callback must exchange the authorization code for tokens using [AUTH_LIBRARY],
  get the userinfo from the OIDC provider, then look up the user in the APPLICATION
  DATABASE to get their role. The flow is:
    1. Exchange authorization code for tokens
    2. Call the OIDC userinfo endpoint to get sub, email, name
    3. Query the users table by oidc_subject (or fall back to email)
    4. If found: read the role from the DATABASE record (NOT from OIDC claims)
    5. If not found: create a new user with default role ("user")
    6. Store {sub, email, name, role} in the session (role comes from DB)
    7. Redirect to the dashboard
  CRITICAL: User roles MUST come from the application database, NOT from OIDC
  provider claims. The OIDC provider (mock-oidc or Azure AD) only provides identity
  (sub, email, name). It does NOT provide application-specific roles.
- /auth/me must return the current user from the session (or 401 if not authenticated)
- /auth/logout must be a POST endpoint that clears the server-side session and returns
  a JSON response (e.g., {"message": "logged out"}). The frontend logout button must
  call this endpoint via POST (using the API client), then redirect to the login page
  via client-side navigation (router.push("/")). Do NOT implement logout as:
    - A GET endpoint (browsers can prefetch GET requests, causing unintended logouts)
    - A frontend-side link (<a href="/api/auth/logout">) -- this routes to the frontend,
      not the backend, causing a 404
    - A redirect-only endpoint -- the frontend needs to handle the redirect itself
- Include a middleware/dependency that extracts the current user from the session
  for use in protected route handlers (e.g., get_current_user dependency in FastAPI)

Mock OIDC configuration for local development:
- The OIDC issuer URL, client ID, and client secret MUST be read from environment
  variables (never hardcoded)
- .env file should point to the mock-oidc service:
    OIDC_ISSUER_URL=http://localhost:3007
    OIDC_CLIENT_ID=mock-oidc-client
    OIDC_CLIENT_SECRET=mock-oidc-secret
- The mock-oidc service provides a user picker with pre-seeded test users
  (admin, analyst, regular user) so developers can test all role-based flows
- The same auth code works against real Azure AD in production -- only the
  environment variables change
- Do NOT add any if/else branching for "mock mode" vs "real mode" -- the OIDC
  protocol is identical regardless of provider
```

**Required context:** auth provider, session length, auth library
**Runs when:** Authentication needed

---

## Prompt #9: User Management + RBAC Permissions

```
Create a production-ready, database-driven RBAC system with full user management
for [PROJECT_NAME]. This is a STANDARD component of every app -- not optional.

Stack: [STACK]
Database: [DATABASE]
Auth provider: [AUTH_PROVIDER]
Pages/resources in this app: [PAGES_LIST]

--- DATABASE SCHEMA ---

Create these 4 tables (in addition to the existing users table):

1. roles
   - id: UUID primary key
   - name: VARCHAR(100) unique, not null
   - description: TEXT
   - is_system: BOOLEAN default false (true for predefined roles -- cannot be deleted)
   - is_active: BOOLEAN default true
   - created_by: UUID FK -> users (nullable for system roles)
   - created_at, updated_at: TIMESTAMP WITH TIMEZONE

2. permissions
   - id: UUID primary key
   - resource: VARCHAR(100) not null (page or feature name, e.g., "forecasts", "users")
   - action: VARCHAR(50) not null (one of: "view", "create", "edit", "delete")
   - description: TEXT (human-readable, e.g., "View the Forecasting page")
   - UNIQUE constraint on (resource, action)

3. role_permissions (junction table)
   - role_id: UUID FK -> roles, not null
   - permission_id: UUID FK -> permissions, not null
   - PRIMARY KEY (role_id, permission_id)

4. Modify the existing users table:
   - Add role_id: UUID FK -> roles (replaces the old VARCHAR role column)
   - Keep email, name, oidc_subject, last_login, etc.

Generate an Alembic migration (or Prisma migration) that:
a. Creates the roles, permissions, and role_permissions tables
b. Migrates the existing users.role VARCHAR column to users.role_id FK
c. Seeds the system roles, permissions, and default mappings (see below)

--- SEED DATA ---

System roles (is_system=true, cannot be deleted):

| Role | Description | Default Permission Level |
|------|-------------|------------------------|
| Super Admin | Full system access, can create custom roles and manage all users | ALL permissions |
| Admin | Can manage app settings, API keys, data sources. Cannot manage users or roles | All except user/role management |
| Manager | Can view most data and run operations (forecasts, scenarios) | View all + create/edit on operational pages |
| User | Read-only access to dashboards and reports | View-only on allowed pages |

Permissions auto-generated from this app's pages/resources:
For EACH page/resource in [PAGES_LIST], create 4 permission records:
- {resource}.view -- "View the {Page Name} page"
- {resource}.create -- "Create new items on {Page Name}"
- {resource}.edit -- "Edit items on {Page Name}"
- {resource}.delete -- "Delete items on {Page Name}"

Plus system permissions:
- users.view, users.create, users.edit, users.delete -- "Manage users"
- roles.view, roles.create, roles.edit, roles.delete -- "Manage roles"
- settings.view, settings.edit -- "Manage app settings"
- api_keys.view, api_keys.create, api_keys.delete -- "Manage API keys"

Default role-permission mappings:
- Super Admin: ALL permissions
- Admin: All EXCEPT users.* and roles.* (cannot manage users or roles)
- Manager: *.view on all resources + *.create and *.edit on operational resources
  (forecasts, scenarios, alerts, etc.) but NOT on admin resources (users, roles, settings)
- User: *.view only on non-admin resources (dashboard, forecasts, scenarios, alerts, finops)

--- RUNTIME PERMISSION SYSTEM ---

Create a permission service/module that:

1. Loads permissions from the database into an in-memory cache on startup:
   - Cache structure: { role_id: Set[permission_strings] }
   - Permission string format: "resource.action" (e.g., "forecasts.view", "users.create")

2. Provides these functions:
   - has_permission(user, resource, action) -> bool
     Checks the cached permissions for the user's role
   - get_user_permissions(user) -> list[str]
     Returns all permission strings for the user's role
   - invalidate_cache()
     Called when roles or role_permissions are modified via admin API

3. Provides a route-protection middleware/dependency:
   - require_permission(resource, action) -- returns 403 if the user lacks the permission
   - Example usage in FastAPI:
     @router.get("/api/forecasts")
     async def list_forecasts(
         user: Annotated[CurrentUser, Depends(require_permission("forecasts", "view"))],
     ):
   - Example usage in Express/NestJS:
     @UseGuards(PermissionGuard("forecasts", "view"))

--- ADMIN API ENDPOINTS ---

User Management (require "users.view" / "users.create" / "users.edit" / "users.delete"):

GET    /api/admin/users              -- List all users with their roles
POST   /api/admin/users              -- Add a new user (by email). Body: { email, name, role_id }
                                       The user must exist in the OIDC provider (Entra ID).
                                       Creates a user record with the given role, ready for
                                       their first SSO login.
GET    /api/admin/users/{id}         -- Get user details with role and permissions
PUT    /api/admin/users/{id}         -- Update user (change role, update name)
DELETE /api/admin/users/{id}         -- Deactivate user (soft delete -- set is_active=false,
                                       do NOT hard delete)

Role Management (require "roles.view" / "roles.create" / "roles.edit" / "roles.delete"):

GET    /api/admin/roles              -- List all roles with permission counts
POST   /api/admin/roles              -- Create a custom role (Super Admin only).
                                       Body: { name, description, permission_ids[] }
GET    /api/admin/roles/{id}         -- Get role with full permission list
PUT    /api/admin/roles/{id}         -- Update role permissions.
                                       Body: { name?, description?, permission_ids[] }
                                       System roles: can change permissions but NOT name
                                       or is_system flag.
DELETE /api/admin/roles/{id}         -- Delete a custom role (Super Admin only).
                                       System roles CANNOT be deleted (return 400).
                                       Reassign users on this role to "User" before deleting.

Permission Reference:

GET    /api/admin/permissions        -- List all available permissions (grouped by resource).
                                       Used by the role management UI to show the permission
                                       matrix. Returns:
                                       [{ resource: "forecasts", permissions: [
                                         { id, action: "view", description },
                                         { id, action: "create", description },
                                         ...
                                       ]}]

After any role or role_permissions change, call invalidate_cache().

--- ADMIN UI PAGES ---

1. User Management page (/admin/users):
   - DataTable listing all users: name, email, role, last login, status (active/inactive)
   - "Add User" button -> modal/dialog:
     - Email input (required)
     - Name input (required)
     - Role dropdown (all active roles)
     - Note: "This person must have a company account (Entra ID) to sign in"
   - Row actions: Edit Role (dropdown), Deactivate/Reactivate
   - Cannot deactivate yourself (prevent lockout)
   - Cannot change Super Admin role unless you are Super Admin

2. Role Management page (/admin/roles):
   - DataTable listing all roles: name, description, user count, type (System/Custom)
   - "Create Role" button (visible only to Super Admin) -> dialog:
     - Name, description inputs
     - Permission matrix (see below)
   - Click any role -> Permission editor:
     - Grid layout: rows = resources (pages), columns = actions (view/create/edit/delete)
     - Checkbox at each intersection
     - "Select All" per row (grant all CRUD for a resource)
     - "Select All" per column (grant an action across all resources)
     - System roles show a badge, cannot be deleted
     - Save button applies changes immediately
   - Row actions: Edit, Delete (custom roles only, Super Admin only)

3. These pages are protected by the users.view / roles.view permissions respectively.
   Regular users and managers should NOT see these pages in the sidebar.

--- INTEGRATION WITH AUTH ---

Update the auth callback (/auth/callback) to:
1. After looking up the user in the database, load their role_id
2. Fetch the role's permissions from the cache
3. Store in session: { sub, email, name, role_id, role_name, permissions[] }

Update get_current_user middleware to:
1. Read role_id and permissions from the session
2. Return a CurrentUser object with: subject, email, name, role_name, permissions[]

Update the frontend sidebar/navigation to:
1. Fetch user permissions from /auth/me on login
2. Show/hide sidebar items based on "{resource}.view" permission
3. Show/hide action buttons (Create, Edit, Delete) based on corresponding permissions
4. Admin pages (Users, Roles) only visible if user has "users.view" / "roles.view"
```

**Required context:** stack, database, auth provider, pages/resources list
**Always runs:** Yes -- every app gets database-driven RBAC with user management

---

## Prompt #10: Design AI Prompt Architecture

**This prompt adapts based on the AI usage level determined during design.**

### Prompt #10a: Tier 1 -- Minimal AI (1-3 prompts)

```
Set up AI prompt management for [PROJECT_NAME] -- Tier 1 (minimal).

This app uses AI for:
[AI_FEATURES_LIST]

AI prompts (list all):
[PROMPT_1_NAME]: [WHAT_IT_DOES]
[PROMPT_2_NAME]: [WHAT_IT_DOES]
[PROMPT_3_NAME]: [WHAT_IT_DOES]

Requirements:
- Store all prompts in a single dedicated file (lib/prompts.py or lib/prompts.ts)
- Each prompt is a named constant with a descriptive variable name
- Allow environment variable override for each prompt (for production tuning
  without redeployment)
- Include the AI model name and parameters (temperature, max_tokens) alongside
  each prompt
- Add a comment block at the top explaining each prompt's purpose

Pattern to follow:
- Python: PROMPT_NAME = os.getenv("PROMPT_NAME", """default content""")
- TypeScript: export const PROMPTS = { name: process.env.PROMPT_NAME ?? `default` }

Do NOT build a database or admin UI for prompts -- this app only has a few
prompts and they rarely change.
```

**Required context:** AI features list, prompt names and purposes
**Runs when:** ai_usage_level = "minimal" (1-3 prompts, developers only)

### Prompt #10b: Tier 2 -- Moderate AI (4-10 prompts)

```
Design the AI prompt management system for [PROJECT_NAME] -- Tier 2
(moderate). All AI prompts should be stored in the database and editable
through the admin UI without code changes.

This app uses AI for:
[AI_FEATURES_LIST]

AI prompts to manage:
[PROMPT_LIST_WITH_CATEGORIES]

Database schema needed (3 tables):
1. managed_prompts -- registry with slug, name, content, version, is_active,
   category, updated_by, timestamps
2. managed_prompt_versions -- immutable version history (append-only),
   content + change_summary + who changed it
3. prompt_audit_log -- append-only audit trail of all changes

API endpoints needed (6 routes, all behind admin permission):
- GET /api/admin/prompts -- list all prompts
- GET /api/admin/prompts/:key -- get prompt with version history
- PUT /api/admin/prompts/:key -- update (creates new version, requires change_summary)
- POST /api/admin/prompts/:key/test -- test with sample input
- POST /api/admin/prompts/:key/restore -- rollback to previous version
- GET /api/admin/prompts/:key/audit -- view change log

Runtime loader: database first, code-defined fallback. Simple in-memory cache.
Seed database on first run from code constants.

Seed data: Generate an Alembic data migration (or seed script) that inserts
all of the app's AI prompts into the managed_prompts table on first run.
Each prompt must have: slug, name, content, category, model, default parameters.
The database must NOT start empty.

Admin UI: prompt list, edit with change summary, test panel, version diff,
one-click rollback, audit trail.

Permission required: [PROMPT_ADMIN_PERMISSION]
Storage: [DATABASE_TYPE]
```

**Required context:** AI features, prompt names/categories, admin permission name
**Runs when:** ai_usage_level = "moderate" (4-10 prompts, product team edits)

### Prompt #10c: Tier 3 -- Heavy AI (10+ prompts, AI-native app)

```
Design a full AI prompt management platform for [PROJECT_NAME] -- Tier 3
(heavy). AI-native application with multiple agents, models, and providers.

This app uses AI for:
[AI_FEATURES_LIST]

AI agents/components:
[AGENT_LIST_WITH_MODELS_AND_PROVIDERS]

AI prompts to manage:
[FULL_PROMPT_LIST_WITH_CATEGORIES_AND_AGENTS]

Database schema (6 tables):
1. prompts -- registry with slug, name, description, category
   (system|user|template|agent|skill|mcp), subcategory, agent_id, provider,
   model, current_version, is_active, is_locked, locked_by/reason, source_file
2. prompt_versions -- immutable history: content, system_message,
   parameters (JSONB), model override, input/output schemas, change_summary
3. prompt_usages -- runtime metrics: usage_type, location, call_count,
   avg_latency_ms, token counts, error_count
4. prompt_tags -- flexible tagging (unique per prompt)
5. prompt_test_cases -- saved regression tests: input_data, expected_output
6. prompt_audit_log -- immutable trail: action, old/new values (JSONB),
   user, ip_address

API (30+ routes): Full CRUD, versioning with diff, locking, tags, test cases,
usage tracking, audit logs, analytics, import/export, full-text search.
Permission scopes: prompts:read, prompts:write, prompts:delete, prompts:admin.

Runtime: 3-tier resolution (Redis cache -> DB -> seed fallback).
Public API: get_prompt(), render_prompt(), get_prompt_with_system(),
invalidate_cache().

Frontend (5 pages): Registry (filterable DataTable), Detail (tabbed: versions,
usage, tests, audit), Editor (metadata + content + schemas), Analytics
Dashboard, Audit Log.

Seed data: Generate an Alembic data migration (or seed script) that inserts
ALL of the app's AI prompts into the database on first run. Each prompt must
have: slug, name, description, content, system_message, category, agent_id,
provider, model, default parameters. The database must NOT start empty.
Include version 1 entries in prompt_versions for each seeded prompt.

Reference architecture: auditgithub prompt management system.
```

**Required context:** AI features, agents/models/providers, full prompt inventory
**Runs when:** ai_usage_level = "heavy" (10+ prompts, AI-native application)

---

## Prompt #11: Secure Everything

```
Implement security for [PROJECT_NAME] following Zero Trust principles.

Protect:
- Network: Use private connections for all services
- Data: Encrypt everything in transit and at rest
- Secrets: Store all passwords/keys in Azure Key Vault
- Input: Validate all user input
[AI_SECURITY_LINE]
- Access: Only authenticated users with right permissions

Rate limits: [RATE_LIMIT]
```

**Required context:** whether AI features exist, rate limit needs
**Always runs:** Yes (security is non-negotiable)

---

## Prompt #12: Add Mock Services for Local Development

```
Set up mock services for [PROJECT_NAME] so the full application can be tested
locally without any external dependencies or service tickets.

Mock services needed:
[MOCK_SERVICES_BLOCK]

For EACH mock service:
- If a ready-made mock exists in the mocksvcs catalog, use it directly:
  - mock-oidc (port 3007) -- Azure AD / OIDC
  - mock-github (port 3006) -- GitHub REST API
  - mock-cribl (port 3005) -- Cribl Stream log ingestion
  - mock-jira (port 8443) -- Jira Software REST API v2/v3
  - mock-tempo (port 8444) -- Tempo Timesheets API v4 (shares seed data with mock-jira)
- If no ready-made mock exists, generate a custom one:
  1. A lightweight FastAPI application in mock_{service_name}/ that implements
     ONLY the endpoints the app actually calls (not the entire external API)
  2. Pre-seeded test data that matches the app's domain and use cases
  3. In-memory storage (data resets on container restart -- this is intentional)
  4. A health check endpoint at GET /health
  5. A Dockerfile (Python 3.12, Alpine base, non-root user)
  6. A docker-compose service entry with:
     - Health check
     - Shared network with the app services
     - Docker Compose profile "dev" (so mock services are excluded from production)
     - Environment variables for configuration

Note: mock-tempo requires mock-jira when both are included -- they share
a DATA_SEED for consistent user/project data across services.

Mock OIDC service (if auth is needed):
- Include mock-oidc as a Docker service (from the mocksvcs repo pattern)
- Pre-seed with test users that match the app's roles:
  [MOCK_USERS_BLOCK]
- Default OIDC client: mock-oidc-client / mock-oidc-secret
- Split URL architecture: localhost URLs for browser-facing endpoints,
  container-hostname URLs for backend-facing endpoints (token, userinfo, JWKS)
- Serves a browser-based user picker for interactive login

Environment variable wiring:
- .env must point all service URLs to the local mock services
- .env.example must document the production URLs (commented out) alongside
  the mock URLs (active) so developers understand what changes for production
- Example:
    # Local development (mock services)
    OIDC_ISSUER_URL=http://localhost:3007
    JIRA_BASE_URL=http://localhost:8443
    TEMPO_BASE_URL=http://localhost:8444
    GITHUB_API_URL=http://localhost:3006
    # Production (uncomment and set real values)
    # OIDC_ISSUER_URL=https://login.microsoftonline.com/{tenant_id}/v2.0
    # JIRA_BASE_URL=https://jira.company.com
    # TEMPO_BASE_URL=https://api.tempo.io
    # GITHUB_API_URL=https://api.github.com

Service client pattern:
- Every external dependency must have a client class/module
- The client reads its base URL from an environment variable
- The client does NOT check whether the URL points to a mock or real service
- No if/else branching for development vs production -- same code path everywhere
- CRITICAL: Service clients MUST only call endpoints that actually exist on the
  mock services. Before writing a service client method, verify the mock service
  implements that endpoint. Known mock service API contracts:
    - mock-jira: Use /rest/api/2/project/search for projects (NOT /rest/api/3/project).
      Use /rest/api/3/search/jql for issue search (NOT /rest/api/3/search GET).
      Use /rest/api/3/issue/{key} for individual issues.
    - mock-tempo: All requests require Authorization: Bearer header.
      Use /4/worklogs for worklogs, /4/teams for teams.
    - mock-oidc: Use /users/{sub} PUT to register users, /clients/{id} PUT for
      redirect URIs. Userinfo only returns sub, email, name, preferred_username
      (NO role or custom claims).
  If you're unsure whether an endpoint exists on a mock service, read the mock
  service's route files before writing the client method.
- Example (Python):
    class JiraClient:
        def __init__(self):
            self.base_url = os.getenv("JIRA_BASE_URL")
        async def get_projects(self):
            async with httpx.AsyncClient() as client:
                response = await client.get(f"{self.base_url}/rest/api/2/project/search")
                return response.json()

Mock service seeding (MANDATORY):
- Generate a seed script (scripts/seed-mock-services.sh) that runs after
  docker-compose --profile dev up and populates all mock services with app data:
    1. Wait for all mock services to be healthy (poll /health endpoints)
    2. Register app-specific users in mock-oidc via PUT /users/{sub} with
       correct name, email, and preferred_username matching the database seed users
    3. Remove any default mock-oidc users that don't belong to this app
       (mock-oidc may have pre-seeded users from other projects)
    4. Update the mock-oidc client redirect URIs via PUT /clients/{client_id}
       to include the app's actual frontend callback URL (e.g.,
       http://localhost:3100/api/auth/callback)
    5. Verify all mock services return data on their main endpoints
- The seed script must be idempotent (safe to run multiple times)
- The seed script runs as part of the build-verify step, NOT left for the user

Verification:
- After docker-compose --profile dev up, ALL mock services must respond to
  their health check endpoints
- The auth flow must work end-to-end against mock-oidc (login -> callback ->
  session -> dashboard)
- Service clients must successfully call mock endpoints and return data
- Mock-oidc must have exactly the right users for this app (no extras, no missing)
```

**Required context:** list of external integrations, auth roles for mock users
**Runs when:** Always (every app has at least auth, which needs mock-oidc)

---

## Prompt #13: Seed Data for Local Development

```
Generate seed data for [PROJECT_NAME] so the app is fully populated on first startup.
The user should open the app and immediately see a living, realistic experience -- NOT
empty pages, NOT blank dashboards, NOT "no data found" messages.

Stack: [STACK]
Database: [DATABASE]
Migration tool: [MIGRATION_TOOL]
Roles: [ROLES_LIST]
Pages: [PAGES_LIST]
Mock OIDC test users: [MOCK_USERS_BLOCK]
External integrations: [INTEGRATIONS_LIST]

Generate a seed migration or startup script that populates the database with:

1. **Users (one per role, matching mock-oidc test users):**
   For each role defined in app-context.json, create a user record with:
   - email matching the mock-oidc test user for that role
   - oidc_subject matching the mock-oidc subject ID (e.g., "mock-admin", "mock-user")
   - name matching the mock-oidc display name
   - role set correctly
   - last_login set to a recent date (so the app looks active)
   CRITICAL: The oidc_subject in the database MUST exactly match the "sub" claim
   that mock-oidc returns in its userinfo response. This is how the auth callback
   maps an OIDC login to a database user with the correct role. If these don't
   match, the user will be created as a new "user" role instead of getting their
   intended role (admin, manager, etc.).
   The mock service seed script (scripts/seed-mock-services.sh) must register
   users in mock-oidc with the same subject IDs used in the database seed.

2. **Core domain records (enough to populate every page):**
   For each page/feature in the app, generate realistic sample data:
   - List pages: 15-25 records with varied statuses, dates, and owners
   - Dashboard metrics: enough underlying data to produce meaningful aggregations
   - Charts/graphs: data spanning at least 6 months of history
   - Detail pages: records with enough related data to look complete
   - Use realistic names, descriptions, and values from the app's domain
   - Vary the data: mix of statuses (active, completed, pending, failed),
     different date ranges, different owners/creators
   - Include some "recent" activity (today, this week) so the app feels alive

3. **Integration-sourced records (if the app syncs from external systems):**
   Create records that look like they were synced from external services:
   - Data source records showing connected/synced status with recent timestamps
   - Sample data that matches the mock service responses
   - Use the same DATA_SEED naming conventions as mock services for consistency

4. **Edge cases and variety:**
   - At least one item in each possible status (don't make everything "active")
   - At least one high-priority/critical item (for alerts, dashboards)
   - Some old records and some very recent ones
   - Records created by different users (spread ownership across roles)

Implementation:
- If using Alembic: create a data migration (separate from the schema migration)
  that uses bulk_insert or op.execute to populate tables
- If using Prisma: create a seed.ts file referenced in package.json prisma.seed
- The seed must be idempotent -- check if data already exists before inserting
  (e.g., use INSERT ... ON CONFLICT DO NOTHING, or check row count first)
- The seed runs automatically on first startup (called from the startup script
  or as part of the migration chain)
- Use deterministic IDs (uuid5 with namespace) so the seed can be re-run safely

Data volume guidelines:
- Users: 1 per role (4-6 typically)
- Primary domain objects: 15-25 each (forecasts, scenarios, projects, etc.)
- Secondary/child objects: 3-5 per parent (tasks per project, items per list)
- History/log records: 50-100 (activity feeds, audit logs)
- Dashboard data: enough for 6-12 months of chart data points
```

**Required context:** roles, pages, features, integrations, mock-oidc test users, database/ORM choice
**Runs when:** Always -- every app needs seed data for a meaningful first-run experience

---

## Prompt #14: Standard UI Components

```
Generate the four standard UI components for [PROJECT_NAME]. These components provide
a polished, production-ready experience out of the box. They are built into every app
by default -- the user can customize them after the initial build.

Stack: Next.js with Tailwind CSS, shadcn/ui, lucide-react
Pages: [PAGES_LIST]
Roles: [ROLES_LIST]

Generate ALL FOUR components below. Do NOT skip any.

--- Component 1: Breadcrumb Navigation ---

File: components/breadcrumbs.tsx

Create an auto-generated breadcrumb component that derives breadcrumbs from the current
URL path using usePathname().

Requirements:
- SEGMENT_LABELS map populated with ALL pages in this app:
  [For each page, map the URL segment to a human-readable label, e.g.:
   "dashboard": "Dashboard",
   "forecasting": "Forecasting",
   "scenarios": "Scenarios",
   "settings": "Settings",
   "admin": "Admin",
   "users": "Users",
   etc.]
- Home icon (lucide Home) as first breadcrumb, links to /
- ChevronRight separators between items (aria-hidden)
- Last item styled as current page (font-medium, text-foreground, not clickable, aria-current="page")
- Intermediate items are clickable links (text-muted-foreground, hover:text-foreground)
- UUID/ID segments auto-detected (regex for UUIDs, numeric IDs) and truncated
- Kebab-case/snake_case segments auto-converted to Title Case
- Returns null on dashboard/home page (no breadcrumbs needed)
- nav element with aria-label="Breadcrumb"

--- Component 2: DataTable with Excel-Style Filters ---

Files:
- components/data-table.tsx (main container)
- components/data-table-column-header.tsx (Excel-style filter popover per column)
- components/data-table-toolbar.tsx (global search, filter badges, column visibility, reset)
- components/data-table-pagination.tsx (rows per page, page navigation)

Create a reusable, paginated DataTable using TanStack React Table v8 (@tanstack/react-table).

Dependencies to install: @tanstack/react-table
shadcn components needed: button, input, badge, checkbox, popover, dropdown-menu, select,
  scroll-area, table, separator

Requirements:
- Custom FilterValue type supporting both array (multi-select) and comparison operators
- arrayIncludesFilter function handling: array filtering, comparison (>=, <=, >, <, =, !=),
  date parsing, numeric parsing, string comparison
- State: sorting, columnFilters, columnVisibility, globalFilter, grouping, expanded, pagination
- LocalStorage persistence with storage key "table-filters-{tableId}"
- Persisted state validation against current column definitions
- Column header popover with:
  - Sort A→Z / Z→A buttons with clear
  - Hide column button
  - Mode toggle for date/number columns (Multi-select vs Comparison)
  - Multi-select mode: search within values, Select All / Clear / Invert,
    checkbox list with counts, hover actions (Select Only, Exclude)
  - Comparison mode: operator selector + value input
- Toolbar: global search, active filter count badge, group by dropdown,
  column visibility popover, reset button (orange when customizations active)
- Pagination: rows per page (10/20/30/40/50), direct page input, First/Prev/Next/Last buttons

Every list page in the app MUST use this DataTable component. Define column definitions
with DataTableColumnHeader for each list page:
[PAGES_THAT_HAVE_LISTS]

--- Component 3: Navigation Search (Command Palette) ---

File: components/quick-search.tsx

Create a command palette accessible via ⌘K (Mac) / Ctrl+K (Windows).

Requirements:
- Trigger button: outline variant, search icon, "Search..." text, ⌘K keyboard hint badge
- Modal dialog (shadcn Dialog) with search input and scrollable results list
- Fuzzy search with weighted scoring across title, description, and keywords:
  - Exact title match: highest priority
  - Title starts with query: high priority
  - Title contains query: medium priority
  - Keyword match: medium priority
  - Description contains: low priority
- Keyboard navigation: Arrow Up/Down, Enter to select, Escape to close, Tab to cycle
- selectedIndex state with scroll-into-view behavior
- Footer with keyboard hint badges (↑↓ Navigate, ↵ Select, Esc Close)
- Reset query and selection when dialog closes

Populate NAVIGATION_ITEMS with ALL pages in this app:
[For each page:
  { id: "page-slug", title: "Page Name", description: "What this page does",
    href: "/page-path", icon: AppropriateIcon, keywords: ["related", "terms"],
    category: "navigation" }
]

Populate SETTINGS_ITEMS for any settings/admin pages.

--- Component 4: Theme Toggle (Light/Dark/System) ---

Files:
- components/theme-provider.tsx (next-themes wrapper)
- components/mode-toggle.tsx (dropdown toggle)

Dependencies to install: next-themes

Requirements:
- ThemeProvider: client component wrapping NextThemesProvider, passes all props through
- Root layout integration:
  - <html lang="en" suppressHydrationWarning>
  - <body suppressHydrationWarning>
  - ThemeProvider with attribute="class", defaultTheme="system", enableSystem,
    disableTransitionOnChange
- ModeToggle: dropdown menu with Light (Sun icon), Dark (Moon icon), System (Monitor icon)
- Animated Sun/Moon icon transition using rotate/scale with dark: variant
- mounted state pattern to prevent hydration mismatch (render disabled placeholder until mounted)
- globals.css must include oklch CSS variables for both :root (light) and .dark themes
  covering: background, foreground, card, popover, primary, secondary, muted, accent,
  destructive, border, input, ring, chart-1 through chart-5, sidebar variants

--- Layout Integration ---

The authenticated layout (e.g., app/(authenticated)/layout.tsx) MUST wire these components
into the header bar:

<div className="flex h-14 items-center gap-4 border-b bg-muted/40 px-6">
  <SidebarTrigger />
  <Breadcrumbs />
  <div className="flex-1" />
  <QuickSearch />
  <ModeToggle />
</div>

This header bar sits above the page content, inside the main content area (right of sidebar).
```

**Required context:** pages list, roles list, features
**Always runs:** Yes -- every app gets these four standard UI components
