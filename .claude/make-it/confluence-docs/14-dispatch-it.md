# /dispatch-it — Fix several unrelated problems at once

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/dispatch-it` sends out several focused AI helpers ("subagents") at the same time — **one per independent problem** — so unrelated issues get worked on in parallel. Each helper gets exactly the context it needs and works in isolation, so they never collide.

> **In one sentence:** Have several unrelated problems? Solve them all at once instead of one by one.

> ℹ️ **This is a power-user skill.** It's most valuable when you clearly have multiple *separate* problems.

---

## What is it used for?

Working on **3 or more failures that have different causes** and don't affect each other — for example, three different broken test files, or three unrelated subsystems. Each gets its own helper; the results are then reviewed and combined.

---

## Why do you need it?

Doing unrelated tasks one at a time is slow. `/dispatch-it` runs them **concurrently**, which is much faster — and because each helper starts with a clean, purpose-built context (it doesn't inherit your whole session), each stays focused and your own view stays uncluttered for coordinating.

---

## How it helps you vibe code

You don't manage the parallelism yourself. You describe the separate problems; `/dispatch-it` decides isolation (read-only helpers can share; helpers that *edit files* each get their own private workspace so they can't overwrite each other), fans them out, and integrates the results.

---

## How to use it

Type:

```
/dispatch-it
```

It first confirms the problems really are independent, groups them into domains, decides the safe isolation level, gives each helper a focused instruction, then runs them in parallel and integrates the fixes.

---

## When to use it

- ✅ You have **3+ unrelated failures** with different root causes.
- ✅ The problems are in independent areas with no shared state.

**When *not* to use it:**
- ❌ The failures are **related** (fixing one might fix others) → find the shared cause with [`/debug-it`](10-debug-it.md) first.
- ❌ You don't yet know what's broken → investigate first.
- ❌ You have an **ordered, step-by-step plan** (not independent problems) → use [`/subagent-it`](15-subagent-it.md) instead.

> Rule of thumb: *If you're not sure the problems are independent, they probably aren't.* Investigate before fanning out.

---

## Which expert does the AI become?

Because each helper works on a *different* problem, each one is given the **specialist role its own problem needs** — the helper on a security issue works as a security engineer, the one on a slow-performance issue works as a reliability engineer, and so on. One right expert per problem, all at once — chosen automatically. (See the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job).)

---

## Related skills

- [`/subagent-it`](15-subagent-it.md) — the sibling for *ordered* plans (sequential, not parallel).
- [`/debug-it`](10-debug-it.md) — find the shared cause when failures are related.
- [`/fix-it`](09-fix-it.md) — uses parallel dispatch internally for independent security fixes.
