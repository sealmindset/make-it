---
name: watcher-reads-failure-as-done
signals: [monitor reports "all done" or "healthy" but the work is not, an empty or failed reading, status check returned nothing]
seen: 2026-11-11 (1 incident)
---
## Shape
A watcher decides "finished" when its reading contains no "running" rows. A failed or empty reading
also contains none, so a query error reads as success.
## How to confirm
Re-read the status directly; compare with the watcher's last real reading.
## Fix
An empty or failed reading is "unknown": retry it; only a successful reading with nothing running is
"done".
## Prevent
The watcher logs the reading it decided on.
