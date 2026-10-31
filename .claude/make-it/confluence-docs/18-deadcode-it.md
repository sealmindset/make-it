# /deadcode-it — Clear out code your app no longer uses

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/deadcode-it` is a tidy-up for your project. It finds code, files and packages that nothing uses anymore, proves they really are unused, and removes them in small steps — checking your app still works after every one.

> **In one sentence:** Type it now and then, and it safely clears out the leftovers.

---

## What is it used for?

- **Removing leftovers** — old pages, helpers and imports left behind as the app changed.
- **Dropping unused packages** — fewer packages means faster builds and fewer security alerts.
- **Keeping a record** — every removal is written down with the reason it was safe.

---

## Why do you need it?

Apps collect clutter. Every feature you change can leave old code behind, and that code still gets scanned, updated and read. Over time it slows everyone down and hides real problems. Removing it by hand is risky, because some code is used in ways a quick search can't see. `/deadcode-it` checks those ways for you.

---

## How it helps you vibe code

You don't need to know what's safe to delete. Tools and an AI search do the proving, and anything that's clearly unused is removed for you. If something only *looks* unused, you get one short pick list in plain words and you decide. Anything risky, like settings, entry points and your app's built-in features, is never touched.

---

## How to use it

From your project folder, type:

```
/deadcode-it
```

If you have unsaved changes, it offers to save them first — it keeps the cleanup separate so it's easy to undo. Files you haven't saved into your project yet are never touched. [`/resume-it`](02-resume-it.md) will also suggest it when unused code piles up.

---

## What do I get?

| What | Where |
|---|---|
| The cleanup itself | A `chore/deadcode-<date>` branch, one small step per kind of thing removed |
| The deletion log | `docs/DELETION_LOG.md` — what went, why it was safe, how it was checked |
| A short summary | In chat: what was removed, what was left alone and why, how to undo |

---

## What it will not do

- Change anything before your app's tests and build pass.
- Remove settings, entry points, database migrations, or your app's built-in features.
- Rewrite, rename or reorganise code — it only removes.
- Share or publish anything — the cleanup stays on your machine until you ship it.
