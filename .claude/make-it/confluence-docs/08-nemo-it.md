# /nemo-it — Scan your app for security & AI-safety problems

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/nemo-it` is a **security auditor** for your app. It scans your project against industry security standards (the OWASP Testing Guide) and, if your app uses AI, against **NeMo Guardrails** AI-safety tests. It produces a clear report of what it found — in plain language — but it **never changes your code.**

> **In one sentence:** A thorough, non-destructive security check-up that tells you what's wrong (but doesn't touch anything).

---

## What is it used for?

Producing a **security attestation report** that covers:
- **OWASP** web-security checks (the standard list of common vulnerabilities).
- **Dependency scanning** (are the building blocks your app relies on safe and up to date?).
- **Static analysis** (problems visible in the code itself).
- **AI safety** (if your app uses AI): tests for prompt injection, jailbreaks, toxic/biased output, staying on-topic, leaking private info, and making things up.

---

## Why do you need it?

Security problems are invisible until they're exploited. `/nemo-it` finds them *first* and explains each in **business-risk terms** — "this means an attacker could…" — so you understand what actually matters, not just a wall of alerts. It's essential before putting anything live, and useful for compliance and stakeholder confidence.

Because it **only reports and never fixes or modifies** anything, it's completely safe to run any time.

---

## How it helps you vibe code

You don't need security expertise. `/nemo-it` translates deep technical findings into language any stakeholder — developer, manager, or executive — can act on, and it ranks findings by severity so you know what to tackle first. When you're ready to actually fix things, its companion [`/fix-it`](09-fix-it.md) does that.

---

## How to use it

From inside your project, type:

```
/nemo-it                # run everything (recommended)
/nemo-it guardrails     # AI-safety tests only
/nemo-it owasp          # OWASP web-security checks only
/nemo-it deps           # dependency/container scanning only
/nemo-it sast           # static code analysis only
```

Optional output formats: add `--format json` or `--format junit`. A Markdown report is always produced.

**The six phases:** Preflight → Static Analysis → Dynamic Analysis → AI Safety Testing (if AI) → Analysis & Reporting → Attestation Generation.

---

## When to use it

- ✅ Before you ship (especially anything customer-facing).
- ✅ On any app — it's completely separate from `/make-it` and works on *any* project.
- ✅ For periodic security check-ups and compliance evidence.

---

## Important behavior

- **It reports only.** It does not fix, patch, or modify your app.
- **It's non-destructive.** No attacks that could damage data or take your app down.
- To act on the findings, use [`/fix-it`](09-fix-it.md).

---

## Which expert does the AI become?

For a security scan, the AI works as a **security engineer**, not a generalist — automatically, no prompt. It thinks like an attacker (where could someone break in?) and holds the report to a professional standard, rather than skimming a checklist. If your app handles sensitive data like payments or personal information, this mindset kicks in even harder. (Set behind the scenes from your app's details — see the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job).)

---

## Related skills

- [`/fix-it`](09-fix-it.md) — automatically fixes the findings `/nemo-it` reports.
- [`/ship-it`](06-ship-it.md) — runs security checks as part of going live.
