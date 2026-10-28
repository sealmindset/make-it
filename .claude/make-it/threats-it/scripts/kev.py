"""CISA KEV lookups against the live feed (archived on first use).

  python3 -I kev.py <outdir> --cves CVE-1,CVE-2 [--vendor Microsoft] [--since 2026-10-01] [--as-of 2026-10-16]

Downloads the feed to <outdir>/cisa-kev-<catalogVersion>.json (once per catalog version) and prints
JSON: catalog metadata, the count as of a date (entries with dateAdded <= as-of), each requested CVE's
record (or "not in KEV"), vendor entries added since a date, and all entries added since a date.
"""
import argparse
import json
import os
import sys
import urllib.request

FEED = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
FIELDS = ("cveID", "vendorProject", "product", "vulnerabilityName", "dateAdded", "dueDate", "knownRansomwareCampaignUse", "forensicTriage", "shortDescription", "notes")

ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("--cves", default="")
ap.add_argument("--vendor", default="")
ap.add_argument("--since", default="")
ap.add_argument("--as-of", default="")
a = ap.parse_args()

req = urllib.request.Request(FEED, headers={"User-Agent": "Mozilla/5.0"})
raw = urllib.request.urlopen(req, timeout=120).read()
d = json.loads(raw)
os.makedirs(a.outdir, exist_ok=True)
path = os.path.join(a.outdir, f"cisa-kev-{d['catalogVersion']}.json")
if not os.path.exists(path):
    open(path, "wb").write(raw)
v = d["vulnerabilities"]
by = {x["cveID"]: x for x in v}
out = {"catalogVersion": d["catalogVersion"], "dateReleased": d["dateReleased"], "count": d["count"], "archived": path}
if a.as_of:
    out["count_as_of"] = {a.as_of: sum(1 for x in v if x["dateAdded"] <= a.as_of)}
if a.cves:
    out["cves"] = {c: ({k: by[c].get(k) for k in FIELDS} if c in by else "not in KEV") for c in a.cves.split(",") if c}
if a.since:
    added = [x for x in v if x["dateAdded"] >= a.since]
    out["added_since"] = [{k: x.get(k) for k in ("cveID", "vendorProject", "product", "dateAdded", "dueDate")} for x in sorted(added, key=lambda x: x["dateAdded"])]
    if a.vendor:
        out["vendor_added_since"] = [x for x in out["added_since"] if x["vendorProject"].lower() == a.vendor.lower()]
json.dump(out, sys.stdout, indent=1)
print()
