---
name: resolve-it
description: Take a problem from a person's report, an alert or failed job, or a backlog card all the way to the person's outcome on the live system -- then make sure it can't happen silently again. An investigator agent gathers evidence read-only from the project's own systems and checks a shared library of known root-cause patterns; /debug-it finds each cause; a plain-English writer drafts what to tell the affected person today; the fix is test-first with a table of every variation of the problem; an independent adversarial reviewer tries to break it round by round; then ship, verify the real outcome, and loop when the next stacked cause shows up. Ends with prevention (detection, refusals, follow-up cards) and four records: the card, an incident report, memory and doctrine, and a new pattern for the library. Project-agnostic. Use when something a person needed did not happen, especially when the first fix didn't make it happen.
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

Resolve the problem for the person who has it, prove it on the live system, find every cause behind
it (they stack), and leave the system and the records so the same failure is caught sooner -- or never
happens -- next time, in this project or any other.

</objective>

<execution_context>

@~/.claude/make-it/references/resolve-it.md
@~/.claude/make-it/references/approval-block.md
@~/.claude/make-it/references/operator-safety.md

</execution_context>

<expert_persona>

Work as an **SRE / incident commander**: outcome first, evidence over theory, one change at a time,
nothing hidden. Agents get the persona their task calls for (see `expert-personas.md`).

@~/.claude/make-it/references/expert-personas.md

</expert_persona>

# /resolve-it -- from the report to the outcome, and never silently again

`/debug-it` finds one cause. This skill carries the whole loop: the person's outcome, every stacked
cause, the variations, the review, the live proof, the prevention and the records. It calls
`/debug-it` for each root cause and never replaces it. A project may ship its own `/resolve-it`; the
project version wins inside that repo.

## Arguments
`/resolve-it <report text | alert | job id | card id> [--propose | --end-to-end]`
No argument: ask once what isn't working and for whom.

## Step 0 -- Settle the run
1. Read the project's `CLAUDE.md`, doctrine file and memory index for: its evidence sources, how it
   ships, its standing authorizations, its model ladder, and a `resolve-it.autonomy:` line.
2. Autonomy (`resolve-it.md` §2): the flag, else the project's line, else `project`; a project whose
   doctrine says nothing about shipping runs `end-to-end`. State it once, with its source.
3. Find or file the card (`/backlog-it` capture rules; Bugs epic). All phase notes go on it.

## The loop (details and rules: `resolve-it.md` §4)
1. **Intake** -- the outcome sentence (§1), who is affected, what they tried.
2. **Evidence** -- dispatch the investigator (`~/.claude/make-it/resolve-it/investigator-prompt.md`),
   read-only, model per the project's ladder. Never investigate on a path that can write (§3.1).
3. **Patterns** -- match the evidence against `~/.claude/make-it/resolve-it/patterns/` and
   `~/.claude/resolve-it/patterns/` (§10). A match is a hypothesis.
4. **Root cause** -- run `/debug-it` on the evidence. The cause names the exact point and its proof.
5. **Today's outcome** -- the writer (`~/.claude/make-it/resolve-it/writer-prompt.md`) drafts the
   update and the workaround for the owner to send (§5). Never send it.
6. **Variations, then fix** -- the §8 table first, then test-first through the project's gates; fix
   the shared place. Quote any rule the owner states, verbatim, into the doctrine.
7. **Adversarial review** -- `~/.claude/make-it/sdd/adversarial-reviewer-prompt.md`, independent,
   the strongest model the ladder allows; rounds until "ship"; accepted Minors listed.
8. **Ship and verify the outcome** (§7) -- the outcome sentence observed true on the live system,
   counts reconciled. Not true: back to step 2 with the new evidence (a stacked cause).
9. **Prevent** -- detection for every silent failure, refusals for every easy human mistake, a card
   for every manual unblock (§3.6) and every deferred item.
10. **Record** -- card, `docs/incidents/<date>-<slug>.md` (§12), memory and doctrine, patterns (§9-10).
    Then the owner report (§11).

## Asking the owner
Only what changes the run, decision-ready and batched (`approval-block.md`). Questions the evidence
can answer are not asked. A high-stakes step the project gates (a release, a data change outside the
autonomy level) is asked on its own, with what changes, the evidence, the blast radius and the undo.

## Never (any level -- `resolve-it.md` §3)
- Write anything while investigating; re-run, re-send or restart as a way of looking.
- Send, post or reply to anyone outside the team.
- Print, log or store a secret; put a private person's name in a shared channel.
- Leave a safeguard bypassed without disclosing it with its undo, or a manual unblock without a card.
- Call it done before the outcome is observed on the live system.
