# Organisation assessment (read-only)

Everything here is GET or a POST to a query endpoint, run as the signed-in Azure CLI identity. **Never change
anything** (no disabling apps, no rule edits, no probing public sites) without the user's explicit go-ahead for that
specific action. If a real indicator turns up (attacker IP/ASN sign-in, outside app granting roles or adding
credentials, IOC on a device), stop, tell the user immediately in plain language (security-warning style), preserve the
evidence (export the rows), and do not remediate.

## Order of work
1. `tenant_access.py <outdir>` — identity (token claims, roles), probes (Graph sign-in/audit APIs, Intune, Security
   API, Entra diagnostic settings — record status **and error text**: "Missing application scopes" is a client
   limitation of the Azure CLI app, not a role denial), licences, every Log Analytics workspace with retention,
   Sentinel onboarding and 30-day ingestion by table. ~4 minutes for ~100 workspaces.
2. Write `ioc.json` from the extracted IOCs (IPs, /24-style prefixes, unconfirmed IPs kept separate, ASNs, user-agent
   prefixes, app IDs, owner tenants, domains, hashes, file and task names, `window_start` = a few days before the
   earliest attack date).
3. `hunt.py <outdir> ioc.json` — per workspace, only queries whose tables exist, each over full retention. Includes
   the **audit sweep of every app-initiated operation** (not a hand-picked list) and app-only privileged Graph writes,
   classified by the owner tenant of the initiating app.
4. `exposure.py <outdir> presence.json --fixmap <msrc.json> --cve <CVE> --since <date>` — takeover / bulk Graph
   permissions (outside and own apps), credentials on outside service principals, roles held by service principals
   and by groups, long-lived certificates, recent credentials, product presence (Resource Graph regex + enterprise-app
   names + their sign-ins), Windows server builds vs the MSRC fixed build.
5. `sentinel_coverage.py <outdir> chains.json` — rule states (live/partial/blind/disabled) per chain; which security
   workspaces are not onboarded.
6. Targeted follow-ups as the evidence demands (e.g. which groups an outside app changes and what roles those groups
   hold; who registered a new app; sign-ins of an app named in the threat). Add each follow-up to the project's own
   collector script so the snapshot stays reproducible, then **re-run the whole snapshot** so every figure comes
   from one run.

Move the outputs into the project as `data/raw/tenant-<date>/`; derive figures with a project `assess.py` into
`data/derived/<org>.json` (the reference implementation shows the shape).

## Interpreting results
- **Owner classes**: own tenant / Microsoft (f8cdef31…, 72f988bf… — an assumption; extend when Microsoft apps show
  up under other owners) / third-party / unknown (no owner — managed identities etc.) / unresolved (initiator has a
  name but no service principal in the tenant — usually Microsoft back-end services; classify "by name only").
- An outside app changing **group membership** can still be granting roles: check the roles those groups hold.
- **Overlapping workspaces** (e.g. a 30-day and a 90-day copy of SigninLogs) — report per workspace, never add.
- `dcount` is an estimate: write "about N". Count **accounts**, not people; filter to successful sign-ins when the
  claim is about use; OS from sign-in logs is the client's own report.
- Presence evidence ladder: Azure resource > service-principal sign-ins > interactive sign-ins to an app still in the
  directory > app registration only > name hint. Apps can be deleted after use — check `in_directory`.
- Retention clocks: compute when the attack window falls out of each workspace and put the date in both documents.
  IOCs older than the oldest log cannot be checked from logs at all — say so.
- "Not checked" is not clean. Name the missing telemetry and the owner who has it.
- Server builds: Server 2025 and Windows 11 24H2 share 10.0.26100 with different fixed revisions — match by product
  line. 2012 R2 / Win10 22H2 fixes may be ESU-only (MSRC files them under the ESU family). ESU enrolment is a
  separate question.

## KQL pitfalls (each one caused a wrong statement in the first run)
- `has` / `has_any` match **whole terms**: `pub has 'paloalto'` misses `paloaltonetworks`, `type has 'mariadb'` misses
  `microsoft.dbformariadb/servers`. Use `contains` or `matches regex` for IDs and resource types.
- `between (datetime(A) .. datetime(B))` with a date-only B stops at B 00:00 — use B = the day after.
- OfficeActivity client IPs can carry ports or brackets — extract the IPv4 before matching.
- Graph activity logs and OfficeActivity have no ASN field — ASN hunts only cover sign-in tables; say so.
- Usage `Quantity` is MB; rounding to GB with 3 decimals makes small tables look empty.
- AuditLogs `InitiatedBy.app.appId` is often empty — join on `servicePrincipalId`, fall back to display name.

## Access gaps seen in practice (verify each run)
| Gap | Typical closer |
|---|---|
| Graph `/auditLogs/*` 403 (no Entra role) | Not needed when Log Analytics copies exist; Global Reader for cross-checks |
| Intune 401 | Endpoint team or Intune read access |
| Defender / Security API 403 (Azure CLI client lacks scopes) | SOC, portal or Defender-consented tooling |
| No firewall / DNS / endpoint tables in reachable workspaces | Network team / SOC |
| Appliance versions (PAN-OS, BeyondTrust…) | Network / application owners |
