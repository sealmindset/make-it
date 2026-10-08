---
name: backlog-it
description: A file-based Epic→Story→Task backlog board -- markdown cards with frontmatter and a rendered BOARD.md, per project or one personal board used from anywhere. Adds planned work (clarify first), captures ideas and bugs (card first, AI triage, then batched questions), runs a bug queue (Reported → Cause found → Fix ready → Live → Checked) with up to N parallel non-overlapping fix lanes, and recalls any card as an editable prompt with `start <id>`. Also reconcile against the code, groom, groom strategy, and dispatch. Use when the user types /backlog-it, or asks to track, list, start, or close a work item, epic, story, task, bug, or design doc.
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
  - Workflow
---

<!-- User invoked: /backlog-it $ARGUMENTS -->

<objective>

Keep the work on a board: every idea and bug becomes a card, the board always shows what's being
fixed and what's next, and any card can be pulled back in and run as a prompt.

Full doctrine (settings, layout, frontmatter, capture, bug queue, lanes, every subcommand):
`~/.claude/make-it/references/backlog-board.md`.

</objective>

<execution_context>

@~/.claude/make-it/references/backlog-board.md
@~/.claude/make-it/references/parallel-dispatch.md
@~/.claude/make-it/references/worktree-workflow.md

</execution_context>

# /backlog-it -- the board

**Core principle:** a report is never lost to a question, a recalled card always runs on the
user's go, and every other skill reads the same board.

---

## Step 1 -- Load settings

1. Find the settings, first match wins as a whole: the project's `.claude/backlog-it.json`; else
   the project's `.claude/backlog/` with defaults; else `~/.claude/backlog-it.json`; else
   defaults. Resolve: `BOARD` = `$BACKLOG_DIR`, else `board`, else `.claude/backlog` (expand `~`;
   relative paths from the project root); `PROJECT` = `project`, else `<board>/.project`, else the
   project folder's name; `REPO` = `repo`, else the project root; `LANE_CAP` = `lane_cap`, else 3;
   `SERIAL` = `serial`, else `[]`.
2. Export `BACKLOG_DIR=$BOARD` for the helpers.
3. **No board yet?** Say in one line that you'll set one up, then create `$BOARD/items/`, a
   `$BOARD/.gitignore` containing `.slack-webhook`, and render an empty `BOARD.md`. Write
   `.claude/backlog-it.json` only if the user chose a non-default setting. Don't ask about
   Slack -- it's optional and off until a webhook exists.

## Step 2 -- Route the argument

| Argument | Action (see the reference) |
|----------|----------------------------|
| *(none)*, `board` | Print the board compactly |
| `list` / `show` | Filter / show a card |
| `epic`, `story <epic>`, `task <parent>` + idea, `add` | Add planned work -- clarify first (Step 3) |
| `capture <text>`, `bug <text>`, or text whose first word isn't a subcommand | Capture -- card first (Step 3) |
| `start <id>` | Recall → preamble (+ alignment brief if high-stakes) → editable prompt → run on the user's go |
| `move`, `status`, `stage`, `done` | Update the card (`done` posts the end summary) |
| `reconcile [<id>\|all] [--fast\|--deep <id>\|--dry-run\|--dispatch]` | Check cards against `REPO`: code, tests, live |
| `dispatch [--dry-run]` | Follow `PLAN.md`'s next wave, else fill free bug lanes, else start the next safe item (Step 4) |
| `plan [filter] [--apply\|--dry-run]` | Route each card to solo / spike / `/subagent-it` / `/dispatch-it`, in waves → `PLAN.md` (Step 4b) |
| `mode <id> <mode\|auto>` | Choose a card's mode yourself; `plan` keeps it |
| `groom [filter] [--apply\|--dry-run\|--dispatch]` | Propose the burn-down → `GROOM-PLAN.md` |
| `groom move/pin <id> <pos>`, `groom unpin <id>` | Pin / release a rank |
| `groom strategy [--apply\|--dry-run]` | Foundation vs polish → `STRATEGY.md` |
| `undo` | Revert the last board commit (board in its own repo only) |
| `regen-board` | Rebuild `BOARD.md` |

Ids are case-insensitive (`e02` → `E02`). Next id = highest existing + 1. `groom` and
`groom strategy` fan out with Workflow at high effort -- running them is the opt-in.

## Step 3 -- Adding work

- **Planned work** (`epic` / `story` / `task` / `add`): ask first -- 1–2 questions for a task, 2–3
  for a story, up to 4 for an epic, in one AskUserQuestion -- reflect the understanding back in a
  sentence, then write the card with the understanding template. Offer a design doc for a
  substantial epic; never block on it.
- **Capture** (`capture` / `bug` / plain text): the card before any question. Snapshot the board,
  triage with a headless `claude -p` (strict JSON: type, size, placement, dedup, open questions),
  then write the card; a bug always goes under the Bugs epic as `type: breakfix`, `status:
  backlog`, `stage: Reported`. Regenerate and sync, then in the same reply: one line with the id
  and its place in line ("✓ Filed E07-S3 (breakfix, S) under Bugs -- #2 in line"), and **every**
  open question batched in one AskUserQuestion -- only questions whose answer changes
  the fix or its order. Check what you can check yourself instead of asking. Answers go under
  `## Answers`.

## Step 4 -- Lanes and dispatch

Bugs first: fill up to `LANE_CAP` lanes from the top of the line. Two cards share the floor only
if they touch **no common source files** and **no common data**. At most one lane per `SERIAL`
category; high-stakes cards are never auto-picked. Dispatch the lanes with `/dispatch-it` -- one
agent per card, each in its own worktree, each running the `/debug-it` method. With no bug
waiting, start **one** item: reconcile verdict `not-built`/`partial`, no unfinished `dependsOn`,
no `conflictsWith` in progress, no file overlap; P1 first, then never-reconciled, then oldest.
Announce each pick before it starts. Gather every lane's questions into one message. Shipping
stays serial: one PR through CI and deploy at a time.

## Step 4b -- Plan: how, and in what order

`plan` reads `handoff.md` and every open card, and gives each card a mode -- **solo**, **spike**
(unknowns first), **subagent-it** (3+ ordered tasks), or **dispatch-it** (3+ independent cards)
-- in waves that finish soonest with every gate held. One headless `claude -p` returns strict
JSON; `check-plan.py` then enforces the hard rules (no shared files or data in a parallel wave,
high-stakes held, `dependsOn` order) -- if it still fails after one retry, nothing is written.
It stamps `mode:` on the cards (never over `mode_by: you`), drafts `## Task N` plans for
`subagent-it` cards, and proposes spike cards (filed with `--apply`). `start` adds the card's
mode line after the preamble; `dispatch` follows the plan's next wave. Drafts never run without
the user's go.

## Step 5 -- After every change

1. Bump `updated:` on each touched card.
2. `python3 ~/.claude/make-it/backlog/bin/regen-board.py "$BOARD" --project "$PROJECT"`
3. Sync: board in its own repo → commit + push there. Board inside the project → stage only the
   board's paths (never the default branch).
4. Notify (no-op without a webhook): `~/.claude/make-it/backlog/bin/slack-notify.sh started <id>
   "<title>" "<category>" "<priority>"` on start, `... done <id> "<title>"` on done, `... raw
   "<text>"` for captures, stage changes, and digests. Never block on Slack.

---

See `backlog-board.md` for the frontmatter schema, the stage table, the reconcile ladder and its
JSON, groom and strategy, the high-stakes gate, the design-doc template, and how several
projects share one board.
