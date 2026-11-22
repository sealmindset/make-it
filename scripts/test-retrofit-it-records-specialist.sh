#!/usr/bin/env bash
# E11-S3: /retrofit-it records the project's specialist when it builds app-context.json from an existing app.
# Fix round 2 (owner decisions D5, D7; review findings N1, N4, N5, N6) is folded in.
#
# WHAT IS PINNED (D5: whole blocks, so an added, removed or changed sentence fails until this test is updated too):
#   - .claude/commands/retrofit-it.md: its opening specialist block (from "**Adopt the specialist persona before
#     retrofitting" up to the reference's import line), and Discovery step 7 (from "**7. Project specialist (SILENT"
#     up to "</step>"), its code-evidence table included. Compared with the text below after every run of whitespace
#     is folded within each unit (a paragraph, list item, heading, table row or code line, with its indentation), so
#     rewrapping is not a change but joining two units or re-indenting one is.
#   - Three lines outside the blocks, each as a whole sentence: Clarification's "never one of them", Foundation's
#     write, and Part E's.
#   - Step 7's place: in Discovery, after the stack compatibility assessment, before Gap Analysis.
# WHAT IS NOT PINNED: the rest of retrofit-it.md (the write guard in test-project-specialist-rule.sh scans it). The
#   one ban kept guards text outside the pinned blocks: no Clarification question asks about the specialist's
#   signals, and the doc page no longer says the specialist is "set behind the scenes from your app's details".
# THE PAPER CHECK checks this test's own derivation against records written out by hand: three sample Discovery
#   profiles (a low-risk internal app; code that shows card payments and public sign-up; personal data unclear) and
#   the existing-record cases of the reference's "Same record or a different one". The derivation reads the order
#   and the specialists' names from the reference's rule 2, the floors from its table and set_by from step 7, and
#   checks the evidence table has one row per rule 2 signal in the same order. It does not show that a real retrofit
#   follows the wording (none ran).
# Usage: test-retrofit-it-records-specialist.sh [ROOT]. With no ROOT it checks this repo, then runs the controls below
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

RF=.claude/commands/retrofit-it.md
REF=.claude/make-it/references/expert-personas.md
D3=.claude/make-it/confluence-docs/03-retrofit-it.md

flat() { tr '\n' ' ' | tr -s ' ' | sed -E 's/^ +//; s/ +$//'; }
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# section FILE START [END]: from the line matching START (included) to the line before END (or the end of the file)
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

# 1. the pinned blocks and lines
IFS= read -r -d '' WANT_TOP <<'BLOCK' || true
**Adopt the specialist persona before retrofitting — do NOT work as a generalist.** Its task
specialist is the **software architect** — preserve original intent, phased change, risk register;
don't break behavior while bolting on foundations. /retrofit-it is also one of the three writers
of the project specialist: Discovery step 7 records it in `expert_persona` from the code, by the
reference's rule. The two stay apart: the architect is the role this skill works in, and the
specialist record is the project's. Once the specialist record is worked out (Discovery step 7), it
works as the architect, held to the checks and output standard of every specialist in the record
as well. Selected automatically; no user prompt. See
`~/.claude/make-it/references/expert-personas.md` (imported below).
BLOCK
IFS= read -r -d '' WANT_STEP <<'BLOCK' || true
**7. Project specialist (SILENT -- no user question):**

Set `project_type` from the code, by the Project Type Classification table in
`templates/app-context.md` (a browser UI with its own backend is `web-app`, a backend with no UI
that serves other systems is `api-service`, and so on). If the code fits no row, `project_type`
stays empty and no specialist record is written (the reference's rule); the run's first write of
`app-context.json` adds one TODO.md line saying why.

Then record the project specialist in `expert_persona` by the reference's rule (its floor row,
filled in from `stack` as the reference says, and rule 2 in its order), as /make-it's Design step
does, with `set_by` `"/retrofit-it"` and `set_at` the date of this run (YYYY-MM-DD). Every
retrofitted app gets a specialist record, a low-risk one its floor. The specialist record is never a
plain text value and never a generalist. What differs from /make-it is where the signals come
from: the code, not an interview.

| Signal (rule 2) | Fires when the code shows |
|---|---|
| Security | a payments SDK (Stripe, Braintree, Adyen, PayPal) or card fields; personal data the app holds about people beyond its own sign-in accounts (customers, patients, contacts: a name with an email, phone, address, date of birth or government ID); health data (diagnoses, medications, patient records). A users table that only holds the app's own sign-in accounts does not fire it. |
| Data | tenant or organisation scoping (`tenant_id` or `org_id` columns, per-tenant filters, row-level security), or data at scale (partitioned tables, bulk-load jobs) |
| Reliability / platform | public sign-up or self-registration, pages or APIs meant for people outside the organisation, or an uptime promise (an SLA) written in the repo |
| AI | an AI SDK behind more than 10 distinct prompts or agents, or prompts stored where non-developers edit them |
| Variant | what its definition file declares under "Project specialist signals", at the rank it declares, when `app-context.json` already names the variant |

Each signal is written `code: <what was found, and where>`; the floor's is
`project_type: <value> (the floor)`. Where the code cannot tell whether a signal fires (for
example, a table whose fields may or may not hold personal data), it fires: record the stricter
specialist and mark that signal `"unconfirmed": true`. This is never a clarifying question and
does not count against Phase 3's 3-5 questions.

The retrofit's own role (the software architect, its task specialist) is never written into
`expert_persona`: the specialist record comes from the signals and the floor only.

If `app-context.json` already holds a specialist record (a second retrofit, or an app /make-it
built), compare it with the new one as the reference's "Same record or a different one" says: with
the same specialists only the signals are brought up to date, silently, even when the old ones were
worded from an interview; different specialists write the new one. When the new one is written over
a specialist record, the one plain line (e.g. "Your app now gets a security specialist because its
code takes card payments.") goes in the report of the step that writes it, and into
`CHANGELOG.md`, which that step adds if the app has none. A value the reference reads as no record
(its "Reading an older value") is not a specialist record: write the new one and say nothing.

**When it is written.** Nothing is written before the plan is approved. The specialist record goes
into the run's first write of `app-context.json`: step 1 (Foundation) in a single-pass retrofit and
in a phased retrofit's first step, or step 12b in an AI-accounting-only run. It describes the app as
Discovery found it, not the foundations the retrofit adds, so a phased retrofit stopped after any
step already has its full specialist record. Part E's final write of `app-context.json` keeps it as
it is.

Apart from the line for a replaced specialist record, nothing here is shown to the user or asked of
them.
BLOCK
check "retrofit-it.md's opening specialist block is exactly the pinned text" \
  'pin "opening block" "$(section "$RF" "^[*][*]Adopt the specialist persona before retrofitting" "^@~/[.]claude/make-it/references/expert-personas[.]md$")" "$WANT_TOP"'
check "retrofit-it.md's Discovery step 7 is exactly the pinned text" \
  'pin "Discovery step 7" "$(section "$RF" "^[*][*]7[.] Project specialist [(]SILENT" "^</step>")" "$WANT_STEP"'
check "step 7 sits in Discovery, after the stack compatibility assessment and before Gap Analysis" \
  '[ "$(grep -n "^\*\*6\. Stack compatibility assessment" "$RF" | cut -d: -f1)" -lt "$(grep -n "^\*\*7\. Project specialist (SILENT" "$RF" | cut -d: -f1)" ] &&
   [ "$(grep -n "^\*\*7\. Project specialist (SILENT" "$RF" | cut -d: -f1)" -lt "$(grep -n "^<step name=\"gap-analysis\">" "$RF" | cut -d: -f1)" ]'
check "Clarification says the specialist is never one of its questions" \
  'section "$RF" "^<step name=\"clarification\">" "^</step>" | flat | gq -F "**Maximum 3-5 questions. Never more.** The project specialist is never one of them (Discovery step 7)."'
check "Foundation's write carries project_type and the record" \
  'has "$RF" "- Generate app-context.json from discovered profile, with \`project_type\` and the project specialist record from Discovery step 7"'
check "Part E keeps the record" \
  'has "$RF" "**Generate app-context.json** -- So /resume-it and /ship-it work going forward. Discovery step 7'"'"'s \`expert_persona\` stays as it is."'
check "(ban outside the pinned blocks) no Clarification question asks about the specialist or its signals" \
  '! section "$RF" "^<step name=\"clarification\">" "^</step>" | flat | gq -iE "\"[^\"]*(personal data|payment|specialist|sign-up|tenant|health)[^\"]*[?]\""'
check "(ban outside the pinned blocks) the doc page no longer says the specialist is set from the app's details" \
  '! flat < "$D3" | gq -iE "set behind the scenes from your app.s details"'

# 2. the paper check: the test's own derivation against records written out by hand
paper() {
  python3 -I - "$RF" "$REF" <<'PY'
import copy, json, re, sys
rf, ref = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
def fail(msg): print(f"  paper check: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
flat_ref, flat_rf = " ".join(ref.split()), " ".join(rf.split())
KINDS = ["Security", "Data", "Reliability / platform", "AI", "Variant"]
order = re.findall(r"\d\. (Security|Data|Reliability / platform|AI|Variant): .*?→ \*\*(.+?)\*\*", flat_ref)
if [k for k, _ in order] != KINDS: fail(f"rule 2 order is {order}")
names = dict(order)
m = re.search(r'with `set_by` `"(/[a-z-]+)"`', flat_rf)
if not m: fail("no set_by in step 7")
set_by = m.group(1)
rows = re.findall(r"^\| (Security|Data|Reliability / platform|AI|Variant) \| ", rf, re.M)
if rows != KINDS: fail(f"evidence table rows are {rows}")
floors = dict(re.findall(r"^\| `([a-z-]+)` \| ([^|]+?) \|$", ref, re.M))
def derive(profile, today):  # profile signals: {kind: ("yes" | "unclear", evidence)}; absent = the code shows none
    floor = {"specialist": floors[profile["project_type"]].replace("its stack", profile["stack"]),
             "signals": [{"signal": f'project_type: {profile["project_type"]} (the floor)', "unconfirmed": False}]}
    applies = [{"specialist": names[k], "signals": [{"signal": f"code: {profile['signals'][k][1]}", "unconfirmed": profile["signals"][k][0] == "unclear"}]}
               for k, _ in order if k in profile["signals"]]
    primary, added = (applies[0], applies[1:] + [floor]) if applies else (floor, [])
    return {"primary": primary, "added": added, "set_by": set_by, "set_at": today}
def reads_as_record(v):
    if isinstance(v, str): return v.strip().lower() not in ("", "generalist", "none")
    return isinstance(v, dict) and bool(v.get("primary", {}).get("specialist"))
def as_record(v): return {"primary": {"specialist": v, "signals": []}, "added": []} if isinstance(v, str) else v
RANK = {n: k for k, n in order}
def rank(entry):  # by rank (D7, G): the floor by its project_type, a rule 2 specialist by its kind
    for g in entry["signals"]:
        m = re.match(r"project_type: (\S+) \(the floor\)", g["signal"])
        if m: return ("floor", m.group(1))
    return (RANK.get(entry["specialist"], "other:" + entry["specialist"]),)
def specialists(r): return [rank(e) for e in [r["primary"]] + r["added"]]
def retrofit(existing, profile, today):  # the reference's "Same record or a different one" (D7, D9)
    new = derive(profile, today)
    if not reads_as_record(existing): return new, False
    if specialists(as_record(existing)) != specialists(new): return new, True
    kept = copy.deepcopy(existing)  # names, set_by and set_at kept; the signal lists brought up to date, silently
    for old, cur in zip([kept["primary"]] + kept["added"], [new["primary"]] + new["added"]): old["signals"] = cur["signals"]
    return kept, False
FLOOR = {"specialist": "Senior full-stack engineer of Flask + React",
         "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]}
P = lambda **s: {"project_type": "web-app", "stack": "Flask + React", "signals": s}
LOW = (P(), {"primary": FLOOR, "added": [], "set_by": "/retrofit-it", "set_at": "2026-11-21"})
PAY = (P(**{"Security": ("yes", "Stripe SDK in requirements.txt and card fields in templates/checkout.html"),
            "Reliability / platform": ("yes", "public self-registration route /register in app/auth.py")}),
       {"primary": {"specialist": "Application security engineer",
                    "signals": [{"signal": "code: Stripe SDK in requirements.txt and card fields in templates/checkout.html", "unconfirmed": False}]},
        "added": [{"specialist": "SRE", "signals": [{"signal": "code: public self-registration route /register in app/auth.py", "unconfirmed": False}]}, FLOOR],
        "set_by": "/retrofit-it", "set_at": "2026-11-21"})
UNCLEAR = (P(**{"Security": ("unclear", "a contacts table with name, email and free-text notes in models.py; whose data it holds is unclear")}),
           {"primary": {"specialist": "Application security engineer",
                        "signals": [{"signal": "code: a contacts table with name, email and free-text notes in models.py; whose data it holds is unclear", "unconfirmed": True}]},
            "added": [FLOOR], "set_by": "/retrofit-it", "set_at": "2026-11-21"})
for name, (profile, want) in (("a low-risk internal app", LOW), ("code shows card payments and public sign-up", PAY),
                              ("personal data unclear", UNCLEAR)):
    got = derive(profile, "2026-11-21")
    if got != want: fail(f"{name}:\n    got  {json.dumps(got)}\n    want {json.dumps(want)}")
    if re.search(r"architect", json.dumps(got), re.I): fail(f"{name}: the architect is in the record")
    print(f"  {name}: {json.dumps(got)}")
SIGNIN = P()  # D8: the code shows only a users table of the app's own sign-in accounts, so Security does not fire
if derive(SIGNIN, "2026-11-21") != LOW[1]: fail("D8: a users-table-only app does not record the floor")
print("  D8, a users-table-only app: the floor")
made = {"primary": {"specialist": "Application security engineer", "signals": [{"signal": "features: card payments", "unconfirmed": False}]},
        "added": [{"specialist": "SRE", "signals": [{"signal": "users.internal_or_external: external", "unconfirmed": False}]},
                  {"specialist": "Senior full-stack engineer of FastAPI + Next.js", "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]}],
        "set_by": "/make-it", "set_at": "2026-10-01"}
made_now = copy.deepcopy(made)
for old, cur in zip([made_now["primary"]] + made_now["added"], [PAY[1]["primary"]] + PAY[1]["added"]): old["signals"] = cur["signals"]
for name, existing, want, said in (("an app /make-it built, the same specialists (floor spelled for another stack), signals from an interview", made, made_now, False),
                                   ("a different record (the low-risk one)", LOW[1], PAY[1], True),
                                   ("the template's empty record", {"primary": {"specialist": "", "signals": []}, "added": [], "set_by": "", "set_at": ""}, PAY[1], False)):
    rec, line = retrofit(existing, PAY[0], "2026-11-21")
    if rec != want or line != said: fail(f"existing record, {name}: got {json.dumps(rec)} said={line}; want said={said}")
    print(f"  existing record, {name}: {'one line said' if said else 'nothing said'}")
PY
}
check "paper check (the test's own derivation; no retrofit runs): three records, the users-table-only app, and three existing-record results" 'paper'

# 3. controls (this repo only), each with its expected result
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$RF" "$REF" "$D3" | tar -xf - -C "$d"; echo "$d"; }
  edit() { local d; d="$(copy)"
           O="$2" N="$3" perl -0pi -e '(my $n = $ENV{N}) =~ s/\\n/\n/g; my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$n/' "$d/$1"
           if cmp -s "$1" "$d/$1"; then echo "  the edit did not apply"; return 2; fi; echo "$d"; }
  fails()  { local d; d="$(edit "$@")" || return 1; ! bash "$SELF" "$d" >/dev/null 2>&1; }
  passes() { local d; d="$(edit "$@")" || return 1; bash "$SELF" "$d" >/dev/null 2>&1 || { bash "$SELF" "$d" | grep -A3 "^FAIL" | head -8 | sed "s|^|    inner: |"; false; }; }
  add() { fails "$1" "$2" "$2$3"; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control, D5) a harmless sentence added inside the opening block fails" 'add "$RF" "Selected automatically; no user prompt." " This keeps things tidy."'
  check "(control, D5) a harmless sentence added inside step 7 fails" 'add "$RF" "the code, not an interview." " This keeps things tidy."'
  check "(control, D5) a harmless sentence added outside the pinned blocks passes" 'passes "$RF" "If stack has issues but is workable, note concerns but proceed." "If stack has issues but is workable, note concerns but proceed. (Tidy.)"'
  check "(control) fails when the record is written as a plain string" 'fails "$RF" "The specialist record is never a plain text value and never a generalist." "Record the specialist as a plain text value."'
  check "(control) fails with set_by wrong (/make-it)" 'fails "$RF" "with \`set_by\` \`\"/retrofit-it\"\`" "with \`set_by\` \`\"/make-it\"\`"'
  check "(control) fails when an unclear signal is recorded as confirmed" 'fails "$RF" "mark that signal \`\"unconfirmed\": true\`." "record it as confirmed."'
  check "(control) fails when a clarifying question is added for the specialist" 'fails "$RF" "**Maximum 3-5 questions. Never more.**" "6. **If personal data is unclear:** \"Does your app store personal data about your users?\"\n\n**Maximum 3-5 questions. Never more.**"'
  check "(control) fails when the architect is recorded as the project specialist" 'fails "$RF" "is never written into \`expert_persona\`: the specialist record comes from the signals and the floor only." "is recorded as the primary, the project specialist."'
  check "(control) fails when the opening block re-infers again" 'fails "$RF" "Selected automatically; no user prompt." "Auto-selected from \`app-context.json\` + this skill; no user prompt."'
  check "(control) fails when the floor is skipped for a low-risk app" 'fails "$RF" "Every retrofitted app gets a specialist record, a low-risk one its floor." "A low-risk app gets no record."'
  check "(control) fails when an existing record is overwritten silently" 'add "$RF" "write the new one and say nothing." " A record with different specialists is replaced without a line."'
  check "(control) fails when the phased-mode rule is reversed" 'fails "$RF" "The specialist record goes into the run'\''s first write of \`app-context.json\`:" "In a phased retrofit the record is written only at the end, in Part E:"'
  check "(control N5-style) fails: an added sentence that refreshes set_at on a kept record" 'add "$RF" "write the new one and say nothing." " Refresh \`set_at\` even when the record is kept."'
  check "(control, D8) fails: the Security row fires on a users table again" 'fails "$RF" " A users table that only holds the app'\''s own sign-in accounts does not fire it." ""'
  check "(control, E) fails: the unknown-type TODO line written during Discovery" 'fails "$RF" "; the run'\''s first write of \`app-context.json\` adds one TODO.md line saying why." ", and TODO.md gets one line saying why."'
  check "(control, F) fails: step 7 says \"the record\" again" 'fails "$RF" "Every retrofitted app gets a specialist record" "Every retrofitted app gets a record"'
  check "(control) the paper check fails when the evidence table drops a row (AI)" 'd="$(copy)"; perl -0pi -e "s/^\| AI \| an AI SDK[^\n]*\n//m" "$d/$RF"; ! bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) the paper check fails when the reference puts data first" 'd="$(copy)"; perl -0pi -e "s/1\. Security: /1. Data: /; s/2\. Data: /2. Security: /" "$d/$REF"; ! bash "$SELF" "$d" >/dev/null 2>&1'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
