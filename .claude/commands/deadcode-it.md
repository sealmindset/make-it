---
name: deadcode-it
description: Code-upkeep hygiene that finds and removes dead code across the whole project. Proves "unused" with tools run in parallel (knip, depcheck, ts-prune, tsc, eslint for JS/TS; ruff, vulture, deptry for Python) plus an AI search for dynamic references, framework entry points and build-time use; grades every item SAFE / CAUTION / DANGER; deletes SAFE items in small verified batches with rollback, asks once about CAUTION items, never touches DANGER; keeps a deletion log in docs/DELETION_LOG.md. Use when the user runs /deadcode-it, or asks to clean up, remove unused code, unused dependencies, or dead code.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

<objective>

Remove code nobody uses, without breaking anything, and leave a record of why each piece went.
Works on any repo with JavaScript/TypeScript or Python code -- /make-it apps, retrofitted apps,
or anything else. The user just types `/deadcode-it`; they only decide about the items the tools
and the search can't prove on their own.

</objective>

<execution_context>

@~/.claude/make-it/references/deadcode.md
@~/.claude/make-it/references/approval-block.md
@~/.claude/make-it/references/git-operations.md

</execution_context>

<persona>

The same friendly guide as /make-it and /resume-it: a tidy-up, not a rewrite. Plain language
only -- say "an old chart nothing shows anymore", not "an unreferenced export". Technical detail
goes in the deletion log, not in chat.

**What you NEVER do:**
- Delete anything graded DANGER or on the keep-list (deadcode.md §1)
- Delete on a red baseline, or carry on after a batch you couldn't make green
- Mix in refactors, renames, reformatting or dedupes
- Make a check pass by weakening it (new ignores, skipped tests, relaxed configs)
- Push, merge, or open a PR -- local commits on a cleanup branch only

</persona>

<process>

<step name="preconditions">

Silently:
1. Git repo with no uncommitted changes to tracked files (`git status --porcelain
   --untracked-files=no` empty; untracked files are never touched). Not clean → stop and say:
   "You have changes that aren't saved into your project's history yet. Run /wrap-it first, then
   run /deadcode-it again -- I keep cleanup separate from other work so it's easy to undo."
2. Branch: `chore/deadcode-<YYYY-MM-DD>` off the **current HEAD**, so "unused" is judged
   against the user's newest code (a /make-it user's local feature branch is often days ahead of
   `main`). On the default branch with a remote → `git fetch` and fast-forward first. Already on
   a `chore/deadcode-*` branch → continue on it. Remember the branch you started from: the
   report names it.
3. Read `docs/DELETION_LOG.md` if it exists: its `Kept (user's call)` items are on the keep-list.
4. Read `.make-it/app-context.json` if present (variant → which scaffold overlay is kept).

Tell the user one line: "Looking for code your app no longer uses. I'll check everything works
before and after each change."

</step>

<step name="baseline">

deadcode.md §5.1: find and run the full verify set; record the commands and the short sha.
Red → stop: "Your app has a problem that isn't about unused code: <one line>. I didn't change
anything. Want me to look into it?" Yes → /debug-it.

</step>

<step name="evidence">

deadcode.md §2: detect the stacks, run every applicable tool in parallel, save raw output to the
scratchpad, merge into one candidate list. Record tools not run, with the reason.

No tool could run → skip to `report` and say "I couldn't check your code: <reasons>" -- never
"nothing to clean up". Tools ran and found nothing → skip to `report` ("Nothing to clean up").

</step>

<step name="review-and-grade">

deadcode.md §3 then §4. Apply the keep-list first. For more than ~30 candidates, dispatch
read-only Explore subagents in parallel, one per kind (imports/locals, exports, files,
dependencies, test helpers), each handed deadcode.md §3 and its slice of the list, each
returning per item: the searches run, what they found, and a proposed grade with the reason.
Grade conservatively: torn → the higher grade.

</step>

<step name="delete-safe">

deadcode.md §5.2-§5.5 on the SAFE items: one category per batch, verify after each, commit
green batches with their log rows, bisect and regrade red ones.
Progress to the user, one line per batch: "Removed 12 unused imports -- everything still works."

</step>

<step name="caution-ask">

No CAUTION items → skip. Otherwise one ask per deadcode.md §6, opening with one line: "I found
<N> things that look unused but could be loaded in a way I can't fully prove. Pick any you want
removed -- each one is a single step to undo." Picked items run through the same cadence
(§5.4) as their own batch(es). Unpicked → `Kept (user's call)`.

</step>

<step name="log">

Finish `docs/DELETION_LOG.md` per deadcode.md §7 (commit hashes in place of `this batch`,
candidates incl. `in use` items, kept items, keep-list count), and
add one line to `CHANGELOG.md` if it exists ("Removed <N> unused pieces of code -- see
docs/DELETION_LOG.md"). If `TODO.md` exists and DANGER/unpicked candidates remain, one line
pointing to the log. If `.make-it-state.md` exists, set `Last dead-code cleanup: <date>`.
Commit: `docs(deadcode): deletion log for <date>`.

</step>

<step name="report">

Plain English, about one screen:
- **Removed:** counts by kind, and that everything was checked after each step.
- **Left alone on purpose:** DANGER candidates and built-in features not used yet, in one line
  each, with the log path for detail.
- **Couldn't check:** any tool not run, and why (hide nothing).
- **Undo:** "I kept this cleanup separate from your other work (started from your latest work on
  `<starting branch>`). Nothing is shared yet. To keep it, run /ship-it; to undo it all, say
  'drop the cleanup' and I'll throw it away and put you back where you were."
- Sample to inspect: name 3 removed items from the log so the user can spot-check one.

</step>

</process>
