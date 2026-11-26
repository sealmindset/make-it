#!/usr/bin/env bash
# /backlog-it: a folder with no board of its own never shows another project's board (E02-S120).
# Contract these checks pin:
#   - One rule picks the board (regen-board.py find_board, `--where`): a project's own board from its
#     root or any folder below it; else the personal board in ~/.claude/backlog-it.json, but only
#     inside that file's `repo`; else none. A personal file with no `repo` is used nowhere.
#   - Outside the repo with no board: nothing of the personal board is listed, a capture writes
#     nothing, and one plain line names the board not used and why.
#   - $BACKLOG_DIR set by hand is honoured, and said when it is not this folder's board.
#   - The skill, the reference, /clear-it, /resume-it and /wrap-it all point at that one rule.
# Every case runs with a throwaway HOME, so the real boards and settings are never read.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }   # reads all its input: no SIGPIPE under pipefail
has() { gq -F -- "$2" <<<"$1"; }        # has TEXT STRING
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$T"' EXIT

BIN="$root/.claude/make-it/backlog/bin"
H="$T/home"
card() { mkdir -p "$1/items/EPIC-01-bugs/stories"
  printf -- '---\nid: E01\ntitle: Bugs\nstatus: in-progress\n---\n' > "$1/items/EPIC-01-bugs/epic.md"
  printf -- '---\nid: E01-S1\ntitle: %s\nstatus: backlog\ntype: breakfix\n---\n' "$2" > "$1/items/EPIC-01-bugs/stories/S1.md"; }
card "$H/pboard" "PERSONAL-CARD"
card "$H/code/proj/.claude/backlog" "PROJECT-CARD"
card "$H/code/shared/boards/b" "SHARED-CARD"
mkdir -p "$H/work/docai/sub/deep" "$H/code/proj/src/x" "$H/code/shared/src" "$H/code/g/.git" "$H/code/g/sub" "$H/code/plain"
mkdir -p "$H/code/shared/.claude" "$H/.claude"
printf '{"board": "boards/b"}\n' > "$H/code/shared/.claude/backlog-it.json"
PERSONAL='{"board": "~/pboard", "repo": "~/work/docai"}'
printf '%s\n' "$PERSONAL" > "$H/.claude/backlog-it.json"
snap() { find "$H/pboard" -type f -exec shasum {} + | sort; }
BEFORE="$(snap)"

# run DIR CMD...: the command from DIR, with the throwaway HOME and no $BACKLOG_DIR; stdout+stderr
run() { local d="$1"; shift; (cd "$d" && env -u BACKLOG_DIR HOME="$H" "$@" 2>&1) || true; }
where() { run "$1" python3 "$BIN/regen-board.py" --where; }
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2]) or "")' "$1" "$2" 2>&1 || true; }
is_board() { [ "$(field "$(where "$1")" board)" = "$2" ]; }

# Outside the personal repo, no board of its own: nothing listed, nothing written, one line why
W="$(where "$H/code/plain")"
check "outside: no board is picked"                 [ -z "$(field "$W" board)" ]
check "outside: the line names the board not used"  has "$(field "$W" note)" "Not using the personal board in $H/pboard: it belongs to $H/work/docai, and this folder is outside it."
check "outside: a new board would go here"          [ "$(field "$W" new)" = "$H/code/plain/.claude/backlog" ]
OUT="$(run "$H/code/plain" python3 "$BIN/status.py")"
check "outside: status lists no personal card"      bash -c '! grep -q PERSONAL-CARD <<<"$1"' _ "$OUT"
check "outside: status says this folder has none"   has "$OUT" "status: this folder has no board, so nothing was read or written."
OUT="$(cd "$H/code/plain" && printf 'a report\n' | env -u BACKLOG_DIR HOME="$H" python3 "$BIN/card.py" --no-sync capture 2>&1 || true)"
check "outside: a capture is refused"               has "$OUT" "card: this folder has no board, so nothing was read or written."
check "outside: the personal board is unchanged"    [ "$(snap)" = "$BEFORE" ]
check "home folder: no board is picked"             [ -z "$(field "$(where "$H")" board)" ]

# Inside the personal repo, and below it: as before
check "repo root: the personal board"               is_board "$H/work/docai" "$H/pboard"
check "below the repo: the personal board"          is_board "$H/work/docai/sub/deep" "$H/pboard"
check "below the repo: status lists its card"       has "$(run "$H/work/docai/sub" python3 "$BIN/status.py")" "PERSONAL-CARD"

# A project's own board wins from its root and any folder below it
check "project root: its own board"                 is_board "$H/code/proj" "$H/code/proj/.claude/backlog"
check "project subfolder: its own board"            is_board "$H/code/proj/src/x" "$H/code/proj/.claude/backlog"
check "project subfolder: status lists its card"    has "$(run "$H/code/proj/src/x" python3 "$BIN/status.py")" "PROJECT-CARD"
check "settings file: board relative to its root"   is_board "$H/code/shared/src" "$H/code/shared/boards/b"
check "a new board goes at the git root"            [ "$(field "$(where "$H/code/g/sub")" new)" = "$H/code/g/.claude/backlog" ]

# $BACKLOG_DIR set by hand: honoured, and said when it is not this folder's board
W="$(cd "$H/code/plain" && BACKLOG_DIR="$H/pboard" HOME="$H" python3 "$BIN/regen-board.py" --where 2>&1 || true)"
check "BACKLOG_DIR: honoured"                       [ "$(field "$W" board)" = "$H/pboard" ]
check "BACKLOG_DIR: says it is not this folder's"   has "$(field "$W" note)" "Using the board in \$BACKLOG_DIR ($H/pboard), set by hand: it is not this folder's board (this folder has none)."
W="$(cd "$H/code/proj" && BACKLOG_DIR="$H/code/proj/.claude/backlog" HOME="$H" python3 "$BIN/regen-board.py" --where 2>&1 || true)"
check "BACKLOG_DIR: quiet when it is this board"    [ -z "$(field "$W" note)" ]

# A personal file with no repo: used nowhere, and said once
printf '{"board": "~/pboard"}\n' > "$H/.claude/backlog-it.json"
W="$(where "$H/work/docai")"
check "no repo: the personal board is not used"     [ -z "$(field "$W" board)" ]
check "no repo: the line says why"                  has "$(field "$W" note)" "has no \"repo\" folder (a full path, or one starting with ~), so no folder is its home. Add \"repo\" to use it there."
printf '{"board": "~/pboard", "repo": "."}\n' > "$H/.claude/backlog-it.json"
check "relative repo: the personal board is not used" [ -z "$(field "$(where "$H/code/plain")" board)" ]
printf '%s\n' "$PERSONAL" > "$H/.claude/backlog-it.json"

# Every reader points at the one rule
CMD=.claude/commands/backlog-it.md; REF=.claude/make-it/references/backlog-board.md
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
check "the reference no longer uses it from any folder" bash -c '! grep -q "used from any folder that has" "$1"' _ "$REF"
check "the reference: personal board only inside repo"  has "$(flat "$REF")" "only from its \`repo\` folder or a folder below it"
check "the reference names the one rule"                has "$(flat "$REF")" "regen-board.py --where"
for f in "$CMD" .claude/commands/clear-it.md .claude/commands/resume-it.md .claude/commands/wrap-it.md; do
  check "$(basename "$f") finds the board by the one rule" has "$(flat "$f")" "regen-board.py --where"
done
check "Step 1 says the line, then offers a board"      has "$(flat "$CMD")" "say its \`note\` in one line"

# controls: the checks above must catch the old rule
has "used from any folder that has neither" "only from its \`repo\` folder or a folder below it" && bad "control: old wording passed" || ok "control: old wording fails"

[ -s "$ERRF" ] && bad "no stderr" || ok "no stderr"
exit "$fail"
