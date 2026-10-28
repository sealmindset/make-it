"""Verify MITRE ATT&CK technique IDs against attack.mitre.org (names change between versions).

  python3 -I attack_ids.py <outfile.json> T1190 T1574.001 T1098.003 ...

For each ID, fetches https://attack.mitre.org/techniques/<T>/<sub>/ and records the page title
(technique name) and the ATT&CK content version shown on the page. Writes the result to <outfile.json>
in the shape the reports cite ({"attack_version", "techniques": {id: name}, "missing": [...]}).
"""
import json
import re
import sys
import urllib.request

out_path, ids = sys.argv[1], sys.argv[2:]
res = {"attack_version": None, "techniques": {}, "missing": []}
for tid in ids:
    path = tid.replace(".", "/")
    url = f"https://attack.mitre.org/techniques/{path}/"
    try:
        page = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read().decode("utf-8", "replace")
    except Exception as e:  # 404 means the ID does not exist in the current version
        res["missing"].append({"id": tid, "error": str(e)})
        continue
    title = re.search(r"<title>(.*?)</title>", page, re.S)
    name = re.split(r",\s*(?:Sub-technique|Technique)\s", title.group(1))[0].strip() if title else None
    name = name.replace("&amp;", "&") if name else None
    ver = re.search(r"ATT&(?:amp;)?CK content v([\d.]+)", page)
    if ver:
        res["attack_version"] = "v" + ver.group(1)
    res["techniques"][tid] = name
    print(f"{tid:12s} {name}")
json.dump(res, open(out_path, "w"), indent=2)
print("version:", res["attack_version"], "| missing:", [m["id"] for m in res["missing"]])
