# Subagent-Driven Development (SDD) Reference

Execute an implementation plan by dispatching a **fresh implementer subagent per task**, a
**task review (spec compliance + code quality) after each**, and a **broad whole-branch review
at the end**. Subagents never inherit your session history — you construct exactly the context
each needs, which keeps them focused and preserves *your* context for coordination.

**Core principle:** fresh subagent per task + task review (spec + quality) + broad final review
= high quality, fast iteration.

SDD is the **sequential sibling of `/dispatch-it`**: dispatch-it fans out *independent*
problems in parallel; SDD walks an *ordered plan* one task at a time. **Never run implementers
in parallel** — they conflict. If a plan's tasks are genuinely independent, that's dispatch-it.

This is an agent-side technique (the `/subagent-it` command exposes it). It needs an existing,
approved plan as input — it executes, it does not brainstorm.

---

## Tooling (installed with make-it)

- `~/.claude/make-it/sdd/scripts/task-brief PLAN_FILE N` — extracts task N's text to a uniquely
  named file; prints the path.
- `~/.claude/make-it/sdd/scripts/review-package BASE HEAD` — writes a single file with the
  commit list + diffstat + `git diff -U10` for the range; prints the path.
- `~/.claude/make-it/sdd/implementer-prompt.md` — implementer dispatch template.
- `~/.claude/make-it/sdd/task-reviewer-prompt.md` — task reviewer dispatch template.
- Final whole-branch review: the **`/code-review`** skill.
- Finishing the branch: **ship-it / wrap-it** (+ the worktree finish from `worktree-workflow.md`).

---

## Narration & continuous execution

- Between tool calls, narrate at most one short line — the ledger and tool results carry the record.
- **Do not pause to check in between tasks.** Execute all plan tasks without stopping. The only
  stop reasons: a BLOCKED status you can't resolve, ambiguity that genuinely prevents progress,
  or all tasks complete. "Should I continue?" prompts waste the user's time — they asked you to
  execute the plan.

---

## The process

1. **Read the plan once.** Note context + global constraints. Create todos for all tasks.
   Start on a branch/worktree — **never main/master** (see `worktree-workflow.md`).
2. **Pre-flight plan review (once).** Scan for tasks that contradict each other or the Global
   Constraints, or anything the plan mandates that the review rubric treats as a defect (a test
   that asserts nothing, verbatim logic duplication). Present everything found as ONE batched
   question to the human (each finding beside the plan text that mandates it, asking which
   governs) before execution. If clean, proceed silently.
3. **Per task** (sequential):
   a. `task-brief PLAN_FILE N` → dispatch a fresh **implementer** subagent (template) with: one
      line on where the task fits, the brief path ("read this first — your requirements, exact
      values verbatim"), interfaces/decisions from earlier tasks the brief can't know, your
      resolution of any ambiguity, and the report-file path + report contract.
   b. Answer the implementer's questions before it proceeds.
   c. Implementer implements (TDD), tests, commits, self-reviews, writes its report file,
      returns only status + commits + one-line test summary + concerns.
   d. `review-package BASE HEAD` (BASE = the commit recorded **before** dispatching — never
      `HEAD~1`, which drops all but the last commit of a multi-commit task) → dispatch the
      **task reviewer** (template) with the brief, report, and package paths + verbatim global
      constraints.
   e. If the reviewer reports spec ❌ or quality issues: dispatch a **fix subagent** for
      Critical/Important findings (implementer contract: re-run the covering tests, name them,
      report command + output) → re-review. Repeat until spec ✅ and quality approved.
   f. Append one line to the ledger: `Task N: complete (commits <base7>..<head7>, review clean)`.
4. **After all tasks:** dispatch the final whole-branch review via `/code-review` on the most
   capable model, with `review-package MERGE_BASE HEAD` (MERGE_BASE = `git merge-base main HEAD`).
   Fix findings with ONE fix subagent carrying the complete list (not one fixer per finding).
5. **Finish the branch** via ship-it / wrap-it.

---

## Model selection (always specify the model when dispatching)

Use the least powerful model that can do each role — an omitted model inherits your (expensive)
session model and silently defeats this.

- **Transcription implementer** (plan text contains the complete code): cheapest tier.
- **Mechanical implementer** (1–2 files, complete spec) / single-file fix: cheap–mid tier.
- **Integration/judgment implementer** (multi-file, debugging): standard tier.
- **Architecture/design + the final whole-branch review:** most capable tier.
- **Reviewers:** scale to the diff's size/risk — a mechanical diff doesn't need the top model; a
  subtle concurrency change does.
- **Turn count beats token price:** the cheapest models often take 2–3× the turns on multi-step
  work. Use a mid-tier model as the floor for reviewers and prose-spec implementers.

Map to the Agent tool's `model` / `effort` params (or Workflow's per-agent `model`).

---

## Handling implementer status

- **DONE:** generate the review package (BASE = recorded pre-dispatch commit) → dispatch reviewer.
- **DONE_WITH_CONCERNS:** read the concerns first. Correctness/scope → address before review.
  Observations → note and proceed.
- **NEEDS_CONTEXT:** provide the missing context, re-dispatch.
- **BLOCKED:** assess — context problem → add context, same model; needs more reasoning →
  re-dispatch on a more capable model; too large → split; plan is wrong → escalate to human.
  **Never** ignore an escalation or retry the same model with no change.

## Reviewer ⚠️ "cannot verify from diff" items

Requirements living in unchanged code or spanning tasks. They don't block the rest of the
review, but YOU resolve each before marking the task complete (you hold the cross-task context).
A confirmed gap = failed spec review → back to the implementer → re-review.

---

## Constructing reviewer prompts (gates, not fishing trips)

- Per-task reviews are **task-scoped**; the broad review happens once at the end.
- Don't add open-ended directives ("check all uses", "run race tests if useful") without a
  concrete task-specific reason. Don't ask a reviewer to re-run tests the implementer already ran.
- **Never pre-judge.** No "do not flag X", "treat as Minor at most", "the plan chose this". If
  you think a finding would be a false positive, let the reviewer raise it and adjudicate in the
  loop. The plan's example code is a starting point, not proof its weaknesses were chosen.
- The **global-constraints block is the reviewer's attention lens** — copy binding requirements
  verbatim from the plan (exact values, formats, stated relationships like "same layout as X").
- Hand diffs as **files** (`review-package`), never paste them into your context. Use the
  recorded BASE, never `HEAD~1`.
- A dispatch prompt describes ONE task — never paste accumulated prior-task summaries (a real
  session hit 42k chars, 99% pasted history). A fresh subagent needs its task, the interfaces it
  touches, and the global constraints. Nothing else.
- Dispatch fixes for Critical/Important; record **Minor** findings in the ledger and point the
  final review at that list (a roll-up nobody reads is a silent discard).
- A **plan-mandated** finding (or any finding conflicting with the plan text) is the human's
  decision: present the finding + the plan text, ask which governs. Don't dismiss it because the
  plan mandates it; don't fix against the plan without asking.
- Final review gets a package too (`review-package MERGE_BASE HEAD`); if it returns findings,
  dispatch ONE fix subagent with the complete list, not one fixer per finding.

## File handoffs (keep your context clean)

Everything pasted into a dispatch — and everything a subagent prints back — stays in your
context and is re-read every later turn. Move artifacts as files:

- **Task brief:** `task-brief PLAN_FILE N`; the dispatch points to it as the single source of
  requirements (exact values live only there).
- **Report file:** name it after the brief (`task-N-brief.md` → `task-N-report.md`); the
  implementer writes the full report there and returns only status/commits/test-summary/concerns.
- **Reviewer inputs:** brief path + report path + review-package path + verbatim global constraints.
- Fix dispatches append their fix report (with test results) to the same report file.

## Durable progress (survives compaction)

Conversation memory doesn't survive compaction; controllers that lost their place have
re-dispatched entire completed sequences — the most expensive failure observed.

- At start: `cat "$(git rev-parse --show-toplevel)/.make-it/sdd/progress.md"`. Tasks marked
  complete there are DONE — resume at the first unmarked task; do not re-dispatch.
- On a clean review, append `Task N: complete (commits <base7>..<head7>, review clean)`.
- The ledger is the recovery map — trust it and `git log` over recollection after compaction.
- `git clean -fdx` destroys the ledger (git-ignored scratch); recover from `git log`.

---

## Red flags — never

- Start implementation on main/master without explicit consent (work on a branch/worktree).
- Skip task review, or accept a report missing either verdict (spec AND quality both required).
- Proceed with unfixed Critical/Important issues; move to the next task with open ones.
- **Dispatch multiple implementers in parallel** (conflicts) — that's `/dispatch-it`, for
  *independent* problems only.
- Make a subagent read the whole plan (hand it its `task-brief`).
- Paste session history / prior-task summaries into a dispatch.
- Pre-judge a finding's severity or tell a reviewer what not to flag.
- Dispatch a task reviewer without a diff file.
- Re-dispatch a task the ledger already marks complete (check the ledger + `git log` after any
  compaction/resume).
- Let implementer self-review replace actual review (both are needed).
