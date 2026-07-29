# /demo-it — Manage demo accounts for prospects

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/demo-it` manages the full life of **demo accounts** used to show your product to prospective customers. It creates a customized demo instance (with the prospect's branding, login, and realistic sample data), tracks it, and cleans it up automatically when it expires.

> **In one sentence:** Spin up a polished, personalized demo for a sales prospect — and tidy it up later — all by conversation.

> ℹ️ **Note:** `/demo-it` is a **specialized, customizable skill.** The version in this framework is tailored to a specific product and audience (a legal-document AI platform). The concepts below apply to any product; the exact branding, integrations, and wording are configured per organization.

---

## What is it used for?

Sales and onboarding teams use it to:
- **Create** a new demo account for a prospect, optionally pre-filled with lifelike sample data so it looks "lived-in."
- **List** all active demos.
- **Check the status/health** of a specific demo.
- **Extend** a demo's expiry.
- **Tear down** (remove) a demo when it's no longer needed.

---

## Why do you need it?

Great demos win deals, but setting them up manually is fiddly and error-prone — branding, logins, sample data, and cleanup all have to be right. `/demo-it` makes a **non-technical person** able to stand up a professional demo in minutes and never worry about leftover demos piling up (they auto-expire, typically after 30 days).

---

## How it helps you vibe code

You don't touch any infrastructure. You answer plain questions — *"What's the firm's name?"*, *"Who's the main contact?"*, *"Should it be pre-filled with sample data or start fresh?"* — and it does all the setup. It never shows raw output; it guides you conversationally.

---

## How to use it

Type the command with a mode:

```
/demo-it new                 # create a new demo (or: /demo-it {firm name})
/demo-it list                # show all active demos
/demo-it status {firm}       # check one demo's health
/demo-it extend {firm}       # extend expiry by 30 days
/demo-it teardown {firm}     # remove a demo
```

Typing `/demo-it` with no mode asks whether you want to set up a new demo or check an existing one.

---

## When to use it

- ✅ You need a tailored demo for a specific prospect.
- ✅ You're managing several live demos and need to see, extend, or remove them.

**When *not* to use it:**
- ❌ You just want to explore your *own* app locally → [`/try-it`](04-try-it.md).

---

## Related skills

- [`/try-it`](04-try-it.md) — explore your own app during development.
- [`/ship-it`](06-ship-it.md) — deploy the real product behind these demos.
