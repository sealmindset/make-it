---
name: parked-state-reported-as-missing
signals: [message says "none", "not provided" or "refused" while a record exists in a set-aside or waiting state, a run polls a record it will not use, many read/audit rows per minute]
seen: 2026-11-07 (1 incident)
---
## Shape
A record exists but is parked (set aside, awaiting a person, not yet tried). The code collapses
"parked" and "absent" into one message, so people are told something was never provided or was
refused when it was saved and is waiting -- and a run may poll it for minutes, refusing to use it.
## How to confirm
The record's status against the message the person saw; the polling reads in the access log.
## Fix
Words that read the real status ("saved, waiting for a try -- press Try once now"); fail fast instead
of polling a parked record.
## Prevent
A test per state that the message names that state.
