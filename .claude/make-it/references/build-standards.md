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

**S09** [Tier 0] [BLOCK] **Project README describes the app** -- README.md must describe the application (not the tool that built it). Must include: app name and purpose, features, tech stack, prerequisites, getting started steps, test users (if applicable), architecture overview, deployment instructions, and environment variables. Must NOT mention /make-it, /ship-it, /resume-it, or Claude Code. **Red flag**: if README contains "scaffold", "placeholder", or "How Claude Uses This", it is the scaffold README and must be replaced.

---

## Authentication & OIDC

**These checks apply to the SaaS auth pattern (OIDC + local RBAC) only.** If EasyAuth is selected (see design-blueprint.md Section 1b), skip all A01-A10 checks.

**A01** [Tier 1, 5*] [BLOCK] **Auth callback reads roles from database** -- Callback queries users table by oidc_subject. NEVER uses OIDC claims for roles.

**A02** [Tier 1, 5*] [BLOCK] **Logout is POST** -- Backend POST endpoint clears JWT cookie. Frontend logout button calls via POST (not GET link or `<a href>`).

**A03** [Tier 1] [BLOCK] **Same-origin proxy** -- next.config.ts has rewrites() routing /api/* to backend. Frontend BASE_URL="/api" (relative). BACKEND_INTERNAL_URL set in frontend Dockerfile/compose. OIDC redirect_uri uses FRONTEND_URL/api/auth/callback.

**A04** [Tier 1, 5*] [BLOCK] **OIDC state parameter** -- Login generates `secrets.token_urlsafe(32)`, stores in oidc_state httpOnly cookie (max_age=600), includes in authorization URL. Callback validates with `secrets.compare_digest()`, clears cookie after use.

**A05** [Tier 1] [FIX] **Set-Cookie workaround (Next.js 16+)** -- OIDC callback returns HTMLResponse (200) with JWT cookie + meta-refresh + JS redirect. NOT RedirectResponse (307 strips Set-Cookie).

**A06** [Tier 1, 5*] [BLOCK] **Cookie Secure flag from URL** -- Derived from `FRONTEND_URL.startswith("https")`. NEVER hardcoded. NEVER from NODE_ENV.

**A07** [Tier 1, 5*] [BLOCK] **Flat JWT payload with multi-role support** -- `{sub, email, name, role_id, role_name, roles: [{id, name}], permissions[]}` at top level. No `.user` wrapper object. `role_id` and `role_name` are the PRIMARY role (highest precedence, for display). `roles` is the full list of effective roles. `permissions` is the UNION of permissions across ALL effective roles.

**A08** [Tier 1] [BLOCK] **AuthMe type matches JWT** -- Frontend AuthMe type is flat and includes multi-role fields. All components use `authMe.name` not `authMe.user.display_name`. Permission checks use `authMe.permissions` (union of all roles). Display uses `authMe.role_name` (primary). `authMe.roles` available for role-specific UI (e.g., classification visibility).

**A09** [Tier 1] [BLOCK] **No global 401 redirect** -- API client handleResponse does NOT redirect to "/" on 401. Login page checks /auth/me (expects 401). Auth guard in layout handles redirects.

**A10** [Tier 1, 5*] [FIX] **ENFORCE_SECRETS pattern** -- `enforce_secrets()` called at app startup. When ENFORCE_SECRETS=true: JWT_SECRET must be >=32 chars and not a known default, OIDC_CLIENT_SECRET must not be mock default. ENFORCE_SECRETS=false in docker-compose (local dev).

---

## RBAC & Permissions

**These checks apply to the SaaS auth pattern (OIDC + local RBAC) only.** If EasyAuth is selected, skip all R01-R07 checks. If database is excluded (design-blueprint.md Section 3b), these checks are not applicable.

**R01** [Tier 1, 5*] [BLOCK] **Database-driven RBAC tables** -- roles, permissions, role_permissions, AND user_roles tables exist in migration. users table has a `primary_role_id` FK for display purposes. The `user_roles` many-to-many junction table (user_id, role_id) stores ALL effective roles per user. Authorization MUST check `user_roles` (not just `primary_role_id`).

**R01a** [Tier 1, 5*] [BLOCK] **Multi-role permission union** -- Permission checks MUST union permissions across ALL of a user's effective roles (from `user_roles`). If ANY role grants a permission, the user has it. Never check only the primary role. The auth callback must query `user_roles` to build the full permissions list for the JWT.

**R02** [Tier 1, 5*] [FIX] **4 system roles seeded** -- Super Admin, Admin, Manager, User with is_system=true.

**R03** [Tier 1, 5*] [FIX] **Scaffold permissions seeded** -- admin.users (read/create/update/delete), admin.roles (read/create/update/delete), admin.settings (read/update), admin.logs (read/delete).

**R04** [Tier 1, 5*] [BLOCK] **require_permission middleware** -- Used on ALL route handlers. Never check role strings directly. Pattern: `require_permission(resource, action)`. Permission check must use the union of all effective roles, not just the primary role.

**R04a** [Tier 1, 5*] [BLOCK] **Permission names consistent across stack** -- Backend `require_permission()` args, frontend `hasPermission()` args, sidebar nav permissions, quick-search permissions, and seed migration data MUST all use identical resource/action strings. Standard format: `admin.users`/`admin.roles` with actions `read`/`create`/`update`/`delete` (NEVER `view`/`edit`). Domain resources use the resource name directly (e.g., `projects.read`). Cross-reference all five locations after any permission change.

**R05** [Tier 1, 5*] [FIX] **Permission service** -- `has_permission(user, resource, action)` with in-memory cache and invalidation on role/permission changes.

**R06** [Tier 1] [FIX] **Admin UI** -- User Management + Role Management pages with permission matrix.

**R07** [Tier 1] [FIX] **Frontend permission gating** -- Sidebar shows/hides items based on permissions from JWT. Action buttons gated with `hasPermission(resource, action)` from `useAuth()`.

---

## UI & Frontend

**U01** [Tier 1] [BLOCK] **Standard UI components** -- All four must exist and be wired:
- `components/breadcrumbs.tsx` with SEGMENT_LABELS for all pages
- `components/data-table.tsx` + `data-table-column-header.tsx` + `data-table-toolbar.tsx` + `data-table-pagination.tsx` -- the FULL 4-file DataTable system (not just the main file)
- `components/quick-search.tsx` with NAVIGATION_ITEMS for all pages (Cmd+K)
- `components/mode-toggle.tsx` + `components/theme-provider.tsx` for light/dark/system theme

**U02** [Tier 1] [FIX] **Header bar structure** -- Authenticated layout header: `SidebarTrigger | Breadcrumbs | <spacer> | QuickSearch | ModeToggle`

**U03** [Tier 1] [FIX] **ThemeProvider** -- Wraps app in root layout with `suppressHydrationWarning`. oklch CSS variables. `@tanstack/react-table` and `next-themes` in package.json.

**U04** [Tier 1] [BLOCK] **System fonts only** -- No `next/font/google`, `fonts.googleapis.com`, or external font CDN references. Replace with system font stacks.

**U05** [Tier 1] [BLOCK] **No hardcoded mock data in pages** -- Pages fetch through service/API layer, not inline arrays.

**U06** [Tier 1] [BLOCK] **All list pages use DataTable** -- No plain HTML tables (`<table>`, `<tr>`, `<td>`) for data lists. Every page that displays tabular data MUST import and use the `<DataTable>` component from `@/components/data-table`. Grep for `<table` in page files -- any match outside the DataTable component itself is a violation.

**U07** [Tier 1] [FIX] **Frontend types match backend schemas** -- Field name spelling, nesting, list vs paginated response. Cross-reference Pydantic schemas against TypeScript interfaces.

**U08** [Tier 1] [BLOCK] **DataTable feature completeness** -- Every DataTable instance MUST have ALL of the following features working (these come from the scaffold's 4-file DataTable system -- if any are missing, the scaffold files were modified or bypassed):
- **Excel-like column filtering**: `DataTableColumnHeader` renders a filter icon on each column header. Clicking opens a dropdown with search box, "Select All"/"Clear" buttons, checkbox list with row counts, and max-height scrollable area. Uses `getFacetedRowModel()` and `getFacetedUniqueValues()` from TanStack.
- **Column sorting**: Click column headers to toggle ascending/descending/unsorted. Visual indicators (ArrowUp, ArrowDown, ChevronsUpDown icons).
- **Toolbar search**: Optional `searchKey` prop targets a specific column for real-time text filtering.
- **Toolbar faceted filters**: Optional `filterableColumns` prop renders filter buttons in the toolbar with badge showing active filter count.
- **Pagination**: Page size selector (10/20/50/100), First/Prev/Next/Last page buttons, "Page X of Y" indicator.
- **Column visibility toggle**: "Columns" dropdown button in toolbar to show/hide columns.
- **State persistence**: Sorting, filters, column visibility, and pagination state saved to localStorage via `storageKey` prop.
- **Row click**: `onRowClick` callback prop for row interaction.
Verification: Read `components/data-table.tsx` and confirm it imports from `@tanstack/react-table` and uses `getSortedRowModel`, `getFilteredRowModel`, `getFacetedRowModel`, `getPaginationRowModel`. Confirm `data-table-column-header.tsx` contains the Excel filter dropdown. Confirm `data-table-pagination.tsx` has page size selector and navigation buttons. Confirm `data-table-toolbar.tsx` has search input, faceted filter buttons, and column visibility dropdown.

**U09** [Tier 1] [BLOCK] **ModeToggle functional and wired** -- The light/dark/system theme toggle MUST be:
- **Present in header**: The authenticated layout header bar MUST render `<ModeToggle />` as the rightmost element (after QuickSearch).
- **ThemeProvider wrapping app**: Root layout MUST wrap children in `<ThemeProvider>` with `attribute="class"`, `defaultTheme="system"`, `enableSystem`, `disableTransitionOnChange`.
- **oklch CSS variables**: `globals.css` MUST define CSS custom properties for BOTH `:root` (light) and `.dark` (dark) themes using oklch color space. At minimum: `--background`, `--foreground`, `--card`, `--primary`, `--secondary`, `--muted`, `--accent`, `--destructive`, `--border`, `--input`, `--ring`, `--success`, `--warning`.
- **Tailwind wired**: `tailwind.config.ts` MUST set `darkMode: "class"` and extend colors to reference CSS variables (e.g., `primary: "var(--primary)"`).
- **All pages use theme variables**: No hardcoded colors in page components. All colors MUST use either CSS variables (`var(--primary)`, `var(--background)`) or Tailwind semantic classes (`bg-primary`, `text-muted-foreground`, `border-border`). Grep for hardcoded hex (`#[0-9a-fA-F]{3,8}`), `rgb(`, `hsl(`, or `oklch(` in page files -- any match in a `.tsx` page file (not globals.css) is a violation.
- **Hydration safe**: `<html>` and `<body>` tags MUST have `suppressHydrationWarning`. ModeToggle component MUST use `mounted` state pattern to prevent server/client mismatch.
Verification: Grep for `ModeToggle` in the authenticated layout file. Grep for `ThemeProvider` in root layout. Grep for `darkMode` in tailwind.config.ts. Check globals.css for `.dark` section.

---

## Database & Seed Data

**These checks require PostgreSQL.** If database is excluded (see design-blueprint.md Section 3b), skip all D01-D05 checks.

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
- PostgreSQL: `pg_isready -U [APP_SLUG]` **(when database included)**

**I04** [Tier 1, 5] [FIX] **Non-root Docker user** -- Every Dockerfile creates and switches to appuser:appgroup (UID/GID 1001).

**I05** [Tier 1, 5] [BLOCK] **Backend Dockerfile uses entrypoint.sh** -- If DB migrations needed (Alembic/Prisma), CMD invokes entrypoint.sh (wait-for-DB → run migrations → exec server). NOT direct uvicorn/node. **If database is excluded (Section 3b), entrypoint.sh is not needed -- CMD can invoke the server directly.**

**I06** [Tier 1, 5] [BLOCK] **Env var names match backend config** -- Cross-reference pydantic Settings fields against docker-compose.yml environment block. Fix mismatches (OIDC_ISSUER vs OIDC_ISSUER_URL, etc.).

**I07** [Tier 1] [FIX] **Trailing-slash wrapper (FastAPI)** -- TrailingSlashASGI middleware prevents Docker hostname leaks in FastAPI redirects.

**I08** [Tier 0] [FIX] **Registry proxy support (Dockyard Gateway / ACR cache)** -- All Dockerfiles use `ARG DOCKER_HUB_PREFIX=` before each `FROM` instruction, with `FROM ${DOCKER_HUB_PREFIX}image:tag`. For MCR-sourced images (e.g., mssql, dotnet), use `ARG MCR_PREFIX=` and `FROM ${MCR_PREFIX}mcr.microsoft.com/...`. For GHCR-sourced images (e.g., zaproxy, custom org images), use `ARG GHCR_PREFIX=` and `FROM ${GHCR_PREFIX}ghcr.io/...`. In multi-stage builds, repeat the relevant `ARG` before EACH `FROM` (Docker ARGs do not persist across stages). All docker-compose.yml services with `build:` include ALL three prefix args: `args: [DOCKER_HUB_PREFIX=${DOCKER_HUB_PREFIX:-}, MCR_PREFIX=${MCR_PREFIX:-}, GHCR_PREFIX=${GHCR_PREFIX:-}]`. Services with `image:` use the matching prefix variable (e.g., `${DOCKER_HUB_PREFIX:-}postgres:16-alpine`). `.env.example` documents all three prefixes with auto-discovery instructions. When an organization operates a Dockyard Gateway (ACR proxy cache), all three prefixes route through it -- Docker Hub, MCR, and GHCR images all pull via the corporate registry, bypassing SSL-inspecting proxies (Zscaler, Netskope, GlobalProtect) entirely.

**I09** [Tier 0] [BLOCK] **`.dockerignore` exists and excludes secrets** -- Every project with a Dockerfile MUST have a `.dockerignore` that excludes at minimum: `.env*` (except `.env.example`), `.git/`, `__pycache__/`, `node_modules/`, `*.md` (except README.md), test directories, IDE config (`.vscode/`, `.idea/`). Without this, `COPY . .` bakes gitignored secrets (`.env`, `.env.azure`, `.env.local`) into the Docker image. Verification: `.dockerignore` exists AND contains a line matching `.env*` or `.env`.

**I10** [Tier 0] [BLOCK] **No `load_dotenv(override=True)`** -- Application code that loads local env files MUST NOT use `override=True` (Python) or `{ override: true }` (Node.js). This causes local dev files to silently overwrite environment variables injected by Kubernetes, Docker Compose, or CI/CD -- leading to production using stale dev endpoints or embedded credentials. Grep for `override=True` and `override: true` in all `.py`, `.ts`, `.js` files near `dotenv`/`load_dotenv` calls. Any match is a BLOCK finding. The correct pattern is `override=False` (or omitting the parameter).

---

## Mock Services

**M01** [Tier 1, 5] [FIX] **mock-oidc exists** -- Copied from scaffold as-is (never regenerated). In docker-compose with profile: dev. Internal/external URL split configured. **SaaS auth pattern only -- skip if EasyAuth is selected.**

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

## Notifications

**N01** [Tier 1, 5] [FIX] **Notification model exists** -- Database table: notifications with fields: id, recipientType (INTERNAL/VENDOR/ROLE), recipientId (nullable -- null means broadcast to all users of that recipientType), notificationType (app-specific string, e.g. ESCALATION, ASSIGNMENT, STATUS_CHANGE), title, message (nullable), relatedEntityType (nullable -- domain entity name), relatedEntityId (nullable -- entity ID for navigation), sentBy (nullable -- agent/service/system name), sentAt, readAt (nullable -- null means unread), status (PENDING/SENT/READ/FAILED, default PENDING), createdAt.

**N02** [Tier 1, 5] [FIX] **Notification query helper** -- Shared module (lib/notifications or services/notification_service) with `buildNotificationWhere(userId, roleName)` that scopes queries to the current user. Internal users see: broadcast notifications (recipientType=INTERNAL, recipientId=null) PLUS targeted notifications (recipientType=INTERNAL, recipientId=userId). External/vendor users see only targeted (recipientId=userId). Query uses OR logic. Separate `withUnreadFilter()` helper adds readAt=null constraint.

**N03** [Tier 1, 5] [FIX] **Notification REST API** -- Three endpoints, all user-scoped via the query helper:
- `GET /api/notifications` -- List notifications for current user. Supports query params: status=UNREAD (filters to unread only), limit (default 20, max 50), offset (default 0). Response: `{ notifications: [...], unreadCount: number, total: number }`. Always returns unreadCount regardless of pagination.
- `PATCH /api/notifications` -- Mark notifications as read. Body: `{ ids: string[] }` (specific) or `{ markAllRead: true }` (all). Updates matching user-scoped notifications: readAt=now(), status=READ. Response: `{ updated: number }`.
- `GET /api/notifications/count` -- Lightweight unread count for polling. Response: `{ unreadCount: number }`. This endpoint must be fast (single COUNT query, no joins).

**N04** [Tier 1] [FIX] **Notification bell component** -- Header bell icon with dynamic unread badge (hidden when 0, shows "9+" when >9). Click opens dropdown panel: positioned absolute right-0, z-50, w-96, with header ("Notifications" + "Mark all read" link), scrollable list (max-h-96 overflow-y-auto), and empty state (muted bell icon + "No notifications"). Each notification item has color-coded left border by type, title (truncated), sentBy badge, relative time ("2m ago", "3h ago", "1d ago"), and unread dot indicator. Click item opens detail Dialog with full message, metadata, and "Go to [entity]" button. Polling: 30s interval on /api/notifications/count endpoint. Full list fetched only on dropdown open.

**N05** [Tier 1, 5] [FIX] **Entity-to-route mapping** -- Function `getEntityRoute(entityType, entityId)` maps notification relatedEntityType + relatedEntityId to app page routes. Each domain entity type has a corresponding route. Fallback to dashboard/home when entityType is null or unrecognized. Used by the detail dialog "Go to" button.

**N06** [Tier 1, 5] [FIX] **Notification type color coding** -- Configuration map: `notificationType` → `{ borderColor, bgColor, textColor, icon, label }`. At minimum 3 types defined matching the app's domain events. Color convention: red/destructive for urgent/escalation, orange/warning for action-required, blue/info for informational requests. Each type has a distinct Lucide icon. Default/fallback config for unknown types (gray).

**N07** [Tier 1, 5] [FIX] **Seed notifications** -- At least 5 sample notifications in seed data. Requirements: tied to real seeded user IDs (capture user IDs during seed), reference real seeded domain entity IDs, mix of broadcast (recipientId=null) and targeted (recipientId=specific user), at least one already-read notification (readAt set, status=READ), spread across multiple notification types, timestamps spread across recent days (1d, 2d, 3d, 5d, 10d ago). Different users should see different unread counts.

**N08** [Tier 1, 5] [FIX] **Notification creation is server-side only** -- Notifications are created by backend services, agents, background jobs, or system events. No public POST /api/notifications endpoint. Notification creation calls are added to service/agent logic wherever the app creates, escalates, assigns, changes status, or alerts. All authenticated users can read their own scoped notifications without additional RBAC permissions (uses the same auth gate as dashboard access).

---

## File Upload & Document Processing

**F01** [Tier 1, 5] [FIX] **Upload UI component exists** -- Reusable `FileUploadZone` component supporting drag-and-drop, click-to-browse, and paste. Uses HTML5 drag events (`onDragOver`, `onDragEnter`, `onDragLeave`, `onDrop`) with visual feedback (dashed border highlight on drag-over). Accepts a configurable `accept` prop for MIME types and an `maxSize` prop for file size limit. Shows file name, size, type after selection. Includes upload progress indicator and error display. Component is self-contained -- no external upload libraries.

**F02** [Tier 1, 5] [BLOCK] **Upload API route processes in-memory** -- File upload POST endpoint accepts `multipart/form-data`, extracts the file into a `Buffer` (Node.js) or `bytes` (Python) in memory, and passes the buffer directly to the extraction/processing pipeline. NEVER writes uploaded files to a temp path before processing. Validates file size BEFORE reading the full buffer (check `Content-Length` header or `file.size` against `MAX_FILE_SIZE` env var, default 50MB). Returns 400 for missing file, 413 for oversized file.

**F03** [Tier 1, 5] [BLOCK] **PDF extraction uses pdf-parse/lib/pdf-parse (NOT pdf-parse index.js)** -- The `pdf-parse` npm package has a known bug: its `index.js` wrapper contains debug code that runs `Fs.readFileSync('./test/data/05-versions-space.pdf')` when `module.parent` is undefined. In Next.js standalone builds (Turbopack/webpack bundling), `module.parent` evaluates to `undefined`, triggering the debug path and causing `ENOENT: no such file or directory` at runtime. The FIX: always import `pdf-parse/lib/pdf-parse` directly, which is the actual parser without the debug wrapper. Python apps using `pdfplumber`, `PyPDF2`, or `pdfminer` are not affected. **This is a BLOCK check -- builds that use `pdf-parse` default import WILL fail in production Docker containers.**

**F04** [Tier 1, 5] [FIX] **Multi-format text extraction** -- A shared extraction utility (`lib/documents/extract-text` or equivalent) handles at minimum: PDF (via pdf-parse/lib/pdf-parse), DOCX (via JSZip reading `word/document.xml` with XML tag stripping), XLSX (via ExcelJS or openpyxl iterating sheets and rows), images (returned as base64 with MIME type for vision AI), and plain text (UTF-8 decode). Each format has a try/catch that throws a descriptive error (`Failed to extract PDF content`) without leaking library internals. File type detection uses both extension and MIME type (`getFileType(filename, mimeType)`).

**F05** [Tier 1, 5] [FIX] **Docker volume for document storage** -- `docker-compose.yml` defines a named volume (e.g., `{app}-documents`) mounted at `/app/data`. Two subdirectories: `/app/data/documents` for persistent document storage and `/app/data/uploads` for temporary upload cache. The Dockerfile creates these directories with proper ownership (`chown appuser:appgroup`) BEFORE the `USER` directive. Environment variables `DOCUMENTS_PATH` and `UPLOAD_CACHE_PATH` are set in docker-compose.yml and `.env.example`. The volume survives container rebuilds -- uploaded documents persist across restarts.

**F06** [Tier 1, 5] [FIX] **Upload environment variables** -- `.env.example` and docker-compose.yml include: `DOCUMENTS_PATH` (default: `/app/data/documents`), `UPLOAD_CACHE_PATH` (default: `/app/data/uploads`), `MAX_FILE_SIZE` (default: `52428800` = 50MB). All file paths in application code read from env vars -- no hardcoded paths.

**F07** [Tier 1] [FIX] **Upload onboarding wizard** -- When the app has a Documents page or any entity that accepts file attachments, include a multi-step upload wizard: (1) Upload zone (drag/drop/browse with file type hints), (2) Processing indicator ("Extracting content..."), (3) Extracted data review (parsed fields, confidence indicators if AI-extracted), (4) Confirm and save. The wizard uses the shared `FileUploadZone` component and calls the upload API endpoint. Errors display user-friendly messages ("This file type isn't supported" not "Failed to parse DOCX").

**F08** [Tier 1, 5] [FIX] **Upload RBAC** -- File upload endpoints use `requirePermission` (e.g., `documents.edit` or the relevant resource). Upload size limits enforced server-side regardless of client claims. File type validation enforced server-side (check magic bytes or extension, not just Content-Type header which can be spoofed). No public/unauthenticated upload endpoints.

**F09** [Tier 1, 5] [BLOCK] **Upload errors never return 500 to the user** -- The upload API route wraps the entire extraction pipeline in a top-level try/catch. Every failure mode returns a specific, user-friendly HTTP status and message -- NEVER an unhandled 500. Required error responses: `400 "No file provided"` (missing file), `400 "Unsupported file type"` (unrecognized format), `413 "File too large"` (exceeds MAX_FILE_SIZE), `422 "Could not extract content from this file"` (extraction failed -- corrupt PDF, password-protected DOCX, etc.), `429` (rate limited, if AI processing). The catch-all returns `500` only as a last resort with a generic safe message ("An error occurred while processing your file. Please try a different file or format.") -- NEVER leaking library names, stack traces, file paths, or internal error details. Build-verify: upload a corrupt/empty file and verify the response is 422 with a friendly message, not 500 with a stack trace.

**F10** [AI] [BLOCK] **AI-powered document analysis pipeline** -- When both file upload AND AI features are enabled, the upload pipeline MUST include an AI analysis step. After text extraction (F04), the extracted content is passed to the AI provider via the document analysis agent (not the chat agent). The pipeline: extract text -> validate size against AI_MAX_DOCUMENT_CHARS (300k, not AI_MAX_PROMPT_CHARS) -> sanitize via sanitizePromptInput() -> wrap in `<document>` tags -> send to AI with document-analysis prompt from managed_prompts -> validate AI output via validateAgentOutput() -> return structured result to user. The upload wizard (F07) adds a step between extraction and confirmation: "AI Analysis" with a streaming progress indicator showing the AI processing the document. If AI analysis fails, the upload still succeeds with extracted text only -- AI failure MUST NOT block document storage. The AI result is stored alongside the document (separate column or JSON field, never overwriting the raw extracted text). Verify: upload a PDF, confirm AI analysis runs, confirm extracted text AND AI analysis are both stored, confirm AI failure still saves the document.

**F11** [AI] [BLOCK] **AI pre-flight health checks on startup** -- When the app has AI features, the startup sequence MUST verify AI readiness before accepting requests. Pre-flight checks run AFTER database migrations and BEFORE the app binds to its HTTP port. Checks (all must pass): (1) AI provider is reachable (HTTP HEAD or lightweight API call to the provider endpoint), (2) Authentication is valid (for bearer-token providers: token is not expired; for API-key providers: key returns 200 not 401), (3) Configured model is available (request with max_tokens=1 to verify model exists), (4) Upload infrastructure is ready (DOCUMENTS_PATH and UPLOAD_CACHE_PATH directories exist and are writable), (5) Extraction libraries loadable (import pdf-parse/pdfplumber, docx parser, xlsx parser without error). On failure: log the specific check that failed with a clear message (e.g., "AI pre-flight failed: provider unreachable at https://..."), exit with non-zero code so Docker restarts the container. Pre-flight is FAST (under 5 seconds total, 2-second timeout per check). Add `AI_PREFLIGHT_ENABLED` env var (default: true) to allow disabling in CI/test environments. Verify: misconfigure the AI provider endpoint, start the app, confirm it logs the failure and exits before binding the port.

**F12** [Tier 1, 5] [BLOCK] **Single-action upload UX** -- From the user's perspective, file import is ONE action: drop file, get result. Validation, parsing, format detection, and error handling happen transparently in the backend pipeline. There is no user-facing "dry run" or "validate then apply" two-step flow. If the backend needs a validation pass before committing, it runs both stages internally within a single user-initiated request (or background task). The user never sees intermediate technical states. The response is either success with a summary, or failure with actionable plain-language errors ("Row 47: vendor name is missing", not "validation failed").

**F13** [Tier 1, 5] [BLOCK] **Bounded API responses** -- Upload, import, and processing endpoints NEVER return unbounded data in the response body. Return counts, summaries, and status -- never the full parsed dataset. A response that scales linearly with input size is a timeout and memory bomb waiting for production data. Specifically: no returning all parsed rows, no returning all validated records, no returning full file contents in JSON. If the frontend needs to display row-level details, use pagination or a separate detail endpoint. Verification: review every response dict/object in upload handlers -- if any value is a list derived from the input data, it's a violation (exception: capped error lists, e.g., `failed_rows[:50]`).

**F14** [Tier 1, 5] [BLOCK] **Resilient file structure detection** -- File parsing MUST auto-detect structure rather than assuming fixed layouts. For CSV/TSV: scan the first N lines (minimum 20) for a header row by matching known column names -- never hardcode a row offset ("skip 3 preamble rows"). For Excel: detect the header row per sheet. For all formats: handle BOM markers (UTF-8-sig), mixed line endings, trailing empty rows, and inconsistent whitespace in column names (strip + case-insensitive matching). If the header row cannot be found, return a specific error ("Could not find expected columns: X, Y, Z in the first 20 rows") not a generic parse failure. Verification: upload a file with 0 preamble rows, 3 preamble rows, and 7 preamble rows -- all three must succeed if they contain the expected columns.

**F15** [Tier 1, 5] [FIX] **Batch processing for large datasets** -- Import operations processing more than a trivial number of records MUST commit in configurable batches (default: 1,000 rows). A single transaction spanning tens of thousands of rows holds database locks too long and risks OOM on large files. Each batch commits independently. Failed rows within a batch are skipped and tracked (row number, identifier, error message) -- a single bad row never aborts the entire import. The batch size is a class-level or config-level constant, not buried in loop logic. After each committed batch, an optional progress callback is invoked for progress reporting.

**F16** [Tier 1, 5] [FIX] **Import progress reporting** -- When an import runs as a background task, progress updates MUST reflect actual committed work, not just "started" and "done". The background task record (or equivalent) is updated after each committed batch with: total items, processed count, successful count, failed count, and progress percentage. The frontend polls this record and displays a progress bar or percentage. Progress never jumps from 0% to 100%.

**F17** [Tier 1, 5] [FIX] **Actionable error reporting** -- Import results distinguish between three outcomes: success, partial success (some rows failed), and total failure. Partial success returns the import summary (how many succeeded, how many failed) plus a capped list of failed rows with row numbers, identifiers, and plain-language error descriptions. The UI displays these as a reviewable list, not a raw JSON dump or stack trace. Total failure (e.g., unrecognizable file format) returns a single clear message. Error messages reference the user's data ("Row 47: VENDOR_NAME is missing"), not internal state ("KeyError: vendor_name in dict").

---

## Data Integration

> Applies when an app ingests data from external systems on a schedule or in
> batch -- Oracle exports, ERP feeds, partner file drops, etc. This is distinct
> from user-initiated file upload (F section): the user didn't drop a file,
> the system picked one up.

**DI01** [Tier 1, 5] [BLOCK] **Integration method decision matrix** -- Before building a data integration, evaluate the source and choose the simplest viable method. The decision matrix:

| Question | If Yes | If No |
|----------|--------|-------|
| Does the source system already export files (CSV, XML, flat file)? | File-based ingestion | Consider API |
| Would middleware (MFT, iPaaS) add transforms, enrichment, or routing? | Middleware may add value | Skip middleware |
| Is the middleware just passing files through without transformation? | File-based ingestion (middleware adds latency and a dependency for no value) | -- |
| Is real-time or near-real-time data required? | API integration | File-based is fine |
| Does the integration require a cross-functional team to change? | Prefer the approach with fewer team dependencies | -- |
| Is the data volume large (>10k records per run)? | File-based with batch processing (F15) | Either approach works |

**Decision rule: if the source already exports files and no transformation is needed, use file-based ingestion. Do not introduce middleware as a pass-through -- it adds latency, dependencies, and points of failure with no value.**

Document the decision in the project's `app-context.json` under `data_integrations[]` with: source system, method chosen (file/api/mft), rationale, and frequency.

**DI02** [Tier 1, 5] [BLOCK] **File-source-agnostic ingestion** -- Import services read from a configurable directory path (environment variable, e.g., `IMPORT_SOURCE_PATH`). The application code never knows or cares whether the file arrived via NFS mount, MFT delivery, S3 sync, or manual upload. The same import service handles both user-uploaded files and system-delivered files -- the only difference is the trigger (user action vs schedule). Verification: grep for hardcoded file paths in import/ingestion code -- any match is a violation.

**DI03** [Tier 1, 5] [FIX] **Job status model** -- A generic background task / job status table exists (or is extended) to track all async operations: imports, scheduled integrations, AI processing, etc. Required fields: id, task_type (string enum), status (pending/running/completed/failed), total_items, processed_items, successful_items, failed_items, progress_percent, error_message, result_data (JSON), created_by, created_at, started_at, completed_at. The model is generic across task types -- not import-specific.

**DI04** [Tier 1] [FIX] **Job status page** -- An admin-accessible UI page displays all background tasks and scheduled jobs. Features: filterable by task_type and status, sortable by date, shows progress bar for running tasks, shows duration for completed tasks, shows error message for failed tasks, and links to result details. This is the single monitoring surface for all async work in the app. RBAC: requires `admin.jobs.read` permission (or equivalent).

**DI05** [Tier 1, 5] [FIX] **Idempotent processing** -- Scheduled import jobs MUST be safe to re-run. Use one of: (a) full replace (delete-and-reload, appropriate when the source is a complete snapshot), (b) upsert on natural key (insert or update based on a business identifier), or (c) watermark/checkpoint (track last-processed timestamp or sequence, only process new records). The strategy is documented in app-context.json per integration. Duplicate detection uses business keys (e.g., invoice_number + vendor_number), not database surrogate keys.

**DI06** [Tier 1, 5] [FIX] **Ingestion inherits upload pipeline** -- All backend pipeline standards from the File Upload section apply to scheduled ingestion: auto-detect file structure (F14), batch commits (F15), progress reporting (F16), actionable error tracking (F17), and bounded responses (F13). Scheduled jobs inherit these patterns -- they are not reimplemented separately.

**DI07** [Tier 1, 5] [WARN] **Scheduled execution** -- When the app requires periodic data ingestion, the scheduling mechanism is determined by the deployment environment. Options: K8s CronJob (preferred for containerized apps), APScheduler / node-cron (in-process, acceptable for simple schedules), or external orchestrator (Airflow, etc. -- only when multi-step DAGs are needed). Schedule configuration is externalized (environment variable or settings table), not hardcoded. The job status model (DI03) records each execution regardless of trigger method.

**DI08** [Tier 1, 5] [WARN] **Job observability** -- Failed jobs create a notification (N01-N08 pattern) to alert administrators. Job execution is logged with: start time, end time, duration, record counts, and outcome. If the app has activity logs (L01-L08), job executions appear as log events. Production environments should expose job metrics (success/failure counts, duration) for monitoring dashboards.

---

## Application Settings

**These checks require PostgreSQL.** If database is excluded (see design-blueprint.md Section 3b), skip all G01-G07 checks.

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

**X07** [Tier 0] [FIX] **Dependency vulnerability audit** -- Run `pip-audit -r backend/requirements.txt` (Python) and/or `npm audit` (Node.js) to detect known CVEs. Auto-fix with retry loop: (1) `pip-audit --fix` / `npm audit fix`, (2) re-audit to verify, (3) manual version pin if auto-fix insufficient, (4) repeat up to 3 cycles. Remaining vulnerabilities after 3 cycles logged to TODO.md with severity, package, and CVE ID. Install `pip-audit` if not available. Runs silently during /resume-it static scan and /try-it smoke test. Rebuild affected Docker services if requirements.txt or package.json changed.

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

**V01** [Tier 0] [FIX] **SSL proxy detection with Dockyard Gateway / ACR cache auto-discovery** -- Check for Zscaler/Netskope/GlobalProtect before Docker builds. If detected: (1) Check if `DOCKER_HUB_PREFIX` is already set in `.env` -- skip if all three prefixes configured. (2) Check Azure CLI availability and login: `az account show`. (3) Discover ACR registries: `az acr list --query "[].{name:name, loginServer:loginServer}" -o json`. Look for registries with names containing "dockyard", "proxy", or "cache" as likely candidates. (4) For each ACR, check for proxy cache rules: `az acr cache list --registry <name> -o json`. Cache rules map upstream registries (docker.io, mcr.microsoft.com, ghcr.io) to local paths through the ACR. (5) If an ACR with cache rules is found (Dockyard Gateway), auto-configure ALL three prefixes in `.env`: `DOCKER_HUB_PREFIX=<loginServer>/docker.io/library/`, `MCR_PREFIX=<loginServer>/mcr.microsoft.com/`, `GHCR_PREFIX=<loginServer>/ghcr.io/`. The prefix format may vary by ACR cache rule configuration -- read the actual `sourceRepository` and `targetRepository` from each cache rule to construct the correct prefix. (6) Run `az acr login --name <acrName>` to authenticate Docker. (7) Tell user: "I detected a corporate SSL proxy and found a Dockyard Gateway (registry cache) at <loginServer>. I've configured your project to pull Docker images through it -- Docker Hub, MCR, and GHCR images all route through your corporate registry. No need to disable your proxy." (8) If no ACR with cache rules is found, fall back to asking user to pause the proxy.

**V02** [Tier 1, 5] [BLOCK] **All containers healthy** -- Poll health endpoints (timeout 120s per service).

**V03** [Tier 1, 5] [BLOCK] **Seed script runs** -- `bash scripts/seed-mock-services.sh` completes without error. **SaaS auth pattern only -- skip if EasyAuth or no mock services.**

**V04** [Tier 1, 5*] [BLOCK] **Auth flow works for EACH role** -- **SaaS auth pattern only -- skip if EasyAuth.** -- Login through mock-oidc, JWT cookie set, /auth/me returns correct roles from DB (primary role + all effective roles), permissions are the union across all effective roles, dashboard loads with content, logout clears cookie. For users with multiple roles, verify that permissions from ALL roles are present in the JWT.

**V05** [Tier 1, 5] [BLOCK] **Every API endpoint responds** -- 2xx, valid JSON, non-empty arrays from list endpoints.

**V06** [Tier 1] [BLOCK] **Every page loads** -- HTTP 200, meaningful content (not empty tables).

**V07** [Tier 1, 5*] [BLOCK] **Permission boundaries** -- Correct access per role. 403 for unauthorized.

**V08** [Tier 1, 5] [FIX] **Activity Logs capturing** -- /api/admin/logs/stats returns data. /api/admin/logs/events has entries after requests.

**V09** [Tier 1, 5] [BLOCK] **Docker build cache** -- After source fixes, rebuild with `--no-cache` to prevent stale output.

**V10** [Tier 1, 5] [FIX] **Notifications working** -- GET /api/notifications/count returns { unreadCount } > 0 (seed data). GET /api/notifications returns notifications scoped to the logged-in user. PATCH /api/notifications marks notification as read. Different users see different unread counts (validates scoping). Bell badge reflects count (Tier 1).

**V12** [Tier 1] [BLOCK] **DataTable features work on every list page** -- For each page that displays tabular data, verify with a browser/curl check:
- Page HTML contains TanStack DataTable markup (look for the pagination row-count text like "Page 1 of", page size selector, and column header buttons)
- Page has data rows (seed data must populate tables -- no "No results" empty states on first load)
- Column headers are clickable (rendered as `<button>` elements, not plain text)
- Filter icon exists in column headers (the Excel-like filter dropdown trigger)
- Toolbar area contains: search input (if searchKey configured), column visibility "Columns" button, and pagination controls
- Pagination shows correct controls: page size dropdown, First/Prev/Next/Last buttons
- If the page source contains `<table` or `<tr>` elements outside the DataTable component, this is a violation -- all tabular data must go through DataTable

**V13** [Tier 1] [BLOCK] **Theme toggle works end-to-end** -- Verify:
- The authenticated layout header contains the ModeToggle component (visible as a button with Sun/Moon/Monitor icon)
- The `<html>` element has a `class` attribute that changes between light/dark (managed by next-themes)
- globals.css contains both `:root` and `.dark` CSS variable blocks
- Pages render correctly in both themes (no elements with hardcoded colors that ignore the theme)
- localStorage key `"theme"` is used by next-themes for persistence

**V11** [Tier 1, 5] [BLOCK] **File upload works end-to-end** -- If the app has a Documents page or file upload feature: upload a valid PDF via the upload API endpoint, verify 200 response with extracted text content (not empty). Upload an image, verify base64 return. Upload oversized file, verify 413 rejection. Verify Docker volume mount exists (`docker exec {container} ls /app/data/documents`). If pdf-parse is in package.json, verify the import uses `pdf-parse/lib/pdf-parse` (NOT default import) by grepping the source.

**V14** [AI] [BLOCK] **SSE streaming and chat work end-to-end** -- If the app has AI features: navigate to the chat page, send a message, verify tokens stream incrementally (not all-at-once after a delay). Verify conversation appears in the sidebar. Reload the page -- verify conversation history is preserved. Open a second browser/incognito session as a different user -- verify they cannot see the first user's conversations. POST to the chat endpoint with `Accept: text/event-stream` and verify `Content-Type: text/event-stream` response with `data:` events. POST with `Accept: application/json` and verify a complete JSON response (non-streaming fallback). Verify heartbeat events arrive during long generations (check for `{"heartbeat": true}` events).

**V15** [Tier 0] [FIX] **Security hardening ran (build-verify Part D)** -- After Part A/B/C pass, the automatic security scan must have executed. Verify: (1) Code pattern scan ran (grep-based checks for hardcoded secrets, SQL injection, XSS, insecure deserialization, missing timeouts). (2) If AI features present, AI safety wiring checks ran (sanitizePromptInput, validateAgentOutput, delimiter tags, rate limiting). (3) Any AUTO-class findings were fixed and verified in a re-scan cycle. (4) Remaining findings (if any) are logged in TODO.md under "Security Improvements". See `build-verify-security.md` for the full specification.

**V16** [AI] [BLOCK] **Agent routing works end-to-end** -- If the app has multiple AI agents: verify each conversational agent responds when its slug is used in a conversation (create conversation with agent_slug, send message, confirm response comes from correct agent context). Verify each batch agent creates a job when triggered via `POST /api/ai/agents/{slug}/run` (confirm job record appears in job status table with correct `task_type`). Verify unknown slug returns 404. If rule-based fallback is configured on any agent: misconfigure the AI provider endpoint, trigger the agent, verify fallback response is returned (conversational: "AI is temporarily unavailable" message; batch: job completes with `"ai_fallback": true` in result_data).

---

## AI Features (when ai_features.needed = true)

These checks apply to ANY project type that uses AI/LLM features.

**AI01** [AI] [BLOCK] **Provider abstraction scaffold** -- Copy `~/.claude/make-it/scaffolds/fastapi-nextjs/backend/app/lib/ai/` into project. Verify: `lib/ai/provider.py` has `AIProvider` ABC with `UsageStats` dataclass. `lib/ai/factory.py` has `get_ai_provider()` factory with failover support. No provider SDK imports (`anthropic`, `openai`) in business logic -- only in `lib/ai/providers/`. Do NOT generate provider layer from scratch -- use the scaffold.

**AI01a** [AI] [FIX] **Self-annealing** -- `lib/ai/self_annealing.py` exists with `validate_model()`, `detect_model_error()`, `extract_corrected_model()`. Both Anthropic providers call `validate_model()` before API calls and retry with `extract_corrected_model()` on model-not-found errors. Verify: setting `AI_MODEL_STANDARD=llama3` logs a correction warning and uses `claude-sonnet-4-20250514` instead.

**AI01b** [AI] [FIX] **Failover provider** -- `lib/ai/providers/failover.py` exists with `FailoverProvider` decorator. Factory wraps primary+secondary when `AI_FAILOVER_PROVIDER` env var is set. Verify: `AI_FAILOVER_PROVIDER=ollama` in .env causes factory to return `FailoverProvider`. On primary exception, subsequent calls route to secondary.

**AI01c** [AI] [FIX] **Cost tracking** -- `AIProvider` base class has `usage: UsageStats` with `total_input_tokens`, `total_output_tokens`, `total_cost_usd`, `request_count`. Each cloud provider overrides `estimate_cost()` with model-specific pricing. Providers call `self.usage.record()` after every API call. Ollama returns cost=0.

**AI02** [AI] [FIX] **Input sanitization** -- sanitize_prompt_input() in lib/ai/sanitize.py, called by BaseAgent before invoke(). User input in `<user_input>` tags.

**AI03** [AI] [FIX] **Output validation** -- validateAgentOutput() called after every AI response. Structured outputs schema-validated. Free-text scanned for XSS.

**AI04** [AI] [FIX] **Rate limiting** -- Dedicated AI rate limits. 429 with Retry-After on excess.

**AI05** [AI] [FIX] **Prompt size validation** -- Rejects inputs exceeding AI_MAX_PROMPT_CHARS (413).

**AI06** [AI] [FIX] **Error sanitization** -- `lib/ai/errors.py` maps provider exceptions to client-safe `AIProviderError` subclasses. No provider/model/key details in responses. Internal details logged via `sanitize_ai_error()`.

**AI07** [AI] [FIX] **No dangerouslySetInnerHTML for AI output** -- Escaped rendering only.

**AI08** [AI] [BLOCK] **Prompt management (Tier 2 minimum)** -- If ai_features.needed = true in app-context.json, the prompt management scaffold module MUST be included. The scaffold provides pre-built: 6 database tables (managed_prompts, prompt_versions, prompt_usages, prompt_tags, prompt_test_cases, prompt_audit_log) in `backend/alembic/versions/003_prompt_management.py`, ~25 API routes in `backend/app/routers/prompts.py`, Pydantic schemas in `backend/app/schemas/prompt.py`, service layer in `backend/app/services/prompt_service.py`, 4 admin UI pages at `frontend/app/(auth)/admin/prompts/`, and 5 reusable components (prompt-card, prompt-editor, safety-indicator, variable-pill, version-timeline). Verify: migration runs, router is wired in main.py, sidebar shows "AI Instructions" nav item, all hardcoded prompts are seeded into managed_prompts table, agents load from DB with code fallback. Do NOT generate prompt management from scratch -- use the scaffold.

**AI08-upgrade** [AI] [FIX] **Prompt management upgrade path** -- When /resume-it detects Tier 2 Outdated prompt management in a FastAPI+Next.js app: rename old tables with `_legacy` suffix, create scaffold tables, migrate data, copy scaffold files (models, schemas, service, router, 5 components, 4 pages), rewire sidebar/breadcrumbs/types/conftest. NEVER drop old tables. NEVER modify existing Alembic migrations. Tier 3 Custom implementations are protected (skip upgrade, note in status). Non-FastAPI+Next.js apps get gap documentation in TODO.md only.

**AI09** [AI] [FIX] **NeMo Guardrails** -- guardrails/ directory, config.yml, Colang rails. Basic suite (18 tests) passes.

**AI10** [AI] [FIX] **Prompt template validation (Tier 2/3)** -- validatePromptTemplate() on save endpoints. Immutable safety preamble. Draft/test/publish workflow. Variable interpolation sanitized. The scaffold prompt-editor component provides guided editing with safety zone indicators (green=safe, yellow=caution) and variable pills for non-technical users.

**AI11** [AI] [BLOCK] **SSE streaming for AI responses** -- ALL AI endpoints that return generated text MUST use Server-Sent Events (SSE) to stream tokens incrementally. Backend: AI chat/agent routes return `StreamingResponse` (FastAPI) or NextResponse with `text/event-stream` content type. Each SSE event is `data: {"token": "...", "done": false}\n\n`. Final event is `data: {"token": "", "done": true, "conversation_id": "..."}\n\n`. Frontend: proxies the SSE stream through a Next.js API route (same-origin, preserves auth cookies). The `useStreamingResponse` hook in `lib/ai/use-streaming.ts` handles EventSource connection, incremental token assembly, error/retry, and abort. Timeout eliminated: SSE keeps the connection alive with heartbeat events (`data: {"heartbeat": true}\n\n` every 15s). Verify: POST to an AI chat endpoint; confirm response is HTTP 200 with `Content-Type: text/event-stream`; confirm tokens arrive incrementally (not buffered); confirm frontend renders tokens as they arrive (typewriter effect). This is the default for all AI apps -- non-streaming AI endpoints are only acceptable for sub-second structured extraction (JSON schema responses under 500 tokens).

**AI12** [AI] [BLOCK] **Conversation persistence** -- AI chat conversations MUST be stored server-side in the database. The scaffold provides pre-built: 2 database tables (`conversations` with id/user_id/title/agent_slug/created_at/updated_at/archived_at, and `conversation_messages` with id/conversation_id/role/content/token_count/model/created_at) in a dedicated Alembic migration. REST API: `POST /api/ai/conversations` (create), `GET /api/ai/conversations` (list user's conversations, paginated), `GET /api/ai/conversations/{id}` (get with messages), `DELETE /api/ai/conversations/{id}` (soft-delete via archived_at), `POST /api/ai/conversations/{id}/messages` (send message, returns SSE stream). Session isolation: users can ONLY access their own conversations (WHERE user_id = current_user.id on all queries). Title auto-generated from first user message (truncated to 80 chars), editable via PATCH. Verify: create conversation, send messages, reload page -- conversation and full history are preserved. Verify: user A cannot access user B's conversations (returns 404).

**AI13** [AI] [BLOCK] **Chat panel scaffold component** -- The scaffold provides a pre-built `ChatPanel` component and supporting components. 4 components total: `chat-panel.tsx` (full chat interface: message list + input + streaming bubble), `chat-message.tsx` (individual message with role icon, markdown rendering via react-markdown, copy button, timestamp), `chat-input.tsx` (auto-resizing textarea, send button, Shift+Enter for newlines, disabled during streaming), `conversation-sidebar.tsx` (conversation list with search, "New Chat" button, active conversation highlight, relative timestamps, archive/delete). Layout: conversation sidebar (w-72, collapsible) + chat panel (flex-1). The ChatPanel accepts an `agentSlug` prop to route messages to different AI agents. Streaming display: assistant messages render incrementally with a blinking cursor during streaming. Empty state: centered prompt with suggested starter questions (configurable per agent). Verify: ChatPanel renders, messages stream with typewriter effect, conversation sidebar lists previous conversations, new conversations appear immediately in sidebar.

**AI14** [AI] [FIX] **SSE error handling and fallback** -- SSE connections MUST handle failures gracefully with automatic retry before falling back to polling. Retry strategy: on SSE connection error or stream interruption, automatically retry up to 3 times with 1s/2s/4s exponential backoff. If all retries fail, fall back to polling mode: POST the message normally (non-streaming), poll `GET /api/ai/conversations/{id}/messages?after={last_message_id}` every 2s until the assistant response appears (complete message, not streamed). If polling also fails after 30s, show a user-friendly error: "AI is temporarily unavailable. Please try again." with a retry button. The `useStreamingResponse` hook manages the full lifecycle: SSE attempt -> retry -> poll fallback -> error state. Backend: AI chat endpoints MUST support both streaming (`Accept: text/event-stream`) and non-streaming (`Accept: application/json`) via the Accept header. Verify: kill the SSE connection mid-stream; confirm retry occurs; if retry fails, confirm polling fallback delivers the complete response. Verify: request with `Accept: application/json` returns the full response as a single JSON object.

**AI15** [AI] [FIX] **SSE environment variables** -- `.env.example` and docker-compose.yml include: `AI_SSE_HEARTBEAT_INTERVAL_SECONDS` (default: 15), `AI_SSE_RETRY_MAX_ATTEMPTS` (default: 3), `AI_SSE_POLL_INTERVAL_SECONDS` (default: 2), `AI_SSE_POLL_TIMEOUT_SECONDS` (default: 30). All timing values in SSE/polling logic read from env vars -- no hardcoded intervals. Settings service (G02) includes these as configurable AI settings.

**AI16** [AI] [FIX] **AI interaction level classified** -- `app-context.json` must include `ai_features.interaction_level` set to one of: `"batch-only"` (single-purpose agents, no chat UI), `"conversational"` (multi-turn chat with conversation persistence), or `"hybrid"` (both chat and batch agents). The interaction level determines which AI infrastructure is generated: `batch-only` skips conversation tables (AI12), chat panel (AI13), and SSE streaming (AI11); `conversational` generates conversation tables + chat UI + SSE + at least one conversational agent; `hybrid` generates everything from both levels. Verify: `ai_features.interaction_level` is set and consistent with generated code -- if `"batch-only"`, no `conversation_messages` table exists; if `"conversational"` or `"hybrid"`, conversation tables and chat panel exist.

**AI17** [AI] [BLOCK] **Agent registry** -- Every AI app declares its agents in `app-context.json` under `ai_features.agents[]` AND in a backend registry module (`lib/ai/agents/registry.py` or `lib/ai/agents/__init__.py`). Each agent entry has: `slug` (unique identifier, used in `conversations.agent_slug` and batch routing), `name` (display name), `type` (`"conversational"` or `"batch"`), `prompt_key` (matches a row slug in `managed_prompts`), `model_tier` (`"heavy"`, `"standard"`, or `"light"`), `description`, `context_sources` (list of domain data the agent queries), and `rule_based_fallback` (boolean). The registry module maps slugs to agent classes. Verify: every agent in `app-context.json` has a corresponding class in the agents directory. Every `prompt_key` has a matching seeded row in `managed_prompts`. Every conversational agent's slug appears in at least one conversation's `agent_slug` column in seed data.

**AI18** [AI] [BLOCK] **BaseAgent scaffold with lifecycle methods** -- `lib/ai/agents/base_agent.py` exists with an abstract `BaseAgent` class. Required methods: `invoke(input) -> str` (single-purpose call with full safety pipeline: sanitize, validate_size, mask_pii, get_system_prompt, build_context, call provider, unmask, validate_output), `stream(input) -> AsyncIterator[str]` (streaming variant for conversational agents), `get_system_prompt() -> str` (loads from `managed_prompts` DB with code fallback), `build_context(**kwargs) -> str` (abstract -- subclasses override with domain-specific data queries). For batch agents, additional lifecycle methods: `create_job(user_id) -> Job`, `complete_job(job_id, result)`, `fail_job(job_id, error)` that write to the job status table (DI03). Verify: `BaseAgent` exists, all concrete agents extend it, `invoke()` calls `sanitize_prompt_input()` and `validate_output()` (safety pipeline from AI02/AI03 is NOT bypassed).

**AI19** [AI] [FIX] **Context builder per agent** -- Every agent subclass implements `build_context()` to gather domain-specific data for the AI prompt. Context assembly order: (1) safety preamble (immutable), (2) system prompt from `managed_prompts`, (3) brain memory context if brain_features.enabled (user memories + org memories, see BN03), (4) domain context from `build_context()` (DB queries, document content, external data), (5) conversation history for conversational agents (last N turns from `conversation_messages`, capped at `AI_MAX_HISTORY_TURNS`), (6) sanitized user input in `<user_input>` tags. Context builders must truncate gracefully when total context exceeds `AI_MAX_PROMPT_CHARS` -- when brain features enabled: memory context gets 15%, domain context gets 55%, conversation history gets 30%. When brain features disabled: original budget applies (domain 70%, history 30%). Never truncate safety preamble or user input. Verify: each agent's `build_context()` returns domain-relevant data (not empty strings). Total assembled prompt length is validated before provider call.

**AI20** [AI] [FIX] **Agent routing** -- Conversational agents are routed via the `agent_slug` field on the `conversations` table (AI12). `POST /api/ai/conversations/{id}/messages` looks up the conversation's `agent_slug`, resolves the agent class from the registry, calls `agent.build_context()` + `agent.stream()`, and stores the response. Batch agents are triggered via `POST /api/ai/agents/{slug}/run` which accepts job parameters, creates a job record (DI03), runs the agent asynchronously, and returns the job ID. The batch endpoint validates the slug against the registry and returns 404 for unknown agents. Verify: send a chat message -- it reaches the correct agent based on `conversation.agent_slug`. Trigger a batch agent -- it creates a job record and the agent executes. Unknown slug returns 404.

**AI21** [AI] [FIX] **Rule-based fallback when AI unavailable** -- Agents with `rule_based_fallback: true` in the registry MUST have a `fallback()` method that returns a useful response without calling the AI provider. BaseAgent's `invoke()` wraps the provider call in a try/except: on provider failure, check `self.rule_based_fallback`; if true, call `self.fallback(input)` and return the result with a flag indicating AI was not used; if false, raise the error. Conversational agents in fallback mode return "AI is temporarily unavailable. Please try again shortly." and do NOT store a `conversation_message`. Batch agents in fallback mode can return deterministic analysis (threshold-based scoring, keyword matching) or mark the job as `status: "completed_without_ai"`. Verify: misconfigure the AI provider endpoint. Trigger an agent with `fallback=true` -- it returns a meaningful response without error. Trigger an agent with `fallback=false` -- it returns a proper error.

**AI22** [AI] [FIX] **Batch agent job tracking** -- Batch agents (`type="batch"` in registry) MUST use the job status table from DI03 for lifecycle tracking. The `task_type` column is set to `"ai_agent:{slug}"` (e.g., `"ai_agent:vendor_enrichment"`). AI-specific fields stored in `result_data` JSON: `agent_slug`, `model_used`, `total_input_tokens`, `total_output_tokens`, `cost_usd`. The job status page (DI04) displays AI agent jobs alongside other background tasks with the agent name as a filterable column. Batch agents processing multiple items use the DI03 batch pattern: per-item progress updates, failed items tracked individually, partial completion supported. Verify: trigger a batch agent; confirm a job record is created with `task_type` starting with `"ai_agent:"`; confirm progress updates during execution; confirm final status includes token/cost data in `result_data`.

**AI23** [AI] [BLOCK] **invoke_agent() primitive with safety guards** -- `BaseAgent.invoke_agent(slug, input)` method exists. It resolves the target agent from the registry, increments a composition depth counter, checks against `AI_MAX_COMPOSITION_DEPTH` (default: 5), maintains a visited-slug set for cycle detection, and rolls up token/cost usage from the child agent to the parent. Raises `CompositionDepthExceeded` when depth limit hit. Raises `CompositionCycleDetected` when a slug appears twice in the same call chain. Verify: write a test that calls invoke_agent() at depth 5 -- confirm it raises. Write a test where Agent A calls Agent B which calls Agent A -- confirm cycle detection fires. Verify cost rollup: parent agent's `get_total_composition_cost()` includes child agent tokens.

**AI24** [AI] [FIX] **depends_on declared for composed agents** -- Every agent that calls `invoke_agent()` in its code MUST have a `depends_on` array in its app-context.json agent entry listing all agent slugs it calls. Every slug in `depends_on` MUST exist in the agent registry. No cycles allowed in the `depends_on` graph (validated at startup). Verify: grep agent code for `invoke_agent(` calls, confirm each called slug appears in the agent's `depends_on`. Build a dependency graph from all agents' `depends_on` -- confirm no cycles.

**AI25** [AI] [FIX] **Pipeline pattern (sequential orchestration)** -- When an agent's composition type is pipeline: `PipelineAgent` base class exists with `pipeline_slugs` list. Pipeline executes agents sequentially, each step's output becomes the next step's input. Per-step results tracked. On step failure: if `rule_based_fallback=true`, calls fallback with partial results; otherwise raises `PipelineStepFailed` with the failing step index and slug. Job `result_data` includes `step_results` array. Verify: trigger a pipeline agent, confirm all steps execute in order. Kill one step's provider mid-pipeline -- confirm error handling matches fallback config.

**AI26** [AI] [FIX] **Delegation pattern (conversational handoff)** -- When an agent uses delegation: `conversations` table has `delegated_from` (VARCHAR nullable) and `delegation_chain` (JSONB, default '[]') columns. `DelegatingAgent` base class exists with `delegation_map` and `_should_delegate()` method. On delegation: conversation's `agent_slug` updated to delegate, `delegation_chain` appended with from/to/reason/timestamp, system message stored in conversation. Delegate receives handoff context (last 5 messages summary). Return delegation supported (delegate hands back to original agent). Verify: start conversation with generalist, trigger delegation keyword -- confirm next message routes to specialist. Confirm delegation_chain has the handoff entry. Confirm specialist has conversation context.

**AI27** [AI] [FIX] **Fan-out pattern (parallel execution)** -- When an agent uses fan-out: `FanOutAgent` base class exists with `fan_out_slugs` list, `fan_out_timeout` (default: `AI_FAN_OUT_TIMEOUT_SECONDS`), and abstract `merge_results()`. Sub-agents execute via `asyncio.gather` with per-agent timeout. Partial results supported: if some sub-agents fail/timeout, merge_results() receives their status and can still produce output from successful agents. Job `result_data` includes per-agent breakdown with status/tokens/cost. Verify: trigger fan-out agent, confirm all sub-agents run. Kill one sub-agent's provider -- confirm partial results returned. Verify timeout: set fan_out_timeout=1, confirm timeout handling.

**AI28** [AI] [FIX] **Composition environment variables** -- `.env.example` and docker-compose.yml include: `AI_MAX_COMPOSITION_DEPTH` (default: 5), `AI_FAN_OUT_TIMEOUT_SECONDS` (default: 300). Settings service (G02) includes these as configurable AI settings. Verify: all env vars present in .env.example with documented defaults.

---

## AI Memory / Brain Layer (when brain_features.enabled = true)

These checks activate when `brain_features.enabled = true` in app-context.json. They require AI features to be active (`ai_features.needed = true`). See design-blueprint.md Section 14 for full specification.

**BN01** [AI+Brain] [BLOCK] **Brain memory tables exist** -- Migration creates all 4 tables: `brain_memories` (id, memory_type enum, owner_id FK nullable, scope string default 'all', agent_slug, title, content, source_conversation_id FK nullable, source_message_ids UUID[], confidence float, is_active boolean, expires_at nullable, timestamps), `brain_memory_tags` (memory_id FK, tag string), `brain_memory_feedback` (id, memory_id FK, user_id FK, feedback_type enum, correction_text nullable, created_at), `brain_memory_audit_log` (id, memory_id FK, action enum, actor_type enum, actor_id, old_content nullable, new_content nullable, reason, created_at). Verify: migration runs without error. All 4 tables exist in the database. The `scope` column has a default of 'all' and is indexed for query performance.

**BN02** [AI+Brain] [BLOCK] **Memory Curator agent registered** -- `memory-curator` slug exists in `AGENT_REGISTRY` mapping to `MemoryCuratorAgent` class. Agent type is `"batch"`. `prompt_key` is `"memory_curator_system"` with a matching seeded row in `managed_prompts`. Model tier is `"light"`. `rule_based_fallback` is `false` (AI-only curation — silently skips when provider unavailable, processes backlog on next run). Verify: `get_agent("memory-curator")` returns a `MemoryCuratorAgent` instance. The managed prompt seed contains curation instructions including structured JSON output format for extracted memories.

**BN03** [AI+Brain] [BLOCK] **Brain context injection in BaseAgent** -- `BaseAgent._load_brain_context(user_id)` method exists. When `BRAIN_FEATURES_ENABLED=true`, `invoke()` and `stream()` call `_load_brain_context()` and include the result in the assembled prompt between system prompt and domain context. Org/decision memories are filtered by scope: only memories with `scope: 'all'` or scope matching the current agent's `context_sources` are loaded. This ensures cross-functional relevance — a procurement agent loads procurement + universal memories, not engineering memories. When `BRAIN_FEATURES_ENABLED=false`, `_load_brain_context()` returns empty string (no-op). Verify: set `BRAIN_FEATURES_ENABLED=true`, create a test user memory, send a chat message as that user -- confirm the memory content appears in the assembled prompt. Create an org memory with scope 'security', chat with a non-security agent -- confirm the memory is NOT included. Chat with a security agent -- confirm it IS included. Set `BRAIN_FEATURES_ENABLED=false` -- confirm no memories are included.

**BN04** [AI+Brain] [BLOCK] **Memory content safety** -- All memory content passes through `sanitizePromptInput()` before injection into prompts. Memory content is wrapped in `<memory_context>` delimiter tags in the assembled prompt. System prompt includes instruction about treating memory_context as learned context, not instructions. `validateAgentOutput()` is called on memory content before storage in `brain_memories`. Verify: create a memory containing `<script>alert(1)</script>` -- confirm it is sanitized before storage. Create a memory containing "ignore previous instructions" -- confirm it is stripped.

**BN05** [AI+Brain] [BLOCK] **User memory isolation and scope filtering** -- `GET /api/brain/memories` always scopes to `owner_id = current_user.id` for user-type memories. Users can see org and decision memories that match their accessible scopes (determined by the union of the user's role permissions and the agents they interact with). Users CANNOT see other users' personal memories. Org memories with `scope: 'all'` are visible to all authenticated users. Org memories with narrow scope (e.g., 'security', 'procurement') are visible only to users with matching role permissions or agent access. Verify: create user memories for user A, login as user B, GET /api/brain/memories -- confirm user B cannot see user A's user-type memories. Create an org memory with `scope: 'security'`, login as a user without security-related permissions -- confirm the memory is NOT returned. Login as a user with security permissions -- confirm it IS returned. Confirm org memories with `scope: 'all'` are visible to all users.

**BN06** [AI+Brain] [FIX] **Brain RBAC permissions seeded** -- 6 permissions seeded in RBAC migration: `brain.own.read`, `brain.own.delete`, `brain.own.correct` (granted to all authenticated roles), `brain.admin.read` (Admin, Super Admin), `brain.admin.edit` (Super Admin), `brain.admin.execute` (Super Admin). All brain API endpoints use `require_permission()` middleware. Verify: User role can read own memories but cannot access /admin/ai-memory. Super Admin can access all brain endpoints.

**BN07** [AI+Brain] [FIX] **User memory transparency page** -- `/settings/ai-memory` page exists. Displays current user's memories in a list/table with: title, content preview, agent source, confidence indicator, created date. "Forget this" button sets `is_active=false` and creates `brain_memory_audit_log` entry (action: deactivated, actor_type: user). "This is wrong" button opens correction dialog that creates `brain_memory_feedback` record (feedback_type: corrected). Empty state message when no memories exist. Page uses DataTable component (U06 compliance).

**BN08** [AI+Brain] [FIX] **Admin memory management page** -- `/admin/ai-memory` page exists (brain.admin.read permission). Shows all memories across all users with filters: memory_type, owner, agent_slug, tag, confidence range, date range. Org memories section with promote/demote actions. Curation status section: last run time, job history from DI03 table. "Run curation now" button triggers MemoryCuratorAgent batch job (brain.admin.execute permission). Memory health metrics: total active count, average confidence, stale count (unreferenced >60 days), user correction rate.

**BN09** [AI+Brain] [FIX] **Brain REST API** -- All endpoints authenticated. User endpoints: `GET /api/brain/memories` (list own, paginated, filterable), `GET /api/brain/memories/{id}` (get own memory detail), `DELETE /api/brain/memories/{id}` (soft-delete own memory), `POST /api/brain/memories/{id}/feedback` (submit correction), `GET /api/brain/memories/export` (export own as JSON). Admin endpoints: `GET /api/admin/brain/memories` (list all, paginated), `PUT /api/admin/brain/memories/{id}` (edit any memory), `POST /api/admin/brain/memories/{id}/promote` (promote user→org), `POST /api/admin/brain/curation/run` (trigger curation job), `GET /api/admin/brain/stats` (memory health metrics). Verify: all endpoints respond with correct status codes and RBAC enforcement.

**BN10** [AI+Brain] [FIX] **Curation job tracking** -- MemoryCuratorAgent uses DI03 job status table with `task_type = "ai_agent:memory-curator"`. Job `result_data` includes: `memories_created`, `memories_updated`, `memories_expired`, `memories_promoted`, `conversations_processed`, `model_used`, `total_input_tokens`, `total_output_tokens`, `cost_usd`. Job appears in job status page (DI04) alongside other AI agent jobs. Verify: trigger curation, confirm job record created with correct task_type and result_data fields.

**BN11** [AI+Brain] [FIX] **Memory audit trail** -- Every memory mutation creates a `brain_memory_audit_log` entry: creates (action: created, actor_type: agent), user corrections (action: updated, actor_type: user, old_content + new_content), user deletions (action: deactivated, actor_type: user), promotions (action: promoted, actor_type: agent or user), expirations (action: deactivated, actor_type: system, reason: "TTL expired"). Admin audit page shows full audit trail per memory. Verify: create, correct, and delete a memory -- confirm 3 audit log entries exist with correct fields.

**BN12** [AI+Brain] [FIX] **Brain environment variables** -- `.env.example` and docker-compose.yml include all brain env vars: `BRAIN_FEATURES_ENABLED` (default: false), `BRAIN_CURATION_TRIGGER` (default: scheduled), `BRAIN_CURATION_SCHEDULE` (default: 0 2 * * *), `BRAIN_MEMORY_TTL_DAYS` (default: 90), `BRAIN_DELETE_RETENTION_DAYS` (default: 30), `BRAIN_MAX_USER_MEMORIES` (default: 20), `BRAIN_MAX_ORG_MEMORIES` (default: 10), `BRAIN_CONFIDENCE_THRESHOLD` (default: 0.5). Settings service (G02) includes these as configurable Brain settings. Verify: all env vars present in .env.example with documented defaults.

**BN13** [AI+Brain] [FIX] **Seed brain memories** -- At least 5 sample brain_memories in seed data when brain features enabled. Requirements: mix of memory_type (user, org, decision), tied to real seeded user IDs, at least one with confidence >= 0.8 (high), at least one with confidence 0.5 (medium), at least one with tags, at least one decision-type with source_conversation_id linking to a seeded conversation. Different users should have different memory counts. Verify: login as seeded user, /settings/ai-memory shows memories. Admin /admin/ai-memory shows memories across users.

---

## AI Memory / Brain Layer -- Live Verification

**BNV01** [AI+Brain] [BLOCK] **Brain context affects AI responses** -- With BRAIN_FEATURES_ENABLED=true: create a user memory "User prefers responses as bullet points, not paragraphs". Send a chat message asking for analysis. Verify the response uses bullet-point format. Delete the memory. Send the same message. Verify the response format is different (default, likely paragraph). This confirms the brain layer is actively influencing agent behavior.

**BNV02** [AI+Brain] [BLOCK] **Curation produces memories** -- Trigger MemoryCuratorAgent (via admin UI or API). Verify: job record created in DI03 table. Job completes (status: completed). At least one new memory created in brain_memories table (if unprocessed conversations exist with memory signals). Job result_data has non-zero conversations_processed count.

**BNV03** [AI+Brain] [BLOCK] **Memory isolation end-to-end** -- Login as user A, verify /settings/ai-memory shows user A's memories. Login as user B, verify /settings/ai-memory does NOT show user A's user-type memories. Verify both users CAN see org-type memories. Call `/api/brain/memories/{user_a_memory_id}` as user B -- verify 404 (not 403, to prevent enumeration).

---

## PWA / Mobile (variant: mobile)

These checks only activate when `variant == "mobile"` in app-context.json. They are additive to the base Tier 1 web-app checks.

**P01** [Tier 1+mobile] [FIX] **Viewport meta** -- Root layout (`app/layout.tsx`) has `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`. The `viewport-fit=cover` enables `env(safe-area-inset-*)` for notched devices (iPhone, etc.).

**P02** [Tier 1+mobile] [BLOCK] **Manifest valid** -- `public/manifest.json` exists and contains: `name`, `short_name`, `start_url: "/"`, `display: "standalone"`, `background_color`, `theme_color`, and `icons` array with at least 192x192 and 512x512 entries. All referenced icon files in `public/icons/` must exist on disk.

**P03** [Tier 1+mobile] [BLOCK] **Service worker compiles** -- `app/sw.ts` exists. `@serwist/next` and `serwist` are in `package.json` dependencies. `next.config.ts` imports and uses `withSerwist()`. At runtime, `/sw.js` is served with a JavaScript content type.

**P04** [Tier 1+mobile] [FIX] **Touch targets 44px+** -- All interactive elements (buttons, links, form controls) meet minimum 44x44px touch target size per WCAG 2.5.8. Use Tailwind `min-h-11 min-w-11` or the `.touch-target` utility class. Grep page files for interactive elements using `h-6`, `h-7`, `h-8`, `w-6`, `w-7`, `w-8` as potential violations.

**P05** [Tier 1+mobile] [FIX] **No horizontal overflow** -- No page causes horizontal scroll on a 375px viewport (iPhone SE width). Check for fixed-width elements wider than the viewport (`w-[400px]`, `min-w-[400px]`, etc.). `overflow-x: hidden` on body is a safeguard, not a fix — the root cause must be proper responsive layout.

**P06** [Tier 1+mobile] [FIX] **Offline fallback** -- `app/offline/page.tsx` exists. Service worker config (`sw.ts`) includes a navigation fallback entry pointing to `/offline`. When the app is offline, navigating to any page shows the fallback instead of the browser's default error.

**P07** [Tier 1+mobile] [WARN] **Lighthouse PWA** -- The app meets Lighthouse PWA installability criteria (valid manifest, registered service worker, served over HTTPS or localhost). This is informational — document in TODO.md if not passing. Full Lighthouse audit requires a browser and is not automated during build-verify.

**P08** [Tier 1+mobile] [FIX] **Apple PWA meta** -- Root layout has: `<meta name="apple-mobile-web-app-capable" content="yes">`, `<meta name="apple-mobile-web-app-status-bar-style" content="default">`, and `<link rel="apple-touch-icon" href="/icons/icon-192x192.png">`. Required for iOS home screen app experience.

---

## Common Fix Cycle Issues

When live verification fails, these are the most common root causes and fixes:

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Auth callback returns wrong role | Callback uses OIDC claims, not DB | Query users table by oidc_subject |
| 403 on login for multi-group users | Single role_id can't represent multiple OIDC groups | Use user_roles junction table; resolve ALL matching roles; union permissions |
| User missing entitlements from second role | Only primary role permissions in JWT | Auth callback must query user_roles, union permissions from ALL effective roles |
| OIDC group GUID used as role name | Unmapped group falls through to raw GUID | Only add roles that have a valid mapping match; skip unmapped groups |
| Logout returns 404 | Route is GET not POST | Change to POST endpoint + frontend button |
| Service client 404 from mock | Endpoint URL mismatch | Cross-reference client with mock routes |
| Empty pages | Seed migration didn't run | Verify entrypoint.sh runs migrations |
| Docker build TLS error | SSL-inspecting proxy | Auto-discover Dockyard Gateway (ACR proxy cache) via `az acr cache list` and set all three prefixes (DOCKER_HUB_PREFIX, MCR_PREFIX, GHCR_PREFIX) in .env (I08, V01). Fallback: ask user to pause Zscaler/Netskope |
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
| PDF upload ENOENT 05-versions-space.pdf | pdf-parse index.js debug wrapper | Import `pdf-parse/lib/pdf-parse` directly (F03) |
| Upload works locally but 500 in Docker | Temp file path doesn't exist in container | Process files in-memory buffers, not temp files (F02) |
| Uploaded documents lost on rebuild | No persistent volume | Add named Docker volume for /app/data (F05) |
| Page uses plain `<table>` HTML | DataTable component not used | Replace with `<DataTable>` import from `@/components/data-table` (U06) |
| Table has no filtering/sorting | Column defs use plain text headers | Change all column `header` properties to use `DataTableColumnHeader` component (U08) |
| Table has no pagination | data-table-pagination.tsx missing or not imported | Verify all 4 DataTable files exist and data-table.tsx imports DataTablePagination (U08) |
| Table state resets on page navigation | `storageKey` prop not set | Add `storageKey="page-name-table"` prop to each DataTable instance (U08) |
| Theme toggle missing from app | ModeToggle not in authenticated layout header | Add `<ModeToggle />` as rightmost element in header bar after QuickSearch (U09) |
| Pages don't respond to dark mode | Hardcoded colors in page .tsx files | Replace hex/rgb/hsl literals with CSS variables (`var(--*)`) or Tailwind classes (U09) |
| Hydration mismatch on theme | Missing suppressHydrationWarning | Add `suppressHydrationWarning` to `<html>` and `<body>` tags in root layout (U09) |
| Theme flashes on load | ThemeProvider not configured correctly | Verify `attribute="class"`, `enableSystem`, `disableTransitionOnChange` props (U09) |
| Prod app uses dev endpoint/credentials | `load_dotenv(override=True)` + `.env.azure` baked into image | Change to `override=False` + add `.dockerignore` excluding `.env*` (I09, I10) |
| K8s secrets ignored by app | Local `.env` file overrides real env vars | Ensure all `load_dotenv` calls use `override=False`; add `.dockerignore` (I10) |
| Secrets baked into Docker image | No `.dockerignore`, `COPY . .` copies `.env*` files | Create `.dockerignore` excluding `.env*`, `.git/`, test dirs, IDE config (I09) |
| Import returns "invalid JSON" or browser shows HTML error | Response includes full parsed dataset, causing timeout or truncation | Strip unbounded data from response; return counts and summaries only (F13) |
| Import fails with "COLUMN_NAME is required" on valid files | Parser assumes fixed preamble row count | Auto-detect header row by scanning for known column names (F14) |
| Large import holds DB locks for minutes or OOMs | Single transaction for entire file | Batch commits every 1,000 rows (F15) |
| Progress bar jumps from 0% to 100% | Background task only updates at completion | Update task record after each committed batch (F16) |
| One bad row kills entire import of 27k records | Exception in import loop raises and rolls back | Catch per-row errors, track failures, continue to next row (F15, F17) |
| User confused by "dry run" / "validate" step | Technical validation exposed as UX step | Merge validation into single-action pipeline (F12) |
| Agent returns wrong response for domain | agent_slug mismatch in registry or wrong agent class mapped | Verify registry maps slugs to correct agent classes (AI17) |
| AI response has no domain context | build_context() returns empty string | Implement domain-specific DB queries in agent's build_context() method (AI19) |
| Batch agent job stuck in "running" forever | Agent exception not caught by job lifecycle | BaseAgent must catch all exceptions and call fail_job() in finally block (AI18, AI22) |
| Chat works but batch agent returns 404 | Missing /api/ai/agents/{slug}/run route | Wire batch agent router with registry lookup (AI20) |
| AI provider down crashes entire app | No rule-based fallback configured | Implement fallback() method on agents with rule_based_fallback=true (AI21) |
| AI response ignores user preferences | BRAIN_FEATURES_ENABLED=false or _load_brain_context() not called | Enable brain features, verify BaseAgent calls _load_brain_context() in invoke/stream (BN03) |
| User sees other user's memories | Missing owner_id scope in query | All user-facing brain queries MUST filter by owner_id = current_user.id (BN05) |
| Memory contains injection payload | validateAgentOutput() not called before storage | Memory content must pass through validation + sanitization pipeline before write (BN04) |
| Curation job stuck or never runs | Trigger misconfigured or schedule not wired | Verify BRAIN_CURATION_TRIGGER matches setup; for scheduled, verify cron is registered (BN10) |
| Memory page empty despite conversations | Curation never ran or no memory signals detected | Check job history in DI03; verify conversations contain signal phrases; run curation manually (BN02) |
| Brain context exceeds token limit | Too many memories loaded or confidence threshold too low | Increase BRAIN_CONFIDENCE_THRESHOLD or decrease BRAIN_MAX_USER_MEMORIES/BRAIN_MAX_ORG_MEMORIES (BN12) |
| Org memory irrelevant to user's domain | Memory scope too broad or scope filtering missing | Verify _load_brain_context() filters org memories by agent's context_sources. Set narrow scope on domain-specific memories (BN03, BN05) |
| Agent composition crashes with recursion | No depth limit or cycle detection | Verify invoke_agent() checks _composition_depth against AI_MAX_COMPOSITION_DEPTH and _composition_visited for cycles (AI23) |
| Pipeline stops mid-chain silently | Step failure swallowed without reporting | PipelineAgent must track step_results and raise PipelineStepFailed with step index (AI25) |
| Delegation loses conversation context | Delegate agent starts with empty history | DelegatingAgent must build handoff context from last 5 messages and pass to delegate (AI26) |
| Fan-out returns empty when one sub-agent fails | merge_results() requires all results | FanOutAgent must handle partial results -- succeeded agents' data still usable (AI27) |
| Composed agent cost shows only parent tokens | Child agent costs not rolled up | invoke_agent() must aggregate _composition_usage from all children; job result_data must call get_total_composition_cost() (AI23) |
| Cross-functional user missing memories from second team | Scope filtering too restrictive | Verify scope union: user sees memories from ALL scopes matching their roles/agent access, not just primary (BN05) |
