# /ship-it — Put your app into production

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/ship-it` gets your app into production — live and usable — with **zero DevOps knowledge required.** You type one command; it does the security checks, packaging, and the request to go live, then tells you the outcome in two or three friendly sentences.

> **In one sentence:** Say "go live," and it handles everything to get your app to production.

---

## What is it used for?

- **Shipping** your finished app to production (the default).
- **Saving** your work safely without going live yet (`/ship-it save`).

Along the way it scans for security problems, generates a safety attestation, and creates the formal "request to go live" with a checklist and reviewers.

---

## Why do you need it?

Deployment is where most non-technical builders get stuck — it's full of jargon (pipelines, pull requests, merges, CI/CD) and easy to get wrong. `/ship-it` hides all of it. It even reuses what [`/make-it`](01-make-it.md) already knows about your app, so it **won't re-ask questions you've already answered.**

---

## How it helps you vibe code

It's the final step of the vibe: you built and explored your app, now you just want it *out there.* `/ship-it` translates "deploy to production" into a single command and speaks only in plain language — "request to go live" and "your change," never "CI/CD pipeline."

---

## How to use it

To go live:

```
/ship-it
```

To save your work without going live:

```
/ship-it save
```

It runs everything silently and asks **zero questions unless truly necessary**, then reports back briefly.

**What it does for you (a production ship):**
1. Detects your repo, branch, and login status.
2. Scans dependencies for vulnerabilities (and auto-fixes where it can).
3. If your app uses AI, runs the full **AI-safety test suite**.
4. Generates a **safety attestation** document.
5. Commits your work, pushes it, and creates the go-live request with labels, reviewers, a security summary, and a go-live checklist.

---

## When to use it

- ✅ Your app is built, verified, and you're ready to deploy.
- ✅ You want to safely save progress (`/ship-it save`) before going live.

**When *not* to use it:**
- ❌ You need Kubernetes-scale hosting → [`/argo-it`](07-argo-it.md).

---

## Related skills

- [`/make-it`](01-make-it.md) / [`/retrofit-it`](03-retrofit-it.md) — build or upgrade before shipping.
- [`/nemo-it`](08-nemo-it.md) + [`/fix-it`](09-fix-it.md) — deeper security scan and fix before you ship.
- [`/argo-it`](07-argo-it.md) — deploy to Kubernetes instead.
