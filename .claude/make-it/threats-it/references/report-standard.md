# Report standard (the report-pair standard, applied to threat work)

Every run ships a **pair**, written together from the same derived data, plus a generated appendix and PDFs.

## Rules binding both documents
- **One set of figures, same denominators.** Every figure in the briefing is derivable from the companion.
  `check_pair.py` enforces it (numbers, dates, CVEs) and a `data/derived/headline.json` (generated from the
  derived data, not typed) pins the headline values in both.
- **The briefing names the companion file** (`technical.md`) and the appendix.
- **Coverage limits appear in the briefing**, in plain words. "No evidence of X" is not "X did not happen".
- **Prove it or do not report it.** Each claim traces to an archived raw file, a transcribed source with provenance
  in `data/curated/`, or a query result in `data/raw/tenant-*/`. Every gap names the exact access that closes it.
- **Write them together, not in sequence.** Derive figures once (scripts), then write both documents from the
  derived JSON. Never write the briefing from memory of the companion.
- **Names go in a generated appendix** (servers, apps, repositories, accounts, IOCs, rule names). Generate it with a
  script; state what it deliberately omits.
- **Publish the formats the audience opens.** Markdown is the source of truth; PDFs are build products from the
  committed `scripts/build.sh` (pandoc + WeasyPrint), committed alongside. Read the PDFs back to check rendering.
- Scope words are evidence-bound: never "every", "all", "daily", "in use", "people" unless the query measured exactly
  that. Say "accounts" (not people), "about N" for dcount estimates, "N days in <workspace>" for coverage.

## Leadership briefing (`briefing.md`) — short, behaviour-first
It must not read like a newspaper. Order:
1. **Header**: internal/confidential marking, snapshot date, read-only, names `technical.md`, `appendix.md`, OpenVEX file.
2. **Bottom line** (5–6 bullets): IOC verdict for the organisation; what could not be checked; the detection-gap
   headline; "we do need to act — N items now" with sub-bullets; VEX status count.
3. **What the attackers did, and where <Org> stands** — one row per attacker *behaviour* (not product):
   `Attacker behaviour | Seen at <Org>? | Would we be alerted? | Our exposure`. Then one paragraph "Indicators checked"
   and one line on workspace-wide detection coverage.
4. **Status of each item (VEX)** — `Status | Item | <Org> evidence | Action · owner · when`, Affected rows bold, "now"
   rows first. One-sentence VEX definition above the table.
5. **The six questions, briefly** (required by the standard, 1–4 lines each): what is this; what is the problem;
   what if we don't act (specific clean-up cost); benefits beyond; what is involved (effort, sequence, purchases —
   list every possible cost, never "nothing to buy" unless proven); what we are not claiming (coverage limits,
   inference vs evidence, staleness, retention clocks, read-only, no admin role).
Minimum jargon; define any term in place. No product deep-dives — those live in the companion.

## Technical companion (`technical.md`)
**Part A — <Org>** (when tenant evidence was collected):
- S0 Method, identity and access (collector, snapshot, token claims, probe results with error text, workspaces with
  retention and Sentinel onboarding, licences).
- S1 Attack chains, behaviours and <Org> visibility (references/attack-chains.md: diagram + stage table per chain,
  rule-state method, workspace-wide rule counts, "what the chains have in common").
- S2 IOC verdict (table: indicator | query name | scope (tables, window, workspace) | result; then notes on any hits,
  the audit sweep, privileged app writes; verdict paragraph with limits).
- S3 VEX statements (summary table; full statements in appendix and OpenVEX; VEX semantics paragraph).
- S4 Patch state (machines vs MSRC fixed builds; caveats).
- S5 Presence of products the generic analysis treated as out of scope (resources, apps, sign-ins).
- S6 Code inventory (if relevant).
- S7 The threat's pattern inside <Org> (exposure, hardening — not IOC), with actions and owners.
- S8 Other observations. S9 Access gaps and who closes them.
**Part B — Generic** (any Microsoft 365 tenant): B0 method and sources table; B1 triage of the source (sections, CVE
count, product count); B2 corrections and additions to the source (table: brief says | verified position | evidence);
B3 findings summary (grouped, separately counted when fixes differ); B4… findings with What / Where / How and
commands marked "NOT TESTED" unless run; licensing and cost; coverage limits with closers; reproduction; sources.

## Appendix (`appendix.md`) — generated only
CVE table with applicability; IOC tables; MSRC batch tables and fixed builds; KEV context; org sections (full VEX
statements, machines below fix, repositories, directory exposure tables, audit sweep, rule states by chain,
product presence); raw-file SHA-256 manifest; a "deliberately omitted" list.

## Build and checks
`scripts/build.sh`: project derivation scripts → OpenVEX → `check_pair.py` → pandoc/WeasyPrint PDFs into `dist/`.
Tune pipe-table column widths with dash counts in the separator row; continued numbered lists need the
`ol[start]` CSS already in `templates/pdf.css`.
