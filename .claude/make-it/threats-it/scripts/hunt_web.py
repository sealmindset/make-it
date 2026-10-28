"""Read-only hunt of inbound web telemetry for a threat's indicators, in every readable workspace.

  python3 -I hunt_web.py <outdir> <ioc.json> [--big-post-bytes N] [--crash-regex REGEX]

hunt.py covers identity, Graph, Office, firewall and endpoint tables. Web-borne threats arrive as HTTP requests, so
this adds the web-server, gateway and API tables. Needs <outdir>/arg_workspaces.json (tenant_access.py). Search terms:
ioc.json "ips", "unconfirmed_ips", "domains" and "web_terms" (e.g. a scanner's user-agent token). Per workspace
(full retention, max 730 days):
  web_tables_<ws>   which web tables the workspace ingests (Usage, 30 days) — the coverage denominator
  web_ioc_<ws>      search of every web table present for the terms
  web_bigpost_<ws>  App Service HTTP logs: POST bodies of at least --big-post-bytes (default 20,000,000)
  web_crash_<ws>    App Service / container console logs matching --crash-regex, by app
Writes web-hunt-summary.json. Pull the full record behind every web_ioc match before reporting it: a term can match
any column.
"""
import argparse
import datetime as dt
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import la, load, save  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("ioc")
ap.add_argument("--big-post-bytes", type=int, default=20_000_000)
ap.add_argument("--crash-regex", default=r"(?i)(segmentation fault|SIGSEGV|core dumped|exited with code 139)")
a = ap.parse_args()
od, cfg = a.outdir, json.load(open(a.ioc))
WEB = ["AppServiceHTTPLogs", "W3CIISLog", "AppRequests", "AGWAccessLogs", "AGWFirewallLogs", "AzureDiagnostics",
       "CommonSecurityLog", "ApiManagementGatewayLogs", "AZFWApplicationRule", "AZFWNetworkRule", "AZFWIdpsSignature",
       "ContainerAppConsoleLogs_CL", "ContainerAppConsoleLogs", "AppServiceConsoleLogs", "ContainerLogV2"]
CONSOLE = {"AppServiceConsoleLogs": "AppServiceConsoleLogs | extend Text=ResultDescription, App=tostring(split(_ResourceId, '/')[-1])",
           "ContainerAppConsoleLogs_CL": "ContainerAppConsoleLogs_CL | extend Text=tostring(column_ifexists('Log_s', '')), App=tostring(column_ifexists('ContainerAppName_s', ''))",
           "ContainerAppConsoleLogs": "ContainerAppConsoleLogs | extend Text=tostring(column_ifexists('Log', '')), App=tostring(column_ifexists('ContainerAppName', ''))",
           "ContainerLogV2": "ContainerLogV2 | extend Text=tostring(LogMessage), App=ContainerName"}
terms = [t for k in ("ips", "unconfirmed_ips", "domains", "web_terms") for t in cfg.get(k, [])]
today = dt.datetime.now(dt.timezone.utc).date()
summary = {"terms": terms, "big_post_bytes": a.big_post_bytes, "crash_regex": a.crash_regex, "workspaces": {}}
for w in load(od, "arg_workspaces")["result"]:
    since = (today - dt.timedelta(days=min(int(w.get("retentionInDays") or 30), 730))).isoformat()
    tag = w["name"]
    code, rows = la(w["customerId"], f"Usage | where TimeGenerated > ago(30d) | where DataType in ({', '.join(json.dumps(t) for t in WEB)}) | summarize MB=round(sum(Quantity), 1) by DataType")
    if code != 200:
        summary["workspaces"][tag] = {"readable": False, "status": code}
        continue
    tables = {r["DataType"]: r["MB"] for r in rows}
    ws = {"readable": True, "retentionInDays": w.get("retentionInDays"), "since": since, "web_tables_mb_30d": tables, "results": {}}
    summary["workspaces"][tag] = ws
    if not tables:
        continue
    save(od, f"web_tables_{tag}", "log_analytics", "Usage of web tables, 30 days", code, rows)
    if terms:
        q = (f"search in ({', '.join(tables)}) TimeGenerated >= datetime({since}) and ({' or '.join(json.dumps(t) for t in terms)})"
             " | summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated) by $table")
        code, rows = la(w["customerId"], q)
        save(od, f"web_ioc_{tag}", "log_analytics", {"workspace": tag, "query": q}, code, rows)
        ws["results"]["web_ioc"] = {"status": code, "rows": rows if code == 200 else None}
    if "AppServiceHTTPLogs" in tables:
        q = (f"AppServiceHTTPLogs | where TimeGenerated >= datetime({since}) | where CsMethod == 'POST' and CsBytes >= {a.big_post_bytes}"
             " | summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), MaxBytes=max(CsBytes), Statuses=make_set(ScStatus), ClientIPs=make_set(CIp, 20) by CsHost")
        code, rows = la(w["customerId"], q)
        save(od, f"web_bigpost_{tag}", "log_analytics", {"workspace": tag, "query": q}, code, rows)
        ws["results"]["big_post"] = {"status": code, "rows": rows if code == 200 else None}
    con = [t for t in CONSOLE if t in tables]
    if con:
        q = ("union isfuzzy=true " + ", ".join(f"({CONSOLE[t]} | extend Src='{t}')" for t in con) +
             f" | where TimeGenerated >= datetime({since}) | where Text matches regex @'{a.crash_regex}'"
             " | summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), Sample=take_any(substring(Text, 0, 240)) by Src, App")
        code, rows = la(w["customerId"], q)
        save(od, f"web_crash_{tag}", "log_analytics", {"workspace": tag, "query": q}, code, rows)
        ws["results"]["crash_signals"] = {"status": code, "rows": rows if code == 200 else None}
json.dump(summary, open(os.path.join(od, "web-hunt-summary.json"), "w"), indent=1)
hits = {k: v["results"]["web_ioc"]["rows"] for k, v in summary["workspaces"].items() if v.get("results", {}).get("web_ioc", {}).get("rows")}
print("workspaces with web tables:", sum(1 for v in summary["workspaces"].values() if v.get("web_tables_mb_30d")), "| IOC hits:", hits or "none")
