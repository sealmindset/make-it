#!/usr/bin/env bash
# E11-S3: /retrofit-it records the project's specialist when it builds app-context.json from an existing app.
# Contract these checks pin (.claude/commands/retrofit-it.md, as the agent reads it):
#   - Discovery step 7 sets project_type from the code and records the project specialist in expert_persona by the
#     reference's rule (floor table, rule 2's order), as /make-it's Design does, set_by "/retrofit-it", set_at. The
#     signals come from the code: a table of what evidence fires each one. Where the code cannot tell, the signal
#     fires (the stricter specialist) and is marked unconfirmed; that is never a clarifying question.
#   - The two specialists stay apart: the architect is /retrofit-it's task specialist, never the project's record.
#     Its own block no longer says it is "auto-selected from app-context.json" or that signals layer in.
#   - An existing record: same result writes nothing and says nothing; a different one is replaced with one line to
#     the user and in CHANGELOG.md; a value that reads as no record is not a record.
#   - When it is written: nothing before the plan is approved; the run's first write of app-context.json (step 1, in
#     single-pass and in a phased retrofit's first step; step 12b in an AI-accounting-only run); Part E keeps it.
#   - A paper check (no retrofit runs): three sample Discovery profiles -- a low-risk internal app, an app whose code
#     shows card payments and public sign-up, an app where personal data is unclear -- each give the record written
#     out below, and three returning-run cases give kept-or-replaced. The derivation reads the floor and the order of
#     specialists from the reference, and set_by from the step; the conditions are the step's pinned sentences. It
#     shows the wording settles the records; it does not show a real retrofit does.
# A tripwire, not a proof. It cannot catch a step that says the right sentences and is then not followed.
# Usage: test-retrofit-it-records-specialist.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail
# on their opposites.
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

flat() { tr '\n' ' ' | tr -s ' '; }
# has FILE SENTENCE: the flattened file holds the whole sentence
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# none REGEX FILE...: no flattened file matches (case ignored)
none() { local re="$1" f m=0; shift; for f in "$@"; do if flat < "$f" | gq -iE -- "$re"; then echo "  in $f: /$re/"; m=1; fi; done; [ "$m" = 0 ]; }
# between A B FILE: the lines from the first match of A to the next match of B
between() { awk -v a="$1" -v b="$2" 'on && $0 ~ b {on = 0} $0 ~ a {on = 1} on' "$3"; }
block()   { between '^[*][*]7[.] Project specialist [(]SILENT' '^</step>' "$RF"; }
clarify() { between '^<step name="clarification">' '^</step>' "$RF"; }
top()     { between '^<objective>' '^</objective>' "$RF"; }

# 1. the task specialist and the record stay apart (the skill's own block)
TOP=(
  'Its task specialist is the **software architect** — preserve original intent, phased change, risk register; don'"'"'t break behavior while bolting on foundations.'
  '/retrofit-it is also one of the three writers of the project specialist: Discovery step 7 records it in `expert_persona` from the code, by the reference'"'"'s rule.'
  'The two stay apart: the architect is the role this skill works in, and the record is the project'"'"'s.'
  'Once the record is worked out (Discovery step 7), it works as the architect, held to the project specialist'"'"'s checks and output standard as well.'
  'Selected automatically; no user prompt.'
)
for s in "${TOP[@]}"; do check "the skill's block says: ${s:0:90}" 'top | flat | gq -F -- "$s" || { echo "  missing: $s"; false; }'; done
check "the skill's block no longer re-infers (\"auto-selected from app-context.json\", \"signals may layer in\")" \
  '! top | flat | gq -iE "auto-selected from \`?app-context|signals may layer in"'

# 2. Discovery step 7, sentence by sentence
STEP=(
  'Set `project_type` from the code, by the Project Type Classification table in `templates/app-context.md` (a browser UI with its own backend is `web-app`, a backend with no UI that serves other systems is `api-service`, and so on).'
  'If the code fits no row, `project_type` stays empty, no record is written (the reference'"'"'s rule), and TODO.md gets one line saying why.'
  'Then record the project specialist in `expert_persona` by the reference'"'"'s rule (its floor table and rule 2'"'"'s order), as /make-it'"'"'s Design step does, with `set_by` `"/retrofit-it"` and `set_at` the date of this run (YYYY-MM-DD).'
  'Every retrofitted app gets a record, a low-risk one its floor.'
  'The record is never a plain text value and never a generalist.'
  'What differs from /make-it is where the signals come from: the code, not an interview.'
  '| Security | a payments SDK (Stripe, Braintree, Adyen, PayPal) or card fields; personal data of the people the app serves (a name with an email, phone, address, date of birth or government ID); health data (diagnoses, medications, patient records) |'
  '| Data | tenant or organisation scoping (`tenant_id` or `org_id` columns, per-tenant filters, row-level security), or data at scale (partitioned tables, bulk-load jobs) |'
  '| Reliability / platform | public sign-up or self-registration, pages or APIs meant for people outside the organisation, or an uptime promise (an SLA) written in the repo |'
  '| AI | an AI SDK behind more than 10 distinct prompts or agents, or prompts stored where non-developers edit them |'
  'Each signal is written `code: <what was found, and where>`; the floor'"'"'s is `project_type: <value> (the floor)`.'
  'Where the code cannot tell whether a signal fires (for example, a table whose fields may or may not hold personal data), it fires: record the stricter specialist and mark that signal `"unconfirmed": true`.'
  'This is never a clarifying question and does not count against Phase 3'"'"'s 3-5 questions.'
  'The retrofit'"'"'s own role (the software architect, its task specialist) is never written into `expert_persona`: the record comes from the signals and the floor only.'
  'If `app-context.json` already holds a record (a second retrofit, or an app /make-it built), keep it, dates included, when the new one has the same specialists and signals.'
  'Otherwise write the new one and say so the way every writer does: one plain line to the user (e.g. "Your app now gets a security specialist because its code takes card payments.") and the same line in `CHANGELOG.md`.'
  'A value the reference reads as no record (its "Reading an older value") is not a record: write the new one and say nothing.'
  '**When it is written.** Nothing is written before the plan is approved.'
  'The record goes into the run'"'"'s first write of `app-context.json`: step 1 (Foundation) in a single-pass retrofit and in a phased retrofit'"'"'s first step, or step 12b in an AI-accounting-only run.'
  'It describes the app as Discovery found it, not the foundations the retrofit adds, so a phased retrofit stopped after any step already has its full record.'
  'Part E'"'"'s final write of `app-context.json` keeps it as it is.'
  'Apart from the line for a replaced record, nothing here is shown to the user or asked of them.'
)
for s in "${STEP[@]}"; do check "Discovery step 7 says: ${s:0:90}" 'block | flat | gq -F -- "$s" || { echo "  missing in step 7: $s"; false; }'; done
check "step 7 sits in Discovery, after the stack compatibility assessment and before Gap Analysis" \
  '[ "$(grep -n "^\*\*6\. Stack compatibility assessment" "$RF" | cut -d: -f1)" -lt "$(grep -n "^\*\*7\. Project specialist (SILENT" "$RF" | cut -d: -f1)" ] &&
   [ "$(grep -n "^\*\*7\. Project specialist (SILENT" "$RF" | cut -d: -f1)" -lt "$(grep -n "^<step name=\"gap-analysis\">" "$RF" | cut -d: -f1)" ]'
check "step 7 asks nothing: no question mark" '! block | flat | gq -F "?"'

# 3. the places that write app-context.json, and Clarification
check "Foundation's write carries project_type and the record" \
  'has "$RF" "- Generate app-context.json from discovered profile, with \`project_type\` and the project specialist record from Discovery step 7"'
check "Part E keeps the record" \
  'has "$RF" "**Generate app-context.json** -- So /resume-it and /ship-it work going forward. Keep the \`expert_persona\` record as Discovery step 7 set it."'
check "Clarification says the specialist is never one of its questions" \
  'clarify | flat | gq -F "The project specialist is never one of them (Discovery step 7)."'
check "no clarifying question asks about the specialist or its signals" \
  '! clarify | flat | gq -iE "\"[^\"]*(personal data|payment|specialist|sign-up|tenant|health)[^\"]*[?]\""'

# 4. none of the old wording, and the architect is never the record
check "retrofit-it.md never records the architect as the project specialist" \
  'none "architect[^.]*\bas the (primary|project specialist)\b|primary[^.]*\bis (the )?(software )?architect|as a plain (text )?value|gets no record" "$RF"'
check "the doc page no longer says the specialist is \"set behind the scenes from your app details\"" \
  'none "set behind the scenes from your app.s details" "$D3"'

# 5. the paper check: sample Discovery profiles, the record the step prescribes for each, written out by hand
paper() {
  python3 -I - "$RF" "$REF" <<'PY'
import copy, json, re, sys
rf, ref = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
def fail(msg): print(f"  paper check: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
flat_ref, flat_rf = " ".join(ref.split()), " ".join(rf.split())
# the reference's rule 2 order (one source of truth), and the step's own set_by
order = re.findall(r"\d\. (Security|Data|Reliability / platform|AI): .*?→ \*\*(.+?)\*\*", flat_ref)
if [k for k, _ in order] != ["Security", "Data", "Reliability / platform", "AI"]: fail(f"rule 2 order is {order}")
names = dict(order)
m = re.search(r'with `set_by` `"(/[a-z-]+)"`', flat_rf)
if not m: fail("no set_by in step 7")
set_by = m.group(1)
# the step's evidence table names the same four signals, in the same order
rows = re.findall(r"^\| (Security|Data|Reliability / platform|AI) \| ", rf, re.M)
if rows != ["Security", "Data", "Reliability / platform", "AI"]: fail(f"evidence table rows are {rows}")
floors = dict(re.findall(r"^\| `([a-z-]+)` \| ([^|]+?) \|$", ref, re.M))

def derive(profile, today):  # profile: {kind: ("yes" | "unclear", evidence)}; absent = the code shows none
    floor = {"specialist": re.sub(r"(its stack|its language)", profile["stack"], floors[profile["project_type"]]),
             "signals": [{"signal": f'project_type: {profile["project_type"]} (the floor)', "unconfirmed": False}]}
    applies = []
    for kind, _ in order:  # where the code cannot tell, the signal fires and is unconfirmed
        if kind in profile["signals"]:
            seen, evidence = profile["signals"][kind]
            applies.append({"specialist": names[kind], "signals": [{"signal": f"code: {evidence}", "unconfirmed": seen == "unclear"}]})
    primary, added = (applies[0], applies[1:] + [floor]) if applies else (floor, [])
    return {"primary": primary, "added": added, "set_by": set_by, "set_at": today}

def reads_as_record(v):
    if isinstance(v, str): return v.strip().lower() not in ("", "generalist", "none")
    return isinstance(v, dict) and bool(v.get("primary", {}).get("specialist"))
def as_record(v): return {"primary": {"specialist": v, "signals": []}, "added": []} if isinstance(v, str) else v
def retrofit(existing, profile, today):
    new = derive(profile, today)
    if not reads_as_record(existing): return new, False
    old = as_record(existing)
    if (old["primary"], old["added"]) == (new["primary"], new["added"]): return existing, False
    return new, True

FLOOR = {"specialist": "Senior full-stack engineer of Flask + React",
         "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]}
P = lambda **s: {"project_type": "web-app", "stack": "Flask + React", "signals": s}
LOW = ("a low-risk internal app", P(), {"primary": FLOOR, "added": [], "set_by": "/retrofit-it", "set_at": "2026-11-21"})
PAY = ("an app whose code shows card payments and public sign-up",
       P(**{"Security": ("yes", "Stripe SDK in requirements.txt and card fields in templates/checkout.html"),
            "Reliability / platform": ("yes", "public self-registration route /register in app/auth.py")}),
       {"primary": {"specialist": "Application security engineer",
                    "signals": [{"signal": "code: Stripe SDK in requirements.txt and card fields in templates/checkout.html", "unconfirmed": False}]},
        "added": [{"specialist": "SRE",
                   "signals": [{"signal": "code: public self-registration route /register in app/auth.py", "unconfirmed": False}]},
                  FLOOR],
        "set_by": "/retrofit-it", "set_at": "2026-11-21"})
UNCLEAR = ("an app where personal data is unclear",
           P(**{"Security": ("unclear", "a contacts table with name, email and free-text notes in models.py; whose data it holds is unclear")}),
           {"primary": {"specialist": "Application security engineer",
                        "signals": [{"signal": "code: a contacts table with name, email and free-text notes in models.py; whose data it holds is unclear", "unconfirmed": True}]},
            "added": [FLOOR], "set_by": "/retrofit-it", "set_at": "2026-11-21"})
for name, profile, want in (LOW, PAY, UNCLEAR):
    got = derive(profile, "2026-11-21")
    if got != want: fail(f"{name}:\n    got  {json.dumps(got)}\n    want {json.dumps(want)}")
    if re.search(r"architect", json.dumps(got), re.I): fail(f"{name}: the architect is in the record")
    print(f"  {name}: {json.dumps(got)}")

same_old = copy.deepcopy(PAY[2]); same_old["set_at"] = "2026-10-01"
for name, existing, kept, said in (("the same record, older date", same_old, True, False),
                                   ("a different record (the low-risk one)", LOW[2], False, True),
                                   ("the template's empty record", {"primary": {"specialist": "", "signals": []}, "added": [], "set_by": "", "set_at": ""}, False, False)):
    rec, line = retrofit(existing, PAY[1], "2026-11-21")
    if (rec is existing) != kept or line != said or (not kept and rec != PAY[2]):
        fail(f"existing record, {name}: kept={rec is existing} said={line}; want kept={kept} said={said}")
    print(f"  existing record, {name}: {'kept' if kept else 'replaced'}, {'one line said' if said else 'nothing said'}")
PY
}
check "paper check (no retrofit runs): the step's wording gives the three records and three existing-record results in this test" 'paper'

# 6. controls (this repo only): each opposite fails
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$RF" "$REF" "$D3" | tar -xf - -C "$d"; echo "$d"; }
  # opp FILE PERL: the copy with one edit must fail this script
  opp() { local d; d="$(copy)"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  # swap FILE OLD NEW: OLD (whitespace-tolerant, literal) replaced by NEW must fail
  swap() { local d; d="$(copy)"; O="$2" N="$3" perl -0pi -e 'my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; (my $n = $ENV{N}) =~ s/\\n/\n/g; s/$o/$n/' "$d/$1"
           ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails when the record is written as a plain string" \
    'swap "$RF" "The record is never a plain text value and never a generalist." "Record the specialist'"'"'s name as a plain text value."'
  check "(control) fails with set_by wrong (/make-it)" 'swap "$RF" "with \`set_by\` \`\"/retrofit-it\"\`" "with \`set_by\` \`\"/make-it\"\`"'
  check "(control) fails with set_by missing" \
    'swap "$RF" ", with \`set_by\` \`\"/retrofit-it\"\` and \`set_at\` the date of this run (YYYY-MM-DD)." "."'
  check "(control) fails when an unclear signal is recorded as confirmed" \
    'swap "$RF" "record the stricter specialist and mark that signal \`\"unconfirmed\": true\`." "record the stricter specialist as confirmed."'
  check "(control) fails when an unclear signal lowers the specialist instead" \
    'swap "$RF" "it fires: record the stricter specialist" "it does not fire: record the lower specialist"'
  check "(control) fails when a clarifying question is added for the specialist" \
    'swap "$RF" "**Maximum 3-5 questions. Never more.**" "6. **If personal data is unclear:** \"Does your app store personal data about your users?\"\n\n**Maximum 3-5 questions. Never more.**"'
  check "(control) fails when the architect is recorded as the project specialist" \
    'swap "$RF" "is never written into \`expert_persona\`: the record comes from the signals and the floor only." "is recorded as the primary in \`expert_persona\`, as the project specialist."'
  check "(control) fails when the skill block re-infers again" \
    'swap "$RF" "Selected automatically; no user prompt." "Auto-selected from \`app-context.json\` + this skill; no user prompt."'
  check "(control) fails when the floor is skipped for a low-risk app" \
    'swap "$RF" "Every retrofitted app gets a record, a low-risk one its floor." "A low-risk app gets no record."'
  check "(control) fails when an existing record is overwritten silently" \
    'swap "$RF" "Otherwise write the new one and say so the way every writer does:" "Otherwise write the new one quietly:"'
  check "(control) fails when the phased-mode rule is reversed (written at the end)" \
    'swap "$RF" "The record goes into the run'"'"'s first write of \`app-context.json\`:" "In a phased retrofit the record is written only at the end, in Part E:"'
  check "(control) fails when a stopped phased retrofit is left without a record" \
    'swap "$RF" "so a phased retrofit stopped after any step already has its full record." "so a phased retrofit stopped halfway has no record yet."'
  check "(control) the paper check fails when the evidence table drops a row (AI)" 'opp "$RF" "s/^\| AI \| an AI SDK[^\n]*\n//m"'
  check "(control) the paper check fails when the reference order puts data first" \
    'opp "$REF" "s/1\. Security: /1. Data: /; s/2\. Data: /2. Security: /"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
