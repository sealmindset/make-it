"""Shared helpers for the threats-it scripts. Standard library only.

Tokens come from the signed-in Azure CLI (`az login`). Every helper here is read-only:
GET requests, or POSTs to *query* endpoints (Log Analytics, Resource Graph).

The one rule every script follows: a query either answered (status 200) or it FAILED. A failed query is recorded
with failed(), the part of the output built on it says NOT ASSESSED (never "none", an empty list or a zero), the
script's summary JSON carries failures(), and the script ends with finish(), which names each one and exits:
  exit 3  STOP and ask: something failed that the person must decide on or a re-run can fix (no workspace readable,
          the workspace list failed, a 429, a 5xx, a timeout, a cut-off or partial answer, a refused Graph call,
          an expired sign-in)
  exit 4  CONTINUE: the only thing not read is one or more workspaces the reader has no access to (401/403 on the
          workspace's tables). Each is named "NOT ASSESSED (no access)"; the run goes on.
A script that reads access.json does it through read_access(), which carries forward what tenant_access.py could not
read, so a workspace that was not read is named again by every later script. A query that answered with nothing in
it is a real "none". Error bodies are never printed or stored (they can repeat a token): the status and a short
reason code only. Credentials never follow a redirect.
"""
import base64
import datetime as dt
from http.client import HTTPException
import json
import os
import re
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


def failed(query, where, status, kind="failed", later=None, origin=None):
    """Record one query that did not answer. `query` is a short name, never the query text; `where` is a workspace
    name or a service, never an id; no token comes near here. kind: "failed" (stop), "no access" (a workspace the
    reader cannot read: named, the run continues) or "partial". later: which later scripts must carry it forward
    ("workspaces", "tenant", "sentinel"). One entry per (query, where)."""
    if any(f["query"] == query and f["where"] == where for f in _failed):
        return
    e = {"query": query, "where": where, "status": status_text(status), "kind": kind}
    _failed.append(e | ({"later": later} if later else {}) | ({"from": origin} if origin else {}))


def workspace_unread(name, status, later=None):
    """A workspace whose tables could not be read. 401/403: the reader has no access, which is normal and does not
    stop the run. Anything else (429, 5xx, a timeout) is a failure a re-run can fix."""
    failed("workspace", name, status, "no access" if status in (401, 403) else "failed", later)


def failures():
    return list(_failed)


def unread(query="workspace"):
    """What was recorded as not read under this name: {where: "NOT ASSESSED (no access)" or "FAILED"}."""
    return {f["where"]: "NOT ASSESSED (no access)" if f["kind"] == "no access" else "FAILED" for f in _failed if f["query"] == query}


def read_access(outdir, *needs):
    """access.json, for every script that runs after tenant_access.py: the ONE way to read it. What tenant_access.py
    could not read is carried forward here (unreadable workspaces and a failed workspace list always; "tenant" and
    "sentinel" when the script depends on them), so a later script names it again instead of reading as clean."""
    with open(os.path.join(outdir, "access.json"), encoding="utf-8") as f:
        access = json.load(f)
    origin = "tenant_access.py"
    for f in access.get("failed_queries") or []:
        if f.get("later") in ("workspaces",) + needs:
            failed(f["query"], f["where"], f["status"], f.get("kind", "failed"), origin=origin)
    for key in ("workspaces_with_security_tables", "workspaces_unreadable"):
        if not isinstance(access.get(key), list):  # "NOT ASSESSED (...)": the workspace list was not read
            access[key] = []
    for name in access["workspaces_unreadable"]:  # an access.json written before failures were listed
        failed("workspace", name, "not readable", origin=origin)
    if "tenant" in needs and not (access.get("tenant") or {}).get("id"):
        failed("tenant (organization)", "Microsoft Graph", "not read", origin=origin)
    return access


def finish():
    """Last line of every script. Nothing failed: return. Otherwise name each one, then exit 3 (stop and ask) or,
    when the only thing not read is workspaces the reader has no access to, exit 4 (named, the run continues)."""
    if not _failed:
        return
    for f in _failed:
        src = f", from {f['from']}" if f.get("from") else ""
        if f["kind"] == "no access":
            print(f"NOT ASSESSED (no access): workspace {f['where']} ({f['status']}{src})")
        elif f["kind"] == "partial":
            print(f"PARTIAL: {f['query']} in {f['where']} (partial answer{src}): the rows shown are not all of them, so this part is not fully assessed")
        else:
            print(f"FAILED: {f['query']} in {f['where']} ({f['status']}{src})")
    stop = [f for f in _failed if f["kind"] != "no access"]
    if stop:
        n = len(stop)
        print(f"NOT ASSESSED: {n} quer{'y' if n == 1 else 'ies'} failed (exit 3). STOP and ask before the next script. What "
              f"{'it covers' if n == 1 else 'they cover'} was not looked at: report it as \"not assessed\", never as \"none\" or clean.")
        sys.exit(3)
    n = len(_failed)
    print(f"CONTINUE: {n} workspace{'' if n == 1 else 's'} could not be read for lack of access (exit 4). The run goes on. "
          "In every part of the report each one is \"not assessed (no access)\", never \"none\" or clean.")
    sys.exit(4)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Credentials go to the host they were meant for and nowhere else: a redirect is not followed, it is a failure."""

    def redirect_request(self, *a, **k):
        return None


_opener = urllib.request.build_opener(NoRedirect)


def token(resource):
    if resource not in _tokens:
        try:
            r = subprocess.run(["az", "account", "get-access-token", "--resource", resource, "--query", "accessToken", "-o", "tsv"],
                               capture_output=True, text=True)
            ok = r.returncode == 0 and r.stdout.strip()
        except OSError:
            ok = False
        if not ok:  # az's own message can name the tenant: say what to do, not what it said
            failed("sign-in", "Azure CLI", "no token: sign in again with `az login`, then run this script again")
            finish()
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
        with _opener.open(req, timeout=timeout) as resp:
            status, txt = resp.status, resp.read().decode(errors="replace")
    except urllib.error.HTTPError as e:  # includes a redirect: it is not followed
        return e.code, {"error": reason(e.read().decode(errors="replace"))}
    except (OSError, HTTPException) as e:  # no HTTP answer: a timeout, a refused or dropped connection
        return no_answer(e), {"error": {"code": "NoAnswer"}}
    try:
        res = json.loads(txt)
    except ValueError:  # an answer that is not the JSON it claims to be is not a result
        return "malformed JSON", {"error": {"code": "MalformedJSON"}}
    if res is None:  # a body of `null` answers nothing
        return "empty answer", {"error": {"code": "EmptyAnswer"}}
    return status, res


def reason(txt):
    """All that is kept of an error body: its short code and whether it is about missing scopes. Never the text:
    a service can repeat the request's token in it."""
    try:
        err = json.loads(txt).get("error") or {}
        code, msg = err.get("code"), str(err.get("message") or "")
    except (ValueError, AttributeError):
        return {"code": ""}
    out = {"code": code if isinstance(code, str) and re.fullmatch(r"[A-Za-z_]{1,48}", code) else ""}
    return out | ({"hint": "missing scopes"} if "scope" in msg.lower() else {})


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


def la(workspace_id, query, name=None, where=None):
    """Log Analytics query. Returns (status, list of row dicts or error body). An HTTP 200 that carries an error
    beside its rows (PartialError) is a partial answer: the rows are returned and, given the query's short name and
    its workspace, it is recorded as "partial" so that part reads not fully assessed."""
    status, res = http("POST", f"{LA}/v1/workspaces/{workspace_id}/query", LA, {"query": query}, extra={"Prefer": "wait=600"})
    if status != 200:
        return status, res
    try:
        t = res["tables"][0]
        cols = [c["name"] for c in t["columns"]]
        rows = [dict(zip(cols, r)) for r in t["rows"]]
    except (KeyError, IndexError, TypeError):
        return "malformed answer", {"error": {"code": "MalformedAnswer"}}
    if res.get("error"):
        failed(name or "query", where or "Log Analytics", "partial answer", "partial")
    return 200, rows


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
