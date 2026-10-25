#!/usr/bin/env bash
# E02-S26: /try-it checks the app's existing pages with sign-in left out, and claims only checks and artifacts that exist.
# Contract these checks pin (.claude/commands/try-it.md):
#   1. Phase 2 has a path for sign-in left out: step 4 still checks, without signing in (it signs in nowhere), the pages
#      the app already had, through the app's own access, that they work as they did before.
#   2. That path says those page checks are not the left-out item's by pointing at left-out-record.md read step 3; try-it
#      never restates that step.
#   3. The report's Pages Tested lists those pages as checked, never as left out.
#   4. Phase 5's closing line says "with screenshots" only if screenshots were taken.
#   5. The report's Screenshots section says "Screenshots unavailable" when none were taken (as with no Playwright).
#   6. "pages were tested" is said only if pages were tested; <error-handling> points at the report's wording.
#   7. A left-out item that keeps the app from building or starting has its own path in build-and-start, before any fix:
#      no fix or retry, a plain message that the app couldn't start, never "Everything is running!", on to the smoke test
#      with left_out.
# Usage: test-try-it-checks.sh [FILE|-]. With no FILE it checks the real try-it.md, then proves each check fails on its
# plain opposite.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

F="${1:-.claude/commands/try-it.md}"
T="$(cat -- "$F")"
flat()  { tr '\n' ' ' | tr -s ' '; }
paras() { awk 'BEGIN{RS="";ORS="\n"} {gsub(/\n/," "); print}' | tr -s ' '; }
sents() { paras | perl -pe 's/([.!?]["\x27]?) (?=\S)/$1\n/g'; }
# does stdin match the perl regex $1 (case-insensitive)? perl, for the lookbehinds that bind a phrase to its polarity
pm() { P="$1" perl -0777 -ne 'exit !(/$ENV{P}/i)'; }
stepof()  { printf '%s\n' "$T" | awk -v n="<step name=\"$1\">" 'index($0,n){on=1;next} on&&/^<\/step>/{exit} on'; }
between() { printf '%s\n' "$T" | awk -v a="$1" -v b="$2" 'index($0,a){on=1} on&&index($0,b)&&!index($0,a){exit} on'; }
SIGNIN='\b(if|when) (the )?(sign-in|sign in|login)\b[^.;:]{0,20}\bleft out\b'

# Phase 2 step N's text, from its "**N. " heading to the next step's
smokestep() { stepof smoke-test | awk -v a="^[*][*]$1[.] " -v b="^[*][*]$(($1+1))[.] " '$0~a{on=1} $0~b{exit} on'; }
# 1-2. Phase 2: with sign-in left out, the pages the app already had are still checked, without signing in.
# What it affirms is read in step 3, where the path lives; what it rejects, in every sign-in paragraph of Phase 2 but
# step 5's, which check 8 reads (there "only an endpoint that belongs to the left-out item is" left out is right).
SIGNP="$(smokestep 3 | paras | grep -iE "$SIGNIN" || true)"
SIGNR="$(stepof smoke-test | awk '/^[*][*]5[.] /{off=1} /^[*][*]6[.] /{off=0} !off' | paras | grep -iE "$SIGNIN" || true)"
S1X='\b(skip|skips|skipped|skipping)\b[^.;]{0,30}\b(step 4|pages?)\b|\bstep 4\b[^.;]{0,10}\b(doesn.t|does not|never|won.t|is not|isn.t) run|\b(sign|signs|log|logs) in (as|with|through|via|using|to)\b|\beven if\b|\bunless\b'
check "S26-1 Phase 2: with sign-in left out, step 4 still checks, without signing in (signing in nowhere), the pages the app already had, through the app's own access, that they work as they did before" \
  '[ -n "$SIGNP" ] && printf "%s" "$SIGNP" | pm "\bstill (runs|checks|opens)\b" && printf "%s" "$SIGNP" | pm "\bpages? the app already had\b" && printf "%s" "$SIGNP" | pm "\bwithout signing in\b" && printf "%s" "$SIGNP" | pm "\bsigns in nowhere\b" && printf "%s" "$SIGNP" | pm "\bapp.s own access\b" && printf "%s" "$SIGNP" | pm "\bas (it|they) did before\b" && ! printf "%s" "$SIGNR" | pm "$S1X"'
check "S26-2 Phase 2: that path says those page checks are not the left-out item's by pointing at left-out-record.md read step 3, and try-it never restates the step" \
  'printf "%s" "$SIGNP" | pm "left-out-record\.md.?\s+read\s+step\s+3\b" && printf "%s" "$SIGNP" | pm "\b(are not|aren.t|never|not) (the )?left.out item.s\b|\b(don.t|do not|never) belong" && ! printf "%s" "$SIGNR" | pm "(?<!not )(?<!never )(?<!n.t )\b(are|is) the left.out item.s\b|(?<!never )(?<!not )(?<!n.t )\bbelongs? to the left.out item" && ! printf "%s" "$T" | flat | pm "still works as it did before never belongs|\(and the user did not take out\)"'

# 3. the report lists those pages as checked
PSIGN="$(between '## Pages Tested' '## Screenshots' | paras | grep -iE "$SIGNIN" || true)"
check "S26-3 report: with sign-in left out, Pages Tested lists the pages the app already had as checked (with how each went), never as left out" \
  '[ -n "$PSIGN" ] && printf "%s" "$PSIGN" | pm "\bpages? the app already had\b" && printf "%s" "$PSIGN" | pm "\b(listed|lists?) as checked\b" && printf "%s" "$PSIGN" | pm "\bnever as left out\b" && ! printf "%s" "$PSIGN" | pm "(?<!never )(?<!not )\b(listed|lists?|reads?|shows?|marked) as (left out|Left out \(your choice\))|\b(reads?|shows?)\s+\W?Left out \(your choice\)|\beven if\b|\bunless\b"'

# 4. Phase 5 claims screenshots only if any were taken
FULLR="$(stepof user-handoff | grep -F 'full report' || true)"
check "S26-4 Phase 5: the closing \"I saved a full report\" says \"with screenshots\" only if screenshots were taken" \
  '[ -n "$FULLR" ] && ! printf "%s\n" "$FULLR" | gq -F "full report with screenshots" && printf "%s\n" "$FULLR" | pm "\[only (if|when) (any )?screenshots were taken: .\s?with screenshots.\]" && ! printf "%s\n" "$FULLR" | pm "\beven (if|when)\b|\bwhether or not\b"'

# 5. the report says when no screenshot was taken
SHOTS="$(between '## Screenshots' '## How to Access Your App')"
check "S26-5 report: when no screenshot was taken (as when Playwright couldn't be installed), the Screenshots section says \"Screenshots unavailable\" in place of the line and the list" \
  's=$(printf "%s\n" "$SHOTS" | sents | grep -F "Screenshots unavailable" || true); [ -n "$s" ] && printf "%s" "$s" | pm "\bno screenshot (was|were) taken\b" && printf "%s" "$s" | pm "\bin place of this line and the list\b" && ! printf "%s" "$s" | pm "\beven (if|when)\b|\bkeep (this line|the list)\b|(don.t|do not|never) (say|write)"'

# 6. "pages were tested" only when they were
check "S26-6 \"pages were tested\" is said only if pages were tested (never when a left-out item kept every page from opening); <error-handling> points at the report's Screenshots wording" \
  's=$(printf "%s\n" "$T" | sents | grep -iF "pages were tested" || true); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -viE "only (if|when) (pages|they) were tested|never .?pages were tested.? when none were" && ! printf "%s\n" "$s" | pm "\beven (if|when)\b|\bwhether or not\b" && e=$(printf "%s\n" "$T" | awk "/If Playwright can.t be installed/{on=1;next} on&&/^\*\*If |^<\/error-handling>/{exit} on" | flat) && printf "%s" "$e" | pm "report.s Screenshots section"'

# 7. a left-out item that keeps the app from starting has a defined path, before any fix
BS="$(stepof build-and-start)"
KEEPS='\b(if|when) a left.out item (keeps|kept|stops|blocks|prevents)\b[^.;:]{0,30}\b(build|start)'
GATE="$(printf '%s\n' "$BS" | paras | grep -iE "$KEEPS" || true)"
check "S26-7 build-and-start: a left-out item that keeps the app from building or starting has its own path before any fix -- no fix or retry, a plain message that it couldn't start, never \"Everything is running!\", on to the smoke test with left_out" \
  '[ -n "$GATE" ] && printf "%s" "$GATE" | pm "(don.t|do not|never) fix\b" && printf "%s" "$GATE" | pm "(don.t|do not|never) retry\b" && printf "%s" "$GATE" | pm "Tell user: \"[^\"]*(couldn.t|could not|can.t|cannot) (be started|start)[^\"]*leave out[^\"]*\"" && printf "%s" "$GATE" | pm "\bnever say\s+.?Everything is running" && printf "%s" "$GATE" | pm "\bsmoke test\b" && printf "%s" "$GATE" | pm "left_out" && ! printf "%s" "$GATE" | pm "\beven if\b|\bunless\b|\bexcept\b|(?<!never )(?<!not )(?<!n.t )\b(say|tell user:?)\s+.?Everything is running|\bfix it anyway\b|(?<!don.t )(?<!not )\bretry (it )?(up to|anyway|again)\b" && a=$(printf "%s\n" "$BS" | grep -niE "$KEEPS" | head -1 | cut -d: -f1) && b=$(printf "%s\n" "$BS" | grep -nF "**If build fails:**" | head -1 | cut -d: -f1) && [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]'

# 8. Phase 2 step 5: with sign-in left out, the endpoints the app already had are still called, without a token
APIP="$(smokestep 5 | paras | grep -iE "$SIGNIN" || true)"
SUMSIGN="$(between '## Summary' '## Login Testing' | paras | grep -iE "$SIGNIN" || true)"
S8X='\b(skip|skips|skipped|skipping)\b[^.;]{0,30}\b(step 5|endpoints?)\b|\bstep 5\b[^.;]{0,10}\b(doesn.t|does not|never|won.t|is not|isn.t) run|\bBearer\b|\b(sign|signs|log|logs) in (as|with|through|via|using|to)\b|(?<!never )(?<!not )\bas left out\b|\beven if\b|\bunless\b'
check "S26-8 Phase 2 step 5: with sign-in left out, the endpoints the app already had are still called, without a token, through the app's own access, and listed as checked; one that needed sign-in before the retrofit is named plainly as not checked, never as left out (only one that belongs to the left-out item is, per read step 3)" \
  '[ -n "$APIP" ] && [ -n "$SUMSIGN" ] && printf "%s" "$APIP" | pm "\bstep 5 still runs, without a token\b" && printf "%s" "$APIP" | pm "\bendpoints? the app already had\b" && printf "%s" "$APIP" | pm "\bapp.s own access\b" && printf "%s" "$APIP" | pm "\bas (it|they) did before\b" && printf "%s" "$APIP" | pm "\breport lists (them|those endpoints) as checked\b" && printf "%s" "$APIP" | pm "\bneeded sign-in before the retrofit\b[^.]*\bname (it|them) plainly\b[^.]*\bas not checked, never as left out\b" && printf "%s" "$APIP" | pm "\bonly an? endpoints? that belongs? to the left.out item\s+\(.left-out-record\.md.?\s+read\s+step\s+3\)" && ! printf "%s" "$APIP" | pm "$S8X" && printf "%s" "$SUMSIGN" | pm "\bendpoints? the app already had\b[^.]*\bwithout signing in\b[^.]*\bas checked, never as left out\b" && printf "%s" "$SUMSIGN" | pm "\bneeded sign-in before the retrofit\b[^.]*\bnot checked\b" && ! printf "%s" "$SUMSIGN" | pm "(?<!never )(?<!not )\bas left out\b|Left out \(your choice\)|\beven if\b|\bunless\b"'

# 9. the guardrails' screenshot minimum names the exceptions <error-handling> and step 3 already allow, in one clause
GR="$(printf '%s\n' "$T" | awk '/^<guardrails>/{on=1} on' | awk '/at least: login, dashboard per role/{on=1;print;next} on&&(/^- /||/^$/||/^</){exit} on' | flat)"
check "S26-9 guardrails: the screenshot minimum names, in one except clause, each case where none can be taken -- all when Playwright couldn't be installed, the per-role ones when sign-in is left out, one a left-out item kept from being taken" \
  '[ -n "$GR" ] && [ "$(printf "%s" "$GR" | perl -ne "\$c += () = /\bexcept\b/gi; END { print \$c + 0 }")" = 1 ] && ! printf "%s" "$GR" | pm "[.;]\s+\S" && printf "%s" "$GR" | pm "\bexcept\b[^.;]*\ball of them when Playwright couldn.t be installed\b" && printf "%s" "$GR" | pm "\bexcept\b[^.;]*\bper.role ones when sign-in is left out\b" && printf "%s" "$GR" | pm "\bexcept\b[^.;]*\bleft.out item kept from being taken, which follows .left-out-record\.md" && ! printf "%s" "$GR" | pm "\bno exception|\beven (if|when)\b|\bunless\b|\bstill (required|needed|must)\b"'

# controls (the real try-it.md only): each check fails on its plain opposite
if [ -z "${1:-}" ]; then
  # opp ID PERL: the mutant differs from try-it.md, and this test run on it prints "FAIL ID"
  opp() { local m out; m="$(perl -0pe "$2" "$F")"; [ "$m" != "$T" ] || return 1; out="$(printf '%s\n' "$m" | bash "$SELF" - 2>/dev/null || true)"; printf '%s\n' "$out" | gq -E "^FAIL $1 "; }
  check "(control) S26-1 fails with the sign-in path gone (every page check skipped again)" \
    'opp S26-1 "s/If sign-in is left out \(a left-out item names it.*?\n\n//s"'
  check "(control) S26-1 fails with step 4 skipped when sign-in is left out" \
    'opp S26-1 "s/Step 4 still runs, once, without signing\s+in:/Step 4 is skipped, since nothing can sign in:/"'
  check "(control) S26-1 fails with the check signing in somewhere" \
    'opp S26-1 "s/this check signs in nowhere/this check signs in as the admin test user/"'
  check "(control) S26-2 fails with those page checks made the left-out item's" \
    'opp S26-2 "s/These page checks are not the left-out item.s/These page checks are the left-out item\x27s/"'
  check "(control) S26-2 fails with the pointer at read step 3 gone" \
    'opp S26-2 "s/\s*\(.left-out-record\.md. read\s+step 3\)//"'
  check "(control) S26-3 fails with the report listing those pages as left out" \
    'opp S26-3 "s/so it is listed as checked, with how its\s+check went, never as left out/so it is listed as left out/"'
  check "(control) S26-4 fails with \"a full report with screenshots\" said whatever was taken" \
    'opp S26-4 "s/I saved a full report\[only if screenshots were taken: . with screenshots.\]/I saved a full report with screenshots/"'
  check "(control) S26-5 fails with the \"Screenshots unavailable\" line gone from the report" \
    'opp S26-5 "s/ Otherwise, if no screenshot was taken.*?only if pages were tested\.\]/]/s"'
  check "(control) S26-6 fails with \"pages were tested\" said whether or not any were" \
    'opp S26-6 "s/ only if pages were tested\.\]/.]/"'
  check "(control) S26-6 fails with <error-handling>'s own note back (\"pages were tested but not captured\", unqualified)" \
    'opp S26-6 "s/- Say so in the report.s Screenshots section.*?when none were\)/- Note in report: \"Screenshots unavailable -- pages were tested but not captured\"/s"'
  check "(control) S26-7 fails with the kept-from-starting path gone" \
    'opp S26-7 "s/\*\*If a left-out item keeps the app from building or starting\*\*.*?\n\n//s"'
  check "(control) S26-7 fails with \"Everything is running!\" said anyway" \
    'opp S26-7 "s/never say\s+\"Everything is running!\"/say \"Everything is running!\"/"'
  check "(control) S26-7 fails with the left-out item fixed and retried" \
    'opp S26-7 "s/don.t fix it and don.t retry it/fix it and retry it/"'
  check "(control) S26-1 still fails with its opposite outside step 3 (\"If sign-in is left out, skip every page check.\" in step 4)" \
    'opp S26-1 "s/(\*\*4\. Test every page for each role \(and take screenshots\):\*\*\n\n)/\$1If sign-in is left out, skip every page check.\n\n/"'
  check "(control) S26-2 still fails with its opposite outside step 3 (\"If sign-in is left out, the existing pages belong to the left-out item.\" in step 4)" \
    'opp S26-2 "s/(\*\*4\. Test every page for each role \(and take screenshots\):\*\*\n\n)/\$1If sign-in is left out, the existing pages belong to the left-out item.\n\n/"'
  check "(control) S26-8 fails with the step-5 path gone (every endpoint left out again)" \
    'opp S26-8 "s/If sign-in is left out \(as in step 3\).*?\n\n//s"'
  check "(control) S26-8 fails with step 5 skipped when sign-in is left out" \
    'opp S26-8 "s/step 5 still runs,\s+without\s+a\s+token:/step 5 is skipped, since there is no token:/"'
  check "(control) S26-8 fails with the endpoint that needed sign-in marked left out" \
    'opp S26-8 "s/name it plainly in\s+the\s+report\s+as\s+not\s+checked,\s+never\s+as\s+left\s+out/mark it in the report as left out/"'
  check "(control) S26-8 fails with step 5 saying the report lists those endpoints as left out" \
    'opp S26-8 "s/the\s+report\s+lists\s+them\s+as\s+checked/the report lists them as left out/"'
  check "(control) S26-8 fails with the pointer at read step 3 gone from step 5" \
    'opp S26-8 "s/\s*\(.left-out-record\.md.\s+read\s+step\s+3\)(?=\s+is\s+left\s+out)//"'
  check "(control) S26-8 fails with the report's API row reading those endpoints as left out" \
    'opp S26-8 "s/\(Phase 2 step 5\),\s+as\s+checked,\s+never\s+as\s+left\s+out/(Phase 2 step 5), as left out/"'
  check "(control) S26-9 fails with the Playwright exception gone" \
    'opp S26-9 "s/\s+all\s+of\s+them\s+when\s+Playwright\s+couldn.t\s+be\s+installed,//"'
  check "(control) S26-9 fails with the sign-in per-role exception gone" \
    'opp S26-9 "s/\s+the\s+per-role\s+ones\s+when\s+sign-in\s+is\s+left\s+out,//"'
  check "(control) S26-9 fails with the rule back to no exception" \
    'opp S26-9 "s/ -- except any that couldn.t\s+be\s+taken:.*?which follows .left-out-record\.md./ -- no exception/s"'
  check "(control) S26-9 fails with the exceptions split over two clauses" \
    'opp S26-9 "s/couldn.t\s+be\s+installed,\s+the\s+per-role/couldn\x27t be installed. Except the per-role/"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
