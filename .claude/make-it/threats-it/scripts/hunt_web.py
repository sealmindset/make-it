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
Writes web-hunt-summary.json. A query that failed is printed as FAILED, listed there under "failed_queries", and the
script exits 3: that workspace or query is not assessed, never "none". A workspace the reader has no access to
(401/403) is named "NOT ASSESSED (no access)" and the run continues (exit 4), unless none could be read. Pull the full record behind every web_ioc match before reporting it: a term can match
any column.
"""
import argparse
import datetime as dt
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import failed, failures, finish, la, load, save, workspace_unread  # noqa: E402

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
listed = load(od, "arg_workspaces")
if listed["http_status"] != 200:  # tenant_access.py could not list the workspaces: there is nothing to search in
    failed("workspace list", "Resource Graph", listed["http_status"], origin="tenant_access.py")
for w in listed["result"] if listed["http_status"] == 200 else []:
    since = (today - dt.timedelta(days=min(int(w.get("retentionInDays") or 30), 730))).isoformat()
    tag = w["name"]
    code, rows = la(w["customerId"], f"Usage | where TimeGenerated > ago(30d) | where DataType in ({', '.join(json.dumps(t) for t in WEB)}) | summarize MB=round(sum(Quantity), 1) by DataType", "web tables (Usage)", tag)
    if code != 200:
        workspace_unread(tag, code)
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
        code, rows = la(w["customerId"], q, "IOC search (web_ioc)", tag)
        save(od, f"web_ioc_{tag}", "log_analytics", {"workspace": tag, "query": q}, code, rows)
        ws["results"]["web_ioc"] = {"status": code, "rows": rows if code == 200 else None}
        if code != 200:
            failed("IOC search (web_ioc)", tag, code)
    if "AppServiceHTTPLogs" in tables:
        q = (f"AppServiceHTTPLogs | where TimeGenerated >= datetime({since}) | where CsMethod == 'POST' and CsBytes >= {a.big_post_bytes}"
             " | summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), MaxBytes=max(CsBytes), Statuses=make_set(ScStatus), ClientIPs=make_set(CIp, 20) by CsHost")
        code, rows = la(w["customerId"], q, "large uploads (big_post)", tag)
        save(od, f"web_bigpost_{tag}", "log_analytics", {"workspace": tag, "query": q}, code, rows)
        ws["results"]["big_post"] = {"status": code, "rows": rows if code == 200 else None}
        if code != 200:
            failed("large uploads (big_post)", tag, code)
    con = [t for t in CONSOLE if t in tables]
    if con:
        crash = a.crash_regex.replace("'", "''")  # inside KQL's verbatim @'...' a quote is doubled
        q = ("union isfuzzy=true " + ", ".join(f"({CONSOLE[t]} | extend Src='{t}')" for t in con) +
             f" | where TimeGenerated >= datetime({since}) | where Text matches regex @'{crash}'"
             " | summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), Sample=take_any(substring(Text, 0, 240)) by Src, App")
        code, rows = la(w["customerId"], q, "crash signals (crash_signals)", tag)
        save(od, f"web_crash_{tag}", "log_analytics", {"workspace": tag, "query": q}, code, rows)
        ws["results"]["crash_signals"] = {"status": code, "rows": rows if code == 200 else None}
        if code != 200:
            failed("crash signals (crash_signals)", tag, code)
if summary["workspaces"] and not any(v.get("readable") for v in summary["workspaces"].values()):
    failed("every workspace", "Log Analytics", "none readable")
summary["failed_queries"] = failures()
json.dump(summary, open(os.path.join(od, "web-hunt-summary.json"), "w"), indent=1)
hits = {k: v["results"]["web_ioc"]["rows"] for k, v in summary["workspaces"].items() if v.get("results", {}).get("web_ioc", {}).get("rows")}
# A query that failed is not a clean result: report it apart from the hits. A workspace whose tables could not be
# listed was not searched either.
not_read = {k: v["status"] for k, v in summary["workspaces"].items() if v.get("readable") is False}
ioc_failed = {k: v["results"]["web_ioc"]["status"] for k, v in summary["workspaces"].items()
              if v.get("results", {}).get("web_ioc", {}).get("status", 200) != 200}
searched = [k for k, v in summary["workspaces"].items() if v.get("results", {}).get("web_ioc", {}).get("status") == 200]
no_list = any(f["query"] == "workspace list" for f in summary.get("failed_queries", []))  # nothing was searched, nothing is "none"
gap = ioc_failed or not_read
verdict = hits or ("NOT ASSESSED, the workspace list was not read" if no_list
                   else "NOT ASSESSED, no workspace answered" if gap and not searched
                   else "none in the workspaces that answered" if gap
                   else "none" if searched else "not searched (no web tables, or no search terms)")
# an IOC search that answered only in part did not look at everything, even when no rows came
part_ioc = sorted(f["where"] for f in summary.get("failed_queries", []) if f.get("kind") == "partial" and f["query"].startswith("IOC search"))
if part_ioc and verdict == "none":
    verdict = "none in the rows that came"
print("workspaces with web tables:", "NOT ASSESSED" if no_list else sum(1 for v in summary["workspaces"].values() if v.get("web_tables_mb_30d")),
      "| IOC hits:", verdict, *(["| IOC query FAILED in:", ioc_failed or "none"] if searched or ioc_failed else []),
      *(["| workspaces not read:", not_read] if not_read else []),
      *(["| IOC search not fully assessed in:", part_ioc] if part_ioc else []))
finish()
