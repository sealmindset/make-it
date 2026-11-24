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
import http.client, http.server, json, os, re, shutil, socket, subprocess, sys, tempfile, textwrap, threading, time, urllib.parse, urllib.request
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

# --- mock-oidc's own checks, in each scaffold (local mode as before; cluster mode: the access code, its cookie,
# the admin API from its own pod only, the not-set-up page, the page headers, no lock-out)
tests = []
for sc in ("fastapi-nextjs", "nextjs-fullstack"):
    d = os.path.join(root, ".claude/make-it/scaffolds", sc, "mock-services/mock-oidc")
    tests.append(open(os.path.join(d, "test_app.py")).read())
    r = subprocess.run([PYEXE, "-I", "-B", "test_app.py"], cwd=d, capture_output=True, text=True, timeout=300)
    fails = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    check("mock-oidc's own checks pass in %s (%d checks)" % (sc, r.stdout.count("\nok ") + r.stdout.startswith("ok ")),
          r.returncode == 0 and "RESULT: ok" in r.stdout, "\n".join(fails) or (r.stdout + r.stderr)[-400:])
check("both scaffolds carry the same mock-oidc checks", tests[0] == tests[1])

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
def blk(after, lang="bash"):
    m_ = re.search(re.escape(after) + r".*?```" + lang + r"\n(.*?)```", doc, re.S)
    return m_.group(1) if m_ else ""
def py_of(b):
    m_ = re.search(r"<<'PY'\n(.*?)\n[ ]*PY\n", b, re.S)
    return textwrap.dedent(m_.group(1)) + "\n" if m_ else ""
g = blk("**Before PHASE 5: the live version holds no practice sign-in.**")
GUARD = py_of(g)
check("PHASE 2 has the live-version check, run on the live version's folder", 'python3 -I - "{manifest_dir}/prod" <<\'PY\'' in g and GUARD)
wf = doc.split('<step name="generate-workflow">', 1)[1].split("</step>", 1)[0]
wstep = re.search(r"\n      - name: Refuse the practice sign-in in the live version\n(.*?)```", wf, re.S)
wstep = wstep.group(1) if wstep else ""
check("on a runner without kubectl or kustomize the step fetches a pinned kustomize and checks its published checksum, or fails (exit 2)",
      "command -v kubectl" in wstep and "sha256sum -c -" in wstep and wstep.count("exit 2") >= 3 and "kustomize%2Fv5.8.1" in wstep)
check("the workflow's live-version step runs the same lines, with --assembled (the assembled version is required there)",
      GUARD and py_of(wstep + "\n").strip() == GUARD.strip() and '"{manifest_dir}/prod" --assembled' in wstep, wstep[:200])
KUBE = shutil.which("kubectl") or shutil.which("kustomize")
check("kubectl or kustomize is here, so the assembled checks run (GitHub's ubuntu runners have both)", KUBE or not os.environ.get("CI"))
KZ = "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n"
def dep(name, image, env=""):
    return ("apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: %s\nspec:\n  selector:\n    matchLabels:\n      app: %s\n"
            "  template:\n    metadata:\n      labels:\n        app: %s\n    spec:\n      containers:\n      - name: %s\n        image: %s\n%s"
            % (name, name, name, name, image, env))
ING = ("apiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: bedapp-ingress\nspec:\n  rules:\n  - host: live.example.test\n"
       "    http:\n      paths:\n      - path: /authorize\n        pathType: Prefix\n        backend:\n          service:\n            name: %s\n"
       "            port:\n              number: 8000\n")
DEVMOCK = dep("mock-oidc", "registry.example.test/app/mock-oidc:sha-1")
CLEAN = {"env/prod/kustomization.yaml": KZ + "- backend.yaml\n- ingress.yaml\n- adapter.yaml\n",
         "env/prod/backend.yaml": dep("bedapp-backend", "registry.example.test/app/backend:prod-latest",
                                      "        env:\n        - name: OIDC_ISSUER_URL\n          valueFrom:\n            secretKeyRef:\n              name: bedapp-oidc-prod\n              key: OIDC_ISSUER_URL\n"),
         "env/prod/ingress.yaml": ING % "backend",
         "env/prod/adapter.yaml": dep("mock-oidc-adapter", "registry.example.test/app/mock-oidc-adapter:1.2"),
         "env/dev/kustomization.yaml": KZ + "- mock-oidc.yaml\n", "env/dev/mock-oidc.yaml": DEVMOCK}
def guard(files, links=(), args=(), path_env=None, folder="env/prod", chmod=None):
    d = tempfile.mkdtemp()
    try:
        for rel, txt in files.items():
            os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
            open(os.path.join(d, rel), "w").write(txt)
        for rel, target in links:
            os.symlink(target, os.path.join(d, rel))
        if chmod:
            os.chmod(os.path.join(d, chmod), 0)
        env = dict(os.environ)
        if path_env is not None:
            env["PATH"] = path_env
        r = subprocess.run([sys.executable, "-I", "-c", GUARD, folder] + list(args), cwd=d, capture_output=True, text=True, env=env)
        return r.returncode, r.stdout + r.stderr
    finally:
        if chmod:
            os.chmod(os.path.join(d, chmod), 0o644)
        shutil.rmtree(d, ignore_errors=True)
def add(extra_name, txt, kz_line=None):
    f = dict(CLEAN, **{"env/prod/" + extra_name: txt})
    f["env/prod/kustomization.yaml"] = CLEAN["env/prod/kustomization.yaml"] + (kz_line or "- %s\n" % extra_name)
    return f
NOKUBE = tempfile.mkdtemp()     # a PATH with neither kubectl nor kustomize
if GUARD:
    rc, out = guard(CLEAN)
    check("the live-version check passes a clean live version: a real /authorize route and a mock-oidc-adapter are no traces",
          rc == 0 and "LIVE VERSION CLEAN" in out, out[-300:])
    if KUBE:
        check("a clean run says the assembled version was checked", "assembled by" in out, out[-200:])
    SVC = "apiVersion: v1\nkind: Service\nmetadata:\n  name: mock-oidc\nspec:\n  ports:\n  - port: 10090\n"
    PEOPLE_KZ = "configMapGenerator:\n- name: mock-oidc-people\n  files:\n  - mock-oidc-people.json\n"
    for label, files in (
            ("its image", add("x.yaml", dep("bedapp-x", "registry.example.test/app/mock-oidc:sha-1"))),
            ("its Service", add("x.yaml", SVC)),
            ("a route to it", add("x.yaml", ING.replace("bedapp-ingress", "x") % "mock-oidc")),
            ("its address", add("x.yaml", dep("bedapp-x", "r/x:1", "        env:\n        - name: OIDC_ISSUER_URL\n          value: http://mock-oidc:10090\n"))),
            ("its access code's key", add("x.yaml", dep("bedapp-x", "r/x:1", "        env:\n        - name: X\n          valueFrom:\n            secretKeyRef:\n              name: bedapp-oidc-prod\n              key: PRACTICE_ACCESS_CODE\n"))),
            ("its start-up hook's setting", add("x.yaml", dep("bedapp-x", "r/x:1", "        env:\n        - name: MOCK_OIDC_REDIRECT_URIS\n          value: https://live.example.test/cb\n"))),
            ("its people listed in the live kustomization", dict(CLEAN, **{"env/prod/mock-oidc-people.json": "[]\n",
                                                                          "env/prod/kustomization.yaml": CLEAN["env/prod/kustomization.yaml"] + PEOPLE_KZ}))):
        for mode, pe in (("assembled", None), ("text only", NOKUBE)):
            if mode == "assembled" and not KUBE:
                continue
            rc, out = guard(files, path_env=pe)
            check("the live-version check (%s) stops on %s" % (mode, label), rc == 1 and "PRACTICE SIGN-IN IN THE LIVE VERSION" in out, out[-300:])
    viadev = dict(CLEAN, **{"env/prod/kustomization.yaml": CLEAN["env/prod/kustomization.yaml"] + "- ../dev\n"})
    if KUBE:
        rc, out = guard(viadev)
        check("the assembled check stops on the practice sign-in pulled in from another folder (no trace in the live folder's text)",
              rc == 1 and "assembled by" in out, out[-300:])
    rc, out = guard(viadev, path_env=NOKUBE)
    check("without kubectl or kustomize the check reads the text only, and says so", rc == 0 and "only the files' text was checked" in out, out[-300:])
    rc, out = guard(viadev, path_env=NOKUBE, args=["--assembled"])
    check("with --assembled (the workflow) and no kubectl or kustomize it fails (exit 2), never skips", rc == 2 and "NOT CHECKED" in out, out[-300:])
    rc, out = guard(CLEAN, links=[("env/prod/extra.yaml", "../dev/mock-oidc.yaml")])
    check("a linked file in the live folder is followed", rc == 1, out[-300:])
    rc, out = guard(CLEAN, links=[("env/prod/sub", "../dev")])
    check("a linked folder in the live folder is followed", rc == 1, out[-300:])
    rc, out = guard(CLEAN, links=[("env/prod/gone.yaml", "../nowhere.yaml")])
    check("a file it can't read stops it (exit 2): an error is a failure, never a pass", rc == 2 and "NOT CHECKED" in out, out[-300:])
    if KUBE:
        rc, out = guard(dict(CLEAN, **{"env/prod/kustomization.yaml": CLEAN["env/prod/kustomization.yaml"] + "- missing.yaml\n"}))
        check("a live version that can't be assembled stops it (exit 2)", rc == 2 and "can't assemble" in out, out[-300:])
    rc, out = guard(CLEAN, folder="k8s/prod")
    check("a live-version folder that isn't there stops it (exit 2), naming the folder", rc == 2 and "k8s/prod" in out, out[-300:])
shutil.rmtree(NOKUBE, ignore_errors=True)

# --- the workflow runs it first, unconditionally; a refused run builds, labels and writes nothing
order = re.findall(r"(?m)^(\d+)\. (.+)$", wf.split("Its steps run in this order", 1)[-1].split("```yaml", 1)[0])
names = [t for _, t in order]
check("the workflow's order puts the live-version check right after the checkout, before anything is built or labelled",
      len(names) > 2 and names[0].startswith("Checkout source branch") and names[1].startswith("Refuse the practice sign-in in the live version"), names[:3])
def step_block(name):
    m_ = re.search(r"\n      - name: %s\n((?:        .*\n|\s*\n)*)" % re.escape(name), wf)
    return m_.group(1) if m_ else ""
gs = step_block("Refuse the practice sign-in in the live version")
check("the live-version step has no if: and no continue-on-error (every run passes it or stops)",
      gs and not re.search(r"(?m)^        (if|continue-on-error):", gs), gs[:200])
later = [l for f_ in re.findall(r"```yaml\n(.*?)```", wf, re.S) for l in f_.splitlines()
         if re.search(r"\b(always|failure|cancelled)\(\)|continue-on-error", l)]
check("no step of the workflow runs after a failed step (no always(), failure(), cancelled() or continue-on-error)", not later, later)
mirror = step_block("Mirror source to deploy branch and patch image tags") + wf.split("**yq patch for split-service apps", 1)[-1].split("**Note:**", 1)[0]
check("the workflow never copies the pretend people or anything of the practice sign-in into the deploy copy by hand",
      not re.search(r"\b(cp|install|rsync|tee)\b[^\n]*(people|seed-mock|mock-oidc)", mirror) and "/prod" not in mirror.split("The practice sign-in", 1)[-1],
      [l for l in mirror.splitlines() if "people" in l or "seed" in l])

# --- every placeholder is filled
ph = blk("**Before PHASE 5: every placeholder is filled.**")
PH = py_of(ph)
check("PHASE 2 checks that no generated file keeps a placeholder", PH and "{manifest_dir} .github/workflows/build-and-deploy.yml ONBOARDING-K8S.md" in ph)
def ph_run(files):
    d = tempfile.mkdtemp()
    for rel, txt in files.items():
        os.makedirs(os.path.dirname(os.path.join(d, rel)) or d, exist_ok=True); open(os.path.join(d, rel), "w").write(txt)
    r = subprocess.run([sys.executable, "-I", "-c", PH, "env", ".github/workflows/build-and-deploy.yml", "ONBOARDING-K8S.md"],
                       cwd=d, capture_output=True, text=True)
    shutil.rmtree(d, ignore_errors=True)
    return r.returncode, r.stdout
if PH:
    rc, out = ph_run({"env/dev/a.yaml": "name: {app}-backend\n", ".github/workflows/build-and-deploy.yml": "x: ${{ github.sha }} ${VAR} ${#A[@]}\n",
                      "ONBOARDING-K8S.md": "psql -U {db_user}\njsonpath='{.data.X}' {\"auths\":{} | {VAR_NAME} |\n"})
    check("the placeholder check lists what is left ({app}, {db_user}, {VAR_NAME}) and not ${...}, ${{ }}, '{.x}' or JSON",
          rc == 1 and all(x in out for x in ("{app}", "{db_user}", "{VAR_NAME}")) and "github" not in out and "{.data" not in out and "auths" not in out, out)
    FILL = {"{app}": "bedapp", "{env}": "dev", "{namespace}": "bedapp", "{hostname}": HOST, "{prod_hostname}": PHOST,
            "{registry_host}": "registry.example.test", "{manifest_dir}": "env", "{deploy_branch}": "deploy-nonprod",
            "{repo_url}": "https://git.example.test/team/bedapp.git", "{tls_secret_name}": "bedapp-tls", "{app_db_name}": "bedapp",
            "{provider}": "oidc"}
    onb_t = doc.split('<step name="generate-onboarding">', 1)[-1].split("</step>", 1)[0]
    onb_t = "\n".join(l for l in onb_t.splitlines() if "{VAR_NAME}" not in l)     # the rows the run writes, one per setting
    for k, v in FILL.items():
        onb_t = onb_t.replace(k, v)
    rc, out = ph_run({"env/dev/a.yaml": "a: 1\n", ".github/workflows/build-and-deploy.yml": "a: 1\n", "ONBOARDING-K8S.md": onb_t})
    check("ONBOARDING's template uses only placeholders a run fills (no {db_user} with nothing to fill it)", rc == 0, out[-400:])

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
          ref("MOCK_OIDC_CLIENT_SECRET").get("name") == "bedapp-oidc-dev" and {k: ref("MOCK_OIDC_ACCESS_CODE").get(k) for k in ("name", "key")} == {"name": "bedapp-oidc-dev", "key": "PRACTICE_ACCESS_CODE"}
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
    check("its people come from a ConfigMap made from mock-oidc-people.json (written at set-up), never from the shell script",
          vols.get("people", {}).get("configMap", {}).get("name") == "mock-oidc-people"
          and re.findall(r"(?m)^#\s+-\s+(\S+)\s*$", (kz or "").split("configMapGenerator", 1)[-1])[:1] == ["mock-oidc-people.json"])
    check("only the access code's key may be missing (the not-set-up page); the client secret is required",
          ref("MOCK_OIDC_ACCESS_CODE").get("optional") is True and not ref("MOCK_OIDC_CLIENT_SECRET").get("optional"))
    hook = (((c.get("lifecycle") or {}).get("postStart") or {}).get("exec") or {}).get("command") or []
    check("a start-up hook with an isolated python registers the return address from its settings",
          hook[:3] == ["python3", "-I", "-c"] and val("MOCK_OIDC_REDIRECT_URIS") == REDIR)
    check("the hook reads the people as data (JSON), with no shell parsing and no regular expression",
          len(hook) == 4 and "json.load(open(\"/people/mock-oidc-people.json\"" in hook[3] and "shlex" not in hook[3] and "re." not in hook[3])
    check("the hook calls the admin API from inside its own pod (127.0.0.1)", len(hook) == 4 and '"http://127.0.0.1:%s"' in hook[3])

# ======================================================================= the pretend people's file (one parser)
pb = blk("### mock-oidc-people.json (the pretend people")
PEOPLE = py_of(pb)
check("PHASE 2 writes the pretend people's file at set-up with one block (PHASE 1 runs the same block to read only)",
      PEOPLE and 'scripts/seed-mock-services.sh "{manifest_dir}/dev/mock-oidc-people.json"' in pb
      and "run PHASE 2's people block" in F and "without its second argument" in F)
def people_run(seed_text, out=None, old=None):
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, "scripts")); open(os.path.join(d, "scripts/seed-mock-services.sh"), "w").write(seed_text)
    if old is not None:
        open(os.path.join(d, "people.json"), "w").write(old)
    args = ["scripts/seed-mock-services.sh"] + (["people.json"] if out else [])
    r = subprocess.run([sys.executable, "-I", "-c", PEOPLE] + args, cwd=d, capture_output=True, text=True)
    data = open(os.path.join(d, "people.json")).read() if out and os.path.exists(os.path.join(d, "people.json")) else None
    shutil.rmtree(d, ignore_errors=True)
    return r.returncode, r.stdout + r.stderr, data
SEED_T = open(os.path.join(root, ".claude/make-it/scaffolds/fastapi-nextjs/scripts/seed-mock-services.sh")).read()
FOUR = (("mock-superadmin", "sa@example.test", "Sarah SuperAdmin"), ("mock-admin", "admin@example.test", "Alex Admin"),
        ("mock-analyst", "an@example.test", "Ana Analyst"), ("mock-viewer", "vi@example.test", "Victor Viewer"))
SEED = SEED_T
for i, (s_, e_, n_) in enumerate(FOUR, 1):
    SEED = SEED.replace("[ROLE_%d_OIDC_SUB]" % i, s_).replace("[ROLE_%d_EMAIL]" % i, e_).replace("[ROLE_%d_DISPLAY_NAME]" % i, n_)
if PEOPLE:
    rc, out, data = people_run(SEED, out=True)
    want = [dict(sub=s_, email=e_, name=n_) for s_, e_, n_ in FOUR]
    check("the people block writes the seed script's people as data: sub, email and name, nothing else of the script",
          rc == 0 and data and json.loads(data) == want and "MOCK_OIDC_URL" not in data and "PEOPLE WRITTEN" in out, out[-300:])
    rc, out, _ = people_run(SEED, out=True, old=data)
    rc2, out2, _ = people_run(SEED.replace("Ana Analyst", "Ana Analyst-Smith"), out=True, old=data)
    check("a re-run says whether the people changed (UNCHANGED / CHANGED)", "PEOPLE UNCHANGED" in out and "PEOPLE CHANGED" in out2, out + out2)
    rc, out, data = people_run(SEED)
    check("without the second argument it only reads (PHASE 1's question)", rc == 0 and "PEOPLE OK: 4" in out and data is None, out)
    A = lambda subs, emails='"a@x" "b@x"', names='"A" "B"': "declare -a USER_SUBS=(%s)\ndeclare -a USER_EMAILS=(%s)\ndeclare -a USER_NAMES=(%s)\n" % (subs, emails, names)
    for label, text, want_rc, want_out in (
            ("comments and an array over several lines", 'USER_SUBS=(\n  "a"   # the first\n  \'b\'\n)\ndeclare -a USER_EMAILS=("a@x" "b@x") # c\ndeclare -a USER_NAMES=("A (one)" "B \\"q\\"")\n', 0, "2 people (a, b)"),
            ("quotes, a ) and a # inside a name", A('"a" "b"', names='"A ) #1" \'B\'\'s\''), 0, "2 people (a, b)"),
            ("$(...) in a name", A('"a" "$(whoami)"'), 2, "PEOPLE STOP: scripts/seed-mock-services.sh:1:"),
            ("a variable", A('"a" $USER'), 2, "PEOPLE STOP: scripts/seed-mock-services.sh:1:"),
            ("backquotes", A('"a" `id`'), 2, "PEOPLE STOP"),
            ("a quote never closed", 'declare -a USER_SUBS=("a" "b)\n', 2, "PEOPLE STOP"),
            ("an array never closed", 'declare -a USER_SUBS=("a" "b"\n', 2, "PEOPLE STOP"),
            ("a different number of emails", A('"a" "b"', emails='"a@x"'), 2, "PEOPLE STOP"),
            ("an array set twice", A('"a" "b"') + 'USER_SUBS=("c")\n', 2, "PEOPLE STOP"),
            ("no people", A(''), 2, "PEOPLE STOP"),
            ("/make-it's placeholders still there", SEED_T, 2, "PEOPLE STOP: scripts/seed-mock-services.sh:39:"),
            ("a ; where a name should be", A('"a"; "b"'), 2, "PEOPLE STOP")):
        rc, out, data = people_run(text, out=True)
        check("the people block, %s: %s" % (label, "read" if want_rc == 0 else "a plain stop naming the line, nothing written"),
              rc == want_rc and want_out in out and "Traceback" not in out and (want_rc == 0 or data is None), out[-300:])
    # the generated dev tree assembles with no workflow run (Argo CD can show the first send at once)
    if KUBE and mt:
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "env/dev"))
        rc, out, data = people_run(SEED, out=True)
        open(os.path.join(d, "env/dev/mock-oidc-people.json"), "w").write(data)
        open(os.path.join(d, "env/dev/mock-oidc.yaml"), "w").write(fill(mt))
        kzt = "\n".join(l[2:] if l.startswith("# ") and re.search(r"configMapGenerator|mock-oidc-people|files:|mock-oidc-people\.json", l) else l
                        for l in (kz or "").splitlines() if not re.match(r"^- \{", l))
        kzt = re.sub(r"(?m)^resources:\n(#.*\n)*", "resources:\n- mock-oidc.yaml\n", kzt)
        open(os.path.join(d, "env/dev/kustomization.yaml"), "w").write(fill(kzt))
        r = subprocess.run([KUBE, "kustomize", "env/dev"] if KUBE.endswith("kubectl") else [KUBE, "build", "env/dev"],
                           cwd=d, capture_output=True, text=True)
        shutil.rmtree(d, ignore_errors=True)
        check("the test copy's files, as set-up writes them, assemble with no workflow run (the people's ConfigMap included)",
              r.returncode == 0 and "kind: ConfigMap" in r.stdout and "mock-oidc-people-" in r.stdout, (r.stderr or r.stdout)[-400:])
if mt and len(hook) == 4 and PEOPLE:
    # the hook against the real mock-oidc, with the people's file the block wrote from the scaffold's seed script
    tmp = tempfile.mkdtemp()
    rc, out, data = people_run(SEED, out=True)
    open(os.path.join(tmp, "mock-oidc-people.json"), "w").write(data or "")
    script = hook[3].replace("/people/", tmp + "/")      # the volume's mount, here a folder
    CODE2 = "cluster-code-abcdef0123"
    m = Mock({"MOCK_OIDC_REQUIRE_ACCESS_CODE": "true", "MOCK_OIDC_ACCESS_CODE": CODE2, "MOCK_OIDC_REDIRECT_URIS": REDIR})
    try:
        if not m.up:
            check("the scaffold's mock-oidc starts here", False, m.output()[-300:])
        else:
            st0, _, _ = m.req("GET", "/authorize?" + QS)
            h = subprocess.run([PYEXE, "-I", "-c", script], env=m.env, capture_output=True, text=True, timeout=120)
            check("the hook runs (from 127.0.0.1, inside the pod): it loads the people and registers the return address", h.returncode == 0, h.stderr[-300:])
            users = json.loads(m.req("GET", "/api/users")[2])
            check("after the hook the practice sign-in holds the seed script's people (one source)",
                  [u["sub"] for u in users] == [p_[0] for p_ in FOUR], users)
            st, hs, _ = m.req("POST", "/authorize", form=dict(access_code=CODE2, return_query=QS))
            cookie = (hdr(hs, "set-cookie") or [""])[0].split(";")[0]
            st, hs, _ = m.req("POST", "/authorize", form=dict(sub="mock-admin", redirect_uri=REDIR, client_id="mock-oidc-client", state="s"), cookie=cookie)
            check("a seeded person signs in through the access code: 302 to the app's return address with a code",
                  st0 == 400 and st == 302 and hdr(hs, "location")[0].startswith(REDIR + "?code="), (st0, st, hdr(hs, "location")))
            disc = json.loads(m.req("GET", "/.well-known/openid-configuration")[2])
            check("the browser is sent to the app's public address for the sign-in page", disc.get("authorization_endpoint") == "https://%s/authorize" % HOST)
    finally:
        m.stop(); shutil.rmtree(tmp, ignore_errors=True)
check("no NetworkPolicy is generated or mentioned any more (the admin API answers only its own pod)",
      "NetworkPolicy" not in doc and "network-policy" not in doc and "ingress_controller_namespace" not in doc)

# ======================================================================= the backend's own seeding stops at once on a cluster
ep = open(os.path.join(root, ".claude/make-it/scaffolds/fastapi-nextjs/backend/entrypoint.sh")).read()
seed_part = ep[ep.index('OIDC_URL="'):ep.index('echo "Mock-oidc users seeded."')]
def ep_run(status):
    seen = []
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append(self.command); self.send_response(status); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"[]")
        do_POST = do_GET
        def log_message(self, *a):
            pass
    srv = http.server.HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    t0 = time.monotonic()
    r = subprocess.run(["bash", "-e", "-c", seed_part], env=dict(os.environ, OIDC_ISSUER_URL="http://127.0.0.1:%d" % srv.server_address[1]),
                       capture_output=True, text=True, timeout=60)
    took = time.monotonic() - t0
    srv.shutdown()
    return r.returncode, seen, took
rc, seen, took = ep_run(403)
# backend/entrypoint.sh is a sealed security file (watermark/protected-fastapi-nextjs.txt): changing it would make every
# existing app's seal check ask for a security review, so its loop is left as it is -- an owner decision. Pinned
# here: against the 403 it gives up after its five tries and never fails the start.
check("the backend's start: against the practice sign-in's 403 its seeding gives up and the start goes on (%.1f s, %d requests)" % (took, len(seen)),
      rc == 0 and seen[:5] == ["GET"] * 5 and took < 15, (rc, seen))
rc, seen, took = ep_run(200)
check("the backend's start, local development: it still registers its four people (as before)", rc == 0 and seen == ["GET"] + ["POST"] * 4, (rc, seen))

# ======================================================================= the question, the sentences, ONBOARDING
q = flat(doc.split("**Sign-in** (only if the app signs people in", 1)[-1].split("**Split-service ingress**", 1)[0])
for phrase in ("**The practice sign-in** -- pretend people, no passwords, behind an access code your DevOps team sets",
               "Anyone who has the code can sign in as any of them, an administrator included, so keep {hostname} off the internet too",
               "**Your organisation's sign-in**", "the test copy won't start until they do",
               "On a re-run, read `deployment.signin_dev` from app-context.json and use it: don't ask again",
               "the app has a separate front end and backend (split-service)",
               "its `mock-services/mock-oidc/app.py` contains `MOCK_OIDC_ACCESS_CODE` (read the file; never guess from a version)",
               "/resume-it updates it first", "the app's pretend people can be read from `scripts/seed-mock-services.sh`: run PHASE 2's people block",
               "[the block's `PEOPLE STOP` line in plain words: the line and why]"):
    check("the sign-in question says: %s" % phrase[:72], flat(phrase) in q)
say = flat(doc.split("### What sign-in will do", 1)[-1].split("\n### ", 1)[0])
for phrase in ("pretend people, no passwords, behind an access code your DevOps team sets. Anyone who has the code can sign in as any of them, an administrator included",
               "The test copy won't start until your DevOps team adds the sign-in password, and nobody can sign in until they add the access code",
               "until then Sign in shows a page saying so",
               "a browser that typed it is remembered for 15 minutes",
               "The live version never uses it",
               "the app won't start until your DevOps team adds its settings, and people can't sign in until they also register {hostname} with it"):
    check("the sentence the person hears says: %s" % phrase[:72], phrase in say)
check("no sentence still claims people can open the app before the Secret exists",
      "people can open the app but can't sign in" not in F and "people can open the test copy but can't sign in" not in F)
p5 = doc.split("<!-- PHASE 5: DEPLOY", 1)[-1]
check("the send ask and the report both say the sign-in sentence", p5.count('sign-in sentence from PHASE 2 "What sign-in will do"') >= 2)
check("the settings copied as is are listed at the send ask", "These settings were copied as they are" in p5.split("**What would you like to do?**", 1)[0])
check("the report says app-context.json was left changed, and names its keys", "left it changed, not saved" in flat(p5) and "deployment.signin_dev" in p5)
for label, phrase in (("ONBOARDING: the admin warning", "The practice sign-in lets anyone who has the access code sign in as any pretend person, an administrator included: keep `{hostname}` reachable only from your organisation's network too."),
                      ("ONBOARDING: the admin routes", "answer only its own pod -- every other address, inside the cluster or out, gets 403"),
                      ("ONBOARDING: 15 minutes", "a browser that typed it is remembered for 15 minutes"),
                      ("ONBOARDING: no lock-out", "A wrong code waits a second and is never counted: nobody can lock testers out"),
                      ("ONBOARDING: what testers see before the code", "**Sign in** opens a page that says \"The practice sign-in isn't set up yet. Ask your DevOps team to finish setting it up\""),
                      ("ONBOARDING: where DevOps looks", "a line starting `mock-oidc: the practice sign-in isn't set up`"),
                      ("ONBOARDING: what a code must be", "The code must be at least 16 characters, not only spaces or one repeated character"),
                      ("ONBOARDING: cluster mode stays on", "Any value other than `false`, `0`, `no` or empty keeps these rules on"),
                      ("ONBOARDING: which shells", "Every command below works in any shell (sh, bash, zsh) and keeps each value off the command line"),
                      ("ONBOARDING: no trailing newline", "A value read from a prompt never keeps a trailing newline"),
                      ("ONBOARDING: the code out of band", "when you hand it to your testers -- out of band"),
                      ("ONBOARDING: never in a ticket", "never in a ticket, chat or email"),
                      ("ONBOARDING: the access code generated into a private file", "openssl rand -hex 12 | tr -d '\\n' > \"$d/PRACTICE_ACCESS_CODE\""),
                      ("ONBOARDING: the organisation's Secret", "kubectl create secret generic {app}-oidc-{env} -n {namespace}"),
                      ("ONBOARDING: the test address only for the organisation's sign-in", "only when the test copy uses your organisation's sign-in too"),
                      ("ONBOARDING: pull access follows the registry", "printf '{\"auths\":{\"%s\":{\"auth\":\"%s\"}}}' '{registry_host}'"),
                      ("ONBOARDING: the app won't start without the Secret", "The app won't start until this Secret exists.")):
    says(label, phrase)
check("ONBOARDING no longer hard-codes ghcr.io for pull access", "--docker-server=ghcr.io" not in doc)
# ONBOARDING's sign-in commands, as generated, must pass the skill's own secret check (PHASE 5 scans every
# generated file: a hit there stops the send). Found by the bed run: `SECRET="$(...)"` read as a secret.
onb = doc.split('<step name="generate-onboarding">', 1)[-1].split("</step>", 1)[0]
devops = onb.split("## For DevOps", 1)[-1].split("## For Developers", 1)[0]
cmds = "\n".join(re.findall(r"```(?:bash|sh)\n(.*?)```", devops, re.S))
literal = [l.strip() for l in cmds.splitlines() if re.search(r"--from-literal=\w*(SECRET|PASSWORD|TOKEN|KEY|CODE|DATABASE_URL)|--docker-password|/dev/stdin|<<<", l)]
check("ONBOARDING never puts a secret on a command line (no --from-literal secret, --docker-password, pasted stdin or here-string)", not literal, literal)
check("every ONBOARDING block that creates a Secret writes its values into a private folder and deletes it",
      all("umask 077" in b_ and 'rm -rf "$d"' in b_ for b_ in re.findall(r"```sh\n(.*?)```", devops, re.S) if "create secret" in b_))
d = tempfile.mkdtemp()
subprocess.run(["git", "init", "-q"], cwd=d)
open(os.path.join(d, "ONBOARDING-K8S.md"), "w").write(fill(cmds))
r = subprocess.run([sys.executable, "-I", os.path.join(root, ".claude/make-it/scripts/secret-scan.py")], cwd=d, capture_output=True, text=True)
shutil.rmtree(d, ignore_errors=True)
check("ONBOARDING's DevOps commands pass the skill's own secret check (else the send stops on its own file)",
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
      re.search(r"\*\*M05\*\* \[Tier 1, 5\] \[WARN\] \*\*The practice sign-in can ask for an access code\*\*.*MOCK_OIDC_ACCESS_CODE", bs) is not None)
m05 = flat(bs.split("**M05**", 1)[-1].split("\n", 1)[0])
for phrase in ("first compare the app's copy with the scaffold versions it can have come from",
               "its sha256 is in `~/.claude/make-it/scaffolds/mock-oidc-releases.sha256`",
               "Listed there (the same apart from the `redirect_uris` list): replace it with the scaffold's, keeping only that list",
               "show the person the differences in plain words and ask one select: **Update it**", "**Keep mine**",
               "Either way a copy of the app's file is kept before anything is written"):
    check("M05 says: %s" % phrase[:72], phrase in m05)
check("/resume-it's catch-up runs M05", "Mock Services (M01-M05)" in ri and "M05" in ri)
import hashlib
def m05_hash(t):
    t = re.sub(r'CLIENT_ID: \{"redirect_uris": \[.*?\]\},', 'CLIENT_ID: {"redirect_uris": []},', t, count=1, flags=re.S)
    return hashlib.sha256(t.encode()).hexdigest()
rel = open(os.path.join(root, ".claude/make-it/scaffolds/mock-oidc-releases.sha256")).read()
known = re.findall(r"(?m)^([0-9a-f]{64})\s", rel)
cur = [m05_hash(open(os.path.join(root, ".claude/make-it/scaffolds", sc, "mock-services/mock-oidc/app.py")).read())
       for sc in ("fastapi-nextjs", "nextjs-fullstack")]
check("M05's list of released mock-oidc copies has this scaffold's copy (both scaffolds; add a line when it changes)",
      all(c in known for c in cur), cur)
check("M05's list keeps the earlier releases (an app built on one is updated without asking)",
      {"7ed5dcc152ffe80268c8b94e617bc7a0e236048681dcdcaf2b59f8d3e2350b64", "28a97b0cb14aaa20bd4ed4a072eb4a6d3dc8fa244304b1df8655de7877e6abae"} <= set(known))

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
