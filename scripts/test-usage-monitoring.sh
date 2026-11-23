#!/usr/bin/env bash
# E15-S1: the administrators' guide to Claude Code's own usage reporting, and the script that renders its settings.
# Contract these checks pin (the change must satisfy it):
#   - .claude/make-it/references/usage-monitoring.md exists; the settings block under "## 1. Switching it on" is valid
#     JSON, turns the reporting on, and locks every content flag off ("0", raw bodies included), with placeholders only.
#   - The statements that matter are there whole: make-it sends nothing; what is not sent; the skill event does not
#     say which make-it skill ran (it is sent by default, on the cost counters) and that a skill name is not proof of
#     make-it; third-party providers; tracking alone does not prove value; the notice text; where per-skill counts come from.
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
for k in ("OTEL_LOG_USER_PROMPTS", "OTEL_LOG_ASSISTANT_RESPONSES", "OTEL_LOG_TOOL_DETAILS", "OTEL_LOG_TOOL_CONTENT",
          "OTEL_LOG_RAW_API_BODIES"):
    assert env[k] == "0", k
assert env["OTEL_METRICS_INCLUDE_REPOSITORY"] == "true" and env["OTEL_METRICS_INCLUDE_VERSION"] == "true"
assert "<collector-host>" in env["OTEL_EXPORTER_OTLP_ENDPOINT"]
assert "<ingest-token>" in env["OTEL_EXPORTER_OTLP_HEADERS"]
PY
}
pinned() { flat < "$1" | grep -qF -- "$2"; }
in_section() {  # $1 file, $2 exact "## " heading, $3 text that must be inside that section
  awk -v h="$2" '/^## /{on=($0==h)} on' "$1" | sed 's/^> \{0,1\}//' | flat | grep -qF -- "$3"; }
content_on_only_in_calibration() {  # tool details on only under the calibration heading; prompts/raw bodies never on
  ! gq -E 'OTEL_LOG_USER_PROMPTS(=|": ")"?1|OTEL_LOG_RAW_API_BODIES(=|": ")"?[^0"]' "$1" || return 1
  ! awk '/^#/{cal=($0 ~ /^### Calibrating `plugin_id_hash`, once/)} !cal && /OTEL_LOG_TOOL_DETAILS(=|": ")"?1/' "$1" | gq . || return 1
}
hosts_generic() {  # every URL host is the documentation site, the Anthropic GitHub, or a placeholder
  ! grep -oE 'https?://[^/ )`"]+' "$1" | grep -vE '^https://code\.claude\.com$|^https://github\.com$|^https?://<[a-z-]+>' | gq .
}

S_NOTHING='make-it itself sends nothing.'
S_NOT_SENT="By default, Claude Code does not send what people type, Claude's replies, the commands Claude runs, the contents of files, or tool inputs such as file paths."
S_SKILL='Which make-it skill ran, and what it cost, is sent by default.'
S_SKILL_EVENT='The `skill_activated` event does not name it: it reports `custom_skill`.'
S_COLLIDE="A skill name is not proof of make-it: anyone's own command with the same name looks the same."
S_OBSERVED='observed with the console exporter on Claude Code v2.1.330, with every content flag off'
S_3P="On Amazon Bedrock, Google Cloud's Agent Platform or Microsoft Foundry, Claude Code skips server-managed settings, and its events carry no \`user.email\`: only the anonymous \`user.id\` and the \`session.id\`."
S_VALUE='Tracking alone does not prove value.'
S_BEFORE_AFTER='Proving value, like time saved, needs a before-and-after measurement.'
H_NOTICE='## 10. A notice for your people'
S_NOTICE="It does not record what you type, Claude's replies, your code or files, or the commands Claude runs."
H_ADOPT='## 11. Counting adoption across your repositories'
S_ADOPT="Per-skill counts come from both: for make-it's standard install, the usage reporting shows who ran which command (a plugin from outside the official marketplace shows \`third-party\`), when, and what it cost; the seal history in each repository shows which sealing steps changed which app."
S_WHO='This reporting goes only to our own collector at `<collector-host>`, and only `<who can see it>` can read it.'
S_OFF='We have set Claude Code so that this content stays off.'
S_NOR='Nor does it record the paths of the files Claude reads or edits.'
S_3PNAME='For a make-it plugin from outside the official marketplace, such as the `make-it-desktop` plugin, the counters show `third-party` instead.'
S_NOTICE_MAKEIT="make-it adds no reporting of its own, but its commands run inside Claude Code, so the name of each make-it command you run is recorded with its cost."
S_NOTICE_PLAN='your Claude plan'
S_CHANGED='Skill names are sent by default on the cost and token counters and the `api_request`, `api_error` and `api_refusal` events; only the `skill_activated` and `user_prompt` events hide them.'
S_NOT_FULL='ships six skills (`guardrails`, `make-it`, `debug-it`, `nemo-it`, `handoff`, `safety`), not the full set'
S_AGG='The transform processor deletes the key and adds the look-alike points together.'
S_NOT_RUN='Not run against a live collector: test it in your own pipeline before you rely on the numbers.'
S_UNINSTALL="Removing make-it means deleting \`~/.claude/make-it\` and the make-it command files the installer copied into \`~/.claude/commands/\`; other files there are the person's own."
S_ROW_CHANGE='also change that row of the full list to "The model, the tokens and the cost of each request"'
S_INV_SAYS='prints `make-it <version>` only when the first line of a regular file (not a symlink) looks like a version'
S_NO_SETTING='The documentation names no setting for this (checked 23 November 2026).'
S_DROP_YAML='- key: skill.name action: delete'
S_NOTICE_DROPPED='make-it adds no reporting of its own, and we remove the name of each command you run before the data is stored.'
S_RAW_WHY='Raw bodies are locked, not left unset, because an unset value can be switched on from a person'"'"'s own shell or user settings, which would send full prompts, replies and code to your collector.'
S_RAW_INVESTIGATE='An organization that later needs content for an investigation makes that a deliberate change to the managed settings, by an administrator, and updates the notice to its people first.'
S_TABLE='| Who has make-it installed, and which version |'
H_ON='## 1. Switching it on'
H_MAKEIT='## 5. What it tells you about make-it'
H_CAL='### Calibrating `plugin_id_hash`, once'
S_CAL='one shell, one time'

# 1. the guide and its settings block
check "the guide exists at $G" '[ -f "$G" ]'
check "the settings block is valid JSON, turns reporting on, and leaves every content flag off" 'settings_ok "$G"'

# 2. the statements that matter, whole
for s in "$S_NOTHING" "$S_NOT_SENT" "$S_SKILL" "$S_SKILL_EVENT" "$S_COLLIDE" "$S_OBSERVED" "$S_3P" "$S_VALUE" "$S_BEFORE_AFTER"; do
  check "the guide says: $s" 'pinned "$G" "$s"'
done
check "the notice section says what is not recorded" 'in_section "$G" "$H_NOTICE" "$S_NOTICE"'
check "the notice says make-it's command names are recorded with their cost" 'in_section "$G" "$H_NOTICE" "$S_NOTICE_MAKEIT"'
check "the notice names the Claude plan" 'in_section "$G" "$H_NOTICE" "$S_NOTICE_PLAN"'
check "the notice says who can see it" 'in_section "$G" "$H_NOTICE" "$S_WHO"'
check "the notice says the content stays off" 'in_section "$G" "$H_NOTICE" "$S_OFF"'
check "the notice says file paths are not recorded" 'in_section "$G" "$H_NOTICE" "$S_NOR"'
check "the guide says a third-party plugin shows third-party on the counters" 'pinned "$G" "$S_3PNAME"'
check "section 5 opens with what changed: skill names are sent by default" 'in_section "$G" "$H_MAKEIT" "$S_CHANGED"'
check "section 5 says no client-side setting omits skill names" 'in_section "$G" "$H_MAKEIT" "$S_NO_SETTING"'
check "section 5 shows the collector step that drops skill.name" 'in_section "$G" "$H_MAKEIT" "$S_DROP_YAML"'
check "section 5 has the who-has-make-it table" 'in_section "$G" "$H_MAKEIT" "$S_TABLE"'
check "section 5 says the Desktop plugin is not the full set" 'in_section "$G" "$H_MAKEIT" "$S_NOT_FULL"'
check "section 5 says the transform processor re-aggregates" 'in_section "$G" "$H_MAKEIT" "$S_AGG"'
check "section 5 says the collector step was not run live" 'in_section "$G" "$H_MAKEIT" "$S_NOT_RUN"'
check "section 5 shows the transform delete and the aggregation" 'in_section "$G" "$H_MAKEIT" "delete_key(datapoint.attributes, \"skill.name\")" && in_section "$G" "$H_MAKEIT" "aggregate_on_attributes(\"sum\")" && in_section "$G" "$H_MAKEIT" "delete_key(log.attributes, \"skill.name\")"'
check "section 5 no longer advises summing look-alike points in the backend" '! in_section "$G" "$H_MAKEIT" "sum them in your backend"'
check "section 5 says removing make-it spares the person's own commands" 'in_section "$G" "$H_MAKEIT" "$S_UNINSTALL"'
check "section 5 says what the inventory check prints, exactly" 'in_section "$G" "$H_MAKEIT" "$S_INV_SAYS"'
check "section 11 uses the scan page's term, seal history" '! in_section "$G" "$H_ADOPT" "ledger"'
check "the notice tells an organization that removes names to change the full-list row" 'in_section "$G" "$H_NOTICE" "$S_ROW_CHANGE"'
check "the notice offers the sentence for names removed at the collector" 'in_section "$G" "$H_NOTICE" "$S_NOTICE_DROPPED"'
check "section 1 says why raw bodies are locked, not left unset" 'in_section "$G" "$H_ON" "$S_RAW_WHY"'
check "section 1 says content for an investigation is a deliberate, announced change" 'in_section "$G" "$H_ON" "$S_RAW_INVESTIGATE"'
check "the adoption section says per-skill counts come from both sources" 'in_section "$G" "$H_ADOPT" "$S_ADOPT"'
S_LINK='The adoption scan is described in [`adoption-scan.md`](adoption-scan.md).'
S_SCAN_ONLY='What the scan answers that the reporting cannot: which repositories were built with make-it, including ones nobody has opened since the reporting was switched on, and which sealing steps changed which app.'
S_REPORT_ONLY='What the reporting answers that the scan cannot: who ran which command, when, and what it cost.'
check "the adoption section links to adoption-scan.md, and that page exists" \
  'in_section "$G" "$H_ADOPT" "$S_LINK" && [ -f .claude/make-it/references/adoption-scan.md ]'
check "the adoption section says what only the scan answers" 'in_section "$G" "$H_ADOPT" "$S_SCAN_ONLY"'
check "the adoption section says what only the reporting answers" 'in_section "$G" "$H_ADOPT" "$S_REPORT_ONLY"'
check "the README names both pages" \
  'awk "/^## Version History/{exit} {print}" README.md | gq -F "references/adoption-scan.md"'
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
ctl "raw bodies switched on"       's/"OTEL_LOG_RAW_API_BODIES": "0"/"OTEL_LOG_RAW_API_BODIES": "1"/' 'settings_ok "$C"'
ctl "what changed reversed"         's/Skill names are sent by default on the cost/Skill names are not sent by default on the cost/' 'in_section "$C" "$H_MAKEIT" "$S_CHANGED"'
ctl "the Desktop plugin said to be the full set" 's/not the full set/the full set/' 'in_section "$C" "$H_MAKEIT" "$S_NOT_FULL"'
ctl "the uninstall deletes the person's commands" "s/other files there are the person's own/delete the whole folder/" 'in_section "$C" "$H_MAKEIT" "$S_UNINSTALL"'
ctl "the collector step said to be tested live" 's/Not run against a live collector:/Run against a live collector:/' 'in_section "$C" "$H_MAKEIT" "$S_NOT_RUN"'
ctl "a client-side setting claimed" 's/The documentation names no setting for this/The documentation names a setting for this/' 'in_section "$C" "$H_MAKEIT" "$S_NO_SETTING"'
ctl "the collector step removed"    's/- key: skill\.name(\s+)action: delete/- key: skill.name$1action: insert/' 'in_section "$C" "$H_MAKEIT" "$S_DROP_YAML"'
ctl "the removed-names notice reversed" 's/and we remove the name of each command/and we keep the name of each command/' 'in_section "$C" "$H_NOTICE" "$S_NOTICE_DROPPED"'
ctl "the lock's reason reversed"    's/an unset value can be switched on from/an unset value can never be switched on from/' 'in_section "$C" "$H_ON" "$S_RAW_WHY"'
ctl "investigation content made routine" 's/makes(\s+)that(\s+)a(\s+)deliberate(\s+)change/switches$1it$2on$3whenever$4needed/' 'in_section "$C" "$H_ON" "$S_RAW_INVESTIGATE"'
ctl "the settings block broken"    's/("CLAUDE_CODE_ENABLE_TELEMETRY": "1"),/$1/' 'settings_ok "$C"'
ctl "make-it sends something"      's/make-it itself sends nothing\./make-it itself sends a summary./g' 'pinned "$C" "$S_NOTHING"'
ctl "what is not sent reversed"    "s/Claude Code does not send what people type/Claude Code sends what people type/" 'pinned "$C" "$S_NOT_SENT"'
ctl "skill names said not sent"   's/and what it cost, is sent by default\./and what it cost, is not sent by default./' 'pinned "$C" "$S_SKILL"'
ctl "the skill event said to name it" 's/event does not name it:/event names it:/' 'pinned "$C" "$S_SKILL_EVENT"'
ctl "a skill name said to be proof" 's/A skill name is not proof of make-it/A skill name is proof of make-it/' 'pinned "$C" "$S_COLLIDE"'
ctl "the observation unlabelled"   's/observed(\s+)with(\s+)the(\s+)console/noticed$1with$2the$3console/gi' 'pinned "$C" "$S_OBSERVED"'
ctl "notice hides make-it command names" 's/so the name of each make-it command you run is recorded with its cost\./so nothing about make-it is recorded./' 'in_section "$C" "$H_NOTICE" "$S_NOTICE_MAKEIT"'
ctl "anyone may read it"            's/and only `<who can see it>` can(\s+>?\s*)read it\./and anyone may$1read it./' 'in_section "$C" "$H_NOTICE" "$S_WHO"'
ctl "we may turn this content on"   's/content(\s+>?\s*)stays(\s+>?\s*)off\./content$1we may turn$2on./' 'in_section "$C" "$H_NOTICE" "$S_OFF"'
ctl "file paths recorded"           's/Nor does it record the paths/It records the paths/' 'in_section "$C" "$H_NOTICE" "$S_NOR"'
ctl "third-party plugin shows the real name" 's/the counters(\s+)show `third-party` instead\./the counters$1show the real name./' 'pinned "$C" "$S_3PNAME"'
ctl "the scan link dropped"         's/The adoption scan is described(\s+)in \[/The adoption scan is not$1in [/' 'in_section "$C" "$H_ADOPT" "$S_LINK"'
ctl "the scan said to know who ran it" 's/What the scan answers that the reporting cannot:/What the scan and the reporting both answer:/' 'in_section "$C" "$H_ADOPT" "$S_SCAN_ONLY"'
ctl "the reporting said to know nothing" 's/who ran which command, when, and what it cost\./nothing about commands./' 'in_section "$C" "$H_ADOPT" "$S_REPORT_ONLY"'
ctl "adoption counts from the seal history only" 's/Per-skill counts come from both:/Per-skill counts come only from the seal history:/' 'in_section "$C" "$H_ADOPT" "$S_ADOPT"'
ctl "third parties carry email"    's/its events carry no `user.email`/its events carry `user.email`/' 'pinned "$C" "$S_3P"'
ctl "tracking proves value"        's/Tracking alone does not prove value\./Tracking alone proves value./' 'pinned "$C" "$S_VALUE"'
ctl "notice says it records code"  's/It does not record what you type/It records what you type/' 'in_section "$C" "$H_NOTICE" "$S_NOTICE"'
ctl "raw bodies dropped from the lock" 's/,\n    "OTEL_LOG_RAW_API_BODIES": "0"//' 'settings_ok "$C"'
ctl "raw bodies on in the text"    's/^## 2\./`OTEL_LOG_RAW_API_BODIES=file:\/tmp\/b`\n\n## 2./m' 'content_on_only_in_calibration "$C"'
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
for v in '""' '"false"'; do
  sed "s|\"OTEL_LOG_TOOL_DETAILS\": \"0\"|\"OTEL_LOG_TOOL_DETAILS\": $v|" "$good" > "$T/v.json"
  run v "$T/v.json" --out "$T/o7"
  check "a content flag set to $v is refused (only \"0\" counts as off)" '[ "$(rc v)" = 1 ] && gq -F "env.OTEL_LOG_TOOL_DETAILS" "$T/v.err"'
done
# every placeholder the guide itself uses is refused by the script
python3 -I -c 'import re,sys; print("\n".join(sorted(set(re.findall(r"<[^<>\n]+>", open(sys.argv[1]).read())))))' "$G" > "$T/ph.list"
check "the guide uses placeholders (the list is not empty)" '[ -s "$T/ph.list" ]'
while IFS= read -r ph; do
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["env"]["OTEL_RESOURCE_ATTRIBUTES"]="enduser.id="+sys.argv[2]; json.dump(d,open(sys.argv[3],"w"))' "$good" "$ph" "$T/gp.json"
  run gp "$T/gp.json" --out "$T/o8"
  check "the guide's placeholder $ph is refused" '[ "$(rc gp)" = 1 ] && gq -F "env.OTEL_RESOURCE_ATTRIBUTES" "$T/gp.err"'
done < "$T/ph.list"
# symlinks and file modes: the token-bearing files never land outside --out, and are always owner-only
mkdir -p "$T/o9"; : > "$T/victim"; ln -s ../victim "$T/o9/ClaudeCode-Settings.reg"
run sl "$good" --out "$T/o9"
check "a target that is a symlink is refused, and nothing is written through it" '[ "$(rc sl)" != 0 ] && [ ! -s "$T/victim" ] && no_token sl'
ln -s "$T/o1" "$T/outlink"
run sd "$good" --out "$T/outlink"
check "an --out folder that is a symlink is refused" '[ "$(rc sd)" != 0 ]'
mkdir -p "$T/o10"; : > "$T/o10/com.anthropic.claudecode.plist"; chmod 644 "$T/o10/com.anthropic.claudecode.plist"
run md "$good" --out "$T/o10"
check "an existing 0644 file is replaced by an owner-only one" \
  '[ "$(rc md)" = 0 ] && [ "$(python3 -I -c "import os,sys;print(oct(os.stat(sys.argv[1]).st_mode&0o777))" "$T/o10/com.anthropic.claudecode.plist")" = 0o600 ]'
check "the fresh files are owner-only" '[ "$(python3 -I -c "import os,sys;print(oct(os.stat(sys.argv[1]).st_mode&0o777))" "$T/o1/ClaudeCode-Settings.reg")" = 0o600 ]'
run ack "$T/on.json" --out "$T/o6" --allow-content-flags
check "with --allow-content-flags the same file renders, and says so" '[ "$(rc ack)" = 0 ] && gq -F "content" "$T/ack.err" && no_token ack'
# a control for the token check itself: it must catch a token that does reach the output
echo "$TOKEN" >> "$T/good.err"
check "control: the token check catches a token in the output" '! no_token good'

# 5. the read-only inventory check, per OS
IS=.claude/make-it/scripts/make-it-installed.sh; IP=.claude/make-it/scripts/make-it-installed.ps1
UNREAD='make-it installed (version unreadable)'
mkh() { mkdir -p "$T/$1/.claude/make-it"; }
mkh home1; printf '1.71.18\n' > "$T/home1/.claude/make-it/VERSION"
mkdir -p "$T/home2"
mkh home3; printf '1.71.18;$(touch x)\033[31m\n' > "$T/home3/.claude/make-it/VERSION"
printf 'SECRETTOKEN-4f9a2c-rootonly\n' > "$T/rootonly"
mkh home4; ln -s "$T/rootonly" "$T/home4/.claude/make-it/VERSION"
mkh home5; printf 'ghp_SECRETSHAPED1234567890abcdef\n' > "$T/home5/.claude/make-it/VERSION"
mkh home6; printf '\377\376\000\001\200binary\n' > "$T/home6/.claude/make-it/VERSION"
mkh home7; { printf '1.2.'; head -c 300 /dev/zero | tr '\0' 9; printf '\n'; } > "$T/home7/.claude/make-it/VERSION"
mkdir -p "$T/real-make-it" "$T/home8/.claude"; printf '1.71.18\n' > "$T/real-make-it/VERSION"; ln -s "$T/real-make-it" "$T/home8/.claude/make-it"
mkh home9; mkdir "$T/home9/.claude/make-it/VERSION"
mkh home10; printf '1.72.0-rc.1\n' > "$T/home10/.claude/make-it/VERSION"
snap() {  # path, mtime and size of everything under the temp root and the folder the test runs from (its own stderr
          # file excepted); Python, so it reads the same on macOS and Linux
  python3 -I -c 'import os,sys
skip=sys.argv[1]
for r in sys.argv[2:]:
    for d,_,fs in os.walk(r):
        for n in [d]+[os.path.join(d,f) for f in fs]:
            if n==skip: continue
            s=os.lstat(n); print(n, s.st_mtime_ns, s.st_size)' "$ERRF" "$T" "$PWD"; }
before="$(snap)"
inv() { case "$1" in sh) sh "$IS" "$T/$2" ;; pwsh) pwsh -NoProfile -File "$IP" -HomeDir "$T/$2" ;; esac; }
runners=sh; if command -v pwsh >/dev/null 2>&1; then runners="sh pwsh"; else
  echo "SKIP the PowerShell inventory check: pwsh is not on this machine."; fi
for R in $runners; do
  check "$R: an installed account prints make-it <version>" '[ "$(inv $R home1)" = "make-it 1.71.18" ]'
  check "$R: an account without make-it prints make-it not installed" '[ "$(inv $R home2)" = "make-it not installed" ]'
  check "$R: a VERSION line that is not a version is not printed" '[ "$(inv $R home3)" = "$UNREAD" ]'
  check "$R: a VERSION file that is a symlink is not followed" '[ "$(inv $R home4)" = "$UNREAD" ] && ! inv $R home4 | gq -F SECRETTOKEN'
  check "$R: a planted secret-shaped line is not printed" '[ "$(inv $R home5)" = "$UNREAD" ] && ! inv $R home5 | gq -F SECRETSHAPED'
  check "$R: a binary VERSION file reads as unreadable, quietly" '[ "$(inv $R home6)" = "$UNREAD" ]'
  check "$R: an over-long VERSION line reads as unreadable" '[ "$(inv $R home7)" = "$UNREAD" ]'
  check "$R: a symlinked make-it folder (dev-link.sh) is still read" '[ "$(inv $R home8)" = "make-it 1.71.18" ]'
  check "$R: a VERSION that is a folder reads as unreadable" '[ "$(inv $R home9)" = "$UNREAD" ]'
  check "$R: a pre-release version is printed" '[ "$(inv $R home10)" = "make-it 1.72.0-rc.1" ]'
done
check "sh: with no argument it reads \$HOME" '[ "$(HOME="$T/home1" sh "$IS")" = "make-it 1.71.18" ]'
check "the inventory checks changed nothing under the temp root or the folder they ran from" '[ "$(snap)" = "$before" ] && [ ! -e x ]'
check "the inventory checks contact nothing (no network command in either)" \
  '! cat "$IS" "$IP" | gq -iE "curl|wget|Invoke-WebRequest|Invoke-RestMethod|nc |ssh|http"'

# the whole run's stderr: a helper error or a bad regex must not read as a pass
exec 2>&4
check "nothing unexpected on stderr" '[ ! -s "$ERRF" ]'
exit $fail
