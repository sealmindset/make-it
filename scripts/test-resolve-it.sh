#!/usr/bin/env bash
# /resolve-it: a person's report → the outcome observed on the live system → prevention → four records.
# Contract these checks pin (behaviour, not phrasing, where a regex can tell the difference):
#   - The skill loads resolve-it.md, approval-block.md and operator-safety.md; it calls /debug-it for
#     every root cause and reuses the SDD adversarial reviewer; its own agents' templates exist.
#   - Never, at any autonomy level: write while investigating, send to a person outside the team,
#     print a secret, leave a bypassed safeguard undisclosed or a manual unblock without a card,
#     call it done before the outcome is observed live.
#   - Owner's calls (2026-11-11): three autonomy levels (propose / project / end-to-end), default
#     `project`, and `end-to-end` where the project's doctrine says nothing about shipping; drafts
#     only to the affected person; four records (card, incident report, memory+doctrine, patterns);
#     the pattern library is project-agnostic and the learned half is user-level.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
none() { local re="$1"; shift; [ "$(cat "$@" | grep -ciE -- "$re")" = 0 ]; }
# Phrase checks read the file as one line, so a sentence that wraps still counts.
has() { tr '\n' ' ' < "$2" | tr -s ' ' | grep -qF -- "$1"; }

CMD=.claude/commands/resolve-it.md
REF=.claude/make-it/references/resolve-it.md
INV=.claude/make-it/resolve-it/investigator-prompt.md
WRI=.claude/make-it/resolve-it/writer-prompt.md
PAT=.claude/make-it/resolve-it/patterns
REV=.claude/make-it/sdd/adversarial-reviewer-prompt.md

# --- wiring
check "the skill loads its reference"                gq -F "@~/.claude/make-it/references/resolve-it.md" "$CMD"
check "the skill loads the ask and safety rules"     bash -c "grep -qF '@~/.claude/make-it/references/approval-block.md' '$CMD' && grep -qF '@~/.claude/make-it/references/operator-safety.md' '$CMD'"
check "every root cause goes through /debug-it"      gq -E "run \`/debug-it\`|/debug-it\` for each root cause" "$CMD"
check "the reviewer is the shared SDD template"      bash -c "grep -qF 'sdd/adversarial-reviewer-prompt.md' '$CMD' && test -f '$REV'"
check "its agent templates exist and are used"       bash -c "test -f '$INV' && test -f '$WRI' && grep -qF 'resolve-it/investigator-prompt.md' '$CMD' && grep -qF 'resolve-it/writer-prompt.md' '$CMD'"

# --- autonomy (owner, 2026-11-11)
check "three autonomy levels are defined"            bash -c "grep -qE '^\| \*\*propose\*\* \|' '$REF' && grep -qE '^\| \*\*project\*\* \|' '$REF' && grep -qE '^\| \*\*end-to-end\*\* \|' '$REF'"
check "default is project, end-to-end without rules" bash -c "grep -qF '**Default:** \`project\`' '$REF' && grep -qE 'says nothing about shipping runs .end-to-end.' '$REF'"
check "end-to-end removes stops, never gates"        gq -F 'removes the stops, never the gates' "$REF"

# --- rails, at every level
check "investigation never writes (ref)"             gq -F 'Investigation never writes.' "$REF"
check "investigation never writes (investigator)"    bash -c "grep -qF 'READ-ONLY, no exceptions' '$INV' && grep -qE 'No retries, re-runs, re-sends, restarts, deploys' '$INV'"
check "a read-only helper that can write is a finding" bash -c "grep -qF 'a \"read-only\" helper that can still write is a' '$REF' && grep -qF 'report the' '$INV'"
check "nothing is sent to the affected person"       bash -c "grep -qF 'No message reaches a person outside the team.' '$REF' && grep -qF 'Nothing you write is sent by you' '$WRI' && grep -qF 'Never send it.' '$CMD'"
check "no secret is printed"                         bash -c "grep -qF 'No secret is printed, logged or stored' '$REF' && grep -qF 'Never print a secret' '$INV'"
check "bypassed safeguards are disclosed with undo"  gq -F 'Disclose every safeguard bypassed or weakened' "$REF"
check "a manual unblock becomes a card"              gq -F 'A manual unblock is a bug report.' "$REF"
check "no rail is relaxed by a level"                gq -F '## 3. Safety rails (every level, no exceptions)' "$REF"

# --- the outcome, and the stacked-cause loop
check "done means the outcome observed live"         bash -c "grep -qF 'observed true on the live system' '$REF' && grep -qF 'Call it done before the outcome is observed on the live system.' '$CMD'"
check "a failed live check loops back to evidence"   gq -E 'Not true yet.*Return to Phase 2|back to Phase 2' "$REF"
check "counts are reconciled before done"            gq -F 'count what came back against what was promised' "$REF"
check "an empty reading is unknown, not done"        has 'an empty or failed reading is "unknown", never "finished"' "$REF"
check "variations come before the fix"               has '**Phase 6 -- Variations, then the fix.** Before writing code, list the **variations**' "$REF"
check "the variations table has its columns"         has 'Columns: **Variation** (seen, or plausible from the evidence) | **Handling** (what the system now does) | **Proof**' "$REF"
check "owner rules are quoted verbatim"              gq -F 'quoted verbatim into the project' "$REF"
check "never a silent drop"                          has 'never a silent drop' "$REF"

# --- dry-run fixes (blind run on the origin incident, 2026-11-11)
check "walk forward from the break to the outcome"   bash -c "grep -qF 'walk forward' '$REF' && grep -qF 'walk forward' '$INV'"
check "a signal is a candidate until confirmed"      has 'Signals are symptoms, not shapes' "$REF"
check "prior fixes go to the investigator"           has 'list every card and commit since the report' "$REF"
check "deleted evidence is looked for"               has 'a log id with no row is **deleted evidence**' "$INV"
check "no read-only path: proceed, disclose, card"   has 'never stop the investigation for it' "$REF"
check "existing alerts must reach a person"          has 'check that the alerts that already exist reach a person' "$REF"
check "no past answer is loaded at run time"         bash -c "! grep -qiE 'origin \\(2026|five stacked causes' '$REF' '$CMD' '$INV' '$WRI'"

# --- records (owner, 2026-11-11: all four)
check "four records are defined"                     bash -c "for r in Card 'Incident report' 'Memory and doctrine' 'Pattern library'; do grep -qE \"^\| \*\*\$r\*\* \|\" '$REF' || exit 1; done"
check "learned patterns are user-level, kept"        bash -c "grep -qF '~/.claude/resolve-it/patterns/' '$REF' && grep -qF 'never overwritten by an install' '$REF'"
check "the incident report has a fixed format"       gq -F 'docs/incidents/<date>-<slug>.md' "$REF"

# --- the pattern library is project-agnostic and well-formed
pattern_ok() { local f="$1" n; n="$(basename "$f" .md)"; grep -qE "^name: $n$" "$f" && grep -qE '^signals: \[' "$f" && for s in '## Shape' '## How to confirm' '## Fix' '## Prevent'; do grep -qF "$s" "$f" || return 1; done; }
for f in "$PAT"/*.md; do [ "$(basename "$f")" = README.md ] && continue; check "pattern well-formed: $(basename "$f")" pattern_ok "$f"; done
check "at least 5 seed patterns ship"                bash -c "[ \$(ls '$PAT'/*.md | grep -vc README) -ge 5 ]"
check "no project, firm or client names anywhere"    none 'docai|vanmeveren|\bvlf\b|carter|hennepin|keller|london ?defense|brian|lawfirm\.|lawyer\.vlf|26a10733|27-cr-' "$CMD" "$REF" "$INV" "$WRI" "$PAT"/*.md

echo
if [ "$fail" = 0 ]; then echo "resolve-it contract: all checks passed"; else echo "resolve-it contract: FAILED"; exit 1; fi
