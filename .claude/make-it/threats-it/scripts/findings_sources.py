"""Findings the organisation's own security tools already hold, every rating included. Read-only.

  python3 -I findings_sources.py <outdir> [--since 2026-08-01]

For the finding-chains step (references/finding-chains.md). Low and informational findings are the point, so
nothing is filtered by severity. Each source is saved with its HTTP status, so a source that could not be read
is on record and is never read as "nothing found": it is printed as FAILED and the script exits 3.
(AuditGitHub left unconfigured is on record as status 0 and is not a failure.)
  secure_score, secure_score_profiles   Graph v1.0 /security/secureScores, /security/secureScoreControlProfiles
  defender_cloud_assessments            Resource Graph: microsoft.security/assessments that are not healthy
  defender_xdr_alerts, _incidents       Graph v1.0 /security/alerts_v2, /security/incidents since --since (default 90 days)
  auditgithub_findings                  GET $AUDITGITHUB_API_URL/findings/paginated with X-API-Key $AUDITGITHUB_API_KEY
                                        (a key with findings:read; code snippets are not kept)
Everything a tool reports is a lead until this run's own evidence confirms it.
"""
import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import GRAPH, NoRedirect, arg, failed, finish, graph_all, http, save  # noqa: E402

ASSESSMENTS = """securityresources
| where type == 'microsoft.security/assessments'
| where properties.status.code !~ 'Healthy' and properties.status.code !~ 'NotApplicable'
| project id, subscriptionId, name=tostring(properties.displayName), state=tostring(properties.status.code),
          severity=tostring(properties.metadata.severity), resource=tostring(properties.resourceDetails.Id),
          threats=properties.metadata.threats, categories=properties.metadata.categories"""


def auditgithub(outdir, url, key, max_pages=200):
    name, shown = "auditgithub_findings", "GET <AUDITGITHUB_API_URL>/findings/paginated (status=open, false positives and snoozed included)"
    if not url or not key:
        return save(outdir, name, "auditgithub", shown, 0, {"message": "not configured: set AUDITGITHUB_API_URL and AUDITGITHUB_API_KEY"})
    u = urllib.parse.urlsplit(url)
    if u.scheme != "https" and u.hostname not in ("localhost", "127.0.0.1"):
        return save(outdir, name, "auditgithub", shown, 0, {"message": "refused: the API URL must be https"})
    opener, items, counts = urllib.request.build_opener(NoRedirect), [], {}  # the key never follows a redirect
    for page in range(1, max_pages + 1):
        q = urllib.parse.urlencode({"page": page, "page_size": 100, "status": "open", "include_snoozed": "true",
                                    "include_false_positives": "true"})
        req = urllib.request.Request(f"{url.rstrip('/')}/findings/paginated?{q}", headers={"X-API-Key": key})
        try:
            with opener.open(req, timeout=120) as resp:
                body = json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            return save(outdir, name, "auditgithub", shown, e.code, {"message": e.read().decode(errors="replace")[:500], "page": page})
        except (urllib.error.URLError, ValueError) as e:
            return save(outdir, name, "auditgithub", shown, 0, {"message": str(e)[:500], "page": page})
        counts = {k: body.get(k) for k in ("total", "total_actionable", "total_false_positive")}
        items += [{k: v for k, v in f.items() if k != "code_snippet"} for f in body.get("items", [])]
        if not body.get("has_next"):
            break
    else:
        counts["stopped_at_page"] = max_pages
    rec = save(outdir, name, "auditgithub", shown, 200, items)
    rec["_provenance"] = {"counts": counts, "excluded": "code_snippet, so that source code and secrets are not copied into the project"}
    with open(os.path.join(outdir, f"{name}.json"), "w", encoding="utf-8") as f:
        json.dump(rec, f, indent=1, ensure_ascii=False)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--since", default=(dt.date.today() - dt.timedelta(days=90)).isoformat())
    a = ap.parse_args()
    gb, since = f"{GRAPH}/v1.0/security", f"$filter=createdDateTime ge {a.since}T00:00:00Z"
    url = f"{gb}/secureScores?$top=1"
    def keep(name, kind, request, where, status, result):
        save(a.outdir, name, kind, request, status, result)
        if status != 200:
            failed(name, where, status)

    status, res = http("GET", url, GRAPH)
    keep("secure_score", "graph", url, "Microsoft Graph", status, res.get("value", res) if status == 200 and isinstance(res, dict) else res)
    for name, url in (("secure_score_profiles", f"{gb}/secureScoreControlProfiles"),
                      ("defender_xdr_alerts", f"{gb}/alerts_v2?{since}"),
                      ("defender_xdr_incidents", f"{gb}/incidents?{since}")):
        keep(name, "graph", url, "Microsoft Graph", *graph_all(url.replace(" ", "%20")))
    keep("defender_cloud_assessments", "arg", ASSESSMENTS, "Resource Graph", *arg(ASSESSMENTS))
    rec = auditgithub(a.outdir, os.environ.get("AUDITGITHUB_API_URL"), os.environ.get("AUDITGITHUB_API_KEY"))
    if rec["http_status"] != 200 and not str(rec["result"].get("message", "")).startswith("not configured"):
        failed("auditgithub_findings", "AuditGitHub", rec["http_status"] or "no answer")
    finish()


if __name__ == "__main__":
    main()
