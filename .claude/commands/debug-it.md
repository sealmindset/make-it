---
name: debug-it
description: Systematic debugging that finds the root cause BEFORE any fix and kills assumption-tunneling. Four phases — root-cause investigation (read the full error, reproduce, check recent changes, instrument component boundaries, trace data flow backward) → pattern analysis (working vs broken) → hypothesis (both "missing step" AND "doing too much" families) → test-first implementation. Two-tier circuit-breaker: flip the lens at 2 failed attempts, question the architecture at 3+. Presents fixes as a tired-friendly decision card. Use for ANY bug, test failure, build failure, or unexpected behavior — before proposing fixes, especially after a fix already failed.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Skill
---

<objective>

Find the *real* cause of a bug, fix the root (not the symptom), and prove it — without
thrashing. Optimized for a tired, multi-tasking operator who needs a good call in ten seconds.
Systematic debugging is FASTER than guess-and-check, especially under pressure.

</objective>

# /debug-it -- root cause first, no looping until 1AM

> A project may ship its own `/debug-it` that shadows this one (capture tools, live-system
> safety rails, ship ritual). Inside such a repo, the project version wins. This is the core.

---

## Two laws

**Iron Law — no fix without root cause.** If you haven't completed Phase 1, you cannot propose a
fix. Symptom patches are failure: they mask the issue and breed new bugs. The error message
often contains the answer — reading it beats guessing.

**Anti-tunneling Law — look both directions.** Painful loops die the same way: every hypothesis
assumes something is *missing*, so every fix *adds* code. When the cause is the opposite (doing
*too much*: a double-action, an over-eager safeguard, a redesign where a one-line workaround
suffices, or the platform already handles it), an all-additive loop never finds it. Force
hypotheses from BOTH families, every time.

---

## Hard rules

1. **Evidence before theory.** Read the FULL error / stack trace (line numbers, file paths,
   error codes — they often name the fix), plus logs / capture / DOM / failing assertion. Build a
   **Facts** list (observed) separate from guesses. Never propose a cause you haven't grounded in
   an observation.
2. **Reproduce before you fix — reliably.** Exact steps; does it happen every time? If you can't
   reproduce it, gather more data — do NOT guess. Capture the reproduction as an automated
   **failing test** when a framework exists (red now, green after the fix, and it stays as the
   regression guard).
3. **Check what changed.** `git diff` / recent commits / new deps / config / env differences — a
   recent change is the #1 root-cause lead.
4. **Never reproduce against a live or irreversible system without explicit per-run approval.**
   Prefer a captured session, a rehearsal/staging target, or a mock.
5. **Both families, every time.** Generate ≥1 *additive* and ≥1 *subtractive* hypothesis before
   proposing a fix (see the table).
6. **One hypothesis at a time, tested minimally.** Smallest possible probe/change, one variable.
   Don't bundle fixes — you won't know what worked.
7. **Fix the root, smallest reversible change.** No symptom patches, no "while I'm here"
   refactors. A pragmatic workaround beats a redesign unless only the redesign prevents recurrence.
8. **Verify against the SAME reproduction.** The failing test goes green, the full suite still
   passes, and the original symptom is gone.
9. **Say what you don't know.** "I don't understand X" beats pretending. Only ask the human what
   changes your actions; otherwise proceed and state assumptions.
10. **Many independent bugs? Fan out.** 3+ INDEPENDENT failures → one agent per domain in
    parallel (`/dispatch-it`), each running this method. Keep *related* failures together.

---

## Hypothesis families (pull from both)

| Family | Mental prompt | Examples |
|--------|---------------|----------|
| **Additive** ("too little") | What step / check / data / await is missing? | unhandled case, missing await, absent null-guard, skipped setup call, race not waited for |
| **Subtractive** ("too much") | What are we doing that we shouldn't? What does the platform already do? | double-fired action, over-eager safeguard rejecting a valid state, retry that duplicates, re-implementing what the framework handles, redesign where a cleanup/workaround suffices |

A loop stuck in one family almost always has its answer in the other.

---

## Workflow — four phases (complete each before the next)

### Phase 0 — Intake
Get the failure from the message, scrollback, or the logs pointed at. Restate the symptom in one
line to confirm you have the right bug.

### Phase 1 — Root-cause investigation (NO fixes yet — the Iron Law)
- **Read the error completely** — stack trace, line/file, codes. Don't skip warnings.
- **Reproduce & isolate** — pin the *exact* failing line / state / DOM node, not the area. UI →
  drive it (Playwright / a capture tool); backend → smallest script/test; intermittent → run N
  times and note what flips it. Not reproducible → gather data, don't guess.
- **Check recent changes** — `git diff` / `git log`, new deps, config, env differences. And
  **external** changes: a working integration/automation that suddenly breaks is often an upstream
  site/API/credential change, not your code — check that before suspecting your own commits.
- **Multi-component systems** (CI→build→sign, API→service→DB, stage→stage pipelines): instrument
  each **boundary** — log what data ENTERS and EXITS each component. Run once to see *where* it
  breaks, THEN dig into that component. Don't guess which layer.
- **Trace data flow backward** — where does the bad value originate? what passed it in? keep
  tracing up to the source; fix at the source, not where it surfaced.
- Output: a **Facts** list + **Open questions**, each candidate cause tagged by family.

### Phase 2 — Pattern analysis (diff working vs broken)
- Find a **working example** — similar code that works in this codebase.
- If you're applying a pattern, read the reference implementation **completely** — don't skim.
- List **every difference** between working and broken. Don't dismiss "that can't matter."
- Confirm dependencies / config / env / assumptions.

### Phase 3 — Hypothesis & decision card
- From the candidates, state the most-supported one: **"X is the root cause because Y."**
- Cheap to confirm? Run a **minimal probe** (one variable) before the real fix.
- Present **two complete fixes** as the decision card (two ways to fix the *confirmed* root
  cause — typically an additive and a subtractive option). Recommend the smallest reversible one.
  If there's no real tradeoff and the smallest fix is obvious, proceed and note it.

### Phase 4 — Implementation & verification
- Ensure a **failing test reproduces the bug** before fixing (TDD).
- Implement **one** root-cause fix. No bundled changes.
- **Verify** — the failing test goes green, the full suite still passes, the original repro is gone.
- **Defense in depth** — add validation at the layer(s) that *should* have caught it.
- **Capture the lesson** (especially subtractive/over-engineering misses) to project memory/notes.

---

## Circuit-breaker (two tiers — anti-loop)

- **At 2 failed attempts in the SAME family** → flip the lens: *"We've added things twice and it
  still fails — the cause is probably that we're doing too much. Subtractive hypotheses only:"*
  (or vice-versa). Never start a 3rd same-family attempt without flipping.
- **At 3+ failed fixes overall** — ESPECIALLY if each fix reveals a new problem elsewhere, needs
  "massive refactoring," or spawns new symptoms — **STOP. This is not a failed hypothesis; it's
  likely the wrong architecture.** Question fundamentals (is this pattern sound, or are we
  continuing through inertia?) and escalate to the human before fix #4.
- **Live / browser-automation bug? The breaker action is a CAPTURE, not another theory.** After 2
  loops on a UI/automation failure you can't fully observe, STOP theorizing and get **fresh
  ground-truth from the human** — a recorded session / real DOM capture / a verbose run log. The
  breakthrough almost always comes from the capture, not the guess. (And if you hit an
  anti-automation/WAF wall, stop automating and go human-in-the-loop — don't try to defeat it.)

---

## Tired-mode decision card (output format)

```
BUG   -- <one sentence, plain English>
CAUSE -- <root cause in one line, grounded in an observed fact / the error>

A) <name>  [additive | subtractive]
   What: <the change, one line>     Risk: <blast radius, one line>
B) <name>  [additive | subtractive]
   What: <the change, one line>     Risk: <blast radius, one line>

I'd pick <A/B> because <one line — usually smallest reversible root fix that can't recur>.
Reply A, B, or tell me your own.
```
Use an analogy only when something is genuinely hard to reason about cold.

---

## Red flags — STOP and return to Phase 1

If you catch yourself: "quick fix now, investigate later" · "just try X and see" · "it's probably
X, fix that" · multiple changes at once · "skip the test, I'll eyeball it" · "I don't get it but
this might work" · proposing fixes before tracing data flow · **"one more fix"** after 2+ failures
· each fix reveals a new problem elsewhere — all of these mean STOP, you're guessing.

**Human signals that mean re-investigate:** "stop guessing", "is that not happening?" (you assumed
without verifying), "will it show us…?" (add instrumentation), **"ultra-think this"** (question
fundamentals, not just symptoms), "we're stuck?" (your approach isn't working).

## "No root cause"? — 95% of the time that's incomplete investigation
If it's truly environmental / timing / external, you've *finished* the process: document what you
ruled out, add appropriate handling (retry / timeout / clear error) and monitoring. But assume
incomplete investigation first.

## Supporting techniques
- **Root-cause tracing** — trace the bad value backward to its origin; fix at source, not symptom.
- **Defense in depth** — after the root fix, validate at the layers that should have caught it.
- **Condition-based waiting** — replace arbitrary timeouts with polling on the real condition;
  never "just bump the timeout."

---

## Canonical worked example (the lesson, distilled)
A one-click "submit" kept producing a phantom duplicate/incomplete record. The loop spent a night
on additive hypotheses ("a step is missing — add a cleanup, add a guard, wait for another
element"). Phase-1 evidence + a *subtractive* hypothesis would have found it on attempt #1: the
click handler **double-fired** (fix: click once), and the leftover record just needed a pragmatic
**cleanup after the real submit** — not a re-architected flow. Root cause first, both directions.
