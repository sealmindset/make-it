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
# a long command is read in time (a big heredoc commit message that mentions push)
big="git commit -F - <<'EOF'
$(for _ in $(seq 1 3000); do echo 'this line mentions git push --force in the message body'; done)
EOF"
s=$(date +%s)
run_hook "$(payload "$big")"; rc=$?
e=$(( $(date +%s) - s ))
[ "$rc" = 0 ] && [ "$e" -lt 20 ] && ok "a 160 KB command that only mentions a force push is allowed in ${e}s" || bad "a long command: exit $rc after ${e}s"

# --- Part 2: the settings merge (install.sh) ----------------------------------------------------
CMD="bash '/home/u/.claude/make-it/hooks/no-force-push.sh'"
count_ours() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[]) if "make-it/hooks/no-force-push.sh" in h.get("command","")))' "$1"; }
baks() { ls "$1"/settings.json.bak-* 2>/dev/null | wc -l | tr -d ' '; }
merge_cases() {  # $1 = label, $2... = the helper's command line, given the settings path last
  local label=$1; shift
  local d
  # no file: created with only the hook, no backup
  d="$T/$label-none"; mkdir -p "$d"
  if "$@" "$d/settings.json" "$CMD" >/dev/null 2>&1 && [ "$(count_ours "$d/settings.json")" = 1 ] && [ "$(baks "$d")" = 0 ]; then
    ok "$label: no settings file -> created with the hook, no backup"; else bad "$label: no settings file"; fi
  # empty file: the hook added, the empty file backed up
  d="$T/$label-empty"; mkdir -p "$d"; : > "$d/settings.json"
  if "$@" "$d/settings.json" "$CMD" >/dev/null 2>&1 && [ "$(count_ours "$d/settings.json")" = 1 ] && [ "$(baks "$d")" = 1 ]; then
    ok "$label: empty settings file -> hook added, backup kept"; else bad "$label: empty settings file"; fi
  # unrelated settings and hooks: all kept, ours appended once, a backup equal to the original
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
  if "$@" "$d/settings.json" "$CMD" >/dev/null 2>&1; then
    python3 - "$T/orig.json" "$d/settings.json" "$CMD" <<'PYEOF' && ok "$label: existing settings and hooks kept, the hook appended once" || bad "$label: existing settings were changed"
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
added = b["hooks"]["PreToolUse"].pop()
assert added == {"matcher": "Bash", "hooks": [{"type": "command", "command": sys.argv[3]}]}, added
assert a == b, (a, b)
PYEOF
    [ "$(baks "$d")" = 1 ] && cmp -s "$(ls "$d"/settings.json.bak-*)" "$T/orig.json" && ok "$label: backup holds the original bytes" || bad "$label: no exact backup"
    # idempotent: a second run changes nothing and makes no second backup
    cp "$d/settings.json" "$T/after1.json"
    "$@" "$d/settings.json" "$CMD" >/dev/null 2>&1
    cmp -s "$d/settings.json" "$T/after1.json" && [ "$(baks "$d")" = 1 ] && ok "$label: a second run adds nothing and backs up nothing" || bad "$label: a second run changed the file or backed it up again"
  else bad "$label: merge into existing settings failed"; fi
  # an identical hook already there (another path to the same script): left alone
  d="$T/$label-same"; mkdir -p "$d"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash /old/home/.claude/make-it/hooks/no-force-push.sh"}]}]}}' > "$d/settings.json"
  cp "$d/settings.json" "$T/same.json"
  "$@" "$d/settings.json" "$CMD" >/dev/null 2>&1
  cmp -s "$d/settings.json" "$T/same.json" && [ "$(baks "$d")" = 0 ] && ok "$label: the hook already there -> nothing written" || bad "$label: an existing hook was added again or the file rewritten"
  # malformed JSON, or a shape it can't merge into: stops, writes nothing, backs up nothing
  local k=0
  for body in '{"model": "opus",' '[1,2]' '{"hooks": []}' '{"hooks": {"PreToolUse": {}}}'; do
    k=$((k + 1)); d="$T/$label-bad$k"; mkdir -p "$d"; printf '%s' "$body" > "$d/settings.json"
    if "$@" "$d/settings.json" "$CMD" >/dev/null 2>&1; then bad "$label: went on with an unusable settings file: $body"
    elif [ "$(cat "$d/settings.json")" = "$body" ] && [ "$(baks "$d")" = 0 ] && [ "$(ls -A "$d" | wc -l | tr -d ' ')" = 1 ]; then
      ok "$label: unusable settings ($body) -> stopped, nothing written"
    else bad "$label: unusable settings ($body) were touched"; fi
  done
}
merge_cases "install.sh helper" python3 -I "$PY"
# a settings file that is a link (a dotfiles setup) stays a link; the file it points to gets the hook
d="$T/link"; mkdir -p "$d/dot"; echo '{"model":"opus"}' > "$d/dot/settings.json"; ln -s "$d/dot/settings.json" "$d/settings.json"
python3 -I "$PY" "$d/settings.json" "$CMD" >/dev/null 2>&1
[ -L "$d/settings.json" ] && [ "$(count_ours "$d/dot/settings.json")" = 1 ] && ok "install.sh helper: a linked settings file stays a link" || bad "install.sh helper: a linked settings file was replaced"

# --- Part 3: install.ps1's helper -----------------------------------------------------------------
if command -v pwsh >/dev/null 2>&1; then
  merge_cases "install.ps1 helper" pwsh -NoProfile -NonInteractive -File "$PS"
  errs=$(pwsh -NoProfile -NonInteractive -c '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "install.ps1"), [ref]$null, [ref]$e); $e.Count')
  [ "$errs" = 0 ] && ok "install.ps1 parses" || bad "install.ps1 has $errs parse errors"
else
  echo "SKIPPED  Part 3 (install.ps1's settings merge): pwsh is not installed here -- NOT PROVEN on this machine"
  [ -z "${CI:-}" ] || bad "pwsh missing in CI: install.ps1's settings merge went untested"
fi

# install.ps1 adds the guard on every install and update (Install-MakeItSkills runs on both paths), with
# git-bash running it, and stops when the helper refuses
fn=$(awk '/^function Install-MakeItSkills/,/^}/' install.ps1)
for want in 'add-no-force-push-hook.ps1' 'no-force-push.sh' 'CLAUDE_CODE_GIT_BASH_PATH' 'if ($LASTEXITCODE -ne 0) {'; do
  case $fn in *"$want"*) ok "install.ps1's Install-MakeItSkills has: $want" ;; *) bad "install.ps1's Install-MakeItSkills lacks: $want" ;; esac
done
grep -q 'Install-MakeItSkills \$tempState' install.ps1 && ok "install.ps1's update path runs Install-MakeItSkills" || bad "install.ps1's update path skips Install-MakeItSkills"

# --- Part 4: install.sh against a temp HOME, twice -------------------------------------------------
H="$T/home"; mkdir -p "$H/.claude"
echo '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/x/stop"}]}]}}' > "$H/.claude/settings.json"
if HOME="$H" bash install.sh >"$T/i1" 2>&1; then
  [ "$(count_ours "$H/.claude/settings.json")" = 1 ] && [ -f "$H/.claude/make-it/hooks/no-force-push.sh" ] && ok "install.sh: the hook is installed and in settings.json" || bad "install.sh: hook missing after install"
  grep -q "$H/.claude/make-it/hooks/no-force-push.sh" "$H/.claude/settings.json" && ok "install.sh: settings point at the installed hook" || bad "install.sh: settings don't point at the installed hook"
  hc=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([h["command"] for e in d["hooks"]["PreToolUse"] for h in e["hooks"]][0])' "$H/.claude/settings.json")
  printf '%s' "$(payload 'git push --force')" | sh -c "$hc" 2>/dev/null; [ $? = 2 ] && ok "install.sh: the command written to settings runs the hook and refuses a force push" || bad "install.sh: the written command doesn't refuse a force push"
  HOME="$H" bash install.sh >"$T/i2" 2>&1
  [ "$(count_ours "$H/.claude/settings.json")" = 1 ] && [ "$(baks "$H/.claude")" = 1 ] && ok "install.sh: a second install adds nothing" || bad "install.sh: a second install added the hook or a backup again"
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["model"]=="opus" and d["hooks"]["Stop"]' "$H/.claude/settings.json" && ok "install.sh: the user's settings survive" || bad "install.sh: the user's settings were lost"
else bad "install.sh failed: $(tail -5 "$T/i1")"; fi
# malformed settings: install.sh says so and leaves the file alone
H2="$T/home2"; mkdir -p "$H2/.claude"; printf '{"model": ' > "$H2/.claude/settings.json"
if HOME="$H2" bash install.sh >"$T/i3" 2>&1; then bad "install.sh: finished quietly over a malformed settings file"
else [ "$(cat "$H2/.claude/settings.json")" = '{"model": ' ] && grep -q "settings.json" "$T/i3" && ok "install.sh: malformed settings -> stops, says so, file untouched" || bad "install.sh: malformed settings were touched or not reported"; fi

[ "$fail" = 0 ] && echo "PASS test-no-force-push" || echo "FAILED test-no-force-push"
exit $fail
