---
name: audit-trail-cascades-with-its-subject
signals: [an id in the logs has no row in the database, the audit rows for a deleted record are gone, "proof" exists only in an application log line]
seen: 2026-11-06 (1 incident)
---
## Shape
Audit rows reference the record they describe with a cascading delete (or none is written on delete).
Deleting the record erases its own history, so the evidence that would prove what a person did is gone.
## How to confirm
Grep log ids against the table; check the audit table's foreign key and whether delete writes a row.
## Fix
Audit rows survive their subject (no cascading key, or soft delete); delete writes its own audit row.
## Prevent
A test that deleting the subject leaves its audit trail and adds a "deleted" row.
