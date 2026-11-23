#!/usr/bin/env bash
# E12-S15 (task 3): sign-in works on the test copy on the cluster, and /argo-it says what sign-in will do.
# The baseline and both task-2 runs on the test bed signed nobody in: the manifests pointed the backend at a mock
# sign-in that was never deployed, and copied compose's local addresses (or translated them, by judgement: two
# readers, two readings). Contract these checks pin, read out of argo-it.md:
#   - the address rule: three rules and one table, so every address-valued compose setting of make-it's scaffolds
#     (fastapi-nextjs, nextjs-fullstack) is decided by text, never by judgement; browser addresses become the app's
#     public address, server addresses the service's cluster address, sign-in settings for the organisation's
#     sign-in and for the live version are secret references;
#   - the live version (env/prod) never names the practice sign-in: its image, Service, address or route, in any
#     column of the table or in the Ingress as the text says to write it for env/prod;
#   - the practice sign-in's manifest (env/dev only): its addresses from the hostname, its client secret a secret
#     reference, no literal secret, and a start-up hook that registers the app's return address through the
#     scaffold's own mock-oidc: run here against the real mock-oidc app, the sign-in page refuses the return address
#     before the hook and shows after it, and the address the browser is sent to is the app's public address;
#   - each app service's Service is named as its compose service, so the front end's built-in backend address works;
#   - the sign-in question (one select, practice by default with mock-oidc, says plainly what it exposes) and the
#     sentence the person hears for each pick, at the send ask and in the report.
# A model, not a cluster: the test bed's acceptance run is where sign-in is shown to work.
# Usage: test-argo-it-signin-on-the-cluster.sh [ARGO_IT_MD]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
DOC="${1:-$root/.claude/commands/argo-it.md}"
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT
fail=0
python3 -I - "$DOC" "$root" <<'PY' || fail=1
import os, re, socket, subprocess, sys, tempfile, time, urllib.error, urllib.parse, urllib.request
try:
    import yaml
except ImportError:
    print("FAIL PyYAML is needed (pip install pyyaml)"); sys.exit(1)
doc_path, root = sys.argv[1:]
doc = open(doc_path, encoding="utf-8").read()
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        for l in str(why).splitlines()[:10]:
            print("  " + l)
flat = lambda t: re.sub(r"\s+", " ", t)
HOST, PHOST, APP = "bedapp.example.test", "bedapp-live.example.test", "bedapp"
def fill(t):
    return (t.replace("{prod_hostname}", PHOST).replace("{hostname}", HOST).replace("{app}", APP)
             .replace("{registry}/{image_base_path}", "registry.example.test/team/bedapp").replace("{tag}", "sha-0123456")
             .replace("{backend_compose_service}", "backend").replace("{frontend_compose_service}", "frontend")
             .replace("{backend_port}", "8000").replace("{frontend_port}", "3000").replace("{tls_secret_name}", "bedapp-tls"))

# ---------- the address rule ----------
sec = doc.split("### Addresses in the app's settings (the address rule)", 1)
check("PHASE 2 states the address rule", len(sec) == 2)
rule = sec[1].split("\n### ", 1)[0] if len(sec) == 2 else ""
F = flat(rule)
for phrase in ("names another service of the Compose file", "keep it as it is",
               "names `localhost` or `127.0.0.1` with a port one of the app's own services publishes",
               "**The browser**", "the app's public address, `https://{hostname}`", "**A server**",
               "ask one select naming the variable and the two readings", "copy it as is, and list it in the report under \"copied as is\""):
    check("the address rule says: %s" % phrase, phrase in F)
TABLE = {}
for l in rule.splitlines():
    m = re.match(r"\|\s*`([A-Z_]+)`\s*\(([^)]*)\)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|", l)
    if m:
        v, svc, readby, dp, do, pr = (x.strip() for x in m.groups())
        TABLE[v] = dict(services=[x.strip() for x in svc.split(",")], readby=readby, dev_practice=dp, dev_org=do, prod=pr)
check("the address rule has its table", len(TABLE) >= 8, "rows: %s" % sorted(TABLE))

# every address-valued setting of each scaffold's deployed services is decided by text
def dflt(v):
    return re.sub(r"\$\{[A-Z_][A-Z0-9_]*(?::?-([^}]*))?\}", lambda x: x.group(1) or "", str(v))
undecided = []
for sc in ("fastapi-nextjs", "nextjs-fullstack"):
    comp = yaml.safe_load(open(os.path.join(root, ".claude/make-it/scaffolds", sc, "docker-compose.yml")))["services"]
    names = set(comp)
    for svc, d in comp.items():
        deployed = d.get("build") and (not svc.startswith("mock-") or svc == "mock-oidc")
        if not deployed:
            continue
        env = d.get("environment") or {}
        env = dict(x.split("=", 1) for x in env if "=" in x) if isinstance(env, list) else env
        for k, v in env.items():
            v = re.sub(r"\[[A-Z_]+\]", "1", dflt(v))   # the scaffold's own [PLACEHOLDERS] stand for a port or a name
            if k == "DATABASE_URL" or not re.match(r"^(https?://|[\w.-]+:\d+$)", v):
                continue
            host = urllib.parse.urlparse(v if "://" in v else "x://" + v).hostname
            if k in TABLE or (host in names and host not in ("localhost", "127.0.0.1")):
                continue
            undecided.append("%s: %s=%s (%s)" % (sc, k, v, svc))
check("every address in the scaffolds' compose settings is decided by the rule or its table", not undecided, "\n".join(undecided))
bad = [v for v, r in TABLE.items() if r["readby"].startswith("the browser") and not all(
       c.startswith("`https://{") or "secret" in c or "not generated" in c or "never" in c for c in (r["dev_practice"], r["dev_org"], r["prod"]))]
check("every address the browser reads becomes the app's public address (or a sign-in secret)", not bad, bad)
live = [v for v, r in TABLE.items() if re.search(r"mock-oidc|localhost|127\.0\.0\.1|practice|10090", r["prod"]) and "never" not in r["prod"]]
check("the live version's column never names the practice sign-in, its address or this computer", not live, live)
sec_rows = [v for v in ("OIDC_ISSUER_URL", "OIDC_EXTERNAL_URL", "OIDC_CLIENT_ID", "OIDC_CLIENT_SECRET")
            if v not in TABLE or "secret `{app}-oidc-prod`" not in TABLE[v]["prod"] or "secret `{app}-oidc-dev`" not in TABLE[v]["dev_org"]]
check("the organisation's sign-in settings, on the test copy and the live version, are secret references", not sec_rows, sec_rows)
check("the sign-in client secret is a secret reference in every column",
      all("secret" in TABLE.get("OIDC_CLIENT_SECRET", {}).get(c, "") for c in ("dev_practice", "dev_org", "prod")))

# ---------- the Service names and the front end's built-in backend address ----------
svc_t = re.search(r"### \{service\}-service\.yaml \(Service\).*?```yaml\n(.*?)```", doc, re.S)
check("each app service's Service is named as its compose service ({compose_service})",
      svc_t is not None and "name: {compose_service}" in svc_t.group(1))
fe_dock = open(os.path.join(root, ".claude/make-it/scaffolds/fastapi-nextjs/frontend/Dockerfile")).read()
baked = re.search(r"BACKEND_INTERNAL_URL=http://([\w-]+):(\d+)", fe_dock)
check("the front end's built-in backend address names the backend's compose service, and the table keeps it",
      baked and baked.group(1) == "backend" and TABLE.get("BACKEND_INTERNAL_URL", {}).get("prod") == "`http://backend:8000`")

# ---------- the Ingress: the sign-in page route is dev-only, and the live version never gets it ----------
ing = re.search(r"\*\*Split-service ingress \(when frontend \+ backend detected.*?```yaml\n(.*?)```", doc, re.S)
def for_prod(text):
    """The text says to leave the lines under a 'Practice sign-in, env/dev only' comment out of env/prod."""
    out, skip = [], False
    for l in text.splitlines():
        if "Practice sign-in, env/dev only" in l:
            skip = True
            continue
        if skip and (re.match(r"\s*#", l) or re.match(r"\s{7,}\S", l) and not re.match(r"\s*- path:", l)):
            continue
        if skip and re.match(r"\s*- path: /authorize", l):
            continue
        skip = False
        out.append(l)
    return "\n".join(out)
if ing:
    dev = fill(ing.group(1)); prod = fill(for_prod(ing.group(1))).replace(HOST, PHOST)
    dd, pd = yaml.safe_load(dev), yaml.safe_load(prod)
    paths = lambda d: [(p["path"], p["backend"]["service"]["name"]) for p in d["spec"]["rules"][0]["http"]["paths"]]
    check("the test copy's Ingress routes the sign-in page (/authorize) to the practice sign-in, before the front end",
          ("/authorize", "mock-oidc") in paths(dd) and paths(dd)[-1][0] == "/", paths(dd))
    check("the live version's Ingress, written as the text says, never routes to the practice sign-in",
          not any("mock-oidc" in n or p == "/authorize" for p, n in paths(pd)) and "mock-oidc" not in prod, paths(pd))
    check("the Ingress sends /api/ to the backend's compose-named Service", ("/api/", "backend") in paths(dd), paths(dd))
else:
    check("the split-service Ingress template is there", False)
for phrase in ("`env/prod/` never holds this file, the `mock-oidc` image, Service or address, or the `/authorize` route",
               "NEVER put the practice sign-in in `env/prod/`"):
    check("the text refuses the practice sign-in in env/prod: %s" % phrase[:60], phrase in flat(doc))

# ---------- the practice sign-in's manifest ----------
mt = re.search(r"### mock-oidc\.yaml \(the practice sign-in.*?```yaml\n(.*?)```", doc, re.S)
check("PHASE 2 has the practice sign-in's manifest (env/dev only)", mt is not None)
if mt:
    docs = list(yaml.safe_load_all(fill(mt.group(1))))
    dep = next((d for d in docs if d and d.get("kind") == "Deployment"), {})
    svc = next((d for d in docs if d and d.get("kind") == "Service"), {})
    c = (dep.get("spec", {}).get("template", {}).get("spec", {}).get("containers") or [{}])[0]
    env = {e["name"]: e for e in c.get("env", [])}
    val = lambda k: env.get(k, {}).get("value")
    check("its Deployment and Service are named mock-oidc (the address the app's server already uses)",
          dep.get("metadata", {}).get("name") == "mock-oidc" and svc.get("metadata", {}).get("name") == "mock-oidc")
    check("the browser's address of it is the app's public address; the server's is its Service",
          val("MOCK_OIDC_EXTERNAL_BASE_URL") == "https://" + HOST and val("MOCK_OIDC_INTERNAL_BASE_URL") == "http://mock-oidc:10090")
    check("its client secret is a secret reference, and no literal secret is in the manifest",
          "secretKeyRef" in str(env.get("MOCK_OIDC_CLIENT_SECRET", {})) and "mock-oidc-secret" not in mt.group(1))
    check("its image is the workflow's own, by the commit's tag", c.get("image") == "registry.example.test/team/bedapp/mock-oidc:sha-0123456", c.get("image"))
    hook = (((c.get("lifecycle") or {}).get("postStart") or {}).get("exec") or {}).get("command") or []
    check("a start-up hook registers the return address from its settings, with an isolated python",
          hook[:3] == ["python3", "-I", "-c"] and val("MOCK_OIDC_REDIRECT_URIS") == "https://%s/api/auth/callback" % HOST)
    # the hook against the real mock-oidc
    mock = os.path.join(root, ".claude/make-it/scaffolds/fastapi-nextjs/mock-services/mock-oidc")
    s_ = socket.socket(); s_.bind(("127.0.0.1", 0)); port = s_.getsockname()[1]; s_.close()
    menv = dict(os.environ, MOCK_OIDC_PORT=str(port), MOCK_OIDC_EXTERNAL_BASE_URL=val("MOCK_OIDC_EXTERNAL_BASE_URL") or "",
                MOCK_OIDC_INTERNAL_BASE_URL="http://127.0.0.1:%d" % port, MOCK_OIDC_CLIENT_ID=val("MOCK_OIDC_CLIENT_ID") or "",
                MOCK_OIDC_CLIENT_SECRET="test-only-value", MOCK_OIDC_REDIRECT_URIS=val("MOCK_OIDC_REDIRECT_URIS") or "")
    srv = subprocess.Popen([sys.executable, "-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", str(port)],
                           cwd=mock, env=menv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        up = False
        for _ in range(100):
            try:
                urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=1); up = True; break
            except Exception:
                time.sleep(0.2)
        if not up:
            check("the scaffold's mock-oidc starts here (fastapi, uvicorn, PyJWT, cryptography, python-multipart)", False,
                  srv.stderr.read1(2000).decode() if srv.poll() is not None else "no answer on /health")
        else:
            q = urllib.parse.urlencode(dict(client_id=val("MOCK_OIDC_CLIENT_ID"), redirect_uri=val("MOCK_OIDC_REDIRECT_URIS"),
                                            response_type="code", state="s"))
            def authorize():
                try:
                    return urllib.request.urlopen("http://127.0.0.1:%d/authorize?%s" % (port, q), timeout=5).status
                except urllib.error.HTTPError as e:
                    return e.code
            before = authorize()
            h = subprocess.run(hook, env=menv, capture_output=True, text=True, timeout=90)
            after = authorize()
            check("the sign-in page refuses the app's return address before the hook (%d) and shows after it (%d)" % (before, after),
                  before == 400 and h.returncode == 0 and after == 200, h.stderr[-300:])
            disc = __import__("json").load(urllib.request.urlopen("http://127.0.0.1:%d/.well-known/openid-configuration" % port, timeout=5))
            check("the browser is sent to the app's public address for the sign-in page",
                  disc.get("authorization_endpoint") == "https://%s/authorize" % HOST, disc.get("authorization_endpoint"))
    finally:
        srv.terminate(); srv.wait(10)

# ---------- the question and the sentence the person hears ----------
q = flat(doc.split("**Sign-in** (only if the app signs people in", 1)[-1].split("**Split-service ingress**", 1)[0]) \
    if "**Sign-in** (only if the app signs people in" in doc else ""
for phrase in ("**The practice sign-in**", "**Your organisation's sign-in**", "a list of pretend people, no passwords",
               "an administrator included", "can't be reached from the internet", "never the practice one",
               "Default, and the recommended option: **The practice sign-in** when docker-compose.yml has a `mock-oidc` service"):
    check("the sign-in question says: %s" % phrase[:70], phrase in q)
say = flat(doc.split("### What sign-in will do", 1)[-1].split("\n### ", 1)[0]) if "### What sign-in will do" in doc else ""
for phrase in ("uses the practice sign-in: a list of pretend people, no passwords. Anyone who can open {hostname} can sign in as any of them, an administrator included",
               "The live version never uses it",
               "uses your organisation's sign-in, and it isn't set up yet",
               "people can open the app but can't sign in"):
    check("the sentence the person hears says: %s" % phrase[:70], phrase in say)
p5 = doc.split("<!-- PHASE 5: DEPLOY", 1)[-1]
check("the send ask and the report both say the sign-in sentence",
      p5.count('sign-in sentence from PHASE 2 "What sign-in will do"') >= 2)
sys.exit(1 if failed else 0)
PY
[ -s "$ERRF" ] && { echo "FAIL stderr was written (shown below)"; fail=1; }
exit $fail
