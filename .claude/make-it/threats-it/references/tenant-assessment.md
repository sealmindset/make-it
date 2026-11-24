# Organisation assessment (read-only)

Everything here is GET or a POST to a query endpoint, run as the signed-in Azure CLI identity. **Never change
anything** (no disabling apps, no rule edits, no probing public sites) without the user's explicit go-ahead for that
specific action. If a real indicator turns up (attacker IP/ASN sign-in, outside app granting roles or adding
credentials, IOC on a device), stop, tell the user immediately in plain language (security-warning style), preserve the
evidence (export the rows), and do not remediate.

## Order of work
1. `tenant_access.py <outdir>` — identity (token claims, roles), probes (Graph sign-in/audit APIs, Intune, Security
   API, Entra diagnostic settings — record status **and the reason code** (the scripts never keep the error text
   itself, which can repeat a token): the reason "missing scopes" is a client limitation of the Azure CLI app, not a
   role denial), licences, every Log Analytics workspace with retention,
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
6. `findings_sources.py <outdir> [--since <date>]` (for the finding-chains step) — Secure Score, Defender for
   Cloud assessments, Defender XDR alerts and incidents, AuditGitHub findings. Read-only GETs and one Resource
   Graph query. Record each source's status: a 403 here is usually a missing Security Reader role or, for the
   Graph security endpoints, the Azure CLI app's missing scopes.
7. Targeted follow-ups as the evidence demands (e.g. which groups an outside app changes and what roles those groups
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
- **A failed query is not checked.** Each script names every query that did not answer and lists it in its JSON
  as `failed_queries`; the fields built on it read `NOT ASSESSED` (`exposure.json`, `hunt-summary.json`,
  `sentinel-coverage.json`, `access.json` licences and workspaces), `null` (Sentinel onboarding in
  `workspace_coverage.json`) or carry a non-200 `status`. Two cases (the skill's "A failed query is not a result"):
  - **exit 4, go on:** a workspace that answers 401 or 403 is one the reader has no access to. It is printed as
    `NOT ASSESSED (no access): workspace <name>`, by `tenant_access.py` and again by every later script, and the run
    continues. Write it as "not assessed (no access)" in both documents, with the role that would open it (Log
    Analytics Reader on the workspace). It was not searched: never "none", never part of "N workspaces searched".
  - **exit 3, stop and ask:** no workspace readable, the workspace list failed, a 429, a 5xx, a timeout, a cut-off
    or partial answer, a refused Graph call (Global Reader or Directory Readers), an expired sign-in. A 429 or a
    timeout is usually worth one more run later. If the run goes on, write that part as "not assessed" with the
    query, the place and the status: an app list that was not read is not "no outside apps", a licence query that
    failed is not "no licence".
- **The organisation's own security testing is not an attacker.** AuditGitHub and the scanners it runs, and any
  other tool the profile lists under "Own security tooling", exist to find weaknesses: their test scripts, probes
  and scan traffic look like an attack and are not one. Never report them as attacker behaviour, as an indicator,
  or as a finding about the organisation. Exclude an event only when it matches an identifier the profile records
  for that tool (its app or service-principal id, its source addresses, its repository): a name alone proves
  nothing, since an attacker can use the same name. Anything that claims to be the tool but matches no recorded
  identifier is hunted like everything else. Excluded activity is counted, never dropped silently: both documents
  say "N events from <tool>, our own testing, were left out", under what we are not claiming.
- The tool's **findings** are still input (to the chaining step and to exposure), but each is a lead: these tools
  give false positives by design, so a finding is used only after this run's own evidence confirms it.
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
