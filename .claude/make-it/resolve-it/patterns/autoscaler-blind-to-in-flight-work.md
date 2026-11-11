---
name: autoscaler-blind-to-in-flight-work
signals: [scale-in to zero while a job runs, scale-in metric is "messages visible" only, long jobs, worker stops mid-download]
seen: 2026-11-11 (1 incident)
---
## Shape
A queue worker scales in on "messages visible < 1". A message being processed is not visible, so a
long job makes the queue look empty and the autoscaler stops the worker that is doing the work.
## How to confirm
The scale-in alarm's metric and statistic; the scale-in time against the job's start; the worker's
shutdown line mid-job.
## Fix
Task scale-in protection held for the whole job (see protection-dropped-at-job-handoff), or scale
in on visible + in-flight.
## Prevent
A job outliving the scale-in window in a test or a staging soak.
