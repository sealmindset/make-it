"""Run the standard IOC and behaviour hunts for one threat, read-only, across every readable workspace.

  python3 -I hunt.py <outdir> <ioc.json>

Needs <outdir>/access.json from tenant_access.py. ioc.json (all keys optional except name):
  {"name": "...", "ips": [], "ip_prefixes": ["144.172.64."], "unconfirmed_ips": [], "asns": ["14956"],
   "user_agent_prefixes": ["curl/7.88.1"], "app_ids": [], "owner_tenants": [], "domains": [],
   "sha256": [], "file_names": [], "task_names": [], "window_start": "2026-10-10"}

Per workspace, only the queries whose tables exist are run, each over that workspace's full retention:
  signin_ioc     every sign-in table: IP / prefix / ASN / user agent / app ID / app-owner tenant, with match reason
  graph_ioc      MicrosoftGraphActivityLogs: IP / prefix / user agent / app ID (no ASN field exists)
  office_ioc     OfficeActivity: IPv4 extracted from the client-IP fields (no ASN field exists)
  network_ioc    firewall / DNS / endpoint-network tables: domains and IPs (search operator)
  endpoint_ioc   endpoint tables: SHA-256, file names, scheduled-task names
  audit_sweep    AuditLogs: EVERY operation initiated by an app, by initiator (classified by owner below)
  graph_appwrites MicrosoftGraphActivityLogs: app-only POST/PATCH/PUT to privileged endpoints
  vendor_new_asn / vendor_tested  outside apps signing in from an ASN unseen before window_start
Writes one JSON per query and hunt-summary.json (counts, owner classification of initiators).
"""
import collections
import datetime as dt
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import GRAPH, graph_all, la, owner_class, save  # noqa: E402

od, cfg_path = sys.argv[1], sys.argv[2]
cfg = json.load(open(cfg_path))
access = json.load(open(os.path.join(od, "access.json")))
own = (access.get("tenant") or {}).get("id")
today = dt.datetime.now(dt.timezone.utc).date()
tomorrow = (today + dt.timedelta(days=1)).isoformat()
J = lambda k: json.dumps(cfg.get(k, []))
ua_or = " or ".join(f'ua startswith "{u}"' for u in cfg.get("user_agent_prefixes", [])) or "false"
pfx_or = " or ".join(f'ip startswith "{p}"' for p in cfg.get("ip_prefixes", [])) or "false"
LETS = f"""
let IOC_IPS = dynamic({J('ips')}); let UNCONF_IPS = dynamic({J('unconfirmed_ips')});
let ASNS = dynamic({J('asns')}); let APPS = dynamic({J('app_ids')}); let OWNERS = dynamic({J('owner_tenants')});
let MSFT = dynamic(["f8cdef31-a31e-4b4a-93e4-5f571e91255a", "72f988bf-86f1-41af-91ab-2d7cd011db47"]);
let OWN = "{own}";
let IsIocIp = (ip:string) {{ ip in (IOC_IPS) or ip in (UNCONF_IPS) or {pfx_or} }};
let IsIocUa = (ua:string) {{ {ua_or} }};
"""
SIGNIN = ["SigninLogs", "AADNonInteractiveUserSignInLogs", "AADServicePrincipalSignInLogs", "AADManagedIdentitySignInLogs"]
NETWORK = ["CommonSecurityLog", "DnsEvents", "ASimDnsActivityLogs", "DeviceNetworkEvents", "AZFWNetworkRule", "AZFWApplicationRule", "AZFWDnsQuery", "AzureDiagnostics"]
ENDPOINT = ["DeviceFileEvents", "DeviceProcessEvents", "DeviceEvents", "DeviceImageLoadEvents"]


def search_terms(*keys):
    terms = [t for k in keys for t in cfg.get(k, [])]
    return " or ".join(json.dumps(t) for t in terms)


summary = {"ioc_config": cfg, "own_tenant": own, "workspaces": {}}
for w in access["workspaces_with_security_tables"]:
    tables = set(w["security_tables_mb_30d"])
    since = (today - dt.timedelta(days=min(int(w["retentionInDays"] or 30), 730))).isoformat()
    ws_sum = {"retentionInDays": w["retentionInDays"], "since": since, "queries": {}}
    queries = {}
    si = [t for t in SIGNIN if t in tables]
    if si:
        queries["signin_ioc"] = f"""union withsource=Table isfuzzy=true {', '.join(si)}
| where TimeGenerated >= datetime({since})
| extend ASN = tostring(AutonomousSystemNumber), Who = coalesce(UserPrincipalName, ServicePrincipalName), UA = tostring(UserAgent)
| extend Match = case(IsIocIp(IPAddress), "ip", ASN in (ASNS), "asn", IsIocUa(UA), "user_agent", AppId in (APPS), "app_id", AppOwnerTenantId in (OWNERS), "owner_tenant", "")
| where isnotempty(Match)
| summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), Results=make_set(tostring(ResultType), 20), IPs=make_set(IPAddress, 10)
          by Table, Match, Who, AppId, AppOwnerTenantId, ASN, UA"""
    if "AADServicePrincipalSignInLogs" in tables and cfg.get("window_start"):
        ws0 = cfg["window_start"]
        queries["vendor_new_asn"] = f"""let base = AADServicePrincipalSignInLogs
    | where TimeGenerated between (datetime({since}) .. datetime({ws0})) and tostring(ResultType) == "0"
    | where isnotempty(AppOwnerTenantId) and AppOwnerTenantId != OWN and AppOwnerTenantId !in (MSFT)
    | summarize KnownASN = make_set(tostring(AutonomousSystemNumber), 500) by AppId;
AADServicePrincipalSignInLogs
| where TimeGenerated between (datetime({ws0}) .. datetime({tomorrow})) and tostring(ResultType) == "0"
| where isnotempty(AppOwnerTenantId) and AppOwnerTenantId != OWN and AppOwnerTenantId !in (MSFT)
| join kind=leftouter base on AppId
| extend ASN = tostring(AutonomousSystemNumber)
| where isnull(KnownASN) or not(set_has_element(KnownASN, ASN))
| summarize Count=count(), First=min(TimeGenerated), IPs=make_set(IPAddress, 20) by AppId, ServicePrincipalName, AppOwnerTenantId, ASN, NewApp = isnull(KnownASN)"""
        queries["vendor_tested"] = f"""AADServicePrincipalSignInLogs
| where TimeGenerated between (datetime({ws0}) .. datetime({tomorrow})) and tostring(ResultType) == "0"
| where isnotempty(AppOwnerTenantId) and AppOwnerTenantId != OWN and AppOwnerTenantId !in (MSFT)
| summarize SuccessfulSignIns=count() by AppId, ServicePrincipalName, AppOwnerTenantId"""
    if "MicrosoftGraphActivityLogs" in tables:
        queries["graph_ioc"] = f"""MicrosoftGraphActivityLogs
| where TimeGenerated >= datetime({since})
| extend Match = case(IsIocIp(IPAddress), "ip", IsIocUa(UserAgent), "user_agent", AppId in (APPS), "app_id", "")
| where isnotempty(Match)
| summarize Count=count(), Writes=countif(RequestMethod != "GET"), First=min(TimeGenerated), Last=max(TimeGenerated), IPs=make_set(IPAddress, 10), SampleUris=make_set(RequestUri, 10)
          by Match, AppId, ServicePrincipalId, UserId, UserAgent"""
        queries["graph_appwrites"] = f"""MicrosoftGraphActivityLogs
| where TimeGenerated >= datetime({since}) and RequestMethod in ("POST", "PATCH", "PUT") and isempty(UserId)
| where RequestUri has_any ("addPassword", "addKey", "roleAssignments", "/directoryRoles/", "appRoleAssignments", "appRoleAssignedTo",
                            "federationConfiguration", "/authentication/", "oauth2PermissionGrants", "/owners/$ref")
| summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), Status=make_set(ResponseStatusCode, 10), IPs=make_set(IPAddress, 10),
            UAs=make_set(UserAgent, 5), SampleUris=make_set(RequestUri, 10) by AppId, ServicePrincipalId"""
    if "OfficeActivity" in tables:
        queries["office_ioc"] = f"""OfficeActivity
| where TimeGenerated >= datetime({since})
| extend Ip = extract(@"(\\d{{1,3}}\\.\\d{{1,3}}\\.\\d{{1,3}}\\.\\d{{1,3}})", 1, tostring(coalesce(ClientIP, Client_IPAddress, ActorIpAddress)))
| where IsIocIp(Ip)
| summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), Ops=make_set(Operation, 20) by Ip, UserId, RecordType"""
    if "AuditLogs" in tables:
        queries["audit_sweep"] = f"""AuditLogs
| where TimeGenerated >= datetime({since})
| extend SpId = tostring(InitiatedBy.app.servicePrincipalId), AppId = tostring(InitiatedBy.app.appId), AppName = tostring(InitiatedBy.app.displayName)
| where isnotempty(SpId) or isnotempty(AppId) or isnotempty(AppName)
| summarize Count=count(), Ops=make_set(OperationName, 60), First=min(TimeGenerated), Last=max(TimeGenerated) by SpId, AppId, AppName"""
    net = [t for t in NETWORK if t in tables]
    terms = search_terms("domains", "ips", "unconfirmed_ips")
    if net and terms:
        queries["network_ioc"] = f"search in ({', '.join(net)}) TimeGenerated >= datetime({since}) and ({terms}) | summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated) by $table"
    ep = [t for t in ENDPOINT if t in tables]
    terms = search_terms("sha256", "file_names", "task_names")
    if ep and terms:
        queries["endpoint_ioc"] = f"search in ({', '.join(ep)}) TimeGenerated >= datetime({since}) and ({terms}) | summarize Count=count(), First=min(TimeGenerated), Last=max(TimeGenerated), Devices=dcount(DeviceId) by $table"
    for qn, q in queries.items():
        st, rows = la(w["customerId"], LETS + q)
        name = f"hunt_{w['name']}_{qn}"
        save(od, name, "log_analytics", {"workspace": w["name"], "query": LETS + q}, st, rows)
        ws_sum["queries"][qn] = {"status": st, "rows": len(rows) if isinstance(rows, list) else None,
                                 "total": sum(int(r.get("Count") or r.get("SuccessfulSignIns") or 0) for r in rows) if isinstance(rows, list) else None}
    ws_sum["not_run"] = sorted({"signin_ioc", "graph_ioc", "graph_appwrites", "office_ioc", "audit_sweep", "network_ioc", "endpoint_ioc"} - set(queries))
    summary["workspaces"][w["name"]] = ws_sum

# classify app initiators and writers by owner tenant
sp_path = os.path.join(od, "graph_service_principals.json")
if not os.path.exists(sp_path):
    st, sps = graph_all(f"{GRAPH}/v1.0/servicePrincipals?$top=999&$select=id,appId,displayName,appOwnerOrganizationId,accountEnabled,servicePrincipalType,passwordCredentials,keyCredentials,verifiedPublisher")
    save(od, "graph_service_principals", "graph", "servicePrincipals", st, sps)
sps = json.load(open(sp_path))["result"]
by_id, by_app = {s["id"]: s for s in sps}, {s["appId"]: s for s in sps}
for wname, ws_sum in summary["workspaces"].items():
    p = os.path.join(od, f"hunt_{wname}_audit_sweep.json")
    if os.path.exists(p):
        rows = json.load(open(p))["result"]
        cls = collections.Counter()
        third = []
        for r in rows if isinstance(rows, list) else []:
            sp = by_id.get(r["SpId"]) or by_app.get(r["AppId"])
            c = owner_class(sp.get("appOwnerOrganizationId"), own) if sp else "unresolved"
            cls[c] += int(r["Count"])
            if c == "third-party":
                third.append({"app": r["AppName"], "owner": sp.get("appOwnerOrganizationId"), "events": int(r["Count"]),
                              "ops": json.loads(r["Ops"]) if isinstance(r["Ops"], str) else r["Ops"]})
        ws_sum["audit_sweep_events_by_owner"] = dict(cls)
        ws_sum["audit_sweep_third_party"] = third
    p = os.path.join(od, f"hunt_{wname}_graph_appwrites.json")
    if os.path.exists(p):
        rows = json.load(open(p))["result"]
        ws_sum["graph_appwrites_by_owner"] = [{"app": (by_app.get(r["AppId"]) or {}).get("displayName", r["AppId"]),
                                               "class": owner_class((by_app.get(r["AppId"]) or {}).get("appOwnerOrganizationId"), own) if r["AppId"] in by_app else "unresolved",
                                               "count": int(r["Count"])} for r in rows] if isinstance(rows, list) else rows
json.dump(summary, open(os.path.join(od, "hunt-summary.json"), "w"), indent=1, ensure_ascii=False)
for wname, s in summary["workspaces"].items():
    print(wname, {q: v["total"] for q, v in s["queries"].items()}, "| not run:", s["not_run"])
    if s.get("audit_sweep_third_party"):
        print("   third-party initiators:", [(x["app"], x["events"]) for x in s["audit_sweep_third_party"]])
