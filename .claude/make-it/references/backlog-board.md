# Backlog Board Reference

A file-based **Epic → Story → Task** board that lives next to the code: one markdown card per
item, frontmatter as the source of truth, and a rendered `BOARD.md`. It is the project's memory
of *what's next* and *what's broken*, readable by any session, any agent, and any human.

The `/backlog-it` command exposes it directly. Other skills read and update it when a board
exists (see [Wiring](#wiring-into-the-other--it-skills)); with no board, they behave exactly as
before. Invisible to the vibe-coder unless they ask for it.

---

## Settings (per project)

Settings live in the project at **`.claude/backlog-it.json`** (committed). Every key is optional.

```json
{
  "board": ".claude/backlog",
  "project": "my-app",
  "lane_cap": 3,
  "serial": ["payments", "outgoing-email"]
}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `board` | `.claude/backlog` | Where the board lives. Relative to the project root, or an absolute / `~` path for a board shared across projects or kept in its own repo. `$BACKLOG_DIR` overrides it. |
| `project` | the project folder's name | The name in the `BOARD.md` title. |
| `lane_cap` | `3` | The most bugs fixed at once (see [Parallel lanes](#parallel-lanes)). |
| `serial` | `[]` | Card `category:` values that always run **one at a time** -- work whose mistakes reach people or systems outside the team (payments, outgoing email, anything filed with an outside party). |

**Slack (optional).** The webhook URL is a secret, so it is **never** in the settings file. It is
read from `$BACKLOG_SLACK_WEBHOOK`, else `<board>/.slack-webhook` (gitignored). With neither,
notifications are a silent no-op and the board works the same.

**Helpers** (installed with the framework, no hardcoded paths):
- `~/.claude/make-it/backlog/bin/regen-board.py <board> [--project NAME]` -- renders `BOARD.md`.
- `~/.claude/make-it/backlog/bin/slack-notify.sh {started|done|raw} ...` -- reads `$BACKLOG_DIR`;
  needs `jq` and `curl`.

---

## Layout

```
<board>/
├── BOARD.md                     # rendered -- never hand-edit; regenerate after every change
├── .project                     # optional: project name (settings `project` wins when passed)
├── .slack-webhook               # optional, gitignored
├── .gitignore                   # contains .slack-webhook
├── archive/                     # optional: retired cards, not rendered
└── items/
    └── EPIC-NN-slug/
        ├── epic.md              # the epic card
        ├── design.md            # optional design doc (for communicating, never a gate)
        └── stories/
            └── S<n>-slug.md     # story / task / breakfix / spike cards
```

## Card frontmatter

```yaml
---
id:        E04            # epics E01..; children <EPIC>-S<n> (E04-S2)
title:     Short plain title
type:      epic | story | task | breakfix | spike
status:    backlog | designing | ready | in-progress | blocked | done
stage:     Reported       # breakfix only -- see the bug queue
category:  free text      # e.g. billing, search, infra; matched against settings `serial`
priority:  P1 | P2 | P3
size:      XS | S | M | L | XL   # optional
parent:    E04            # children only
pin:       1              # optional rank override set by `groom move`
stakes:    critical       # optional -- never auto-started (see High-stakes items)
created:   YYYY-MM-DD
updated:   YYYY-MM-DD
---
```

Status flow: `backlog → designing → ready → in-progress → blocked ⇄ in-progress → done`.
`breakfix` renders with ⚡, `spike` with 🔬 (a spike's body states its timebox). Unknown keys are
kept; missing optional keys are fine. Never delete a card on `done` -- the history is the point.

**Card body (the understanding):**
```
## Goal -- the outcome we want
## Who it's for / the pain
## Constraints
## Definition of done
## Open questions
```

---

## Capture: card first, then questions

A report is never lost to a clarifying question. On any new item or bug:

1. **Write the card first** -- place it under the best-fitting epic (or a new epic if none fits,
   or the Bugs epic for a bug), fill what is known, put unknowns under *Open questions*.
2. **Regenerate the board and sync.**
3. **Then ask, batched** -- every open question in ONE message, plain words, only questions whose
   answer changes the fix or its place in line. Anything checkable (logs, data, the screen, the
   code) is checked, not asked. Answers go on the card under `## Answers`.
4. Reply with one line: the id, where it went, and its place in line.

---

## The bug queue

Bugs are `type: breakfix` cards under a **Bugs** epic (created on the first bug), each with a
`stage:`:

**Reported → Cause found → Fix ready → Live → Checked**

| Stage | Means | Set by |
|-------|-------|--------|
| Reported | card exists, cause unknown | capture / `/debug-it` intake |
| Cause found | root cause confirmed with evidence | `/debug-it` Phase 3 |
| Fix ready | fix + test on a branch, PR open | the fixing lane |
| Live | merged and deployed | ship, on merge |
| Checked | verified on the live system **against the original report** | ship, after the live check |

A bug is not `done` until **Checked**. Harm happening now (damaged data, a wrong outgoing
message, anything in a `serial` category) jumps the line; everything else takes its place.
Improvements are not bugs -- they wait behind the bug list.

**The status line** at the top of any epic with bug cards in `BOARD.md` (rendered by `regen-board.py`):
- **Now fixing** -- `in-progress` at Reported / Cause found (one entry per lane)
- **Shipping** -- Fix ready
- **Live, to check** -- Live
- **Next up** -- the top `backlog` bug by priority, then age

## Parallel lanes

Up to **`lane_cap`** bugs (default 3) are fixed at once, each by its own agent in its own git
worktree (the `/dispatch-it` pattern), taken from the top of the line when they don't overlap:

- **No overlap.** Two lanes never touch the same source files, and never run data changes
  against the same data at the same time. Unsure → they overlap; run them one after another.
- **Serial categories stay one at a time.** A card whose `category:` is in settings `serial` (or
  has `stakes: critical`) never shares the floor with another lane of the same category.
- **The ship queue is serial.** One PR through CI and deploy at a time, whatever the lane count.
- **Questions are batched.** Collect every lane's open questions into one message.
- Each lane moves its own card through the stages; the status line lists every lane.

---

## Subcommands

| Command | What it does |
|---------|--------------|
| *(none)* / `board` | Print the board, grouped by status, epics with children nested |
| `list <filter>` | Filter by status, category, priority, or epic id |
| `show <id>` | The card; for an epic, its children and design docs |
| `epic` / `story <epic>` / `task <parent>` `<idea>` | Add an item (capture flow) |
| `bug <text>` or plain text | Capture a bug into the queue (`stage: Reported`) |
| `start <id>` | Recall the card as an editable prompt, then run it |
| `move <id> <status>` · `stage <id> <stage>` | Change status / bug stage |
| `done <id>` | Short end summary, `status: done` |
| `reconcile [<id>\|all]` | Check cards against the code |
| `groom [filter]` | Propose an order that finishes the most, soonest |
| `groom move <id> <pos>` · `groom unpin <id>` | Pin / release an item's rank |
| `dispatch [--dry-run]` | Start the next safe lanes |
| `undo` | `git revert` the last board commit (board in its own repo) |

Every mutation: bump `updated:`, **regenerate `BOARD.md`, sync**, then notify Slack (never block
on Slack).

**`start <id>`** -- build the prompt (the card's own text for a raw card; a short precap from the
design doc for a design-backed one), prepend the standing preamble below, **show it and let the
user edit it**, then run it on their go. Set `status: in-progress` (and the parent epic), sync,
`slack-notify.sh started`. Starting is never refused -- a high-stakes card only leads with the
alignment brief.

> **Standing preamble.** If anything is ambiguous, ask first and state assumptions. Work on a
> branch or worktree, never the default branch. Root cause before fixing. 100% green tests are
> the gate for commit, merge, and deploy. Ship reversible changes on the project's normal path;
> for anything destructive, security-sensitive, or visible outside the team, stop at the open PR
> unless the project has granted standing approval for it.

**`reconcile`** -- for each open card, a three-rung ladder: **code** (find the implementation,
cite `file:line`), **tests** (covering tests, green/red), **live** (the project's own live check,
else `unknown`). `built` needs all three. Auto-apply only high-confidence, reversible verdicts
(`done`, duplicate, restatus) with a dated `## Reconciliation` block on the card; flag the rest.
Never trust the card over the code.

**`groom`** -- propose-only unless `--apply`. Ground via reconcile, then order: pins first, then
what unblocks the most, near-done work, parallel-safe batches (disjoint files), smaller size.
Write the order to `<board>/GROOM-PLAN.md` (not into cards). Splits and kills are always
proposals. `groom move <id> <pos>` sets `pin:` and re-flows the rest; pins stick until `unpin`
or `done`.

**`dispatch`** -- take the top of the line (bugs first), drop high-stakes cards, cards with
unfinished dependencies, and anything overlapping an in-progress lane, fill free lanes up to
`lane_cap` (one per serial category), and `start` each in its own worktree via `/dispatch-it`.
`--dry-run` prints the picks only. Every gate from the preamble still applies.

### High-stakes items

A card is high-stakes if `stakes: critical` is set or it touches auth / secrets, schema or data
migrations, money, or deletion of live data. It is **never** auto-started or dispatched, renders with ⚠️, and `start` leads with an alignment brief: what exists in the code
now, what already works, what would change, the blast radius, and a safe place to rehearse. Then
wait for an explicit go.

---

## Sync

- **Board in its own git repo** (e.g. `~/boards/my-app`, or shared by several projects):
  `git -C <board> add -A && git commit -m "<what changed>" && git push` after every mutation.
- **Board inside the project** (the default): stage only the board's paths; the changes ride
  with the current branch's commits. Never commit to the default branch for a card update.

## Sharing one board

Point several projects -- or a personal board command -- at the same `board` path. The format is
the only contract: the same folders, the same frontmatter, the same `BOARD.md` renderer. Whoever
writes last regenerates `BOARD.md` from the cards, so nothing is lost.

---

## Wiring into the other -it skills

When `.claude/backlog-it.json` or `.claude/backlog/BOARD.md` exists:

| Skill | Hook |
|-------|------|
| `/resume-it` | Starts from the board: **Now fixing** lanes first, then **Next up** |
| `/dispatch-it` | Takes its lanes from the board -- non-overlapping, up to `lane_cap` |
| ship (`ship-it-guide.md`) | On merge: stage **Live**. After the live check: **Checked**, then `done`. `/resume-it` and `/wrap-it` catch up any `Fix ready` card whose PR has merged |
| `/wrap-it` | Updates each touched card and regenerates the status line alongside the handoff |
| `/debug-it` / `/fix-it` | A new bug gets a card (`stage: Reported`) before any fix work |
