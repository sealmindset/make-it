#!/usr/bin/env bash
# E12-S3 step 4: the shipped hook refuses Claude's `git push --force` and lets --force-with-lease through,
# and the installers add it to ~/.claude/settings.json without clobbering anything there.
#   Part 1  the hook script against a table of command lines (refused / allowed), sent the way Claude
#           Code sends them (a JSON object on stdin), plus its failure mode
#   Part 2  the settings merge (install.sh's Python helper) against temp-HOME fixtures
#   Part 3  install.ps1's PowerShell helper against the same fixtures (pwsh; SKIPPED loudly without it,
#           and a failure in CI, where pwsh is present on the runner)
#   Part 4  install.sh itself, run twice against a temp HOME: the hook is added once, with a backup
# Never touches the real ~/.claude.
set -uo pipefail
cd "$(dirname "$0")/.."
HOOK=.claude/make-it/hooks/no-force-push.sh
PY=.claude/make-it/scripts/add-no-force-push-hook.py
PS=.claude/make-it/scripts/add-no-force-push-hook.ps1
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- Part 1: the hook ---------------------------------------------------------------------------
payload() { python3 -c 'import json,sys; print(json.dumps({"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"run it"}}))' "$1"; }
run_hook() { printf '%s' "$1" | bash "$HOOK" >/dev/null 2>"$T/err"; }

blocked=(
  'git push --force'
  'git push -f'
  'git push -f origin main'
  'git push origin main --force'
  'git push origin main -f'
  'git push -uf origin feat'
  'git push -fu origin feat'
  'git push origin +main'
  'git push origin +HEAD:main'
  'git push origin "+main:main"'
  'git -C /tmp/x push --force'
  'git -C "/tmp/with space" push -f origin main'
  'git -c push.default=current push --force'
  'git --git-dir=.git push --force'
  'cd app && git push --force origin main'
  'git status; git push -f'
  'npm test || git push --force'
  'echo hi | git push --force'
  '(git push --force)'
  'FOO=1 git push --force'
  'env GIT_TRACE=1 git push --force'
  'command git push -f'
  '/usr/bin/git push --force'
  'git.exe push --force'
  'git push --force-with-lease --force'
  'git push --force-with-lease -f origin main'
  'git push --mirror'
  'git push --mirr origin'
  'git push -o ci.skip -f origin main'
  'git push origin main --force 2>&1'
  $'git fetch\ngit push --force'
)
allowed=(
  'git push'
  'git push origin main'
  'git push -u origin feat'
  'git push --force-with-lease'
  'git push --force-with-lease origin feat'
  'git push --force-with-lease=main:abc123 origin main'
  'git push --force-with-lease --force-if-includes origin feat'
  'git push --force-if-includes origin feat'
  'git push origin :old-branch'
  'git push --delete origin old-branch'
  'git push --no-force-with-lease origin feat'
  'git push origin main 2>&1 | tail -5'
  'git -C /tmp/x push origin main'
  'git commit -m "never git push --force"'
  "git commit -m 'git push -f is refused'"
  'echo "git push --force"'
  'git stash push -m wip'
  'git log --oneline -5'
  'ls -la'
  'rm -rf build && git push origin feat'
  'git push -o ci.skip origin feat'
  'git push origin feat # --force'
)
nb=0; na=0
for c in "${blocked[@]}"; do
  if run_hook "$(payload "$c")"; then bad "allowed (should refuse): $c"
  elif [ $? -ne 2 ]; then bad "refused with the wrong exit code: $c"
  else nb=$((nb + 1)); fi
done
for c in "${allowed[@]}"; do
  if run_hook "$(payload "$c")"; then na=$((na + 1)); else bad "refused (should allow): $c ($(cat "$T/err"))"; fi
done
ok "the hook refuses $nb of ${#blocked[@]} force pushes and allows $na of ${#allowed[@]} other commands"
# the message names the safe way
run_hook "$(payload 'git push --force')"
grep -qF -- '--force-with-lease' "$T/err" && ok "the refusal names --force-with-lease" || bad "the refusal doesn't name --force-with-lease"
# failure mode: input it can't read
if run_hook '{"tool_name":"Bash","tool_input":{"command":"git push --force'; then bad "an unterminated command string with a force push was allowed"; else ok "unreadable input with a force push: refused"; fi
if run_hook '{"tool_name":"Bash","tool_input":{"command":"git push origin main'; then ok "unreadable input without a force sign: allowed"; else bad "unreadable input without a force sign was refused"; fi
if run_hook 'not json at all: git push -f'; then bad "non-JSON input with a force push was allowed"; else ok "non-JSON input with a force push: refused"; fi
if run_hook 'not json at all'; then ok "non-JSON input with no push: allowed"; else bad "non-JSON input with no push was refused"; fi
if run_hook "$(payload "git push 'unterminated --force")"; then bad "an unterminated quote with a force push was allowed"; else ok "an unterminated quote with a force push: refused"; fi
if run_hook "$(payload "echo 'unterminated")"; then ok "an unterminated quote and no push: allowed"; else bad "an unterminated quote and no push was refused"; fi
# JSON escapes are read: a \" inside the command, a \\ before it, a \n between commands
if run_hook "$(payload 'git commit -m "a \"quoted\" word" && git push -f')"; then bad "escaped quotes hid the force push"; else ok "escaped quotes in the command are read"; fi
# wrappers with options that take values (review, 2026-11-22)
for c in 'sudo -u root git push -f' 'nice -n 5 git push --force' '/usr/bin/env git push -f' 'env -u X git push --force' 'doas -u root git push -f origin main'; do
  if run_hook "$(payload "$c")"; then bad "allowed behind a wrapper (should refuse): $c"; else ok "refused behind a wrapper: $c"; fi
done
run_hook "$(payload 'sudo ls -la')" && ok "a wrapper running something else: allowed" || bad "sudo ls was refused"
# the fallback reads only the command, never the description: an unreadable plain push with a + in the description
if run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin 'main\",\"description\":\"push a + b\"}}"; then ok "unreadable command: a + in the description doesn't refuse a plain push"
else bad "unreadable command: a + in the description refused a plain push"; fi
# a long command is read in time: a 60 KB heredoc that only mentions a force push is read and allowed
big="git commit -F - <<'EOF'
$(for _ in $(seq 1 1000); do echo 'this line mentions git push --force in the message body'; done)
EOF"
s=$(date +%s); run_hook "$(payload "$big")"; rc=$?; e=$(( $(date +%s) - s ))
[ "$rc" = 0 ] && [ "$e" -lt 5 ] && ok "a 55 KB command that only mentions a force push is allowed in ${e}s" || bad "a 55 KB command: exit $rc after ${e}s"
# past 64 KB the raw-text rule decides, fast: a 2 MB word (2 s at most) with and without a force sign
python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":"git push origin " + "x"*2000000 + " --force"}}))' > "$T/big-force.json"
python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":"git push origin " + "x"*2000000}}))' > "$T/big-plain.json"
s=$(python3 -c 'import time;print(time.time())'); bash "$HOOK" < "$T/big-force.json" >/dev/null 2>&1; rc1=$?; bash "$HOOK" < "$T/big-plain.json" >/dev/null 2>&1; rc2=$?
e=$(python3 -c "import time;print(round(time.time()-$s,2))")
[ "$rc1" = 2 ] && [ "$rc2" = 0 ] && python3 -c "import sys; sys.exit(0 if $e < 2 else 1)" && ok "two 2 MB commands judged by the raw-text rule in ${e}s: force refused, plain push allowed" || bad "2 MB commands: exits $rc1/$rc2 in ${e}s"
# the hook header names what it does not catch
for w in 'bash -c' 'eval' 'xargs' 'aliases' 'remote.*.push' '$(...)' "pu''sh"; do
  grep -qF -- "$w" "$HOOK" && ok "the hook's header names a bypass it doesn't catch: $w" || bad "the hook's header doesn't name: $w"
done

# --- Part 2 and 3: the settings merge, both helpers, the same fixtures and the same outcomes ------
HF="$T/hookfile/make-it/hooks/no-force-push.sh"; mkdir -p "$(dirname "$HF")"; echo '#!/bin/sh' > "$HF"
CMD="bash '$HF'"
WANT='{"type": "command", "command": "'"$HF"'", "onFailure": "block"}'
ours() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(json.dumps([h for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[]) if "make-it/hooks/no-force-push.sh" in h.get("command","")], sort_keys=True))' "$1"; }
expect_ours() { python3 -c 'import json,sys; print(json.dumps([{"type":"command","command":sys.argv[1],"onFailure":"block"}], sort_keys=True))' "$CMD"; }
baks() { ls "$1"/settings.json.bak-* 2>/dev/null | wc -l | tr -d ' '; }
OUTCOMES="$T/outcomes"; : > "$OUTCOMES"
merge_cases() {  # $1 = label, $2... = the helper's command line; it is given: settings, command, hook file, state file, [mode]
  local label=$1; shift
  local d st
  run() { "$@" >"$T/out" 2>"$T/err"; }
  # no file: created with only the hook, no backup, state "added"
  d="$T/$label-none"; mkdir -p "$d"; st="$d/state"
  if run "$@" "$d/settings.json" "$CMD" "$HF" "$st" && [ "$(ours "$d/settings.json")" = "$(expect_ours)" ] && [ "$(baks "$d")" = 0 ] && [ "$(cat "$st")" = added ]; then
    ok "$label: no settings file -> created with the hook (onFailure block), no backup"; else bad "$label: no settings file ($(cat "$T/err"))"; fi
  # empty file
  d="$T/$label-empty"; mkdir -p "$d"; : > "$d/settings.json"
  if run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state" && [ "$(ours "$d/settings.json")" = "$(expect_ours)" ] && [ "$(baks "$d")" = 1 ]; then
    ok "$label: empty settings file -> hook added, backup kept"; else bad "$label: empty settings file"; fi
  # unrelated settings and hooks: all kept in order, ours appended once, an exact backup; then idempotent
  d="$T/$label-other"; mkdir -p "$d"
  cat > "$d/settings.json" <<'JSON'
{
  "model": "opus",
  "env": {"FOO": "bär"},
  "permissions": {"allow": ["Bash(ls:*)"], "deny": []},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "python3 /x/git-guard.py"}]},
      {"hooks": [{"type": "command", "command": "/x/other", "timeout": 5}]}
    ],
    "Stop": [{"hooks": [{"type": "command", "command": "/x/stop"}]}]
  },
  "startedAt": "2026-01-02T03:04:05Z",
  "enabledPlugins": {"a@b": true}
}
JSON
  cp "$d/settings.json" "$T/orig.json"
  if run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"; then
    python3 - "$T/orig.json" "$d/settings.json" "$CMD" <<'PYEOF' && ok "$label: existing settings kept (and in their order), the hook appended once" || bad "$label: existing settings were changed"
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
added = b["hooks"]["PreToolUse"].pop()
assert added == {"matcher": "Bash", "hooks": [{"type": "command", "command": sys.argv[3], "onFailure": "block"}]}, added
assert a == b and list(a) == list(b) and list(a["hooks"]) == list(b["hooks"]), (a, b)
PYEOF
    [ "$(baks "$d")" = 1 ] && cmp -s "$(ls "$d"/settings.json.bak-*)" "$T/orig.json" && ok "$label: backup holds the original bytes" || bad "$label: no exact backup"
    cp "$d/settings.json" "$T/after1.json"
    run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"
    cmp -s "$d/settings.json" "$T/after1.json" && [ "$(baks "$d")" = 1 ] && ok "$label: a second run adds nothing and backs up nothing" || bad "$label: a second run changed the file or backed it up again"
  else bad "$label: merge into existing settings failed ($(cat "$T/err"))"; fi
  # a stale make-it entry (an old path, the old form without onFailure): replaced, not duplicated, backed up
  # (fixture changed on purpose, review 2026-11-22: it used to count as installed)
  d="$T/$label-stale"; mkdir -p "$d"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash /old/home/.claude/make-it/hooks/no-force-push.sh"}]}]}}' > "$d/settings.json"
  run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"
  [ "$(ours "$d/settings.json")" = "$(expect_ours)" ] && [ "$(baks "$d")" = 1 ] && grep -q '^Updated' "$T/out" && ok "$label: a stale make-it entry -> replaced once, with a backup" || bad "$label: a stale entry was kept or duplicated ($(cat "$T/out"))"
  # the exact entry but the hook file is gone: not installed (rewritten), never "already there"
  d="$T/$label-gone"; mkdir -p "$d"; cp "$T/$label-none/settings.json" "$d/settings.json"
  run "$@" "$d/settings.json" "$CMD" "$d/no-such-hook.sh" "$d/state"
  grep -q 'already' "$T/out" && bad "$label: an entry whose hook file is missing counted as installed" || ok "$label: an entry whose hook file is missing doesn't count as installed"
  # removed by the user: an "added" state with no entry -> stays off; a "removed" state -> stays off; add brings it back
  d="$T/$label-took-out"; mkdir -p "$d"; echo '{"model":"opus"}' > "$d/settings.json"; echo added > "$d/state"
  run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"
  [ "$(ours "$d/settings.json")" = "[]" ] && [ "$(cat "$d/state")" = removed ] && grep -q 'stays off' "$T/out" && ok "$label: taken out by the user -> stays out, recorded as removed" || bad "$label: an entry the user took out came back"
  run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"
  [ "$(ours "$d/settings.json")" = "[]" ] && ok "$label: a later install leaves it out" || bad "$label: a later install put it back"
  run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state" add
  [ "$(ours "$d/settings.json")" = "$(expect_ours)" ] && [ "$(cat "$d/state")" = added ] && ok "$label: add puts it back" || bad "$label: add didn't put it back"
  run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state" remove
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d == {"model":"opus"}, d' "$d/settings.json" && [ "$(cat "$d/state")" = removed ] && grep -q '^Removed' "$T/out" \
    && ok "$label: remove takes it out (and only it) and records it" || bad "$label: remove left something behind or took too much"
  # unusable files: stop, write nothing, back up nothing (bad JSON, wrong shapes, comments, NaN, a byte that isn't UTF-8)
  local k=0
  for body in '{"model": "opus",' '[1,2]' '[{}]' '{"hooks": []}' '{"hooks": {"PreToolUse": {}}}' '{"a": 1, // note
}' '{"a": NaN}' '{"a": 1,}' $'{"a": "\xff"}'; do
    k=$((k + 1)); d="$T/$label-bad$k"; mkdir -p "$d"; printf '%s' "$body" > "$d/settings.json"; cp "$d/settings.json" "$T/b.json"
    run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"; rc=$?
    if [ "$rc" = 0 ]; then bad "$label: went on with an unusable settings file: $body"
    elif cmp -s "$d/settings.json" "$T/b.json" && [ "$(baks "$d")" = 0 ] && [ ! -e "$d/state" ] && ! grep -q Traceback "$T/err"; then
      ok "$label: unusable settings ($(printf '%s' "$body" | LC_ALL=C tr '\n\377' ' ?')) -> stopped, nothing written"
    else bad "$label: unusable settings ($body) were touched"; fi
    echo "bad$k $rc" >> "$OUTCOMES.$label"
  done
  # a byte-order mark is read past, the same way by both
  d="$T/$label-bom"; mkdir -p "$d"; printf '\357\273\277{"model":"opus"}' > "$d/settings.json"
  run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state" && [ "$(ours "$d/settings.json")" = "$(expect_ours)" ] && ok "$label: a file with a byte-order mark -> hook added" || bad "$label: a byte-order mark stopped it ($(cat "$T/err"))"
  # read-only file, read-only folder: a plain message, no change, no traceback
  d="$T/$label-ro"; mkdir -p "$d"; echo '{"model":"opus"}' > "$d/settings.json"; chmod 444 "$d/settings.json"
  if run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"; then bad "$label: wrote over a read-only settings file"
  else [ "$(cat "$d/settings.json")" = '{"model":"opus"}' ] && grep -q "didn't change it" "$T/err" && ! grep -q Traceback "$T/err" && ok "$label: read-only file -> plain message, unchanged" || bad "$label: read-only file: $(cat "$T/err")"; fi
  chmod 644 "$d/settings.json"
  d="$T/$label-rodir"; mkdir -p "$d"; echo '{"model":"opus"}' > "$d/settings.json"; chmod 555 "$d"
  if run "$@" "$d/settings.json" "$CMD" "$HF" "$T/$label-rodir-state"; then bad "$label: wrote into a read-only folder"
  else [ "$(cat "$d/settings.json")" = '{"model":"opus"}' ] && grep -q "didn't change it" "$T/err" && ! grep -q Traceback "$T/err" && ok "$label: read-only folder -> plain message, unchanged" || bad "$label: read-only folder: $(cat "$T/err")"; fi
  chmod 755 "$d"
  # a settings file that is a link stays a link
  d="$T/$label-link"; mkdir -p "$d/dot"; echo '{"model":"opus"}' > "$d/dot/settings.json"; ln -s "$d/dot/settings.json" "$d/settings.json"
  run "$@" "$d/settings.json" "$CMD" "$HF" "$d/state"
  [ -L "$d/settings.json" ] && [ "$(ours "$d/dot/settings.json")" = "$(expect_ours)" ] && ok "$label: a linked settings file stays a link" || bad "$label: a linked settings file was replaced"
}
merge_cases "install.sh helper" python3 -I "$PY"
if command -v pwsh >/dev/null 2>&1; then
  merge_cases "install.ps1 helper" pwsh -NoProfile -NonInteractive -File "$PS"
  cmp -s "$OUTCOMES.install.sh helper" "$OUTCOMES.install.ps1 helper" && ok "both helpers end the same way on every unusable file" || bad "the helpers differ on an unusable file: $(diff "$OUTCOMES.install.sh helper" "$OUTCOMES.install.ps1 helper" | tr '\n' ' ')"
  errs=$(pwsh -NoProfile -NonInteractive -c '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "install.ps1"), [ref]$null, [ref]$e); $e.Count')
  [ "$errs" = 0 ] && ok "install.ps1 parses" || bad "install.ps1 has $errs parse errors"
else
  echo "SKIPPED  install.ps1's settings merge: pwsh is not installed here -- NOT PROVEN on this machine"
  [ -z "${CI:-}" ] || bad "pwsh missing in CI: install.ps1's settings merge went untested"
fi

# install.ps1 adds the guard on every install and update (Install-MakeItSkills runs on both paths), with
# git-bash running it, keeps the user's choice across updates, and stops when the helper refuses
fn=$(awk '/^function Install-MakeItSkills/,/^}/' install.ps1)
for want in 'add-no-force-push-hook.ps1' 'no-force-push.sh' 'CLAUDE_CODE_GIT_BASH_PATH' 'if ($LASTEXITCODE -ne 0) {' 'force-push-guard.state' 'MAKEIT_FORCE_PUSH_GUARD' 'in every project on this computer' 'To remove it:' '[ -f "$0" ] || exit 0; exec "$BASH" "$0"'; do
  case $fn in *"$want"*) ok "install.ps1's Install-MakeItSkills has: $want" ;; *) bad "install.ps1's Install-MakeItSkills lacks: $want" ;; esac
done
grep -q 'Install-MakeItSkills \$tempState' install.ps1 && ok "install.ps1's update path runs Install-MakeItSkills" || bad "install.ps1's update path skips Install-MakeItSkills"
grep -qF -- '--remove-force-push-guard' README.md && grep -qF 'every project on' README.md && ok "README says what the guard does, where, and how to remove it" || bad "README lacks the guard's removal"

# --- Part 4: install.sh against a temp HOME --------------------------------------------------------
H="$T/home"; mkdir -p "$H/.claude"
echo '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/x/stop"}]}]}}' > "$H/.claude/settings.json"
if HOME="$H" bash install.sh >"$T/i1" 2>&1; then
  hc=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([h["command"] for e in d["hooks"]["PreToolUse"] for h in e["hooks"]][0])' "$H/.claude/settings.json")
  case $hc in *"$H/.claude/make-it/hooks/no-force-push.sh"*) ok "install.sh: settings point at the installed hook" ;; *) bad "install.sh: settings don't point at the installed hook" ;; esac
  printf '%s' "$(payload 'git push --force')" | sh -c "$hc" 2>/dev/null; [ $? = 2 ] && ok "install.sh: the command written to settings runs the hook and refuses a force push" || bad "install.sh: the written command doesn't refuse a force push"
  grep -q 'in every project on this computer' "$T/i1" && grep -qF -- '--remove-force-push-guard' "$T/i1" && ok "install.sh: says it applies to every project and how to remove it" || bad "install.sh: didn't say where it applies or how to remove it"
  HOME="$H" bash install.sh >"$T/i2" 2>&1
  [ "$(baks "$H/.claude")" = 1 ] && grep -q 'already' "$T/i2" && ok "install.sh: a second install adds nothing" || bad "install.sh: a second install changed settings again"
  HOME="$H" bash install.sh --remove-force-push-guard >"$T/i3" 2>&1
  [ "$(ours "$H/.claude/settings.json")" = "[]" ] && HOME="$H" bash install.sh >"$T/i4" 2>&1 && [ "$(ours "$H/.claude/settings.json")" = "[]" ] && grep -q 'stays off' "$T/i4" \
    && ok "install.sh: removed with --remove-force-push-guard, and an update (folder replaced) keeps it removed" || bad "install.sh: a removed guard came back on update"
  HOME="$H" bash install.sh --add-force-push-guard >"$T/i5" 2>&1; [ "$(ours "$H/.claude/settings.json")" != "[]" ] && ok "install.sh: --add-force-push-guard brings it back" || bad "install.sh: --add-force-push-guard didn't"
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["model"]=="opus" and d["hooks"]["Stop"]' "$H/.claude/settings.json" && ok "install.sh: the user's settings survive" || bad "install.sh: the user's settings were lost"
else bad "install.sh failed: $(tail -5 "$T/i1")"; fi
# the written command, in a HOME with a space, a quote and a $: runs the hook when it is there; when the hook file
# is gone (make-it removed), everything runs (the guard is off, by design); when the hook is broken, it blocks
H4="$T/o'brien \$HOME home"; mkdir -p "$H4/.claude"
if HOME="$H4" bash install.sh >"$T/i8" 2>&1; then
  hc=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));h=[h for e in d["hooks"]["PreToolUse"] for h in e["hooks"]][0];assert h.get("onFailure")=="block";print(h["command"])' "$H4/.claude/settings.json") \
    && ok "install.sh: the entry sets onFailure: block" || bad "install.sh: the entry doesn't set onFailure: block"
  hf="$H4/.claude/make-it/hooks/no-force-push.sh"
  printf '%s' "$(payload 'git push --force')" | sh -c "$hc" 2>/dev/null; [ $? = 2 ] && ok "odd HOME: the written command refuses a force push" || bad "odd HOME: the written command doesn't refuse a force push"
  printf '%s' "$(payload 'git status')" | sh -c "$hc" 2>/dev/null && ok "odd HOME: a plain command runs" || bad "odd HOME: a plain command was blocked"
  mv "$hf" "$hf.gone"
  for c in 'git status' 'git push --force'; do
    printf '%s' "$(payload "$c")" | sh -c "$hc" 2>/dev/null && ok "hook file gone: '$c' runs (the guard is off, by design)" || bad "hook file gone: '$c' was blocked"
  done
  echo 'if then fi (' > "$hf"
  printf '%s' "$(payload 'git status')" | sh -c "$hc" 2>/dev/null; rc=$?; [ "$rc" != 0 ] && ok "a broken hook file blocks (exit $rc)" || bad "a broken hook file let the command through"
  mv "$hf.gone" "$hf"
else bad "install.sh failed in an odd HOME: $(tail -3 "$T/i8")"; fi
for want in 'If the hook file is gone' ; do
  grep -qF "$want" "$HOOK" && ok "the hook's header says what happens when it is gone" || bad "the hook's header doesn't say what happens when it is gone"
  grep -qF 'turns the guard off' README.md && ok "README says removing make-it turns the guard off" || bad "README doesn't say what removing make-it does"
done

# malformed settings: install.sh says so and leaves the file alone
H2="$T/home2"; mkdir -p "$H2/.claude"; printf '{"model": ' > "$H2/.claude/settings.json"
if HOME="$H2" bash install.sh >"$T/i6" 2>&1; then bad "install.sh: finished quietly over a malformed settings file"
else [ "$(cat "$H2/.claude/settings.json")" = '{"model": ' ] && grep -q "settings.json" "$T/i6" && ok "install.sh: malformed settings -> stops, says so, file untouched" || bad "install.sh: malformed settings were touched or not reported"; fi
# no working python3: the skills install, the guard is skipped with a plain line and a note in the summary, no hang
H3="$T/home3"; mkdir -p "$H3/.claude" "$T/nopy"
for tool in bash sh cp mv rm mkdir ls cat sed awk tr dirname basename diff mktemp find sort xargs head tail grep wc uname cut shasum sha256sum git date env printf chmod ln readlink stat od python3-not; do
  w=$(command -v "$tool" 2>/dev/null) && [ -n "$w" ] && ln -sf "$w" "$T/nopy/$tool"
done
if PATH="$T/nopy" HOME="$H3" bash install.sh >"$T/i7" 2>&1; then
  [ ! -e "$H3/.claude/settings.json" ] && [ -f "$H3/.claude/make-it/hooks/no-force-push.sh" ] && grep -q "1 step not done" "$T/i7" && [ "$(grep -c 'Python 3' "$T/i7")" -ge 2 ] \
    && ok "install.sh: no python3 -> skills installed, guard skipped, said twice (the line and the summary)" || bad "install.sh: no python3: $(tail -4 "$T/i7")"
else bad "install.sh failed without python3: $(tail -4 "$T/i7")"; fi

[ "$fail" = 0 ] && echo "PASS test-no-force-push" || echo "FAILED test-no-force-push"
exit $fail
