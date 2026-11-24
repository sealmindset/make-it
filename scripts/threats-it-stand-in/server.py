"""A stand-in for what the threats-it scripts call: Microsoft Graph, Resource Graph, Log Analytics, attack.mitre.org.

How to run it (localhost only; nothing here ever reaches a real tenant):
  1. python3 -I scripts/threats-it-stand-in/server.py /tmp/port /tmp/scenario.json &     (port 0 on 127.0.0.1; the port lands in /tmp/port)
  2. echo '[{"when": ["/la/", "Usage"], "status": 403}]' > /tmp/scenario.json             (rules are re-read on every request; [] = healthy)
  3. PATH="scripts/threats-it-stand-in:$PATH" python3 -I scripts/threats-it-stand-in/run.py "$(cat /tmp/port)" <script.py> <args>

A scenario is a list of rules; the first whose "when" strings are ALL in the request (path, then body) wins:
  {"when": [...], "status": 403}      that HTTP status with an error body (403, 429, 500 ...)
  {"when": [...], "mode": "timeout"}  no answer for 5 seconds (run.py caps the client's wait at 1 second)
  {"when": [...], "mode": "malformed"} HTTP 200 with JSON cut off half way
  {"when": [...], "mode": "empty"}    HTTP 200, a successful answer with nothing in it
  {"when": [...], "mode": "pass"}     the fixture, as if no rule matched (put it before a wider rule to exempt a call)
No rule matches: HTTP 200 with the fixture below. scripts/test-threats-it-failed-queries.sh drives every script with it.
"""
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TENANT = "00000000-aaaa-4bbb-8ccc-00000000dddd"       # the fake tenant id: no script may print it
VENDOR = "11111111-aaaa-4bbb-8ccc-00000000eeee"       # an outside owner tenant
WS = [{"id": f"/subscriptions/s1/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/{n}", "name": n, "resourceGroup": "rg",
       "subscriptionId": "s1", "customerId": f"cid-{n}", "retentionInDays": 90} for n in ("ws-a", "ws-b")]
SPS = [{"id": "sp-vendor", "appId": "app-vendor", "displayName": "Vendor Backup App", "appOwnerOrganizationId": VENDOR, "accountEnabled": True,
        "passwordCredentials": [{"startDateTime": "2026-01-01T00:00:00Z", "endDateTime": "2027-01-01T00:00:00Z"}], "keyCredentials": []},
       {"id": "sp-own", "appId": "app-own", "displayName": "Own Portal", "appOwnerOrganizationId": TENANT, "accountEnabled": True,
        "passwordCredentials": [], "keyCredentials": []}]
APPS = [{"id": "a1", "appId": "app-own", "displayName": "Own Portal", "signInAudience": "AzureADMyOrg", "passwordCredentials": [],
         "keyCredentials": [{"displayName": "CN=portal", "startDateTime": "2020-01-01T00:00:00Z", "endDateTime": "2032-01-01T00:00:00Z"}]}]
ROLES = [{"principalId": "sp-vendor", "roleDefinitionId": "rd-1", "directoryScopeId": "/",
          "principal": {"@odata.type": "#microsoft.graph.servicePrincipal", "displayName": "Vendor Backup App"}}]
USAGE = ["SigninLogs", "AADServicePrincipalSignInLogs", "AuditLogs", "MicrosoftGraphActivityLogs", "AppServiceHTTPLogs", "AppServiceConsoleLogs"]
TITLE = "<html><head><title>Exploit Public-Facing Application, Technique T1190 - Enterprise | MITRE ATT&amp;CK&reg;</title></head><body>ATT&amp;CK content v18.0</body></html>"


def table(cols, *rows):
    return {"tables": [{"columns": [{"name": c} for c in cols], "rows": list(rows)}]}


def log_analytics(q, empty):
    """The row shapes the scripts' queries summarise to. `empty` = the query worked and found nothing."""
    q = q[q.rfind(";") + 1:].lstrip()          # hunt.py puts its `let` lines first
    t = "2026-11-01T00:00:00Z"
    for marker, cols, row in (
            ("Usage", ["DataType", "MB"], None),
            ("search in", ["$table", "Count", "First", "Last"], ["AppServiceHTTPLogs", 3, t, t]),
            ("CsMethod", ["CsHost", "Count", "First", "Last", "MaxBytes"], ["shop.example", 2, t, t, 30000000]),
            ("matches regex @'", ["Src", "App", "Count", "First", "Last", "Sample"], ["AppServiceConsoleLogs", "shop", 1, t, t, "SIGSEGV"]),
            ("Kind='interactive'", ["Kind", "Name", "AppId", "SignIns", "Accounts", "First", "Last"], ["service principal", "Vendor Backup App", "app-vendor", 12, 1, t, t]),
            ("InitiatedBy.app", ["SpId", "AppId", "AppName", "Count", "Ops", "First", "Last"], ["sp-vendor", "app-vendor", "Vendor Backup App", 7, ["Add member to group"], t, t]),
            ("RequestMethod in", ["AppId", "ServicePrincipalId", "Count"], ["app-vendor", "sp-vendor", 4]),
            ("", ["Count"], None)):
        if marker in q:
            if marker == "Usage":
                return table(cols, *([] if empty else [[n, 5.0] for n in USAGE]))
            return table(cols, *([] if empty or row is None else [row]))


def resource_graph(q, empty):
    if "operationalinsights/workspaces" in q:
        return {"data": WS}                     # the workspace list stays: "empty" is about what the queries find
    if "SecurityInsights" in q:
        return {"data": [] if empty else [{"workspaceId": WS[0]["id"].lower()}]}
    if "hybridcompute" in q:
        return {"data": [] if empty else [{"name": "arc-1", "os": "Windows Server 2022", "v": "10.0.20348.100", "agent": "Connected"}]}
    if "virtualmachines" in q and "osDisk" in q:
        return {"data": [] if empty else [{"name": "vm-1", "os": "2022-datacenter", "v": "10.0.20348.9999", "agent": "PowerState/running"}]}
    return {"data": [] if empty else [{"type": "microsoft.compute/virtualmachines", "name": "fw-1", "pub": "paloaltonetworks", "offer": "vmseries"}]}


def graph(path, empty):
    m = re.search(r"servicePrincipals\(appId='([^']+)'\)", path)
    if m:
        return {"id": "res-" + m.group(1)[:8], "appRoles": [{"id": "role-1", "value": "Directory.ReadWrite.All"}]}
    for marker, value in (("appRoleAssignedTo", [{"principalType": "ServicePrincipal", "principalId": "sp-vendor", "appRoleId": "role-1"}]),
                          ("/servicePrincipals", SPS), ("/applications", APPS), ("roleAssignments", ROLES),
                          ("roleDefinitions", [{"id": "rd-1", "displayName": "Global Reader", "templateId": "t-1"}]),
                          ("subscribedSkus", [{"skuPartNumber": "SPE_E5", "servicePlans": [{"servicePlanName": "AAD_PREMIUM_P2"}]}]),
                          ("/organization", [{"id": TENANT, "displayName": "Stand-in Org"}])):
        if marker in path:
            return {"value": value if marker == "/organization" or not empty else []}
    return {"value": []}                        # the probes and the security endpoints: reachable, nothing in them


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def answer(self, status, body, kind="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        query = json.loads(body).get("query", "") if body else ""
        seen = self.path + "\n" + body
        try:
            rules = json.load(open(sys.argv[2]))
        except (OSError, ValueError):
            rules = []
        rule = next((r for r in rules if all(w in seen for w in r["when"])), {})
        mode, empty = rule.get("mode"), rule.get("mode") == "empty"
        if mode == "timeout":
            time.sleep(5)
            return
        if mode == "malformed":
            return self.answer(200, b'{"value": [{"id": ')
        if "status" in rule:
            return self.answer(rule["status"], {"error": {"code": "StandIn", "message": f"stand-in answered {rule['status']}"}})
        if self.path.startswith("/attack/"):
            if "T1190" in self.path and not empty:
                return self.answer(200, TITLE.encode(), "text/html")
            return self.answer(200, b"<html><body>nothing here</body></html>", "text/html") if empty else self.answer(404, b"not found", "text/html")
        if self.path.startswith("/la/"):
            return self.answer(200, log_analytics(query, empty))
        if "ResourceGraph" in self.path:
            return self.answer(200, resource_graph(query, empty))
        if "alertRules" in self.path:
            return self.answer(200, {"value": [] if empty else [{"name": "r1", "kind": "Scheduled", "properties": {
                "displayName": "Service principal sign-in from new ASN", "enabled": True, "query": "AADServicePrincipalSignInLogs | take 1"}}]})
        if self.path.startswith("/graph/"):
            return self.answer(200, graph(self.path, empty))
        return self.answer(200, {"value": []})

    do_GET = do_POST = handle_any


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    srv.daemon_threads = True
    with open(sys.argv[1], "w") as f:
        f.write(str(srv.server_address[1]))
    srv.serve_forever()
