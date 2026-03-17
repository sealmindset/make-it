# TODO -- make-it Framework

## High Priority

### /retrofit-it: Plain-language phase presentation
**Lesson learned:** The phased retrofit plan (Phase A, B, C...) uses technical language
that assumes the reader understands database migrations, OIDC, RBAC tables, Docker Compose,
and middleware. This defeats the purpose -- /retrofit-it should speak the same plain English
as /make-it.

**Fix:** Rewrite the Phase 4 (Plan) step in retrofit-it.md to present phases in user terms:
- Phase A: "Setting up your development environment" (not "Docker + PostgreSQL migration")
- Phase B: "Adding secure login and user permissions" (not "OIDC + RBAC tables")
- Phase C: "Making your AI flexible" (not "multi-provider AI abstraction")
- Phase D: "Polishing the interface" (not "standard UI components + DataTable")
- Phase E: "Final security checks and deployment prep"

The technical details should be internal (logged to state file), not shown to the user.

### Add Multi-Provider AI Pattern to skill references
The /make-it framework currently assumes a single AI provider. Real apps need configurable
AI providers (Anthropic Foundry, Claude direct, OpenAI, Ollama, Docker local).

**Update these files:**
- `references/design-blueprint.md` -- Add AI Provider selection to Design phase decisions
- `references/prompt-templates.md` -- Add Prompt #10 variants for multi-provider setup
- `references/guardrails.md` -- Add Tier 1 guardrail: AI provider must be env-configurable
- `templates/app-context.md` -- Add `ai_providers` section with model tiering
- `commands/make-it.md` -- Update Ideation to ask about AI features, update Build to
  generate multi-provider abstraction with model tiering per feature complexity

**Pattern to follow:** auditgithub's `AI_PROVIDER` env var approach:
- `AI_PROVIDER=anthropic_foundry` (Azure AI Foundry with Claude)
- `AI_PROVIDER=claude` (direct Anthropic API)
- `AI_PROVIDER=openai` (OpenAI API)
- `AI_PROVIDER=ollama` (local Ollama)
- `AI_PROVIDER=docker` (Docker AI)
- Per-agent model selection via env vars (Opus for complex reasoning, Sonnet for standard, Haiku for simple)

### Add OIDC/RBAC Reference Implementation to skill references
DeliverIt provides the gold-standard implementation of the /make-it OIDC and RBAC patterns.
The skill references should explicitly document these patterns so every new build and
retrofit follows the same proven approach.

**Update these files:**
- `references/design-blueprint.md` -- Add OIDC flow diagram (login → mock-oidc → callback → JWT cookie → /me → logout), document the DeliverIt auth.py pattern
- `references/prompt-templates.md` -- Update Prompt #8 (Auth) and #9 (Permissions) with
  concrete code patterns from DeliverIt: auth router, permission middleware, permission
  service with cache, role/permission models, seed migration format
- `references/guardrails.md` -- Add Tier 1 checklist items: `require_permission` on all
  routes, permission service with invalidation cache, 4 system roles seeded, admin UI for
  user/role management
- `commands/retrofit-it.md` -- Reference DeliverIt as the target pattern for auth retrofit

**Key patterns from DeliverIt to codify:**
- `require_permission(resource, action)` as FastAPI Depends
- Permission service with in-memory cache + invalidation
- Role model with `is_system` flag (system roles can't be deleted)
- Seed migration: 4 roles, page-level CRUD permissions, role_permissions mappings
- Auth callback reads role from DATABASE (not OIDC claims)
- JWT contains: sub, email, name, role_id, role_name, permissions[]
- Logout is POST, clears httpOnly cookie
- mock-oidc copied as-is, seed script registers app users

## Medium Priority

### /retrofit-it: Automated risk score calibration
The current risk weights are manual estimates. After several real retrofits, calibrate
the weights based on actual effort and breakage rates.

### Scaffold for non-FastAPI+Next.js stacks
Currently only the fastapi-nextjs scaffold exists. Consider scaffolds for:
- Next.js full-stack (API routes as backend) -- common for apps like TPRMAI
- Express + React
- Django + React

## Low Priority

### /retrofit-it: Pre-retrofit snapshot
Before making any changes, create a git branch or tag so the user can always
roll back to their exact pre-retrofit state.
