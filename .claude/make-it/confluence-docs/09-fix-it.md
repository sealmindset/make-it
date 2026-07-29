# /fix-it — Automatically fix security findings

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/fix-it` reads the most recent security report from [`/nemo-it`](08-nemo-it.md), sorts each finding into "can be fixed automatically" vs. "needs a human," applies all the automatic fixes, **checks the app still works**, and then re-scans to show you an updated report with the before/after difference.

> **In one sentence:** The doer that fixes what `/nemo-it` found — safely, and with proof it didn't break anything.

---

## What is it used for?

Closing the gap between *finding* security problems and *shipping* a safe app. It:
- Fixes vulnerabilities (upgrading unsafe building blocks, tightening settings, etc.).
- Verifies the app still builds and passes its tests after each batch of fixes.
- Re-runs `/nemo-it` so you can see exactly what improved.

---

## Why do you need it?

A security report is only useful if someone acts on it. `/fix-it` does the acting — methodically and safely. It **verifies after every fix category**, because a fix that breaks your app is worse than the original problem. You get fewer vulnerabilities *and* confidence that nothing regressed.

---

## How it helps you vibe code

You don't need to understand each vulnerability or how to patch it. `/fix-it` shows you what it plans to change in plain language ("I upgraded the framework to fix a security bug," not cryptic version numbers and codes), applies it, and proves the app still works.

---

## How to use it

After running [`/nemo-it`](08-nemo-it.md), type:

```
/fix-it              # fix all CRITICAL + HIGH findings (default)
/fix-it critical     # fix only CRITICAL findings
/fix-it high         # same as default
/fix-it medium       # fix CRITICAL + HIGH + MEDIUM
/fix-it all          # fix everything, including low-priority items
```

It will ask **how you want your work saved** (a new branch, or the current branch, with various commit styles), then work through the fixes.

**The six phases:** Preflight → Triage (classify + get your approval) → Fix → Verify (build/tests/lint) → Re-scan → Report.

---

## When to use it

- ✅ Right after `/nemo-it` reports findings you want resolved.
- ✅ Before shipping, to clear out known vulnerabilities.

**When *not* to use it:**
- ❌ You haven't scanned yet → run [`/nemo-it`](08-nemo-it.md) first (it needs the report).

---

## Good to know

- Some findings **can't be safely auto-fixed** — `/fix-it` clearly separates those and leaves them for a human, rather than guessing.
- It always gets your **approval on the plan** before changing anything.

---

## Which expert does the AI become?

When fixing security findings, the AI works as a **security engineer**, not a generalist — automatically, no prompt. It fixes the *underlying cause* and can explain why the fix is sound, instead of a surface patch that looks fine but leaves the door open. (Set behind the scenes from your app's details — see the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job).)

---

## Related skills

- [`/nemo-it`](08-nemo-it.md) — produces the report `/fix-it` acts on (run this first).
- [`/ship-it`](06-ship-it.md) — go live once findings are cleared.
- [`/dispatch-it`](14-dispatch-it.md) — used internally to fix independent issues in parallel.
