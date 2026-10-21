# Subagent-Driven Development (SDD) Reference

Execute an implementation plan by dispatching a **fresh implementer subagent per task**, a
**task review (spec compliance + code quality + safeguards) after each**, and a **broad whole-branch review
at the end**. Subagents never inherit your session history — you construct exactly the context
each needs, which keeps them focused and preserves *your* context for coordination.

**Core principle:** fresh subagent per task + task review (spec + quality + safeguards) + broad final review
= high quality, fast iteration.

SDD is the **sequential sibling of `/dispatch-it`**: dispatch-it fans out *independent*
problems in parallel; SDD walks an *ordered plan* one task at a time. **Never run implementers
in parallel** — they conflict. If a plan's tasks are genuinely independent, that's dispatch-it.

This is an agent-side technique (the `/subagent-it` command exposes it). It needs an existing,
approved plan as input — it executes, it does not brainstorm. The plan's shape and where it lives
are the Plan format in `backlog-board.md`; a plan marked `status: draft` needs the user's go first.

---

## Tooling (installed with make-it)

- `~/.claude/make-it/sdd/scripts/task-brief PLAN_FILE N` — extracts task N's text to a uniquely
  named file; prints the path.
- `~/.claude/make-it/sdd/scripts/review-package BASE HEAD` — writes a single file with the
  commit list + diffstat + `git diff -U10` for the range; prints the path.
- `~/.claude/make-it/sdd/scripts/sdd-gate` — Stop hook that keeps an open run going until its
  gates pass (see Durable progress).
- `~/.claude/make-it/sdd/test-writer-prompt.md` — test-writer dispatch template (tests first).
- `~/.claude/make-it/sdd/implementer-prompt.md` — implementer dispatch template.
- `~/.claude/make-it/sdd/adversarial-reviewer-prompt.md` — adversarial reviewer template
  (counterexamples only, after the task reviewer passes).
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
   a. `task-brief PLAN_FILE N`, record BASE, then dispatch a fresh **test-writer** (template, on
      **Opus** or Fable) with the brief path, the test framework, and the report-file path. It writes
      and commits tests only, and returns TESTS_READY with its commit, files, command, and SAFEGUARDS line -- or
      NOT_TESTABLE for a task with nothing to test (docs, config, prompt wording; then skip to b
      with no Tests section). Answer its questions before it proceeds.
   a2. **Red check (gate):** run its test command yourself. It must fail, for the missing
      behavior -- not a broken test file. A test that already passes (the behavior exists, or it
      asserts nothing) or fails for the wrong reason → back to the test-writer before any code.
      After a mid-task test-writer fix, re-run just the corrected tests: with no implementer code
      yet they must fail; a pass that comes from code already committed is fine.
   b. Dispatch a fresh **implementer** subagent (template) with: one line on where the task
      fits, the brief path ("read this first — your requirements, exact values verbatim"), the
      **Tests** section (files, command -- it may not change them), interfaces/decisions from
      earlier tasks the brief can't know, your resolution of any ambiguity, and the report-file
      path + report contract. UI task: also the approved preview file + its screen ids
      (`ui-gate.md`). Answer its questions before it proceeds. A NEEDS_CONTEXT that names a
      wrong test → the test-writer fixes it (re-run a2), then the implementer continues.
   c. Implementer makes the tests pass, commits, self-reviews, writes its report file, returns
      only status + commits + one-line test summary + concerns + its **SAFEGUARDS** line (every
      safeguard it bypassed or weakened, or "none" -- `approval-block.md`). Keep every SAFEGUARDS
      line the task produces (test-writer, implementer, each fix): the reviewers get them all, with
      the task's `safeguards undone` / `safeguards accepted` ledger lines, as `[SAFEGUARDS_LINES]`.
   c2. **Tests untouched and green (gate):** `git diff --name-only <TESTS_SHA> -- <test files>`
      must print nothing (TESTS_SHA = the test-writer's latest commit; no `HEAD`, so uncommitted
      edits count too), then run the test command yourself: all pass, none skipped. Anything
      listed, failing, or skipped → back to the implementer; no review until it's clean.
   d. `review-package BASE HEAD` (BASE = the commit recorded **before** the test-writer, so the
      tests are reviewed too — never
      `HEAD~1`, which drops all but the last commit of a multi-commit task) → dispatch the
      **task reviewer** (template) with the brief, report, and package paths, the SAFEGUARDS
      lines, and the verbatim global constraints.
   e. If the reviewer reports spec ❌, quality issues, or safeguards ❌ or ⚠️: dispatch a **fix
      subagent** for Critical/Important findings (implementer contract: re-run the covering tests,
      name them, report command + output + SAFEGUARDS; tests stay untouched) → **c2 again** →
      re-review. A finding in the tests themselves goes to the test-writer instead (then c2 with
      its new commit). **Safeguards:** an undisclosed weakening (❌) is undone, never kept. A
      disclosed one (⚠️) is undone too (a skipped hook: run it now and fix what it finds) -- unless
      undoing it would change behavior the plan didn't decide: then it's the human's call
      (`STATUS: AWAITING_HUMAN`). Log each as `Task N: safeguards undone: <item>` or `Task N:
      safeguards accepted: <item>`; every later review gets those as settled, and an accepted one
      is never asked about again. Repeat until spec ✅, quality approved, and safeguards ✅.
      **Same root cause three rounds running:** when three consecutive review rounds on this task
      trace to the same root cause, stop patching -- append `STATUS: AWAITING_HUMAN task N: <the
      cause>` and give the human a decision-ready design choice (`approval-block.md`, Every ask is
      decision-ready) instead of another patch.
   e2. **Adversarial review (tasks with tests; NOT_TESTABLE skips to f) -- at most 3 rounds.**
      Note `git status --porcelain` and HEAD, then dispatch the **adversarial reviewer**
      (template) with the brief, the verbatim global constraints, a fresh `review-package BASE
      HEAD`, the test files and command, the SAFEGUARDS lines, and earlier rounds'
      counterexamples. Its own **SAFEGUARDS** output line is not a counterexample -- no
      adjudication, no round count: `undisclosed` → undo it as in e, in any round, before the rules
      below. Afterwards the
      status and HEAD must be unchanged -- remove anything it left behind. It returns CLEAN (with
      what it tried) or confirmed counterexamples. **You adjudicate each one:** grounded in the
      brief? One that rests on input or behavior the brief doesn't mention, or that conflicts with
      the plan, is the human's call (as for a plan-mandated finding). Confirm its severity against
      the template's definitions; unsure → Important. Log every round:
      `Task N: adversarial round K: clean` or `... K: <n> counterexamples (<C>C <I>I <M>M)`.
      - **CLEAN** → f -- unless a counterexample is still open (it couldn't be a test): then the
        round-3 split below decides.
      - **Counterexamples in rounds 1–2** → the **test-writer** writes one failing test per
        counterexample, with its exact input (pass the counterexample blocks); a2's red check must
        fail. A test that passes on the exact input means the case wasn't real -- drop it; one that
        doesn't use the exact input goes back to the test-writer; one that can't be a test stays
        open. Then the implementer fixes it → **c2** → re-review as in e → next round.
      - **Round 3 counterexamples are not fixed.** Any Critical/Important → stop this task: append
        `STATUS: AWAITING_HUMAN task N: open counterexamples` and show them beside the brief.
        Only Minor → accept: log `Task N: minor counterexamples accepted: <list>`, point the final
        review at them, then f.
      - **After the human answers** (`RUN: resume`): the round count doesn't reset. Apply their
        call -- fix it once (test-writer → implementer → c2 → re-review) or accept and log -- then
        carry on where you stopped: in rounds 1–2, the round's other counterexamples, then the next
        round; at round 3, f.
   f. Append one line to the ledger: `Task N: complete (commits <base7>..<head7>, review clean)`.
4. **After all tasks:** dispatch the final whole-branch review via `/code-review` on the most
   capable model, with `review-package MERGE_BASE HEAD` (MERGE_BASE = `git merge-base main HEAD`)
   and every `safeguards accepted` ledger line, so nothing weakened ships unseen.
   Fix findings with ONE fix subagent carrying the complete list (not one fixer per finding).
5. **After `STATUS: DONE`, offer learnings** (`learnings.md`): queued agent lessons (e.g. reviewer
   findings that recurred across tasks) and any correction the user made at acceptance, in one
   message, each numbered with its evidence and what it would change; the user answers per item.
   Then **finish the branch** via ship-it / wrap-it.

---

## Model selection (always specify the model when dispatching)

Use the least powerful model that can do each role — an omitted model inherits your (expensive)
session model and silently defeats this.

- **Test-writer:** Opus or Fable, never Sonnet (owner decision, 2026-10-20).
- **Adversarial reviewer:** standard tier or above -- finding a real break takes reasoning.
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

## Handling subagent status

- **DONE:** run c2, then generate the review package (BASE = recorded before the test-writer) →
  dispatch reviewer.
- **DONE_WITH_CONCERNS:** read the concerns first. Correctness/scope → address before review.
  Observations → note and proceed.
- **NEEDS_CONTEXT:** provide the missing context, re-dispatch.
- **BLOCKED:** assess — context problem → add context, same model; needs more reasoning →
  re-dispatch on a more capable model; too large → split; plan is wrong → escalate to human.
  **Never** ignore an escalation or retry the same model with no change.
- **The test-writer** gets the same handling for NEEDS_CONTEXT and BLOCKED, but stays on Opus (or
  Fable): if it still can't write the tests with more context or a smaller task, escalate to the human.

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
  implementer writes the full report there and returns only status/commits/test-summary/concerns/
  safeguards.
- **Reviewer inputs:** brief path + report path + review-package path + the task's SAFEGUARDS lines
  (and accepted items) + verbatim global constraints.
- Fix dispatches append their fix report (with test results) to the same report file.

## Durable progress (survives compaction)

Conversation memory doesn't survive compaction; controllers that lost their place have
re-dispatched entire completed sequences — the most expensive failure observed.

- At start: `cat "$(git rev-parse --show-toplevel)/.make-it/sdd/progress.md"`. Tasks marked
  complete there are DONE — resume at the first unmarked task; do not re-dispatch.
- **Arm the run:** append `RUN: plan=<plan-path> tasks=<N>` before dispatching the first task.
  (After a compaction/resume on an already-armed run, append `RUN: resume` instead.) Then
  register the ledger so the gate finds it even when the session started in another folder
  (a worktree, another repo): `python3 ~/.claude/make-it/sdd/scripts/sdd-gate register
  "$(git rev-parse --show-toplevel)/.make-it/sdd/progress.md"`. Run it from the repo or
  worktree that holds the ledger; registering twice is harmless.
- On a clean review, append `Task N: complete (commits <base7>..<head7>, review clean)`.
- **Release the run** by appending exactly one of: `STATUS: DONE` (final review clean),
  `STATUS: BLOCKED <why>` (cannot proceed), or `STATUS: AWAITING_HUMAN <what you need>` (a
  question only the user can answer — write it BEFORE you ask, and ask it
  readable cold: its title, what waits and why, 2-4 named answers, a batch as one grouped line, a high-stakes item never batched (`approval-block.md`, A list of asks)). When the user has answered,
  append `RUN: resume` to re-arm.
- The ledger is the recovery map — trust it and `git log` over recollection after compaction.
- `git clean -fdx` destroys the ledger (git-ignored scratch); recover from `git log`.

### The gate (Stop hook)

A rule in this document is advice the controller can forget mid-run. `sdd/scripts/sdd-gate` is a
**Stop hook**: while the ledger holds an armed `RUN:` with no later `STATUS:`, any attempt to end
the turn is refused (exit 2) with a reminder of the next checkpoint and the escape hatches above.
It checks the ledger in the session folder's repo plus any registered ledger whose path appears
in this session's transcript (so another session's run never blocks you). It is a no-op with no
armed ledger, so it is safe to leave installed globally.
Waiting is not stalling: while a background agent this session launched hasn't reported back
(up to 2 hours after launch), ending the turn to wait for its notice passes without a nudge and
doesn't count toward the circuit breaker.
Circuit breaker: after 3 nudges with no new `Task N: complete`, the gate records that in the
ledger and releases — a stuck controller is handed back to the human, never looped forever.

Install once (user-level `~/.claude/settings.json`):

```json
"Stop": [
  { "hooks": [ { "type": "command",
                 "command": "python3 ~/.claude/make-it/sdd/scripts/sdd-gate",
                 "timeout": 5 } ] }
]
```

---

## Red flags — never

- Start implementation on main/master without explicit consent (work on a branch/worktree).
- Skip task review, or accept a report missing any verdict (spec, quality, and safeguards all required).
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
