# Learnings Reference (LEARNINGS.md)

Every generated project keeps a `LEARNINGS.md` in its root, and its `CLAUDE.md` imports it
(`@LEARNINGS.md`). Every assistant and every subagent working in the project reads it on every
turn, so a correction made once stays made. This is Helix gate 4: feedback at the verification
checkpoint becomes a durable rule instead of something re-learned each session.

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

## Ask first: one plain yes/no per learning

Never write a learning without a yes. Ask in plain language; the stored line may be technical,
because assistants read it.
- **User corrections:** ask right after the fix is verified: "Want me to remember this for next
  time? *<plain one-line version>*"
- **Agent lessons:** don't interrupt the work. Queue them and ask at the end of the work item or
  in /wrap-it: one message, one numbered yes/no line per lesson, so the user can answer "yes to
  1 and 3".
- **No:** drop it, and don't offer the same lesson again this session.

## Format

```markdown
# Learnings

Rules this project has learned. Every assistant working here follows them.
Newest first, one line each.

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
- **Capture points:** /try-it explore-support, /resume-it after any work, /subagent-it finish, and
  /wrap-it save-progress (the sweep for anything still queued).
