# /make-it

A Claude Code skill that takes a first-time developer from a raw idea to a fully working, production-ready application through guided conversation. No coding experience required.

## What It Does

The user describes what they want in plain English. /make-it handles everything else:

1. **Preflight** -- Verifies the machine is ready (tools, access, connectivity)
2. **Ideation** -- Understands what the user wants to build through conversational Q&A
3. **Design** -- Makes all technical decisions behind the scenes based on their answers
4. **Build** -- Generates the complete application, verifies it works, hands it to the user
5. **Ship** -- Hands off to /ship-it for deployment

The user never sees code during Q&A, never picks frameworks, and never configures infrastructure.

## Skill Ecosystem

/make-it is one skill in a family that covers the full application lifecycle:

| Skill | Purpose |
|-------|---------|
| `/make-it` | Build a new app from an idea |
| `/resume-it` | Continue work on an existing app (features, bugs, testing) |
| `/try-it` | Demo the app with mock services and guided walkthrough |
| `/ship-it` | Deploy -- creates PR with security checks, attestation, review |
| `/nemo-it` | Security attestation scan (OWASP + NeMo Guardrails AI safety) |
| `/retrofit-it` | Add production foundations (auth, RBAC, Docker, security) to an existing app |

## Directory Structure

```
~/.claude/make-it/
├── README.md                          # This file
├── references/
│   ├── prerequisites.md               # Phase 0: machine readiness checks
│   ├── design-blueprint.md            # Phase 2: architectural decision framework
│   ├── prompt-templates.md            # Phase 3: 14 build prompts executed in order
│   ├── guardrails.md                  # Tiered security and quality guardrails
│   └── ship-it-guide.md              # Phase 4: deployment lifecycle and CI/CD
├── scaffolds/
│   ├── fastapi-nextjs/                # Battle-tested scaffold for Python + React apps
│   │   ├── backend/                   # FastAPI app structure with RBAC, auth, Alembic
│   │   ├── frontend/                  # Next.js app with standard UI components
│   │   ├── mock-services/mock-oidc/   # Mock OIDC provider for local auth
│   │   ├── scripts/                   # Seed scripts for mock services
│   │   ├── docker-compose.yml         # Full orchestration (app + DB + mocks)
│   │   ├── .env.example               # Environment variable template
│   │   └── .gitignore                 # Standard ignores for Python + Node + Docker
│   └── nextjs-fullstack/              # Alternative scaffold (Next.js API routes)
└── templates/
    ├── app-context.md                 # JSON template for design decisions
    ├── ai-safety-attestation.md       # AI safety attestation report template
    └── nemo-it-attestation.md         # Security attestation report template (v1.1.0)
```

## Supported Project Types

/make-it classifies projects into types during Design and applies the appropriate guardrail tiers:

| Type | Tiers | What Gets Built |
|------|-------|----------------|
| `web-app` | 0, 1 | Frontend + backend, OIDC auth, RBAC, Docker, mock services, standard UI |
| `extension` | 0, 2 | IDE or browser extension with manifest, activation events, secret storage |
| `cli` | 0, 3 | Command-line tool with help, version, structured output, exit codes |
| `library` | 0, 4 | Importable package with types, entry points, no circular deps |
| `api-service` | 0, 5 | Backend API with health check, OpenAPI spec, error handling |

For `web-app` projects with a Python backend, /make-it uses the **FastAPI + Next.js scaffold** as a foundation. All other combinations generate from prompt templates directly.

## Design Blueprint (13 Architectural Decisions)

The design-blueprint.md drives all technical decisions. The user answers plain-language questions; /make-it maps answers to these patterns:

| # | Area | What It Decides |
|---|------|----------------|
| 1 | Authentication | OIDC provider, token handling, session management |
| 2 | Authorization | Database-driven RBAC: roles, permissions, role_permissions tables |
| 3 | Technology Stack | Language, framework, database, ORM, validation library |
| 4 | Multi-Tenancy | Single org vs multi-tenant, tenant isolation strategy |
| 5 | Security Essentials | Headers, CORS, CSRF, rate limiting, encryption |
| 6 | Infrastructure as Code | Terraform configuration for cloud deployment |
| 7 | Containerization | Dockerfile, docker-compose, health checks |
| 8 | M.A.C.H. Architecture | Microservices, API-first, Cloud-native, Headless principles |
| 9 | AI Provider Architecture | Provider abstraction, model selection, fallback strategy |
| 10 | AI Prompt Management | Tiered prompt storage: code, database, or full platform |
| 10a | Prompt Template Validation | Content validation, immutable safety preamble, draft/publish workflow |
| 11 | NeMo Guardrails | AI safety testing across 6 categories |
| 11b | AI Operational Safety | Runtime controls: sanitize, validate, rate-limit, PII mask, error handling |
| 12 | Mock Services | Local development without external dependencies |
| 13 | Standard UI Components | Breadcrumbs, DataTable, QuickSearch, ModeToggle |

## Build Prompts (14-Step Execution)

During the Build phase, /make-it executes these prompts in order. Each prompt generates a specific part of the application:

| # | Prompt | What It Generates |
|---|--------|-------------------|
| 1 | Start Project | Project structure, git init, CHANGELOG, TODO |
| 2 | Design UI | Pages, layouts, navigation, responsive design |
| 3 | Choose Stack | Package manifests, dependency installation |
| 4 | Design Architecture | API routes, service layer, data models |
| 5 | Cloud Infrastructure | Terraform configs (DevOps handoff artifact) |
| 6 | Docker Support | Dockerfile, docker-compose, entrypoint scripts |
| 7 | Multi-Tenant | Tenant isolation, RLS policies (if needed) |
| 8 | User Login | OIDC flow, JWT cookies, login/logout endpoints |
| 9 | RBAC Permissions | Roles, permissions, admin UI, permission middleware |
| 10 | AI Architecture | Provider abstraction, agents, prompt management |
| 10e | AI Safety Controls | Input sanitization, output validation, rate limiting, PII masking, template validation |
| 11 | Security Hardening | Headers, encryption, input validation, verification of all safety controls |
| 12 | Mock Services | Mock OIDC, mock external APIs, Docker profiles |
| 13 | Seed Data | Sample data for all pages, test users matching mock OIDC |
| 14 | Standard UI | Breadcrumbs, DataTable, QuickSearch, ModeToggle |

## Security Architecture

### Tiered Guardrail System

Security guardrails are organized into tiers. **Tier 0 is mandatory for every project.** Higher tiers activate based on project type.

**Tier 0 -- Universal (all projects):**
- No secrets in committed files (.env gitignored, .env.example with placeholders)
- No hardcoded config values (all from environment variables)
- Input validation at system boundaries
- Sensitive data masked in output
- Latest stable dependencies with no known CVEs
- No Java runtime dependencies (policy)

**Tier 1 -- Web App (in addition to Tier 0):**
- OIDC authentication (never custom password management)
- Database-driven RBAC with `require_permission(resource, action)` middleware
- 4 system roles seeded: Super Admin, Admin, Manager, User
- Same-origin proxy pattern (Next.js rewrites to backend)
- httpOnly, Secure, SameSite cookies for JWT tokens
- Security headers (Helmet/equivalent)
- System fonts only (no external CDN calls -- Zscaler-safe)

### AI Safety Controls

When an app uses AI features, /make-it implements a comprehensive safety stack:

**Runtime Controls (Prompt #10e Parts 1-8):**

| Control | Module | Purpose |
|---------|--------|---------|
| Input Sanitization | `lib/ai/sanitize.ts` | Strips injection patterns, wraps user input in `<user_input>` delimiter tags |
| Output Validation | `lib/ai/validate.ts` | Validates AI responses against schemas + value ranges before storage |
| Rate Limiting | `lib/ai/rate-limit.ts` | Per-user request and token budget on AI endpoints |
| PII Masking | `lib/ai/pii-masker.ts` | Pseudonymizes names, emails, phones, financials before AI submission |
| Error Sanitization | `lib/ai/errors.ts` | Maps provider errors to generic safe messages (no key/model leakage) |
| Prompt Size Validation | BaseAgent | Rejects prompts exceeding `AI_MAX_PROMPT_CHARS` |
| System Prompt Hardening | All agents | Anti-injection/anti-jailbreak instructions appended to every system prompt |
| Conversation History | BaseAgent | Server-side storage, max depth, session isolation |

**Prompt Template Content Validation (Prompt #10e Part 9 -- Tier 2/3 only):**

When administrators can edit AI prompts through the UI, the saved content becomes part of the system prompt at runtime. This creates a supply-chain injection surface that requires dedicated protection:

| Control | Purpose |
|---------|---------|
| `validatePromptTemplate()` | Hybrid blocklist on save -- blocks injection overrides, code injection, encoded payloads, preamble tampering |
| Immutable Safety Preamble | Locked safety instructions auto-prepended at runtime. Admin UI never shows it. No code path skips it. |
| Draft/Test/Publish Workflow | New edits save as draft. Test button runs blocklist + sanitize + test cases + mini NeMo check. Publish only enabled after all tests pass. |
| `renderPromptSafe()` | Sanitizes ALL template variable values via `sanitizePromptInput()` before interpolation. Escapes HTML entities. |
| `testPromptDraft()` | Mandatory test gate: validation + 5 adversarial NeMo inputs against draft prompt |
| Risk Warnings | Friendly yellow banners for suspicious patterns (no jargon). Overrides logged with `risk_flag` for security review. |
| /ship-it Integration | PR description flags `risk_flag` audit entries as "Prompt Safety Review Required" |

**NeMo Guardrails AI Safety Testing (Prompt #10d):**

Every AI-powered app gets a NeMo Guardrails test suite covering 6 categories:

| Category | What It Tests | Minimum Cases |
|----------|--------------|--------------|
| Prompt Injection | Can adversarial input override system instructions? | 10 |
| Jailbreak | Can the AI be convinced to operate outside boundaries? | 10 |
| Toxicity/Bias | Does the AI produce harmful or biased content? | 10 |
| Topic Boundaries | Does the AI stay within its intended domain? | 10 |
| PII Leakage | Does the AI reveal personal or system information? | 10 |
| Hallucination | Does the AI generate false or fabricated information? | 10 |

### AI Prompt Management Tiers

Prompt management scales with the app's AI complexity:

| Tier | When | Storage | UI | Validation |
|------|------|---------|-----|------------|
| 1 (Minimal) | 1-3 prompts, devs only | Code + env var override | None | N/A |
| 2 (Moderate) | 4-10 prompts, product team edits | 3 DB tables + admin UI | Edit, test, version diff, rollback | `validatePromptTemplate()` + draft/publish + immutable preamble |
| 3 (Heavy) | 10+ prompts, AI-native app | 6 DB tables + 5 pages | Full platform: registry, editor, analytics, audit | All Tier 2 controls + import validation + system prompt locking + risk escalation |

## Build-Verify Quality Gate

Before the user ever sees their app, /make-it runs a comprehensive verification:

**Part A -- Static Code Verification (24 checks):**
- Project structure completeness
- No stub endpoints or hardcoded mock data
- Database migrations exist
- .env/.env.example properly configured
- Mock services wired in docker-compose
- Standard UI components present and integrated
- Seed data populates all pages
- Auth callback reads roles from database (not OIDC claims)
- Same-origin proxy pattern correct
- Frontend types match backend schemas
- AI safety controls wired (if AI features)
- Prompt template validation controls wired (if Tier 2/3 prompts)

**Part B -- Live Verification (after Docker startup):**
- All containers healthy
- Mock services seeded
- Auth flow works for every role (correct permissions from database)
- Every API endpoint returns data
- Every page loads with content
- Permission boundaries enforced
- Logout clears JWT cookie

**Part C -- Automated Fix Cycle:**
- If any test fails: diagnose, fix, rebuild, retest (up to 3 cycles)
- Common fixes applied automatically (port conflicts, env var mismatches, migration syntax)

## Scaffold: FastAPI + Next.js

The primary scaffold provides battle-tested, internally-consistent code for web apps:

**Backend (FastAPI + SQLAlchemy + Alembic):**
- OIDC auth flow (login, callback, logout, /auth/me)
- RBAC middleware (`require_permission`)
- User, Role, Permission models with relationships
- Alembic migration for RBAC schema
- Pydantic schemas for request/response validation
- Entrypoint script (wait for DB, run migrations, start server)

**Frontend (Next.js + Tailwind + Radix UI):**
- Authenticated layout with sidebar, header bar
- Login page with OIDC redirect
- Admin pages: User Management, Role Management
- Dashboard with widget placeholders
- Standard components: Breadcrumbs, DataTable, QuickSearch, ModeToggle
- Auth context with `useAuth()` hook and `hasPermission()` checks
- API client with same-origin proxy pattern

**Infrastructure:**
- `docker-compose.yml` with profiles (dev, test)
- PostgreSQL database container
- Mock OIDC provider (Python, in-memory)
- Seed script for mock services
- `.env.example` with all required variables

**Placeholders replaced during build:**
`[APP_NAME]`, `[APP_SLUG]`, `[APP_TAGLINE]`, `[APP_ICON]`, `[FRONTEND_PORT]`, `[BACKEND_PORT]`, `[DB_PORT]`, `[MOCK_OIDC_PORT]`, `[NAV_ITEMS]`, `[SEGMENT_LABELS]`, `[NAVIGATION_ITEMS]`, `[DASHBOARD_WIDGETS]`, `[DOMAIN_ROUTERS]`, `[DOMAIN_TYPES]`

## Templates

### app-context.json

The single source of truth for all design decisions. Populated during ideation and design, consumed by all 14 build prompts. Key sections:

- `project_name`, `purpose`, `project_type`, `active_tiers`
- `users` -- types, count, internal/external
- `auth` -- provider, token expiry
- `roles` and `permissions` -- RBAC configuration
- `stack` -- frontend, backend, database, ORM, language
- `ai_features` -- usage level, prompts, agents, models, management tier
- `ai_providers` -- primary/fallback, model tiers, provider config
- `nemo_guardrails` -- categories, topic domain, attestation mode
- `mock_services` -- which mocks needed, ports, test users
- `deployment` -- target environment, containerization, networking
- `security_scanner` -- optional integration for continuous scanning

### nemo-it-attestation.md (v1.1.0)

Template for security attestation reports generated by /nemo-it. Includes:

- Executive summary with posture rating
- OWASP Top 10 coverage matrix
- Findings by severity with full analysis (what, where, how, root cause, risk matrix, remediation)
- AI Safety Assessment (6 NeMo Guardrails categories)
- Dependency health summary
- **Secure-by-Design Coverage** -- cross-references each finding against /make-it guardrails:
  - Prevention Classification (Prevented / Reduced / Not covered)
  - Finding Prevention Matrix
  - AI Safety Prevention Summary (12 control checks)
  - Coverage Statistics (prevention rate, critical/high findings prevented)

## Environment Variables (AI Features)

When AI features are enabled, these environment variables are added to `.env.example`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `AI_PROVIDER` | (required) | AI provider name (throws error if missing) |
| `AI_RATE_LIMIT_REQUESTS_PER_MINUTE` | 20 | Per-user request limit on AI endpoints |
| `AI_RATE_LIMIT_TOKENS_PER_MINUTE` | 50000 | Per-user token budget |
| `AI_MAX_PROMPT_CHARS` | 100000 | Max prompt length before AI submission |
| `AI_MAX_DOCUMENT_CHARS` | 500000 | Max document length for analysis features |
| `AI_MAX_HISTORY_TURNS` | 20 | Max conversation history depth |
| `AI_PII_MASKING_ENABLED` | true | Enable PII pseudonymization for external AI |

## Deployment (/ship-it Integration)

When the user types `/ship-it`, the deployment pipeline:

1. Detects repo, branch, auth status, project type
2. Reads `.ship-it.yml` config
3. Scans dependencies for vulnerabilities (auto-fixes where possible)
4. Runs NeMo Guardrails full test suite (if AI features) -- 60+ test cases
5. **Checks prompt template safety** (if Tier 2/3) -- flags `risk_flag` audit entries for security review
6. Generates AI Safety Attestation
7. Creates branch, commits (including security fixes + attestation), pushes
8. Generates CI/CD caller workflow
9. Creates PR with labels, reviewers, security summary, go-live checklist
10. Reports back to user

The user's entire deployment experience is typing `/ship-it` and waiting.

## Retrofit (/retrofit-it Integration)

For existing apps not built by /make-it, `/retrofit-it` can add production foundations:

- OIDC authentication + database-driven RBAC
- Docker orchestration with mock services
- Standard UI components
- AI prompt management (Tier 2/3)
- AI operational safety controls (Parts 1-9 of Prompt #10e)
- Security hardening

Risk-scored to determine single-pass vs phased retrofit with user verification between phases.

## Version History

### v1.3.0 (2026-03-19) -- Prompt Template Content Validation
- Added `validatePromptTemplate()` content blocklist for admin-editable prompts
- Added immutable safety preamble (auto-prepended, invisible to admin UI)
- Added draft/test/publish workflow (mandatory testing before activation)
- Added `renderPromptSafe()` with variable interpolation sanitization
- Added `testPromptDraft()` with mini NeMo Guardrails safety check
- Added risk_flag audit logging with /ship-it PR integration
- Updated Prompts #10b, #10c, #10e (Part 9), #11
- Updated guardrails.md with 10 new build-verify checks
- Updated design-blueprint.md Section 10a architecture
- Updated ship-it-guide.md with prompt safety review gate
- Updated retrofit-it.md Steps 11j-m and Step 4.5
- Updated nemo-it cross-reference classification (3 new entries)

### v1.2.0 (2026-03-19) -- AI Operational Safety Controls
- Added Prompt #10e (8 parts): sanitize, validate, rate-limit, size, PII, errors, hardening, history
- Added `lib/ai/` module architecture to design-blueprint.md Section 11b
- Added AI Operational Safety Controls section to guardrails.md
- Added consolidated AI Build-Verify Checklist
- Updated prompt-templates.md Prompt #11 for safety control verification
- Updated retrofit-it.md with Phase F2 + Step 11 + Step 4.5
- Updated nemo-it attestation template with Secure-by-Design cross-reference (v1.1.0)
- Updated both nemo-it.md skill files with Step 6 classification logic

### v1.1.0 -- NeMo Guardrails Integration
- Added Prompt #10d: NeMo Guardrails AI safety testing
- Added 6-category test suite (prompt injection, jailbreak, toxicity, topic, PII, hallucination)
- Added AI Safety Attestation template
- Added /ship-it NeMo Guardrails pre-deploy gate

### v1.0.0 -- Initial Release
- 5-phase build process (preflight, ideation, design, build, ship)
- FastAPI + Next.js scaffold with OIDC auth and database-driven RBAC
- 14 build prompts with tiered guardrails (6 project types)
- Mock services for offline development
- Standard UI components (Breadcrumbs, DataTable, QuickSearch, ModeToggle)
- Build-verify quality gate with automated fix cycle
- /ship-it deployment pipeline integration
