---
name: backlog-it
description: A file-based Epic→Story→Task backlog board -- markdown cards with frontmatter and a rendered BOARD.md, per project or one personal board used from anywhere. Adds planned work (clarify first), captures ideas and bugs (card first, AI triage, then batched questions), runs a bug queue (Reported → Cause found → Fix ready → Live → Checked) with up to N parallel non-overlapping fix lanes, recalls any card as an editable prompt with `start <id>`, and explains any card in plain terms with `info <id>`. Also reconcile against the code, groom, groom strategy, and dispatch. Use when the user types /backlog-it, or asks to track, list, start, or close a work item, epic, story, task, bug, or design doc.
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
@~/.claude/make-it/references/approval-block.md
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
   `SERIAL` = `serial`, else `[]`;
   `MODELS` = `models` over the defaults `{"route": "opus", "ground": "opus", "judge": ["claude-fable-5-2", "claude-fable-5-1"]}` (a list = first one the deployment serves; no `judge`
   served -> `route`, said in one line).
2. Export `BACKLOG_DIR=$BOARD` for the helpers.
3. **No board yet?** Say in one line that you'll set one up, then create `$BOARD/items/`, a
   `$BOARD/.gitignore` containing `.slack-webhook` and `.last-seen.json`, and render an empty `BOARD.md`. Write
   `.claude/backlog-it.json` only if the user chose a non-default setting. Don't ask about
   Slack -- it's optional and off until a webhook exists.

## Step 2 -- Route the argument

| Argument | Action (see the reference) |
|----------|----------------------------|
| *(none)*, `board` | The first screen (Step 2b): the one thing to do next with its choices, only what needs you, what changed since last time, the trend |
| `list` / `show` | The compact board, all of it or filtered / show a card |
| `info [<id>\|<title words>] [<focus>]` | The card in plain terms -- the problem, the impact if it isn't fixed, why it's fixed this way. Read-only; a background subagent reads, so running work isn't disturbed; bare `info` = this session's card |
| `epic`, `story <epic>`, `task <parent>` + idea, `add` | Add planned work -- clarify first (Step 3) |
| `capture <text>`, `bug <text>`, or text whose first word isn't a subcommand | Capture -- card first (Step 3) |
| `start <id>` | Recall → preamble (+ alignment brief if high-stakes) → editable prompt → run on the user's go |
| `status` (no id) | Run `python3 ~/.claude/make-it/backlog/bin/status.py "$BOARD" --project "$PROJECT"` and print its output as-is, in a code block. Read-only |
| `move`, `status <id> <status>`, `stage`, `done` | Update the card (`done` posts the end summary) |
| `reconcile [<id>\|all] [--fast\|--deep <id>\|--dry-run\|--dispatch]` | Check cards against `REPO`: code, tests, live |
| `reconcile --prs [--dry-run]` | No AI: `python3 ~/.claude/make-it/backlog/bin/sync-prs.py "$BOARD" --repo "$REPO" --project "$PROJECT"`, print its report, then sync (commit `reconcile: prs`). With `--dry-run`, pass it through and don't sync |
| `dispatch [--dry-run]` | New bugs into free lanes, then `PLAN.md`'s next wave, else the bug line, else the next safe item (Step 4); always end with `python3 ~/.claude/make-it/backlog/bin/status.py "$BOARD" --project "$PROJECT" --needs-you` |
| `plan [filter] [--with-deps] [--apply\|--dry-run]` | Route each card to solo / spike / `/subagent-it` / `/dispatch-it`, in waves → `PLAN.md` (Step 4b); `--with-deps` also plans what the filter waits on, across epics |
| `mode <id> <mode\|auto>` | Choose a card's mode yourself; `plan` keeps it |
| `groom [filter] [--with-deps] [--apply\|--dry-run\|--dispatch]` | Propose the burn-down → `GROOM-PLAN.md`, and say which epics, stories and tasks are no longer needed (proposals; one multi-select ask closes the ones you pick); `--with-deps` adds the chain behind the filter |
| `groom move/pin <id> <pos>`, `groom unpin <id>` | Pin / release a rank |
| `groom strategy [--apply\|--dry-run]` | Foundation vs polish → `STRATEGY.md` |
| `undo` | Revert the last board commit (board in its own repo only) |
| `regen-board` | Rebuild `BOARD.md` |

Ids are case-insensitive (`e02` → `E02`). Next id = highest existing + 1. `groom` and
`groom strategy` fan out with Workflow at high effort -- running them is the opt-in. Each AI step runs on the
model the reference's "Which model does what" names (settings `models`; default Opus for routing and
grounding, Fable 5.2 then 5.1 for judgment, Opus when neither is served).

## Step 2b -- The first screen

Run `python3 ~/.claude/make-it/backlog/bin/status.py "$BOARD" --project "$PROJECT" --repo "$REPO" --lane-cap "$LANE_CAP" --first --seen`
and print its output as-is, in a code block. **The helper decides; you present and ask**: the
recommendation under DO NEXT comes from its written rule (the reference's "The first screen"), never
from your own reading of the board. Then ask its choices with AskUserQuestion, exactly as printed:
one question ("What next?"), one option per numbered choice, the label before ` -- ` and what
happens after it, the Recommended one first with the `against:` line under it as its counter-argument. Add no option and drop none. Then
do what was picked, with every gate that step already has:

| Pick | What runs |
|------|-----------|
| Answer now | Each waiting card's `decision:` as its own AskUserQuestion with its `answers:`, most urgent first; the answer goes on the card, which clears `decision:` and `answers:` |
| Release it | First what the screen could not know: confirm the pull request's review (unless the screen says it is recorded on its card) and bring it up to date with main if it is behind. Then the project's own release steps for the pull request named, with their gates; the pick names the pull request, so it is the go for that one only |
| Sort them | `reconcile --prs`, then one plain line per pull request named: what it needs (bring up to date, fix its check, close with a note) |
| Start the wave | `dispatch` |
| Start the others | `dispatch`, for the wave's cards that share no file with an open pull request; the card named as sharing one waits |
| Wait for it | Nothing starts: every card in the wave shares a file with an open pull request. Say which pull request, and that releasing or finishing it comes first |
| Plan | `plan` |
| Groom | `groom` |
| Start it | `start <id>` for the card named |
| Wait | Nothing; say in one line what would change the answer |
| Full status | `status` |

A dismissed ask starts nothing. Everything the old board printed is under `status` and `list`.

## Step 3 -- Adding work

- **Planned work** (`epic` / `story` / `task` / `add`): ask first -- 1–2 questions for a task, 2–3
  for a story, up to 4 for an epic, in one AskUserQuestion -- reflect the understanding back in a
  sentence, then write the card with the understanding template. Offer a design doc for a
  substantial epic; never block on it.
- **Capture** (`capture` / `bug` / plain text): the card before any question. Snapshot the board,
  triage with a headless `claude -p` (strict JSON: type, size, placement, dedup, open questions),
  save what it gave back to a file (no file when it failed or timed out) and pipe the raw text to
  `card.py capture <file>`. Bad triage output never loses the report: `card.py` files it word for
  word under Bugs, marked "not sorted yet -- triage failed: <reason>" -- say that in the reply.
  On `triage ok`, write the card; a bug always goes under the Bugs epic as `type: breakfix`, `status:
  backlog`, `stage: Reported`. Regenerate and sync, then in the same reply: one line with the id
  and its place in line ("✓ Filed "Export drops the last row" (E07-S3), a bug, size S, under Bugs -- #2 in line"), and **every**
  open question batched in one AskUserQuestion -- only questions whose answer changes
  the fix or its order. Check what you can check yourself instead of asking. Answers go under
  `## Answers`. A question that blocks a card goes on it as `decision:` (plain context, then the
  question) and `answers:` (2-4 named options) -- the board's **Waiting on you** block; the write that
  adds the answer removes both.

## Step 4 -- Lanes and dispatch

Bugs first: fill up to `LANE_CAP` lanes from the top of the line. Two cards share the floor only
if they touch **no common source files** and **no common data**. At most one lane per `SERIAL`
category; high-stakes cards are never auto-picked. Dispatch the lanes with `/dispatch-it` -- one
agent per card, each in its own worktree, each running the `/debug-it` method and recording its PR
as `pr:` and how the fix is proved live as `signal:`. Dispatch starts with `reconcile --prs`. With no bug
waiting, start **one** item: reconcile verdict `not-built`/`partial`, nothing it waits on unfinished (its own `dependsOn` or its epic's; an epic id = its open cards),
no open `decision:`, no `conflictsWith` in progress, no file overlap; P1 first, then never-reconciled, then oldest.
Announce each pick before it starts, by its title with its id. Gather every lane's questions into one message, each item readable cold: its title, what waits and why, 2-4 named answers, a batch as one grouped line, a high-stakes item never batched (`approval-block.md`, A list of asks). Shipping
stays serial: one PR through CI and deploy at a time.

**Plain words, and no flood** (`approval-block.md`, A message to the owner, and A review sorts its
findings). Every lane and reviewer brief carries both rules' lines. When you pass on a lane's or a
reviewer's report, rewrite it in plain words: names with ids, shortest true form; never forward a
lane's shorthand. A lane files no follow-up card by default: leftovers are fixed inside the work, and a
fault that was already there goes on the running list (the reference's "The running list") unless it
can hurt someone. `capture` and `bug` are unchanged: the owner's own reports always become cards.

## Step 4b -- Plan: how, and in what order

`plan` reads `handoff.md` and the board, and gives each card that could start a mode --
**solo**, **spike** (unknowns first), **subagent-it** (3+ ordered tasks), or **dispatch-it** (3+
independent cards) -- in waves that finish soonest with every gate held, bugs first. High-stakes
cards are held; cards that must wait are skipped with what they wait on. `scope.py` fixes the cards
first: the filter (a card id such as an epic or one story, a status, a priority, or a category) and,
with **`--with-deps`**, the chain of open cards they wait on across epics, all the way down
(upstream only; same finish-soonest order) -- so `plan E04 --with-deps` puts E04 first without
dropping its prerequisites. One headless `claude -p` returns strict JSON -- with `--with-deps`,
also suggested missing links with their evidence; `check-plan.py --scope` then enforces the hard
rules (no shared files or data in a parallel wave, high-stakes never in a wave, wait order, nothing
outside the scope) -- if it still fails after one re-run, nothing is written. `--apply` writes the
suggested links as `dependsOn:` and plans what they pull in (one more pass).
It stamps `mode:` on the cards (never over `mode_by: you`), drafts `## Task N` plans for
`subagent-it` cards, and proposes spike cards (filed with `--apply`). `start` adds the card's
mode line after the preamble; `dispatch` follows the plan's next wave. A plan stays in force for
the cards it lists (new bugs take a free lane first; other new cards go after its waves); re-plan
when every wave is merged, its next wave is stuck, a spike's finding lands, or when asked. Drafts never run without the user's go.

## Step 5 -- After every change

**Card writes go through `card.py`** -- never `printf`, `sed` or a glob:
`python3 ~/.claude/make-it/backlog/bin/card.py --board "$BOARD" --project "$PROJECT"` then
`append <id> <section>` (text on stdin) · `set <id> key=value …` (`key=` removes) · `new <epic>` (a card on
stdin with `id: NEW`). It pulls first, writes the whole file, bumps `updated:`, regenerates and syncs --
steps 1-3 in one call. Its line ends `committed + pushed` only when the shared board has the write;
a line with `NOT sent` is relayed to the person as it is. Exit 3 = written here, the shared board
did not get it (never write it again; the next write that can send carries it). Any other non-zero
exit = nothing written. For other
board files (`PLAN.md`, design docs):

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
