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
python3 - "$DOC" "$SCAFFOLD" <<'PY' || fail=1
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
        return "true"
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

# expand {service}
expanded = []
for t in steps:
    if "{service}" in t:
        who = DB_SERVICES if "smoke" in step_name(t).lower() else SERVICES
        for n in who:
            expanded.append((n, t.replace("{service}", n)))
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
        e = e.replace("{service}", svc or "")
        if name == e or (e and name.startswith(e)):
            return (int(k), SERVICES.index(svc) if svc in SERVICES else 0)
    return (999, idx)
ordered = [it[1] for it in sorted(enumerate(expanded), key=order_key)]

# fill the remaining placeholders the way the text says
splitctx = {k.lower(): v.strip() for k, v in re.findall(r"^- (\w+): `context: ([^`]+)`", phase, re.M)}
def fill(t, svc):
    if svc:
        ctx, df = CTX[svc]
        if svc in splitctx:   # the text names this service's context: use it, as an agent would
            ctx = os.path.normpath(splitctx[svc])
        t = t.replace("./{build_context}", "./" + ctx).replace("{build_context}", ctx)
        t = t.replace("./{dockerfile_path}", "./" + CTX[svc][1]).replace("{dockerfile_path}", CTX[svc][1])
        if svc in DB_SERVICES:
            t = t.replace("{database_url_scheme}", scheme(svc)).replace("{healthcheck_command}", health(svc))
    return (t.replace("{db_image}", dbimg).replace("{deploy_branch}", "deploy-nonprod")
             .replace("{registry_host}/{image_base_path}", "ghcr.io/example/myapp")
             .replace("{manifest_dir}", "env").replace("{app}", "myapp"))
body_steps = [fill(t, s) for s, t in ordered]
wf_text = (fill(header, None) + "\n" + fill(envsplit, None) + "\n" + fill(jobs_head, None) + "    steps:\n"
           + "\n".join(body_steps) + "\n")
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
ids = [s.get("id") for s in ST if s.get("id")]
dup = sorted(set(x for x in ids if ids.count(x) > 1))
check("every step id is unique (one image-tags step per service, each with its own id)", not dup, "repeated: %s" % dup)
check("the order of the steps is stated in the text", ORDER_GIVEN, "PHASE 3 gives no numbered step order")
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
    cmd = ["docker", "run", "--rm", "--name", "argoit-workflow-test-%d-%d" % (os.getpid(), RUNS[0]), "-v", "%s:%s" % (TMP, TMP), "-w", cwd, "--env-file", envf,
           "-e", "PATH=%s:/usr/local/bin:/usr/bin:/bin" % STUBS, "python:3.12-slim", "bash"] + args
    return subprocess.run(cmd, capture_output=True, text=True)
STUBS = tempfile.mkdtemp(dir=TMP)
def stub(name, script):
    p = os.path.join(STUBS, name)
    open(p, "w").write("#!/usr/bin/env bash\n" + script + "\n")
    os.chmod(p, 0o755)
stub("docker", 'case "$1" in ps) echo x;; esac; exit 0')
stub("yq", "exit 0")
stub("rsync", "exit 0")
stub("sudo", "exit 0")
stub("git", 'exit 0')
stub("curl", 'while [ $# -gt 0 ]; do [ "$1" = -o ] && : > "$2"; shift; done; exit 0')

def expr_value(e, ctx, outputs, problems, who):
    e = e.strip()
    m = re.fullmatch(r"steps\.([\w-]+)\.outputs\.(\w+)", e)
    if m:
        sid, key = m.groups()
        if sid not in outputs or key not in outputs[sid]:
            problems.append("%s reads steps.%s.outputs.%s before that step ran and set it" % (who, sid, key))
            return ""
        return outputs[sid][key]
    m = re.fullmatch(r"env\.(\w+)", e)
    if m:
        return WENV.get(m.group(1), "")
    m = re.fullmatch(r"github\.(\w+)", e)
    if m:
        return ctx.get(m.group(1), "")
    if e.startswith("secrets."):
        return "stub-secret"
    m = re.fullmatch(r"github\.(\w+) (==|!=) '([^']*)'", e)
    if m:
        a, op, b = m.groups()
        return str((ctx.get(a, "") == b) == (op == "=="))
    return "<<%s>>" % e
def subst(s, ctx, outputs, problems, who):
    return re.sub(r"\$\{\{(.*?)\}\}", lambda m: expr_value(m.group(1), ctx, outputs, problems, who), str(s))
def cond(step, ctx):
    c = str(step.get("if", "true"))
    m = re.search(r"github\.event_name (==|!=) 'pull_request'", c)
    if m:
        return (ctx["event_name"] == "pull_request") == (m.group(1) == "==")
    m = re.search(r"github\.ref_name != '([^']+)'", c)
    if m:
        return ctx["ref_name"] != m.group(1)
    return True
def meta_tags(step, ctx):
    w = step.get("with") or {}
    img = subst(w.get("images", ""), ctx, {}, [], "")
    out = []
    for line in str(w.get("tags", "")).splitlines():
        line = line.strip()
        if not line:
            continue
        kv = dict(x.split("=", 1) for x in line.split(",") if "=" in x)
        en = kv.get("enable")
        if en is not None and subst(en, ctx, {}, [], "") not in ("True", "true"):
            continue
        if kv.get("type") == "raw":
            out.append(kv["value"])
        elif kv.get("type") == "sha":
            out.append(kv.get("prefix", "sha-") + ctx["sha"][:7])
        elif kv.get("type") == "ref" and kv.get("event") == "branch" and ctx["event_name"] != "pull_request":
            out.append(re.sub(r"[^\w.-]", "-", ctx["ref_name"]))
    return img, out

def simulate(ref_name):
    ctx = {"event_name": "push", "ref_name": ref_name, "ref": "refs/heads/" + ref_name,
           "sha": "0123456789abcdef0123456789abcdef01234567", "actor": "someone"}
    work = tempfile.mkdtemp(dir=TMP)
    shutil.copytree(scaffold, os.path.join(work, "src"))
    src = os.path.join(work, "src")
    outputs, problems, pushed, runs, order_log = {}, [], {}, [], []
    meta = {}
    for idx, s in enumerate(ST):
        name = s.get("name", s.get("uses", "?"))
        if not cond(s, ctx):
            continue
        order_log.append(name)
        sid = s.get("id")
        uses = s.get("uses", "")
        if uses.startswith("docker/metadata-action"):
            img, tags = meta_tags(s, ctx)
            meta[sid] = (img, tags)
            outputs[sid] = {"tags": "\n".join(img + ":" + t for t in tags)}
        elif uses.startswith("docker/build-push-action"):
            w = s.get("with") or {}
            tags = subst(w.get("tags", ""), ctx, outputs, problems, name)
            if str(w.get("push")).lower() == "true":
                for t in tags.split("\n"):
                    if ":" in t:
                        pushed.setdefault(t.rsplit(":", 1)[0], set()).add(t.rsplit(":", 1)[1])
            runs.append(("build", idx, name, w))
        elif uses.startswith("actions/checkout") and (s.get("with") or {}).get("path"):
            os.makedirs(os.path.join(src, s["with"]["path"], ".github"), exist_ok=True)
        elif "run" in s:
            env = dict(os.environ)
            env.update(WENV)
            env.update({"GITHUB_SHA": ctx["sha"], "GITHUB_REF_NAME": ref_name, "GITHUB_REF": ctx["ref"],
                        "GITHUB_RUN_ID": "42", "PATH": STUBS + ":" + os.environ["PATH"]})
            for k, v in (s.get("env") or {}).items():
                env[k] = subst(v, ctx, outputs, problems, name)
            outf = os.path.join(work, "out-%d" % idx)
            open(outf, "w").close()
            env["GITHUB_OUTPUT"] = outf
            script = os.path.join(work, "step-%d.sh" % idx)
            open(script, "w").write(s["run"])
            syn = run_bash(["-n", script], src, env)
            if syn.returncode:
                problems.append("%s: not valid bash: %s" % (name, syn.stderr.strip()))
                continue
            r = run_bash(["-euo", "pipefail", script], src, env)
            runs.append(("run", idx, name, s["run"]))
            if r.returncode:
                problems.append("%s: exit %d: %s" % (name, r.returncode, (r.stderr or r.stdout).strip()[-300:]))
            if sid:
                outputs[sid] = dict(l.split("=", 1) for l in open(outf).read().splitlines() if "=" in l)
    shutil.rmtree(work, ignore_errors=True)
    return outputs, problems, pushed, runs, meta, ctx

for ref in ("main", "feature-x"):
    outputs, problems, pushed, runs, meta, ctx = simulate(ref)
    check("push to %s: every run: body is valid bash and runs to the end under set -euo pipefail, every variable "
          "and step output set before it is used" % ref, not problems, "\n".join(problems))
    # tags: each service's push uses its own image-tags step
    for svc in SERVICES:
        b = next((s for s in ST if str(s.get("uses", "")).startswith("docker/build-push-action")
                  and str((s.get("with") or {}).get("push")).lower() == "true" and svc in s.get("name", "")), None)
        tagexpr = str((b or {}).get("with", {}).get("tags", ""))
        m = re.search(r"steps\.([\w-]+)\.outputs\.tags", tagexpr)
        mid = m.group(1) if m else None
        img = meta.get(mid, ("", []))[0]
        if ref == "main":
            check("%s is pushed with tags from its own image-tags step, named for %s" % (svc, svc),
                  b is not None and mid and img.endswith("/" + svc) and ids.count(mid) == 1,
                  "build step %r, tags from %r, image %r" % ((b or {}).get("name"), mid, img))
    # the deploy step writes tags this run built
    mirror = next((s for s in ST if "run" in s and "rsync" in s["run"]), None)
    dt = outputs.get("deploytag", {}).get("DEPLOY_TAG", "")
    patched = re.findall(r'"/([\w-]+):" \+ env\(DEPLOY_TAG\)', (mirror or {}).get("run", ""))
    base = WENV.get("IMAGE_BASE", "").lower()
    missing = [p for p in sorted(set(patched)) if dt not in pushed.get(base + "/" + p, set())]
    check("push to %s: every image the deploy step writes (%s) carries a tag this run pushed (deploy tag %r)"
          % (ref, ", ".join(sorted(set(patched))) or "none", dt),
          patched and dt and not missing,
          "; ".join("%s pushed %s" % (p, sorted(pushed.get(base + "/" + p, []))) for p in missing))

# contexts
for svc in SERVICES:
    b = next((s for s in ST if str(s.get("uses", "")).startswith("docker/build-push-action")
              and str((s.get("with") or {}).get("push")).lower() == "true" and svc in s.get("name", "")), {})
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
push_at = {svc: pos(lambda s, v=svc: str(s.get("uses", "")).startswith("docker/build-push-action")
                    and str((s.get("with") or {}).get("push")).lower() == "true" and v in s.get("name", ""))
           for svc in SERVICES}
smoke_at = pos(lambda s: "run" in s and "docker run" in s["run"] and "IMAGE" in s["run"])
tag_at = pos(lambda s: s.get("id") == "deploytag")
mirror_at = pos(lambda s: "run" in s and "rsync" in s["run"])
bad_order = []
for i in smoke_at:
    svc = next((v for v in SERVICES if v in ST[i].get("name", "") or "/%s:" % v in ST[i]["run"]), None)
    if svc and (not push_at[svc] or i < max(push_at[svc])):
        bad_order.append("%r runs before %s is pushed" % (names[i], svc))
    if not tag_at or i < tag_at[0]:
        bad_order.append("%r runs before the deploy tag is set" % names[i])
all_push = [i for v in push_at.values() for i in v]
if mirror_at and all_push and mirror_at[0] < max(all_push):
    bad_order.append("the deploy branch is written before every image is pushed")
check("nothing starts an image before it is pushed, the deploy tag comes before the smoke test, the deploy "
      "branch is written last", smoke_at and not bad_order, "\n".join(bad_order) or "no smoke test step found")

# .github stays out of the mirror
mr = ST[mirror_at[0]]["run"] if mirror_at else ""
check("the mirror to the deploy branch leaves .github/ out (rsync excludes it, the cleanup keeps it)",
      "--exclude '.github'" in mr and "! -name '.github'" in mr)

# the migration check on fixtures
vstep = next((s for s in ST if "run" in s and "MIGRATIONS_DIR" in s["run"]), None)
def run_validate(files):
    d = tempfile.mkdtemp(dir=TMP)
    v = os.path.join(d, "backend", "alembic", "versions")
    os.makedirs(v)
    for n, body in files.items():
        open(os.path.join(v, n), "w").write(body)
    sc = os.path.join(d, "validate.sh")
    open(sc, "w").write(vstep["run"])
    r = run_bash(["-euo", "pipefail", sc], d, dict(os.environ, PATH=STUBS + ":" + os.environ["PATH"]))
    shutil.rmtree(d, ignore_errors=True)
    return r.returncode, r.stdout + r.stderr
vdir = os.path.join(scaffold, "backend", "alembic", "versions")
scaf = {n: open(os.path.join(vdir, n)).read() for n in os.listdir(vdir) if n.endswith(".py")}
if vstep:
    rc, out = run_validate(scaf)
    check("the migration check passes on the scaffold's own Alembic files (typed headers)", rc == 0, out.strip()[-300:] or "exit %d, no output" % rc)
    typed_break = dict(scaf)
    typed_break["009_orphan.py"] = ('from typing import Union\nrevision: str = "009"\n'
                                    'down_revision: Union[str, None] = "008"\n')
    rc, out = run_validate(typed_break)
    check("the migration check fails on a down_revision no file declares, naming the file",
          rc != 0 and "009_orphan.py" in out, "exit %d: %s" % (rc, out.strip()[-300:]))
    plain = {"a1.py": 'revision = "a1"\ndown_revision = None\n', "a2.py": "revision = 'a2'\ndown_revision = 'a1'\n"}
    rc, out = run_validate(plain)
    check("the migration check passes on plain headers (revision = ...)", rc == 0, out.strip()[-300:])
    plain["a3.py"] = 'revision = "a3"\ndown_revision = "zz"\n'
    rc, out = run_validate(plain)
    check("the migration check fails on a plain-header break, naming the file", rc != 0 and "a3.py" in out,
          "exit %d: %s" % (rc, out.strip()[-300:]))
else:
    check("the workflow has a migration check", False)
shutil.rmtree(TMP, ignore_errors=True)
sys.exit(1 if failed else 0)
PY
[ -s "$ERRF" ] && { echo "FAIL stderr was written (shown below)"; fail=1; }
exit $fail
