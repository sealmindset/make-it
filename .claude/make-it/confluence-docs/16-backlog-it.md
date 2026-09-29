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

- **Capturing** a bug or idea the moment you think of it. The card is written first; any
  questions come after, all at once.
- **Fixing bugs in order**, each one moving through five steps: *Reported → Cause found → Fix
  ready → Live → Checked*. A bug isn't finished until it has been checked on the live app.
- **Fixing several bugs at once**, when they don't touch the same parts of the app (three at a
  time by default).
- **Picking a card back up** later: `/backlog-it start <id>` turns the card into an instruction
  you can edit, then runs it.

---

## Why do you need it?

Without a board, bug reports get lost in chat and each new session starts by asking "where were
we?". With one, every session -- and every AI helper -- works from the same list.

---

## How to use it

```
/backlog-it                        # show the board
/backlog-it the export button does nothing on the reports page
/backlog-it start E02-S4           # pick a card back up
/backlog-it dispatch               # start the next bugs that can be fixed side by side
```

The first run sets up the board inside your project. Settings (optional) go in
`.claude/backlog-it.json`: where the board lives, the project's name, how many bugs to fix at
once, and which kinds of work must always be done one at a time (for example anything that
sends email or takes payments). Slack updates are optional and off until you add a webhook.

---

## How it works with the other skills

- [`/resume-it`](02-resume-it.md) starts where the board says: the bugs being fixed, then what's next.
- [`/dispatch-it`](14-dispatch-it.md) takes its parallel work from the board.
- [`/ship-it`](06-ship-it.md) moves a card to *Live* when it ships and to *Checked* once it's verified.
- [`/wrap-it`](13-wrap-it.md) updates the cards when you finish for the day.
- [`/debug-it`](10-debug-it.md) and [`/fix-it`](09-fix-it.md) write a card for a new bug before fixing it.
