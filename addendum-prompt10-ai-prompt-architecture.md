# Addendum: Updated Prompt #10 -- Design AI Prompt Architecture

**To be added to: Prompts for Building Enterprise Applications (replaces existing Prompt #10)**

---

## 10. Design AI Prompt Architecture (if applicable)

This Design AI Prompt Architecture prompt helps a developer design an application where all AI prompts are centrally managed rather than being buried in code. By scaling the prompt management system to match the application's AI usage level -- from simple config overrides to a full management platform -- it ensures prompts are discoverable, editable, testable, and auditable while avoiding over-engineering for simpler use cases.

**AI Usage Tiers:**

The prompt adapts based on the AI usage level determined during the design phase:

| AI Usage Level | Prompt Count | Who Edits Prompts | Tier |
|----------------|-------------|-------------------|------|
| Minimal | 1-3 | Developers only | 1 -- Code + config override |
| Moderate | 4-10 | Developers + product team | 2 -- Database + basic admin UI |
| Heavy | 10+ | Product, ops, business users | 3 -- Full management platform |

---

### Tier 1 Prompt (Minimal AI -- 1-3 prompts)

```
Set up AI prompt management for [YOUR PROJECT NAME] -- Tier 1 (minimal).

This app uses AI for:
[LIST AI FEATURES -- e.g., document summarization, content classification]

AI prompts (list all):
[PROMPT 1 NAME]: [WHAT IT DOES]
[PROMPT 2 NAME]: [WHAT IT DOES]
[PROMPT 3 NAME]: [WHAT IT DOES]

Requirements:
- Store all prompts in a single dedicated file (lib/prompts.py or lib/prompts.ts)
- Each prompt is a named constant with a descriptive variable name
- Allow environment variable override for each prompt (for production tuning
  without redeployment)
- Include the AI model name and parameters (temperature, max_tokens) alongside
  each prompt
- Add a comment block at the top explaining each prompt's purpose

Pattern to follow:
- Python: PROMPT_NAME = os.getenv("PROMPT_NAME", """default content""")
- TypeScript: export const PROMPTS = { name: process.env.PROMPT_NAME ?? `default` }

Do NOT build a database or admin UI for prompts -- this app only has a few
prompts and they rarely change. Environment variable overrides are sufficient.
```

**Required context:** AI features list, prompt names and purposes
**Runs when:** AI usage level is "minimal" (1-3 prompts, developers manage them)

---

### Tier 2 Prompt (Moderate AI -- 4-10 prompts)

```
Design the AI prompt management system for [YOUR PROJECT NAME] -- Tier 2
(moderate). All AI prompts should be stored in the database and editable
through the admin UI without code changes.

This app uses AI for:
[LIST AI FEATURES]

AI prompts to manage (list all):
[PROMPT 1 NAME]: [WHAT IT DOES] -- category: [system|template|agent]
[PROMPT 2 NAME]: [WHAT IT DOES] -- category: [system|template|agent]
[... up to 10 prompts]

Database schema needed (3 tables):
1. managed_prompts -- prompt registry with slug, name, content, version,
   is_active, category, updated_by timestamps
2. managed_prompt_versions -- immutable version history (append-only),
   linked to prompt by key, stores content + change_summary + who
3. prompt_audit_log -- append-only audit trail of all changes (action,
   prompt_key, version, user, timestamp)

API endpoints needed (6 routes, all behind admin permission):
- GET /api/admin/prompts -- list all prompts with status
- GET /api/admin/prompts/:key -- get prompt with version history
- PUT /api/admin/prompts/:key -- update prompt (creates new version,
  requires change_summary)
- POST /api/admin/prompts/:key/test -- test prompt with sample input,
  return AI response without saving
- POST /api/admin/prompts/:key/restore -- rollback to a previous version
- GET /api/admin/prompts/:key/audit -- view change log

Runtime prompt loader:
- Load from database first, fall back to code-defined defaults
- Simple in-memory cache (invalidate on update)
- Seed the database on first run from code-defined prompt constants

Admin UI features:
- Prompt list page with name, category, version, status, last updated
- Edit page with content textarea, change summary field (required)
- Test panel: enter sample input, see AI response before saving
- Version history with diff view between any two versions
- One-click rollback to any previous version
- Audit trail showing who changed what and when

Permission required: [PROMPT_ADMIN_PERMISSION -- e.g., can_manage_prompts]

Storage: [database / PostgreSQL]

Code defaults: Create a lib/prompts.py (or .ts) file with all prompts as
named constants. These serve as the initial seed data AND the fallback if
the database is unavailable.
```

**Required context:** AI features list, prompt names/purposes/categories, storage preference, admin permission name
**Runs when:** AI usage level is "moderate" (4-10 prompts, product team needs to edit)

---

### Tier 3 Prompt (Heavy AI -- 10+ prompts, AI-native app)

```
Design a full AI prompt management platform for [YOUR PROJECT NAME] -- Tier 3
(heavy). This is an AI-native application where prompts are a core part of the
product. The system must support multiple agents, models, and providers with
enterprise-grade versioning, analytics, and access control.

This app uses AI for:
[LIST AI FEATURES]

AI agents/components:
[AGENT 1]: [WHAT IT DOES] -- model: [MODEL] -- provider: [PROVIDER]
[AGENT 2]: [WHAT IT DOES] -- model: [MODEL] -- provider: [PROVIDER]
[... list all AI agents]

AI prompts to manage:
[LIST ALL PROMPTS with name, category, agent, description]

Database schema needed (6 tables):

1. prompts -- Central registry with rich metadata:
   id, slug (unique), name, description, category (system|user|template|
   agent|skill|mcp), subcategory, agent_id, provider, model, current_version,
   is_active, is_locked, locked_by, locked_reason, source_file, created_by,
   updated_by, timestamps

2. prompt_versions -- Immutable version history (append-only):
   id, prompt_id (FK), version, content, system_message, parameters (JSONB
   with temperature/max_tokens/top_p), model override, input_schema (JSONB),
   output_schema (JSONB), change_summary, created_by, timestamp
   Constraint: UNIQUE(prompt_id, version)

3. prompt_usages -- Runtime usage tracking and metrics:
   id, prompt_id (FK), usage_type (code_reference|runtime_call|agent_binding),
   location, last_called_at, call_count, avg_latency_ms, avg_tokens_in,
   avg_tokens_out, total_tokens, error_count, timestamps

4. prompt_tags -- Flexible tagging system:
   id, prompt_id (FK), tag
   Constraint: UNIQUE(prompt_id, tag)

5. prompt_test_cases -- Saved test inputs for regression testing:
   id, prompt_id (FK), name, input_data (JSONB), expected_output, created_by,
   timestamp

6. prompt_audit_log -- Immutable append-only audit trail:
   id, action (created|updated|restored|activated|deactivated|locked|unlocked|
   deleted|tested|imported), prompt_id, prompt_slug, version, user_id,
   user_email, old_value (JSONB), new_value (JSONB), ip_address, timestamp

API endpoints needed (30+ routes organized by category):

Prompt CRUD:
- POST /prompts/ -- Create prompt (prompts:write)
- GET /prompts/ -- List with filtering, pagination, search (prompts:read)
- GET /prompts/:slug -- Get single prompt (prompts:read)
- PUT /prompts/:slug -- Update, creates new version (prompts:write)
- DELETE /prompts/:slug -- Soft-delete/deactivate (prompts:delete)
- PATCH /prompts/:slug/activate -- Reactivate (prompts:write)

Locking:
- PATCH /prompts/:slug/lock -- Lock to prevent edits (prompts:admin)
- PATCH /prompts/:slug/unlock -- Unlock (prompts:admin)

Versioning:
- GET /prompts/:slug/versions -- List all versions (prompts:read)
- GET /prompts/:slug/versions/:version -- Get specific version (prompts:read)
- POST /prompts/:slug/restore/:version -- Restore to version (prompts:write)
- GET /prompts/:slug/diff/:v1/:v2 -- Unified diff between versions (prompts:read)

Usage & Analytics:
- GET /prompts/:slug/usages -- Runtime statistics (prompts:read)
- GET /prompts/analytics/overview -- System-wide analytics (prompts:read)
- GET /prompts/agents -- List agents with prompt counts (prompts:read)
- GET /prompts/agents/:agent_id -- Agent detail (prompts:read)

Tags:
- POST /prompts/:slug/tags -- Add tag (prompts:write)
- DELETE /prompts/:slug/tags/:tag -- Remove tag (prompts:write)
- GET /prompts/tags -- List all tags with counts (prompts:read)

Test Cases:
- POST /prompts/:slug/test-cases -- Create test case (prompts:write)
- GET /prompts/:slug/test-cases -- List test cases (prompts:read)

Audit:
- GET /prompts/audit -- System-wide audit log (prompts:admin)
- GET /prompts/:slug/audit -- Per-prompt audit log (prompts:read)

Import/Export:
- GET /prompts/export -- Export as JSON (prompts:admin)
- POST /prompts/import -- Bulk import from JSON (prompts:admin)

Search:
- GET /prompts/search?q=... -- Full-text search (prompts:read)

Runtime prompt loader with 3-tier resolution:
1. Redis cache (5-minute TTL) -- fast retrieval, invalidated on update
2. Database (authoritative source) -- always consulted if cache misses
3. Seed fallback (emergency only) -- code-defined defaults if DB is down,
   logs ERROR when used

Public API for runtime consumers:
- get_prompt(slug, version?) -- Resolve prompt with 3-tier fallback
- render_prompt(slug, variables?) -- Render template with variable substitution
- get_prompt_with_system(slug, variables?) -- Get (content, system_message,
  parameters) tuple for AI provider calls
- invalidate_cache(slug) -- Clear cache on update

Frontend pages needed (5):

1. Prompt Registry -- DataTable with sortable columns, advanced filtering
   (category, provider, status, search), analytics summary cards, create dialog

2. Prompt Detail -- Tabbed interface: Overview, Versions (with diff viewer),
   Usage (call counts, latency, tokens, errors), Test Cases, Audit Log

3. Prompt Editor -- Metadata form, content editor (markdown), system message
   editor, JSON editors for parameters/input_schema/output_schema, change
   summary (required), tags management

4. Analytics Dashboard -- System-wide statistics, category/provider/model
   breakdowns, top prompts by usage, recent changes feed, error rates

5. Audit Log -- Immutable trail viewer, filtering by action/slug, pagination,
   action color coding, user/timestamp tracking, old/new value display

Permission scopes:
- prompts:read -- List, view, search, diff, export
- prompts:write -- Create, update, tags, test cases
- prompts:delete -- Soft-delete (deactivate)
- prompts:admin -- Lock/unlock, import, audit logs, analytics

Seed system: Create a scripts/seed_prompts.py that defines all prompts with
metadata (slug, name, description, category, agent_id, provider, model,
source_file). Run on first deploy to populate the database. These also serve
as Tier 3 (emergency) fallback for the runtime loader.
```

**Required context:** AI features list, agents/models/providers, all prompt names/categories, permission model
**Runs when:** AI usage level is "heavy" (10+ prompts, AI-native application)

---

### How /make-it Uses This Prompt

During the **Ideation** phase, when the user describes AI features, /make-it internally classifies the AI usage level:

```
AI features mentioned?
  No -> ai_usage_level = "none", skip Prompt #10 entirely
  Yes -> Count distinct AI behaviors/prompts described:
    1-3  -> ai_usage_level = "minimal"
    4-10 -> ai_usage_level = "moderate"
    10+  -> ai_usage_level = "heavy"
```

Additional signals that push toward a higher tier:
- "Non-technical people need to edit prompts" -> at least Tier 2
- "Multiple AI models or providers" -> at least Tier 2
- "AI personas, agents, or evaluators" -> likely Tier 3
- "Prompts will change frequently" -> at least Tier 2
- "Need analytics on AI usage" -> Tier 3

The appropriate tier prompt is then auto-filled with context from the conversation and executed during the Build phase.

---

*Document History*

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-03-06 | Architecture Team | Initial release -- single prompt for AI architecture |
| 1.1 | 2026-03-10 | Architecture Team | Expanded to 3-tier system based on AI usage level. Added Tier 1 (code+config), Tier 2 (database+admin UI), Tier 3 (full platform from auditgithub reference). Added classification logic for /make-it integration. |
