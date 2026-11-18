#!/usr/bin/env bash
# /backlog-it groom also judges whether each epic, story and task is still needed (owner, 2026-11-18).
# The rules pinned here: evidence for "not needed", a default of "needed", never closed without the
# owner's pick (not even under --apply), kept and reversible.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
REF=.claude/make-it/references/backlog-board.md
CMD=.claude/commands/backlog-it.md
G="$(awk 'index($0, "### `groom [filter] [--with-deps]") == 1 {on=1; print; next} on && /^### /{exit} on' "$REF" | tr '\n' ' ' | tr -s ' ')"
has() { if [ "$(grep -cF -- "$1" <<<"$G")" -gt 0 ]; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi; }
hasf() { if [ "$(tr '\n' ' ' < "$2" | tr -s ' ' | grep -cF -- "$1")" -gt 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
[ -n "$G" ] && echo "ok   the groom section is found" || { echo "FAIL the groom section is found"; fail=1; }
has '**Needed or not.** Before anything is ranked, ask of every card in scope, and of every epic that owns one' "every card and its epic is judged, before ranking"
has 'The answer is `needed`, `not needed` or `can'"'"'t tell`' "three answers"
has '`not needed` takes evidence of one of these, cited' "not needed takes cited evidence"
has '**Already covered**' "reason: already covered"
has '**Overtaken**' "reason: overtaken"
has '**Nobody is asking**' "reason: nobody is asking"
has '**An epic with nothing left**' "reason: an epic with nothing left"
has 'The default is `needed`' "the default is needed"
has 'Age, a low priority and "it'"'"'s hard" are never evidence' "age, priority and difficulty are not evidence"
has 'is `not needed` only when the code shows it fixed or gone, never because it is unwelcome' "a security finding is not dismissed"
has '"Not worth doing now" is a deferral, not `not needed`' "not now is a deferral"
has '**A `not needed` verdict is a proposal, under `--apply` too.**' "never applied on its own"
has 'one option per card, each with its title and the reason in a line, no "all of them"' "the ask is one pick per card"
has 'a card not picked stays as it was' "an unpicked card is untouched"
has '`status: done`, `closed_as: not-needed`' "a picked card is closed and marked"
has 'It is never deleted, and `undo` brings it back' "kept and reversible"
has '## Needed or not (proposals -- nothing closes without your pick)' "the plan has the section"
has '**what is no longer needed** (count, then each card with its reason)' "the report names them"
hasf 'say which epics, stories and tasks are no longer needed' "$CMD" "the command's table says so"
exit $fail
