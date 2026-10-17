# Learnings Reference (LEARNINGS.md)

Every generated project keeps a `LEARNINGS.md` in its root, and its `CLAUDE.md` imports it
(`@LEARNINGS.md`). Every assistant and every subagent working in the project reads it on every
turn, so a correction made once stays made: feedback at the verification checkpoint becomes a
durable rule instead of something re-learned each session.

## What becomes a learning

Two sources:
1. **User corrections.** The user checks a result (exploring in /try-it, a /resume-it fix or
   feature, the end of an SDD run) and corrects it, and the correction is a rule that applies
   beyond this one fix. "Show dates like 29 Sep 2026" is a learning; "make this button blue" is
   a one-off.
2. **Agent lessons.** Things learned the hard way in THIS project: a fix that took more than one
   attempt, an approach that failed, an environment gotcha, a reviewer finding that recurred
   across SDD tasks.

Not a learning: one-off tweaks; anything already in `CLAUDE.md`, build-standards.md, or the
scaffold; task status (that goes in TODO.md / .make-it-state.md); secrets, `.env` values, or
personal data (operator-safety.md §1).

## Ask first: one batched, decision-ready ask

Adding a learning is **consequential** (`approval-block.md`): every assistant in the project
follows it from then on, and the undo is one "forget that". So it gets one decision-ready ask,
never a bare "want me to remember this?". Never write a learning without the user's yes --
nothing is added on its own. Ask in plain language; the stored line may be technical, because
assistants read it.

- **One message, every proposed learning numbered.** Each number carries, in a line or two:
  - **the rule** in plain words -- what would be remembered;
  - **the evidence** -- what happened that taught it (the correction the user made, the fix that
    took two tries, the error that was hit);
  - **what it would change** -- what gets done differently next time because of it;
  - **what is unusual** -- if it would replace or narrow a line already in `LEARNINGS.md`
    ("Replace, don't stack", below), quote that line; if it would relax a check or touch sign-in,
    permissions or secrets, say so plainly. Otherwise, nothing.
- **Frame it once, not per item:** anything kept applies to the whole project from now on; any
  line can be removed later with "forget that"; the one thing to check per item is whether the
  rule holds beyond the case that taught it (a one-off is a no). Close with how to answer:
  "yes to 1 and 3", or "none".
- **User corrections:** ask right after the fix is verified -- same shape, usually a one-item list.
- **Agent lessons:** don't interrupt the work. Queue them and ask at the end of the work item or
  in /wrap-it, in the same message as any pending correction.
- The message counts as ONE ask: send it on its own and wait for the answer before asking
  anything else. Only the items the user names are written. Nothing queued -> skip it silently.
- **No** (or not named in the answer): drop it, and don't offer the same lesson again this session.

Example ask -- illustration only, never copy these learnings into a project:

> Two things I'd remember for this project. Anything you keep applies to all future work here,
> and "forget that" removes it later. For each, the thing to check: does it hold beyond today?
>
> 1. **Show dates like "29 Sep 2026", never 2026-09-29.** You corrected the orders page just
>    now. Next time, every new screen gets that format without you asking.
> 2. **Make database updates from inside the app's server box, not from your own computer.** The
>    first try failed because your computer is missing a piece the server has; it worked from
>    inside the server box. Next time I skip the failing step.
>
> Which should I keep -- "yes to 1 and 2", "just 1", or "none"?

## Before writing

- `LEARNINGS.md` or the `@LEARNINGS.md` line in `CLAUDE.md` missing -> add both per build-standards
  S10 first (no extra question), so the yes'd line is actually loaded.
- Not a make-it project (no `.make-it/app-context.json`) and no `LEARNINGS.md` -> skip the offer
  entirely; don't create files or edit the user's `CLAUDE.md` in someone else's repo.

## Format

Header -- copy exactly when creating the file:

```markdown
# Learnings

Rules this project has learned. Every assistant working here follows them.
Newest first, one line each.
```

Example lines -- illustration only, NEVER copy these into a project:

```markdown
- 2026-09-29 -- Show dates as "29 Sep 2026" everywhere, never ISO. (user)
- 2026-09-28 -- Run migrations inside the backend container, not on the host: the host has no DB driver. (agent)
```

- One line: `date -- rule (source)`. The rule is imperative and specific enough to act on; add
  the reason as a short clause when it isn't obvious.
- **Replace, don't stack.** If a new learning repeats, narrows, or contradicts an existing line,
  rewrite that line (with the new date) instead of adding one. Two conflicting rules are worse
  than none.
- "Forget that" / "forget X" from the user: delete the line, no question needed.
- Learnings go in `LEARNINGS.md` only, never directly in `CLAUDE.md`.
- `LEARNINGS.md` is committed with the project: it is shared project knowledge, not local state.

## Wiring

- **/make-it** creates `LEARNINGS.md` (header only) and the `@LEARNINGS.md` import in `CLAUDE.md`
  during Build Phase A.
- **build-standards.md S10** checks both; the /resume-it catch-up scan adds them to older projects
  (header only -- never invent entries).
- **Capture points:** /try-it explore-support, /resume-it after any work, /subagent-it finish
  (after `STATUS: DONE`), and /wrap-it save-progress (the sweep for anything still queued).
