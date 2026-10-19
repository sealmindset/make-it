# Backlog Board Reference

A file-based **Epic → Story → Task** board that lives next to the code: one markdown card per
item, frontmatter as the source of truth, and a rendered `BOARD.md`. It is the project's memory
of *what's next* and *what's broken*, readable by any session, any agent, and any human. Log
ideas, then recall them to run.

The `/backlog-it` command exposes it directly. Other skills read and update it when a board
exists (see [Wiring](#wiring-into-the-other--it-skills)); with no board, they behave exactly as
before. Invisible to the vibe-coder unless they ask for it.

---

## Settings

Every key is optional. The first file found wins **as a whole** (keys are not mixed across files):

1. **Project:** `.claude/backlog-it.json` in the project root (committed).
2. **Project board, no settings file:** `.claude/backlog/` exists → use it with defaults.
3. **User:** `~/.claude/backlog-it.json` -- one personal board used from any folder that has
   neither of the above (e.g. a board in its own repo at `~/.claude/backlog`).
4. **Defaults** -- a new board at `.claude/backlog` in the project.

```json
{
  "board": ".claude/backlog",
  "project": "my-app",
  "repo": ".",
  "lane_cap": 3,
  "serial": ["payments", "outgoing-email"]
}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `board` | `.claude/backlog` | Where the board lives. Relative to the project root, or an absolute / `~` path for a board shared across projects or kept in its own repo. `$BACKLOG_DIR` overrides it. |
| `project` | `<board>/.project`, else the project folder's name | The name in the `BOARD.md` title. |
| `repo` | the project root | The code that `reconcile`, `groom`, and `groom strategy` check cards against. Set it in the user file when the board is used from anywhere. |
| `lane_cap` | `3` | The most bugs fixed at once (see [Parallel lanes](#parallel-lanes)). |
| `serial` | `[]` | Card `category:` values that always run **one at a time** -- work whose mistakes reach people or systems outside the team (payments, outgoing email, anything filed with an outside party). |

**Slack (optional).** The webhook URL is a secret, so it is **never** in the settings file. It is
read from `$BACKLOG_SLACK_WEBHOOK`, else `<board>/.slack-webhook` (gitignored). With neither,
notifications are a silent no-op and the board works the same.

**Helpers** (installed with the framework, no hardcoded paths):
- `~/.claude/make-it/backlog/bin/regen-board.py <board> [--project NAME]` -- renders `BOARD.md`.
- `~/.claude/make-it/backlog/bin/status.py <board> [--project NAME] [--needs-you]` -- prints the `status`
  report (read-only; shares `regen-board.py`'s rules); `--needs-you` prints only its Needs you section.
- `~/.claude/make-it/backlog/bin/sync-prs.py <board> --repo <repo> [--dry-run]` -- `reconcile --prs`:
  moves cards forward from their PRs' real state (needs `gh`; writes the cards, the caller syncs).
- `~/.claude/make-it/backlog/bin/card.py {append <id> <section> | set <id> k=v … | new <epic>}` -- the
  one way to write a card (see [Writing a card](#writing-a-card)).
- `~/.claude/make-it/backlog/bin/slack-notify.sh {started|done|raw} ...` -- reads `$BACKLOG_DIR`;
  needs `jq` and `curl`.

---

## Layout

```
<board>/
├── BOARD.md                     # rendered -- never hand-edit; regenerate after every change
├── README.md                    # optional
├── GROOM-PLAN.md                # written by `groom` (the burn-down lives here, not in cards)
├── PLAN.md                      # written by `plan` (waves + a mode per card)
├── STRATEGY.md                  # written by `groom strategy`
├── .project                     # optional: project name
├── .slack-webhook               # optional, gitignored
├── .gitignore                   # contains .slack-webhook
├── archive/                     # optional: retired cards, not rendered
└── items/
    └── EPIC-NN-slug/
        ├── epic.md              # the epic card
        ├── design.md            # optional design doc (for communicating, never a gate)
        ├── <other-docs>.md      # capture plans, ADRs, etc.
        ├── plans/<id>.md        # `## Task N` plans for /subagent-it (see the Plan format)
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
size:      XS | S | M | L | XL   # optional; absent shows as — in tables
parent:    E04            # children only
design:    design.md      # epics with a design doc
pin:       1              # optional rank override set by `groom move`; dropped on done
stakes:    critical       # optional -- never auto-started (see the High-stakes gate)
dependsOn: [E02]          # optional -- not dispatched until these are done
conflictsWith: [E07]      # optional -- not dispatched while these are in progress
decision:  3 import rows failed twice; the rest went in. Retry them, or refile by hand?   # optional -- plain context, then the one question this card waits on (see Waiting on you)
answers:   Retry -- runs it again tonight | Refile -- you re-enter the 3 rows   # with decision: -- 2-4 named answers, split by |
pr:        [1590]         # the fix PR(s), set by the fixing lane when it opens one; another repo's PR as its URL
signal:    worker log shows 'filed: 2/2' for a new filing   # one line: how the fix is proved live (read-only); the lane writes it with the PR
checkAfter: v2026.10.17   # when that check can first run: a release tag (due on the date in its name) or a date; set at ship
mode:      solo | spike | subagent-it | dispatch-it   # set by `plan` (see the mode rubric)
mode_by:   you            # set by `mode <id>` -- `plan` never overwrites a mode you chose
plan:      plans/E04-S2.md   # the card's `## Task N` plan, relative to the epic folder
reconciled: YYYY-MM-DD    # set by reconcile on its first auto-apply
created:   YYYY-MM-DD
updated:   YYYY-MM-DD
---
```

Status flow: `backlog → designing → ready → in-progress → blocked ⇄ in-progress → done`.
Unknown keys are kept; missing optional keys are fine. Never delete a card on `done` -- the
history is the point.

**Types:**
- `epic` -- a large workstream that owns the cards under it. Typically L · XL.
- `story` -- a shippable slice of an epic. Typically XS · S · M.
- `task` -- a concrete atomic unit under an epic or story. Typically XS · S.
- `breakfix` -- a defect. Uses the child id scheme; renders with ⚡. Typically XS · S.
- `spike` -- a timeboxed investigation whose output is a finding or ADR, not shippable code. The
  body states its timebox; renders with 🔬. Typically S · M.

**Card body (the understanding):**
```
## Goal -- the outcome we want
## Who it's for / the pain -- who benefits and why it matters
## Constraints -- must-haves, limits, non-negotiables
## Definition of done -- how we'll know it's complete
## Open questions -- anything still unresolved
```

---

## Adding work

There are two ways in, and the difference matters:

| You type | Flow | Why |
|----------|------|-----|
| `epic <idea>` · `story <epic> <idea>` · `task <parent> <idea>` · `add` | **Clarify first, then write the card** | Planned work: a shared understanding is worth a question or two |
| `capture <text>` · `bug <text>` · plain text | **Card first, then questions** | A report is never lost to a clarifying question |

### Clarify first (`epic` / `story` / `task` / `add`)

1. **Ask clarifying questions** in one AskUserQuestion, sized to the item and never zero: a
   **task** 1–2, a **story** 2–3, an **epic** up to 4. Frame them around the understanding
   template (goal, who/why, constraints, done).
2. **Reflect the understanding back** in one sentence so it's confirmed.
3. **Write the card**, filling the understanding template from the answers; anything still open
   goes under *Open questions*. Infer title, slug, category, and priority.
4. One line showing what was made; regenerate and sync.

- `epic <idea>` -- next id `E<NN>`; scaffold `items/EPIC-NN-slug/{epic.md, stories/}`. A
  freshly-clarified epic usually lands `ready` (or `designing` if a design doc will follow). If
  it's substantial, offer a `design.md` in the [design-doc template](#design-doc-template) --
  never block on it.
- `story <epic> <idea>` -- next id `<EPIC>-S<n>`, `parent:` the epic.
- `task <epic|story> <idea>` -- `type: task` under the given epic or story.
- `add` -- interactive fallback when no idea is given inline: ask only what can't be inferred.

Ids are case-insensitive (`e02` → `E02`); the next id is the highest existing + 1. New cards go
to the bottom of their status.

### Card first (`capture` / `bug` / plain text)

Plain text whose first word isn't a subcommand is `capture <text>`. The user just describes it.

1. **Snapshot the board:** one line per epic -- `id · title · [category] · status`, plus the first
   meaningful body line when cheap.
2. **Triage** with a headless `claude -p` (read-only tools `Read,Glob,Grep`, cwd = the board),
   passing the snapshot, the raw text, and today's date. It returns **strict JSON only**:
   ```json
   {
     "type": "epic|story|task|breakfix|spike",
     "size": "XS|S|M|L|XL",
     "title": "short imperative title",
     "category": "best-fit category",
     "priority": "P1|P2|P3",
     "placement": { "mode": "existing|new", "epic": "E09", "confidence": 0.82, "why": "one line" },
     "new_epic": { "slug": "kebab-slug", "title": "Title Case", "category": "..." },
     "acceptance": ["testable criterion"],
     "dedup": { "duplicate_of": "E09-S2", "confidence": 0.4 },
     "open_questions": ["..."]
   }
   ```
   - A **bug** always files under the **Bugs** epic (created on first use) as `type: breakfix`,
     `status: backlog`, `stage: Reported` -- never a new epic.
   - `existing` → file under `epic` as `<EPIC>-S<n>`. `new` → create `EPIC-NN-<slug>/` with its
     `epic.md` and file the item under it; if the item is itself epic-scale, the new epic IS the
     item. Below 0.6 confidence for every existing epic, choose `new` -- creating epics on its own
     is intended. `new_epic` only when `mode` is `new`.
   - `dedup` is advisory: never auto-close; surface it on the card and in the questions.
3. **Validate.** The target epic must exist in the folder listing. Malformed JSON or an unknown
   epic → stop with an error, write nothing.
4. **Write the card -- no approval gate** (`undo` is the safety valve for a board in its own repo;
   in a project board the card rides on the branch), with `card.py new <epic>`: the understanding template,
   then:
   ```markdown
   ## Captured
   > <raw text, verbatim>
   _via /backlog-it capture · YYYY-MM-DD_

   ## Scrum Master triage
   - type: <t> · size: <s> · placement: <epic> (confidence <c>)
   - reasoning: <placement.why>
   ```
5. Regenerate and sync (commit `capture: <title>`); `slack-notify.sh raw ":inbox_tray: Captured
   <id> -- <title> · <category> · <priority>"`.
6. **In the same reply:** one line -- `✓ Filed E09-S3 (breakfix, S) under Bugs -- #3 in line,
   behind E09-S1 · /backlog-it undo to revert` -- then **every** open question batched in one
   AskUserQuestion, in plain words, only those whose answer changes the fix or its place in line.
   Anything checkable (logs, data, the screen, the code) is checked, not asked. Answers go on the
   card under `## Answers` (the same write clears any `decision:` and `answers:`). Before a bug moves to Cause found, any remaining question that would
   change the fix is asked then.

---

## The bug queue

Bugs are `type: breakfix` cards under a **Bugs** epic, each with a `stage:`:

**Reported → Cause found → Fix ready → Live → Checked**

| Stage | Means | Set by |
|-------|-------|--------|
| Reported | card exists, cause unknown | capture / `/debug-it` intake |
| Cause found | root cause confirmed with evidence | `/debug-it` Phase 3 |
| Fix ready | fix + test on a branch, PR open -- or merged and waiting for its `signal:` | the fixing lane, which records the PR in `pr:` and how the fix is proved live in `signal:` |
| Live | merged (and deployed, where merge deploys) | ship, on merge, setting `checkAfter:` to the release that carries it -- or `reconcile --prs` once `gh` shows the card's PRs merged. **No `signal:`, no Live**: the card waits at Fix ready until it says how it will be checked |
| Checked | verified on the live system **against the original report** | ship, after the live check |

A bug is not `done` until **Checked**; `reconcile --prs` closes a Checked card. **Jump the line** only for harm happening now: damaged
data, a wrong outgoing message, anything in a `serial` category. Everything else takes its
place. Improvements are not bugs -- they wait until the bug list is empty. One message to the
reporter per finished card.

**The status line** at the top of any epic with bug cards in `BOARD.md`:
- **Now fixing** -- `in-progress` at Reported / Cause found, not waiting on you (one entry per lane)
- **Shipping** -- Fix ready
- **Live, to check** -- Live and due: no `checkAfter:`, or its date has come (a release tag counts as out on
  the date in its name, `v2026.10.17`; an undated tag or a non-date waits, and `status` flags it as never
  due). The live check first confirms that release is really out -- its tag, or the running version --
  since a day's release can land hours into the day, or not at all
- **Live, waits** -- Live with a `checkAfter:` still ahead, grouped by it (`v2026.10.17 → S85, S87`); only
  shown when some card waits
- **Next up** -- the top `backlog` bug that can start (not high-stakes, no unfinished
  `dependsOn`, not waiting on you), by priority, then age

**Waiting on you** -- one block at the top of `BOARD.md`: every open card, of any type, that
waits on the human's answer, each readable cold (`approval-block.md`, A list of asks): `id · title
· days since the card last changed`, then its `decision:`, then its `answers:`.
- Whoever asks (a lane, `/debug-it`, capture, a ship gate) writes both in the same write that asks
  (`card.py set <id> decision="…" answers="…"`). The card keeps its stage.
  - `decision:` -- one or two plain sentences on what waits and why, then the question. No bare
    card or PR number, no internal term without a gloss.
  - `answers:` -- 2-4, split by `|`, each `Name -- what happens if picked`; a Recommended one
    carries `against:` its strongest counter-argument (`Go -- deploys today (Recommended; against:
    only rehearsed on a copy) | Wait -- does the rollback, E68-S4, first`).
- `BOARD.md` and `status --needs-you` flag a gap under the item: no context (only an id or a few
  words), answers not on card, not 2-4 answers each with ` -- `, or a Recommended with no `against:`.
  Fix the card before asking.
- The write that records the answer under `## Answers` removes both (`card.py append <id>
  Answers`, then `card.py set <id> decision=`, which clears `answers:` too). A stale one keeps the
  card out of Next up, so never leave it behind.
- Now fixing and Next up skip a waiting card; `plan` and `dispatch` treat it as waiting on you.
- An older card with `stage: Needs decision` is listed too, flagged "question not on card" until
  its question moves into `decision:` and its answers into `answers:`.

## Parallel lanes

Up to **`lane_cap`** bugs (default 3) are fixed at once, each by its own agent in its own git
worktree (the `/dispatch-it` pattern), taken from the top of the line when they don't overlap:

- **No overlap.** Two lanes never touch the same source files, and never run data changes
  against the same data at the same time. Unsure → they overlap; run them one after another.
- **Serial categories stay one at a time.** A card whose `category:` is in settings `serial`
  never shares the floor with another lane of the same category.
- **The ship queue is serial.** One PR through CI and deploy at a time, whatever the lane count.
- **Questions are batched.** Collect every lane's open questions into one message, each item
  readable cold (`approval-block.md`, A list of asks). A question that blocks a card also goes on it as `decision:` + `answers:`.
- Each lane moves its own card through the stages, and records its PR as `pr:` when it opens one, with
  how the fix is proved live as `signal:` (`card.py set <id> stage="Fix ready" pr="[N]" signal="…"`);
  the status line lists every lane.
- **A lane that stops hands its card back** -- done, blocked, or out of turns: the next stage, a
  `decision:` with its `answers:`, or `status: backlog` with a note. Now fixing is read from the cards, so a card left
  behind looks like a running lane; `status` flags a Now fixing card idle 2+ days as "lane stopped?".

---

## Subcommands

| Command | What it does |
|---------|--------------|
| *(none)* / `board` | Print the board compactly: by status (in-progress → ready → blocked → designing → backlog → done), epics with children nested, `id · title · [category] P#` |
| `list <filter>` | The same, filtered by status, category, priority, or epic id |
| `show <id>` | The card; for an epic, its children (id · status · title) and design docs |
| `epic` / `story <epic>` / `task <parent>` `<idea>` · `add` | Add planned work (clarify first) |
| `capture <text>` · `bug <text>` · plain text | Capture (card first, AI triage) |
| `start <id>` | Recall the card as an editable prompt, then run it |
| `status` (no id) | Where the board stands: in flight, up next, burn-down + forecast, needs you, drift, epics, cycle time (see [`status`](#status)) |
| `move <id> <status>` · `status <id> <status>` · `stage <id> <stage>` | Change status / bug stage (a stage change also posts `slack-notify.sh raw`) |
| `done <id>` | End summary, `status: done` |
| `reconcile [<id>\|all]` | Check cards against the code, tests, and live system |
| `dispatch [--dry-run]` | New bugs into free lanes, then `PLAN.md`'s next wave, else the bug line, else the next safe item; ends with what needs you |
| `plan [filter] [--apply\|--dry-run]` | Route each card to solo, spike, `/subagent-it` or `/dispatch-it`, in waves → `PLAN.md` |
| `mode <id> <solo\|spike\|subagent-it\|dispatch-it\|auto>` | Choose a card's mode yourself (`auto` hands it back to `plan`) |
| `groom [filter]` | Propose the order that finishes the most, soonest |
| `groom move <id> <pos>` · `groom pin` · `groom unpin <id>` | Pin / release an item's rank |
| `groom strategy` | Which work is foundation and which is polish, and why |
| `undo` | `git revert` the last board commit (board in its own repo) |
| `regen-board` | Rebuild `BOARD.md` from the cards |

Every mutation: bump `updated:`, **regenerate `BOARD.md`, sync**, then notify Slack (never block
on Slack). For a card, `card.py` does all three in one call.

### `start <id>` -- the recall feature

No risk scoring, no gating, no "too risky to start" -- ever. A high-stakes card is not an
exception: it still runs on the user's go; it only leads with the alignment brief (see the
[High-stakes gate](#high-stakes-gate)).

1. **Build the prompt.** A raw card → its own text, as-is. A design-backed card → a **precap**: a
   prompt distilled from the design doc and card. (The design doc stays a communication artifact,
   never a gate.) **Always prepend the standing preamble** below, for every type, then the
   card's **mode line** if it has a `mode:` (see [`plan`](#plan-filter---apply---dry-run)); for
   `solo` and `spike`, drop the preamble's opening **Launch subagents.**
2. **Show the assembled prompt and let the user edit it** -- anything, including the preamble.
   This is an edit step, not an approval gate.
3. On the user's **go**, run the (possibly edited) prompt as the active instruction, start to
   finish. Ground facts when it's cheap (see [Grounding](#grounding-verify-never-block)) -- never
   block on it.
4. `status: in-progress` (and the parent epic if a child starts), bump `updated:`.
5. Regenerate, sync, `slack-notify.sh started <id> "<title>" "<category>" "<priority>"`.

> **Standing preamble** (prepended verbatim on every `start`; editable before it runs)
>
> **Launch subagents.**
>
> Before you start: if anything about this is ambiguous, underspecified, or could reasonably be
> interpreted more than one way, ask your clarifying questions first rather than guessing. If
> you're making assumptions to proceed, state them explicitly. Don't begin the work until you're
> confident you understand what's actually needed -- and if you only need to clarify one or two
> things, ask those and wait. Only ask if it would actually change what you do; otherwise proceed
> and note your assumptions.
>
> Work on a branch or worktree, never the default branch. Root cause before fixing.
>
> **Ship protocol -- when everything has been built and updated:** always run the necessary smoke
> tests. **100% green is the hard gate** -- never commit, merge, or deploy on anything less; if a
> test is red, stop, fix, and re-run until green (or, if genuinely blocked, surface the blocker
> rather than shipping). Once green, judge the blast radius and ship on the matching track:
> - **Safe / reversible** -- additive features, UI/cosmetic, docs, tests, internal refactors,
>   local tooling → commit → push → PR → merge → deploy on the project's normal path, **without a
>   human step where the project has granted standing approval for it**; otherwise stop at the
>   open PR.
> - **Potentially harmful or app-impacting** → everything up to the **open PR**, then **STOP for
>   explicit human approval before merge or deploy.** Triggers (non-exhaustive): anything
>   destructive or hard to reverse (data deletion, migrations, schema changes, rewriting
>   production data); auth, permissions, security, secrets, networking/infra; changes to a live
>   customer-facing product; externally visible side effects (customer emails or notifications,
>   filings with an outside party, billing); breaking changes or removed behavior. **When in doubt
>   whether a change can cause harm, gate it -- ask, don't ship.**

> **Mode line** (after the preamble; it governs how the work is run -- for `solo` and `spike`
> it replaces the preamble's opening **Launch subagents.**)
> - `solo` -- **Mode: solo.** Do this in this session; subagents only for read-only research or
>   an independent review.
> - `spike` -- **Mode: spike (timebox <T>).** Answer: <question>. Append the answer to the card as
>   `## Finding`; ship no code. Then run `/backlog-it plan` again.
> - `subagent-it` -- **Mode: subagent-it.** Run the card's approved plan (`plan:`) with
>   `/subagent-it`. No approved plan yet: draft it first (Plan format), show it, wait for the go,
>   mark it `status: approved`, then run it.
> - `dispatch-it` -- **Mode: dispatch-it (one lane).** This card is one lane of a parallel wave:
>   its own worktree, the `/debug-it` method for a bug, no files outside its lane. `dispatch`
>   launches the whole wave; `start` runs just this lane.

**For whoever runs a started card:** "deploy" means the project's real production path, with the
project's own smoke tests; if a deploy goes wrong, prefer the project's rollback path. Two
conditions halt shipping: red tests, and potential harm.

### `status`

Bare `status` prints one report from `status.py`: read-only, no AI call, under a second on a
365-card board, and the same answer every run. It shares the card reader and the status-line,
waiting and can-start rules with `regen-board.py`, so the report and `BOARD.md` never disagree.

- **In flight** -- by stage, not status (most `in-progress` bugs are waiting at Live): the board's
  Now fixing, Shipping and Live to check lines (the cards due now, each with its `signal:`), Live
  waits (counted by what they wait on), then other in-progress work; each with its count and oldest
  idle card.
- **Up next** -- the board's Next up bug, `PLAN.md`'s next unmerged wave ("covers N of M
  candidates; K new since (new bugs first, the rest after its waves)"), and the top stories / tasks / spikes that can
  start.
- **Burn-down** -- per week for 4 weeks: opened, closed, net, open at week's end; then a forecast
  ("clear in ~N wks", or "growing, no finish at this rate" plus how long the open cards would
  take with no new ones).
- **Needs you** -- Waiting on you (top 5), then **every** held P1, oldest first, with P2/P3 held
  as a count. A card already under Waiting on you isn't repeated. `dispatch` ends with this section.
- **Drift** -- Now fixing cards idle 2+ days (lanes work in hours: the lane probably stopped), other
  in-progress work (not bugs) idle 14+ days, Live cards idle 14+ days, Checked cards not closed, Live
  cards with no `signal:` (write one), Live cards waiting on a `checkAfter:` that never comes due, a `PLAN.md` whose waves are all merged or whose next wave is stuck on a held, waiting or blocked
  card (re-plan).
- **Epics** -- done / total per epic, most open first. **Cycle time** -- median days Reported →
  Live and Live → Checked, by priority.

Dates come from the board's git history: the last commit that set a card `done`, the first that
set `Live` / `Checked`, and the last that touched it; renames are followed, and the weeks start at
the board's first card. A card that entered git already done (a seed or an import) is left out of
the weekly opened / closed counts, and cycle time counts only transitions git saw. With no git,
it falls back to `created:` / `updated:` and says so. Lists show the top 5. Runs on Python 3.9+.

### `done <id>`

A brief, **non-blocking end summary** -- what actually changed (tests/build, where applied, the
commit) and the suggested next item. Then `status: done`, drop any `pin:`, bump `updated:`,
regenerate, sync, `slack-notify.sh done <id> "<title>"`.

### `reconcile [<id> | all]`

Code-grounded reconciliation. For each open card (or the one given), run a three-rung
**verification ladder** through a headless `claude -p` (tools `Read,Glob,Grep,Bash`, cwd =
settings `repo`), auto-apply high-confidence reversible verdicts, and flag the rest. **`built`
needs all three rungs -- a false "done" hides real work. Never trust the card over the code.**

1. **CODE** -- find the implementation (routes, models and migrations, components, agents --
   whatever the stack has) and cite `file:line`.
2. **TESTS** -- find the covering tests; report green/red if runnable headlessly, else their
   presence and the last CI signal.
3. **LIVE** -- check the live system the project names (its `CLAUDE.md` / `app-context.json`):
   HTTP probe, UI, or data. If it needs auth that can't safely be probed, say `unknown` -- never
   guess.

The engine returns **strict JSON per card**:
```json
{
  "item": "E20",
  "verdict": "built|partial|not-built|unknown",
  "confidence": 0.85,
  "evidence": {
    "code": ["src/lib/export.ts:1 -- ExportService"],
    "tests": ["tests/unit/export.test.ts -- 12 passing"],
    "live": ["GET /api/export 200"]
  },
  "gaps": ["multi-page export errors live"],
  "proposed_action": { "kind": "mark_done|close_dup|restatus|split|none", "to_status": "done", "dup_of": "", "why": "one line" }
}
```

`built` = code ✓ + tests ✓ + live ✓ · `partial` = code ✓ but tests missing/red or live failing ·
`not-built` = no meaningful code · `unknown` = not enough signal.

**Auto-apply** when `confidence ≥ 0.8` AND the action is reversible and non-harmful (`mark_done`,
`close_dup`, `restatus` -- never `split`); otherwise flag for the human. Each auto-apply sets `reconciled:` on
first use, bumps `updated:`, and appends:
```markdown
## Reconciliation (YYYY-MM-DD)
- verdict: built · confidence: 0.85 · via: code+tests+live
- evidence: src/lib/export.ts:1, tests/unit/export.test.ts (12 passing), GET /api/export 200
- action: mark_done -- undo available (`/backlog-it undo`)
```

Then regenerate, sync (commit `reconcile: <summary>`), notify, and print:
```
Reconcile run -- YYYY-MM-DD -- N items checked
  built: N  (auto-applied mark_done: ...)
  partial: N  (flagged: ...)
  not-built: N  (no action)
  unknown: N  (flagged: ...)
Auto-applied: N actions  |  Flagged for human: N items
```

Flags: `--prs` (no AI: `sync-prs.py` reads each open card's `pr:` with `gh pr view` and moves it
forward on facts only -- every PR closed and one merged → Live (merged; the live check confirms the
deploy), but only with a `signal:` (a merged card without one waits, named); Checked → done; never backward, never past Live. A card with no `pr:` is never guessed
from its text: a Shipping card without one is listed to set by hand, as is a `repo#N` short form
(use the PR's URL). Each card is re-read at write time, so another session's move wins. No `gh`
→ the PR step is skipped and said so) · `--fast` (code rung only) · `--deep <id>` (run the project's unit and end-to-end tests
headlessly for one card) · `--dry-run` (print what would apply, write nothing) · `--dispatch`
(run `dispatch` afterwards).

### `dispatch [--dry-run]`

Autonomous "do the next thing" -- a hands-free way to call `start`. **It never bypasses the
green gate or the harm gate** in the standing preamble.

0. **Stages first, then the plan.** Run `reconcile --prs` (`--dry-run` under `dispatch
   --dry-run`) so Shipping and Checked are true. **New bugs first:** fill free lanes with bugs the
   plan doesn't list, by step 1's rules -- bugs before improvements holds even mid-plan. **Then the
   plan, which stays in force for the cards it lists**: cards changed since it was written keep
   their place, and other new cards go after its waves. **Re-plan** when every wave is merged, when
   its next wave can't start (a card in it is held, waiting on you, or blocked -- `status` flags
   "PLAN.md stuck"), after a spike's finding lands, or when asked (`plan`); no `PLAN.md` → the
   steps below. (A stricter "any change makes it stale" rule went stale within hours on a busy
   board, and the re-plan it demanded was skipped every time.) Take the first wave whose cards
   aren't all merged, and start it only when every card
   in the waves before it is merged (`done`, Live, or Checked) and none of its own cards is in
   progress. Each card must still pass step 2's excludes; one that fails waits. A `dispatch-it`
   wave → its cards as `/dispatch-it` lanes, once they fit the free lanes (`lane_cap` minus the
   lanes running); a `solo`, `spike`, or `subagent-it` card → `start`
   it (a `subagent-it` card still waits for its plan's go; a proposed spike waits for
   `plan --apply`). Held cards are never taken.
1. **Bugs first -- fill free lanes.** Take bugs from the top of the line and fill free lanes up to
   `lane_cap` under the [Parallel lanes](#parallel-lanes) rules, each started in its own worktree
   via `/dispatch-it` (one agent per card, running the `/debug-it` method).
2. **No bugs waiting -- start one item.** Improvements wait behind bugs, and run one at a time:
   - Filter to reconcile verdict `not-built` or `partial` (if reconcile hasn't run: `status:
     ready` or `backlog`).
   - Exclude: high-stakes cards (never auto-selected -- log the skip and why); unfinished
     `dependsOn`; an open `decision:` (waiting on you); a `conflictsWith` card in progress; file
     overlap with any in-progress card's reconcile evidence.
   - Sort: P1 → P3, then never-reconciled first, then oldest `updated:` first. Pick the top.
3. **Announce** each pick -- `Dispatching <id> -- <title> [category] P# · <verdict> · confidence
   <c>` -- so the human can interrupt, then run `start <id>` with every gate in place.
4. Append to each card, then sync (commit `dispatch: started <id>`):
   ```markdown
   ## Dispatch (YYYY-MM-DD)
   - auto-dispatched by /backlog-it dispatch
   - verdict at dispatch: not-built · confidence: 0.82
   ```

5. **End with what needs you** -- `status.py <board> --needs-you`, every time (also under
   `--dry-run`): the decisions waiting on you, and every held P1, oldest first, so a high-stakes
   card that dispatch rightly never takes still comes back to you. Anything else the reply lists for
   the human is readable cold: its title, what waits and why, 2-4 named answers, a batch as one grouped line (`approval-block.md`, A list of asks).

Armed by default; `--dry-run` prints the picks without starting anything; everything is logged
and reversible.

### `plan [filter] [--apply] [--dry-run]`

**How and in what order.** One AI pass reads the project's `handoff.md` and the board, routes
each card that could start to an execution mode, and orders them into **waves** -- the path that
**finishes soonest with every gate held**. `groom` decides *what next*; `plan` decides *how to
run it*. It does no per-card code check of its own (it reuses recorded evidence; run `groom` to
re-ground). One headless call: about a minute on a small board, ~10 on a 100-card board. The plan
then leads `dispatch` for the cards it names until its waves are merged (see `dispatch` step 0).

**The mode rubric:**
- **spike** -- unknowns dominate: open questions that change the approach, no code evidence, an
  unfamiliar outside system. Timeboxed; the output is a finding, then plan again.
- **solo** -- one coherent change; small; or tightly coupled / needs whole-system context.
- **subagent-it** -- splits into **3+ ordered tasks** (size is a hint, not a gate); needs a
  `## Task N` plan (Plan format below).
- **dispatch-it** -- **3+ independent cards** (up to `lane_cap`): disjoint files and written
  data, no shared root cause, no two of one `serial` category. Bugs that share a cause → one
  `solo` `/debug-it`, never parallel lanes.
- **held** (not a mode) -- high-stakes: `stakes: critical` or a [High-stakes gate](#high-stakes-gate)
  signal. Never in a wave; it needs the alignment brief and an explicit go.
- **skipped** (not a mode) -- a candidate that must wait: an open `dependsOn` not planned in an
  earlier wave, files an in-progress card is changing, or an open `decision:` (waits on you). Its
  reason names what it waits on.
- **Order** -- bugs before improvements (the bug queue rule), then most-unblocking first, a spike
  before the work it de-risks, near-done wins, then the parallel waves. Shipping stays one PR at
  a time. A **wave** is one step: a `dispatch-it` wave runs its cards side by side; any other
  wave is one card. Waves run in list order.

1. **Gather.** **Candidates** are the open leaf cards in scope (no card names them as `parent`
   -- an epic whose children are all done is a container, not work) with status `backlog`,
   `ready`, or `designing`: pass each one's frontmatter and full text except the Captured and
   triage blocks, plus the repo files it cites. **Context:** the
   in-progress cards (id, stage, and the files they change -- their branch diff when there is
   one, else the files they cite), the
   **Live, to check** list, `<repo>/handoff.md` if present (Next Steps, Failed Approaches -- the
   board wins where they disagree), `GROOM-PLAN.md` and `STRATEGY.md` if present, settings
   `lane_cap` and `serial`, and the High-stakes gate's signal list. A card with `mode_by: you`
   keeps its mode. **Release bookkeeping** that every change touches (version file, changelog,
   generated manifest) never counts as shared files -- the serial ship queue reconciles it.
2. **Route** with `claude -p --allowedTools "Read,Glob,Grep"` (cwd = settings `repo`), passing
   all of the above, the rubric, and today's date. Look up files only for cards that could share
   a dispatch wave; give them as repo-relative paths, and `data` as the exact tables, buckets, or
   queues the change *writes*. It returns **strict JSON only**:
   ```json
   {
     "waves": [
       { "why": "one line",
         "items": [ { "id": "E04-S2", "mode": "solo|spike|subagent-it|dispatch-it",
                      "reason": "one line", "files": ["src/a.ts"], "data": ["table:orders"],
                      "spike": { "question": "...", "timebox": "2h" }, "proposed": false,
                      "plan_tasks": ["Task 1 title", "Task 2 title", "Task 3 title"] } ] }
     ],
     "held":    [ { "id": "E09-S1", "why": "high-stakes: <signal>" } ],
     "skipped": [ { "id": "E04-S5", "why": "waits on E04-S1" } ]
   }
   ```
   A spike that isn't a card yet has `"proposed": true` and a new id (next free under the epic).
3. **Gate.** `python3 ~/.claude/make-it/backlog/bin/check-plan.py <board> <plan.json> --lane-cap
   N` (add `--serial a,b` when settings has any; `--partial` with a filter). It enforces the hard
   rules: waves in list order; a dispatch wave is 3..`lane_cap` cards that share no files, data,
   or serial category and each name repo-relative files; `stakes: critical` cards are never in a
   wave; every unfinished `dependsOn` comes in an earlier wave; only candidates sit in waves, and
   every candidate is accounted for. Violations → re-run the call once with them appended; still
   failing → stop, print them, write nothing.
4. **Write.** `PLAN.md` at the board root; `mode:` on each planned card (never over
   `mode_by: you`); for each `subagent-it` card with no plan, a **draft** plan at
   `items/<epic>/plans/<id>.md` (Plan format, `status: draft`) linked as `plan:`. Proposed spikes
   are filed only under `--apply` (a `type: spike` card, plus the target card's `dependsOn:` on
   it). Drafts never run without the user's go. Bump `updated:` on touched cards, regenerate,
   sync (commit `plan: <summary>`). `--dry-run` prints and writes nothing.
5. **Report.** The waves, one line each, then the held block, what's skipped and why, and the
   proposals.

**`PLAN.md`:**
```markdown
# Run Plan -- YYYY-MM-DD  (scope: <filter>)
> /backlog-it plan · handoff.md + N open cards · finish soonest, every gate held · start/dispatch run it

## Waves
1. **solo** · E02-S1 · <title> -- <reason>
2. **dispatch-it** ×3 · E05-S1 · E05-S2 · E05-S3 -- <why they're independent>
   - E05-S1 -- <reason> · files: src/a.ts
3. **spike** (2h) · E04-S9 (proposed) → de-risks E04-S3 -- <question>
4. **subagent-it** · E04-S3 · <title> -- plan: items/EPIC-04-…/plans/E04-S3.md (draft) -- <reason>

## Live, to check first   (verify against the original report before wave 1)
## ⚠️ Held -- needs the alignment brief and an explicit go
## Skipped -- waits on
## Proposed (filed with `plan --apply`)
```

**`mode <id> <mode|auto>`** -- the human override: sets `mode:` and `mode_by: you`; `auto` removes
both so the next `plan` decides. Regenerate, sync.

### Plan format

The `## Task N` plan that `/subagent-it` runs (and `/resume-it` writes for 3+ ordered tasks).
With a board it sits next to its card, `items/<epic>/plans/<id>.md`, linked as `plan:` -- so a
plan is as private and as backed up as the board. With no board: `.make-it/plans/<slug>.md` in
the project, committed with the work.

```markdown
# Plan -- <title>
_Card: <id> · drafted YYYY-MM-DD · status: draft_

## Goal
## Global Constraints
## Task 1: <title>
- Files: <paths>
- Do: <the change>
- Test: <the check that proves it>
- Done when: <observable result>
## Task 2: <title>
```

`/subagent-it` runs only an approved plan: `status: draft` → the user's go → `status: approved`.
`task-brief PLAN_FILE N` reads the `## Task N` headings.

### `groom [filter] [--apply] [--dry-run] [--dispatch]`

**Throughput grooming:** reorder and reshape the board so more finishes sooner -- sequenced by
what **unblocks the most**, not by the priority field. **groom proposes; it changes the board
only under `--apply`** (and even then never splits or kills on its own). `filter` = a status,
category, priority, or epic id (default: all open cards).

**AI-powered by default.** Running `groom` (or `groom strategy`) is itself the opt-in to
multi-agent, high-effort reasoning: fan out one grounder per card with the **Workflow** tool and
think at high effort. Don't ask permission for it; the user doesn't need any extra keyword.

1. **Ground in code (reuse `reconcile`).** Run the reconcile ladder for every card in scope --
   `--dry-run` by default; `--apply` lets reconcile auto-apply as usual. For `partial`, name why:
   **unbuilt**, **untested**, or **unverified**.
2. **Clean the board.** From the verdicts: **close** finished cards, **merge** duplicates,
   **restatus** drift, **split** epics too big for one pass into the smallest shippable slices
   (the "minimum lovable loop"), **carve out** deferred work into its own card (never hold a
   delivered feature open), **flag** mis-scoped cards. Close / merge / restatus apply under
   `--apply`; **splits, deferrals, and kills are always proposals**.
3. **Sequence.** Pins first: a card with `pin: N` sits at rank N and everything else re-flows
   around it (two pins on one rank: smaller id first, flagged). Then the unpinned cards by:
   (a) **unblock value** -- what unblocks the most downstream work jumps the queue;
   (b) **near-done wins** -- `partial` cards a story or a few hours from done go early;
   (c) **parallel-safe batches** -- group cards whose evidence touches disjoint files, and call
   out overlaps; (d) **smaller `size`** breaks ties -- priority is only a weak signal;
   (e) **cut ruthlessly** -- name what's not worth doing now. `STRATEGY.md`, if present, makes
   foundational work outrank polish in (a) unless a card is pinned.
4. **Tag the ship track** from the standing preamble: **safe** (ships on the normal path) or
   **gated** (stops at the PR), and the **mode** from the [`plan`](#plan-filter---apply---dry-run)
   rubric (a card's own `mode:` wins). Keep in-progress small.
5. **Persist.** Write `GROOM-PLAN.md` at the board root; regenerate only if `--apply` changed
   something; sync (commit `groom: <summary>`); post a one-line digest with `slack-notify.sh
   raw`. **`--dry-run` prints everything and writes nothing.**
6. **Report.** A one-line state digest -- **Started N · Finished N · Not-started N · Stalled N**
   (stalled = `in-progress` with no commit or `updated:` movement in 14 days; list them) -- then
   the board deltas, the burn-down, the high-stakes block, **top 3 to start now** (never
   high-stakes), and **3 to drop or defer**. `--dispatch` then runs `dispatch` for the #1
   parallel-safe card (off by default).

**`GROOM-PLAN.md`:**
```markdown
# Groom Plan -- YYYY-MM-DD  (scope: <filter>)
> /backlog-it groom · grounded via reconcile (code+tests+live) · advisory (start/dispatch are the only ways work starts)

## Board deltas   (✅ applied · 📋 proposed)
- ✅ E14-S18 → done            -- built: code+tests+live
- 📋 split E04 → E04-S19..S21  -- too big to finish in one pass
- 📋 defer E05-S5              -- blocked until <condition>

## Burn-down   (top-down = most throughput · 📌 = pinned · ⚠️ = high-stakes, out of auto-run)
1. 📌 <id> · <title> · [safe|gated] · <mode> · pinned · blocks:<ids> / blocked-by:<ids> · est <size>
2. <id> · <title> · [safe|gated] · <mode> · <one-line reason> · blocks:<ids> / blocked-by:<ids> · est <size>

## ⚠️ Requires alignment before touching   (high-stakes -- not auto-runnable)
- ⚠️ <id> · <title> · why high-stakes · needs the alignment brief + an explicit go before `start`

## Start now (top 3 -- never ⚠️)   ·   ## Drop / defer (3)
```

Applied deltas are reversible and stamped on the card (the reconciliation block, `via: groom`).

**`groom move <id> <pos>`** (alias **`groom pin`**) -- the human's override. Sets `pin: <pos>`,
re-sequences honoring every pin (the card lands at `<pos>`; everything at or below shifts down --
the user never specifies the cascade), rewrites `GROOM-PLAN.md`, regenerates, syncs. `<pos>` is
`1`/`top`, any `N`, `bottom`, or `+1`/`-1`. Natural language maps here ("move E57 to the top" →
`groom move E57 1`). It applies immediately and re-sequences from the last verdicts without
re-grounding (run a full `groom` to re-ground). The pin sticks until `groom unpin <id>` (removes
`pin:`, re-sequences, regenerates, syncs) or `done`.

### `groom strategy [--apply] [--dry-run]`

The strategic pass over **all epics**: which work is **foundational leverage** and which is
**polish**, and the order that lets later epics build on the right foundations. Tactical `groom`
answers *what next and how*; `groom strategy` answers *what to build and why*. Always the deep
multi-agent pass (one analyst per epic via Workflow, high effort). Run it weekly or when choosing
direction, not on every check.

1. **State digest** -- Started · Finished · Not-started · Stalled, across every epic.
2. **North star** -- read the project's `CLAUDE.md` (its product vision) and the epics; state in
   2–3 lines the goal the analysis optimizes for. The user can override it.
3. **Leverage graph** -- per epic: what it **enables** and what it **depends on**, inferred from
   its goal and design doc (most `dependsOn` fields are empty) with the enabling edges cited.
   Leverage = how many epics it unblocks, direct and transitive.
4. **Tier + why** -- 🏛️ **Foundational** (high leverage, do first) · 💰 **Product-value**
   (directly advances the north star) · ✨ **Polish** (real but no downstream, defer unless
   cheap). Each with a one-line rationale tied to the graph and the north star.
5. **Strategic map** -- the foundational spine first ("build X before Y and Z because they build
   on it"), then product-value, then polish: `id · tier · leverage (unblocks: …) · north-star fit
   · rationale`. End with **3 highest-leverage to invest in next** and **3 to defer or kill**.
6. **Persist** -- write a dated `STRATEGY.md` (north star + graph + map) at the board root; sync.
   Read-only by default; `--dry-run` writes nothing. `--apply` also stamps the inferred
   `dependsOn:` and a `tier:` note onto cards and restatuses drift (reversible, `via: groom
   strategy`); splits and
   kills stay proposals.

### High-stakes gate

Governs `groom`, `groom --dispatch`, `plan`, and `dispatch`. A card is **high-stakes** if `stakes:
critical` is set, or it touches -- by signal, not guesswork -- any of:
- anything sent to or filed with an outside party (a `serial` category)
- auth, permissions, secrets, or session handling
- schema, migrations, or row-level / tenant isolation
- money: billing, payments, metering
- deletion or bulk moves of live data

**The rule:**
1. Never auto-started or dispatched. `dispatch` skips it, takes the next safe card, and logs the
   skip and why.
2. A high-stakes verdict needs the **CODE rung actually read** -- the card's status is a claim to
   verify, never a fact.
3. `start` leads with an **alignment brief**, grounded in code, ahead of the standing preamble:
   what exists now, what already works (and the proof), what would change (touch the working
   path vs. add alongside it), the blast radius, and a safe place to rehearse (never live data).
   Then wait for an explicit go.

It renders with ⚠️ on the board and in its own block of the groom plan, outside the runnable
lane. It only removes cards from auto-run paths -- it never starts or changes anything itself.

### `undo`

Revert the last board commit with `git -C <board> revert --no-edit HEAD` (never a history
rewrite), regenerate, sync, and print `✓ Reverted the last board change.` It reverts whatever
the last commit was; running it twice reverts the revert. Board in its own repo only.

### `regen-board`

`regen-board.py` rebuilds `BOARD.md` from frontmatter, so nothing transient is lost when any
session rebuilds it: the Waiting on you block, ⚠️ for high-stakes, ⚡ breakfix, 🔬 spike, the stage, a size chip (`[M]`),
a pin marker (`📌2`), and the mode (`→solo`). One compact line per card. An epic of more than 30
cards shows its done cards as a count (`show <epic>` lists them) and groups its open cards by
`category:`, so a long-lived Bugs epic stays readable.

---

## Design-doc template

Every `design.md` follows this where it applies (skip what doesn't fit, keep the spine). Design
docs are for detail and for communicating with stakeholders -- never a gate.

**Design toward:**
- **Tame complexity -- surface it, don't hide it.**
- **A complexity ladder.** A low-effort path for the common case (Tier 0); the genuinely hard
  parts in an opt-in advanced layer (Tier 1/2) -- present and honest, never forced.
- **Augment, don't replace.** Extend what exists; take no current ability away.
- **Value from the first use.** No "configure everything first" wall.
- **Human-gated where it matters; provenance everywhere.** An approval gate for consequential
  actions; every output shows its source and confidence.
- **Beautiful, smart, elegant; low operational and management load;** scale through reuse.

**Sections:** 1. Problem & context · 2. Goals / non-goals · 3. Design principles for this item ·
4. Architecture · 5. The complexity ladder · 6. First-use path · 7. Core flows, data and quality,
accuracy gate · 8. Provenance & audit · 9. Scale and operations · 10. Security / legal risk ·
11. Phasing → stories (name the minimum lovable loop) · 12. `[reconcile]` markers for
integration points to confirm against real code (never invent APIs) · 13. Open questions and
risks.

## Grounding (verify, never block)

Verify before you assert -- but never gate, pause, or block a run; the user edits the prompt
and runs it regardless.

- **Ground factual claims when it's cheap** -- read the code, grep call sites, look at the
  screen, query the data. Design docs and memory go stale; live code, UI, and data are ground
  truth.
- **Flag, don't block.** If you can't confirm something, say so and proceed. Never present a
  guess as fact.
- **What, why, where.** What it does, why, and where it's used (call sites, blast radius).
- **Depth in proportion to consequence** -- more for live, destructive, or customer-facing work.

---

## Writing a card

Write cards only through `card.py`, never `printf`, `sed`, or a shell glob:
- `card.py append <id> <section>` -- text on **stdin** (so `%`, `*`, `$` and quotes arrive intact)
  goes under `## <section>`; an existing section grows, else a new one is added at the end.
- `card.py set <id> key=value …` -- sets frontmatter fields; `key=` removes one (`decision=`). Writing or clearing
  `decision` also clears `answers:` unless the same write sets `answers=`. `id` is never settable.
- `card.py new <epic>` -- a whole card on stdin with `id: NEW`; it gets the next id **after a pull**,
  a slugged file name, and `parent:` / `created:` if missing. Prints the new id.

Call it as `card.py --board "$BOARD" --project "$PROJECT" <verb> …`. Every verb reads its stdin
first (never from a terminal; empty text is refused), then takes the board's writer lock (one card
writer per board at a time, so parallel lanes never lose a write or share an id), pulls (a board in
its own repo; a failed pull, a detached HEAD or a half-done rebase writes nothing), finds the card
by its `id:` (exactly one match), writes the whole file then swaps it in, bumps `updated:`,
regenerates `BOARD.md`, and syncs as below (`--no-sync` leaves the commit to you). If another session
pushed first, it rebases onto theirs, regenerating `BOARD.md` when that is the only conflict, and
never leaves the board mid-rebase. **Any write that didn't sync exits non-zero** with the reason.
`sync-prs.py` writes through the same function, under the same lock.

## Sync

- **Board in its own git repo** (e.g. `~/.claude/backlog`, or shared by several projects):
  `git -C <board> add -A && git commit -m "<what changed>" && git push` after every mutation, so
  nothing is lost if the machine dies.
- **Board inside the project** (the default): stage only the board's paths; the changes ride
  with the current branch's commits. Never commit to the default branch for a card update.

## Slack

Optional, see [Settings](#settings). Post **after** sync and never block on it:
- `start` → `slack-notify.sh started <id> "<title>" "<category>" "<priority>"`
- `done` → `slack-notify.sh done <id> "<title>"`
- capture, stage changes, and groom/reconcile digests → `slack-notify.sh raw "<text>"`

## Sharing one board

Point several projects -- or a personal board in the user settings -- at the same `board` path.
The format is the only contract: the same folders, the same frontmatter, the same `BOARD.md`
renderer. Whoever writes last regenerates `BOARD.md` from the cards, so nothing is lost. A
project that wants its own board instead sets its own `board`.

---

## Wiring into the other -it skills

When the **project** has `.claude/backlog-it.json` or `.claude/backlog/BOARD.md` (the user-level
settings file alone does not switch these on):

| Skill | Hook |
|-------|------|
| `/resume-it` | Starts from the board: **Now fixing** lanes first, then **Next up** |
| `/dispatch-it` | Takes its lanes from the board -- non-overlapping, up to `lane_cap` |
| ship (`ship-it-guide.md`) | On merge: stage **Live**. After the live check: **Checked**, then `done`. `/resume-it` and `/wrap-it` catch up with `reconcile --prs` (the card's `pr:`, never a guess) |
| `/wrap-it` | Updates each touched card and regenerates the status line alongside the handoff |
| `/debug-it` / `/fix-it` | A new bug gets a card (`stage: Reported`) before any fix work |

**The handoff is the exception: the project's own board counts, settings file or not, and so
does the personal board inside its own `repo` folder.** A board that belongs to another project
never feeds a handoff, so each project's `handoff.md` stays its own. `/clear-it` writes
`handoff.md`'s Next Steps as card ids under a copy of the status line, and files a card
(capture, no questions) for any next step that has none.
`/resume-it` re-reads those cards when it reads the handoff. Where the two disagree, the board
wins -- so what to work on next lives in one place.
