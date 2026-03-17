# TODO -- make-it Framework

## High Priority

_All high priority items completed._

## Medium Priority

### Populate Next.js full-stack scaffold template files
The `scaffolds/nextjs-fullstack/` directory has the README and architecture documented,
but the actual template files (Dockerfile, docker-compose.yml, prisma/schema.prisma,
src/lib/auth.ts, etc.) need to be extracted from the TPRMAI reference implementation.

**Steps:**
1. Read TPRMAI source files and generalize them into templates with [PLACEHOLDER] values
2. Copy shared files from fastapi-nextjs scaffold (mock-oidc, .gitignore, seed script)
3. Create Next.js-specific templates: Dockerfile, next.config.js, middleware.ts,
   auth.ts, auth-context.tsx, db.ts, prisma/schema.prisma (RBAC tables only)
4. Create standard UI components: sidebar, data-table, breadcrumbs, quick-search, mode-toggle
5. Test by running /make-it with a simple app and selecting the nextjs-fullstack scaffold

### /resume-it: Sync changes from repo to installed location
Currently, skill files live in both `~/.claude/` (installed) and the make-it repo
(source of truth). Changes to the repo must be manually copied. Consider:
- A sync script that copies from repo to ~/.claude/
- Or using symlinks so the installed version always reads from the repo

## Low Priority

_All low priority items completed._

## Completed

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
