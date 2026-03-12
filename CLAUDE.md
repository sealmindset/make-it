# make-it

## What This Is

`/make-it` is a Claude Code skill that takes a first-time developer from an app idea to a fully working, deployed application through guided Q&A. No programming knowledge required.

## How It Works

The user types `/make-it` and answers questions about their idea in plain English. The skill handles everything else:

0. **Preflight** -- Verify machine readiness (VPN, local admin, GitHub, Azure, Docker)
1. **Ideation** -- Conversational Q&A to understand the app idea
2. **Design** -- AI-driven technical decisions (invisible to user)
3. **Build** -- Code generation following the AI Vibe Coded Design Pattern Guide
4. **Ship** -- Handoff to `/ship-it` for CI/CD deployment

## Key Principles

- The user NEVER needs to understand code, frameworks, or infrastructure
- All technical jargon is translated to plain language
- Questions are asked one at a time, conversationally
- The Design Pattern Guide is the architectural blueprint (enforced silently)
- The 14 Enterprise Prompts are the execution templates (filled in automatically)
- Build-verify is a silent quality gate: starts the app, tests auth/API/pages/permissions, fixes issues -- the user never sees broken output
- `/try-it` presents the verified app to the user for exploration (app is already working)
- `/ship-it` handles deployment (the user just types the command)

## /try-it

`/try-it` presents the user's app for exploration. When called after `/make-it`, the app is already running and verified by build-verify. When called standalone, it starts the app first.

0. **Context Discovery** -- Reads app-context, docker-compose, .env; checks if app is already running
1. **Startup** -- Starts containers if not already running; skips if build-verify left them up
2. **Smoke Test** -- Quick verification (health checks, login, pages, screenshots) as a safety net
3. **Fix (safety net)** -- If smoke test finds issues, diagnose and fix (should rarely happen)
4. **Report** -- Generates `TRY-IT-REPORT.md` with test results, screenshots, and access instructions
5. **Handoff** -- Tells user how to explore their app in the browser, stays available to fix issues they find

## /resume-it

`/resume-it` picks up where `/make-it` left off. The user runs it from within the project directory.

0. **Context Discovery** -- Reads `.make-it-state.md`, `CHANGELOG.md`, `TODO.md`, `CLAUDE.md`, git log
1. **Greet + Suggest** -- Shows project status and suggests actionable next steps
2. **Work** -- Helps with bug fixes, new features, TODO items, or anything the user describes
3. **Readiness Check** -- Standup-style "what's done / what's blocked / what's next" assessment. Scans `app-context.json` and codebase to detect required infrastructure, env vars, tickets, and approvals. Generates a shareable `NEXT-STEPS.md` checklist.
4. **Test** -- Scaffolds test infrastructure (pytest, Playwright) if needed, generates and runs tests
5. **Ship** -- Handoff to `/ship-it` when ready

### State Breadcrumb

`/make-it` writes `.make-it-state.md` at the end of the build phase. `/resume-it` reads and updates this file each session. It tracks what was built, what's pending, test status, and suggested next steps.

## File Structure

```
.claude/
  commands/
    make-it.md                    # Main skill -- idea to working app
    try-it.md                     # Try skill -- spin up, test, explore in browser
    resume-it.md                  # Resume skill -- continue, test, fix, ship
  make-it/
    references/
      prerequisites.md             # Preflight checks (from Vibe Code Quick Start)
      design-blueprint.md         # Extracted from AI Vibe Coded Design Pattern Guide
      prompt-templates.md          # The 14 prompts (auto-filled from user answers)
      ship-it-guide.md            # /ship-it integration reference
      guardrails.md               # Tiered guardrail system (Tier 0-5)
    templates/
      app-context.md              # Template for tracking user answers -> technical decisions
```

## Source Documents

- `AC-Vibe Code Developed Quick Start` -- Prerequisites and machine setup
- `AC-AI Vibe Coded Design Pattern Guide` -- The architectural blueprint
- `AC-Prompts for Building Enterprise Applications` -- The 12 execution prompts
- `ship-it RFC` -- The CI/CD deployment skill

## Tiered Guardrails

Guardrails are split into tiers. Tier 0 is mandatory for ALL project types. Higher tiers activate based on what's being built. See `guardrails.md` for the complete reference.

### Tier 0: Universal (every project)
- Ideation confirmed, Design documented in app-context.json, Build-verified before handoff
- CHANGELOG.md and TODO.md from day one
- No secrets in committed files, no hardcoded config values
- Input validation at system boundaries, sensitive data masked in output
- Latest stable dependencies, separation of concerns, environment-based config
- Git initialized with proper .gitignore

### Tier 1: Web Application
- OIDC authentication, database-driven RBAC, 4 system roles, permission matrix
- Standard UI components (Breadcrumbs, DataTable, QuickSearch, ModeToggle)
- Docker Compose with mock services, seed data, system fonts only
- 14 Enterprise Prompts executed in order

### Tier 2: IDE Extension
- Extension manifest complete, activation events scoped, SecretStorage for tokens
- Provider pattern (TreeView, DiagnosticCollection), graceful degradation
- Build produces bundled output, packaging exclusion file

### Tier 3: CLI Tool
- Argument parser, --help/--version, exit codes, structured output option

### Tier 4: Library / Package
- Package manifest, type declarations, explicit public API, no circular deps

### Tier 5: API Service
- Health check endpoint, OpenAPI spec, structured logging, consistent error format

## Standards Enforced (Tier 1: Web App)

Web applications additionally follow:
- OIDC authentication (Azure AD / Entra ID)
- Auth roles from application database (NOT OIDC provider claims)
- Logout via POST to backend API (NOT GET links)
- Database-driven RBAC with 4 tables (roles, permissions, role_permissions, users.role_id FK)
- Page-level CRUD permissions (resource.action format, auto-generated per page)
- 4 system roles (Super Admin, Admin, Manager, User) seeded in migration
- Custom roles with dynamic permission sets via admin UI permission matrix
- User provisioning from OIDC directory only (no email invites)
- require_permission(resource, action) middleware on all route handlers (never role string checks)
- M.A.C.H. architecture principles
- System fonts only (no external font CDNs -- Zscaler-safe)
- Mock services for local development (mock-oidc + per-integration mocks)
- Mock service seed script (scripts/seed-mock-services.sh)
- Service client endpoints verified against mock API contracts
- Database seed data matching mock-oidc users (oidc_subject alignment)
- Environment-based service switching (no code branching for dev vs prod)
- Input validation on all endpoints
- Parameterized database queries
- Security headers before production
- Terraform for infrastructure as code

## Build Quality

The build process has three layers:
1. **Prevention** -- Prompts encode lessons learned from past builds (auth patterns, font rules, API contracts, seed data requirements)
2. **Detection** -- Build-verify silently starts the app and tests auth flow, API endpoints, page content, and permission boundaries before the user sees anything
3. **Demo** -- /try-it presents the verified app to the user; its fix cycle is a safety net, not the primary quality mechanism
