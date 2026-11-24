"""Shared helpers for the threats-it scripts. Standard library only.

Tokens come from the signed-in Azure CLI (`az login`). Every helper here is read-only:
GET requests, or POSTs to *query* endpoints (Log Analytics, Resource Graph).

The one rule every script follows: a query either answered (status 200) or it FAILED. A failed query is recorded
with failed(), the part of the output built on it says NOT ASSESSED (never "none", an empty list or a zero), the
script's summary JSON carries failures(), and the script ends with finish(): one FAILED line per query, then exit 3.
A query that answered with nothing in it is a real "none".
"""
import base64
import datetime as dt
from http.client import HTTPException
import json
import os
import socket
import subprocess
import sys
import urllib.error
import urllib.request

GRAPH = "https://graph.microsoft.com"
ARM = "https://management.azure.com"
LA = "https://api.loganalytics.io"
MICROSOFT_OWNER_TENANTS = {"f8cdef31-a31e-4b4a-93e4-5f571e91255a", "72f988bf-86f1-41af-91ab-2d7cd011db47"}
_tokens = {}
_failed = []


def status_text(status):
    return f"HTTP {status}" if isinstance(status, int) else str(status)


def no_answer(e):
    """Why a request got no HTTP answer at all, as a status word."""
    return "timeout" if isinstance(getattr(e, "reason", e), (TimeoutError, socket.timeout)) else "no answer"


def failed(query, where, status):
    """Record one query that did not answer. `query` is a short name, never the query text; `where` is a workspace
    name or a service, never an id; no token comes near here."""
    _failed.append({"query": query, "where": where, "status": status_text(status)})


def failures():
    return list(_failed)


def finish():
    """Last line of every script. Nothing failed: return. Otherwise name each failed query and exit 3."""
    if not _failed:
        return
    for f in _failed:
        print(f"FAILED: {f['query']} in {f['where']} ({f['status']})")
    n = len(_failed)
    print(f"NOT ASSESSED: {n} quer{'y' if n == 1 else 'ies'} failed (exit 3). What {'it covers' if n == 1 else 'they cover'} "
          "was not looked at: report it as \"not assessed\", never as \"none\" or clean.")
    sys.exit(3)


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
            status, txt = resp.status, resp.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        txt = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(txt)
        except ValueError:
            return e.code, {"raw": txt[:2000]}
    except (OSError, HTTPException) as e:  # no HTTP answer: a timeout, a refused or dropped connection
        return no_answer(e), {"error": {"code": "NoAnswer", "message": type(e).__name__}}
    try:
        return status, json.loads(txt or "null")
    except ValueError:  # an answer that is not the JSON it claims to be is not a result
        return "malformed JSON", {"raw": txt[:2000]}


def graph_all(url):
    """Follow @odata.nextLink. Returns (status, list or error body)."""
    items = []
    while url:
        status, page = http("GET", url, GRAPH, extra={"ConsistencyLevel": "eventual"})
        if status != 200:
            return status, page
        if not isinstance(page, dict):
            return "malformed answer", page
        items += page.get("value", [])
        url = page.get("@odata.nextLink")
    return 200, items


def graph_cached(outdir, name, url):
    """A Graph list, read once per run: this run's saved copy when that copy answered, else fetched and saved.
    Returns the list, or None when the call failed (recorded with failed())."""
    p = os.path.join(outdir, f"{name}.json")
    if os.path.exists(p):
        rec = load(outdir, name)
        if rec.get("http_status") == 200:
            return rec["result"]
    status, res = graph_all(url)
    save(outdir, name, "graph", url, status, res)
    if status != 200:
        failed(name, "Microsoft Graph", status)
        return None
    return res


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
        if not isinstance(res, dict):
            return "malformed answer", res
        rows += res.get("data", [])
        skip = res.get("$skipToken")
        if not skip:
            return 200, rows


def la(workspace_id, query):
    """Log Analytics query. Returns (status, list of row dicts or error body)."""
    status, res = http("POST", f"{LA}/v1/workspaces/{workspace_id}/query", LA, {"query": query}, extra={"Prefer": "wait=600"})
    if status != 200:
        return status, res
    try:
        t = res["tables"][0]
        cols = [c["name"] for c in t["columns"]]
        return 200, [dict(zip(cols, r)) for r in t["rows"]]
    except (KeyError, IndexError, TypeError):
        return "malformed answer", res


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
