#!/usr/bin/env bash
# The threats-it scripts report a failure as a failure, never as a clean result.
#   - fetch_source.sh: a fetch that can't connect logs HTTP 000 (not 000000), logs 0 bytes instead of dying under
#     set -e, exits 2 (refused), and leaves no copy from an earlier run looking like this run's page.
#   - templates/build.sh: a pandoc failure stops the build with exit 1 and leaves no PDF (not even last run's) in dist/.
#   - hunt.py: user-agent and IP prefixes go into KQL as escaped string literals, so a " or \ can't break the query.
#   - hunt_web.py: --crash-regex has its quotes doubled for KQL's verbatim @'...' string, and an IOC query that
#     failed is reported as FAILED, apart from the hits, instead of reading "IOC hits: none".
# curl and pandoc are replaced by stubs on PATH, so nothing here needs a network, pandoc or Azure.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
TI="$root/.claude/make-it/threats-it"
fail=0
check() { local name="$1"; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi; }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"

# --- fetch_source.sh -------------------------------------------------------------------------------
cat > "$t/bin/curl" <<'SH'
#!/bin/sh
# Stub: no connection. Real curl prints 000 for -w %{http_code} and exits non-zero.
printf 000; exit 7
SH
chmod +x "$t/bin/curl"
mkdir -p "$t/src"; echo "<p>last week's page</p>" > "$t/src/advisory.html"; echo "last week's page" > "$t/src/advisory.txt"
set +e; PATH="$t/bin:$PATH" sh "$TI/scripts/fetch_source.sh" "https://example.invalid/a" "$t/src" advisory 2>/dev/null; rc=$?; set -e
check "a fetch that can't connect exits 2 (refused)" [ "$rc" = 2 ]
check "it logs HTTP 000, not 000000" [ "$(tail -1 "$t/src/FETCH-LOG.tsv" | cut -f2)" = 000 ]
check "it logs 0 bytes instead of dying" [ "$(tail -1 "$t/src/FETCH-LOG.tsv" | cut -f3)" = 0 ]
gone() { [ ! -e "$t/src/advisory.html" ] && [ ! -e "$t/src/advisory.txt" ]; }
check "the earlier run's copy is gone" gone

cat > "$t/bin/curl" <<'SH'
#!/bin/sh
# Stub: a page arrives. Writes the -o file and prints 200.
while [ $# -gt 0 ]; do [ "$1" = -o ] && { out="$2"; shift; }; shift; done
echo "<html><body><p>fresh page</p></body></html>" > "$out"; printf 200
SH
set +e; PATH="$t/bin:$PATH" sh "$TI/scripts/fetch_source.sh" "https://example.invalid/a" "$t/src" advisory >/dev/null 2>&1; rc=$?; set -e
archived() { [ "$rc" = 0 ] && grep -q "fresh page" "$t/src/advisory.txt"; }
check "a page that arrives is archived and converted (exit 0)" archived

# --- templates/build.sh ----------------------------------------------------------------------------
proj="$t/proj"; mkdir -p "$proj/scripts" "$proj/dist"; cp "$TI/templates/build.sh" "$proj/scripts/build.sh"
printf '# Briefing\n\nSee technical.md. 3 items.\n' > "$proj/briefing.md"; printf '# Technical\n\n3 items.\n' > "$proj/technical.md"
echo "last run" > "$proj/dist/briefing.pdf"
cat > "$t/bin/pandoc" <<'SH'
#!/bin/sh
# Stub: a pandoc that fails after writing part of its output.
while [ $# -gt 0 ]; do [ "$1" = -o ] && { out="$2"; shift; }; shift; done
echo partial > "$out"; echo "Error producing PDF." >&2; exit 43
SH
chmod +x "$t/bin/pandoc"
set +e; PATH="$t/bin:$PATH" THREATS_IT="$TI" sh "$proj/scripts/build.sh" >/dev/null 2>"$t/build.err"; rc=$?; set -e
check "a pandoc failure stops the build with exit 1" [ "$rc" = 1 ]
check "it says which PDF was not built" grep -q "FAILED: dist/briefing.pdf was not built" "$t/build.err"
check "no PDF is left in dist/, not even last run's" [ ! -e "$proj/dist/briefing.pdf" ]
cat > "$t/bin/pandoc" <<'SH'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = -o ] && { out="$2"; shift; }; shift; done
echo "WARNING: a font fell back" >&2; echo pdf > "$out"
SH
set +e; PATH="$t/bin:$PATH" THREATS_IT="$TI" sh "$proj/scripts/build.sh" >"$t/build.out" 2>&1; rc=$?; set -e
built() { [ "$rc" = 0 ] && [ -s "$proj/dist/briefing.pdf" ] && [ -s "$proj/dist/technical.pdf" ]; }
check "a pandoc that succeeds builds both PDFs (exit 0)" built
no_warnings() { ! grep -q '^WARNING' "$t/build.out"; }
check "its WARNING lines are still filtered out" no_warnings

# --- hunt.py and hunt_web.py: the KQL they build -----------------------------------------------------
python3 -I - "$TI/scripts/hunt.py" "$TI/scripts/hunt_web.py" <<'PY' || fail=1
import io, json, re, sys, contextlib
hunt, web = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
failed = False
def check(name, cond):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    failed |= not cond

# hunt.py: run its own two prefix lines with prefixes holding a quote and a backslash
lines = [l for l in hunt.splitlines() if l.startswith(("ua_or = ", "pfx_or = "))]
check("hunt.py builds both prefix filters on one line each", len(lines) == 2)
ns = {"json": json, "cfg": {"user_agent_prefixes": ['Mozilla/5.0 "evil', "curl/"], "ip_prefixes": ["10.0.\\", "192.0.2."]}}
for l in lines:
    exec(l, ns)
lits = re.findall(r'startswith ("(?:[^"\\]|\\.)*")', ns.get("ua_or", "") + " or " + ns.get("pfx_or", ""))
check("every prefix is one complete, escaped string literal", len(lits) == 4)
check("the quote and the backslash survive as data", [json.loads(x) for x in lits] ==
      ['Mozilla/5.0 "evil', "curl/", "10.0.\\", "192.0.2."])

# hunt_web.py: the crash regex goes into @'...' with its quotes doubled
m = re.search(r"^\s*(crash = .*)$", web, re.M)
check("hunt_web.py doubles quotes in --crash-regex", bool(m))
if m:
    class A: crash_regex = "can't connect|it's down"
    ns = {"a": A}
    exec(m.group(1).strip(), ns)
    check("a quote in the regex becomes '' inside @'...'", ns["crash"] == "can''t connect|it''s down")
check("the query uses the doubled regex", "matches regex @'{crash}'" in web and "@'{a.crash_regex}'" not in web)

# hunt_web.py: a failed IOC query is reported apart from the hits
tail = web[web.index("hits = {k: v"):]
summary = {"workspaces": {
    "ws-ok": {"web_tables_mb_30d": 5, "results": {"web_ioc": {"status": 200, "rows": []}}},
    "ws-broken": {"web_tables_mb_30d": 7, "results": {"web_ioc": {"status": 400, "rows": None}}}}}
out, ended = io.StringIO(), []
with contextlib.redirect_stdout(out):
    exec(tail, {"summary": summary, "finish": lambda: ended.append(1)})  # finish(): the shared last line (E02-S110)
said = out.getvalue()
check("the summary ends with the shared finish(), which names every failed query and exits 3", ended == [1])
check("a failed IOC query is named as FAILED", "IOC query FAILED in: {'ws-broken': 400}" in said)
check("and the summary no longer reads a plain 'IOC hits: none'", re.search(r"IOC hits: none( \||$)", said, re.M) is None)
sys.exit(1 if failed else 0)
PY
exit "$fail"
