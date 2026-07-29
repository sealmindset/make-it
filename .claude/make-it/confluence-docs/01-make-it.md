# /make-it — Build a new app from an idea

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/make-it` takes a first-time builder from a **raw idea** to a **fully working, production-ready application** through a friendly conversation. You describe what you want in plain English; it handles everything technical behind the scenes.

> **In one sentence:** Tell it what you want to build, answer some easy questions, and get a real working app.

---

## What is it used for?

Creating a brand-new application from scratch. For example:
- "A tool where my team can submit and approve expense reports."
- "A website where customers can browse our products and book appointments."
- "An internal dashboard that shows our sales numbers."

It builds the whole thing: the screens people see, the logic behind them, the database, user logins, permissions, and the packaging needed to run it.

---

## Why do you need it?

Because building software normally requires a team and months of specialized work. `/make-it` compresses that into a conversation. You get:

- **Zero coding required.** You never see or write code during the questions.
- **Real, professional foundations.** Logins, user roles/permissions, security, and containerization are built in automatically — not bolted on later.
- **A verified app.** It doesn't just generate code and walk away; it tests the app and fixes problems before handing it to you.

---

## How it helps you vibe code

This is the flagship "vibe coding" skill. You supply the vibe — the idea and the goals — and it makes **every technical decision for you**: what programming language, what database, how logins work, how data is protected. You answer plain-language questions like *"Who will use this?"* and *"What should they be able to do?"*, and it maps your answers to professional engineering choices invisibly.

---

## How to use it

In your terminal (or Claude Code), type:

```
/make-it
```

You can also give it a head start:

```
/make-it a tool for tracking customer support tickets
```

Then just **talk to it.** It asks one easy question at a time, celebrates your answers, and summarizes progress so you always know where you are.

**The five phases (all handled for you):**
1. **Preflight** — checks your computer is ready.
2. **Ideation** — understands what you want to build.
3. **Design** — makes all the technical decisions from your answers.
4. **Build** — generates the app and **verifies it actually works**.
5. **Ship** — hands off to [`/ship-it`](06-ship-it.md) when you're ready to go live.

> 💡 **To update the framework itself**, type `/make-it update`.

---

## When to use it

- ✅ You have an idea and **no app yet**.
- ✅ You want something built to professional standards without learning to code.

**When *not* to use it:**
- ❌ You already have an app → use [`/resume-it`](02-resume-it.md) to continue it, or [`/retrofit-it`](03-retrofit-it.md) to upgrade it.

---

## What happens behind the scenes (optional reading)

- It picks a proven **starter template** for common app types and fills in your specifics.
- It runs a **24-point quality check** plus a live test (logins work, every page loads, permissions are enforced) and **auto-fixes** issues (up to 3 rounds) before you ever see the app.
- If your app uses AI, it automatically adds **AI safety controls** and tests them.

---

## Which expert does the AI become?

While building, the AI quietly figures out what kind of specialist your app needs most — based on what you described (payments? personal data? lots of users? heavy AI?) — and **builds and reviews the risky parts in that expert's role**, not as a generalist. You won't be asked anything; it just raises the quality bar where it matters. (See the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job) for how this works across every skill.)

---

## Related skills

- [`/try-it`](04-try-it.md) — see and explore what you just built.
- [`/resume-it`](02-resume-it.md) — pick this app back up later.
- [`/ship-it`](06-ship-it.md) — put it live.
- [`/wrap-it`](13-wrap-it.md) — end your session cleanly.
