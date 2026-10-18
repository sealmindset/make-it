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

#### Windows

The install script handles everything automatically: Node.js, Git, Azure CLI, Docker, Claude Code, configuration files, and skills. If a restart is needed, it saves progress and picks up where it left off.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
```

To check for updates without installing, set `MAKEIT_ACTION` first -- `irm ... | iex`
cannot pass arguments to the script:

```powershell
$env:MAKEIT_ACTION = "check"
irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
$env:MAKEIT_ACTION = $null
```

Running Claude Code through an enterprise Azure AI Foundry gateway is opt-in. Set
`MAKEIT_FOUNDRY_BASE_URL` (and, if your deployment names differ from the defaults,
`MAKEIT_OPUS_MODEL` / `MAKEIT_SONNET_MODEL` / `MAKEIT_HAIKU_MODEL`) before running the
installer. Without it, nothing touches your Claude Code authentication.

See the complete **[Windows Setup Guide](docs/WINDOWS-SETUP.md)** for manual steps, daily workflow, and troubleshooting.

#### macOS / Linux

##### Option A: One-Line Install (recommended)

No clone needed. Just run:

```bash
curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash
```

This downloads the latest release and installs all skills into `~/.claude/`.

##### Option B: Clone and Install

```bash
git clone https://github.com/sealmindset/make-it.git
cd make-it
bash install.sh
```

#### Option C: Manual Install (macOS / Linux)

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
| `/backlog-it` | Keeps the project's work and bugs on a markdown board (Epic → Story → Task), with a bug queue and parallel fix lanes | Tracking what's next, capturing a bug, or pulling a card back in to work on it |

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
5. **Pre-retrofit Snapshot** -- Saves a snapshot before anything changes. An app in its own repo gets a git tag (`pre-retrofit-<folder>`). An app inside another repo gets a plain copy beside it, and nothing is written to the outer repo. Local file databases (`*.db`, `*.sqlite`) are copied too, so undo puts your files and that data back. Your .env settings and server databases like Postgres are not part of it.
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
- Database-backed application settings with Admin UI (cascading precedence, sensitive value masking, audit log)
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
      nemo-it-attestation.md      # Security attestation report template (v1.2.0, includes Secure-by-Design cross-ref)
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
Minor changes (UI tweaks, adding a page) are handled seamlessly. Major changes (different architecture) trigger a conversation about what needs to change before proceeding. A change to sign-in or to who can do what is handled differently, however small: the skill asks you to name the specific change (the new sign-in method and who it applies to, or what changes for which user type) before redoing anything. If your request doesn't say that yet, it first shows what is in place today.

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
Yes. `/retrofit-it` is designed exactly for this. It reverse-engineers your existing app, identifies what's missing (auth, RBAC, Docker, etc.), and upgrades it surgically. It saves a snapshot first that puts your files and local database files back if you want to go back (your .env settings and server databases are not part of it).

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

Building in Claude Desktop or Cowork instead of Claude Code? See [`desktop/README.md`](desktop/README.md) for the `make-it-desktop` plugin.

---

## Version History

### v1.44.12 -- Only a practice script may plant a practice item; subagents never plant flaws

Rule 4 of "Keep the human able to notice" told agents to now and then plant a harmless flaw in a
review. That rule is in every project's `CLAUDE.md`, and every subagent reads it, so an
implementer or reviewer could take it as permission to plant a flaw in code, tests, a review or a
report. Now:
- **Every subagent prompt says never.** The implementer, test-writer, task-reviewer and
  adversarial-reviewer templates, and the dispatch prompt rule, all say: never plant a deliberate
  flaw in code, tests, a review, a report or a commit.
- **Rule 4 is narrowed.** Only the coordinator's practice script may plant a practice item. It
  goes only in chat, and only if the user turned practice items on (they are off by default). It
  is revealed right after the answer, and never goes in code, tests, reviews, reports or commits.
- **Existing projects are updated.** On the next catch-up, check S12 replaces an old copy of rule
  4 in place.

### v1.44.11 -- New apps' database migrations always follow the scaffold's own

`/make-it` told builds to create migration `002_domain_schema.py`, then `003_domain_permissions.py` and
`003_seed_data.py`. Those numbers date from when the scaffold had one migration. It now ships `002` and `003`,
so every build made two migration heads, and `alembic upgrade head` failed on first start. The backend
container died, and a fix cycle had to work out why. Now:
- Each migration a build adds takes the next free number after the highest one in
  `backend/alembic/versions/`, with `down_revision` set to that revision. No number is hard-coded, and the
  chain must keep exactly one head.
- A new fastapi-nextjs build gets `004_domain_schema.py` (after `003`). This was checked with alembic:
  one head, and `upgrade head` runs clean.

### v1.44.10 -- `/retrofit-it`'s undo never writes into another repo, and puts `.db` files back

The undo snapshot only checked that it was inside a git repo. When the app lived inside a bigger
repo, the "before" commit and the fixed `pre-retrofit` tag went into that outer repo, along with
whatever else was staged there. Two apps in one repo also shared one tag, and undo never covered
local database files. Now:
- **App inside another repo:** the snapshot is a plain copy beside the app, without installed
  packages or secret files. Nothing is committed, tagged or ignored in the outer repo, and the
  retrofit makes no branch or worktree there.
- **App in its own repo:** the tag is named after the app folder (`pre-retrofit-<folder>`).
- **Local databases:** `*.db` and `*.sqlite` files are copied, and a new Undo step puts files and
  data back exactly. It compares contents, not timestamps. Journal files (`*.db-*`) are no longer
  committed.
- **Stop:** tells you where the upgraded app is and how to get back to it.
- **The plan's steps:** the step names now match the checkpoints the retrofit actually runs.

Checked under bash and zsh: an app with its own repo, an app inside another repo, and two apps in
one repo. Undo restored the app folder and its database byte for byte, and the outer repo was left
untouched.

### v1.44.9 -- `/try-it` never stops other programs, and asks about your security tool only when needed

`/try-it` stopped whatever program was on the ports it needed, without asking. It started
downloads before checking for a corporate proxy, and it asked you to pause a security tool as
soon as it saw one, before anything had failed. Now:
- **Other programs keep running.** If a port is taken, the app moves to a free one and you get a
  new address. If no free port works, it asks first, naming the program. Only typing that
  program's name stops it.
- **Proxy check first.** The security-tool and proxy check runs before any download or build.
- **Try first, ask on error** (same as `/make-it` step 21). `/try-it` builds first. It asks to
  pause a security tool only after a real certificate error, once, in the same words as
  `/make-it`. The reminder to turn the tool back on comes after the smoke test's downloads have
  finished.

### v1.44.8 -- Catch-up puts each `CLAUDE.md` section in one exact spot

S10-S12 placed their sections in a range ("after the canary and before `@LEARNINGS.md`"),
and their fixes could only add a section, never move one. So a literal reading depended on the
order the checks ran in. An older project could end up with sections after its own old ones, or
with a second copy. Now:
- **One spot for each section.** S11 goes directly before the next heading after the canary, and
  S12 directly before the next heading after S11. S10 writes `## Learnings` + `@LEARNINGS.md`
  right after them. The result is canary, settle-filter-verify, keep-the-human-able-to-notice,
  Learnings, then the project's own sections unchanged. That matches a fresh `/make-it` build.
- **Moved, never copied.** A section that exists in the wrong place is moved. A stray
  `@LEARNINGS.md` is moved too.
- **The canary's fallback:** when there's no builder name, `🐤 canary ok` replaces only the
  canary's first sentence. The explanation now reads "fails to open that way", which fits both
  forms. Existing canaries are untouched.

Checked by applying the wording literally in every order to three starting files. Each gave one
result, byte for byte the same as a fresh build, and a second run changed nothing.

### v1.44.7 -- `/nemo-it` reports only what ran, and scans only your app

A live check of v1.44.4 found more places where `/nemo-it` said a scan was complete, or a check
passed, when it never ran. It also found that it could point its requests at another project's
server. Now:
- **Only what ran is reported as run** (new guardrail 11). Browser tests, ZAP, the API tests,
  Semgrep, Bandit/ESLint, the dependency and container scans and SQLMap each print "did not run
  … NOT RUN" when they didn't run. Each decides from its actual result (a missing or empty report
  counts as not run), never from the tool merely being installed. "All scans are complete" is
  printed only when they all ran.
- **Only your app is scanned** (new guardrail 12). Step 5 checks that the server on a port was
  started from this project's folder before it sends anything. If the port belongs to another
  project, nemo-it says so and leaves it alone. If it can't tell, it asks. The container scan
  covers only this project's containers.
- **AI results:** code-level results read `NO FINDINGS (code-level)`, never PASS.
- **The attestation template (1.2.0)** adds NO FINDINGS and NOT RUN, and Key Metrics rows for
  them.
- **Nothing downloads without asking:** `npx --no-install` and `docker run --pull=never`.
  Preflight checks for the pytest plugin the run actually uses, and clears old results so a
  stale report can't count.
- The OWASP guide import is gone. It never shipped with a normal install, so it never loaded.

### v1.44.6 -- New apps keep their dev database password out of committed files

Both app templates (fastapi-nextjs and nextjs-fullstack) wrote the dev database password into
`docker-compose.yml`, and that password was just the app's name. So every new app committed it,
and argo-it's secret check would stop on it at the first deploy. Now:
- `docker-compose.yml` reads `${POSTGRES_PASSWORD}` from `.env`, and the backend builds its
  database URL from the same value. There is no fallback that puts it back in the file.
- `/make-it` seeds a random password into `.env` at build time, alongside `JWT_SECRET`.
  `.env.example` documents a `local-dev-only` placeholder, so `cp .env.example .env` still
  starts.
- The backend's fallback defaults (`config.py`, `alembic/env.py`) no longer hold the old password.

Checked on a test app built from the new template: no hits in its committed files, the database
and backend came up healthy, the migrations ran, and the old password was rejected. Apps built
before this keep the old value in their committed files. A catch-up for them is tracked
separately, and it must keep the value each app's database was created with.

### v1.44.5 -- The sdd-gate waits for running agents instead of nudging

During a `/subagent-it` run, the sdd-gate counted every turn end as a stall. That included the
turns spent waiting for a background agent to report. So it nudged while work was running, and
after 3 nudges it let the run go, even though nothing had stalled. Now:
- A background agent that is still running doesn't trigger a nudge, and the wait doesn't count
  toward the cap. That holds for up to 2 hours after launch, because real implementers ran for
  up to an hour. An agent whose finished notice is queued but not yet delivered still counts as
  running.
- A real stall, a turn that ends with no agent running, is nudged 1-3 times and then capped, as
  before.
- If the session transcript can't be read in the expected format, the gate goes back to the old
  strict nudging. It never traps a session.

Checks: 6 new fixture cases in `scripts/test-sdd-gate.sh`, and a replay of a real 114-nudge
transcript, where all 114 are now held.

### v1.44.4 -- `/nemo-it` read-only mode says what it actually ran

When `/nemo-it` sees your live system, it switches to read-only mode, but its messages still
described a full run. It said it had tested logins, endpoints and SQL injection that it had
skipped on purpose, and the attestation marked those checks Completed or PASS. Now:
- **Go ahead** only offers read-only requests when the app is running, or is about to start.
- Completion lines name the checks that ran and list what was skipped. "SQL injection probes
  skipped" replaces "detection complete".
- The attestation marks a phase that skipped checks as `Partial (read-only)`, with a "Skipped --
  production detected" list. A category is PASS only when none of its checks was skipped. The
  posture rating says it is based on a read-only scan, and JUnit reports a skipped check as
  skipped, never as a pass.
- The closing summary adds a "Not run, so not passed" line.
- The AI behavioral results show `[X/10 passed]` only when those tests actually ran. This
  applies in every mode, so a run with no AI service set up no longer claims them either.

### v1.44.3 -- Catch-up adds the `CLAUDE.md` canary (new check S13)

Every project's `CLAUDE.md` should open with the instruction-drift canary (guardrail 16), but no
check enforced it, so `/resume-it` never added it to a project that lacked it. New check **S13**
(Tier 0, auto-fix) does:
- No `CLAUDE.md`: it creates one that opens with the canary, filled from `builder_name`, or the
  `🐤 canary ok` fallback when there's no name.
- A `CLAUDE.md` without the canary: it puts the canary right under the title, or moves it there.
- S13 runs before S10-S12. All four write `CLAUDE.md`, so they run together as one change, and S11
  and S12 now land right after the canary instead of at the end of the file.

The build-verify summaries in `/make-it` and `/retrofit-it` now say S01-S13. Apps put through
`/retrofit-it` get the canary too, since its verify step runs every check.

### v1.44.2 -- `/nemo-it` never shows a secret value

`/nemo-it` reported secrets by printing them. Its production check printed whole `.env` lines,
so a `DATABASE_URL` showed its password in the conversation. Its hardcoded-secret checks printed
the matched line, which is the secret itself, and nothing stopped that text from being copied into
the attestation on disk. Now:
- The production check prints `file:line: NAME` only. A comment line no longer causes a false
  "this is your live system" stop. A setting whose name or value says production still counts:
  a missed stop costs more than a false one. An odd byte or a BOM in the file no longer makes it
  miss a line, and `KEY: value` and `APP-ENV=` settings count too.
- The hardcoded-secret checks print `file:line` only. A secret finding keeps its file, line,
  rule ID and kind, never bandit's `issue_text`/`code` or semgrep's `extra.lines`, which quote it.
- A new guardrail says a secret is reported by where it is and what kind it is, never its value:
  not in the conversation, the attestation (markdown, JSON or JUnit), or any finding field.

The AI-key check already printed names only (v1.44.0). It was re-checked on the same fake
project.

### v1.44.1 -- Safety update: PyJWT 2.15.0 in every app template

New apps start with PyJWT 2.15.0 instead of 2.14.0, which has two published advisories
(PYSEC-2026-4141, PYSEC-2026-4183). The pin changes in the three places it lives: the
fastapi-nextjs backend and both scaffolds' mock-oidc. Each file installs on Python 3.12 (the
Dockerfiles' base) with `pip check` clean, the backend's HS256 cookie and mock-oidc's RS256
`kid`-signed token both round-trip, and `pip-audit` reports nothing. Apps already built keep
their own pin; `/resume-it`'s dependency check picks it up there.

### v1.44.0 -- Fewer asks, no gate lost: six skills ask through the approval block

`/resume-it`, `/make-it`, `/argo-it`, `/retrofit-it`, `/nemo-it`, `/try-it` and the learnings ask now
ask through `references/approval-block.md`. Routine asks are removed: the skill proceeds and says
so. Consequential asks are batched into one decision-ready ask (what changes, the evidence, the
blast radius and undo, what is unusual, the one thing to check). Every high-stakes gate is kept as
active confirmation: the user picks or types the specific (the target, the items, the tool), never
a plain yes. No bare yes/no remains in these skills.

| Skill | Asks before | Asks after | High-stakes gates |
|---|---|---|---|
| resume-it | 30 | 24 | 4 kept + 1 conditional (sign-in, permissions, database changes) |
| make-it | 14 (10 interview) | 14 | 1 kept + 1 raised (pausing a security tool; sign-in / who-can-do-what changes mid-build) |
| argo-it | 23 | 17 | 6 kept, 2 of them tightened (the secret check before a redeploy, the troubleshooting re-send when CI never ran) + 2 added (the deploy save's keep-out list, its failed-save stop) |
| retrofit-it | 11 | 9 | 6 kept + 1 raised + 1 added (the plan, the checkpoints, the live database) |
| nemo-it | 3 | 2 | 1 kept + 1 raised (the live-system scan, the production-path start) |
| try-it | 6 | 4 | 1 kept (pausing a security tool) |
| learnings (learnings.md + callers) | 6 | 6 | none (one batched, decision-ready message)[^learnings] |

[^learnings]: learnings.md itself plus the callers this card reworked: try-it (two), resume-it, wrap-it and subagent-it; the try-it and resume-it ones are counted in those rows too. ui-gate.md's offer is on card E03-S16.

Gate column: *kept* = the same gate, now active confirmation; *raised* = an existing ask moved up
to high-stakes; *added* = a new gate; *tightened* = a kept gate that now fires in more cases;
*conditional* = fires only when a change touches sign-in, permissions or the database.

The card's (E03-S5) earlier rough counts (resume-it 37, make-it 31, argo-it 16, retrofit-it 14,
nemo-it 12, try-it 11) came from a grep with no recorded method. The table above is a line-by-line
inventory: an ask is any point the skill stops for the user's answer, and interview questions stay
word for word.

Also fixed on the gates' own paths:
- argo-it's secret check before a redeploy now actually runs. It used to read an empty diff and
  never fired. It reads unsaved edits, new files and unsent saved changes, and a secret already in
  a saved change stops the send. Its inline scan is a stopgap; a tested rebuild is filed as E02-S5.
- Deploy and snapshot saves never stage `.env` files, keys, SSH keys, keychains, credential files
  or local databases, at any depth, and a failed save stops before anything is sent.
- retrofit-it's snapshot is honest about what it can undo (your files, not your .env settings or data), and a failed save
  stops the run.
- nemo-it's read-only mode for live systems is really read-only (no form submissions, no sign-in,
  no injection probes) and fails closed: the active checks run only when the scan explicitly says
  it is not on a live system.
- Declined or left-out items stay out of later automatic steps (retrofit-it's verify, try-it's fix
  step, the catch-up workflow). The next /resume-it scan mentions them again; only an answer
  brings one back.

### v1.43.0 -- Every ask decision-ready; every weakened safeguard disclosed

`references/approval-block.md` is the working form of "Keep the human able to notice" for skills
and agents. An ask picks its tier first: **routine** steps proceed with a note, **consequential**
ones are batched into one ask, **high-stakes** ones need the human to state or pick the specific.
Every ask says what changes, the evidence, the blast radius and undo, what is unusual, and the one
thing to check; a "Recommended" option carries its strongest counter-argument.

Every agent that changes files -- the SDD test-writer, implementer and fixers, and every
`/dispatch-it` lane -- ends its report with a **SAFEGUARDS** line: "none", or each `--no-verify`,
skipped, deleted or loosened test, edited hook, CI step or evaluator, or wider agent/tool/CI
permission. A change the brief explicitly asks for (an expected value it states) is not a
weakening. The task reviewer gives a third verdict, **safeguards ✅ / ⚠️ / ❌**, against every line
the task produced: a weakening on no line is Critical and is undone; a disclosed one is undone, or
the human decides, and the ledger records it (`safeguards undone|accepted`) so it is never asked
twice. The adversarial reviewer reports hidden weakenings on their own output line, apart from
counterexamples; dispatch-it's integration step re-runs a lane once, then goes to the human.

Tested in scratch repos with the real templates: a loosened assertion hiding a regression and a
deleted test called a duplicate came back ❌ in 6/6 reviews; the disclosed variant came back ⚠️;
a test change the brief ordered came back ✅ (3/3, no false alarm); the adversarial reviewer put
the deleted test on its SAFEGUARDS line with a CLEAN verdict. The old reviewer prompt also caught
both plants (4/4) on these small diffs, so the gain is the required verdict, the disclosure to
check against, and a defined path for each outcome. The skills link the block as each one's asks
are reworked (E03-S5).

### v1.42.0 -- Live cards say how and when they'll be checked

Bug cards gain `signal:` (one line: how the fix is proved on the live system, read-only) and
`checkAfter:` (a release tag such as `v2026.10.17`, due on the date in its name, or a date). The fixing
lane writes `signal:` with its PR; ship sets `checkAfter:`. `reconcile --prs` won't move a merged card
to Live without a `signal:`. The board splits **Live, to check** (due now) from **Live, waits** (grouped
by release or date); `status` shows each due card's signal and flags Live cards with none. The
after-release sweep that runs the due signals is its own card, designed once real signals exist.

### v1.41.0 -- One safe way to write a card

`card.py` is now the only way skills write board cards. `append <id> <section>` takes text on
stdin, `set <id> key=value` sets or removes (`key=`) fields, and `new <epic>` files a card with the
next free id after a pull. Each one pulls first, writes the whole file at once, bumps `updated:`,
regenerates `BOARD.md`, and commits and pushes (or only stages, for a board inside a project). This
fixes the three write failures a docai dispatch hit: a `%` in `printf` cut a note short, zsh globs
skipped writes quietly, and an un-pulled board handed out a card id twice. `reconcile --prs` writes
through it too.

### v1.40.0 -- The plan keeps leading; a big epic stays readable

- **A plan stays in force for the cards it names.** The old rule (any candidate changed after the
  plan's date = stale, so re-plan first) went stale within hours on a busy board. The ~10-minute
  re-plan it demanded was skipped every time, and dispatch quietly fell back to the default order.
  Now a new bug still takes a free lane first, other cards added since go after the plan's waves,
  and you re-plan when every wave is merged, when the next wave is stuck on a held, waiting or
  blocked card, after a spike's finding, or when you ask. `status` says "covers N of M candidates;
  K new since" and flags a plan that ran out or is stuck.
- **An epic of more than 30 cards** shows its done cards as a count (`/backlog-it show <epic>` lists
  them) and groups its open cards by category. docai's BOARD.md: 494 → 361 lines. Display only.

### v1.39.0 -- Held high-stakes cards come back to you

Every `/backlog-it dispatch` now ends with what needs you: the decisions waiting on your answer,
then **every** held P1 high-stakes card, oldest first (P2/P3 held as a count). Dispatch rightly
never auto-starts those cards, but before this nothing brought them back -- a P1 like "the AWS
root account has no MFA" could sit for weeks. `status` shows the same list, a card already
waiting on you isn't listed twice, and `status.py --needs-you` prints just this section.

### v1.38.1 -- A stopped lane shows up in days, not weeks

`/backlog-it status` now flags a Now fixing card that hasn't changed in 2+ days as "lane stopped?"
(lanes work in hours), instead of waiting for the 14-day stall. The doctrine adds that a lane
that stops hands its card back -- the next stage, a `decision:`, or back to the backlog. No new
card field: a `lane:` field would go stale exactly when a lane dies.

### v1.38.0 -- Bug stages come from GitHub, not memory (`reconcile --prs`)

A bug card now records its fix PR in `pr:` (the fixing lane sets it when it opens the PR).
`/backlog-it reconcile --prs` -- no AI, a script -- reads each open card's PRs with `gh` and moves
it forward on facts only: every PR closed and one merged → Live, and a Checked card closes. It
never moves a card back or past Live (merged isn't deployed: the live check confirms that).
`dispatch` runs it first, and `/resume-it` and `/wrap-it` use it for their catch-up instead of
guessing which PR was the fix. It never guesses either: a card without `pr:` is listed to set.

### v1.37.0 -- `/backlog-it status`: where the board stands, in one report

Bare `/backlog-it status` prints one read-only report: what's in flight (by bug stage, not
status), what's next, opened vs. closed per week with a forecast, what needs you, what has
drifted, each epic's progress, and median cycle time. It's a script (`status.py`), not an AI
call: under a second on a 365-card board, and the same answer every run. Dates come from the
board's git history. `status <id> <status>` still sets a card. The board renderer's rules are now
shared with the report, and Next up now only ever names a bug, as the doctrine says (a story in a
bug epic could be picked before).

### v1.36.0 -- "Waiting on you": every decision in one list

A card blocked on your answer now carries the exact question in `decision:` (one line, any card
type). `BOARD.md` opens with a **Waiting on you** block listing them all as `id · the question ·
days since the card last changed`, and Now fixing, Next up, `plan`, and `dispatch` skip them. The
write that records your answer clears the field. Older cards marked `stage: Needs decision` show
too, flagged "question not on card". `regen-board.py --self-test` covers it.

### v1.35.0 -- Keep the human able to notice (against approval fatigue)

"Human in the loop" fails from both sides: agents route around safeguards, and people who approve
all day slide from evaluating to confirming. Every project's `CLAUDE.md` now carries a principle
that designs the loop so the human stays able to notice:
1. Ask less, ask better.
2. Make every ask decision-ready.
3. Evaluate, don't confirm, on high-stakes decisions.
4. Keep the human in practice (a digest of what ran automatically, situation briefs, occasional
   planted harmless flaws revealed right after).
5. Hide nothing: disclose any bypassed or weakened safeguard.
6. Alerts earn their noise.

New projects get it when `/make-it` writes `CLAUDE.md`. Existing projects get it through
build-standards check **S12**, via `/resume-it` and `/retrofit-it`. The text lives once, in
`references/human-in-the-loop.md`. The skill-level changes (the shared approval block, the digest,
the per-skill rework) follow as their own releases.

### v1.34.0 -- Settle, filter, verify in every project

Every project's `CLAUDE.md` now carries the **muddy-water principle**, so every assistant and
subagent working in it reads it on every turn:
1. **Settle:** reproduce it and find the root cause from ground truth before any fix.
2. **Filter:** one small, reversible change at a time, and never bypass a guard.
3. **Verify:** re-run the same reproduction and check the real system before the next change and
   before claiming done.
4. **Don't mistake stillness for clean:** close latent risks only on a positive re-check.

New projects get it when `/make-it` writes `CLAUDE.md`. Existing projects get it through
build-standards check **S11**, which `/resume-it`'s catch-up scan and `/retrofit-it`'s verify
add when it is missing. The text lives once, in `references/muddy-water.md`.

### v1.33.0 -- An adversarial reviewer tries to break each task (Helix slice 5)

After a task passes its spec and quality review, `/subagent-it` sends an **adversarial reviewer**
to break it -- **counterexamples only**: a concrete input, run and confirmed, that breaks a
requirement in the brief. Each one becomes a failing test by the test-writer, the implementer
fixes it, and the next round runs. **At most 3 rounds per task**; if Critical or Important
counterexamples are still open after round 3 the task stops and asks you, and Minor-only ones are
accepted and logged for the final review. Tasks with nothing to test skip it.

### v1.32.1 -- `plan` no longer schedules an empty epic

An epic whose cards are all done (a Bugs epic between bugs) was treated as work to plan, and the
checker demanded it be scheduled. A card is a candidate only when no card -- done or not -- names
it as `parent`; an epic with no cards at all still counts. `check-plan.py --self-test` covers both.

### v1.32.0 -- Tests first, by a separate author (Helix slice 3)

`/subagent-it` now runs a **test-writer** subagent (Sonnet) before each task's implementer. It
writes and commits failing tests for the brief; the coordinator **runs them and they must fail**
(red check) before any code is written; the implementer then makes them pass and **may not change
them** -- a `git diff` against the test-writer's commit rejects any edit. A test the implementer
thinks is wrong goes back to the test-writer. Tasks with nothing to test (docs, config, prompt
wording) skip the step.

### v1.31.1 -- The board's "Next up" names a bug you can start

"Next up" used to name the top backlog bug even when it was high-stakes or waiting on another
card (on 2026-10-08 the docai board showed a `stakes: critical` P1). It now skips both, quietly;
skipped cards still show with ⚠️ and their stage, and `PLAN.md` says why. `regen-board.py
--self-test` covers it.

### v1.31.0 -- /backlog-it plan: how to run each card, and in what order

- **`plan`** reads `handoff.md` and every open card, and routes each card to **solo**, **spike**
  (unknowns first), **`/subagent-it`** (3+ ordered tasks), or **`/dispatch-it`** (3+ independent
  cards), in waves that finish soonest with every gate held → `PLAN.md`
- **`check-plan.py`** gates the AI's plan: no shared files, data, or serial category in a
  parallel wave; high-stakes cards held; `dependsOn` order kept. If it fails, nothing is written
- Cards carry `mode:` (`mode <id> <mode>` to choose it yourself); `start` adds a mode line after
  the preamble, `dispatch` follows the plan's next wave, and the board shows `→solo`
- **Plan format** (Helix slice 4): `## Task N` plans next to their card (else
  `.make-it/plans/`), drafted for approval; `/resume-it` writes one first for 3+ ordered tasks

### v1.30.1 -- Each project's handoff syncs only with its own board

v1.30.0 let a folder with no board of its own sync its handoff with the personal board, which
mixed one project's cards into another project's `handoff.md`. Now a handoff syncs with the
project's own board, and with the personal board only inside that board's `repo` folder.
Running `/backlog-it` directly still works from any folder.

### v1.30.0 -- The handoff and the board agree on what's next

When a `/backlog-it` board exists (the personal board included), it owns *what's next*.

- **`/clear-it`** pulls the board, writes each Next Step as a card id under a copy of the
  status line, and files a card (capture, no questions) for any step that has none -- or cites
  the existing card when triage finds a duplicate. It never changes an existing card's status,
  and a board it can't sync never stops the handoff from being written
- **`/resume-it`** re-reads the cards a handoff cites; a card now `done` drops out and the
  board's current stage wins
- **`/wrap-it`** points `.make-it-state.md`'s next steps at the same cards
- Desktop's handoff skill skips the board (none is reachable there)

### v1.29.0 -- /backlog-it: the full personal-board feature set

`/backlog-it` now does everything a hand-tuned personal board does, and can be one board used
from any folder.

- **User-level settings** `~/.claude/backlog-it.json` -- one board (e.g. its own repo at
  `~/.claude/backlog`) used from any folder without project settings; new `repo` key names the
  code that `reconcile` and `groom` check against
- **Two ways in:** planned work (`epic` / `story` / `task` / `add`) asks 1–4 questions first;
  `capture` / plain text writes the card first, then an AI triage step files it (type, size,
  placement, duplicates, new epics when nothing fits) and batches the questions
- **`reconcile`** -- strict-JSON verdicts from a code → tests → live ladder, auto-apply only at
  ≥ 0.8 confidence and only reversible actions, `--fast` / `--deep` / `--dry-run` / `--dispatch`
- **`dispatch`** -- bug lanes first; with no bug waiting, one item at a time by verdict,
  `dependsOn`, `conflictsWith`, and file overlap
- **`groom`** -- Workflow fan-out by default, state digest (started / finished / stalled), safe vs
  gated ship tracks, `GROOM-PLAN.md`; **`groom strategy`** writes `STRATEGY.md` (north star,
  leverage graph, foundation vs polish)
- The full standing preamble, the high-stakes gate with its alignment brief, the design-doc
  template, and "verify, never block" grounding
- `regen-board.py` renders size chips, 📌 pins, and ⚠️ on epics too

### v1.28.0 -- UI gate: approve a clickable preview, then the built screens

Vibe coders can't read code, but they can click. Web apps now get a clickable preview before any
screen is built, and the finished screens are shown next to that preview before handoff.

- Added `references/ui-gate.md`. Part 1: `.make-it/design.md` from the ideation answers (no new
  questions) and a single self-contained HTML preview built on the scaffold's own layout and theme
  tokens, revised until the user approves it. That approval is the go-ahead to build. Part 2: the
  built screens and the approved preview, screenshotted side by side for a second yes.
- Runs in `/make-it` (before the build, and before `/try-it`) and in `/resume-it` for features that
  add or change screens; pages are built to match the approved preview. SDD briefs for UI tasks
  name the preview.
- Claude Desktop: the preview is made before the handoff and travels in the bundle.
- Scaffold `.gitignore`s ignore `.make-it/ui-review/` (regenerable screenshots).

### v1.27.0 -- Project learnings (LEARNINGS.md)

A correction made once stays made. Every generated project keeps a `LEARNINGS.md` that its
`CLAUDE.md` imports, so every assistant and subagent working in the project reads it each turn.

- Added `references/learnings.md`: what counts as a learning (the user's corrections after
  checking a result, plus lessons the agent learned the hard way), one plain yes/no before
  anything is saved, one line per rule, and a new rule replaces one it repeats or contradicts
- Build Phase A creates `LEARNINGS.md` and the `@LEARNINGS.md` import; new check **S10** lets the
  `/resume-it` catch-up add both to older projects
- `/try-it`, `/resume-it`, `/subagent-it` and `/wrap-it` offer learnings at their checkpoints
- `/dispatch-it` and `/git-it` now always load their full doctrine (`@` includes)

### v1.26.0 -- /backlog-it project board

A file-based Epic → Story → Task board that lives next to the code, so every session and agent
works from the same list of what's next and what's broken.

- Added `/backlog-it` and `references/backlog-board.md`: cards with frontmatter, a rendered
  `BOARD.md`, capture (card first, then batched questions), `start <id>` to recall a card as an
  editable prompt, plus `groom`, `reconcile`, and `dispatch`
- Bug queue with stages Reported → Cause found → Fix ready → Live → Checked, and up to
  `lane_cap` (default 3) parallel fix lanes that never share files or data; `serial` categories
  and the ship queue stay one at a time
- Per-project settings in `.claude/backlog-it.json` (board location, project name, lane cap,
  serial categories); optional Slack notifications that do nothing without a webhook
- Helpers `backlog/bin/regen-board.py` and `backlog/bin/slack-notify.sh`, with no hardcoded paths
- Wired in: `/resume-it` starts from Now fixing / Next up, `/dispatch-it` takes its lanes from
  the board, ship moves cards to Live and Checked, `/wrap-it` updates cards with the handoff,
  `/debug-it` and `/fix-it` file a card for a new bug first

### v1.25.0 -- Claude Desktop & Cowork plugin

`/make-it`'s guardrails now follow you into Claude Desktop and Cowork, environments with no
shell, no Docker, and no git. A generated plugin (`desktop/`, see [`desktop/README.md`](desktop/README.md))
carries the same rules there, with anything the sandbox can't run handed off cleanly instead of
silently skipped.

- Added the `make-it-desktop` plugin: `guardrails`, `make-it`, `debug-it`, `nemo-it`,
  `handoff`, and `safety` skills, generated from the same `.claude/make-it/references/*.md` rule files
  `/make-it` uses -- never a hand-copied fork
- `/resume-it` now detects a Desktop handoff (including a plan-only bundle with no code yet) and
  runs its deferred checks as the first work item
- Added Tier 0 guardrail 18a, "Re-verify on every code change" (`references/guardrails.md`), and
  the matching verify-step rule in `/debug-it`: a check from before the latest edit is stale and
  must not be reported as passing; re-run what's runnable, defer the rest
- Added operator safety rules (`references/operator-safety.md`, Tier 0 guardrail 16a), loaded by
  `/make-it`, `/resume-it`, and `/debug-it` and by every Desktop skill. Claude is instructed never
  to read or bundle secret files, to ask before opening the user's financial, legal, HR, or
  medical files, to treat web and document content as information rather than instructions, and
  to add MCP servers or connectors only from a trusted publisher after the user confirms.
  Desktop/Cowork adds browser-profile and permission-mode reminders, plus an admin checklist of
  organization settings that back these up
- `/resume-it` is instructed to gitignore the secret-file patterns and check `git status` before a
  Desktop bundle's first commit

### v1.22.0 -- Instruction-Drift Canary

Every generated project now ships a root `CLAUDE.md` whose first section is an instruction-drift canary. Models don't fail loudly -- they drift: silently dropping a rule, then making assumptions, then being confidently wrong. The canary forces any AI assistant to open every reply by addressing the builder by name; a reply that doesn't is the first visible sign a rule was dropped, so the rest of that output is suspect.

- Added Tier 0 guardrail "Instruction-drift canary in `CLAUDE.md`" (`references/guardrails.md`)
- `/make-it` preflight now asks "What should I call you?" and stores `builder_name`
- Build Phase A writes the project `CLAUDE.md` canary using `builder_name`, with a fixed `🐤 canary ok` token fallback when no name is given
- Added `builder_name` field to `templates/app-context.md`

### v1.20.0 -- Expert-Persona Layer

Before high-stakes work, skills now adopt a specialist persona instead of working as a generalist -- a role-prompting quality lever. The persona is auto-inferred from `app-context.json` signals x the active skill: no user prompt, never gates, and stays a generalist below threshold.

- Added `references/expert-personas.md`: persona catalog (identity + mental model + generalist blind spot + output standard), auto-inference rules, and skill invocation contract
- `/debug-it` adopts SRE / performance engineer; `/nemo-it` + `/fix-it` adopt application security engineer; `/argo-it` adopts platform / DevOps + SRE; `/retrofit-it` adopts software architect
- `/dispatch-it` and `/subagent-it` inject the matching persona into each spawned worker's brief (per-domain / per-task)
- `/make-it` Design silently infers the dominant persona and caches it in `app-context.expert_persona`
- Added `expert_persona` field to `templates/app-context.md`
- Added `confluence-docs/`: business-user documentation for the whole framework, with a "Which expert does the AI become?" section per skill

### v1.7.0 -- Variant System, Argo CD, and Build Hardening

Adds a plugin architecture for project variants, Kubernetes deployment via Argo CD, and multiple build quality improvements.

- Added variant/plugin system with registry, template, and PWA mobile as first variant (`/make-it mobile`)
- Added `/argo-it` skill: generates Kustomize manifests, CI/CD pipelines, and onboarding docs for any K8s cluster via Argo CD
- Added `/wrap-it` skill: saves progress, updates TODO/CHANGELOG/.make-it-state, shuts down containers cleanly
- Added automatic security hardening to build-verify (Part D): static analysis, dependency audit, AI safety checks with self-healing loop
- Added AI-powered upload pipeline with pre-flight checks (F10-F11)
- Added SSE streaming build standard (AI11-AI15) for AI chat features
- Added notification system build standards (N01-N08)
- Added deployment profiles with schema, architecture, and non-technical UX
- Added Dockyard Gateway auto-discovery for SSL proxy bypass (I08)
- Added `.dockerignore` and `load_dotenv(override=False)` guardrails (I09, I10)
- Added consistent DataTable and theme toggle enforcement (U08, U09, V12, V13)
- Fixed OIDC dual-URL trust check in scaffold
- Fixed cryptography pinned to 46.0.7 in mock-oidc scaffolds
- Fixed /retrofit-it mock-oidc seed script, scaffold README leaking into builds, resume-it AI prompt detection

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
