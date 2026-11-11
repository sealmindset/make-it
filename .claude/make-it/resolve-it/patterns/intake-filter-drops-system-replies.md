---
name: intake-filter-drops-system-replies
signals: [a job waits for an emailed link or callback that "never arrives", the email IS in the mailbox, intake status ignored/rejected as unknown or unauthorized sender]
seen: 2026-11-11 (1 incident)
---
## Shape
An intake that accepts only trusted senders (staff forwards, an allowlist) also receives the replies
the system itself asked a third party for (an export-ready email, a verification link). The filter
drops them, and the waiting job times out with "never arrived" -- a message that hides the cause.
## How to confirm
Find the expected reply in the mailbox or intake records; read why it was ignored. Compare the
sender with the filter's rule.
## Fix
Recognise the system's own expected replies by sender, authentication and shape, and correlate each
one to the job that asked for it by an identifier both messages carry (never "the newest waiting
job"). When the identifier finds no single owner, hold and ask the person who can answer.
## Prevent
The timeout notice says "the reply arrived but was not filed: <why>" when it did; an unfiled
expected reply raises one message to whoever can act.
