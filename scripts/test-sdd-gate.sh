#!/usr/bin/env bash
# Regression test for .claude/make-it/sdd/scripts/sdd-gate.
# Exit 2 from the gate = it blocks the stop (run still armed); 0 = no-op.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$root/.claude/make-it/sdd/scripts/sdd-gate"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export SDD_GATE_REGISTRY="$T/sdd-runs"
fail=0
expect() { # expect <label> <want-exit> <payload-json>
  printf '%s' "$3" | python3 "$GATE" >/dev/null 2>&1; got=$?
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (want $2, got $got)"; fail=1; fi
}
arm() { mkdir -p "$1/.make-it/sdd"; printf 'RUN: plan=p.md tasks=2\n' > "$1/.make-it/sdd/progress.md"; }

git init -q "$T/repo" && arm "$T/repo"
L="$T/repo/.make-it/sdd/progress.md"
mkdir -p "$T/elsewhere"
: > "$T/empty-transcript.jsonl"

expect "armed ledger in session repo blocks" 2 "{\"cwd\":\"$T/repo\"}"
expect "session outside repo, nothing registered: no-op" 0 "{\"cwd\":\"$T/elsewhere\",\"transcript_path\":\"$T/empty-transcript.jsonl\"}"

out="$(python3 "$GATE" register "$L")"
case "$out" in *"$L"*) echo "ok   register prints the ledger path" ;; *) echo "FAIL register output: $out"; fail=1 ;; esac
python3 "$GATE" register "$L" >/dev/null
[ "$(grep -c . "$SDD_GATE_REGISTRY")" = 1 ] && echo "ok   register dedups" || { echo "FAIL register dedup"; fail=1; }

printf '{"tool_result":"sdd-gate: registered %s"}\n' "$L" > "$T/this-session.jsonl"
expect "registered + in this session's transcript blocks from any cwd" 2 "{\"cwd\":\"$T/elsewhere\",\"transcript_path\":\"$T/this-session.jsonl\"}"
expect "registered but another session's transcript: no-op" 0 "{\"cwd\":\"$T/elsewhere\",\"transcript_path\":\"$T/empty-transcript.jsonl\"}"
expect "registered, no transcript_path: no-op (fail open)" 0 "{\"cwd\":\"$T/elsewhere\"}"

printf 'STATUS: DONE\n' >> "$L"
expect "released run: no-op" 0 "{\"cwd\":\"$T/elsewhere\",\"transcript_path\":\"$T/this-session.jsonl\"}"

rm -rf "$T/repo/.make-it"
expect "deleted ledger: no-op" 0 "{\"cwd\":\"$T/elsewhere\",\"transcript_path\":\"$T/this-session.jsonl\"}"
grep -q . "$SDD_GATE_REGISTRY" && { echo "FAIL deleted ledger not pruned from registry"; fail=1; } || echo "ok   deleted ledger pruned from registry"

# E02-S4: ending the turn to wait for a background agent is not a stall. Fixture lines copy
# the transcript's real shapes: the Agent tool_result, then the completion notice (queued,
# then delivered).
ago() { python3 -c 'import datetime as d,sys; print((d.datetime.now(d.timezone.utc)-d.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%S.000Z"))' "$1"; }
RESULT='{"role":"user","content":[{"tool_use_id":"toolu_A","type":"tool_result","content":[{"type":"text","text":"Async agent launched successfully.\\nagentId: a1"}]}]}'
# the transcript also stores an untimestamped api-request-blob copy of the same result
launch() { printf '{"type":"user","timestamp":"%s","message":%s}\n{"type":"api-request-blob","message":%s}\n' "$(ago "$1")" "$RESULT" "$RESULT"; }
NOTE='<task-notification>\\n<task-id>a1</task-id>\\n<tool-use-id>toolu_A</tool-use-id>\\n<status>completed</status>\\n</task-notification>'
queued() { printf '{"type":"queue-operation","operation":"enqueue","timestamp":"%s","content":"%s"}\n' "$(ago 0)" "$NOTE"; }
delivered() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' "$(ago 0)" "$NOTE"; }
git init -q "$T/wait" && W="$T/wait/.make-it/sdd/progress.md"
wait_case() { # wait_case <label> <want-exit> <transcript lines...>
  arm "$T/wait"; printf '%s' "$3" > "$T/wait.jsonl"
  expect "$1" "$2" "{\"cwd\":\"$T/wait\",\"transcript_path\":\"$T/wait.jsonl\"}"
}
wait_case "background agent still running: no nudge" 0 "$(launch 5)"
grep -q "gate: nudged" "$W" && { echo "FAIL a wait counted toward the cap"; fail=1; } || echo "ok   a wait is not counted toward the cap"
wait_case "agent finished, notice queued but not delivered: no nudge" 0 "$(launch 5; queued)"
wait_case "agent's notice delivered, nothing else running: nudges" 2 "$(launch 5; queued; delivered)"
wait_case "agent launched past the wait window (stale): nudges" 2 "$(launch 180)"
wait_case "garbage transcript line: still nudges" 2 "$(launch 5 | cut -c1-40)"

# E02-S37: an interim notice ("is waiting on its own background work", status still completed)
# is not the agent reporting back; only its final notice is. Later notices for the same task may
# carry only <task-id>, which the launch result's agentId ties back to the launch.
notice() { # notice <tool-use-id or ""> <summary>
  tu=""; [ -n "$1" ] && tu="<tool-use-id>$1</tool-use-id>\\n"
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"<task-notification>\\n<task-id>a1</task-id>\\n%s<status>completed</status>\\n<summary>%s</summary>\\n</task-notification>"}}\n' "$(ago 0)" "$tu" "$2"
}
INTERIM='Agent \"impl\" is waiting on its own background work'
FINAL='Agent \"impl\" finished'
wait_case "interim notice: still waiting, no nudge" 0 "$(launch 5; notice toolu_A "$INTERIM")"
grep -q "gate: nudged" "$W" && { echo "FAIL an interim wait counted toward the cap"; fail=1; } || echo "ok   an interim wait is not counted toward the cap"
wait_case "interim, then task-id-only interim: still waiting" 0 "$(launch 5; notice toolu_A "$INTERIM"; notice "" "$INTERIM")"
wait_case "interim, then final notice: nudges" 2 "$(launch 5; notice toolu_A "$INTERIM"; notice toolu_A "$FINAL")"
wait_case "final notice carrying only task-id: nudges" 2 "$(launch 5; notice "" "$FINAL")"
wait_case "interim past the wait window (stale): nudges" 2 "$(launch 180; notice toolu_A "$INTERIM")"

expect "garbage stdin: no-op (fail open)" 0 "not json"
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
