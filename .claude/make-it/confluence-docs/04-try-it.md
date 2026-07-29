# /try-it — See your app working and explore it

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/try-it` launches your app, quickly confirms everything still works, takes screenshots, and guides you through exploring it in your browser. No technical setup — just watch it come to life, then click around.

> **In one sentence:** Press play on your app and take it for a spin.

---

## What is it used for?

Seeing and using your app as a real, working demo:
- Confirm your idea actually looks and behaves the way you wanted.
- Explore the screens, logins, and features hands-on.
- Double-check that recent changes didn't break anything.

---

## Why do you need it?

Building software is abstract until you can *use* it. `/try-it` turns your project into a running app you can open in a browser — without you ever touching a command line, a container, or a log file. It handles the startup and does a quick automated smoke test so you walk into something that already works.

---

## How it helps you vibe code

It closes the feedback loop. You built with a vibe; now you *feel* the result. Everything technical (starting services, checking health, seeding sample data) is invisible. If it spots a small problem, it quietly fixes it — it won't show you error messages or ask you to run commands.

---

## How to use it

From inside your project, type:

```
/try-it
```

It will:
1. **Start the app** (if it isn't already running).
2. **Run a quick smoke test** to confirm it works.
3. **Take screenshots** and **guide you** through exploring it.

`/try-it` also runs **automatically at the end of [`/make-it`](01-make-it.md)** and can be run again after [`/resume-it`](02-resume-it.md) changes.

---

## When to use it

- ✅ Right after building with `/make-it` (happens automatically).
- ✅ Any time you want to open and explore your app.
- ✅ After making changes, to confirm nothing broke.

---

## Good to know

- If `/make-it` did its job, `/try-it` finds **zero issues** — it has a fix cycle as a safety net, but rarely needs it.
- It never asks you to fix technical things yourself.

---

## Related skills

- [`/make-it`](01-make-it.md) / [`/resume-it`](02-resume-it.md) — build or change the app first.
- [`/demo-it`](05-demo-it.md) — for polished, shareable demos aimed at prospects.
- [`/ship-it`](06-ship-it.md) — when you're happy and ready to go live.
