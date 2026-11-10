# /backlog-it — Keep your work and bugs on one simple board

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/backlog-it` keeps a **board** for your project: every idea, feature, and bug becomes a small
card, and one page (`BOARD.md`) shows what's being fixed right now, what's shipping, what's live
and waiting to be checked, and what's next.

> **In one sentence:** Tell it about a bug or an idea in plain words; it's written down at once
> and gets its place in line.

> ℹ️ **This is a power-user skill.** Most useful once a project has more going on than one
> to-do list can hold.

---

## What is it used for?

- **Capturing** a bug or idea the moment you think of it. The card is written first and filed
  in the right place automatically; any questions come after, all at once.
- **Planning** new work: for an epic, story, or task it asks a few questions first, so the card
  says what you actually mean.
- **Fixing bugs in order**, each one moving through five steps: *Reported → Cause found → Fix
  ready → Live → Checked*. A bug isn't finished until it has been checked on the live app. When
  a fix ships, its card says how the fix will be checked on the live app, and when that check
  is due.
- **Fixing several bugs at once**, when they don't touch the same parts of the app (three at a
  time by default).
- **Picking a card back up** later: `/backlog-it start <id>` turns the card into an instruction
  you can edit, then runs it.
- **Understanding a card**: `/backlog-it info <id>` explains in plain words what problem it
  solves, what happens if it isn't solved, and why it's being solved this way. It only reads, so
  you can ask while other work is running.
- **Answering what waits on you**: every card that needs your decision sits in one *Waiting on
  you* list at the top of the board, each with its title, what waits and why, and 2–4 answers to
  pick from. `dispatch` ends by showing you that list, plus any high-stakes card it rightly
  won't start on its own.
- **Seeing where things stand**: `status` prints one report: what's in flight, what's next,
  whether the list is shrinking, what needs you, and what has drifted (a fix that has stopped
  moving shows up within 2 days). It's a script, not AI, so it gives the same answer every time,
  in under a second.
- **Keeping the board honest**: `reconcile` checks each card against the code, the tests, and
  the live app, so nothing is marked done that isn't. `reconcile --prs` moves bugs forward from
  their pull requests on GitHub: facts, not memory.
- **Deciding what's next**: `groom` proposes the order that finishes the most, soonest (you can
  pin anything to a spot), and `groom strategy` sorts the work into foundation and polish, and
  says why.
- **Deciding how to run it**: `plan` reads your handoff note and the board, and says for each
  card whether to do it directly, investigate first (a spike), build it step by step from a plan,
  or fix several side by side, in the order that gets everything done soonest, without skipping
  any safety check. A plan stays in force for the cards it names; new bugs still go first. You
  can change any card's choice with `mode`.
- **Putting one epic first**: `plan E04 --with-deps` plans that epic **plus** the cards in other
  epics it can't finish without, and the cards those wait on, all the way down. See
  [Putting one epic first](#putting-one-epic-first) below.

---

## Why do you need it?

Without a board, bug reports get lost in chat and each new session starts by asking "where were
we?". With one, every session -- and every AI helper -- works from the same list.

---

## How to use it

```
/backlog-it                        # show the board
/backlog-it list                   # what's on the board
/backlog-it status                 # where things stand: in flight, next, burn-down, what needs you
/backlog-it reconcile --prs        # move bugs forward from their PRs on GitHub (merged → Live)
/backlog-it the export button does nothing on the reports page   # capture a bug in plain words
/backlog-it epic a monthly report for managers   # plan new work (asks first)
/backlog-it start E02-S4           # pick a card back up
/backlog-it info E02-S4            # what it solves, what happens if it isn't, why it's fixed this way
/backlog-it plan                   # how to run each card, and in what order
/backlog-it plan E04 --with-deps   # put epic E04 first, with what it needs from other epics
/backlog-it dispatch               # start the next work: new bugs first, then the plan's next step
/backlog-it groom                  # what to do next, in order
/backlog-it groom move E05 1       # pin E05 to the top
```

The first run sets up the board inside your project. Settings (optional) go in
`.claude/backlog-it.json`: where the board lives, the project's name, how many bugs to fix at
once, and which kinds of work must always be done one at a time (for example anything that
sends email or takes payments). Slack updates are optional and off until you add a webhook.

**One personal board for everything?** Put the same settings in `~/.claude/backlog-it.json`
instead, for example `{"board": "~/.claude/backlog", "repo": "~/code/my-app"}`, and
`/backlog-it` uses that board from any folder that doesn't have its own.

---

## Putting one epic first

`/backlog-it plan E04 --with-deps` is for when one epic should go first. It plans E04's cards
and every card they wait on in other epics, then what those wait on, all the way down. Nothing
else from the board joins the plan.

- **What "waits on" means**: the cards named in a card's own `dependsOn`, and in its epic's. If
  epic E16 depends on E13, every card under E16 waits on E13's open cards. A link that names an
  epic means that epic's open cards; an epic whose cards are all done waits on nothing.
- **Only what the epic needs comes in**, never the cards that wait on it.
- **The order rule doesn't change**: the plan still finishes everything soonest, so prerequisites
  usually run early.
- **When a prerequisite can't run yet** (held for your go, waiting on your answer, already being
  worked on, or blocked), the cards that need it are skipped, and the plan says why down the
  chain, for example "waits on E02-S3 → E05-S1 (held)".
- **Links nobody wrote down**: when a card plainly needs another card that no `dependsOn` names
  (a table one card reads that the other creates, say), the plan suggests the link, with its
  evidence. `--apply` saves it and plans the card it brings in; without `--apply` it's only
  listed.
- **Works on one story too**: `plan E04-S2 --with-deps`. `groom E04 --with-deps` does the same
  for the burn-down.
- **Without `--with-deps`**, a filtered plan works as before: a card waiting on another epic's
  work is left out, and the plan says what it waits on and that `--with-deps` would pull it in.

> **Heads-up for existing boards:** an epic's `dependsOn` now applies to every card under that
> epic, everywhere the board decides what can start (Next up, `status`, `plan`, `groom`,
> `dispatch`). Cards under an epic that carries `dependsOn` (`groom strategy --apply` adds
> these) may now show as waiting until that work is done.

---

## What's changed since mid-October

- **2026-11-10** (v1.50.0) — **Putting one epic first**: `plan` and `groom` take `--with-deps`; a
  single card id works as a filter; an epic's `dependsOn` now holds for every card under it.
- **2026-10-28** (v1.46.0) — **`info`** explains any card in plain terms, in the same three parts
  every time (the problem, the impact if it isn't fixed, why it's fixed this way), in about one
  screen. It only reads, in the background.
- **2026-10-19** (v1.44.13) — **Every "Waiting on you" item makes sense on its own**: its title,
  what waits and why in plain sentences, and 2–4 named answers kept on the card. The board flags
  an item that is only an id or has no answers.
- **2026-10-16** (v1.36.0 – v1.42.0):
  - **Waiting on you**: every decision in one list at the top of the board (v1.36.0).
  - **`status`**: where the board stands, in one report (v1.37.0); a fix that has stopped moving
    shows up in 2 days, not 14 (v1.38.1).
  - **Bug stages come from GitHub, not memory**: `reconcile --prs` (v1.38.0).
  - **Held high-stakes cards come back to you** at the end of every `dispatch` (v1.39.0).
  - **The plan keeps leading** for the cards it names, and an epic of more than 30 cards stays
    readable (v1.40.0).
  - **One safe way to write a card**, so notes are never cut short and card ids are never handed
    out twice (v1.41.0).
  - **Live cards say how and when they'll be checked** (v1.42.0).

---

## How it works with the other skills

- [`/resume-it`](02-resume-it.md) starts where the board says: the bugs being fixed, then what's
  next. It catches the board up from GitHub first.
- [`/dispatch-it`](14-dispatch-it.md) takes its parallel work from the board, including a plan's
  side-by-side steps.
- [`/subagent-it`](15-subagent-it.md) runs a card's step-by-step plan, which `plan` drafts for
  you to approve first.
- [`/ship-it`](06-ship-it.md) moves a card to *Live* when it ships and to *Checked* once it's verified.
- [`/wrap-it`](13-wrap-it.md) updates the cards when you finish for the day.
- [`/debug-it`](10-debug-it.md) and [`/fix-it`](09-fix-it.md) write a card for a new bug before fixing it.
