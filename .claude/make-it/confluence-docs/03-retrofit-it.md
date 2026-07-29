# /retrofit-it — Add enterprise foundations to an existing app

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/retrofit-it` takes an app that already works — built by you, another developer, or any tool — and adds the **production-ready foundations** that `/make-it` normally builds in from the start: user logins, permissions, packaging, and security. It studies your app *first*, then upgrades it carefully so nothing breaks.

> **In one sentence:** Bring an existing app up to professional, enterprise-ready standards without rebuilding it.

---

## What is it used for?

Upgrading an app that's functional but missing "enterprise" requirements, such as:
- **Login / single sign-on** (OIDC authentication)
- **Roles and permissions** (who can do what — RBAC)
- **Containerization** (standard packaging for reliable deployment)
- **Mock services** (so it runs locally without external dependencies)
- **Security hardening** and **AI safety controls**

---

## Why do you need it?

Lots of apps start as quick prototypes and only later need to be "real." Rewriting from scratch is wasteful and risky. `/retrofit-it` **preserves everything you built** — your app's purpose, design, and behavior — and strengthens the foundation underneath it.

Critically, it **reverse-engineers first**: it understands your app before proposing a single change, and it's honest about risk.

---

## How it helps you vibe code

You don't need to know *what* enterprise foundations are missing or *how* to add them. `/retrofit-it` figures out the gaps, explains them in plain terms ("this lets your app be deployed to production"), and does the upgrade for you — with your approval on the plan.

---

## How to use it

From inside your existing project, type:

```
/retrofit-it
```

**The seven phases:**
1. **Preflight** — checks your machine is ready.
2. **Discovery** — reverse-engineers your app (no interrogation upfront).
3. **Gap analysis** — compares what you have vs. professional standards and scores the risk.
4. **Clarification** — asks targeted questions *only* where your code is ambiguous.
5. **Plan** — shows you the plan and risk, and **waits for your approval**.
6. **Retrofit** — makes the changes (all at once, or in careful phases if risky).
7. **Verify** — tests everything, then hands off to [`/ship-it`](06-ship-it.md).

---

## When to use it

- ✅ You have a **working app** that lacks logins, permissions, or production packaging.
- ✅ You inherited an app and need to make it enterprise-ready.

**When *not* to use it:**
- ❌ You have no app yet → [`/make-it`](01-make-it.md).
- ❌ Your app already has the foundations and you just want new features → [`/resume-it`](02-resume-it.md).

---

## Which expert does the AI become?

For retrofitting an existing app, the AI works as a **software architect**, not a generalist — automatically, no prompt. Its priority is upgrading your app *without breaking what already works*: it plans the change in safe stages and keeps a record of the risks. (Set behind the scenes from your app's details — see the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job).)

---

## Related skills

- [`/make-it`](01-make-it.md) — builds these foundations from the start for new apps.
- [`/nemo-it`](08-nemo-it.md) — check the retrofitted app for security issues.
- [`/ship-it`](06-ship-it.md) — deploy once foundations are in place.
