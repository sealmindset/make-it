#!/usr/bin/env bash
# E12-S6 review (2026-11-24): build-verify step 26 a's clean-up deletes only rows the step itself made. /retrofit-it
# runs that step on an app that already exists, so its database can hold a person's real data.
# The fault this pins: the old sweep deleted any row, in any table, whose text or JSON merely CONTAINED
# `live-check-test-`, with cascades: a user whose JSON list named the test note, that user's real notes, and another
# person's note that only mentioned the words.
# What runs: the step's own bash block, cut out of make-it.md, on a database with that case in it:
#   - a user whose JSON list mentions the test note, and that user's real notes;
#   - another person's note whose title and text mention the words (the title does not START with them);
#   - a real comment that points at a test note (the test note is left, and named);
#   - a notification made BY a test note (goes), one that only mentions the words, and one with the same id number
#     for another kind of record (both stay);
#   - a test note and its test comment left by a run that was cut off (go).
# Which database: CI has no Postgres, so by default the block's delete statements run on SQLite with the same schema
# and foreign keys on. Only the catalog lookups are stood in for (`shim.py` below): the statement shapes -- the
# DELETE, its condition, its "no other row points at it" guard -- are read from the block's own text, and the tables
# that point at a table come from SQLite's foreign-key list instead of pg_constraint. `count` and `mentions` are
# catalog-only, so on SQLite the counts are the shim's and `mentions` isn't checked.
# With LIVE_SWEEP_PG=<a running postgres container that has POSTGRES_USER and POSTGRES_DB set>, the block runs
# unchanged through psql in that container (its `public` schema is dropped and remade) and `mentions` is checked too.
# Usage: test-live-checks-sweep-own-rows.sh [MAKE-IT.MD]. With no argument it checks this repo, then proves the checks
# fail on opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
MK="${1:-$root/.claude/commands/make-it.md}"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT

# the step's bash block, without its own q() (the line that reaches the app's database container)
awk '/^26\. \*\*Test every API endpoint/{on=1} /^27\. /{on=0} on && /^ *```bash/{f=1; next} on && f && /^ *```/{f=0} on && f' "$MK" \
  | sed '/^ *q() {/d' > "$TMPD/block.sh"
check "step 26 a has a bash block that defines count, mark, sweep, left and mentions" \
  '[ -s "$TMPD/block.sh" ] && ( for f in count mark sweep left mentions; do grep -E "^ *$f\(\) \{" "$TMPD/block.sh" >/dev/null || exit 1; done )'

cat > "$TMPD/fixture.sql" <<'SQL'
CREATE TABLE users (id integer PRIMARY KEY, name text, recent json);
CREATE TABLE notes (id integer PRIMARY KEY, title text, body text, user_id integer REFERENCES users(id) ON DELETE CASCADE);
CREATE TABLE comments (id integer PRIMARY KEY, note_id integer REFERENCES notes(id) ON DELETE CASCADE, body text);
CREATE TABLE notifications (id integer PRIMARY KEY, title text, kind text, related_id integer, user_id integer REFERENCES users(id) ON DELETE CASCADE);
CREATE TABLE audit_log (id integer PRIMARY KEY, detail json);
INSERT INTO users VALUES (1, 'Ana', '["live-check-test-note-1"]');
INSERT INTO users VALUES (2, 'Ben', '[]');
INSERT INTO notes VALUES (1, 'Groceries', 'milk', 1);
INSERT INTO notes VALUES (2, 'Trip', 'pack', 1);
INSERT INTO notes VALUES (3, 'Re: live-check-test-note-1', 'see live-check-test-note-1', 2);
INSERT INTO notes VALUES (4, 'Ideas', 'later', 2);
INSERT INTO notes VALUES (5, 'live-check-test-leftover', '', 1);
INSERT INTO notes VALUES (6, 'live-check-test-pinned', '', 1);
INSERT INTO comments VALUES (1, 1, 'nice');
INSERT INTO comments VALUES (2, 6, 'Ben wrote this on the test note');
INSERT INTO comments VALUES (3, 5, 'live-check-test-comment');
INSERT INTO notifications VALUES (1, 'Welcome', 'system', NULL, 1);
INSERT INTO notifications VALUES (2, 'New note', 'note', 5, 1);
INSERT INTO notifications VALUES (3, 'About live-check-test- words', 'note', 1, 2);
INSERT INTO notifications VALUES (4, 'Task due', 'task', 5, 2);
INSERT INTO audit_log VALUES (1, '{"msg": "created live-check-test-leftover"}');
SQL

cat > "$TMPD/shim.py" <<'PY'
"""Stands in for `psql -At` on SQLite. Plain SQL runs as it is. The block's delete generator is rebuilt from its own
format() strings, with SQLite's foreign-key list in place of pg_constraint. Counts are native."""
import re, sqlite3, sys
db = sqlite3.connect(sys.argv[1]); db.execute("PRAGMA foreign_keys = ON")
sql = sys.stdin.read()
flat = re.sub(r"\s+", " ", sql)
tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")]
if "\\gexec" not in flat:
    for st in [s for s in re.split(r";\s*\n", sql) if s.strip()]:
        for row in db.execute(st): print("|".join("" if v is None else str(v) for v in row))
elif re.search(r"\b(DELETE|UPDATE|INSERT|DROP|TRUNCATE)\b", flat) and "information_schema" in flat:
    sys.exit("shim: a write built from information_schema (every table, every column) is not run")
elif "pg_constraint" in flat or "DELETE" in flat:
    m = re.search(r"format\('(DELETE FROM %s AS t WHERE \(%s\)%s)', '(\w+)'::regclass, \$c\$(.*?)\$c\$, (.*)\\gexec", flat)
    if not m: sys.exit("shim: no delete of the known shape in: " + flat[:120])
    tmpl, table, cond, rest = m.groups()
    g = re.search(r"format\('( AND NOT EXISTS \(SELECT 1 FROM %s AS k WHERE %s\))'", rest)
    j = re.search(r"format\('(k\.%I = t\.%I)'", rest)
    guards = ""
    if g and j and "pg_constraint" in rest and "confrelid = '%s'::regclass" % table in rest:
        for child in tables:
            fks = {}
            for fid, _, parent, frm, to, *_ in db.execute(f"PRAGMA foreign_key_list({child})"):
                if parent == table: fks.setdefault(fid, []).append(j.group(1).replace("%I", frm, 1).replace("%I", to, 1))
            for conds in fks.values():
                guards += g.group(1).replace("%s", child, 1).replace("%s", " AND ".join(conds), 1)
    st = tmpl.replace("%s", table, 1).replace("%s", cond, 1).replace("%s", guards, 1)
    print("DELETE %d" % db.execute(st).rowcount)
elif "information_schema.tables" in flat:
    for t in tables: print("%s|%d" % (t, db.execute(f"SELECT count(*) FROM {t}").fetchone()[0]))
elif "information_schema.columns" in flat:
    pass  # mentions: catalog-only and read-only; checked on Postgres
else:
    sys.exit("shim: not understood: " + flat[:120])
db.commit()
PY

if [ -n "${LIVE_SWEEP_PG:-}" ]; then
  MODE=postgres
  q() { docker exec -i "$LIVE_SWEEP_PG" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'; }
  printf '%s\n' "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" | q >/dev/null
else
  MODE=sqlite
  q() { python3 -I "$TMPD/shim.py" "$TMPD/app.db"; }
fi
NOTE="mark notifications related_id notes title"
# the run: count, sweep, count, the writes, sweep, count -- as step 26 a orders it
( set +e
  . "$TMPD/block.sh"
  q < "$TMPD/fixture.sql" >/dev/null
  echo "== A"; count
  echo "== sweep1"; $NOTE "t.kind = 'note'"; sweep comments body; sweep notes title
  echo "== B"; count
  printf '%s\n' "INSERT INTO notes VALUES (7, 'live-check-test-run', '', 2);" \
    "INSERT INTO notifications VALUES (5, 'New note', 'note', 7, 2);" \
    "INSERT INTO comments VALUES (4, 7, 'live-check-test-c');" | q >/dev/null
  echo "== sweep2"; $NOTE "t.kind = 'note'"; sweep comments body; sweep notes title
  echo "== left"; left notes title
  echo "== C"; count
  echo "== rows"
  for t in users notes comments notifications audit_log; do printf '%s\n' "SELECT '$t', id FROM $t ORDER BY id;" | q; done
  echo "== mentions"; mentions
) > "$TMPD/record" 2>&1 || true

python3 -I - "$TMPD/record" "$MODE" <<'PY' || fail=1
import sys
rec, mode = open(sys.argv[1]).read(), sys.argv[2]
sec, cur = {}, None
for l in rec.splitlines():
    if l.startswith("== "): cur = sec.setdefault(l[3:], [])
    elif cur is not None and l.strip(): cur.append(l.strip())
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        print("  " + str(why)[:400])
def counts(k): return {a: int(b) for a, b in (l.split("|") for l in sec.get(k, []) if l.count("|") == 1 and l.split("|")[1].isdigit())}
def dels(k):
    out = {}
    for l in sec.get(k, []):
        t, _, tag = l.partition("|")
        if tag.startswith("DELETE "): out[t] = out.get(t, 0) + int(tag.split()[1])
    return out
A, B, C = counts("A"), counts("B"), counts("C")
rows = {}
for l in sec.get("rows", []):
    t, _, i = l.partition("|"); rows.setdefault(t, []).append(int(i) if i.isdigit() else i)
REAL = {"users": [1, 2], "notes": [1, 2, 3, 4], "comments": [1, 2], "notifications": [1, 3, 4], "audit_log": [1]}
check("the first count is taken before the first sweep (it still has the cut-off run's rows)",
      A == {"audit_log": 1, "comments": 3, "notes": 6, "notifications": 4, "users": 2}, A)
check("the first sweep removes only the cut-off run's own rows and says how many, table by table",
      dels("sweep1") == {"notifications": 1, "comments": 1, "notes": 1}, sec.get("sweep1"))
check("after the first sweep each table is smaller by exactly what the sweep said, and by nothing else",
      bool(B) and all(A.get(t, 0) - B.get(t, 0) == dels("sweep1").get(t, 0) for t in A), (A, B))
lost = {t: [i for i in ids if i not in rows.get(t, [])] for t, ids in REAL.items()}
check("every real row survives: the user whose JSON list names the test note, that user's notes, the note and the notification that only mention the words, the same id number under another kind",
      not any(lost.values()), "lost: " + str({t: v for t, v in lost.items() if v}) + " | " + rec[-300:])
check("the step's own rows go: the leftover note, its comment and its notification, and the run's own",
      [i for i in rows.get("notes", []) if i in (5, 7)] == [] and [i for i in rows.get("comments", []) if i in (3, 4)] == []
      and [i for i in rows.get("notifications", []) if i in (2, 5)] == [], rows)
check("a test row a real row points at is left, and named", sec.get("left") == ["notes|live-check-test-pinned"]
      and 6 in rows.get("notes", []) and 2 in rows.get("comments", []), sec.get("left"))
check("the last count equals the count after the first sweep: nothing grew, nothing shrank", bool(C) and C == B, (B, C))
if mode == "postgres":
    check("(postgres) mentions names the tables that still hold the words, and deletes nothing",
          counts("mentions") == {"audit_log": 1, "notes": 2, "notifications": 1, "users": 1}, sec.get("mentions"))
sys.exit(1 if failed else 0)
PY

# controls (this repo only, on SQLite): each opposite fails for its own reason
if [ -z "${1:-}" ]; then
  # opp PERL REASON: make-it.md with one edit must fail this script on the check named REASON
  opp() {
    cp "$MK" "$TMPD/m.md"; perl -0pi -e "$1" "$TMPD/m.md"; ! cmp -s "$MK" "$TMPD/m.md" || return 1
    local out; out="$(LIVE_SWEEP_PG= bash "$SELF" "$TMPD/m.md" 2>&1)" && return 1
    printf '%s\n' "$out" | grep -F "FAIL $2" >/dev/null
  }
  check "(control) the sweep matches rows that CONTAIN the words: a real note goes" \
    'opp "s/(sweep\(\) \{ del \"\\\$1\" \"t\.\\\$2 LIKE .)\\\$P%/\$1%\\\$P%/" "every real row survives"'
  check "(control) the guard removed: a test note a real comment points at goes, and the comment with it" \
    'opp "s/, coalesce\(string_agg\(format\(. AND NOT EXISTS.*?\), ..\), ..\)\) FROM pg_constraint/, \$\$\$\$) FROM pg_constraint/s" "every real row survives"'
  check "(control) the old sweep back (every table, every text or JSON column, contains): nothing of it runs" \
    'opp "s/^ *sweep\(\) \{.*\n/       sweep() { printf \"%s\\\\n\" \"SELECT format(\x27DELETE FROM %I.%I WHERE %I::text LIKE %L\x27, table_schema, table_name, column_name, \x27%live-check-test-%\x27) FROM information_schema.columns \\\\gexec\" | q; }\n/m" "the step'"'"'s own rows go"'
fi

[ "$fail" = 0 ] && echo "ALL PASSED ($MODE)" || { echo "SOME FAILED ($MODE)"; exit 1; }
