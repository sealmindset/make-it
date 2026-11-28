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

Every key is optional. The first file found wins **as a whole** (keys are not mixed across files).
This is the one rule for which board a folder uses. It lives in code, `find_board` in
`regen-board.py`; `regen-board.py --where` prints its answer as JSON (`board`, `settings`, `root`,
`new`, `note`), and every skill and helper finds the board through it:

1. **Project:** `.claude/backlog-it.json` in the project root (committed).
2. **Project board, no settings file:** `.claude/backlog/` exists → use it with defaults.

   The **project root** is the nearest folder at or above the current one that has either of
   these. The search never reaches the home folder (whose `.claude/` holds the user file below)
   and never goes above a git repository's top folder, so a repository cloned inside another
   project does not take that project's board. A project's board is used from its root and from
   any folder below it -- except that a board in a folder *above* the personal board's `repo`
   never takes over that repo: inside it the personal board wins, and one line names the other.
3. **User:** `~/.claude/backlog-it.json` -- one personal board, used only from its `repo` folder or
   a folder below it (e.g. a board in its own repo at `~/.claude/backlog`, `repo` = the code it
   tracks). From any other folder it is not used, and one plain line says so: `Not using the
   personal board in <board>: it belongs to <repo>, and this folder is outside it.` A user file with
   no `repo` (or a relative one, which would mean wherever you stand) is used nowhere until a full
   `repo` path is set, and the line says that instead -- a board tied to
   no folder would show up in every folder.
4. **Defaults** -- no board yet. `new` is where one may be set up: `.claude/backlog` in the git
   root of this folder (the nearest folder above with `.git`), else in this folder. Never in the
   home folder, inside `~/.claude`, on a board that already exists, or in a folder that holds the
   personal board's `repo` (a board there would take the repo over): then `new` is empty, one line
   says why, and nothing is set up. `/backlog-it` shows only `board`; `new` is used only to set up
   a new board.

`$BACKLOG_DIR`, when it is set, is an explicit choice and always wins. When it is not the board the
rule above picks, one line says so: `Using the board in $BACKLOG_DIR (<path>), set by hand: it is
not this folder's board (<board, or "this folder has none">).`

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
| `repo` | the project root | The code that `reconcile`, `groom`, and `groom strategy` check cards against. In the user file it is also the only folder (and those below it) the personal board is used from. |
| `lane_cap` | `3` | The most bugs fixed at once (see [Parallel lanes](#parallel-lanes)). |
| `serial` | `[]` | Card `category:` values that always run **one at a time** -- work whose mistakes reach people or systems outside the team (payments, outgoing email, anything filed with an outside party). |
| `models` | `{"route": "opus", "ground": "opus", "judge": ["claude-fable-5-2", "claude-fable-5-1"]}` | Which model does which AI step (see [Which model does what](#which-model-does-what)). Each value is a model or a list tried in order. Any key left out keeps its default. |

### Which model does what

The board's AI work is split by what a mistake costs, not run on whatever the session uses.
Mechanical and gated steps take **`route`/`ground`** (default Opus): a checker or a script catches
their slips. Pure-judgment steps that nothing downstream can check take **`judge`** (default Fable
5.2, then Fable 5.1). Pass the name as `claude -p --model <name>` or as the agent's / Workflow
agent's `model`.

**Availability.** A list is tried in order: the first model the deployment serves wins (a
"not available on your deployment" error means try the next). Check once per run with a one-word
`claude -p --model <name>` call, not per agent. When no `judge` model is served, judge steps run on
`route` and the run says so in one line ("Fable isn't enabled on this deployment -- grooming on
Opus"); never a silent switch.

| Step | Model | Why |
|------|-------|-----|
| `plan` routing call | `route` | `check-plan.py` gates every hard rule; a slip costs one re-run |
| `plan --with-deps`, or 100+ candidates | `judge` | suggested links and long chains are judgment the gate only shape-checks |
| `groom` grounders (one per card, the reconcile ladder) | `ground` | evidence gathering against code and tests; many cards |
| `groom` steps 2-5 (clean, needed or not, sequence, tag, persist) | `judge` | one agent with every grounder's verdict decides what unblocks the most, what is no longer needed and what to cut |
| `groom strategy` analysts and the map | `judge` | inferred epic dependencies and foundation-vs-polish calls go wrong quietly |

Capture triage, `reconcile` and `info` keep the session's model.

**Slack (optional).** The webhook URL is a secret, so it is **never** in the settings file. It is
read from `$BACKLOG_SLACK_WEBHOOK`, else `<board>/.slack-webhook` (gitignored). With neither,
notifications are a silent no-op and the board works the same.

**Helpers** (installed with the framework, no hardcoded paths):
- `~/.claude/make-it/backlog/bin/regen-board.py <board> [--project NAME]` -- renders `BOARD.md`.
- `~/.claude/make-it/backlog/bin/status.py <board> [--project NAME] [--needs-you]` -- prints the `status`
  report (read-only; shares `regen-board.py`'s rules); `--needs-you` prints only its Needs you section.
- `~/.claude/make-it/backlog/bin/sync-prs.py <board> --repo <repo> [--dry-run]` -- `reconcile --prs`:
  closes cards whose fix is merged, released and passing its checks (needs `gh`; writes the cards, the caller syncs).
- `~/.claude/make-it/backlog/bin/shrink.py {combine [filter] | bundle <ids> | part-done <id> | unbundle <id> | reopen <id> | stamp <id> --by groom\|you | expire [--dry-run]}` --
  what makes the pile shrink: candidate groups to combine, bundles, reopening a fix that did not hold, and closing
  quiet cards (no AI call; see [`combine`](#combine-filter), [`reopen`](#reopen-id-what-was-seen), [`expire`](#expire---dry-run)).
- `~/.claude/make-it/backlog/bin/card.py {append <id> <section> | set <id> k=v … | new <epic>}` -- the
  one way to write a card (see [Writing a card](#writing-a-card)).
- `~/.claude/make-it/backlog/bin/scope.py <board> [<filter>] [--with-deps]` -- which cards a `plan` or
  `groom` covers: the filter's cards and, with `--with-deps`, the chain they wait on across epics
  (read-only JSON; shares `regen-board.py`'s waiting rule).
- `~/.claude/make-it/backlog/bin/check-plan.py <board> <plan.json> --scope <scope.json> …` -- the
  `plan` gate (see [`plan`](#plan-filter---with-deps---apply---dry-run)).
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
├── .last-seen.json              # when the first screen was last opened, and what the board held then; never committed
├── .gitignore                   # contains .slack-webhook and .last-seen.json
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
dependsOn: [E02]          # optional -- not started until these are done (see What a card waits on)
conflictsWith: [E07]      # optional -- not dispatched while these are in progress
decision:  3 import rows failed twice; the rest went in. Retry them, or refile by hand?   # optional -- plain context, then the one question this card waits on (see Waiting on you)
answers:   Retry -- runs it again tonight | Refile -- you re-enter the 3 rows   # with decision: -- 2-4 named answers, split by |
pr:        [1590]         # the fix PR(s), set by the fixing lane when it opens one; another repo's PR as its URL
signal:    worker log shows 'filed: 2/2' for a new filing   # optional, one line: what a real run would show if the fix holds; the lane writes it with the PR. Nothing waits on it
reviewed:  2026-11-24 ready 1a2b3c4   # optional: the pull request's last review -- `<date> ready <commit it read>` or `<date> not ready`; the lead writes it. The first screen says "reviewed" only from this
sat:       2026-11-25 answered 1a2b3c4d5e6f   # set by `sitting`: the day this held card was answered (or `not-now`) at a weekly sitting, and a print of the card as it then was; any change to the card brings it back
files:     [src/export.py, src/csv.py]   # optional: the files this card would change, repo-relative -- the ONE place a card lists them (see combine)
bundles:   [E07-S3, E07-S9]   # a bundle card only: the cards it does as one piece of work (see combine)
bundledIn: E07-S12        # a part of a bundle: the bundle card that carries it; the part closes only on its own check
ground:    same file | same root cause | same goal   # a bundle card only: why its parts go together
closed_as: shipped-tests-pass | not-needed | expired | unbundled   # with status: done -- how it closed; absent = plain done
expires:   ok             # a judge's mark that the card may close after 30 quiet days, with expires_why:, expires_by: and expires_of: (see expire). No mark, never
reopened:  2026-11-25     # set by `reopen`: a fix that did not hold, or a card someone brought back; it never expires
mode:      solo | spike | subagent-it | dispatch-it   # set by `plan` (see the mode rubric)
mode_by:   you            # set by `mode <id>` -- `plan` never overwrites a mode you chose
plan:      plans/E04-S2.md   # the card's `## Task N` plan, relative to the epic folder
reconciled: YYYY-MM-DD    # set by reconcile on its first auto-apply
created:   YYYY-MM-DD
updated:   YYYY-MM-DD
---
```

Status flow: `backlog → designing → ready → in-progress → blocked ⇄ in-progress → done`.
Unknown keys are kept; missing optional keys are fine.

**What a card waits on** -- one rule, the same for `BOARD.md`'s Next up, `status`, `plan`, `groom`
and `dispatch` (`regen-board.py`'s `needs`): the cards named in its own `dependsOn` **and in every
ancestor's** -- an epic's `dependsOn` holds for each card under it. An id with children stands for
its open cards: `dependsOn: [E02]` waits until every open card under E02 is done, and an epic whose
cards are all done waits on nothing. A card never waits on itself or its own ancestors; an id not
on this board doesn't block (it may live on another board). A story with no `parent:` belongs to
its folder's epic. Never delete a card on `done` -- the
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
3. **Check the triage output -- the report is never lost.** Save exactly what the call gave back
   to a file (no file when it failed or timed out) and pipe the raw text, word for word, to
   `card.py capture <file>`. No AI takes part in this step.
   - **Bad output** (not JSON, empty, a refusal, missing or bad fields, an epic that is not on the
     board) → `card.py` files the report itself: under the Bugs epic (made on first use), a bug at
     Reported, the raw text quoted line for line under `## Captured`, marked `not sorted yet --
     triage failed: <reason>`. It prints the card by its title and id. Go on to step 5's notice,
     and say in the reply that the report is filed but not sorted yet, and why.
   - **Good output** → it prints `triage ok` and writes nothing: go on to step 4. If step 4's write
     then fails with nothing written, pipe the raw text to `card.py capture` with no file.
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
7. **Offer a bundle when the new card clearly belongs with an open one.** Run `shrink.py combine <the
   new id>` (read-only). If it shows a same-file group, or triage named a likely duplicate, add one
   more one-click question to step 6's ask: "Do this together with <title> (<id>)?" with the
   ground and the evidence in a line -- `Together -- one piece of work, each card keeps its own
   check` | `Apart -- they stay two cards`. Only on "Together" make the bundle
   ([`combine`](#combine-filter)). No group, no question.

---

## The bug queue

Bugs are `type: breakfix` cards under a **Bugs** epic, each with a `stage:`:

**Reported → Cause found → Fix ready → done**

| Stage | Means | Set by |
|-------|-------|--------|
| Reported | card exists, cause unknown | capture / `/debug-it` intake |
| Cause found | root cause confirmed with evidence | `/debug-it` Phase 3 |
| Fix ready | fix + test on a branch, PR open -- or merged and waiting for its release | the fixing lane, which records the PR in `pr:` |
| *(done)* | **released, tests pass**: the PR is merged, a release carries it, and every check on that release passed | `reconcile --prs`, from facts `gh` gives -- `status: done`, `closed_as: shipped-tests-pass` |

**Shipped means done** (the owner's rule, 2026-11-24): "Assume it's fixed unless any and all tests
prove otherwise. If during usage it was not, I'll file or you reopen the card." No card waits to be
confirmed by a real run: there is no "live, to check" pile. The closed card says what proved it, that
no real run confirmed it, and how to reopen it ([`reopen`](#reopen-id-what-was-seen)). A card left at
the older `Live` or `Checked` stage shows under Shipping until `reconcile --prs` reads its release,
and then closes by the same rule. **Jump the line** only for harm happening now: damaged
data, a wrong outgoing message, anything in a `serial` category. Everything else takes its
place. Improvements are not bugs -- they wait until the bug list is empty. One message to the
reporter per finished card.

**The status line** at the top of any epic with bug cards in `BOARD.md`:
- **Now fixing** -- `in-progress` at Reported / Cause found, not waiting on you (one entry per lane)
- **Shipping** -- Fix ready: the fix is in review, or merged and waiting for its release's checks
- **Next up** -- the top `backlog` bug that can start (not high-stakes, nothing it waits on
  unfinished, not waiting on you, not a part of a bundle), by priority, then age

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
  Fix the card before asking; to reword a decision, rewrite `decision=` and `answers=` in one write
  (a `decision=` alone drops the old answers).
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
  how the fix is proved live as `signal:` (`card.py set <id> stage="Fix ready" pr="[N]" signal="…"`) and the files it
  changed as `files:`; the status line lists every lane. A lane whose card is a bundle records each part's own
  check as it passes (`shrink.py part-done <part id>`, what showed it on stdin).
- **A lane that stops hands its card back** -- done, blocked, or out of turns: the next stage, a
  `decision:` with its `answers:`, or `status: backlog` with a note. Now fixing is read from the cards, so a card left
  behind looks like a running lane; `status` flags a Now fixing card idle 2+ days as "lane stopped?".

---

## Subcommands

| Command | What it does |
|---------|--------------|
| *(none)* / `board` | The first screen: the one thing to do next with its choices, only what needs you, what changed since last time, and the trend (see [The first screen](#the-first-screen)) |
| `list [<filter>]` | The board compactly: by status (in-progress → ready → blocked → designing → backlog → done), epics with children nested, `title (id) · [category] P#`; with a filter, only that status, category, priority, or epic id |
| `show <id>` | The card; for an epic, its children (id · status · title) and design docs |
| `info [<card>] [<focus>]` | The card in plain terms: the problem, the impact if it isn't fixed, and why it's fixed this way. Read-only |
| `epic` / `story <epic>` / `task <parent>` `<idea>` · `add` | Add planned work (clarify first) |
| `capture <text>` · `bug <text>` · plain text | Capture (card first, AI triage) |
| `start <id>` | Recall the card as an editable prompt, then run it |
| `status` (no id) | Where the board stands: in flight, up next, burn-down + forecast, needs you, drift, epics, cycle time (see [`status`](#status)) |
| `move <id> <status>` · `status <id> <status>` · `stage <id> <stage>` | Change status / bug stage (a stage change also posts `slack-notify.sh raw`) |
| `done <id>` | End summary, `status: done` |
| `combine [filter]` | Propose bundles: cards that go together as one piece of work, each keeping its own check. Nothing combines without your pick |
| `unbundle <id>` | Put a bundle's cards back in line as they were (a bundle's id), or take one card out (that card's id) |
| `reopen <id> <what was seen>` | Put a closed card back in line, with your words kept on it |
| `expire [--dry-run]` | Close the quiet cards a judge marked safe to close (30 quiet days; no mark, never; never a safety one); `--dry-run` only lists them |
| `reconcile [<id>\|all]` | Check cards against the code, tests, and live system; `--prs` closes cards whose fix is released with passing tests, then sorts every open pull request by what it needs |
| `sitting` | The weekly sitting: the three to five held high-stakes cards that free the most other work, one question each; the answer goes on the card (see [`sitting`](#sitting)) |
| `release` | One release a day: every pull request that is ready goes out as one numbered release (see [One release a day](#one-release-a-day)) |
| `dispatch [--dry-run]` | New bugs into free lanes, then `PLAN.md`'s next wave, else the bug line, else the next safe item; ends with what needs you |
| `plan [filter] [--with-deps] [--apply\|--dry-run]` | Route each card to solo, spike, `/subagent-it` or `/dispatch-it`, in waves → `PLAN.md`; `--with-deps` also plans the cards the filter waits on, across epics |
| `mode <id> <solo\|spike\|subagent-it\|dispatch-it\|auto>` | Choose a card's mode yourself (`auto` hands it back to `plan`) |
| `groom [filter] [--with-deps]` | Propose the order that finishes the most, soonest, and say which cards are no longer needed; `--with-deps` adds the chain behind the filter |
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
   card's **mode line** if it has a `mode:` (see [`plan`](#plan-filter---with-deps---apply---dry-run)); for
   `solo` and `spike`, drop the preamble's opening **Launch subagents.**
2. **Show the assembled prompt and let the user edit it** -- anything, including the preamble.
   This is an edit step, not an approval gate. End with one line on what `go` starts -- the card,
   its mode, where it runs (a branch or worktree) -- and the answers `Go -- runs it as shown` or
   `Edit first -- say what to change`; no bare "OK to proceed?". A high-stakes card's go is the
   pick its alignment brief asks for ([High-stakes gate](#high-stakes-gate)).
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
>   open PR with one ask: what the PR changes, the evidence (the green run), what it touches and
>   how to roll it back, anything unusual, and the one thing to check -- answered `Merge -- ships
>   on the normal path` or `Hold -- stays an open PR`.
> - **Potentially harmful or app-impacting** → everything up to the **open PR**, then **STOP for
>   explicit human approval before merge or deploy.** Ask once: what the PR changes, the evidence
>   (the green run), what it touches and how to roll it back, what is unusual (which trigger below
>   it hit), and the one thing to check. The human picks the specific -- `Merge only --
>   no deploy` or `Merge and deploy -- to <environment>`, naming the environment -- never a plain
>   yes; no answer, no merge. Triggers (non-exhaustive): anything
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
>   `/subagent-it`. No approved plan yet: draft it first, show it, and ask for the go
>   as [Plan format](#plan-format) says; on the go, mark it `status: approved`, then run it.
> - `dispatch-it` -- **Mode: dispatch-it (one lane).** This card is one lane of a parallel wave:
>   its own worktree, the `/debug-it` method for a bug, no files outside its lane. `dispatch`
>   launches the whole wave; `start` runs just this lane.

**For whoever runs a started card:** "deploy" means the project's real production path, with the
project's own smoke tests; if a deploy goes wrong, prefer the project's rollback path. Two
conditions halt shipping: red tests, and potential harm.

### `info [<card>] [<focus>]` -- a card in plain terms

What problem a card solves, what happens if it isn't solved, and why it's being solved the way it
is -- in plain English, in the same shape every time. Read-only: it never writes a card, the
board, or a lane's worktree, so it's safe to ask while lanes run.

**Which card.**
- `info E02-S5` -- the card with that id, of any type.
- `info argo-it secret scan` -- the card whose title best matches the words. Several match → ask
  which in one AskUserQuestion (id · title · stage, up to 4); none → say so and name the 3 closest
  titles.
- Words after the card are a **focus** (`info E02-S5 why is Task 3 taking so long`): it decides
  what the three parts dwell on, never their headings.
- Bare `info` -- the card this session is working on (its lane, run or `start`). Several → ask
  which; none → explain this session's current work in the same shape yourself, and say it isn't
  on a card.

**Where it reads** (see [Grounding](#grounding-verify-never-block)): the card (frontmatter, body,
`## Answers`, `## Finding`, reconciliations), its epic and design doc, its `plan:`, its PRs
(`gh pr view`: state, checks, body), and for a card in a run, the run's ledger
(`.make-it/sdd/progress.md` in the worktree on its PR's branch or named after the card, or
`.make-it/sdd-archive/<id>/` once merged) with the owner calls in its briefs. A claim about the
code is checked against the code when that's cheap; one that can't be confirmed is said as such.

**Out of the way.** Hand the reading and the writing to one read-only background subagent (Opus or
Fable: this is writing for a person). Give it the paths (card, board, repo), the focus, and what
this session knows that the files don't (a step still running); it returns only the finished
answer. Carry on with whatever was running. When it arrives, count its words (`wc -w`): over 550,
send it back once -- "Cut this to under 550 words: keep the three parts, drop the least important
bullets and sentences, add nothing" -- then print what you have.

**The answer** -- this shape, every time. It gives quick understanding, not analysis: about one
screen (roughly 400-550 words), answering the question asked and nothing more. Read deep, write
short: the run's record and the owner's calls are read to know why the work is shaped as it is
now, never retold. **No history of the card** -- not how it was found over time, review rounds,
dated calls or who decided what -- and no status or next steps unless the focus asks. Check
quietly: mention only what couldn't be confirmed, in a few words.

> Here's <id> in plain terms.
>
> **The problem**
> What is wrong or missing, and what found it and when, in a sentence or two. Then one bullet per
> main thing a person sees or can't do, a sentence or two each, up to about 7.
>
> **Impact if it's not fixed**
> - Who it hits: who is affected and who isn't, and whether data, money or security is at risk.
> - The wider risk: what it endangers beyond those people (legal, sales, trust, work it blocks).
> - How far it reaches: which users, pages, projects or environments.
>
> **Why it's being fixed this way**
> One bullet per main choice, up to about 7 (fold or drop the small ones), in the order the work
> runs: the choice in a few words, then why in a sentence or two -- the order of the tasks,
> deliberate trade-offs or widenings, what is reused instead of added, how it's proved (tests first,
> reviews, its PR), and what needs a person. No fix chosen yet: the first bullet says so, then what
> is known and what is still open (a `decision:` it waits on).

Plain bullets of one or two sentences: no sub-bullets, no bold inside them. No jargon without a
gloss, another card by its title rather than a bare id, dates as dates. For an epic, the problem is
its goal, and the last part is how it's split into cards and in what order.

### The first screen

Bare `/backlog-it` (and `board`) prints one screen of at most about 25 short lines, from
`status.py --first`: read-only facts and a written rule, no AI call, so the same board gives the same
answer. The skill prints it as-is and asks the choices as one select; it never picks for itself.

1. **DO NEXT** -- one plain sentence: what the board recommends now, and why, with the count in the
   sentence and each card or pull request it means on its own short line beneath, by title with id.
   Then the choices, 2-4, each `Name -- what happens`: the recommendation first, marked
   Recommended, with the strongest argument against it on the line under it (`against: …`); then
   the next steps of the rule that also hold; `Full status` last. No line is longer than about 110
   characters. Under the choices, one line counts the open pull requests by what each needs
   ("Pull requests: 2 ready · 1 out of date · 1 stalled"; see [After every merge](#after-every-merge-every-open-pull-request-is-sorted)).
2. **NEEDS YOU** -- each question waiting on you as one line (the card's title with its id, then its
   `decision:`: what waits, and the question), the first three, or "nothing waits on you". Held
   high-stakes cards are a count, then the three to five that free the most other cards (the ones
   for the weekly sitting), never the whole list. The same line says when a sitting is due (none
   on record in the last 7 days), or the day the next one is; while one is due, "Hold the sitting"
   is always one of the choices under DO NEXT. Then one line counting the running list: its
   open lines and how many areas they are in. Then, only when there are any: **Reopened** -- how many
   fixes did not hold, by title with id (the signal that matters most); and **Quiet cards** -- how many
   marked cards will close by themselves in the next 7 days, with the command that lists them (or,
   while the screen has room, that no card is marked yet). When the running list is shown too, the
   two counts share its line, so the fullest screen keeps to 25 lines without hiding a question or
   the held list.
3. **SINCE YOU LAST LOOKED** -- three lines: what shipped (cards closed as not needed are counted
   apart), what was found, what got stuck. "Last looked" is the last time the skill showed this
   screen: `--seen` writes `<board>/.last-seen.json` (the time, and the ids that were open, done and
   stuck). The file never reaches the board's git: a new board's `.gitignore` names it, and for an
   older board the helper adds the one line to the repo's own `.git/info/exclude`, which is local
   and never committed. With no such file, or one that cannot be read, the three lines cover the
   last 24 hours; when the look cannot be recorded (a read-only folder), the screen still prints and
   says so in one line. A card closed as done or as `shipped-tests-pass` counts as shipped; only
   `closed_as: not-needed` counts as not needed; `closed_as: expired` is counted apart ("2 expired": how
   many quiet cards closed by themselves since you last looked); any other `closed_as` value is
   named as it is. A bundle is named once, with each card it does on its own line beneath (`part: …`).
4. **TREND** -- one line: cards opened and closed this week, whether the pile grew or shrank, and the
   single biggest reason ("mostly new bugs (70 of 135)", "with 6 fixes shipped").

**The next-thing rule** -- the first step that holds is the recommendation:

| # | When | The board says |
|---|------|----------------|
| 1 | A card has a question for you (`decision:`) | answer it |
| 2 | An open pull request is ready as far as GitHub shows: no longer a draft, no conflict with main, every check finished and passed, and not behind main | release it: confirm its review, bring it up to date if needed, then release |
| 3 | Open pull requests are stuck or out of date: behind or in conflict with main, or a draft, a failing check or a running check with no change for 2 days | sort them |
| 4 | `PLAN.md`'s next wave can start (no card in it held, waiting, blocked or already running) and a lane is free | start that wave; if an open pull request changes a file one of its cards names, say so and offer to start the others |
| 5 | The plan is stale: every wave is done, or its next wave is stuck, or more than half the cards that can start are not in it | plan |
| 6 | More cards were opened than closed two weeks running (and the last groom is at least 7 days old), or the last groom is over 14 days old | groom |
| 7 | A card can start and a lane is free. While a plan is in force only a card it does not list: the plan keeps the order of the ones it does | start the next safe card |
| 8 | A weekly sitting is due: a held card can be brought, and none is on record in the last 7 days | hold the sitting (it needs your time, so it is the recommendation only when no earlier step holds; it is always offered as a choice) |
| 9 | None of the above | wait, and why (a wave is running, the lanes are busy, or nothing can start safely) |

The numbers are named constants at the top of `status.py`, each with its reason (`PR_STALL`,
`PLAN_STALE`, `GROW_WEEKS`, `GROOM_AGE`, `GROOM_REST`, `SIT`, `SIT_EVERY`, `SIT_REST`, `STALL_HOURS`). Pull requests come from `gh pr list`
in `repo`; a pull request named in a card's `pr:` is called by that card's title. With no `repo` or
no `gh`, steps 2 and 3 are skipped and the screen says so. A pull request that is simply moving (a
fresh draft, checks running) is not mentioned.

**What "ready" can and cannot know.** The screen says only what it can read. "Behind main" is worked
out by comparing the pull request's head with main (`gh api …/compare`), because a repo with no
branch rule never reports it; a pull request that is behind goes to step 3 with how far, and when
the comparison cannot be read the screen says "could not tell whether it is up to date". GitHub
holds no review in a repo where the owner's own agents review, so the screen never says a pull request is reviewed unless its card says so:
after each review the lead records it with `card.py set <id> reviewed="<date> ready <commit>"`
(the commit the review read) or `reviewed="<date> not ready"`. The screen reads "Review: recorded
on its card for this version" only when the value says ready and that commit is the pull request's head
now. A ready review of an older commit reads "recorded for an earlier version, so confirm it
again"; a not-ready one reads "its last review said not ready"; a value in any other shape counts
as no review. In all three the choice keeps "I confirm its review". Step 4 says what is running in plain
words: work that moved in the last 2 days is named, work marked in progress but quiet is only
counted, and a quiet card is never the example. It checks the files each
wave card names in `PLAN.md` against the files of every open pull request (`gh pr view --json
files`); when either cannot be read it says so. When some of the wave's cards share a file with
an open pull request, starting the others is the recommendation; when every card does, the
recommendation is to wait for that pull request, or release it, first.

### `sitting`

Held high-stakes cards never start by themselves, so they pile up unless someone brings them. The
owner's choice (2026-11-24): a short weekly sitting, the three to five that free the most other
work. `sitting.py` picks, says when one is due, and records the answers -- no AI call; the skill
writes each question (`/backlog-it`, Step 2c).

- **The pick** (`sitting.py pick`, read-only; the rule is `sitting` in `status.py`): the held cards
  -- high-stakes, open, with no question already waiting (those are under Waiting on you). The card
  that frees the most other cards comes first (every open card that waits on it, directly or through
  a card or epic it sits under), then the higher priority, then the older card. A bundle counts once:
  the bundle is brought, never its parts. At most five (`SIT`). The rest wait for a later sitting.
- **Due** (`sitting.py due`): a card can be brought, and no sitting is on record in the last 7 days
  (`SIT_EVERY`). The first screen says so in one line and offers one choice.
- **Each card is its own question**, never batched (`approval-block.md`): what it is by title with
  id, what waits and why in two plain sentences, 2-4 named answers that are the specifics, one
  Recommended with its strongest counter-argument, and always "Not now".
- **The record** (`sitting.py answer <id> "<answer>"`, what it does on stdin): only one of the
  card's own `answers:` names -- the skill writes the question and its answers on the card before
  asking -- so a plain yes is refused. One line under
  `## Answers` -- the date, the answer by name, what it does -- and `decision:` / `answers:` cleared.
  The card is then marked, for example `sat: 2026-11-25 answered 1a2b3c4d5e6f`: the day, and a print
  of the card as answered. An answered card is not brought again while it is unchanged.
- **Not now is kept** (`sitting.py not-now <id>`): written on the card the same way, and the card
  stays out for 14 days (`SIT_REST`), so it is not asked two weeks running. Any change to the card
  -- a new note, a new priority, new evidence -- brings it back at once.
- An answer starts nothing. Starting an answered card is `start <id>`, with the high-stakes gate
  as it is.

### One release a day

The owner's choice (2026-11-24): one release a day carrying that day's reviewed fixes, not one
release per fix. Each release used to move main, so every other branch had to rebase, and every
rebase clashed in `CONTENT_MANIFEST` because every branch had regenerated it.

`scripts/release-day.sh` (in the make-it repo; a project without it uses its own release steps):

1. takes only pull requests the sort calls READY -- into main itself (a stacked one, based on
   another branch, would bring that branch's unreviewed commits), reviewed for the exact commit
   that is the head now, at least one check ran on that commit and every one passed (none
   reported yet is not green), up to date with main; a pull request named by hand that is not
   READY is refused with the reason. Right before each merge it fetches the head again from GitHub
   and merges that exact commit only if it is still the one reviewed. A pull request from another
   repository is handled the same way: GitHub's own copy of its head (`refs/pull/N/head`), only as
   the commit reviewed;
2. builds one release branch from main in its own worktree and squash-merges each in turn. A
   clash in the manifest alone is not a conflict. Any other clash stops the run, names the pull
   request and removes the branch again;
3. writes the manifest: written once, at release time, from the merged files, then checked
   against them exactly;
4. runs the quick contract tests -- the ones that changed or that name a changed file; CI runs
   all of them on the release pull request;
5. prints the version commit, the commands, the note that closes each original pull request, and
   the cards to close.

It never picks the version number, and refuses one that is already a tag (here or on the origin)
or is not above `VERSION` on main. It sends the branch and opens the release pull request only
with `--version X.Y.Z --go`. It never merges and it never tags: the release pull request needs an
independent review and green checks on current main like any other, and those commands are
printed. `--dry-run` changes nothing. After the release, each original pull request is closed, not
merged: close it with a note that names the release, keep the branch, and add the release pull
request to the card's `pr:` so `reconcile --prs` closes the card from facts.

**Why every pull request still carries a matching manifest.** The installer and `/make-it update`
read `CONTENT_MANIFEST` from the tip of main, and main has no branch rule, so the CI check that
fails a pull request whose manifest does not match its files is the only thing that stops a stale
manifest reaching users. Letting fix pull requests skip the manifest would mean loosening that
check, so it stays as it is. The clash is removed where it cost time instead: the release writes
the manifest itself, and a branch that must rebase settles it with one command,
`content-manifest.sh generate . --write`.

### After every merge: every open pull request is sorted

The owner's rule (2026-11-24): on every merge, check every open pull request and sort it by what
it needs. `sync-prs.py --sort` does it from facts, no AI (`gh`: draft or not, GitHub's merge state,
how far behind main, each check, the last activity; the board: the card a pull request belongs to
-- one whose `pr:` lists it, else one its title names -- and that card's `reviewed:` line). Each
pull request lands in exactly one group, the first that holds:

| Group | When | The action |
|-------|------|------------|
| WILL NEVER MERGE | Its card is already closed, or main already holds everything in it | close it with a note, keep the branch |
| NEEDS YOU | Its card has a question only you can answer (`decision:`) | a one-click question |
| STALLED | Still being worked on (a draft, or checks not finished) with no activity for 48 hours (`STALL_HOURS`) | chase its lane, or take it over |
| OUT OF DATE | It is stacked on another branch, conflicts with main, or is behind it | rebase it onto main (a stacked one once its base is in main, pointed at main); its checks run again |
| CAN BE SETTLED | A check fails, or its last review said not ready; or every check passed and no ready review of this exact commit is on its card | `/resolve-it` for the failing check or the finding; an independent review for the missing one |
| READY | Into main, reviewed for this commit, at least one check ran on it and every one passed, up to date with main | release it with the day's release |

Each line names the pull request by its own title and number, the card it is for, why it is in
its group, and the action. A pull request that is being worked on and active is counted as "still
moving" and left alone. One whose facts cannot be read is listed as not sorted, never guessed;
when GitHub cannot be asked at all, the helper says so, sorts nothing and exits 2.

It runs without anyone remembering: `reconcile --prs` ends with the list (so a groom, a dispatch
and `/resume-it`'s catch-up all print it), the skill runs it after every merge and every release,
and the first screen counts each group.

### Plain words on the board

Every line the board prints or writes names a card by its **title with its id** --
"Export drops the last row (E07-S3)" -- never a bare id; a long title is shortened at a word
boundary. A pull request is named by its card when a card's `pr:` lists it, else by its own title
with its number. This holds for `status.py`, the first screen, `PLAN.md`, `GROOM-PLAN.md`, the
dispatch announcements and every "waiting on you" list. (`BOARD.md`'s status lines keep their short
form: other skills read them.) A message to the owner follows `approval-block.md`, A message to the
owner: a few plain lines, one update a day unless the owner is needed, every question one click.

### The running list

A review finds faults that were there before the change (`approval-block.md`, A review sorts its
findings). One that can lose data, leak a secret, send something wrong, or tell the person
something untrue becomes a card. Any other goes on the **running list**: one `## Running list: <skill or area>` section per skill or area, on the epic card the work's card sits under
(the area is the card's `category:`), one line each, written with
`card.py append <epic id> "Running list: <skill or area>"`:

`- <the fault, in plain words> (<file>) · found <date> in "<the work's title> (<its id>)"`

A lane starts by reading the running list for the area it is working in. It fixes the lines that
sit in files it is changing anyway, inside its own work, and clears each one by appending a line
under the same section: `- fixed <date>: "<the first words of the line>" · <the pull request or
commit>`. A line is open until a `fixed` line quotes it. The first screen counts the open lines
and their areas. The list is never turned into cards in bulk; `groom` reads
it as evidence. With no board, the line goes in the lane's report under "Already there" and stops
there.

### `status`

Bare `status` prints one report from `status.py`: read-only, no AI call, under a second on a
365-card board, and the same answer every run. It shares the card reader and the status-line,
waiting and can-start rules with `regen-board.py`, so the report and `BOARD.md` never disagree.

- **In flight** -- by stage, not status: the board's Now fixing and Shipping lines, then other
  in-progress work; each with its count and oldest idle card.
- **Bundles** -- only when there are any: each open bundle once, with its ground, how many of its
  parts are still open, and every part by its title with its id and whether its own check has
  passed. The first line of the report counts **things to do**: a bundle is one, however many cards
  it does.
- **Up next** -- the board's Next up bug, `PLAN.md`'s next unmerged wave ("covers N of M
  candidates; K new since (new bugs first, the rest after its waves)"), and the top stories / tasks / spikes that can
  start.
- **Burn-down** -- per week for 4 weeks: opened, closed, net, open at week's end; then a forecast
  ("clear in ~N wks", or "growing, no finish at this rate" plus how long the open cards would
  take with no new ones).
- Every card is named by its title with its id.
- **Needs you** -- Waiting on you (top 5), then **every** held P1, oldest first, with P2/P3 held
  as a count. A card already under Waiting on you isn't repeated. `dispatch` ends with this section.
- **Drift** -- Now fixing cards idle 2+ days (lanes work in hours: the lane probably stopped), other
  in-progress work (not bugs) idle 14+ days, Shipping cards idle 14+ days (merged? run `reconcile --prs`),
  reopened cards (a fix that did not hold), a `PLAN.md` whose waves are all merged or whose next wave is stuck on a held, waiting or blocked
  card (re-plan).
- **Epics** -- done / total per epic, most open first. **Cycle time** -- median days from Reported
  to shipped, by priority.

Dates come from the board's git history: the last commit that set a card `done`, and the last
that touched it; renames are followed, and the weeks start at
the board's first card. A card that entered git already done (a seed or an import) is left out of
the weekly opened / closed counts, and cycle time counts only transitions git saw. With no git,
it falls back to `created:` / `updated:` and says so. Lists show the top 5. Runs on Python 3.9+.

### `done <id>`

A brief, **non-blocking end summary** -- what actually changed (tests/build, where applied, the
commit) and the suggested next item. Then `status: done`, drop any `pin:`, bump `updated:`,
regenerate, sync, `slack-notify.sh done <id> "<title>"`.

### `combine [filter]`

The owner's words: look at the cards "to see where we can combine if their synergy supports without
watering down what each card is meant to address". Three grounds, not only exact duplicates:

- **Same file** -- cards that change the same file or skill are done in one sitting.
- **Same root cause** -- symptoms of one fault become one piece of work for the cause.
- **Same goal** -- several cards become tasks under one measured goal.

`combine` runs on its own (`/backlog-it combine [filter]`), as a step of `groom`, and at capture when
a new card clearly belongs with an open one. **It proposes. Nothing combines without the owner's pick.**

1. **The facts come from a helper, not from an AI's mood.** `shrink.py combine [filter]` (read-only,
   no AI call) prints candidate groups with the facts they share: cards that name the **same files**,
   cards of the **same skill** (`category:`), and cards that already **wait on each other**. It only
   considers open cards nobody has started that are in no bundle, never groups a high-stakes card
   with one that is not, and says when a group is too big for one bundle. `<filter>` is `plan`'s; a
   single card's id shows only the groups that card is in.
2. **Where the files come from.** A card lists the files it would change in ONE place, the
   frontmatter field `files: [src/export.py, src/csv.py]` (repo-relative). Three writers fill it:
   `plan` writes it for each card it puts in a wave (the `files` its route call returns); a `groom`
   grounder writes it from the code it cites as evidence; A lane writes the files it really changed
   when it opens its pull request. Each uses `card.py set <id> files="[…]"`. A card with no `files:`
   yet is grouped by the file names its text mentions, and the helper says which it was ("from its
   `files:`" or "named in its text"). Release bookkeeping every change touches (the version file, the
   changelog, the manifest) never counts.
3. **The judgement is the AI's, and its reason is written down.** Same file is a fact. Whether a
   group has the **same root cause** or the **same goal** is a judgement: the AI reads the groups and
   the cards, proposes at most five bundles, and gives each one its ground and the evidence in one
   line (the files, the fault, or the goal). A proposal it cannot give evidence for is dropped.
4. **One click.** The proposals go to the owner as one multi-select ask (`approval-block.md`): one
   option per proposed bundle, each saying which cards (title with id), on which ground, and the
   evidence in a line; no "all of them"; a bundle not picked is not made, and a dismissed ask makes none.
5. **Make each picked bundle** with `shrink.py bundle <id> <id> …`, the text on stdin:
   ```
   title: <the bundle's title, plain words>
   ground: same file | same root cause | same goal
   why: <the evidence, in a line>
   <id>: <that card's own check: how we will know its point is met>     (one line per card)
   ```

**What a bundle is, so nothing is watered down.** One piece of work -- one lane, one pull request --
with one card of its own (`bundles: [ids]`, `ground:`). That card LISTS each original card with ITS
OWN check under `## Parts`. The original cards are not deleted and not merged: each stays whole and
readable, is only marked `bundledIn: <the bundle's id>`, and **closes only when its own check
passes** -- `shrink.py part-done <id>` with what showed it on stdin. A plain `status=done` on a part
is refused, and so is closing the bundle while a part is open; `reconcile --prs` leaves a released
bundle open, naming the parts, until every part has passed. A part whose check fails is taken out
(`unbundle <its id>`) and goes back in line, so the rest can still ship.

**A bundle's state is its parts' state, worked out from its parts every time the board is read and
never stored** on the bundle card (`regen-board.py`'s `lift` and `needs`, which every helper reads
through). So a part that changes after bundling carries the bundle with it: the bundle is
high-stakes if any part is (held, never in a wave); it waits on your answer if any part does (the
question is listed once, on the part); it waits on whatever any part waits on, and on a part
somebody started alone; it conflicts with whatever any part conflicts with; it takes its parts' highest
priority (and drops when they are lowered) and their pin; and it is one-at-a-time in every `serial` category a part is in.
A part's own `pr:` is not lifted: one pull request does the bundle, and it is the bundle's.

**A bundle counts as ONE thing to do**, and its parts are still shown by title with id: `BOARD.md`
lists the bundle with a `part:` line per card, and Next up never offers a part; `status` counts
"things to do" and lists every bundle with its parts; `scope.py` puts the bundle in a plan's or a
groom's scope and never its parts (they come under `bundles`); `plan` gives the bundle one place in
a wave and writes it as `<title> (<id>), a bundle of N`; the first screen names it once with its
parts beneath. A bundle waits on whatever its parts wait on, and a card that waits on a part waits
on the bundle.

**The limits** (named constants in `shrink.py`, each with its reason):
- `BUNDLE_MAX` = 5 cards, and `SITTING` = 8 points of size (XS 1, S 2, M 3, L 5, XL 8; no size
  counts as M): a bundle is at most five cards **and** one sitting. Past that the helper refuses and
  says to split.
- **A high-stakes card is never bundled with a card that is not**: the gate must not be lost. A bundle
  of high-stakes cards is held like any other, and so is a bundle one of whose parts becomes
  high-stakes later.
- Cards of different priority may bundle, and the bundle takes the highest. It is a bug if any of
  its parts is one, so it keeps its place in the bug line.

**`unbundle <id>`** -- one command, and it loses nothing. With a bundle's id, every open part goes
back in line and its file is byte for byte what it was before; the bundle card is kept, closed as
`unbundled`. With a part's id, only that card goes back (a bundle left with one card is un-bundled
whole).

### `reopen <id> <what was seen>`

For a fix that did not hold, or a closed card someone wants back. `shrink.py reopen <id>`, the
person's words on stdin, word for word. The card goes back in line: `status: backlog` (a bug at
`stage: Reported`), `closed_as:` removed, `reopened: <date>` set, and the words quoted under
`## Reopened (<date>)` with how it had been closed. Its old `pr:` moves into that note, so the
merged pull request that closed it never closes it again; every earlier note stays. A card that is
not closed is refused (add what was seen with `card.py append`). The first screen counts reopened
cards, and a card a person brought back never expires.

### `expire [--dry-run]`

The owner's choice (2026-11-24): "Yes, after 30 days, never a safety one". A card that nobody asks
for closes itself after **30 quiet days**, with a note saying why, who judged it safe, and how to
bring it back (`status: done`, `closed_as: expired`; never deleted; `reopen` brings it back).

**No mark, never.** Whether a card is safe to close, and whether anyone asked for it, cannot be read
from its fields or headings: a security matter may use no security word, and "the owner asked" may
sit in any sentence. So the rule is turned round, which is what "when it cannot be told, it does NOT
expire" means. A card can expire ONLY if a judge who read the whole card marked it:

```yaml
expires: ok
expires_why: a tidy-up of names; it cannot hurt anyone, and nobody asked for it   # one plain line
expires_by: groom        # who judged: groom (its judge) or you (the owner's pick)
expires_of: 3f9a1c0b7d2e # set by the helper: a print of the whole card that was judged
```

Two judges give the mark, and nobody else:
- **`groom`'s judge** (step 2, Safe to close when quiet) reads the whole card and answers four
  questions, each `yes`, `no` or `unsure`: can it lose data, leak a secret, send something wrong, or
  tell the person something untrue (`"can_hurt"`)? Did a person ask for it, in any wording, anywhere
  in the card (`"person_asked"`)? Is it a rule the product must meet, such as `maturity: mandate`
  (`"must_meet"`)? Does anything else on the card say to keep it (`"keep"`)? On any `yes` or `unsure`
  there is no mark. Only four `no`s give one, written with `shrink.py stamp <id> --by groom` (the
  reason on stdin).
- **The owner**, picking cards in a one-click list (a multi-select, one option per card with its
  title and the reason in a line, no "all of them"): `shrink.py stamp <id> --by you`.

**The helper stays no-AI.** `shrink.py expire` closes only marked cards, and **every hard rule still
applies on top of the mark**, so a wrong mark alone cannot close a protected card. `shrink.py stamp`
refuses a card a hard rule protects. **An edit clears the mark**: the print covers the whole card, every field and every section, so any
change after the judgement -- a new note, a new section, a changed title or field -- means the mark
does not count (the judgement was about the old card) until a judge marks it again. Only bookkeeping a
helper itself writes is left out of the print, and so leaves the mark standing: `updated:`, the
`expires…` fields, `mode:`, `plan:`, `files:` and `reconciled:` (the named constant `STAMP_SKIP`).

**Never expires**, marked or not:
- a bug (`type: breakfix`), or a card whose type is not recorded;
- anything high-stakes (`stakes: critical`, or a `## High-stakes` section), and `maturity: mandate`;
- a card the owner captured himself (`## Captured`): his own reports never expire;
- a card with a question, an answer or an owner decision on it, or one that was reopened;
- a pinned card; a card with a pull request; a card another open card waits on; a part of a bundle
  that is still open, and the bundle itself; a card somebody has started;
- a card whose title or category holds a safety word (the named constant `SAFETY`): a guard on top of
  the judge, never the judgement;
- a card with no date that can be read.

**Quiet** means no change to the card and no change to any card that mentions its id; a date in the
future counts as today. `expire --dry-run` lists what would close, what will close within 7 days,
what could close later, and why every other card is kept, and writes nothing; `--dry-run --as-of
YYYY-MM-DD` works the same out for a later day (dry run only: a real expire always uses today).
`groom` runs it. The first screen counts the marked cards that will close in the next 7 days and
says how many closed since the last look; with none marked, it and the dry run say "no card is
marked as safe to close yet: groom marks them" (on the first screen only while it has room). The 30
and the 7 are the named constants `EXPIRE_DAYS` and `EXPIRE_WARN`.

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

Flags: `--prs` (no AI: `sync-prs.py` closes cards by the shipped-means-done rule, on facts `gh` gives
and nothing else. A card is done, `closed_as: shipped-tests-pass`, when every PR in its `pr:` is
closed and one is merged, a release carries that merge (the repo's newest tag holds the merge
commit; a repo with no tag at all releases by merging), and every check that ran on that release
passed. The card gets a `## Shipped means done` block: the evidence, that no real run confirmed it,
and how to reopen it. **When a fact cannot be read it says so and leaves the card**: checks that
could not be read, are still running, did not run at all, or failed ("a test says otherwise"); a
merge no release carries yet; a PR still open or closed without merging. A fix whose own PR was
closed and carried by a release PR lists both in `pr:`. A bundle is left open, its parts named,
until each has passed its own check. A card with no `pr:` is never guessed
from its text: a Shipping card without one is listed to set by hand, as is a `repo#N` short form
(use the PR's URL). Each card is re-read at write time, so another session's move wins. Never
backward. No `gh` → the PR step is skipped and said so) · `--fast` (code rung only) · `--deep <id>` (run the project's unit and end-to-end tests
headlessly for one card) · `--dry-run` (print what would apply, write nothing) · `--dispatch`
(run `dispatch` afterwards).

### `dispatch [--dry-run]`

Autonomous "do the next thing" -- a hands-free way to call `start`. **It never bypasses the
green gate or the harm gate** in the standing preamble.

0. **Stages first, then the plan.** Run `reconcile --prs` (`--dry-run` under `dispatch
   --dry-run`) so Shipping is true and released fixes are closed. **New bugs first:** fill free lanes with bugs the
   plan doesn't list, by step 1's rules -- bugs before improvements holds even mid-plan. **Then the
   plan, which stays in force for the cards it lists**: cards changed since it was written keep
   their place, and other new cards go after its waves. **Re-plan** when every wave is merged, when
   its next wave can't start (a card in it is held, waiting on you, or blocked -- `status` flags
   "PLAN.md stuck"), after a spike's finding lands, or when asked (`plan`); no `PLAN.md` → the
   steps below. (A stricter "any change makes it stale" rule went stale within hours on a busy
   board, and the re-plan it demanded was skipped every time.) Take the first wave whose cards
   aren't all merged, and start it only when every card
   in the waves before it is done and none of its own cards is in
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
   - Exclude: high-stakes cards (never auto-selected -- log the skip and why); anything it
     waits on unfinished (its own `dependsOn` or an ancestor's -- see What a card waits on); an
     open `decision:` (waiting on you); a `conflictsWith` card in progress; file
     overlap with any in-progress card's reconcile evidence.
   - Sort: P1 → P3, then never-reconciled first, then oldest `updated:` first. Pick the top.
3. **Announce** each pick -- `Dispatching <title> (<id>) [category] P# · <verdict> · confidence
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
   the human is readable cold: its title, what waits and why, 2-4 named answers, a batch as one grouped line, a high-stakes item never batched (`approval-block.md`, A list of asks).

Armed by default; `--dry-run` prints the picks without starting anything; everything is logged
and reversible.

### `plan [filter] [--with-deps] [--apply] [--dry-run]`

**How and in what order.** One AI pass reads the project's `handoff.md` and the board, routes
each card that could start to an execution mode, and orders them into **waves** -- the path that
**finishes soonest with every gate held**. `groom` decides *what next*; `plan` decides *how to
run it*. It does no per-card code check of its own (it reuses recorded evidence; run `groom` to
re-ground). One headless call: about a minute on a small board, ~10 on a 100-card board. The plan
then leads `dispatch` for the cards it names until its waves are merged (see `dispatch` step 0).

**Scope -- the filter, and `--with-deps`.** `filter` = a card id (an epic, or one story -- a card
with children means its open cards), a status, a priority, or a category; none = every open card.
`scope.py` resolves it, so the gate knows exactly which cards the plan owes. Without `--with-deps`,
a filter card that waits on an open card outside the filter is skipped ("waits on E02-S3, outside
the filter -- `--with-deps` pulls it in"). **`--with-deps`** pulls that chain in instead: every
open card the filter's cards wait on ([What a card waits on](#card-frontmatter)), across epics,
then what those wait on, all the way down. Only upstream -- never the cards that wait on the
filter -- and `conflictsWith` is not followed. Pulled-in cards are planned like any other, under
the same order (finish soonest, so a chain on the critical path usually lands early), and the plan
holds the filter plus its chain and nothing else from the board. The use: put one epic first --
`plan E04 --with-deps` -- without its cross-epic prerequisites falling out of the plan. A chain
card that can't run (held, waiting on you, in progress, blocked, or in a loop) skips the cards that
need it, and the reason names the chain. Written `dependsOn` is often missing, so a `--with-deps`
call also **suggests links** (step 2); `--apply` writes them and plans what they pull in.

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
- **skipped** (not a mode) -- a candidate that must wait: an open card it waits on that isn't
  planned in an earlier wave (in progress, blocked, held, waiting on you, in a loop, or outside the
  filter without `--with-deps`), files an in-progress card is changing, or an open `decision:`
  (waits on you). Its reason names what it waits on, down the chain: `waits on E02-S3 → E05-S1
  (held)`.
- **Order** -- bugs before improvements (the bug queue rule), then most-unblocking first, a spike
  before the work it de-risks, near-done wins, then the parallel waves. Shipping stays one PR at
  a time. A **wave** is one step: a `dispatch-it` wave runs its cards side by side; any other
  wave is one card. Waves run in list order.

1. **Gather.** **Scope first:** `python3 ~/.claude/make-it/backlog/bin/scope.py <board> [filter]
   [--with-deps] > <tmp>/scope.json` (read-only; exit 2 = the filter names a card that isn't on the
   board -- say so and stop; a `notes` entry that nothing matches -- say so and stop). **Candidates**
   are its `scope` list: open leaf cards (no card names them as `parent` -- an epic whose children
   are all done is a container, not work) with status `backlog`, `ready`, or `designing`. Pass each
   one's frontmatter and full text except the Captured and triage blocks, plus the repo files it
   cites, and the scope JSON itself (`pulled_in` with what each is for, `outside`, `waits`, `loops`,
   `notes`). **Context:** the
   in-progress cards (id, stage, and the files they change -- their `files:`, their branch diff when there is
   one, else the files they cite), `<repo>/handoff.md` if present (Next Steps, Failed Approaches -- the
   board wins where they disagree), `GROOM-PLAN.md` and `STRATEGY.md` if present, settings
   `lane_cap` and `serial`, and the High-stakes gate's signal list. A card with `mode_by: you`
   keeps its mode. **Release bookkeeping** that every change touches (version file, changelog,
   generated manifest) never counts as shared files -- the serial ship queue reconciles it.
2. **Route** with `claude -p --model <route> --allowedTools "Read,Glob,Grep"` (cwd = settings `repo`;
   `<judge>` instead with `--with-deps` or 100+ candidates -- [Which model does what](#which-model-does-what)), passing
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
     "skipped": [ { "id": "E04-S5", "why": "waits on E04-S1" } ],
     "links":   [ { "id": "E04-S2", "needs": "E07-S1", "why": "one line",
                    "evidence": "src/orders.py: E07-S1 creates table:orders, which E04-S2 reads" } ]
   }
   ```
   A spike that isn't a card yet has `"proposed": true` and a new id (next free under the epic).
   **`links`** -- `--with-deps` only: a scope card that plainly needs an open card **outside** the
   scope that no `dependsOn` names (a table it reads that the other creates, an API the other
   builds), each with the evidence. A card already in the plan isn't a link -- the waves order it.
3. **Gate.** `python3 ~/.claude/make-it/backlog/bin/check-plan.py <board> <plan.json> --lane-cap
   N --scope <tmp>/scope.json` (add `--serial a,b` when settings has any). It enforces the hard
   rules: waves in list order; a dispatch wave is 3..`lane_cap` cards that share no files, data,
   or serial category and each name repo-relative files; `stakes: critical` cards are never in a
   wave; every open card a card waits on (an ancestor's `dependsOn` included) comes in an earlier
   wave; only scope candidates sit in waves, and every one is accounted for; each link goes from a
   scope card to an open card outside the scope that it doesn't already wait on, wouldn't make a
   loop, and gives its evidence. Violations → re-run the call once with them appended; still
   failing → stop, print them, write nothing.
4. **Write.** `PLAN.md` at the board root; `mode:` on each planned card (never over
   `mode_by: you`), and `files:` with the files the route call gave for it (`combine` reads them); for each `subagent-it` card with no plan, a **draft** plan at
   `items/<epic>/plans/<id>.md` (Plan format, `status: draft`) linked as `plan:`. Proposed spikes
   are filed only under `--apply` (a `type: spike` card, plus the target card's `dependsOn:` on
   it). **Suggested links**, too, are written only under `--apply` and before `PLAN.md`: for
   each, `card.py set <id> dependsOn=[<what it had>, <new id>]` and an `append <id> Links` line
   (`<new id> -- <why> · <evidence> · via plan --with-deps`), then re-run `scope.py`; if the
   scope grew, route and gate **once more** so the newly pulled-in cards get their waves. Links
   that second pass finds are listed, not written -- one round, no chase. A written link stays
   even if that second gate fails (it's true either way; only the plan isn't written). Without
   `--apply` they're listed under Proposed links and the card that would wait keeps its place.
   Drafts never run without the user's go. Bump `updated:` on touched cards, regenerate,
   sync (commit `plan: <summary>`). `--dry-run` prints and writes nothing.
5. **Report.** The waves, one line each, then the held block, what's skipped and why (the chain,
   for a pulled-in wait), what was pulled in and for which filter cards, and the proposals --
   spikes and links, with the `--apply` command that files them.

**`PLAN.md`:**
```markdown
# Run Plan -- YYYY-MM-DD  (scope: <filter>[ + N pulled in])
> /backlog-it plan · handoff.md + N open cards · finish soonest, every gate held · start/dispatch run it

## Waves
1. **solo** · <title> (E02-S1) -- <reason>
   (a pulled-in card: `1. **solo** · <title> (E07-S4) -- pulled in for <title> (E04-S2) -- <reason>`)
2. **dispatch-it** ×3 · <title> (E05-S1) · <title> (E05-S2) · <title> (E05-S3) -- <why they're independent>
   - <title> (E05-S1) -- <reason> · files: src/a.ts
3. **spike** (2h) · <title> (E04-S9) (proposed) → de-risks <title> (E04-S3) -- <question>
4. **subagent-it** · <title> (E04-S3) -- plan: items/EPIC-04-…/plans/E04-S3.md (draft) -- <reason>

## ⚠️ Held -- needs the alignment brief and an explicit go
## Skipped -- waits on
- <title> (E04-S6) -- waits on <title> (E02-S3) → <title> (E05-S1), which is held
## Pulled in -- the chain behind the filter   (--with-deps)
- <title> (E07-S4) -- needed by <title> (E04-S2)
## Proposed (filed with `plan --apply`)
- spike: <title> (E04-S9) -- <question> (2h)
- link: <title> (E04-S2) waits on <title> (E07-S1) -- <why> · <evidence>
```

A bundle (`scope.json`'s `bundles`) is one card to plan: it takes one place in a wave, written
`<title> (<id>), a bundle of N`, and its parts are never planned on their own.
Every card in `PLAN.md` is its title with its id, the id in brackets right after the title; a
wave's cards come before its first ` -- `, and the reason after it may name other cards the same
way. `status.py` reads both this form and the older one that led with bare ids.

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
The go is one ask: what the plan changes (its tasks and the files they touch), the evidence (what
the card and the code show), what it touches and how to undo it, anything unusual (a migration, a
sign-in or permission change), and the one thing to check -- answered `Approve -- runs it` |
`Change first -- say what` | `Not now -- stays a draft`. A draft with no go stays a draft.
`task-brief PLAN_FILE N` reads the `## Task N` headings.

### `groom [filter] [--with-deps] [--apply] [--dry-run] [--dispatch]`

**Throughput grooming:** reorder and reshape the board so more finishes sooner -- sequenced by
what **unblocks the most**, not by the priority field. **groom proposes; it changes the board
only under `--apply`** (and even then never splits or kills on its own). `filter` = a card id (an
epic, or one story), a status, category, or priority, resolved by `scope.py` as for
[`plan`](#plan-filter---with-deps---apply---dry-run) (default: all open cards). **`--with-deps`**
adds the chain behind the filter (`scope.py --with-deps`): the pulled-in cards are grounded and
ranked too -- one grounder each, so a long chain costs more -- and marked `pulled in for <id>` in
the burn-down. A missing link a grounder finds is a 📋 proposed Board delta, written as `dependsOn:`
only under `--apply` and not re-grounded this run (the next `plan --with-deps` pulls it in).

**AI-powered by default.** Running `groom` (or `groom strategy`) is itself the opt-in to
multi-agent, high-effort reasoning: fan out one grounder per card with the **Workflow** tool (model
`ground`; each grounder's brief ends: "Report plainly (`approval-block.md`, A message to the owner): a few short lines in plain words, each card or pull request by its title with its id."), then hand every verdict to one agent on model `judge` for steps 2-5, at high effort
([Which model does what](#which-model-does-what)). Don't ask permission for it; the user doesn't need any extra keyword.

0. **Close what is already settled, with no AI.** `reconcile --prs` (fixes released with passing
   tests are done), then `shrink.py expire` (marked quiet cards close; `--dry-run` under
   `groom --dry-run`). Say both counts in the report.
1. **Ground in code (reuse `reconcile`).** Run the reconcile ladder for every card in scope --
   `--dry-run` by default; `--apply` lets reconcile auto-apply as usual. For `partial`, name why:
   **unbuilt**, **untested**, or **unverified**. Each grounder also writes the files the card would
   change as `files:` (from the code it cites), so the next `combine` has facts.
2. **Clean the board.** From the verdicts: **close** finished cards, **merge** duplicates,
   **restatus** drift, **split** epics too big for one pass into the smallest shippable slices
   (the "minimum lovable loop"), **carve out** deferred work into its own card (never hold a
   delivered feature open), **flag** mis-scoped cards. Close / merge / restatus apply under
   `--apply`; **splits, deferrals, and kills are always proposals**.
   **Needed or not.** Before anything is ranked, ask of every card in scope, and of every epic
   that owns one: does this still need doing? The answer is `needed`, `not needed` or `can't tell`,
   and `not needed` takes evidence of one of these, cited:
   - **Already covered** -- the code does it today, or another card does (name it).
   - **Overtaken** -- what it fixes or extends is gone or was replaced, or the owner has since
     decided against it (the card, `handoff.md`, a later card's notes).
   - **Nobody is asking** -- no report, no person and no card waits on it, and it names no one it
     is for.
   - **An epic with nothing left** -- every card under it is done or not needed.

   The default is `needed`: `can't tell` stays in the burn-down with the one fact that would settle
   it. Age, a low priority and "it's hard" are never evidence. A security finding, a failed check
   or a gate is `not needed` only when the code shows it fixed or gone, never because it is
   unwelcome. "Not worth doing now" is a deferral, not `not needed`.
   Each grounder adds two facts for this, evidence only: whether what the card targets still
   exists (`file:line`, or "gone"), and who or what asks for it (a report, a person, a card that
   waits on it). The judge decides.
   **A `not needed` verdict is a proposal, under `--apply` too.** It is listed under
   `## Needed or not` in `GROOM-PLAN.md`, and after the report the strongest cases go to the human
   in one multi-select ask (`approval-block.md`): one option per card, each with its title and the
   reason in a line, no "all of them"; a card not picked stays as it was. A picked card is closed
   the board's way: `status: done`, `closed_as: not-needed`, and a `## Not needed (YYYY-MM-DD)`
   block with the reason and the evidence. It is never deleted, and `undo` brings it back. A
   not-needed card leaves the burn-down only once picked; until then it ranks last, marked.
   **Safe to close when quiet.** For each card that `shrink.py expire --dry-run` keeps only because
   it is "not marked", the judge reads the whole card and returns strict JSON:
   ```json
   { "id": "E09-S2", "can_hurt": "yes|no|unsure", "person_asked": "yes|no|unsure",
     "must_meet": "yes|no|unsure", "keep": "yes|no|unsure", "why": "one plain line" }
   ```
   On any `yes` or `unsure` the card gets no mark. Only when all four are `no`, and under `--apply`,
   the card is marked: `shrink.py stamp <id> --by groom`, the `why` on stdin (without `--apply` the
   cards are listed under `## Safe to close when quiet` in `GROOM-PLAN.md`). The mark closes nothing
   by itself: the card must then stay quiet for 30 days, and every hard rule of
   [`expire`](#expire---dry-run) still applies. After the report the owner may mark more himself in
   one multi-select ask (`--by you`).
   **Combine.** Run [`combine`](#combine-filter) over the scope: the helper's groups, the judge's
   proposals (at most five, each with its ground and evidence), listed under `## Combine` in
   `GROOM-PLAN.md`, then the one multi-select ask after the report. A bundle is made only on the
   owner's pick, under `--apply` too. A bundle already on the board is one line in the burn-down.
3. **Sequence.** Pins first: a card with `pin: N` sits at rank N and everything else re-flows
   around it (two pins on one rank: smaller id first, flagged). Then the unpinned cards by:
   (a) **unblock value** -- what unblocks the most downstream work jumps the queue;
   (b) **near-done wins** -- `partial` cards a story or a few hours from done go early;
   (c) **parallel-safe batches** -- group cards whose evidence touches disjoint files, and call
   out overlaps; (d) **smaller `size`** breaks ties -- priority is only a weak signal;
   (e) **cut ruthlessly** -- name what's not worth doing now. `STRATEGY.md`, if present, makes
   foundational work outrank polish in (a) unless a card is pinned.
4. **Tag the ship track** from the standing preamble: **safe** (ships on the normal path) or
   **gated** (stops at the PR), and the **mode** from the [`plan`](#plan-filter---with-deps---apply---dry-run)
   rubric (a card's own `mode:` wins). Keep in-progress small.
5. **Persist.** Write `GROOM-PLAN.md` at the board root; regenerate only if `--apply` changed
   something; sync (commit `groom: <summary>`); post a one-line digest with `slack-notify.sh
   raw`. **`--dry-run` prints everything and writes nothing.**
6. **Report.** A one-line state digest -- **Started N · Finished N · Not-started N · Stalled N**
   (stalled = `in-progress` with no commit or `updated:` movement in 14 days; list them) -- then
   the board deltas, the burn-down, the high-stakes block, **top 3 to start now** (never
   high-stakes), **what is no longer needed** (count, then each card with its reason), and **3 to
   drop or defer**. `--dispatch` then runs `dispatch` for the #1
   parallel-safe card (off by default).

**`GROOM-PLAN.md`:**
```markdown
# Groom Plan -- YYYY-MM-DD  (scope: <filter>[ + N pulled in])
> /backlog-it groom · grounded via reconcile (code+tests+live) · advisory (start/dispatch are the only ways work starts)

## Board deltas   (✅ applied · 📋 proposed)
- ✅ <title> (E14-S18) → done                       -- built: code+tests+live
- 📋 split <title> (E04) → three cards (E04-S19..S21)  -- too big to finish in one pass
- 📋 defer <title> (E05-S5)                         -- blocked until <condition>

## Burn-down   (top-down = most throughput · 📌 = pinned · ⚠️ = high-stakes, out of auto-run)
1. 📌 <title> (<id>) · [safe|gated] · <mode> · pinned · frees: <titles (ids)> / waits on: <titles (ids)> · est <size>
2. <title> (<id>) · [safe|gated] · <mode> · <one-line reason> · frees: <titles (ids)> / waits on: <titles (ids)> · est <size>

## ⚠️ Requires alignment before touching   (high-stakes -- not auto-runnable)
- ⚠️ <title> (<id>) · why high-stakes · needs the alignment brief + an explicit go before `start`

## Needed or not   (proposals -- nothing closes without your pick)
- ✂️ <title> (<id>) · not needed: <already covered | overtaken | nobody is asking | nothing left> -- <evidence>
- ❓ <title> (<id>) · can't tell: <the one fact that would settle it>

## Combine   (proposals -- nothing combines without your pick)
- 🧺 <title> (<id>) + <title> (<id>) · same file | same root cause | same goal -- <the evidence, in a line>

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
multi-agent pass (one analyst per epic via Workflow, high effort, model `judge`). Run it weekly or when choosing
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
   Then wait for an explicit go, asked as active confirmation: the brief adds what is unusual
   (the signal that made it high-stakes) and the one thing to check, and the user picks
   the specific -- `Add alongside -- rehearse on <place>`, `Change the working path -- rehearse on
   <place>`, or `Not now -- stays on the board`, naming the place -- never a plain yes. Not
   batched with any other ask; no pick, no start.

It renders with ⚠️ on the board and in its own block of the groom plan, outside the runnable
lane. It only removes cards from auto-run paths -- it never starts or changes anything itself.

### `undo`

Revert the last board commit with `git -C <board> revert --no-edit HEAD` (never a history
rewrite), regenerate, sync, and print `✓ Reverted the last board change: <its commit message>.`
No ask: the user typed `undo`, and it is undone the same way; the message names what was
reverted, so a change from another session is noticed. It reverts whatever
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
- `card.py capture [<triage-file>]` -- a report on stdin, word for word, and what the triage call
  gave back in the file (no file = it gave nothing). Bad triage output → the report becomes a bug
  under the Bugs epic at Reported, marked `not sorted yet -- triage failed: <reason>`; it is written
  even when the pull fails. Good output → `triage ok`, nothing written.

Call it as `card.py --board "$BOARD" --project "$PROJECT" <verb> …`. Every verb reads its stdin
first (never from a terminal; empty text is refused), then takes the board's writer lock (one card
writer per board at a time, so parallel lanes never lose a write or share an id), pulls (a board in
its own repo; a failed pull, a detached HEAD or a half-done rebase writes nothing), finds the card
by its `id:` (exactly one match), writes the whole file then swaps it in, bumps `updated:`,
regenerates `BOARD.md`, and syncs as below (`--no-sync` leaves the commit to you). If another session
pushed first, it rebases onto theirs, regenerating `BOARD.md` when that is the only conflict, and
never leaves the board mid-rebase; if both clones gave a new card the same id (or file name)
meanwhile, ours takes the next free one before it is sent, and that is never silent: it prints
`Your card "<title>" is now <new id>: <old id> was taken by "<their title>" on the shared board` --
relay it -- and the card keeps a line under `## Renumbered` saying what it was. Our own new cards
not sent yet that depend on it follow; the line names any card that still mentions the old id
("these cards still mention <old id>: …: check them").

**The line it prints is true, and so is its exit.** It ends `committed + pushed` only when the shared
board has the write. Otherwise it ends `… NOT sent to …: <reason>`, and you **relay that line** to
the person:
- **exit 0**, `NOT sent to a shared board` -- the board has no shared copy to send to: no remote
  ("not shared yet"), inside a project (staged; it goes with the project's next commit), not in git,
  or `--no-sync`.
- **exit 3**, `NOT sent to the shared board` -- written here, but the shared board did not get it:
  the send was refused, the board could not catch up, the branch follows nothing, or the commit
  failed. The card is saved here: do NOT run the write again. It is sent with the next card write,
  which also commits any card file an earlier write saved but could not commit.
- **any other non-zero exit** -- nothing was written; the message says why.

`sync-prs.py` and `shrink.py` write through the same function, under the same lock; `shrink.py`'s
lines end the same way, with the same exit codes. `card.py set <id> status=done` is refused for a
part of an open bundle (it closes on its own check) and for a bundle whose parts are still open.

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

Point several projects at the same `board` path, each in its own `.claude/backlog-it.json`. The
personal board in the user settings is not a way to share: it is used only inside its own `repo`
(see [Settings](#settings)), so a project that shares it sets that `board` in its own settings file.
The format is the only contract: the same folders, the same frontmatter, the same `BOARD.md`
renderer. Whoever writes last regenerates `BOARD.md` from the cards, so nothing is lost. A
project that wants its own board instead sets its own `board`.

---

## Wiring into the other -it skills

When the **project** has `.claude/backlog-it.json` or `.claude/backlog/BOARD.md`, found by the one
rule in [Settings](#settings) from its root or any folder below it (the user-level settings file
alone does not switch these on):

| Skill | Hook |
|-------|------|
| `/resume-it` | Starts from the board: **Now fixing** lanes first, then **Next up**; catches up first with `reconcile --prs` |
| `/dispatch-it` | Takes its lanes from the board -- non-overlapping, up to `lane_cap` |
| ship (`ship-it-guide.md`) | Records the card's PR in `pr:`. Once the fix is released and its checks pass the card is done (shipped means done): `/resume-it` and `/wrap-it` catch up with `reconcile --prs` (the card's `pr:`, never a guess) |
| `/wrap-it` | Updates each touched card and regenerates the status line alongside the handoff |
| `/debug-it` / `/fix-it` | A new bug gets a card (`stage: Reported`) before any fix work |

**The handoff is the exception: the project's own board counts, settings file or not, and so
does the personal board inside its own `repo` folder.** A board that belongs to another project
never feeds a handoff, so each project's `handoff.md` stays its own. `/clear-it` writes
`handoff.md`'s Next Steps as card ids under a copy of the status line, and files a card
(capture, no questions) for any next step that has none.
`/resume-it` re-reads those cards when it reads the handoff. Where the two disagree, the board
wins -- so what to work on next lives in one place.
