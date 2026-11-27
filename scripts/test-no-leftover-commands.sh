#!/usr/bin/env bash
# E04-S17: a helper (lane, reviewer) never gives its final report while a background command it started is
# still running. make-it ships a SubagentStop hook that reads only that helper's own transcript and refuses
# once, and the installers register it.
#   Part 1  the hook against hand-built transcripts, sent the way Claude Code sends a SubagentStop event
#           (a JSON object on stdin). The transcripts are the smallest made-up ones with the structure real
#           ones have: a Bash call with run_in_background, its "Command running in background with ID: <id>"
#           result, and a <task-notification> with a <status> (or a TaskStop result) when it ends.
#   Part 2  the settings merge helper against temp settings files
#   Part 3  install.sh itself, run twice against a temp HOME; install.ps1 parses and calls the same helper
# Never touches the real ~/.claude.
set -uo pipefail
cd "$(dirname "$0")/.."
HOOK=.claude/make-it/hooks/no-leftover-commands.py
HELPER=.claude/make-it/scripts/add-subagent-stop-hook.py
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MSG='You still have a background command running: %s. Stop each with TaskStop, then give your report.'

# --- Part 1: the hook ---------------------------------------------------------------------------
# A session folder laid out the way Claude Code lays it out: <project>/<session>.jsonl, and each helper's
# own transcript in <project>/<session>/subagents/agent-<agent id>.jsonl.
P="$T/projects/-proj"; S="$P/sess1"; mkdir -p "$S/subagents"; : > "$P/sess1.jsonl"
# fixture <agent id> <event>...   events: bg:<toolu>:<task id>  moved:<toolu>:<task id>  done:<task id>:<status>
#   stop:<toolu>:<task id>  note:<task id> (an interim notice with no status)  fg:<toolu>  junk  half
fixture() {
  python3 -I - "$S/subagents/agent-$1.jsonl" "${@:2}" <<'PY'
import json, sys
out, lines = sys.argv[1], []
use = lambda i, name, inp: {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": i, "name": name, "input": inp}]}}
res = lambda i, text: {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": i, "content": text}]}}
for ev in sys.argv[2:]:
    k, *a = ev.split(":")
    if k == "bg":
        lines += [use(a[0], "Bash", {"command": "sleep 600", "run_in_background": True}),
                  res(a[0], "Command running in background with ID: %s. Output is being written to: /tmp/t/%s.output" % (a[1], a[1]))]
    elif k == "moved":
        lines += [use(a[0], "Bash", {"command": "make test"}),
                  res(a[0], "Command was moved to the background (ID: %s) after running for 180s. Output is being written to: /tmp/t/%s.output" % (a[1], a[1]))]
    elif k == "fg":
        lines += [use(a[0], "Bash", {"command": "echo hi"}), res(a[0], "hi")]
    elif k == "done":
        lines.append({"type": "user", "message": {"role": "user", "content":
                      "<task-notification>\n<task-id>%s</task-id>\n<status>%s</status>\n<summary>ended</summary>\n</task-notification>" % (a[0], a[1])}})
    elif k == "note":
        lines.append({"type": "user", "message": {"role": "user", "content":
                      "<task-notification>\n<task-id>%s</task-id>\n<event>a line</event>\n</task-notification>" % a[0]}})
    elif k == "stop":
        lines += [use(a[0], "TaskStop", {"task_id": a[1]}),
                  res(a[0], json.dumps({"message": "Successfully stopped task: %s (sleep 600)" % a[1], "task_id": a[1]}))]
    elif k == "junk":
        lines.append("not json at all {")
    elif k == "half":
        lines.append('{"type": "user", "message": {"content": [{"type": "tool_res')
with open(out, "w") as f:
    for l in lines:
        f.write((l if isinstance(l, str) else json.dumps(l)) + "\n")
PY
}
# event <agent id> [stop_hook_active] [transcript path] [background_tasks json]
event() {
  python3 -I -c 'import json,sys
a, act, path, bt = sys.argv[1:5]
d = {"session_id": "sess1", "transcript_path": sys.argv[5], "cwd": "/x", "hook_event_name": "SubagentStop",
     "stop_hook_active": act == "true", "agent_id": a, "agent_type": "general-purpose",
     "agent_transcript_path": path, "last_assistant_message": "Done."}
if bt: d["background_tasks"] = json.loads(bt)
print(json.dumps(d))' "$1" "${2:-false}" "${3:-$S/subagents/agent-$1.jsonl}" "${4:-}" "$P/sess1.jsonl"
}
run() { printf '%s' "$1" | python3 -I "$HOOK" >"$T/out" 2>"$T/err"; echo $?; }
expect() { # expect <name> <exit> <stderr ids or empty> <payload>
  local rc want
  rc=$(run "$4")
  if [ -n "$3" ]; then want="$(printf "$MSG" "$3")"; else want=""; fi
  if [ "$rc" = "$2" ] && [ "$(cat "$T/err")" = "$want" ] && [ ! -s "$T/out" ]; then ok "$1"
  else bad "$1 (exit $rc, stderr: $(head -c 300 "$T/err"), stdout: $(head -c 100 "$T/out"))"; fi
}

fixture run1 fg:t0 bg:t1:b1111 bg:t2:b2222
expect "two still running: refused once, both ids named" 2 "b1111, b2222" "$(event run1)"
expect "stop_hook_active set: let through, silent" 0 "" "$(event run1 true)"
fixture moved1 moved:t1:bm001
expect "a command moved to the background counts as started" 2 "bm001" "$(event moved1)"
fixture half1 bg:t1:b1111 bg:t2:b2222 done:b1111:completed
expect "one finished, one running: only the running one named" 2 "b2222" "$(event half1)"
fixture note1 bg:t1:b1111 note:b1111
expect "an interim notice with no status doesn't count as finished" 2 "b1111" "$(event note1)"
fixture fin1 bg:t1:b1111 bg:t2:b2222 bg:t3:b3333 bg:t4:b4444 done:b1111:completed done:b2222:failed done:b3333:killed stop:t5:b4444
expect "every command finished, failed, killed or stopped: let through, silent" 0 "" "$(event fin1)"
fixture none1 fg:t1 fg:t2
expect "no background command started: let through, silent" 0 "" "$(event none1)"
expect "no transcript file: let through, silent" 0 "" "$(event gone1)"
mkdir -p "$S/subagents/agent-dir1.jsonl"
expect "a transcript that is a folder: let through, silent" 0 "" "$(event dir1)"
fixture locked1 bg:t1:b1111; chmod 000 "$S/subagents/agent-locked1.jsonl"
if [ -r "$S/subagents/agent-locked1.jsonl" ]; then echo "SKIPPED  unreadable file: this user can read a mode-000 file (root)"; else
  expect "an unreadable transcript: let through, silent" 0 "" "$(event locked1)"; fi
chmod 600 "$S/subagents/agent-locked1.jsonl"
fixture junk1 junk half junk
expect "a transcript in an unknown format: let through, silent" 0 "" "$(event junk1)"
fixture mixed1 junk bg:t1:b1111 half junk
expect "junk lines around a running command: still refused (the readable lines count)" 2 "b1111" "$(event mixed1)"
printf '[1,2]\n"x"\n{"type":"user","message":"text"}\n{"type":"user","message":{"content":[1,null,{"type":"tool_result"}]}}\n' > "$S/subagents/agent-odd1.jsonl"
expect "lines of the wrong shape: let through, silent" 0 "" "$(event odd1)"
expect "stdin that isn't JSON: let through, silent" 0 "" "not json"
expect "stdin that is a JSON list: let through, silent" 0 "" "[1]"
expect "an empty event: let through, silent" 0 "" "{}"

# It reads only the helper's own transcript: any other path is let through without being read.
fixture other1 bg:t1:b9999
expect "another helper's transcript named as this helper's: let through" 0 "" "$(event mine1 false "$S/subagents/agent-other1.jsonl")"
mkdir -p "$T/elsewhere/subagents"; cp "$S/subagents/agent-other1.jsonl" "$T/elsewhere/subagents/agent-other1.jsonl"
expect "a transcript outside this session's folder: let through" 0 "" "$(event other1 false "$T/elsewhere/subagents/agent-other1.jsonl")"
expect "a path that climbs out of the folder: let through" 0 "" "$(event other1 false "$S/subagents/../../elsewhere/subagents/agent-other1.jsonl")"
ln -s "$T/elsewhere/subagents/agent-other1.jsonl" "$S/subagents/agent-link1.jsonl"
expect "a transcript that is a link to a file elsewhere: let through" 0 "" "$(event link1)"
expect "an agent id with a path in it: let through" 0 "" "$(event '../subagents/agent-other1' false "$S/subagents/agent-../subagents/agent-other1.jsonl")"
expect "(control) the same transcript, named by its own helper: refused" 2 "b9999" "$(event other1)"

# background_tasks (the session's in-flight tasks) narrows the list when Claude Code sends it.
expect "the session no longer lists the command: let through" 0 "" "$(event run1 false "" '[{"id":"bzzzz","type":"shell","status":"running"}]')"
expect "the session lists one of the two: only that one named" 2 "b2222" "$(event run1 false "" '[{"id":"b2222","type":"shell","status":"running"}]')"
expect "background_tasks that isn't a list: ignored, the transcript decides" 2 "b1111, b2222" "$(event run1 false "" '"x"')"

# A crash inside the hook lets the helper finish and says nothing.
crash=$(event run1 | python3 -I -c 'import json, runpy, sys
def boom(*a, **k): raise RuntimeError("boom")
json.loads = boom
runpy.run_path(sys.argv[1], run_name="__main__")' "$HOOK" 2>"$T/err"; echo $?)
[ "$crash" = 0 ] && [ ! -s "$T/err" ] && ok "the hook's own crash: let through, silent" || bad "the hook's own crash: exit $crash, stderr $(head -c 200 "$T/err")"

# Fast: a 20 MB transcript with one running command at the end takes well under a second.
python3 -I -c 'import json,sys
f=open(sys.argv[1],"w"); pad={"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"*2000}]}}
for _ in range(10000): f.write(json.dumps(pad)+"\n")' "$S/subagents/agent-big1.jsonl"
cat "$S/subagents/agent-run1.jsonl" >> "$S/subagents/agent-big1.jsonl"
t0=$(python3 -c 'import time;print(time.time())'); rc=$(run "$(event big1)"); t1=$(python3 -c 'import time;print(time.time())')
python3 -c 'import sys; sys.exit(0 if float(sys.argv[2])-float(sys.argv[1]) < 2 else 1)' "$t0" "$t1" && [ "$rc" = 2 ] \
  && ok "a 20 MB transcript is read in under two seconds" || bad "a 20 MB transcript: exit $rc, $(python3 -c 'import sys;print(float(sys.argv[2])-float(sys.argv[1]))' "$t0" "$t1")s"
grep -qE '^import (json|os|re|sys)(, (json|os|re|sys))*$' "$HOOK" && ! grep -qE '^(import|from) ' <(grep -vE '^import (json|os|re|sys)(, (json|os|re|sys))*$' "$HOOK") \
  && ok "standard library only" || bad "the hook imports something outside json, os, re, sys"

# --- Part 2: the settings merge helper ----------------------------------------------------------
CMD="/h/.claude/make-it/hooks/no-leftover-commands.py python3"
OLD="/other/.claude/make-it/hooks/no-leftover-commands.py python3"
ours() { python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(len([h for e in d.get("hooks",{}).get("SubagentStop",[]) for h in e.get("hooks",[]) if "make-it/hooks/no-leftover-commands.py" in h.get("command","")]))' "$1"; }
baks() { ls "$1" | grep -c '\.bak-' ; }
mkdir -p "$T/m1"; F="$T/m1/settings.json"
echo '{"model":"opus","hooks":{"SubagentStop":[{"matcher":"Explore","hooks":[{"type":"command","command":"/user/own"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/x/pre"}]}]}}' > "$F"
out=$(python3 -I "$HELPER" "$F" $CMD) && [ "$(ours "$F")" = 1 ] && case $out in Added*) true ;; *) false ;; esac \
  && ok "helper: adds the hook once, and says so" || bad "helper: didn't add it ($out)"
python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1])); s=d["hooks"]["SubagentStop"]
assert d["model"]=="opus" and d["hooks"]["PreToolUse"][0]["hooks"][0]["command"]=="/x/pre"
assert s[0]=={"matcher":"Explore","hooks":[{"type":"command","command":"/user/own"}]}
assert s[1]=={"hooks":[{"type":"command","command":sys.argv[2]}]}' "$F" "bash -c '[ -f \"\$0\" ] || exit 0; exec python3 -I \"\$0\"' /h/.claude/make-it/hooks/no-leftover-commands.py" && ok "helper: everything else stays; the entry has no matcher (every helper)" || bad "helper: other settings changed or the entry is wrong"
[ "$(baks "$T/m1")" = 1 ] && ok "helper: keeps a copy of the old file" || bad "helper: no backup kept"
out=$(python3 -I "$HELPER" "$F" $CMD); [ "$(ours "$F")" = 1 ] && [ "$(baks "$T/m1")" = 1 ] && case $out in *already*) true ;; *) false ;; esac \
  && ok "helper: a second run adds nothing and changes nothing" || bad "helper: a second run changed settings ($out)"
out=$(python3 -I "$HELPER" "$F" $OLD); [ "$(ours "$F")" = 1 ] && grep -qF '/other/.claude' "$F" && ! grep -qF " /h/.claude" "$F" && case $out in Updated*) true ;; *) false ;; esac \
  && ok "helper: an older make-it entry (another path) is replaced, never doubled" || bad "helper: an older entry was doubled or kept ($out)"
rm -f "$T/m2.json"; python3 -I "$HELPER" "$T/m2.json" $CMD >/dev/null && [ "$(ours "$T/m2.json")" = 1 ] && ok "helper: no settings file yet: one is made" || bad "helper: no settings file: not made"
for bad_json in '{"hooks": [' '[1]' '{"hooks":[]}' '{"hooks":{"SubagentStop":{}}}' '{"a":NaN}'; do
  printf '%s' "$bad_json" > "$T/m3.json"
  python3 -I "$HELPER" "$T/m3.json" $CMD >/dev/null 2>"$T/err"; rc=$?
  [ $rc = 1 ] && [ "$(cat "$T/m3.json")" = "$bad_json" ] && grep -q "didn't change it" "$T/err" \
    && ok "helper: refuses and leaves alone: $bad_json" || bad "helper: changed or accepted: $bad_json (exit $rc)"
done
mkdir -p "$T/m4"; echo '{}' > "$T/m4/real.json"; ln -s real.json "$T/m4/settings.json"
python3 -I "$HELPER" "$T/m4/settings.json" $CMD >/dev/null && [ -L "$T/m4/settings.json" ] && [ "$(ours "$T/m4/real.json")" = 1 ] \
  && ok "helper: a settings file that is a link stays a link" || bad "helper: the link was replaced"

# --- Part 3: the installers ---------------------------------------------------------------------
H="$T/home o'q \$x"; mkdir -p "$H/.claude"
echo '{"model":"opus","hooks":{"SubagentStop":[{"hooks":[{"type":"command","command":"/user/own"}]}]}}' > "$H/.claude/settings.json"
if HOME="$H" bash install.sh >"$T/i1" 2>&1; then
  [ "$(ours "$H/.claude/settings.json")" = 1 ] && ok "install.sh: registers the hook on SubagentStop" || bad "install.sh: the hook isn't registered once"
  hc=$(python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));print([h["command"] for e in d["hooks"]["SubagentStop"] for h in e["hooks"] if "no-leftover" in h["command"]][0])' "$H/.claude/settings.json")
  case $hc in *"make-it/hooks/no-leftover-commands.py"*) ok "install.sh: the entry points at the installed hook" ;; *) bad "install.sh: the entry doesn't point at the installed hook" ;; esac
  # the written command, run the way Claude Code runs it, against this test's session folder
  event run1 > "$T/ev.json"; rc=$(sh -c "$hc" <"$T/ev.json" 2>"$T/err"; echo $?)
  [ "$rc" = 2 ] && [ "$(cat "$T/err")" = "$(printf "$MSG" "b1111, b2222")" ] && ok "install.sh: the written command runs the hook and refuses a helper with a running command" || bad "install.sh: the written command didn't refuse (exit $rc)"
  hf="$H/.claude/make-it/hooks/no-leftover-commands.py"; mv "$hf" "$hf.gone"
  rc=$(sh -c "$hc" <"$T/ev.json" 2>"$T/err"; echo $?); mv "$hf.gone" "$hf"
  [ "$rc" = 0 ] && [ ! -s "$T/err" ] && ok "install.sh: hook file gone (make-it removed): every helper finishes, nothing said" || bad "install.sh: hook file gone: exit $rc"
  grep -qi 'background command' "$T/i1" && ok "install.sh: says what it added" || bad "install.sh: didn't say it added the hook"
  HOME="$H" bash install.sh >"$T/i2" 2>&1
  [ "$(ours "$H/.claude/settings.json")" = 1 ] && grep -q 'already' "$T/i2" && ok "install.sh: a re-install keeps one copy" || bad "install.sh: a re-install doubled or dropped it"
  python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["model"]=="opus" and d["hooks"]["SubagentStop"][0]["hooks"][0]["command"]=="/user/own" and d["hooks"]["PreToolUse"]' "$H/.claude/settings.json" \
    && ok "install.sh: the user's own settings and the force-push guard stay" || bad "install.sh: settings were lost"
else bad "install.sh failed: $(tail -5 "$T/i1")"; fi
grep -qF 'add-subagent-stop-hook.py' install.ps1 && grep -qF 'no-leftover-commands.py' install.ps1 && grep -q 'python3", "python"' install.ps1 \
  && ok "install.ps1: registers the same hook with the same helper, with python3 or python" || bad "install.ps1 doesn't register the hook"
if command -v pwsh >/dev/null 2>&1; then
  errs=$(LC_ALL=C LANG=C pwsh -NoProfile -NonInteractive -c '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "install.ps1"), [ref]$null, [ref]$e); $e.Count')
  [ "$errs" = 0 ] && ok "install.ps1 parses" || bad "install.ps1 has $errs parse errors"
else
  echo "SKIPPED  install.ps1 parse: pwsh is not installed here -- NOT PROVEN on this machine"
  [ -z "${CI:-}" ] || bad "pwsh missing in CI"
fi

[ $fail = 0 ] && echo "PASS  no leftover background commands" || echo "FAILED"
exit $fail
