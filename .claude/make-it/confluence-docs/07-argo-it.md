# /argo-it — Deploy to Kubernetes automatically

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/argo-it` takes an app that runs locally (in Docker Compose) and deploys it to **Kubernetes** — the industry-standard system for running apps at scale — using **Argo CD**. It generates all the necessary configuration and a full automated pipeline so that, from then on, you just push your code and the system deploys it for you.

> **In one sentence:** Get your app running on big-league, scalable hosting — without learning Kubernetes.

> ℹ️ **This is an advanced deployment skill.** Most builders start with [`/ship-it`](06-ship-it.md). Use `/argo-it` when your app needs to run on Kubernetes specifically.

---

## What is it used for?

- Turning a local Docker app into a **Kubernetes deployment**.
- Setting up a **fully automated pipeline**: every time you push code, it builds, mirrors, and deploys automatically.
- Producing **onboarding docs** so your team knows how it all works.

---

## Why do you need it?

Kubernetes is powerful but notoriously complex — it usually requires dedicated platform engineers. `/argo-it` removes that barrier. It reads your existing setup, detects your organization's conventions, and generates everything needed. **You never manually deploy again** — you push code, and the automation does the rest.

---

## How it helps you vibe code

All Kubernetes complexity stays invisible. It won't show you raw configuration files or ask about internal Kubernetes settings. You get the benefit of enterprise-scale hosting while staying in plain-language territory.

---

## How to use it

From inside your app (which must already run in Docker Compose), type:

```
/argo-it
```

It will:
1. **Discover** — read your `docker-compose.yml` and detect your org's conventions.
2. **Generate** — create the Kubernetes configuration and a build-and-deploy pipeline.
3. **Document** — produce onboarding docs for your team.

After that, the workflow is simply: **push your code → automation deploys it.**

---

## When to use it

- ✅ Your app runs in Docker Compose and needs to live on Kubernetes.
- ✅ Your organization uses Argo CD (or you want that automated model).

**When *not* to use it:**
- ❌ You just want a straightforward production deploy → [`/ship-it`](06-ship-it.md).
- ❌ Your app doesn't have Docker Compose yet → build with [`/make-it`](01-make-it.md) or add foundations with [`/retrofit-it`](03-retrofit-it.md) first.

---

## Which expert does the AI become?

For large-scale deployment, the AI works as a **platform / operations engineer**, not a generalist — automatically, no prompt. It plans for what happens when things go wrong (how to roll back, how you'll know there's a problem), not just how to get the app live. (Set behind the scenes from your app's details — see the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job).)

---

## Related skills

- [`/ship-it`](06-ship-it.md) — the simpler production path.
- [`/make-it`](01-make-it.md) / [`/retrofit-it`](03-retrofit-it.md) — ensure your app is containerized first.
