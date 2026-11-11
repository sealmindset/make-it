---
name: orphaned-job-claim-skipped-on-redelivery
signals: [job stuck "running" with no worker, redelivered message logged "already claimed, skipping", queue empty, worker scaled to zero, recovery only after a long stale window]
seen: 2026-11-11 (1 incident)
---
## Shape
A worker dies mid-job and its claim stays on the job. The queue redelivers the message; the next
worker sees the claim, skips, and deletes the message. Nothing runs the job until a stale sweep
re-queues it, and a re-queue that lands on a worker that is itself shutting down is lost too.
## How to confirm
Job row: claimed, not updated for a long time. Logs: the skip line on redelivery. Queue: no visible
or in-flight message for it.
## Fix
A claim whose heartbeat stopped is stale: the next delivery re-claims instead of skipping; a
shutdown that can't finish releases its claims; a re-queue is confirmed received.
## Prevent
An alert when a claimed job has no heartbeat and no message in the queue.
