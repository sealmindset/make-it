#!/usr/bin/env bash
# E11-S6: /subagent-it and /dispatch-it adopt no specialist themselves; every agent they launch on app code is handed
# the project specialist record plus the specialist its task calls for, through a named slot in its prompt.
#
# WHAT IS PINNED (whole, D5: an added, removed or changed sentence fails until this test is updated too), compared
# unit by unit (a paragraph, a list item, a table row, a code line, with its indentation; whitespace folded inside):
#   - the <expert_persona> block of subagent-it.md and of dispatch-it.md.
#   - each SDD prompt template's "## Your specialist" section (implementer, test-writer: work as; task reviewer,
#     adversarial reviewer: review against), and the "Specialist" item of parallel-dispatch.md's agent prompt
#     structure.
# NOT PINNED: the rest of those files. The final review is /code-review (no template of its own); the subagent-it
#   block says it reviews against the recorded specialists' checks too.
# THE PAPER CHECK checks this test's own reading of the pinned text: for the S5 record (security primary, SRE and
#   the floor added), what an implementer and a reviewer launched by each coordinator are handed. No real run of
#   any skill happened.
# Usage: test-coordinators-hand-over-the-specialist.sh [ROOT]. With no ROOT it checks this repo, then runs the
# controls below on edited copies (each with its expected result).
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
SDD=.claude/make-it/sdd
PD=.claude/make-it/references/parallel-dispatch.md
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
block() { section "$C/$1.md" "^<expert_persona>$" "^</expert_persona>$"; echo "</expert_persona>"; }
slot()  { section "$1" "^## Your specialist$" "^## "; }
IFS= read -r -d '' WANT_subagent_it <<'BLOCK' || true
<expert_persona>

/subagent-it adopts no specialist itself. Every subagent it launches on app code is handed two
things in its brief: the project specialist, the specialists the `expert_persona` field in the
app's `app-context.json` names (the template's `[PROJECT_SPECIALISTS]` slot), and the task
specialist that task's domain calls for (`[TASK_SPECIALIST]`). The implementer and the test-writer
work as the task specialist, held to the checks and output standard of every specialist recorded
in `expert_persona`; the task reviewer, the adversarial reviewer and the final `/code-review`
review against those checks too. With no `expert_persona` set, an older value the reference does not count (its "Reading an older value"), or a run outside an
app, the slot is left empty and each agent works as its task specialist alone and says nothing. Choose the task
specialist per task from the task's text; never work a project specialist out from signals, and
never change the specialist record. No user prompt. See the reference below.

@~/.claude/make-it/references/expert-personas.md

</expert_persona>
BLOCK
IFS= read -r -d '' WANT_dispatch_it <<'BLOCK' || true
<expert_persona>

/dispatch-it adopts no specialist itself. Every agent it launches on app code is handed, in its
prompt, the project specialist (the specialists the `expert_persona` field in the app's
`app-context.json` names) and the task specialist its own problem calls for: a security problem →
application security engineer; a slow or flaky bug → senior maintainer of that stack; a data problem →
data engineer. The agent works as its task specialist, held to the checks and output standard of
every specialist recorded in `expert_persona`. With no `expert_persona` set, an older value the reference does not count (its "Reading an older value"), or a run outside an
app, the agent works as its task specialist alone and says nothing. Choose the task specialist per
agent from its problem; never work a project specialist out from signals, and never change the
specialist record. No user prompt. See the reference below.

@~/.claude/make-it/references/expert-personas.md

</expert_persona>
BLOCK
IFS= read -r -d '' WANT_work <<'BLOCK' || true
## Your specialist
Task specialist: [TASK_SPECIALIST]. Project specialist: [PROJECT_SPECIALISTS -- the specialists the app's `expert_persona` field names, primary first; leave empty when there are none or the field holds an older value the reference does not count (its "Reading an older value")].
Work as the task specialist, held to the checks and output standard of every specialist listed as the project specialist (`expert-personas.md`, "Each project specialist's checks"). If none is listed, work as the task specialist alone and say nothing about it.
BLOCK
IFS= read -r -d '' WANT_review <<'BLOCK' || true
## Your specialist
Task specialist: [TASK_SPECIALIST]. Project specialist: [PROJECT_SPECIALISTS -- the specialists the app's `expert_persona` field names, primary first; leave empty when there are none or the field holds an older value the reference does not count (its "Reading an older value")].
Review as the task specialist, against the checks and output standard of every specialist listed as the project specialist as well as your own (`expert-personas.md`, "Each project specialist's checks"). If none is listed, review as the task specialist alone and say nothing about it.
BLOCK
IFS= read -r -d '' WANT_item <<'BLOCK' || true
4. **Specialist** — name the agent's task specialist and, under "Project specialist:", the
   specialists the app's `expert_persona` field names (leave it empty when there are none or the field holds an older value the reference does not
   count). The
   agent works as its task specialist, held to the checks and output standard of every specialist
   listed; with none listed, as its task specialist alone, saying nothing about it.
BLOCK
for s in subagent-it dispatch-it; do
  v="WANT_${s//-/_}"
  check "$s's <expert_persona> block is exactly the pinned text" 'pin "$s block" "$(block "$s")" "${!v}"'
done
for t in implementer test-writer; do check "$t template: its specialist slot is exactly the pinned text" 'pin "$t slot" "$(slot "$SDD/$t-prompt.md")" "$WANT_work"'; done
for t in task-reviewer adversarial-reviewer; do check "$t template: its specialist slot is exactly the pinned text" 'pin "$t slot" "$(slot "$SDD/$t-prompt.md")" "$WANT_review"'; done
check "parallel-dispatch.md's agent prompt structure has the Specialist item, exactly" 'pin "dispatch item" "$(section "$PD" "^4[.] [*][*]Specialist[*][*]" "^$")" "$WANT_item"'
for s in subagent-it dispatch-it; do
  check "$s: adopts no specialist, hands over the record and a task specialist, no re-inference, no write" \
    'b="$(block "$s" | flat)"; printf "%s" "$b" | gq -F "/$s adopts no specialist itself." && printf "%s" "$b" | gq -F "never work a project specialist out from signals, and never change the specialist record." && ! printf "%s" "$b" | gq -iE "\binfer\b|app-context.json. signals"'
done

paper() {
  python3 -I - "$@" <<'PY'
import re, sys
record = "Application security engineer, SRE, Senior full-stack engineer of FastAPI + Next.js"
def fail(m): print("  paper check: " + m); sys.exit(1)
texts = dict(a.split("=", 1) for a in sys.argv[1:])
t = {k: " ".join(v.split()) for k, v in texts.items()}
for coord, impl, rev in (("subagent-it", "work", "review"), ("dispatch-it", "item", "item")):
    if "adopts no specialist itself" not in t[coord]: fail(coord + " adopts a specialist")
    for role, key in (("implementer", impl), ("reviewer", rev)):
        s = t[key]
        if "[TASK_SPECIALIST]" not in s and "task specialist" not in s: fail(f"{coord} {role}: no task specialist")
        if "every specialist listed" not in s: fail(f"{coord} {role}: not held to every recorded specialist")
        verb = "reviews against" if "Review as the task specialist" in s else "works as its task specialist, held to"
        print(f"  {coord} launches a {role}: handed its task specialist and [{record}]; it {verb} the checks of all three")
PY
}
check "paper check (the test's own reading of the pinned text): what each coordinator's implementer and reviewer are handed" \
  'paper "subagent-it=$(block subagent-it)" "dispatch-it=$(block dispatch-it)" "work=$(slot "$SDD/implementer-prompt.md")" "review=$(slot "$SDD/task-reviewer-prompt.md")" "item=$(section "$PD" "^4[.] [*][*]Specialist[*][*]" "^$")"'

if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$C" "$SDD" "$PD" | tar -xf - -C "$d"; echo "$d"; }
  edit() { local d; d="$(copy)"
           O="$2" N="$3" perl -0pi -e '(my $n = $ENV{N}) =~ s/\\n/\n/g; my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$n/' "$d/$1"
           if cmp -s "$1" "$d/$1"; then echo "  the edit did not apply"; return 2; fi; echo "$d"; }
  fails()  { local d; d="$(edit "$@")" || return 1; ! bash "$SELF" "$d" >/dev/null 2>&1; }
  add() { fails "$1" "$2" "$2$3"; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  for s in subagent-it dispatch-it; do
    check "(control) $s given a specialist of its own fails" 'fails "$C/$s.md" "/$s adopts no specialist itself." "/$s works as a software architect itself."'
    check "(control) $s inferring a project specialist from signals fails" 'fails "$C/$s.md" "never work a project specialist out from signals" "infer the project specialist from the app-context.json signals"'
    check "(control) $s made to write the record fails" 'add "$C/$s.md" "No user prompt." " Then save the task specialist into the record."'
    check "(control) a sentence added inside $s's block fails" 'add "$C/$s.md" "No user prompt." " This keeps things tidy."'
  done
  check "(control) a template with the slot removed fails (implementer)" 'd="$(copy)"; perl -0pi -e "s/## Your specialist\n.*?\n(?=## )//s" "$d/$SDD/implementer-prompt.md"; ! cmp -s "$SDD/implementer-prompt.md" "$d/$SDD/implementer-prompt.md" && ! bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) the empty-record line dropped fails (task reviewer)" 'fails "$SDD/task-reviewer-prompt.md" " If none is listed, review as the task specialist alone and say nothing about it." ""'
  check "(control) the dispatch Specialist item dropped fails" 'd="$(copy)"; perl -0pi -e "s/\n4\. \*\*Specialist\*\*.*?\n\n/\n\n/s" "$d/$PD"; ! cmp -s "$PD" "$d/$PD" && ! bash "$SELF" "$d" >/dev/null 2>&1'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
