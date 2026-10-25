# AI Accounting -- design record (v1.45.0)

Why `references/ai-accounting.md`, Prompt #10g and checks AC01-AC16 / ACV01-ACV03 look the way
they do. The spec is the rule; this file is the reasoning and where it came from.

## Goal

Retrofit an existing project with the "AI accounting" one production app (docai) grew by hand:
seven admin surfaces (AI Prompt Management, AI Agents, Control Plane, AI Monitor, AI Spend, Infra
Spend, Spend Statements), with nothing specific to that app's customers. The point is the
metrics: the ROI of AI for a project, from the project's own AI usage, plus a check of whether it
uses cheaper models for work that doesn't need the expensive ones.

## Decisions (Rob, 2026-10-25)

| Question | Decision |
|----------|----------|
| Main path | A retrofit prompt for an existing project (Prompt #10g, MODE = retrofit); new builds use the same prompt. |
| Model ladder | **Assess + route + prove.** Score every call site; record the tier on every call; every agent has a tier with one step up on a weak answer; replay past tasks on the cheaper model before any step down. |
| ROI | **Both.** Always: cost per completed task, accepted / corrected / redone rates, items done without a person. Dollar ROI when an admin enters minutes per task and an hourly rate: (minutes saved × rate − AI cost − infra cost) ÷ cost. |
| Reach | **Both.** `/make-it` builds it into new AI apps; `/retrofit-it` (Phase F3, or `ai-accounting` alone) and the `/resume-it` catch-up add it to existing ones. |
| Split by | **Generic cost centers:** agent, model, tier, feature, user. A tenant column only when the app is multi-tenant, and then fair-share infra. |
| Cloud bill | **Adapters, AWS first.** AWS Cost Explorer built (daily, last 3 days re-collected, split by a cost-allocation tag); Azure and GCP stubs; manual monthly lines for SaaS vendors. |
| Control Plane | **Operator switches, admin-only:** each agent on / off / shadow, the model behind each tier, budget caps that stop spend before the call (all / agent / tenant), the failover breaker, one-click prompt rollback, every change audited. |
| Statements | **Internal statements:** 30 / 90 days, month, lifetime; AI by agent × model, infra, total, ROI, against a budget or price if set; frozen, gapless numbers from a counter row, print to PDF; no invoicing. |

## What the source app taught (each became a rule)

Mapped from docai on 2026-10-25 (paths relative to that repo).

| What happened there | Rule in the spec |
|---------------------|------------------|
| The agent name came from an ambient context (`withMeteringContext`); one subsystem never set it, so most of one tenant's calls showed as "(untagged)". | Rule 1: the agent is a required argument of the wrapper; AC03's CI test covers inline calls too. |
| The drift test scanned only agent classes (`src/lib/agents`), so inline `chat()` calls in routes were invisible to it. | AC03 scans every call site, not one folder. |
| An unknown model was recorded at $0 with `priced:false`; the backfill ignored cache tokens; the fallback model had no seeded price. | Rule 2 (empty, never 0), AC04, and the Control Plane refuses an unpriced model. |
| The cache-hit rate was computed but no page showed it. | Rule 3; AC15 requires it on AI Spend. |
| The fallback retried on a dearer model, unrecorded as a step up. | Rule 4; `fallback` column; dearer fallbacks flagged. |
| Saving an edit set the live prompt to `draft`, so the app fell back to the coded default until it was republished. | Rule 8; AC15 verifies the published version keeps serving. |
| Prompt rows had `model` / `temperature` / `maxTokens` fields never read at runtime. | Rule 9. |
| Docs said the top tier ran the top model; the deployed env mapped it to the mid model. | Rule 10: the ladder report reads the deployed value. |
| No tier column on spend rows, and two tiers mapped to one model, so tier spend couldn't be recovered. | `tier` on every ledger row (AC05). |
| "Control Plane" was a prompt-hosting service that controlled no switches; the breaker lived in one subsystem only. | Section 8: one admin page that holds every switch, with a shared breaker. |
| The statement number was "last one + 1"; two at once hit the unique key and the second failed. | Section 10: counter row in the same transaction (AC14). |
| Tenant hosts, the issuer and Fargate list prices were hard-coded in several places. | Rule 7. |
| A per-record cost was a ratio of totals, described as a median. | Section 7: the ratio is named as one, with the real median and p90 beside it. |
| No time-saved metric existed anywhere. | Section 7: dollar ROI from admin-entered baselines, assumptions labelled. |
| Model comparison existed only as per-question calibration in one subsystem. | Section 6: replay proof per agent before a step down. |

## Left out on purpose (specific to that app)

- "As if dedicated" infra and the subscription-minus-cost margin per customer: pricing, not
  accounting. Statements compare against a set price only when one is set.
- Per-customer host fan-out with signed tickets: an artifact of one database per customer. The
  spec assumes one app database; a multi-instance app adds its own fan-out.
- Allocating compute by resource name and by CloudWatch samples: the spec splits by the
  cost-allocation tag, which every cloud supports.
- The legal-domain safety preamble and transcription-minute pricing.
- Invoices (that app's backlog plans them separately).

## Choices made while writing the spec

- **No prompt text in the ledger.** The replay rebuilds inputs from the task's source record, so
  no new store of sensitive text is needed to prove a step down.
- **Unpriced is empty, not zero,** so sums never quietly undercount; pages show the unpriced count.
- **A budget check that errors lets the call through and is counted:** a cap guards cost, not
  security, and failing closed would take the app's AI down with the database.
- **Prove-before-step-down is a gate with a typed-reason override,** because a new app has no
  history to replay; the reason is audited and shown next to the agent.
- **No scaffold files in this release.** Each build generates the tables and pages from the spec
  in the project's own stack; ready-made scaffold modules are a later step.
- **`app-context.json` stays small** (`enabled`, `infra_source`, `infra_tag_key`,
  `ladder_verdict`): multi-tenancy already lives in `multi_tenancy.needed`, and budgets and
  baselines are entered by admins in the app, not at design time.
