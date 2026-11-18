#!/usr/bin/env bash
# /resume-it, /wrap-it and /try-it stand still when a merge or rebase was left unfinished (E05-S22, from the E05-S9
# spike; owner 2026-11-18). They save nothing, finish, continue or undo nothing, and say one line. Until /ship-it can
# put a stuck update back (E05-S24), the line points to a developer (owner's pick, 2026-11-18).
# Part 1 runs each skill's own detection command in throwaway repos. Part 2 pins the sentences that carry the rule.
# Not covered here: an agent actually following the skill. That needs a real session.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
C=.claude/commands
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
gx() ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX; git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -c init.defaultBranch=main "$@" )
# the fenced bash block that follows a skill's "An unfinished update" line
snippet() { awk '/An unfinished update/{seen=1} seen&&/^```bash/{on=1;next} on&&/^```/{exit} on' "$C/$1.md"; }
mk() { rm -rf "$T/$1"; mkdir -p "$T/$1" && gx -C "$T/$1" init -q && printf 'one\n' > "$T/$1/app.txt" && gx -C "$T/$1" add app.txt && gx -C "$T/$1" commit -qm init \
  && gx -C "$T/$1" checkout -qb other && printf 'other\n' > "$T/$1/app.txt" && gx -C "$T/$1" commit -qam other \
  && gx -C "$T/$1" checkout -q main && printf 'main\n' > "$T/$1/app.txt" && gx -C "$T/$1" commit -qam main; }
state() { printf '%s|%s|%s' "$(gx -C "$1" rev-parse HEAD)" "$(gx -C "$1" status --porcelain)" "$(ls "$1/.git" | sort | tr '\n' ' ')"; }
run() { ( cd "$1" && unset GIT_DIR GIT_WORK_TREE && bash -c "$2" 2>&1 ) || true; }
FIRST="$(snippet resume-it)"
for s in resume-it wrap-it try-it; do
  S="$(snippet "$s")"
  [ -n "$S" ] && ok "$s: has a detection command" || { bad "$s: has a detection command"; continue; }
  [ "$S" = "$FIRST" ] && ok "$s: the command is the same one in all three skills" || bad "$s: the command is the same one in all three skills"
  mk clean; [ -z "$(run "$T/clean" "$S")" ] && ok "$s: a clean project prints nothing" || bad "$s: a clean project prints nothing"
  mk merge; gx -C "$T/merge" merge -q other >/dev/null 2>&1 || true; printf 'not saved\n' > "$T/merge/note.txt"; b="$(state "$T/merge")"
  [ "$(run "$T/merge" "$S")" = unfinished ] && ok "$s: an unfinished merge is seen" || bad "$s: an unfinished merge is seen"
  [ "$b" = "$(state "$T/merge")" ] && [ -f "$T/merge/note.txt" ] && ok "$s: looking changes nothing in an unfinished merge" || bad "$s: looking changes nothing in an unfinished merge"
  mk rebase; gx -C "$T/rebase" rebase -q other >/dev/null 2>&1 || true; b="$(state "$T/rebase")"
  [ "$(run "$T/rebase" "$S")" = unfinished ] && ok "$s: an unfinished rebase is seen" || bad "$s: an unfinished rebase is seen"
  [ "$b" = "$(state "$T/rebase")" ] && ok "$s: looking changes nothing in an unfinished rebase" || bad "$s: looking changes nothing in an unfinished rebase"
  mk apply; gx -C "$T/apply" rebase -q --apply other >/dev/null 2>&1 || true
  [ "$(run "$T/apply" "$S")" = unfinished ] && ok "$s: an unfinished rebase of the older kind (apply) is seen" || bad "$s: an unfinished rebase of the older kind (apply) is seen"
  mkdir -p "$T/nogit"; [ -z "$(run "$T/nogit" "$S")" ] && ok "$s: a folder that is not a git project prints nothing" || bad "$s: a folder that is not a git project prints nothing"
  mk wt; gx -C "$T/wt" worktree add -q "$T/wt-linked" -b linked >/dev/null 2>&1; gx -C "$T/wt-linked" merge -q other >/dev/null 2>&1 || true
  [ "$(run "$T/wt-linked" "$S")" = unfinished ] && ok "$s: an unfinished merge in a linked working copy is seen" || bad "$s: an unfinished merge in a linked working copy is seen"
  gx -C "$T/wt" worktree remove --force "$T/wt-linked" >/dev/null 2>&1 || true
done
flat() { tr '\n' ' ' | tr -s ' '; }
has() { if [ "$(flat < "$C/$1.md" | grep -cF -- "$2")" -gt 0 ]; then ok "$1: $3"; else bad "$1: $3"; fi; }
hasnt() { if [ "$(flat < "$C/$1.md" | grep -cF -- "$2")" -eq 0 ]; then ok "$1: $3"; else bad "$1: $3"; fi; }
LINE="\"An update of your branch isn't finished. I haven't changed it and I'm not saving anything while it is. A developer can finish it.\""
for s in resume-it wrap-it try-it; do
  has "$s" "$LINE" "says the exact line, pointing to a developer"
  has "$s" 'makes no commit, stages nothing, and runs nothing that finishes, continues or undoes the update' "saves nothing and finishes, continues or undoes nothing"
  has "$s" 'no `--continue`, no `--abort`, no stash, no reset, no checkout of files' "the forbidden commands are named"
  has "$s" 'any of those can lose work that was never saved' "the reason is unsaved work"
  has "$s" 'whichever files the update touches' "the rule holds whatever files are in the update"
  hasnt "$s" 'Updates belong to /ship-it' "does not send the user to /ship-it, which cannot do it yet"
done
has resume-it '**An unfinished update, everywhere in this skill:**' "the rule covers the whole skill"
has resume-it 'before any step that would save, stage or commit' "checked before every save"
has resume-it 'Reading, explaining and answering questions go on as usual; work that needs a save waits' "reading goes on, saving waits"
has wrap-it 'it skips this save and the worktree and branch tidy-up' "skips the save and the tidy-up"
has wrap-it 'It still updates its notes on disk and shuts the app down' "still writes notes and shuts down"
has try-it 'it skips the safety updates and their save, and runs the app as it is' "skips safety patches and runs the app as it is"
has try-it 'Unless an update is unfinished (above), stage and commit any fixes' "the save step is guarded"
if [ "$fail" = 0 ]; then echo "ALL PASSED"; else echo "SOME FAILED"; fi
exit $fail
