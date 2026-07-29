# /clear-it — Checkpoint your session, then reset cleanly

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/clear-it` writes a short handoff note (`handoff.md`) that captures **everything important about where you are right now**, so you can safely reset the conversation and continue fresh without losing the thread.

> **In one sentence:** Save a smart checkpoint of your session so Claude can start clean and stay sharp.

---

## What is it used for?

Fighting **"context rot."** During long sessions, the AI accumulates dead ends, messy detours, and wrong assumptions — and starts repeating the same mistakes. `/clear-it` captures what actually matters, then you clear the conversation and pick up cleanly.

The handoff note has exactly six sections:
1. **Goal** — what you're ultimately trying to accomplish.
2. **Current State** — where things stand (working? broken? half-done?).
3. **Active Files** — what's being worked on and why.
4. **Changes Made** — what changed this session (and whether it's saved).
5. **Failed Approaches** — dead ends and wrong assumptions, **with why they failed** — so they're never retried.
6. **Next Steps** — the concrete next actions, in order.

---

## Why do you need it?

The most valuable knowledge in a session — *which ideas were already tried and disproven* — exists **only in the live conversation.** It's not saved anywhere on disk. If you just clear the conversation, that hard-won knowledge is gone and you'll repeat the same dead ends. `/clear-it` preserves it first.

Section 5 (**Failed Approaches**) is the whole reason the skill exists: "Tried X, failed" is useless; "Tried X assuming Y; failed because Z — Y is false, don't retry" saves the next session an hour.

---

## How it helps you vibe code

Long AI sessions get confused and start looping. A clean reset makes the AI sharp again — but only if the important context survives. `/clear-it` gives you the best of both: a fresh, focused assistant *and* continuity.

---

## How to use it

When a session is getting long or tangled — or before you step away — type:

```
/clear-it
```

It writes `handoff.md`, then you run the normal `/clear` command to reset. The next session (or [`/resume-it`](02-resume-it.md)) reads `handoff.md` and continues right where you left off.

---

## When to use it

- ✅ Mid-session, when the AI seems confused or is repeating mistakes.
- ✅ The context is getting very long.
- ✅ Before stepping away for a while.

**How it differs from [`/wrap-it`](13-wrap-it.md):** `/clear-it` is a *lightweight* checkpoint — it does **not** stop your app, update to-do lists, or save code to git. `/wrap-it` is the full end-of-day shutdown. Also, `/clear-it` works in **any** project, not just `/make-it` apps.

---

## Related skills

- [`/resume-it`](02-resume-it.md) — reads the handoff note first and continues from it.
- [`/wrap-it`](13-wrap-it.md) — the heavier, end-of-session shutdown.
