# TODO -- make-it Framework

## High Priority

_All high priority items completed._

## Medium Priority

### /resume-it: Sync changes from repo to installed location
Currently, skill files live in both `~/.claude/` (installed) and the make-it repo
(source of truth). Changes to the repo must be manually copied. Consider:
- A sync script that copies from repo to ~/.claude/
- Or using symlinks so the installed version always reads from the repo

### Kubernetes / Argo CD deployment support (`/make-it k8s`)
Add a `k8s` (or `argo`) flag to `/make-it` that generates K8s deployment manifests
alongside the existing Docker Compose setup. Local dev stays Docker Compose; K8s
manifests are an additional production artifact.

**Onboarding prerequisites (before first deploy):**
- Submit a story to get team onboarded to Argo CD + Rancher
- AD group access granted after onboarding:
  - `rancher<dev/prd>_teamname_SSO`
  - `argocd<dev/prd>_teamname_SSO`
- SNOW request to get privileges in the AD group

**Team answers (resolved):**
1. **Helm vs Kustomize:** User's choice — Argo CD supports both. Ask during ideation.
2. **Registry:** ghcr.io (SleepNumber GitHub Corp). Other registries possible but
   team projects are scoped to SleepNumber GitHub org.
3. **Namespace strategy:** Each team gets a project + namespace (e.g.,
   `security-engineering-project`). Apps stay in the team namespace by default.
   New namespaces can be requested if something warrants isolation (e.g., a
   shared connector). Request to create additional namespaces.
4. **Secrets management:** Currently manual creation in Rancher before use.
   External Secrets Operator is the future target (per-project external secret
   store with service account scoped to Secret Server folder) but not yet
   onboarded for all teams.

**DevOps integration (from Argo team):**
- `/ship-it` (or GitHub Actions + Claude) creates the Argo CD Application resource
  directly — no manual Argo UI step needed
- Requires a **service account token** scoped to the team's Argo CD project for RBAC
- `/make-it k8s` or `/ship-it` prompts user for:
  1. Argo CD service account token (stored in `.env`, never committed)
  2. Namespace (or default to team naming convention: `teamname-project`)
- Once the Argo Application is created and pointed at the Git repo, Argo handles
  deployment automatically on every push
- Flow: `/make-it k8s` builds app + generates manifests → `/ship-it` pushes to Git
  → GitHub Actions builds + pushes images to ghcr.io → `/ship-it` creates Argo
  Application via API using service account token → Argo syncs and deploys

**DevOps requirements (from Argo/infra team):**
- Need solid templates for Services, IngressRoutes, etc. — these vary per app
- IngressRoutes are especially variable (different routing rules per app)
- Traefik is the ingress controller — requires host matching URL (e.g., `app1.comfort.com`)
- `/make-it k8s` must prompt for or derive the hostname for IngressRoute
- Once External Secret Store is set up: secrets go in Secret Server (SS), their
  IDs are placed in ExternalSecret manifests. Until then, secrets are manual in Rancher.
- TLS/cert management needs to be sorted for HTTPS apps (cert-manager? Traefik TLS
  passthrough? Wildcard cert from org CA?)

**Open questions for DevOps:**
1. Is there a standard wildcard cert (e.g., `*.comfort.com`) or do apps request
   individual certs? Is cert-manager in use?
2. Are there existing IngressRoute examples we can use as reference templates?
3. For the ExternalSecret manifest — what's the Secret Server ID format? Is there
   a standard manifest structure the team already uses?
4. Any Traefik middleware in use (rate limiting, auth forwarding, IP allowlisting)?

**Design decisions already made:**
- Flag approach, not separate skill (`/make-it k8s`)
- Sets `deployment.target: "argocd"` in app-context.json
- Build phase identical — same scaffold, same Docker Compose for local dev
- Extra step at end generates: `k8s/` directory (Deployments, Services, ConfigMap,
  Secrets template, Ingress), `argocd/application.yml`, DB migration as K8s Job
- `/ship-it` detects target and creates Argo Application via API (not just Git push)
- Docker Compose always present for local dev, `/try-it`, and build-verify
- Ask user "Helm or Kustomize?" as part of the k8s flag flow
- Generate GHCR push workflow (GitHub Actions) for container images
- Include ONBOARDING.md with step-by-step for AD group access + SNOW request
- Service account token + namespace stored in `.env` (gitignored), documented
  in `.env.example` as `ARGOCD_TOKEN` and `ARGOCD_NAMESPACE`

## High Priority (RBAC & Identity)
- [ ] Determine RBAC model: Object_ID-based vs Application-based RBAC
  - Object_ID-based RBAC requires external setup steps outside the container:
    - Register app in Entra ID (Azure AD)
    - Obtain Object_ID and configure role assignments
    - Store secrets in Secret Server
    - Document the manual Entra ID + Secret Server steps for business users
  - Application-based RBAC may be self-contained within the app
  - /make-it and /ship-it should detect which model the app uses and guide accordingly

## High Priority (Deployment)
- [ ] Automate end-to-end app deployment via /ship-it or /argo-it
  - User should do absolute bare minimum to get their app from local to dev to production
  - /ship-it: commit, push, create PR, trigger CI/CD -- all in one command
  - /argo-it: ArgoCD-based deployment pipeline for Kubernetes environments
  - Auto-detect deployment target (Docker Compose, K8s, cloud run, etc.)
  - Auto-generate Dockerfile, Helm chart, or manifests if missing
  - Auto-configure GitHub Actions or ArgoCD pipeline
  - Handle secrets/env vars promotion across environments (dev -> staging -> prod)
  - Provide plain-English deployment status ("Your app is live at https://...")

## Low Priority

_All low priority items completed._

## Completed

### Populate Next.js full-stack scaffold template files ✓
Created 60 template files for `scaffolds/nextjs-fullstack/` with `[BRACKET_PLACEHOLDER]`
values. Includes: Prisma schema + seed (RBAC 4-table model), auth (jose JWT, OIDC with
state parameter, Next.js 16 Set-Cookie workaround, ENFORCE_SECRETS pattern), middleware,
15 API routes (auth, users, roles, permissions, settings with audit log, dashboard),
10 standard UI components (sidebar, data-table with 4 sub-components, breadcrumbs,
quick-search, mode-toggle, theme-provider, login-button), 5 page templates (dashboard,
users, roles, settings, login), Docker (multi-stage Dockerfile, 3-service compose),
config files (package.json, next.config.ts, tsconfig, tailwind, postcss), entrypoint.sh
(prisma migrate + seed), seed-mock-services.sh, and mock-oidc (copied as-is from
fastapi-nextjs). Updated README status to COMPLETE.

### /nemo-it: Standalone security attestation skill ✓
Created /nemo-it as a completely separate skill from /make-it and /ship-it. Scans any
project against NeMo Guardrails AI safety (6 categories) and OWASP Testing Guide (all 11
categories). Uses pytest, Playwright, OWASP ZAP, semgrep, Bandit/ESLint, Trivy, SQLMap
(passive), npm audit, and pip-audit. Non-destructive testing only -- detects susceptibility
without exploiting. Generates versioned attestation at docs/attestations/nemo-it/YYYY-MM-DD-vN.md
with executive summary, risk matrix (likelihood x impact), compensating controls, and
OWASP Top 10 mapping. Optional JSON and JUnit XML output for CI/CD. Preflight auto-installs
missing tools with user consent. Created: nemo-it.md (skill), owasp-testing-guide.md
(reference), nemo-it-attestation.md (template). Updated: README.md.

### NeMo Guardrails -- AI Safety Testing integration ✓
Added NeMo Guardrails as mandatory AI safety gate for all AI-powered apps. 6 test
categories (prompt injection, jailbreak, toxicity/bias, topic boundaries, PII leakage,
hallucination). Basic suite (18 tests) runs during build-verify, full suite (60 tests)
runs during /ship-it. Self-healing remediation loop. Attestation template generates
GRC-required sign-off document in docs/. Updated: guardrails.md, design-blueprint.md
(section 11), prompt-templates.md (Prompt #10d), app-context.md (nemo_guardrails config),
ship-it-guide.md (pre-ship gate), README.md. Created: templates/ai-safety-attestation.md.

### /retrofit-it: Plain-language phase presentation ✓
Rewrote Phase 4 (Plan) and Phase 5b (Phased retrofit) to use user-friendly language.
Phase table now has "User-Facing Name" column. Internal labels only in state files.

### Add Multi-Provider AI Pattern to skill references ✓
Added to: design-blueprint.md (section 9), guardrails.md, app-context.md (ai_providers),
prompt-templates.md (Prompt #10-provider). Covers provider abstraction layer, model
tiering (heavy/standard/light), env var configuration, and supported providers
(anthropic_foundry, anthropic, openai, ollama).

### Add OIDC/RBAC Reference Implementation to skill references ✓
Added to: design-blueprint.md (OIDC flow diagram + critical auth rules),
guardrails.md (expanded auth checklist with permission service, cache invalidation,
cookie Secure from URL, anti-patterns), retrofit-it.md (references blueprint patterns).

### /retrofit-it: Automated risk score calibration ✓
Added calibration table with TPRMAI as first real-world data point (score ~40, phased
strategy, auth bugs caught in verification). Added lessons learned for each change type.

### Scaffold for Next.js full-stack (nextjs-fullstack) ✓
Created scaffold directory with comprehensive README. Architecture, placeholders, and
auth/RBAC patterns documented. Template files flagged for population from TPRMAI.
Updated app-context.md scaffold selection logic.

### /retrofit-it: Pre-retrofit snapshot ✓
Added git tag creation (`pre-retrofit`) after user approves the plan. Commits
uncommitted changes first if needed. Provides guaranteed rollback point.

### Auth callback redirect + cookie Secure flag guardrails ✓
Added to guardrails.md Build-Verify section: callback must use EXTERNAL frontend URL,
cookie Secure flag from URL protocol not NODE_ENV, live auth flow smoke test with
6 assertions and self-healing loop.

### AI Prompt Management detection in /resume-it ✓
Added step 7 to resume-it.md: scans for hardcoded prompts, checks for managed_prompts
table, suggests Tier 2/3 prompt management if gaps found.

### AI Prompt Management phase in /retrofit-it ✓
Added Phase F (AI Prompts) to gap analysis and phased retrofit. Added step 10
(AI Prompt Management) to single-pass retrofit sequence.

### AI Operational Safety Controls (v1.2.0) ✓
Added runtime safety stack for every AI invocation, closing 6 gaps found during
TPRMAI security attestation. Prompt #10e (8 parts): input sanitization, output
validation, rate limiting, prompt size validation, PII masking, error sanitization,
system prompt hardening, conversation history management. lib/ai/ module architecture
in design-blueprint.md. AI Build-Verify Checklist in guardrails.md. Phase F2 + Step 11
in retrofit-it.md. Secure-by-Design cross-reference in nemo-it attestation template
(v1.1.0). Updated: guardrails.md, design-blueprint.md, prompt-templates.md,
retrofit-it.md, nemo-it-attestation.md, both nemo-it.md files.

### Activity Logs -- In-Memory Observability (v1.4.0) ✓
New standard component for every web app. Circular buffer LogStore captures all
inbound API requests and outbound HTTP calls with no external dependencies. LogService
singleton, request/outbound middleware, URL sanitization (strips tokens/keys from query
params), RBAC-gated admin UI (stats cards, filters, auto-refresh, clear buffer). Added:
design-blueprint.md (Section 9a -- architecture + middleware + admin UI spec),
guardrails.md (Activity Logs checklist + tier matrix entry), prompt-templates.md
(Prompt #9c with full implementation spec for any stack).

### AI Prompt Template Content Validation (v1.3.0) ✓
Protects admin prompt editing surface against supply-chain injection. validatePromptTemplate()
hybrid blocklist, immutable safety preamble (runtime-prepended, invisible to UI), draft/test/
publish workflow with mandatory testing, renderPromptSafe() with variable interpolation
sanitization, testPromptDraft() with mini NeMo check, risk_flag audit logging with /ship-it
PR integration. Updated: guardrails.md (10 new build-verify checks), design-blueprint.md
(Section 10a), prompt-templates.md (Part 9 + #10b/#10c/#11), ship-it-guide.md (step 6),
retrofit-it.md (Steps 11j-m + Step 4.5), both nemo-it.md files (3 new classification entries).
README.md updated with AI Security Architecture section.
