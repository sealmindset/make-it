#!/usr/bin/env bash
# E03-S8: /wrap-it asks through the approval block -- fewer asks, same gates.
# Contract these checks pin (.claude/commands/wrap-it.md, as the /wrap-it agent reads it):
#   - approval-block.md is linked exactly once, inside <execution_context>; no bare yes/no ask is left.
#   - Saving uncommitted work is routine: no question, a local save, never pushed, said in one line with its undo;
#     a file that may hold a password or key is never saved by it.
#   - Removing a finished worktree and deleting a merged local branch stay high-stakes: each is its own ask, decision-ready
#     (evidence, undo, what is unusual, the one thing to check), and only what the user names is removed -- never on a plain
#     yes, never forced.
#   - Every /wrap-it gate stays: no volume-destroying shutdown, no prune, no killed process, no push, no new work, the
#     state file always written, unsaved or unmerged worktrees never removed, other sessions' branches and worktrees left.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# the whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise)
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

F=.claude/commands/wrap-it.md
LINK='@~/.claude/make-it/references/approval-block.md'
flat() { tr '\n' ' ' | tr -s ' '; }
# text between the first line matching $1 and the next line matching $2 (start line included)
between() { awk -v a="$1" -v b="$2" 'on && $0 ~ b {exit} $0 ~ a {on=1} on' "$F"; }

CTX="$(between '^<execution_context>' '^</execution_context>')"
SAVE="$(between '<step name="save-progress">' '^\*\*3\. ' | awk '/^\*\*2\. /{on=1} on' | flat)"
WT="$(between '^\*\*4\. Tidy up finished worktrees' '^\*\*5\. ' | flat)"
BR="$(between '^\*\*5\. Prune stale branches' '^</step>' | flat)"
GUARD="$(between '^<guardrails>' '^</guardrails>')"
ALL="$(flat < "$F")"

# 1. the block is linked once, in <execution_context>, as the other skills link it
check "approval-block.md is named exactly once in wrap-it.md" '[ "$(grep -c "approval-block\.md" "$F")" = 1 ]'
check "that one link is the @-import inside <execution_context>" 'printf "%s\n" "$CTX" | gq -xF "$LINK"'

# 2. no bare yes/no ask
check "grep -niE '\\(y/n\\)|y/n\\b|yes/no' prints nothing" '[ "$(grep -ciE "\(y/n\)|y/n\b|yes/no" "$F")" = 0 ]'

# 3. the save is routine: no question, a local save, never pushed, said in one line, with its undo
check "the save step was found" '[ -n "$SAVE" ]'
check "the save step asks nothing: no question offering to save or commit" \
  '! printf "%s" "$SAVE" | gq -iE "(want me to|should I|shall I|ok to|okay to|do you want)[^?]{0,80}(save|commit)[^?]*\?"'
check "the save step does not wait on the user before saving" \
  '! printf "%s" "$SAVE" | gq -iE "\b(ask|wait for|confirm with)\b[^.]{0,60}\b(save|commit)"'
check "the save step says it saves without asking" \
  'printf "%s" "$SAVE" | gq -iE "(without asking|no question)[^.]{0,80}(save|commit)|(save|commit)[^.]{0,80}(without asking|no question)"'
check "the save is a local commit and is never pushed" \
  'printf "%s" "$SAVE" | gq -iE "commit[^.]{0,40}locally|local (checkpoint|commit|save)" && printf "%s" "$SAVE" | gq -iE "(do not|never|don.t) push"'
check "the user is told in one line what was saved, and that nothing was sent" \
  'printf "%s" "$SAVE" | gq -iE "in one line" && printf "%s" "$SAVE" | gq -iE "nothing (was|is) sent"'
check "the save says how to take it back, and the undo keeps the changes" \
  'printf "%s" "$SAVE" | gq -iE "take (the save|it) back" && printf "%s" "$SAVE" | gq -F "git reset --soft HEAD~1"'
check "a file that may hold a password or key is never saved by it" \
  'printf "%s" "$SAVE" | gq -F ".env" && printf "%s" "$SAVE" | gq -iE "password" && printf "%s" "$SAVE" | gq -iE "(never stage|leave[^.]{0,30}out)"'
check "no leftover 'declined to save' branch elsewhere (the save no longer has a no)" \
  '! printf "%s" "$ALL" | gq -iE "declined to save|offer to save"'

# 4. each deletion is its own active confirmation, decision-ready, naming what is removed
for x in "worktree removal|WT|scripts/worktree.sh rm|--force" "branch deletion|BR|git branch -d|git branch -D"; do
  IFS='|' read -r name var cmd forbidden <<<"$x"
  T="${!var}"
  check "$name: the step was found" '[ -n "$T" ]'
  check "$name: the user picks or names which ones; nothing else is removed" \
    'printf "%s" "$T" | gq -iE "\b(pick|name)s? (them|which|each)|which (ones )?should I (remove|delete)" && printf "%s" "$T" | gq -iE "only the ones (they|the user) (named|picked|name|pick)"'
  check "$name: a plain yes is not a pick" \
    'printf "%s" "$T" | gq -iE "plain .?(yes|ok).?[^.]{0,40}(is not|isn.t) a pick"'
  check "$name: 'all' counts only with the number in it" \
    'printf "%s" "$T" | gq -iE "\ball\b[^.]{0,60}\b(number|count)\b"'
  check "$name: a way to keep everything is offered" 'printf "%s" "$T" | gq -iE "keep them all"'
  check "$name: evidence -- it says what was checked" 'printf "%s" "$T" | gq -iE "I checked"'
  check "$name: blast radius and undo are stated" \
    'printf "%s" "$T" | gq -iE "(removes|deletes) only" && printf "%s" "$T" | gq -iE "brought back|undo|can.t be"'
  check "$name: what is unusual is stated" 'printf "%s" "$T" | gq -iE "unusual"'
  check "$name: the one thing to check is stated" 'printf "%s" "$T" | gq -iE "the one thing to check"'
  check "$name: runs $cmd on the named ones" 'printf "%s" "$T" | gq -F -- "$cmd"'
  check "$name: never $forbidden" \
    '! printf "%s" "$T" | sed "s/[Nn][Ee][Vv][Ee][Rr][^.]*//g" | gq -F -- "$forbidden"'
  check "$name: it is high-stakes per the approval block" 'printf "%s" "$T" | gq -iE "high-stakes"'
done
check "worktree removal: never a worktree with unsaved work or an unmerged branch" \
  'printf "%s" "$WT" | gq -iE "NEVER remove a worktree that has uncommitted changes or an unmerged branch"'
check "branch deletion: other sessions' and tools' branches and worktrees are off-limits" \
  'printf "%s" "$BR" | gq -iE "don.t own" && printf "%s" "$BR" | gq -iE "off-limits"'
check "branch deletion: never pushes a delete" 'printf "%s" "$BR" | gq -iE "never .?git push.? deletes"'

# 5. every /wrap-it gate stays
check "the only 'down -v' is the NEVER rule" \
  '[ "$(grep -c "down -v" "$F")" = 1 ] && printf "%s\n" "$GUARD" | gq -F "NEVER run \`docker compose down -v\`"'
check "shutdown preserves data volumes" 'printf "%s" "$ALL" | gq -iE "preserves data volumes"'
check "no prune of docker data" 'printf "%s\n" "$GUARD" | gq -F "NEVER run \`docker system prune\` or \`docker volume prune\`"'
check "never kills processes; orphaned ports are only reported" \
  'printf "%s\n" "$GUARD" | gq -F "NEVER kill processes" && printf "%s" "$ALL" | gq -iE "do NOT kill them"'
check "never pushes to remote" 'printf "%s\n" "$GUARD" | gq -F "NEVER push to remote"'
check "never starts new work" 'printf "%s\n" "$GUARD" | gq -F "NEVER start new work"'
check "always updates the state file" 'printf "%s\n" "$GUARD" | gq -F "ALWAYS update .make-it-state.md"'
check "guardrails: never remove or delete a worktree or branch the user didn't name" \
  'printf "%s\n" "$GUARD" | gq -iE "NEVER (remove|delete)[^.]*(worktree|branch)[^.]*(didn.t|did not) (name|pick)"'
check "guardrails: never save a file that may hold a password or key" \
  'printf "%s\n" "$GUARD" | gq -iE "NEVER (save|commit|stage)[^.]*password"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
