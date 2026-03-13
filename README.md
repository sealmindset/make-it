# /make-it

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill suite that takes anyone from an app idea to a fully working application through guided conversational Q&A. No programming knowledge required.

You describe what you want in plain English. The skills handle everything else -- technical decisions, code generation, testing, and deployment.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Skills Overview](#skills-overview)
- [How /make-it Works](#how-make-it-works)
- [How /try-it Works](#how-try-it-works)
- [How /resume-it Works](#how-resume-it-works)
- [What Gets Built](#what-gets-built)
- [Supported Project Types](#supported-project-types)
- [Architecture](#architecture)
- [Build Quality](#build-quality)
- [Deployment Lifecycle](#deployment-lifecycle)
- [FAQ](#faq)
- [Related Skills](#related-skills)
- [License](#license)

---

## Quick Start

```bash
# 1. Install Claude Code (if you haven't already)
npm install -g @anthropic-ai/claude-code

# 2. Clone this repo
git clone https://github.com/sealmindset/make-it.git

# 3. Install the skills into Claude Code
cd make-it
bash install.sh   # or follow the manual steps below

# 4. Go to where you want your new project
cd ~/Documents/GitHub

# 5. Start Claude Code and build your app
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

#### Option A: Automated Install

```bash
git clone https://github.com/sealmindset/make-it.git
cd make-it
bash install.sh
```

The install script copies skill commands and references into your Claude Code configuration directory (`~/.claude/`).

#### Option B: Manual Install

```bash
# Clone the repo
git clone https://github.com/sealmindset/make-it.git ~/.claude/make-it-repo

# Create the commands directory if it doesn't exist
mkdir -p ~/.claude/commands

# Copy the three skill entry points
cp ~/.claude/make-it-repo/.claude/commands/make-it.md ~/.claude/commands/
cp ~/.claude/make-it-repo/.claude/commands/try-it.md ~/.claude/commands/
cp ~/.claude/make-it-repo/.claude/commands/resume-it.md ~/.claude/commands/

# Copy the references, templates, and scaffolds
cp -r ~/.claude/make-it-repo/.claude/make-it ~/.claude/make-it
```

### Verify Installation

```bash
claude
```

Inside Claude Code, type `/make-it` -- you should see the skill activate and greet you. Type `/try-it` or `/resume-it` to verify those are available too.

### Updating

```bash
cd ~/.claude/make-it-repo   # or wherever you cloned it
git pull
bash install.sh             # re-copies updated files
```

---

## Skills Overview

| Skill | What It Does | When to Use It |
|-------|-------------|----------------|
| `/make-it` | Builds a new app from scratch through conversational Q&A | Starting a brand new project |
| `/try-it` | Spins up your app locally, tests everything, lets you explore in the browser | After `/make-it` finishes, or anytime you want to see your app running |
| `/resume-it` | Picks up where you left off -- add features, fix bugs, run tests, deploy | Any time after the initial build |

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

## What Gets Built

### Web Applications (Tier 1)

A complete, production-ready web application with:

| Layer | What's Included |
|-------|----------------|
| **Frontend** | Next.js with TypeScript, Tailwind CSS, oklch theming (light/dark mode), responsive layout |
| **Backend** | FastAPI with async SQLAlchemy, Pydantic validation, Alembic migrations |
| **Database** | PostgreSQL with role-based access control tables, seed data |
| **Auth** | OIDC authentication (Azure AD, Auth0, Okta, Google, GitHub, Keycloak) with JWT sessions |
| **RBAC** | 4 system roles (Super Admin, Admin, Manager, User), page-level CRUD permissions, permission matrix admin UI |
| **UI Components** | DataTable with Excel-like filtering, breadcrumbs, command palette (Cmd+K), sidebar navigation, dark mode toggle |
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

## Supported Project Types

The skill automatically classifies your project during the Design phase based on your answers. You never need to choose -- it figures it out.

| Type | Detected When You Say... | Tech Stack |
|------|-------------------------|------------|
| **Web App** | "dashboard", "login", "users can...", "CRUD", "reports" | FastAPI + Next.js + PostgreSQL (scaffold) |
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
  make-it/
    references/
      prerequisites.md            # Machine setup checks
      design-blueprint.md         # Architectural decision framework
      prompt-templates.md         # 14 enterprise build prompts
      ship-it-guide.md            # Deployment handoff reference
      guardrails.md               # Tiered guardrail system (Tier 0-5)
    templates/
      app-context.md              # Template for tracking user answers
    scaffolds/
      fastapi-nextjs/             # Pre-built scaffold (61 files)
        backend/                  # FastAPI: auth, RBAC, models, routers, Alembic
        frontend/                 # Next.js: pages, components, Tailwind, oklch theme
        mock-services/mock-oidc/  # Complete mock OIDC provider
        scripts/                  # seed-mock-services.sh template
        docker-compose.yml        # Multi-service orchestration template
        .env.example              # Environment variable documentation
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
| `CHANGELOG.md` | Running log of all changes across sessions |
| `TODO.md` | Outstanding work items |

### How the Scaffold Works

For web applications with Python backends, the Build phase uses a **pre-built scaffold** instead of generating everything from scratch. This is how recurring bugs are eliminated:

1. **Design phase** determines the app name, ports, users, roles, and integrations
2. **Build phase** copies the scaffold (61 files) into the project directory
3. All `[BRACKET_PLACEHOLDERS]` are replaced with values from `app-context.json`
4. Domain-specific code (your pages, APIs, models, seed data) is generated on top
5. The scaffold's auth, RBAC, Docker, and UI components are never regenerated

The scaffold provides:
- Complete OIDC auth flow (login, callback, JWT cookie, /me, logout)
- Database-driven RBAC (4 tables, permission middleware, admin UI)
- Same-origin API proxy (Next.js rewrites to FastAPI)
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

**Live checks (app running in Docker):**
- All containers healthy
- Mock services seeded with correct users
- Login works for every role
- Every API endpoint returns data
- Every page loads with content
- Permission boundaries enforced (403 for unauthorized access)
- Logout clears JWT cookie

Issues found during build-verify are fixed automatically (up to 3 cycles). You never see a broken app.

---

## Deployment Lifecycle

Your experience is simple: **describe what you want, verify it works, say "ready."**

```
/make-it    --> Build your app, verify it works
/try-it     --> Explore it in the browser
/resume-it  --> Iterate (add features, fix things, run tests)
/ship-it    --> Deploy (creates PR, triggers CI/CD)
```

The full lifecycle with CI/CD automation:

```
/make-it -> Build in Docker, push to GitHub
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
- OIDC authentication with chosen provider
- Database-driven RBAC with 4 system roles and permission matrix
- Standard UI components (DataTable, Breadcrumbs, QuickSearch, ModeToggle)
- Docker Compose with mock services and seed data
- System fonts only (no external font CDNs -- safe behind corporate proxies)
- Parameterized database queries, security headers
- Terraform generated as DevOps handoff artifact

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
For web apps: Python (FastAPI) backend, TypeScript (Next.js) frontend, PostgreSQL database. Other project types use the language best suited for the task.

**Can I customize the generated code later?**
Yes. The generated code is standard, well-structured code in your project directory. Any developer can modify it. `/resume-it` helps you make changes without coding knowledge.

**Does it work behind a corporate proxy (Zscaler, Netskope)?**
Yes. The skill detects SSL-inspecting proxies during Preflight and guides you through temporarily disabling them for Docker builds. All generated apps use system fonts (no external font CDNs) to avoid proxy issues.

**What if I want to change my app idea mid-build?**
Minor changes (UI tweaks, adding a page) are handled seamlessly. Major changes (different architecture) trigger a conversation about what needs to change before proceeding.

**How do roles and permissions work?**
Every web app gets database-driven RBAC: 4 system roles (Super Admin, Admin, Manager, User) with page-level CRUD permissions. Super Admins can create custom roles with any combination of permissions via an admin UI. Roles are stored in the application database, not the identity provider.

**Can it build apps that talk to external systems (Jira, Salesforce, etc.)?**
Yes. The skill detects external integrations during Ideation and generates mock services for each one, so you can develop and test locally without access to the real systems.

**What does "mock OIDC" mean?**
When your app requires login, the skill generates a local mock identity provider (like a fake Azure AD) so you can test the full login flow on your machine without setting up a real identity provider. It includes a user picker with test accounts for each role.

**Where does my code live?**
In a standard Git repository in the directory where you ran `/make-it`. It gets pushed to GitHub when you run `/ship-it`.

---

## Related Skills

| Skill | Purpose | Repo |
|-------|---------|------|
| `/ship-it` | CI/CD deployment -- commits, pushes, creates PR with shared GHA workflows | [sealmindset/ship-it](https://github.com/sealmindset/ship-it) |

---

## License

[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) -- free to use, share, and adapt with attribution.
