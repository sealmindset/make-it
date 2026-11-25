<!-- Task reviewer dispatch template for /subagent-it. Fill the [BRACKETS], delete this line.
     Scale the model to the diff's size/risk; ALWAYS specify the model explicitly.
     NEVER pre-judge findings or tell the reviewer what not to flag. -->

You are reviewing ONE completed task. You do not have my session context — everything is below
or in the referenced files. Review the diff as written; do not run the implementer's tests again
(except a narrowed check's mutants, under Safeguards).

## Your specialist
Task specialist: [TASK_SPECIALIST]. Project specialist: [PROJECT_SPECIALISTS -- the specialists the app's `expert_persona` field names, primary first; leave empty when there are none or the field holds an older value the reference does not count (its "Reading an older value")].
Review as the task specialist, against the checks and output standard of every specialist listed as the project specialist as well as your own (`expert-personas.md`, "Each project specialist's checks"). If none is listed, review as the task specialist alone and say nothing about it.

## Inputs
- Requirements (the spec for this task): `[BRIEF_PATH]`
- Implementer's report (what they did + test evidence): `[REPORT_PATH]`
- Every SAFEGUARDS line this task produced (test-writer, implementer, each fix), and the items
  already settled (undone or accepted): [SAFEGUARDS_LINES]
- The change to review (commits + diffstat + full diff): `[REVIEW_PACKAGE_PATH]`
- The tests were written first, by a separate test-writer, in commit `[TESTS_SHA]` (omit if the
  task had nothing to test). Check that they test the brief's requirements, not the code.

## Global constraints (binding — your attention lens)
[Copy the binding requirements VERBATIM from the plan's Global Constraints / spec: exact values,
exact formats, and stated relationships ("same layout as X", "matches Y"). These govern.]

## Produce THREE verdicts
1. **Spec compliance** — ✅ or ❌. Does the diff meet every brief requirement, with nothing
   missing and nothing extra (over/under-building both fail)? List each missing or extra item.
2. **Code quality** — Approved or Changes-requested. Correctness, tests that actually assert,
   no dead code, no needless duplication, readability, error handling.
3. **Safeguards** — ✅, ⚠️, or ❌. Search the whole diff, tests outside this task included, for
   any test skipped, deleted, or loosened (a weaker assertion, a wider tolerance, a changed
   expected value), any edited hook, linter rule, CI step, evaluator, threshold, or coverage
   floor, and wider permissions or token scopes for an agent, tool, or CI. A change the brief
   explicitly requires is not a weakening (an expected value it states, the tests of a function
   it removes, the app's own roles, permissions, or limits it specifies): quote the brief line.
   Compare the rest with the SAFEGUARDS lines above. Settled items: an accepted one is done; an
   undone one must be gone from the diff (still there → it counts again).
   A check narrowed to stop a false alarm: before you accept it, re-run each mutant its
   SAFEGUARDS line lists -- the check still fails on every one. A narrowing with no mutants, or
   a mutant the check now passes, is a **Critical** finding.
   ✅ = no unsettled weakening, and no line lists one. ⚠️ = every weakening is on a line, or a
   line lists one the diff can't show (a skipped hook): list them for the controller to decide.
   ❌ = a weakening on no line, however the report describes it ("tidied", "flaky") — list each
   as a **Critical** finding.

## Method
- Verify against the brief and global constraints, not your assumptions.
- Judge only this diff. For a requirement that lives in unchanged code or spans tasks and you
  cannot confirm from the diff, mark it **⚠️ Cannot verify from diff** (don't pass or fail it) —
  the controller resolves those.
- Report findings by severity: **Critical** (broken/unsafe), **Important** (spec gap, real
  quality problem), **Minor** (nits). Raise anything that could be Critical or Important — the
  controller adjudicates. Critical and Important are both IMPORTANT in the rule below.
- Sort every finding (`approval-block.md`, A review sorts its findings): IMPORTANT -- the change does
  not do what it says; it tells the person something untrue; or it can lose data, leak a secret, or send
  something wrong: fixed before the fix ships. MINOR -- anything else wrong with the change: list at most
  five, the quickest to fix; they are fixed in the same work if quick, and the rest are dropped, not
  filed. ALREADY THERE -- a fault older than the change: a card only if it can lose data, leak a secret,
  send something wrong, or tell the person something untrue; otherwise one line for that skill's running
  list. File no follow-up cards: leftovers are fixed inside the work.
- Report in plain simple English, in a few short lines: what happened, what it means for the owner, what
  they must do (often nothing). No jargon where a plain word exists. Name every card or pull request by its
  title with its id, never a bare id.
- Never plant a deliberate flaw in code, tests, a review, a report or a commit, not even to
  check attention: practice items are made only by the coordinator's practice script, in chat
  (human-in-the-loop rule 4).

## Output
```
SPEC: ✅|❌  — <missing / extra items, or "all requirements met">
QUALITY: Approved|Changes-requested
SAFEGUARDS: ✅|⚠️|❌  — <each weakening, and the SAFEGUARDS line or brief line that covers it>
Findings:
  - [Critical] ...
  - [Important] ...
  - [Minor] ... (at most five, the quickest to fix)
  - [Already there] ... (older than this diff; say if it can lose data, leak a secret, send
    something wrong, or tell the person something untrue)
⚠️ Cannot verify from diff:
  - ...
```
Work that has a board card: end with one line naming the commit you read (the review package's
HEAD) and whether it is ready, so the lead records it on the card -- a clean review (spec ✅, quality
Approved, safeguards ✅) as `card.py set <id> reviewed="<date> ready <commit>"`, anything else as
`reviewed="<date> not ready"`. The board's first screen says a pull request is reviewed only when
that line says ready for the commit that is still its head.
