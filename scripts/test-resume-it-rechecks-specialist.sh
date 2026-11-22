#!/usr/bin/env bash
# E11-S4: /resume-it re-checks the project's specialist when work is planned, changes it and says so, and brings an
# older app's value up to the record's shape once, at catch-up (build-standards check S15).
#
# WHAT IS PINNED (whole, D5: an added, removed or changed sentence fails until this test is updated too):
#   - .claude/commands/resume-it.md: the "Project specialist re-check" block in execute-work, from its heading up to
#     route A, compared unit by unit (a paragraph, a list item, a table row, a code line, with its indentation;
#     whitespace inside a unit folded); and its place: after WORKTREE FIRST, before route A.
#   - .claude/make-it/references/build-standards.md: the S15 line, whole, once, in Structure & Configuration.
#   - The catch-up scan names S01-S15 and S15's gap; /retrofit-it's Verify names S01-S15; the governance doc counts
#     Structure as S01-S15 (15).
# WHAT IS NOT PINNED: the rest of resume-it.md and build-standards.md (the write guard in
#   test-project-specialist-rule.sh scans them, minus this block and S15).
# THE PAPER CHECK checks this test's own derivation against records written out by hand: a low-risk app that gains
#   payments; a session with no change; a signal removed with the same specialists; a lowering; an older app with
#   "", with "generalist", with a plain specialist name and with no field; a record that is already the shape. The
#   derivation reads the order and names from the reference's rule 2 and the floors from its table; which field
#   carries each signal is this test's reading of the pinned step. It does not show that a real /resume-it session
#   follows the wording (none ran).
# Usage: test-resume-it-rechecks-specialist.sh [ROOT]. With no ROOT it checks this repo, then runs the controls below
# on edited copies (each with its expected result).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

RS=.claude/commands/resume-it.md
RF=.claude/commands/retrofit-it.md
BS=.claude/make-it/references/build-standards.md
REF=.claude/make-it/references/expert-personas.md
GV=docs/AI-GOVERNANCE-HOMEGROWN.md

flat() { tr '\n' ' ' | tr -s ' ' | sed -E 's/^ +//; s/ +$//'; }
section() { awk -v a="$2" -v b="${3:-}" 'on && b != "" && $0 ~ b {on = 0} $0 ~ a {on = 1} on' "$1"; }
# pin LABEL ACTUAL WANT [DROP]: the two texts are equal unit by unit. A unit is a paragraph, a list item, a heading,
# a quote line, one table row, or one line inside a code fence; it keeps the indentation of its first line, and the
# whitespace inside it is folded (so rewrapping a paragraph is not a change, but joining two table rows, joining two
# list items or re-indenting a block is). Units starting with DROP are left out of both.
pin() {
  python3 -I -c '
import re, sys
def norm(text, drop):
    units, cur, fence = [], None, False
    for ln in text.split("\n"):
        s, ind = ln.strip(), len(ln) - len(ln.lstrip(" "))
        if s.startswith("```"):
            if cur: units.append(cur); cur = None
            units.append([ind, s]); fence = not fence; continue
        if fence: units.append([ind, ln.rstrip()]); continue
        if not s:
            if cur: units.append(cur); cur = None
            continue
        if cur is None or re.match(r"(\||#|> |[-*+] |\d+\. )", s):
            if cur: units.append(cur)
            cur = [ind, s]
            if s.startswith("|"): units.append(cur); cur = None
        else:
            cur[1] += " " + s
    if cur: units.append(cur)
    return [str(i) + "|" + " ".join(t.split()) for i, t in units if not (drop and re.fullmatch(drop, " ".join(t.split())))]
label, a, w, drop = sys.argv[1], norm(sys.argv[2], sys.argv[4]), norm(sys.argv[3], sys.argv[4]), sys.argv[4]
if not w: print(f"  {label}: the expected block is empty"); sys.exit(1)
if a == w: sys.exit(0)
k = next((k for k in range(min(len(a), len(w))) if a[k] != w[k]), min(len(a), len(w)))
fa = a[k] if k < len(a) else "(none)"; fw = w[k] if k < len(w) else "(none)"
print("  " + label + " differs at unit " + str(k + 1) + ":\n    file: " + fa[:220] + "\n    pin:  " + fw[:220])
sys.exit(1)' "$1" "$2" "$3" "${4:-}"
}
# 1. the pinned block, S15, and the lists that name it
IFS= read -r -d '' WANT_BLOCK <<'BLOCK' || true
**Project specialist re-check (SILENT -- no user question):** /resume-it is one of the three
writers of the project specialist (`references/expert-personas.md`). It re-checks `expert_persona`
when work is planned, before anything is built: once the plan or the agreed change is settled, in
every route below that changes the app.

1. The triggers are the reference's "What changes it" list, not a judgement: the planned work adds
   or removes a signal of rule 2 (payments; personal or health data beyond the app's own sign-in
   accounts; external users or thousands of them; separate tenants or data at scale; heavy AI use
   or prompts that non-developers edit; a signal its variant declares), the user's words or the
   planned work confirm or disprove an unconfirmed signal, or `project_type` becomes set.
2. With no trigger, nothing is written: the record stays byte for byte as it is. An unconfirmed
   signal that nobody confirms or disproves stays unconfirmed; with no new work there is no
   re-check.
3. With a trigger, work the record out again by the reference's rule from `app-context.json` and
   the planned work, with `set_by` `"/resume-it"` and `set_at` today's date (YYYY-MM-DD). A signal
   the work adds is written `<field>: <value>` from the app-context field the work changes, and
   one the user did not state is marked `"unconfirmed": true`.
4. Compare it as the reference's "Same record or a different one" says. With the same
   specialists, keep their names, `set_by` and `set_at`, and bring only the signals up to date,
   silently. With different specialists, higher or lower but never below the floor, write the new
   record, say one plain line before building (what the app now handles, and what that changes
   about how it is checked, e.g. "Your app now takes card payments, so a security specialist leads
   how it's built and checked."), and add the same line to `CHANGELOG.md`. Nothing is asked.
5. An older value (plain text, empty, or no field) is not re-checked here: catch-up check S15
   brings it up to the record's shape once.

Working as the project specialist while building is card S5; this block only keeps the record
current.
BLOCK
IFS= read -r -d '' S15 <<'BLOCK' || true
**S15** [Tier 0] [FIX] **Project specialist record** -- `.make-it/app-context.json` holds `expert_persona` as the record `references/expert-personas.md` describes (`primary`, `added`, `set_by`, `set_at`). An older value -- a plain text value, an empty one, or no field -- fails. Fix, once, at /resume-it's catch-up: work the record out by the reference's rule from `app-context.json`, with `set_by` `"/resume-it"` and `set_at` today's date, write it in place of the older value, and say one plain line to the user with the same line in `CHANGELOG.md` (for a plain text value that named a specialist, the line says what it was). A value the reference reads as no record is migrated the same way. The fix runs once: after it the check passes.
BLOCK
S15="${S15%$'\n'}"
line() { grep -n -E "$1" "$2" | head -1 | cut -d: -f1; }
check "resume-it.md's re-check block is exactly the pinned text" \
  'pin "re-check block" "$(section "$RS" "^[*][*]Project specialist re-check" "^[*][*]A[.] Continue building")" "$WANT_BLOCK"'
check "the block sits after WORKTREE FIRST and before route A" \
  'a="$(line "^[*][*]WORKTREE FIRST" "$RS")"; b="$(line "^[*][*]Project specialist re-check" "$RS")"; c="$(line "^[*][*]A[.] Continue building" "$RS")"; [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]'
check "build-standards.md holds S15 exactly, once, in Structure & Configuration" \
  '[ "$(grep -cxF -- "$S15" "$BS")" = 1 ] && s="$(line "^## Structure & Configuration" "$BS")" && e="$(line "^## Version Control" "$BS")" && n="$(grep -nxF -- "$S15" "$BS" | cut -d: -f1)" && [ "$s" -lt "$n" ] && [ "$n" -lt "$e" ]'
check "the catch-up scan names S01-S15 and S15's gap" \
  'flat < "$RS" | gq -F "**Structure (S01-S15):**" && flat < "$RS" | gq -F "S15: an \`expert_persona\` that is not yet the record (a plain text value, an empty one, or no field), brought up to it once."'
check "/retrofit-it's Verify names S01-S15; the governance doc counts Structure as S01-S15 (15)" \
  'gq -F "S01-S15" "$RF" && gq -xF "| Structure & Configuration | S01-S15 | 15 | 0 (Universal) |" "$GV"'

# 2. the paper check: the test's own derivation against records written out by hand
paper() {
  python3 -I - "$REF" <<'PY'
import copy, json, re, sys
ref = open(sys.argv[1], encoding="utf-8").read()
def fail(msg): print(f"  paper check: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
flat = " ".join(ref.split())
order = re.findall(r"\d\. (Security|Data|Reliability / platform|AI|Variant): .*?→ \*\*(.+?)\*\*", flat)
if [k for k, _ in order] != ["Security", "Data", "Reliability / platform", "AI", "Variant"]: fail(f"rule 2 order is {order}")
names = dict(order); RANK = {n: k for k, n in order}
floors = dict(re.findall(r"^\| `([a-z-]+)` \| ([^|]+?) \|$", ref, re.M))
TODAY = "2026-11-21"
def signals(ctx, guessed):
    def sig(field, value): return {"signal": f"{field}: {value}", "unconfirmed": field in guessed}
    u, ai = ctx["users"], ctx["ai_features"]
    return {
      "Security": [sig("features", v) for v in ctx["features"] if re.search(r"payment|personal data|health data", v, re.I)],
      "Data": [sig("multi_tenancy.needed", "true")] if ctx["multi_tenancy"]["needed"] else [],
      "Reliability / platform": ([sig("users.internal_or_external", "external")] if u["internal_or_external"] == "external" else [])
                   + ([sig("users.estimated_count", u["estimated_count"])] if re.search(r"thousand|million", u["estimated_count"], re.I) else []),
      "AI": [sig("ai_features.usage_level", "heavy")] if ai["usage_level"] == "heavy" else [], "Variant": []}
def derive(ctx, guessed):
    floor = {"specialist": floors[ctx["project_type"]].replace("its stack", ctx["stack"]),
             "signals": [{"signal": f'project_type: {ctx["project_type"]} (the floor)', "unconfirmed": False}]}
    fired = signals(ctx, guessed)
    applies = [{"specialist": names[k], "signals": fired[k]} for k, _ in order if fired[k]]
    primary, added = (applies[0], applies[1:] + [floor]) if applies else (floor, [])
    return {"primary": primary, "added": added, "set_by": "/resume-it", "set_at": TODAY}
def rank(e):
    for g in e["signals"]:
        m = re.match(r"project_type: (\S+) \(the floor\)", g["signal"])
        if m: return ("floor", m.group(1))
    return (RANK.get(e["specialist"], "other:" + e["specialist"]),)
def ranks(r): return [rank(e) for e in [r["primary"]] + r["added"]]
def recheck(existing, now, planned):  # the block's steps 1-4: (record, a line said)
    if signals(now, []) == signals(planned, []) and now["project_type"] == planned["project_type"]:
        return existing, False                                          # step 2: no trigger, nothing written
    new = derive(planned, [])                                           # step 3
    if ranks(existing) != ranks(new): return new, True                  # step 4: different specialists
    kept = copy.deepcopy(existing)                                      # step 4: same specialists, signals current
    for old, cur in zip([kept["primary"]] + kept["added"], [new["primary"]] + new["added"]): old["signals"] = cur["signals"]
    return kept, False
def migrate(value, ctx):  # S15: an older value (or no field) becomes the record once, and that is said
    if isinstance(value, dict) and set(value) == {"primary", "added", "set_by", "set_at"} and value["primary"].get("specialist"):
        return value, False
    return derive(ctx, []), True
base = lambda **kw: {**{"project_type": "web-app", "stack": "FastAPI + Next.js", "features": ["equipment list"],
    "users": {"internal_or_external": "internal", "estimated_count": "15"}, "multi_tenancy": {"needed": False},
    "ai_features": {"usage_level": "none"}}, **kw}
FLOOR = {"specialist": "Senior full-stack engineer of FastAPI + Next.js", "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]}
LOWREC = {"primary": FLOOR, "added": [], "set_by": "/make-it", "set_at": "2026-10-01"}
APP = base()
PAYS = base(features=["equipment list", "card payments"])
SEC = lambda *f: {"specialist": "Application security engineer", "signals": [{"signal": f"features: {x}", "unconfirmed": False} for x in f]}
def expect(name, got, want, said, line):
    if got != want or line != said: fail(f"{name}: got {json.dumps(got)} said={line}; want {json.dumps(want)} said={said}")
    print(f"  {name}: {json.dumps(got)} -- {'one line said' if said else 'nothing said'}")
rec, line = recheck(LOWREC, APP, PAYS)
expect("a low-risk app gains card payments: security becomes primary", rec,
       {"primary": SEC("card payments"), "added": [FLOOR], "set_by": "/resume-it", "set_at": TODAY}, True, line)
rec, line = recheck(LOWREC, APP, APP)
if rec is not LOWREC: fail("a session with no change wrote the record")
expect("a session with no change: the record byte for byte as it was", rec, LOWREC, False, line)
both = {"primary": SEC("card payments", "customer personal data"), "added": [FLOOR], "set_by": "/make-it", "set_at": "2026-10-01"}
rec, line = recheck(both, base(features=["card payments", "customer personal data"]), base(features=["customer personal data"]))
expect("payments removed, personal data stays: reasons updated silently, set_by and set_at kept", rec,
       {"primary": SEC("customer personal data"), "added": [FLOOR], "set_by": "/make-it", "set_at": "2026-10-01"}, False, line)
paid = {"primary": SEC("card payments"), "added": [FLOOR], "set_by": "/make-it", "set_at": "2026-10-01"}
rec, line = recheck(paid, PAYS, APP)
expect("payments removed and nothing else: lowered to the floor, said", rec,
       {"primary": FLOOR, "added": [], "set_by": "/resume-it", "set_at": TODAY}, True, line)
want = {"primary": FLOOR, "added": [], "set_by": "/resume-it", "set_at": TODAY}
for name, value in (('an older app with ""', ""), ('an older app with "generalist"', "generalist"),
                    ("an older app with a plain specialist name", "Senior full-stack engineer"), ("an older app with no field", None)):
    rec, line = migrate(value, APP)
    expect(name + ": migrated once by S15", rec, want, True, line)
rec, line = migrate(LOWREC, APP)
expect("an app already in the record's shape: S15 passes, nothing changes", rec, LOWREC, False, line)
PY
}
check "paper check (the test's own derivation; no session runs): re-check and migration results written out by hand" 'paper'

# 3. controls (this repo only), each with its expected result
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$RS" "$RF" "$BS" "$REF" "$GV" | tar -xf - -C "$d"; echo "$d"; }
  edit() { local d; d="$(copy)"
           O="$2" N="$3" perl -0pi -e '(my $n = $ENV{N}) =~ s/\\n/\n/g; my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$n/' "$d/$1"
           if cmp -s "$1" "$d/$1"; then echo "  the edit did not apply"; return 2; fi; echo "$d"; }
  fails()  { local d; d="$(edit "$@")" || return 1; ! bash "$SELF" "$d" >/dev/null 2>&1; }
  passes() { local d; d="$(edit "$@")" || return 1; bash "$SELF" "$d" >/dev/null 2>&1 || { bash "$SELF" "$d" | grep -A3 "^FAIL" | head -8 | sed "s|^|    inner: |"; false; }; }
  add() { fails "$1" "$2" "$2$3"; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control, D5) a harmless sentence added inside the block fails" 'add "$RS" "this block only keeps the record current." " This keeps things tidy."'
  check "(control, D5) a harmless sentence added outside the block passes" 'passes "$RS" "Fewer tasks: just do the work." "Fewer tasks: just do the work. (Tidy.)"'
  check "(control) fails: the re-check runs after building" 'fails "$RS" "when work is planned, before anything is built" "after the work is built"'
  check "(control) fails: a judgement trigger added" 'add "$RS" "or \`project_type\` becomes set." " Also re-check whenever the stakes feel different."'
  check "(control) fails: a session with no change refreshes set_at" 'fails "$RS" "nothing is written: the record stays byte for byte as it is." "only \`set_at\` is refreshed."'
  check "(control) fails: the user is asked before a change" 'fails "$RS" "Nothing is asked." "Ask the user to approve first."'
  check "(control) fails: lowering is forbidden" 'fails "$RS" "higher or lower but never below the floor" "only ever higher"'
  check "(control) fails: the line is not written to CHANGELOG.md" 'fails "$RS" ", and add the same line to \`CHANGELOG.md\`." "."'
  check "(control) fails: set_by is wrong" 'fails "$RS" "\`set_by\` \`\"/resume-it\"\`" "\`set_by\` \`\"/make-it\"\`"'
  check "(control) fails: same specialists refresh set_at" 'fails "$RS" "keep their names, \`set_by\` and \`set_at\`, and bring only the signals up to date" "keep their names, rewrite \`set_at\`, and bring the signals up to date"'
  check "(control) fails: the block migrates older values every session" 'fails "$RS" "catch-up check S15 brings it up to the record'"'"'s shape once." "it is migrated again in every session."'
  check "(control) fails: S15 runs every session instead of once" 'fails "$BS" "The fix runs once: after it the check passes." "The fix runs every session."'
  check "(control) fails: S15 migrates silently" 'fails "$BS" "and say one plain line to the user with the same line in \`CHANGELOG.md\`" "silently"'
  check "(control) fails: the catch-up scan forgets S15" 'fails "$RS" "**Structure (S01-S15):**" "**Structure (S01-S14):**"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
