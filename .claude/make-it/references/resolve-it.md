# /resolve-it -- from a report to a verified fix and its prevention

Loaded by `/resolve-it`. This file is the contract; the command is its outline. Project-agnostic: it
names no stack, cloud, mail system or firm. A project's own facts (where its logs live, how it
ships, what it may change alone) come from that project's `CLAUDE.md`, memory and doctrine.

Origin (2026-11-11): one missing-evidence report took five stacked causes to resolve -- a login saved
under the wrong address; an intake that dropped the system's own replies; a mail redirect that hid
the sender's authentication; a rule the owner then stated ("only the court number decides"); and a
worker that dropped its own protection between two jobs. Each cause hid the next. `/debug-it` found
each one; nothing carried the loop from the person's report to the person's outcome, or kept the
lessons. This skill is that loop.

---

## 1. The outcome, not the bug

Every run starts by writing the **outcome** as one checkable sentence, from the affected person's
side: "the client's evidence is in the case", "the invoice reaches the customer", "the export opens".
A run is done only when that sentence is **observed true on the live system** (§7). Green tests,
a merged PR and a clean deploy are steps, never the finish.

## 2. Autonomy: three levels, one per run

| Level | What it may do without asking |
|---|---|
| **propose** | Investigate (read-only), then stop with the cause, the fix plan, the variations table and the prevention plan. |
| **project** | Everything the project's own doctrine allows without asking (its PR/CI/review gates, its standing authorizations for merge, deploy, release). It stops exactly where that doctrine says to stop. |
| **end-to-end** | Fix, review, ship and verify without stopping, still inside every safety rail in §3. |

**Default:** `project`. A project whose doctrine says nothing about shipping runs `end-to-end`
(the owner's choice, 2026-11-11). The level can be set per project (a `resolve-it.autonomy:` line in
its `CLAUDE.md`) and overridden per run (`/resolve-it --propose`, `--end-to-end`). The run states
its level once, at intake, with where it came from.

## 3. Safety rails (every level, no exceptions)

1. **Investigation never writes.** Reading a live system is read-only by construction (a read-only
   session or role, not a flag the tool may ignore; a "read-only" helper that can still write is a
   finding to file). A data change is a fix (§6), never part of looking.
2. **No message reaches a person outside the team.** Updates to the affected person are drafts the
   owner sends (§5). The skill never sends, posts or replies on anyone's behalf.
3. **No secret is printed, logged or stored** -- not in chat, cards, reports or patterns. Check that a
   credential exists and when it changed, never its value.
4. **No client or person's name in a shared channel** (chat rooms, Slack, public trackers). Cards,
   reports and patterns name records by id and outcome.
5. **Disclose every safeguard bypassed or weakened** (a skipped test, a suspended alarm or autoscaler,
   a hand-sent queue message, a skipped soak): what, why, the undo, and when it is undone. Use the
   SAFEGUARDS line from `approval-block.md`.
6. **A manual unblock is a bug report.** Anything the run had to do by hand to get the outcome (re-send
   a message, re-queue a job, flip a setting) is filed as a card: the system should have done it.
7. **The project's gates win.** Test-first, review, CI and release rules in the project's doctrine
   bind at every level; `end-to-end` removes the stops, never the gates.

## 4. The phases

Run them in order. Phases 2-8 loop: a live check that fails sends the run back to Phase 2 with the
new evidence (§7). Record each phase on the card as it ends (§9), so a cleared session resumes.

**Phase 1 -- Intake.** From the trigger (a person's report, an alert or failed job, a backlog card),
write: the outcome sentence (§1); who is affected; what they already tried; the autonomy level.
Find the card or file one (Bugs epic, `/backlog-it` capture rules). Never ask the affected person
anything; ask the owner only what changes the run.

**Phase 2 -- Evidence (investigator agent).** Dispatch the investigator (`resolve-it/investigator-prompt.md`)
with the outcome, the trigger, and the project's evidence sources as its notes list them (database,
logs, queues, mail, audit trail, cloud APIs, the system's own job records). It returns a timeline of
observed facts with their sources, the narrowest point reached, and what it could not see. Facts and
inferences stay labelled.

**Phase 3 -- Known patterns first.** Before theorizing, match the evidence against the pattern
library (§10): shipped seeds plus the owner's learned patterns. A match is a hypothesis to prove,
never a conclusion.

**Phase 4 -- Root cause (`/debug-it`).** Hand the evidence to `/debug-it` for the method: Iron Law,
both hypothesis families, the circuit-breaker. The cause must name the exact point (file and line,
the config value, the record) and the evidence that proves it.

**Phase 5 -- Today's outcome (writer agent).** In parallel with the fix: the fastest safe way for the
affected person to get their outcome now (a manual step, a workaround), drafted for the owner to send
(`resolve-it/writer-prompt.md`). The fix may take hours; the person should not wait for it.

**Phase 6 -- Variations, then the fix.** Before writing code, list the **variations** of this problem
(§8): the forms the same failure takes, seen or plausible, each with its handling. Then fix
test-first: one failing test per variation that is handled in code, red before the change, green after.
Fix the shared place every caller goes through, not the one path the report named. Any rule the owner
states during the run is quoted verbatim into the project's doctrine (§9), and the fix follows it.

**Phase 7 -- Adversarial review.** An independent reviewer that never sees the investigator's or the
implementer's reasoning tries to break the fix (`sdd/adversarial-reviewer-prompt.md`, the strongest
model the project's model ladder allows). Rounds continue until it says ship; each round's real
findings are fixed with a test first, Minors that can't misfile or lose data may be accepted, and
every accepted one is listed on the PR and the card. Stop after three rounds with no Critical or
Important findings.

**Phase 8 -- Ship and verify the outcome.** Ship through the project's gates and at its autonomy
level. Then verify the **outcome sentence** on the live system (§7). Not true yet? The next cause
was hiding behind this one: back to Phase 2 with what the live system now shows.

**Phase 9 -- Prevent.** For every cause: what would have told someone sooner? A failure that was
silent gets detection (an alert to the owner, or a message to the sender when the sender can act);
a failure a person could cause gets a refusal with plain words at the moment they cause it; a
manual unblock from the run gets its card (§3.6). File follow-ups for anything deferred.

**Phase 10 -- Record.** Write all four records (§9). Then report to the owner (§11).

## 5. Messages to the affected person

Drafts only, for the owner to send. Plain words, no codes, no system names, no blame. Say what
happened in one or two sentences, what they can do today, and what changes so it won't happen again.
Never promise a time the run can't control. One draft per real change in their situation, not per
phase.

## 6. What counts as a fix

- It removes the cause. A change that hides the symptom is not a fix.
- It changes the shared place all callers go through.
- Every variation it handles has a test that failed before it.
- It discloses any safeguard it touched (§3.5).
- A data change on a live system is a fix: guarded (it touches only rows that match the evidence),
  logged, with its undo written down before it runs, and inside the autonomy level.

## 7. Verify the outcome, and the stacked-cause loop

After shipping, look at the live system for the **outcome**, not the fix:
- Read the record that proves it (the files in the case, the sent invoice, the opened export), and
  count what came back against what was promised.
- A count that differs from the promise is reconciled before "done": by the system's own
  completeness record when it has one, or by an explanation backed by evidence.
- **Not true yet:** do not patch on top. Return to Phase 2 with the new evidence. Each loop is a new
  cause with its own variation table, tests and review. Five loops are normal for a deep failure.
- A background watcher that reports "done" must have read real data: an empty or failed reading is
  "unknown", never "finished".

## 8. The variations table

One row per form the problem takes. Columns: **Variation** (seen, or plausible from the evidence) |
**Handling** (what the system now does) | **Proof** (the test name, or "accepted: <why>"). Rows
come from the evidence, the review rounds and the owner's rules. The table goes in the PR, the
incident report and the card. A handling may be "hold and ask the person who can answer", never a
silent drop.

## 9. Records: four places, so it is recalled next time

| Record | Where | Contains |
|---|---|---|
| **Card** | The project's backlog (`/backlog-it`), Bugs epic | Findings per phase, PRs, live proof, stage moved to Checked only on the outcome; follow-up cards for deferred items and manual unblocks. |
| **Incident report** | `docs/incidents/<YYYY-MM-DD>-<slug>.md` in the project | The format in §12. |
| **Memory and doctrine** | The project's memory; its doctrine file (`CLAUDE.md` or the file it names) | Lessons as memory entries; any rule the owner stated, verbatim and dated, in the doctrine. |
| **Pattern library** | Shipped seeds in `~/.claude/make-it/resolve-it/patterns/`; the owner's learned patterns in `~/.claude/resolve-it/patterns/` (user-level, shared across projects, never overwritten by an install) | Each root cause made generic (§10). |

## 10. The pattern library

One file per pattern, generic: no project, firm, client or vendor-account names; a technology may be
named when the pattern depends on it. Format:

```markdown
---
name: <kebab-slug>
signals: [<observable symptom>, <log or record shape>, ...]
seen: <YYYY-MM-DD> (<count> incidents)
---
## Shape
<the cause in two or three sentences>
## How to confirm
<the read-only check that proves or rules it out>
## Fix
<the fix that removes it, and where>
## Prevent
<the detection or refusal that catches it sooner>
```

Phase 3 reads every pattern's `signals` against the evidence. Phase 10 writes a new pattern for each
cause not already in the library, or bumps `seen` on the one it matched. Learned patterns go to the
user-level folder; a learned pattern worth shipping is proposed to the framework as a PR.

## 11. The report to the owner

Short and in plain words. The outcome (true or not, with the proof); the causes in order, each one
sentence; what is live and what is pending; what was done by hand and its card; safeguards touched
and their undo; follow-up cards; the draft message for the affected person. If asked whose fault it
was: count the causes, say which were code and which a person did, and whether the system invited
the person's step. Never blame the affected person.

## 12. Incident report format (`docs/incidents/<date>-<slug>.md`)

```markdown
# <outcome sentence> -- <date>
**Status:** resolved | partly resolved (<what is pending>)   **Card:** <id>   **PRs:** <list>
## What the person saw
## Timeline
| Time (UTC) | What happened | Evidence |
## Causes (in the order they were found)
1. <cause> -- <proof> -- fixed by <PR> -- human or code: <which, and whether the system invited it>
## Variations and how each is handled
<the §8 table>
## What we did by hand, and its card
## Prevention added
## Follow-ups
## Lessons (also in memory; patterns: <names>)
```
