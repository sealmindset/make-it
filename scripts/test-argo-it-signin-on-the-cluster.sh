#!/usr/bin/env bash
# E12-S15 (task 3): sign-in works on the test copy on the cluster, /argo-it says what sign-in will do, and the
# practice sign-in is guarded by an access code (owner, 2026-11-23).
# Contract these checks pin, read out of argo-it.md and the scaffolds' mock-oidc:
#   - mock-oidc (both scaffolds, the same code): with no access code it behaves as before (local development);
#     with one, its sign-in page asks for the code first (no names, login_hint no way round it), a wrong code is
#     refused and counted (a small in-memory limit), a right one is remembered in a signed HttpOnly, SameSite=Lax,
#     Secure-over-https cookie scoped to /authorize, a pick without it is refused, the code is never logged; in
#     cluster mode it refuses to start without a code of 16+ characters, saying so without the code;
#   - the practice sign-in's manifest (env/dev only): addresses from the hostname, every secret a reference, cluster
#     mode, non-root, no privilege escalation, read-only root filesystem, resources; its start-up hook loads the
#     pretend people from scripts/seed-mock-services.sh (their single source) and registers the return address --
#     run here against the real mock-oidc: a seeded person signs in through the code and gets the 302 to the
#     callback; a NetworkPolicy lets only the backend and the ingress controller reach it;
#   - the address rule and its table decide every address-valued compose setting of both scaffolds; the live
#     version's column never names the practice sign-in and always turns ENFORCE_SECRETS on;
#   - the live version never gets the practice sign-in: not in its kustomization, its Ingress or IngressRoute as the
#     text says to write them, its table column, or any literal secret; the text refuses it and checks for it;
#   - the question (offered only for a split-service app whose mock-oidc reads an access code and whose people are in
#     the seed script; re-read on a re-run) and the sentences the person hears, true to what is generated;
#   - the redeploy's setting check (5b step 3b) follows the address rule and skips the practice sign-in;
#   - the text leaves no second reading of its placeholders, the database answer, ONBOARDING's registration and
#     pull secret, the existing-workflow rule, the init container and the "to do" form.
# A model, not a cluster: the test bed's acceptance run is where sign-in is shown to work.
# Usage: test-argo-it-signin-on-the-cluster.sh [ARGO_IT_MD] [MOCK_OIDC_DIR]
# MOCK_OIDC_PYTHON: the python that runs mock-oidc (CI: a venv with mock-oidc's own pinned requirements).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
DOC="${1:-$root/.claude/commands/argo-it.md}"
MOCK="${2:-$root/.claude/make-it/scaffolds/fastapi-nextjs/mock-services/mock-oidc}"
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT
fail=0
python3 -I - "$DOC" "$root" "$MOCK" <<'PY' || fail=1
import http.client, json, os, re, shutil, socket, subprocess, sys, tempfile, time, urllib.parse, urllib.request
try:
    import yaml
except ImportError:
    print("FAIL PyYAML is needed (pip install pyyaml)"); sys.exit(1)
doc_path, root, MOCK = sys.argv[1:]
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
F = flat(doc)
HOST, PHOST, APP = "bedapp.example.test", "bedapp-live.example.test", "bedapp"
def fill(t):
    return (t.replace("{prod_hostname}", PHOST).replace("{hostname}", HOST).replace("{app}", APP)
             .replace("{registry}/{image_base_path}", "registry.example.test/team/bedapp").replace("{tag}", "sha-0123456")
             .replace("{backend_compose_service}", "backend").replace("{frontend_compose_service}", "frontend")
             .replace("{backend_port}", "8000").replace("{frontend_port}", "3000").replace("{tls_secret_name}", "bedapp-tls")
             .replace("{ingress_controller_namespace}", "kube-system").replace("{namespace}", "bedapp"))
def fence_after(heading_re):
    m = re.search(heading_re + r".*?```yaml\n(.*?)```", doc, re.S)
    return m.group(1) if m else None
def says(label, phrase):
    check("the text says (%s): %s" % (label, phrase[:72]), flat(phrase) in F)

# ======================================================================= mock-oidc itself
other = os.path.join(root, ".claude/make-it/scaffolds/nextjs-fullstack/mock-services/mock-oidc/app.py")
a, b = open(os.path.join(MOCK, "app.py")).read(), open(other).read()
strip = lambda t: re.sub(r'CLIENT_ID: \{"redirect_uris": \[.*?\]\},', "", t, flags=re.S)
check("both scaffolds carry the same mock-oidc code (only the built-in return addresses differ)", strip(a) == strip(b))
PYEXE = os.environ.get("MOCK_OIDC_PYTHON") or sys.executable
def free_port():
    s_ = socket.socket(); s_.bind(("127.0.0.1", 0)); p = s_.getsockname()[1]; s_.close(); return p
class Mock:
    def __init__(self, extra, port=None):
        self.port = port or free_port()
        self.env = dict(os.environ, MOCK_OIDC_PORT=str(self.port), MOCK_OIDC_EXTERNAL_BASE_URL="https://" + HOST,
                        MOCK_OIDC_INTERNAL_BASE_URL="http://127.0.0.1:%d" % self.port, MOCK_OIDC_CLIENT_ID="mock-oidc-client",
                        MOCK_OIDC_CLIENT_SECRET="test-only-client-value")
        for k in ("MOCK_OIDC_ACCESS_CODE", "MOCK_OIDC_REQUIRE_ACCESS_CODE"):
            self.env.pop(k, None)
        self.env.update(extra)
        self.log = tempfile.TemporaryFile()
        self.p = subprocess.Popen([PYEXE, "-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", str(self.port)],
                                  cwd=MOCK, env=self.env, stdout=self.log, stderr=subprocess.STDOUT)
        self.up = False
        for _ in range(100):
            if self.p.poll() is not None:
                break
            try:
                urllib.request.urlopen("http://127.0.0.1:%d/health" % self.port, timeout=1); self.up = True; break
            except Exception:
                time.sleep(0.2)
    def req(self, method, path, form=None, cookie=None, js=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        h = {}
        body = None
        if form is not None:
            body = urllib.parse.urlencode(form); h["Content-Type"] = "application/x-www-form-urlencoded"
        if js is not None:
            body = json.dumps(js); h["Content-Type"] = "application/json"
        if cookie:
            h["Cookie"] = cookie
        c.request(method, path, body=body, headers=h)
        r = c.getresponse()
        return r.status, r.getheaders(), r.read().decode("utf-8", "replace")
    def output(self):
        self.log.seek(0); return self.log.read().decode("utf-8", "replace")
    def stop(self):
        if self.p.poll() is None:
            self.p.terminate(); self.p.wait(10)
REDIR = "https://%s/api/auth/callback" % HOST
QS = urllib.parse.urlencode(dict(client_id="mock-oidc-client", redirect_uri=REDIR, response_type="code", state="s"))
def seed(m, people=(("mock-admin", "admin@example.test", "Alex Admin"),)):
    for sub, email, name in people:
        m.req("POST", "/api/users", js=dict(sub=sub, email=email, name=name))
    m.req("PUT", "/api/clients/mock-oidc-client/redirect_uris", js=dict(redirect_uris=[REDIR]))
hdr = lambda hs, k: [v for n, v in hs if n.lower() == k]

# --- local development: no code, as before
m = Mock({})
try:
    check("local mode: mock-oidc starts with no access code (as before)", m.up, m.output()[-300:])
    if m.up:
        seed(m)
        st, hs, body = m.req("GET", "/authorize?" + QS)
        check("local mode: the sign-in page lists the pretend people (as before)", st == 200 and "Alex Admin" in body)
        st, hs, _ = m.req("GET", "/authorize?" + QS + "&login_hint=mock-admin")
        check("local mode: login_hint signs in at once (as before)", st == 302 and hdr(hs, "location")[0].startswith(REDIR))
        st, hs, _ = m.req("POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client", state="s"))
        check("local mode: picking a person signs in (as before)", st == 302 and hdr(hs, "location")[0].startswith(REDIR + "?code="))
finally:
    m.stop()

# --- cluster mode: refuses to start without a long-enough code, and never prints the code
SHORT = "short-code-1234"
m = Mock({"MOCK_OIDC_REQUIRE_ACCESS_CODE": "true", "MOCK_OIDC_ACCESS_CODE": SHORT})
try:
    time.sleep(1)
    out = m.output()
    check("cluster mode: with a code under 16 characters it refuses to start, in a plain line without the code",
          not m.up and m.p.poll() not in (None, 0) and "not starting" in out and SHORT not in out, out[-300:])
finally:
    m.stop()
m = Mock({"MOCK_OIDC_REQUIRE_ACCESS_CODE": "true"})
try:
    time.sleep(1)
    check("cluster mode: with no code it refuses to start", not m.up and m.p.poll() not in (None, 0))
finally:
    m.stop()

# --- with a code
CODE = "right-code-0123456789"
m = Mock({"MOCK_OIDC_REQUIRE_ACCESS_CODE": "true", "MOCK_OIDC_ACCESS_CODE": CODE})
try:
    check("with a code: it starts", m.up, m.output()[-300:])
    if m.up:
        seed(m)
        st, hs, body = m.req("GET", "/authorize?" + QS)
        check("with a code: the sign-in page asks for the code and lists no one", st == 200 and "access_code" in body and "Alex Admin" not in body)
        st, hs, body = m.req("GET", "/authorize?" + QS + "&login_hint=mock-admin")
        check("with a code: login_hint is no way round it", st == 200 and "access_code" in body and not hdr(hs, "location"))
        st, hs, _ = m.req("POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client"))
        check("with a code: picking a person without the code is refused", st == 403, st)
        st, hs, body = m.req("POST", "/authorize", form=dict(access_code="wrong-" + CODE, return_query=QS))
        check("with a code: a wrong code is refused, and no cookie is given", st == 401 and not hdr(hs, "set-cookie"), st)
        st, hs, _ = m.req("POST", "/authorize", form=dict(access_code=CODE, return_query=QS))
        ck = (hdr(hs, "set-cookie") or [""])[0]
        check("with a code: the right code is remembered in a cookie: HttpOnly, SameSite=Lax, Secure (https), for /authorize only",
              st == 303 and "httponly" in ck.lower() and "samesite=lax" in ck.lower() and "secure" in ck.lower()
              and "path=/authorize" in ck.lower() and CODE not in ck, ck)
        cookie = ck.split(";")[0]
        st, hs, body = m.req("GET", "/authorize?" + QS, cookie=cookie)
        check("with the cookie: the sign-in page lists the people", st == 200 and "Alex Admin" in body)
        st, hs, _ = m.req("POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client", state="s"), cookie=cookie)
        check("with the cookie: a person signs in: 302 to the app's return address with a code",
              st == 302 and hdr(hs, "location")[0].startswith(REDIR + "?code="), (st, hdr(hs, "location")))
        st, hs, _ = m.req("POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client"),
                          cookie=cookie.split("=")[0] + "=" + str(int(time.time()) + 600) + ".forged")
        check("a forged cookie is refused", st == 403, st)
        for _ in range(5):
            m.req("POST", "/authorize", form=dict(access_code="nope", return_query=QS))
        st, hs, body = m.req("POST", "/authorize", form=dict(access_code=CODE, return_query=QS))
        check("after five wrong codes, even the right one is refused for a while (in memory)", st == 401 and not hdr(hs, "set-cookie"), st)
        check("the code never appears in mock-oidc's own output", CODE not in m.output())
finally:
    m.stop()

# ======================================================================= the address rule
sec = doc.split("### Addresses in the app's settings (the address rule)", 1)
check("PHASE 2 states the address rule", len(sec) == 2)
rule = sec[1].split("\n### ", 1)[0] if len(sec) == 2 else ""
FR = flat(rule)
for phrase in ("names another service of the Compose file", "keep it as it is",
               "names `localhost` or `127.0.0.1` with a port one of the app's own services publishes",
               "**The browser**", "the app's public address, `https://{hostname}`", "**A server**",
               "ask one select naming the variable and the two readings", "copy it as is, and list it in the report under \"copied as is\""):
    check("the address rule says: %s" % phrase, phrase in FR)
TABLE = {}
for l in rule.splitlines():
    mm = re.match(r"\|\s*`([A-Z_]+)`\s*\(([^)]*)\)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|", l)
    if mm:
        v, svc, readby, dp, do, pr = (x.strip() for x in mm.groups())
        TABLE[v] = dict(readby=readby, dev_practice=dp, dev_org=do, prod=pr)
check("the address rule has its table", len(TABLE) >= 9, "rows: %s" % sorted(TABLE))
def dflt(v):
    return re.sub(r"\$\{[A-Z_][A-Z0-9_]*(?::?-([^}]*))?\}", lambda x: x.group(1) or "", str(v))
undecided = []
for sc in ("fastapi-nextjs", "nextjs-fullstack"):
    comp = yaml.safe_load(open(os.path.join(root, ".claude/make-it/scaffolds", sc, "docker-compose.yml")))["services"]
    for svc, d in comp.items():
        if not (d.get("build") and (not svc.startswith("mock-") or svc == "mock-oidc")):
            continue
        env = d.get("environment") or {}
        env = dict(x.split("=", 1) for x in env if "=" in x) if isinstance(env, list) else env
        for k, v in env.items():
            v = re.sub(r"\[[A-Z_]+\]", "1", dflt(v))
            if k == "DATABASE_URL" or not re.match(r"^(https?://|[\w.-]+:\d+$)", v):
                continue
            host = urllib.parse.urlparse(v if "://" in v else "x://" + v).hostname
            if k in TABLE or (host in comp and host not in ("localhost", "127.0.0.1")):
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
check("the live version always turns ENFORCE_SECRETS on, whatever compose says",
      TABLE.get("ENFORCE_SECRETS", {}).get("prod", "").startswith('`"true"`'), TABLE.get("ENFORCE_SECRETS"))

# ======================================================================= Service names, the built-in backend address
svc_t = fence_after(r"### \{service\}-service\.yaml \(Service\)")
check("each app service's Service is named as its compose service ({compose_service})", svc_t is not None and "name: {compose_service}" in svc_t)
fe_dock = open(os.path.join(root, ".claude/make-it/scaffolds/fastapi-nextjs/frontend/Dockerfile")).read()
baked = re.search(r"BACKEND_INTERNAL_URL=http://([\w-]+):(\d+)", fe_dock)
check("the front end's built-in backend address names the backend's compose service, and the table keeps it",
      baked and baked.group(1) == "backend" and TABLE.get("BACKEND_INTERNAL_URL", {}).get("prod") == "`http://backend:8000`")
says("a -service convention loses to the compose name", "This wins over a `-service` naming convention found in existing manifests")

# ======================================================================= the Ingress and IngressRoute, dev and live
DEVONLY = "Practice sign-in, env/dev only"
def drop_block(text):
    """Drop the list item (and its deeper lines) that follows a 'Practice sign-in, env/dev only' comment."""
    lines, out, i = text.splitlines(), [], 0
    while i < len(lines):
        l = lines[i]
        if DEVONLY in l:
            ind = len(l) - len(l.lstrip())
            i += 1
            while i < len(lines) and lines[i].strip().startswith("#"):
                i += 1
            if i < len(lines):                       # the item itself
                i += 1
            while i < len(lines) and (len(lines[i]) - len(lines[i].lstrip())) > ind and not lines[i].lstrip().startswith("- "):
                i += 1
            while i < len(lines) and (len(lines[i]) - len(lines[i].lstrip())) > ind + 2:
                i += 1
            continue
        out.append(l); i += 1
    return "\n".join(out)
ing = fence_after(r"\*\*Split-service ingress \(when frontend \+ backend detected")
if ing:
    dd, pd = yaml.safe_load(fill(ing)), yaml.safe_load(fill(drop_block(ing)).replace(HOST, PHOST))
    paths = lambda d: [(p["path"], p["backend"]["service"]["name"]) for p in d["spec"]["rules"][0]["http"]["paths"]]
    check("the test copy's Ingress routes only /authorize to the practice sign-in, before the front end",
          [x for x in paths(dd) if x[1] == "mock-oidc"] == [("/authorize", "mock-oidc")] and paths(dd)[-1][0] == "/", paths(dd))
    check("the live version's Ingress, written as the text says, never routes to the practice sign-in",
          not any(n == "mock-oidc" or p == "/authorize" for p, n in paths(pd)), paths(pd))
    check("the Ingress sends /api/ to the backend's compose-named Service", ("/api/", "backend") in paths(dd), paths(dd))
else:
    check("the split-service Ingress template is there", False)
ir = fence_after(r"\*\*Split-service Traefik IngressRoute \(CRD\):\*\*")
if ir:
    dr, pr = yaml.safe_load(fill(ir)), yaml.safe_load(fill(drop_block(ir)).replace(HOST, PHOST))
    routes = lambda d: [(r_["match"], [x["name"] for x in r_["services"]]) for r_ in d["spec"]["routes"]]
    mock_routes = [mt for mt, names in routes(dr) if "mock-oidc" in names]
    check("the test copy's IngressRoute sends only Host && PathPrefix(`/authorize`) to the practice sign-in",
          mock_routes == ["Host(`%s`) && PathPrefix(`/authorize`)" % HOST], routes(dr))
    check("the live version's IngressRoute, written as the text says, never routes to the practice sign-in",
          not any("mock-oidc" in names or "/authorize" in mt for mt, names in routes(pr)), routes(pr))
else:
    check("the split-service IngressRoute template is there", False)
kz = fence_after(r"### kustomization\.yaml")
live_kz = [l for l in (kz or "").splitlines() if not l.strip().startswith("#") and re.search(r"mock-oidc|seed-mock-services", l)]
mock_comments = [i for i, l in enumerate((kz or "").splitlines()) if l.strip().startswith("#") and "mock-oidc" in l]
marker = next((i for i, l in enumerate((kz or "").splitlines()) if "The practice sign-in (env/dev only, only when picked)" in l), None)
check("the kustomization template never lists the practice sign-in for the live version (only under its env/dev-only note)",
      kz and not live_kz and marker is not None and all(i > marker for i in mock_comments), live_kz)
for label, phrase in (("only in env/dev", "Generate it ONLY in `env/dev/`, and only for **The practice sign-in**"),
                      ("the live version never", "`env/prod/` never holds this file, the `mock-oidc` image, Service or address, its people, its access code, or the `/authorize` route"),
                      ("the guardrail", "NEVER put the practice sign-in in `env/prod/`"),
                      ("never without its code", "NEVER run the practice sign-in on a cluster without its access code"),
                      ("the question's last line", "The live version of your app always uses your organisation's sign-in, never the practice one.")):
    says(label, phrase)
chk = re.search(r"\*\*Before PHASE 5: the live version holds no practice sign-in\.\*\*.*?```bash\n(.*?)```", doc, re.S)
check("PHASE 2 has a check that the live version holds no practice sign-in", chk is not None)
if chk:
    def run_check(files):
        d = tempfile.mkdtemp()
        for rel, txt in files.items():
            os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True); open(os.path.join(d, rel), "w").write(txt)
        r = subprocess.run(["bash", "-c", chk.group(1).replace("{manifest_dir}", "env")], cwd=d, capture_output=True, text=True)
        shutil.rmtree(d, ignore_errors=True)
        return r.returncode, r.stdout
    clean = {"env/prod/backend.yaml": "image: registry/app/backend:prod-latest\n", "env/dev/mock-oidc.yaml": "name: mock-oidc\n"}
    rc, out = run_check(clean)
    check("the live-version check passes a clean live folder (the test copy may hold the practice sign-in)", rc == 0, out)
    for label, txt in (("its image", "image: registry/app/mock-oidc:sha-1\n"), ("its address", "value: http://mock-oidc:10090\n"),
                       ("its access code", "key: PRACTICE_ACCESS_CODE\n"), ("its route", "- path: /authorize\n"),
                       ("its people", "- seed-mock-services.sh\n")):
        rc, out = run_check(dict(clean, **{"env/prod/x.yaml": txt}))
        check("the live-version check stops on %s in the live folder" % label, rc != 0 and "PRACTICE SIGN-IN IN THE LIVE VERSION" in out, out)

# ======================================================================= the practice sign-in's manifest
mt = fence_after(r"### mock-oidc\.yaml \(the practice sign-in")
check("PHASE 2 has the practice sign-in's manifest (env/dev only)", mt is not None)
LITERAL_SECRET = re.compile(r"- name: (\w*(?:SECRET|PASSWORD|TOKEN|ACCESS_CODE|_KEY)\w*)\s*\n\s*value:")
fences = re.findall(r"```yaml\n(.*?)```", doc.split('<step name="generate-manifests">', 1)[1].split("</step>", 1)[0], re.S)
lit = [m_.group(1) for f in fences for m_ in LITERAL_SECRET.finditer(f)]
check("no manifest template gives a secret, password, token, key or access code a literal value", not lit, lit)
if mt:
    docs = list(yaml.safe_load_all(fill(mt)))
    dep = next((d for d in docs if d and d.get("kind") == "Deployment"), {})
    svc = next((d for d in docs if d and d.get("kind") == "Service"), {})
    pod = dep.get("spec", {}).get("template", {}).get("spec", {})
    c = (pod.get("containers") or [{}])[0]
    env = {e["name"]: e for e in c.get("env", [])}
    val = lambda k: env.get(k, {}).get("value")
    ref = lambda k: env.get(k, {}).get("valueFrom", {}).get("secretKeyRef", {})
    check("its Deployment and Service are named mock-oidc", dep.get("metadata", {}).get("name") == "mock-oidc" and svc.get("metadata", {}).get("name") == "mock-oidc")
    check("the browser's address of it is the app's public address; the server's is its Service",
          val("MOCK_OIDC_EXTERNAL_BASE_URL") == "https://" + HOST and val("MOCK_OIDC_INTERNAL_BASE_URL") == "http://mock-oidc:10090")
    check("its client secret and its access code are secret references to bedapp-oidc-dev",
          ref("MOCK_OIDC_CLIENT_SECRET").get("name") == "bedapp-oidc-dev" and ref("MOCK_OIDC_ACCESS_CODE") == {"name": "bedapp-oidc-dev", "key": "PRACTICE_ACCESS_CODE"}
          and "mock-oidc-secret" not in mt)
    check("it runs in cluster mode (no code, no start)", val("MOCK_OIDC_REQUIRE_ACCESS_CODE") == "true")
    sc, csc = pod.get("securityContext", {}), c.get("securityContext", {})
    check("it runs as a non-root user, without privilege escalation, with a read-only root filesystem and no capabilities",
          sc.get("runAsNonRoot") is True and csc.get("allowPrivilegeEscalation") is False and csc.get("readOnlyRootFilesystem") is True
          and csc.get("capabilities", {}).get("drop") == ["ALL"], (sc, csc))
    check("it has resource requests and limits, and pulls like the app's own workloads",
          c.get("resources", {}).get("requests") and c.get("resources", {}).get("limits") and c.get("imagePullPolicy") == "Always")
    check("its image is the workflow's own, by the commit's tag", c.get("image") == "registry.example.test/team/bedapp/mock-oidc:sha-0123456", c.get("image"))
    vols = {v["name"]: v for v in pod.get("volumes", [])}
    check("its people come from a ConfigMap made from scripts/seed-mock-services.sh",
          vols.get("people", {}).get("configMap", {}).get("name") == "mock-oidc-people" and "seed-mock-services.sh" in (kz or ""))
    hook = (((c.get("lifecycle") or {}).get("postStart") or {}).get("exec") or {}).get("command") or []
    check("a start-up hook with an isolated python registers the return address from its settings",
          hook[:3] == ["python3", "-I", "-c"] and val("MOCK_OIDC_REDIRECT_URIS") == REDIR)
    # the hook against the real mock-oidc, with the scaffold's seed script as the people's file
    if len(hook) == 4:
        tmp = tempfile.mkdtemp()
        seedsrc = open(os.path.join(root, ".claude/make-it/scaffolds/fastapi-nextjs/scripts/seed-mock-services.sh")).read()
        for i, (s_, e_, n_) in enumerate((("mock-superadmin", "sa@example.test", "Sarah SuperAdmin"), ("mock-admin", "admin@example.test", "Alex Admin"),
                                          ("mock-analyst", "an@example.test", "Ana Analyst"), ("mock-viewer", "vi@example.test", "Victor Viewer")), 1):
            seedsrc = seedsrc.replace("[ROLE_%d_OIDC_SUB]" % i, s_).replace("[ROLE_%d_EMAIL]" % i, e_).replace("[ROLE_%d_DISPLAY_NAME]" % i, n_)
        open(os.path.join(tmp, "seed-mock-services.sh"), "w").write(seedsrc)
        script = hook[3].replace("/people/", tmp + "/")      # the volume's mount, here a folder
        CODE2 = "cluster-code-abcdef0123"
        m = Mock({"MOCK_OIDC_REQUIRE_ACCESS_CODE": "true", "MOCK_OIDC_ACCESS_CODE": CODE2, "MOCK_OIDC_REDIRECT_URIS": REDIR})
        try:
            if not m.up:
                check("the scaffold's mock-oidc starts here", False, m.output()[-300:])
            else:
                st0, _, _ = m.req("GET", "/authorize?" + QS)
                h = subprocess.run([PYEXE, "-I", "-c", script], env=m.env, capture_output=True, text=True, timeout=120)
                check("the hook runs: it loads the people and registers the return address", h.returncode == 0, h.stderr[-300:])
                users = json.loads(m.req("GET", "/api/users")[2])
                check("after the hook the practice sign-in holds the seed script's people (one source)",
                      [u["sub"] for u in users] == ["mock-superadmin", "mock-admin", "mock-analyst", "mock-viewer"], users)
                st, hs, _ = m.req("POST", "/authorize", form=dict(access_code=CODE2, return_query=QS))
                cookie = (hdr(hs, "set-cookie") or [""])[0].split(";")[0]
                st, hs, _ = m.req("POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client", state="s"), cookie=cookie)
                check("a seeded person signs in through the access code: 302 to the app's return address with a code",
                      st0 == 400 and st == 302 and hdr(hs, "location")[0].startswith(REDIR + "?code="), (st0, st, hdr(hs, "location")))
                disc = json.loads(m.req("GET", "/.well-known/openid-configuration")[2])
                check("the browser is sent to the app's public address for the sign-in page", disc.get("authorization_endpoint") == "https://%s/authorize" % HOST)
        finally:
            m.stop(); shutil.rmtree(tmp, ignore_errors=True)
np_ = fence_after(r"### mock-oidc-network-policy\.yaml")
if np_:
    npd = yaml.safe_load(fill(np_))
    froms = npd["spec"]["ingress"][0]["from"]
    check("a NetworkPolicy lets only the app's backend and the ingress controller reach the practice sign-in",
          npd["spec"]["podSelector"]["matchLabels"] == {"app": "mock-oidc"}
          and {"podSelector": {"matchLabels": {"app": "bedapp-backend"}}} in froms
          and {"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}}} in froms and len(froms) == 2, froms)
else:
    check("PHASE 2 has the practice sign-in's NetworkPolicy", False)

# ======================================================================= the question, the sentences, ONBOARDING
q = flat(doc.split("**Sign-in** (only if the app signs people in", 1)[-1].split("**Split-service ingress**", 1)[0])
for phrase in ("**The practice sign-in** -- pretend people, no passwords, behind an access code your DevOps team sets",
               "Anyone who has the code can sign in as any of them, an administrator included, so keep {hostname} off the internet too",
               "**Your organisation's sign-in**", "the test copy won't start until they do",
               "On a re-run, read `deployment.signin_dev` from app-context.json and use it: don't ask again",
               "the app has a separate front end and backend (split-service)",
               "its `mock-services/mock-oidc/app.py` contains `MOCK_OIDC_ACCESS_CODE` (read the file; never guess from a version)",
               "/resume-it updates it first", "the app's pretend people are in `scripts/seed-mock-services.sh`"):
    check("the sign-in question says: %s" % phrase[:72], flat(phrase) in q)
say = flat(doc.split("### What sign-in will do", 1)[-1].split("\n### ", 1)[0])
for phrase in ("pretend people, no passwords, behind an access code your DevOps team sets. Anyone who has the code can sign in as any of them, an administrator included",
               "The test copy won't start until your DevOps team adds the access code and the sign-in password",
               "The live version never uses it",
               "the app won't start until your DevOps team adds its settings, and people can't sign in until they also register {hostname} with it"):
    check("the sentence the person hears says: %s" % phrase[:72], phrase in say)
check("no sentence still claims people can open the app before the Secret exists",
      "people can open the app but can't sign in" not in F and "people can open the test copy but can't sign in" not in F)
p5 = doc.split("<!-- PHASE 5: DEPLOY", 1)[-1]
check("the send ask and the report both say the sign-in sentence", p5.count('sign-in sentence from PHASE 2 "What sign-in will do"') >= 2)
check("the settings copied as is are listed at the send ask", "These settings were copied as they are" in p5.split("**What would you like to do?**", 1)[0])
check("the report says app-context.json was left changed, and names its keys", "left it changed, not saved" in flat(p5) and "deployment.signin_dev" in p5)
for label, phrase in (("ONBOARDING: the admin routes", "Its admin routes are reachable only inside the cluster"),
                      ("ONBOARDING: the code out of band", "when you hand it to your testers -- out of band"),
                      ("ONBOARDING: never in a ticket", "never in a ticket, chat or email"),
                      ("ONBOARDING: no value in history", "--from-file=PRACTICE_ACCESS_CODE=<(openssl rand -hex 12 | tr -d '\\n')"),
                      ("ONBOARDING: the organisation's Secret", "kubectl create secret generic {app}-oidc-{env} -n {namespace}"),
                      ("ONBOARDING: the test address only for the organisation's sign-in", "only when the test copy uses your organisation's sign-in too"),
                      ("ONBOARDING: pull access follows the registry", "--docker-server={registry_host}"),
                      ("ONBOARDING: the app won't start without the Secret", "The app won't start until this Secret exists.")):
    says(label, phrase)
check("ONBOARDING no longer hard-codes ghcr.io for pull access", "--docker-server=ghcr.io" not in doc)
# ONBOARDING's sign-in commands, as generated, must pass the skill's own secret check (PHASE 5 scans every
# generated file: a hit there stops the send). Found by the bed run: `SECRET="$(...)"` read as a secret.
onb = doc.split('<step name="generate-onboarding">', 1)[-1].split("</step>", 1)[0]
cmds = "\n".join(re.findall(r"```bash\n(.*?)```", onb.split("**{app}-oidc-{env}:**", 1)[-1].split("**Option A", 1)[0], re.S))
d = tempfile.mkdtemp()
subprocess.run(["git", "init", "-q"], cwd=d)
open(os.path.join(d, "ONBOARDING-K8S.md"), "w").write(fill(cmds))
r = subprocess.run([sys.executable, "-I", os.path.join(root, ".claude/make-it/scripts/secret-scan.py")], cwd=d, capture_output=True, text=True)
shutil.rmtree(d, ignore_errors=True)
check("ONBOARDING's sign-in commands pass the skill's own secret check (else the send stops on its own file)",
      cmds.strip() and r.returncode == 0, r.stdout[-300:])

# ======================================================================= one reading only
for label, phrase in (("{app}", "`{app}` -- the app's short name"), ("{compose_service}", "`{compose_service}` -- a Compose service's own name"),
                      ("{service}", "`{service}` -- a workload's name (its Deployment, container, file and labels): `{app}-{compose_service}`"),
                      ("the workflow's names", "In this workflow `{compose_service}` is that service's Compose name"),
                      ("hostname checked", "a host name only -- letters, digits, hyphens and dots"),
                      ("compose names as DNS labels", "A Compose service name that isn't a valid DNS label"),
                      ("the database answer", "The answer is the TEST COPY's (`env/dev/`). The live version never gets an in-cluster database from it"),
                      ("existing workflows", "always create this workflow as its own new file"),
                      ("the init container", "Every env entry of the main container, as above"),
                      ("to do", "A setting the person doesn't know is written as `TODO-<what>`"),
                      ("the online home", "Where it says GitHub, read the project's online home"),
                      ("the timeout", "macOS has no `timeout` command")):
    says(label, phrase)
wf_names = re.findall(r"- name: [^\n]*\{service\}|id: meta-\{service\}|/\{service\}:", doc.split('<step name="generate-workflow">', 1)[1].split("</step>", 1)[0])
check("the workflow never uses {service} (the workload's name) where it means the compose service", not wf_names, wf_names)

# ======================================================================= apps already built: the catch-up (M05)
bs = open(os.path.join(root, ".claude/make-it/references/build-standards.md")).read()
ri = open(os.path.join(root, ".claude/commands/resume-it.md")).read()
check("build-standards has M05: an older mock-oidc is brought up to the scaffold's (read by its source)",
      re.search(r"\*\*M05\*\* \[Tier 1, 5\] \[FIX\] \*\*The practice sign-in can ask for an access code\*\*.*MOCK_OIDC_ACCESS_CODE", bs) is not None)
check("/resume-it's catch-up runs M05", "Mock Services (M01-M05)" in ri and "M05" in ri)

# ======================================================================= the redeploy's setting check (5b step 3b)
b3 = re.search(r"\*\*3b\. Cross-check env vars against K8s manifests:\*\*\n```bash\n(.*?)```(.*?)\*\*3c\.", doc, re.S)
if b3:
    d = tempfile.mkdtemp()
    open(os.path.join(d, "docker-compose.yml"), "w").write(
        "services:\n  backend:\n    environment:\n      - FRONTEND_URL=http://localhost:3100\n      - NEW_FEATURE_FLAG=on\n"
        "  mock-oidc:\n    environment:\n      - MOCK_OIDC_EXTERNAL_BASE_URL=http://localhost:10190\n")
    os.makedirs(os.path.join(d, "env/dev"))
    open(os.path.join(d, "env/dev/b.yaml"), "w").write("        env:\n          - name: FRONTEND_URL\n            value: x\n")
    r = subprocess.run(["bash", "-c", b3.group(1) + '\necho "$MISSING"'], cwd=d, capture_output=True, text=True)
    shutil.rmtree(d, ignore_errors=True)
    found = set(r.stdout.split())
    rule3b = flat(b3.group(2))
    check("3b's block, run on a fixture, flags the new setting and the practice sign-in's own (as it always did)",
          {"NEW_FEATURE_FLAG", "MOCK_OIDC_EXTERNAL_BASE_URL"} <= found, found)
    check("3b's rule then skips the practice sign-in's settings and follows the address rule, never into env/prod",
          "skip the practice sign-in's own settings (every `MOCK_OIDC_*`)" in rule3b and "the address rule and its table" in rule3b
          and "never write anything of the practice sign-in into `env/prod/`" in rule3b
          and "literal `value:` otherwise" not in rule3b, rule3b[:300])
else:
    check("5b step 3b is there", False)
sys.exit(1 if failed else 0)
PY
[ -s "$ERRF" ] && { echo "FAIL stderr was written (shown below)"; fail=1; }
exit $fail
