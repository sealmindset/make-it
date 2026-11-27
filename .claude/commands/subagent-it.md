---
name: subagent-it
description: Execute an implementation plan in THIS session via Subagent-Driven Development — a fresh implementer subagent per task, a task review (spec compliance + code quality + safeguards) after each, fix loops until clean, and a broad whole-branch review at the end. Subagents never inherit your session context; you hand them files. Use when you have an approved multi-task plan with mostly independent tasks and want continuous, reviewed execution. For parallel INDEPENDENT problems (not an ordered plan) use /dispatch-it instead.
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

Turn an approved implementation plan into reviewed, committed code — one task at a time, each
implemented by a fresh subagent with an isolated, file-based context, gated by a per-task review
(spec + quality + safeguards) and a final whole-branch review. You coordinate; subagents do the work, so your
context stays clean.

Full doctrine: `~/.claude/make-it/references/subagent-driven-development.md`.

</objective>

<execution_context>

@~/.claude/make-it/references/approval-block.md

</execution_context>

<expert_persona>

/subagent-it adopts no specialist itself. Every subagent it launches on app code is handed two
things in its brief: the project specialist, the specialists the `expert_persona` field in the
app's `app-context.json` names (the template's `[PROJECT_SPECIALISTS]` slot), and the task
specialist that task's domain calls for (`[TASK_SPECIALIST]`). The implementer and the test-writer
work as the task specialist, held to the checks and output standard of every specialist recorded
in `expert_persona`; the task reviewer, the adversarial reviewer and the final `/code-review`
review against those checks too. With no `expert_persona` set, an older value the reference does not count (its "Reading an older value"), or a run outside an
app, the slot is left empty and each agent works as its task specialist alone and says nothing. Choose the task
specialist per task from the task's text; never work a project specialist out from signals, and
never change the specialist record. No user prompt. See the reference below.

@~/.claude/make-it/references/expert-personas.md

</expert_persona>

# /subagent-it -- Subagent-Driven Development

**Core principle:** fresh subagent per task + task review (spec + quality + safeguards) + broad final review.
**Sequential only** — never run implementers in parallel (they conflict). Independent parallel
problems are `/dispatch-it`'s job.

**Needs an approved plan as input** (it executes, it doesn't brainstorm). A plan marked
`status: draft` isn't approved: get the user's go, then mark it `status: approved` (Plan
format: `~/.claude/make-it/references/backlog-board.md`). **Work on a
branch/worktree, never main/master.** Don't pause to check in between tasks — run the whole plan;
stop only for an unresolvable BLOCKED, genuine blocking ambiguity, or completion.

## Tooling
- `~/.claude/make-it/sdd/scripts/task-brief PLAN_FILE N` → the task's brief file
- `~/.claude/make-it/sdd/scripts/review-package BASE HEAD` → one diff file for a reviewer
- `~/.claude/make-it/sdd/test-writer-prompt.md` / `implementer-prompt.md` / `task-reviewer-prompt.md` /
  `adversarial-reviewer-prompt.md` → dispatch templates
- Final review: `/code-review`. Finish: ship-it / wrap-it.

## Steps
1. **Resume check** — `cat "$(git rev-parse --show-toplevel)/.make-it/sdd/progress.md"`. Tasks
   marked complete are DONE; resume at the first unmarked one. Arm the ledger: append
   `RUN: plan=<path> tasks=<N>` (or `RUN: resume` if already armed), then register it from the
   repo/worktree that holds it: `python3 ~/.claude/make-it/sdd/scripts/sdd-gate register
   "$(git rev-parse --show-toplevel)/.make-it/sdd/progress.md"`. A Stop hook (`sdd-gate`)
   then refuses to let the run end until you append `STATUS: DONE | BLOCKED <why> |
   AWAITING_HUMAN <what>` — write AWAITING_HUMAN before asking the user anything, and ask it readable cold: its title, what waits and why, 2-4 named answers, a batch as one grouped line, a high-stakes item never batched (`approval-block.md`, A list of asks).
2. **Read the plan once** — note global constraints, create todos, ensure you're on a branch/worktree.
3. **Pre-flight review (once)** — scan for tasks that contradict each other/the constraints or
   that mandate something the review rubric treats as a defect; present all findings as ONE
   batched question (finding beside plan text, "which governs?"). Clean → proceed silently.
4. **Per task (sequential):** `task-brief` → record BASE → dispatch the **test-writer**
   (template, Opus or Fable) → **red check**: run its tests, they must fail for the missing behavior
   (NOT_TESTABLE: skip to the implementer with no Tests section) → dispatch implementer
   (template, cheapest fitting model, ALWAYS specify it; it may not change the tests; a test it
   says is wrong goes back to the test-writer) → answer its questions → on DONE, **tests
   untouched and green**: `git diff --name-only <TESTS_SHA> -- <test files>` prints nothing and
   you run them yourself, all passing, none skipped (again after every fix) → `review-package`
   → dispatch task reviewer (template, with every SAFEGUARDS line the task produced) →
   fix-subagent loop for Critical/Important until spec ✅, quality approved, and safeguards ✅ (an
   undisclosed weakening is undone; a disclosed one is undone too, unless that changes behavior
   the plan didn't decide -- then the human's call; log each as `Task N: safeguards undone|accepted:
   <item>`; three consecutive rounds on the same root cause: stop patching and write
   `STATUS: AWAITING_HUMAN` with a decision-ready design choice) → **adversarial review** (tasks
   with tests, at most 3 rounds per task; the
   repo must be untouched after each): confirmed counterexamples only (its SAFEGUARDS
   line is separate: an `undisclosed` one is undone, in any round), which you adjudicate
   (ungrounded or plan-conflicting → the human; unsure severity → Important); in rounds 1–2 each
   becomes one test-writer test on its exact input (red check), the implementer fixes it, tests
   untouched and green, re-review, next round; round 3's are not fixed -- open Critical/Important →
   `STATUS: AWAITING_HUMAN`, Minor only → accept and log; after the human answers, the count
   doesn't reset -- apply their call and carry on where you stopped → append `Task N: complete (commits <base7>..<head7>,
   review clean)` to the ledger.
   Handle DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED per the reference.
5. **Final review** — `/code-review` on the most capable model with `review-package MERGE_BASE HEAD`
   (`git merge-base main HEAD`) and every `safeguards accepted` ledger line; fix findings with ONE
   fix subagent carrying the full list.
6. **Finish** — after `STATUS: DONE`, offer learnings (`~/.claude/make-it/references/learnings.md`):
   queued agent lessons (e.g. reviewer findings that recurred across tasks), plus corrections the
   user made at acceptance — one message, each numbered with its evidence and what it would
   change; the user answers per item. Then ship-it / wrap-it.

## Hard rules (see reference for the full list)
- Never pre-judge findings or tell a reviewer what not to flag.
- Hand artifacts as FILES (brief / report / package) — never paste plan text or diffs into your context.
- Use the recorded BASE, never `HEAD~1`. One task per dispatch — no pasted session history.
- All three verdicts (spec, quality, safeguards) are required; never skip a re-review. An
  undisclosed weakened safeguard is undone, never kept (`approval-block.md`).
- Trust the ledger + `git log` over recollection after a compaction/resume.
- When a helper's final report arrives, stop it (TaskStop) so nothing it started is left running
  (`approval-block.md`, Leave nothing running).
- What you tell the owner is plain (`approval-block.md`, A message to the owner): when you pass on a
  subagent's or a reviewer's report, rewrite it in plain words: names with ids, shortest true form; never forward a lane's shorthand.
- Findings are sorted (`approval-block.md`, A review sorts its findings): Critical and Important are
  fixed before the task is complete; at most five quick Minors are fixed with them and the rest are
  dropped; a fault that was already there is a card only if it can hurt someone, else one line on
  the running list. No task files a follow-up card by default.

See `subagent-driven-development.md` for model selection, status handling, reviewer ⚠️ items,
reviewer-prompt construction, file handoffs, durable progress, and red flags.
