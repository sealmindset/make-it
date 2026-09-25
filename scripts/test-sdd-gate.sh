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

expect "garbage stdin: no-op (fail open)" 0 "not json"
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
