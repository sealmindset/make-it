# Guardrails Reference (Tiered)

Guardrails are split into tiers. **Tier 0 is mandatory for every project**, regardless of type. Higher tiers activate based on the project type detected during Design.

---

## Project Type Classification

During the Design phase, classify the project into one of these types:

| Type | Signals | Example |
|------|---------|---------|
| `web-app` | Frontend + backend, browser-based, user login, dashboards, CRUD pages | Internal business tool, SaaS product, admin portal |
| `extension` | IDE plugin, browser extension, editor tooling | VS Code extension, Chrome extension |
| `cli` | Command-line tool, terminal-based, no GUI | Build tool, scanner, code generator |
| `library` | Importable package, no standalone runtime | SDK, utility library, shared module |
| `api-service` | Backend only, no frontend, serves other systems | REST API, webhook handler, data pipeline |

If ambiguous, default to `web-app`. The user does NOT need to know about this classification.

---

## Tier 0: Universal Guardrails (ALL project types)

These apply to every project /make-it builds, no exceptions.

### Process

1. **Ideation with confirmation** -- Summarize what you understood and get explicit "yes" before building.
2. **Design phase with documented decisions** -- Write `app-context.json` with all decisions, even if most fields are "not applicable." The document IS the decision record.
3. **Build-verify before handoff** -- Verify the project works (compiles, runs, tests pass) before the user sees it. Never hand off broken output.
4. **CHANGELOG.md from day one** -- Created during project setup, updated during build.
5. **TODO.md from day one** -- Created during project setup, populated with known follow-ups.
6. **Progress updates** -- Tell the user what's happening every 2-3 build steps.

### Security

7. **No secrets in committed files** -- `.gitignore` must exclude `.env`, credentials, tokens. `.env.example` committed with placeholder values.
8. **No hardcoded config values** -- URLs, keys, ports, feature flags all come from environment variables or settings files. Zero hardcoded `localhost:XXXX` in application code.
9. **Input validation at system boundaries** -- Validate all external input (user input, API responses, file parsing, CLI arguments). Trust internal code; validate at the edges.
10. **Mask/redact sensitive data in output** -- Logs, error messages, and UI never display full secrets, tokens, or credentials.
11. **Latest stable dependencies** -- Always use the latest stable version of every dependency. No pinning to outdated majors. Check for known CVEs before proceeding.
12. **No Java runtime dependencies** -- Do not use Java-based tools, libraries, or Docker images (including navikt/mock-oauth2-server). Java runtime dependencies are prohibited by project policy. Use Python, Node.js, Go, or Rust alternatives instead.

### Architecture

13. **Separation of concerns** -- Distinct layers/modules with clear responsibilities. Models separate from business logic separate from presentation/UI.
14. **Environment-based configuration** -- Same code path in dev and prod. No `if (isDevelopment)` branching. Configuration changes via env vars or settings files.
15. **Extensibility by design** -- Identify the primary extension point (plugins, middleware, hooks, event handlers) and build it in from the start. Avoid monolithic designs where adding a feature requires modifying core code.
16. **API-first for external communication** -- Any communication with external systems uses a client abstraction that reads its target from configuration.

### Quality

17. **Project compiles/builds with zero errors** -- Type-check, lint, or compile before handoff. The user never sees a build failure.
18. **Verify the thing works** -- Beyond "it compiles": start it, run it, confirm the primary function operates. For a web app, load the page. For a CLI, run the command. For an extension, verify it activates.
19. **Git repo initialized** -- `git init`, `.gitignore` configured, initial state committed or ready to commit.

---

## Tier 1: Web Application Guardrails

Activate when `project_type == "web-app"`. These are the existing /make-it guardrails for browser-based applications with frontend + backend.

### Authentication & Authorization
- OIDC authentication (provider chosen during Design: Azure AD, Auth0, Okta, Google, GitHub, Keycloak, etc.)
- Auth roles from application database (NOT OIDC provider claims)
- Logout via POST to backend API (NOT GET links)
- Database-driven RBAC with 4 tables (roles, permissions, role_permissions, users.role_id FK)
- Page-level CRUD permissions (resource.action format, auto-generated per page)
- 4 system roles (Super Admin, Admin, Manager, User) seeded in migration
- Custom roles with dynamic permission sets via admin UI permission matrix
- User provisioning from OIDC directory only (no email invites)
- `require_permission(resource, action)` middleware on all route handlers
- Mock-oidc for local development with pre-seeded test users

### UI & Frontend
- System fonts only (no external font CDNs -- Zscaler-safe)
- One shared authenticated layout (not duplicated per page)
- Header bar: SidebarTrigger | Breadcrumbs | Spacer | QuickSearch | ModeToggle
- Standard UI components: Breadcrumbs, DataTable, QuickSearch, ModeToggle
- All list pages use DataTable component (not plain HTML tables)
- ThemeProvider wraps app with oklch CSS variables
- Pages fetch data through service/API layer (no hardcoded mock data)

### Data & Backend
- Database migrations generated (Alembic or Prisma -- not just models)
- Seed data mandatory -- app starts with populated pages, not empty screens
- Seed user oidc_subjects match mock-oidc subject IDs exactly
- Parameterized database queries (never string concatenation)
- API-first: backend returns JSON, frontend is separate concern

### Infrastructure
- Docker Compose for local development (profiles: default for app, "dev" for mocks)
- Mock services for all external integrations
- Mock service seed script (scripts/seed-mock-services.sh)
- Service client endpoints verified against mock API contracts
- Terraform (or equivalent IaC) generated for the user's chosen cloud provider as DevOps handoff artifact (user never applies)
- IaC state backend configured for the chosen cloud provider's state storage
- All cloud resources tagged (app, environment, managed-by, owner)

### Prompts
- Execute all 14 prompts in order (#1-#14)
- All [BRACKETS] filled from app-context.json

### Build-Verify (Web App)
Full static verification + live verification per make-it.md build-verify step.

Additional OIDC/auth/type checks (CRITICAL -- these prevent recurring issues across apps):
- Frontend uses same-origin proxy: next.config.ts rewrites /api/* to backend
- Frontend BASE_URL="/api" (relative path, not hardcoded hostname)
- OIDC redirect_uri goes through frontend proxy: {FRONTEND_URL}/api/auth/callback
- AuthMe type is flat: { sub, email, name, role_id, role_name, permissions[] }
- No .user wrapper or nested Role object in AuthMe
- API client does NOT globally redirect on 401
- Login endpoint returns 302 redirect (not JSON)
- Frontend API calls use paths without /api prefix (BASE_URL adds it)
- Frontend TypeScript types match backend Pydantic schema field names exactly
- Backend list endpoints: frontend uses T[] not PaginatedResponse<T> (unless backend actually paginates)

---

## Tier 2: IDE Extension Guardrails

Activate when `project_type == "extension"`. For VS Code extensions, browser extensions, and editor plugins.

### Project Structure
- Extension manifest complete (`package.json` contributes section or `manifest.json`)
- All commands, views, menus, and configuration declared in manifest
- Activation events scoped appropriately (not `*` wildcard)
- `.vscodeignore` or equivalent packaging exclusion file
- Build script produces bundled output (esbuild, webpack)

### Extension-Specific Security
- Extension tokens/API keys stored in VS Code SecretStorage (not plaintext settings)
- User-facing settings for server URLs and configuration (not hardcoded)
- External tool output parsed defensively (malicious scanner output should not crash the extension)

### Extension Architecture
- Provider pattern for VS Code integration points (TreeDataProvider, DiagnosticCollection, etc.)
- Commands registered with proper disposal (context.subscriptions)
- Configuration change listeners for dynamic settings
- Output channel for debug/diagnostic logging (not console.log)
- Graceful degradation when optional dependencies (binaries, servers) are unavailable

### Extension Build-Verify
- TypeScript compiles with zero errors (`tsc --noEmit`)
- Extension bundles successfully (esbuild/webpack)
- Manifest is valid (all referenced commands exist in code)
- Extension activates without errors in Extension Development Host

---

## Tier 3: CLI Tool Guardrails

Activate when `project_type == "cli"`. For command-line tools and terminal-based applications.

### Project Structure
- Entry point with argument parser (argparse, commander, clap, cobra)
- Help text for every command and flag (`--help` works)
- Version flag (`--version`)
- Exit codes: 0 for success, non-zero for failure (documented)

### CLI-Specific Security
- No secrets in command-line arguments (use env vars or config files)
- Input validation on all arguments and flags
- Safe file path handling (no path traversal)

### CLI Architecture
- Subcommand pattern for multi-function tools
- Structured output option (JSON with `--json` or `--output json`)
- Quiet/verbose modes (`-q`, `-v`, `--verbose`)
- Stderr for diagnostics, stdout for output (pipeable)
- Progress indicators for long-running operations

### CLI Build-Verify
- Compiles/builds to a single binary or entry point
- `--help` produces valid output
- `--version` produces version string
- Primary command runs successfully with sample input
- Exit codes are correct (0 on success, non-zero on error)

---

## Tier 4: Library / Package Guardrails

Activate when `project_type == "library"`. For importable packages and shared modules.

### Project Structure
- Package manifest with correct entry points (main, module, types, exports)
- TypeScript declarations or type stubs generated
- Minimal dependencies (avoid pulling in heavy transitive deps)

### Library Architecture
- Public API surface is explicit and small
- Internal implementation details are not exported
- Backward-compatible API changes (semver respected)
- Tree-shakeable exports (named exports, no side effects)

### Library Build-Verify
- Compiles with zero errors
- Package can be imported in a test consumer
- Exported types are correct
- No circular dependencies

---

## Tier 5: API Service Guardrails

Activate when `project_type == "api-service"`. Backend-only services with no frontend.

### Inherits from Tier 1 (Web App) EXCEPT:
- No frontend/UI guardrails (no Breadcrumbs, DataTable, QuickSearch, ModeToggle)
- No standard UI components
- No shared authenticated layout

### API-Specific Additions
- OpenAPI/Swagger spec generated or maintained
- Health check endpoint (`/health` or `/healthz`)
- Structured logging (JSON format)
- Request/response validation on all endpoints
- Error responses follow consistent format (RFC 7807 or similar)
- Rate limiting on public endpoints

### API Build-Verify
- Server starts and responds to health check
- All endpoints return expected status codes
- Request validation rejects malformed input
- Auth-protected endpoints return 401/403 appropriately

---

## How /make-it Uses These Tiers

During the **Design phase**, after ideation is complete:

1. **Classify the project type** based on ideation answers (the user never sees this classification)
2. **Record `project_type` in app-context.json**
3. **Apply Tier 0** -- always, unconditionally
4. **Apply the matching higher tier** (Tier 1-5) based on project_type
5. **Skip guardrails from non-matching tiers** -- but document WHY in app-context.json
6. **Adapt the build-verify checklist** to match the active tiers

The Design phase summary to the user should reflect the project type without using technical jargon:
- Web app: "A web app with a modern interface..."
- Extension: "A plugin for your code editor..."
- CLI: "A command-line tool you run from your terminal..."
- Library: "A reusable building block other apps can use..."
- API service: "A backend service that other systems connect to..."

---

## Tier Activation Matrix

| Guardrail Area | Tier 0 | Tier 1 (Web) | Tier 2 (Ext) | Tier 3 (CLI) | Tier 4 (Lib) | Tier 5 (API) |
|----------------|--------|-------------|-------------|-------------|-------------|-------------|
| app-context.json | Y | Y | Y | Y | Y | Y |
| CHANGELOG + TODO | Y | Y | Y | Y | Y | Y |
| .gitignore + no secrets | Y | Y | Y | Y | Y | Y |
| No hardcoded config | Y | Y | Y | Y | Y | Y |
| Input validation | Y | Y | Y | Y | Y | Y |
| Latest stable deps | Y | Y | Y | Y | Y | Y |
| Build-verify | Y | Y | Y | Y | Y | Y |
| OIDC / Auth | | Y | | | | Y* |
| Database RBAC | | Y | | | | Y* |
| Docker Compose | | Y | | | | Y |
| Mock services | | Y | | | | Y |
| Seed data | | Y | | | | Y |
| Standard UI components | | Y | | | | |
| System fonts only | | Y | | | | |
| Extension manifest | | | Y | | | |
| SecretStorage | | | Y | | | |
| Argument parser | | | | Y | | |
| Exit codes | | | | Y | | |
| Package exports | | | | | Y | |
| OpenAPI spec | | | | | | Y |
| Health check endpoint | | | | | | Y |

*Y* = when auth is needed for the API service
