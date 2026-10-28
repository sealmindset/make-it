"""Directory exposure, product presence and server patch state. Read-only.

  python3 -I exposure.py <outdir> <presence.json> [--fixmap <msrc-summary.json> --cve CVE-x] [--since 2026-10-13]

presence.json maps each product named in the threat to search patterns:
  {"Palo Alto PAN-OS": {"app_names": "palo ?alto|globalprotect", "arm_publisher": "paloalto", "arm_offer": "vmseries|panorama",
                        "arm_type": ""}, ...}
Outputs <outdir>/exposure.json with:
  takeover / bulk-data Graph application permissions held by outside and own service principals
  credentials stored on outside service principals; service principals and groups holding directory roles
  certificates valid > 5 years on own app registrations; credentials whose start date >= --since
  per product: Azure resources (regex on publisher/offer/type — never KQL `has` for IDs), enterprise apps whose
  display name matches, and their interactive / service-principal sign-ins in every readable workspace
  servers (with --fixmap): Arc and Azure VM Windows builds against the MSRC fixed build for --cve
"""
import argparse
import collections
import datetime as dt
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import GRAPH, arg, graph_all, http, la, owner_class, save  # noqa: E402

TAKEOVER_VERIFIED = ["RoleManagement.ReadWrite.Directory", "Application.ReadWrite.All", "Directory.ReadWrite.All"]
TAKEOVER_COMMON = ["AppRoleAssignment.ReadWrite.All", "UserAuthenticationMethod.ReadWrite.All", "Domain.ReadWrite.All",
                   "Policy.ReadWrite.ConditionalAccess", "PrivilegedAccess.ReadWrite.AzureADGroup",
                   "RoleAssignmentSchedule.ReadWrite.Directory", "RoleEligibilitySchedule.ReadWrite.Directory"]
BULK = ["Mail.Read", "Mail.ReadWrite", "Mail.Send", "Files.Read.All", "Files.ReadWrite.All", "Sites.Read.All", "Sites.ReadWrite.All",
        "Sites.FullControl.All", "full_access_as_app", "User.ReadWrite.All", "Group.ReadWrite.All"]
RESOURCES = {"graph": "00000003-0000-0000-c000-000000000000", "exchange": "00000002-0000-0ff1-ce00-000000000000",
             "sharepoint": "00000003-0000-0ff1-ce00-000000000000", "aadgraph": "00000002-0000-0000-c000-000000000000"}

ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("presence")
ap.add_argument("--fixmap")
ap.add_argument("--cve")
ap.add_argument("--since", default="")
a = ap.parse_args()
od = a.outdir
gb = f"{GRAPH}/v1.0"
access = json.load(open(os.path.join(od, "access.json")))
own = (access.get("tenant") or {}).get("id")


def fetch(name, url):
    p = os.path.join(od, name + ".json")
    if os.path.exists(p):
        return json.load(open(p))["result"]
    st, res = graph_all(url)
    save(od, name, "graph", url, st, res)
    return res if st == 200 else []


sps = fetch("graph_service_principals", f"{gb}/servicePrincipals?$top=999&$select=id,appId,displayName,appOwnerOrganizationId,accountEnabled,servicePrincipalType,passwordCredentials,keyCredentials,verifiedPublisher")
apps = fetch("graph_applications", f"{gb}/applications?$top=999&$select=id,appId,displayName,createdDateTime,signInAudience,passwordCredentials,keyCredentials")
ras = fetch("graph_role_assignments", f"{gb}/roleManagement/directory/roleAssignments?$expand=principal")
rds = fetch("graph_role_definitions", f"{gb}/roleManagement/directory/roleDefinitions?$select=id,displayName,templateId")
by_id = {s["id"]: s for s in sps}
cls = lambda spid: owner_class((by_id.get(spid) or {}).get("appOwnerOrganizationId"), own)
role_name = {d["id"]: d["displayName"] for d in rds} | {d["templateId"]: d["displayName"] for d in rds if d.get("templateId")}

perms = collections.defaultdict(set)
for key, app_id in RESOURCES.items():
    st, sp = http("GET", f"{gb}/servicePrincipals(appId='{app_id}')?$select=id,appRoles", GRAPH)
    if st != 200:
        continue
    values = {r["id"]: r["value"] for r in sp.get("appRoles", [])}
    for x in fetch(f"graph_assignedto_{key}", f"{gb}/servicePrincipals/{sp['id']}/appRoleAssignedTo?$top=999"):
        if x.get("principalType") == "ServicePrincipal" and values.get(x["appRoleId"]):
            perms[x["principalId"]].add(values[x["appRoleId"]])
aud = {x["appId"]: x.get("signInAudience") for x in apps}
rows = []
for spid, p in perms.items():
    s = by_id.get(spid, {})
    rows.append({"name": s.get("displayName"), "appId": s.get("appId"), "owner": s.get("appOwnerOrganizationId"), "class": cls(spid),
                 "publisher": (s.get("verifiedPublisher") or {}).get("displayName"), "enabled": s.get("accountEnabled"),
                 "signInAudience": aud.get(s.get("appId")), "takeover_verified": sorted(p & set(TAKEOVER_VERIFIED)),
                 "takeover_common": sorted(p & set(TAKEOVER_COMMON)), "bulk": sorted(p & set(BULK))})
tk = lambda r: r["takeover_verified"] or r["takeover_common"]
group_roles = collections.defaultdict(list)
sp_roles = []
for r in ras:
    p = r.get("principal") or {}
    t = p.get("@odata.type")
    if t == "#microsoft.graph.servicePrincipal":
        sp_roles.append({"sp": p.get("displayName"), "class": cls(r["principalId"]), "role": role_name.get(r["roleDefinitionId"]), "scope": r.get("directoryScopeId")})
    elif t == "#microsoft.graph.group":
        group_roles[p.get("displayName")].append(role_name.get(r["roleDefinitionId"]))
long_certs, new_creds = [], []
for x in apps:
    for kind, lst in (("certificate", x.get("keyCredentials") or []), ("secret", x.get("passwordCredentials") or [])):
        for c in lst:
            st_, en = c.get("startDateTime"), c.get("endDateTime")
            if kind == "certificate" and st_ and en:
                yrs = (dt.datetime.fromisoformat(en.replace("Z", "+00:00")) - dt.datetime.fromisoformat(st_.replace("Z", "+00:00"))).days / 365.25
                if yrs > 5:
                    long_certs.append({"app": x["displayName"], "subject": c.get("displayName"), "years": round(yrs, 1), "start": st_[:10]})
            if a.since and (st_ or "") >= a.since:
                new_creds.append({"app": x["displayName"], "kind": kind, "start": (st_ or "")[:10], "end": (en or "")[:10]})
foreign_creds = [{"sp": s["displayName"], "owner": s.get("appOwnerOrganizationId"), "kind": k, "usage": c.get("usage"),
                  "start": (c.get("startDateTime") or "")[:10], "end": (c.get("endDateTime") or "")[:10]}
                 for s in sps if owner_class(s.get("appOwnerOrganizationId"), own) == "third-party"
                 for k, lst in (("secret", s.get("passwordCredentials") or []), ("certificate", s.get("keyCredentials") or [])) for c in lst]

presence = json.load(open(a.presence))
signin_ws = [w for w in access["workspaces_with_security_tables"] if "SigninLogs" in w["security_tables_mb_30d"] or "AADServicePrincipalSignInLogs" in w["security_tables_mb_30d"]]
products = {}
for product, pat in presence.items():
    conds = []
    if pat.get("arm_publisher"):
        conds.append(f"pub matches regex @\"(?i){pat['arm_publisher']}\"")
    if pat.get("arm_offer"):
        conds.append(f"offer matches regex @\"(?i){pat['arm_offer']}\"")
    if pat.get("arm_type"):
        conds.append(f"type matches regex @\"(?i){pat['arm_type']}\"")
    resources = []
    if conds:
        st, resources = arg(f"""resources
| extend pub=tolower(tostring(coalesce(properties.storageProfile.imageReference.publisher, plan.publisher))),
         offer=tolower(tostring(coalesce(properties.storageProfile.imageReference.offer, plan.product)))
| where {' or '.join(conds)}
| project type, name, resourceGroup, subscriptionId, pub, offer, sku=tostring(coalesce(properties.storageProfile.imageReference.sku, plan.name)),
          imageVersion=tostring(properties.storageProfile.imageReference.exactVersion), powerState=tostring(properties.extended.instanceView.powerState.code)""")
        resources = resources if st == 200 else [{"error": resources}]
    names = sorted({s["displayName"] for s in sps if pat.get("app_names") and re.search(pat["app_names"], s.get("displayName") or "", re.I)})
    usage = []
    if pat.get("app_names"):
        for w in signin_ws:
            t = w["security_tables_mb_30d"]
            parts = []
            if "SigninLogs" in t:
                parts.append(f"SigninLogs | where AppDisplayName matches regex @\"(?i){pat['app_names']}\" | extend Kind='interactive', Name=AppDisplayName, Who=UserPrincipalName")
            if "AADServicePrincipalSignInLogs" in t:
                parts.append(f"AADServicePrincipalSignInLogs | where ServicePrincipalName matches regex @\"(?i){pat['app_names']}\" | extend Kind='service principal', Name=ServicePrincipalName, Who=ServicePrincipalName")
            q = "union " + ", ".join(f"({x})" for x in parts) + " | summarize SignIns=count(), Accounts=dcount(Who), First=min(TimeGenerated), Last=max(TimeGenerated) by Kind, Name, AppId"
            st, res = la(w["customerId"], q)
            usage += [dict(r, workspace=w["name"], in_directory=r["AppId"] in {s["appId"] for s in sps}) for r in (res if st == 200 else [])]
    products[product] = {"azure_resources": resources, "enterprise_apps": names, "signins": usage}

servers = None
if a.fixmap and a.cve:
    fm = json.load(open(a.fixmap))[a.cve]["fixed_builds"]
    need = {}
    for prod, entries in fm.items():
        for e in entries:
            b = e.split()[-1]
            if re.match(r"^\d+\.\d+\.\d+\.\d+$", b):
                pre, rev = b.rsplit(".", 1)
                need[(pre, "Server" in prod)] = int(rev)
    st, arc = arg("resources | where type =~ 'microsoft.hybridcompute/machines' and tostring(properties.osType) =~ 'windows' | project name, os=tostring(properties.osSku), v=tostring(properties.osVersion), agent=tostring(properties.status)")
    st2, vms = arg("resources | where type =~ 'microsoft.compute/virtualmachines' and tostring(properties.storageProfile.osDisk.osType) =~ 'windows' | project name, os=coalesce(tostring(properties.extended.instanceView.osName), tostring(properties.storageProfile.imageReference.sku)), v=tostring(properties.extended.instanceView.osVersion), agent=tostring(properties.extended.instanceView.powerState.code)")
    machines = []
    for src, lst in (("arc", arc if st == 200 else []), ("vm", vms if st2 == 200 else [])):
        for m in lst:
            is_server = bool(re.search(r"server|datacenter|20\d\d", m["os"] or "", re.I))
            reporting = (m["agent"] == "Connected") if src == "arc" else bool(m["v"])
            status, fixed = "not reporting", None
            if reporting and m["v"]:
                pre, rev = m["v"].rsplit(".", 1)
                fixed = need.get((pre, is_server)) or need.get((pre, not is_server))
                status = "build not in fix map" if fixed is None else ("fixed" if int(rev) >= fixed else "below fix")
            machines.append({"name": m["name"], "source": src, "os": m["os"], "version": m["v"], "agent": m["agent"], "server": is_server,
                             "status": status, "fixed_revision": fixed})
    servers = {"cve": a.cve, "counts": dict(collections.Counter(m["status"] for m in machines)), "machines": machines}

out = {"own_tenant": own,
       "third_party_takeover": [r for r in rows if r["class"] == "third-party" and tk(r)],
       "third_party_bulk_only": [r for r in rows if r["class"] == "third-party" and r["bulk"] and not tk(r)],
       "own_takeover": [r for r in rows if r["class"] == "own" and tk(r)],
       "foreign_sp_credentials": foreign_creds, "sp_roles": sp_roles, "group_roles": dict(group_roles),
       "long_lived_certs": long_certs, "creds_since": {"since": a.since, "items": new_creds}, "products": products, "servers": servers}
json.dump(out, open(os.path.join(od, "exposure.json"), "w"), indent=1, ensure_ascii=False)
print("third-party takeover:", [r["name"] for r in out["third_party_takeover"]])
print("own takeover:", len(out["own_takeover"]), "| foreign SP creds:", len(foreign_creds), "| SP roles:", len(sp_roles), "| long certs:", len(long_certs))
for p, v in products.items():
    per_ws = collections.defaultdict(int)
    for x in v["signins"]:
        per_ws[x["workspace"]] += int(x["SignIns"])
    # workspaces can overlap in time: report per workspace, never summed
    print(f"  {p}: resources={len(v['azure_resources'])} apps={len(v['enterprise_apps'])} signins_by_workspace={dict(per_ws)}")
if servers:
    print("servers:", servers["counts"])
