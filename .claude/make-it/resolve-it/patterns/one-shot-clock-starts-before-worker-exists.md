---
name: one-shot-clock-starts-before-worker-exists
signals: [a one-time try or token "withdrawn" or "expired" before any attempt, worker scaled from zero, first worker boots minutes after the click, a different job used the try]
seen: 2026-11-07 (1 incident)
---
## Shape
A person's action arms a one-shot (a single sign-in try, a short-lived token) with a clock that starts
at the click. The work that should use it waits for a worker that scales from zero and takes minutes
to boot -- or another job takes it first. The clock runs out before the intended job ever starts, and
the person is told the try was used or refused.
## How to confirm
The arm time, the worker's first boot log, the withdraw/expire record, and which job (if any) touched
it. Compare the window with the cold-start time.
## Fix
Start the clock when a worker claims the intended job, not at the click; bind the one-shot to that job.
## Prevent
A test with a cold-start delay longer than the old window; words that say "waiting for a worker".
