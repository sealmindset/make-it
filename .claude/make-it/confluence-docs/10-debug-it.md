# /debug-it — Find the real cause of a bug before fixing

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/debug-it` is a disciplined way to track down bugs. Instead of guessing and trying random fixes, it **finds the true root cause first**, proves it, then fixes it — and stops the frustrating loop of "try something, still broken, try something else."

> **In one sentence:** Stop guessing at bugs — find out what's *actually* wrong, then fix that.

---

## What is it used for?

Any bug, test failure, build failure, or "it's not doing what I expected" moment — **especially after a fix already failed once.** It works through:
1. **Root-cause investigation** — read the full error, reproduce the problem, check what recently changed, trace the data.
2. **Pattern analysis** — compare what works vs. what's broken.
3. **Hypothesis** — consider both "something's missing" *and* "something's doing too much."
4. **Test-first fix** — capture the bug as a failing test, then fix until it passes.

---

## Why do you need it?

Guess-and-check debugging wastes hours and often makes things worse by patching symptoms instead of causes. `/debug-it` is **faster** because it's systematic. Its two core rules:

- **Iron Law:** no fix without a proven root cause.
- **Anti-tunneling Law:** always look in *both* directions — sometimes the bug is that the code does too much, not too little. (This is the trap that keeps people stuck for hours.)

It even has a built-in "circuit breaker": if attempts keep failing, it deliberately changes its approach rather than repeating the same idea.

---

## How it helps you vibe code

Bugs are the most demoralizing part of building. `/debug-it` is designed for a **tired, busy person who needs a good decision in ten seconds** — it presents fixes as a simple decision card and does the investigative heavy lifting so you don't spin your wheels.

---

## How to use it

When something's broken, type:

```
/debug-it
```

Describe (or point it at) the problem. It reads the actual error, reproduces the issue, checks recent changes, and only then proposes a fix — grounded in evidence, not guesses.

---

## When to use it

- ✅ Any time something breaks or behaves unexpectedly.
- ✅ **Especially** after a first fix attempt didn't work.
- ✅ Before proposing fixes, when you want to avoid thrashing.

---

## Which expert does the AI become?

For debugging, the AI works as a **reliability & performance engineer**, not a generalist — automatically, no prompt. That means it thinks about the causes generalists skip (timing issues, resource limits, things happening twice) instead of slapping on a quick patch. What you get: the *proven* root cause, a fix for it, and a test so the bug can't quietly return. (Set behind the scenes from your app's details — see the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job).)

---

## Related skills

- [`/resume-it`](02-resume-it.md) — often where a bug surfaces during ongoing work.
- [`/fix-it`](09-fix-it.md) — for fixing *security* findings specifically (different job).
- [`/dispatch-it`](14-dispatch-it.md) — when you have several *unrelated* bugs to fix at once.
