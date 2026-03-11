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
- The 12 Enterprise Prompts are the execution templates (filled in automatically)
- `/try-it` spins up the app locally with mock services, tests everything, and lets the user explore
- `/ship-it` handles deployment (the user just types the command)

## /try-it

`/try-it` spins up the app with all mock services and tests everything automatically. Runs after `/make-it` build completes (automatically) or standalone anytime.

0. **Context Discovery** -- Reads app-context, docker-compose, .env
1. **Startup** -- Builds containers, starts all services + mock services, resolves port conflicts
2. **Automated Testing** -- Playwright tests login as each role, navigates every page, checks permissions, takes screenshots
3. **Fix** -- Any failures are diagnosed and fixed automatically (up to 3 retry cycles)
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
      prompt-templates.md          # The 12 prompts (auto-filled from user answers)
      ship-it-guide.md            # /ship-it integration reference
    templates/
      app-context.md              # Template for tracking user answers -> technical decisions
```

## Source Documents

- `AC-Vibe Code Developed Quick Start` -- Prerequisites and machine setup
- `AC-AI Vibe Coded Design Pattern Guide` -- The architectural blueprint
- `AC-Prompts for Building Enterprise Applications` -- The 12 execution prompts
- `ship-it RFC` -- The CI/CD deployment skill

## Standards Enforced

All generated applications follow:
- OIDC authentication (Azure AD / Entra ID)
- Permission-based RBAC (never role string checks)
- M.A.C.H. architecture principles
- Mock services for local development (mock-oidc + per-integration mocks)
- Environment-based service switching (no code branching for dev vs prod)
- Input validation on all endpoints
- Parameterized database queries
- Security headers before production
- Terraform for infrastructure as code
