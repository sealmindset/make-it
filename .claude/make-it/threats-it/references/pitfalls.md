# Pitfalls (each one happened in the first run; most were caught by the independent fact-checks)

Sources
- WebFetch summaries dropped the one exploited Microsoft CVE and moved a date. Raw or two-extraction only.
- A source's own action checklist can omit its own most important item — compare its tables to its checklists.
- Press round numbers ("two dozen") vs the vendor's count (22) — use the vendor's, note the difference.
- "N can be triggered via the Preview Pane" ≠ N code-execution flaws — read each FAQ.
- A CVE titled for one product may be fixed in another (an "ASP.NET Core" DoS fixed in a NuGet package and
  Visual Studio) — use the affected-product list.
- KEV due dates and `forensicTriage` belong in derived data; don't quote them from memory.

Claims
- Scope creep: "no outside app made a privileged change" from a 20-operation, 30-day query. Sweep every
  app-initiated operation in every workspace (30 and 90 days) before claiming.
- "In daily use", "people", "every sign-in type", "all" — only if measured. Use accounts, "regular use", the tables
  actually searched.
- Presence by name ≠ presence. A failed `has` search "proved" a firewall vendor absent; a fixed regex found its appliances.
- A transient table (sign-ins to apps since deleted) is not current presence.
- "Firewall/MDR detection" in Sentinel ≠ detection: rules whose tables are empty cannot fire; joins marked partial may
  never fire; native Defender/MDR detection is a separate, unverified question.
- Purchases: list every possible cost (ESU, ingestion, licences) — "nothing to buy" was wrong twice.
- "Logging is in place" ≠ "logs are watched": check Sentinel onboarding of the workspace that holds them.

Figures
- Overlapping workspaces double-count; distinct counts summed across OS strings double-count users.
- Snapshot drift: re-running some queries later changes live counts (754 → 755). Re-run the whole snapshot and
  re-derive everything after any re-run.
- Hardcoded facts (token roles) must be archived from the source (decoded claims file), not typed.
- Section numbering collisions (Part A "A1" vs finding "A1") confuse reviewers — use S-sections for the org part.

Process
- Don't delete or overwrite earlier deliverables: commit a baseline before restructuring.
- Memory can be stale (a report folder had moved) — verify paths before citing them.
- Never probe the organisation's public endpoints, change settings or contact vendors without explicit approval.
- Tenant data makes the repo confidential: local only, say so in the README.

Second run (Node2Shell, 27 Oct 2026)
- Exploitation status moves daily: three sources said "not exploited" a day before the CISA KEV entry. Pull KEV on the
  day you write, and follow each researcher's own follow-up posts (a news site's "exploited" sequel was linked from
  its first article).
- Web-borne threats need web tables: `hunt.py` does not search gateway, API Management or App Service request logs —
  run `hunt_web.py`. A `search` term matches any column, so pull the full record behind every match before reporting.
- App Insights `AppRequests.ClientIP` is usually masked (0.0.0.0): an address search there is partial; say so.
- Windows App Service runtime versions live in app settings (with secrets) — don't read them; identify the language
  from telemetry `SDKVersion` prefixes (`awm_node`, `flm_node`, `node`) and leave the version under investigation.
- Rule-name regexes over Sentinel rules are noisy (a "c2|outbound" pattern matched cross-tenant-settings rules). Read
  the matched rules, and separately count every rule that reads a table the workspace does not ingest.
- A component in code is not a deployment: map repositories to running apps only by evidence, and say when the
  mapping is by name.
