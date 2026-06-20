---
name: subagent-it
description: Execute an implementation plan in THIS session via Subagent-Driven Development — a fresh implementer subagent per task, a task review (spec compliance + code quality) after each, fix loops until clean, and a broad whole-branch review at the end. Subagents never inherit your session context; you hand them files. Use when you have an approved multi-task plan with mostly independent tasks and want continuous, reviewed execution. For parallel INDEPENDENT problems (not an ordered plan) use /dispatch-it instead.
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
(spec + quality) and a final whole-branch review. You coordinate; subagents do the work, so your
context stays clean.

Full doctrine: `~/.claude/make-it/references/subagent-driven-development.md`.

</objective>

# /subagent-it -- Subagent-Driven Development

**Core principle:** fresh subagent per task + task review (spec + quality) + broad final review.
**Sequential only** — never run implementers in parallel (they conflict). Independent parallel
problems are `/dispatch-it`'s job.

**Needs an approved plan as input** (it executes, it doesn't brainstorm). **Work on a
branch/worktree, never main/master.** Don't pause to check in between tasks — run the whole plan;
stop only for an unresolvable BLOCKED, genuine blocking ambiguity, or completion.

## Tooling
- `~/.claude/make-it/sdd/scripts/task-brief PLAN_FILE N` → the task's brief file
- `~/.claude/make-it/sdd/scripts/review-package BASE HEAD` → one diff file for a reviewer
- `~/.claude/make-it/sdd/implementer-prompt.md` / `task-reviewer-prompt.md` → dispatch templates
- Final review: `/code-review`. Finish: ship-it / wrap-it.

## Steps
1. **Resume check** — `cat "$(git rev-parse --show-toplevel)/.make-it/sdd/progress.md"`. Tasks
   marked complete are DONE; resume at the first unmarked one.
2. **Read the plan once** — note global constraints, create todos, ensure you're on a branch/worktree.
3. **Pre-flight review (once)** — scan for tasks that contradict each other/the constraints or
   that mandate something the review rubric treats as a defect; present all findings as ONE
   batched question (finding beside plan text, "which governs?"). Clean → proceed silently.
4. **Per task (sequential):** `task-brief` → dispatch implementer (template, cheapest fitting
   model, ALWAYS specify it) → answer its questions → on DONE, record BASE then `review-package`
   → dispatch task reviewer (template) → fix-subagent loop for Critical/Important until spec ✅ +
   quality approved → append `Task N: complete (commits <base7>..<head7>, review clean)` to the ledger.
   Handle DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED per the reference.
5. **Final review** — `/code-review` on the most capable model with `review-package MERGE_BASE HEAD`
   (`git merge-base main HEAD`); fix findings with ONE fix subagent carrying the full list.
6. **Finish** — ship-it / wrap-it.

## Hard rules (see reference for the full list)
- Never pre-judge findings or tell a reviewer what not to flag.
- Hand artifacts as FILES (brief / report / package) — never paste plan text or diffs into your context.
- Use the recorded BASE, never `HEAD~1`. One task per dispatch — no pasted session history.
- Both verdicts (spec + quality) are required; never skip a re-review.
- Trust the ledger + `git log` over recollection after a compaction/resume.

See `subagent-driven-development.md` for model selection, status handling, reviewer ⚠️ items,
reviewer-prompt construction, file handoffs, durable progress, and red flags.
