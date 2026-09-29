---
name: backlog-it
description: A file-based Epic→Story→Task backlog board for this project -- markdown cards with frontmatter and a rendered BOARD.md. Captures ideas and bugs (card first, then batched questions), runs a bug queue (Reported → Cause found → Fix ready → Live → Checked) with up to N parallel non-overlapping fix lanes, and recalls any card as an editable prompt with `start <id>`. Also groom, reconcile, and dispatch. Use when the user types /backlog-it, or asks to track, list, start, or close a work item, epic, story, task, or bug.
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

<!-- User invoked: /backlog-it $ARGUMENTS -->

<objective>

Keep the project's work on a board that lives next to the code: every idea and bug becomes a
card before anything else happens, the board always shows what's being fixed and what's next,
and any card can be pulled back in and run as a prompt.

Full doctrine (settings, layout, frontmatter, bug queue, lanes, subcommands):
`~/.claude/make-it/references/backlog-board.md`.

</objective>

<execution_context>

@~/.claude/make-it/references/backlog-board.md
@~/.claude/make-it/references/parallel-dispatch.md
@~/.claude/make-it/references/worktree-workflow.md

</execution_context>

# /backlog-it -- the project board

**Core principle:** the card comes first. A report is never lost to a question, and every other
skill reads the same board.

---

## Step 1 -- Load settings

1. Read `.claude/backlog-it.json` from the project root if it exists. Resolve:
   `BOARD` = `$BACKLOG_DIR`, else `board`, else `.claude/backlog` (expand `~`, resolve relative
   paths from the project root); `PROJECT` = `project`, else the project folder's name;
   `LANE_CAP` = `lane_cap`, else 3; `SERIAL` = `serial`, else `[]`.
2. Export `BACKLOG_DIR=$BOARD` for the helpers.
3. **No board yet?** Say in one line that you'll set one up, then create `$BOARD/items/`, a
   `$BOARD/.gitignore` containing `.slack-webhook`, and render an empty `BOARD.md`. Write
   `.claude/backlog-it.json` only if the user chose a non-default setting. Don't ask about
   Slack -- it's optional and off until a webhook exists.

## Step 2 -- Route the argument

| Argument | Action (see the reference) |
|----------|----------------------------|
| *(none)*, `board` | Print `BOARD.md` compactly |
| `list` / `show` | Filter / show a card |
| `epic`, `story <epic>`, `task <parent>` + idea | Capture (Step 3) |
| `bug <text>`, or text whose first word isn't a subcommand | Capture as a bug (Step 3) |
| `start <id>` | Recall → show the editable prompt → run on the user's go |
| `move`, `stage`, `done` | Update the card |
| `reconcile`, `groom`, `groom move/unpin` | Check cards against the code / propose an order |
| `dispatch [--dry-run]` | Fill free lanes (Step 4) |
| `undo` | Revert the last board commit (board in its own repo only) |

Ids are case-insensitive (`e02` → `E02`). Next id = highest existing + 1.

## Step 3 -- Capture (card first, then questions)

1. Write the card with what's known: type, title, category, priority, the understanding body,
   unknowns under *Open questions*. A bug goes under the Bugs epic (create it on first use) as
   `type: breakfix`, `status: backlog`, `stage: Reported`.
2. Regenerate and sync (Step 5).
3. In the same reply: one line with the id and its place in line ("E07-S3, #2 in line"), then
   **every** open question batched in one AskUserQuestion -- only questions whose answer changes
   the fix or its order. Check what you can check yourself instead of asking.
4. Record answers on the card under `## Answers`.

## Step 4 -- Lanes and dispatch

Pick from the top of the line, bugs first. Fill up to `LANE_CAP` lanes. Two cards share the floor
only if they touch **no common source files** and **no common data**. At most one lane per
`SERIAL` category; `stakes: critical` cards are never auto-picked. Dispatch the lanes with
`/dispatch-it` -- one agent per card, each in its own worktree, each running the `/debug-it`
method for bugs. Gather every lane's questions into one message. Shipping stays serial: one PR
through CI and deploy at a time.

## Step 5 -- After every change

1. Bump `updated:` on each touched card.
2. `python3 ~/.claude/make-it/backlog/bin/regen-board.py "$BOARD" --project "$PROJECT"`
3. Sync: board in its own repo → commit + push there. Board inside the project → stage only the
   board's paths (never the default branch).
4. Notify (no-op without a webhook): `~/.claude/make-it/backlog/bin/slack-notify.sh started <id>
   "<title>" "<category>" "<priority>"` on start, `... done <id> "<title>"` on done, `... raw
   "<text>"` for stage changes. Never block on Slack.

---

See `backlog-board.md` for the frontmatter schema, the stage table, the reconcile ladder, groom
rules, and how several projects share one board.
