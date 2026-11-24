#!/usr/bin/env bash
# E12-S15 (tasks 1-2): the build-and-deploy workflow /argo-it generates must build and deploy an app made from
# make-it's own fastapi-nextjs scaffold. The baseline run on the test bed (v1.71.18) needed five hand fixes to the
# generated workflow before anything reached the cluster; this test pins each of them without a bed.
# How: the workflow template is read out of argo-it.md's PHASE 3 (<step name="generate-workflow">) the way an agent
# assembles it -- the ```yaml fences, the split-service variant, each `{service}` step once per service, the steps
# placed by the order list the phase gives (document order when it gives none) -- and filled for the scaffold from
# its docker-compose.yml (build contexts by the text's own rule; when the text names a context for a service, that).
# Contract these checks pin, on that filled workflow:
#   - it is valid YAML, every placeholder is filled, step ids are unique;
#   - every step's `run:` body is valid bash and runs to the end with stubbed tools (docker, git, yq, rsync, curl,
#     sudo) under `bash -euo pipefail`, on a push to main and to a feature branch: no variable is used before it
#     is set, and no step reads `steps.<id>.outputs` of a step that hasn't run;
#   - the migration check passes on the scaffold's own Alembic files (typed headers) and on plain ones, and fails
#     loudly, naming the file, on a down_revision no file declares;
#   - each service is built from the build context docker-compose.yml gives it, and that context holds its Dockerfile;
#   - each service's image tags come from its own image-tags step, named for that service;
#   - every image the deploy step writes, on main and on a feature branch, carries a tag the same run built and
#     pushed;
#   - nothing starts an image before its build-and-push step, the deploy tag is set before the smoke test, and the
#     deploy branch is written after every image is pushed;
#   - the mirror to the deploy branch leaves `.github/` out.
# A model, not a run: real Actions, a registry and a cluster are the bed's acceptance run (E12-S15).
# Usage: test-argo-it-workflow-fits-the-scaffold.sh [ARGO_IT_MD]  (default: this repo's argo-it.md)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
DOC="${1:-$root/.claude/commands/argo-it.md}"
SCAFFOLD="$root/.claude/make-it/scaffolds/fastapi-nextjs"
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT
fail=0
python3 -I - "$DOC" "$SCAFFOLD" <<'PY' || fail=1
import os, re, shlex, shutil, subprocess, sys, tempfile
try:
    import yaml
except ImportError:
    print("FAIL PyYAML is needed to read docker-compose.yml and the workflow (pip install pyyaml)"); sys.exit(1)
doc_path, scaffold = sys.argv[1:]
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        for l in str(why).splitlines()[:12]:
            print("  " + l)

doc = open(doc_path, encoding="utf-8").read()
m = re.search(r'<step name="generate-workflow">(.*?)</step>', doc, re.S)
if not m:
    print('FAIL argo-it.md has a <step name="generate-workflow">'); sys.exit(1)
phase = m.group(1)

# ---------- the scaffold's facts, from its docker-compose.yml ----------
def dflt(v):  # ${VAR:-default} -> default, ${VAR} -> ""
    return re.sub(r'\$\{[A-Z_][A-Z0-9_]*(?::?-([^}]*))?\}', lambda x: x.group(1) or "", str(v))
compose = yaml.safe_load(open(os.path.join(scaffold, "docker-compose.yml")))["services"]
def envmap(svc):
    e = svc.get("environment") or {}
    if isinstance(e, list):
        e = dict(x.split("=", 1) if "=" in x else (x, "") for x in e)
    return e
SERVICES = [n for n, s in compose.items() if s.get("build") and not n.startswith("mock-") and "dev" not in (s.get("profiles") or [])]
DB_SERVICES = [n for n in SERVICES if "DATABASE_URL" in envmap(compose[n])]
# The practice sign-in (E12-S15 task 3): when the text builds mock-oidc's image too, the model builds it, as its
# compose service, last (it gets no smoke test: no DATABASE_URL)
if "plus `mock-oidc` when the practice sign-in was picked" in re.sub(r"\s+", " ", phase) and "mock-oidc" in compose:
    SERVICES.append("mock-oidc")
CTX = {}
for n in SERVICES:
    b = compose[n]["build"]
    c = b if isinstance(b, str) else b.get("context", ".")
    f = "Dockerfile" if isinstance(b, str) else b.get("dockerfile", "Dockerfile")
    CTX[n] = (os.path.normpath(c), os.path.normpath(os.path.join(c, f)))
dbimg = next(dflt(s["image"]) for s in compose.values() if "postgres" in str(s.get("image", "")))
check("the scaffold's compose file has buildable app services, one with DATABASE_URL, and a postgres database",
      len(SERVICES) >= 2 and DB_SERVICES and dbimg, "services %s, with a database %s" % (SERVICES, DB_SERVICES))
def scheme(n):
    return envmap(compose[n])["DATABASE_URL"].split("://", 1)[0]
def health(n):
    t = (compose[n].get("healthcheck") or {}).get("test")
    if not t:
        return NOHEALTH
    if t[0] == "CMD":
        return shlex.join(t[1:])
    return "sh -c " + shlex.quote(t[1])

# ---------- the template, assembled the way the text says ----------
fences = []  # (label, body)
label = ""
lines = phase.split("\n")
i = 0
while i < len(lines):
    l = lines[i]
    if l.startswith("**"):
        label = l
    if l.strip() == "```yaml":
        j = i + 1
        while lines[j].strip() != "```":
            j += 1
        fences.append((label, "\n".join(lines[i + 1:j])))
        i = j
    i += 1

def is_single(lbl):
    return "single-service" in lbl.lower()
header = next(b for _, b in fences if b.lstrip().startswith("name:"))
envsplit = next(b for lb, b in fences if "split-service" in lb.lower() and b.lstrip().startswith("#") and "TARGET" in b)
jobs = next(b for _, b in fences if b.startswith("jobs:"))
jobs_head, _, first_steps = jobs.partition("    steps:\n")

steps = []  # raw step texts in document order
def split_steps(body):
    """Steps start at '      - '; comment lines at the step indent go with the step after them."""
    blocks, pending, cur = [], [], None
    for l in body.split("\n"):
        if re.match(r"      - ", l):
            if cur is not None:
                blocks.append(cur)
            cur, pending = pending + [l], []
        elif re.match(r"      #", l) or (cur is None):
            pending.append(l)
        else:
            cur.append(l)
    if cur is not None:
        blocks.append(cur)
    return ["\n".join(x) for x in blocks]
for blk in split_steps(first_steps):
    steps.append(blk)
for lb, b in fences:
    if b in (header, envsplit, jobs) or is_single(lb) or b.lstrip().startswith("name:"):
        continue
    first = next((x for x in b.split("\n") if x.strip()), "")
    indent = len(first) - len(first.lstrip())
    if re.search(r"^      - (name|uses):", b, re.M):
        steps.extend(split_steps(b))
    elif indent >= 10 and steps:          # a continuation of the step before (the mirror's run: body)
        steps[-1] += "\n" + b
def step_name(t):
    mm = re.search(r"^      - name: (.*)$", t, re.M)
    return mm.group(1).strip() if mm else ""

# expand the per-service steps ({compose_service} since E12-S15 task 3; {service} before it)
PER = "{compose_service}" if "{compose_service}" in phase else "{service}"
expanded = []
for t in steps:
    if PER in t:
        who = DB_SERVICES if "smoke" in step_name(t).lower() else SERVICES
        for n in who:
            expanded.append((n, t.replace(PER, n)))
    else:
        expanded.append((None, t))

# order: the phase's numbered list, else document order
order = re.findall(r"^(\d+)\. ([^\n]+)$", phase.split("```yaml")[0], re.M)
ORDER_GIVEN = bool(order) and "in this order" in phase
def order_key(item):
    idx, (svc, t) = item
    if not ORDER_GIVEN:
        return (idx, 0)
    name = step_name(t)
    for k, entry in order:
        e = entry.split(" -- ")[0].strip()
        e = e.replace(PER, svc or "")
        if name == e or (e and name.startswith(e)):
            return (int(k), SERVICES.index(svc) if svc in SERVICES else 0)
    UNPLACED.append(step_name(t))
    return (999, idx)
UNPLACED = []
ordered = [it[1] for it in sorted(enumerate(expanded), key=order_key)]

# fill the remaining placeholders the way the text says
splitctx = {k.lower(): v.strip() for k, v in re.findall(r"^- (\w+): `context: ([^`]+)`", phase, re.M)}
# a service with no health check: what the text says to put there (`true` in the old text, nothing now)
NOHEALTH = "true" if "`{healthcheck_command}` is `true`" in phase else ""
def fill(t, svc, nohealth=False):
    if svc:
        ctx, df = CTX[svc]
        if svc in splitctx:   # the text names this service's context: use it, as an agent would
            ctx = os.path.normpath(splitctx[svc])
        t = t.replace("./{build_context}", "./" + ctx).replace("{build_context}", ctx)
        t = t.replace("./{dockerfile_path}", "./" + CTX[svc][1]).replace("{dockerfile_path}", CTX[svc][1])
        if svc in DB_SERVICES:
            t = t.replace("{database_url_scheme}", scheme(svc))
            t = t.replace("{healthcheck_command}", NOHEALTH if nohealth else health(svc))
    return (t.replace("{db_image}", dbimg).replace("{deploy_branch}", "deploy-nonprod")
             .replace("{registry_host}/{image_base_path}", "ghcr.io/example/myapp")
             .replace("{first_service}", SERVICES[0]).replace("{services}", " ".join(SERVICES))
             .replace("{manifest_dir}", "env").replace("{app}", "myapp"))
def build_wf(nohealth=False):
    body = [fill(t, s, nohealth) for s, t in ordered]
    return (fill(header, None) + "\n" + fill(envsplit, None) + "\n" + fill(jobs_head, None) + "    steps:\n"
            + "\n".join(body) + "\n")
wf_text = build_wf()
left = sorted(set(re.findall(r"(?<![$\w])\{[a-z][a-z_]+\}", wf_text)))
check("every placeholder in the workflow is filled", not left, "left: %s" % left)
try:
    wf = yaml.safe_load(wf_text)
    ok_yaml = True
except yaml.YAMLError as e:
    ok_yaml, wf = False, None
    err = e
check("the filled workflow is valid YAML", ok_yaml, "" if ok_yaml else err)
if not ok_yaml:
    sys.exit(1)
job = next(iter(wf["jobs"].values()))
ST = job["steps"]
ST_NOHEALTH = next(iter(yaml.safe_load(build_wf(nohealth=True))["jobs"].values()))["steps"]
ids = [s.get("id") for s in ST if s.get("id")]
dup = sorted(set(x for x in ids if ids.count(x) > 1))
check("every step id is unique (one image-tags step per service, each with its own id)", not dup, "repeated: %s" % dup)
check("the order of the steps is stated in the text, and it places every step", ORDER_GIVEN and not UNPLACED,
      "PHASE 3 gives no numbered step order" if not ORDER_GIVEN else "not in the order list: %s" % UNPLACED)
WENV = {k: str(v) for k, v in (wf.get("env") or {}).items()}

# ---------- a model run ----------
# The step bodies run where the runner runs them: bash 4 or later (macOS ships 3.2, which lacks ${VAR,,}). With no
# such bash here, they run in a throwaway python:3.12-slim container (bash 5, python3), removed when it exits.
def find_bash():
    for b in (os.environ.get("BASH4"), "/opt/homebrew/bin/bash", "/usr/local/bin/bash", shutil.which("bash")):
        if b and os.path.exists(b):
            v = subprocess.run([b, "-c", "echo ${BASH_VERSINFO[0]}"], capture_output=True, text=True).stdout.strip()
            if v.isdigit() and int(v) >= 4:
                return b
    return None
BASH = find_bash()
TMP = tempfile.mkdtemp()
RUNS = [0]
def run_bash(args, cwd, env):
    if BASH:
        return subprocess.run([BASH] + args, cwd=cwd, env=env, capture_output=True, text=True)
    if not shutil.which("docker"):
        return subprocess.CompletedProcess(args, 99, "", "no bash 4+ and no docker to run the step bodies in")
    envf = os.path.join(TMP, "env.list")
    keep = {k: v for k, v in env.items() if k not in ("PATH", "HOME", "TMPDIR", "SHELL") and "\n" not in v}
    open(envf, "w").write("".join("%s=%s\n" % kv for kv in keep.items()))
    RUNS[0] += 1
    cmd = ["docker", "run", "--rm", "--name", "argoit-workflow-test-%d-%d" % (os.getpid(), RUNS[0]),
           "-v", "%s:%s" % (TMP, TMP), "-w", cwd, "--env-file", envf,
           "-e", "PATH=%s:/usr/local/bin:/usr/bin:/bin" % STUBS, "python:3.12-slim", "bash"] + args
    return subprocess.run(cmd, capture_output=True, text=True)
STUBS = tempfile.mkdtemp(dir=TMP)
def stub(name, script):
    p = os.path.join(STUBS, name)
    open(p, "w").write("#!/usr/bin/env bash\n" + script + "\n")
    os.chmod(p, 0o755)
# docker: every call is written to $STUB_LOG. STUB_MODE=ok: the app runs and answers its check. STUB_MODE=crash: the
# app exits at once -- `docker ps` lists nothing running, a real check fails, and `docker exec ... true` still
# succeeds (the race the old no-health-check text lost); its log holds SMOKE-LOG-MARK.
stub("docker", r'''echo "docker $*" >> "${STUB_LOG:-/dev/null}"
case "$1" in
  ps) [ "${STUB_MODE:-ok}" = ok ] && echo 0123abcd ;;
  exec) [ "${STUB_MODE:-ok}" = ok ] && exit 0; [ "${!#}" = true ] && exit 0; exit 1 ;;
  logs) echo SMOKE-LOG-MARK ;;
esac
exit 0''')
stub("yq", "exit 0")
# kubectl: `kubectl kustomize DIR` prints DIR's YAML files, as an assembled version (the live-version step needs one)
stub("kubectl", '[ "$1" = kustomize ] || exit 1; [ -f "$2/kustomization.yaml" ] || { echo "no kustomization in $2" >&2; exit 1; }; cat "$2"/*.yaml')
stub("rsync", "exit 0")
stub("sudo", "exit 0")
stub("git", 'exit 0')
stub("sleep", "exit 0")
stub("curl", 'while [ $# -gt 0 ]; do [ "$1" = -o ] && : > "$2"; shift; done; exit 0')

PRIO = {"sha": 100, "raw": 200, "ref": 600}
def expr_eval(e, ctx, outputs, problems, who):
    """The few expression forms the template uses: a context value, == / !=, && / ||. Its input is only this
    repo's own template text, translated to a Python expression and evaluated with no builtins."""
    e = e.strip()
    m = re.fullmatch(r"steps\.([\w-]+)\.outputs\.(\w+)", e)
    if m:
        sid, key = m.groups()
        if sid not in outputs or key not in outputs[sid]:
            problems.append("%s reads steps.%s.outputs.%s before that step ran and set it" % (who, sid, key))
            return ""
        return outputs[sid][key]
    py = e
    py = re.sub(r"'([^']*)'", lambda m: repr(m.group(1)), py)
    py = py.replace("&&", " and ").replace("||", " or ").replace("!", " not ").replace(" not =", "!=")
    py = re.sub(r"\benv\.(\w+)", lambda m: repr(WENV.get(m.group(1), "")), py)
    py = re.sub(r"\bgithub\.([\w.]+)", lambda m: repr(ctx.get(m.group(1), "")), py)
    py = re.sub(r"\bsecrets\.\w+", "'stub-secret'", py)
    try:
        v = eval(py, {"__builtins__": {}})
    except Exception:
        return "<<%s>>" % e
    return v
def subst(s, ctx, outputs, problems, who):
    s = str(s)
    m = re.fullmatch(r"\s*\$\{\{(.*?)\}\}\s*", s)
    if m:
        return expr_eval(m.group(1), ctx, outputs, problems, who)
    return re.sub(r"\$\{\{(.*?)\}\}", lambda m: str(expr_eval(m.group(1), ctx, outputs, problems, who)), s)
def truthy(v):
    return v is True or str(v).lower() == "true"
def cond(step, ctx):
    return truthy(subst(step.get("if", "true"), ctx, {}, [], "")) if "if" in step else True
def meta_tags(step, ctx):
    w = step.get("with") or {}
    img = subst(w.get("images", ""), ctx, {}, [], "")
    n = int((step.get("env") or {}).get("DOCKER_METADATA_SHORT_SHA_LENGTH", 7))
    out = []
    for line in str(w.get("tags", "")).splitlines():
        line = line.strip()
        if not line:
            continue
        kv = dict(x.split("=", 1) for x in line.split(",") if "=" in x)
        en = kv.get("enable")
        if en is not None and not truthy(subst(en, ctx, {}, [], "")):
            continue
        if kv.get("type") == "raw":
            out.append((PRIO["raw"], kv["value"]))
        elif kv.get("type") == "sha":
            out.append((PRIO["sha"], kv.get("prefix", "sha-") + ctx["sha"][:n]))
        elif kv.get("type") == "ref" and kv.get("event") == "branch" and ctx["event_name"] != "pull_request":
            out.append((PRIO["ref"], re.sub(r"[^\w.-]", "-", ctx["ref_name"])))
    out.sort(key=lambda x: -x[0])
    return img, [t for _, t in out]
def is_build(s, push=None):
    if not str(s.get("uses", "")).startswith("docker/build-push-action"):
        return False
    return push is None or (str((s.get("with") or {}).get("push")).lower() == "true") == push

def simulate(ref_name, steps=None, mode="ok", event="push"):
    """One run, GitHub's rules: a step runs when its `if:` holds and no step before it failed."""
    steps = steps or ST
    ctx = {"event_name": event, "ref_name": ref_name,
           "ref": "refs/pull/7/merge" if event == "pull_request" else "refs/heads/" + ref_name,
           "sha": "0123456789abcdef0123456789abcdef01234567", "actor": "someone"}
    work = tempfile.mkdtemp(dir=TMP)
    shutil.copytree(scaffold, os.path.join(work, "src"))
    src = os.path.join(work, "src")
    os.makedirs(os.path.join(src, "env/prod"))     # the live version's folder, as set-up writes it (clean)
    open(os.path.join(src, "env/prod/kustomization.yaml"), "w").write("resources:\n- backend.yaml\n")
    open(os.path.join(src, "env/prod/backend.yaml"), "w").write("image: x/backend:prod-latest\n")
    log = os.path.join(work, "docker.log")
    open(log, "w").close()
    R = {"outputs": {}, "problems": [], "pushed": {}, "ran": [], "failed": None, "out": {}, "meta": {}, "ctx": ctx}
    for idx, s in enumerate(steps):
        name = s.get("name", s.get("uses", "?"))
        if R["failed"] is not None or not cond(s, ctx):
            continue
        R["ran"].append(name)
        sid = s.get("id")
        uses = s.get("uses", "")
        if uses.startswith("docker/metadata-action"):
            img, tags = meta_tags(s, ctx)
            R["meta"][sid] = (img, tags)
            R["outputs"][sid] = {"tags": "\n".join(img + ":" + t for t in tags), "version": tags[0] if tags else ""}
        elif uses.startswith("docker/build-push-action"):
            w = s.get("with") or {}
            tags = subst(w.get("tags", ""), ctx, R["outputs"], R["problems"], name)
            if str(w.get("push")).lower() == "true":
                for t in str(tags).split("\n"):
                    if ":" in t:
                        R["pushed"].setdefault(t.rsplit(":", 1)[0].lower(), set()).add(t.rsplit(":", 1)[1])
        elif uses.startswith("actions/checkout") and (s.get("with") or {}).get("path"):
            os.makedirs(os.path.join(src, s["with"]["path"], ".github"), exist_ok=True)
        elif "run" in s:
            env = dict(os.environ)
            env.update(WENV)
            env.update({"GITHUB_SHA": ctx["sha"], "GITHUB_REF_NAME": ref_name, "GITHUB_REF": ctx["ref"],
                        "GITHUB_RUN_ID": "42", "PATH": STUBS + ":" + os.environ["PATH"],
                        "STUB_MODE": mode, "STUB_LOG": log})
            for k, v in (s.get("env") or {}).items():
                env[k] = str(subst(v, ctx, R["outputs"], R["problems"], name))
            outf = os.path.join(work, "out-%d" % idx)
            open(outf, "w").close()
            env["GITHUB_OUTPUT"] = outf
            script = os.path.join(work, "step-%d.sh" % idx)
            open(script, "w").write(s["run"])
            open(log, "a").write("STEP %s\n" % name)
            syn = run_bash(["-n", script], src, env)
            if syn.returncode:
                R["problems"].append("%s: not valid bash: %s" % (name, syn.stderr.strip()))
                R["failed"] = name
                continue
            r = run_bash(["-euo", "pipefail", script], src, env)
            R["out"][name] = (r.returncode, r.stdout + r.stderr)
            if r.returncode:
                R["failed"] = name
                if mode == "ok":
                    R["problems"].append("%s: exit %d: %s" % (name, r.returncode, (r.stderr or r.stdout).strip()[-300:]))
            if sid:
                R["outputs"][sid] = dict(l.split("=", 1) for l in open(outf).read().splitlines() if "=" in l)
    R["docker"] = open(log).read()
    shutil.rmtree(work, ignore_errors=True)
    return R

def moving_tags(ref):
    return {re.sub(r"[^\w.-]", "-", ref), "prod-latest" if ref == "main" else "dev-latest"}
base = WENV.get("IMAGE_BASE", "").lower()
mirror = next((s for s in ST if "run" in s and "rsync" in s["run"]), None)
patched = sorted(set(re.findall(r'"/([\w-]+):" \+ env\(DEPLOY_TAG\)', (mirror or {}).get("run", ""))))
for ref in ("main", "feature-x"):
    R = simulate(ref)
    check("push to %s: every run: body is valid bash and runs to the end under set -euo pipefail, every variable "
          "and step output set before it is used" % ref, not R["problems"], "\n".join(R["problems"]))
    dt = R["outputs"].get("deploytag", {}).get("DEPLOY_TAG", "")
    if ref == "main":
        for svc in SERVICES:
            b = next((s for s in ST if is_build(s, True) and svc in s.get("name", "")), None)
            m = re.search(r"steps\.([\w-]+)\.outputs\.tags", str((b or {}).get("with", {}).get("tags", "")))
            mid = m.group(1) if m else None
            img = R["meta"].get(mid, ("", []))[0]
            check("%s is pushed with tags from its own image-tags step, named for %s" % (svc, svc),
                  b is not None and mid and img.endswith("/" + svc) and ids.count(mid) == 1,
                  "build step %r, tags from %r, image %r" % ((b or {}).get("name"), mid, img))
    missing = [p for p in patched if dt not in R["pushed"].get(base + "/" + p, set())]
    check("push to %s: every image the deploy step writes (%s) carries a tag this run pushed (deploy tag %r)"
          % (ref, ", ".join(patched) or "none", dt), patched and dt and not missing,
          "; ".join("%s pushed %s" % (p, sorted(R["pushed"].get(base + "/" + p, []))) for p in missing))
    extra = {p: sorted(t - {dt}) for p, t in R["pushed"].items() if t - {dt}}
    check("push to %s: the build pushes only the commit's tag (%s); no moving tag before the smoke test" % (ref, dt),
          dt and not extra, "also pushed: %s" % extra)
    made = set(re.findall(r"imagetools create -t \S+?/([\w-]+):(\S+) ", R["docker"]))
    want = {(svc, t) for svc in SERVICES for t in moving_tags(ref)}
    check("push to %s: after the smoke test passes, every service gets its moving tags (%s) on that version"
          % (ref, ", ".join(sorted(moving_tags(ref)))), want <= made, "made: %s" % sorted(made))

# the deploy tag has one source: the image-tags step's own output
dts = next((s for s in ST if s.get("id") == "deploytag"), {})
check("the deploy tag is read from an image-tags step's output, not recomputed from the commit",
      re.search(r"steps\.meta-[\w-]+\.outputs\.version", str(dts.get("env", ""))) is not None
      and "GITHUB_SHA" not in dts.get("run", ""))

# a smoke test that fails: the run stops there, with the app's log printed, the throwaway containers removed, and no
# moving tag and no deploy-branch change
for label, steps in (("an app whose check fails", ST), ("an app with no health check that exits at once", ST_NOHEALTH)):
    R = simulate("main", steps, mode="crash")
    smoke = next((n for n in R["ran"] if n.lower().startswith("smoke")), None)
    rc, out = R["out"].get(smoke, (0, ""))
    check("%s: the smoke test fails (exit %d) and prints the app's log" % (label, rc),
          smoke and rc != 0 and "SMOKE-LOG-MARK" in out and R["failed"] == smoke, out.strip()[-300:])
    check("%s: no moving tag is added and the deploy branch is not written" % label,
          "imagetools" not in R["docker"] and not any("Mirror" in n for n in R["ran"]),
          "ran after the smoke test: %s" % R["ran"][R["ran"].index(smoke) + 1:] if smoke in R["ran"] else R["ran"])
    seg = R["docker"].split("STEP " + (smoke or "?"), 1)[-1].split("STEP ", 1)[0]
    check("%s: the throwaway app, database and network are removed" % label,
          "docker rm -f" in seg and "docker network rm" in seg, seg[-300:])
R = simulate("main")
smoke = next((n for n in R["ran"] if n.lower().startswith("smoke")), "?")
seg = R["docker"].split("STEP " + smoke, 1)[-1].split("STEP ", 1)[0]
check("an app that starts: the throwaway app, database and network are removed too",
      "docker rm -f" in seg and "docker network rm" in seg, seg[-300:])
check("the smoke test has a time limit of its own (timeout-minutes) and each check is cut off (timeout)",
      all("timeout-minutes" in s and "timeout " in s["run"] for s in ST if s.get("name", "").lower().startswith("smoke")))

# a failed check must stop the run: no continue-on-error on the smoke test or any step it depends on, and no
# always()/failure()/cancelled() on the steps that tag, check out the deploy branch, mirror or push after it
first_smoke = min(smoke_at_early) if (smoke_at_early := [i for i, s in enumerate(ST) if s.get("name", "").lower().startswith("smoke")]) else len(ST)
coe = [s.get("name") for s in ST if s.get("continue-on-error") not in (None, False, "false")]
check("no step carries continue-on-error (a failed build, check or smoke test would let the tagging and the deploy go "
      "ahead)", not coe, "continue-on-error on: %s" % coe)
after = [s for s in ST[first_smoke:]]
loose = [s.get("name") for s in after if re.search(r"\b(always|failure|cancelled)\s*\(", str(s.get("if", "")))]
check("no step from the smoke test on runs after a failure (no always(), failure() or cancelled() in its if:)",
      not loose and after, "if: lets these run after a failure: %s" % loose)

# pull requests: the migration check runs; their concurrency group is their own, cancelling their own older builds
P = simulate("feature-x", event="pull_request")
check("on a pull request the migration check runs (it only reads files)",
      any("migration" in n.lower() for n in P["ran"]), "ran: %s" % P["ran"])
conc = wf.get("concurrency") or {}
def conc_of(ctx):
    return (str(subst(conc.get("group", ""), ctx, {}, [], "")), truthy(subst(conc.get("cancel-in-progress", False), ctx, {}, [], "")))
pr1 = conc_of({"event_name": "pull_request", "ref": "refs/pull/7/merge", "ref_name": "7/merge"})
pr2 = conc_of({"event_name": "pull_request", "ref": "refs/pull/8/merge", "ref_name": "8/merge"})
pu1 = conc_of({"event_name": "push", "ref": "refs/heads/main", "ref_name": "main"})
pu2 = conc_of({"event_name": "push", "ref": "refs/heads/feature-x", "ref_name": "feature-x"})
check("pushes share one group per deploy branch and never cancel a running deploy; each pull request has its own "
      "group, apart from the deploys", pu1 == pu2 and pu1[1] is False and pr1[0] != pr2[0]
      and pu1[0] not in (pr1[0], pr2[0]) and pr1[1] is True, "push %s %s; pull requests %s %s" % (pu1, pu2, pr1, pr2))

# the token: only the deploy checkout keeps it
co = [s for s in ST if str(s.get("uses", "")).startswith("actions/checkout")]
src_co = [s for s in co if not (s.get("with") or {}).get("path")]
dep_co = [s for s in co if (s.get("with") or {}).get("path")]
check("the source checkout keeps no token (persist-credentials: false); the deploy checkout, which pushes, keeps it",
      src_co and all(str((s.get("with") or {}).get("persist-credentials")).lower() == "false" for s in src_co)
      and dep_co and all(str((s.get("with") or {}).get("persist-credentials")).lower() == "true" for s in dep_co))

# contexts
for svc in SERVICES:
    b = next((s for s in ST if is_build(s, True) and svc in s.get("name", "")), {})
    w = b.get("with") or {}
    ctx_used = os.path.normpath(str(w.get("context", "")))
    file_used = os.path.normpath(str(w.get("file") or os.path.join(ctx_used, "Dockerfile")))
    ok_ctx = ctx_used == CTX[svc][0] and file_used == CTX[svc][1] \
        and os.path.isfile(os.path.join(scaffold, file_used)) \
        and (file_used + "/").startswith(ctx_used.rstrip("/") + "/")
    check("%s is built from its docker-compose.yml context (%s, %s) and that context holds its Dockerfile"
          % (svc, CTX[svc][0], CTX[svc][1]), ok_ctx, "the workflow builds it from %s with %s" % (ctx_used, file_used))

# order
names = [s.get("name", "") for s in ST]
def pos(pred):
    return [i for i, s in enumerate(ST) if pred(s)]
push_at = {svc: pos(lambda s, v=svc: is_build(s, True) and v in s.get("name", "")) for svc in SERVICES}
smoke_at = pos(lambda s: "run" in s and "docker run" in s["run"] and "IMAGE" in s["run"])
tag_at = pos(lambda s: s.get("id") == "deploytag")
moving_at = pos(lambda s: "run" in s and "imagetools create" in s["run"])
mirror_at = pos(lambda s: "run" in s and "rsync" in s["run"])
bad_order = []
for i in smoke_at:
    svc = next((v for v in SERVICES if v in ST[i].get("name", "") or "/%s:" % v in ST[i]["run"]), None)
    if svc and (not push_at[svc] or i < max(push_at[svc])):
        bad_order.append("%r runs before %s is pushed" % (names[i], svc))
    if not tag_at or i < tag_at[0]:
        bad_order.append("%r runs before the deploy tag is set" % names[i])
if not moving_at or (smoke_at and moving_at[0] < max(smoke_at)):
    bad_order.append("the moving tags are not added after the smoke test")
all_push = [i for v in push_at.values() for i in v]
if mirror_at and all_push and mirror_at[0] < max(all_push + smoke_at):
    bad_order.append("the deploy branch is written before every image is pushed and smoke-tested")
check("nothing starts an image before it is pushed, the deploy tag comes before the smoke test, the moving tags "
      "and the deploy branch come after it", smoke_at and not bad_order, "\n".join(bad_order) or "no smoke test step found")

# the mirror: top-level .git, .github and deploy stay out; nested ones of the same names are mirrored. Run with real
# rsync and find (the mirror body uses nothing past bash 3), yq and git stubbed.
mr = ST[mirror_at[0]]["run"] if mirror_at else ""
def mirror_fixture():
    d = tempfile.mkdtemp(dir=TMP)
    w = lambda rel, txt="x": (os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True), open(os.path.join(d, rel), "w").write(txt))
    w(".github/workflows/new.yml"); w("frontend/.github/a.txt"); w("backend/app/deploy/b.txt"); w("scripts/deploy")
    w("app.txt"); w("deploy/.git/HEAD"); w("deploy/.github/keep.yml"); w("deploy/stale.txt")
    stubs = tempfile.mkdtemp(dir=TMP)
    for n in ("yq", "git"):
        open(os.path.join(stubs, n), "w").write("#!/bin/sh\nexit 0\n"); os.chmod(os.path.join(stubs, n), 0o755)
    env = dict(os.environ, PATH=stubs + ":" + os.environ["PATH"], IMAGE_BASE_LC="x", DEPLOY_TAG="sha-1",
               BACKEND_TARGET="none.yaml", FRONTEND_TARGET="none.yaml", BACKEND_CONTAINER="b", FRONTEND_CONTAINER="f",
               DEPLOY_BRANCH="deploy-nonprod", GITHUB_REF_NAME="main", TARGET_FILE="none.yaml", CONTAINER_NAME="c")
    r = subprocess.run(["bash", "-c", mr], cwd=d, env=env, capture_output=True, text=True)
    has = lambda rel: os.path.exists(os.path.join(d, "deploy", rel))
    res = {"nested .github mirrored": has("frontend/.github/a.txt"), "nested deploy folder mirrored": has("backend/app/deploy/b.txt"),
           "a file named deploy mirrored": has("scripts/deploy"), "top .github not taken": not has(".github/workflows/new.yml"),
           "the deploy branch's .github kept": has(".github/keep.yml"), "no deploy/deploy": not has("deploy"),
           "stale files removed": not has("stale.txt"), "the source mirrored": has("app.txt")}
    return r, res
if shutil.which("rsync") and mr:
    r, res = mirror_fixture()
    check("the mirror leaves the top-level .github/, .git and deploy out and mirrors nested ones of the same names",
          all(res.values()), "; ".join(k for k, v in res.items() if not v) + " " + (r.stderr or "")[-200:])
else:
    check("the mirror can be checked (rsync on this machine, and a mirror step)", False)

# the live version never runs the practice sign-in: a step on every run, before the deploy branch is written
live = [i for i, s in enumerate(ST) if "run" in s and "PRACTICE_ACCESS_CODE" in s["run"] and "/prod" in s["run"]]
check("a step refuses the practice sign-in in the live version, on every run (no if:), before the deploy branch is touched",
      live and "if" not in ST[live[0]] and all(live[0] < i for i in pos(lambda s: str(s.get("uses", "")).startswith("actions/checkout")
      and (s.get("with") or {}).get("path")) + mirror_at), [ST[i].get("name") for i in live])
if live:
    def run_live(files):
        d = tempfile.mkdtemp(dir=TMP)
        for rel, txt in files.items():
            os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True); open(os.path.join(d, rel), "w").write(txt)
        r = run_bash(["-euo", "pipefail", "-c", ST[live[0]]["run"]], d, dict(os.environ, PATH=STUBS + ":" + os.environ["PATH"]))
        shutil.rmtree(d, ignore_errors=True)
        return r.returncode
    check("that step passes a clean live folder, stops on the practice sign-in in it (a hand edit too), and fails when there is no live folder",
          run_live({"env/prod/kustomization.yaml": "resources:\n- a.yaml\n", "env/prod/a.yaml": "image: x/backend:prod-latest\n", "env/dev/mock-oidc.yaml": "x\n"}) == 0
          and run_live({"env/prod/kustomization.yaml": "resources:\n- a.yaml\n", "env/prod/a.yaml": "image: x/mock-oidc:sha-1\n"}) == 1
          and run_live({"env/dev/mock-oidc.yaml": "x\n"}) == 2)
mr_txt = ST[mirror_at[0]]["run"] if mirror_at else ""
check("the workflow patches and fills the practice sign-in only in the test copy's folder, never the live version's",
      ("mock-oidc" not in mr_txt) or ("deploy/env/dev/mock-oidc.yaml" in mr_txt and "env/prod" not in mr_txt
      and not re.search(r"(?m)^(?!\s*#).*(seed-mock-services|mock-oidc-people)", mr_txt)), mr_txt[-600:])

# the migration check on fixtures
vstep = next((s for s in ST if "run" in s and "MIGRATIONS_DIR" in s["run"]), None)
def run_validate(files, extra=None):
    d = tempfile.mkdtemp(dir=TMP)
    v = os.path.join(d, "backend", "alembic", "versions")
    os.makedirs(v)
    for n, body in files.items():
        open(os.path.join(v, n), "w").write(body)
    if extra:
        extra(v)
    sc = os.path.join(d, "validate.sh")
    open(sc, "w").write(vstep["run"])
    r = run_bash(["-euo", "pipefail", sc], d, dict(os.environ, PATH=STUBS + ":" + os.environ["PATH"]))
    shutil.rmtree(d, ignore_errors=True)
    return r.returncode, r.stdout + r.stderr
vdir = os.path.join(scaffold, "backend", "alembic", "versions")
scaf = {n: open(os.path.join(vdir, n)).read() for n in os.listdir(vdir) if n.endswith(".py")}
T = 'from typing import Union\nrevision: str = "%s"\ndown_revision: Union[str, None] = %s\n'
def loud(rc, out, fname):
    return rc != 0 and fname in out and "Traceback" not in out
if vstep:
    rc, out = run_validate(scaf)
    check("the migration check passes on the scaffold's own Alembic files (typed headers)", rc == 0, out.strip()[-300:] or "exit %d, no output" % rc)
    rc, out = run_validate(dict(scaf, **{"009_orphan.py": T % ("009", '"008"')}))
    check("the migration check fails on a down_revision no file declares, naming the file", loud(rc, out, "009_orphan.py"), "exit %d: %s" % (rc, out.strip()[-300:]))
    plain = {"a1.py": 'revision = "a1"\ndown_revision = None\n', "a2.py": "revision = 'a2'\ndown_revision = 'a1'\n"}
    rc, out = run_validate(plain)
    check("the migration check passes on plain headers (revision = ...)", rc == 0, out.strip()[-300:])
    rc, out = run_validate(dict(plain, **{"a3.py": 'revision = "a3"\ndown_revision = "zz"\n'}))
    check("the migration check fails on a plain-header break, naming the file", loud(rc, out, "a3.py"), "exit %d: %s" % (rc, out.strip()[-300:]))
    rc, out = run_validate(dict(plain, **{"a2_copy.py": "revision = 'a2'\ndown_revision = 'a1'\n"}))
    check("the migration check fails on two files declaring the same revision, naming them",
          rc != 0 and "a2_copy.py" in out and "a2.py" in out and "also declared" in out, "exit %d: %s" % (rc, out.strip()[-300:]))
    rc, out = run_validate(dict(plain, **{"b2.py": "revision = 'b2'\ndown_revision = 'a1'\n"}))
    check("the migration check fails on a chain with two heads", rc != 0 and "heads" in out, "exit %d: %s" % (rc, out.strip()[-300:]))
    rc, out = run_validate(dict(plain, **{"a3.py": "revision = ['a3']\ndown_revision = 'a2'\n"}))
    check("the migration check fails, naming the file, on a revision that isn't a name (no traceback)", loud(rc, out, "a3.py"), "exit %d: %s" % (rc, out.strip()[-300:]))
    rc, out = run_validate(plain, lambda v: os.makedirs(os.path.join(v, "x.py")))
    check("the migration check fails, naming it, on a folder named like a migration (no traceback)", loud(rc, out, "x.py"), "exit %d: %s" % (rc, out.strip()[-300:]))
    rc, out = run_validate(plain, lambda v: os.symlink(os.path.join(v, "gone.lock"), os.path.join(v, "link.py")))
    check("the migration check fails, naming it, on a link to a missing file (no traceback)", loud(rc, out, "link.py"), "exit %d: %s" % (rc, out.strip()[-300:]))
    def planted(v):
        root = os.path.dirname(os.path.dirname(os.path.dirname(v)))
        for mod in ("ast", "json", "os", "sys"):
            open(os.path.join(root, mod + ".py"), "w").write(
                "open(%r, 'w').write('ran')\n" % os.path.join(root, "MARKER-" + mod))
    MARKS = []
    def run_planted(files):
        d = tempfile.mkdtemp(dir=TMP)
        v = os.path.join(d, "backend", "alembic", "versions")
        os.makedirs(v)
        for n, body in files.items():
            open(os.path.join(v, n), "w").write(body)
        planted(v)
        sc = os.path.join(d, "validate.sh")
        open(sc, "w").write(vstep["run"])
        r = run_bash(["-euo", "pipefail", sc], d, dict(os.environ, PATH=STUBS + ":" + os.environ["PATH"]))
        found = sorted(f for f in os.listdir(d) if f.startswith("MARKER-"))
        shutil.rmtree(d, ignore_errors=True)
        return r.returncode, found
    rc, found = run_planted(plain)
    check("the migration check runs no module from the repository (ast.py, json.py, os.py, sys.py at its root): "
          "its python is isolated", not found and rc == 0, "these ran: %s (exit %d)" % (found, rc))
    pys = [l.strip() for s_ in ST if "run" in s_ for l in s_["run"].splitlines()
           if re.match(r"\s*(?:\S+=\S+\s+)*python3?\b(?!\s+-I\b)", l) and "docker" not in l]
    check("every python the workflow runs on the runner is started isolated (python3 -I)", not pys, "\n".join(pys))
else:
    check("the workflow has a migration check", False)
shutil.rmtree(TMP, ignore_errors=True)
sys.exit(1 if failed else 0)
PY
[ -s "$ERRF" ] && { echo "FAIL stderr was written (shown below)"; fail=1; }
exit $fail
