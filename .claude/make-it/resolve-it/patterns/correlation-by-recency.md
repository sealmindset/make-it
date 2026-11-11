---
name: correlation-by-recency
signals: [two records swapped between owners, "newest pending" or "latest waiting" lookup, several waiting items share a host or type, replies arrive out of order]
seen: 2026-11-11 (caught in review)
---
## Shape
An incoming reply is matched to "the newest waiting request" of its kind instead of the request it
answers. With two requests waiting, normal arrival order hands each reply to the wrong owner.
## How to confirm
Find the lookup's ordering; replay two overlapping requests.
## Fix
Match by an identifier both sides carry; when it finds none or several owners, hold and ask.
## Prevent
A test with two requests waiting and replies in both orders.
