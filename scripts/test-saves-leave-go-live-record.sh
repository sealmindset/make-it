#!/usr/bin/env bash
# /wrap-it and /try-it leave the go-live record out of their saves (E02-S47; the E05-S9 spike, 2026-11-18).
# Only /ship-it writes .ship-it-go-live.json; a skill that saves for the user never stages or commits it.
# Part 1 runs /try-it's own save command, taken from the skill file, in throwaway repos. Part 2 pins the rule's sentences.
# Not covered here: an agent following /wrap-it's prose (it stages by name); that needs a real session.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
C=.claude/commands; REC=.ship-it-go-live.json
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
gx() ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX; git -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" )
# the save command: the backticked `git add ...` on try-it's "stage and commit any fixes" line
CMD="$(grep -F 'stage and commit any fixes' "$C/try-it.md" | sed -E 's/^[^`]*`(git add[^`]*)`.*$/\1/')"
case "$CMD" in "git add"*) ok "try-it: the save command is found";; *) bad "try-it: the save command is found"; CMD=false;; esac
mk() { # mk <name> <modified|staged|new|none>
  local d="$T/$1"; rm -rf "$d"; mkdir -p "$d" && gx -C "$d" init -q -b main && printf 'a\n' > "$d/app.txt"
  [ "$2" = new ] || printf '{"schema": 1, "items": {}}\n' > "$d/$REC"
  gx -C "$d" add -A && gx -C "$d" commit -qm init && printf 'patched\n' > "$d/app.txt" && printf 'new\n' > "$d/lock.json"
  [ "$2" = none ] || printf '{"schema": 1, "items": {"terms_privacy": "edited"}}\n' > "$d/$REC"
  [ "$2" != staged ] || gx -C "$d" add "$REC"; }
run() { ( cd "$T/$1" && unset GIT_DIR GIT_WORK_TREE && git config commit.gpgsign false && git config core.hooksPath /dev/null && bash -c "$CMD" >/dev/null 2>&1 ) || true; }
for c in "modified: M" "staged:M " "new:??"; do
  n="${c%%:*}"; want="${c#*:}"; mk "$n" "$n"; before="$(cat "$T/$n/$REC")"; run "$n"
  names="$(gx -C "$T/$n" show --name-only --format= HEAD | sort | tr '\n' ' ')"
  [ "$names" = "app.txt lock.json " ] && ok "try-it, record $n: the patches are saved and the record is not in the save" || bad "try-it, record $n: the patches are saved and the record is not in the save (saved: $names)"
  [ "$(gx -C "$T/$n" status --porcelain)" = "$want $REC" ] && [ "$(cat "$T/$n/$REC")" = "$before" ] && ok "try-it, record $n: the record is left exactly as it was" || bad "try-it, record $n: the record is left exactly as it was"
done
mk none none; run none
[ "$(gx -C "$T/none" show --name-only --format= HEAD | sort | tr '\n' ' ')" = "app.txt lock.json " ] && [ -z "$(gx -C "$T/none" status --porcelain)" ] && ok "try-it, record untouched: the save works as before" || bad "try-it, record untouched: the save works as before"
flat() { tr '\n' ' ' | tr -s ' '; }
has() { if [ "$(flat < "$1" | grep -cF -- "$2")" -gt 0 ]; then ok "$3"; else bad "$3"; fi; }
hasnt() { if [ "$(flat < "$1" | grep -cF -- "$2")" -eq 0 ]; then ok "$3"; else bad "$3"; fi; }
LINE='"I left your go-live record unsaved. /ship-it owns that file."'
G=.claude/make-it/references/ship-it-guide.md
has "$G" 'A skill that saves for the user leaves the record out: /resume-it, /wrap-it and /try-it never stage or commit it, even when it has changes' "guide: the rule is written once, for every skill that saves"
has "$C/wrap-it.md" 'Leave out the go-live record, `.ship-it-go-live.json`, the same way' "wrap-it: the record is left out like a password file"
has "$C/wrap-it.md" 'Never stage it, and if it was already staged, commit only the files you named' "wrap-it: a record that was already staged is still left out"
has "$C/wrap-it.md" "$LINE" "wrap-it: says the line"
has "$C/wrap-it.md" '(`ship-it-guide.md`, The record)' "wrap-it: points at the guide's rule"
has "$C/try-it.md" "$LINE" "try-it: says the line"
has "$C/try-it.md" '(`ship-it-guide.md`, The record)' "try-it: points at the guide's rule"
hasnt "$C/try-it.md" 'git add -A && git commit' "try-it: no save that takes every file"
if [ "$fail" = 0 ]; then echo "ALL PASSED"; else echo "SOME FAILED"; fi
exit $fail
