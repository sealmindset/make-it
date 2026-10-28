# Organisation profile — template

`/threats-it` reads the organisation profile from `~/.claude/threats-it/environment.md` (override with
`THREATS_IT_PROFILE`). **That file lives only on the analyst's machine. Never commit it**: it holds tenant identifiers,
workspace IDs and known gaps, which are exactly what an attacker wants. Copy this template there on first run and fill
it in from `tenant_access.py` output; update it at the end of every run (phase 9).

Everything in the profile is a lead to verify, not a fact to quote. Reports cite the current run's evidence only.

```markdown
# <Org> environment notes (as of <YYYY-MM-DD> — verify every run; these are leads, not facts)

Organisation name (reports, VEX author): <Org>            # also export THREATS_IT_ORG="<Org>"
VEX id base: https://<org-domain>/vex/                     # also export VEX_ID_BASE
Confidentiality label: Internal — <Org> confidential
Projects folder: ~/Documents/threat-briefs                 # THREATS_IT_HOME

Identity used: <upn> via Azure CLI. Entra roles (token wids): <…>. Probe results: Graph /auditLogs/* <status>;
Intune <status>; Security API <status>; Entra diagnostic settings <status>.

Tenant `<tenant-id>`. Licences relevant to detection: <Entra P1/P2, Defender, Workload Identities Premium…>.

Log Analytics:
| Workspace | customerId | Retention | Sentinel | Identity / security / web tables |
|---|---|---|---|---|
| <name> | <guid> | <n> d | Yes/No | <tables> |
Missing telemetry: <firewall / DNS / endpoint / web-server tables not in any readable workspace>.

Known in the environment (from <date> evidence): <appliances, remote-support tools, MDR apps, high-privilege
third-party apps, internet-facing apps, server counts, runtime counts>.

Code inventory: <dependency export path and date, or SBOM source> — check its date; a rescan beats a stale export.

Owners named in reports by role, not by person: <server team, endpoint team, network team, SOC, app owners…>.

Email style (optional, for covering-email drafts): <length, bullets or not, sign-off>.

Reference implementation of a full run: <path to a previous threats-it project, for shape and depth>.
```
