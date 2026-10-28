"""Microsoft Security Update Guide (MSRC) lookups. No authentication needed.

  python3 -I msrc.py <outdir> --cves CVE-1,CVE-2          # vulnerability + affectedProduct records
  python3 -I msrc.py <outdir> --window 2026-10-14 2026-10-17   # everything released in a window (PT dates)

Archives every response under <outdir>/msrc/ and prints a JSON summary per CVE: title, tag, severity,
CVSS, vector, exploited, publicly disclosed, Preview-Pane FAQ answer, revisions, and fixed builds per product.
For a window it also prints counts by date and tag, separating Mariner (Azure Linux) and Edge/Chromium entries.
"""
import argparse
import collections
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request

API = "https://api.msrc.microsoft.com/sug/v2.0/en-US"
ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("--cves", default="")
ap.add_argument("--window", nargs=2)
a = ap.parse_args()
od = os.path.join(a.outdir, "msrc")
os.makedirs(od, exist_ok=True)


def get(path, params, name):
    url = f"{API}/{path}?" + urllib.parse.urlencode(params, safe="$'")
    items = []
    while url:
        d = json.loads(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=120).read())
        items += d.get("value", [])
        url = d.get("@odata.nextLink")
    json.dump(items, open(os.path.join(od, name + ".json"), "w"), indent=1)
    return items


def text(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s or ""))).strip()


def summarise(v, ap_rows):
    pp = "n/a"
    for art in v.get("articles") or []:
        m = re.search(r"Is the Preview Pane an attack vector for this vulnerability\? (Yes|No)", text(art.get("description")))
        if m:
            pp = m.group(1)
    fixes = collections.defaultdict(set)
    for r in ap_rows:
        for k in r.get("kbArticles") or []:
            fixes[r["product"]].add(f"{k.get('articleName') or ''} {k.get('fixedBuildNumber') or ''}".strip())
    return {"cve": v["cveNumber"], "title": v.get("cveTitle"), "tag": v.get("tag"), "released": v.get("releaseDate"),
            "latest_revision": v.get("latestRevisionDate"), "severity": v.get("severity"), "impact": v.get("impact"),
            "cvss": v.get("baseScore"), "vector": v.get("vectorString"), "exploited": v.get("exploited"),
            "publiclyDisclosed": v.get("publiclyDisclosed"), "preview_pane": pp,
            "faq": [text(x.get("description")) for x in v.get("articles") or [] if x.get("articleType") == "FAQ"][:4],
            "revisions": [{"version": r["version"], "date": r["revisionDate"][:10], "text": text(r["description"])} for r in v.get("revisions") or []],
            "fixed_builds": {p: sorted(s) for p, s in sorted(fixes.items())}}


out = {}
if a.cves:
    for c in [x for x in a.cves.split(",") if x]:
        vs = get("vulnerability", {"$filter": f"cveNumber eq '{c}'"}, f"vuln-{c}")
        aps = get("affectedProduct", {"$filter": f"cveNumber eq '{c}'", "$top": 500}, f"affected-{c}")
        out[c] = summarise(vs[0], aps) if vs else "not in MSRC"
if a.window:
    s, e = a.window
    vs = get("vulnerability", {"$filter": f"releaseDate gt {s}T00:00:00-07:00 and releaseDate lt {e}T00:00:00-07:00", "$top": 200}, f"window-{s}_{e}")
    kind = lambda x: "mariner" if (x.get("isMariner") or x.get("tag") == "Mariner") else ("edge" if "Edge" in (x.get("tag") or "") else "microsoft")
    out["window"] = {"total": len(vs), "by_date_kind": {f"{k[0]} {k[1]}": n for k, n in collections.Counter((x["releaseDate"][:10], kind(x)) for x in vs).items()},
                     "microsoft": [{"cve": x["cveNumber"], "tag": x.get("tag"), "impact": x.get("impact"), "severity": x.get("severity"),
                                    "cvss": x.get("baseScore"), "exploited": x.get("exploited"), "released": x["releaseDate"]}
                                   for x in sorted(vs, key=lambda x: (x["releaseDate"], x.get("tag") or "")) if kind(x) == "microsoft"]}
json.dump(out, sys.stdout, indent=1)
print()
