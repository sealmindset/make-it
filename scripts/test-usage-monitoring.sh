#!/usr/bin/env bash
# E15-S1: the administrators' guide to Claude Code's own usage reporting, and the script that renders its settings.
# Contract these checks pin (the change must satisfy it):
#   - .claude/make-it/references/usage-monitoring.md exists; the settings block under "## 1. Switching it on" is valid
#     JSON, turns the reporting on, and leaves every content flag off ("0"; raw bodies unset), with placeholders only.
#   - The statements that matter are there whole: make-it sends nothing; what is not sent; the skill event does not
#     tell you which make-it skill ran; third-party providers; tracking alone does not prove value; the notice text.
#   - The guide never turns on prompt, raw-body or tool-detail logging, except tool details in the one-shell calibration.
#   - Only placeholder or documentation hosts appear in the guide; the README links to it outside Version History.
#   - render-managed-settings.py: valid JSON in gives a plist (plutil -lint when plutil exists) and a registry file;
#     malformed JSON, an unfilled placeholder and a content flag switched on are refused, naming the key and never the
#     value; no token value appears on stdout or stderr, whatever the outcome.
# Every check on the guide is also run against a reversed copy (a control), which must fail.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
T="$(mktemp -d)"; ERRF="$T/stderr"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$T"' EXIT

G=.claude/make-it/references/usage-monitoring.md
R=.claude/make-it/scripts/render-managed-settings.py
flat() { tr '\n' ' ' | tr -s ' '; }

# ---- checks over a guide file (run on the real guide, then on reversed copies) ----
settings_ok() {  # the first json block in section 1 is valid, turns reporting on, content flags off, placeholders
  python3 -I - "$1" <<'PY' 2>/dev/null
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^## 1\. Switching it on\n(.*?)(?=^## )", text, re.S | re.M)
b = m and re.search(r"```json\n(.*?)```", m.group(1), re.S)
env = json.loads(b.group(1))["env"]
assert env["CLAUDE_CODE_ENABLE_TELEMETRY"] == "1"
for k in ("OTEL_LOG_USER_PROMPTS", "OTEL_LOG_ASSISTANT_RESPONSES", "OTEL_LOG_TOOL_DETAILS", "OTEL_LOG_TOOL_CONTENT"):
    assert env[k] == "0", k
assert "OTEL_LOG_RAW_API_BODIES" not in env
assert env["OTEL_METRICS_INCLUDE_REPOSITORY"] == "true" and env["OTEL_METRICS_INCLUDE_VERSION"] == "true"
assert "<collector-host>" in env["OTEL_EXPORTER_OTLP_ENDPOINT"]
assert "<ingest-token>" in env["OTEL_EXPORTER_OTLP_HEADERS"]
PY
}
pinned() { flat < "$1" | grep -qF -- "$2"; }
in_section() {  # $1 file, $2 exact "## " heading, $3 text that must be inside that section
  awk -v h="$2" '/^## /{on=($0==h)} on' "$1" | flat | grep -qF -- "$3"; }
content_on_only_in_calibration() {  # tool details on only under the calibration heading; prompts/raw bodies never on
  ! gq -E 'OTEL_LOG_USER_PROMPTS(=|": ")"?1|OTEL_LOG_RAW_API_BODIES(=|": ")' "$1" || return 1
  ! awk '/^#/{cal=($0 ~ /^### Calibrating `plugin_id_hash`, once/)} !cal && /OTEL_LOG_TOOL_DETAILS(=|": ")"?1/' "$1" | gq . || return 1
}
hosts_generic() {  # every URL host is the documentation site, the Anthropic GitHub, or a placeholder
  ! grep -oE 'https?://[^/ )`"]+' "$1" | grep -vE '^https://code\.claude\.com$|^https://github\.com$|^https?://<[a-z-]+>' | gq .
}

S_NOTHING='make-it itself sends nothing.'
S_NOT_SENT="By default, Claude Code does not send what people type, Claude's replies, the commands Claude runs, the contents of files, or tool inputs such as file paths."
S_SKILL='The skill event does not tell you which make-it skill ran.'
S_3P="On Amazon Bedrock, Google Cloud's Agent Platform or Microsoft Foundry, Claude Code skips server-managed settings, and its events carry no \`user.email\`: only the anonymous \`user.id\` and the \`session.id\`."
S_VALUE='Tracking alone does not prove value.'
S_BEFORE_AFTER='Proving value, like time saved, needs a before-and-after measurement.'
H_NOTICE='## 10. A notice for your people'
S_NOTICE="It does not record what you type, Claude's replies, your code or files, or the commands Claude runs."
H_ADOPT='## 11. Counting adoption across your repositories'
S_ADOPT="Per-skill counts come from make-it's ledger in each repository, not from the usage reporting."
H_CAL='### Calibrating `plugin_id_hash`, once'
S_CAL='one shell, one time'

# 1. the guide and its settings block
check "the guide exists at $G" '[ -f "$G" ]'
check "the settings block is valid JSON, turns reporting on, and leaves every content flag off" 'settings_ok "$G"'

# 2. the statements that matter, whole
for s in "$S_NOTHING" "$S_NOT_SENT" "$S_SKILL" "$S_3P" "$S_VALUE" "$S_BEFORE_AFTER"; do
  check "the guide says: $s" 'pinned "$G" "$s"'
done
check "the notice section says what is not recorded" 'in_section "$G" "$H_NOTICE" "$S_NOTICE"'
check "the notice section says make-it sends nothing" 'in_section "$G" "$H_NOTICE" "$S_NOTHING"'
check "the adoption placeholder says per-skill counts come from the ledger" 'in_section "$G" "$H_ADOPT" "$S_ADOPT"'
check "the calibration is one shell, one time" 'awk -v h="$H_CAL" "/^#/{on=(\$0==h)} on" "$G" | flat | grep -qF "$S_CAL"'
check "no content flag is turned on outside the calibration" 'content_on_only_in_calibration "$G"'
check "every URL host in the guide is the documentation or a placeholder" 'hosts_generic "$G"'
check "the README links to the guide before Version History" \
  'awk "/^## Version History/{exit} {print}" README.md | gq -F "references/usage-monitoring.md"'

# 3. controls: each check above fails on a copy with that one thing reversed
ctl() {  # $1 name, $2 perl substitution, $3 the check (uses $C)
  C="$T/ctl.md"; perl -0pe "$2" "$G" > "$C"
  if eval "$3"; then bad "control: $1 (the check passed on a reversed copy)"; else ok "control: $1"; fi; }
ctl "a content flag switched on"   's/"OTEL_LOG_TOOL_DETAILS": "0"/"OTEL_LOG_TOOL_DETAILS": "1"/' 'settings_ok "$C"'
ctl "raw bodies set"               's/("OTEL_LOG_TOOL_CONTENT": "0")/$1,\n    "OTEL_LOG_RAW_API_BODIES": "1"/' 'settings_ok "$C"'
ctl "the settings block broken"    's/("CLAUDE_CODE_ENABLE_TELEMETRY": "1"),/$1/' 'settings_ok "$C"'
ctl "make-it sends something"      's/make-it itself sends nothing\./make-it itself sends a summary./g' 'pinned "$C" "$S_NOTHING"'
ctl "what is not sent reversed"    "s/Claude Code does not send what people type/Claude Code sends what people type/" 'pinned "$C" "$S_NOT_SENT"'
ctl "the skill event names skills" 's/The skill event does not tell you/The skill event does tell you/' 'pinned "$C" "$S_SKILL"'
ctl "third parties carry email"    's/its events carry no `user.email`/its events carry `user.email`/' 'pinned "$C" "$S_3P"'
ctl "tracking proves value"        's/Tracking alone does not prove value\./Tracking alone proves value./' 'pinned "$C" "$S_VALUE"'
ctl "notice says it records code"  's/It does not record what you type/It records what you type/' 'in_section "$C" "$H_NOTICE" "$S_NOTICE"'
ctl "prompt logging turned on"     's/("OTEL_LOG_USER_PROMPTS": )"0"/$1"1"/' 'content_on_only_in_calibration "$C"'
ctl "tool details on outside the calibration" 's/^## 2\./`OTEL_LOG_TOOL_DETAILS=1`\n\n## 2./m' 'content_on_only_in_calibration "$C"'
ctl "a real host in the guide"     's/<collector-host>/collector.internal.example.org/g' 'hosts_generic "$C"'
ctl "the calibration not one-shell" 's/one shell, one time/in every shell/' 'awk -v h="$H_CAL" "/^#/{on=(\$0==h)} on" "$C" | flat | grep -qF "$S_CAL"'

# 4. the render/validate script
TOKEN='tok-SENTINEL-4f9a2c'
good="$T/good.json"
cat > "$good" <<JSON
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://collector.test:4318",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer $TOKEN",
    "OTEL_LOG_USER_PROMPTS": "0",
    "OTEL_LOG_TOOL_DETAILS": "0"
  },
  "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "python3 -I \"\$HOME/x.py\" hook", "timeout": 10 } ] } ] }
}
JSON
run() { local o="$1"; shift; set +e; python3 -I "$R" "$@" > "$T/$o.out" 2> "$T/$o.err"; echo $? > "$T/$o.rc"; set -e; }
rc() { cat "$T/$1.rc"; }
no_token() { ! cat "$T/$1.out" "$T/$1.err" | gq -F "$TOKEN"; }

check "the render script exists at $R" '[ -f "$R" ]'
run good "$good" --out "$T/o1"
check "valid JSON in: exit 0" '[ "$(rc good)" = 0 ]'
check "valid JSON in: a plist and a registry file out" '[ -s "$T/o1/com.anthropic.claudecode.plist" ] && [ -s "$T/o1/ClaudeCode-Settings.reg" ]'
if command -v plutil >/dev/null 2>&1; then
  check "plutil -lint accepts the plist" 'plutil -lint "$T/o1/com.anthropic.claudecode.plist" >/dev/null'
else
  echo "SKIP plutil -lint: plutil is not on this machine (Linux CI). Only the Python plistlib read-back below covers the plist here."
fi
check "the plist reads back to the same settings" \
  'python3 -I -c "import json,plistlib,sys; sys.exit(plistlib.load(open(sys.argv[1],\"rb\"))!=json.load(open(sys.argv[2])))" "$T/o1/com.anthropic.claudecode.plist" "$good"'
check "the registry file sets Settings under HKLM\\SOFTWARE\\Policies\\ClaudeCode, and the value reads back to the same settings" \
  'python3 -I - "$T/o1/ClaudeCode-Settings.reg" "$good" <<'"'"'PY'"'"'
import json, sys
t = open(sys.argv[1], encoding="utf-16").read().splitlines()
assert t[0] == "Windows Registry Editor Version 5.00", t[0]
assert "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\ClaudeCode]" in t
line = [l for l in t if l.startswith("\"Settings\"=")][0]
v = line[len("\"Settings\"=\""):-1].replace("\\\"", "\"").replace("\\\\", "\\")
assert json.loads(v) == json.load(open(sys.argv[2]))
PY'
check "valid run: no token value on stdout or stderr" 'no_token good'

printf '{"env": {"OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer %s",}' "$TOKEN" > "$T/bad.json"
run bad "$T/bad.json" --out "$T/o2"
check "malformed JSON is refused (exit 1) and nothing is written" '[ "$(rc bad)" = 1 ] && [ ! -e "$T/o2/com.anthropic.claudecode.plist" ]'
check "malformed run: no token value in the output" 'no_token bad'

sed "s|https://collector.test:4318|https://<collector-host>:4318|" "$good" > "$T/ph.json"
run ph "$T/ph.json" --out "$T/o3"
check "an unfilled placeholder is refused, naming the key" '[ "$(rc ph)" = 1 ] && gq -F "env.OTEL_EXPORTER_OTLP_ENDPOINT" "$T/ph.err"'
check "the placeholder refusal does not print the value" '! gq -F "collector-host" "$T/ph.err" && no_token ph'

sed "s|\"OTEL_LOG_TOOL_DETAILS\": \"0\"|\"OTEL_LOG_TOOL_DETAILS\": \"1\"|" "$good" > "$T/on.json"
run on "$T/on.json" --out "$T/o4"
check "a content flag switched on is refused, naming the key" '[ "$(rc on)" = 1 ] && gq -F "env.OTEL_LOG_TOOL_DETAILS" "$T/on.err" && [ ! -e "$T/o4/com.anthropic.claudecode.plist" ]'
check "the content-flag refusal prints no token" 'no_token on'
sed "s|\"OTEL_LOG_USER_PROMPTS\": \"0\"|\"OTEL_LOG_RAW_API_BODIES\": \"file:/tmp/x\"|" "$good" > "$T/raw.json"
run raw "$T/raw.json" --out "$T/o5"
check "raw-body logging set is refused" '[ "$(rc raw)" = 1 ] && gq -F "env.OTEL_LOG_RAW_API_BODIES" "$T/raw.err"'
run ack "$T/on.json" --out "$T/o6" --allow-content-flags
check "with --allow-content-flags the same file renders, and says so" '[ "$(rc ack)" = 0 ] && gq -F "content" "$T/ack.err" && no_token ack'
# a control for the token check itself: it must catch a token that does reach the output
echo "$TOKEN" >> "$T/good.err"
check "control: the token check catches a token in the output" '! no_token good'

# the whole run's stderr: a helper error or a bad regex must not read as a pass
exec 2>&4
check "nothing unexpected on stderr" '[ ! -s "$ERRF" ]'
exit $fail
