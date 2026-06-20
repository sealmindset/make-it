# Parallel Agent Dispatch Reference

Delegate independent problems to specialized subagents that run **concurrently**, each with an
isolated, purpose-built context. You craft exactly what each agent needs — they never inherit
your session history. This keeps each agent focused, prevents cross-contamination, and
preserves *your* context for coordination and integration.

**Core principle:** one agent per independent problem domain; let them work in parallel.

**Sibling — `/subagent-it`:** dispatch-it is for *independent problems run in parallel*; for an
*ordered implementation plan* (sequential, possibly dependent tasks), use Subagent-Driven
Development (`subagent-driven-development.md`) — one implementer at a time with review gates.

This is an agent-side technique (the `/dispatch-it` command exposes it directly; other skills
invoke it when they hit multiple independent problems). It is invisible to the vibe-coder.

---

## Mechanism (Claude Code)

- Dispatch = the **Agent/Task tool**. **Multiple Agent dispatches issued in a SINGLE response
  run concurrently; one dispatch per response runs sequentially.** That is the whole trick.
- Agents start **fresh** — they do NOT see your conversation. Everything they need (file paths,
  error text, test names, constraints, expected output) must be written INTO the prompt.
- For heavy, deterministic orchestration (many agents, pipelines, fan-out with barriers,
  loop-until-done), use the **Workflow tool** instead — but that is opt-in; default to direct
  parallel Agent dispatch.

---

## When to use

- 3+ failures with different root causes (different test files / subsystems / bugs)
- Multiple subsystems broken independently
- Each problem is understandable on its own, with no shared state between investigations

## When NOT to use

- **Related failures** — fixing one may fix the others; investigate the shared cause together
  first (use `/debug-it` on it). Parallel dispatch on a shared root cause just produces N
  conflicting fixes for one bug.
- **Need full-system context** to understand the problem.
- **Exploratory** — you don't yet know what's broken. Scout first, then dispatch.
- **Shared state / same files** — agents would collide (see Isolation).

```
Multiple failures?  --no-->  handle normally
        | yes
Independent?  --no (related)-->  single investigation (/debug-it on the shared cause)
        | yes
Would they edit the same files / shared state?
        |-- yes -->  isolate each agent in its own worktree (below), THEN dispatch in parallel
        |-- no  -->  dispatch in parallel directly
```

---

## Safety: isolate when agents write

This is the mitigation for the #1 dispatch failure mode — concurrent edits clobbering each
other or the working tree:

- **Read-only investigation** (diagnose, locate, propose) → agents can share the checkout safely.
- **Parallel edits** (agents change files) → give each agent its **own git worktree** so they
  cannot collide. Use the Agent tool's `isolation: "worktree"`, or pre-create worktrees with
  `scripts/worktree.sh new <branch>` (see `worktree-workflow.md`). Each worktree also gets
  isolated ports/DB so agents can even run the app independently.

---

## The pattern

1. **Identify independent domains.** Group failures by what's broken; confirm fixing one does
   not affect another. If unsure they're independent, they probably aren't — investigate first.
2. **Craft one focused task per agent** — specific scope (one file/subsystem), a clear goal,
   explicit constraints ("don't touch other code"), and a defined return ("summary of root
   cause + exactly what you changed").
3. **Dispatch in parallel** — issue ALL the Agent calls in ONE response.
4. **Review & integrate** — read each summary, check for conflicts (did two agents touch the
   same file?), run the FULL test suite, and spot-check (agents make systematic errors).

---

## Agent prompt structure

Every dispatched prompt is:
1. **Focused** — one clear problem domain.
2. **Self-contained** — paste the error text, failing test names, and file paths. The agent has
   *none* of your context; reconstruct exactly what it needs and nothing more.
3. **Specific about output** — say what to return (a structured summary), and tell it *how* to
   attack and what NOT to touch.

```
Fix the 3 failing tests in src/agents/agent-tool-abort.test.ts:
  1. "should abort tool with partial output capture" — expects 'interrupted at' in message
  2. "should handle mixed completed and aborted tools" — fast tool aborted instead of completed
  3. "should properly track pendingToolCount" — expects 3 results but gets 0

These look like timing/race issues. Your task:
  1. Read the test file; understand what each test verifies.
  2. Identify the root cause — timing, or a real bug?
  3. Fix by replacing arbitrary timeouts with event-based waiting, fixing abort bugs if found,
     or adjusting expectations if the behavior intentionally changed.
Do NOT just increase timeouts — find the real issue. Do NOT change unrelated code.
Return: root cause + the exact changes you made.
```

---

## Scale & cost

Fan out to the number of *genuinely independent* domains — no more. Parallel agents multiply
token cost, and over-fanning ("6 agents for 2 bugs") wastes it. If domains exceed a handful or
need ordering/barriers, switch to a Workflow. Always note if you capped or batched.

## Compose with /debug-it

Each dispatched agent should run the **/debug-it** method on its domain: reproduce against
ground truth → generate both hypothesis families (missing-step AND doing-too-much) → smallest
reversible fix → verify against the same repro. Dispatch is the fan-out; debug-it is the
per-domain rigor.

## Common mistakes

- **Too broad** ("fix all the tests") → focused scope per agent.
- **No context** ("fix the race condition") → paste errors + locations; the agent can't see your chat.
- **No constraints** → agent refactors everything; pin the blast radius.
- **Vague output** → demand a structured summary of root cause + changes.
- **Parallelizing writers without isolation** → conflicts; give each a worktree.
- **Dispatching related failures** → N conflicting fixes for one bug; find the shared cause first.

---

## Verification (after agents return)

1. Review each summary — understand what changed.
2. Check for conflicts — did agents edit the same code?
3. Run the full suite — verify all fixes work together.
4. Spot-check — agents can make systematic errors; don't trust blindly.
