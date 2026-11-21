#!/usr/bin/env bash
# E11-S2: /make-it records the project's specialist at Design, in the record's shape, for every project.
# Contract these checks pin (.claude/commands/make-it.md, as the agent reads it):
#   - The Design step works the specialist out by the reference's rule (the floor for the project_type, raised or
#     added to by the signals) and writes the whole record: primary, added, the signals behind each (a guessed one
#     marked unconfirmed), set_by "/make-it", set_at. Every project gets one, a low-risk one its floor. Silent: no
#     question in the step. A variant's own signals reach the record the same way (variants/_template.md says how).
#   - /make-it's own sub-agent briefs (Build Phase B, the build-verify fix cycle) hand over the recorded specialist
#     plus the one the task needs, instead of each agent inferring its own.
#   - None of the old step is back: the "dominant expert persona" as a plain value, nothing forced below thresholds.
#   - A paper check (no build runs): two sample app-contexts, a low-risk internal web app and a web app taking card
#     payments from external users, each give the record written out below. The derivation reads the floor from the
#     reference's table and the specialists, in order, from the step's own list; the conditions are the step's
#     sentences, pinned above them. It shows the wording settles both records; it does not show a real build does.
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
  '1. The floor is the row for the `project_type` in the reference'"'"'s floor table, filled in from `stack` (a web app'"'"'s backend + frontend, e.g. "Senior full-stack engineer of FastAPI + Next.js"; otherwise its language or editor).'
  'Its signal is `project_type: <value> (the floor)`.'
  '2. Payments, personal data (PII) or health data (PHI) in `compliance`, `purpose` or `features` make "Application security engineer" the primary specialist, and the floor becomes the first added specialist.'
  '3. Each other signal that fires adds its specialist, in this order: `users.internal_or_external` is `external`, or `users.estimated_count` is in the thousands or more -> SRE; `multi_tenancy.needed` is true, or the answers describe data at scale -> Data engineer / DBA; `ai_features.usage_level` is `heavy`, or `ai_features.who_edits_prompts` is not `developers` -> AI / prompt engineer; the app goes to production with an uptime promise (an SLA) the user named -> Platform / SRE.'
  'A variant'"'"'s own signals, named in its definition file under "Project specialist signals", come after these and are recorded the same way.'
  '4. Without the payments, PII or PHI signal, the floor stays the primary specialist; with no signal at all, `added` is empty.'
  '5. A specialist two signals call for appears once, with both signals.'
  'Each signal is written `<field>: <value>`, and one the user did not state (a guess or a smart default, such as a rough user count) is marked `"unconfirmed": true`.'
  '6. `set_by` is `"/make-it"` and `set_at` is the date of this Design (YYYY-MM-DD).'
  'The record is never a plain text value and never a generalist.'
  '/make-it builds and reviews in this specialist'"'"'s role, and hands the record to every sub-agent it briefs.'
  'This is a build-quality lever, not a staffing recommendation.'
  'Nothing here is shown to the user or asked of them.'
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
VS='- **Project specialist signals (optional):** a `variant_config` value that adds a specialist, written as `` `variant_config.[field]` is [value] -> [specialist] ``. /make-it checks it at Design after the base signals and records it in `expert_persona` like any other signal.'
check "the variant template says how a variant's signals reach the record" 'has "$VT" "$VS"'

# 4. none of the old step is back
check "make-it.md has no dominant persona, no plain value, nothing left unforced, no agent inferring its own" \
  'none "dominant (expert )?persona|infer the [^.]*persona|as a plain (text )?value|nothing is forced|below (all )?(the )?thresholds|stay(s)? (a )?generalist|infers? (its|their) own (persona|specialist)" "$MK"'
check "the user doc no longer says the AI picks the one specialist the app \"needs most\"" 'none "specialist your app needs most" "$D1"'

# 5. the paper check: two sample app-contexts, the record the step prescribes for each, written out by hand
paper() {
  python3 -I - "$MK" "$REF" <<'PY'
import json, re, sys
mk, ref = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
def fail(msg): print(f"  paper check: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
flat = " ".join(mk.split())
# step 3's specialists, in its order (the conditions are its pinned sentence)
m = re.search(r"3\. Each other signal that fires adds its specialist, in this order: (.*?)\.(?= A variant)", flat)
if not m: fail("no step 3 list")
names = [x.split(";")[0].strip() for x in m.group(1).split("-> ")[1:]]
if len(names) != 4: fail(f"step 3 names {names}")
SRE, DBA, AIE, PLAT = names
appsec = re.search(r'make "([^"]+)" the primary specialist', flat)
if not appsec: fail("no primary named in step 2")
floors = dict(re.findall(r"^\| `([a-z-]+)` \| ([^|]+?) \|$", ref, re.M))
def stack_of(ctx):
    s = ctx["stack"]
    return f'{s["backend"]} + {s["frontend"]}' if ctx["project_type"] == "web-app" else s["language"]

def derive(ctx, guessed, today):
    def sig(field, value): return {"signal": f"{field}: {value}", "unconfirmed": field in guessed}
    floor = {"specialist": re.sub(r"(its stack|its language|that editor)", stack_of(ctx), floors[ctx["project_type"]]),
             "signals": [{"signal": f'project_type: {ctx["project_type"]} (the floor)', "unconfirmed": False}]}
    added = []
    def add(name, signals):  # step 5: one entry per specialist, its signals merged
        for a in added:
            if a["specialist"] == name: a["signals"] += signals; return
        added.append({"specialist": name, "signals": signals})
    hits = [sig(k, v) for k in ("compliance", "purpose", "features") for v in (ctx[k] if isinstance(ctx[k], list) else [ctx[k]])
            if re.search(r"payment|\bPII\b|personal data|\bPHI\b|health data", v, re.I)]
    if hits:  # step 2
        primary = {"specialist": appsec.group(1), "signals": hits}; added.append(floor)
    else:     # step 4
        primary = floor
    u, at_scale = ctx["users"], re.search(r"thousand|million", ctx["users"]["estimated_count"], re.I)
    s = [sig("users.internal_or_external", "external")] if u["internal_or_external"] == "external" else []
    s += [sig("users.estimated_count", u["estimated_count"])] if at_scale else []
    if s: add(SRE, s)
    if ctx["multi_tenancy"]["needed"]: add(DBA, [sig("multi_tenancy.needed", "true")])
    ai = ctx["ai_features"]
    if ai["usage_level"] == "heavy": add(AIE, [sig("ai_features.usage_level", "heavy")])
    if ai["who_edits_prompts"] != "developers": add(AIE, [sig("ai_features.who_edits_prompts", ai["who_edits_prompts"])])
    if ctx.get("_sla"): add(PLAT, [sig("deployment.target", ctx["deployment"]["target"])])
    return {"primary": primary, "added": added, "set_by": "/make-it", "set_at": today}  # step 6

base = lambda **kw: {**{"project_type": "web-app", "purpose": "", "features": [], "compliance": [],
    "stack": {"backend": "FastAPI", "frontend": "Next.js", "language": "Python"},
    "users": {"internal_or_external": "internal", "estimated_count": "15"},
    "multi_tenancy": {"needed": False}, "ai_features": {"usage_level": "none", "who_edits_prompts": "developers"},
    "deployment": {"target": "local"}}, **kw}
SAMPLES = [
  ("a low-risk internal web app", base(purpose="track the team's equipment loans",
      features=["check out equipment", "return equipment", "overdue list"]), [],
   {"primary": {"specialist": "Senior full-stack engineer of FastAPI + Next.js",
                "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]},
    "added": [], "set_by": "/make-it", "set_at": "2026-11-21"}),
  ("a web app taking card payments from external users", base(purpose="sell event tickets online",
      features=["browse events", "card payments", "email tickets"],
      users={"internal_or_external": "external", "estimated_count": "thousands"},
      deployment={"target": "aws"}), ["users.estimated_count"],
   {"primary": {"specialist": "Application security engineer",
                "signals": [{"signal": "features: card payments", "unconfirmed": False}]},
    "added": [{"specialist": "Senior full-stack engineer of FastAPI + Next.js",
               "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]},
              {"specialist": "SRE",
               "signals": [{"signal": "users.internal_or_external: external", "unconfirmed": False},
                           {"signal": "users.estimated_count: thousands", "unconfirmed": True}]}],
    "set_by": "/make-it", "set_at": "2026-11-21"}),
]
for name, ctx, guessed, want in SAMPLES:
    got = derive(ctx, guessed, "2026-11-21")
    if got != want: fail(f"{name}:\n    got  {json.dumps(got)}\n    want {json.dumps(want)}")
    print(f"  {name}: {json.dumps(got)}")
if SAMPLES[0][3]["primary"]["specialist"] == SAMPLES[1][3]["primary"]["specialist"]: fail("both records name one specialist")
PY
}
check "paper check (no build runs): the step's wording gives the two records written out in this test" 'paper'

# 6. controls (this repo only): each opposite fails
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$MK" "$REF" "$VT" "$D1" | tar -xf - -C "$d"; echo "$d"; }
  # opp FILE PERL: the copy with one edit must fail this script
  opp() { local d; d="$(copy)"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails when the step writes a plain string again" \
    'opp "$MK" "s/The record is never a plain text value and never a generalist\./Record the dominant expert persona in \`expert_persona\` as a plain text value./"'
  check "(control) fails when a low-risk app gets no floor" \
    'opp "$MK" "s/4\. Without the payments, PII or PHI signal,[^\n]*\n[^\n]*/4. Below all thresholds nothing is forced and \`expert_persona\` stays empty./"'
  check "(control) fails with set_by and set_at dropped" 'opp "$MK" "s/6\. \`set_by\` is [^\n]*\n[^\n]*\n//"'
  check "(control) fails with the signals dropped from the record" 'opp "$MK" "s/the added ones, the signals behind each, /the added ones, /"'
  check "(control) fails when a sub-agent brief re-infers (Phase B)" \
    'opp "$MK" "s/it works as both, instead of inferring a specialist of its own\./each subagent infers its own persona./"'
  check "(control) fails when the step asks the user a question" \
    'opp "$MK" "s/(Nothing here is shown to the user or asked of them\.)/\$1 Ask the user: \"Which expert should build this?\"/"'
  check "(control) fails when the step moves before the stack is chosen" \
    'opp "$MK" "my \$b; s/(\*\*Project specialist \(SILENT.*?\n)(?=\*\*)/\$b = \$1; q()/se; s/(\*\*For everything else)/\$b\$1/"'
  check "(control) the paper check fails when step 3 maps external users to another specialist" \
    'opp "$MK" "s/-> SRE;/-> Data engineer \/ DBA;/"'
  check "(control) the paper check fails when step 2 names another primary" \
    'opp "$MK" "s/make \"Application security engineer\" the primary/make \"Security reviewer\" the primary/"'
  check "(control) fails with the variant template's sentence dropped" 'opp "$VT" "s/^- \*\*Project specialist signals[^\n]*\n[^\n]*\n//m"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
