"""Render VEX statements as OpenVEX v0.2.0.

  python3 -I openvex.py <vex.json> <out.openvex.json> --author "<Org> Information Security" --id-base https://<org-domain>/vex/<slug>

vex.json is a list of statements:
  {"id": "V01", "item": "...", "vulnerabilities": ["CVE-..."], "product": "...", "status": "affected|not_affected|fixed|under_investigation",
   "justification": "component_not_present|vulnerable_code_not_present|vulnerable_code_not_in_execute_path|vulnerable_code_cannot_be_controlled_by_adversary|inline_mitigations_already_exist",
   "impact_statement": "...", "action_statement": "...", "evidence": "...", "owner": "...", "priority": "..."}
Rules enforced (fail loudly): not_affected needs a justification from the list above; affected needs an action_statement;
under_investigation needs evidence and an owner. Items with no CVE get a NOCVE-<id> name.
"""
import argparse
import datetime as dt
import json
import sys

JUST = {"component_not_present", "vulnerable_code_not_present", "vulnerable_code_not_in_execute_path",
        "vulnerable_code_cannot_be_controlled_by_adversary", "inline_mitigations_already_exist"}
ap = argparse.ArgumentParser()
ap.add_argument("vex")
ap.add_argument("out")
ap.add_argument("--author", required=True)
ap.add_argument("--id-base", required=True)
a = ap.parse_args()
V = json.load(open(a.vex))
errors = []
for v in V:
    if v["status"] == "not_affected" and v.get("justification") not in JUST:
        errors.append(f"{v['id']}: not_affected needs a valid justification")
    if v["status"] == "affected" and not v.get("action_statement"):
        errors.append(f"{v['id']}: affected needs an action_statement")
    if v["status"] == "under_investigation" and not (v.get("evidence") and v.get("owner")):
        errors.append(f"{v['id']}: under_investigation needs evidence and an owner")
    if v["status"] not in ("affected", "not_affected", "fixed", "under_investigation"):
        errors.append(f"{v['id']}: unknown status {v['status']}")
if errors:
    sys.exit("VEX validation failed:\n  " + "\n  ".join(errors))
now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
doc = {"@context": "https://openvex.dev/ns/v0.2.0", "@id": f"{a.id_base}/{now[:10]}", "author": a.author, "timestamp": now, "version": 1, "statements": []}
for v in V:
    for cve in v.get("vulnerabilities") or [f"NOCVE-{v['id']}"]:
        st = {"vulnerability": {"name": cve}, "products": [{"@id": v["product"]}], "status": v["status"]}
        if v["status"] == "not_affected":
            st["justification"], st["impact_statement"] = v["justification"], v.get("impact_statement")
        elif v["status"] == "affected":
            st["action_statement"] = v["action_statement"]
        elif v["status"] == "under_investigation":
            st["status_notes"] = f"{v['evidence']} Next: {v.get('action_statement') or ''} Owner: {v['owner']}."
        doc["statements"].append(st)
json.dump(doc, open(a.out, "w"), indent=1, ensure_ascii=False)
print(f"wrote {a.out}: {len(doc['statements'])} statements from {len(V)} items")
