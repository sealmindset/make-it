#!/usr/bin/env bash
# /threats-it reads findings from the organisation's own tools (owner, 2026-11-17). The AuditGitHub reader is
# tested against a local stand-in; the Microsoft readers need a signed-in tenant and are not run here.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
T=.claude/make-it/threats-it
python3 - "$PWD/$T/scripts" <<'PY' || fail=1
import http.server, json, os, sys, tempfile, threading
sys.path.insert(0, sys.argv[1])
import findings_sources as fs
seen, bad = [], 0
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        seen.append((self.server.server_port, self.path, self.headers.get("X-API-Key")))
        if self.path.startswith("/moved"):
            self.send_response(302); self.send_header("Location", f"http://127.0.0.1:{other.server_port}/findings/paginated"); self.end_headers(); return
        if self.headers.get("X-API-Key") != "agh_good":
            self.send_response(401); self.end_headers(); self.wfile.write(b'{"detail":"no"}'); return
        page = int(self.path.split("page=")[1].split("&")[0])
        body = {"items": [{"id": f"f{page}", "severity": "info", "title": "t", "code_snippet": "password=hunter2"}],
                "total": 2, "total_actionable": 1, "total_false_positive": 1, "has_next": page < 2}
        self.send_response(200); self.end_headers(); self.wfile.write(json.dumps(body).encode())
def serve():
    s = http.server.HTTPServer(("127.0.0.1", 0), H); threading.Thread(target=s.serve_forever, daemon=True).start(); return s
main, other = serve(), serve()
base = f"http://127.0.0.1:{main.server_port}"
def check(name, ok):
    global bad
    print(("ok   " if ok else "FAIL ") + name); bad |= not ok
def run(url, key):
    d = tempfile.mkdtemp(); seen.clear()
    sys.stdout = open(os.devnull, "w"); rec = fs.auditgithub(d, url, key); sys.stdout = sys.__stdout__
    return rec, open(os.path.join(d, "auditgithub_findings.json")).read()
rec, text = run(base, "agh_good")
check("every page is read", [f["id"] for f in rec["result"]] == ["f1", "f2"])
check("low and informational findings are kept", rec["result"][0]["severity"] == "info")
check("the key is sent as X-API-Key", all(k == "agh_good" for _, _, k in seen))
check("false positives and snoozed findings are asked for", all("include_false_positives=true" in p and "include_snoozed=true" in p for _, p, _ in seen))
check("code snippets are not kept", "hunter2" not in text and "code_snippet" in json.loads(text)["_provenance"]["excluded"])
check("the key is never written to the project", "agh_good" not in text)
check("the counts are kept with the findings", json.loads(text)["_provenance"]["counts"]["total_false_positive"] == 1)
rec, text = run(base, "agh_wrong")
check("a refused key is recorded with its status, not as no findings", rec["http_status"] == 401 and not isinstance(rec["result"], list))
rec, text = run(base + "/moved", "agh_good")
check("a redirect is not followed", rec["http_status"] == 302 and not any(port == other.server_port for port, _, _ in seen))
rec, text = run(None, None)
check("a source that is not set up is recorded as not configured", "not configured" in rec["result"]["message"] and rec["http_status"] == 0)
rec, text = run("http://example.com", "agh_good")
check("a plain http address is refused before the key is sent", "must be https" in rec["result"]["message"] and not seen)
# the Microsoft readers, with every call refused: each source must still be on record with its status
calls = []
fs.http = lambda m, u, r, *a, **k: (calls.append(u), (403, {"error": "denied"}))[1]
fs.graph_all = lambda u: (calls.append(u), (403, {"error": "denied"}))[1]
fs.arg = lambda q: (calls.append(q), (403, {"error": "denied"}))[1]
d = tempfile.mkdtemp(); sys.argv = ["x", d, "--since", "2026-08-01"]
for k in ("AUDITGITHUB_API_URL", "AUDITGITHUB_API_KEY"): os.environ.pop(k, None)
sys.stdout = open(os.devnull, "w"); fs.main(); sys.stdout = sys.__stdout__
want = ["secure_score", "secure_score_profiles", "defender_xdr_alerts", "defender_xdr_incidents", "defender_cloud_assessments", "auditgithub_findings"]
recs = {n: json.load(open(os.path.join(d, n + ".json"))) for n in want if os.path.exists(os.path.join(d, n + ".json"))}
check("every source leaves a record even when refused", sorted(recs) == sorted(want))
check("a refused source keeps its status and error", all(recs[n]["http_status"] == 403 and recs[n]["result"] == {"error": "denied"} for n in want[:5]))
check("alerts are asked for since the given date, with no severity filter", any("alerts_v2?$filter=createdDateTime%20ge%202026-08-01T00:00:00Z" in c for c in calls) and not any("severity" in c for c in calls if "alerts_v2" in c))
check("only security read endpoints and one Resource Graph query are called", all("/v1.0/security/" in c or c.startswith("securityresources") for c in calls))
sys.exit(bad)
PY
R=$T/references
flat() { tr '\n' ' ' | tr -s ' '; }
has() { if [ "$(flat < "$2" | grep -cF -- "$1")" -gt 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
has 'findings_sources.py' .claude/commands/threats-it.md "the skill lists the collector"
has 'findings_sources.py' "$R/finding-chains.md" "the chaining step names the collector"
has 'findings_sources.py' "$R/tenant-assessment.md" "the collection order includes it"
has 'could not be read is reported as not read' "$R/finding-chains.md" "an unreadable source is never read as nothing found"
has 'AUDITGITHUB_API_URL' "$R/environment-template.md" "the profile says how AuditGitHub is set up"
has 'never written into the profile' "$R/environment-template.md" "the key stays out of the profile"
has 'An alert is not a finding' "$R/finding-chains.md" "alerts are treated as signals, not weaknesses"
exit $fail
