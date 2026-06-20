---
name: dispatch-it
description: Dispatch parallel subagents, one per independent problem domain, each with an isolated purpose-built context they do not inherit from your session. Use when you have multiple unrelated failures (different test files, subsystems, or bugs) that can be investigated/fixed concurrently. Reviews and integrates the results, isolating writers in worktrees so they never collide. Don't use for related failures (find the shared cause first) or exploratory debugging.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Task
---

<objective>

Solve several INDEPENDENT problems at once by dispatching one focused subagent per problem
domain, concurrently. You construct exactly the context each agent needs — they never inherit
your session history — which keeps them focused and preserves your context for coordinating
and integrating their results.

Full doctrine: `~/.claude/make-it/references/parallel-dispatch.md`.

</objective>

# /dispatch-it -- parallel agents, one per independent problem

**Core principle:** one agent per independent problem domain; let them work in parallel.
**The trick:** multiple Agent dispatches in a SINGLE response run concurrently; one per
response runs sequentially.
**Sibling:** for an *ordered implementation plan* (sequential, possibly dependent tasks — not
independent problems), use `/subagent-it` (Subagent-Driven Development) instead.

---

## Step 1 -- Confirm parallel dispatch is the right move

Dispatch in parallel when: 3+ failures with different root causes, independent subsystems, each
understandable on its own, no shared state.

Do NOT dispatch when:
- **Failures are related** — fixing one may fix others. Find the shared cause first (`/debug-it`).
- **You don't yet know what's broken** — scout first, then dispatch.
- **You need full-system context** to understand the problem.

If unsure the problems are independent, they probably aren't — investigate before fanning out.

## Step 2 -- Identify independent domains

Group the failures by what's broken (e.g. file A = tool-approval flow, file B = batch
completion, file C = abort logic). Confirm fixing one does not affect another.

## Step 3 -- Decide isolation (the safety gate)

- **Read-only** (diagnose/locate/propose) → agents can share the checkout.
- **Writers** (agents edit files) → give each its own git worktree so they can't collide: the
  Agent tool's `isolation: "worktree"`, or pre-make worktrees with `scripts/worktree.sh`.

## Step 4 -- Craft one focused prompt per agent

Each prompt must be: **focused** (one domain), **self-contained** (paste the error text,
failing test names, file paths — the agent sees none of your chat), and **specific about
output** (return a structured summary of root cause + exact changes). Tell it how to attack and
what NOT to touch. Have each agent follow the `/debug-it` method on its domain.

## Step 5 -- Dispatch in parallel

Issue ALL the Agent calls in ONE response. Scale the count to the number of *genuinely
independent* domains — don't over-fan-out (cost multiplies). For dozens of agents or ordered
stages, use the Workflow tool instead.

## Step 6 -- Review & integrate

Read each summary → check for conflicts (same file touched twice?) → run the FULL test suite →
spot-check (agents make systematic errors). Then integrate.

---

See `parallel-dispatch.md` for the decision tree, prompt template, and common mistakes.
