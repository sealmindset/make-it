"""Which Sentinel analytics rules can actually fire? Read-only.

  python3 -I sentinel_coverage.py <outdir> [chains.json]

Uses <outdir>/access.json (tenant_access.py) to find Sentinel-onboarded workspaces, then for each:
  - lists analytics rules (ARM GET alertRules)
  - reads ingestion per data type for the last 30 days (Usage table, in MB)
  - classifies each rule by matching table names in its query against what the workspace ingests:
      live      enabled, every recognised source table has data
      partial   some source tables empty (a rule that joins them may in practice never fire)
      blind     every recognised source table empty
      disabled
      tables not recognised   (parser/function-based rules; check by hand)
chains.json (optional) maps a chain label to a regex over rule display names, e.g.
  {"C1 vendor app key abuse": "^service principal (authentication|assigned)|credential added"}
Writes sentinel-coverage.json and one raw file per workspace.
"""
import collections
import datetime as dt
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ARM, http, la, save  # noqa: E402

TABLES = ["SigninLogs", "AADNonInteractiveUserSignInLogs", "AADServicePrincipalSignInLogs", "AADManagedIdentitySignInLogs", "AuditLogs",
          "MicrosoftGraphActivityLogs", "OfficeActivity", "DeviceProcessEvents", "DeviceEvents", "DeviceNetworkEvents", "DeviceFileEvents",
          "DeviceImageLoadEvents", "DeviceRegistryEvents", "DeviceLogonEvents", "SecurityEvent", "Event", "Syslog", "CommonSecurityLog",
          "AzureActivity", "AzureDiagnostics", "SecurityAlert", "BehaviorAnalytics", "IdentityInfo", "ADFSSignInLogs", "EmailEvents",
          "EmailUrlInfo", "EmailAttachmentInfo", "CloudAppEvents", "IdentityLogonEvents", "IdentityDirectoryEvents", "W3CIISLog",
          "ThreatIntelligenceIndicator", "ThreatIntelIndicators", "DnsEvents", "AADRiskyUsers", "AADUserRiskEvents", "AWSCloudTrail",
          "AZFWNetworkRule", "AZFWApplicationRule", "AZFWDnsQuery", "ASimDnsActivityLogs", "ASimAuthenticationEventLogs"]
od = sys.argv[1]
chains = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else {}
access = json.load(open(os.path.join(od, "access.json")))
cov = json.load(open(os.path.join(od, "workspace_coverage.json")))["result"]
since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)).strftime("%Y-%m-%d")
out = {"since": since, "workspaces": {}}
for w in [x for x in cov if x["sentinel"]]:
    url = f"{ARM}{w['resourceId']}/providers/Microsoft.SecurityInsights/alertRules?api-version=2024-03-01"
    rules = []
    while url:
        st, res = http("GET", url, ARM)
        if st != 200:
            break
        rules += [{"name": r["name"], "kind": r.get("kind"), "displayName": r["properties"].get("displayName"), "enabled": r["properties"].get("enabled"),
                   "query": r["properties"].get("query"), "tactics": r["properties"].get("tactics"), "techniques": r["properties"].get("techniques")}
                  for r in res.get("value", [])]
        url = res.get("nextLink")
    save(od, f"sentinel_rules_{w['name']}", "arm", w["resourceId"], st, rules if st == 200 else res)
    st2, usage = la(w["customerId"], f"Usage | where TimeGenerated > datetime({since}) | summarize MB = sum(Quantity) by DataType")
    save(od, f"sentinel_usage_{w['name']}", "log_analytics", "Usage MB by DataType", st2, usage)
    ingest = {r["DataType"]: float(r["MB"]) for r in usage} if st2 == 200 else {}
    rows = []
    for r in rules:
        t = [x for x in TABLES if re.search(r"(?<![\w])" + re.escape(x) + r"(?![\w])", r.get("query") or "")]
        live = [x for x in t if ingest.get(x, 0) > 0]
        state = ("disabled" if not r["enabled"] else "tables not recognised" if not t else "blind" if not live
                 else "partial" if len(live) < len(t) else "live")
        rows.append({"rule": r["displayName"], "kind": r["kind"], "enabled": r["enabled"], "state": state, "tables": t, "live_tables": live})
    sched = [x for x in rows if x["enabled"] and x["kind"] == "Scheduled"]
    out["workspaces"][w["name"]] = {
        "rules_total": len(rows), "enabled_scheduled": len(sched), "disabled": sum(1 for x in rows if not x["enabled"]),
        "enabled_by_state": dict(collections.Counter(x["state"] for x in sched)),
        "ingested": sorted(k for k, v in ingest.items() if v > 0),
        "chains": {c: sorted([x for x in rows if re.search(p, x["rule"] or "", re.I)], key=lambda x: (x["state"], x["rule"])) for c, p in chains.items()},
        "blind_rules": sorted(x["rule"] for x in sched if x["state"] == "blind"),
    }
    s = out["workspaces"][w["name"]]
    print(w["name"], "| rules", s["rules_total"], "| enabled scheduled", s["enabled_scheduled"], "|", s["enabled_by_state"])
    for c, rr in s["chains"].items():
        print("  ", c, dict(collections.Counter(x["state"] for x in rr)))
not_onboarded = [x["name"] for x in access["workspaces_with_security_tables"] if not x["sentinel"]]
out["security_workspaces_not_in_sentinel"] = not_onboarded
json.dump(out, open(os.path.join(od, "sentinel-coverage.json"), "w"), indent=1, ensure_ascii=False)
print("security workspaces not onboarded to Sentinel:", not_onboarded)
