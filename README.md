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
- [For Administrators: Usage Reporting](#for-administrators-usage-reporting)
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

### The guard against `git push --force`

The installer adds one hook to your Claude settings (`~/.claude/settings.json`). It stops Claude
from running `git push --force` (or `-f`, `--mirror`, or a `+branch` push) in **every project on
this computer**, because those can overwrite work on GitHub that nobody has seen. `git push
--force-with-lease` still works. Everything else in your settings stays as it was, and a copy of
the old file is kept beside it (`settings.json.bak-<date>`).

To remove it:

```bash
curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash -s -- --remove-force-push-guard
```

On Windows (PowerShell): `$env:MAKEIT_FORCE_PUSH_GUARD = "remove"; irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex`

Once removed (that way, or by deleting it from `settings.json` yourself), later updates leave it
out. Deleting make-it's folder (`~/.claude/make-it`) also turns the guard off, so Claude's commands
keep working. To add it back, run the same command with `--add-force-push-guard` (on Windows, `"add"`).

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
| `/deadcode-it` | Finds code your app no longer uses, proves it with tools and a search, and removes it in small checked steps with a deletion log; asks you about anything it can't fully prove | Routine upkeep, or when `/resume-it` says unused code has piled up |
| `/resolve-it` | Takes a problem someone reported (or an alert, a failed job, a bug card) all the way to the person's outcome, checked on the live system: finds every cause behind it, fixes each one test-first with an independent review, drafts what to tell the person, and records what it learned so the next one is caught sooner | Something a person needed didn't happen, especially when the first fix didn't make it happen |
| `/threats-it` | Now its own skill, installed on its own: https://github.com/sealmindset/threats-it | A new threat lands and someone asks "does this affect us?" |

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
| `/nemo-it` or `/nemo-it full` | Everything: NeMo AI safety + OWASP + Dependencies + Static Analysis + Deep Code Audit |
| `/nemo-it audit` | Deep code audit only: reads the code for logic flaws (no running app needed) |
| `/nemo-it guardrails` | NeMo Guardrails AI safety testing only (6 categories) |
| `/nemo-it owasp` | OWASP Testing Guide (all 11 categories) + dynamic analysis |
| `/nemo-it deps` | Dependency vulnerabilities + container image scanning |
| `/nemo-it sast` | Static code analysis only (no running app needed) |

### What It Does

1. **Preflight** -- Detects your project type, installs security tools (with permission), checks if the app is running
2. **Static Analysis** -- Scans source code with semgrep, Bandit (Python), ESLint security (JS/TS) for vulnerability patterns
3. **Dependency Scanning** -- Runs npm audit, pip-audit, and Trivy to find vulnerable libraries and container images
   - **Deep Code Audit** -- Several reviewers read the code for flaws in the app's own logic (a login that can be skipped, one customer reading another's records); a separate reviewer tries to disprove each one. Only what survives is reported with a severity; a lead that needs a fact the code can't show is listed as "needs validation". It reads only: nothing is run, installed or sent. Uses Cloudflare's [security-audit skill](https://github.com/cloudflare/security-audit-skill) (MIT), vendored at a pinned commit in `.claude/make-it/security-audit/`. This is the longest phase and uses many agents; say `quick` for a shorter, partial pass
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

Its closing report says what really happened. Every in-scope finding ends with exactly one outcome -- fixed, changed but not re-checked, failed, needs a person, or not attempted -- and the counts add up; none of them is worked out by subtracting one report from the other. "Fixed" means the change was kept and the scanner that found the problem ran again in the new scan and no longer reports it: if that scanner did not run the second time, its findings are "not re-checked". "Ready to ship" is said only when the whole new report lists no critical or high finding, not only the ones the run set out to fix. The tests and the build run where they live (`backend/`, `frontend/`, ...), and each is passed, failed or not run from the command's own exit status: "no tests ran" and "the build was not checked" are never worded as a pass. The record is `.claude/make-it/scripts/fix-it-results.py`; `scripts/test-fix-it-true-results.sh` runs it against a small stand-in project and report (`scripts/fix-it-fixtures/`).

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

### Deep-audit findings: fixed without asking, on a branch

Critical and High findings from the deep code audit change who can do what in the app, so they get their own path. `/fix-it` fixes each one without asking: a test that shows the flaw first (it must fail), the smallest fix, then a fresh agent tries to get in another way. Each fix is its own commit on a new `fix-it/YYYY-MM-DD` branch. The skill never merges that branch: the report shows before, after, the test and the reviewer's check for each, and you keep or drop it. A fix that fails twice is undone and goes on the manual list. "Needs validation" leads are never fixed.

### Fix Strategies

The skill includes 13 automated fix strategies:

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
| Deep-audit findings | Missing permission check, cross-customer read: regression test, smallest fix, independent re-check |

### Git Strategy

Before making changes, `/fix-it` creates a rollback point (`git tag pre-fix-it`). You choose how to commit:
1. New `fix-it/YYYY-MM-DD` branch
2. Current branch, single commit
3. Current branch, one commit per fix category

When deep-audit findings are in scope there is no choice: the run uses a new `fix-it/YYYY-MM-DD` branch.

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
| **AI Prompt Template Validation** | Supply-chain injection protection: `validatePromptTemplate()` blocklist, immutable safety preamble auto-prepended at runtime, draft/test/publish workflow, variable interpolation sanitization, risk-flagged edits logged for security review (no skill flags them at ship: ship-it-guide.md, "What make-it runs before /ship-it") |
| **AI Safety Testing** | NeMo Guardrails with 6 test categories (prompt injection, jailbreak, toxicity/bias, topic boundaries, PII leakage, hallucination) -- the GRC-required attestation document comes from `/nemo-it` |
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
- Test runs: blocklist check + sanitize rendered output + all saved test cases + 5 adversarial inputs sent to the AI with the draft prompt (3 injection + 2 jailbreak; Prompt #10e names this step "mini NeMo", and it specifies no use of the NeMo Guardrails rails)
- All tests must pass before the prompt version can go live

**Variable Interpolation Safety:**
- Template variables (`{{vendor_name}}`, `{user_input}`) are sanitized through `sanitizePromptInput()` at render time
- HTML entities escaped in all interpolated values
- Prevents injection through template variables even when the template itself is clean

**Security Review Integration:**
- Risk-flagged edits (override warnings, system-category prompts) are logged with `risk_flag: true`
- No skill flags them for security team review at ship (ship-it-guide.md, "What make-it runs before /ship-it")

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

- Build-verify's own checks run no NeMo Guardrails test: check AI09 confirms in code that the guardrail files exist and the config references every rail, never a behavioral PASS
- Full suite (60+ tests) runs in `/nemo-it`, before `/ship-it` (ship-it-guide.md, "What make-it runs before /ship-it"): these are `/nemo-it`'s own cases, written each run, not the generated files in the table above. `/fix-it` runs the generated files when it verifies a fix, and with a live AI provider, when you pick it, `/nemo-it` runs them too, in their own block of the attestation (nemo-it.md, step 7b, lists when it cannot)
- Check AI09 has no fix-and-retest loop (it runs no test); /nemo-it reports its failures and fixes nothing. A /nemo-it run is recommended before each production deploy, and nothing in make-it enforces it
- The GRC-required AI Safety Attestation comes from `/nemo-it`, in `docs/attestations/nemo-it/`

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
- Mock OIDC provider (Python)

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
- **AI safety testing** (if app uses AI) -- NeMo Guardrails with 6 mandatory test categories; the GRC-required attestation for production deployment comes from `/nemo-it`
- **Prompt safety review** (if app uses AI + Tier 2/3 prompts) -- risk-flagged prompt edits are logged for security team review; no skill flags them at ship (ship-it-guide.md, "What make-it runs before /ship-it")

### Tier 2: IDE Extension

All of Tier 0, plus: extension manifest, scoped activation events, SecretStorage for tokens, bundled output, provider patterns

### Tier 3: CLI Tool

All of Tier 0, plus: argument parser, --help/--version, correct exit codes, structured output option (--json)

### Tier 4: Library / Package

All of Tier 0, plus: package manifest, type declarations, explicit public API, no circular dependencies

### Tier 5: API Service

All of Tier 0, plus: health check endpoint, OpenAPI spec, structured logging, consistent error format

---

## For Administrators: Usage Reporting

make-it itself sends nothing. To see how Claude Code is used across your organization, switch on Claude Code's own
usage reporting (OpenTelemetry) centrally, sent to a collector you run.
[`usage-monitoring.md`](.claude/make-it/references/usage-monitoring.md) is the guide: the managed-settings file with
every content flag off, how to deliver and confirm it, what is sent and what is not, what it does and doesn't tell you
about make-it, third-party providers, the collector token, and a notice to publish to your people.
`render-managed-settings.py` checks that file and renders the macOS plist and Windows registry forms.
`make-it-installed.sh` and `make-it-installed.ps1` let your device-management tool list which accounts have make-it
installed, and which version.
To count which of your repositories were built with make-it, and which make-it steps changed them, run the
read-only adoption scan described in [`adoption-scan.md`](.claude/make-it/references/adoption-scan.md); the two
pages say which questions each one answers.

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
Three things: (1) A `validatePromptTemplate()` blocklist that rejects known injection patterns, code injection, and encoded payloads on every save. (2) An immutable safety preamble that is always prepended to prompts at runtime -- admins can't see it, edit it, or remove it. (3) A mandatory test-before-publish workflow that sends 5 adversarial inputs to the AI with every draft prompt before it can go live (it specifies no use of the NeMo Guardrails rails). Additionally, template variables are sanitized at render time and risk-flagged edits are logged for security review (no skill flags them at ship: ship-it-guide.md, "What make-it runs before /ship-it").

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

### v1.71.33 -- /threats-it moves to its own repository

- **/threats-it now lives on its own** at https://github.com/sealmindset/threats-it, with its
  own installer, version and tests. It works without make-it.
- **make-it no longer ships it.** When you update make-it, it removes only the old copy it
  installed itself, and only files that are unchanged. A file you changed or added is kept and
  named. Your organisation profile in `~/.claude/threats-it/` is never touched.
- **To keep using it,** install it from its repository; the update tells you how, once.
- **The board's /threats-it cards** moved to the new repository's own board.

### v1.71.32 -- /backlog-it never shows another project's board

- **A folder with no board of its own shows no board.** Before, `/backlog-it` fell back to your
  personal board from any such folder, so a session started in the wrong folder listed another
  project's cards, and a capture there would have written to that board.
- **One rule, in one place, used by every helper and skill that finds a board:** a project's
  own board wins from its top folder and any folder below it (the search stops at a git
  repository's top folder); the personal board is used only inside its own `repo` folder;
  `$BACKLOG_DIR` still wins, with a line saying so when it isn't this folder's board.
- **A new board is never set up where it would clash:** not in the home folder, not inside
  `~/.claude`, not on an existing board, and not in a folder that holds the personal board's
  `repo`. Each time, one line says why.
- **A board made in such a folder before this release** no longer takes over the personal board
  inside its own repo; one line names it so you can move or remove it.
- **A personal settings file with no `repo`** is used nowhere until `repo` is set, and says so.

### v1.71.31 -- the board shrinks: cards combine without losing their point, shipped means done, and quiet cards can close

- **Cards combine.** `/backlog-it combine` proposes bundles of cards that change the same file,
  share one cause, or serve one goal. Nothing combines without your pick. A bundle is one piece
  of work; each card inside keeps its own check and closes only when that check passes.
  Un-bundling puts every card back exactly as it was.
- **A bundle never loses a gate.** It is held whenever any card inside it is high-stakes, waits
  on a question, or waits on other work, worked out each time the board is read.
- **Shipped means done.** The bug line is now Reported, Cause found, Fix ready, done. A card
  closes when its pull request is merged, a release holds it, and that release's checks passed.
  If the checks cannot be read, the card is left and the reason is said. `reopen` puts a card
  back in line with your words kept, and the first screen counts reopened cards.
- **Quiet cards can close after 30 days,** but only cards marked as safe to close, with the
  reason written on them. Groom marks them after reading the whole card, or you pick them. Any
  change to a card clears its mark. A bug, a high-stakes card, a rule the product must meet,
  your own report, a bundled card and a card other work waits on never close this way.
  `expire --dry-run` shows what would close and why.
- **Not built yet:** the weekly sitting, the daily release, test beds as part of a fix, and
  knowledge that saves itself are later tasks of the same card.

### v1.71.30 -- the activity log hides every secret; the seal is harder to fool; a report given to the board is never lost

Three fixes in one release.

**The starter app's activity log**
- **It shows only what is known to be safe.** Before, it hid seven named kinds of secret and
  let everything else through. Now a value is shown only under a name known to be safe and in
  a safe shape; everything else reads `***`. That covers names, values, incoming and outgoing
  addresses, and error text.
- **The console is covered too,** including an AI provider address with a password in it.
- **A failed outgoing call is recorded,** with the kind of failure and none of its text.
- **What it cannot hide,** stated in the rulebook: a secret that looks like an ordinary short
  word or number, and logs already written.
- **Not yet recorded:** three of the app's own sign-in calls. They sit in protected files and
  are on the board to be done together.
- **Apps already built** are offered the new masking at their next /resume-it.

**The seal**
- **A project can no longer make the seal run a command,** on any version of git.
- **A link to a folder is refused,** whatever it is called. Before, a changed file behind such a
  link could pass the check.
- **A refused seal writes nothing,** and never says "sealed".
- **An odd file name can no longer hide a change,** and an existing `.gitattributes` file is
  kept exactly as it is or the seal is refused.
- **The hostile-code check** got the same second guard.
- **Apps already sealed:** nothing new for most. An app with a link to a folder must replace the
  link before it can be sealed again. A file name holding a backslash or a line break needs one
  reseal.

**The board**
- **A report always becomes a card.** If the step that sorts a new report fails, the report is
  still filed with the person's exact words, marked "not sorted yet".
- **A card write says truly where it went:** sent to the shared board, or "written here, NOT
  sent", with the reason. A card saved here goes with the next write.
- **Two sessions filing at once no longer take the same number,** and a card that is given a new
  number says so in plain words.

### v1.71.29 -- the board's first screen says what to do next, speaks plainly, and reviews stop flooding it

- **A first screen that tells you what to do.** `/backlog-it` now opens with one recommendation
  and one-click choices, worked out by a written rule: answer what waits on you; release what is
  ready; sort out stuck pull requests; start the plan's next wave; re-plan; groom; or wait. It
  then shows only what needs you, what changed since you last looked, and one line on whether
  the pile is growing.
- **It says only what it can see.** A pull request is called reviewed only when its card records
  a review that said ready for that exact version. It notices when a card would change the same
  file as an open pull request, and recommends starting the others.
- **Held cards come as a short list.** The first screen names the three to five held cards that
  would free the most other work, for a weekly sitting, and counts the rest.
- **Plain words everywhere.** Every card and pull request is named by its title with its
  number. Messages are a few short lines: what happened, what it means for you, what you need
  to do. One update a day unless you are needed. Every question is one click.
- **Reviews sort what they find.** Important findings are fixed before a fix ships. At most
  five quick minor ones are fixed in the same work; the rest are dropped. A fault that was
  already there becomes a card only if it can hurt someone; otherwise it goes on a short
  running list for that area. Lanes no longer file follow-up cards by default. A fault that
  repeats for three review rounds goes to the owner as a choice.
- **Not built yet:** combining cards, the weekly sitting itself, the 30-day expiry and the
  daily release are later tasks of the same card.

### v1.71.28 -- checks that say they test the running app now do; /fix-it reports what really happened

Two changes in one release.

**Live checks**
- **The rulebook said the AI "checks the running app" for many checks, with no step that did.**
  Now 32 must-pass checks are marked as live, and each has a named step in the build's check
  that really exercises the running app. A test fails if a live check has no step.
- **Results are said truly.** The closing line counts what passed, what failed, what is a known
  gap in the starter code, and what was not run, with the reason for each. "Everything I
  checked works" is said only when nothing failed, nothing is a known gap and nothing was left
  unrun.
- **The test that creates, changes and deletes a record never touches your data.** It runs in
  a temporary copy of the app with its own empty database, which is removed afterwards. Your
  own database is counted before and after, and any change is a failure.
- **The copy is used only on a set-up make-it's build produces.** Anything else, such as an
  outside database or an added network, means that test is not run, and it says why. Nothing
  is started or removed in that case.
- **/resume-it runs a live pass** limited to checks that are free and change nothing.
- **A write route's permission check is tested two ways:** in the code, and by trying it as a
  person without the permission and as someone signed out.
- **The browser checks install the app's own browser tool once,** and are marked "not run",
  never "failed", when that is not possible.
- **Not proven:** the AI checks are not run against a running app anywhere yet. That needs a
  stand-in AI provider. An app whose set-up has been customised does not get its create,
  change and delete tested live. 25 other checks are still to be made live.

**/fix-it**
- **Its counts are true.** Each finding gets exactly one result: fixed, changed but not
  re-checked, failed, needs a person, or not attempted. They add up. "Fixed" needs a kept
  change and a new scan in which the same scanner ran and no longer reports it.
- **"Tests pass" and "the app still builds" are said only when they did.** A failed run is
  never read as "no tests found", and a build is checked in the folder where it lives.
- **"Ready to ship" is said only when the new report lists no critical or high finding at
  all,** not just none of the ones it set out to fix.
- **Known limit:** on an unusual project layout /fix-it may run the tests from the wrong
  folder and report passing tests as failing. It never reports failing tests as passing.

### v1.71.27 -- /threats-it names a failed search as failed; Java is allowed; the force-push guard stops refusing harmless commands

Three changes in one release.

**/threats-it never reads a failed search as "nothing found"**
- **One rule in every script:** each search is answered or FAILED. A failed one is named
  (which search, where, the status), and what it covers reads NOT ASSESSED, never "none",
  "no licence", "missing" or zero. Results that did come back are kept.
- **Later scripts carry earlier failures forward,** so a gap found early cannot read as clean
  later in the run.
- **A workspace you have no access to** is named "not assessed (no access)" everywhere and the
  run goes on. The run stops and asks only when nothing can be read at all, or when the failure
  is one a re-run can fix (too many requests, a server error, a time-out, a partial answer, an
  expired sign-in).
- **In the report:** anything not assessed says so in both documents; a statement that rests on
  it is "under investigation", never "not affected"; the verdict line is scoped to what was
  searched.
- **Safer by the way:** a sign-in token is never sent on to another server by a redirect, and no
  error text from a service is printed or stored.
- **Proven against a stand-in** for the services these scripts call, on this computer only. Not
  proven against a real tenant.

**Java is allowed**
- The rule that kept Java out of apps and tools (rulebook check X04, guardrail 12) is removed.
  It was there to limit licence scope, which is no longer a concern. Nothing replaces it, and
  nothing is moved onto Java: the practice sign-in service stays the Python one.
- Every other check keeps its number. The rulebook now has 249 checks, 87 of them must-pass.

**The force-push guard**
- **It no longer refuses commands that only mention a force push:** a commit message, a
  pull-request description, a note written to a file.
- **It refuses more real ones than before:** a force push run inside another command, through
  a shortened option, or hidden behind a planted end line. Nothing the earlier guard refused
  gets through, with one deliberate exception: writing the words into an ordinary file.
- **It is a guard against mistakes, not against hiding a push.** Its own header lists what it
  does not see.

### v1.71.26 -- /argo-it: people can sign in on the test copy on a cluster, and /argo-it says what sign-in will do

Before, an app deployed by /argo-it ran on the cluster but nobody could sign in, and /argo-it
never said so.

- **One new question at set-up:** who signs people in on the test copy. The practice sign-in
  (a list of pretend people, no passwords, behind an access code), or your organisation's
  sign-in. The live version always uses your organisation's.
- **The practice sign-in asks for an access code** before it lists anyone. Your DevOps team
  sets the code as a cluster secret. Without a proper code it shows a plain "isn't set up yet"
  page and signs nobody in. Anyone who has the code can sign in as any pretend person, an
  administrator included, so keep the test address off the internet.
- **Its admin side answers only its own start-up step,** and needs a secret as well. Other
  workloads on the cluster are refused.
- **It can never reach the live version.** A check before sending, and a step at the start of
  every build, fail if the live version's files mention it. A refused build publishes
  nothing.
- **Addresses follow one written rule,** so two people setting up the same app get the same
  files.
- **The live version always enforces strong keys.** A live copy with a weak key refuses to
  start.
- **The first deploy shows up straight away,** and /argo-it says what you will see while the
  first build runs.
- **Secrets in the onboarding notes are created without the value reaching a command line.**
- **Apps already built** get the updated practice sign-in at their next /resume-it. Until
  then /argo-it offers them only the organisation's sign-in.
- **Proven on a local test bed** by an independent run: running and signed in with no hand
  fix. **Not proven:** a real organisation sign-in, a cluster other than the test one, and
  GitHub itself. One-service apps are not offered the practice sign-in yet.

### v1.71.25 -- `.env` stays out of every image, and a worktree gets its own database port

- **Every image an app builds leaves `.env` files out.** Before, the backend image and both
  front-end images shipped the project's `.env` inside them, and so did the practice sign-in's
  image. Each build folder now has its own ignore file, and `.env.example` is still included.
- **The check finds every build folder by reading the Compose files,** so a service added
  later is covered without anyone remembering to add it.
- **A worktree gets its own database port.** Before, a second checkout of the same app pointed
  at the first one's database. The project name is also lower-cased, as Docker requires.
- **Apps already built:** the existing rulebook check already flags an image that can pick up
  `.env`, so /resume-it catches that part. Their `.env` still has the database port written
  in, so a new worktree of an older app points at the main checkout's database until that
  line reads the port from `DB_PORT`.
- **Not yet true, on the board as a card:** a worktree's other ports can still land on the
  main checkout's, and the seed script still uses the main checkout's ports.

### v1.71.24 -- the logs say who and from where and keep sign-in codes out; the hostile-code check confirms an old copy by its bytes; each /nemo-it scan has its own temp folder

Three fixes in one release.

**The scaffold's activity log**
- **It names the signed-in user** (id and e-mail) on every request, including a refused one,
  and records the visitor's address where it used to record the front end's.
- **Sign-in codes stay out of the console.** The server's console line no longer prints query
  strings. Tokens, cookies and codes are absent from the log, its API and its page. Logs
  already written keep what they hold.
- **A visitor's address is believed only from proxies you name** in `TRUSTED_PROXIES`. Compose
  names the front end. On Kubernetes, name the ingress's network and the front-end pods'
  network together; otherwise the proxy's address is recorded.
- **Personal data:** the log holds e-mail and visitor addresses in memory (10,000 events,
  emptied on restart). The visitor's address now also appears in the console line.
- **Apps already built** get these through /resume-it's catch-up (L09, L10, L11).
- **Not proven:** /argo-it does not set `TRUSTED_PROXIES` yet, and no cluster run was made.

**The hostile-code check**
- **An old copy counts only when its bytes match.** The check finds a possible old copy by
  git's id for the file, then compares the bytes git holds with the file on disk. Only an
  exact match softens a stop. The same id with different bytes keeps the stop and adds a note.
- The id's hash is now marked as not used for security, which is true: the bytes decide.

**/nemo-it**
- **Each scan makes its own private temp folder** and removes only that one. Before, a second
  scan started while the first was running deleted the first one's files.
- **The cleanup cannot widen,** and folders left by an earlier version are named, never
  deleted.

### v1.71.23 -- the board's helpers work under any locale, and a task brief takes a task number only

- **The six board helpers no longer crash on a non-ASCII title** when the computer's locale
  is not UTF-8. Before, a card could be written and the helper would then crash while
  printing, so a save that worked looked like one that failed.
- **Input is strict; output never crashes.** Text that is not UTF-8 is refused with nothing
  written, so a card is never stored with garbled characters.
- **Odd cards are handled plainly.** A card that cannot be read is named, left out of
  listings, and never written to. A card keeps its own line endings on a one-field change.
- **`task-brief` takes a task number and nothing else.** Before, a pattern in its place could
  copy the whole plan into one task's brief.
- **On a plain ASCII board nothing changes:** output, exit codes, commits and files are
  byte-identical to the last release.
- **Checked on Linux and macOS, not Windows.** Card writes do not run on Windows today.

### v1.71.22 -- a crash in the secret scan is reported as a crash, and the version that crashed is replaced

Every app built with make-it pinned gitleaks v8.22.1. Built with a recent Go, that version
crashes on Intel processors that have a fast string-copy feature. Every save was then
refused, and the person was told a password or key had been found when none had.

- **The scan is pinned to v8.29.1** in both scaffolds, which carries the upstream fix and
  still builds with the Go most people have. On the affected processors the old version
  crashed 310 times out of 310; the new one, 0 out of 310.
- **A found key is reported only when the scan names one.** A crash, a scan that stopped
  partway, or a tool that could not be set up each gets its own true sentence. The save is
  still refused in every case.
- **A found key outranks a lint failure** when both stop the same save.
- **Apps already built get the new version at their next /resume-it,** as one changed line,
  saved on its own, with a one-line note. It never lowers a newer version, leaves a
  customised hook alone, and puts the old line back if the new version cannot be set up.
- **The scaffold's CI check downloads the same pinned version** and verifies it against the
  publisher's checksum.
- **Not reproduced on a developer machine:** the crash needs the affected processor. The
  figures above come from probe runs on GitHub's runners.

### v1.71.21 -- /threats-it's fetch, build and hunt scripts report a failure as a failure

Four places in /threats-it's scripts could turn a failure into something that looked like a
result.

- **Fetching a source:** a failed download was logged with a meaningless code, a missing file
  stopped the script before it logged anything, and the page from the last run stayed in
  place. Now the old page is removed first, the real result is logged, and a failed or
  timed-out fetch is refused.
- **Building the reports:** a failure in the document converter was hidden. Now the build
  stops with an error.
- **Hunting:** a quote character in a search prefix or pattern broke the query. Both are now
  passed safely.
- **The indicator search no longer reads "none" when its query failed.** It names the
  workspaces where the query failed.
- **Known limit, on the board as a card:** other failed queries in the web hunt (a workspace
  that cannot be read, the crash and large-upload searches) and three scripts this release
  does not touch (exposure, tenant access, technique lookup) can still read as "nothing
  found" when a query fails.

### v1.71.20 -- the workflow /argo-it generates can build and deploy an app made from make-it's scaffold

Run as released, /argo-it's generated workflow failed on every app built from make-it's own
scaffold: five failed runs and six hand fixes before the app came up on a test cluster.

- **The first deploy works with no hand fix.** Proven on a local test bed (a git server with
  a runner, a registry, a cluster with Argo CD) by an agent that did not write the fix.
- **The migration check reads make-it's own migration files,** and only reads them: it never
  runs a file from the repository. It fails naming the file on a broken chain, and now runs
  on pull requests too.
- **Each service builds from its own folder,** with its own image-tags step.
- **The workflow deploys the version the same run built,** labelled by its commit.
- **Nothing is offered for use before it passes its check.** The smoke test starts the real
  app beside a throwaway database. Only after it passes are the moving labels added and the
  deploy branch updated. A service with no health check must still be running after 30
  seconds.
- **The workflow folder stays out of the deploy branch,** and pull requests no longer share
  a queue with deploys.
- **Known limits.** Sign-in does not work on the cluster yet: the app runs, but nobody can
  sign in. The front end gets no smoke test. GitHub's own registry, queueing and token rules
  are proven on the local bed only. Building the same commit twice can replace its image
  before the second smoke test.

### v1.71.19 -- A guide for administrators to Claude Code's own usage reporting, and what it says about make-it

An organization that adopts make-it wants to see how it is used. Claude Code already has its
own usage reporting, which the organization switches on centrally. make-it sends nothing itself.

- **A guide for administrators.** `usage-monitoring.md` shows the settings to switch the
  reporting on with every content flag off, how to deliver them, and how to check them.
- **What is sent and what is not, in one table.** Prompts, replies, code, commands and file
  paths are not sent with the flags as the guide sets them.
- **It says plainly what the reporting shows about make-it.** The name of each make-it command
  a person runs is sent by default, with its cost. This was observed on Claude Code 2.1.330.
- **A notice to publish.** A short text, with a full table under it, that tells people what is
  recorded about them.
- **A small script** turns the settings into the Mac and Windows forms and refuses malformed
  input, an unfilled placeholder, or a content flag switched on.
- **Who has make-it installed.** Two read-only checks, for Mac or Linux and for Windows, read
  the version file the installer writes, so a device-management tool can list machines and
  versions. They change nothing and contact nothing.
- **Known limits.** Not yet rolled out through a real device-management tool. Reporting shows
  cost and activity; showing value needs a before-and-after measurement.

### v1.71.18 -- A read-only scan that sorts an organization's GitHub repositories by make-it use

An organization that adopts make-it had no way to count which of its repositories were built
with make-it, which use AI without it, and which show neither.

- **One script, read-only.** `adoption-scan.py` reads GitHub through the `gh` sign-in you
  already have. It never clones and never writes: only queries and read requests can leave it.
- **Five classes.** Built with make-it; make-it without a build record; Claude Code without
  make-it; no signal; not scanned. Older apps are found by make-it's decision file, since the
  build record is newer than they are.
- **A miss is never read as "no signal".** A lookup that fails is "not scanned". A listing that
  stops partway, or a search GitHub capped, marks the result incomplete or partial on screen
  and in both output files, with its own exit code.
- **Names stay off the screen.** Repository names go only into files private to you, and the
  scan refuses to write them inside a git project.
- **It works on a personal account too,** with `--user`.
- **Known limits.** Not yet run on a large organization, GitHub Enterprise Server, or an
  organization with single sign-on. Presence of a seal is not proof it is intact.

### v1.71.17 -- The seal check says what actually differs when the version matches and the content doesn't

When an app was sealed by an organization's own build of make-it, the check failed with a line
that showed the same version number twice, as if nothing differed.

- **The message names the difference.** Same version, different content: it shows a short form
  of each content fingerprint, and says the app was sealed by another build of make-it, or the
  record was edited.
- **It points to a reviewed build.** An organization that ships its own build checks apps
  against that reviewed build, never one the app's author supplies.
- **A record with no content fingerprint** gets its own message.
- **A new section in the seal's reference** says how an organization with its own build runs
  the check against its own releases, and that the GitHub job accepts any version tag in the
  repository it is pointed at.
- **No verdict changed.** The same cases pass and fail, with the same exit codes.

### v1.71.16 -- The git guards are switched on, and the scaffold's secret scan really scans

Every app shipped with checks that run before each save, but nothing switched them on. And
the scaffold's secret scan had no rules, so it found nothing, in the hook and in the app's CI.

- **The hooks are on.** The build installs them and requires them (Q12 is now must-pass);
  /resume-it's catch-up installs them in apps built earlier. A skill that saves for you
  refuses when they are off.
- **The secret scan has rules.** The scaffold's gitleaks config now uses gitleaks' defaults,
  and no longer skips `tests/` or `mock-services/` (Q08).
- **New projects work on a branch called `work`.** The main copy stays clean until you ship.
  Catch-up moves an older app there too.
- **A guard refuses Claude's `git push --force`** in every project on the computer;
  `--force-with-lease` still works. The installer says so, backs up your settings first,
  and a guard you remove stays removed.
- **Lint checks run in the app's container** and are skipped, with a line saying so, when
  Docker isn't available. The security checks never skip.
- **Known limits.** Not yet proven on Windows or in a full build. The first ship of a new
  project needs the main copy pushed once by hand.

### v1.71.15 -- /argo-it's secret check is a tested script, and nothing is sent or restarted without your pick

/argo-it looked for passwords and keys with a pattern written into its instructions, and
some paths went around it: troubleshooting could push a fix or restart the live app on its own.

- **The check is a script with tests.** `secret-scan.py` scans exactly what will be sent,
  against what is already online, and shows only the file and line, never the value.
- **A send carries only what you agreed to.** A new save, a new file, a branch switch, or a
  save added by one of your project's own steps after the ask stops it.
- **Unsaved code stops the first deploy** before the seal is taken, so the seal matches
  what goes online.
- **Troubleshooting never pushes.** A fix it makes stays unsaved and goes through the
  redeploy and its pick.
- **Restarts and re-runs ask first,** and only on the app's own cluster, matched by name
  and server address. Setup asks once which cluster that is.
- **Known limits.** Save messages are not scanned; not yet proven on a real cluster.

### v1.71.14 -- One project specialist per app, recorded once and read by every skill that touches code

Each skill used to pick its own expert from whatever it noticed, so the same app could be
built by one specialist and checked by another, and nothing recorded who.

- **One record.** `app-context.json` holds the project specialist: who leads, who else is
  added, the reasons, and which skill set it. Security leads, then data, reliability and AI.
- **Three writers.** /make-it and /retrofit-it write it; /resume-it re-checks it when planned
  work changes a reason. A later writer starts from what is recorded and changes only what
  its own evidence shows. A change in who is named is said in one plain line.
- **Older apps catch up.** New check S15 brings an older value up to date once.
- **Every reader adds its own.** /debug-it, /nemo-it, /fix-it, /argo-it, /try-it,
  /deadcode-it and /resolve-it work as their task specialist, held to the recorded
  specialists' checks. /subagent-it and /dispatch-it hand the record to every agent.
- **Not yet proven by a real run.** The rule is pinned by contract tests and paper checks.

### v1.71.13 -- The build's security pass runs from pinned Docker images, through one tested script

The build ran its security scanners from whatever happened to be installed on the computer,
so two machines could give two answers, and a scanner that was missing could read as clean.

- **One script runs the pass.** `security-pass.py` runs Semgrep, Bandit, npm audit, pip-audit
  and Trivy from pinned images. Nothing is installed on the computer for it.
- **A scanner that can't run says so.** It is recorded NOT RUN with its reason, never as clean
  or as no findings.
- **pip-audit only sees a file the script wrote.** Each requirements file is rewritten from a
  strict line grammar; anything outside it makes that file NOT RUN.
- **Build-verify Part D is pinned whole** against a saved copy, so a change to it is a visible
  two-file change.
- **Known limits.** Docker must be running; Windows is refused; /make-it and /resume-it still
  run two audits on the computer outside Part D for now.

### v1.71.12 -- The scaffold's quality-gate workflow keeps the branch name out of its shell commands

The workflow every web app gets put the pull request's branch name straight into a shell
command. GitHub pastes that value into the script before the shell runs, so a branch named
with shell code would run it.

- **The scaffold is fixed.** The branch name, the commit and the step results now reach the
  script through `env:` and are used as quoted variables. The attestation it writes is the
  same for an ordinary branch.
- **How serious it was here: not very.** This workflow runs only on pull requests, where the
  pull request's own code already runs in the same runner with the same read-only token. The
  branch name gave an attacker nothing extra. In a workflow with a `pull_request_target`,
  `issue_comment` or `workflow_run` trigger the same pattern is a real hole, which is why it
  is kept out of every workflow.
- **New build check Q16, blocking.** No `${{ }}` expression in a workflow step's script text
  under `.github/workflows/`. It is not marked as a security fix: an alarm for something that
  cannot be exploited here would teach people to ignore the next one.
- **Apps already built** fail Q16 until they are updated. `/resume-it` offers it with the other
  must-do updates and fixes it when you pick that group.
- **Not covered, and the check says so.** Composite actions, and GitLab, Jenkins and Azure
  DevOps pipelines. The workflow file is also not one of the files an app's seal compares
  with the release.
- **Checked:** `scripts/test-workflow-no-expression-in-run.sh` (22 planted opposites, each
  caught), Semgrep before and after, and the step run on this computer with hostile branch
  names: the old script ran one, the new one treats it as text. Two independent review rounds.
  Nothing hostile was pushed, and no pipeline run on GitHub exercised the fixed workflow.
- **A tripwire, not proof.** The test reads lines, not YAML: quoted keys, anchors and flow
  mappings get past it, and its header lists them.

### v1.71.11 -- A build fails when an app adds model training, fine-tuning or retrieval

The governance document said data poisoning was covered, and listed controls that guard the
app's own prompts. Data poisoning is about training data, fine-tuning data and retrieval data.
make-it apps have none of those, so the honest answer is "not applicable", and now a check
holds that line.

- **New build check AI30, on every app.** It reads the app's dependency files and code for
  training libraries and loops, fine-tuning calls, embeddings calls and vector stores. A hit
  blocks the handoff.
- **Nothing is removed on its own.** You are told what was found and where. The code comes out
  only at your word, or you accept it.
- **Accepting it** is one line in the app's own record of things left out by your choice.
  The check then reads "Left out (your choice)", never passed, and `/ship-it` names it before
  production.
- **A tripwire, not proof.** A library under another name gets past it, and an unrelated
  `.fit(` trips it. It shows the app holds none of these; it does nothing to protect training
  or retrieval data once you accept one.
- **The governance row** for data poisoning now reads "Not applicable, enforced by check AI30".
- **Checked:** `scripts/test-ai30-training-retrieval.sh` (52 checks, 17 planted defects, each
  caught), both scaffolds, and one real generated app: no hit. No real build ran the check,
  and this change had no independent review.
- **Not built.** The same scan in an organization's pipeline, with its own exceptions list.
  Only the build check exists.
- **Known and filed.** A first `/make-it` build whose idea needs retrieval is blocked with no
  way to accept it; `/resume-it` and `/retrofit-it` can record the choice, `/make-it` cannot
  yet. The optional AI memory layer is not covered by this check.

### v1.71.10 -- /retrofit-it logs a missing AI-safety control in code you already had

`/retrofit-it` checks an app against the same list a new build is checked against, and its rule
for a failing check was "fix it at once". On a retrofit that rule landed on AI code you wrote:
it was changed without a word, by a rule meant for code a build had generated minutes earlier.

- **Logged, not added.** When the check finds a safety control missing in a file the app
  already had (a sanitizer or output-validation call, delimiter tags, rate limiting on an AI
  route, the safety preamble), `/retrofit-it` changes nothing in that file and writes one line
  to `TODO.md`. `/fix-it` applies the fix, with an ask.
- **How it tells.** By the snapshot `/retrofit-it` takes before it changes anything. A file in
  the snapshot is yours. A file that is not was added by the retrofit, and is still completed.
- **Still fixed at once on your code:** error sanitizing, the prompt size limit and unsafe HTML
  rendering. They close leaks and do not change what the AI says.
- **Security fixes still block.** The Claude-subscription provider check (AI29) is never turned
  into a `TODO.md` line.
- **`/make-it` is unchanged.**
- **Checked:** `scripts/test-retrofit-ai-safety-logs.sh` (22 checks, 9 planted defects, each
  caught). It pins the wording; no real retrofit was run, and this change had no independent
  review.

### v1.71.9 -- Security fix: the Claude-subscription AI provider gives the model no tools

The scaffold's Claude-subscription provider sends what an app's users type to the Claude Code
CLI, a coding agent that can run commands and read and write files. Its comment said "pure text
completion -- no tools". That was wrong: it turned the CLI's permission checks off and removed
no tool, so anyone who could type into an app's AI chat could have the assistant run commands
in the backend, next to the app's secrets and the owner's Claude sign-in.

- **Who is affected.** An app that runs on this provider with a sign-in token in it. An app on
  another provider carries the same file, unused.
- **No tools, nothing loaded.** The provider now passes an empty tool list, names every
  built-in tool as disallowed, uses the `dontAsk` permission mode, refuses any tool call in a
  hook, loads no settings, skills or MCP servers, and runs in an empty folder.
- **Checked before the reply.** The CLI reports the session's tools before the model runs. If
  that report shows a tool, an MCP server or another permission mode, the call ends there.
- **An alarm on the reply.** A reply that shows a tool call ends the call and leaves a log
  line. This detects; it does not prevent, because the CLI runs a tool before the provider can
  read the message. A stopped call is never retried on the failover provider.
- **No transcript kept.** The CLI is told not to save each prompt and reply on the backend's
  disk.
- **New build check AI29, marked `[SECURITY FIX]`.** `/resume-it` shows a failing one first, on
  its own, and says what is exposed. "Not now" lets the session go on and nothing else: it is
  asked again every session and still blocks the handoff to `/ship-it`.
- **Checked:** the scaffold's provider tests (58 with the SDK, now run in CI) and
  `scripts/test-claude-agent-text-only.sh`, with 23 planted defects, each caught. One
  independent security review; its six findings were fixed in this release.
- **Not checked.** No call to a real model was made. The session check, the alarm and the
  no-transcript flag have not seen a live session. If a real text-only session reports a tool,
  every call on this provider stops until that is fixed.
- **Known and left.** The CLI process still inherits the backend's environment variables. The
  scaffold's Docker Compose file publishes its ports on every network interface (filed, not
  fixed here).

### v1.71.8 -- The build's security scan logs missing AI-safety wiring and no longer fixes it silently

The scan a build runs on the app it just generated contradicted itself. One step said it adds
missing AI-safety calls without asking. The same file said only fully mechanical fixes are
silent, and the fix list classes those calls as needing a look.

- **Logged, not fixed.** When the scan finds a safety control missing or not wired in (a
  sanitizer or output-validation call, delimiter tags, rate limiting on an AI route, the safety
  preamble), it writes one line to `TODO.md` and changes nothing in the app. `/fix-it` applies
  that fix, with an ask.
- **The scan runs no NeMo Guardrails test** for such a finding, and does not run the app's
  guardrail suite.
- **This is about the scan's findings only.** Before the scan, the build's own checks still
  complete the app it is generating: a safety control one of those checks finds missing is added
  then, as before.
- **Checked:** `scripts/test-scan-ai-fixes-log-only.sh` (28 checks). It pins the wording; no real
  build was run, and this change had no independent review.
- **Known and filed, not fixed here.** `/retrofit-it` applies those same build checks to code you
  already had, without asking. And the scan's fix list still moves hardcoded secrets silently,
  along with a few other fixes its own rule says must not be silent.

### v1.71.7 -- The compliance documents stop presenting NeMo Guardrails as a run-time control

A build writes NeMo Guardrails files into every AI app: a config, five rails and six test files.
They are test-time files. Nothing make-it generates loads the rails when the app runs. The
governance and pentest-readiness documents said otherwise in about twenty rows ("topic boundary
enforcement", "hallucination detection", "toxicity/bias detection").

- **Those rows now say what is true:** NeMo here is a test suite, run when someone runs it, not a
  run-time filter. Each row names the control that does act when the app runs, where one exists.
- **Three verdicts changed** in `docs/PENTEST-READINESS.md`, each decided by the project owner:
  - *Harmful Content Generation* is now **GAP** (was COVERED). Nothing generated filters toxic or
    biased AI output. It is listed as a new gap, GAP-26.
  - *Direct Prompt Injection* is now **PARTIAL** (was COVERED), and the risk for direct injection
    is Low-Medium (was Low). The sanitizer replaces a fixed list of known phrases; a reworded
    injection is not caught. The row's example claimed a phrase was "blocked" that the list does
    not even match.
  - The two competitor and reputational rows stay PARTIAL, on a model instruction alone.
- **`/nemo-it`'s attestation table agrees.** Jailbreak, hallucination and topic boundaries name
  their real control and stay "Reduced"; toxicity and bias is "Not covered"; prompt injection is
  "Reduced" (was "Prevented").
- **"Present and wired" is gone.** Check AI09 confirms the guardrail files exist and the config
  references every rail, and the documents now use those words.
- **New apps say so themselves.** Each generated `guardrails/README.md` now opens by saying the
  rails are loaded by the tests only.
- **Checked:** `scripts/test-nemo-rails-not-runtime.sh` pins the changed rows with their verdict
  words. One independent review confirmed that no scaffold file, overlay or build prompt loads
  the rails. No real `/make-it` build was inspected.
- **Worth knowing:** several AI controls these documents list exist as build-prompt instructions,
  not as scaffold code. In the scaffold today only error sanitization is called; the build is
  what adds the rest.

### v1.71.6 -- /fix-it asks properly before it rolls back, keeps a fix, or moves a secret

`/fix-it` still had two bare asks: a numbered "would you like me to" menu before a full rollback,
and "let the user confirm" for fixes that change how the app's code works.

- **A full rollback is its own ask, and never a plain yes.** It says which check is failing, exactly
  what a rollback discards (the fixes that pass included), what happens to work you had before the
  run, and what can and cannot be brought back. Rolling back is never the recommended option, and
  nothing is rolled back unless you pick it.
- **Fixes that change app logic: one pick-list per step.** Each fix is its own pick, shown with its
  diff. There is no "apply all". A fix you do not pick is reverted and goes on the manual list;
  dismissing the ask keeps nothing.
- **A fix that moves a secret is asked separately and never shows the value.** It names the file,
  the line and the kind of secret, shows the diff with the value hidden, and says what git shows
  about `.env`. It also says what the move does not do: the old value is still in git history and
  should be rotated, and `/fix-it` does not rotate it.
- **Every earlier gate is kept:** approval before any change, the save choice with its "not now",
  the per-fix revert before any full rollback, and the ten guardrails.
- **Checked:** `scripts/test-fix-it-asks.sh` (90 checks). It pins the wording; no real `/fix-it` run
  was made, and this change had no independent review.
- **Known and filed, not fixed here.** `/fix-it` moves uncommitted work into git's stash before it
  starts and never puts it back. And its hardcoded-secret fix never checks that git ignores
  `.env`, so a value written there can be committed. The new asks tell the truth about both.

### v1.71.5 -- /nemo-it can run your app's own guardrail tests too, when you pick it

A build writes a guardrail test suite into every AI app (`guardrails/tests/`). `/nemo-it`, whose
result goes into the safety attestation, never ran it: it only ran cases it wrote itself.

- **A second, separate block in the attestation.** With a live AI provider, and when you pick it
  in `/nemo-it`'s preflight ask, `/nemo-it` runs the app's own suite once and reports it beside
  its own 60 or more cases. The two are never merged, and the overall AI-safety result is the
  worst block.
- **It asks every run, and a yes is never kept.** Running those tests runs your project's own
  code on your computer with your account's access. The ask says so, says what the hostile-code
  check found (a tripwire, not a guarantee), and says there is no undo. Not picked: that block
  reads NOT TESTED.
- **NOT TESTED is never a pass and never a fail.** It is what the block says when the suite could
  not run: no pick, no reachable AI provider, a live system, a missing tool, or a test that could
  not load. A project with no suite gets no block at all.
- **Expect NOT TESTED often, for now.** The app's tests need the AI provider's key and `/nemo-it`
  gives them none. Getting a key to them safely is a separate change, not in this release.
- **It is evidence, not proof.** The results come from code the project controls, and there is no
  sandbox. Afterwards `/nemo-it` lists the files in the project folder that the run added,
  changed or removed (git hooks and permission changes included; installed-package folders and
  anything outside the project are not covered). It never edits a test and installs nothing in
  that step.
- **Fixed on the way: preflight could run a file planted in a project.** The checks for pytest and
  pip ran from the project folder, so a `pytest.py` or `pip.py` at a project's root was executed
  in every scan, with no ask. They now run from an empty temp folder.
- **Checked:** `scripts/test-nemo-it-runs-app-suite.sh` (73 checks) pins the new step, the ask and
  the attestation section, and runs the result reader on a sample file. Two independent reviews.
  No real `/nemo-it` run and no real generated suite were run.
- **Known and filed, not fixed here:** `/nemo-it` offers to start the app before the hostile-code
  check has run; `npx` can run a tool planted in a project's `node_modules`; and a few later
  result readers still run Python from the project folder.

### v1.71.4 -- Nothing claims a NeMo test runs at build, and the two guardrail suites are named apart

Check AI09 said "Basic suite (18 tests) passes" at build. No file defined those 18 tests, the check
runs before the app starts, and a build often has no AI provider. A dozen places repeated the
claim, some of them read by compliance reviewers.

- **AI09 is a code-level wiring check.** It reads the guardrail config, the five rails, the six
  generated test files, the dev dependency and the run command. It runs no NeMo Guardrails test,
  and a code-level result is never reported as a behavioral pass.
- **There are two suites, and the documents now say so.** The build generates the app's suite in
  `guardrails/tests/`; `/fix-it` runs it when it verifies a fix. `/nemo-it` does not use it: with
  a live AI provider it writes and runs its own 60 or more cases, and the attestation is based on
  those. With no reachable provider, or read-only against a live system, `/nemo-it`'s AI-safety
  checks are code-level only, never a pass.
- **A `/nemo-it` run is recommended, not enforced.** The governance document said the 60 tests
  run "before deploy"; nothing in make-it makes anyone run them. The risk row for this is now
  rated Medium (was Low).
- **The NeMo fix-and-retest loop at build is gone from the documents,** because no test runs
  there. The security scan's own fix cycles (up to 3) are unchanged, and the count is now stated
  in the steps that run the scan.
- **Also corrected:** the build's AI endpoint probe (3 payloads, when the app is running) is named
  as a separate, smaller check; `build-verify-security.md` calls itself Part D throughout;
  `nemoguardrails` is a Python dev dependency for Node apps too.
- **Checked:** `scripts/test-ai09-code-level.sh` pins the exact sentences and table rows across
  every Markdown file, after three independent reviews. It is a tripwire, not a proof: it cannot
  catch a claim split across sentences, other words for "build" or "pass", or non-Markdown files.
  No real `/make-it`, `/nemo-it` or `/fix-it` run was made.
- **Known and filed, not fixed here:** the security scan contradicts itself on whether it applies
  AI-safety wiring fixes silently; `/nemo-it` never runs the suite a build generates; and some
  compliance rows still present NeMo rails as runtime enforcement, which no generated app has.

### v1.71.3 -- /argo-it's lint auto-fix is limited to safe fixes, and it says which files it changed

`/argo-it` told itself two things that could not both hold: auto-fix lint errors in the app's
code before sending, and never modify application source code.

- **Safe fixes only.** Step 3a now runs `ruff check --fix --no-unsafe-fixes` and
  `eslint --fix --fix-type layout`. Formatting is tidied; nothing that rewrites what the code does
  is applied, even when the project's own settings turn unsafe fixes on.
- **It lists each file the fixes changed** before it saves anything. A note, not a question.
- **The rule is now "never change how the app behaves".** `docker-compose.yml` is still never
  modified. Any other change to the code waits for the person's pick.
- **JavaScript import order is not fixed silently.** eslint cannot fix it without also rewriting
  code (`var` to `const`, removing an `else`), so an import-order error goes to the ask at the
  end of the check step.
- **Checked:** `scripts/test-argo-it-lint-fix-rule.sh` (30 checks), the first test to cover
  `argo-it.md`. It pins the wording. The flags were tried on ruff 0.15.15 and eslint 9.39.5; no
  real redeploy was run, and ruff 0.16.0 and ESLint 10 were not tried.

### v1.71.2 -- The secret pattern list catches a password in a URL, `key=` and three vendor key formats

The go-live record refuses a typed reason that looks like it holds a password or key. Its pattern
list missed several common shapes.

- **Added to the list:** a URL that carries a user name and password (`https://user:pass@host`),
  `key=` (so `API_KEY=...`), Google `AIza`, Slack `xoxb-` and Stripe `sk_live_`.
- **Ordinary text still passes.** `key=` matches at the start of a word or after a character that
  isn't a letter or digit, so "monkey=3" and "the key = value pairs" are accepted; a URL with no
  password in it is too.
- **One list.** The pre-push secret scan section now points at it, leaving out the long
  random-string pattern, which a lock file's hashes would match.
- **Known limits:** a typed reason holding a literal `key=value` with no spaces is refused, as
  `token=value` already was. Other Slack prefixes, `rk_live_` and `apikey=` are not on the list.
- **Checked:** `scripts/test-secret-pattern-shapes.sh` (10 checks), with fixtures built at run
  time. It pins the wording; `/ship-it` does not run these steps yet, so nothing here is proven in
  real use.

### v1.71.1 -- Small leftovers: a stale check range, two skill descriptions, two guide PDFs

- **The governance doc counts the structure checks correctly.** `docs/AI-GOVERNANCE-HOMEGROWN.md`
  said S01-S10 (10 checks); it is S01-S14 (14) since v1.71.0, and the table total goes from ~174
  to ~178.
- **`/debug-it` and `/resolve-it` descriptions are quoted.** Each held a colon followed by a space
  in an unquoted value, which a strict YAML reader rejects. The text is unchanged; all 18 skill
  files now parse strictly.
- **`docs/DEVOPS-GUIDE.pdf` and `docs/USER-GUIDE.pdf` are removed.** They carried text the markdown
  guides no longer have, nothing rebuilt them, and nothing linked to them. The markdown guides are
  the only copy.

### v1.71.0 -- Claude reaches for the right skill on its own, in every make-it project

Claude Code lets an assistant start a skill itself when the task fits. How often it does depends
on two things: what each skill's one-line description says, and a standing instruction to use them.
make-it shipped neither consistently.

- **A new section in every project's `CLAUDE.md`: "Which make-it skill, when".** It says which skill
  to start as part of the work (`/debug-it` before any fix, `/git-it` for git steps), which to start
  when the person's words ask for it ("I'm done for today" → `/wrap-it`), and which only to suggest.
  The person never has to type a skill's name. Claude says in one line which skill it started.
- **Nothing Claude starts by itself leaves the computer.** A merge into the main branch and anything
  sent to GitHub wait for the person's go, and `/resolve-it` is only suggested, in its propose
  mode, because on its own it fixes and ships without stopping.
- **Four skills are never started on Claude's own:** `/ship-it`, `/argo-it`, `/demo-it` and
  `/threats-it`. They deploy, send or reach outside the computer, so they start only when the person
  asks for that outcome, and every ask the skill makes is kept.
- **Existing apps get it too.** New check S14: `/resume-it` and `/retrofit-it` add the section, and
  replace an older copy when the list of skills changes.
- **Every skill's description now says when to use it.** Ten of 18 were changed: nine had no trigger
  (two read as ads: "Just run /wrap-it when you're done for the day"), and `/threats-it` now says it
  starts only when asked.
- **Checked:** `scripts/test-skills-on-their-own.sh` (19 checks), with each skill pinned to its
  group. It pins the wording; it cannot prove what Claude does with it.

### v1.70.9 -- /nemo-it tests an app's fallback AI model too

The guardrails have always said the NeMo safety tests MUST run against both the primary and the
fallback model. No skill did it, and the references said so as a known gap.

- **One result per model.** /nemo-it's AI-safety phase now reports the six categories for the
  primary and again for the fallback.
- **How the fallback is run.** An app uses its fallback only when the primary fails, so /nemo-it
  starts the app a second time on the fallback, for that run only, then puts it back. It does this
  only for a Docker Compose app it started itself, never on a production path, and it changes no file in the
  project. The start ask says so before anything is started.
- **A fallback that did not run is NOT TESTED, never a pass**, with the reason: the app was already
  running, no AI provider was reachable, the fallback's name isn't recorded, it didn't start, or
  /nemo-it couldn't confirm the app was really answering from the fallback.
- **Where the names come from:** `app-context.json` (`ai_providers`). From `.env` and the compose
  file, /nemo-it reads only whether `AI_FAILOVER_PROVIDER` is set, never its value.
- **Cost:** with a fallback configured, the AI tests take about twice as long and cost about twice
  as much.

### v1.70.8 -- The unused attestation setting is gone, and /nemo-it is no longer credited with fixing

- **`attestation_mode` is removed.** No skill ever read it. /nemo-it writes one dated attestation per run to
  `docs/attestations/nemo-it/`, as it always has, and no run overwrites an earlier one. The
  references no longer name the two files only that setting pointed at, and the old
  `ai-safety-attestation.md` template, which nothing read, is deleted. An existing app's
  `app-context.json` may still carry the key; nothing reads it, and nothing needs changing.
- **The fix-and-retest loop is the build's.** Two governance tables, the guardrails, the blueprint
  and this README put a self-healing loop beside /nemo-it, which reports and never fixes. They now
  say whose it is, and what the build can't fix goes to TODO.md, not into an attestation.
- **Smaller wording:** a "Frequency" column that held no frequency, a "no attestation" line inside a
  "generates" list, and which part of build-verify runs the basic NeMo suite (Part A, check AI09;
  Part D is code-level).
- **The guard test catches rephrasings** it used to miss ("also runs", "re-runs", "/ship-it's PR
  carries", "exercises the fallback model", "emits the attestation"), and has five new checks.

### v1.70.7 -- No reference claims a /ship-it step that doesn't run

v1.44.18 made the ship-it guide describe only what /ship-it really runs. Sixteen other files still
said /ship-it runs the NeMo full suite, writes the AI-safety attestation, or flags risky prompts in the
PR. Some also said a skill tests the fallback AI model, which none does.
- **Pointed at what really runs.** References, the README and the docs now name build-verify,
  /nemo-it and /fix-it (the guide's "What make-it runs before /ship-it"), or the guide's "Safety steps
  /ship-it doesn't run yet". The fallback-model rule says plainly that it's a known gap.
- **No card ids in shipped text.** Installed files name no board card. A new check enforces it.
- **Checked.** New `scripts/test-references-ship-it-steps.sh` (20 checks): every reverted file fails it,
  and every other test script stays green.

### v1.70.6 -- The second scaffold passes its own checks too, and both stay clean after the app runs

- **`nextjs-fullstack` on a fresh copy** failed lint (1 error, 16 warnings), its formatting check
  and its type check, so its production build failed. Fixed the same way as the first scaffold:
  the hook before the early return, lookups through `own()`, a typed roles query, formatting.
  It stays on Next 15.
- **A gap in v1.70.5, found here.** Next.js writes `tsconfig.json` and `next-env.d.ts` itself.
  After the first dev run or build, the first scaffold failed its formatting check on
  `tsconfig.json` and the second failed lint on `next-env.d.ts`. Both files are now excluded from
  the checks, and the first scaffold ships `tsconfig.json` the way Next 16 writes it.
- **`nextjs-fullstack`'s formatting check covers app code only.** The project's notes and Docker
  setup sit at its root and are no longer in scope, matching the first scaffold.
- **CI:** the scaffold job now covers both scaffolds and runs lint again after the build, and
  fails if the build changed a tracked file.

### v1.70.5 -- The scaffold's frontend passes its own lint, type check and build

Reported by a developer on a company branch: with `eslint-config-next` 16 the scaffold's lint
config crashed, and lint errors blocked every frontend commit of a new app. Reproducing it showed
the scaffold had never passed its own checks on a fresh copy, version 16 or not.

- **Lint config:** imports the native flat configs; `FlatCompat` is gone. `eslint-config-next` is
  now on the same major version as `next` (it was 15 against Next 16).
- **Production build:** 4 type errors made `next build` fail on a fresh copy. Fixed.
- **Lint errors (15):** 14 `set-state-in-effect` and one hook called after an early return. Pages
  load through a small `useAsyncEffect` helper; three spots that did set state in an effect now
  set it in the event that causes it.
- **Warnings (25), which the zero-warnings hook treats as failures:** the security rule stays on;
  lookups by a variable key go through one audited helper, `own()`, that reads own properties
  only. That also fixes a real bug: a URL segment such as `constructor` was looked up on the
  breadcrumb table's prototype.
- **Formatting:** 31 files failed the scaffold's own Prettier check. Formatted.
- **Guard:** a new CI job installs the scaffold's dependencies fresh and runs lint, the hook's
  commands, the type check and the build, on scaffold changes and weekly.
- **Not covered:** the second scaffold (`nextjs-fullstack`) has the same old lint config.

### v1.70.4 -- /wrap-it and /try-it leave the go-live record out of their saves

- **The bug:** only /ship-it may write the go-live record, but /wrap-it saved every changed file
  and /try-it ran `git add -A && git commit` for its safety updates, so either could commit a
  changed record.
- **The fix:** both leave `.ship-it-go-live.json` out, even if it was already staged, and say
  "I left your go-live record unsaved. /ship-it owns that file." The record on disk is untouched.
- **The rule is written once** in the ship-it guide: a skill that saves for the user never stages
  or commits the record.
- **Checked:** `scripts/test-saves-leave-go-live-record.sh` runs /try-it's own save command in
  throwaway repos with the record changed, staged, new and untouched.

### v1.70.3 -- /resume-it, /wrap-it and /try-it stand still on an unfinished merge or rebase

- **One rule in all three skills.** Before saving anything, each checks whether a merge or rebase
  was left unfinished. If one was, it makes no commit, stages nothing, and runs nothing that
  finishes, continues or undoes it, because any of those can lose unsaved work.
- **It says one line:** "An update of your branch isn't finished. I haven't changed it and I'm not
  saving anything while it is. A developer can finish it." The last sentence will point to
  /ship-it once /ship-it can put a stuck update back.
- **What still happens:** /resume-it keeps reading and answering; /wrap-it still writes its notes
  and shuts the app down; /try-it skips its safety updates and runs the app as it is.
- **Checked:** `scripts/test-unfinished-update.sh` (55 checks) runs each skill's own detection
  command in throwaway repos: a clean project, an unfinished merge, both kinds of unfinished
  rebase, a linked working copy, and a folder that is not a git project.

### v1.70.2 -- The go-live record: /ship-it settles a clash by merge (the rule, not yet the step)

- **The rule is written.** When two branches both change a go-live answer, /ship-it tries the
  update from main as a trial that changes nothing. If the go-live record is the only file that
  clashes, it merges main into the branch, keeps the newer answer per item, and pushes normally.
  If any other file clashes too, it starts no merge and the request goes on.
- **One exception to "update a branch by rebase"** (`git-operations.md`, rule 5), chosen by the
  owner on 2026-11-18. /ship-it never rebases and never force-pushes.
- **Not live yet.** /ship-it's own file has no go-live step; the guide lists this with the other
  steps /ship-it doesn't run yet. Until then a clash is still settled by hand.
- **Checked:** `scripts/test-go-live-checklist.sh` (119 checks): three checks flipped, a sandbox
  shows the trial names exactly the files that clash and changes nothing, and 14 reversed rules
  each failed a check.

### v1.70.1 -- /dispatch-it and /subagent-it load the approval block

- **Both skills now load `approval-block.md`** (how a skill asks: selects only, fewer asks, every
  gate kept). Their asks already followed it; until now neither skill actually loaded the file.
- **No ask or gate wording changed.** An inventory of every ask and gate in both skills found
  nothing to remove or reword.
- **Checked:** `scripts/test-dispatch-it-asks.sh` (21 checks) and
  `scripts/test-subagent-it-asks.sh` (32 checks) pin the link, the no-yes/no rule and each gate.

### v1.70.0 -- /backlog-it groom says which cards are no longer needed

- **Groom now asks of every epic, story and task: does this still need doing?** The answer is
  needed, not needed or can't tell.
- **"Not needed" takes evidence:** the code or another card already covers it; what it was about
  is gone or the owner decided against it; nobody and nothing is asking for it; or an epic has
  nothing left under it. Age, low priority and difficulty don't count, and a security finding is
  never "not needed" unless the code shows it fixed.
- **Nothing closes on its own,** even with `--apply`. The plan lists the cards, then one
  multi-select ask lets you pick which to close. A closed card is kept, marked
  `closed_as: not-needed` with the reason, and `undo` brings it back.
- **Checked:** `scripts/test-backlog-groom-needed.sh`.

### v1.69.0 -- /threats-it treats the organisation's own AI systems as a target

Last of four parts adding AI as a threat actor to /threats-it.

- **AI assistants and agents are inventoried like privileged identities.** For each: what it runs
  as, what it can read and change, what it reads that outsiders can write, what it can do with
  nobody approving, and whether its actions are logged and watched.
- **Found with the collector the skill already has.** A ready list of AI product names and Azure
  AI resource types (`templates/presence-ai.json`) is fed to `exposure.py`. A name match is only a
  hint until its permissions, resources or sign-ins confirm it.
- **Their weaknesses join the chaining step,** and three attack patterns through AI systems are
  added: a planted instruction, an over-permissioned agent, a poisoned skill, plugin or MCP server.
- **Read-only, as always.** The skill never prompts one of the organisation's AI systems, never
  plants content for one to read, and never reports a prompt that would work.
- **What it can't see, it says:** low-code agents, assistants on people's machines, AI inside
  third-party services.
- **Checked:** `scripts/test-threats-it-ai-systems.sh`.

### v1.68.0 -- /threats-it reads the findings your own security tools already hold

Third of four parts adding AI as a threat actor to /threats-it.

- **New collector, `findings_sources.py`.** It reads Secure Score, Defender for Cloud assessments,
  Defender XDR alerts and incidents, and AuditGitHub's open findings, with every rating included.
  Low and informational findings are what the chaining step needs.
- **Read-only.** Only read requests and one Resource Graph query.
- **A source that could not be read is reported** with its error, and is never counted as "no
  findings".
- **AuditGitHub is read through its own API** with a read-only key from the environment. The key
  is never written to disk, is never sent on a redirect, and code snippets are not copied.
- **An alert is not a finding.** Alerts show whether a stage would be seen; they are never a link
  in a path.
- **Checked:** `scripts/test-threats-it-sources.sh`. The Microsoft readers have not been run
  against a live tenant.

### v1.67.0 -- /threats-it joins small findings into attack paths, with a test plan

Second of four parts adding AI as a threat actor to /threats-it.

- **Low and informational findings are no longer ignored.** The skill lists every finding it can
  read, whatever its rating (accepted risks included), and works out which ones connect into a
  path from a real starting point to an incident.
- **Two ways to run it.** `/threats-it chains` looks at the whole organisation with no threat
  feed. Every normal run also checks which small findings make that threat easier.
- **Each path carries its cheapest break and a test plan** for a purple team: the action, what to
  expect, the signal, the detection that should fire and when to stop. No exploit code.
- **Nothing is called proven.** Every path is "not exercised" until a person's test record says
  otherwise. The skill stays read-only and never runs a test.
- **A tool's finding is a lead** until the run's own evidence confirms it, and a path with an
  unconfirmed link is listed as a lead, not a path.
- **AI acting on its own is rated as an attacker,** beside a person alone and a person with AI
  help: machine-speed trial and error, wide knowledge of published techniques, learning from each
  failed try. Each chain now states how fast it could finish against how fast the organisation
  would notice, and whether the failed tries would be seen. A general figure such as "under N
  hours" goes in only with a source.
- **Checked by a script.** `check_paths.py` refuses a path that claims more than its evidence;
  the report build runs it. Tests: `scripts/test-threats-it-chains.sh`.

### v1.66.0 -- /threats-it rates every attack chain for an AI-assisted attacker

First of four parts adding AI as a threat actor to /threats-it.

- **Every attack chain now says who can run it.** Per stage: what it took a person alone (skill
  and time) and what it takes with AI help, with the reason it changes or doesn't. Under it, the
  one stage that still stands in the way and whether the organisation controls it.
- **The leadership briefing carries one line per chain** from that table, so "needs a skilled
  attacker" is no longer read as "unlikely".
- **These are assessments, and say so.** Time is given as minutes, hours, days or weeks, never a
  number. A statement that AI was used in an attack, or in any named incident, needs an archived
  source that says so. The fact-check step now checks all of this.
- **Your own security testing is never reported as an attacker.** AuditGitHub and its scanners
  are left out of hunts and reports, by the identifiers recorded in the organisation profile and
  never by name alone. What was left out is counted and said. Their findings stay as leads that
  each run must confirm, since such tools give false positives by design.
- **Checked:** `scripts/test-threats-it-ai.sh`.

### v1.65.5 -- /threats-it no longer keeps tenant evidence in a folder that syncs to the cloud

- **Fixed: the default projects folder was `~/Documents/threat-briefs`.** On a Mac where iCloud
  syncs Documents, the "never pushed" evidence was uploaded anyway. The default is now
  `~/threat-briefs`.
- **The scaffold refuses a synced folder.** iCloud Drive, Documents or Desktop when iCloud syncs
  them, Dropbox, OneDrive and Google Drive, including through a link. Nothing is created, and
  the skill offers a folder that stays on the computer.
- **Existing projects are not moved.** If yours are under `~/Documents/threat-briefs`, move them
  and update "Projects folder" in your organisation profile.
- **Checked:** `scripts/test-threats-it-folder.sh` (14 checks; 13 failed before the fix).

### v1.65.4 -- a repeated stop is reported as make-it's fault; the last named-answer asks

- **The same stop twice is said to be make-it's fault.** When a stop or an ask comes back with
  nothing changed since you answered it, the skill says so in one line, gives the way out, and
  notes it in the report. It stays stopped, and it never applies to approving an action.
- **/argo-it and /retrofit-it:** files to replace, secret values to move and items to include
  are picked from a list, not named or numbered.
- /nemo-it, /deadcode-it and /fix-it were read against the shared rule and needed no change.
- **Checked:** `scripts/test-asks-select.sh` (52 checks).

### v1.65.3 -- the ask rules, tightened after a second review

- **A security stop or a gate can never be "put off".** Keeping a "no" only silences an offer.
  A stop, a failed check or a finding still runs, still reports and still holds. An ask that a
  blocked step needs is asked again whenever the step is blocked again.
- **No "all of them" pick, and no typed counts.** /wrap-it's "all 3" is gone: every copy or label
  is its own pick.
- **Leftover typing removed** from /wrap-it, /fix-it, the board's merge and high-stakes gates,
  the learnings ask and the preview's access gate. /fix-it and /demo-it now read the shared rules.
- **/demo-it's teardown ask states the real undo:** the data is archived for 90 days.
- **The test for these rules now fails when a rule is reversed or removed** (45 checks; nine
  mutants got past the first version).

### v1.65.2 -- the hostile-code check reads the git index exactly before skipping a packages folder

Follow-up to the third independent review.

- **Fixed: a packages folder could be skipped on a forged or compressed git index.** The check
  skipped `node_modules`, `venv` and the like when the folder's name did not appear anywhere in
  `.git/index`. A file that only starts like an index hid a committed folder, and a version 4
  index stores paths in a way that can keep the name out of the file. The index is now parsed
  (versions 2 to 4). One that can't be read exactly, or a split index, skips nothing.
- **Fixed: a `conftest.py` or `setup.py` that is a link was never read** (found by a second
  review of v1.65.1). A code file linked to another file in the project is now read through the
  link. A link that leaves the project is never opened and is noted in the report.
- **Fixed: the "was this file really read" check from v1.65.1 could be fooled** by a second file
  of the same name in another folder, or by a path with `..` in it. Both now stop.
- **Tests now catch three safeguards being removed:** git's replace refs staying off, a `git`
  reached through a link into the project, and hooks staying off.
- **Checked:** `scripts/test-hostile-code.py` (145 tests); the parser was also run on three real
  repositories, and against git's own version 2 and version 4 indexes.

### v1.65.1 -- the hostile-code check no longer trusts a Python file it never read

Found by a third independent review. Both gaps are older than v1.62.0.

- **Fixed: code hidden behind a file the check skips could pass as "nothing found".** Reading a
  named `.py` file and running it was treated as harmless, on the theory that the check reads
  that file too. It does not read a link, anything under a `.git` folder, an installed-packages
  folder, or a path outside the project. Loading such a file now stops the run.
- **Fixed: an old copy of `conftest.py` or `setup.py` was softened** in a project marked as
  yours. Files that run on their own are never softened, old copy or not.
- **Checked:** six new tests in `scripts/test-hostile-code.py` (129 in all); each failed before
  the fix.

### v1.65.0 -- no skill asks you to type a confirmation, and a "no" is kept everywhere

- **One shared rule, read by every skill that asks:** an ask is a select, never a typed path,
  name, count or phrase. A high-stakes ask still names exactly what happens, one option per target.
- **A "no" or "not now" is kept** in the project's state file and not raised again unless you ask
  or something changed. A yes to an action (a send, a deploy, a delete, a paused security tool) is
  never kept: it is asked each time.
- **/try-it:** stopping another program that holds a port is a pick, not its typed name.
- **/make-it and /try-it:** pausing a network security tool is a pick per tool. How long you
  paused it for is no longer asked.
- **/demo-it:** removing a demo is a pick that names the firm, not a bare yes/no.
- **/wrap-it:** "keep them all" is remembered, so finished copies and labels you chose to keep
  are not offered again.
- **Checked:** `scripts/test-asks-select.sh` (23 checks).

### v1.64.2 -- fixes from an independent review of v1.63.0 to v1.64.1

- **Fixed: a hostile file could pass as "nothing found" (introduced in v1.63.0).** A Python file
  the check's own Python can't parse was given a light text search and passed as a note. A file
  written for a newer Python fails to parse in the check but runs where the project runs, and the
  text search misses most attack shapes. Such files stop the run again, as before v1.63.0, and are
  let through only by your pick, which is remembered.
- **"I know this code" now asks which files.** One pick used to let through every file listed.
  It is a select with one option per file.
- **/resume-it:** passing over a suggestion no longer counts as turning it down, and must-do
  updates you put off are named in every status, not only counted.
- **Installers:** the new folder is built first and swapped in, so a failed update no longer
  loses the remembered answers. A linked answers file is not followed.
- **Tests:** the checks for the put-off rules and the no-typing rule now fail when those rules
  are removed.

### v1.64.1 -- updating make-it no longer forgets what you told the hostile-code check

- **Fixed: every update deleted the remembered answers.** The files you let through, the projects
  you marked as yours and the stops you chose live in make-it's install folder, and the installer
  replaced that folder whole. Both installers now keep them. Answers already lost have to be given
  once more.
- **Fixed: "I know these files" is back** on the could-not-finish ask, as a select. v1.63.0 removed
  it by mistake: a file in an unusual text encoding still gets there and can be let through.
- **Checked:** `scripts/test-update-keeps-answers.sh` runs the real installer against a throwaway
  home folder. The Windows installer got the same change but was not run.

### v1.64.0 -- /resume-it remembers "not now" and never asks you to type

- **A "not now" is written down once.** Suggestions, catch-up updates, the AI memory and AI cost
  offers, the prompt-management upgrade and declined learnings go under `## Put off by your choice`
  in `.make-it-state.md` and are not raised again. The status shows one line for all of them.
- **It comes back only** when you ask, or when it has gained something new. Must-do updates you
  put off are named in one line before the hand-off to /ship-it.
- **It approves nothing.** Remembering a "not now" only stops the question.
- **Selects, not typing.** The prompt-management upgrade no longer asks for a count or an exact
  phrase.
- **Checked:** `scripts/test-put-off.sh`.

### v1.63.0 -- the hostile-code check asks far less, and never asks you to type

- **An old or broken Python file no longer stops the run.** When Python can't parse a file but
  its text is plain, the text checks read it and it becomes a note. Nobody is asked. Text that
  looks like an attack still stops. A file whose text can't be read plainly (another encoding,
  hidden bytes), one that is too large, or one that can't be opened still counts as unfinished.
- **Every remaining ask is a select.** "I know this code" lets through the files the ask listed,
  and "This whole project is mine" marks the project. No path or folder name to type.
- **Real attacks stop exactly as before**, in every project.
- **Checked:** `scripts/test-hostile-code.py` (124 tests).

### v1.62.0 -- the hostile-code check stops raising the same false alarm in your own project

- **"This project is mine", asked once.** The check's stop now offers a third answer, confirmed
  by typing the folder's name. The mark is two matching halves, one outside the project and one
  inside its `.git` folder, so a clone, a download or a folder made again never has it. In a project
  marked as yours, a test that loads your own code is a note, an old copy of a file the main
  line has since fixed is a note that names the fixing commit, and the same read-and-run shape in
  your own code is a weakness to fix first (new exit 3), not a stop. An old copy softens only
  those soft findings; code shaped like an attack stops even as an old copy.
- **Real attacks stop exactly as before, in every project:** unpacking hidden data, downloading
  and running, a hidden run command, install hooks, folder-open tasks, and anything in
  `conftest.py` or `setup.py`.
- **Answered once, not asked again.** "Stop" is remembered for those exact files and said in one
  line next time. A file the check cannot read can now be let through by typing its path.
- **Other working copies are left out only in a project marked as yours.** v1.61.1 left them out
  everywhere, and a review showed a downloaded archive could carry a fake registration and hide a
  folder from the check. An unmarked project is read in full again, and the report says so.
- **A repository inside your project is never treated as yours:** a clone, a download with its
  own `.git`, or a submodule keeps the strict rules.
- **git, only for your own projects, and locked down.** The old-copy lookup is the first time
  this check runs git. It never does in a folder nobody marked, it needs git 2.45 or later, and a
  repository's own settings cannot make it run a command or fetch anything.
- **Checked:** `scripts/test-hostile-code.py` (49 new tests, 122 in all), including a repository
  whose settings try to run a command and one set up to fetch missing objects on demand. Two
  independent reviews broke earlier versions; each way they found is closed and has its own test,
  and two rules were narrowed on the owner's ruling.

### v1.61.1 -- the hostile-code check no longer reads a project's other working copies

- **Faster where it was slowest.** The check that runs before anything in a project is installed or
  started (X09) read every git worktree inside the folder, each a full copy of the project. On a
  project with 128 of them it ran for over 25 minutes; it now takes about 20 seconds. It reads the
  copy being worked in, and says how many others it left out. Each is checked when work happens there.
- **Only copies git registered are left out:** the folder must point at this project's registry and
  the registry must point back. A folder that merely claims to be one is still read.
- **Low priority.** The check lowers its own priority so it does not slow the computer down.
- **Checked:** `scripts/test-hostile-code.py` (8 new tests; four ways of weakening the rule each fail one).

### v1.61.0 -- the watermark check runs in Jenkins and any other CI system

- **One script, any pipeline.** Every web app now ships `scripts/watermark-check.sh`. One line in
  a `Jenkinsfile`, `.gitlab-ci.yml` or `azure-pipelines.yml` runs the same check the GitHub Actions
  job runs: it reads the project's make-it release, fetches that release outside the project, and
  fails when code changed outside make-it. It needs bash, git and python3, and leaves nothing behind.
- **The organization's check in Jenkins.** With `ALLOWED_RELEASES` set, the same script is the
  stronger tier: only listed releases pass (pinned by digest) and the hostile-code check runs
  first. `watermark.md` describes holding it in a Jenkins global shared library and requiring its
  status in GitHub. That part is written from Jenkins' and GitHub's docs and has not run in a Jenkins.
- **/argo-it** puts the stage first in the Jenkins, GitLab CI and Azure DevOps pipelines it
  generates. Check WM07 covers projects built by those systems.
- **Checked:** `scripts/test-watermark.py` (13 new tests, run against a local copy of the release).

### v1.60.0 -- the seal: a watermark that needs nothing but the project

- **Every make-it run seals the project.** At the end of /make-it, /retrofit-it, /resume-it,
  /fix-it, /deadcode-it, /argo-it (and /try-it when it fixed something), make-it fingerprints the
  project's code and adds an entry to `.make-it/ledger/`, chained to the one before. No account,
  no service, no special plan.
- **Code changed outside make-it fails the check.** `watermark.py verify` names the files that
  changed since the last seal and says to run /resume-it, which rechecks them and seals. Markdown
  can change freely. A removed or edited history entry fails too.
- **Three places to see it:** `MAKE-IT.md` at the project's root (for a person), a `watermark` job
  in the generated `quality-gate.yml` (for any CI plan), and an admins-only "About this app" card
  that rehashes the app's own sign-in and permission code while it runs.
- **It survives how teams really work:** squash-merges and rebases (it fingerprints content, not
  commits), git worktrees, and two branches merged together (the next seal joins both histories).
- **The limit, stated plainly:** the seal attests; it does not prove. Running `watermark.py seal`
  by hand gives a valid seal, and a project's owner can remove the CI job. Resisting someone who
  sets out to fake it is the organization's check from v1.59.0, which stays as the stronger tier.
- **What it costs:** every code change has to go through a make-it skill before CI passes,
  including a one-line hand fix and a dependency bot's pull request.
- **New checks WM05-WM07. Checked:** `scripts/test-watermark.py` (70 tests).

### v1.59.0 -- the build record: proof that make-it's guardrails ran

- **A build record in every project:** `.make-it/manifest.json`, written silently at the end of
  /make-it, /retrofit-it, /resume-it and /fix-it. It names the make-it release, the project's
  security files with their hashes, and what the security step did. No questions, no secrets, no
  timestamps.
- **The record is a claim; the check is the proof:** `watermark.py verify` recomputes everything
  from the code and ignores what the record says. Python is parsed, not text-matched. A missing
  record, a missing security file, a route without its own permission check, a replaced
  `require_permission` or a missing roles table fails. A security file that differs from the
  release needs security review, unless that content is already in the base commit. A project
  with none of make-it's security files needs review too: "nothing to check" is never a pass.
- **Only plain code passes on its own:** two independent adversarial reviews each got a clean pass
  with an unprotected route. Every bypass they found is closed and has its own test, and the rule
  is now the other way round: ordinary route code passes, anything unusual in the backend (code
  built while running, routes or request filters added another way) needs security review.
- **Next phase, not in this release:** the GitHub check starts the app and tests its real routes.
  Until then a pass means "nothing wrong was found", not proof against someone acting on purpose.
- **For organizations:** `references/watermark.md` describes the two one-time setups: a required
  GitHub check run from an organization-owned repository (with GitHub's own attestation as the
  watermark), and a Claude Code managed hook that keeps the record current and cannot be switched
  off by a user. The GitHub side needs Enterprise Cloud for the required-workflow rule and for
  attestations on private repositories.
- **Limits:** v1 covers the FastAPI + Next.js scaffold; other project types get the record and
  need review. It proves the result, not that every line was typed through make-it, and it does
  not prove which folder the deployed container runs.
- **New checks WM01-WM04. Checked:** `scripts/test-watermark.py`.

### v1.58.0 -- security is found and fixed inside every build

- **Deep code audit in the build:** build-verify's security step now ends with a deep code audit
  (`build-verify-security.md` Phase 6). The first build audits the whole app; later ones audit only
  what changed. It runs at the `quick` profile, which is partial coverage by design.
- **Critical and High are fixed before handoff, without asking:** a test that fails first, the
  smallest fix, a fresh agent's re-check, one commit per finding, in place. Two failed tries are
  undone; a serious one left unfixed goes to the top of TODO.md and the user is told in one line.
- **Every build flow runs it:** `/make-it` (step 39b) and `/retrofit-it` before handoff; `/resume-it`
  at the start of a session and again before the `/ship-it` handoff, when the code changed. New
  check **V17** carries it into `/resume-it`'s catch-up for apps built earlier.
- **`/nemo-it` is the attestation, not the first look:** it still reports only and still produces the
  document that shows the code was scanned. Its audit reuses the build's audit runs.
- **Not changed:** `/try-it` (it presents an app the build already checked). Never fixed: leads that
  need validation, left-out items, the go-live record.
- **Checked:** `scripts/test-audit-every-build.sh`.

### v1.57.0 -- /nemo-it deep code audit, and /fix-it fixes its Critical and High findings

- **New phase in `/nemo-it`:** a deep code audit runs by default (and alone as `/nemo-it audit`). It
  maps the app, hunts for flaws in its own logic, and has a separate reviewer try to disprove each
  one. Confirmed flaws become `AUDIT-` findings; leads it cannot settle from the code are listed as
  "needs validation" with no severity. It only reads the code.
- **Vendored, pinned:** Cloudflare's security-audit skill (MIT) at commit `c1c8a8c`, unmodified, in
  `.claude/make-it/security-audit/` with its licence and a checksum list.
- **`/fix-it` fixes them without asking:** each Critical and High `AUDIT-` finding gets a failing
  test, the smallest fix, and a fresh agent's re-check, as its own commit on a `fix-it/<date>`
  branch. Nothing is merged; you keep or drop the branch. Two failed tries: undone, listed as manual.
- **Not included:** a sandbox for running the project's code during the audit. Without one, leads
  that need the code run stay "needs validation". /make-it's silent build scan is unchanged.
- **Checked:** `scripts/test-nemo-audit.sh`.

### v1.56.0 -- /wrap-it asks through the approval block

- **Saving is no longer asked:** /wrap-it saves the session's changes as a local commit, says in
  one line what it saved and how to take it back, and never saves a file that may hold a password
  or key (it is left on disk, unsaved, and the user is told). Nothing is pushed.
- **Deletions stay active confirmation:** removing finished worktrees and deleting merged local
  branches each says what is deleted and whether it comes back, and the user names each one; "all"
  counts only with the number in it. Worktrees are never forced; branches use `git branch -d` only.
- **Every other gate kept:** data volumes are never removed, processes are never killed, nothing is
  pushed, no new work is started, and the state file is always updated.
- **Checked:** `scripts/test-wrap-it-asks.sh`.

### v1.55.0 -- /backlog-it asks through the approval block

/backlog-it's five approval points now follow `approval-block.md`; every gate is kept.
- **`start`'s go** stays an edit step and ends with what `go` starts: `Go` or `Edit first`.
- **The standing preamble** (every started card and every dispatch lane gets it): the stop at the
  open PR is one decision-ready ask, `Merge` or `Hold`; the harm gate is active confirmation --
  `Merge only` or `Merge and deploy -- to <environment>`, never a plain yes.
- **A draft plan's go** is one ask: `Approve`, `Change first` or `Not now`.
- **The high-stakes alignment brief** ends in active confirmation: `Add alongside` or `Change the
  working path`, each naming where it is rehearsed, or `Not now`. Never batched.
- **`undo`** still asks nothing; its message names the commit it reverted.
- **Checked:** `scripts/test-backlog-it-asks.sh`.

### v1.54.0 -- /make-it's web-app build go asks through the approval block

The preview question in `ui-gate.md` is also the go-ahead to build, and it was a plain "yes". It is
now one decision-ready ask: what a go starts, the evidence (the preview), what it touches and the
undo, what is unusual against the plan, and the one thing to check (who sees which screen). The
user answers "build it" or says what to change.
- **High-stakes case:** a /resume-it feature that changes who can see or do something the app
  already has needs the user to name those screens and roles; a plain yes is not enough.
- **Learnings:** the offer after the build follows `learnings.md` (one batched ask, each item with
  its evidence).
- **Checked:** `scripts/test-ui-gate-go.sh`.

### v1.53.0 -- Go-live checklist: the contract, and /resume-it lists what's open

`ship-it-guide.md` gains the **Go-live checklist** contract: five go-live items (terms and privacy
pages, security audit, backup restore test, load test, live payment walk-through) that every
production /ship-it goes through and records in a committed `.ship-it-go-live.json`. It is a
checklist, not a gate: no answer stops a request. /ship-it's own side ships separately; until then
the guide lists the checklist under "Safety steps /ship-it doesn't run yet".
- **The contract:** when it runs (a PR into `main` whose workflow deploys to production; `--aws`
  and `--vlf` always), the record's shape, starting from main's copy so an answer given on another
  branch stays quiet, each ask as active confirmation with a typed reason for a skip, item 1 (the
  terms and privacy pages are served and mention user content, arbitration and personal data --
  never a legal review), the PR section, and no secret in the record.
- **/resume-it:** the readiness check lists the open items in NEXT-STEPS.md, read-only. It says
  what it did and who owns the file, never what /ship-it will do. A serious finding that a
  password or key is in the record holds up work and says to remove it and replace the key.
- **Not in this release:** how the skills handle a go-live record caught in a merge conflict (it
  is settled by hand for now), and items 2-5, which are recorded "coming soon".
- **Checked:** `scripts/test-go-live-checklist.sh` pins the contract and the listing.

### v1.52.0 -- /resolve-it: from a person's report to their outcome, and never silently again

A new skill. `/resolve-it` starts from a person's report, an alert or failed job, or a backlog card and
carries the problem until the person's outcome is observed on the live system -- looping when a fixed
cause reveals the next one.
- **Agents:** an investigator gathers evidence read-only and checks a shared **pattern library** of known
  root causes; `/debug-it` finds each cause; a writer drafts the plain-English update for the owner to
  send; the SDD adversarial reviewer breaks each fix until it says ship.
- **Autonomy:** propose, project (default) or end-to-end (where a project's doctrine says nothing about
  shipping); `end-to-end` removes stops, never gates. At every level: no write while investigating,
  nothing sent to a person, no secret printed, every bypass disclosed, every manual unblock a card.
- **Records:** the card, `docs/incidents/<date>-<slug>.md`, memory and doctrine (owner rules verbatim),
  and the pattern library (11 generic seeds; learned patterns in `~/.claude/resolve-it/patterns/`).
- **Checked:** `scripts/test-resolve-it.sh` (CI) pins the rails, the autonomy default, the records and a
  project-agnostic library.

### v1.51.0 -- /backlog-it runs each AI step on the model it needs

`plan`, `groom` and `groom strategy` no longer run everything on the session's model. Steps a
checker or script backs up run on Opus: `plan`'s routing call (`check-plan.py` gates it) and
`groom`'s per-card grounders. Pure-judgment steps run on Fable: `plan --with-deps` or a 100+ card
plan, `groom`'s sequencing, and `groom strategy`.
- **Fable 5.2, then 5.1**, whichever the deployment serves; with neither, judgment runs on Opus
  and the run says so in one line, never silently.
- **Settings `models`** (`route`, `ground`, `judge`; a model or a list tried in order) overrides it.
- **Checked:** `scripts/test-backlog-with-deps.sh` pins the table, the order and the fallback.

### v1.50.1 -- The Confluence docs match the published pages

The /backlog-it and overview pages on Confluence were updated, and their sources here now match
them, so the next publish doesn't undo those edits.
- **`16-backlog-it.md`** covers every /backlog-it change since mid-October: `info`, Waiting on
  you, `status`, `reconcile --prs`, the plan keeping its lead, Live checks, and a new **Putting
  one epic first** section for `plan --with-deps`, plus a dated "What's changed" list.
- **`00-make-it-framework-overview.md`** keeps the wording edited on Confluence (the skills link,
  Claude Desktop, "tasks, processes, workflows", the vibe-coding sentence).
- Docs only: no skill behaviour changes.

### v1.50.0 -- /backlog-it plan --with-deps: put one epic first, with what it needs from other epics

`/backlog-it plan E04 --with-deps` plans epic E04 **and** the cards in other epics it waits on --
then what those wait on, all the way down -- so putting an epic first no longer drops its
cross-epic prerequisites out of the plan. Without the flag nothing changes: a filtered plan skips a
card that waits outside the filter, and now says `--with-deps` pulls it in.
- **One waiting rule, everywhere.** A card waits on its own `dependsOn` **and its epic's**, and a
  `dependsOn` that names an epic means that epic's open cards (an epic whose cards are all done
  waits on nothing). `BOARD.md`'s Next up, `status`, `plan`, `groom` and `dispatch` share it
  (`regen-board.py`'s `needs`). **This changes existing boards:** cards under an epic that carries
  `dependsOn:` -- `groom strategy --apply` stamps these -- now wait on it too.
- **`scope.py`** (new, read-only) resolves the filter -- a card id (an epic or one story), a status,
  a priority, or a category -- and with `--with-deps` the chain: what was pulled in and for which
  card, what can't run (in progress, blocked), loops, and links to ids on another board.
- **Suggested links.** Most cards have no written `dependsOn`, so a `--with-deps` plan also names
  missing links with their evidence. `--apply` writes them as `dependsOn:` (plus a `## Links` note
  on the card) and plans the cards they pull in, in one more pass; without it they're listed.
- **The gate knows the scope.** `check-plan.py --scope` refuses a card outside the filter and its
  chain, requires every scope card to be placed, held or skipped (filtered plans used to switch
  that check off), and checks each suggested link (from a scope card, to an open card outside it,
  not already a link, no loop, evidence given).
- **`groom [filter] --with-deps`** grounds and ranks the chain too; its missing links are proposed
  Board deltas, written under `--apply`.
- **Checked.** New `scripts/test-backlog-with-deps.sh`: every backlog helper's self-test (new cases
  for inheritance, epic ids, the scope, the gate), the routes, the doc contract and its anchors,
  with planted-defect controls.

### v1.49.1 -- /try-it checks for code that attacks your computer, too

`/try-it` can be the first thing to run a project, and it runs package installs early, so the hostile-code check (X09) now comes before all of that.

### v1.49.0 -- Check for code that attacks your computer, before running anything

Some fake projects start a password stealer the moment a file is loaded, and the usual scanners can
miss them entirely. A new check (X09) reads a project before `/retrofit-it`, `/resume-it`,
`/deadcode-it` or build-verify runs any of it, and `/nemo-it` reports it.

- A match stops the run. Nothing is fixed, deleted or run, and only you can clear a file, by typing
  its path. A clearing holds for those exact contents and lives outside the project.
- It looks for shapes, not one campaign's addresses, and reads Python, npm install hooks and VS Code
  tasks. Finding nothing doesn't prove a project is safe.

### v1.48.0 -- /deadcode-it: clear out code nobody uses, safely

A new upkeep skill. `/deadcode-it` finds dead code across the whole project and removes it without breaking anything.
- **Proof, not guesses.** knip, depcheck, ts-prune, tsc and eslint (JS/TS) and ruff, vulture and deptry (Python) run in
  parallel; an AI search then checks each candidate for string and path references, dynamic imports, framework entry
  points, CI and script use, and config-loaded packages. A tool that can't run is reported, never read as "nothing found".
- **Deletion decisions on a strong model.** The subagents that prove and grade candidates always run on Fable (Opus
  if unavailable), never Sonnet or Haiku, whatever the session uses.
- **Graded before it's touched.** SAFE items go automatically; CAUTION items (whole files, routes, shared utilities)
  come to you in one plain-English pick list; DANGER items (configs, entry points, public APIs, migrations) and the
  app's built-in scaffold features are never removed.
- **Small, checked, undoable steps.** Tests and build must pass first, and existing lint/type findings may only shrink
  (a ratchet, so apps with old warnings can still be cleaned). One kind per batch, checked after each -- for Docker
  apps against freshly rebuilt containers; a red batch is rolled back and split until the culprit is found. Everything
  lands on a `chore/deadcode-<date>` branch, and no branch is ever deleted.
- **A deletion log.** `docs/DELETION_LOG.md` records what went, why it was safe, how it was verified, and the commit.
- **Wired into the framework, tool-free.** New check Q14 is an upkeep reminder that runs no tools: when no cleanup has
  been done, or the last is 30+ days and 20+ commits old, `/resume-it` suggests `/deadcode-it`. `/retrofit-it` suggests
  it once a retrofit is verified.
- **Scaffold fixes found along the way.** Both scaffolds' `lint` scripts use `eslint .` (`next lint` is gone in Next 16).
  The `fastapi-nextjs` scaffold's ruff config now reports unused imports instead of auto-deleting them on commit (an
  import can be there for what it does when loaded), and its own 12 unused imports are removed. Both scaffolds get a
  `.dockerignore`, so image builds no longer copy the developer's own `node_modules` / `.venv` over the image's install.
  The `fastapi-nextjs` test fixture no longer sets a `user_id` that `UserInfo` doesn't have (its tests pass again).

### v1.47.0 -- /threats-it: does this threat affect us, with proof

A new skill for security teams. Give `/threats-it` a threat advisory URL, a pasted article, a CVE list or an IOC
list, and it answers three questions for your own organisation -- has it happened here, would we be alerted, how
exposed are we -- with every figure traceable to archived evidence.
- **Sources archived, not summarised.** Pages are saved raw with SHA-256; refused pages are transcribed twice and
  only matching values kept. Every CVE is checked on the day against CISA KEV, MSRC, the CVE record and vendor
  advisories, and a corrections table records what the source got wrong or has since been overtaken by.
- **Attack chains.** Each attack becomes a stage-by-stage flow diagram an engineer can hunt from, with ATT&CK IDs
  verified against attack.mitre.org.
- **Read-only tenant hunt.** Graph, Log Analytics and Resource Graph through the analyst's Azure CLI sign-in: IOC
  and behaviour hunts in every readable workspace, an owner-classified sweep of app-initiated changes, exposure
  (permissions, credentials, product presence, server builds against the fix) and Sentinel rule coverage
  (live / partial / blind / disabled). Nothing is changed.
- **VEX + OpenVEX.** One statement per product and item, validated, rendered as OpenVEX v0.2.0.
- **The report pair.** A behaviour-first leadership briefing and a technical companion written from the same derived
  data, a generated appendix, PDFs from a committed build script, a figure check that fails when the two disagree,
  and an independent fact-check pass before delivery.
- **Organisation profile stays local.** Tenant identifiers and known gaps live in
  `~/.claude/threats-it/environment.md`, never in the repo; `references/environment-template.md` shows its shape.

### v1.46.0 -- /backlog-it info: any card in plain terms

`/backlog-it info <card>` explains a card in plain English, in the same three parts every time:
**The problem**, **Impact if it's not fixed** (who it hits, the wider risk, how far it reaches),
and **Why it's being fixed this way** (each choice and its reason, in the order the work runs).
About one screen, for quick understanding: no history of the card, no status unless asked.
- **Any way in:** a card id, words from its title, a focus question after it (`info E02-S5 why is
  Task 3 taking so long`), or bare `info` for the card this session is working on.
- **Grounded:** it reads the card, its plan, its PRs and, for a card in a run, the run's ledger
  and the owner's calls, and checks claims against the code when that's cheap.
- **Out of the way:** read-only, and a background subagent does the reading, so running lanes
  aren't disturbed.
- **`/btw` knows the shape too** (in make-it sessions): CLAUDE.md carries the three parts, and
  since `/btw` can't read files, it answers only from what the session has read and points to
  `info` otherwise.
- **Checked.** New `scripts/test-backlog-info.sh`: the route, the read-only rule, and the same
  headings in the reference and in CLAUDE.md, with planted-defect controls.

### v1.45.0 -- AI accounting: what your AI costs, what it saves, and cheaper models where they're good enough

Every AI app now records each AI call (which step, which model, what it cost) and sets it against
what people did with the result, so the app can show its AI's return on cost. It also checks
whether the app steps down to cheaper models for work that doesn't need the expensive ones.
- **A prompt that retrofits it.** Prompt #10g adds it to an existing app: it finds every AI call
  first, writes a model-ladder report (`.make-it/ai-ladder.md`), then meters, measures and builds
  the pages. `/retrofit-it` runs it as a new step ("Measuring what your AI costs and saves"), or on
  its own with `/retrofit-it ai-accounting`; `/resume-it` offers it to AI apps that lack it;
  `/make-it` builds it into new AI apps.
- **Seven admin pages:** AI Instructions, AI Agents, Control Plane, AI Monitor, AI Spend, Infra
  Spend, Spend Statements.
- **The model ladder:** every call names a tier, a weak answer gets one step up, and no step is
  moved to a cheaper model until a replay of past work shows the answers hold.
- **ROI:** cost per finished task and how often people accept, fix or redo the AI's work, always.
  Dollar ROI when an admin enters minutes per task and an hourly rate.
- **Control Plane:** turn an AI step on, off or to shadow, pick the model behind each tier, set
  spending limits that stop a call before it spends, see the failover state, roll a prompt back.
  Every change is audited.
- **Spend:** the cloud bill from AWS Cost Explorer (Azure and GCP stubs, manual lines for other
  vendors), and frozen internal statements with gapless numbers. Not invoices.
- **New spec and checks:** `references/ai-accounting.md`, AC01-AC16 and ACV01-ACV03 in
  build-standards; the reasoning is in `docs/ai-accounting-design.md`.
- **Checked.** New `scripts/test-ai-accounting.sh`: the ids, sections, tables and wiring agree,
  with a planted-defect control for each core check.

### v1.44.22 -- /try-it checks what still works when sign-in is left out

When a /retrofit-it user left secure sign-in out, /try-it skipped every page check. So the pages and
API the app already had were never checked. /try-it also claimed screenshots and tested pages that
didn't exist.
- **Existing pages and API, checked without signing in.** With sign-in left out, /try-it opens each
  page and calls each endpoint the app already had through its own access, and lists them as
  checked, never as left out. An endpoint that needed sign-in before is named plainly as not checked.
- **Only claims what ran.** "with screenshots" is said only when screenshots were taken.
  "Screenshots unavailable" says pages were tested only when they were. The report rule names its
  exceptions.
- **A left-out item that stops the app from starting** gets a true path: no fix, no retry, never
  "Everything is running!", and the smoke test marks what it kept from running.
- **Checked.** New `scripts/test-try-it-checks.sh` (9 checks, each with controls for its plain
  opposite); the left-out record's 456 checks stay green.

### v1.44.21 -- A broken migration chain is caught before the app starts

Build-verify only checked that an app had migrations. An app whose Alembic chain was broken passed
Part A, then its backend container died on `alembic upgrade head` in Part B.
- **New check D06 [BLOCK].** Part A, and the /resume-it catch-up, read every migration's `revision`
  and `down_revision`. The check fails on a duplicate revision, a `down_revision` that names nothing,
  or anything other than exactly one head. `alembic heads` is an extra when it's installed, never
  a way to clear a failure. Each failure has a plain fix, and the scaffold's own ids never change.
- **Checked.** New `scripts/test-migration-chain.sh` (25 checks). The shipped scaffold and a proper
  merge revision pass. A duplicate `002`, a second head and a dangling link fail. Real Alembic
  agrees with every verdict.

### v1.44.20 -- The canary no longer splits a CLAUDE.md's intro from its title

Claude Code's `/init` writes a short intro under a `CLAUDE.md`'s title. The S13 catch-up put the
instruction-drift canary between the title and that intro, so the intro ended up inside the canary
section.
- **After the intro.** S13 now inserts the canary directly before the file's first `##` heading. The
  title and any text under it stay together on top, and a file with no intro comes out as before.
- **Checked.** New `scripts/test-claude-md-order.sh` (88 checks) turns S10-S13's wording into
  placement rules and runs them in every order. Before the fix, 31 checks failed, all with the
  canary right under the title. After it, every order gives the same file, and a second run changes
  nothing.

### v1.44.19 -- The SDD gate knows a resumed agent is still working

The `/subagent-it` Stop hook nudged the coordinator as if a run had stalled while an agent it had
resumed by message was still working. Three nudges later, the gate released and stopped guarding the run.
- **Resumes count.** A successful message that resumes a finished agent now counts as that agent
  running again, until its final notice. An interim "waiting on its own work" notice still doesn't
  end the wait, and the final notice ends every launch of that agent.
- **Checked.** `scripts/test-sdd-gate.sh` grows from 23 to 31 checks; three of the new ones failed
  before the fix. Replayed against this project's own session transcripts, the new gate counts all
  60 resumes, and is never quieter than the old one.

### v1.44.18 -- The ship-it guide describes what /ship-it really does

make-it's `ship-it-guide.md` described 18 /ship-it steps that ship-it's own instructions never run.
The owner chose a split:
- **The guide matches ship-it.** Every step it calls a /ship-it step maps to ship-it's own
  instructions, by their names; six wording mismatches are fixed.
- **Safety steps stay, marked "not yet".** The secret leak scan on every push (save included), the
  switch off the personal Claude token, the billing ask and the left-out rules stay in the guide,
  under a section that says plainly ship-it doesn't run them yet and a later ship-it release adds
  them -- and what guards a push meanwhile (the gitleaks pre-commit hook and the quality-gate scan).
- **What make-it runs before ship.** NeMo, the AI-safety attestation, and the lint, migration and
  build checks are no longer called /ship-it steps; a new section points at build-verify,
  /nemo-it and /fix-it, which run them.
- **Checked.** New `scripts/test-ship-it-guide.sh`; the left-out checks re-pinned to the guide's
  new shape, including the rule that a check which found something says what it found.

### v1.44.17 -- You choose who pays for your app's AI before it's shared

An app that uses AI through the builder's own Claude Code subscription can't be shared that way:
the subscription is for one person. The ship hand-off used to switch the app to pay-per-use
billing on its own, with only a warning. Now:
- **You pick, by name.** Before an app goes to anyone else, /make-it, /resume-it and /retrofit-it
  all reach one question in the ship-it guide: use an Anthropic API key (pay per use), use your
  organization's provider, or keep it local and don't share it yet. A plain yes isn't an answer,
  and nothing switches before you pick.
- **Your own copy stays on your plan.** A pick changes the shared app's settings
  (`app-context.json`, `.env.example`, and the key where the app runs), never your local `.env`,
  and you're told which files changed. The undo says plainly what to change back, and that
  deleting the key is what stops the charges.
- **"Keep it local" is remembered.** It's noted under `## Before sharing` in `.make-it-state.md`,
  so the next hand-off asks first; /wrap-it and /resume-it keep that note when they rewrite the file.
- **Checked.** `scripts/test-billing-ask.sh`: 50 checks, including that no other skill or reference
  switches billing on its own.

### v1.44.16 -- The run gate waits for a subagent's final word

The Stop hook that keeps a `/subagent-it` run going counted a background agent's interim notice
("waiting on its own background work") as the agent reporting back, so the next wait nudged as if
the run had stalled. Now:
- **Only a final notice ends the wait.** An interim notice keeps it open; a final notice ends it
  whether it carries the launch's tool-use id or only the agent's task id.
- **The two-hour limit stays.** An agent that never sends a final notice is waited on for at most
  two hours after its launch, as before.
- **Checked.** `scripts/test-sdd-gate.sh` gains six cases (four failed on the old hook); a replay on
  two real session transcripts keeps every interim wait open and ends every final one.

### v1.44.15 -- Subagent runs carry four lessons the owner approved

The last two long `/subagent-it` runs taught four things the run instructions didn't say yet. Now:
- **Test-writers run on Opus (or Fable), never Sonnet.** Sonnet test-writers kept writing checks
  that passed on the rule's exact opposite.
- **Shell checks never pipe big text into `grep -q`.** Under `pipefail` that can flip a check as
  files grow; the templates give a helper that reads all input, and a run fails on any stderr.
- **A narrowed check must prove what it still catches.** A check narrowed to stop a false alarm
  lists the real opposites it still fails, each with a mutant, and the reviewer re-runs them.
- **A cause that keeps coming back goes to the owner.** Three review rounds in a row on the same
  root cause stop the patching: the run waits for a decision-ready design choice.
- **Checked.** `scripts/test-sdd-lessons.sh` pins each rule.

### v1.44.14 -- What you leave out stays out, and every skill knows it

When a first-time builder left something out "by their choice" (secure sign-in, say), each skill
read that choice its own way: some offered it again, some counted its checks as failures, /ship-it
never named it, and a rewrite of `.make-it-state.md` or a retrofit re-run could lose it. Now:
- **One record, one reading.** The new `left-out-record.md` says where the choice lives
  (`## Left out by your choice` in `.make-it-state.md`) and how every skill reads it. A left-out
  item is mentioned once, never offered, never counted as a failure, and never put back without
  the user's own answer. Older projects are read only in the shapes older skills wrote.
- **/resume-it and /try-it** show "Left out (your choice)" instead of a failure, say what could not
  be checked, and never call an app "up and running" when a left-out item kept it from starting.
- **/ship-it names each left-out item that matters before going live** and asks per item: ship
  with it left out, or add it first. The picks go on the PR's go-live checklist, and the automation
  never blocks on, fixes, or puts back a left-out item. A secret found in a left-out item still
  stops the ship: it is never moved and never sent.
- **The record survives.** Every skill that rewrites the state file keeps the section as it is,
  and /retrofit-it's undo keeps it. A /retrofit-it re-run reads it first, keeps left-out items out
  of its plan, writes it where the work runs (a worktree included), and asks before a fresh build.
- **Checked.** `scripts/test-left-out-record.sh`: 456 checks; any error output fails the run.

### v1.44.13 -- Every "Waiting on you" item makes sense on its own

The board's "Waiting on you" list, and the lists agents write at the end of a reply, showed bare
card ids, PR numbers and shorthand ("batch leftovers", "apply-day", "fold"), so the owner could not
answer an item without digging. Now:
- **Each item reads cold.** The board and `/backlog-it status` show each waiting item with its
  title, one or two plain sentences on what waits and why, and the expected answers.
- **Cards carry their answers.** A card's new `answers:` field holds 2-4 named choices, each with
  what it does; a recommended one also gives its strongest reason against. The board flags an item
  that is only an id, has no answers, has too few or too many, or recommends without a reason
  against. Older cards still show, flagged "answers not on card".
- **Old answers never carry over.** Writing or clearing a card's question also clears its old
  answers, unless the same write sets new ones.
- **Chat lists follow the same shape.** `approval-block.md` gains "A list of asks": the title, what
  waits and why, the named answers, a batch as one grouped line, and a high-stakes item never
  batched. The dispatch, subagent and backlog skills point at it.

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
