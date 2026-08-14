# /session-it — Checkpoint one session at a time, when several share a folder

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/session-it` is [`/clear-it`](12-clear-it.md) for the case where you have **more than one Claude session open in the same folder.** It saves the same handoff note, but into a private lane belonging to *this* session, so parallel sessions never overwrite each other.

> **In one sentence:** Save a checkpoint that belongs to this conversation only, so two sessions working in the same folder don't get spliced together.

---

## What is it used for?

Working on two things at once in the same project.

`/clear-it` writes one file, `handoff.md`, at the top of the project. That is exactly right when you have one session going. The moment you have two, they both write to that one file — the second one wins, the first one's notes are gone, and whichever session reads it next is reading a description of work it never did.

`/session-it` gives each conversation its own lane inside a `.handoffs/` folder:

```
.handoffs/
  handoff-c4d2e427.md      <- this session's notes
  handoff-c8379bec.md      <- the other session's notes, untouched
```

Same six sections as `/clear-it` — Goal, Current State, Active Files, Changes Made, Failed Approaches, Next Steps. Only the addressing is different.

---

## Why do you need it?

Two reasons, and the second is the one people don't see coming.

**The obvious one:** two sessions writing one file means one of them loses its notes.

**The one that actually costs you:** a dead end in one piece of work can be the *right answer* in another. If session A proved that approach X fails, and session B is doing something different in the same folder, a merged handoff will tell session B not to try X — and it will believe it. A note that mixes two efforts is worse than no note, because it gets trusted.

So `/session-it` enforces a hard rule: a session reads and writes **only its own lane.** When it lists the other lanes it reads their one-line goal and nothing else.

---

## How it helps you vibe code

You can run one session on the feature and another on the bug, in the same folder, and keep both threads straight. Each one resets cleanly without dragging the other's dead ends along.

---

## How to use it

**Save this session's checkpoint:**

```
/session-it
```

It prints a short key, like `c4d2e427`. Write it down — you need it after clearing.

**See every lane in the folder:**

```
/session-it list
```

**Pick a lane back up after clearing:**

```
/session-it resume c4d2e427
```

Or just `/session-it resume`, and it will show you the lanes and ask which one.

That last step matters. Clearing the conversation starts a brand-new session, and a new session does not know which lane was yours. `resume` is how you tell it.

---

## When to use it

- ✅ You have two or more Claude windows open on the same folder.
- ✅ You're working in sibling git worktrees of the same repository.
- ✅ You want a checkpoint that can't be clobbered by whatever else you're running.
- ❌ One session, one folder — use [`/clear-it`](12-clear-it.md); it's simpler.

**How it differs from [`/clear-it`](12-clear-it.md):** only in where the note goes and who may read it. `/clear-it` writes `handoff.md` at the project root. `/session-it` writes `.handoffs/handoff-<id>.md` and refuses to read anyone else's. The two are completely independent — they never touch each other's files, and you can use both in the same repository.

**How it differs from [`/wrap-it`](13-wrap-it.md):** `/session-it` is a *lightweight* checkpoint. It does not stop your app, update to-do lists, or save code to git.

---

## Things worth knowing

- The `.handoffs/` folder is added to `.gitignore` automatically. These are working notes, not part of the project.
- Nothing is ever deleted. Overwriting a lane archives the old version to `history-<id>.md` beside it, and dead ends still relevant to the goal are carried forward, not just filed away.
- Lanes are never merged. If two turn out to be the same piece of work, `/session-it` says so and leaves the decision to you.
- If it cannot confirm which session it is running in, it tells you, in the output, instead of guessing quietly.

---

## Related skills

- [`/clear-it`](12-clear-it.md) — the single-session version; same six sections.
- [`/resume-it`](02-resume-it.md) — continues work on an existing app.
- [`/wrap-it`](13-wrap-it.md) — the heavier, end-of-session shutdown.
