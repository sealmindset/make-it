# /resume-it — Continue work on an existing app

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/resume-it` picks up where you (or [`/make-it`](01-make-it.md)) left off on an app you already have. It figures out the state of your project on its own, then shows you a short list of things you could do next and helps you do them — conversationally.

> **In one sentence:** Come back to your app and keep improving it, with a co-pilot that already knows where things stand.

---

## What is it used for?

Ongoing work on an existing application:
- **Adding new features** ("add a way for users to export their data")
- **Fixing bugs** ("the login button doesn't work on mobile")
- **Testing** (it automates tests for you)
- **Getting it ready to ship**

---

## Why do you need it?

Because software is never "done." You'll always come back to change something. `/resume-it` removes the hardest part of returning to a project — **remembering where you were and what's safe to touch.** It reads your project automatically, so you don't have to re-explain anything.

---

## How it helps you vibe code

It's your **ongoing co-pilot**. You say what you want changed in plain language; it plans the change, makes it, and **automatically tests it** so nothing breaks. Test failures are translated into plain English — no scary error screens.

---

## How to use it

From inside your project folder, type:

```
/resume-it
```

It will:
1. **Discover context** — check for a handoff note from [`/clear-it`](12-clear-it.md), read your project, and figure out what exists.
2. **Present next steps** — offer you a short menu of sensible options.
3. **Do the work** — one thing at a time, testing as it goes.

Just pick what you want to work on and talk it through.

---

## When to use it

- ✅ You have an app built by `/make-it` (or otherwise) and want to keep working on it.
- ✅ You're returning after a break, a `/clear-it` checkpoint, or a `/wrap-it` shutdown.

**When *not* to use it:**
- ❌ You have no app yet → [`/make-it`](01-make-it.md).
- ❌ Your app is missing enterprise foundations (logins, permissions, security) → [`/retrofit-it`](03-retrofit-it.md).

---

## Related skills

- [`/make-it`](01-make-it.md) — where most `/resume-it` projects came from.
- [`/clear-it`](12-clear-it.md) — leaves the handoff note `/resume-it` reads first.
- [`/try-it`](04-try-it.md) — verify changes still work.
- [`/debug-it`](10-debug-it.md) — when a bug needs deeper investigation.
- [`/wrap-it`](13-wrap-it.md) — close up when you're done.
