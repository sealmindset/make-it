# /wrap-it — End your work session cleanly

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/wrap-it` closes up shop at the end of a work session. It saves your progress, updates your project's to-do and change logs, and shuts down your running app cleanly — leaving everything ready for next time.

> **In one sentence:** Type it when you're done for the day, and it tidies everything up for you.

---

## What is it used for?

A clean end-of-session shutdown for a `/make-it` app:
- **Save progress** and update project state files.
- **Update your to-do list** and changelog so you know where to resume.
- **Stop all running services** so nothing keeps running in the background.
- Leave the project ready for the next [`/resume-it`](02-resume-it.md).

---

## Why do you need it?

Stopping cleanly matters. If you just close your laptop, your app may keep running, your progress notes go stale, and next time you'll waste time figuring out where you were. `/wrap-it` makes stopping as easy as starting — one command, and everything's in order.

---

## How it helps you vibe code

No need to know how to stop containers, save state, or update logs. You just signal "I'm done," and it handles the housekeeping and confirms what was saved and what to expect next time — briefly and warmly, no jargon.

---

## How to use it

When you're finished working, type:

```
/wrap-it
```

It discovers what's running and what changed, saves and updates everything, shuts the app down, and confirms you're all set.

---

## When to use it

- ✅ At the end of a work session on a `/make-it` app.
- ✅ Whenever you want to safely stop and pick up cleanly later.

**How it differs from [`/clear-it`](12-clear-it.md):** `/wrap-it` is the **full shutdown** (stops the app, updates logs, saves work). `/clear-it` is a **lightweight mid-session checkpoint** that only captures context so you can reset the conversation.

---

## Related skills

- [`/resume-it`](02-resume-it.md) — picks up cleanly next time.
- [`/clear-it`](12-clear-it.md) — the lightweight mid-session alternative.
- [`/git-it`](11-git-it.md) — for deeper control over how your work is saved.
