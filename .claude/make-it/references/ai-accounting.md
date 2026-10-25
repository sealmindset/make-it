# AI Accounting Reference

Every AI call is counted, priced, named and set against what it produced, so the project can say
what its AI costs, what it saves, and whether it uses cheaper models where they are good enough.

Runs when `ai_features.needed = true`. Used by Prompt #10g (retrofit and new build),
`/retrofit-it` Phase F3, the `/resume-it` catch-up, and `/make-it` Build step 9f. Checks:
`build-standards.md` AC01-AC16 and ACV01-ACV03.

It adds seven admin surfaces: **AI Instructions** (prompt management, AI08), **AI Agents**,
**Control Plane**, **AI Monitor**, **AI Spend**, **Infra Spend**, **Spend Statements**.

---

## 1. Words used here

| Word | Meaning |
|------|---------|
| **Call** | One request to an AI model (each retry and each escalation is its own call). |
| **Task** | One unit of work the AI helps finish: a document filed, a ticket triaged, a reply drafted. A task can take many calls. Named by `task_ref` = `<kind>:<id>` (e.g. `ticket:812`). |
| **Agent** | A named AI capability with a slug in the agent registry (AI17). An inline call in a route is an agent too. |
| **Tier** | `heavy`, `standard` or `light` -- the model class a call asks for (AI17 `model_tier`). The Control Plane says which model each tier means. |
| **Cost center** | What a dollar is charged to: agent, model, tier, feature, user -- and tenant, only when the app is multi-tenant. |
| **Outcome** | What people did with a task's AI result: accepted, corrected, redone, auto, or unsure (section 7). |

## 2. Rules (each one closes a hole a real project fell into)

1. **No unnamed call.** The agent slug is a required argument of the one metering wrapper, never
   read from ambient context that a code path can forget to set. A CI check fails on any call
   site that skips the wrapper or names an agent that isn't registered, inline calls included.
2. **No silent $0.** A model with no price row is recorded with `cost_usd` empty and
   `priced = false`, never as zero, and every spend page shows the count of unpriced calls. A real
   zero (a local model) is a priced row at 0. Adding a price re-prices the earlier unpriced rows,
   cache tokens included.
3. **No hidden cache.** Cached and cache-write tokens are stored apart from plain input, priced at
   their own rates, and the cache-hit rate is shown on AI Spend.
4. **Fallback never steps up quietly.** A fallback call is marked `fallback = true` with its real
   model and cost. A fallback that costs more than the primary is flagged on AI Spend.
5. **No prompt text in the ledger.** The ledger holds counts, ids and money, never prompt or
   response text. A replay rebuilds its input from the task's source record (section 6). The only
   model output kept is a shadow or replay result in `ai_comparisons`, deleted after
   `AI_COMPARISON_RETENTION_DAYS`.
6. **Recording never breaks the app, and is never silent.** A failed ledger write is logged and
   counted (`ai_ledger_write_failures`), and the count is shown on AI Spend.
7. **No hard-coded hosts, names or prices in code.** Tenants, hosts, the statement issuer and
   prices come from data or settings.
8. **Editing a live prompt never takes it dark.** An edit makes a new draft version; the published
   version keeps serving until the new one is tested and published (AI08, AI10).
9. **Every field an admin can edit is read at runtime**, or it isn't shown.
10. **Read the deployed config, not the docs.** The model behind a tier is what the running app
    resolves (env, settings, Control Plane), not what a README says.

## 3. Data

Table names are snake_case; adapt the column types to the stack. All money is a decimal with 6
places (USD), never a float.

**`ai_usage_events`** -- the ledger, one row per call.
`id`, `occurred_at`, `agent_slug` (required), `feature`, `user_id` (empty for system jobs),
`tenant_id` (only when multi-tenant), `task_ref`, `provider`, `model` (the exact id the provider
returned), `tier` (empty only for a pinned model), `escalated_from` (tier or empty), `fallback`
(bool), `attempt` (1 = first try), `mode` (`live` | `shadow` | `replay`), `prompt_version_id`,
`input_tokens` (uncached), `cached_input_tokens`, `cache_write_tokens`, `output_tokens`,
`cost_usd` (empty when unpriced), `priced` (bool), `price_id`, `latency_ms`,
`status` (`ok` | `error` | `refused_budget` | `aborted`).
Index: (`occurred_at`), (`agent_slug`, `occurred_at`), (`task_ref`), and (`tenant_id`,
`occurred_at`) when multi-tenant.

**`model_prices`** -- `provider`, `model`, `effective_from`, `input_per_mtok`, `output_per_mtok`,
`cache_read_per_mtok`, `cache_write_per_mtok`, `billing` (`per_token` | `subscription` | `local`),
`source` (URL or note), `entered_by`. Unique (`provider`, `model`, `effective_from`).

**`ai_outcomes`** -- one row per task: `task_ref`, `agent_slug`, `feature`, `tenant_id` (when
multi-tenant), `verdict`, `verdict_source` (`person` | `system`), `decided_by`, `decided_at`,
`confidence` (the model's own, if the agent reports one), `created_at`. Unique (`task_ref`,
`agent_slug`).

**`value_baselines`** -- optional, entered by an admin: `agent_slug` or `feature`,
`minutes_per_task` (what a person would spend doing the task by hand),
`minutes_per_correction` (empty = assume half of `minutes_per_task`, shown as assumed),
`hourly_rate`, `effective_from`, `entered_by`.

**`agent_controls`** -- `agent_slug` (PK), `mode` (`on` | `off` | `shadow`), `tier`,
`escalate` (bool; seeded off in a retrofit so nothing costs more on day one, on in a new build),
`updated_by`, `updated_at`.
**`tier_models`** -- `tier` (PK), `model`, `fallback_model`, `updated_by`, `updated_at`.
**`budget_caps`** -- `scope` (`all` | `agent:<slug>` | `tenant:<id>`), `period` (`day` | `month`),
`cap_usd`, `updated_by`, `updated_at`. Unique (`scope`, `period`).
**`provider_breakers`** -- `provider` (PK), `state` (`closed` | `open` | `half_open`), `opened_at`,
`reason`, `retry_at`, `forced_by`.
**`control_audit_log`** -- `id`, `at`, `actor`, `surface` (`agent` | `tier` | `budget` | `breaker`
| `prompt` | `price` | `baseline` | `vendor` | `statement`), `target`, `before` (JSON), `after` (JSON), `reason`.
Insert-only.

**`ai_comparisons`** -- shadow and replay results only: `id`, `run_id`, `agent_slug`,
`task_ref`, `mode` (`shadow` | `replay`), `tier`, `model`, `output` (the model's answer),
`agreed` (bool or empty until judged), `created_at`. A daily job deletes rows older than
`AI_COMPARISON_RETENTION_DAYS`; summaries (counts, agreement, cost) go to `control_audit_log`.

**`infra_cost_daily`** -- `day`, `source` (`aws` | `azure` | `gcp`), `service`, `cost_center` (the
tag value, or `shared` when untagged), `amount_usd`, `collected_at`. Unique (`day`, `source`,
`service`, `cost_center`).
**`vendor_spend`** -- monthly manual lines: `month`, `vendor`, `amount_usd`, `allocation`
(`shared` | `cost_center:<name>` | `excluded`), `note`, `entered_by`.

**`spend_statements`** -- `number` (unique), `period_kind` (`30d` | `90d` | `month` | `lifetime`),
`period_from`, `period_to`, `scope` (`all` or `tenant:<id>`), `total_usd`, `payload` (JSON, the
frozen statement), `replaces` (number or empty), `issued_by`, `issued_at`. No update or delete
route; a correction is a new statement that names the one it replaces.
**`statement_counters`** -- `name` (PK), `next_value`. Seeded with one row (`next_value = 1`);
it never resets, so the year in a statement number is the issue year only.

The AI01c in-memory `UsageStats` stays as the running process view; the ledger is the record.
AI22's per-job `cost_usd` is a sum of the job's ledger rows, never a separate estimate.

## 4. Metering -- the one wrapper

Every AI call in the app goes through one function in the provider layer (AI01), for example
`complete(agent=..., feature=..., task_ref=..., tier=..., messages=...)`. No call site calls an
SDK or a provider URL directly.

The wrapper, in order:
1. Looks up the agent's control row. `off` → returns the agent's fallback (AI21) or a plain "this
   AI step is turned off" result, and makes no call. `shadow` → runs the call with
   `mode = shadow`; the caller gets the fallback or "no AI result" and the shadow output goes to
   `ai_comparisons` only, never acted on.
2. Resolves the model: a pinned model (with a code comment saying why), else `tier_models[tier]`.
3. Checks the budget (section 8). Over a cap → records `status = refused_budget` (cost 0) and
   returns the fallback; no tokens are spent.
4. Checks the provider breaker; open → goes straight to the fallback model or provider.
5. Calls the provider, then maps its usage fields to the four token columns:

| Provider | input_tokens | cached_input_tokens | cache_write_tokens | output_tokens |
|----------|-------------|---------------------|--------------------|---------------|
| Anthropic API | `usage.input_tokens` | `usage.cache_read_input_tokens` | `usage.cache_creation_input_tokens` | `usage.output_tokens` |
| AWS Bedrock (Converse) | `usage.inputTokens` | `usage.cacheReadInputTokens` | `usage.cacheWriteInputTokens` | `usage.outputTokens` |
| OpenAI / Azure OpenAI | `usage.prompt_tokens` minus cached | `usage.prompt_tokens_details.cached_tokens` | 0 | `usage.completion_tokens` |
| Ollama / local | `prompt_eval_count` | 0 | 0 | `eval_count` |
| Claude Code subscription (claude_agent) | from the SDK result's usage | same | same | same |

   Streaming: Anthropic sends input and cache counts in `message_start` and the running output
   count in each `message_delta` (keep the last); OpenAI sends usage in the final chunk when
   `stream_options.include_usage` is set. A stream cut short records what is known, `status = aborted`.
6. Prices the call (section 5) and writes the ledger row without blocking the caller. A write that
   fails is logged and counted (rule 6).
7. If the answer is weak and escalation is on, makes one more call a tier up (section 6).

## 5. Prices

- Seed `model_prices` at build time from the provider's current public price page, with that URL
  in `source` and today's date in `effective_from`. Tell the admin in one line that the prices
  were copied on that date and where to check them.
- Lookup: the newest row with `effective_from <= occurred_at` for the exact model id, then for the
  id with a trailing date suffix removed (`-20250514`, `-2025-05-14`). None → unpriced (rule 2).
- Cost = (`input_tokens` × `input_per_mtok` + `cached_input_tokens` × `cache_read_per_mtok` +
  `cache_write_tokens` × `cache_write_per_mtok` + `output_tokens` × `output_per_mtok`) ÷ 1,000,000.
  Rates are stored per model, never derived from fixed multipliers.
- `billing = local` (Ollama): priced at 0. `billing = subscription` (claude_agent): priced at 0
  per call, tokens still counted, and the plan's monthly fee goes in as a vendor line. AI Spend
  says "on a subscription: tokens counted, dollars come from the plan".
- Adding or changing a price row is audited and re-prices the rows it covers that are still
  unpriced. It never rewrites a priced row.

## 6. The model ladder -- assess, route, prove

**Assess (read-only, always first).** Find every call site (section 12, step 1) and draft the
ladder report; it is shown in the plan and written to `.make-it/ai-ladder.md` (committed) when
building starts:

```
Verdict: no ladder | fixed per agent | routed per call
| Call site (file:line) | Agent | Model today (as deployed) | Calls/month | Cost/month | Suggested tier | Why | Est. saving/month | Proof needed |
```

- **No ladder:** every call uses one model. **Fixed per agent:** tiers are chosen in code, one
  per agent. **Routed per call:** the tier is picked per call, with escalation.
- Calls and cost come from the ledger when one exists, else from an estimate marked "estimate".
- Suggested tier, by the work the call does:
  - **light** -- picking from a fixed set of labels, pulling named fields from short text,
    routing, yes/no checks, short rewrites, parsing a short note into a form. Short output that a
    schema can check.
  - **standard** -- summaries, drafts, extracting many fields from long documents, answering from
    retrieved text, tool use with a few steps.
  - **heavy** -- multi-step reasoning or planning, code, long agent loops, safety or adversarial
    checks, and any judgment where a miss is costly and no person reviews it.
- Then weigh: a person reviews every output → one tier lower is usually safe. The output acts with
  no review and a miss is costly → keep it heavy. High volume on a light job → the biggest saving.
- "Proof needed" = the replay sample size (below), or "none" when the suggestion keeps or raises
  the tier.

**Route.** Every call names a tier (or a pinned model with a reason); the Control Plane maps
tier → model, and the ledger records `tier`. **Escalation:** when an answer is weak -- it fails
schema validation, the output validator (AI03) flags it, or the agent's own confidence is below
`AI_ESCALATE_BELOW` -- the wrapper makes **one** call a tier up (light → standard → heavy), records
`escalated_from`, and stops there: never a loop, never above heavy. The escalation rate per agent
is shown on AI Monitor; a rate above 30% means the agent's tier is too low.

**Prove before stepping down.** The Control Plane will not lower an agent's tier until a replay
has passed in the last 30 days:
1. Pick up to 50 recent tasks of that agent with a person's verdict (`accepted` or `corrected`;
   the corrected result is the answer key). Fewer than 20 → say "not enough history to prove
   this yet" and offer shadow mode at the lower tier for 14 days instead.
2. Rebuild each input from the task's source record through the agent's own context builder
   (AI19) and run it at the lower tier with `mode = replay`: no writes, no messages, tools that
   act on the world replaced by stubs. An agent that can't run without side effects is marked
   "can't replay" in the ladder report and is proved by shadow mode only.
3. Compare: structured output field by field; free text judged "same meaning or not" by a
   heavy-tier check, plus 10 shown to the admin side by side. Outputs go to `ai_comparisons`.
4. Pass = agreement at least the current tier's own accepted-as-is rate minus 2 points, and no
   miss on a field marked critical. The result (agreement, sample size, cost, `run_id`) goes in
   `control_audit_log`; the admin then makes the switch.
5. An admin may switch without a pass only by typing a reason; the reason is audited and shown
   on the AI Agents page next to that agent.

## 7. Outcomes and ROI

**Where verdicts come from: real actions, never guesses.** Hook the app's existing actions on AI
results:

| Verdict | When |
|---------|------|
| `accepted` | A person approves or uses the AI result unchanged. |
| `corrected` | A person changes the AI result before or after saving it, within `AI_CORRECTION_WINDOW_DAYS`. |
| `redone` | A person rejects it, regenerates it, or does the task by hand instead. |
| `auto` | It went through with no person, and nobody changed it within the correction window. |
| `unsure` | No signal yet. Shown as a count, left out of the rates. |

A person's verdict always beats a system one. Where the app has no approve step, the AI-written
fields are compared with the saved record at the end of the correction window: unchanged →
`auto`, changed → `corrected`.

**Always shown (no setup):**
- **Cost per completed task** = AI cost of all live calls for that agent in the period (retries,
  escalations and redone tasks included) ÷ tasks completed (`accepted` + `corrected` + `auto`). A
  redone task costs money and completes nothing, so it raises the number. Shown with the median
  and 90th percentile per task. Shadow and replay spend is shown apart, as the cost of proving.
- **Accepted / corrected / redone / auto rates** over decided tasks.
- **Done without a person** = the `auto` count and its share of completed tasks.

**Dollar ROI (only when an admin has entered a baseline):**
- Minutes saved = `accepted` and `auto` tasks × `minutes_per_task` + `corrected` tasks ×
  (`minutes_per_task` − `minutes_per_correction`). A `redone` task saves nothing.
- Value = minutes saved ÷ 60 × `hourly_rate`.
- Cost = AI cost + infra cost for the same period and scope.
- **ROI = (value − cost) ÷ cost**, shown as a percent and in plain words: "for every $1 spent,
  $X came back".
- App-wide ROI includes infra. Per-agent ROI uses AI cost only (infra isn't split by agent) and is
  labelled "AI cost only". Every assumed value is labelled "assumed" where it is used.

## 8. Control Plane (admin-only)

One page, permission `ai_accounting.manage`. Every change writes `control_audit_log` (who, when,
before, after, reason) and takes effect within 60 seconds; the page says so.

- **Agents:** each one on, off or shadow; its tier; escalation on or off.
- **Tier models:** the model and fallback model behind each tier. A model with no price row is
  refused (rule 2). When `AI_ALLOWED_MODELS` is set, a model outside it is refused too.
- **Budget caps:** for all AI, one agent, or one tenant (multi-tenant only), per day or month. Before each call the
  wrapper adds the period's spend so far to this call's worst case (input tokens counted or
  estimated at 4 characters per token, times the input price, plus `max_tokens` times the output
  price) and refuses the call if that passes any cap that applies. One notice at 80% and one at
  100% per cap per period, to the admins. A budget check that errors lets the call through, is
  logged, and is counted on this page: a cap guards cost, not security. Summing the ledger on
  each check is fine up to about 10 calls a second; past that, keep a running total per cap.
- **Breaker:** each provider's state. It opens after `AI_BREAKER_ERRORS` errors in
  `AI_BREAKER_WINDOW_SECONDS` and sends calls to the fallback until `retry_at`; then one trial call
  decides (half-open). An admin can force it open or closed.
- **Prompt rollback:** per agent, "Go back to the previous version" restores the last published
  prompt version (AI08's version timeline) in one click, audited here and in `prompt_audit_log`.
- Turning an agent off and raising a cap ask for a second confirmation and a reason. Every change
  has a "Put it back" action on its audit row.

## 9. Infra Spend -- the cloud bill

One adapter per source with the same shape: `collect(day_from, day_to) → rows` of
(`day`, `service`, `cost_center`, `amount_usd`), upserted into `infra_cost_daily`.
`INFRA_COST_SOURCE` = `aws` | `azure` | `gcp` | `mock` | `none` (`mock` in local dev, per the
mock-services rule).

- **AWS (built):** Cost Explorer `GetCostAndUsage`, `Granularity = DAILY`, metric
  `UnblendedCost`, grouped by `SERVICE` and `TAG:<INFRA_COST_TAG_KEY>`; follow `NextPageToken`.
  Runs daily; each run re-collects the last `INFRA_COST_RECOLLECT_DAYS` (3) because the bill
  keeps settling; the first run backfills `INFRA_COST_BACKFILL_DAYS` (90). An empty tag value
  is `shared`. Needs only `ce:GetCostAndUsage` on a read-only role. Two things to tell DevOps: the
  tag must be activated as a cost-allocation tag in the Billing console (it can take a day to
  appear; ask for a backfill there to cover up to 12 earlier months), and Cost Explorer charges
  $0.01 per API request (a few requests a day).
- **Azure, GCP (stubs):** implement the same `collect` shape and return "not connected yet".
  Azure's path is the Cost Management Query API grouped by `ServiceName` and the tag; GCP's is a
  query over the billing export table in BigQuery. Building one is a new change with its own
  checks.
- **A source that isn't connected shows "not connected", never $0.**
- **Manual lines:** `vendor_spend` holds monthly bills with no API (SaaS tools, a subscription
  plan), each marked shared, for one cost center, or excluded.
- Credentials come from the environment or a secret manager, never from the database.
- **Parts add up:** the page shows cost centers + shared = the collected total; a gap of more than
  1 cent is a warning on the page.

## 10. Spend Statements -- internal only

- Periods: last 30 days, last 90 days, a calendar month, lifetime. Scope: the whole app, or one
  tenant when multi-tenant.
- Contents: AI by agent × model (calls, tokens, cost); infra by service and cost center; vendor
  lines; the total; outcomes and ROI (section 7, when a baseline exists); and actual against a
  budget cap or a set price, when one is set.
- **Frozen:** the whole statement is computed once and stored in `payload`; viewing it never
  recomputes it.
- **Gapless numbers:** the number comes from `statement_counters`, taken and incremented in the
  same database transaction as the insert (`UPDATE ... SET next_value = next_value + 1 RETURNING`,
  or a row lock). A failed insert rolls the number back. Never "read the last number and add 1".
  Format `<STATEMENT_NUMBER_PREFIX>-<YYYY>-<NNNN>`.
- Printing: a print stylesheet; the admin uses the browser's Print → Save as PDF.
- **Not an invoice:** no amount due, no payment details, never sent outside the team. The header
  says "Internal cost statement -- not an invoice".

## 11. The seven surfaces

Admin-only by default: `ai_accounting.view` for the pages, `ai_accounting.manage` for the
Control Plane, prices, baselines, vendor lines and issuing statements. Both go to Super Admin and
Admin in the seed; the permission matrix can grant view to others. Sidebar group "AI & Spend".
Plain labels, no codes, no enum values on screen.

| Page | Route | Shows |
|------|-------|-------|
| **AI Instructions** | `/admin/prompts` | AI08 as built. Plus rule 8: editing a live prompt never takes it dark. |
| **AI Agents** | `/admin/ai-agents` | Every agent: what it does in plain words, mode, tier, model now, calls and cost (30 days), accepted rate, last change, any unproven step-down reason. Links to its prompt and its controls. |
| **Control Plane** | `/admin/ai-control` | Section 8. |
| **AI Monitor** | `/admin/ai-monitor` | Per agent per week, 12 weeks: verdict rates, cost per 1,000 tasks, cost per completed task, p50/p95 latency, error rate, escalation rate. Markers where the model or the published prompt changed. |
| **AI Spend** | `/admin/ai-spend` | Period picker (month to date first). Totals; by agent, agent × model, tier, feature, top 25 users, tenant (when multi-tenant), day. Cache-hit rate = cached ÷ (cached + cache-write + uncached input). Warnings: unpriced calls, unnamed calls, ledger write failures, fallbacks that cost more. Shadow and replay spend apart. Calls with no task = overhead. |
| **Infra Spend** | `/admin/infra-spend` | Section 9: by day, service and cost center; vendor lines; each source's status. |
| **Spend Statements** | `/admin/spend-statements` | Issue (period + scope), list, view, print. |

Every page loads within the app's normal page budget for a year of rows: roll up with database
aggregates, never by loading rows into the app.

## 12. Retrofit order (an existing app)

Never rebuild a surface the app already has: wrap it or extend it, and keep its data.

1. **Find every call site (read-only).** SDK imports (`anthropic`, `openai`, `@anthropic-ai/sdk`,
   `@aws-sdk/client-bedrock-runtime`, `boto3` `bedrock-runtime`, `google-genai`, `ollama`,
   `langchain`, `llama_index`); provider URLs (`api.anthropic.com`, `api.openai.com`,
   `bedrock-runtime`, `openai.azure.com`, `generativelanguage.googleapis.com`, `:11434`); the app's
   own AI wrapper; routes, scheduled jobs and scripts that call any of these. For each: file:line,
   agent (existing name or a proposed slug), what it does, and where its model comes from (a
   literal, env, or settings, with the deployed value).
2. **Find what accounting exists.** Usage or cost tables, pricing code, spend pages, budget checks,
   billing collectors, approve/reject actions on AI results. Mark each surface none / partial /
   present.
3. **Write the ladder report** (section 6). It is read-only and goes into the plan.
4. **Meter:** no agent registry (AI17)? Create it first from step 1's list (slug, name, type,
   tier as deployed). Then add the ledger, prices and the one wrapper; route every call site
   through it.
5. **Outcomes:** hook the verdicts into the app's own actions (section 7).
6. **Control Plane:** controls, tier models, caps, breaker, rollback, audit.
7. **Infra:** the adapter for the app's cloud, plus manual lines.
8. **Pages and statements.**
9. **The CI check (AC03)** and seed data for local dev (sample calls, outcomes, a day of infra
   rows, one baseline) so no page opens empty.

The pages and statements need an admin permission check. An app with no sign-in or admin gate
gets steps 1-7 and 9 and no pages or statements yet, and the plan says so in plain words.

**New build:** the same pieces built in, in order 4-9; step 1 is the agent registry (AI17)
itself, and the ladder report is written from each agent's planned tier.

## 13. Multi-tenant (only when `multi_tenancy.needed = true`)

- `tenant_id` on the ledger, outcomes and caps; every rollup can filter by it.
- AI cost is direct: each call belongs to its tenant.
- Infra **fair share:** a tenant pays its own tagged cost plus shared cost × its weight. Weight =
  the tenant's directly charged cost (its own tagged infra plus its AI) ÷ all tenants' directly
  charged cost; when none has any, split equally. Shared vendor lines split by the same weight.
- **Parts add up:** tenants + unallocated = the total, checked and shown on AI Spend and Infra
  Spend.
- Without multi-tenancy there is no tenant column anywhere.

## 14. Settings (`.env.example`, docker-compose, and app settings when G-series exists)

```
INFRA_COST_SOURCE=mock            # aws | azure | gcp | mock | none
INFRA_COST_TAG_KEY=CostCenter
INFRA_COST_RECOLLECT_DAYS=3
INFRA_COST_BACKFILL_DAYS=90
AI_ESCALATE_BELOW=0.5             # agent-reported confidence that triggers one step up
AI_CORRECTION_WINDOW_DAYS=14
AI_COMPARISON_RETENTION_DAYS=30   # shadow and replay outputs, then deleted
AI_BREAKER_ERRORS=5
AI_BREAKER_WINDOW_SECONDS=60
AI_ALLOWED_MODELS=                # optional, comma-separated
STATEMENT_NUMBER_PREFIX=ST
```

## 15. Stack notes

- **FastAPI + Next.js (scaffold):** the wrapper lives in `backend/app/lib/ai/metering.py`, called
  by `BaseAgent.invoke()`/`stream()` (AI18); tables in a new Alembic migration; routers under
  `/api/admin/ai-*`; pages under `frontend/app/(auth)/admin/`; the daily collector uses the DI07
  scheduled-job pattern.
- **Next.js + Prisma:** the wrapper in `src/lib/ai/metering.ts`; Prisma models plus a migration;
  route handlers under `src/app/api/admin/`.
- **Other stacks:** the same tables, wrapper contract and pages, in the app's own patterns.
- **CLI, library and API-service types:** the ledger, wrapper, prices, ladder report, caps and the
  CI check; spend comes out as a command or API endpoint instead of pages.

## 16. Out of scope

Invoicing and payments; showing costs to end users; per-call prompt or response storage; Azure and
GCP collectors beyond the stub; ready-made scaffold files (each build generates these from this
spec).
