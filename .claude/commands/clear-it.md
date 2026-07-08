---
name: clear-it
description: Checkpoint your session into handoff.md, then clear context with confidence. Use mid-session when context is getting long and confused, or before stepping away. Run /clear-it, then /clear -- the next session picks up cleanly from handoff.md.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
---

<objective>

Fight context rot. Long sessions accumulate dead ends, messy debugging detours, and bad
assumptions -- and the model keeps replaying that broken loop, making the same mistakes.
The cure is a clean reset: capture what actually matters into `handoff.md`, then clear
the context.

/clear-it writes a `handoff.md` at the project root with exactly six sections:

1. **Goal** -- what we are ultimately trying to accomplish
2. **Current State** -- where things stand right now (working? broken? partially done?)
3. **Active Files** -- the files being worked on, with a one-line note each on why
4. **Changes Made** -- what has been changed this session (and whether committed)
5. **Failed Approaches** -- dead ends, disproven hypotheses, and bad assumptions, with WHY
   each failed -- so the next session does not repeat them
6. **Next Steps** -- the concrete next actions, in order, starting with the one that was
   in progress

This is a LIGHTWEIGHT checkpoint, not an end-of-day shutdown:
- It does NOT stop containers, update CHANGELOG.md/TODO.md, or commit code (that is /wrap-it)
- It works in ANY project, not just /make-it apps -- context rot is universal
- It also serves as a save point before stepping away for a long period; /resume-it (or any
  fresh session reading handoff.md) continues from it

</objective>

<critical_insight>

**The most valuable content lives ONLY in the current conversation context -- capture it
before it is cleared.**

Git can reconstruct what changed. Nothing on disk records which hypotheses were already
tried and disproven, which assumptions turned out to be wrong, or what the plan was.
That knowledge exists only in this session's context right now. Section 5 (Failed
Approaches) is the whole reason this skill exists -- be brutally honest and specific there.
"Tried X, failed" is useless; "Tried X because we assumed Y; it failed because Z -- Y is
false, do not retry" saves the next session an hour.

Write from the conversation FIRST, then use git/disk only to verify and fill gaps.

</critical_insight>

<process>

<step name="gather">

**Gather silently -- do not interrogate the user unless the session context is genuinely empty.**

**1. From the current conversation (primary source):**
- The original goal and any scope changes since
- What was attempted, what worked, what failed and why
- Assumptions that were made and later disproven
- The step that was in progress when /clear-it was invoked

**2. From disk (verification and gap-filling):**

```bash
git status --short 2>/dev/null
git log --oneline -15 2>/dev/null
git diff --stat 2>/dev/null
git branch --show-current 2>/dev/null
```

**3. Make-it context, if present (read silently):**
- `.make-it-state.md`, `.make-it/app-context.json`, `TODO.md` -- fold anything relevant
  into the six sections. If absent, this is not a make-it project; proceed anyway.

**4. If context is thin** (e.g. /clear-it invoked at the very start of a session), ask the
user ONE question: "What should the handoff say you were working toward and what's next?"
Do not fabricate content for sections you have no evidence for -- write "None this session"
instead.

</step>

<step name="archive">

**Preserve the previous handoff before overwriting.**

If `handoff.md` already exists at the project root, prepend its full content to
`.handoff-history.md` under a heading with the current date, newest first:

```markdown
## Archived <YYYY-MM-DD HH:MM>

<previous handoff.md content>
```

Failed-approach knowledge must never be silently lost: if the old handoff's **Failed
Approaches** section lists dead ends still relevant to the current goal, CARRY THEM
FORWARD into the new handoff.md (marked `(carried forward)`), not just the archive.

</step>

<step name="write">

**Write `handoff.md` at the project root:**

```markdown
# Handoff -- <project name>
_Written <YYYY-MM-DD HH:MM> by /clear-it. Read this file in full before continuing work._

## 1. Goal
<What we are ultimately building/fixing, in 1-3 sentences. Include acceptance criteria if known.>

## 2. Current State
<Where things stand: what works, what's broken, what's half-done. Branch name,
uncommitted-changes status, whether the app/tests currently run.>

## 3. Active Files
- `path/to/file` -- <why it's in play>
- ...

## 4. Changes Made
- <change> (<committed as `abc1234` | uncommitted>)
- ...

## 5. Failed Approaches -- DO NOT RETRY
- **<approach>** -- assumed <assumption>; failed because <evidence>. Conclusion: <what this rules out>.
- ...

## 6. Next Steps
1. <the step that was in progress -- with enough detail to resume mid-thought>
2. <subsequent steps in order>
```

Rules:
- Facts only -- every claim traceable to the conversation or a command you just ran.
  No speculation dressed as state.
- Specific over complete: five precise bullets beat twenty vague ones.
- Plain language; the reader may be a fresh session with zero context OR the user
  themselves days later.
- Empty section -> write "None this session", never delete the section.

</step>

<step name="handoff">

**Confirm and hand the user the reset procedure:**

```
Checkpoint saved to handoff.md

  Goal: <one line>
  Failed approaches captured: <N>
  Next step on deck: <one line>

To reset context now:   type /clear, then start with "Read handoff.md and continue"
To step away instead:   you're safe to close this session anytime
To resume later:        /resume-it picks up handoff.md automatically
```

Keep it to roughly that. Do not start new work, do not suggest features, do not
re-explain what was saved.

</step>

</process>

<guardrails>

- NEVER commit, push, stop containers, or modify code -- this skill only writes
  `handoff.md` and `.handoff-history.md`.
- NEVER overwrite an existing `handoff.md` without archiving it first.
- NEVER pad Failed Approaches with filler -- an inaccurate dead-end list is worse than
  none, because the next session will trust it.
- If the project root is unclear (no git repo, no obvious markers), ask the user where
  to write the file rather than guessing.

</guardrails>
