#!/usr/bin/env bash
# E02-S36: the SDD run instructions carry the four lessons the owner approved on 2026-10-20.
#   1. Test-writers run on Opus (or Fable), never Sonnet.
#   2. A shell check never pipes large text into grep -q under pipefail (a helper that reads all of
#      its input, or capture first), and a run fails on any stderr: test-writer + implementer templates.
#   3. A check narrowed to stop a false alarm lists the real opposites it still fails, with mutants
#      (test-writer SAFEGUARDS line); the task reviewer re-runs them before accepting it.
#   4. Three consecutive review rounds on one task with the same root cause: STATUS: AWAITING_HUMAN
#      with a decision-ready design choice, not another patch (reference fix loop + /subagent-it).
# Each check reads one sentence (or clause) of one named place and fails on the rule's plain opposite.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# rule 2 applied here: gq reads all of its input, so no writer is cut off by SIGPIPE
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# any stderr fails the run (a bad regex read by a negated check would otherwise pass); shown again on exit
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

REF=.claude/make-it/references/subagent-driven-development.md
CMD=.claude/commands/subagent-it.md
TW=.claude/make-it/sdd/test-writer-prompt.md
IMP=.claude/make-it/sdd/implementer-prompt.md
REV=.claude/make-it/sdd/task-reviewer-prompt.md

flat()  { tr '\n' ' ' | tr -s ' '; echo; }
# one sentence per line: breaks at ". ", blank lines, and list items ("- ", "4. ", "e. ", "a2. ")
sents() { awk 'NF==0{print ""; next} /^ *(- |[0-9]+[.] |[a-z][0-9]?[.] )/{print ""} {printf "%s ", $0} END{print ""}' |
          tr -s ' ' | sed 's/\. /.\
/g'; }
# sentences also broken at " → " and "; " (/subagent-it's step 4 is one long chain)
clauses() { sents | sed 's/ → /\
/g; s/; /\
/g'; }
# has PAT...: some stdin line, lowercased, matches every PAT; a PAT starting with "!" must not match
has() { awk 'BEGIN{n=ARGC-1; for(i=1;i<=n;i++){p[i]=ARGV[i]; delete ARGV[i]}}
  {l=tolower($0); m=1; for(i=1;i<=n;i++){q=p[i]; if(substr(q,1,1)=="!"){if(l ~ substr(q,2)) m=0} else if(l !~ q) m=0} if(m) hit=1}
  END{exit !hit}' "$@"; }
# block FILE START END: the lines from the first START match up to (not including) the next END match
block() { awk -v a="$2" -v b="$3" 'on && $0 ~ b {exit} $0 ~ a {on=1} on' "$1"; }
NEG_SONNET='s/([Nn]ever|[Nn]ot) [*]*[Ss]onnet//g'

# ---- 1. test-writers run on Opus (or Fable), never Sonnet ----
STEP_A="$(block $REF '^   a[.] ' '^   a2[.] ')"
MODEL="$(grep '^- [*][*]Test-writer:[*][*]' $REF || true)"
STATUS_TW="$(block $REF '^- [*][*]The test-writer[*][*]' '^(- |#|$)')"
TW_HEAD="$(sed -n '1,/-->/p' $TW)"
CMD_TW="$(block $CMD '^4[.] ' '^5[.] ' | clauses | grep 'dispatch the [*][*]test-writer[*][*]' || true)"
check "rule 1 anchors found (reference step a, model line, status bullet; template header; /subagent-it step 4)" \
  '[ -n "$STEP_A" ] && [ -n "$MODEL" ] && [ -n "$STATUS_TW" ] && [ -n "$TW_HEAD" ] && [ -n "$CMD_TW" ]'
# names Opus, and every Sonnet in it is negated ("never Sonnet", "not Sonnet")
opus() { printf '%s\n' "$1" | flat | sed -E "$NEG_SONNET" | has 'opus' '!sonnet'; }
check "reference step a dispatches the test-writer on Opus (or Fable), never Sonnet" 'opus "$STEP_A"'
check "reference model selection: the test-writer runs on Opus (or Fable), never Sonnet" 'opus "$MODEL"'
check "reference status handling: a stuck test-writer stays on Opus (or Fable), never Sonnet" 'opus "$STATUS_TW"'
check "test-writer template header: dispatch on Opus (or Fable), never Sonnet" 'opus "$TW_HEAD"'
check "/subagent-it step 4 dispatches the test-writer on Opus (or Fable), never Sonnet" 'opus "$CMD_TW"'
# sweep (guards a moved anchor or a new mention): no test-writer sentence, and no template line, names Sonnet
tw_sentences() { sents < $REF | grep -i 'test-writer'; sents < $CMD | grep -i 'test-writer'; cat $TW; }
check "no test-writer sentence in the reference or /subagent-it, and no line of its template, names Sonnet un-negated" \
  '! { tw_sentences || true; } | sed -E "$NEG_SONNET" | has "sonnet"'

# ---- 2. shell checks: never grep -q on piped text under pipefail; read all input; fail on any stderr ----
for f in $TW $IMP; do
  check "$f: never pipe large text into grep -q under pipefail" \
    "sents < $f | has 'grep -q' 'never pipe' 'pipefail'"
  check "$f: every sentence that names grep -q forbids it" \
    "! sents < $f | has 'grep -q' '!never|not |don.t|do not'"
  check "$f: shows the helper that reads all of its input (gq on grep -c), or capturing first" \
    "gq -F 'gq() { [ \"\$(grep -c \"\$@\")\" -gt 0 ]; }' $f && sents < $f | has 'reads all of its input' 'capture'"
  check "$f: a run fails on any output to stderr" \
    "sents < $f | has 'fail' 'any' 'stderr' '!never fail|not fail|ignore|doesn.t fail'"
done

# ---- 3. a narrowed check lists the opposites it still fails, with mutants; the reviewer re-runs them ----
TW_SAFE="$(sents < $TW | grep '^- [*][*]SAFEGUARDS:[*][*]' || true)"
check "rule 3 anchor found (the test-writer's SAFEGUARDS line)" '[ -n "$TW_SAFE" ]'
check "test-writer SAFEGUARDS: a check narrowed to stop a false alarm lists the real opposites it still fails, each with a mutant" \
  'printf "%s\n" "$TW_SAFE" | has "narrow" "false alarm" "opposite" "mutant" "!no mutant|without (a )?mutant|needn.t|need not"'
check "task reviewer: re-runs each mutant of a narrowed check before accepting it, and the check must still fail" \
  "sents < $REV | has 'narrow' 'mutant' 're-run' 'still fails' '!do not|don.t|never|no need|without re-?run'"
check "task reviewer: a narrowing with no mutants, or a mutant it now passes, is Critical" \
  "sents < $REV | has 'narrow' 'no mutant' 'now passes' 'critical'"
check "task reviewer: the do-not-run-tests rule carves out a narrowed check's mutants" \
  "sents < $REV | has 'do not run' 'except' 'mutant'"

# ---- 4. three consecutive same-cause review rounds: AWAITING_HUMAN with a design choice ----
STEP_E="$(block $REF '^   e[.] ' '^   e2[.] ')"
CMD4="$(block $CMD '^4[.] ' '^5[.] ')"
check "rule 4 anchors found (reference step e, /subagent-it step 4)" '[ -n "$STEP_E" ] && [ -n "$CMD4" ]'
ESC4='"same root cause" "(three|3) consecutive" "status: awaiting_human" "design choice" "stop patching|instead of another patch|not another patch" "!keep patching"'
check "reference fix loop (step e): three consecutive same-cause rounds -> STATUS: AWAITING_HUMAN with a design choice, not another patch" \
  "printf '%s\n' \"\$STEP_E\" | sents | has $ESC4"
check "/subagent-it step 4: three consecutive same-cause rounds -> STATUS: AWAITING_HUMAN with a design choice, not another patch" \
  "printf '%s\n' \"\$CMD4\" | clauses | has $ESC4"

check "the run printed nothing on stderr" '[ ! -s "$ERRF" ]'
if [ "$fail" = 0 ]; then echo "ALL PASSED"; else echo "SOME CHECKS FAILED"; exit 1; fi
