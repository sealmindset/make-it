# /subagent-it — Execute a multi-step plan automatically, with review

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/subagent-it` takes an **approved, step-by-step plan** and carries it out one task at a time. A fresh AI helper implements each task, and after each one a reviewer checks it for correctness and quality, with fix loops until it's clean — plus a broad review of the whole thing at the end.

> **In one sentence:** Hand it a plan, and it builds each step for you with a quality check after every one.

> ℹ️ **This is a power-user skill** and it's for *executing* a plan, not brainstorming one. It needs an approved plan as its input.

---

## What is it used for?

Turning an approved implementation plan (a list of mostly independent tasks, done in order) into **reviewed, saved code** — without you babysitting each step. This is called **Subagent-Driven Development**: coordinate at the top, let fresh helpers do the work so the main context stays clean.

---

## Why do you need it?

Big plans are tedious and error-prone to execute by hand, and quality tends to drift as you get tired. `/subagent-it` keeps quality consistent: **every task is independently reviewed** (against both the plan and code-quality standards) before moving on, and the whole branch gets a final review. Each helper starts fresh, so mistakes don't compound.

---

## How it helps you vibe code

You focus on *what* you want built (the plan); it handles the disciplined execution and review. You're not asked to check in between every task — it runs the whole plan and stops only if it hits a genuine blocker, a real ambiguity, or completion.

---

## How to use it

First, have an **approved plan** (a numbered list of tasks). Then, on a working branch, type:

```
/subagent-it
```

It will:
1. **Resume-check** — skip tasks already done, continue from the first unfinished one.
2. **Read the plan once** and flag any contradictions up front.
3. **For each task, in order:** a fresh helper implements it → a reviewer checks spec + quality → fix loop until clean.
4. **Final review** of the whole branch, then hand off to [`/ship-it`](06-ship-it.md) or [`/wrap-it`](13-wrap-it.md).

---

## When to use it

- ✅ You have an **approved multi-step plan** with mostly independent tasks.
- ✅ You want continuous, reviewed execution without micromanaging.

**When *not* to use it:**
- ❌ You have several **independent, unordered** problems → use [`/dispatch-it`](14-dispatch-it.md) (parallel).
- ❌ You don't have a plan yet → create and approve one first.
- ❌ You're debugging something → [`/debug-it`](10-debug-it.md).

> **Sequential only.** `/subagent-it` never runs implementers in parallel — that's `/dispatch-it`'s job. Use it for *ordered* plans; use `/dispatch-it` for *independent* problems.

---

## Which expert does the AI become?

Each step of the plan is handed to a fresh helper set up as the **right specialist for that step**, and the reviewer that checks the work is set up the same way. So every task is done — and checked — by the expert it calls for, not one generalist across the whole plan. Chosen automatically, no prompt. (See the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job).)

---

## Related skills

- [`/dispatch-it`](14-dispatch-it.md) — the parallel sibling for independent problems.
- [`/ship-it`](06-ship-it.md) / [`/wrap-it`](13-wrap-it.md) — finish up after the plan is done.
