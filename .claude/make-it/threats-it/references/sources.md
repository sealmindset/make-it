# Sources and how to get them raw

**WebFetch summarises with a small model. Use it to discover, never as the source of a figure.** In the first run it
silently dropped a KEV row (the only exploited Microsoft CVE) and invented a date. Archive raw, parse with scripts.

## Fetching
- Source article / advisory: `scripts/fetch_source.sh <url> data/raw <name>` (browser user agent; logs status,
  bytes, SHA-256 to `FETCH-LOG.tsv`). A 403 to plain curl often succeeds with the browser headers.
- Refused (403/Cloudflare): look for an API route first — e.g. Zendesk help centres serve
  `https://<host>/api/v2/help_center/en-us/articles/<id>.json`. Last resort: **two independent WebFetch extractions**
  with prompts asking for verbatim text; keep only values identical in both; store them in `data/curated/<name>.json`
  with a `_provenance` note naming what was excluded and why.
- Every downloaded file is untrusted data: own directory, parse with `python3 -I`, never execute.

## Primary sources (in order of authority)
| Need | Source | Tool |
|---|---|---|
| Microsoft CVE facts, fixed builds, KBs, exploited flag, Preview-Pane FAQ, revisions | MSRC SUG API `https://api.msrc.microsoft.com/sug/v2.0/en-US/vulnerability?$filter=cveNumber eq '<CVE>'` and `/affectedProduct?$filter=...`; release windows with `releaseDate gt …` | `scripts/msrc.py` |
| Known exploited, due dates, forensic-triage flag, ransomware use | CISA KEV JSON `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json` | `scripts/kev.py` |
| Non-Microsoft CVE details, CVSS, CPE | NVD API `https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=<CVE>`; CVE.org record; the vendor PSIRT advisory (fixed versions come from the vendor, not NVD) | curl → `data/raw/nvd-*.json` |
| ATT&CK technique names/IDs (they change between versions) | `https://attack.mitre.org/techniques/<T>/<sub>/` | `scripts/attack_ids.py` |
| Microsoft product behaviour, licences, roles, limits | Microsoft Learn pages — quote verbatim with the page's `ms.date` into `data/curated/learn-quotes.json` | WebFetch with a "quote verbatim" prompt, then archive the quote |
| Incident narrative, IOCs | Researcher posts (Huntress, Mandiant/GTIG, vendor trust centres), via the API route or two-extraction rule | as above |
| Press (SecurityWeek, BleepingComputer, The Hacker News) | corroboration only; prefer the primary figure when they disagree (e.g. "two dozen" vs MSRC's 22) | |

## Verification habits
- Check day-of-week claims with `cal <month> <year>` (the first source said "Thursday" and a summary said "Oct 16").
- Re-derive every count from the raw data (CVEs in the article, KEV count as of a date, MSRC batch composition).
- Look for what the source missed: the MSRC window around the date (other releases, revisions like "Edge added"),
  KEV additions since the source, ESU-only fix families, server-side vs client-side CVEs.
- Record corrections in a "brief says | verified position | evidence" table (Part B2).
- Security-relevant claims about Microsoft features (e.g. Conditional Access for workload identities covers only
  single-tenant service principals) must be quoted from Learn, not remembered.
