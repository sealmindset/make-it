# Build Standards (Shared Verification Checklist)

This is the **single source of truth** for what a compliant application looks like.
All three skills reference this file:

| Skill | When it runs these checks |
|-------|--------------------------|
| `/make-it` | Build-verify (Part A static checks) |
| `/retrofit-it` | Verify phase (Part A static checks) |
| `/resume-it` | Catch-up scan during context discovery |

**How to use this file:**
- Each check has an ID (e.g., `S01`) for cross-referencing
- Checks are grouped by category
- Each check specifies which tiers it applies to
- `[FIX]` = auto-fix if failing, `[BLOCK]` = must pass before handoff, `[WARN]` = note in TODO.md

**Version:** When this file is updated with new checks, `/resume-it` automatically detects
the gap on the next run and suggests the missing patterns as catch-up work.

---

## Structure & Configuration

**S01** [Tier 0] [FIX] **Project structure exists** -- All expected files for the project type are present.

**S02** [Tier 0] [FIX] **CHANGELOG.md exists** -- Has content from the build or retrofit.

**S03** [Tier 0] [FIX] **TODO.md exists** -- Has section headers and any known follow-ups.

**S04** [Tier 0] [FIX] **.gitignore configured** -- Excludes .env, credentials, node_modules, __pycache__, .next, venv, build artifacts.

**S05** [Tier 0] [BLOCK] **No secrets in committed files** -- .env is gitignored. .env.example has placeholder values only. JWT_SECRET is empty in .env.example with a generation comment.

**S06** [Tier 0] [FIX] **.env and .env.example both exist** -- .env has real local dev values. .env.example is the committed documentation. JWT_SECRET populated in .env (not empty).

**S07** [Tier 0] [BLOCK] **No hardcoded config values** -- Grep for hardcoded localhost ports or production URLs in application code. All URLs, keys, ports from environment variables.

**S08** [Tier 0] [FIX] **No stub endpoints** -- Search for "not yet implemented", "TODO: implement", "implement with" in route handlers. If found, complete the implementation.

**S09** [Tier 0] [FIX] **Project README describes the app** -- README.md must describe the application (not the tool that built it). Must include: app name and purpose, features, tech stack, prerequisites, getting started steps, test users (if applicable), architecture overview, deployment instructions, and environment variables. Must NOT mention /make-it, /ship-it, /resume-it, or Claude Code.

---

## Authentication & OIDC

**A01** [Tier 1, 5*] [BLOCK] **Auth callback reads roles from database** -- Callback queries users table by oidc_subject. NEVER uses OIDC claims for roles.

**A02** [Tier 1, 5*] [BLOCK] **Logout is POST** -- Backend POST endpoint clears JWT cookie. Frontend logout button calls via POST (not GET link or `<a href>`).

**A03** [Tier 1] [BLOCK] **Same-origin proxy** -- next.config.ts has rewrites() routing /api/* to backend. Frontend BASE_URL="/api" (relative). BACKEND_INTERNAL_URL set in frontend Dockerfile/compose. OIDC redirect_uri uses FRONTEND_URL/api/auth/callback.

**A04** [Tier 1, 5*] [BLOCK] **OIDC state parameter** -- Login generates `secrets.token_urlsafe(32)`, stores in oidc_state httpOnly cookie (max_age=600), includes in authorization URL. Callback validates with `secrets.compare_digest()`, clears cookie after use.

**A05** [Tier 1] [FIX] **Set-Cookie workaround (Next.js 16+)** -- OIDC callback returns HTMLResponse (200) with JWT cookie + meta-refresh + JS redirect. NOT RedirectResponse (307 strips Set-Cookie).

**A06** [Tier 1, 5*] [BLOCK] **Cookie Secure flag from URL** -- Derived from `FRONTEND_URL.startswith("https")`. NEVER hardcoded. NEVER from NODE_ENV.

**A07** [Tier 1, 5*] [BLOCK] **Flat JWT payload** -- `{sub, email, name, role_id, role_name, permissions[]}` at top level. No `.user` wrapper object.

**A08** [Tier 1] [BLOCK] **AuthMe type matches JWT** -- Frontend AuthMe type is flat. All components use `authMe.name` not `authMe.user.display_name`.

**A09** [Tier 1] [BLOCK] **No global 401 redirect** -- API client handleResponse does NOT redirect to "/" on 401. Login page checks /auth/me (expects 401). Auth guard in layout handles redirects.

**A10** [Tier 1, 5*] [FIX] **ENFORCE_SECRETS pattern** -- `enforce_secrets()` called at app startup. When ENFORCE_SECRETS=true: JWT_SECRET must be >=32 chars and not a known default, OIDC_CLIENT_SECRET must not be mock default. ENFORCE_SECRETS=false in docker-compose (local dev).

---

## RBAC & Permissions

**R01** [Tier 1, 5*] [BLOCK] **Database-driven RBAC tables** -- roles, permissions, role_permissions tables exist in migration. users table has role_id FK (not VARCHAR role column).

**R02** [Tier 1, 5*] [FIX] **4 system roles seeded** -- Super Admin, Admin, Manager, User with is_system=true.

**R03** [Tier 1, 5*] [FIX] **Scaffold permissions seeded** -- admin.users (read/create/update/delete), admin.roles (read/create/update/delete), admin.settings (read/update), admin.logs (read/delete).

**R04** [Tier 1, 5*] [BLOCK] **require_permission middleware** -- Used on ALL route handlers. Never check role strings directly. Pattern: `require_permission(resource, action)`.

**R04a** [Tier 1, 5*] [BLOCK] **Permission names consistent across stack** -- Backend `require_permission()` args, frontend `hasPermission()` args, sidebar nav permissions, quick-search permissions, and seed migration data MUST all use identical resource/action strings. Standard format: `admin.users`/`admin.roles` with actions `read`/`create`/`update`/`delete` (NEVER `view`/`edit`). Domain resources use the resource name directly (e.g., `projects.read`). Cross-reference all five locations after any permission change.

**R05** [Tier 1, 5*] [FIX] **Permission service** -- `has_permission(user, resource, action)` with in-memory cache and invalidation on role/permission changes.

**R06** [Tier 1] [FIX] **Admin UI** -- User Management + Role Management pages with permission matrix.

**R07** [Tier 1] [FIX] **Frontend permission gating** -- Sidebar shows/hides items based on permissions from JWT. Action buttons gated with `hasPermission(resource, action)` from `useAuth()`.

---

## UI & Frontend

**U01** [Tier 1] [FIX] **Standard UI components** -- All four must exist and be wired:
- `components/breadcrumbs.tsx` with SEGMENT_LABELS for all pages
- `components/data-table.tsx` with sorting, filtering, pagination
- `components/quick-search.tsx` with NAVIGATION_ITEMS for all pages (Cmd+K)
- `components/mode-toggle.tsx` for light/dark theme

**U02** [Tier 1] [FIX] **Header bar structure** -- Authenticated layout header: `SidebarTrigger | Breadcrumbs | <spacer> | QuickSearch | ModeToggle`

**U03** [Tier 1] [FIX] **ThemeProvider** -- Wraps app in root layout with `suppressHydrationWarning`. oklch CSS variables. `@tanstack/react-table` and `next-themes` in package.json.

**U04** [Tier 1] [BLOCK] **System fonts only** -- No `next/font/google`, `fonts.googleapis.com`, or external font CDN references. Replace with system font stacks.

**U05** [Tier 1] [BLOCK] **No hardcoded mock data in pages** -- Pages fetch through service/API layer, not inline arrays.

**U06** [Tier 1] [FIX] **All list pages use DataTable** -- No plain HTML tables for data lists.

**U07** [Tier 1] [FIX] **Frontend types match backend schemas** -- Field name spelling, nesting, list vs paginated response. Cross-reference Pydantic schemas against TypeScript interfaces.

---

## Database & Seed Data

**D01** [Tier 1, 5] [BLOCK] **Database migrations exist** -- Alembic versions/ or Prisma migrations/ (not just model files).

**D02** [Tier 1, 5] [FIX] **Seed data exists** -- At least one user per role (oidc_subject matching mock-oidc), 10-20 domain items per list page, dashboard metrics show non-zero, recent timestamps.

**D03** [Tier 1, 5] [BLOCK] **Seed user oidc_subjects match mock-oidc** -- mock-admin, mock-manager, mock-user, mock-viewer aligned with DB seed.

**D04** [Tier 1, 5] [FIX] **Seed migration is idempotent** -- Safe to run multiple times.

**D05** [Tier 1] [FIX] **Alembic syntax rules** (if using SQLAlchemy):
- `sa.text("...").bindparams(...)` for parameterized inserts (NOT `op.execute()` with 2+ args)
- f-string literals for deterministic UUIDs (NOT PostgreSQL `::uuid` cast)
- `sa.Enum(create_type=False)` for existing enum columns (NOT `sa.String`)

---

## Docker & Infrastructure

**I01** [Tier 1, 5] [FIX] **Docker Compose exists** -- Profiles: default for app, "dev" for mocks.

**I02** [Tier 1, 5] [FIX] **Port availability** -- Check `lsof -i :PORT` for all ports. Remap if in use (increment by 100).

**I03** [Tier 1, 5] [FIX] **Health checks use 127.0.0.1** -- NOT localhost (IPv6 resolution issues in Alpine).
- Frontend: `wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/`
- Backend: `python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"`
- mock-oidc: `python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:10090/health')"`
- PostgreSQL: `pg_isready -U [APP_SLUG]`

**I04** [Tier 1, 5] [FIX] **Non-root Docker user** -- Every Dockerfile creates and switches to appuser:appgroup (UID/GID 1001).

**I05** [Tier 1, 5] [BLOCK] **Backend Dockerfile uses entrypoint.sh** -- If DB migrations needed (Alembic/Prisma), CMD invokes entrypoint.sh (wait-for-DB → run migrations → exec server). NOT direct uvicorn/node.

**I06** [Tier 1, 5] [BLOCK] **Env var names match backend config** -- Cross-reference pydantic Settings fields against docker-compose.yml environment block. Fix mismatches (OIDC_ISSUER vs OIDC_ISSUER_URL, etc.).

**I07** [Tier 1] [FIX] **Trailing-slash wrapper (FastAPI)** -- TrailingSlashASGI middleware prevents Docker hostname leaks in FastAPI redirects.

---

## Mock Services

**M01** [Tier 1, 5] [FIX] **mock-oidc exists** -- Copied from scaffold as-is (never regenerated). In docker-compose with profile: dev. Internal/external URL split configured.

**M02** [Tier 1, 5] [FIX] **Seed script exists** -- scripts/seed-mock-services.sh registers users (one per role), removes non-app users, updates redirect URIs.

**M03** [Tier 1, 5] [BLOCK] **Service client ↔ mock contracts** -- Cross-reference client methods with mock route files. Fix endpoint mismatches.

**M04** [Tier 1, 5] [BLOCK] **All service URLs from env vars** -- Never hardcoded base URLs in client code.

---

## Activity Logs

**L01** [Tier 1, 5] [FIX] **LogStore/LogService exists** -- Circular buffer with configurable max size (LOG_BUFFER_SIZE env var, default 10000).

**L02** [Tier 1, 5] [FIX] **Inbound request middleware** -- Captures method, path, status, duration, user, ip, user_agent. Skips health checks and static assets.

**L03** [Tier 1, 5] [BLOCK] **Outbound HTTP interceptors** -- Attached to ALL HTTP client creation points. Captures service name, sanitized URL, method, status, duration.

**L04** [Tier 1, 5] [FIX] **URL sanitization** -- Strips query params containing token, key, secret, password, auth before logging.

**L05** [Tier 1, 5] [FIX] **REST API** -- GET /api/admin/logs/events (filtered, paginated), GET /api/admin/logs/stats, DELETE /api/admin/logs/events.

**L06** [Tier 1, 5] [FIX] **RBAC permissions** -- admin.logs.read and admin.logs.delete in seed data. DELETE requires admin.logs.delete.

**L07** [Tier 1] [FIX] **Admin UI tab** -- Stats cards, filter controls (type, service, method, search), event table, auto-refresh toggle, Clear Buffer button (admin.logs.delete permission).

**L08** [Tier 1, 5] [FIX] **Environment variables** -- LOG_BUFFER_SIZE in .env.example and docker-compose.yml. CRIBL_STREAM_URL and CRIBL_STREAM_TOKEN placeholders in .env.example.

---

## Application Settings

**G01** [Tier 1] [FIX] **Settings tables exist** -- app_settings and app_setting_audit_logs tables in migration.

**G02** [Tier 1] [FIX] **Settings service** -- get_setting() with cascading precedence: DB > .env > code default. In-memory cache (60s TTL). invalidate_cache() and mask_sensitive().

**G03** [Tier 1] [FIX] **All .env vars seeded** -- app_settings table populated with metadata (group_name, display_name, description, value_type, is_sensitive, requires_restart).

**G04** [Tier 1] [FIX] **Settings REST API** -- GET /api/admin/settings (masked), PUT /api/admin/settings/{key}, GET /api/admin/settings/{key}/reveal, GET /api/admin/settings/audit-log.

**G05** [Tier 1] [FIX] **Admin Settings page** -- /admin/settings with group tabs, masked sensitive values, inline editing, audit log.

**G06** [Tier 1] [FIX] **Settings RBAC** -- app_settings.view and app_settings.edit permissions. Super Admin and Admin only.

**G07** [Tier 1] [FIX] **Graceful fallback** -- App starts correctly with empty app_settings table (falls back to .env).

---

## Security

**X01** [Tier 0] [BLOCK] **No secrets in code** -- Grep for API keys, passwords, tokens in committed files.

**X02** [Tier 0] [FIX] **Input validation** -- At system boundaries (user input, API responses, file parsing).

**X03** [Tier 0] [FIX] **Latest stable dependencies** -- No outdated majors. Check for known CVEs.

**X04** [Tier 0] [BLOCK] **No Java runtime dependencies** -- No Java-based tools, libraries, or Docker images.

**X05** [Tier 1] [FIX] **Security headers** -- Appropriate headers for production (HSTS, CSP, X-Frame-Options, etc.).

**X06** [Tier 0] [BLOCK] **No module-level throws (Next.js)** -- Secret/config assertions deferred to runtime functions, not import-time throws.

---

## Test Infrastructure

**T01** [Tier 1, 5] [FIX] **pytest configuration** -- pytest.ini with asyncio_mode=auto, testpaths=tests.

**T02** [Tier 1, 5] [FIX] **Test conftest.py** -- In-memory SQLite with UUID compat patch, auth bypass via dependency overrides, admin_client/user_client/viewer_client fixtures, seed_user() helper.

**T03** [Tier 1, 5] [FIX] **Health endpoint tests** -- tests/integration/test_health.py with basic smoke tests.

**T04** [Tier 1] [FIX] **Playwright scaffolding** -- e2e/package.json, e2e/playwright.config.ts targeting FRONTEND_PORT, e2e/tests/health.spec.ts.

**T05** [Tier 0] [FIX] **Existing tests preserved** -- After any retrofit or update, existing tests still pass.

---

## Live Verification Checks

These checks run after the app is started (Docker containers up, health checks passing).

**V01** [Tier 1, 5] [BLOCK] **SSL proxy detection** -- Check for Zscaler/Netskope/GlobalProtect before Docker builds. Ask user to pause if detected.

**V02** [Tier 1, 5] [BLOCK] **All containers healthy** -- Poll health endpoints (timeout 120s per service).

**V03** [Tier 1, 5] [BLOCK] **Seed script runs** -- `bash scripts/seed-mock-services.sh` completes without error.

**V04** [Tier 1, 5*] [BLOCK] **Auth flow works for EACH role** -- Login through mock-oidc, JWT cookie set, /auth/me returns correct role from DB, dashboard loads with content, logout clears cookie.

**V05** [Tier 1, 5] [BLOCK] **Every API endpoint responds** -- 2xx, valid JSON, non-empty arrays from list endpoints.

**V06** [Tier 1] [BLOCK] **Every page loads** -- HTTP 200, meaningful content (not empty tables).

**V07** [Tier 1, 5*] [BLOCK] **Permission boundaries** -- Correct access per role. 403 for unauthorized.

**V08** [Tier 1, 5] [FIX] **Activity Logs capturing** -- /api/admin/logs/stats returns data. /api/admin/logs/events has entries after requests.

**V09** [Tier 1, 5] [BLOCK] **Docker build cache** -- After source fixes, rebuild with `--no-cache` to prevent stale output.

---

## AI Features (when ai_features.needed = true)

These checks apply to ANY project type that uses AI/LLM features.

**AI01** [AI] [FIX] **Provider abstraction** -- lib/ai/ with factory function. No provider SDK imports in business logic.

**AI02** [AI] [FIX] **Input sanitization** -- sanitizePromptInput() in lib/ai/, called by BaseAgent before invoke(). User input in `<user_input>` tags.

**AI03** [AI] [FIX] **Output validation** -- validateAgentOutput() called after every AI response. Structured outputs schema-validated. Free-text scanned for XSS.

**AI04** [AI] [FIX] **Rate limiting** -- Dedicated AI rate limits. 429 with Retry-After on excess.

**AI05** [AI] [FIX] **Prompt size validation** -- Rejects inputs exceeding AI_MAX_PROMPT_CHARS (413).

**AI06** [AI] [FIX] **Error sanitization** -- Provider errors mapped to generic messages. No provider/model/key details in responses.

**AI07** [AI] [FIX] **No dangerouslySetInnerHTML for AI output** -- Escaped rendering only.

**AI08** [AI] [FIX] **Prompt management (Tier 2 minimum)** -- managed_prompts + prompt_versions tables. Admin UI for editing. Safety preamble. Seed all prompts. Agents load from DB with code fallback.

**AI09** [AI] [FIX] **NeMo Guardrails** -- guardrails/ directory, config.yml, Colang rails. Basic suite (18 tests) passes.

**AI10** [AI] [FIX] **Prompt template validation (Tier 2/3)** -- validatePromptTemplate() on save endpoints. Immutable safety preamble. Draft/test/publish workflow. Variable interpolation sanitized.

---

## Common Fix Cycle Issues

When live verification fails, these are the most common root causes and fixes:

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Auth callback returns wrong role | Callback uses OIDC claims, not DB | Query users table by oidc_subject |
| Logout returns 404 | Route is GET not POST | Change to POST endpoint + frontend button |
| Service client 404 from mock | Endpoint URL mismatch | Cross-reference client with mock routes |
| Empty pages | Seed migration didn't run | Verify entrypoint.sh runs migrations |
| Docker build TLS error | SSL-inspecting proxy | Ask user to pause Zscaler/Netskope |
| Health check fails | IPv6 resolution | Use 127.0.0.1 not localhost |
| Port already allocated | Host port conflict | Remap in docker-compose + .env |
| Backend can't reach mock-oidc | Wrong issuer URL | Use http://mock-oidc:10090 (internal) |
| Alembic migration fails | Syntax issues | sa.text().bindparams(), f-string UUIDs |
| DB empty after startup | CMD bypasses entrypoint | Dockerfile CMD must use entrypoint.sh |
| Cross-origin cookie blocked | Missing proxy | Implement same-origin proxy in next.config.ts |
| AuthMe undefined errors | Nested .user wrapper | Flatten to match JWT payload |
| Login infinite loop | Global 401 redirect | Remove from API client handleResponse |
| API 404s | Double /api prefix | BASE_URL="/api" + paths without /api |
| Frontend type errors | Schema mismatch | Read Pydantic schemas, fix TS interfaces |
| OIDC callback cookie not set | redirect_uri wrong | Must go through frontend proxy |
| Stale code after fix | Docker layer cache | Rebuild with --no-cache |
