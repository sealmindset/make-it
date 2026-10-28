#!/usr/bin/env bash
# /backlog-it info: every card is explained in the same three parts, in plain English.
# Contract these checks pin:
#   - /backlog-it routes `info`, and backlog-board.md defines it: read-only, read by a background subagent.
#   - The answer's three headings and the impact's three labels are the same in backlog-board.md and in
#     CLAUDE.md, the copy /btw sees (it can't read files), and CLAUDE.md tells /btw to answer only from
#     what the session has read.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }   # reads all its input: no SIGPIPE under pipefail
has() { gq -F -- "$2" <<<"$1"; }        # has TEXT STRING
# any stderr fails the run; shown again on exit
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

CMD=.claude/commands/backlog-it.md
REF=.claude/make-it/references/backlog-board.md
SEC="$(awk '/^### `info /{on=1; print; next} on && /^### /{exit} on' "$REF")"
BTW="$(awk '/^## Explaining a card/{on=1; print; next} on && /^## /{exit} on' CLAUDE.md)"
HEADS=("**The problem**" "**Impact if it's not fixed**" "**Why it's being fixed this way**")
LABELS=("Who it hits" "The wider risk" "How far it reaches")
parts() { local p; for p in "${HEADS[@]}" "${LABELS[@]}"; do has "$1" "$p" || return 1; done; }

check "backlog-it routes info"                gq -E '^\| `info ' "$CMD"
check "the reference lists info"              gq -E '^\| `info ' "$REF"
check "the reference defines info"            [ -n "$SEC" ]
check "info never writes"                     has "$SEC" "it never writes a card, the"
check "a background subagent reads"           has "$SEC" "one read-only background subagent"
check "the reference's answer has every part" parts "$SEC"
check "CLAUDE.md gives /btw every part"       parts "$BTW"
check "/btw answers only from what it read"   has "$BTW" "answer only from what this session has already read"
# controls: a renamed heading or label must fail the parts check
parts "${SEC//The wider risk/The bigger risk}" && bad "control: renamed label passed" || ok "control: renamed label fails parts"
parts "${BTW//\*\*The problem\*\*/The problem}" && bad "control: unbolded heading passed" || ok "control: unbolded heading fails parts"

[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
