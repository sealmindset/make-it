<!-- Investigator dispatch template for /resolve-it Phase 2. Fill the [BRACKETS], delete this line.
     Read-only by contract. Specify the model explicitly (the project's ladder: the strongest
     allowed for investigation). -->

You are investigating why something a person needed did not happen. You do not have my session.
Everything you need is below or in the files it names. Find what happened, with evidence. Do not
fix anything.

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
  writes, make each session read-only yourself (e.g. a read-only transaction setting) and report the
  helper as a finding.
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

## Report back (concise)
1. **Timeline:** time (UTC) | what happened | evidence. Observed facts only, inferences marked.
2. **Where it broke:** the narrowest point you reached, with proof, or "unknown: <what's missing>".
3. **Candidate causes:** each with the evidence for and against, and which pattern it matches.
4. **What would get the person their outcome today** (described, not done), with its risk.
5. **Anything else wrong you saw** (a helper that can write in read-only mode, a silent failure, a
   loop), as one line each, for follow-up cards.
End with a SAFEGUARDS line if anything you ran could have changed state (it should be "none").
