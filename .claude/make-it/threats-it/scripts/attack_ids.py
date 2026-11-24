"""Verify MITRE ATT&CK technique IDs against attack.mitre.org (names change between versions).

  python3 -I attack_ids.py <outfile.json> T1190 T1574.001 T1098.003 ...

For each ID, fetches https://attack.mitre.org/techniques/<T>/<sub>/ and records the page title
(technique name) and the ATT&CK content version shown on the page. Writes the result to <outfile.json>
in the shape the reports cite ({"attack_version", "techniques": {id: name}, "missing": [...], "failed": [...]}).
"missing" is only an ID the site answered 404 for. An ID that could not be checked (any other status, a timeout,
a page with no technique name) is under "failed", is printed as FAILED, and the script exits 3: not verified, not missing.
"""
import http.client
import json
import os
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import failed, failures, finish, no_answer  # noqa: E402

out_path, ids = sys.argv[1], sys.argv[2:]
res = {"attack_version": None, "techniques": {}, "missing": []}
for tid in ids:
    path = tid.replace(".", "/")
    url = f"https://attack.mitre.org/techniques/{path}/"
    try:
        page = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:  # the ID does not exist in the current version
            res["missing"].append({"id": tid, "error": str(e)})
        else:
            failed(tid, "attack.mitre.org", e.code)
        continue
    except (OSError, http.client.HTTPException) as e:
        failed(tid, "attack.mitre.org", no_answer(e))
        continue
    title = re.search(r"<title>(.*?)</title>", page, re.S)
    name = re.split(r",\s*(?:Sub-technique|Technique)\s", title.group(1))[0].strip() if title else None
    name = name.replace("&amp;", "&") if name else None
    if not name:
        failed(tid, "attack.mitre.org", "no technique name on the page")
        continue
    if tid not in title.group(1):  # a block or error page answered 200: its title is not the technique's name
        failed(tid, "attack.mitre.org", "not a technique page")
        continue
    ver = re.search(r"ATT&(?:amp;)?CK content v([\d.]+)", page)
    if ver:
        res["attack_version"] = "v" + ver.group(1)
    res["techniques"][tid] = name
    print(f"{tid:12s} {name}")
res["failed"] = failures()
json.dump(res, open(out_path, "w"), indent=2)
print("version:", res["attack_version"] or ("not read" if res["failed"] else None), "| missing:", [m["id"] for m in res["missing"]],
      *(["| FAILED, not checked:", [f["query"] for f in res["failed"]]] if res["failed"] else []))
finish()
