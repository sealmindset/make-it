"""
mock-oidc's own checks: local mode as before; in cluster mode the access code, its cookie, the admin API from
this machine only, the not-set-up page and the page headers. Runs the app in-process (no server, no network):
    python3 -I test_app.py        (needs requirements.txt installed)
Exit 0 = every check passed.
"""

import ast
import asyncio
import contextlib
import importlib.util
import io
import json
import os
import sys
import time
from urllib.parse import urlencode

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "app.py")
REDIR = "https://app.example.test/api/auth/callback"
QS = urlencode(dict(client_id="mock-oidc-client", redirect_uri=REDIR, response_type="code", state="s"))
CODE = "right-code-0123456789"
OUTSIDE, LOCAL = "10.42.0.17", "127.0.0.1"
SECRET = "test-only-client-secret"   # the pod's client secret: the admin API's bearer token in cluster mode
BEARER = "Bearer " + SECRET
failed = []
_loads = 0


def check(name, cond, why=""):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed.append(name)
        if why != "":
            print("     " + str(why)[:300])


def load(**env):
    """A fresh copy of app.py with these settings (and its start-up output)."""
    global _loads
    _loads += 1
    keep = dict(os.environ)
    for k in [k for k in os.environ if k.startswith("MOCK_OIDC_")]:
        del os.environ[k]
    os.environ.update(MOCK_OIDC_EXTERNAL_BASE_URL="https://app.example.test", MOCK_OIDC_CLIENT_SECRET=SECRET)
    os.environ.update(env)
    err = io.StringIO()
    try:
        spec = importlib.util.spec_from_file_location("mock_oidc_%d" % _loads, SRC)
        mod = importlib.util.module_from_spec(spec)
        with contextlib.redirect_stderr(err):
            spec.loader.exec_module(mod)
    finally:
        os.environ.clear()
        os.environ.update(keep)
    mod.startup_output = err.getvalue()
    return mod


async def _call(mod, method, path, client, form, js, cookie, auth=None):
    path, _, qs = path.partition("?")
    headers, body = [], b""
    if form is not None:
        body = urlencode(form).encode()
        headers.append((b"content-type", b"application/x-www-form-urlencoded"))
    if js is not None:
        body = json.dumps(js).encode()
        headers.append((b"content-type", b"application/json"))
    if cookie:
        headers.append((b"cookie", cookie.encode()))
    if auth:
        headers.append((b"authorization", auth.encode()))
    headers.append((b"content-length", str(len(body)).encode()))
    scope = {"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": method, "scheme": "http",
             "path": path, "raw_path": path.encode(), "query_string": qs.encode(), "root_path": "",
             "headers": headers, "client": (client, 40000), "server": ("mock-oidc", 10090)}
    sent = [{"type": "http.request", "body": body, "more_body": False}]
    out = {"status": 0, "headers": {}, "body": b""}

    async def receive():
        if sent:
            return sent.pop(0)
        await asyncio.sleep(3600)

    async def send(msg):
        if msg["type"] == "http.response.start":
            out["status"] = msg["status"]
            for k, v in msg.get("headers", []):
                out["headers"].setdefault(k.decode().lower(), []).append(v.decode())
        elif msg["type"] == "http.response.body":
            out["body"] += msg.get("body", b"")

    await mod.app(scope, receive, send)
    return out["status"], out["headers"], out["body"].decode("utf-8", "replace")


def call(mod, method, path, client=OUTSIDE, form=None, js=None, cookie=None, auth=None):
    return asyncio.run(_call(mod, method, path, client, form, js, cookie, auth))


def many(mod, reqs):
    async def run():
        return await asyncio.gather(*(_call(mod, *r) for r in reqs))
    return asyncio.run(run())


def seed(mod, client):
    call(mod, "POST", "/api/users", client, js=dict(sub="mock-admin", email="admin@example.test", name="Alex Admin"), auth=BEARER)
    call(mod, "PUT", "/api/clients/mock-oidc-client/redirect_uris", client, js=dict(redirect_uris=[REDIR]), auth=BEARER)


def cookie_from(hs):
    return (hs.get("set-cookie") or [""])[0].split(";")[0]


# ---------------------------------------------------------------- local development: as before
m = load()
seed(m, OUTSIDE)
st, hs, body = call(m, "GET", "/api/users", OUTSIDE)
check("local mode: the admin API answers another address (as before)", st == 200 and "mock-admin" in body, st)
st, hs, body = call(m, "GET", "/authorize?" + QS)
check("local mode: the sign-in page lists the pretend people (as before)", st == 200 and "Alex Admin" in body, st)
st, hs, _ = call(m, "GET", "/authorize?" + QS + "&login_hint=mock-admin")
check("local mode: login_hint signs in at once (as before)", st == 302 and hs["location"][0].startswith(REDIR + "?code="))

# ---------------------------------------------------------------- cluster mode: the admin API from this machine only
m = load(MOCK_OIDC_REQUIRE_ACCESS_CODE="true", MOCK_OIDC_ACCESS_CODE=CODE)
ADMIN = [("GET", "/api/users", None), ("POST", "/api/users", dict(sub="x", email="x@example.test", name="X")),
         ("DELETE", "/api/users/mock-admin", None), ("PUT", "/api/clients/mock-oidc-client/redirect_uris", dict(redirect_uris=["https://evil.example/cb"])),
         ("GET", "/docs", None), ("GET", "/openapi.json", None), ("GET", "/redoc", None),
         ("GET", "/api/users/", None), ("GET", "//api/users", None), ("GET", "/authorize/../api/users", None)]
refused = [(meth, p, call(m, meth, p, OUTSIDE, js=js, auth=BEARER)[0]) for meth, p, js in ADMIN]
check("cluster mode: the admin API, the API docs and look-alike paths answer 403 to another address, even with the secret",
      all(s == 403 for _, _, s in refused), refused)
for label, auth in (("no token", None), ("a wrong token", "Bearer wrong-" + SECRET), ("the secret without Bearer", SECRET),
                    ("lower-case bearer and the secret plus a space", "bearer " + SECRET + " ")):
    refused = [(meth, p, call(m, meth, p, LOCAL, js=js, auth=auth)[0]) for meth, p, js in ADMIN]
    check("cluster mode: from this machine with %s, the admin API and docs answer 403 (a same-pod proxy is no way in)" % label,
          all(s == 403 for _, _, s in refused), refused)
for who in (LOCAL, "::1"):
    st, _, _ = call(m, "POST", "/api/users", who, js=dict(sub="mock-admin", email="admin@example.test", name="Alex Admin"), auth=BEARER)
    st2, _, body = call(m, "GET", "/api/users", who, auth=BEARER)
    check("cluster mode: the admin API works from this machine (%s) with the client secret as its bearer token, as the start-up hook calls it" % who,
          st == 200 and st2 == 200 and "mock-admin" in body, (st, st2))
call(m, "PUT", "/api/clients/mock-oidc-client/redirect_uris", LOCAL, js=dict(redirect_uris=[REDIR]), auth=BEARER)
st, _, body = call(m, "GET", "/api/users", LOCAL, auth=BEARER)
check("cluster mode: the refused calls from outside changed nothing", [u["sub"] for u in json.loads(body)] == ["mock-admin"], body)
md = load(MOCK_OIDC_REQUIRE_ACCESS_CODE="true", MOCK_OIDC_ACCESS_CODE=CODE, MOCK_OIDC_CLIENT_SECRET="mock-oidc-secret")
check("cluster mode with the scaffold's default client secret: the admin API stays shut, even from this machine with it",
      call(md, "GET", "/api/users", LOCAL, auth="Bearer mock-oidc-secret")[0] == 403)
tree0 = ast.parse(open(SRC).read())
mw = next((ast.unparse(n) for n in ast.walk(tree0) if isinstance(n, ast.AsyncFunctionDef) and n.name == "_cluster_admin_only"), "")
check("the admin token is compared in constant time (hmac.compare_digest)", "compare_digest" in mw, mw[:200])
public = [(p, call(m, "GET", p, OUTSIDE)[0]) for p in ("/health", "/.well-known/openid-configuration", "/jwks")]
check("cluster mode: the public routes answer another address", all(s == 200 for _, s in public), public)

# ---------------------------------------------------------------- the access code
st, hs, body = call(m, "GET", "/authorize?" + QS)
check("the sign-in page asks for the code and lists no one", st == 200 and "access_code" in body and "Alex Admin" not in body)
check("the code page says the code is remembered for 15 minutes", "remembered for 15 minutes" in body)
for k, want in (("x-frame-options", "DENY"), ("referrer-policy", "no-referrer"), ("cache-control", "no-store")):
    check("the code page sends %s: %s" % (k, want), hs.get(k) == [want], hs.get(k))
csp = (hs.get("content-security-policy") or [""])[0]
check("the code page's Content-Security-Policy allows nothing but its own inline styles and forms",
      "default-src 'none'" in csp and "frame-ancestors 'none'" in csp and "form-action 'self'" in csp and "script-src" not in csp, csp)
st, hs, body = call(m, "GET", "/authorize?" + QS + "&login_hint=mock-admin")
check("login_hint is no way round the code", st == 200 and "access_code" in body and "location" not in hs)
st, _, _ = call(m, "POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client"))
check("picking a person without the code is refused", st == 403, st)

t0 = time.monotonic()
wrong = many(m, [("POST", "/authorize", who, dict(access_code="wrong-%d" % i, return_query=QS), None, None)
                 for i, who in enumerate([OUTSIDE] * 20)])
took = time.monotonic() - t0
check("20 wrong codes are each refused (401, no cookie)", all(s == 401 and "set-cookie" not in h for s, h, _ in wrong))
check("wrong codes wait without holding up each other (20 at once took %.1f s, under 5)" % took, took < 5)
for who in (OUTSIDE, "10.42.0.99"):
    st, hs, _ = call(m, "POST", "/authorize", who, form=dict(access_code=CODE, return_query=QS))
    check("after 20 wrong codes the right one is still accepted (from %s): no lock-out" % who,
          st == 303 and "set-cookie" in hs, st)
ck = hs["set-cookie"][0].lower()
check("the right code is remembered in a cookie: HttpOnly, SameSite=Lax, Secure (https), for /authorize only, 15 minutes",
      all(x in ck for x in ("httponly", "samesite=lax", "secure", "path=/authorize", "max-age=900")) and CODE.lower() not in ck, ck)
cookie = cookie_from(hs)
st, hs, body = call(m, "GET", "/authorize?" + QS, cookie=cookie)
check("with the cookie the sign-in page lists the people", st == 200 and "Alex Admin" in body)
csp = (hs.get("content-security-policy") or [""])[0]
check("the people page sends the same headers, and its form may go on only to the app's return address",
      hs.get("x-frame-options") == ["DENY"] and hs.get("cache-control") == ["no-store"]
      and "form-action 'self' https://app.example.test" in csp and "frame-ancestors 'none'" in csp, (hs.get("x-frame-options"), csp))
st, hs, _ = call(m, "POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client", state="s"), cookie=cookie)
check("with the cookie a person signs in: 302 to the app's return address with a code",
      st == 302 and hs["location"][0].startswith(REDIR + "?code="), st)
forged = "mock_oidc_access=%d.%s" % (int(time.time()) + 600, "0" * 64)
st, _, _ = call(m, "POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client"), cookie=forged)
check("a forged cookie is refused", st == 403, st)
m2 = load(MOCK_OIDC_REQUIRE_ACCESS_CODE="true", MOCK_OIDC_ACCESS_CODE=CODE)
check("the cookie's signing key is new on every start (never a fixed value)", m._access_key != m2._access_key)
st, _, _ = call(m2, "GET", "/authorize?" + QS, cookie=cookie)
seed(m2, LOCAL)
st, _, body = call(m2, "GET", "/authorize?" + QS, cookie=cookie)
check("a cookie from before a restart is refused", "access_code" in body and "Alex Admin" not in body)
check("the code is never in mock-oidc's own output", CODE not in m.startup_output)

tree = ast.parse(open(SRC).read())
plain = [n.lineno for n in ast.walk(tree) if isinstance(n, ast.Compare)
         and any(isinstance(x, ast.Name) and x.id == "ACCESS_CODE" for x in [n.left] + n.comparators)]
fns = {n.name: ast.unparse(n) for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
check("the code and the cookie are compared in constant time (hmac.compare_digest), never with == or !=",
      not plain and "compare_digest" in fns.get("_check_code", "") and "compare_digest" in fns.get("_has_access", ""),
      "plain compare at line(s) %s" % plain)
check("nothing counts wrong codes (no lock-out)", "_access_fails" not in open(SRC).read() and "Too many" not in open(SRC).read())

# ---------------------------------------------------------------- not set up: a plain page, never a crash or a 500
for label, code in (("no code", None), ("a code under 16 characters", "short-code-1234"), ("only spaces", " " * 20),
                    ("one repeated character", "a" * 20)):
    env = dict(MOCK_OIDC_REQUIRE_ACCESS_CODE="true")
    if code is not None:
        env["MOCK_OIDC_ACCESS_CODE"] = code
    m = load(**env)
    seed(m, LOCAL)
    st, hs, body = call(m, "GET", "/authorize?" + QS)
    st2, _, _ = call(m, "POST", "/authorize", form=dict(access_code=code or "x", return_query=QS))
    st3, _, _ = call(m, "POST", "/token", form=dict(grant_type="authorization_code", code="c", redirect_uri=REDIR,
                                                    client_id="mock-oidc-client", client_secret="test-only"))
    sth, _, _ = call(m, "GET", "/health")
    std, _, _ = call(m, "GET", "/.well-known/openid-configuration")
    out = m.startup_output
    check("cluster mode, %s: the sign-in page says it isn't set up yet (503, plain words), nobody signs in" % label,
          st == 503 and "isn't set up yet" in body and "DevOps" in body and st2 == 503 and st3 == 503, (st, st2, st3))
    check("cluster mode, %s: it still answers its health check and the app's sign-in button (so people see that page)" % label,
          sth == 200 and std == 200, (sth, std))
    check("cluster mode, %s: a plain line at start says why, without the code" % label,
          "isn't set up" in out and (code is None or code.strip() == "" or code not in out), out)

# ---------------------------------------------------------------- what turns cluster mode on
for value, on in (("true", True), ("1", True), ("yes", True), ("TRUE", True), ("on", True), ("enabled", True),
                  ("", False), ("false", False), ("0", False), ("no", False)):
    m = load(MOCK_OIDC_REQUIRE_ACCESS_CODE=value)
    check("MOCK_OIDC_REQUIRE_ACCESS_CODE=%r: cluster mode %s" % (value, "on" if on else "off"), m.CLUSTER is on)

print("RESULT: %s" % ("FAIL (%d)" % len(failed) if failed else "ok"))
sys.exit(1 if failed else 0)
