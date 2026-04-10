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

**I08** [Tier 0] [FIX] **Registry proxy support** -- All Dockerfiles use `ARG DOCKER_HUB_PREFIX=` before each `FROM` instruction, with `FROM ${DOCKER_HUB_PREFIX}image:tag`. In multi-stage builds, repeat `ARG DOCKER_HUB_PREFIX=` before EACH `FROM` (Docker ARGs do not persist across stages). All docker-compose.yml services with `build:` include `args: [DOCKER_HUB_PREFIX=${DOCKER_HUB_PREFIX:-}]`. Services with `image:` use `${DOCKER_HUB_PREFIX:-}image:tag`. `.env.example` documents `DOCKER_HUB_PREFIX`, `MCR_PREFIX`, `GHCR_PREFIX` with auto-discovery instructions. This enables developers behind corporate SSL-inspecting proxies (Zscaler, Netskope, GlobalProtect) to pull Docker images through an ACR proxy cache without disabling the proxy.

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

**V01** [Tier 0] [FIX] **SSL proxy detection with registry auto-discovery** -- Check for Zscaler/Netskope/GlobalProtect before Docker builds. If detected: (1) Check if `DOCKER_HUB_PREFIX` is already set in `.env` -- skip if configured. (2) Check Azure CLI availability and login: `az account show`. (3) Discover ACR registries: `az acr list --query "[].{name:name, loginServer:loginServer}" -o json`. (4) For each ACR, check for proxy cache rules: `az acr cache list --registry <name> -o json`. (5) If an ACR with cache rules is found, auto-configure `.env`: `DOCKER_HUB_PREFIX=<loginServer>/docker.io/library/`, `MCR_PREFIX=<loginServer>/mcr.microsoft.com/`, `GHCR_PREFIX=<loginServer>/ghcr.io/`. (6) Run `az acr login --name <acrName>` to authenticate Docker. (7) Tell user: "I detected a corporate SSL proxy and found a container registry cache at <loginServer>. I've configured your project to pull Docker images through it -- no need to disable your proxy." (8) If no ACR with cache rules is found, fall back to asking user to pause the proxy.

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

**AI08** [AI] [BLOCK] **Prompt management (Tier 2 minimum)** -- If ai_features.needed = true in app-context.json, the prompt management scaffold module MUST be included. The scaffold provides pre-built: 6 database tables (managed_prompts, prompt_versions, prompt_usages, prompt_tags, prompt_test_cases, prompt_audit_log) in `backend/alembic/versions/003_prompt_management.py`, ~25 API routes in `backend/app/routers/prompts.py`, Pydantic schemas in `backend/app/schemas/prompt.py`, service layer in `backend/app/services/prompt_service.py`, 4 admin UI pages at `frontend/app/(auth)/admin/prompts/`, and 5 reusable components (prompt-card, prompt-editor, safety-indicator, variable-pill, version-timeline). Verify: migration runs, router is wired in main.py, sidebar shows "AI Instructions" nav item, all hardcoded prompts are seeded into managed_prompts table, agents load from DB with code fallback. Do NOT generate prompt management from scratch -- use the scaffold.

**AI08-upgrade** [AI] [FIX] **Prompt management upgrade path** -- When /resume-it detects Tier 2 Outdated prompt management in a FastAPI+Next.js app: rename old tables with `_legacy` suffix, create scaffold tables, migrate data, copy scaffold files (models, schemas, service, router, 5 components, 4 pages), rewire sidebar/breadcrumbs/types/conftest. NEVER drop old tables. NEVER modify existing Alembic migrations. Tier 3 Custom implementations are protected (skip upgrade, note in status). Non-FastAPI+Next.js apps get gap documentation in TODO.md only.

**AI09** [AI] [FIX] **NeMo Guardrails** -- guardrails/ directory, config.yml, Colang rails. Basic suite (18 tests) passes.

**AI10** [AI] [FIX] **Prompt template validation (Tier 2/3)** -- validatePromptTemplate() on save endpoints. Immutable safety preamble. Draft/test/publish workflow. Variable interpolation sanitized. The scaffold prompt-editor component provides guided editing with safety zone indicators (green=safe, yellow=caution) and variable pills for non-technical users.

**AI11** [AI] [BLOCK] **SSE streaming for AI responses** -- ALL AI endpoints that return generated text MUST use Server-Sent Events (SSE) to stream tokens incrementally. Backend: AI chat/agent routes return `StreamingResponse` (FastAPI) or NextResponse with `text/event-stream` content type. Each SSE event is `data: {"token": "...", "done": false}\n\n`. Final event is `data: {"token": "", "done": true, "conversation_id": "..."}\n\n`. Frontend: proxies the SSE stream through a Next.js API route (same-origin, preserves auth cookies). The `useStreamingResponse` hook in `lib/ai/use-streaming.ts` handles EventSource connection, incremental token assembly, error/retry, and abort. Timeout eliminated: SSE keeps the connection alive with heartbeat events (`data: {"heartbeat": true}\n\n` every 15s). Verify: POST to an AI chat endpoint; confirm response is HTTP 200 with `Content-Type: text/event-stream`; confirm tokens arrive incrementally (not buffered); confirm frontend renders tokens as they arrive (typewriter effect). This is the default for all AI apps -- non-streaming AI endpoints are only acceptable for sub-second structured extraction (JSON schema responses under 500 tokens).

**AI12** [AI] [BLOCK] **Conversation persistence** -- AI chat conversations MUST be stored server-side in the database. The scaffold provides pre-built: 2 database tables (`conversations` with id/user_id/title/agent_slug/created_at/updated_at/archived_at, and `conversation_messages` with id/conversation_id/role/content/token_count/model/created_at) in a dedicated Alembic migration. REST API: `POST /api/ai/conversations` (create), `GET /api/ai/conversations` (list user's conversations, paginated), `GET /api/ai/conversations/{id}` (get with messages), `DELETE /api/ai/conversations/{id}` (soft-delete via archived_at), `POST /api/ai/conversations/{id}/messages` (send message, returns SSE stream). Session isolation: users can ONLY access their own conversations (WHERE user_id = current_user.id on all queries). Title auto-generated from first user message (truncated to 80 chars), editable via PATCH. Verify: create conversation, send messages, reload page -- conversation and full history are preserved. Verify: user A cannot access user B's conversations (returns 404).

**AI13** [AI] [BLOCK] **Chat panel scaffold component** -- The scaffold provides a pre-built `ChatPanel` component and supporting components. 4 components total: `chat-panel.tsx` (full chat interface: message list + input + streaming bubble), `chat-message.tsx` (individual message with role icon, markdown rendering via react-markdown, copy button, timestamp), `chat-input.tsx` (auto-resizing textarea, send button, Shift+Enter for newlines, disabled during streaming), `conversation-sidebar.tsx` (conversation list with search, "New Chat" button, active conversation highlight, relative timestamps, archive/delete). Layout: conversation sidebar (w-72, collapsible) + chat panel (flex-1). The ChatPanel accepts an `agentSlug` prop to route messages to different AI agents. Streaming display: assistant messages render incrementally with a blinking cursor during streaming. Empty state: centered prompt with suggested starter questions (configurable per agent). Verify: ChatPanel renders, messages stream with typewriter effect, conversation sidebar lists previous conversations, new conversations appear immediately in sidebar.

**AI14** [AI] [FIX] **SSE error handling and fallback** -- SSE connections MUST handle failures gracefully with automatic retry before falling back to polling. Retry strategy: on SSE connection error or stream interruption, automatically retry up to 3 times with 1s/2s/4s exponential backoff. If all retries fail, fall back to polling mode: POST the message normally (non-streaming), poll `GET /api/ai/conversations/{id}/messages?after={last_message_id}` every 2s until the assistant response appears (complete message, not streamed). If polling also fails after 30s, show a user-friendly error: "AI is temporarily unavailable. Please try again." with a retry button. The `useStreamingResponse` hook manages the full lifecycle: SSE attempt -> retry -> poll fallback -> error state. Backend: AI chat endpoints MUST support both streaming (`Accept: text/event-stream`) and non-streaming (`Accept: application/json`) via the Accept header. Verify: kill the SSE connection mid-stream; confirm retry occurs; if retry fails, confirm polling fallback delivers the complete response. Verify: request with `Accept: application/json` returns the full response as a single JSON object.

**AI15** [AI] [FIX] **SSE environment variables** -- `.env.example` and docker-compose.yml include: `AI_SSE_HEARTBEAT_INTERVAL_SECONDS` (default: 15), `AI_SSE_RETRY_MAX_ATTEMPTS` (default: 3), `AI_SSE_POLL_INTERVAL_SECONDS` (default: 2), `AI_SSE_POLL_TIMEOUT_SECONDS` (default: 30). All timing values in SSE/polling logic read from env vars -- no hardcoded intervals. Settings service (G02) includes these as configurable AI settings.

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
| Docker build TLS error | SSL-inspecting proxy | Auto-discover ACR proxy via `az acr cache list` and set DOCKER_HUB_PREFIX/MCR_PREFIX/GHCR_PREFIX in .env (I08, V01). Fallback: ask user to pause Zscaler/Netskope |
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
