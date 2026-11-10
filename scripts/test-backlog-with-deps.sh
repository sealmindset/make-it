#!/usr/bin/env bash
# /backlog-it plan --with-deps: plan a filter (one epic, say) plus the chain of cards it waits on, across epics.
# Contract these checks pin:
#   - Every backlog helper's self-test passes: regen-board (the one waiting rule, `needs`: own + ancestors'
#     dependsOn, an id with children = its open cards), scope (the filter and its chain), check-plan (the
#     gate: wait order, nothing outside the scope, links), and the helpers that share regen-board.
#   - /backlog-it routes `plan` and `groom` with --with-deps; the reference defines both, defines
#     "What a card waits on" once, runs scope.py before the route call and passes --scope to the gate.
#   - The owner's 2026-11-10 calls: written links plus suggested ones (written only under --apply);
#     an epic id means its open cards and an epic's dependsOn holds for its cards; finish-soonest
#     order unchanged; upstream only; a card id works as a filter; groom takes the flag too.
#   - Every in-file link to the plan/groom headings resolves (renaming a heading breaks anchors).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }   # reads all its input: no SIGPIPE under pipefail
has() { gq -F -- "$2" <<<"$1"; }        # has TEXT STRING
ERRF="$(mktemp)"; TMPF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF" "$TMPF"' EXIT

BIN=.claude/make-it/backlog/bin
CMD=.claude/commands/backlog-it.md
REF=.claude/make-it/references/backlog-board.md
DOC=.claude/make-it/confluence-docs/16-backlog-it.md
one() { tr '\n' ' ' <<<"$1" | tr -s ' '; }   # one line, so a rule wrapped across lines still reads
sec() { awk -v h="$1" 'index($0, h) == 1 {on=1; print; next} on && /^### /{exit} on' "$REF"; }
PLAN="$(one "$(sec '### `plan [filter] [--with-deps]')")"
GROOM="$(one "$(sec '### `groom [filter] [--with-deps]')")"
CARD="$(one "$(awk '/^## Card frontmatter/{on=1; next} on && /^## /{exit} on' "$REF")")"
# every (#plan-…)/(#groom-…) link in the reference names a heading in it, by GitHub's slug rule
anchors() { python3 -I - "$1" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
slug = lambda h: re.sub(r'[^\w\- ]', '', h.strip().lower()).replace(' ', '-')
heads = {slug(h) for h in re.findall(r'^#{1,6} (.+)$', t, re.M)}
miss = sorted({a for a in re.findall(r'\]\(#([^)]+)\)', t) if a.startswith(('plan-', 'groom-')) and a not in heads})
if miss: print('\n'.join(miss))
sys.exit(1 if miss else 0)
PY
}

for s in regen-board scope check-plan status card sync-prs; do
  check "$s self-test" bash -c "python3 '$BIN/$s.py' --self-test | grep -q 'self-test: OK'"
done
check "backlog-it routes plan --with-deps"       gq -E '^\| `plan \[filter\] \[--with-deps\]' "$CMD"
check "backlog-it routes groom --with-deps"      gq -E '^\| `groom \[filter\] \[--with-deps\]' "$CMD"
check "the reference lists plan --with-deps"     gq -E '^\| `plan \[filter\] \[--with-deps\]' "$REF"
check "the reference lists groom --with-deps"    gq -E '^\| `groom \[filter\] \[--with-deps\]' "$REF"
check "the reference defines plan --with-deps"   [ -n "$PLAN" ]
check "the reference defines groom --with-deps"  [ -n "$GROOM" ]
check "one waiting rule, defined once"           [ "$(grep -c -F '**What a card waits on**' "$REF")" -eq 1 ]
check "an epic's dependsOn holds for its cards"  has "$CARD" "an epic's \`dependsOn\` holds for each card under it"
check "an epic id means its open cards"          has "$CARD" "An id with children stands for its open cards"
check "the helpers list scope.py"                gq -F 'backlog/bin/scope.py <board> [<filter>] [--with-deps]' "$REF"
check "plan runs scope.py first"                 has "$PLAN" 'scope.py <board> [filter] [--with-deps] > <tmp>/scope.json'
check "the gate gets the scope"                  has "$PLAN" '--scope <tmp>/scope.json'
check "a card id is a filter"                    has "$PLAN" '`filter` = a card id (an epic, or one story'
check "upstream only"                            has "$PLAN" 'Only upstream -- never the cards that wait on the filter'
check "conflictsWith is not followed"            has "$PLAN" '`conflictsWith` is not followed'
check "finish-soonest order unchanged"           has "$PLAN" 'under the same order (finish soonest'
check "links are suggested with evidence"        has "$PLAN" 'each with the evidence'
check "links are written only under --apply"     has "$PLAN" '**Suggested links**, too, are written only under `--apply`'
check "one more pass, no chase"                  has "$PLAN" 'one round, no chase'
check "groom pulls in the chain too"             has "$GROOM" "**\`--with-deps\`** adds the chain behind the filter"
check "dispatch waits on the same rule"          gq -F "nothing it waits on unfinished (its own \`dependsOn\` or its epic's" "$CMD"
check "the user doc shows plan E04 --with-deps"  gq -F 'plan E04 --with-deps' "$DOC"
check "plan/groom anchors resolve"               anchors "$REF"
MODELS="$(one "$(awk '/^### Which model does what/{on=1; next} on && /^##/{exit} on' "$REF")")"
check "the reference says which model does what" [ -n "$MODELS" ]
check "settings carry models, Fable 5.2 then 5.1" gq -F '"judge": ["claude-fable-5-2", "claude-fable-5-1"]' "$REF"
check "plan routes with --model"                 has "$PLAN" 'claude -p --model <route>'
check "groom judges on the judge model"          has "$GROOM" 'one agent on model `judge` for steps 2-5'
check "no judge served -> route, said aloud"     has "$MODELS" 'never a silent switch'
check "the skill loads MODELS"                   gq -F '`MODELS` = `models`' "$CMD"
# controls: a renamed heading must break the anchor check; a dropped flag must fail the route check
sed 's/^### `plan \[filter\] \[--with-deps\]/### `plan [filter]/' "$REF" >"$TMPF"
anchors "$TMPF" >/dev/null && bad "control: renamed plan heading passed" || ok "control: renamed plan heading breaks anchors"
sed 's/^| `plan \[filter\] \[--with-deps\]/| `plan [filter]/' "$CMD" >"$TMPF"
gq -E '^\| `plan \[filter\] \[--with-deps\]' "$TMPF" && bad "control: dropped flag passed" || ok "control: dropped flag fails the route check"

[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
