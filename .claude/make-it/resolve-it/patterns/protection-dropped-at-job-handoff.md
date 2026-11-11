---
name: protection-dropped-at-job-handoff
signals: [job killed seconds after it started, worker got SIGTERM mid-job, a deploy or scale-in was pending, jobs run back to back, protection or lease toggled off then on in the same second]
seen: 2026-11-11 (2 kills, 1 incident)
---
## Shape
A worker protects itself from scale-in or deploys only while its in-flight count is above zero. When
jobs run back to back, the count touches zero at each hand-off, protection is dropped and retaken in
the same second, and a pending stop takes the task in that gap -- killing the next job just after it
starts.
## How to confirm
The platform's audit trail for the protection call (off then on at the same second on the same task),
a pending stop just before it (desired count lowered, a deployment), the worker's shutdown line a few
seconds later.
## Fix
Hold protection through a short idle grace after the last job, cancelled when a new job starts;
apply calls in order; renew before the protection's own expiry while busy; retry a failed protect.
## Prevent
A test of the hand-off; an alert on a job killed by a planned stop.
