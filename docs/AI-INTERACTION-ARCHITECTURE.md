# AI Interaction Architecture

## Purpose

The AI Interaction Architecture is a standardized framework for building AI-powered features into applications created by `/make-it`. It provides a structured agent system with a common lifecycle, context assembly pipeline, routing, job tracking, and graceful degradation -- so every app gets production-grade AI infrastructure without rebuilding it from scratch.

## The Problem

Every AI-powered app built with `/make-it` needs the same foundational patterns:

1. **Agent identity** -- Each AI behavior needs its own system prompt, model tier, and domain context. Without structure, prompts get hardcoded in random files, model choices are inconsistent, and there's no registry of what AI does what.

2. **Context assembly** -- AI responses are only as good as the context they receive. Every agent needs domain data (DB queries, documents, API data) assembled into prompts with proper truncation, safety preambles, and conversation history. Without a standard pattern, each agent reinvents this pipeline.

3. **Conversation persistence** -- Multi-turn chat requires server-side message storage, session isolation (user A can't see user B's chats), and history management. Building this ad-hoc leads to inconsistent storage patterns and security gaps.

4. **Background processing** -- Batch AI tasks (scoring 500 vendors, extracting 200 contracts) need job lifecycle tracking: queued, running, progress updates, completed, failed. Without it, users stare at spinners with no feedback.

5. **Graceful degradation** -- When the AI provider goes down (and it will), apps crash. Some agents can return deterministic results instead; others should show a clear error. This decision should be per-agent, not app-wide.

6. **Routing** -- Apps with multiple agents need a way to route requests to the right one. Chat messages route by conversation context; batch jobs route by agent slug. Without a registry, routing is hardcoded and brittle.

**Evidence:** Four real applications (AuditGithub, Tailspend, TechDebt, ShadowFinder) all built these patterns by hand. Same bugs, same architectural decisions, same solutions -- rebuilt from zero each time.

## How It's Addressed

The architecture defines seven components that work together:

### 1. Interaction Level Classification

Every AI app is classified into one of three levels during the Design phase. This classification determines what infrastructure gets generated -- nothing more, nothing less.

| Level | Name | Signals | What Gets Generated |
|-------|------|---------|---------------------|
| `batch-only` | Single-Purpose Agents | "analyze", "scan", "score", "classify", "extract" | BaseAgent, agent registry, context builders, job tracking |
| `conversational` | Multi-Turn Chat | "chat", "ask questions", "assistant", "Q&A" | Above + conversation tables, chat UI, SSE streaming |
| `hybrid` | Both | Chat features AND background/batch processing | Everything from both levels |

`batch-only` apps **skip** conversation tables, chat UI, and SSE streaming entirely. No dead code.

### 2. Agent Registry

Every AI agent is declared in two places:

**`app-context.json`** (design-time declaration):
```json
{
  "slug": "security-architect",
  "name": "Security Architect",
  "type": "conversational",
  "prompt_key": "security_architect_system",
  "model_tier": "heavy",
  "description": "Multi-turn security analysis chat",
  "context_sources": ["repositories", "vulnerabilities", "findings"],
  "rule_based_fallback": false
}
```

**Backend registry module** (runtime mapping):
```python
AGENT_REGISTRY: dict[str, type[BaseAgent]] = {
    "security-architect": SecurityArchitectAgent,
    "vendor-enrichment": VendorEnrichmentAgent,
    "cost-analyzer": CostAnalyzerAgent,
}

def get_agent(slug: str) -> BaseAgent:
    agent_class = AGENT_REGISTRY.get(slug)
    if not agent_class:
        raise AgentNotFoundError(f"Unknown agent: {slug}")
    return agent_class()
```

Every agent's `prompt_key` maps to a seeded row in `managed_prompts` (database-driven prompt management). No hardcoded system prompts in agent code.

### 3. BaseAgent Abstract Class

All agents extend `BaseAgent`, which enforces a standard lifecycle:

```
invoke(input)
  1. Sanitize input (strip injection patterns)
  2. Validate prompt size
  3. Mask PII
  4. Load system prompt from managed_prompts DB (code fallback)
  5. Load brain context (if brain layer enabled)
  6. Call build_context() for domain-specific data
  7. Assemble full prompt with truncation budget
  8. Call AI provider
  9. On provider failure: call fallback() if configured, else raise
  10. Unmask PII in response
  11. Validate output
  12. Return
```

Two subclass patterns:

- **ConversationalAgent** -- adds `chat()` method with conversation history assembly and SSE streaming
- **BatchAgent** -- adds `run_batch()` method with job creation, per-item progress tracking, and completion/failure recording

### 4. Context Builder Pattern

Each agent implements `build_context()` to gather domain-specific data. This is the primary customization point -- the scaffold provides structure, the app provides domain queries.

**Context assembly order (full prompt):**

```
1. Safety preamble (immutable)              -- Never truncated
2. System prompt (from managed_prompts DB)  -- Never truncated
3. Brain memory context (if enabled)        -- 15% of budget
4. Domain context (from build_context)      -- 55-70% of budget
5. Conversation history (chat agents only)  -- 30% of budget
6. User input (sanitized, tagged)           -- Never truncated
```

When total context exceeds `AI_MAX_PROMPT_CHARS`, truncation follows the budget: domain context truncated first (agent decides priority of sections), then conversation history (oldest messages dropped first). Safety preamble, system prompt, and user input are never truncated.

**Real-world context builder examples:**

| App | Agent | Context Sources | Data Gathered |
|-----|-------|-----------------|---------------|
| AuditGithub | Security Architect | repos, vulns, findings | Repo metadata, CVE list, severity counts |
| Tailspend | Spend Analyst | vendors, contracts, invoices | Vendor profiles, contract terms, spend by year |
| TechDebt | App Rationalizer | applications, usage, costs | App metadata, sign-in trends, risk scores |
| ShadowFinder | SaaS Detector | emails, expenses, vendors | Email signals, expense items, vendor catalog |

### 5. Agent Routing

**Conversational agents** route via `agent_slug` on the `conversations` table:

```
POST /api/ai/conversations                    -- Create (pass agent_slug)
POST /api/ai/conversations/{id}/messages      -- Chat (agent resolved from conversation)
GET  /api/ai/conversations                    -- List user's conversations
GET  /api/ai/conversations/{id}               -- Get with messages
DELETE /api/ai/conversations/{id}             -- Soft-delete (archive)
```

**Batch agents** route via slug in the URL:

```
POST /api/ai/agents/{slug}/run                -- Trigger job (returns job_id)
GET  /api/ai/agents/{slug}/jobs               -- List jobs for agent
```

Unknown slugs return 404. All endpoints enforce RBAC.

### 6. Background Job Tracking

Batch agents reuse the existing job status table (DI03 pattern) -- no separate `ai_jobs` table. The `task_type` column distinguishes AI jobs: `"ai_agent:{slug}"`.

AI-specific metadata stored in `result_data` JSON:
```json
{
  "agent_slug": "vendor-enrichment",
  "model_used": "claude-sonnet-4-20250514",
  "total_input_tokens": 45200,
  "total_output_tokens": 12800,
  "cost_usd": 0.34,
  "items_processed": 47,
  "items_succeeded": 45,
  "items_failed": 2
}
```

AI agent jobs appear alongside other background tasks in the job status page, with agent name as a filterable column and token/cost data visible.

### 7. Rule-Based Fallback

Per-agent opt-in. When the AI provider is unavailable:

| Agent Type | Fallback Behavior |
|------------|------------------|
| Conversational (fallback=true) | Returns "AI temporarily unavailable" system message. Does NOT store a failed message. Shows retry button. |
| Conversational (fallback=false) | Returns error to client. |
| Batch (fallback=true) | Runs deterministic logic (thresholds, keyword matching, rules). Marks job `completed_without_ai`. |
| Batch (fallback=false) | Marks job failed with error. |

**Example -- Tailspend recommendation fallback:**
```python
async def fallback(self, contract_data: str, **kwargs) -> str:
    contract = json.loads(contract_data)
    if contract["annual_cost"] < 5000:
        return json.dumps({"recommendation": "ELIMINATE", "confidence": 0.7,
                           "reason": "Below $5k threshold"})
    if contract["similar_vendors_count"] > 2:
        return json.dumps({"recommendation": "CONSOLIDATE", "confidence": 0.6,
                           "reason": f"{contract['similar_vendors_count']} similar vendors"})
    return json.dumps({"recommendation": "REVIEW", "confidence": 0.3,
                       "reason": "Insufficient signals"})
```

Not every agent benefits from fallback. Some are better off returning an error than a low-confidence deterministic guess.

## How It's Included or Excluded

### Inclusion (automatic)

The architecture activates when `ai_features.needed = true` in `app-context.json`. This is set during the Ideation/Design phase when the user describes AI-powered features. No manual flag-setting required.

**What triggers it:**
- User mentions AI, ML, or LLM features during ideation
- User describes analysis, scoring, classification, chat, Q&A, or assistant features
- AI SDK dependencies detected in existing projects (/resume-it, /retrofit-it)

**What gets generated depends on interaction level:**

| Interaction Level | Generated | Skipped |
|-------------------|-----------|---------|
| `batch-only` | BaseAgent, registry, context builders, job tracking, batch routes | Conversation tables, chat UI, SSE streaming |
| `conversational` | Everything above + conversation tables, chat panel, SSE streaming, chat routes | (nothing skipped) |
| `hybrid` | Everything | (nothing skipped) |

### Exclusion (automatic)

- `ai_features.needed = false` -- entire architecture skipped
- `ai_features.interaction_level = "none"` -- skipped
- Non-AI apps (CLI tools, libraries, simple CRUD apps with no AI) -- never activated

No AI infrastructure is generated for apps that don't need it. Zero dead code.

### Adding to an existing app (/resume-it)

`/resume-it` detects missing AI interaction patterns via catch-up scan (checks AI16-AI22):

```
"I found 7 improvements available since your app was built -- including
AI agent infrastructure (agent registry, routing, fallback). Want me to
bring your app up to date?"
```

If the user accepts, /resume-it scaffolds the architecture into the existing codebase.

## When to Use It

**Use it when the app has ANY AI-powered feature.** Specifically:

| Scenario | Interaction Level | Example |
|----------|-------------------|---------|
| AI analyzes data in bulk, no user interaction | `batch-only` | Score 500 vendors for risk, extract contract terms from PDFs |
| User chats with an AI assistant | `conversational` | Q&A about security findings, help with expense categorization |
| Both chat AND background processing | `hybrid` | Chat with AI about vendors AND run batch enrichment on all vendors |
| Multiple distinct AI behaviors | any | Security analysis agent + code review agent + cost estimation agent |
| AI should work when provider is down | any (with fallback) | Critical scoring that can't wait for provider recovery |

**Don't use it when:**
- App has no AI features (obvious)
- AI is a single hardcoded API call with no prompt management, no conversation, no job tracking (rare -- even simple AI features benefit from the safety pipeline)

## Why to Use It

### Consistency
Every AI app follows the same patterns. Engineers moving between projects recognize the agent registry, BaseAgent lifecycle, context builder pattern, and routing conventions instantly.

### Safety by default
BaseAgent enforces the safety pipeline on every AI call: input sanitization, PII masking, prompt size validation, output validation. Individual agents can't accidentally bypass these protections because they're baked into the base class.

### Auditability
The agent registry + context_sources field documents exactly what data each agent accesses. Prompt management stores version history of every system prompt. Job tracking records token usage and cost per agent. The entire AI data flow is traceable.

### Graceful degradation
Apps don't crash when the AI provider goes down. Fallback is a deliberate per-agent design decision, not an afterthought.

### No wasted code
`batch-only` apps don't generate conversation tables, chat UI, or SSE streaming. The interaction level classification ensures the app only gets infrastructure it actually uses.

### Faster builds
Four apps rebuilt these patterns from scratch. The architecture encodes all lessons learned (context truncation strategy, job tracking via DI03, SSE heartbeats, conversation isolation) so they're correct on first generation.

## Build Standards Verification

The architecture is enforced by 7 build-standards checks (AI16-AI22) plus 1 live verification (V16):

| Check | Severity | What It Verifies |
|-------|----------|-----------------|
| AI16 | FIX | Interaction level classified in app-context.json |
| AI17 | BLOCK | Agent registry: every agent has a class, prompt_key has a seed, slugs are consistent |
| AI18 | BLOCK | BaseAgent exists with full lifecycle (invoke, stream, build_context, safety pipeline) |
| AI19 | FIX | Context builder per agent returns domain data (not empty), truncation works |
| AI20 | FIX | Agent routing: chat by agent_slug, batch by /agents/{slug}/run, unknown = 404 |
| AI21 | FIX | Rule-based fallback works for configured agents, errors for non-configured |
| AI22 | FIX | Batch jobs use DI03 table with task_type="ai_agent:{slug}" and token/cost metadata |
| V16 | BLOCK | End-to-end: each agent responds correctly, unknown slugs return 404, fallback works |

`BLOCK` checks must pass before the app is handed to the user. `FIX` checks are auto-remediated during build-verify.

## Relationship to Other AI Components

The AI Interaction Architecture (Section 11c) sits between the foundation layers and the optional brain layer:

```
Section 9:  AI Provider Abstraction     -- HOW the app talks to AI (provider, model tiers, failover)
Section 10: AI Prompt Management        -- WHERE system prompts live (database, versioned, admin UI)
Section 11: NeMo Guardrails             -- HOW AI safety is tested (Colang rails, attestation)
Section 11b: AI Operational Safety      -- HOW inputs/outputs are protected (sanitize, validate, mask, rate limit)
Section 11c: AI Interaction Architecture -- HOW agents are structured, routed, and tracked (this document)
Section 14: AI Memory / Brain Layer     -- HOW agents remember across sessions (optional, additive)
```

Each layer is independent but builds on the ones below it. The interaction architecture assumes provider abstraction (Section 9) and prompt management (Section 10) exist. The brain layer (Section 14) is optional and enhances the context builder pipeline when enabled.

## File Structure (generated per app)

```
backend/app/
  lib/ai/
    agents/
      __init__.py           -- AGENT_REGISTRY dict + get_agent()
      base_agent.py         -- BaseAgent abstract class (invoke, stream, build_context, fallback, job methods)
      {agent_slug}.py       -- One file per declared agent (extends BaseAgent or ConversationalAgent/BatchAgent)
    providers/              -- AI provider abstraction (Section 9)
    sanitize.py             -- Input sanitization (Section 11b)
    validate.py             -- Output validation (Section 11b)
    rate_limit.py           -- Rate limiting (Section 11b)
  routers/
    ai_conversations.py     -- Chat endpoints (conversational/hybrid only)
    ai_agents.py            -- Batch agent trigger endpoints
  services/
    conversation_service.py -- Conversation CRUD + message storage
    job_service.py          -- Job lifecycle (DI03 pattern)
  models/
    conversation.py         -- conversations + conversation_messages tables
    job_status.py           -- Job status table (DI03)

frontend/
  components/
    chat-panel.tsx           -- Full chat interface (conversational/hybrid only)
    chat-message.tsx         -- Individual message with markdown rendering
    chat-input.tsx           -- Auto-resizing textarea with send button
    conversation-sidebar.tsx -- Conversation list with search
  app/(auth)/
    ai/chat/page.tsx         -- Dedicated chat page (if chat_layout = "dedicated" or "both")
```
