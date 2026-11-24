"""Map what the signed-in identity can see, before any hunting. Read-only.

  python3 -I tenant_access.py <outdir> [--workspaces name1,name2]

Writes to <outdir>/ (one JSON per call) and <outdir>/access.json:
  - decoded Graph token claims (no token stored): roles (wids), scopes, client app
  - probes: Graph sign-in/audit APIs, Intune, Security API, Entra diagnostic settings (status + error text)
  - licences: SKUs and service plans (Entra P1/P2, Workload ID Premium, Defender Experts, E5)
  - Log Analytics workspaces (Resource Graph), retention, Sentinel onboarding, and per-workspace
    ingestion by data type over the last 30 days (Usage table) -> which hold identity/security tables
Workspaces holding none of the security tables are listed but not queried further by hunt.py.
A query that failed is printed as FAILED and listed in access.json under "failed_queries", and the script exits 3:
licences read NOT ASSESSED (not "false"), Sentinel onboarding reads FAILED (null in the JSON, not "false").
A probe answering 401/403/404 is the probe's finding, not a failure.
"""
import argparse
import datetime as dt
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import GRAPH, ARM, arg, claims, failed, failures, finish, graph_all, http, la, save  # noqa: E402

SECURITY_TABLES = ["SigninLogs", "AADNonInteractiveUserSignInLogs", "AADServicePrincipalSignInLogs", "AADManagedIdentitySignInLogs",
                   "AuditLogs", "MicrosoftGraphActivityLogs", "OfficeActivity", "CommonSecurityLog", "DnsEvents", "ASimDnsActivityLogs",
                   "AZFWNetworkRule", "AZFWApplicationRule", "AZFWDnsQuery", "DeviceNetworkEvents", "DeviceProcessEvents", "DeviceEvents",
                   "DeviceFileEvents", "DeviceImageLoadEvents", "DeviceTvmSoftwareInventory", "DeviceTvmSoftwareVulnerabilities",
                   "SecurityEvent", "Syslog", "W3CIISLog", "AzureDiagnostics", "AWSCloudTrail", "EmailEvents", "CloudAppEvents"]

ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("--workspaces", default="")
a = ap.parse_args()
od = a.outdir
gb = f"{GRAPH}/v1.0"

c = claims()
save(od, "probe_token_claims", "probe", "decoded Graph access-token claims (no signature, no token)", 200, c)
probes = {}
for name, url in {"graph_signins": f"{gb}/auditLogs/signIns?$top=1", "graph_directory_audits": f"{gb}/auditLogs/directoryAudits?$top=1",
                  "graph_intune_devices": f"{gb}/deviceManagement/managedDevices?$top=1&$select=id",
                  "graph_security_alerts": f"{gb}/security/alerts_v2?$top=1"}.items():
    status, res = http("GET", url, GRAPH)
    msg = (res.get("error") or {}).get("message", "")[:300] if isinstance(res, dict) else ""
    save(od, f"probe_{name}", "probe", url, status, {"ok": status == 200, "message": msg})
    probes[name] = {"status": status, "message": msg}
    if status not in (200, 400, 401, 403, 404):  # no answer about access at all (429, 5xx, a timeout)
        failed(f"probe {name}", "Microsoft Graph", status)
status, res = http("GET", f"{ARM}/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01-preview", ARM)
probes["arm_entra_diagnostic_settings"] = {"status": status, "settings": res.get("value") if status == 200 else None}
save(od, "probe_arm_entra_diagnostic_settings", "probe", "aadiam diagnosticSettings", status, res)
if status not in (200, 400, 401, 403, 404):
    failed("probe arm_entra_diagnostic_settings", "Azure Resource Manager", status)

status, skus = graph_all(f"{gb}/subscribedSkus?$select=skuPartNumber,consumedUnits,prepaidUnits,servicePlans")
save(od, "graph_skus", "graph", "subscribedSkus", status, skus)
licences_read = status == 200
if not licences_read:
    failed("licences (subscribedSkus)", "Microsoft Graph", status)
    skus = []
plans = {p["servicePlanName"] for s in skus for p in s.get("servicePlans", [])}
status, org = graph_all(f"{gb}/organization?$select=id,displayName")
save(od, "graph_org", "graph", "organization", status, org)
if status != 200:  # without the tenant id, hunt.py and exposure.py cannot tell own apps from outside ones
    failed("tenant (organization)", "Microsoft Graph", status)
    org = []

status, ws = arg("""resources | where type =~ 'microsoft.operationalinsights/workspaces'
| project id, name, resourceGroup, subscriptionId, customerId=tostring(properties.customerId), retentionInDays=toint(properties.retentionInDays)""")
save(od, "arg_workspaces", "resource_graph", "workspaces", status, ws)
if status != 200:
    failed("workspace list", "Resource Graph", status)
    ws = []
status, sent = arg("""resources | where type =~ 'microsoft.operationsmanagement/solutions' and name startswith 'SecurityInsights'
| project workspaceId=tolower(tostring(properties.workspaceResourceId))""")
sentinel_read = status == 200
if not sentinel_read:
    failed("Sentinel onboarding", "Resource Graph", status)
    sent = []
sentinel_ids = {r["workspaceId"] for r in sent}
wanted = set(filter(None, a.workspaces.split(",")))
since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)).strftime("%Y-%m-%d")
summary = []
for w in ws:
    if wanted and w["name"] not in wanted:
        continue
    st, usage = la(w["customerId"], f"Usage | where TimeGenerated > datetime({since}) | summarize MB = sum(Quantity) by DataType")
    if st != 200:
        failed("tables (Usage)", w["name"], st)
    tables = {r["DataType"]: round(r["MB"], 1) for r in usage} if st == 200 else {}
    sec = {t: tables[t] for t in SECURITY_TABLES if tables.get(t)}
    summary.append({"name": w["name"], "customerId": w["customerId"], "resourceId": w["id"], "retentionInDays": w["retentionInDays"],
                    "sentinel": w["id"].lower() in sentinel_ids if sentinel_read else None, "readable": st == 200, "security_tables_mb_30d": sec})
summary.sort(key=lambda x: -len(x["security_tables_mb_30d"]))
save(od, "workspace_coverage", "log_analytics", f"Usage since {since} per workspace", 200, summary)

access = {
    "identity": {"upn": c.get("upn"), "client": c.get("app_displayname"), "roles_wids": c.get("wids"), "scopes": c.get("scp")},
    "tenant": org[0] if org else None,
    "probes": probes,
    "licences": {"entra_p2": "AAD_PREMIUM_P2" in plans, "entra_p1": "AAD_PREMIUM" in plans or "AAD_PREMIUM_P2" in plans,
                 "workload_id_premium": any("WRKLD" in p.upper() for p in plans),
                 "defender_experts_sku": any("Defender_Experts" in (s.get("skuPartNumber") or "") for s in skus)}
    if licences_read else "NOT ASSESSED (subscribedSkus not read)",
    "workspaces_with_security_tables": [w for w in summary if w["security_tables_mb_30d"]],
    "workspaces_unreadable": [w["name"] for w in summary if not w["readable"]],
    "failed_queries": failures(),
}
json.dump(access, open(os.path.join(od, "access.json"), "w"), indent=1)
print(json.dumps({k: access[k] for k in ("identity", "probes", "licences")}, indent=1)[:3000])
for w in access["workspaces_with_security_tables"]:
    print(f"  {w['name']:36s} retention={w['retentionInDays'] or '?':>3} sentinel={'FAILED' if w['sentinel'] is None else w['sentinel']!s:6} tables={sorted(w['security_tables_mb_30d'])}")
if access["workspaces_unreadable"]:
    print("workspaces that could not be read (not assessed):", access["workspaces_unreadable"])
finish()
