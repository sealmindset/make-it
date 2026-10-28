"""Fail if the leadership briefing and the technical companion drift apart.

  python3 -I check_pair.py <briefing.md> <technical.md> [headline.json]

Rule 1: every number, date (D Month / YYYY-MM-DD) and CVE identifier in the briefing appears in the companion.
Rule 2 (optional): headline.json is a list of {"label", "value", "in_brief": bool}; each value must appear (as a
whole token) in the companion, and in the briefing when in_brief is true. Generate headline.json from the
derived data so a change in the evidence cannot leave the prose stale.
Also checks that the briefing names the companion file.
"""
import json
import os
import re
import sys

brief_p, tech_p = sys.argv[1], sys.argv[2]
brief, tech = open(brief_p, encoding="utf-8").read(), open(tech_p, encoding="utf-8").read()
MONTHS = {m: f"{i:02d}" for i, m in enumerate(["January", "February", "March", "April", "May", "June", "July", "August",
                                                "September", "October", "November", "December"], 1)}
MRE = "|".join(MONTHS)
fail = []


def dates(s):
    out = set()
    for m in re.finditer(rf"\b(\d{{1,2}})(?:\s*[–-]\s*(\d{{1,2}}))?\s+({MRE})\b", s):
        out.add(f"{MONTHS[m.group(3)]}-{int(m.group(1)):02d}")
        if m.group(2):
            out.add(f"{MONTHS[m.group(3)]}-{int(m.group(2)):02d}")
    for m in re.finditer(r"\b\d{4}-(\d{2})-(\d{2})\b", s):
        out.add(f"{m.group(1)}-{m.group(2)}")
    return out


def numbers(s):
    s = re.sub(rf"\b\d{{1,2}}(?:\s*[–-]\s*\d{{1,2}})?\s+(?:{MRE})(?:\s+\d{{4}})?\b", " ", s)
    s = re.sub(r"\b\d{4}-\d{2}-\d{2}\b", " ", s)
    s = re.sub(r"CVE-\d{4}-\d+", " ", s)
    s = re.sub(r"^\s*(?:#+\s*)?\d+(?:\.\d+)*[.)]\s", " ", s, flags=re.M)
    return set(re.findall(r"(?<![\w.])\d(?:\d|,(?=\d))*(?:\.\d+)?(?![\w])", s))


def has(text, value):
    return re.search(r"(?<![\w.,])" + re.escape(value) + r"(?![\w]|[.,]\d)", text) is not None


tn = numbers(tech) | {n.replace(",", "") for n in numbers(tech)}
for kind, b, t in (("number", numbers(brief), tn), ("date", dates(brief), dates(tech)),
                   ("CVE", set(re.findall(r"CVE-\d{4}-\d+", brief)), set(re.findall(r"CVE-\d{4}-\d+", tech)))):
    for x in sorted(b):
        if x not in t and x.replace(",", "") not in t:
            fail.append(f"briefing {kind} '{x}' not found in {os.path.basename(tech_p)}")
if len(sys.argv) > 3:
    for h in json.load(open(sys.argv[3])):
        v = str(h["value"])
        if not has(tech, v):
            fail.append(f"{h['label']} '{v}' missing from {os.path.basename(tech_p)}")
        if h.get("in_brief") and not has(brief, v):
            fail.append(f"{h['label']} '{v}' missing from {os.path.basename(brief_p)}")
if os.path.basename(tech_p) not in brief:
    fail.append(f"briefing does not name the companion file {os.path.basename(tech_p)}")
if fail:
    print("PAIR CHECK FAILED")
    for f in fail:
        print("  -", f)
    sys.exit(1)
print(f"pair check passed: {len(numbers(brief))} numbers, {len(dates(brief))} dates, {len(set(re.findall(r'CVE-[0-9]{4}-[0-9]+', brief)))} CVEs in the briefing found in the companion")
