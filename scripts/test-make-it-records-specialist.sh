#!/usr/bin/env bash
# E11-S2: /make-it records the project's specialist at Design, in the record's shape, for every project.
# Fix rounds 1 and 2 (owner decisions D1, D5, D6, D7; review findings F6, F8, N1, N4, N5, N6, N9) are folded in.
#
# WHAT IS PINNED (D5: whole blocks, so an added, removed or changed sentence fails until this test is updated too):
#   - .claude/commands/make-it.md: the Design step block, from "**Project specialist (SILENT" up to
#     "**Build the app-context internally."; and the two paragraphs that brief /make-it's own sub-agents (Build
#     Phase B's Subagent-Driven Development paragraph, and the fix cycle's parallel-dispatch paragraph). Compared with
#     the text below after every run of whitespace is folded to one space, so rewrapping a line is not a change.
#   - .claude/make-it/variants/_template.md: the "Project specialist signals" line, whole; and Build step g's
#     sentence that carries the specialist line into CHANGELOG.md.
#   Compared unit by unit (a paragraph, a list item, a heading, a table row, a code line; with the indentation of its
#   first line; whitespace inside a unit folded): rewrapping is not a change, joining two list items is.
#   - The Design block's place: after the stack is chosen, before app-context.json is written.
# WHAT IS NOT PINNED: the rest of make-it.md and of the variant template. The one ban kept guards text outside the
#   pinned blocks: the user doc 01-make-it.md no longer says the AI picks the one specialist the app "needs most".
# THE PAPER CHECK checks this test's own derivation against records written out by hand: three sample app-contexts
#   (a low-risk internal web app; card payments from external users; a multi-tenant internal app with heavy AI and
#   no security signal) and the returning-run cases of the reference's "Same record or a different one". The
#   derivation reads the order and the specialists' names from the reference's rule 2 and the floors from its table;
#   which app-context field carries each signal is this test's reading of the pinned step 2. It shows the pinned
#   wording and the reference settle those records; it does not show that a real build follows them (none ran).
# Usage: test-make-it-records-specialist.sh [ROOT]. With no ROOT it checks this repo, then runs the controls below on
# edited copies (each with its expected result).
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

flat() { tr '\n' ' ' | tr -s ' ' | sed -E 's/^ +//; s/ +$//'; }
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

# 1. the pinned blocks
IFS= read -r -d '' WANT_STEP <<'BLOCK' || true
**Project specialist (SILENT -- no user question):**

Reference `references/expert-personas.md`. Every project records its project specialist in
`expert_persona`, a low-risk one included: the primary specialist, the added ones, the signals
behind each, `set_by` and `set_at`. Work it out from the app-context answers once the stack is
chosen:

1. The floor is the reference's floor row for the `project_type`, filled in from `stack` as the
   reference says. Its signal is `project_type: <value> (the floor)`.
2. Check the signals of the reference's rule 2, in its order, and build the record by its "The
   order decides the primary" paragraph. In app-context they are carried by: security --
   `compliance`, `purpose`, `features` (personal data as rule 2 defines it, not the sign-in
   accounts every app has); data -- `multi_tenancy.needed` and the answers; reliability --
   `users.internal_or_external`, `users.estimated_count`, and an uptime promise the user named; AI -- `ai_features.usage_level` and `ai_features.who_edits_prompts` (the app's own AI use, never
   the scaffold's AI Instructions screens); a variant -- the
   `variant_config` fields its definition file names, at the rank it declares.
3. Each signal is written `<field>: <value>`. Only what the person said counts: a smart default
   /make-it filled in is not a signal, and one the person gave only as a guess ("maybe a few
   thousand") is marked `"unconfirmed": true`.
4. `set_by` is `"/make-it"` and `set_at` is the date of this Design (YYYY-MM-DD).
5. If `app-context.json` already holds a record (a returning run), update it as the reference's
   "The record is the starting point" says (keep each signal the answers do not disprove), then
   compare as its "Same record or a different one" says: with the same specialists only the
   signals are brought up to date, silently; different specialists write the new one. When the new
   one is written over a record, the one plain line (e.g. "Your app now gets a security specialist
   because it takes card payments.") goes in the plain-English summary's sentence on what departs
   from the standard setup, and into `CHANGELOG.md`: now if the file exists, otherwise in the
   initial entry Build step g writes. An older value (the reference's "Reading an older value") is not compared: replace it and say
   S15's line the same way.

The record is never a plain text value and never a generalist. /make-it builds and reviews in the
role of every specialist in the record, the primary leading, and hands the record to every
sub-agent it briefs. This is a build-quality lever, not a staffing recommendation. Apart from the
line in step 5, nothing here is shown to the user, and nothing is asked of them.
BLOCK
IFS= read -r -d '' WANT_SDD <<'BLOCK' || true
When the app-specific work is sizable (several independent domains/features), execute it via
Subagent-Driven Development (`/subagent-it`, see `subagent-driven-development.md`): treat these
steps as the plan, dispatch a fresh implementer subagent per step + per-step review + a final
whole-branch review, keeping your own context for coordination. Stay sequential on shared files.
Brief each implementer and reviewer subagent with the project specialist recorded in
`expert_persona` at Design plus the specialist its step needs (a data engineer for the migration,
say); it works as both, instead of inferring a specialist of its own.
BLOCK
IFS= read -r -d '' WANT_FIX <<'BLOCK' || true
If several failures are INDEPENDENT (different files/subsystems/root causes), fix them in
parallel instead of sequentially: dispatch one agent per domain (`/dispatch-it`, see
`parallel-dispatch.md`), isolate writers in their own worktrees, then re-run the FULL suite
once and integrate. Keep related failures together (find the shared cause first). Brief each
agent with the project specialist recorded in `expert_persona` plus the specialist its failure
needs; it works as both, instead of inferring a specialist of its own.
BLOCK
VS='- **Project specialist signals (optional):** one line per signal, written as `` `variant_config.[field]` is [value] -> [specialist], rank: [security | data | reliability | AI | after AI, before the floor] ``, with that specialist'"'"'s checks and output standard. Writers copy the declared rank and never judge it; /make-it, /retrofit-it and /resume-it apply the signal like any other.'
check "make-it.md's Design step block is exactly the pinned text" \
  'pin "Design step" "$(section "$MK" "^[*][*]Project specialist [(]SILENT" "^[*][*]Build the app-context internally")" "$WANT_STEP"'
check "make-it.md's Subagent-Driven Development brief paragraph is exactly the pinned text" \
  'pin "Phase B brief" "$(section "$MK" "^When the app-specific work is sizable" "^$")" "$WANT_SDD"'
check "make-it.md's parallel fix brief paragraph is exactly the pinned text" \
  'pin "fix-cycle brief" "$(section "$MK" "^If several failures are INDEPENDENT" "^$")" "$WANT_FIX"'
check "the variant template's \"Project specialist signals\" line is exactly the pinned text, once" '[ "$(grep -cxF -- "$VS" "$VT")" = 1 ]'
check "Build step g carries the specialist line Design may need to write" \
  'flat < "$MK" | gq -F "g. **Create CHANGELOG.md** with initial entry (carrying the specialist line from Design step 5 when Design wrote a new record over an older one),"'
check "the Design block sits after the stack is chosen and before app-context.json is written" \
  '[ "$(grep -n "^- Stack selection:" "$MK" | cut -d: -f1)" -lt "$(grep -n "^\*\*Project specialist (SILENT" "$MK" | cut -d: -f1)" ] &&
   [ "$(grep -n "^\*\*Project specialist (SILENT" "$MK" | cut -d: -f1)" -lt "$(grep -n "^\*\*Build the app-context internally" "$MK" | cut -d: -f1)" ]'
check "(ban outside the pinned blocks) the user doc no longer says the AI picks the one specialist the app \"needs most\"" \
  '! flat < "$D1" | gq -iF "specialist your app needs most"'

# 2. the paper check: the test's own derivation against records written out by hand
paper() {
  python3 -I - "$REF" <<'PY'
import copy, json, re, sys
ref = open(sys.argv[1], encoding="utf-8").read()
def fail(msg): print(f"  paper check: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
flat = " ".join(ref.split())
order = re.findall(r"\d\. (Security|Data|Reliability / platform|AI|Variant): .*?→ \*\*(.+?)\*\*", flat)
if [k for k, _ in order] != ["Security", "Data", "Reliability / platform", "AI", "Variant"]: fail(f"rule 2 order is {order}")
names = dict(order)
floors = dict(re.findall(r"^\| `([a-z-]+)` \| ([^|]+?) \|$", ref, re.M))
def derive(ctx, guessed, today):
    def sig(field, value): return {"signal": f"{field}: {value}", "unconfirmed": field in guessed}
    s = ctx["stack"]
    floor = {"specialist": floors[ctx["project_type"]].replace("its stack", f'{s["backend"]} + {s["frontend"]}'),
             "signals": [{"signal": f'project_type: {ctx["project_type"]} (the floor)', "unconfirmed": False}]}
    u, ai = ctx["users"], ctx["ai_features"]
    fired = {
      "Security": [sig(k, v) for k in ("compliance", "purpose", "features") for v in (ctx[k] if isinstance(ctx[k], list) else [ctx[k]])
                   if re.search(r"payment|\bPII\b|personal data|\bPHI\b|health data", v, re.I)],
      "Data": [sig("multi_tenancy.needed", "true")] if ctx["multi_tenancy"]["needed"] else [],
      "Reliability / platform": ([sig("users.internal_or_external", "external")] if u["internal_or_external"] == "external" else [])
                   + ([sig("users.estimated_count", u["estimated_count"])] if re.search(r"thousand|million", u["estimated_count"], re.I) else []),
      "AI": ([sig("ai_features.usage_level", "heavy")] if ai["usage_level"] == "heavy" else [])
            + ([sig("ai_features.who_edits_prompts", ai["who_edits_prompts"])] if ai["who_edits_prompts"] != "developers" else []),
      "Variant": []}
    applies = [{"specialist": names[k], "signals": fired[k]} for k, _ in order if fired[k]]
    primary, added = (applies[0], applies[1:] + [floor]) if applies else (floor, [])
    return {"primary": primary, "added": added, "set_by": "/make-it", "set_at": today}
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
def design(existing, ctx, guessed, today):  # step 5 and the reference's "Same record or a different one" (D7, D9)
    new = derive(ctx, guessed, today)
    if not isinstance(existing, dict) or not reads_as_record(existing): return new, True  # an older value: replaced, S15's line
    if specialists(as_record(existing)) != specialists(new): return new, True
    kept = copy.deepcopy(existing)  # names, set_by and set_at kept; the signal lists brought up to date, silently
    for old, cur in zip([kept["primary"]] + kept["added"], [new["primary"]] + new["added"]): old["signals"] = cur["signals"]
    return kept, False
FLOOR = {"specialist": "Senior full-stack engineer of FastAPI + Next.js",
         "signals": [{"signal": "project_type: web-app (the floor)", "unconfirmed": False}]}
base = lambda **kw: {**{"project_type": "web-app", "purpose": "", "features": [], "compliance": [],
    "stack": {"backend": "FastAPI", "frontend": "Next.js", "language": "Python"},
    "users": {"internal_or_external": "internal", "estimated_count": "15"},
    "multi_tenancy": {"needed": False}, "ai_features": {"usage_level": "none", "who_edits_prompts": "developers"}}, **kw}
LOW = (base(purpose="track the team's equipment loans", features=["check out equipment", "return equipment", "overdue list"]), [],
       {"primary": FLOOR, "added": [], "set_by": "/make-it", "set_at": "2026-11-21"})
PAY = (base(purpose="sell event tickets online", features=["browse events", "card payments", "email tickets"],
            users={"internal_or_external": "external", "estimated_count": "thousands"}), ["users.estimated_count"],
       {"primary": {"specialist": "Application security engineer", "signals": [{"signal": "features: card payments", "unconfirmed": False}]},
        "added": [{"specialist": "SRE", "signals": [{"signal": "users.internal_or_external: external", "unconfirmed": False},
                                                    {"signal": "users.estimated_count: thousands", "unconfirmed": True}]}, FLOOR],
        "set_by": "/make-it", "set_at": "2026-11-21"})
DATA = (base(purpose="monthly reports for each division", features=["division dashboards", "AI report summaries"],
             multi_tenancy={"needed": True}, users={"internal_or_external": "internal", "estimated_count": "40"},
             ai_features={"usage_level": "heavy", "who_edits_prompts": "developers"}), [],
        {"primary": {"specialist": "Data engineer / DBA", "signals": [{"signal": "multi_tenancy.needed: true", "unconfirmed": False}]},
         "added": [{"specialist": "AI / prompt engineer", "signals": [{"signal": "ai_features.usage_level: heavy", "unconfirmed": False}]}, FLOOR],
         "set_by": "/make-it", "set_at": "2026-11-21"})
for name, (ctx, guessed, want) in (("a low-risk internal web app", LOW), ("card payments from external users", PAY),
                                   ("a multi-tenant internal app with heavy AI, no security signal", DATA)):
    got = derive(ctx, guessed, "2026-11-21")
    if got != want: fail(f"{name}:\n    got  {json.dumps(got)}\n    want {json.dumps(want)}")
    print(f"  {name}: {json.dumps(got)}")
SIGNIN = (base(purpose="lend equipment to staff", features=["staff sign in with their name and email", "equipment list"]), [],
          {"primary": FLOOR, "added": [], "set_by": "/make-it", "set_at": "2026-11-21"})
got = derive(SIGNIN[0], [], "2026-11-21")
if got != SIGNIN[2]: fail(f"D8, sign-in accounts only: got {json.dumps(got)}")
print("  D8, an app whose only personal data is its sign-in accounts: the floor")
older = copy.deepcopy(PAY[2]); older["set_at"] = "2026-10-01"
reworded = copy.deepcopy(older); reworded["set_by"] = "/retrofit-it"
reworded["primary"]["signals"] = [{"signal": "code: Stripe SDK in requirements.txt", "unconfirmed": False}]
reworded_now = copy.deepcopy(reworded); reworded_now["primary"]["signals"] = PAY[2]["primary"]["signals"]
confirmed = copy.deepcopy(older); confirmed["added"][0]["signals"][1]["unconfirmed"] = False
extra = copy.deepcopy(older); extra["primary"]["signals"].append({"signal": "features: stored customer addresses", "unconfirmed": False})
spelled = copy.deepcopy(older); spelled["added"][1]["specialist"] = "Senior full-stack engineer of Next.js 15"
CASES = [  # (name, existing, guessed now, want record, want a line said)
  ("the same record, older date", older, ["users.estimated_count"], older, False),
  ("the same specialists, signals worded by /retrofit-it", reworded, ["users.estimated_count"], reworded_now, False),
  ("the same specialists, the guessed user count now stated", older, [], confirmed, False),
  ("the same specialists, a signal that is gone (B)", extra, ["users.estimated_count"], older, False),
  ("the same specialists, the floor spelled \"Next.js 15\" (G)", spelled, ["users.estimated_count"], spelled, False),
  ("different specialists (the low-risk record)", LOW[2], ["users.estimated_count"], PAY[2], True),
  ("an empty string (an older value: S15's line)", "", ["users.estimated_count"], PAY[2], True),
  ("the template's empty record (an older value: S15's line)", {"primary": {"specialist": "", "signals": []}, "added": [], "set_by": "", "set_at": ""}, ["users.estimated_count"], PAY[2], True),
  ('the text "generalist" (an older value: S15\'s line)', "generalist", ["users.estimated_count"], PAY[2], True),
  ("an older text value naming a specialist", "Senior full-stack engineer", ["users.estimated_count"], PAY[2], True)]
for name, existing, guessed, want, said in CASES:
    rec, line = design(existing, PAY[0], guessed, "2026-11-21")
    if rec != want or line != said: fail(f"returning run, {name}: got {json.dumps(rec)} said={line}; want said={said}")
    print(f"  returning run, {name}: {'one line said' if said else 'nothing said'}")
PY
}
check "paper check (the test's own derivation; no build runs): three records, the sign-in-only app, and ten returning-run results" 'paper'

# 3. controls (this repo only), each with its expected result
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$MK" "$REF" "$VT" "$D1" | tar -xf - -C "$d"; echo "$d"; }
  edit() { local d; d="$(copy)"
           O="$2" N="$3" perl -0pi -e '(my $n = $ENV{N}) =~ s/\\n/\n/g; my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$n/' "$d/$1"
           if cmp -s "$1" "$d/$1"; then echo "  the edit did not apply"; return 2; fi; echo "$d"; }
  fails()  { local d; d="$(edit "$@")" || return 1; ! bash "$SELF" "$d" >/dev/null 2>&1; }
  passes() { local d; d="$(edit "$@")" || return 1; bash "$SELF" "$d" >/dev/null 2>&1 || { bash "$SELF" "$d" | grep -A3 "^FAIL" | head -8 | sed "s|^|    inner: |"; false; }; }
  add() { fails "$1" "$2" "$2$3"; }
  STEP5='S15'"'"'s line the same way.'
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control, D5) a harmless sentence added inside the Design block fails" 'add "$MK" "$STEP5" " This keeps things tidy."'
  check "(control, D5) a harmless sentence added inside the Phase B brief fails" 'add "$MK" "Stay sequential on shared files." " This keeps things tidy."'
  check "(control, D5) a harmless sentence added inside the fix-cycle brief fails" 'add "$MK" "(find the shared cause first)." " This keeps things tidy."'
  check "(control, D5) a harmless sentence added outside the pinned blocks passes" 'passes "$MK" "Ready for me to start building? This will take a few minutes." "Ready for me to start building? This will take a few minutes. (Tidy.)"'
  check "(control N5) fails: refresh set_at even when the record is kept" 'add "$MK" "$STEP5" " On a returning run, refresh \`set_at\` even when the record is kept."'
  check "(control N5) fails: a lower record is written without a line" 'add "$MK" "$STEP5" " If the new record is lower than the old one, write it without a line."'
  check "(control N5) fails: an unsettled project_type uses the web-app floor" 'add "$MK" "$STEP5" " If \`project_type\` is not settled yet, use the web-app floor."'
  check "(control N5) fails: an internal app never counts the security signal" 'add "$MK" "$STEP5" " An internal app never counts the security signal."'
  check "(control N5) fails: a smart default counts as stated" 'add "$MK" "$STEP5" " A smart default counts as stated."'
  check "(control N1) fails: a variant signal marked security goes first, added to step 2" 'add "$MK" "at the rank it declares." " A variant signal marked \"security\" goes first instead."'
  check "(control N4) fails: \"A reviewer that disagrees updates the record.\" in the Phase B brief" 'add "$MK" "Stay sequential on shared files." " A reviewer that disagrees updates the record."'
  check "(control) fails when the step writes a plain string again" 'fails "$MK" "The record is never a plain text value and never a generalist." "Record the specialist as a plain text value."'
  check "(control) fails with set_by dropped" 'fails "$MK" "4. \`set_by\` is \`\"/make-it\"\` and \`set_at\` is the date of this Design (YYYY-MM-DD)." ""'
  check "(control) fails when the step asks the user a question" 'add "$MK" "$STEP5" " Ask the user: \"Which expert should build this?\""'
  check "(control) fails when the step moves before the stack is chosen" \
    'd="$(copy)"; perl -0pi -e "my \$b; s/(\*\*Project specialist \(SILENT.*?\n)(?=\*\*Build the app-context)/\$b = \$1; q()/se; s/(\*\*For everything else)/\$b\$1/" "$d/$MK"; ! cmp -s "$MK" "$d/$MK" && ! bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails when the variant template line drops its rank" 'fails "$VT" ", rank: [security | data | reliability | AI | after AI, before the floor]" ""'
  JOIN32='s/\n3\. Each signal is written/ Each signal is written/'
  check "(control, H) fails: step 3 joined into step 2" 'd="$(copy)"; perl -0pi -e "$JOIN32" "$d/$MK"; ! cmp -s "$MK" "$d/$MK" && ! bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control, D9) fails: kept specialists get a new set_at" 'add "$MK" "$STEP5" " A kept record gets today'\''s \`set_at\`."'
  check "(control) fails: Build step g drops the specialist line" 'fails "$MK" " (carrying the specialist line from Design step 5 when Design wrote a new record over an older one)" ""'
  check "(control) the paper check fails when the reference renames the reliability specialist" 'fails "$REF" "→ **SRE**" "→ **Reliability engineer**"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
