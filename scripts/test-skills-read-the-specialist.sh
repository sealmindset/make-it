#!/usr/bin/env bash
# E11-S5: every skill that changes or judges code reads the project specialist record and adds its task specialist.
#
# WHAT IS PINNED (whole, D5: an added, removed or changed sentence fails until this test is updated too), compared
# unit by unit (a paragraph, a list item, a table row, a code line, with its indentation; whitespace folded inside):
#   - the specialist block of /debug-it, /argo-it, /try-it, /deadcode-it, /resolve-it and /threats-it (from
#     <expert_persona> to </expert_persona>), and of /nemo-it and /fix-it (from "**Adopt the specialist persona" to
#     the reference's import line).
#   - /resolve-it's investigator prompt sentence that hands its agent the record.
# PER SKILL: the task specialist is named in bold, the block reads the record, has the no-record sentence, and has no
#   re-inference wording ("Infer", "Auto-selected from `app-context.json`", "Signals may layer in"). /threats-it: a
#   fixed threat intelligence analyst that reads no project record. /resume-it (a builder): works as the project
#   specialist and adds none of its own (its block is pinned whole in test-resume-it-rechecks-specialist.sh).
# THE REFERENCE (pinned whole in test-project-specialist-rule.sh): rule 1 names every task specialist, the readers
#   and the skills that get none are listed; /debug-it's old role is gone from it, from debug-it.md and both docs.
# THE PAPER CHECK checks this test's own reading: for one record (security primary, SRE and the floor added) each
#   skill's lead and the checks that apply, taken from the pinned blocks. No real run of any skill happened.
# Usage: test-skills-read-the-specialist.sh [ROOT]. With no ROOT it checks this repo, then runs the controls below on
# edited copies (each with its expected result).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

C=.claude/commands
REF=.claude/make-it/references/expert-personas.md
OV=.claude/make-it/confluence-docs/00-make-it-framework-overview.md
D10=.claude/make-it/confluence-docs/10-debug-it.md
INV=.claude/make-it/resolve-it/investigator-prompt.md
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
# block SKILL: the skill's specialist block
block() {
  case "$1" in
    nemo-it|fix-it) section "$C/$1.md" "^[*][*]Adopt the specialist persona" "^@~/[.]claude/make-it/references/expert-personas[.]md$" ;;
    *) section "$C/$1.md" "^<expert_persona>$" "^</expert_persona>$"; echo "</expert_persona>" ;;
  esac
}
IFS= read -r -d '' WANT_debug_it <<'BLOCK' || true
<expert_persona>

Before investigating, adopt the specialist persona — do NOT work as a generalist. Its task specialist is the **Senior maintainer of that stack** — knows its idioms, failure modes and tests, and proves the root cause instead of adding a retry. Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.

@~/.claude/make-it/references/expert-personas.md
@~/.claude/make-it/references/operator-safety.md

</expert_persona>
BLOCK
IFS= read -r -d '' WANT_nemo_it <<'BLOCK' || true
**Adopt the specialist persona before scanning — do NOT scan as a generalist.** Its task specialist is the **Application security engineer** — attacker mindset, threat-model first, findings held to attestation-grade rigor. Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). So an app whose record holds customer, personal or health data gets a privacy-aware review. With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.
BLOCK
IFS= read -r -d '' WANT_fix_it <<'BLOCK' || true
**Adopt the specialist persona before fixing — do NOT fix as a generalist.** Its task specialist is the **Application security engineer** — fix the root cause with a compensating control, not a surface patch. Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). So an app whose record holds customer, personal or health data gets a privacy-aware review. With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.
BLOCK
IFS= read -r -d '' WANT_argo_it <<'BLOCK' || true
<expert_persona>

Before generating manifests or pipelines, adopt the specialist persona — do NOT work as a generalist. Its task specialist is the **Platform / Kubernetes engineer** — blast radius, SLOs, rollback and failure modes, not just "make it deploy". Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.

@~/.claude/make-it/references/expert-personas.md

</expert_persona>
BLOCK
IFS= read -r -d '' WANT_try_it <<'BLOCK' || true
<expert_persona>

Before testing, adopt the specialist persona — do NOT test as a generalist. Its task specialist is the **QA / test engineer** — tests what a person would really do, edge cases and permission boundaries included, and reports what it saw. Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.

@~/.claude/make-it/references/expert-personas.md

</expert_persona>
BLOCK
IFS= read -r -d '' WANT_deadcode_it <<'BLOCK' || true
<expert_persona>

Before grading anything as dead, adopt the specialist persona — do NOT work as a generalist. Its task specialist is the **Senior maintainer of that stack** — knows what its framework loads by convention, by name or at run time, and keeps anything it cannot prove unused. Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.

@~/.claude/make-it/references/expert-personas.md

</expert_persona>
BLOCK
IFS= read -r -d '' WANT_resolve_it <<'BLOCK' || true
<expert_persona>

Its task specialist is the **SRE / incident commander** — outcome first, evidence over theory, one change at a time, nothing hidden. Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). Every agent it launches on app code is handed the same project specialist plus the specialist its own task calls for. With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.

@~/.claude/make-it/references/expert-personas.md

</expert_persona>
BLOCK
IFS= read -r -d '' WANT_threats_it <<'BLOCK' || true
<expert_persona>

Work as a **threat intelligence analyst** — verify every claim at its source, map each attack to
ATT&CK, and report no more than was measured. This is a fixed specialist: /threats-it is standalone,
not tied to an app, and reads no project specialist record.

</expert_persona>
BLOCK
WANT_INV='Work as the specialist this investigation calls for, held to the checks and output standard of every specialist recorded in `expert_persona` in the app'"'"'s `app-context.json`; with no `expert_persona` set, or an older value the reference does not count (its "Reading an older value"), work as that specialist alone.'
READERS="debug-it nemo-it fix-it argo-it try-it deadcode-it resolve-it"
for s in $READERS threats-it; do
  v="WANT_${s//-/_}"
  check "$s's specialist block is exactly the pinned text" 'pin "$s block" "$(block "$s")" "${!v}"'
done
for s in nemo-it fix-it; do check "$s still imports the reference right after its block" 'gq -xF "@~/.claude/make-it/references/expert-personas.md" "$C/$s.md"'; done
task() { case "$1" in debug-it|deadcode-it) echo "Senior maintainer of that stack" ;; nemo-it|fix-it) echo "Application security engineer" ;;
  argo-it) echo "Platform / Kubernetes engineer" ;; try-it) echo "QA / test engineer" ;; resolve-it) echo "SRE / incident commander" ;; esac; }
for s in $READERS; do
  check "$s: names its task specialist ($(task "$s")), reads the record, has the no-record sentence, no re-inference" \
    'b="$(block "$s" | flat)"; printf "%s" "$b" | gq -F "Its task specialist is the **$(task "$s")**" &&
     printf "%s" "$b" | gq -F "Read the project specialist: the specialists the \`expert_persona\` field in the app'"'"'s \`app-context.json\` names" &&
     printf "%s" "$b" | gq -F "a run outside an app, work as the task specialist alone and say nothing." &&
     ! printf "%s" "$b" | gq -iE "\binfer\b|auto-selected from \`?app-context|signals may layer in"'
done
check "/threats-it: a fixed threat intelligence analyst that reads no project record" \
  'b="$(block threats-it | flat)"; printf "%s" "$b" | gq -F "**threat intelligence analyst**" && printf "%s" "$b" | gq -F "reads no project specialist record" && ! printf "%s" "$b" | gq -F "expert_persona\`"'
check "/resume-it is a builder: works as the project specialist and adds no task specialist of its own" \
  'b="$(section "$C/resume-it.md" "^[*][*]Project specialist re-check" "^[*][*]A[.] Continue building" | flat)"; printf "%s" "$b" | gq -F "While it builds, /resume-it works as the project specialist, the way /make-it does" && printf "%s" "$b" | gq -F "with no task specialist of its own" && ! printf "%s" "$b" | gq -F "Its task specialist is"'
check "/resolve-it's investigator prompt hands its agent the record" 'flat < "$INV" | gq -F "$WANT_INV"'
check "the reference's rule 1 names every task specialist" \
  'r="$(flat < "$REF")"; for e in "\`debug-it\` → senior maintainer of that stack" "\`argo-it\` → Platform / Kubernetes engineer" "\`try-it\` → QA / test engineer" "\`deadcode-it\` → senior maintainer of that stack" "\`resolve-it\` → SRE / incident commander"; do printf "%s" "$r" | gq -F "$e" || { echo "  rule 1 lacks: $e"; exit 1; }; done'
check "the reference lists the readers and the skills that get none (/demo-it with its reason; /threats-it fixed)" \
  'r="$(flat < "$REF")"; printf "%s" "$r" | gq -F "The skills that read it and add a task specialist are \`/debug-it\`, \`/nemo-it\`, \`/fix-it\`, \`/argo-it\`, \`/try-it\`, \`/deadcode-it\` and \`/resolve-it\`" && printf "%s" "$r" | gq -F "\`/demo-it\`, \`/wrap-it\`, \`/clear-it\`, \`/git-it\` and \`/backlog-it\` get no specialist at all: \`/demo-it\` manages demo accounts and their sample data for a product, and does not change or judge an app'"'"'s code."'
check "/debug-it's old role is gone from the reference, debug-it.md and both docs" \
  '! cat "$REF" "$C/debug-it.md" "$D10" "$OV" | flat | gq -iE "SRE / performance engineer|reliability & performance engineer"'
check "(ban outside the pinned blocks) no per-skill doc page says the specialist is set from the app's details" \
  '! cat .claude/make-it/confluence-docs/0[7-9]-*.md "$D10" | flat | gq -F "Set behind the scenes from your app'"'"'s details"'

paper() {
  python3 -I - "$@" <<'PY'
import re, sys
# one record: security primary, SRE and the floor added
record = ["Application security engineer", "SRE", "Senior full-stack engineer of FastAPI + Next.js"]
def fail(m): print("  paper check: " + m); sys.exit(1)
for arg in sys.argv[1:]:
    name, text = arg.split("=", 1)
    t = " ".join(text.split())
    if name == "resume-it":
        if "the primary leading, with no task specialist of its own" not in t: fail("resume-it does not let the primary lead")
        lead, checks = record[0], record
    elif name == "threats-it":
        if "reads no project specialist record" not in t: fail("threats-it reads a record")
        lead, checks = "threat intelligence analyst", []
    else:
        m = re.search(r"Its task specialist is the \*\*(.+?)\*\*", t)
        if not m or "held to the checks and output standard of every specialist recorded in `expert_persona`" not in t: fail(name + ": no task lead held to every recorded specialist")
        lead, checks = m.group(1), record
    print(f"  {name}: leads as {lead}; checks of {', '.join(checks) if checks else 'no project record'}")
PY
}
check "paper check (the test's own reading of the pinned blocks): who leads and whose checks apply, per skill" \
  'args=(); for s in $READERS threats-it; do args+=("$s=$(block "$s")"); done; args+=("resume-it=$(section "$C/resume-it.md" "^[*][*]Project specialist re-check" "^[*][*]A[.] Continue building")"); paper "${args[@]}"'

if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$C" "$REF" "$OV" "$D10" .claude/make-it/confluence-docs "$INV" | tar -xf - -C "$d"; echo "$d"; }
  edit() { local d; d="$(copy)"
           O="$2" N="$3" perl -0pi -e '(my $n = $ENV{N}) =~ s/\\n/\n/g; my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$n/' "$d/$1"
           if cmp -s "$1" "$d/$1"; then echo "  the edit did not apply"; return 2; fi; echo "$d"; }
  fails()  { local d; d="$(edit "$@")" || return 1; ! bash "$SELF" "$d" >/dev/null 2>&1; }
  add() { fails "$1" "$2" "$2$3"; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  for s in $READERS; do
    check "(control) $s: block reverted to inferring fails" 'fails "$C/$s.md" "Never work a project specialist out from signals, and never change the specialist record." "Infer it from \`app-context.json\` signals + this skill."'
  done
  check "(control) a reading skill made to write the record fails (argo-it)" 'add "$C/argo-it.md" "say nothing." " Then save your role as the primary in the record."'
  check "(control) the no-record sentence dropped fails (try-it)" 'fails "$C/try-it.md" "With no \`expert_persona\` set," "With"'
  check "(control) /debug-it back to SRE in the reference fails" 'fails "$REF" "\`debug-it\` → senior maintainer of that stack;" "\`debug-it\` → SRE;"'
  check "(control) /debug-it back to SRE in its block fails" 'fails "$C/debug-it.md" "**Senior maintainer of that stack**" "**SRE / performance engineer**"'
  check "(control) /debug-it back to SRE in its doc page fails" 'fails "$D10" "**senior maintainer of your app'"'"'s stack**" "**reliability & performance engineer**"'
  check "(control) /debug-it back to SRE in the overview fails" 'fails "$OV" "senior maintainer of your app'"'"'s stack |" "reliability & performance engineer |"'
  check "(control) /threats-it given a project read fails" 'fails "$C/threats-it.md" "and reads no project specialist record." "and reads the \`expert_persona\` record of the app."'
  check "(control) /resume-it given a task specialist of its own fails" 'fails "$C/resume-it.md" "with no task specialist of its own (the" "with QA / test engineer as its own task specialist (the"'
  for s in $READERS threats-it; do
    check "(control) a sentence added inside $s's block fails" 'd="$(copy)"; perl -0pi -e "s/(<\/expert_persona>|\n\n\@~\/\.claude\/make-it\/references\/expert-personas\.md\n)/ This keeps things tidy.\$1/" "$d/$C/$s.md"; ! cmp -s "$C/$s.md" "$d/$C/$s.md" && ! bash "$SELF" "$d" >/dev/null 2>&1'
  done
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
