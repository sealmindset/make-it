#!/usr/bin/env bash
# E11-S2: /make-it records the project's specialist at Design, in the record's shape, for every project.
# Fix round 1 (owner decision D1, review findings F6 and F8, 2026-11-21) is folded in.
# Contract these checks pin (.claude/commands/make-it.md, as the agent reads it):
#   - The Design step works the specialist out by the reference's rule and writes the whole record: primary, added,
#     the signals behind each (a guessed one marked unconfirmed), set_by "/make-it", set_at. D1: a fixed order
#     (security, data, reliability/platform, AI, then the floor) decides the primary; the floor is always in the
#     record. Every project gets one, a low-risk one its floor. A variant's own signals come after the base ones and
#     before the floor (variants/_template.md says how).
#   - F6: on a returning run a record already there is kept when the new one has the same specialists and signals;
#     otherwise it is replaced and said in one plain line and in CHANGELOG.md. F8: a value the reference reads as no
#     record is not a record. Otherwise silent: no question in the step.
#   - /make-it's own sub-agent briefs (Build Phase B, the build-verify fix cycle) hand over the recorded specialist
#     plus the one the task needs, instead of each agent inferring its own.
#   - None of the old step is back: the "dominant expert persona" as a plain value, nothing forced below thresholds,
#     only payments changing the primary.
#   - A paper check (no build runs): three sample app-contexts -- a low-risk internal web app, a web app taking card
#     payments from external users, and a multi-tenant internal app with heavy AI and no security signal -- each give
#     the record written out below, and six returning-run cases give the kept-or-replaced result and whether a line
#     is said. The derivation reads the floor from the reference's table and the specialists, in order, from the
#     step's own list; the conditions are the step's sentences, pinned above them. It shows the wording settles the
#     records; it does not show a real build does. The SLA signal is not exercised (no sample names one).
# A tripwire, not a proof. It cannot catch a step that says the right sentences and is then not followed.
# Usage: test-make-it-records-specialist.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on
# their opposites.
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

MK=.claude/commands/make-it.md
REF=.claude/make-it/references/expert-personas.md
VT=.claude/make-it/variants/_template.md
D1=.claude/make-it/confluence-docs/01-make-it.md

flat() { tr '\n' ' ' | tr -s ' '; }
# has FILE SENTENCE: the flattened file holds the whole sentence
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# none REGEX FILE...: no flattened file matches (case ignored)
none() { local re="$1" f m=0; shift; for f in "$@"; do if flat < "$f" | gq -iE -- "$re"; then echo "  in $f: /$re/"; m=1; fi; done; [ "$m" = 0 ]; }
# the Design step's block: from its heading to the next line that starts in bold
step() { awk '/^\*\*Project specialist \(SILENT/ {on=1; print; next} on && /^\*\*/ {on=0} on' "$MK"; }

# 1. the Design step, sentence by sentence
STEP=(
  'Every project records its project specialist in `expert_persona`, a low-risk one included: the primary specialist, the added ones, the signals behind each, `set_by` and `set_at`.'
  'Work it out from the app-context answers once the stack is chosen, in this order:'
  '1. The floor is the row for the `project_type` in the reference'"'"'s floor table, filled in from `stack` (a web app'"'"'s backend + frontend, e.g. "Senior full-stack engineer of FastAPI + Next.js"; otherwise its language, or the editor or browser an extension runs in).'
  'Its signal is `project_type: <value> (the floor)`.'
  '2. Check the signals in the reference'"'"'s order and note the specialist each calls for: payments, personal data (PII) or health data (PHI) in `compliance`, `purpose` or `features` -> Application security engineer; `multi_tenancy.needed` is true, or the answers describe data at scale -> Data engineer / DBA; `users.internal_or_external` is `external`, `users.estimated_count` is in the thousands or more, or the user named an uptime promise (an SLA) for production -> SRE; `ai_features.usage_level` is `heavy`, or `ai_features.who_edits_prompts` is not `developers` -> AI / prompt engineer.'
  'A variant'"'"'s own signals, named in its definition file under "Project specialist signals", come after these and before the floor, and are recorded the same way.'
  '3. The first specialist in that order that applies is the primary; every other one that applies is added, in that order, and the floor is always in the record: the primary when nothing outranks it, otherwise added last.'
  '4. With no signal at all, the floor is the primary and `added` is empty.'
  '5. A specialist two signals call for appears once, with both signals.'
  'Each signal is written `<field>: <value>`, and one the user did not state (a guess or a smart default, such as a rough user count) is marked `"unconfirmed": true`.'
  '6. `set_by` is `"/make-it"` and `set_at` is the date of this Design (YYYY-MM-DD).'
  '7. If `app-context.json` already holds a record (a returning run), keep it, dates included, when the new one has the same specialists and signals.'
  'Otherwise write the new one and say so the way every writer does: one plain line to the user (e.g. "Your app now gets a security specialist because it takes card payments.") and the same line in `CHANGELOG.md`.'
  'A value the reference reads as no record (its "Reading an older value") is not a record: write the new one and say nothing.'
  'The record is never a plain text value and never a generalist.'
  '/make-it builds and reviews in this specialist'"'"'s role, and hands the record to every sub-agent it briefs.'
  'This is a build-quality lever, not a staffing recommendation.'
  'Apart from the line in step 7, nothing here is shown to the user, and nothing is asked of them.'
)
for s in "${STEP[@]}"; do check "the Design step says: ${s:0:90}" 'has "$MK" "$s"'; done
check "the Design step is one block, after the stack is chosen and before app-context.json is written" \
  '[ "$(step | flat | grep -cF "${STEP[0]}")" = 1 ] &&
   [ "$(grep -n "^- Stack selection:" "$MK" | cut -d: -f1)" -lt "$(grep -n "^\*\*Project specialist (SILENT" "$MK" | cut -d: -f1)" ] &&
   [ "$(grep -n "^\*\*Project specialist (SILENT" "$MK" | cut -d: -f1)" -lt "$(grep -n "^\*\*Build the app-context internally" "$MK" | cut -d: -f1)" ]'
check "the Design step asks nothing: no question mark, no ask" \
  '! step | flat | gq -iE "[?]|\bask(s)? (the user|them)\b"'

# 2. /make-it's own sub-agent briefs read the record
BRIEF=(
  'Brief each implementer and reviewer subagent with the project specialist recorded in `expert_persona` at Design plus the specialist its step needs (a data engineer for the migration, say); it works as both, instead of inferring a specialist of its own.'
  'Brief each agent with the project specialist recorded in `expert_persona` plus the specialist its failure needs; it works as both, instead of inferring a specialist of its own.'
)
for s in "${BRIEF[@]}"; do check "a sub-agent brief says: ${s:0:90}" 'has "$MK" "$s"'; done

# 3. the variant template says how a variant's signals reach the record
VS='- **Project specialist signals (optional):** a `variant_config` value that adds a specialist, written as `` `variant_config.[field]` is [value] -> [specialist] ``. /make-it checks it at Design after the base signals and before the floor, and records it in `expert_persona` like any other signal.'
check "the variant template says how a variant's signals reach the record" 'has "$VT" "$VS"'

# 4. none of the old step is back
check "make-it.md has no dominant persona, no plain value, nothing left unforced, no agent inferring its own, no payments-only primary" \
  'none "dominant (expert )?persona|infer the [^.]*persona|as a plain (text )?value|nothing is forced|below (all )?(the )?thresholds|stay(s)? (a )?generalist|infers? (its|their) own (persona|specialist)|floor becomes the first added|without the payments, PII or PHI signal" "$MK"'
check "the user doc no longer says the AI picks the one specialist the app \"needs most\"" 'none "specialist your app needs most" "$D1"'

# 5. the paper check: sample app-contexts, the record the step prescribes for each, written out by hand
paper() {
  python3 -I - "$MK" "$REF" <<'PY'
import copy, json, re, sys
mk, ref = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
def fail(msg): print(f"  paper check: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
flat = " ".join(mk.split())
# step 2's specialists, in its order (the conditions are its pinned sentence)
m = re.search(r"2\. Check the signals in the reference's order and note the specialist each calls for: (.*?)\.(?= A variant)", flat)
if not m: fail("no step 2 list")
names = [x.split(";")[0].strip() for x in m.group(1).split("-> ")[1:]]
if len(names) != 4: fail(f"step 2 names {names}")
SEC, DBA, SRE, AIE = names
floors = dict(re.findall(r"^\| `([a-z-]+)` \| ([^|]+?) \|$", ref, re.M))
def stack_of(ctx):
    s = ctx["stack"]
    return f'{s["backend"]} + {s["frontend"]}' if ctx["project_type"] == "web-app" else s["language"]

def derive(ctx, guessed, today):
    def sig(field, value): return {"signal": f"{field}: {value}", "unconfirmed": field in guessed}
    floor = {"specialist": re.sub(r"(its stack|its language)", stack_of(ctx), floors[ctx["project_type"]]),
             "signals": [{"signal": f'project_type: {ctx["project_type"]} (the floor)', "unconfirmed": False}]}
    sec = [sig(k, v) for k in ("compliance", "purpose", "features") for v in (ctx[k] if isinstance(ctx[k], list) else [ctx[k]])
           if re.search(r"payment|\bPII\b|personal data|\bPHI\b|health data", v, re.I)]
    dba = [sig("multi_tenancy.needed", "true")] if ctx["multi_tenancy"]["needed"] else []
    u = ctx["users"]
    sre = [sig("users.internal_or_external", "external")] if u["internal_or_external"] == "external" else []
    sre += [sig("users.estimated_count", u["estimated_count"])] if re.search(r"thousand|million", u["estimated_count"], re.I) else []
    ai = ctx["ai_features"]
    aie = [sig("ai_features.usage_level", "heavy")] if ai["usage_level"] == "heavy" else []
    aie += [sig("ai_features.who_edits_prompts", ai["who_edits_prompts"])] if ai["who_edits_prompts"] != "developers" else []
    # steps 2, 3 and 5: in order, one entry per specialist with its signals; the first is primary; the floor always in
    applies = [{"specialist": n, "signals": s} for n, s in ((SEC, sec), (DBA, dba), (SRE, sre), (AIE, aie)) if s]
    if applies: primary, added = applies[0], applies[1:] + [floor]
    else:       primary, added = floor, []                                   # step 4
    return {"primary": primary, "added": added, "set_by": "/make-it", "set_at": today}  # step 6

def reads_as_record(v):  # the reference's "Reading an older value"
    if isinstance(v, str): return v.strip().lower() not in ("", "generalist", "none")
    return isinstance(v, dict) and bool(v.get("primary", {}).get("specialist"))
def as_record(v):
    return {"primary": {"specialist": v, "signals": []}, "added": []} if isinstance(v, str) else v
def design(existing, ctx, guessed, today):  # step 7: (the record written, whether a line is said)
    new = derive(ctx, guessed, today)
    if not reads_as_record(existing): return new, False
    old = as_record(existing)
    if (old["primary"], old["added"]) == (new["primary"], new["added"]): return existing, False
    return new, True

FLOOR = {"specialist": "Senior full-stack engineer of FastAPI + Next.js",
         "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]}
base = lambda **kw: {**{"project_type": "web-app", "purpose": "", "features": [], "compliance": [],
    "stack": {"backend": "FastAPI", "frontend": "Next.js", "language": "Python"},
    "users": {"internal_or_external": "internal", "estimated_count": "15"},
    "multi_tenancy": {"needed": False}, "ai_features": {"usage_level": "none", "who_edits_prompts": "developers"},
    "deployment": {"target": "local"}}, **kw}
LOW = ("a low-risk internal web app", base(purpose="track the team's equipment loans",
      features=["check out equipment", "return equipment", "overdue list"]), [],
   {"primary": FLOOR, "added": [], "set_by": "/make-it", "set_at": "2026-11-21"})
PAY = ("a web app taking card payments from external users", base(purpose="sell event tickets online",
      features=["browse events", "card payments", "email tickets"],
      users={"internal_or_external": "external", "estimated_count": "thousands"},
      deployment={"target": "aws"}), ["users.estimated_count"],
   {"primary": {"specialist": "Application security engineer",
                "signals": [{"signal": "features: card payments", "unconfirmed": False}]},
    "added": [{"specialist": "SRE",
               "signals": [{"signal": "users.internal_or_external: external", "unconfirmed": False},
                           {"signal": "users.estimated_count: thousands", "unconfirmed": True}]},
              FLOOR],
    "set_by": "/make-it", "set_at": "2026-11-21"})
DATA = ("a multi-tenant internal app with heavy AI and no security signal", base(purpose="monthly reports for each division",
      features=["division dashboards", "AI report summaries"], multi_tenancy={"needed": True},
      users={"internal_or_external": "internal", "estimated_count": "40"},
      ai_features={"usage_level": "heavy", "who_edits_prompts": "developers"}), [],
   {"primary": {"specialist": "Data engineer / DBA",
                "signals": [{"signal": "multi_tenancy.needed: true", "unconfirmed": False}]},
    "added": [{"specialist": "AI / prompt engineer",
               "signals": [{"signal": "ai_features.usage_level: heavy", "unconfirmed": False}]},
              FLOOR],
    "set_by": "/make-it", "set_at": "2026-11-21"})
for name, ctx, guessed, want in (LOW, PAY, DATA):
    got = derive(ctx, guessed, "2026-11-21")
    if got != want: fail(f"{name}:\n    got  {json.dumps(got)}\n    want {json.dumps(want)}")
    print(f"  {name}: {json.dumps(got)}")
if len({LOW[3]["primary"]["specialist"], PAY[3]["primary"]["specialist"], DATA[3]["primary"]["specialist"]}) != 3:
    fail("the three records do not name three different primaries")

# returning runs, on the payments app: (existing value, kept?, line said?)
same_old = copy.deepcopy(PAY[3]); same_old["set_at"] = "2026-10-01"
TEMPLATE_EMPTY = {"primary": {"specialist": "", "signals": []}, "added": [], "set_by": "", "set_at": ""}
CASES = [("the same record, older date", same_old, True, False),
         ("a different record (the low-risk one)", LOW[3], False, True),
         ("an empty string", "", False, False),
         ("the template's empty record", TEMPLATE_EMPTY, False, False),
         ('the text "generalist"', "generalist", False, False),
         ("an older text value naming a specialist", "Senior full-stack engineer", False, True)]
for name, existing, kept, said in CASES:
    rec, line = design(existing, PAY[1], PAY[2], "2026-11-21")
    if (rec is existing) != kept or line != said or (not kept and rec != PAY[3]):
        fail(f"returning run, {name}: kept={rec is existing} said={line}; want kept={kept} said={said}")
    print(f"  returning run, {name}: {'kept' if kept else 'replaced'}, {'one line said' if said else 'nothing said'}")
PY
}
check "paper check (no build runs): the step's wording gives the three records and six returning-run results in this test" 'paper'

# 6. controls (this repo only): each opposite fails
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$MK" "$REF" "$VT" "$D1" | tar -xf - -C "$d"; echo "$d"; }
  # opp FILE PERL: the copy with one edit must fail this script
  opp() { local d; d="$(copy)"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  # swap FILE OLD NEW: OLD (whitespace-tolerant, literal) replaced by NEW must fail
  swap() { local d; d="$(copy)"; O="$2" N="$3" perl -0pi -e 'my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; (my $n = $ENV{N}) =~ s/\\n/\n/g; s/$o/$n/' "$d/$1"
           ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails when the step writes a plain string again" \
    'swap "$MK" "The record is never a plain text value and never a generalist." "Record the dominant expert persona in \`expert_persona\` as a plain text value."'
  check "(control) fails when a low-risk app gets no floor" \
    'swap "$MK" "4. With no signal at all, the floor is the primary and \`added\` is empty." "4. Below all thresholds nothing is forced and \`expert_persona\` stays empty."'
  check "(control) fails with set_by and set_at dropped" 'opp "$MK" "s/\n *6\. \`set_by\` is [^\n]*//"'
  check "(control) fails with the signals dropped from the record" 'swap "$MK" "the added ones, the signals behind each, " "the added ones, "'
  check "(control) fails when a sub-agent brief re-infers (Phase B)" \
    'swap "$MK" "it works as both, instead of inferring a specialist of its own." "each subagent infers its own persona."'
  check "(control) fails when the step asks the user a question" \
    'swap "$MK" "nothing is asked of them." "nothing is asked of them. Ask the user: \"Which expert should build this?\""'
  check "(control) fails when the step moves before the stack is chosen" \
    'opp "$MK" "my \$b; s/(\*\*Project specialist \(SILENT.*?\n)(?=\*\*)/\$b = \$1; q()/se; s/(\*\*For everything else)/\$b\$1/"'
  check "(control) D1 fails: the floor is always the primary" \
    'swap "$MK" "The first specialist in that order that applies is the primary;" "The floor is the primary;"'
  check "(control) D1 fails: the floor is left out when outranked" \
    'swap "$MK" "and the floor is always in the record: the primary when nothing outranks it, otherwise added last." "and the floor is left out."'
  check "(control) D1 fails: only payments change the primary again" \
    'swap "$MK" "3. The first specialist" "3. Without the payments, PII or PHI signal, the floor stays the primary specialist. The first specialist"'
  check "(control) the paper check fails when step 2 maps external users to another specialist" \
    'swap "$MK" "-> SRE;" "-> Data engineer / DBA;"'
  check "(control) the paper check fails when step 2 names another security specialist" \
    'swap "$MK" "-> Application security engineer;" "-> Security reviewer;"'
  check "(control) the paper check fails when data and reliability swap places in step 2" \
    'opp "$MK" "s/-> Data engineer \/ DBA;/-> TMPNAME;/; s/-> SRE;/-> Data engineer \/ DBA;/; s/-> TMPNAME;/-> SRE;/"'
  check "(control) F6 fails: a returning run replaces the record quietly" \
    'swap "$MK" "Otherwise write the new one and say so the way every writer does:" "Otherwise write the new one quietly, as it would anyway:"'
  check "(control) F6 fails: a returning run always replaces the record" \
    'swap "$MK" "keep it, dates included, when the new one has the same specialists and signals." "replace it."'
  check "(control) F8 fails: a value that reads as no record is treated as a record" \
    'swap "$MK" "is not a record: write the new one and say nothing." "is a record like any other."'
  check "(control) fails with the variant template's sentence dropped" 'opp "$VT" "s/^- \*\*Project specialist signals[^\n]*\n//m"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
