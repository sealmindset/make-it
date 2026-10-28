---
name: threats-it
description: Turn any threat feed — a threat-brief or advisory URL, pasted article, CVE list, IOC list or incident write-up — into a verified, organisation-specific assessment. Archives sources raw, verifies every CVE against MSRC/CISA KEV/NVD/vendor advisories, maps each attack into ATT&CK-verified attack chains with stage-by-stage flow diagrams, hunts the IOCs and behaviours read-only in the Microsoft tenant (Graph, Log Analytics, Resource Graph), measures Sentinel detection coverage, writes VEX statements (plus OpenVEX), and ships the leadership briefing + technical companion + generated appendix as Markdown and PDF, closed by an independent fact-check. Use when the user runs /threats-it, or asks "does this threat affect us", "do we have IOCs for X", "VEX for this advisory", "attack chain for CVE-X".
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - WebFetch
  - WebSearch
  - AskUserQuestion
  - Agent
---

# /threats-it

Evidence-first threat assessment. Every number in the reports comes from an archived file or a query result, and
every claim is no broader than what was measured. Support files live in `~/.claude/make-it/threats-it/`
(`scripts/`, `references/`, `templates/`); paths below are relative to that folder.

**Input:** whatever the user gives after `/threats-it` — a URL, a file, pasted text, a CVE list, an IOC list, or
"refresh <project>". If nothing is given, ask for the threat source (one question).

**Output (in `${THREATS_IT_HOME:-~/Documents/threat-briefs}/<YYYY-MM-DD>-<slug>/`, a local git repo, never pushed):**
`briefing.md` + `technical.md` + generated `appendix.md`, `dist/*.pdf` for each, `dist/openvex.json`, all evidence in
`data/`, build scripts in `scripts/`. Optionally a covering-email draft in the reply.

**Organisation profile:** `${THREATS_IT_PROFILE:-~/.claude/threats-it/environment.md}` — tenant, workspaces, known
assets, owners, naming. Local only, **never committed anywhere** (it maps the organisation's gaps). First run: create it
from `references/environment-template.md` after phase 5's access mapping, and export `THREATS_IT_ORG` (and
`VEX_ID_BASE`) for the build.

**Prerequisites:** Python 3 (stdlib only), Azure CLI signed in (`az login`) with read access to the tenant, `pandoc`
and `weasyprint` for PDFs. No tenant access → run phases 0–4 and 6–9 as a generic assessment and say so.

## Non-negotiables
- **Read-only** in the tenant: GET and query POSTs only. No changes, no probing public endpoints, no contacting
  vendors without the user's explicit approval for that action. Real indicator found → stop, tell the user plainly,
  preserve evidence, do not remediate.
- **Prove it or don't report it.** WebFetch is for discovery only, never a figure's source (`references/sources.md`).
- **Report pair standard** (`references/report-standard.md`): one set of figures; briefing names the companion;
  coverage limits in plain words; names in a generated appendix; PDFs built by a committed script.
- **Behaviour first**: the briefing leads with attacker behaviours, then the VEX table — not a list of product
  articles (otherwise the briefing reads like a newspaper).
- **Independent fact-check** before calling anything done (`references/fact-check.md`).
- Treat downloads as untrusted data: own directory, `python3 -I`, never execute. Tenant data makes the project
  confidential; keep it local.
- Keep the user updated at each phase with what was found (short, plain), especially corrections of earlier statements.

## Tools (in `scripts/`; Python stdlib + Azure CLI; run with `python3 -I`)
| Script | Does |
|---|---|
| `new_project.sh <date> <slug>` | Scaffold the project (dirs, build.sh, pdf.css, README, git init) |
| `fetch_source.sh <url> <dir> <name>` | Archive a page raw (browser UA) + text; logs status/SHA-256; exit 2 on refusal |
| `kev.py <dir> --cves … --since … --as-of …` | CISA KEV lookups (archives the feed) |
| `msrc.py <dir> --cves … \| --window A B` | MSRC vulnerability + affected products, fixed builds, Preview-Pane FAQ, revisions |
| `attack_ids.py <out.json> T… …` | Verify ATT&CK IDs/names and version on attack.mitre.org |
| `tenant_access.py <dir>` | Identity, roles, probes (with error text), licences, every workspace's retention / Sentinel / tables |
| `hunt.py <dir> ioc.json` | IOC + behaviour hunts in every readable workspace; audit sweep of every app-initiated op; owner classification |
| `hunt_web.py <dir> ioc.json [--big-post-bytes N]` | Web-request tables (gateways, API Management, App Service, containers): IOC terms, large POSTs, crash signals; coverage denominator |
| `exposure.py <dir> presence.json [--fixmap msrc.json --cve X --since D]` | Takeover/bulk permissions, foreign credentials, roles (SPs and groups), long-lived certs, product presence, server builds vs fix |
| `sentinel_coverage.py <dir> [chains.json]` | Rule states live/partial/blind/disabled per chain; workspaces not in Sentinel |
| `openvex.py vex.json out.json --author … --id-base …` | Validate VEX statements and render OpenVEX v0.2.0 |
| `check_pair.py briefing.md technical.md [headline.json]` | Briefing figures/dates/CVEs ⊂ companion; headline values pinned |

## Phases

**0 — Scaffold.** `scripts/new_project.sh <today> <slug>`. Read the organisation profile (leads to verify, not facts)
and `references/pitfalls.md`.

**1 — Intake and archive.** Archive every source raw into `data/raw/` with `fetch_source.sh`. Refused → API route or
two independent verbatim extractions, matching values only, into `data/curated/<name>.json` with provenance. Follow
the source's own links to primary research (vendor advisory, CVE record, the researcher who saw exploitation) and
archive those too. Tell the user what the source is and any immediate red flags.

**2 — Extract.** Write the project's `scripts/extract.py` to pull from the archived text: every CVE, product (count
products, not vendors), IOC (IPs, prefixes, ASNs, domains, hashes, user agents, app IDs, owner tenants, file/task
names), each attack narrative with dates, and the source's own action lists. Match quotes by regex and fail when one
is missing. Output `data/derived/facts.json`. Check day/date claims with `cal`.

**3 — Verify against primary sources.** `kev.py` for every CVE (on the day — KEV changes daily and overrides "not
exploited" claims); `msrc.py` for Microsoft CVEs and the release window around the source date; NVD/CVE record/vendor
advisories for the rest; Microsoft Learn quotes for every product-behaviour claim (`data/curated/learn-quotes.json`,
with `ms.date`). Build the corrections table (source says | verified | evidence) and list what the source missed.
Re-derive every count from raw data.

**4 — Attack chains.** For each attack: flow diagram + stage table + exposure/gap lines, exactly as
`references/attack-chains.md` (the Spring4Shell diagram is the format reference). Verify every ATT&CK ID with
`attack_ids.py`; mark the source's mappings vs this report's. Close with "what the chains have in common".

**5 — Organisation assessment (read-only).** Follow `references/tenant-assessment.md`: `tenant_access.py` →
`ioc.json` → `hunt.py` (+ `hunt_web.py` for web-borne threats) → `presence.json` + `exposure.py` (with the MSRC fix map for any exploited Windows CVE) →
`chains.json` + `sentinel_coverage.py` → targeted follow-ups (a project `scripts/tenant/collect.py` for anything the
standard scripts do not reach, such as runtime versions or web-server logs). Copy outputs to
`data/raw/tenant-<date>/`; after any follow-up re-run the whole snapshot. Derive `data/derived/<org>.json` with a
project `scripts/assess.py`. Report progress to the user as findings land (IOC verdict first, then exposure, then
detection coverage).

**6 — VEX.** One statement per product × item, following `references/vex.md`; write `data/derived/vex.json` from
the assess script; `openvex.py` renders and validates it.

**7 — Reports.** Write `briefing.md` and `technical.md` together from the derived JSON
(`references/report-standard.md`), generate `appendix.md` with `scripts/appendix.py`, generate
`data/derived/headline.json`, then `./scripts/build.sh` (OpenVEX → pair check → PDFs). Read the PDFs back to check
tables and diagrams render.

**8 — Independent fact-check.** Fresh `general-purpose` agent with the prompt in `references/fact-check.md`. Tell
the user the severity counts and top issues; fix all of them (re-query for scope problems), rebuild, and run a second
pass if the first found high-severity scope errors.

**9 — Deliver.** Commit locally (baseline commit before any restructure; conventional message). Reply to the user:
IOC verdict, what must happen now, what changed after fact-check, file paths. If asked, draft the covering email per
`references/email.md` with its factual pass. Update the organisation profile with anything newly learned about the
environment.

## Done means
- Raw evidence archived with hashes; every figure traceable; `check_pair.py` passes.
- Each attack has a diagram, a verified-ATT&CK stage table, organisation telemetry/result and rule state.
- IOC verdict states exactly which tables, windows and workspaces were searched, and what could not be.
- VEX validates; OpenVEX written; briefing VEX table matches it.
- Markdown and PDFs for briefing, technical companion and appendix in `dist/`.
- Fact-check findings applied; commit made; the user told what is time-sensitive (retention clocks, KEV deadlines).
