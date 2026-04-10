# make-it

## What This Is

`/make-it` is a Claude Code skill that takes a first-time developer from an app idea to a fully working, deployed application through guided Q&A. No programming knowledge required.

## How It Works

The user types `/make-it` and answers questions about their idea in plain English. The skill handles everything else:

0. **Preflight** -- Verify machine readiness (Git, Docker, GitHub CLI, Claude Code, VS Code; enterprise extras if detected)
1. **Ideation** -- Conversational Q&A to understand the app idea
2. **Design** -- AI-driven technical decisions (invisible to user)
3. **Build** -- Code generation following the AI Vibe Coded Design Pattern Guide
4. **Ship** -- Handoff to `/ship-it` for deployment

## Key Principles

- The user NEVER needs to understand code, frameworks, or infrastructure
- All technical jargon is translated to plain language
- Questions are asked one at a time, conversationally
- The Design Pattern Guide is the architectural blueprint (enforced silently)
- The 14 Enterprise Prompts are the execution templates (filled in automatically)
- Build-verify is a silent quality gate: starts the app, tests auth/API/pages/permissions, fixes issues -- the user never sees broken output
- `/try-it` presents the verified app to the user for exploration (app is already working)
- `/ship-it` handles deployment (the user just types the command)
- The user never fixes code -- security scanner findings (if configured) and CI/CD automation issues are auto-remediated
- The user only verifies their app works the way they envision it

## /try-it

`/try-it` presents the user's app for exploration. When called after `/make-it`, the app is already running and verified by build-verify. When called standalone, it starts the app first.

0. **Context Discovery** -- Reads app-context, docker-compose, .env; checks if app is already running
1. **Startup** -- Starts containers if not already running; skips if build-verify left them up
2. **Smoke Test** -- Quick verification (health checks, login, pages, screenshots) as a safety net
3. **Fix (safety net)** -- If smoke test finds issues, diagnose and fix (should rarely happen)
4. **Report** -- Generates `TRY-IT-REPORT.md` with test results, screenshots, and access instructions
5. **Handoff** -- Tells user how to explore their app in the browser, stays available to fix issues they find

## /retrofit-it

`/retrofit-it` takes an existing application (not built by /make-it) and upgrades it with production-ready foundations. Instead of asking interview questions, it reverse-engineers the codebase first, then asks targeted clarifying questions only when the code is ambiguous. Foundations include OIDC auth, database-driven RBAC, database-backed application settings, Docker Compose, mock services, and security hardening.

0. **Preflight** -- Same machine readiness checks as /make-it
1. **Discovery** -- Reverse-engineer the app (stack, architecture, features, auth, data model, integrations)
2. **Gap Analysis** -- Compare what exists vs /make-it standards, calculate a retrofit risk score
3. **Clarification** -- Ask targeted questions about ambiguities (NOT a full interview -- max 3-5 questions)
4. **Plan** -- Present the retrofit plan with risk assessment, get user approval
5. **Retrofit** -- Execute changes (single-pass if risk score <= 35, phased with user verification if higher)
6. **Verify** -- Build-verify identical to /make-it, plus preservation checks (existing features still work)
7. **Ship** -- Hand off to /ship-it

### Risk Score System

Each gap is weighted by change type: Add (1), Enhance (2), Wrap (3), Restructure (4), Replace (5), Rewrite (8). Total score determines strategy:
- 0-15: Low risk, single-pass
- 16-35: Medium risk, single-pass with extra verification
- 36-60: High risk, phased retrofit (user verifies between phases)
- 61+: Very high risk, phased + migration recommendation

### Key Principles

- Reverse-engineer first, ask questions second
- Never break existing functionality (the #1 rule)
- Preserve the user's design intent -- add foundations UNDER existing design
- Existing code is additive (keep tests, CI, custom components)
- Auth wrapping preferred over replacement, unless wrapping costs more
- Settings management added after auth + RBAC (depends on permission gating)
- Stack migration is a last resort (only if framework is incompatible or EOL)
- Generates app-context.json for /resume-it and /ship-it compatibility

## /resume-it

`/resume-it` picks up where `/make-it` left off. The user runs it from within the project directory.

0. **Context Discovery** -- Reads `.make-it-state.md`, `CHANGELOG.md`, `TODO.md`, `CLAUDE.md`, git log, security scanner findings
1. **Security Scanner Remediation** -- Auto-fixes scan findings (invisible to user unless behavior changes)
2. **Greet + Suggest** -- Shows project status and suggests actionable next steps
3. **Work** -- Helps with new features, TODO items, or anything the user describes
4. **Readiness Check** -- Standup-style "what's done / what's blocked / what's next" assessment. Scans `app-context.json` and codebase to detect required infrastructure, env vars, tickets, and approvals. Generates a shareable `NEXT-STEPS.md` checklist.
5. **Test** -- Scaffolds test infrastructure (pytest, Playwright) if needed, generates and runs tests
6. **Ship** -- Handoff to `/ship-it` when ready

## /argo-it

`/argo-it` deploys a Docker Compose app to Kubernetes via Argo CD. Universal skill -- works with any K8s cluster, any container registry, any ingress controller. The user runs it from any project that has a docker-compose.yml.

0. **Detect** -- Read docker-compose.yml + any existing K8s manifests to auto-detect conventions (registry, ingress controller, storage class, secret naming, namespace)
1. **Setup** -- Only ask what couldn't be detected (typically 3-4 questions: namespace, hostname, deploy branch)
2. **Generate** -- Create `env/dev/` and `env/prod/` Kustomize manifests using detected patterns
3. **CI Workflow** -- Generate build-and-push workflow (GitHub Actions, GitLab CI, Jenkins, or Azure DevOps)
4. **Onboarding** -- Generate `ONBOARDING-K8S.md` with manual steps (secrets, Argo config) + local K8s testing instructions
5. **Deploy** -- Offer 4 options: push+merge, test locally first (Rancher Desktop/minikube/kind), just push, or review only

### Key Principles

- **Detect-first**: Reads existing manifests to extract conventions before asking questions
- Follows Kustomize + Argo CD GitOps pattern (no Helm, no Kompose)
- Generates manifests for multi-service apps (one Deployment per app service)
- Skips databases and mock services (handled separately in K8s)
- Never hardcodes secrets -- always K8s Secret references
- Never applies K8s resources directly -- Argo CD handles that via GitOps
- Supports multiple registries (ghcr.io, ECR, ACR, Docker Hub), ingress controllers (nginx, Traefik, ALB, Istio), and storage classes
- Local K8s testing via `kubectl apply -k env/dev/` on Rancher Desktop, minikube, or kind

## /wrap-it

`/wrap-it` cleanly wraps up a work session. The user runs it when they're done for the day.

0. **Discover** -- Check what's running (containers), what's changed (git status), read state files
1. **Save** -- Offer to commit uncommitted changes, update TODO.md, CHANGELOG.md, and .make-it-state.md
2. **Shutdown** -- `docker compose down` (preserves data volumes for fast restart), check for orphaned ports
3. **Report** -- Summary of what was saved, what was shut down, and top 3 items for next session

### Key Principles

- Never destroys data volumes (`docker compose down` without `-v`)
- Never pushes to remote -- local commits only
- Never kills processes -- only reports orphaned ports
- Never starts new work -- the user said they're done
- Always updates .make-it-state.md so /resume-it picks up seamlessly

### State Breadcrumb

`/make-it` writes `.make-it-state.md` at the end of the build phase. `/resume-it` and `/wrap-it` read and update this file each session. It tracks what was built, what's pending, test status, and suggested next steps.

## File Structure

```
.claude/
  commands/
    make-it.md                    # Main skill -- idea to working app
    try-it.md                     # Try skill -- spin up, test, explore in browser
    resume-it.md                  # Resume skill -- continue, test, fix, ship
    wrap-it.md                    # Wrap-up skill -- save progress, shut down, prep for next session
    argo-it.md                    # Argo CD skill -- generate K8s manifests, deploy via GitOps
    retrofit-it.md                # Retrofit skill -- upgrade existing app with production foundations
  make-it/
    references/
      prerequisites.md             # Preflight checks (from Vibe Code Quick Start)
      design-blueprint.md         # Extracted from AI Vibe Coded Design Pattern Guide
      prompt-templates.md          # The 14 prompts (auto-filled from user answers)
      ship-it-guide.md            # /ship-it integration reference
      guardrails.md               # Tiered guardrail system (Tier 0-5)
      build-standards.md          # Shared verification checklist (single source of truth)
      build-verify-security.md   # Automatic security scan during build-verify Part D
      fix-strategies.md          # 12 fix strategies for auto-remediation (AUTO/SEMI-AUTO/MANUAL)
    templates/
      app-context.md              # Template for tracking user answers -> technical decisions
    variants/
      registry.md               # Maps variant names -> definition files (read by make-it.md)
      _template.md              # Template for creating new variants
      mobile.md                 # PWA mobile variant (first implementation)
    scaffolds/
      fastapi-nextjs/             # Pre-built scaffold for FastAPI + Next.js web apps
        backend/                  # FastAPI app (auth, RBAC, models, routers, schemas, Alembic)
        frontend/                 # Next.js app (pages, components, lib, Tailwind, oklch theme)
        mock-services/mock-oidc/  # Complete mock OIDC provider (copied as-is, never regenerated)
        scripts/                  # seed-mock-services.sh template
        docker-compose.yml        # Multi-service orchestration template
        .env.example              # Environment variable documentation
        .gitignore                # Standard Python + Node.js + Docker ignores
        README.md                 # Scaffold documentation (placeholders, architecture, patterns)
      overlays/
        pwa/                      # PWA scaffold overlay (mobile variant)
          frontend/components/    # install-prompt, offline-indicator, pull-to-refresh
          frontend/lib/           # pwa.ts, use-online-status.ts
          frontend/app/           # sw.ts (service worker), offline/page.tsx
          frontend/public/        # manifest.json, icons/
```

## Scaffolds

Scaffolds are pre-built, battle-tested code foundations with `[BRACKET_PLACEHOLDERS]` for app-specific values. They encode every lesson learned from real builds so the same bugs never recur.

### fastapi-nextjs (98 files)
The primary scaffold for web applications. The Build phase copies it into the project, replaces placeholders, then generates domain-specific code on top. Provides:
- **Auth**: Complete OIDC flow (login → mock-oidc → callback → JWT cookie → /me → logout)
- **RBAC**: 5 tables (roles, permissions, role_permissions, user_roles, users), multi-role support via user_roles junction table, require_permission middleware with union semantics, admin UI with multi-role assignment
- **Frontend**: Same-origin proxy, flat AuthMe, DataTable with Excel-like filtering, sidebar, breadcrumbs, quick search, mode toggle, oklch theming
- **Docker**: Compose with health checks (127.0.0.1), entrypoint.sh for migrations, mock-oidc on dev profile
- **Mock-oidc**: Copied as-is. RSA signing, internal/external URL split, user picker, admin API
- **Activity Logs**: LogStore circular buffer, request logging middleware, REST API, admin UI page with stats/filters/auto-refresh
- **AI Prompt Management**: 6 database tables, ~25 API routes, 4 admin UI pages ("AI Instructions"), 5 reusable components (prompt-card, prompt-editor with guided mode/safety zones, safety-indicator, variable-pill, version-timeline). Card-based registry, guided editing for non-technical users, version timeline with one-click restore, "Try It" testing, "Where Used" breadcrumbs
- **Trailing-slash wrapper**: ASGI middleware that prevents Docker hostname leaks in FastAPI redirects
- **Test infrastructure**: pytest conftest with SQLite UUID compat, auth bypass fixtures, health tests, Playwright e2e scaffolding

What the scaffold does NOT provide (generated fresh per app):
- Domain models, migrations, and seed data
- Domain API routes and schemas
- Domain frontend pages
- Dashboard widgets
- External integration mock services
- Terraform infrastructure

## Variants (Plugin System)

Variants extend the standard /make-it flow with different design patterns, scaffold overlays, and guardrail checks. They are activated by CLI argument: `/make-it <variant-name>`.

### How Variants Work

- `/make-it` (no argument) = standard web-app (unchanged)
- `/make-it mobile` = web-app + PWA overlay (service workers, manifest, responsive-first)
- `/make-it <name>` = looks up variant in `variants/registry.md`, loads its definition file

A variant is always layered ON TOP of a base project type. It augments each phase (Ideation, Design, Build, Build-Verify) — it never replaces them. The variant is recorded in `app-context.json` as `"variant": "mobile"` so downstream skills (/resume-it, /try-it, /ship-it) are aware.

### Available Variants

| Variant | Command | Description |
|---------|---------|-------------|
| mobile (PWA) | `/make-it mobile` | Progressive Web App with offline support, install prompt, responsive-first layouts. Uses Serwist for service worker. Adds 8 guardrail checks (P01-P08). |

### Creating a New Variant

1. Copy `variants/_template.md` to `variants/<your-variant>.md`
2. Fill in all sections (metadata, ideation additions, design additions, scaffold overlay, guardrails, build-verify)
3. Create overlay files in `scaffolds/overlays/<name>/` if the variant needs new frontend files
4. Add a row to `variants/registry.md`
5. Add check IDs to `build-standards.md`

### Architecture

- **Registry**: `variants/registry.md` — maps variant names to definition files
- **Definitions**: `variants/<name>.md` — complete spec for a variant (questions, decisions, overlay, checks)
- **Overlays**: `scaffolds/overlays/<name>/` — files copied on top of the base scaffold during Build
- **Guardrail checks**: `[Tier N+variant_name]` format in build-standards.md (e.g., `[Tier 1+mobile]`)
- **App-context**: `variant` and `variant_config` fields track the active variant and its configuration

## Source Documents

- `AC-Vibe Code Developed Quick Start` -- Prerequisites and machine setup
- `AC-AI Vibe Coded Design Pattern Guide` -- The architectural blueprint
- `AC-Prompts for Building Enterprise Applications` -- The 14 execution prompts
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
- Scaffold foundation + domain-specific code generation

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
- OIDC authentication (provider chosen during Design: Azure AD, Auth0, Okta, Google, GitHub, Keycloak, etc.)
- Auth roles from application database (NOT OIDC provider claims)
- Logout via POST to backend API (NOT GET links)
- Database-driven RBAC with 5 tables (roles, permissions, role_permissions, user_roles, users.primary_role_id FK)
- Multi-role model: users can have multiple effective roles via user_roles junction table; permissions are the union across all roles
- Page-level CRUD permissions (resource.action format, auto-generated per page)
- 4 system roles (Super Admin, Admin, Manager, User) seeded in migration
- Custom roles with dynamic permission sets via admin UI permission matrix
- User provisioning from OIDC directory only (no email invites)
- require_permission(resource, action) middleware on all route handlers (never role string checks)
- M.A.C.H. architecture principles
- System fonts only (no external font CDNs -- safe behind SSL-inspecting proxies)
- Mock services for local development (mock-oidc + per-integration mocks)
- Mock service seed script (scripts/seed-mock-services.sh)
- Service client endpoints verified against mock API contracts
- Database seed data matching mock-oidc users (oidc_subject alignment)
- Environment-based service switching (no code branching for dev vs prod)
- Input validation on all endpoints
- Parameterized database queries
- Security headers before production
- Terraform generated as DevOps handoff artifact (user never applies)

## Deployment Lifecycle

The user's world is simple: describe, verify, say "ready." Everything else is automated.

```
/make-it -> Build new app in Docker sandbox, push to GitHub
/retrofit-it -> Upgrade existing app with production foundations (OIDC, RBAC, Docker, etc.)
/resume-it -> Iterate (security scanner auto-fixes, user verifies idea works)
/wrap-it -> Save progress, shut down app, prep state for next session
/argo-it -> Generate K8s manifests from Docker Compose, merge to deploy branch for Argo CD
/ship-it -> Hand off to CI/CD
  CI/CD Automation -> Scan, auto-remediate, send back for verification
  /try-it -> User verifies app still works
  /ship-it -> Recheck, deploy to dev
  User confirms prod-ready -> Production checks -> Deploy to prod
```

See `ship-it-guide.md` for the full lifecycle, CI/CD automation contract, and security scanner integration.

## Shared Build Standards

`build-standards.md` is the **single source of truth** for what a compliant application looks like. All three skills reference it:

| Skill | How it uses build-standards.md |
|-------|-------------------------------|
| `/make-it` | Build-verify Part A runs all checks for active tiers |
| `/retrofit-it` | Verify phase runs all checks + retrofit-specific preservation checks |
| `/resume-it` | Catch-up scan compares project against latest checks, surfaces gaps |

Each check has an ID (S01, A01, R01, etc.), a tier, and a severity:
- `[BLOCK]` -- must pass before handoff
- `[FIX]` -- auto-fix if failing
- `[WARN]` -- note in TODO.md

When build-standards.md is updated with new checks, `/resume-it` automatically detects the gap on the next run and suggests the missing patterns. This eliminates drift between skills.

## Build Quality

The build process has six layers:
1. **Foundation** -- Scaffold provides pre-verified auth, RBAC, Docker, and UI components (these patterns were debugged once and never regenerated)
2. **Prevention** -- Prompts and build instructions encode lessons learned (API contract verification, seed data alignment, Alembic syntax rules)
3. **Detection** -- Build-verify silently starts the app and tests auth flow, API endpoints, page content, and permission boundaries before the user sees anything
4. **Security Hardening** -- Build-verify Part D runs an automatic security scan (static analysis, dependency audit, AI safety checks) and auto-fixes findings in a self-healing loop (up to 3 cycles) before the user ever sees the app. Only mechanical AUTO-class fixes are applied silently; remaining findings go to TODO.md. This logic is fully internalized in /make-it (via `build-verify-security.md` + `fix-strategies.md`) -- no separate skill installation required. Standalone /nemo-it and /fix-it are optional skills for GRC teams needing formal attestation, interactive triage, or deeper analysis (OWASP ZAP, SQLMap, behavioral AI testing).
5. **Demo** -- /try-it presents the verified app to the user; its fix cycle is a safety net, not the primary quality mechanism
6. **Catch-up** -- /resume-it scans existing projects against the latest build-standards.md and applies any new patterns
