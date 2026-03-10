# Addendum: Section 9 -- AI Prompt Management System

**To be added to: AI Vibe Coded Design Pattern Guide (after Section 8: M.A.C.H. Architecture)**

---

## 9. AI Prompt Management

### Standard Says

Any application that uses AI/LLM features MUST externalize prompt management. Prompts should never be hardcoded in application source code for production systems. Use a centralized, versioned prompt management system with audit trails, rollback capability, and RBAC-controlled editing.

### In Practice

The depth of prompt management you need scales directly with how much AI your app uses. **Not every AI app needs a full prompt management platform.** The key principle is: **prompts are content, not code.** Treat them like CMS-managed content that business users can iterate on without developer involvement.

Here's how to determine your AI usage tier:

```
How much does your app use AI?
|
+-- None (no AI features)
|     -> Skip this section entirely
|
+-- Minimal (1-3 prompts, simple features like summarization)
|     -> Tier 1: Prompts in code with config override
|
+-- Moderate (4-10 prompts, AI is important but not the core product)
|     -> Tier 2: Database-stored prompts with basic admin UI
|
+-- Heavy (10+ prompts, AI IS the product, multiple agents/personas)
      -> Tier 3: Full prompt management platform
```

**AI Usage Level Indicators:**

| Signal | Minimal | Moderate | Heavy |
|--------|---------|----------|-------|
| Number of prompts | 1-3 | 4-10 | 10+ |
| Who tunes prompts | Developers only | Developers + product team | Product, ops, and business users |
| How often prompts change | Rarely (quarterly) | Sometimes (weekly/monthly) | Frequently (daily/weekly) |
| Prompt types | One type (system prompt) | 2-3 types (system, template, agent) | Many types (system, template, agent, skill, evaluation) |
| AI model diversity | Single model | 1-2 models | Multiple models/providers |
| Examples | Chatbot, summarizer, search enhancer | Content generator, recommendation engine, document analyzer | Training simulator, multi-agent system, AI-native SaaS |

---

### Tier 1: Prompts in Code with Config Override (Minimal AI)

**When to use:** Your app has 1-3 prompts that developers manage. Changes are infrequent.

**Pattern:** Store prompts as named constants in a dedicated file. Allow environment variable or database override for production tuning without redeployment.

```python
# Python (FastAPI)
# lib/prompts.py

import os

SUMMARIZE_SYSTEM_PROMPT = os.getenv(
    "PROMPT_SUMMARIZE",
    """You are a helpful assistant that summarizes documents.
    Be concise. Use bullet points for key findings."""
)

CLASSIFY_SYSTEM_PROMPT = os.getenv(
    "PROMPT_CLASSIFY",
    """You are a document classifier. Categorize the document
    into one of: [CATEGORIES]. Return JSON with category and confidence."""
)
```

```typescript
// TypeScript (Next.js)
// lib/prompts.ts

export const PROMPTS = {
  summarize: process.env.PROMPT_SUMMARIZE ??
    `You are a helpful assistant that summarizes documents.
     Be concise. Use bullet points for key findings.`,

  classify: process.env.PROMPT_CLASSIFY ??
    `You are a document classifier. Categorize the document
     into one of: [CATEGORIES]. Return JSON with category and confidence.`,
} as const;
```

**What you get:**
- All prompts in one file (easy to find and audit)
- Environment variable override for production changes without redeploy
- Version controlled via git

**What you don't get:**
- Non-developer editing
- Version history beyond git
- A/B testing or rollback without redeployment

---

### Tier 2: Database-Stored Prompts with Basic Admin UI (Moderate AI)

**When to use:** Your app has 4-10 prompts. Product managers or non-developers need to edit prompts. You need version history and rollback.

**Database schema (3 tables):**

```sql
-- Core prompt registry
CREATE TABLE managed_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_key VARCHAR(128) UNIQUE NOT NULL,   -- URL-safe slug
    name VARCHAR(256) NOT NULL,                -- Human-friendly name
    description TEXT,                          -- What this prompt does
    category VARCHAR(64) DEFAULT 'system',     -- system|template|agent
    content TEXT NOT NULL,                     -- The actual prompt text
    version INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    updated_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Immutable version history (append-only)
CREATE TABLE managed_prompt_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_key VARCHAR(128) NOT NULL,
    version INTEGER NOT NULL,
    content TEXT NOT NULL,
    change_summary TEXT,                       -- Why this version was created
    updated_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(prompt_key, version)
);

-- Audit trail
CREATE TABLE prompt_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action VARCHAR(64) NOT NULL,               -- created|updated|restored|tested
    prompt_key VARCHAR(128),
    version INTEGER,
    user_id VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_prompts_key ON managed_prompts(prompt_key);
CREATE INDEX idx_prompts_active ON managed_prompts(is_active);
CREATE INDEX idx_prompt_versions_key ON managed_prompt_versions(prompt_key);
CREATE INDEX idx_prompt_audit_time ON prompt_audit_log(created_at);
```

**API endpoints (6 routes):**

```
GET    /api/admin/prompts              -- List all prompts
GET    /api/admin/prompts/:key         -- Get prompt with version history
PUT    /api/admin/prompts/:key         -- Update prompt (creates new version)
POST   /api/admin/prompts/:key/test    -- Test prompt with sample input
POST   /api/admin/prompts/:key/restore -- Rollback to previous version
GET    /api/admin/prompts/:key/audit   -- View change history
```

**Runtime loader with fallback:**

```python
# lib/prompt_loader.py

from lib.database import fetch_one
from lib.prompts import PROMPTS  # Code defaults as fallback

_cache = {}  # Simple in-memory cache

async def get_prompt(key: str) -> str:
    """Load prompt: database first, code fallback."""
    if key in _cache:
        return _cache[key]

    row = await fetch_one(
        "SELECT content FROM managed_prompts WHERE prompt_key = $1 AND is_active = true",
        key,
    )

    if row:
        _cache[key] = row["content"]
        return row["content"]

    # Fallback to code-defined prompt
    return PROMPTS.get(key, "")

def invalidate_cache(key: str):
    """Clear cache when prompt is updated."""
    _cache.pop(key, None)
```

**Admin UI features:**
- List all prompts with status (active/inactive)
- Edit prompt content with a simple textarea
- Test prompt with sample input and see AI response
- View version history with diff between versions
- One-click rollback to any previous version
- Change summary required on each edit

**What you get:**
- Non-developers can edit prompts through the admin panel
- Full version history with rollback
- Test before deploy
- Audit trail of who changed what

**What you don't get:**
- Usage analytics and performance metrics
- Multi-model/multi-provider management
- Import/export for environment promotion
- Redis caching for high-traffic scenarios

---

### Tier 3: Full Prompt Management Platform (Heavy AI)

**When to use:** AI is the core of your product. You have 10+ prompts across multiple agents, models, or providers. Multiple teams (product, engineering, ops) need to manage prompts independently. You need usage analytics, performance tracking, and enterprise-grade audit trails.

**Reference implementation:** The `auditgithub` project provides a production-grade Tier 3 system.

**Database schema (6 tables):**

```sql
-- 1. Prompt registry with rich metadata
CREATE TABLE prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(128) UNIQUE NOT NULL,
    name VARCHAR(256) NOT NULL,
    description TEXT,
    category VARCHAR(64) NOT NULL,         -- system|user|template|agent|skill|mcp
    subcategory VARCHAR(64),               -- e.g., security-analysis, remediation
    agent_id VARCHAR(128),                 -- Which agent uses this (null = global)
    provider VARCHAR(64),                  -- claude|openai|gemini|any
    model VARCHAR(128),                    -- e.g., claude-sonnet-4-5, gpt-4o
    current_version INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    is_locked BOOLEAN DEFAULT false,
    locked_by VARCHAR(255),
    locked_reason TEXT,
    source_file VARCHAR(512),              -- Where this was extracted from
    created_by VARCHAR(255),
    updated_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Immutable version history
CREATE TABLE prompt_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id UUID NOT NULL REFERENCES prompts(id),
    version INTEGER NOT NULL,
    content TEXT NOT NULL,
    system_message TEXT,                   -- Optional separate system message
    parameters JSONB,                      -- {temperature, max_tokens, top_p, ...}
    model VARCHAR(128),                    -- Version-level model override
    input_schema JSONB,                    -- Expected input variables
    output_schema JSONB,                   -- Expected output format
    change_summary TEXT,
    created_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(prompt_id, version)
);

-- 3. Runtime usage tracking and metrics
CREATE TABLE prompt_usages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id UUID NOT NULL REFERENCES prompts(id),
    usage_type VARCHAR(64),                -- code_reference|runtime_call|agent_binding
    location VARCHAR(512),                 -- File path, agent name, or tool name
    last_called_at TIMESTAMPTZ,
    call_count BIGINT DEFAULT 0,
    avg_latency_ms INTEGER DEFAULT 0,
    avg_tokens_in INTEGER DEFAULT 0,
    avg_tokens_out INTEGER DEFAULT 0,
    total_tokens BIGINT DEFAULT 0,
    error_count BIGINT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Flexible tagging
CREATE TABLE prompt_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id UUID NOT NULL REFERENCES prompts(id),
    tag VARCHAR(64) NOT NULL,
    UNIQUE(prompt_id, tag)
);

-- 5. Saved test cases for regression testing
CREATE TABLE prompt_test_cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id UUID NOT NULL REFERENCES prompts(id),
    name VARCHAR(256) NOT NULL,
    input_data JSONB,
    expected_output TEXT,
    created_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Immutable audit log
CREATE TABLE prompt_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action VARCHAR(64) NOT NULL,
    prompt_id UUID,
    prompt_slug VARCHAR(128),
    version INTEGER,
    user_id VARCHAR(255),
    user_email VARCHAR(255),
    old_value JSONB,
    new_value JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**API surface (30+ endpoints):**

| Category | Endpoints |
|----------|-----------|
| CRUD | Create, list (with filtering/pagination/search), get by slug, update (creates version), soft-delete, reactivate |
| Versioning | List versions, get specific version, restore to version, unified diff between versions |
| Locking | Lock prompt (prevent edits), unlock |
| Tags | Add tag, remove tag, list all tags with counts |
| Test Cases | Create test case, list test cases, execute test run |
| Usage | List usage locations, record runtime call metrics |
| Audit | System-wide audit log, per-prompt audit log |
| Analytics | Overview dashboard (totals, error rates), agent summary, top prompts by usage |
| Import/Export | Export prompts as JSON, bulk import from JSON |
| Search | Full-text search across prompts |

**3-tier runtime resolution:**

```
Tier 1: Redis Cache (5-minute TTL)
  -> Fast retrieval for high-traffic prompts
  -> Invalidated on update

Tier 2: Database (authoritative source)
  -> Always consulted if cache misses
  -> Provides current, version-controlled prompts

Tier 3: Seed Fallback (emergency only)
  -> Used if database is unreachable
  -> Loaded from code-defined seed definitions
  -> Logs ERROR when used (alerts ops that DB is down)
```

**Frontend pages (5):**
1. **Prompt Registry** -- Searchable, filterable list with analytics cards
2. **Prompt Detail** -- Tabbed view (overview, versions, usage, test cases, audit)
3. **Prompt Editor** -- Metadata form, content editor, JSON schema editors, change summary
4. **Analytics Dashboard** -- System stats, category/provider/model breakdowns, top prompts
5. **Audit Log** -- Immutable trail with action filtering and user tracking

**Permission model:**

| Scope | Actions |
|-------|---------|
| prompts:read | List, view, search, diff, export |
| prompts:write | Create, update, tags, test cases |
| prompts:delete | Soft-delete (deactivate) |
| prompts:admin | Lock/unlock, import, audit logs |

**Key architectural decisions:**
1. **Immutable versioning** -- Updates create new versions, never modify old ones
2. **Append-only audit** -- All actions logged, never deleted/modified
3. **Soft deletes** -- Prompts deactivated, not hard-deleted (enables recovery)
4. **Runtime metrics** -- Usage tracking captures real-world performance
5. **No hardcoded prompts in production** -- All prompts live in database, seeded from code on first run

---

### When to Deviate

- **Prototype / hackathon:** Tier 1 is fine. You can always upgrade to Tier 2 later.
- **Single developer, no prompt iteration needed:** Tier 1 with git version control is sufficient.
- **Your prompts genuinely never change:** If the prompt is a fixed instruction (e.g., "format this as JSON"), a code constant is fine. But if it shapes user-facing AI behavior, it WILL change -- plan for it.

### Getting Started

1. **Determine your AI usage tier** using the indicator table above
2. **For Tier 1:** Create a `lib/prompts.py` (or `.ts`) file with all prompts as named constants, add env var overrides
3. **For Tier 2:** Add the 3-table schema, build the admin API (6 routes), add a basic prompt editor to your admin panel, implement the fallback loader
4. **For Tier 3:** Use the `auditgithub` prompt management system as your reference architecture, implement the 6-table schema, build the full API surface, add the 5 frontend pages, implement 3-tier caching

**Upgrading path:** Start at the tier that matches your current needs. Each tier builds on the previous one -- Tier 1 code constants become Tier 2 seed defaults, which become Tier 3 seed fallbacks.

---

### Standards Compliance Matrix Update

Add this row to the existing compliance matrix:

| Standard | Required | Flexible | Skip If |
|----------|----------|----------|---------|
| AI Prompt Management | Yes -- if using AI | Tier level (1/2/3) based on AI usage | No AI features |

---

### Quick-Start Checklist Update

Add to the **During Development** section:
- [ ] AI prompts externalized (not hardcoded in business logic)
- [ ] Prompt management tier determined and implemented

Add to the **Before Production** section:
- [ ] Prompt version history enabled (Tier 2+)
- [ ] Prompt audit logging active (Tier 2+)
- [ ] Prompt testing capability available (Tier 2+)

Add to the **Production Hardening** section:
- [ ] Prompt usage analytics and performance monitoring (Tier 3)
- [ ] Prompt caching strategy implemented (Tier 3)
- [ ] Prompt import/export for environment promotion (Tier 3)

---

*Document History*

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-03-06 | Architecture Team | Initial release bridging Enterprise Standards with practical implementation |
| 1.1 | 2026-03-10 | Architecture Team | Added Section 9: AI Prompt Management with tiered implementation pattern |
