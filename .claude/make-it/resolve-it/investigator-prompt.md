<!-- Investigator dispatch template for /resolve-it Phase 2. Fill the [BRACKETS], delete this line.
     Read-only by contract. Specify the model explicitly (the project's ladder: the strongest
     allowed for investigation). -->

You are investigating why something a person needed did not happen. You do not have my session.
Everything you need is below or in the files it names. Find what happened, with evidence. Do not
fix anything.

Work as the specialist this investigation calls for, held to the checks and output standard of every specialist recorded in `expert_persona` in the app's `app-context.json`; with no `expert_persona` set, or an older value the reference does not count (its "Reading an older value"), work as that specialist alone.

## The outcome that is not true
[OUTCOME_SENTENCE]  (from the affected person's side, e.g. "the client's evidence is in the case")

## What we were told
[TRIGGER -- the report, alert, failed job or card, verbatim; names of private people redacted]

## Where the evidence lives (from the project's own notes)
[EVIDENCE_SOURCES -- each source with how to read it read-only: the database helper and its
read-only switch, log groups, queues, mailboxes, audit trails, the job records]

## Already known (do not re-derive)
[PRIOR_FINDINGS or "none" -- earlier loops' causes, fixes and what is now live]

## Rules -- READ-ONLY, no exceptions
- Read nothing through a path that can write. If a helper's "read-only" mode does not actually block
  writes, or no read-only path exists, make each session read-only yourself (e.g. a read-only
  transaction setting), list every run in your SAFEGUARDS line, report the helper as a finding, and
  carry on.
- No retries, re-runs, re-sends, restarts, deploys, setting changes or messages to anyone.
- Never print a secret: check that a credential exists and when it changed, never its value.
- Never put a private person's name anywhere but your report to me.
- Do not call billable AI or paid APIs unless the brief says you may.

## Method
1. Start from the outcome and walk backward through the system's own records: what was supposed to
   happen, step by step, and where the evidence stops matching.
2. For every step, record **observed** facts with their source (record id, log line with time,
   header, file:line). Keep every **inference** labelled as one.
3. Check these known pattern signals first, and say which match: [PATTERN_SIGNALS]
4. Look in both directions: something missing (a step never ran) AND something doing too much (a
   filter, a guard, a cleanup or a scale-in that removed what was needed).
5. When a step's record is missing, say where you looked and what you would need to see further.
6. Compare ids you find in logs against the database: a log id with no row is **deleted evidence**.
   Say so and name where it could be recovered (a point-in-time restore, a snapshot, request logs).
7. Map each action the person says they took to the records it should have left.
8. Then **walk forward** from where it broke to the outcome: for each remaining step, read its code
   and say whether it will work once the break is fixed. A step that won't is a stacked cause.
9. Prior findings already shipped: for each, say whether it is live and whether it changed what the
   person sees.

## Report back (concise)
1. **Timeline:** time (UTC) | what happened | evidence. Observed facts only, inferences marked.
2. **Where it broke:** the narrowest point you reached, with proof, or "unknown: <what's missing>".
3. **Candidate causes:** each with the evidence for and against; which pattern signals fired and
   whether each pattern's *How to confirm* check passed or ruled it out.
   Then the **forward walk:** each remaining step, will it work, and why.
4. **What would get the person their outcome today** (described, not done), with its risk.
5. **Anything else wrong you saw** (a helper that can write in read-only mode, a silent failure, a
   loop), as one line each, sorted as ALREADY THERE: say for each whether it can lose data, leak a
   secret, send something wrong, or tell the person something untrue.
Sort every finding (`approval-block.md`, A review sorts its findings): IMPORTANT -- the change does
not do what it says; it tells the person something untrue; or it can lose data, leak a secret, or send
something wrong: fixed before the fix ships. MINOR -- anything else wrong with the change: list at most
five, the quickest to fix; they are fixed in the same work if quick, and the rest are dropped, not
filed. ALREADY THERE -- a fault older than the change: a card only if it can lose data, leak a secret,
send something wrong, or tell the person something untrue; otherwise one line for that skill's running
list. File no follow-up cards: leftovers are fixed inside the work.
Report in plain simple English, in a few short lines: what happened, what it means for the owner, what
they must do (often nothing). No jargon where a plain word exists. Name every card or pull request by its
title with its id, never a bare id.
Wait for CI or long tests with a foreground command that has a time limit, not a background one.
Never give your final report while a background command you started is still running: stop each one
with TaskStop first.
End with a SAFEGUARDS line if anything you ran could have changed state (it should be "none").
