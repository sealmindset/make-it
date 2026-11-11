# /resolve-it — From "it didn't happen" to "it happened, and it won't fail silently again"

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/resolve-it` takes a problem someone reported — "my client's files never arrived", an alert, a failed job, or a bug card — and works it until the person actually has what they needed, checked on the real system. Then it makes sure the same failure is caught sooner, or can't happen, next time.

> **In one sentence:** Tell it what didn't happen for whom; it finds every cause, fixes them, proves the result, and writes down what it learned.

---

## What is it used for?

- **Problems a person reports** — something they needed didn't happen, and they don't know why.
- **Problems that come back** — the first fix didn't make it work, because another cause was hiding behind the first.
- **Learning from each problem** — every cause is kept as a pattern, so the next problem (in any project) is recognised faster.

---

## Why do you need it?

Real problems rarely have one cause. In the case that led to this skill, one missing delivery took five causes to resolve, and each one only became visible after the one before it was fixed. Fixing "the bug" and stopping there leaves the person still waiting. `/resolve-it` keeps going until the person's outcome is real, and leaves the system better at noticing the next time.

---

## How it works

1. **Understands the goal** — writes down, from the person's side, what should be true ("the files are in the case").
2. **Gathers evidence without changing anything** — an investigator agent reads the system's own records and logs, read-only.
3. **Checks known patterns** — a shared library of causes seen before, in any project.
4. **Finds the root cause** — using `/debug-it`'s method.
5. **Helps the person today** — drafts a plain-English update and a workaround for you to send. It never sends anything itself.
6. **Lists every variation** of the problem, then fixes it test-first.
7. **Gets an independent review** — a separate agent tries to break the fix before it ships.
8. **Ships and checks the real result** — if the person's outcome still isn't there, it looks for the next cause and repeats.
9. **Prevents a repeat** — adds an alert or a clear message where the failure was silent.
10. **Keeps the record** — the backlog card, an incident report, project memory and rules, and the pattern library.

---

## How far does it go on its own?

You choose per project (or per run): **propose** (stop at the plan), **project** (follow the project's own rules — the default), or **end-to-end** (fix, ship and verify without stopping). Whatever you choose, it never changes anything while investigating, never messages anyone outside the team, never shows a secret, and tells you about anything it had to do by hand.

---

## How to start it

```
/resolve-it "Client's evidence from the county still isn't in the case"
/resolve-it E63-S346
```
