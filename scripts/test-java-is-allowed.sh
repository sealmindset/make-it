#!/usr/bin/env bash
# Java is allowed (owner, 2026-11-24): the no-Java rule (rulebook row X04, guardrails rule 12) is removed and nothing
# replaces it. The other ids and rule numbers stay where they were, and no copy of the ban may creep back.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
B=.claude/make-it/references/build-standards.md
G=.claude/make-it/references/guardrails.md
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
n() { grep -cE -- "$1" "$2" || true; }
check "the rulebook has no row X04" '[ "$(n "^[*][*]X04[*][*]" "$B")" = 0 ]'
check "rows X01-X03 and X05-X09 keep their ids" \
  '( for i in 1 2 3 5 6 7 8 9; do [ "$(n "^[*][*]X0$i[*][*] \[" "$B")" = 1 ] || exit 1; done )'
check "guardrails rule 12 is marked removed, and rules 11, 13 and 14 keep their numbers" \
  '[ "$(n "^12[.] [(]removed 2026-11-24: Java is allowed[)]\$" "$G")" = 1 ] && [ "$(n "^11[.] [*][*]Latest stable dependencies" "$G")" = 1 ] && [ "$(n "^13[.] [*][*]ENFORCE_SECRETS" "$G")" = 1 ] && [ "$(n "^14[.] [*][*]No module-level throws" "$G")" = 1 ]'
check "no range in a skill, reference or doc still counts X04 (X01-X04 ... X01-X09)" \
  '[ "$(git grep -I -cE "X0[1-3] ?(-|to|through) ?X0[4-9]" -- .claude desktop README.md CLAUDE.md docs presentation | wc -l | tr -d " ")" = 0 ]'
J='(^|[^a-z])java([^a-z]|$)'
BAN="(^|[^a-z])(no|not|never|without|avoid|prohibit[a-z]*|forbid[a-z]*|ban[a-z]*)[^.a-z][^.]{0,60}$J|$J[^.]{0,80}(prohibited|forbidden|banned|not allowed|not permitted)|no-java"
check "no skill, reference, scaffold, desktop copy or doc forbids Java" \
  '[ "$(git grep -I -i -E "$BAN" -- .claude desktop README.md CLAUDE.md docs presentation | wc -l | tr -d " ")" = 0 ]'
exit $fail
