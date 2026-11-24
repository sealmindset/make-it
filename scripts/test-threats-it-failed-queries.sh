#!/usr/bin/env bash
# /threats-it: a query that failed is named as failed, in every script, and is never read as "nothing found" (E02-S110).
# The one rule (scripts/_common.py failed() + finish()): every query is ok or failed; each failed one is printed as
#   FAILED: <query> in <workspace or service> (<status>)
# the summary never says "none", "no licence" or "missing" for something that was not looked at, the script's JSON
# carries the same list as "failed_queries", and the script exits 3. A query that worked and found nothing still reads "none".
#
# Every script is RUN, unchanged, against a stand-in on localhost (scripts/threats-it-stand-in/): a fake Microsoft
# Graph, Resource Graph, Log Analytics and attack.mitre.org that can answer 200 with fixtures, 403, 429, 500, a
# timeout, cut-off JSON, or a successful empty result, plus a fake `az`. No real tenant, no network beyond 127.0.0.1.
# Also here: build.sh leaves no earlier PDF behind when any document fails, and a refused fetch leaves no partial page.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
TI="$root/.claude/make-it/threats-it"
SI="$root/scripts/threats-it-stand-in"
fail=0
check() { local name="$1"; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi; }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"

python3 -I - "$TI" "$SI" <<'PY' || fail=1
import json, os, shutil, subprocess, sys, tempfile, time
TI, SI = sys.argv[1:3]
tmp = tempfile.mkdtemp()
portf, scen = tmp + "/port", tmp + "/scenario.json"
open(scen, "w").write("[]")
srv = subprocess.Popen([sys.executable, "-I", SI + "/server.py", portf, scen])
bad, said = False, []


def check(name, cond):
    global bad
    print(("ok   " if cond else "FAIL ") + name)
    bad |= not cond


def run(script, args, rules, base=None):
    od = tempfile.mkdtemp(dir=tmp)
    if base:
        shutil.copytree(base, od, dirs_exist_ok=True)
    json.dump(rules, open(scen, "w"))
    env = dict(os.environ, PATH=SI + os.pathsep + os.environ["PATH"])
    p = subprocess.run([sys.executable, "-I", SI + "/run.py", port, f"{TI}/scripts/{script}", *[a.replace("@", od) for a in args]],
                       capture_output=True, text=True, env=env, timeout=180)
    said.append(p.stdout + p.stderr)
    return p.returncode, p.stdout + p.stderr, od


def failed(name, got, *named, never=()):
    """The shared rule: exit 3, no crash, every word of the failure named, and none of the clean-sounding words."""
    rc, out, _ = got
    check(f"{name}: exits 3", rc == 3)
    check(f"{name}: named as FAILED ({', '.join(named)})", "Traceback" not in out and any(
        l.startswith("FAILED: ") and all(n in l for n in named) for l in out.splitlines()))
    check(f"{name}: says NOT ASSESSED", "NOT ASSESSED" in out)
    for n in never:
        check(f"{name}: never reads '{n}'", n not in out)


def js(path, *keys):
    """A value from a script's JSON output; None when the script wrote no such file or key."""
    try:
        v = json.load(open(path))
        for k in keys:
            v = v[k]
        return v
    except (OSError, ValueError, KeyError, TypeError):
        return None


def clean(name, got, *has):
    rc, out, _ = got
    check(f"{name}: exits 0 with no FAILED line", rc == 0 and "FAILED: " not in out and "NOT ASSESSED" not in out)
    for h in has:
        check(f"{name}: reads '{h}'", h in out)


try:
    for _ in range(100):
        if os.path.exists(portf) and open(portf).read().strip():
            break
        time.sleep(0.1)
    port = open(portf).read().strip()
    ioc, pres, fix = tmp + "/ioc.json", tmp + "/presence.json", tmp + "/fix.json"
    json.dump({"name": "t", "ips": ["203.0.113.9"], "domains": ["evil.example"], "window_start": "2026-10-10"}, open(ioc, "w"))
    json.dump({"Palo Alto PAN-OS": {"app_names": "vendor backup", "arm_publisher": "paloalto"}}, open(pres, "w"))
    json.dump({"CVE-2026-0001": {"fixed_builds": {"Windows Server 2022": ["KB1 10.0.20348.500"]}}}, open(fix, "w"))
    EMPTY = [{"when": [""], "mode": "empty"}]
    # "the queries work and find nothing": Usage still lists the tables, everything else answers empty
    empty_finds = lambda *keep: [{"when": [k], "mode": "pass"} for k in ("Usage", "operationalinsights") + keep] + EMPTY

    # ---- tenant_access.py --------------------------------------------------------------------------------------
    T = "tenant_access.py"
    base = run(T, ["@"], [])
    clean("tenant_access, healthy", base, '"entra_p2": true', "sentinel=True")
    base = base[2]
    failed("tenant_access, licence query 403", run(T, ["@"], [{"when": ["subscribedSkus"], "status": 403}]),
           "licences", "Microsoft Graph", "HTTP 403", never=('"entra_p2": false',))
    got = run(T, ["@"], [{"when": ["ResourceGraph", "SecurityInsights"], "status": 403}])
    failed("tenant_access, Sentinel query 403", got, "Sentinel", "Resource Graph", "HTTP 403", never=("sentinel=False",))
    check("tenant_access, Sentinel query 403: access.json carries the failed query",
          any("Sentinel" in f["query"] for f in js(got[2] + "/access.json", "failed_queries") or []))
    failed("tenant_access, workspace list 500", run(T, ["@"], [{"when": ["ResourceGraph", "operationalinsights"], "status": 500}]),
           "workspace list", "Resource Graph", "HTTP 500")
    failed("tenant_access, one workspace's Usage 403", run(T, ["@"], [{"when": ["cid-ws-b", "Usage"], "status": 403}]),
           "ws-b", "HTTP 403")
    failed("tenant_access, organization timeout", run(T, ["@"], [{"when": ["/organization"], "mode": "timeout"}]),
           "tenant", "Microsoft Graph", "timeout")
    failed("tenant_access, a probe times out", run(T, ["@"], [{"when": ["auditLogs/signIns"], "mode": "timeout"}]),
           "probe graph_signins", "Microsoft Graph", "timeout")
    clean("tenant_access, a probe answers 403 (that is the probe's finding)", run(T, ["@"], [{"when": ["auditLogs/signIns"], "status": 403}]),
          '"status": 403')
    clean("tenant_access, no licences and no Sentinel (the queries worked)", run(T, ["@"], empty_finds()),
          '"entra_p2": false', "sentinel=False")

    # ---- hunt_web.py -------------------------------------------------------------------------------------------
    W, wargs = "hunt_web.py", ["@", ioc]
    failed("hunt_web, every workspace 403", run(W, wargs, [{"when": ["/la/", "Usage"], "status": 403}], base),
           "ws-a", "HTTP 403", never=("IOC hits: none", "FAILED in: none"))
    failed("hunt_web, only the crash-signals query 500", run(W, wargs, [{"when": ["cid-ws-a", "matches regex @'"], "status": 500}], base),
           "crash signals", "ws-a", "HTTP 500")
    failed("hunt_web, only the large-upload query 429", run(W, wargs, [{"when": ["cid-ws-b", "CsMethod"], "status": 429}], base),
           "large uploads", "ws-b", "HTTP 429")
    got = run(W, wargs, [{"when": ["cid-ws-a", "search in"], "mode": "timeout"}], base)
    failed("hunt_web, the IOC search times out in one workspace", got, "IOC search", "ws-a", "timeout", never=("IOC hits: none ",))
    check("hunt_web, the IOC search times out in one workspace: the other workspace's hits are still shown", "'ws-b': [{" in got[1])
    failed("hunt_web, cut-off JSON", run(W, wargs, [{"when": ["cid-ws-a", "search in"], "mode": "malformed"}], base),
           "IOC search", "ws-a", "malformed")
    clean("hunt_web, healthy with hits", run(W, wargs, [], base), "IOC hits: {'ws-a'")
    clean("hunt_web, the searches worked and found nothing", run(W, wargs, empty_finds(), base), "IOC hits: none")

    # ---- exposure.py -------------------------------------------------------------------------------------------
    E, eargs = "exposure.py", ["@", pres, "--fixmap", fix, "--cve", "CVE-2026-0001"]
    clean("exposure, healthy", run(E, eargs, [], base), "third-party takeover: ['Vendor Backup App']", "SP roles: 1", "long certs: 1",
          "resources=1 apps=1", "'ws-a': 12", "'below fix': 1")
    got = run(E, eargs, [{"when": ["/servicePrincipals?"], "status": 403}], base)
    failed("exposure, service principals 403", got, "graph_service_principals", "Microsoft Graph", "HTTP 403",
           never=("third-party takeover: []", "own takeover: 0", "foreign SP creds: 0", "apps=0"))
    check("exposure, service principals 403: exposure.json says NOT ASSESSED, not an empty list",
          str(js(got[2] + "/exposure.json", "third_party_takeover")).startswith("NOT ASSESSED"))
    failed("exposure, role assignments 500", run(E, eargs, [{"when": ["roleAssignments"], "status": 500}], base),
           "graph_role_assignments", "HTTP 500", never=("SP roles: 0",))
    failed("exposure, applications answer cut-off JSON", run(E, eargs, [{"when": ["/applications"], "mode": "malformed"}], base),
           "graph_applications", "malformed", never=("long certs: 0",))
    failed("exposure, who holds Graph permissions 429", run(E, eargs, [{"when": ["appRoleAssignedTo"], "status": 429}], base),
           "graph_assignedto_graph", "HTTP 429", never=("third-party takeover: []", "own takeover: 0"))
    failed("exposure, a sign-in query 403", run(E, eargs, [{"when": ["cid-ws-a", "Kind='interactive'"], "status": 403}], base),
           "sign-ins", "ws-a", "HTTP 403", never=("signins_by_workspace={'ws-b': 12}",))
    failed("exposure, the product's Resource Graph query 403", run(E, eargs, [{"when": ["ResourceGraph", "pub matches regex"], "status": 403}], base),
           "Azure resources", "Resource Graph", "HTTP 403", never=("resources=1", "resources=0"))
    failed("exposure, the Arc servers query times out", run(E, eargs, [{"when": ["ResourceGraph", "hybridcompute"], "mode": "timeout"}], base),
           "servers", "arc", "timeout")
    clean("exposure, the queries worked and found nothing", run(E, eargs, empty_finds(), base), "third-party takeover: []", "SP roles: 0",
          "resources=0 apps=0", "servers: {}")

    # ---- hunt.py -----------------------------------------------------------------------------------------------
    H, hargs = "hunt.py", ["@", ioc]
    clean("hunt, healthy", run(H, hargs, [], base), "'audit_sweep': 7", "third-party initiators: [('Vendor Backup App', 7)]")
    failed("hunt, the sign-in hunt 403 in one workspace", run(H, hargs, [{"when": ["cid-ws-a", "withsource=Table"], "status": 403}], base),
           "signin_ioc", "ws-a", "HTTP 403", never=("'signin_ioc': None",))
    got = run(H, hargs, [{"when": ["/servicePrincipals?"], "status": 403}], base)
    failed("hunt, service principals 403", got, "graph_service_principals", "Microsoft Graph", "HTTP 403")
    check("hunt, service principals 403: the owner classification says NOT ASSESSED",
          js(got[2] + "/hunt-summary.json", "workspaces", "ws-a", "audit_sweep_events_by_owner") == "NOT ASSESSED")
    got = run(H, hargs, [{"when": ["InitiatedBy.app"], "mode": "timeout"}], base)
    failed("hunt, the audit sweep times out", got, "audit_sweep", "ws-a", "timeout", never=("'audit_sweep': None",))
    check("hunt, the audit sweep times out: no empty owner table",
          js(got[2] + "/hunt-summary.json", "workspaces", "ws-a", "audit_sweep_events_by_owner") == "NOT ASSESSED")
    clean("hunt, the hunts worked and found nothing", run(H, hargs, empty_finds("/servicePrincipals?"), base), "'signin_ioc': 0")

    # ---- attack_ids.py -----------------------------------------------------------------------------------------
    A = "attack_ids.py"
    clean("attack_ids, healthy, one real and one unknown ID", run(A, ["@/a.json", "T1190", "T9999"], []),
          "T1190        Exploit Public-Facing Application", "version: v18.0", "missing: ['T9999']")
    for what, rule, word in (("500", {"status": 500}, "HTTP 500"), ("a timeout", {"mode": "timeout"}, "timeout"),
                             ("a page with no technique on it", {"mode": "empty"}, "no technique name")):
        got = run(A, ["@/a.json", "T1190"], [dict(rule, when=["/attack/techniques/T1190"])])
        failed(f"attack_ids, {what}", got, "T1190", "attack.mitre.org", word, never=("missing: ['T1190']",))
        res = js(got[2] + "/a.json") or {"missing": [tid for tid in ["?"]], "techniques": {}}
        check(f"attack_ids, {what}: the file lists it as failed, not missing and not verified",
              [f["query"] for f in res.get("failed", [])] == ["T1190"] and not res["missing"] and "T1190" not in res["techniques"])

    # ---- sentinel_coverage.py and findings_sources.py: the same rule -------------------------------------------
    S = "sentinel_coverage.py"
    clean("sentinel_coverage, healthy", run(S, ["@"], [], base), "ws-a | rules 1", "{'live': 1}")
    failed("sentinel_coverage, the rules list 403", run(S, ["@"], [{"when": ["alertRules"], "status": 403}], base),
           "analytics rules", "ws-a", "HTTP 403", never=("rules 0",))
    failed("sentinel_coverage, the ingestion query 500", run(S, ["@"], [{"when": ["cid-ws-a", "Usage"], "status": 500}], base),
           "ingestion", "ws-a", "HTTP 500", never=("'blind': 1",))
    sent = run(T, ["@"], [{"when": ["ResourceGraph", "SecurityInsights"], "status": 403}])[2]
    failed("sentinel_coverage, after a failed Sentinel query", run(S, ["@"], [], sent), "Sentinel onboarding", "ws-a",
           never=("not onboarded to Sentinel: ['ws-a'",))
    failed("findings_sources, Secure Score 403", run("findings_sources.py", ["@"], [{"when": ["secureScores"], "status": 403}]),
           "secure_score", "HTTP 403")

    # ---- nothing secret in anything any run printed ------------------------------------------------------------
    everything = "\n".join(said)
    check("no run printed the token", "STANDIN-TOKEN-MARKER" not in everything)
    check("no run printed the tenant id", "00000000-aaaa-4bbb-8ccc-00000000dddd" not in everything)
    check("no run printed query text", "summarize" not in everything and "| where" not in everything)
finally:
    srv.kill()
    shutil.rmtree(tmp, ignore_errors=True)
sys.exit(1 if bad else 0)
PY

# --- templates/build.sh: any failed document leaves no PDF from an earlier run -----------------------------------------
proj="$t/proj"; mkdir -p "$proj/scripts" "$proj/dist"; cp "$TI/templates/build.sh" "$proj/scripts/build.sh"
printf '# Briefing\n\nSee technical.md. 3 items.\n' > "$proj/briefing.md"; printf '# Technical\n\n3 items.\n' > "$proj/technical.md"
printf '# Appendix\n' > "$proj/appendix.md"
for d in briefing technical appendix; do echo "last run" > "$proj/dist/$d.pdf"; done
cat > "$t/bin/pandoc" <<'SH'
#!/bin/sh
# Stub: the first document builds, the second fails.
while [ $# -gt 0 ]; do [ "$1" = -o ] && { out="$2"; shift; }; shift; done
case "$out" in *technical*) echo "Error producing PDF." >&2; exit 43;; esac
echo pdf > "$out"
SH
chmod +x "$t/bin/pandoc"
set +e; PATH="$t/bin:$PATH" THREATS_IT="$TI" sh "$proj/scripts/build.sh" >/dev/null 2>"$t/build.err"; rc=$?; set -e
check "build.sh: a document that fails stops the build with exit 1, named" [ "$rc" = 1 ]
check "build.sh: it says which PDF was not built" grep -q "FAILED: dist/technical.pdf was not built" "$t/build.err"
check "build.sh: a later document's PDF from the last run is gone too" [ ! -e "$proj/dist/appendix.pdf" ]
printf '# Briefing\n\nSee technical.md. 4 items.\n' > "$proj/briefing.md"   # the pair check now fails, before any PDF is built
for d in briefing technical appendix; do echo "last run" > "$proj/dist/$d.pdf"; done
set +e; PATH="$t/bin:$PATH" THREATS_IT="$TI" sh "$proj/scripts/build.sh" >/dev/null 2>&1; rc=$?; set -e
none_left() { [ "$rc" != 0 ] && ! ls "$proj/dist/"*.pdf >/dev/null 2>&1; }
check "build.sh: a failed pair check leaves no PDF from the last run either" none_left

# --- fetch_source.sh: a fetch that timed out half way leaves no partial page -------------------------------------------
cat > "$t/bin/curl" <<'SH'
#!/bin/sh
# Stub: half a page arrives, then the connection times out. Real curl prints 000 and exits 28.
while [ $# -gt 0 ]; do [ "$1" = -o ] && { out="$2"; shift; }; shift; done
echo "<html><body><p>half a pa" > "$out"; printf 000; exit 28
SH
chmod +x "$t/bin/curl"
set +e; PATH="$t/bin:$PATH" sh "$TI/scripts/fetch_source.sh" "https://example.invalid/a" "$t/src" advisory 2>/dev/null; rc=$?; set -e
check "fetch_source.sh: a timed-out fetch is refused (exit 2)" [ "$rc" = 2 ]
check "fetch_source.sh: the partial page is not left behind" [ ! -e "$t/src/advisory.html" ]
check "fetch_source.sh: the log still records what arrived" [ "$(tail -1 "$t/src/FETCH-LOG.tsv" | cut -f3)" != 0 ]
exit "$fail"
