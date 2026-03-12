# /make-it

A Claude Code skill that takes a first-time developer from an app idea to a fully working, deployed application through guided Q&A. No programming knowledge required.

You describe what you want in plain English. The skill handles everything else -- technical decisions, code generation, testing, and deployment.

## What's Included

| Skill | Purpose |
|-------|---------|
| `/make-it` | Build a new app from scratch through conversational Q&A |
| `/try-it` | Spin up your app locally with mock services, test everything, and explore in the browser |
| `/resume-it` | Continue working on an app after the initial build -- fix bugs, add features, test, and deploy |

### /make-it Flow

0. **Preflight** -- Verifies your machine is ready (Git, Docker, GitHub CLI, Azure CLI, VS Code)
1. **Ideation** -- Asks about your app idea in plain English (one question at a time)
2. **Design** -- Makes all technical decisions behind the scenes using the Design Pattern Guide
3. **Build** -- Generates the full application (pages, API, auth, permissions, infrastructure)
4. **Ship** -- Hands off to `/ship-it` for CI/CD deployment

### /try-it Flow

0. **Context Discovery** -- Reads app-context, docker-compose, .env configuration
1. **Startup** -- Builds containers, starts app + mock services, resolves port conflicts
2. **Automated Testing** -- Uses Playwright to log in as each user role, visit every page, check permissions, and take screenshots
3. **Fix** -- Any failures are diagnosed and fixed automatically (retries up to 3 times)
4. **Report** -- Generates `TRY-IT-REPORT.md` with results, screenshots, and browser instructions
5. **Explore** -- Tells you how to open your app in the browser and test it yourself
6. **Support** -- If you find anything that doesn't look right, just describe it and it gets fixed

Runs automatically after `/make-it` builds your app, or anytime standalone with `/try-it`.

### /resume-it Flow

0. **Context Discovery** -- Reads project state, changelog, TODOs, and git history
1. **Greet + Suggest** -- Shows where things stand and suggests next actions
2. **Work** -- Helps with bug fixes, new features, TODO items, or anything you describe
3. **Readiness Check** -- Standup-style assessment: what's done, what's blocked (tickets, env vars, infrastructure), what's next. Generates a shareable `NEXT-STEPS.md` checklist.
4. **Test** -- Scaffolds automated tests (pytest, Playwright) and runs them
5. **Ship** -- Hands off to `/ship-it` when ready

## Prerequisites

Before running `/make-it`, you need the following on your machine. The skill will check for these automatically and guide you through any missing items.

| Tool | How to Install |
|------|---------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `npm install -g @anthropic-ai/claude-code` |
| Git | `brew install git` |
| Docker Desktop | Install via [Dockyard](https://dockyard.example.com) or [docker.com](https://www.docker.com/products/docker-desktop/) |
| GitHub CLI | `brew install gh` then `gh auth login` |
| Azure CLI | `brew install azure-cli` then `az login` |
| VS Code | `brew install --cask visual-studio-code` |
| VPN access | Connect to your organization's VPN |

## Installation

1. Clone this repo into your Claude Code skills directory:

```bash
git clone https://github.com/sealmindset/make-it.git ~/.claude/make-it-skill
```

2. Copy the skill commands into your Claude Code commands directory:

```bash
# Create the commands directory if it doesn't exist
mkdir -p ~/.claude/commands

# Copy the skill entry points
cp ~/.claude/make-it-skill/.claude/commands/make-it.md ~/.claude/commands/
cp ~/.claude/make-it-skill/.claude/commands/try-it.md ~/.claude/commands/
cp ~/.claude/make-it-skill/.claude/commands/resume-it.md ~/.claude/commands/

# Copy the references and templates
cp -r ~/.claude/make-it-skill/.claude/make-it ~/.claude/make-it
```

3. Verify the skills are available:

```bash
claude
# Then type /make-it, /try-it, or /resume-it
```

## Usage

### Building a New App

```bash
# Navigate to where you want to create your project
cd ~/Documents/GitHub

# Start Claude Code
claude

# Run the skill
/make-it
```

The skill will:
1. Check your machine is ready
2. Ask you questions about your app idea
3. Build the entire application
4. Spin it up and test everything (via /try-it)
5. Let you explore your app in the browser
6. Guide you to deployment when you're ready

### Trying Out Your App

```bash
# Navigate to your existing project
cd ~/Documents/GitHub/my-app

# Start Claude Code
claude

# Spin it up
/try-it
```

The skill will:
1. Start your app and all mock services
2. Test login as every user role
3. Test every page automatically
4. Show you how to explore in your browser
5. Fix anything you find that doesn't look right

### Resuming Work

```bash
# Navigate to your existing project
cd ~/Documents/GitHub/my-app

# Start Claude Code
claude

# Resume where you left off
/resume-it
```

The skill will:
1. Detect what was already built
2. Show your current status and suggest next actions
3. Help you continue building, fix issues, or run tests

### Checking Readiness

When running `/resume-it`, you can ask "what's next?" or "what do I need?" to get a standup-style assessment:

- **What's done** -- completed work since last session
- **What's blocked** -- tickets, infrastructure requests, env vars you need from other teams
- **What's next** -- actionable items you can work on right now

This generates a `NEXT-STEPS.md` file you can share with your manager or DevOps team.

## Architecture

```
.claude/
  commands/
    make-it.md              # Main skill -- idea to working app
    try-it.md               # Try skill -- spin up, test, explore
    resume-it.md            # Resume skill -- continue, test, fix, ship
  make-it/
    references/
      prerequisites.md      # Machine setup checks
      design-blueprint.md   # Architectural decision framework
      prompt-templates.md   # 14 enterprise build prompts
      ship-it-guide.md      # Deployment handoff reference
      guardrails.md         # Tiered guardrail system (Tier 0-5)
    templates/
      app-context.md        # Template for tracking user answers
.backup/
  docs/                     # Source PDFs and addendum docs (not used at runtime)
  make-it/                  # Example session artifacts (app-context, preflight)
CLAUDE.md                   # Project instructions
README.md                   # This file
.gitignore
```

### State Files (created in your project directory at runtime)

These files are generated by the skills inside the user's app project -- not in this repo:

| File | Purpose |
|------|---------|
| `.make-it/app-context.json` | All design decisions from ideation and design phases |
| `.make-it/preflight-status.json` | Machine readiness check results |
| `.make-it-state.md` | Session breadcrumb -- what was built, what's pending, test status |
| `TRY-IT-REPORT.md` | Test results, screenshots, and browser access instructions |
| `.try-it/screenshots/` | Screenshots of every page per user role |
| `NEXT-STEPS.md` | Shareable checklist of infrastructure, tickets, and env vars needed |
| `CHANGELOG.md` | Running log of changes made across sessions |
| `TODO.md` | Outstanding work items |

## Standards Enforced

All generated applications follow a tiered guardrail system. **Tier 0 applies to every project** regardless of type. Higher tiers activate based on what's being built.

### Tier 0: Universal (every project)
- Ideation confirmed, design documented in `app-context.json`, build-verified before handoff
- `CHANGELOG.md` and `TODO.md` from day one
- No secrets in committed files, no hardcoded config values
- Input validation at system boundaries, sensitive data masked in output
- Latest stable dependencies, separation of concerns, environment-based config
- Git initialized with proper `.gitignore`

### Tier 1: Web Application (additional)
- OIDC authentication (Azure AD / Entra ID)
- Database-driven RBAC with 4 system roles and permission matrix
- Standard UI components (Breadcrumbs, DataTable, QuickSearch, ModeToggle)
- Mock services for local development (mock-oidc + per-integration mocks)
- Docker Compose with seed data, system fonts only
- Parameterized database queries, security headers, Terraform for IaC

### Tier 2-5: Extension, CLI, Library, API Service
Each project type has its own guardrails. See `guardrails.md` for the complete reference.

## Related Skills

| Skill | Purpose | Repo |
|-------|---------|------|
| `/ship-it` | CI/CD deployment -- commits, pushes, creates PR with shared GHA workflows | [sealmindset/ship-it](https://github.com/sealmindset/ship-it) |

## License

Internal use.
