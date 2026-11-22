#!/usr/bin/env bash
# E11-S2: /make-it records the project's specialist at Design, in the record's shape, for every project.
# Fix rounds 1 and 2 (owner decisions D1, D5, D6, D7; review findings F6, F8, N1, N4, N5, N6, N9) are folded in.
#
# WHAT IS PINNED (D5: whole blocks, so an added, removed or changed sentence fails until this test is updated too):
#   - .claude/commands/make-it.md: the Design step block, from "**Project specialist (SILENT" up to
#     "**Build the app-context internally."; and the two paragraphs that brief /make-it's own sub-agents (Build
#     Phase B's Subagent-Driven Development paragraph, and the fix cycle's parallel-dispatch paragraph). Compared with
#     the text below after every run of whitespace is folded to one space, so rewrapping a line is not a change.
#   - .claude/make-it/variants/_template.md: the "Project specialist signals" line, whole.
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
# pin LABEL ACTUAL WANT: the two texts are equal once whitespace is folded; on a difference, show the first one
pin() {
  local a w; a="$(printf '%s' "$2" | flat)"; w="$(printf '%s' "$3" | flat)"
  [ -n "$w" ] || { echo "  $1: the expected block is empty"; return 1; }
  [ "$a" = "$w" ] && return 0
  python3 -I -c 'import sys
a, w = sys.argv[1], sys.argv[2]
i = next((k for k in range(min(len(a), len(w))) if a[k] != w[k]), min(len(a), len(w)))
print(f"  {sys.argv[3]} differs at character {i}:\n    file: ...{a[max(0, i - 60):i + 100]!r}\n    pin:  ...{w[max(0, i - 60):i + 100]!r}")' "$a" "$w" "$1"
  return 1
}

# 1. the pinned blocks
read -r -d '' WANT_STEP <<'BLOCK' || true
**Project specialist (SILENT -- no user question):**

Reference `references/expert-personas.md`. Every project records its project specialist in
`expert_persona`, a low-risk one included: the primary specialist, the added ones, the signals
behind each, `set_by` and `set_at`. Work it out from the app-context answers once the stack is
chosen:

1. The floor is the reference's floor row for the `project_type`, filled in from `stack` as the
   reference says. Its signal is `project_type: <value> (the floor)`.
2. Check the signals of the reference's rule 2, in its order, and build the record by its "The
   order decides the primary" paragraph. In app-context they are carried by: security --
   `compliance`, `purpose`, `features`; data -- `multi_tenancy.needed` and the answers; reliability
   -- `users.internal_or_external`, `users.estimated_count`, and an uptime promise the user named;
   AI -- `ai_features.usage_level` and `ai_features.who_edits_prompts`; a variant -- the
   `variant_config` fields its definition file names.
3. Each signal is written `<field>: <value>`, and one the user did not state (a guess or a smart
   default, such as a rough user count) is marked `"unconfirmed": true`.
4. `set_by` is `"/make-it"` and `set_at` is the date of this Design (YYYY-MM-DD).
5. If `app-context.json` already holds a record (a returning run), compare it with the new one as
   the reference's "Same record or a different one" says: the same specialists keep it as it is;
   different specialists write the new one. When the new one is written over a record, the one plain
   line (e.g. "Your app now gets a security specialist because it takes card payments.") goes in
   the plain-English summary's sentence on what departs from the standard setup, and into
   `CHANGELOG.md`: now if the file exists, otherwise in the initial entry Build step g writes. A
   value the reference reads as no record (its "Reading an older value") is not a record: write the
   new one and say nothing.

The record is never a plain text value and never a generalist. /make-it builds and reviews in the
role of every specialist in the record, and hands the record to every sub-agent it briefs. This is
a build-quality lever, not a staffing recommendation. Apart from the line in step 5, nothing here
is shown to the user, and nothing is asked of them.
BLOCK
read -r -d '' WANT_SDD <<'BLOCK' || true
When the app-specific work is sizable (several independent domains/features), execute it via
Subagent-Driven Development (`/subagent-it`, see `subagent-driven-development.md`): treat these
steps as the plan, dispatch a fresh implementer subagent per step + per-step review + a final
whole-branch review, keeping your own context for coordination. Stay sequential on shared files.
Brief each implementer and reviewer subagent with the project specialist recorded in
`expert_persona` at Design plus the specialist its step needs (a data engineer for the migration,
say); it works as both, instead of inferring a specialist of its own.
BLOCK
read -r -d '' WANT_FIX <<'BLOCK' || true
If several failures are INDEPENDENT (different files/subsystems/root causes), fix them in
parallel instead of sequentially: dispatch one agent per domain (`/dispatch-it`, see
`parallel-dispatch.md`), isolate writers in their own worktrees, then re-run the FULL suite
once and integrate. Keep related failures together (find the shared cause first). Brief each
agent with the project specialist recorded in `expert_persona` plus the specialist its failure
needs; it works as both, instead of inferring a specialist of its own.
BLOCK
VS='- **Project specialist signals (optional):** a `variant_config` value that adds a specialist, written as `` `variant_config.[field]` is [value] -> [specialist] ``, with that specialist'"'"'s checks and output standard. Its rank is the reference'"'"'s rule 2, item 5: after the AI signal and before the floor, unless it is really a security, data, reliability or AI signal, which takes that signal'"'"'s rank. /make-it, /retrofit-it and /resume-it apply it like any other signal.'
check "make-it.md's Design step block is exactly the pinned text" \
  'pin "Design step" "$(section "$MK" "^[*][*]Project specialist [(]SILENT" "^[*][*]Build the app-context internally")" "$WANT_STEP"'
check "make-it.md's Subagent-Driven Development brief paragraph is exactly the pinned text" \
  'pin "Phase B brief" "$(section "$MK" "^When the app-specific work is sizable" "^$")" "$WANT_SDD"'
check "make-it.md's parallel fix brief paragraph is exactly the pinned text" \
  'pin "fix-cycle brief" "$(section "$MK" "^If several failures are INDEPENDENT" "^$")" "$WANT_FIX"'
check "the variant template's \"Project specialist signals\" line is exactly the pinned text, once" '[ "$(grep -cxF -- "$VS" "$VT")" = 1 ]'
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
def specialists(r): return [r["primary"]["specialist"]] + [a["specialist"] for a in r["added"]]
def design(existing, ctx, guessed, today):  # step 5 and the reference's "Same record or a different one"
    new = derive(ctx, guessed, today)
    if not reads_as_record(existing): return new, False
    if specialists(as_record(existing)) != specialists(new): return new, True
    kept = copy.deepcopy(existing)
    if isinstance(kept, dict):  # the one edit: an unconfirmed signal the new evidence settles
        now = {g["signal"]: g["unconfirmed"] for s in [new["primary"]] + new["added"] for g in s["signals"]}
        for s in [kept["primary"]] + kept["added"]:
            s["signals"] = [dict(g, unconfirmed=False) if g["unconfirmed"] and now.get(g["signal"]) is False else g
                            for g in s["signals"] if not (g["unconfirmed"] and g["signal"] not in now)]
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
older = copy.deepcopy(PAY[2]); older["set_at"] = "2026-10-01"
reworded = copy.deepcopy(older); reworded["set_by"] = "/retrofit-it"
reworded["primary"]["signals"] = [{"signal": "code: Stripe SDK in requirements.txt", "unconfirmed": False}]
confirmed = copy.deepcopy(older); confirmed["added"][0]["signals"][1]["unconfirmed"] = False
CASES = [  # (name, existing, guessed now, want record, want a line said)
  ("the same record, older date", older, ["users.estimated_count"], older, False),
  ("the same specialists, signals worded by /retrofit-it", reworded, ["users.estimated_count"], reworded, False),
  ("the same specialists, the guessed user count now stated", older, [], confirmed, False),
  ("different specialists (the low-risk record)", LOW[2], ["users.estimated_count"], PAY[2], True),
  ("an empty string", "", ["users.estimated_count"], PAY[2], False),
  ("the template's empty record", {"primary": {"specialist": "", "signals": []}, "added": [], "set_by": "", "set_at": ""}, ["users.estimated_count"], PAY[2], False),
  ('the text "generalist"', "generalist", ["users.estimated_count"], PAY[2], False),
  ("an older text value naming a specialist", "Senior full-stack engineer", ["users.estimated_count"], PAY[2], True)]
for name, existing, guessed, want, said in CASES:
    rec, line = design(existing, PAY[0], guessed, "2026-11-21")
    if rec != want or line != said: fail(f"returning run, {name}: got {json.dumps(rec)} said={line}; want said={said}")
    print(f"  returning run, {name}: {'one line said' if said else 'nothing said'}")
PY
}
check "paper check (the test's own derivation; no build runs): three records and eight returning-run results" 'paper'

# 3. controls (this repo only), each with its expected result
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$MK" "$REF" "$VT" "$D1" | tar -xf - -C "$d"; echo "$d"; }
  edit() { local d; d="$(copy)"
           O="$2" N="$3" perl -0pi -e '(my $n = $ENV{N}) =~ s/\\n/\n/g; my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$n/' "$d/$1"
           if cmp -s "$1" "$d/$1"; then echo "  the edit did not apply"; return 2; fi; echo "$d"; }
  fails()  { local d; d="$(edit "$@")" || return 1; ! bash "$SELF" "$d" >/dev/null 2>&1; }
  passes() { local d; d="$(edit "$@")" || return 1; bash "$SELF" "$d" >/dev/null 2>&1 || { bash "$SELF" "$d" | grep -A3 "^FAIL" | head -8 | sed "s|^|    inner: |"; false; }; }
  add() { fails "$1" "$2" "$2$3"; }
  STEP5='A value the reference reads as no record (its "Reading an older value") is not a record: write the new one and say nothing.'
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
  check "(control N1) fails: a variant signal marked security goes first, added to step 2" 'add "$MK" "the \`variant_config\` fields its definition file names." " A variant signal marked \"security\" goes first instead."'
  check "(control N4) fails: \"A reviewer that disagrees updates the record.\" in the Phase B brief" 'add "$MK" "Stay sequential on shared files." " A reviewer that disagrees updates the record."'
  check "(control) fails when the step writes a plain string again" 'fails "$MK" "The record is never a plain text value and never a generalist." "Record the specialist as a plain text value."'
  check "(control) fails with set_by dropped" 'fails "$MK" "4. \`set_by\` is \`\"/make-it\"\` and \`set_at\` is the date of this Design (YYYY-MM-DD)." ""'
  check "(control) fails when the step asks the user a question" 'add "$MK" "$STEP5" " Ask the user: \"Which expert should build this?\""'
  check "(control) fails when the step moves before the stack is chosen" \
    'd="$(copy)"; perl -0pi -e "my \$b; s/(\*\*Project specialist \(SILENT.*?\n)(?=\*\*Build the app-context)/\$b = \$1; q()/se; s/(\*\*For everything else)/\$b\$1/" "$d/$MK"; ! cmp -s "$MK" "$d/$MK" && ! bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails when the variant template line drops its rank" 'fails "$VT" "Its rank is the reference'\''s rule 2, item 5: after the AI signal and before the floor, unless it is really a security, data, reliability or AI signal, which takes that signal'\''s rank. " ""'
  check "(control) the paper check fails when the reference renames the reliability specialist" 'fails "$REF" "→ **SRE**" "→ **Reliability engineer**"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
