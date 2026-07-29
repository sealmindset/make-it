# /git-it — Keep your saved work clean and safe

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/git-it` handles the everyday chores of **saving and organizing your work history** (this is called "git") the right way — so your main version is always working, your changes are tidy, and nothing ever gets lost or breaks the team's work.

> **In one sentence:** Save, organize, and clean up your work history safely — without needing to understand git.

> ℹ️ **What is "git"?** It's the system that records every version of your project, like an unlimited undo history plus a way for a team to work together without stepping on each other. Powerful, but easy to misuse — which is exactly why `/git-it` exists.

---

## What is it used for?

- **Saving changes** correctly (clean, meaningful save points).
- **Keeping the main version always working** and safe to release.
- **Cleaning up** the backlog of half-finished branches and open requests.
- **Merging** finished work in without conflicts.
- Answering "**what's safe to keep and what's safe to throw away?**"

---

## Why do you need it?

Git mistakes are a top source of lost work and team confusion. `/git-it` follows **one proven, safe model** and has a **prime directive: never negatively impact the app or someone else's work.** When an action isn't provably safe and reversible, it *reports* instead of acting. It only touches *your* work, never other people's.

---

## How it helps you vibe code

You get professional version-control discipline for free. You don't have to learn commands like rebase, squash-merge, or force-with-lease — `/git-it` applies them correctly and keeps everything reversible, so you can build fearlessly.

---

## How to use it

Type:

```
/git-it
```

Then tell it what you want — "save my work," "clean up old branches," "merge this in," or "what's safe to land?" It will:
- Save your changes as clean, well-labeled checkpoints.
- Keep your main version green (always working).
- Triage old branches and requests into **drop / refine / safe** and handle each appropriately.
- Recover almost anything if something goes wrong (git keeps a safety net).

---

## When to use it

- ✅ When you want to save or organize your work properly.
- ✅ When branches and open requests have piled up and need cleaning.
- ✅ When you're unsure what's safe to merge or delete.

---

## Related skills

- [`/wrap-it`](13-wrap-it.md) — end-of-day shutdown that includes saving your work.
- [`/ship-it`](06-ship-it.md) — deploys the clean work `/git-it` helps you maintain.
- [`/clear-it`](12-clear-it.md) — checkpoint your *thinking* (git only saves *files*).
