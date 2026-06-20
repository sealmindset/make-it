---
name: debug-it
description: Structured debugging workflow that kills assumption-tunneling. Reproduce the failure against ground truth (CVR/Playwright for UI, logs/repro scripts for backend), diagnose from BOTH the "something is missing" and "we're doing too much" hypothesis families, present two complete solutions as a tired-friendly decision card, implement the smallest reversible fix, and verify against the same reproduction. Use when a bug, error, broken feature, or failing test needs diagnosis -- especially after one or more fix attempts have already failed.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Skill
---

<objective>

Find the *real* cause of a bug fast, propose two complete fixes, and ship the smallest one
that structurally can't recur. Optimized for a tired, multi-tasking operator who needs to make
a good call in ten seconds.

This skill exists to kill ONE failure mode: debugging loops that only ever ask "what's
*missing*?" and keep *adding* code, when the true cause is that the system is doing *too much*.

</objective>

# /debug-it -- debugging that doesn't loop until 1AM

> A project may ship its own `/debug-it` that shadows this one (e.g. wired to a specific
> capture tool, live-system safety rails, or a ship ritual). Inside such a repo, the project
> version wins. This is the generic core.

---

## The one failure mode this skill exists to kill

Most painful debugging loops die the same way: **every hypothesis assumes something is
*missing*** -- "we skipped a step", "we need another guard", "the platform needs us to do X
first" -- so every fix *adds* code. When the true cause is the opposite (you're doing **too
much**: a double-action, an over-eager safeguard, a re-architecture where a one-line
workaround suffices, or the platform already handles the thing), an all-additive loop will
**never** find it. It just stacks band-aids and the symptom mutates.

The cure is forced **hypothesis diversity** plus a **circuit-breaker** that flips your lens
after repeated failures. Both are baked into the workflow below -- do not skip them.

---

## Hard rules

1. **Evidence before theory.** Read the logs / capture / DOM / failing assertion FIRST.
   Build a "what actually happened" fact list that is separate from your guesses. Never
   propose a cause you haven't grounded in an observation. Verify everything; assume nothing.
2. **Reproduce before you fix.** A fix you can't tie to a reproduction is a guess. Isolate
   the *exact* failing line / state / DOM node, not the general area.
3. **Never reproduce against a live or irreversible system without explicit per-run
   approval.** Prefer a captured session, a rehearsal/staging target, or a mock. If the only
   repro path mutates production or does something you can't undo, STOP and ask.
4. **Both families, every time.** You must generate at least one *additive* and one
   *subtractive* hypothesis before proposing solutions (see the table). No exceptions.
5. **Smallest reversible fix wins.** A pragmatic workaround beats a redesign unless the
   redesign is the only thing that prevents recurrence. Say which you chose and why.
6. **Verify against the SAME reproduction.** The bug is not fixed until the original repro
   passes and the fix structurally prevents recurrence.
7. **Only ask what changes your actions.** Interview to remove real ambiguity, then proceed
   and state your assumptions. Don't stall on questions whose answer wouldn't change the fix.

---

## Hypothesis families (you must pull from both)

| Family | Mental prompt | Examples |
|--------|---------------|----------|
| **Additive** ("too little") | What step / check / data / permission / await is missing? | unhandled case, missing await, absent null-guard, skipped setup call, race we didn't wait for |
| **Subtractive** ("too much") | What are we doing that we shouldn't? What does the platform already do? | double-fired action, over-eager safeguard rejecting a valid state, retry that creates a duplicate, re-implementing something the framework/host handles, a redesign where a cleanup/workaround suffices |

When a loop has only ever explored one family, the answer is almost always in the other one.

---

## Workflow

### 0. Intake & interview
- Get the failure: from the user's message, from the conversation scrollback, or from logs
  they point you at. Restate the symptom in one sentence to confirm you have the right bug.
- Clarify ONLY what changes your actions (which environment, which user/case, expected vs
  actual). If a couple of clarifications are needed, ask them and wait. Otherwise proceed and
  state assumptions explicitly.

### 1. Reproduce & isolate
- **UI / browser bug:** drive it with Playwright (the `webapp-testing` skill) or a session
  capture/replay tool if the project has one. Capture the DOM, console, network, and the
  exact click/element that misbehaves.
- **Backend / logic bug:** write the smallest script or test that triggers it; capture the
  stack/log lines.
- **Intermittent bug:** reproduce N times; note the conditions that flip it.
- Pin the *exact* failure point. "Somewhere in submit()" is not isolated; "the second
  click handler fires a duplicate POST" is.
- Respect Hard Rule #3 -- safe target only, or ask.

### 2. Evidence-first diagnosis
- Write the **Facts** list (observed) and, separately, the **Open questions** list.
- Map facts to candidate causes. Explicitly note which family each candidate belongs to.

### 3. Two complete solutions -> decision card
- Produce **>=2 complete solutions**, drawn from different families (>=1 additive, >=1
  subtractive -- Hard Rule #4). "Complete" means each has: root-cause statement, the actual
  change, blast radius, and *why it can't recur*.
- Present as a **tired-mode decision card** (format below). Recommend the best with a
  one-line reason. Invite the user to pick or supply their own.
- Default recommendation leans to the smallest reversible fix (Hard Rule #5).

### 4. Implement
- Apply the chosen fix. Keep it minimal and reversible. Match surrounding code style.
- If the project has a ship/deploy ritual, follow it only when the user asks to ship.

### 5. Verify (hard guarantee)
- Re-run the **exact** reproduction from step 1. It must now pass.
- Add a regression guard (test / assertion / invariant) so this specific failure can't
  silently return.
- State plainly: reproduced OK, fixed OK, regression guard OK -- or what's still red.

### 6. Circuit-breaker (anti-loop)
- Track each fix attempt and its family. **After 2 failed attempts in the same family,
  HARD STOP** and force a lens-flip:
  > "We've tried *adding* things twice and it still fails. Per /debug-it, the cause is
  > probably that we're doing **too much**, not too little. New hypotheses, subtractive
  > family only:" -- then generate them.
- Never start a 3rd same-family attempt without doing the flip first.

### 7. Capture the lesson
- One-line takeaway, especially if the root cause was a subtractive/over-engineering miss.
  If the project has a memory or notes convention, record it so the pattern is recognized
  next time.

---

## Tired-mode decision card (output format)

```
BUG   -- <one sentence, plain English>
CAUSE -- <root cause in one line, grounded in an observed fact>

A) <name>  [additive | subtractive]
   What: <the change, one line>
   Feels like: <analogy, only if it's genuinely complex>
   Risk: <blast radius, one line>

B) <name>  [additive | subtractive]
   What: <the change, one line>
   Feels like: <analogy, if needed>
   Risk: <blast radius, one line>

I'd pick <A/B> because <one line -- usually smallest reversible fix that can't recur>.
Reply A, B, or tell me your own.
```

Keep analogies for when something is genuinely hard to reason about cold. Don't pad simple
bugs with metaphors.

---

## Canonical worked example (the lesson, distilled)

Symptom: a one-click "submit" action kept producing a phantom duplicate/incomplete record.
The loop spent a night generating only additive hypotheses ("a step is missing, add a
cleanup procedure, add another guard, wait for another element"). The real causes were
subtractive: the click handler **double-fired** (fix: click once), and the leftover record
just needed a **pragmatic cleanup** (delete it *after* the real submit) instead of
re-architecting the whole flow. A single forced subtractive hypothesis on attempt #1 would
have ended it in minutes. That is what this skill guarantees.
