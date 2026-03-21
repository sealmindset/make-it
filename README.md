# /make-it

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill suite that takes anyone from an app idea to a fully working application through guided conversational Q&A. No programming knowledge required.

You describe what you want in plain English. The skills handle everything else -- technical decisions, code generation, testing, and deployment. Already have an app? `/retrofit-it` upgrades it with production-ready foundations.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Updating](#updating)
- [Skills Overview](#skills-overview)
- [How /make-it Works](#how-make-it-works)
- [How /try-it Works](#how-try-it-works)
- [How /resume-it Works](#how-resume-it-works)
- [How /retrofit-it Works](#how-retrofit-it-works)
- [How /nemo-it Works](#how-nemo-it-works)
- [How /fix-it Works](#how-fix-it-works)
- [What Gets Built](#what-gets-built)
- [AI Security Architecture](#ai-security-architecture)
- [Supported Project Types](#supported-project-types)
- [Architecture](#architecture)
- [Build Quality](#build-quality)
- [Deployment Lifecycle](#deployment-lifecycle)
- [FAQ](#faq)
- [Related Skills](#related-skills)
- [Version History](#version-history)
- [License](#license)

---

## Quick Start

```bash
# 1. Install Claude Code (if you haven't already)
npm install -g @anthropic-ai/claude-code

# 2. Install the skills (one command -- no clone needed)
curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash

# 3. Go to where you want your new project
cd ~/Documents/GitHub

# 4. Start Claude Code and build your app
claude
> /make-it
```

That's it. Answer the questions, and your app gets built.

---

## Installation

### Prerequisites

Before running `/make-it`, you need these tools on your machine. The skill checks for them automatically during its Preflight phase and guides you through anything missing.

#### Required

| Tool | Purpose | Install |
|------|---------|---------|
| **Claude Code** | AI coding assistant (the runtime for these skills) | `npm install -g @anthropic-ai/claude-code` |
| **Git** | Version control | `brew install git` (macOS) or [git-scm.com](https://git-scm.com/) |
| **Docker Desktop** | Runs your app and services locally in containers | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) or Rancher Desktop |
| **GitHub CLI** | Pushes code and creates pull requests | `brew install gh` then `gh auth login` |
| **VS Code** | Code editor (optional but recommended) | `brew install --cask visual-studio-code` |

#### Enterprise / Optional (auto-detected)

| Tool | When Needed |
|------|-------------|
| Cloud CLI (Azure, AWS, or GCP) | Only if deploying to a cloud provider |
| VPN access | If your organization requires VPN for GitHub or cloud access |
| SSL proxy awareness | If behind Zscaler, Netskope, or GlobalProtect -- the skill detects this and walks you through it |

### Install Steps

#### Option A: One-Line Install (recommended)

No clone needed. Just run:

```bash
curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash
```

This downloads the latest release and installs all skills into `~/.claude/`.

#### Option B: Clone and Install

```bash
git clone https://github.com/sealmindset/make-it.git
cd make-it
bash install.sh
```

#### Option C: Manual Install

```bash
# Clone the repo
git clone https://github.com/sealmindset/make-it.git ~/.claude/make-it-repo

# Create the commands directory if it doesn't exist
mkdir -p ~/.claude/commands

# Copy all skill entry points
cp ~/.claude/make-it-repo/.claude/commands/make-it.md ~/.claude/commands/
cp ~/.claude/make-it-repo/.claude/commands/try-it.md ~/.claude/commands/
cp ~/.claude/make-it-repo/.claude/commands/resume-it.md ~/.claude/commands/
cp ~/.claude/make-it-repo/.claude/commands/retrofit-it.md ~/.claude/commands/
cp ~/.claude/make-it-repo/.claude/commands/nemo-it.md ~/.claude/commands/
cp ~/.claude/make-it-repo/.claude/commands/fix-it.md ~/.claude/commands/

# Copy the references, templates, and scaffolds
cp -r ~/.claude/make-it-repo/.claude/make-it ~/.claude/make-it
cp -r ~/.claude/make-it-repo/.claude/nemo-it ~/.claude/nemo-it
```

### Verify Installation

```bash
claude
```

Inside Claude Code, type `/make-it` -- you should see the skill activate and greet you. Type `/try-it`, `/resume-it`, `/retrofit-it`, `/nemo-it`, or `/fix-it` to verify those are available too.

### Updating

The easiest way to update is from inside Claude Code:

```
> /make-it update
```

This checks your installed version against the latest release, downloads and installs any updates (including new skills), and tells you what changed. You just need to restart Claude Code afterward.

You can also update from the terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash
```

Or if you have the repo cloned:

```bash
cd ~/path/to/make-it
git pull
bash install.sh
```

---

## Skills Overview

| Skill | What It Does | When to Use It |
|-------|-------------|----------------|
| `/make-it` | Builds a new app from scratch through conversational Q&A | Starting a brand new project |
| `/make-it update` | Updates all installed skills to the latest version | When you want the latest features and fixes |
| `/try-it` | Spins up your app locally, tests everything, lets you explore in the browser | After `/make-it` finishes, or anytime you want to see your app running |
| `/resume-it` | Picks up where you left off -- add features, fix bugs, run tests, deploy | Any time after the initial build |
| `/retrofit-it` | Upgrades an existing app with production foundations (auth, RBAC, Docker, security) | You have an app that works but needs enterprise-grade infrastructure |
| `/nemo-it` | Scans any app for security vulnerabilities (OWASP + NeMo AI safety) and generates an attestation report | Security assessment of any project -- standalone, not tied to /make-it |
| `/fix-it` | Automatically fixes security findings from a `/nemo-it` attestation report | After `/nemo-it` identifies vulnerabilities you want to resolve |

---

## How /make-it Works

`/make-it` guides you through five phases. You only interact during the first two -- the rest happens automatically.

### Phase 0: Preflight

The skill silently checks your machine:

- Git, Docker, GitHub CLI, VS Code installed?
- Docker running?
- GitHub authenticated?
- Behind a corporate SSL proxy (Zscaler, Netskope)?

If everything is green, you move straight to Ideation. If something is missing, the skill tells you exactly what to install and how -- in plain language, not jargon.

### Phase 1: Ideation

A friendly conversation to understand your app idea. The skill asks **one question at a time**:

- "What problem does this solve?"
- "Who's going to use it?"
- "What are the 3-5 most important things it should do?"
- "What do you want to call your app?"

It listens for signals like:
- Multiple user types (admins vs. regular users) -- triggers role/permission design
- External systems (Jira, Salesforce, Oracle) -- triggers mock service generation
- AI features -- triggers prompt management architecture
- Enterprise context -- triggers compliance and security considerations

When it has enough information, it summarizes your app idea and asks you to confirm.

### Phase 2: Design

All technical decisions happen behind the scenes. You may be asked 1-3 clarifying questions:

- "Should users log in with their company account or create their own?"
- "What can admins do that regular users can't?"
- "Is this for real users soon, or a first version to test the idea?"

Everything else is decided automatically:
- Tech stack (framework, database, ORM)
- Authentication provider
- Role and permission structure
- Page layout and navigation
- Mock services needed for local development
- Infrastructure requirements

The result is saved as `app-context.json` -- a complete blueprint for the Build phase.

### Phase 3: Build

The skill generates your entire application:

- **For web apps with Python backends**, it starts from a pre-built scaffold (FastAPI + Next.js) that includes proven auth, RBAC, Docker, and UI patterns. Domain-specific code (your pages, APIs, and data models) is generated on top.
- **For web apps with Node.js full-stack** (Next.js API routes), it uses the Next.js full-stack scaffold -- same auth, RBAC, and Docker patterns but with Prisma ORM and a single container instead of separate frontend/backend services.
- **For all other project types**, everything is generated from 14 enterprise prompt templates.

You see progress updates like "Setting up your project structure..." and "Designing your pages..." but never raw code or error messages.

After generation, **build-verify** runs silently:
1. Starts the app in Docker
2. Tests login as every user role
3. Visits every page and API endpoint
4. Verifies permissions are enforced
5. Fixes any issues it finds (up to 3 cycles)

### Phase 4: Ship

When you're ready to deploy, the skill hands off to `/ship-it` for CI/CD. You just type the command -- the skill handles commits, pull requests, and deployment automation.

### What You Experience

```
You:     "I want to build a tool for my team to track project forecasts"
make-it: "Great! Who's going to use this?"
You:     "About 20 people -- managers submit forecasts, directors review them"
make-it: "What are the most important things it should do?"
You:     "Submit weekly forecasts, dashboard with charts, export to Excel"
make-it: "What do you want to call it?"
You:     "ForecastHub"
make-it: "Here's what I understood: [summary]. Sound right?"
You:     "Yes!"
make-it: "Building ForecastHub..."
         ... progress updates for a few minutes ...
         "Your app is ready! Opening it in your browser now."
```

---

## How /try-it Works

`/try-it` presents your app for hands-on exploration. When called after `/make-it`, the app is already running. When called standalone, it starts the app first.

### What It Does

1. **Context Discovery** -- Reads your project configuration, checks if containers are already running
2. **Startup** -- Builds and starts Docker containers if needed; resolves port conflicts automatically
3. **Smoke Test** -- Logs in as each user role, visits every page, takes screenshots, checks permissions
4. **Fix** -- If anything fails, diagnoses and fixes it automatically (safety net -- rarely needed after build-verify)
5. **Report** -- Generates `TRY-IT-REPORT.md` with test results, screenshots, and access instructions
6. **Handoff** -- Tells you exactly how to open your app in the browser and what credentials to use

### Usage

```bash
# After /make-it (automatic -- it chains into /try-it)
# Or standalone:
cd ~/Documents/GitHub/my-app
claude
> /try-it
```

### What You Get

- Your app running at `http://localhost:<port>` with all services healthy
- Test credentials for every user role (e.g., admin, manager, user)
- Screenshots of every page from every role's perspective
- A report documenting what works and any known issues

If you spot anything that doesn't look right while exploring, just describe it:

```
You: "The forecast chart on the dashboard is empty"
```

The skill diagnoses the issue and fixes it without you touching any code.

---

## How /resume-it Works

`/resume-it` picks up where `/make-it` left off. Run it from inside your project directory.

### What It Does

1. **Context Discovery** -- Reads project state, changelog, TODOs, git history, and any security scanner findings
2. **Security Remediation** -- Auto-fixes security scan findings (invisible to you unless app behavior changes)
3. **Greet + Suggest** -- Shows where things stand and suggests next actions
4. **Work** -- Helps with whatever you need: new features, bug fixes, TODO items, or anything you describe
5. **Readiness Check** -- Ask "what's next?" to get a standup-style assessment:
   - **What's done** -- completed work since last session
   - **What's blocked** -- tickets, infrastructure, or env vars needed from other teams
   - **What's next** -- actionable items you can do right now
   - Generates a shareable `NEXT-STEPS.md` checklist
6. **Test** -- Scaffolds automated tests (pytest for backend, Playwright for frontend) and runs them
7. **Ship** -- Hands off to `/ship-it` when ready

### Usage

```bash
cd ~/Documents/GitHub/my-app
claude
> /resume-it
```

### Example Interactions

```
resume-it: "Welcome back to ForecastHub! Here's where things stand:
            - 12 pages built, all passing
            - 3 TODO items remaining
            - Suggestion: Add the Excel export feature"

You:       "Let's add the Excel export"
resume-it: [builds the feature, tests it, updates changelog]

You:       "What's next?"
resume-it: [generates NEXT-STEPS.md with infrastructure checklist]

You:       "Run the tests"
resume-it: [scaffolds pytest + Playwright if first time, runs all tests]
```

---

## How /retrofit-it Works

`/retrofit-it` upgrades an existing application with production-ready foundations. Unlike `/make-it` (which builds from scratch), `/retrofit-it` reverse-engineers your app first, then adds what's missing surgically.

### When to Use It

- You have a working app but it lacks proper authentication, RBAC, or Docker setup
- Your app was built outside of `/make-it` and you want to bring it up to the same standard
- You want to add enterprise foundations (OIDC login, role-based permissions, mock services) to an existing codebase

### What It Does

1. **Discovery** -- Scans your codebase to understand what's already built: framework, database, auth, folder structure, AI features
2. **Gap Analysis** -- Compares what you have against the make-it guardrails and identifies what's missing
3. **Risk Score** -- Calculates a risk score (0-100) based on the size and complexity of changes needed. Calibrated with real-world retrofit data
4. **Plan** -- Presents the upgrade plan in plain language with phases like "Setting up your development environment" and "Adding secure login and user permissions"
5. **Pre-retrofit Snapshot** -- Creates a git tag (`pre-retrofit`) so you can always roll back
6. **Retrofit** -- Applies changes in safe, verifiable phases. Each phase is tested before moving to the next
7. **Verify** -- Runs the same build-verify checks as `/make-it` to ensure everything works

### Two Retrofit Modes

- **Phased retrofit** (recommended for higher risk scores) -- applies changes in 5 ordered steps, each verified before proceeding
- **Single-pass retrofit** (for lower risk scores) -- applies all changes at once with a comprehensive verification pass

### Usage

```bash
cd ~/Documents/GitHub/my-existing-app
claude
> /retrofit-it
```

### What Gets Added

Depending on what's missing, `/retrofit-it` can add:

- Environment-based configuration (`.env`, Docker Compose)
- Database migrations and RBAC tables (roles, permissions, users)
- OIDC authentication with your chosen provider
- Standard UI components (DataTable, Breadcrumbs, QuickSearch, ModeToggle)
- Mock services for external integrations
- AI prompt management (if your app uses AI features)
- AI operational safety controls: input sanitization, output validation, rate limiting, PII masking, error sanitization, system prompt hardening (if your app uses AI features)
- AI prompt template validation: content blocklist, immutable preamble, draft/publish workflow, variable sanitization (if Tier 2/3 prompt management)
- Security headers, input validation, and deployment prep

---

## How /nemo-it Works

`/nemo-it` is a standalone security attestation skill that scans any application -- not just apps built by `/make-it`. It reports findings but never fixes them. Think of it as a security audit that produces a detailed report.

### Scan Modes

| Command | What It Scans |
|---------|--------------|
| `/nemo-it` or `/nemo-it full` | Everything: NeMo AI safety + OWASP + Dependencies + Static Analysis |
| `/nemo-it guardrails` | NeMo Guardrails AI safety testing only (6 categories) |
| `/nemo-it owasp` | OWASP Testing Guide (all 11 categories) + dynamic analysis |
| `/nemo-it deps` | Dependency vulnerabilities + container image scanning |
| `/nemo-it sast` | Static code analysis only (no running app needed) |

### What It Does

1. **Preflight** -- Detects your project type, installs security tools (with permission), checks if the app is running
2. **Static Analysis** -- Scans source code with semgrep, Bandit (Python), ESLint security (JS/TS) for vulnerability patterns
3. **Dependency Scanning** -- Runs npm audit, pip-audit, and Trivy to find vulnerable libraries and container images
4. **Dynamic Analysis** -- Tests the running app with OWASP ZAP, Playwright, and pytest for auth bypass, XSS, injection, and more
5. **AI Safety Testing** -- If AI features are detected, runs NeMo Guardrails tests across 6 categories (prompt injection, jailbreak, toxicity/bias, topic boundaries, PII leakage, hallucination). If no AI features, marks all as N/A
6. **Attestation Generation** -- Produces a versioned report at `docs/attestations/nemo-it/YYYY-MM-DD-vN.md`

### Safety Guarantees

- All testing is non-destructive -- no DoS, no buffer overflows, no brute force
- SQL injection and other dangerous tests run in detect-only mode
- Production environments trigger a warning and are limited to passive scans
- Optional JSON and JUnit XML output for CI/CD integration (`--format json` or `--format junit`)

### What the Attestation Includes

- Executive summary for GRC leadership
- OWASP Top 10 (2021) coverage mapping
- Risk matrix (likelihood x impact) for every finding
- Detailed analysis per finding: what, where, how, root cause, remediation
- Compensating controls for issues that need technological solutions (WAF, rate limiting, etc.)
- **Secure-by-Design cross-reference** -- classifies each finding as Prevented, Reduced, or Not covered by /make-it guardrails. Shows the prevention rate and which AI safety controls would have caught the issue
- Historical comparison with prior scans
- Exceptions register for accepted risks

### Usage

```bash
cd ~/Documents/GitHub/any-app
claude
> /nemo-it              # full scan
> /nemo-it owasp        # OWASP only
> /nemo-it sast         # static analysis only (no running app needed)
```

---

## How /fix-it Works

`/fix-it` reads the most recent `/nemo-it` attestation, classifies each finding as auto-fixable or manual-only, applies all safe fixes, verifies nothing broke, and re-scans to produce an updated attestation showing the improvement.

### Severity Modes

| Command | What It Fixes |
|---------|--------------|
| `/fix-it` or `/fix-it high` | All CRITICAL + HIGH findings (default) |
| `/fix-it critical` | Only CRITICAL findings |
| `/fix-it medium` | CRITICAL + HIGH + MEDIUM findings |
| `/fix-it all` | Everything including LOW and INFO |

### What It Does

1. **Preflight** -- Locates the latest attestation in `docs/attestations/nemo-it/`, parses all findings, detects your project stack
2. **Triage** -- Classifies every finding as AUTO (mechanical fix), SEMI-AUTO (needs your review), MANUAL (needs human judgment), or SKIP. Presents the plan and waits for your approval
3. **Fix** -- Applies changes in risk order: dependencies first, then config, then code patterns, then AI safety wiring, then rate limiting. Shows diffs for SEMI-AUTO fixes
4. **Verify** -- Runs syntax checks, tests, and builds to ensure nothing broke. Self-healing loop fixes any regressions (up to 3 cycles)
5. **Re-scan** -- Runs `/nemo-it` again to produce an updated attestation with before/after delta
6. **Report** -- Presents what was fixed, what remains, and the risk posture change

### Fix Strategies

The skill includes 12 automated fix strategies:

| Strategy | Example |
|----------|---------|
| Dependency upgrades | `npm audit fix`, pip version bumps |
| SSL/TLS fixes | `verify=False` to configurable env var |
| Request timeouts | Add `timeout=30` to HTTP calls |
| SQL injection | f-strings to parameterized queries + table allowlists |
| Weak cryptography | MD5 to SHA-256 or `usedforsecurity=False` |
| HTML injection / XSS | Add `html.escape()` or DOMPurify |
| Pickle deserialization | Replace with JSON serialization |
| AI safety integration | Wire sanitize/mask/validate pipeline into LLM calls |
| Rate limiting | Add slowapi or express-rate-limit to AI endpoints |
| Config fixes | Terraform TLS versions, file permissions |
| Temp file fixes | `mktemp()` to `mkstemp()` |
| Hardcoded secrets | Extract to env vars + `.env.example` |

### Git Strategy

Before making changes, `/fix-it` creates a rollback point (`git tag pre-fix-it`). You choose how to commit:
1. New `fix-it/YYYY-MM-DD` branch
2. Current branch, single commit
3. Current branch, one commit per fix category

### Usage

```bash
cd ~/Documents/GitHub/my-app
claude
> /fix-it                # fix CRITICAL + HIGH (default)
> /fix-it all            # fix everything
> /fix-it medium         # fix CRITICAL + HIGH + MEDIUM
```

---

## What Gets Built

### Web Applications (Tier 1)

A complete, production-ready web application with:

| Layer | What's Included |
|-------|----------------|
| **Frontend** | Next.js with TypeScript, Tailwind CSS, oklch theming (light/dark mode), responsive layout |
| **Backend** | FastAPI + SQLAlchemy (Python scaffold) or Next.js API routes + Prisma (Node.js scaffold) |
| **Database** | PostgreSQL with role-based access control tables, seed data |
| **Auth** | OIDC authentication (Azure AD, Auth0, Okta, Google, GitHub, Keycloak) with stateless JWT sessions |
| **RBAC** | 4 system roles (Super Admin, Admin, Manager, User), page-level CRUD permissions, permission matrix admin UI |
| **UI Components** | DataTable with Excel-like filtering, breadcrumbs, command palette (Cmd+K), sidebar navigation, dark mode toggle |
| **AI Providers** | Multi-provider abstraction layer (Azure AI Foundry, Anthropic, OpenAI, Ollama) with model tiering (heavy/standard/light) -- only if your app uses AI features |
| **AI Prompt Management** | Database-stored prompts with version history and admin UI for editing -- scales from code-only (1-3 prompts) to full management platform (10+ prompts). Includes content validation, immutable safety preamble, and mandatory test-before-publish workflow |
| **AI Operational Safety** | Runtime safety stack: input sanitization, output validation, rate limiting, PII masking, error sanitization, prompt size validation, system prompt hardening, conversation history management |
| **AI Prompt Template Validation** | Supply-chain injection protection: `validatePromptTemplate()` blocklist, immutable safety preamble auto-prepended at runtime, draft/test/publish workflow, variable interpolation sanitization, risk-flagged edits flagged for security review at deploy time |
| **AI Safety Testing** | NeMo Guardrails with 6 test categories (prompt injection, jailbreak, toxicity/bias, topic boundaries, PII leakage, hallucination) -- generates a GRC-required attestation document |
| **Application Settings** | Database-backed settings management with in-memory cache (60s TTL), cascading precedence (DB > .env > default), Admin Settings page with tab grouping, sensitive value masking, inline editing, and audit log |
| **Docker** | Multi-service Compose with health checks, migration auto-run, mock services on dev profile |
| **Mock Services** | Mock OIDC provider for local auth, plus mock services for any external integrations (Jira, Tempo, etc.) |
| **Seed Data** | Realistic sample data so every page is populated on first launch |
| **Infrastructure** | Terraform configs generated as DevOps handoff artifact (you never apply these yourself) |

### Other Project Types

| Type | What's Generated |
|------|-----------------|
| **IDE Extension** (Tier 2) | VS Code extension with manifest, activation events, SecretStorage, TreeView/DiagnosticCollection providers |
| **CLI Tool** (Tier 3) | Command-line tool with argument parser, --help/--version, exit codes, structured output (--json) |
| **Library** (Tier 4) | Importable package with type declarations, explicit public API, package manifest |
| **API Service** (Tier 5) | Backend-only service with health check, OpenAPI spec, structured logging, consistent error format |

---

## AI Security Architecture

When your app uses AI features, /make-it implements a comprehensive safety stack that protects against prompt injection, data leakage, and supply-chain attacks -- all invisible to the user.

### Three Layers of AI Protection

```
Layer 1: Runtime Controls          -- Protect every AI call at execution time
Layer 2: Prompt Template Validation -- Protect the admin editing surface
Layer 3: NeMo Guardrails Testing    -- Verify safety through adversarial testing
```

### Layer 1: Runtime Controls (Prompt #10e Parts 1-8)

Every AI invocation passes through a safety pipeline implemented in `lib/ai/`:

| Module | What It Does |
|--------|-------------|
| `sanitize.ts` | Strips injection patterns from user input, wraps in `<user_input>` delimiter tags, decodes and re-scans encoded payloads (Base64, Unicode homoglyphs, ROT13) |
| `validate.ts` | Validates AI responses against schemas + value ranges before storage. Strips HTML/script tags from free-text responses. Detects system prompt leakage |
| `rate-limit.ts` | Per-user request and token budget on AI endpoints. Returns 429 with Retry-After header when limits exceeded |
| `pii-masker.ts` | Pseudonymizes names, emails, phones, financial figures before submission to external AI providers. Reverses on response |
| `errors.ts` | Maps AI provider errors to generic safe messages. No API keys, model names, or provider details ever reach the client |

Additional controls in BaseAgent:
- **Prompt size validation** -- Rejects inputs exceeding `AI_MAX_PROMPT_CHARS` (default 100K) before they reach the AI provider
- **System prompt hardening** -- Anti-injection and anti-jailbreak instructions automatically appended to every agent's system prompt
- **Conversation history management** -- Server-side storage with max depth (`AI_MAX_HISTORY_TURNS`), session isolation, PII masking on stored history

### Layer 2: Prompt Template Content Validation (Prompt #10e Part 9)

When administrators can edit AI prompts through the UI (Tier 2/3 prompt management), the saved content becomes part of the system prompt at runtime. This creates a **supply-chain injection surface** -- a compromised or careless admin edit could override safety controls. /make-it protects against this while keeping the experience frictionless:

**Immutable Safety Preamble:**
- Every prompt has two parts at runtime: a **locked safety preamble** (system-managed) + **prompt content** (admin-editable)
- The preamble contains anti-injection and anti-jailbreak instructions -- admins never see it
- The runtime ALWAYS prepends the preamble. There is no code path that skips it

**Content Validation on Save:**
- `validatePromptTemplate()` runs a hybrid blocklist on every save:
  - **Blocked** (hard reject): injection overrides ("ignore previous instructions"), role manipulation ("you are now"), system token spoofing, code injection (`<script>`, `eval(`, shell metacharacters), encoded payloads, safety preamble tampering
  - **Warned** (soft flag): references to prompt architecture, unusual encoding, meta-instructions
- Friendly, plain-language warnings -- no jargon. E.g., "This wording could let users override the AI's instructions. Try rephrasing: [highlighted text]"

**Mandatory Test-Before-Publish:**
- New edits save as `status: draft` (not active -- agents never see draft prompts)
- The admin must click "Test" before "Publish" becomes enabled
- Test runs: blocklist check + sanitize rendered output + all saved test cases + mini NeMo Guardrails check (3 injection + 2 jailbreak adversarial inputs)
- All tests must pass before the prompt version can go live

**Variable Interpolation Safety:**
- Template variables (`{{vendor_name}}`, `{user_input}`) are sanitized through `sanitizePromptInput()` at render time
- HTML entities escaped in all interpolated values
- Prevents injection through template variables even when the template itself is clean

**Security Review Integration:**
- Risk-flagged edits (override warnings, system-category prompts) are logged with `risk_flag: true`
- `/ship-it` checks for risk-flagged edits since last deploy and adds a "Prompt Safety Review Required" section to the PR for security team review

### Layer 3: NeMo Guardrails Testing (Prompt #10d)

Every AI-powered app gets a NeMo Guardrails test suite covering 6 categories:

| Category | What It Tests | Minimum Cases |
|----------|--------------|--------------|
| Prompt Injection | Can adversarial input override system instructions? | 10 |
| Jailbreak | Can the AI be convinced to operate outside boundaries? | 10 |
| Toxicity/Bias | Does the AI produce harmful or biased content? | 10 |
| Topic Boundaries | Does the AI stay within its intended domain? | 10 |
| PII Leakage | Does the AI reveal personal or system information? | 10 |
| Hallucination | Does the AI generate false or fabricated information? | 10 |

- Basic suite (18 tests) runs during build-verify
- Full suite (60+ tests) runs during `/ship-it`
- Self-healing remediation loop for failures
- Generates GRC-required AI Safety Attestation in `docs/`

### AI Prompt Management Tiers

Prompt management scales with the app's AI complexity:

| Tier | When | Storage | Admin UI | Content Validation |
|------|------|---------|----------|--------------------|
| 1 (Minimal) | 1-3 prompts, devs only | Code + env var override | None | N/A (no admin editing) |
| 2 (Moderate) | 4-10 prompts, product team edits | 3 DB tables | Edit, test, version diff, rollback, audit trail | `validatePromptTemplate()` + draft/publish + immutable preamble |
| 3 (Heavy) | 10+ prompts, AI-native app | 6 DB tables | Full platform: registry, editor, analytics, audit | All Tier 2 controls + import validation + system prompt locking + risk escalation |

### Environment Variables (AI Features)

| Variable | Default | Purpose |
|----------|---------|---------|
| `AI_PROVIDER` | (required) | AI provider name -- throws error if missing, no silent fallback |
| `AI_RATE_LIMIT_REQUESTS_PER_MINUTE` | 20 | Per-user request limit on AI endpoints |
| `AI_RATE_LIMIT_TOKENS_PER_MINUTE` | 50000 | Per-user token budget |
| `AI_MAX_PROMPT_CHARS` | 100000 | Max prompt length before AI submission |
| `AI_MAX_DOCUMENT_CHARS` | 500000 | Max document length for analysis features |
| `AI_MAX_HISTORY_TURNS` | 20 | Max conversation history depth |
| `AI_PII_MASKING_ENABLED` | true | Enable PII pseudonymization for external AI |

---

## Supported Project Types

The skill automatically classifies your project during the Design phase based on your answers. You never need to choose -- it figures it out.

| Type | Detected When You Say... | Tech Stack |
|------|-------------------------|------------|
| **Web App** (Python backend) | "dashboard", "login", "data processing", "Python" | FastAPI + Next.js + PostgreSQL (scaffold) |
| **Web App** (Node.js full-stack) | "dashboard", "login", "CRUD", "AI features", "TypeScript only" | Next.js API routes + Prisma + PostgreSQL (scaffold) |
| **IDE Extension** | "VS Code plugin", "editor tool", "code analysis" | TypeScript + VS Code API |
| **CLI Tool** | "command line", "terminal tool", "script" | Python or Node.js |
| **Library** | "importable package", "SDK", "shared module" | TypeScript or Python |
| **API Service** | "backend only", "webhook handler", "data pipeline" | FastAPI + PostgreSQL |

---

## Architecture

### Repository Structure

```
.claude/
  commands/
    make-it.md                    # Main skill -- idea to working app
    try-it.md                     # Try skill -- spin up, test, explore
    resume-it.md                  # Resume skill -- continue, test, fix, ship
    retrofit-it.md                # Retrofit skill -- upgrade existing apps
    nemo-it.md                    # Security attestation skill -- scan any app
    fix-it.md                     # Fix skill -- auto-fix /nemo-it findings
  make-it/
    references/
      prerequisites.md            # Machine setup checks
      design-blueprint.md         # Architectural decision framework (13 areas + AI safety)
      prompt-templates.md         # 14+ enterprise build prompts (includes AI safety controls)
      ship-it-guide.md            # Deployment handoff reference (includes prompt safety gate)
      guardrails.md               # Tiered guardrail system (Tier 0-5 + AI operational safety)
      fix-strategies.md            # 12 automated fix strategies for /fix-it
    templates/
      app-context.md              # Template for tracking user answers (includes AI provider config)
      ai-safety-attestation.md    # AI safety attestation report template
      nemo-it-attestation.md      # Security attestation report template (v1.1.0, includes Secure-by-Design cross-ref)
    scaffolds/
      fastapi-nextjs/             # Pre-built scaffold (61 files) -- Python backend
        backend/                  # FastAPI: auth, RBAC, models, routers, Alembic
        frontend/                 # Next.js: pages, components, Tailwind, oklch theme
        mock-services/mock-oidc/  # Complete mock OIDC provider
        scripts/                  # seed-mock-services.sh template
        docker-compose.yml        # Multi-service orchestration template
        .env.example              # Environment variable documentation
      nextjs-fullstack/           # Pre-built scaffold -- Node.js full-stack
        README.md                 # Architecture, auth flow, RBAC, placeholders
  nemo-it/
    references/
      owasp-testing-guide.md      # OWASP Testing Guide v4 mapped to automated test strategies
docs/
  sequence-diagrams.md            # Mermaid diagrams of the full lifecycle
CLAUDE.md                         # Project instructions for Claude Code
README.md                         # This file
```

### State Files (created in YOUR project at runtime)

These files are generated inside the app you build -- not in this repo:

| File | Purpose |
|------|---------|
| `.make-it/app-context.json` | All design decisions from ideation and design phases |
| `.make-it/preflight-status.json` | Machine readiness check results (cached between runs) |
| `.make-it-state.md` | Session breadcrumb -- what was built, what's pending, test results |
| `TRY-IT-REPORT.md` | Test results, screenshots, and browser access instructions |
| `.try-it/screenshots/` | Screenshots of every page per user role |
| `NEXT-STEPS.md` | Shareable checklist of infrastructure, tickets, and env vars needed |
| `docs/attestations/nemo-it/` | Versioned security attestation reports from `/nemo-it` scans |
| `CHANGELOG.md` | Running log of all changes across sessions |
| `TODO.md` | Outstanding work items |

### How the Scaffolds Work

For web applications, the Build phase uses a **pre-built scaffold** instead of generating everything from scratch. This is how recurring bugs are eliminated:

1. **Design phase** determines the app name, ports, users, roles, integrations, and backend type
2. **Build phase** selects the right scaffold (Python backend or Node.js full-stack)
3. All `[BRACKET_PLACEHOLDERS]` are replaced with values from `app-context.json`
4. Domain-specific code (your pages, APIs, models, seed data) is generated on top
5. The scaffold's auth, RBAC, Docker, and UI components are never regenerated

| Scaffold | When Selected | Backend | ORM | Containers |
|----------|--------------|---------|-----|------------|
| **fastapi-nextjs** | Python backend, data processing, ML features | FastAPI (Python) | SQLAlchemy + Alembic | 4 (frontend, backend, db, mock-oidc) |
| **nextjs-fullstack** | Node.js only, AI via Node SDKs, simple CRUD | Next.js API routes (TypeScript) | Prisma | 3 (app, db, mock-oidc) |

Both scaffolds provide the same core foundations:
- Complete OIDC auth flow (login, callback, JWT cookie, /me, logout)
- Database-driven RBAC (4 tables, permission middleware, admin UI)
- DataTable with Excel-like column filtering
- Sidebar, breadcrumbs, command palette, dark mode toggle
- Docker Compose with health checks and migration auto-run
- Mock OIDC provider (Python, no Java dependencies)

---

## Build Quality

The build process has four layers of quality assurance:

```
Layer 1: Foundation     -- Scaffold provides pre-verified patterns (debugged once, reused always)
Layer 2: Prevention     -- Prompts encode lessons learned (API contracts, seed data alignment, etc.)
Layer 3: Detection      -- Build-verify silently tests auth, APIs, pages, and permissions
Layer 4: Demo           -- /try-it presents the working app; its fix cycle is a safety net
```

### What Build-Verify Checks (silently, before you see anything)

**Static checks (before starting the app):**
- All expected files exist
- No stub endpoints ("not yet implemented")
- No hardcoded mock data in pages
- Database migrations exist
- `.env` and `.env.example` both present
- No external font imports (safe behind SSL proxies)
- All four standard UI components wired into layout
- Seed data populates every page
- Auth callback reads roles from database (not OIDC claims)
- Logout is POST (not GET)
- Service client endpoints match mock API contracts
- Docker env var names match backend config
- Port availability checked
- AI safety controls wired: `sanitizePromptInput()`, `validateAgentOutput()`, rate limiting middleware, PII masking, error sanitization, system prompt hardening (if AI features)
- Prompt template validation: `validatePromptTemplate()` on save endpoints, immutable preamble prepended by runtime, draft/test/publish workflow, variable interpolation sanitized (if Tier 2/3 prompt management)

**Live checks (app running in Docker):**
- All containers healthy
- Mock services seeded with correct users
- Login works for every role
- Every API endpoint returns data
- Every page loads with content
- Permission boundaries enforced (403 for unauthorized access)
- Logout clears JWT cookie
- **Auth smoke test** -- end-to-end curl-based test that verifies the full OIDC flow:
  - Login redirects to the identity provider
  - Callback redirect goes to the correct external URL (not a Docker-internal address)
  - JWT cookie is set with the correct Secure flag for the protocol
  - Cookie Secure flag matches the frontend URL (prevents silent browser rejection)

Issues found during build-verify are fixed automatically (up to 3 cycles). You never see a broken app.

---

## Deployment Lifecycle

Your experience is simple: **describe what you want, verify it works, say "ready."**

```
/make-it      --> Build a new app from scratch, verify it works
/retrofit-it  --> Upgrade an existing app with production foundations
/try-it       --> Explore it in the browser
/resume-it    --> Iterate (add features, fix things, run tests)
/nemo-it      --> Security attestation (scan any app, generate report)
/fix-it       --> Automatically fix security findings from /nemo-it
/ship-it      --> Deploy (creates PR, triggers CI/CD)
```

The full lifecycle with CI/CD automation:

```
/make-it (new app) or /retrofit-it (existing app)
  -> Build/upgrade in Docker, push to GitHub
/resume-it -> Iterate (security auto-fixes, you verify your app still works)
/ship-it -> Create PR, trigger CI/CD
  CI/CD -> Scan, auto-remediate, send back for verification
  /try-it -> You verify app still works
  /ship-it -> Deploy to dev
  You confirm prod-ready -> Production checks -> Deploy to prod
```

You never fix code directly. Security findings and CI/CD issues are auto-remediated. You only verify that your app works the way you envisioned.

---

## Guardrails

Every app built by `/make-it` follows a tiered guardrail system. **Tier 0 applies to all projects.** Higher tiers activate based on what you're building.

### Tier 0: Universal (every project)

- Ideation confirmed, design documented, build-verified before handoff
- `CHANGELOG.md` and `TODO.md` from day one
- No secrets in committed files, no hardcoded config values
- Input validation at system boundaries
- Latest stable dependencies with no known vulnerabilities
- Git initialized with proper `.gitignore`

### Tier 1: Web Application

All of Tier 0, plus:
- OIDC authentication with chosen provider (callback redirect, cookie Secure flag, and JWT format all verified by live smoke test)
- Database-driven RBAC with 4 system roles and permission matrix
- Standard UI components (DataTable, Breadcrumbs, QuickSearch, ModeToggle)
- Docker Compose with mock services and seed data
- Database-backed application settings with Admin UI (cascading precedence, sensitive value masking, audit log)
- System fonts only (no external font CDNs -- safe behind corporate proxies)
- Parameterized database queries, security headers
- Terraform generated as DevOps handoff artifact
- **AI provider abstraction** (if app uses AI) -- configurable via env var, supports Azure AI Foundry, Anthropic, OpenAI, Ollama
- **AI operational safety** (if app uses AI) -- runtime safety stack in `lib/ai/`: input sanitization, output validation, rate limiting, PII masking, error sanitization, prompt size validation, system prompt hardening, conversation history management
- **AI prompt management** (if app uses AI) -- scales from code-only to database-managed with admin UI based on prompt count. Tier 2/3 includes content validation with blocklist, immutable safety preamble, mandatory test-before-publish workflow, and variable interpolation sanitization
- **AI safety testing** (if app uses AI) -- NeMo Guardrails with 6 mandatory test categories; generates GRC-required attestation for production deployment
- **Prompt safety review gate** (if app uses AI + Tier 2/3 prompts) -- `/ship-it` checks for risk-flagged prompt edits and includes them in the PR for security team review before merge

### Tier 2: IDE Extension

All of Tier 0, plus: extension manifest, scoped activation events, SecretStorage for tokens, bundled output, provider patterns

### Tier 3: CLI Tool

All of Tier 0, plus: argument parser, --help/--version, correct exit codes, structured output option (--json)

### Tier 4: Library / Package

All of Tier 0, plus: package manifest, type declarations, explicit public API, no circular dependencies

### Tier 5: API Service

All of Tier 0, plus: health check endpoint, OpenAPI spec, structured logging, consistent error format

---

## FAQ

**Do I need to know how to code?**
No. The entire experience is conversational. You describe what you want in plain English, and the skill builds it.

**What languages/frameworks does it use?**
For web apps: either Python (FastAPI) backend with Next.js frontend, or Node.js full-stack (Next.js API routes with Prisma). Both use PostgreSQL. Other project types use the language best suited for the task.

**Can I customize the generated code later?**
Yes. The generated code is standard, well-structured code in your project directory. Any developer can modify it. `/resume-it` helps you make changes without coding knowledge.

**Does it work behind a corporate proxy (Zscaler, Netskope)?**
Yes. The skill detects SSL-inspecting proxies during Preflight and guides you through temporarily disabling them for Docker builds. All generated apps use system fonts (no external font CDNs) to avoid proxy issues.

**What if I want to change my app idea mid-build?**
Minor changes (UI tweaks, adding a page) are handled seamlessly. Major changes (different architecture) trigger a conversation about what needs to change before proceeding.

**How does application settings management work?**
Every web app gets a database-backed settings system. All `.env` variables are seeded into an `app_settings` table during migration. Settings follow a cascading precedence: database value wins over `.env`, which wins over code defaults. The Admin Settings page lets authorized users view, edit, and audit settings -- sensitive values (passwords, API keys) are masked unless explicitly revealed. Changes are logged in an audit trail with before/after values. An in-memory cache with 60-second TTL keeps reads fast.

**How do roles and permissions work?**
Every web app gets database-driven RBAC: 4 system roles (Super Admin, Admin, Manager, User) with page-level CRUD permissions. Super Admins can create custom roles with any combination of permissions via an admin UI. Roles are stored in the application database, not the identity provider.

**Can it build apps that talk to external systems (Jira, Salesforce, etc.)?**
Yes. The skill detects external integrations during Ideation and generates mock services for each one, so you can develop and test locally without access to the real systems.

**What does "mock OIDC" mean?**
When your app requires login, the skill generates a local mock identity provider (like a fake Azure AD) so you can test the full login flow on your machine without setting up a real identity provider. It includes a user picker with test accounts for each role.

**Where does my code live?**
In a standard Git repository in the directory where you ran `/make-it`. It gets pushed to GitHub when you run `/ship-it`.

**I already have an app -- can I still use these skills?**
Yes. `/retrofit-it` is designed exactly for this. It reverse-engineers your existing app, identifies what's missing (auth, RBAC, Docker, etc.), and upgrades it surgically. It creates a git snapshot first so you can always roll back.

**Does it support AI-powered apps?**
Yes. If your app uses AI features, the skill automatically adds a multi-provider abstraction layer (Azure AI Foundry, Anthropic, OpenAI, Ollama) with configurable model tiering. It also sets up prompt management that scales with your needs -- from simple prompts in code to a full database-managed prompt platform with admin UI. See [AI Security Architecture](#ai-security-architecture) for the full safety stack.

**What prevents someone from injecting malicious prompts through the admin UI?**
Three things: (1) A `validatePromptTemplate()` blocklist that rejects known injection patterns, code injection, and encoded payloads on every save. (2) An immutable safety preamble that is always prepended to prompts at runtime -- admins can't see it, edit it, or remove it. (3) A mandatory test-before-publish workflow that runs adversarial NeMo Guardrails tests against every draft prompt before it can go live. Additionally, template variables are sanitized at render time, risk-flagged edits are logged, and `/ship-it` flags them in the PR for security review.

**What if the AI returns something dangerous (XSS, hallucinated data, etc.)?**
Every AI response passes through `validateAgentOutput()` before it reaches the database or the UI. Structured responses are validated against schemas with value range checks. Free-text responses are scanned for HTML/script tags, markdown injection, and system prompt leakage. AI-generated content in the frontend uses escaped rendering -- never `dangerouslySetInnerHTML`.

**Is PII protected when using external AI providers?**
Yes. The `maskPII()` function pseudonymizes names, emails, phone numbers, and financial figures before any data leaves for an external AI provider. The `unmaskPII()` function reverses the masking on the response. This means external providers like OpenAI or Anthropic never see real personal data. Controlled by the `AI_PII_MASKING_ENABLED` environment variable.

---

## Related Skills

| Skill | Purpose | Repo |
|-------|---------|------|
| `/ship-it` | CI/CD deployment -- commits, pushes, creates PR with shared GHA workflows | [sealmindset/ship-it](https://github.com/sealmindset/ship-it) |

---

## Version History

### v1.6.0 -- Database-Backed Application Settings

Adds database-backed settings management as a standard feature for all Tier 1 (web app) projects.

- Added `app_settings` and `app_setting_audit_logs` tables to scaffold (SQLAlchemy models, Pydantic schemas)
- Added settings service with in-memory cache (60s TTL) and cascading precedence (DB > .env > code default)
- Added settings FastAPI router with RBAC-gated endpoints (list, update, bulk update, reveal sensitive, audit log)
- Added Admin Settings page placeholder in scaffold (replaced during build with full tab-grouped UI)
- Added Prompt #9b to prompt-templates.md with full generation instructions for settings feature
- Added Section 2b to design-blueprint.md with schema, service, API, and UI specification
- Added 11 guardrail rules and 12 build-verify checks for settings to guardrails.md
- Added build step 4 "Application Settings (Database-Backed)" to make-it.md build phase
- Seed migration auto-populates `app_settings` from all `.env` variables with category, sensitivity, and description
- Sensitive values masked in API responses and audit logs; reveal requires explicit permission

### v1.5.0 -- Self-Update and Curl Install

Adds seamless update capability and one-line installation -- no git clone required.

- Added `/make-it update` subcommand: checks installed vs latest version, downloads and installs updates, reports what changed
- Added curl one-liner install: `curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash`
- Rewrote `install.sh` to work from cloned repo OR via curl (auto-detects context)
- Added `VERSION` file for version tracking (installed version stored at `~/.claude/make-it/VERSION`)
- Auto-discovers new skills on update (no hardcoded skill list -- any new `*.md` in commands/ gets installed)
- Fallback to tarball download if git is not installed (curl-only machines)
- Update interceptor in `make-it.md` catches "update" keyword before Preflight phase

### v1.4.0 -- /fix-it Automated Security Remediation

Bridges the gap between `/nemo-it` scanning and `/ship-it` deployment by automatically fixing security findings.

- Added `/fix-it` skill with 6-phase workflow: preflight, triage, fix, verify, re-scan, report
- Added `fix-strategies.md` reference with 12 automated fix strategies (dependencies, SSL/TLS, timeouts, SQL injection, weak crypto, HTML/XSS, pickle, AI safety, rate limiting, config, temp files, secrets)
- Classification system: AUTO (mechanical), SEMI-AUTO (needs review), MANUAL (needs human), SKIP
- Risk-ordered fix execution: dependencies first, then config, code patterns, AI safety, rate limiting
- Self-healing verification loop (up to 3 cycles) after each fix category
- Before/after attestation comparison with delta reporting
- Git rollback safety: `pre-fix-it` tag created before any changes
- Severity modes: `/fix-it critical`, `/fix-it` (default: CRIT+HIGH), `/fix-it medium`, `/fix-it all`

### v1.3.0 -- Prompt Template Content Validation

Protects the admin prompt editing surface against supply-chain injection attacks.

- Added `validatePromptTemplate()` hybrid blocklist for admin-editable prompts (Tier 2/3)
- Added immutable safety preamble (auto-prepended at runtime, invisible to admin UI)
- Added draft/test/publish workflow (mandatory testing before activation)
- Added `renderPromptSafe()` with variable interpolation sanitization via `sanitizePromptInput()`
- Added `testPromptDraft()` with mini NeMo Guardrails safety check (5 adversarial inputs)
- Added `risk_flag` audit logging with `/ship-it` PR integration for security review
- Updated Prompt #10b (Tier 2) and #10c (Tier 3) with validation requirements
- Updated Prompt #10e with Part 9 (template content validation)
- Updated Prompt #11 with template validation verification steps
- Updated guardrails.md with 10 new build-verify checks
- Updated design-blueprint.md Section 10a (validation architecture)
- Updated ship-it-guide.md with prompt safety review gate (step 6)
- Updated retrofit-it.md Steps 11j-m (gap detection) and Step 4.5 (phased verification)
- Updated nemo-it cross-reference classification (3 new prevention entries)

### v1.2.0 -- AI Operational Safety Controls

Adds runtime safety controls for every AI invocation, closing 6 gaps identified during the TPRMAI security attestation.

- Added Prompt #10e with 8 parts: input sanitization, output validation, rate limiting, prompt size validation, PII masking, error sanitization, system prompt hardening, conversation history management
- Added `lib/ai/` module architecture to design-blueprint.md Section 11b: `sanitize.ts`, `validate.ts`, `rate-limit.ts`, `pii-masker.ts`, `errors.ts`
- Added BaseAgent safety pipeline: sanitize -> validate size -> mask PII -> call AI -> unmask -> validate output
- Added AI Operational Safety Controls section to guardrails.md with consolidated AI Build-Verify Checklist
- Added 6 new environment variables for AI safety configuration
- Updated Prompt #11 (Secure Everything) with AI safety control verification
- Updated retrofit-it.md with Phase F2 gap analysis + Step 11 (AI operational safety) + Step 4.5 (phased retrofit)
- Updated nemo-it attestation template with Secure-by-Design cross-reference section (v1.1.0)
- Updated both nemo-it.md skill files with Step 6 classification logic

### v1.1.0 -- NeMo Guardrails Integration

- Added Prompt #10d: NeMo Guardrails AI safety testing with 6 categories
- Added 60+ test cases (10 per category) with self-healing remediation loop
- Added AI Safety Attestation template (GRC-required for production)
- Added /ship-it pre-deploy gate: full NeMo suite must pass before PR creation

### v1.0.0 -- Initial Release

- 5-phase build process (preflight, ideation, design, build, ship)
- FastAPI + Next.js scaffold with OIDC auth and database-driven RBAC
- 14 build prompts with tiered guardrails (6 project types)
- /try-it, /resume-it, /retrofit-it, /nemo-it companion skills
- Mock services for offline development
- Standard UI components (Breadcrumbs, DataTable, QuickSearch, ModeToggle)
- Build-verify quality gate with automated fix cycle
- /ship-it deployment pipeline integration

---

## License

[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) -- free to use, share, and adapt with attribution.
