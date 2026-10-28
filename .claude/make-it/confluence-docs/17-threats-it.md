# /threats-it — Does this new threat affect us? Answered with proof

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/threats-it` takes a threat warning — a security advisory, a news article, a list of flaws (CVEs) or a list of
attacker fingerprints (indicators) — and finds out what it means for **your** organisation. It reads the sources,
checks every claim against the official records, looks for the attacker's fingerprints in your Microsoft cloud
logs without changing anything, and writes two reports: one for leaders, one for engineers.

> **In one sentence:** Paste the link; get back "has this happened here, would we notice, how exposed are we" —
> with every number traceable to saved evidence.

> ℹ️ **This is a security-team skill.** It needs read access to your Microsoft tenant through the Azure CLI. Without
> that access it still produces a verified general assessment, and says what it could not check.

---

## What is it used for?

- **A new threat lands** and someone asks "does this affect us?" — before anyone has had time to read ten articles.
- **Checking for indicators**: the attacker addresses, user agents, file hashes or apps named in the research are
  searched across every log workspace you can read, and the report says exactly which logs and how many days.
- **Correcting the news**: sources go stale fast ("not exploited" on Monday, on the government's exploited list on
  Tuesday). The skill checks each claim on the day and keeps a corrections table.
- **Explaining how the attack works**: each attack becomes a step-by-step diagram, with the point where your
  controls would break it.
- **Saying what is and isn't affected** (VEX): one line per product — affected, not affected, fixed, or still being
  checked — with the evidence and the owner.
- **Seeing whether you would be alerted**: your Sentinel detection rules are checked against the logs they need;
  rules that read empty tables are reported as blind.

---

## How do I use it?

```
/threats-it https://example.com/advisory-about-a-new-flaw
/threats-it CVE-2026-12345 CVE-2026-12346
/threats-it refresh 2026-10-27-node2shell
```

It keeps you updated as findings land, stops and tells you at once if it finds a real indicator, and finishes with
the file paths and anything time-sensitive (fix deadlines, log retention running out).

---

## What do I get?

| File | For |
|---|---|
| `briefing.md` / `.pdf` | Leaders: the verdict, what attackers do and where you stand, the status table, six plain questions |
| `technical.md` / `.pdf` | Engineers: method, attack chains, every query and result, exposure, detection coverage, gaps |
| `appendix.md` / `.pdf` | Generated lists of names and identifiers behind every count |
| `dist/openvex.json` | Machine-readable status for tooling |

All evidence stays in the project folder (`data/`), which is a local git repository and is never pushed.

---

## What it will not do

- Change anything in your tenant, contact vendors, or probe your public sites.
- Quote a figure it cannot trace to a saved source or a query result.
- Treat "no evidence found" as "it did not happen" — the reports say which logs were searched and for how long.

---

## Before the first run

- Sign in with `az login` (read access to the tenant and its Log Analytics workspaces).
- Install `pandoc` and `weasyprint` for the PDFs.
- On the first run the skill creates your organisation profile at `~/.claude/threats-it/environment.md` from the
  template. It stays on your machine only, because it maps your logs and gaps.
