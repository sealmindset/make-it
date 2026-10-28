"""Shared helpers for the threats-it scripts. Standard library only.

Tokens come from the signed-in Azure CLI (`az login`). Every helper here is read-only:
GET requests, or POSTs to *query* endpoints (Log Analytics, Resource Graph).
"""
import base64
import datetime as dt
import json
import os
import subprocess
import urllib.error
import urllib.request

GRAPH = "https://graph.microsoft.com"
ARM = "https://management.azure.com"
LA = "https://api.loganalytics.io"
MICROSOFT_OWNER_TENANTS = {"f8cdef31-a31e-4b4a-93e4-5f571e91255a", "72f988bf-86f1-41af-91ab-2d7cd011db47"}
_tokens = {}


def token(resource):
    if resource not in _tokens:
        r = subprocess.run(["az", "account", "get-access-token", "--resource", resource, "--query", "accessToken", "-o", "tsv"],
                           capture_output=True, text=True, check=True)
        _tokens[resource] = r.stdout.strip()
    return _tokens[resource]


def claims(resource=GRAPH):
    part = token(resource).split(".")[1]
    c = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
    return {k: c.get(k) for k in ("aud", "appid", "app_displayname", "tid", "upn", "scp", "wids", "amr")}


def http(method, url, resource, body=None, extra=None, timeout=660):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token(resource)}")
    req.add_header("Content-Type", "application/json")
    for k, v in (extra or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode() or "null")
    except urllib.error.HTTPError as e:
        txt = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(txt)
        except ValueError:
            return e.code, {"raw": txt[:2000]}


def graph_all(url):
    """Follow @odata.nextLink. Returns (status, list or error body)."""
    items = []
    while url:
        status, page = http("GET", url, GRAPH, extra={"ConsistencyLevel": "eventual"})
        if status != 200:
            return status, page
        items += page.get("value", [])
        url = page.get("@odata.nextLink")
    return 200, items


def arg(query):
    """Azure Resource Graph across every subscription the identity can read."""
    url = f"{ARM}/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01"
    rows, skip = [], None
    while True:
        body = {"query": query, "options": {"resultFormat": "objectArray", "$top": 1000}}
        if skip:
            body["options"]["$skipToken"] = skip
        status, res = http("POST", url, ARM, body)
        if status != 200:
            return status, res
        rows += res.get("data", [])
        skip = res.get("$skipToken")
        if not skip:
            return 200, rows


def la(workspace_id, query):
    """Log Analytics query. Returns (status, list of row dicts or error body)."""
    status, res = http("POST", f"{LA}/v1/workspaces/{workspace_id}/query", LA, {"query": query}, extra={"Prefer": "wait=600"})
    if status != 200:
        return status, res
    t = res["tables"][0]
    cols = [c["name"] for c in t["columns"]]
    return 200, [dict(zip(cols, r)) for r in t["rows"]]


def save(outdir, name, kind, request, status, result):
    os.makedirs(outdir, exist_ok=True)
    rec = {"name": name, "kind": kind, "request": request,
           "run_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "http_status": status, "result": result}
    with open(os.path.join(outdir, f"{name}.json"), "w", encoding="utf-8") as f:
        json.dump(rec, f, indent=1, ensure_ascii=False)
    n = len(result) if isinstance(result, list) else "-"
    print(f"{name:44s} {status}  rows={n}")
    return rec


def load(outdir, name):
    with open(os.path.join(outdir, f"{name}.json"), encoding="utf-8") as f:
        return json.load(f)


def owner_class(owner, own_tenant):
    if not owner:
        return "unknown"
    if owner == own_tenant:
        return "own"
    if owner in MICROSOFT_OWNER_TENANTS:
        return "microsoft"
    return "third-party"
