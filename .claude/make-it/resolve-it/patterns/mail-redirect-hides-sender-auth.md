---
name: mail-redirect-hides-sender-auth
signals: [genuine system email treated as unverified or unknown sender, "Resent-From" header, inbox-rules-loop header, two Authentication-Results headers, top one dmarc=none]
seen: 2026-11-11 (1 incident)
---
## Shape
A mailbox rule redirects a system's email (a portal's "your download is ready") to a scanned
mailbox. The mail server re-stamps the redirected copy with a new, inconclusive authentication
result on top, above its own stamp from the original arrival. Code that reads only the top stamp sees
"not verified" and drops or distrusts a genuine email.
## How to confirm
Read the message's raw headers through the mail API: two Authentication-Results, the top one
inconclusive (dmarc=none, no signing domain), the next one a pass; a redirect marker (Resent-From,
an inbox-rule loop header) and the provider's own "internal" directionality header.
## Fix
Read the original arrival stamp one level down only when the provider itself marks the message as an
internal redirect with a header outside mail cannot set, the top stamp is inconclusive (a fail on top
is final), and both stamps come from the same receiving service. Never deeper than one level.
## Prevent
A test built from the real header sequence; an alert or "ask the sender" when a system email that a
job is waiting for arrives unverified.
