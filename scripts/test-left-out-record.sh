#!/usr/bin/env bash
# E02-S10: the "left out by your choice" record is defined once and read the same way everywhere.
# Contract these checks pin (the change must satisfy it):
#   - ONE file, .claude/make-it/references/left-out-record.md, has the heading "## The left-out record".
#   - It names the file `.make-it-state.md` and the section heading "## Left out by your choice".
#   - retrofit-it (write) and try-it (read) name that same file + section and point at the definition file.
#   - try-it points at the definition; it does not carry the definition heading itself.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# review6 Minor 6: "grep -q" quits at its first match, so the perl or sed feeding it a long left-out section gets SIGPIPE,
# and under pipefail the pipe reads 141: a positive check goes red, a negated one green. gq reads all of its input, so every
# negated "! ... | grep -q" here is "! ... | gq" (final review X1).
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# final review X1: the whole run's stderr is caught. A bad regex or a helper called before its definition prints there, and a
# negated check reads that failure as a pass; the last check below fails on any of it (it is also shown again on exit).
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

DEF=.claude/make-it/references/left-out-record.md
RETRO=.claude/commands/retrofit-it.md
TRY=.claude/commands/try-it.md
STATE='.make-it-state.md'
SECTION='## Left out by your choice'
HEAD='^## The left-out record$'

# 1. exactly one definition across skills and references
defs="$(grep -rlE "$HEAD" .claude/commands .claude/make-it 2>/dev/null || true)"
check "exactly one file defines the left-out record" '[ "$(printf "%s" "$defs" | grep -c .)" = 1 ]'
check "the definition lives at $DEF" '[ "$defs" = "$DEF" ]'

# 2. the definition names the file and the exact section
check "definition names $STATE" '[ -f "$DEF" ] && grep -qF "$STATE" "$DEF"'
check "definition names the section \"$SECTION\"" '[ -f "$DEF" ] && grep -qF "$SECTION" "$DEF"'

# 3. write (retrofit-it) and read (try-it) name the same file + section, and point at the definition
for f in "$RETRO" "$TRY"; do
  check "$f names $STATE and \"$SECTION\"" "grep -qF '$STATE' $f && grep -qF '$SECTION' $f"
  check "$f points at left-out-record.md" "grep -qF 'left-out-record.md' $f"
done

# 4. try-it points rather than restates
check "try-it does not carry the definition heading" '! grep -qE "$HEAD" $TRY'
# position-free: the reference is cited (the @-include counts) at or before try-it's first use of the section
check "try-it cites the reference before its first use of the section" \
  'a=$(grep -nF left-out-record.md $TRY | head -1 | cut -d: -f1); b=$(grep -nF "$SECTION" $TRY | head -1 | cut -d: -f1); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -le "$b" ]'

# ---- the definition's meaning, not its strings ----
# helpers: flat TEXT; the text of the block under a "## " heading; the text of numbered read step N
flat() { tr '\n' ' ' | tr -s ' '; }
sec()  { awk -v h="$2" '/^## /{on=($0==h)} on' "$1"; }
step() { awk -v n="$2" '/^## /{on=0} /^[0-9]+\. /{on=($0 ~ "^"n"\\. ")} on' "$1"; }
READS="$(sec $DEF '## How a skill reads it' 2>/dev/null || true)"
RULE="$(sec $DEF '## The rule every reader follows' 2>/dev/null || true)"

# 5. entry shape: an example entry line with the item, its checks, and the date
check "definition shows an entry: item -- checks [IDs or none] -- left out [date]" \
  'grep -qE "^- .+ -- checks .+ -- left out .+" $DEF'
# 6. read steps: four numbered steps; the missing-file and missing-section cases are each handled
check "definition has four numbered read steps" '[ "$(printf "%s\n" "$READS" | grep -cE "^[1-4]\. ")" = 4 ]'
check "read step 1 handles a missing file" 'step $DEF 1 | flat | grep -qiE "no file.*nothing is left out"'
check "read step 2 handles a missing or empty section" 'step $DEF 2 | flat | grep -qiE "no section.*nothing is left out"'
# 7. each reader rule, by what it requires
check "rule: mentioned once, never offered (not in an ask or suggestion list)" \
  'printf "%s\n" "$RULE" | flat | grep -qiE "never offered.*never goes in an ask"'
check "rule: reads \"Left out (your choice)\", never FAIL, never counted or listed as an issue" \
  'printf "%s\n" "$RULE" | flat | grep -qiE "never fail.*Left out \(your choice\).*never counted.*never listed"'
check "rule: never put back on its own (no auto-fix, no app-code fix, never blocks)" \
  'printf "%s\n" "$RULE" | flat | grep -qiE "never put back.*no auto-fix.*no fix in app code.*never blocks"'
check "rule: at ship a [BLOCK] item is named in the high-stakes ask, user picks" \
  'printf "%s\n" "$RULE" | flat | grep -qiE "never silently blocked.*never silently passed.*high-stakes ask.*(user picks|the user picks)"'

# 8. read step 3: a left-out item owns any test that tests what it names, whether or not it has check IDs
check "read step 3: ownership by ID or by what a test tests (not only for an item with no checks)" \
  's=$(step $DEF 3 | flat); printf "%s" "$s" | grep -qF "tests what the item names" && printf "%s" "$s" | grep -qiE "ID is on the item.s line" && ! printf "%s" "$s" | gq -iE "no checks[^.]*tests what"'
# 9. "[BLOCK] item" is defined: any check that belongs to the item is [BLOCK] in build-standards.md
check "definition defines a [BLOCK] item by its checks' severity in build-standards.md" \
  'flat < $DEF | grep -qE "\[BLOCK\]. item (when|is|if)[^.]*(any|one) check[^.]*belong[^.]*\[BLOCK\][^.]*build-standards\.md" && ! flat < $DEF | gq -iE "\b(every|all|each) checks? [^.]*\bbelong"'
# 10. the section holds only entries; what follows has its own heading
check "definition: only entries go in the section; what follows starts with its own ## heading" \
  'flat < $DEF | grep -qiE "only entries[^.]*own .## . heading"'
# 11. the "no section" case must not drop items older state files carry elsewhere
check "read step 2: \"no section\" is conditional on no older left-out line elsewhere" \
  'step $DEF 2 | flat | grep -qiE "no section[^.:]*(elsewhere|other line|no line)[^.]*nothing is left out"'

# 12. one definition means nobody else restates the rule (not just: nobody else has the heading)
others="$(grep -rlE "Mentioned, never offered|Never put back on its own|brings an item back|The rule every reader follows" .claude/commands .claude/make-it 2>/dev/null | grep -vxF "$DEF" || true)"
check "no skill or reference other than the definition restates the reader rule" '[ -z "$others" ]'
# a mention of the record's file + section outside the definition must sit next to a pointer (within 3 lines)
unpointed="$(for f in $(ls .claude/commands/*.md .claude/make-it/references/*.md | grep -vxF "$DEF"); do
  awk -v f="$f" '{L[NR]=$0} END{for(i=1;i<=NR;i++){j=L[i]" "L[i+1]; if(tolower(j) ~ /left out by your choice/ && j ~ /make-it-state\.md/){ok=0; for(k=i-3;k<=i+4;k++) if(L[k] ~ /left-out-record\.md/) ok=1; if(!ok) print f":"i}}}' "$f"; done)"
check "every skill mention of the state file's left-out items sits next to a pointer to the definition" '[ -z "$unpointed" ]'

# 13. write side (retrofit-it): the write instruction itself names the file, the section and the definition
SAVE="$(awk '/Save project state/{on=1} on&&/^$/{exit} on' $RETRO)"
BULLET="$(awk '/^- Items the user left out/{on=1;print;next} on&&(/^- /||/^$/){exit} on' $RETRO | sed -E 's/<!--.*-->//g')"
check "retrofit-it Part E: the write instruction names $STATE" 'printf "%s\n" "$SAVE" | grep -qF "$STATE"'
check "retrofit-it Part E: the left-out bullet itself names \"$SECTION\" and the definition" \
  'printf "%s\n" "$BULLET" | grep -qF "$SECTION" && printf "%s\n" "$BULLET" | grep -qF left-out-record.md'

# 14. review2 fixes: what a left-out item can own, where the older-file fallback applies, who points where
# I-1: preservation checks (the app's existing features still work) are never owned by a left-out item
check "read step 3: a check that something the app already had still works never belongs to a left-out item" \
  'step $DEF 3 | flat | grep -qiE "(already had|already has|existing)[^.]*still works?[^.]*never belongs? to (a|an|any) left-out item" && ! step $DEF 3 | flat | gq -iE "never belongs? to (a|an|any) left-out item[^.]*(unless|except)"'
# I-2: the older-file fallback applies only to a state file with no such section
check "read step 2: the older-file fallback is limited to a state file with no such section" \
  'step $DEF 2 | flat | grep -qiE "(with no|without|lacks|only when there is no|only if there is no|only when the section is (missing|absent))[^.]*section[^.]*(may say|left out by your choice)"'
# Minor 1: try-it Phase 0 invokes the definition read steps, not only its rule
check "try-it Phase 0: the read of the section points at the definition read steps" \
  'awk -v s="$SECTION" "{L[NR]=\$0} END{for(i=1;i<=NR;i++) if(index(L[i],s)){j=L[i]\" \"L[i+1]\" \"L[i+2]\" \"L[i+3]; exit !(tolower(j) ~ /read steps|how a skill reads it/ && j ~ /left-out-record\.md/)}; exit 1}" $TRY'
# Minor 2: rule 1 vs rule 4: the ship ask is the stated exception to "never goes in an ask"
check "rule: \"never goes in an ask\" names the ship ask as the one exception" \
  'printf "%s\n" "$RULE" | flat | grep -qiE "never goes in an ask[^.]*\([^)]*ship[^)]*exception"'
# Minor 3: step 4 names the section, not "here"
check "read step 4: names the section it deletes the line from (not \"here\")" \
  's=$(step $DEF 4 | flat); printf "%s" "$s" | grep -qF "$SECTION" && ! printf "%s" "$s" | gq -iE "line here"'
# Minor: retrofit-it Phase 6 skip rule points at the definition instead of restating it alone
SKIP="$(awk '/Left-out items \(the user/{on=1} on&&/^$/{exit} on' $RETRO)"
check "retrofit-it Phase 6: the left-out skip sentence sits in a block that points at left-out-record.md" \
  '[ -n "$SKIP" ] && printf "%s\n" "$SKIP" | grep -qF left-out-record.md'

# 15. review3 fixes: emptied section, fix ownership, older-file moves, rules pinned through their end
# A: a section that exists but has no entries means nothing is left out (no fallback to older lines)
# (steps 2 and 4 carry no qualifier anywhere: a whole-step ban on unless|except. Step 3 is whole-step too.)
check "read step 2: a section with no entries means nothing is left out (no qualifier in the step)" \
  's=$(step $DEF 2 | flat); printf "%s" "$s" | grep -qiE "section with no entries: nothing is left out\." && ! printf "%s" "$s" | gq -iE "unless|except"'
# the drop ban keys on the heading/section as the object ("deletes the section"), not on any later mention ("under the section")
check "read step 4: the heading stays even with no entries left (no qualifier in the step, heading never dropped)" \
  's=$(step $DEF 4 | flat); printf "%s" "$s" | grep -qiE "heading stays, even with no entries left\." && ! printf "%s" "$s" | gq -iE "unless|except" && ! printf "%s" "$s" | gq -iE "(drop|delet|remov)[a-z]* [^.]*(heading|section)|(heading|section)[^.]*(is|are) (drop|delet|remov)" && ! printf "%s" "$s" | sed "s/section line/SL/g" | gq -iE "(drop|delet|remov|omit)[a-z]* [^.(]*(heading|section)|(heading|section)( itself)? (is|are|goes|gets)( [a-z]+)? (dropped|deleted|removed|omitted)"'
check "Where: a rewrite keeps the section as it is, and no sentence there drops, removes or deletes the section" \
  'w=$(sec $DEF "## The left-out record" | flat); printf "%s" "$w" | grep -qiE "rewrites [^ ]*make-it-state\.md[^ ]* keeps this section as it is" && ! printf "%s" "$w" | gq -iE "(drop|delet|remov|omit)[a-z]* [^.]*(the|this) section"'
# B: a fix has an owner; it may not add a left-out item back
check "read step 3: a fix belongs to its failure.s item and to any item whose code it would add (no qualifier, no kept item may add one)" \
  's=$(step $DEF 3 | flat); printf "%s" "$s" | grep -qiE "a fix belongs to the item its failure belongs to, and to any item whose code it would add\." && ! printf "%s" "$s" | gq -iE "unless|except" && ! printf "%s" "$s" | gq -iE "kept item[^.]*(needs?|may|can)[^.]*add|fix[^.]*(may|can|might|is allowed to)[^.]*(still )?add"'
# C: a failure only a left-out item.s code would fix belongs to that item too, but a preservation check never does
check "read step 3: a failure only a left-out item.s code would fix belongs to that item too, with the preservation carve-out" \
  'step $DEF 3 | flat | grep -qiE "failure that only a left-out item.s code would fix belongs to that item too[;.] [^.]*(already had|already has|existing)[^.]*still never does\."'
# review3 Minor 1: applying an item clears every line step 2 read; adding the section to an older file moves the older lines in
check "read step 4: deletes every line step 2 read for the item (the section line and an older file.s own lines)" \
  's=$(step $DEF 4 | flat); printf "%s" "$s" | grep -qiE "deletes every line step 2 read for it \([^)]*Left out by your choice[^)]*older file[^)]*each line that says so[^)]*\)" && ! printf "%s" "$s" | gq -iE "unless|except"'
check "Where: adding the section, to an older file or in a new one, first moves the older left-out lines into it" \
  'sec $DEF "## The left-out record" | flat | grep -qiE "adds the section, to an older file or in a new one, first moves the older left-out lines[^.]*into it\."'
# review4 Minor 1: a moved line becomes one `- ` entry in the entry form, so step 2 reads it
check "Where: each moved item becomes one - entry in the entry form (checks: the IDs any of its lines names, none when none does)" \
  'sec $DEF "## The left-out record" | flat | grep -qiE "each item becomes one .- . entry in the form below \(checks: the IDs any of its lines names, .none. when none does\)"'
# Minor 2: step 4 TODO.md clause
check "read step 4: also deletes the item.s left-out line in TODO.md" \
  'step $DEF 4 | flat | grep -qiE "item.s .left out by your choice. line in TODO\.md"'
# review5 D: an absorbed failure is not "passed" either -- the skill says what it could not check
rb() { printf "%s\n" "$RULE" | awk -v n="- **$1" 'index($0,n)==1{on=1;print;next} /^- /{on=0} on' | flat; }
check "rule: a left-out item's failure is never reported as passed; say what could not be checked because of it" \
  'rb "Never FAIL" | grep -qF "It is never reported as passed either: say what could not be checked because of it."'
# review5 E: rules 2 and 4 cover a failure that belongs to the item, not only a check or test that does
check "rule: Never FAIL covers a check or test that belongs to it, or whose failure does" \
  'rb "Never FAIL" | grep -qiE "(check|test) that belongs to it, or whose failure does"'
check "rule: At ship names a [BLOCK] item by any check that belongs to it, or whose failure does" \
  'rb "At ship" | grep -qiE "check that belongs to it, or whose failure does \(read step 3\)"'
# Minor 3: plain wording for the one-line mention, everywhere it is given
check "mention wording is \"tell me if you want it added\", never \"say the word\"" \
  'printf "%s\n" "$RULE" | flat | grep -qiE "tell me if you want it added" && ! grep -rqiE "say the word" .claude/commands .claude/make-it'

# review7 (adversarial round 1): a change of mind, a request in the user's words, and try-it's whole scope
sentences() { flat | sed 's/\. /.\
/g'; }
# #2: the definition's writers include a mid-run change of mind (check-ins included)
check "definition: a user taking an item out at any point (check-ins included) is an answer that writes the record" \
  'sentences < $DEF | grep -iE "check-in" | grep -iE "at any point|any time|mid-run|change of mind|changes? (their|his|her) mind" | grep -qiE "writ(es|ten)|record"'
# #4: the user's own words asking for a left-out feature are their answer; building it clears the record
check "read step 4: a request in the user's own words for what an item names is their answer (so building it clears the record)" \
  'step $DEF 4 | sentences | grep -iE "own words" | grep -qiE "(is|counts as|as) (their|the user.s) (own )?answer"'
check "read step 4: a skill may ask one plain question to confirm it is that item" \
  'step $DEF 4 | sentences | grep -iE "(one|a single) plain question" | grep -qiE "confirm|is (it|that)"'
check "rule: the mention rule still has no ask in it for an unprompted offer" \
  'rb "Mentioned" | grep -qiE "never goes in an ask" && ! rb "Mentioned" | gq -iE "plain question"'
# #3: try-it follows the rule in Phase 0 (step 3b auto-fixes) and <error-handling>, and generates nothing for a left-out item
PTR="$(awk '/^From \.make-it-state\.md/{on=1} on&&/^$/{exit} on' $TRY | flat)"
check "try-it pointer: scope names Phase 0 and error-handling (or everywhere in this skill), not only \"every phase below\"" \
  '[ -n "$PTR" ] && printf "%s" "$PTR" | grep -qiE "(everywhere|anywhere) in this skill|Phase 0[^.]*error.handling|error.handling[^.]*Phase 0"'
check "try-it pointer or definition rule 3: no auto-fix and no generating anything for a left-out item" \
  '{ printf "%s\n" "$PTR"; rb "Never put back"; } | flat | grep -qiE "no (auto-fix|generat)[^.]*generat|generat[^.]*auto-fix"'

# adv2 #1: the preservation carve-out must not cover what the user took out (else a removed feature FAILs every run)
check "read step 3: both carve-out sentences exempt what the user took out (already had (and the user did not take out))" \
  '[ "$(step $DEF 3 | sentences | grep -iE "never belongs to a left-out item|still never does" | grep -ciE "already had \(and the user did not take out\)")" = 2 ]'

# adv3 #1: bringing back only PART of an item narrows its line to the part still left out
check "read step 4: bringing back only part of an item replaces every line step 2 read for it with one line for the part still left out (that part's checks), keeping its TODO.md line, narrowed the same way" \
  's=$(step $DEF 4 | sentences | grep -iE "only part of an item"); printf "%s\n" "$s" | grep -iE "replaces every line step 2 read for it with one line" | grep -iE "part still left out" | grep -iE "checks" | grep -iE "TODO\.md" | grep -iE "keeps" | gq -iE "narrowed the same way" && ! printf "%s\n" "$s" | gq -iE "TODO\.md line,? (as it is|unchanged|whole)"'
check "read step 4: the part case never deletes the whole line and never keeps the applied part" \
  'p=$(step $DEF 4 | sentences | grep -iE "only part of an item"); [ -n "$p" ] && ! printf "%s" "$p" | gq -iE "delet|remov|keeps? (the|its) (whole|applied)"'

# review8 Minor 1: a take-out is marked "(taken out)" after the date; only a marked line is exempt from the carve-out
check "entry form: the entry line shows an optional \"(taken out)\" after the date" \
  'grep -qE "^- .*left out \[YYYY-MM-DD\].*\(taken out\)" $DEF && sentences < $DEF | grep -iF "(taken out)" | grep -qi "optional"'
check "Where: a \"take it out\" writes its line with \"(taken out)\" after the date" \
  'sec $DEF "## The left-out record" | sentences | grep -iE "take it out" | grep -qF "\"(taken out)\" after the date"'
check "read step 3: the user took out only what a line marked \"(taken out)\" names" \
  'step $DEF 3 | sentences | grep -qiE "the user took out only what a line marked .\(taken out\). names"'
check "definition: an entry with no marker (older entry) is read as left out at plan time" \
  'sentences < $DEF | grep -iE "no marker|without (it|the marker)|lacks (it|the marker)" | grep -qiE "plan"'

# ---- Task 2: resume-it never re-offers a left-out item and writes the record at its catch-up ----
RESUME=.claude/commands/resume-it.md
PHRASE='left out by your choice -- tell me if you want it added'
# text from the line containing anchor $2 up to (not including) the line containing anchor $3
between() { awk -v a="$2" -v b="$3" 'index($0,a){on=1} on&&index($0,b)&&!index($0,a){exit} on' "$1"; }
# the 4 lines starting at the line containing anchor $2
win() { awk -v a="$2" 'index($0,a){n=5} n>0{print;n--}' "$1"; }
STEP8="$(between $RESUME '**8. Standards catch-up scan' '**9. Build an internal context summary')"
GAPS_TXT="$(between $RESUME '**When standards gaps are found, present them' '**If the user accepts the catch-up work')"
ACCEPT="$(between $RESUME '**If the user accepts the catch-up work' 'When the gaps are INDEPENDENT')"
# a left-out sentence that keeps the item out of groups/ask (not just the word "left out")
excl() { sentences | grep -iE "left out by your choice|left-out" | grep -iE "must-do|improvement|gaps? list|\bask\b|to-do|todo" | grep -qiE "\b(not|never|no)\b|out of|exclud|without|kept out|leave[s]? (it|them) out|skip"; }

# T2-1: resume-it reads the record through the definition, before it builds the gaps list (step 8d)
check "resume-it step 8 points at left-out-record.md before it builds the gaps list" \
  'a=$(printf "%s\n" "$STEP8" | grep -nF left-out-record.md | head -1 | cut -d: -f1); b=$(printf "%s\n" "$STEP8" | grep -nF "Build a gaps list" | head -1 | cut -d: -f1); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]'
check "resume-it step 8 pointer sits with a read of the section (read steps / $SECTION)" \
  'printf "%s\n" "$STEP8" | awk "{L[NR]=\$0} END{for(i=1;i<=NR;i++) if(index(L[i],\"left-out-record.md\")){j=L[i]\" \"L[i-1]\" \"L[i+1]\" \"L[i+2]; exit !(tolower(j) ~ /read steps|how a skill reads it|make-it-state\.md|left out by your choice/)}; exit 1}"'

# T2-2: a left-out item is kept out of the must-do / improvements groups and their ask
check "resume-it step 8 keeps left-out items out of the gaps list / must-do and improvements groups" \
  'printf "%s\n" "$STEP8" | excl'
check "resume-it no longer tells the user the next catch-up scan raises left-out items again" \
  '! grep -qiE "raise them again|will mention it again|scan will (raise|mention)" $RESUME'
# the ask block itself: no left-out item inside the counts or the question
check "resume-it greet-and-suggest keeps left-out items out of the counts and the ask" \
  'printf "%s\n" "$GAPS_TXT" | excl'
# the three to-do-list offers (table row, option C, readiness "what is next")
check "resume-it to-do offer (TODO.md has items row) excludes left-out items" \
  'win $RESUME "| TODO.md has items |" | sentences | grep -iE "left out by your choice|left-out" | grep -qiE "\b(not|never|no)\b|out of|exclud|without|skip"'
check "resume-it option C (work on TODO items) excludes left-out items from what it shows" \
  'win $RESUME "**C. Work on TODO items:**" | sentences | grep -iE "left out by your choice|left-out" | grep -qiE "\b(not|never|no)\b|out of|exclud|without|skip"'
check "resume-it readiness \"what is next\" from TODO.md excludes left-out items" \
  'win $RESUME "[Next work item from TODO.md" | sentences | grep -iE "left out by your choice|left-out" | grep -qiE "\b(not|never|no)\b|out of|exclud|without|skip"'

# T2-3: exactly one plain mention, never with an ask
check "resume-it gives the one-line mention: \"$PHRASE\"" 'grep -qiF "$PHRASE" $RESUME'
check "resume-it mention carries no question (never with an ask)" \
  'grep -iF "$PHRASE" $RESUME | grep -qv "?" && ! grep -iF "$PHRASE" $RESUME | gq "?"'
check "resume-it mention is not inside the catch-up ask (the Which-should-I-apply question)" \
  '[ -n "$(grep -iF "$PHRASE" $RESUME)" ] && ! win $RESUME "Which should I apply" | gq -iF "$PHRASE" && ! grep -iF "$PHRASE" $RESUME | gq -iE "which should|want me to|should I|apply the"'

# T2-4: the catch-up writes the record (not only TODO.md) for every item the user names to leave out, on ANY answer
# (fix round 1: "not now", "just the improvements", "both, but skip X", either group). The write must not live
# only in catch-up step 1, which runs only when the must-do group is applied.
CU="$(between $RESUME '**When standards gaps are found' 'When the gaps are INDEPENDENT')"
# the catch-up block without numbered step 1 (the must-do group) -- the rule must stand outside it
CU_OUT="$(printf "%s\n" "$CU" | awk 'index($0,"1. Apply all critical gaps first"){skip=1} index($0,"2. Apply important"){skip=0} !skip')"
# the sentence naming the section, with the sentence before and after (a rule may run over two or three sentences)
rulewin() { printf "%s\n" "$CU_OUT" | sentences | awk -v s="$SECTION" '{L[NR]=$0} END{for(i=1;i<=NR;i++) if(index(L[i],s)) print L[i-1] " " L[i] " " L[i+1]}'; }
check "resume-it writes every named leave-out under \"$SECTION\" in $STATE, outside the must-do step" \
  'w=$(rulewin); printf "%s" "$w" | grep -qF "$SECTION" && printf "%s" "$w" | grep -qF "$STATE"'
check "that write runs on any answer: \"not now\" included, and for either group (must-do or improvement)" \
  'w=$(rulewin); printf "%s" "$w" | grep -qiE "whatever|regardless|any answer|every answer|no matter|on any" && printf "%s" "$w" | grep -qiE "not now" && printf "%s" "$w" | grep -qiE "improvement" && printf "%s" "$w" | grep -qiE "must-do|either group|both groups|any group"'
check "an improvement group the user simply did not pick is a deferral, not recorded as left out" \
  'w=$(rulewin); printf "%s" "$w" | grep -qiE "didn.t (name|pick|choose|select)|did not (name|pick|choose|select)|not (named|picked|chosen|selected)|put(ting)? (it |them )?off|deferr" && printf "%s" "$w" | grep -qiE "(isn.t|aren.t|is not|are not|nothing else|only)[^.]*(written|recorded|record)"'
check "resume-it catch-up writes the line in the definition's form (item, checks, date)" \
  'w=$(printf "%s\n" "$CU_OUT" | flat); printf "%s" "$w" | grep -iE "$SECTION" | grep -qiE "checks" && printf "%s" "$w" | grep -qiE "$SECTION[^.]*(date|left out \[)|(date|left out \[)[^.]*$SECTION|checks[^.]*date|date[^.]*checks"'
check "resume-it catch-up still lists the left-out item in TODO.md (the user's to-do list, not the record)" \
  'rulewin | grep -qiE "TODO\.md"'
check "resume-it catch-up report says what was left out without promising it will be raised again" \
  'p=$(printf "%s\n" "$ACCEPT" | flat); printf "%s" "$p" | grep -qiE "left out by your choice" && ! printf "%s" "$p" | gq -iE "raise them again|mention it again|raised again"'

# T2-6 (fix round 1): one skill-wide pointer at or before discovery step 1 -- bring back / narrow / take out follow the definition
PRE="$(awk '/^<process>/{on=1} /\*\*1\. Look for the make-it state breadcrumb/{exit} on' $RESUME)"
ptr() { printf "%s\n" "$PRE" | awk '{L[NR]=$0} END{for(i=1;i<=NR;i++) if(index(L[i],"left-out-record.md")){for(k=i-3;k<=i+4;k++) printf "%s ", L[k]; print ""}}' | flat; }
check "resume-it points at left-out-record.md at or before discovery step 1 (read step 4, and its write)" \
  'p=$(ptr); printf "%s" "$p" | grep -qiE "read step 4"'
check "that pointer covers bringing back, narrowing and taking out" \
  'p=$(ptr); printf "%s" "$p" | grep -qiE "bring(s|ing)?[^.]{0,30} back|brought[^.]{0,30} back" && printf "%s" "$p" | grep -qiE "narrow" && printf "%s" "$p" | grep -qiE "take(s|n)?[^.]{0,20} out|taking"'
check "that pointer says nothing puts a left-out item back on its own" \
  'p=$(ptr); printf "%s" "$p" | grep -qiE "(nothing|never|no)[^.]*back on its own|on its own"'

# T2-7 (fix round 1): the ask promises only a mention next time, not "not offer it again"
check "resume-it ask does not promise \"not offer it again\"" \
  '! printf "%s\n" "$GAPS_TXT" | flat | gq -iE "(not|never|won.t|n.t) (be )?(re-?)?offer(ed|ing)?( it)?( again)?"'
check "resume-it ask says next time the item is only mentioned, not asked" \
  'printf "%s\n" "$GAPS_TXT" | flat | grep -qiE "next time[^.]*(only|just) mention[^.]*not ask"'

# T2-8 (fix round 1): the plain mention appears exactly once for a session, in greet step 2 -- not in the gaps summary or the ask
GREET2="$(between $RESUME '**2. Present a brief status summary' '**3. Generate suggested actions')"
check "resume-it greet step 2 carries the plain mention exactly once" \
  '[ "$(printf "%s\n" "$GREET2" | flat | grep -oiF "$PHRASE" | wc -l | tr -d " ")" = 1 ]'
check "resume-it gaps summary and ask do not repeat the plain mention" \
  '! printf "%s\n" "$GAPS_TXT" | flat | gq -iF "$PHRASE"'

# T2-9 (adversarial round 1, #1): a leave-out the released resume-it (v1.44.0-v1.44.12) wrote ONLY to TODO.md is read as left out.
# It lives in the definition (read step 2's no-section fallback + the move into the section), not restated in resume-it.
S2="$(step $DEF 2 | sentences)"
check "read step 2: with no section, a TODO.md \"left out by your choice\" line is an item too" \
  'printf "%s\n" "$S2" | grep -iE "TODO\.md" | grep -iE "left out by your choice" | grep -qiE "no (such )?section|without (a|the) section|older|before it existed"'
check "read step 2: that TODO.md fallback applies only while the section is missing (once it exists, a TODO.md line alone means nothing)" \
  'printf "%s\n" "$S2" | grep -iE "TODO\.md" | grep -iE "left out by your choice" | grep -qiE "\b(only|no|without|missing|not yet|none)\b[^.]*section|section[^.]*\b(missing|absent|does not exist|doesn.t exist|not there)\b"'
check "definition: adding the section moves the TODO.md leave-out lines into it (the record becomes the one authority)" \
  '{ sec $DEF "## The left-out record"; step $DEF 2; } | sentences | grep -iE "\bmov(e|es|ed|ing)\b" | grep -iE "TODO\.md" | grep -qiE "into (it|the section|that section)|to (it|the section)"'
check "resume-it still does not restate the TODO.md fallback (step 8 only points at the definition)" \
  '! printf "%s\n" "$STEP8" | sentences | grep -iE "TODO\.md" | grep -iE "left out by your choice" | gq -iE "no (record|section)|older|released|before"'

# T2-10 (adversarial round 1, #2 + review2 Minor 2): nothing is generated or fixed for a left-out item in test setup or scanner remediation.
# Covered either by the skill-wide pointer naming the phase, or by the step itself reading the record through the definition.
blk() { awk -v a="$2" 'index($0,a){on=1} on{print} on&&index($0,"</step>"){exit}' "$1"; }
TESTSETUP="$(blk $RESUME '<step name="test-setup">')"
SCANNER="$(blk $RESUME '<step name="security-scanner-remediation">')"
# the step names the definition and says what a left-out item gets (skipped / reported), in one sentence
stepcovers() { printf "%s\n" "$1" | grep -qF left-out-record.md && printf "%s\n" "$1" | sentences | grep -iE "left.out" | grep -qiE "skip|report|not (generate|scaffold|fix|set up)|never|no (test|scaffold|fix)|without"; }
check "test setup / scaffolding gets nothing generated for a left-out item (pointer names it, or the step reads the record via the definition)" \
  'p=$(ptr); { printf "%s" "$p" | grep -qiE "test[- ]setup|scaffold" ; } || stepcovers "$TESTSETUP"'
check "scanner remediation fixes nothing silently for a left-out item (pointer names it, or the step reads the record via the definition)" \
  'p=$(ptr); { printf "%s" "$p" | grep -qiE "scanner|remediation" ; } || stepcovers "$SCANNER"'
check "the two steps were found (guards the checks above against a moved anchor)" \
  '[ -n "$TESTSETUP" ] && [ -n "$SCANNER" ]'

# T2-11 (review 3): one item one entry; no state file; a moved line's date; scanner reports, never blocks; try-it's read; resume-it moves TODO-only leave-outs in
WHERE="$(sec $DEF '## The left-out record' | sentences)"
check "definition: the same item read on two lines is one item, one entry when moved (read step 2 or the move)" \
  '{ printf "%s\n" "$WHERE"; printf "%s\n" "$S2"; } | grep -iE "same item" | grep -iE "two lines|more than one line|both lines|several lines|each line" | grep -qiE "one item" && { printf "%s\n" "$WHERE"; printf "%s\n" "$S2"; } | grep -iE "same item" | grep -qiE "one entry|moved|moves|move"'
S1="$(step $DEF 1 | sentences)"
check "read step 1: with no .make-it-state.md, a TODO.md line (step 2) can still name an item" \
  'printf "%s\n" "$S1" | grep -iE "no file" | grep -qiE "TODO\.md"'
check "read step 1: with no file and no such line, nothing is left out (the empty case is kept)" \
  'step $DEF 1 | flat | grep -qiE "no file.*(none|no such|neither|without|no (todo|line)).*nothing is left out"'
check "definition: a moved line with no date of its own takes the date it is moved (today's date)" \
  'sentences < $DEF | grep -iE "no date|without a date|has no date|lacks a date" | grep -qiE "today|date (it is|they are|of the) mov|the day (it is|they are) mov"'
SC_LO="$(printf "%s\n" "$SCANNER" | sentences | grep -iE "left.out|left-out-record" || true)"
check "scanner remediation: a finding that belongs to a left-out item is not fixed" \
  'printf "%s\n" "$SC_LO" | grep -iE "finding" | grep -qiE "not fix|never fix|left as it is|isn.t fixed|is not fixed|no fix|skip"'
check "scanner remediation: that finding gets one plain line to the user, with no scan detail" \
  'printf "%s\n" "$SC_LO" | grep -iE "one (plain )?line|a plain line|one short line" | grep -qiE "no scan detail|without scan detail|no (CVE|scan|technical)|not the scan|no detail"'
check "scanner remediation: that finding does not hold up the user's work" \
  'printf "%s\n" "$SC_LO" | grep -iE "finding" | grep -qiE "(not|n.t|never|no)[^.]{0,30}(block|hold|wait|delay)|doesn.t hold"'
check "the skill-wide pointer's list also names step 6b's dependency auto-fix" \
  'p=$(ptr); printf "%s" "$p" | grep -qiE "dependenc|6b"'
TRY_P="$(between $TRY '**2. Extract key information' 'From app-context.json')"
TRY_LIST="$(between $TRY '**1. Read project state files' '**2. Extract key information')"
check "try-it Phase 0: the lead-in no longer limits the items to .make-it-state.md" \
  'f=$(printf "%s\n" "$TRY_P" | tail -n +2 | sentences | grep . | head -1); [ -n "$f" ] && ! { printf "%s" "$f" | gq -F "$STATE" && ! printf "%s" "$f" | gq -F "TODO.md"; }'
check "try-it Phase 0: the lead-in points at the definition's read steps" \
  'printf "%s\n" "$TRY_P" | flat | grep -qiE "read steps" && printf "%s\n" "$TRY_P" | grep -qF left-out-record.md'
check "try-it Phase 0: the read names TODO.md (list or lead-in) or defers to the definition" \
  'printf "%s\n%s\n" "$TRY_LIST" "$TRY_P" | grep -qiE "TODO\.md|fallback"'
check "resume-it: leave-outs found only in TODO.md are moved into the section (following the definition), so the record no longer rests on the to-do list" \
  'printf "%s\n" "$STEP8" | sentences | awk "{L[NR]=\$0} END{for(i=1;i<=NR;i++) if(L[i] ~ /TODO\.md/ && tolower(L[i]) ~ /left.out|left out by your choice/ && L[i] ~ /[Mm]ov(e|es|ed|ing)|[Ww]rit(e|es|ing)[^.]*section/){j=L[i-1]\" \"L[i]\" \"L[i+1]; if(j ~ /left-out-record\.md|definition|read steps/) f=1}; exit !f}" && printf "%s\n" "$STEP8" | sentences | grep -iE "TODO\.md" | grep -iE "left.out|left out by your choice" | grep -qE "[Mm]ov(e|es|ed|ing)"'

# T2-12 (adversarial round 2, #1): a bring-back keeps the gate the catch-up ask would have used for that item.
# Pinned in read step 4, where every bring-back routes (resume-it's pointer sends the reply there).
S4="$(step $DEF 4 | sentences)"
check "read step 4: applying a brought-back item goes through the same ask, at the same tier, as the catch-up ask" \
  'printf "%s\n" "$S4" | grep -iE "catch-up" | grep -qiE "same (ask|tier|gate)"'
check "read step 4: a high-stakes item (sign-in, roles) brought back gets active confirmation" \
  'printf "%s\n" "$S4" | grep -iE "high-stakes" | grep -qiE "active confirmation"'
check "read step 4: that high-stakes bring-back is never a plain yes" \
  'printf "%s\n" "$S4" | grep -iE "high-stakes|active confirmation" | grep -qiE "(never|not|n.t|no)[^.]{0,30}plain .?yes|plain .?yes[^.]{0,30}(is not|isn.t|never|not enough)"'
check "read step 4: the confirming \"plain question\" is not the gate" \
  'printf "%s\n" "$S4" | awk "/plain question/{print; getline; print}" | grep -qiE "\b(not|isn.t|never|no)\b[^.]{0,40}(gate|high-stakes|active confirmation|approval)|(gate|high-stakes|active confirmation|approval)[^.]{0,40}\b(not|isn.t|never|no)\b"'
check "resume-it pointer still reaches read step 4 for every bring-back (the gate lives there)" \
  'p=$(ptr); printf "%s" "$p" | grep -qiE "read step 4" && printf "%s" "$p" | grep -qiE "bring(s|ing)?[^.]{0,30} back"'

# T2-13 (adversarial round 2, #2): with no state file (or no section), TODO.md leave-outs grouped under a heading are items,
# one per line under it; the heading line itself is never an item. Pinned in read step 2's TODO.md rule.
check "read step 2: TODO.md lines listed under a heading that says \"left out by your choice\" are items, one per line" \
  'printf "%s\n" "$S2" | grep -iE "TODO\.md" | grep -iE "heading" | grep -iE "left out by your choice" | grep -qiE "under|beneath" && printf "%s\n" "$S2" | grep -iE "TODO\.md" | grep -iE "heading" | grep -qiE "each|every|one per line|per line"'
check "read step 2: the TODO.md heading line itself is never an item" \
  'printf "%s\n" "$S2" | grep -iE "TODO\.md" | grep -iE "heading" | grep -qiE "heading (line )?(itself )?(is )?(never|not)[^.]{0,20}(an )?item|(never|not)[^.]{0,20}(an )?item[^.]{0,20}heading|heading[^.]{0,30}(is not|isn.t|never)"'

# T2-5: resume-it points at the definition and does not restate it
check "resume-it does not carry the definition heading" '! grep -qE "$HEAD" $RESUME'
check "resume-it does not restate the reader rule (never counted, Left out (your choice), put back, brings an item back)" \
  '! grep -qE "Mentioned, never offered|Never put back on its own|brings an item back|The rule every reader follows|Left out \(your choice\)|never counted|Never FAIL" $RESUME'
check "resume-it points at left-out-record.md" 'grep -qF left-out-record.md $RESUME'
check "every resume-it use of \"$SECTION\" sits near a pointer to left-out-record.md (within 6 lines)" \
  'n=$(grep -cF "$SECTION" $RESUME); [ "$n" -ge 1 ] && awk -v s="$SECTION" "{L[NR]=\$0} END{for(i=1;i<=NR;i++) if(index(L[i],s)){ok=0; for(k=i-6;k<=i+6;k++) if(index(L[k],\"left-out-record.md\")) ok=1; if(!ok) bad=1}; exit bad+0}" $RESUME'


# ---- Task 3: try-it's report shows left-out rows as left out, never FAIL or passed ----
# text of one <step name="..."> (tags excluded)
stepof() { awk -v n="<step name=\"$2\">" 'index($0,n){on=1;next} on&&/^<\/step>/{exit} on' "$1"; }
# sentences, also split at ".[" (a bracketed alternative glued to the previous sentence)
sents2() { flat | sed 's/\. /.\
/g; s/\.\[/.\
[/g'; }
# blank-line-separated paragraphs of stdin, each flattened to one line
paras() { awk 'BEGIN{RS="";ORS="\n"} {gsub(/\n/," "); print}'; }
LO='left.out|leave out|left out'
NEG='never|not |n.t |exclud|without|no '
T3_FIX="$(stepof $TRY fix-issues)"
T3_REP="$(stepof $TRY generate-report)"
T3_HAND="$(stepof $TRY user-handoff)"
T3_EXP="$(stepof $TRY explore-support)"
T3_SAVE="$(stepof $TRY save-state)"
check "T3 anchors found (guards the checks below against a moved anchor)" \
  '[ -n "$T3_FIX" ] && [ -n "$T3_REP" ] && [ -n "$T3_HAND" ] && [ -n "$T3_EXP" ] && [ -n "$T3_SAVE" ]'

# 1. the "never include left-out items" note sits outside every user-facing quote (as the Phase 3 note does)
t3_note_outside_quote() {
  printf "%s\n" "$T3_HAND" | awk '
    /^"/{inq=1}
    /never (include|count)s? left-out/{found=1; if(inq) bad=1}
    /"$/ && length($0)>1{inq=0}
    END{exit !(found && !bad)}'
}
check "Phase 5: the \"never include left-out items\" note exists and sits outside the user-facing quote" t3_note_outside_quote
t3_fix_note_outside_quote() {
  printf "%s\n" "$T3_FIX" | awk '
    /^"/{inq=1}
    /never counts? left-out/{found=1; if(inq) bad=1}
    /"$/ && length($0)>1{inq=0}
    END{exit !(found && !bad)}'
}
check "(control, passes today) Phase 3: the \"never counts left-out items\" note sits outside its quote" t3_fix_note_outside_quote

# 2. a left-out row reads "Left out (your choice)": the three tables, and what that reading means
for sect in "## Summary|## Login Testing" "## Login Testing|## Pages Tested" "## Pages Tested|## Screenshots"; do
  a="${sect%%|*}"; b="${sect##*|}"
  check "report table under \"$a\" shows a left-out row as \"Left out (your choice)\"" \
    "between $TRY '$a' '$b' | grep -qF 'Left out (your choice)'"
done
# the rule sentences live after the report's code fence; each "never" is bound to its own term
T3_AFTER="$(printf "%s\n" "$T3_REP" | awk '/^```/{n++;next} n>=2')"
REPS="$(printf "%s\n" "$T3_AFTER" | sents2 | grep -F 'Left out (your choice)' || true)"
check "report: \"Left out (your choice)\" is never FAIL" \
  'printf "%s\n" "$REPS" | grep -qE "(never|\bnot\b|n[^[:alnum:] ]t)[^.,;]{0,15}FAIL"'
check "report: a \"Left out (your choice)\" row is never counted in X of Y" \
  'printf "%s\n" "$REPS" | grep -qiE "(never|\bnot\b|n[^[:alnum:] ]t)[^.,;]{0,20}(counted|count|included?)[^.,;]{0,12}X of Y|exclud[^.,;]{0,20}X of Y"'
check "report: a \"Left out (your choice)\" row is never listed under Issues Found" \
  'printf "%s\n" "$REPS" | grep -qiE "(never|\bnot\b|n[^[:alnum:] ]t)[^.,;]{0,20}(listed|list|shown|included?)[^.,;]{0,15}Issues Found|exclud[^.,;]{0,20}Issues Found"'
check "report: a \"Left out (your choice)\" row is never reported as passed" \
  'printf "%s\n" "$REPS" | sed -E "s/(never|not)[^.,;]{0,15}PASS[^.,;]{0,15}0 of 0//" | grep -qE "(never|\bnot\b|n[^[:alnum:] ]t)[^.,;]{0,15}(PASS|passed)"'

# 3. no [N]-style placeholder means two things: the unfixed count (Phase 3) and the left-out count (Phases 4-5)
tok() { grep -oE '\[[A-Za-z_]{1,12}\]' | head -1; }
T3_U="$(printf "%s\n" "$T3_FIX" | flat | grep -oE '\[[A-Za-z_]{1,12}\] thing\(s\)' | tok || true)"
T3_REPHAND="$(printf "%s\n%s\n" "$T3_REP" "$T3_HAND")"
T3_L="$(printf "%s\n" "$T3_REPHAND" | flat | grep -oE '\[[A-Za-z_]{1,12}\] item\(s\)' | tok || true)"
check "the unfixed-count and left-out-count placeholders were found" '[ -n "$T3_U" ] && [ -n "$T3_L" ]'
check "the unfixed count and the left-out count use different placeholders" '[ -n "$T3_U" ] && [ -n "$T3_L" ] && [ "$T3_U" != "$T3_L" ]'
check "the left-out placeholder appears only in sentences about left-out items" \
  '[ -n "$T3_L" ] && ! printf "%s\n%s\n" "$T3_FIX" "$T3_REPHAND" | sents2 | grep -F -- "$T3_L" | gq -viE "$LO"'
check "the unfixed placeholder is not used in Phases 4-5 for anything but unfixed things" \
  '[ -n "$T3_U" ] && ! printf "%s\n" "$T3_REPHAND" | sents2 | grep -F -- "$T3_U" | gq -viE "able to fix|unfix|never (count|include)"'

# 4. save-state excludes left-out items from X of Y, Issues found, and the TODO.md update
t3_units() { awk '/^ *(- |[0-9]+\. |```)/||/^$/{if(u!="")print u; u=$0; next} {u=u" "$0} END{if(u!="")print u}'; }
SAVEU="$(printf "%s\n" "$T3_SAVE" | t3_units)"
for a in "X of Y" "Issues found" "TODO.md"; do
  check "save-state: \"$a\" excludes left-out items" \
    "printf '%s\n' \"\$SAVEU\" | grep -iF '$a' | grep -iE '$LO' | grep -qiE '$NEG'"
done

# 5. when a left-out item blocks other tests, they are never counted as passed; the report says what could not be checked
CANT='could(n.t| not) be (checked|tested|verified)|(was|were)(n.t| not) (checked|tested)|(can.t|cannot|could(n.t| not)) (be )?(check|test|sign|log)|not (checked|tested)|unable to (check|test)'
FIXP="$(printf "%s\n" "$T3_FIX" | paras | grep -F 'Failures marked' || true)"
check "Phase 3: all-failures-left-out does not count as \"all passed\"" \
  '[ -n "$FIXP" ] && ! printf "%s\n" "$FIXP" | gq -iE "counts? as all passed|all passed|everything (looks great|passed)|every page"'
check "Phase 3: all-failures-left-out says what could not be checked because of the left-out item" \
  'printf "%s\n" "$FIXP" | grep -qiE "$CANT"'
ALLP="$(printf "%s\n" "$T3_HAND" | awk '/^If (ALL PASSING|every test (that ran )?passed(, apart from a left-out item.s tests)?)/{on=1} /^If SOME FAILURES/{exit} on')"
check "Phase 5 (all passing): \"Everything passed\" / \"Every page\" is not claimed when a left-out item blocked tests" \
  '[ -n "$ALLP" ] && h=$(printf "%s\n" "$ALLP" | head -1) && cond="no tests? (belongs?|that belong)|none of (the|its) tests|no (left.out )?items?|nothing (is |was )?(left|to leave) out|none[^.]{0,25}($LO)|without (a |any )?left.out|only (when|if)[^.]{0,20}(no|nothing|none)[^.]{0,30}($LO)" && { ! printf "%s\n" "$ALLP" | gq -iE "everything passed|every page" || { printf "%s\n" "$h" | grep -qiE "$cond"; } || ! printf "%s\n" "$ALLP" | grep -iE "everything passed|every page" | gq -ivE "$cond"; }'
check "Phase 5: a left-out item that blocked tests is reported with what could not be checked" \
  'printf "%s\n" "$T3_HAND" | sents2 | grep -iE "$LO" | grep -qiE "$CANT"'
LOSEC="$(printf "%s\n" "$T3_REP" | awk '/^## Left Out by Your Choice/{on=1;next} /^## /{on=0} on' | flat)"
check "report: the Left Out section says what could not be checked because of it" \
  '[ -n "$LOSEC" ] && printf "%s\n" "$LOSEC" | grep -qiE "$CANT"'

# 6. the left-out pointer ends at "<error-handling> included." and does not restate rule 3
T3_PTR="$(awk '/^From \.make-it-state\.md/{on=1} on&&/^$/{exit} on' $TRY | flat | sed 's/ *$//')"
check "try-it pointer ends at \"\`<error-handling>\` included.\"" \
  'case "$T3_PTR" in *"\`<error-handling>\` included.") true;; *) false;; esac'
check "try-it pointer does not restate rule 3 (no auto-fix / nothing generated)" \
  '[ -n "$T3_PTR" ] && ! printf "%s" "$T3_PTR" | gq -iE "auto-fix|nothing generated|generated, for"'

# 7. a skill-wide pointer to read step 4 (as resume-it has), and the explore phase uses it
T3_PRE="$(awk '/^<process>/{on=1} on&&/^<\/step>/{exit} on' $TRY)"
check "try-it has a skill-wide pointer (up to the end of Phase 0) to left-out-record.md read step 4 for bringing back, narrowing, taking out; nothing puts an item back on its own" \
  'printf "%s\n" "$T3_PRE" | paras | grep -F left-out-record.md | grep -iE "read step 4" | grep -iE "bring(s|ing)?[^.]{0,30} back|brought[^.]{0,30} back" | grep -iE "narrow" | grep -iE "take(s|n)?[^.]{0,20} out|taking" | grep -qiE "(nothing|never|no step)[^.]{0,60}back on its own"'
check "explore phase: a request in the user's own words for a left-out item is a bring-back through the pointer, not a plain fix" \
  'u=$(printf "%s\n" "$T3_EXP" | t3_units | grep -iE "$LO" | grep -iE "bring(s|ing)?[^.]{0,30} back|bring-back" | grep -iE "follow[^.]{0,30}(left-out-record\.md|read step 4)" | grep -iE "read step 4" | grep -iE "(not|never|rather than|instead of|isn.t)[^.]{0,40}fix"); [ -n "$u" ] && ! printf "%s\n" "$u" | gq -iE "do(es)? not (fix|build|add|bring)|refus|declin|keep(ing)? it left out|tell(s)? them it was left out|won.t|can.t bring|stays? left out"'
check "every \"nothing generated\" in try-it says \"on its own\" (so it never reads as refusing the user's own request)" \
  '! sents2 < $TRY | grep -iE "nothing generated|nothing is generated" | gq -viE "on its own"'

# 8. try-it points at the definition and does not restate it
check "try-it does not restate the reader rules or the bring-back gate" \
  '! grep -qE "Mentioned, never offered|Never put back on its own|The rule every reader follows|Never FAIL|brings an item back|never blocks a step|At ship, named" $TRY && ! grep -qiE "active confirmation|plain .?yes" $TRY'

# ---- Task 3 fix round 1 ----
# 9. aggregate cells: how a left-out test reads in X-of-Y cells, the Login columns and the Status line
SUMM="$(between $TRY '## Summary' '## Login Testing')"
t3_cell() { printf '%s\n' "$SUMM" | grep -F "| $1 |" | grep -qiE 'left out'; }
check "report Summary: the \"All pages load\" cell says how left-out tests read (apart from X of Y, or Left out)" 't3_cell "All pages load"'
check "report Summary: the \"API is responding\" cell says how a left-out test reads" 't3_cell "API is responding"'
t3_login_cols() {
  between $TRY '## Login Testing' '## Pages Tested' | awk -F'|' '/^\| *\[Role/{n++; for(i=3;i<=5;i++) if($i !~ /Left out/) bad=1} END{exit !(n>0 && !bad)}'
}
check "report Login table: the Login, Dashboard and Pages Tested cells can each read Left out (your choice)" t3_login_cols
check "report Status line says how left-out tests read (plus N left out, or Left out (your choice)), not only \"All Passing\"" \
  'printf "%s\n" "$T3_REP" | grep "^> Status:" | grep -qiE "plus[^.]{0,25}left out|Left out \(your choice\)"'
AFTS="$(printf "%s\n" "$T3_AFTER" | sents2)"
check "report: an X of Y cell shows left-out tests apart from X of Y (\"plus ... left out\")" \
  'printf "%s\n" "$AFTS" | grep -F "X of Y" | grep -iE "$LO" | grep -qiE "plus|apart from|separately from|alongside|besides"'
check "report: a cell whose every test is left out reads Left out (your choice), never PASS or 0 of 0" \
  'printf "%s\n" "$AFTS" | grep -F "Left out (your choice)" | grep -qiE "(every|all|each) (of (its|the) )?tests?\b" && printf "%s\n" "$AFTS" | grep -F "Left out (your choice)" | grep -qiE "(never|\bnot\b|n[^[:alnum:] ]t)[^.,;]{0,15}PASS[^.,;]{0,15}0 of 0"'

# 10. one meaning, one trigger for the left-out count and every left-out message
check "report: the Left Out section is not gated on a failure or a test being marked left_out" \
  '[ -n "$LOSEC" ] && ! printf "%s\n" "$LOSEC" | gq -iE "only if any (failure|test)|marked left_out"'
check "report: the Left Out section names every left-out item whether or not a test belongs to it" \
  'printf "%s\n" "$LOSEC" | grep -qiE "(whether or not|even (if|when)|regardless of whether|no test)[^.]{0,50}(test|belong)"'
check "report: the Left Out section lists as \"could not be checked\" only what a left-out item blocked" \
  'printf "%s\n" "$LOSEC" | grep -qiE "(only|if)[^.]{0,60}(blocked|stopp|prevent|remov)|(blocked|stopp|prevent)[^.]{0,60}(only|nothing else)"'
HDRS="$(printf "%s\n" "$T3_HAND" | grep -E '^If ' || true)"
check "Phase 5: no message fires on a test belonging to a left-out item; they fire on the item (same trigger as the Status line)" \
  '[ -n "$HDRS" ] && ! printf "%s\n" "$HDRS" | gq -iE "tests? (that |which )?belong|marked left_out"'
check "Phase 5: the first ALL PASSING message fires only when nothing is left out" \
  'printf "%s\n" "$HDRS" | grep -E "^If (ALL PASSING|every test (that ran )?passed(, apart from a left-out item.s tests)?)" | head -1 | grep -qiE "no left.out items?|nothing (is |was )?left out|no items?[^.:]{0,30}left.out|none[^.:]{0,25}left.out"'
check "(control) Phase 5 has a left-out-only message besides ALL PASSING and SOME FAILURES" \
  '[ "$(printf "%s\n" "$HDRS" | grep -cE "^If (ALL PASSING|every test (that ran )?passed(, apart from a left-out item.s tests)?)")" -ge 2 ]'
t3_cant_gated() {
  c=$(printf "%s\n" "$T3_HAND" | sents2 | grep -iE "could(n.t| not) (be )?check" || true); [ -n "$c" ] || return 1
  ! printf "%s\n" "$c" | gq -viE "only (if|when)[^.]{0,80}(blocked|stopp|prevent|remov)|(if|when) (it|they|a left-out|any)[^.]{0,30}(blocked|stopp|prevent|remov)|(skip|omit|drop)[^.]{0,50}(couldn.t|could not)"
}
check "Phase 5: \"I couldn't check ...\" lists only what a left-out item blocked (not an item nothing depended on)" t3_cant_gated
t3_count_means_items() {
  [ -n "$T3_L" ] || return 1
  ! printf "%s\n" "$T3_REPHAND" | flat | sed "s/\\$T3_L/@@&/g" | tr '@' '\n' | grep -F -- "$T3_L" | grep -vE "^\\$T3_L( item\(s\)| left out)" | gq .
}
check "(control) the left-out count placeholder only ever counts items (\"[N] item(s)\" or \"[N] left out\")" t3_count_means_items

# 11. no false sign-in steps when a left-out item removed them
SIGN='sign.in|log.?in|test users?|try each user|per-user'
GONE='leave[ -]out|drop|skip|omit|remov|without'
t3_signin_para() { printf "%s\n" "$T3_HAND" | paras | grep -iE "$1" | grep -iE "($GONE)[^.]{0,80}($SIGN)|($SIGN)[^.]{0,80}($GONE)" | grep -qiE "$LO"; }
check "Phase 5: the \"same message\" branch leaves out sign-in / test-user steps a left-out item removed" 't3_signin_para "the same message"'
check "Phase 5: SOME FAILURES' \"same browser instructions\" leave out sign-in steps a left-out item removed" 't3_signin_para "same browser instructions"'
HOW="$(printf "%s\n" "$T3_REP" | awk '/^## How to Access/{on=1;next} /^## /{on=0} on' | flat)"
check "report How to Access: sign-in steps are left out when a left-out item (sign-in, roles) removed them" \
  '[ -n "$HOW" ] && printf "%s\n" "$HOW" | grep -iE "$LO" | grep -qiE "($GONE)[^.]{0,80}($SIGN)|($SIGN)[^.]{0,80}($GONE)"'

# 12. minors
check "Phase 5 \"I tested\": [Y] is the total and [X] the passed count, as in the report's \"X of Y\"" \
  '[ "$(printf "%s\n" "$T3_HAND" | flat | grep -oE "I tested \[[A-Za-z_]+\] things and \[[A-Za-z_]+\] passed")" = "I tested [Y] things and [X] passed" ]'
check "the page count in Phase 5 does not reuse [X], [Y], [Z] or the left-out count" \
  'pg=$(printf "%s\n" "$T3_HAND" | flat | grep -oE "\[[A-Za-z_]+\] pages" | tok); [ -n "$pg" ] && case "$pg" in "[X]"|"[Y]"|"[Z]"|"$T3_L") false;; esac'
t3_bare() {
  tl="${T3_L//[\[\]]/}"; [ -n "$tl" ] || return 1
  ! grep -E "vulnerabilit|\"(total_tests|passed|failed)\"" $TRY | gq -E "(^|[^][:alnum:]_])$tl($|[^][:alnum:]_/])"
}
check "the left-out count placeholder is not a bare letter also used for vulnerabilities or the results JSON counts" t3_bare
check "report Left Out section invites the user to have the item added (\"tell me if you want it added\")" \
  'printf "%s\n" "$LOSEC" | grep -qiE "tell me if you want"'
t3_invites() {
  p=$(printf "%s\n" "$T3_HAND" | paras | grep -F -- "$T3_L"); [ -n "$p" ] || return 1
  ! printf "%s\n" "$p" | gq -viE "tell me if you want"
}
check "every Phase 5 paragraph that mentions the left-out count says \"tell me if you want it added\"" t3_invites
check "the \"couldn't check\" message is said once: not in Phase 3 and again in Phase 5" \
  '! printf "%s\n" "$T3_FIX" | flat | gq -iE "couldn.t check" && printf "%s\n" "$T3_HAND" | flat | grep -qiE "couldn.t check"'

# ---- Task 3 fix round 2 ----
# (c) the Status line reads All Passing only when nothing is left out
check "report: the Status line reads All Passing only when nothing is left out" \
  'printf "%s\n" "$AFTS" | grep -F "All Passing" | grep -qiE "only (when|if)[^.]{0,30}(nothing|no |none)[^.]{0,25}left out"'
# (d) Phase 5 lists under "I tested" only what was checked, and says how for a partly checked line / nothing checked
ALLLO="$(printf "%s\n" "$T3_HAND" | paras | grep -E '^If (ALL PASSING|every test (that ran )?passed(, apart from a left-out item.s tests)?), and anything is left out' || true)"
check "Phase 5 (all passing, left out): lists under \"I tested\" only what was checked" \
  'printf "%s\n" "$ALLLO" | grep -qiE "(list|say)[^.]{0,30}I tested.{0,12}only what was (checked|tested)"'
check "Phase 5 (all passing, left out): a partly checked line says how much (e.g. \"6 of your 10 pages\")" \
  'printf "%s\n" "$ALLLO" | grep -qiE "(partly|partially|only some|part of) checked,? (says?|gives?|writes?|shows?) how (much|many)"'
check "Phase 5 (all passing, left out): when nothing on the list was checked, say only that the app starts/runs" \
  'printf "%s\n" "$ALLLO" | grep -qiE "(nothing|none)[^.]{0,80}(checked|tested|listed)[^.]{0,100}(app|it)[^.]{0,25}(start|run|up)"'
# minors: the same ", plus [W] left out" reading on the other Summary cells (or the rule names them)
for c in "Login works" "Permissions work correctly" "API is responding"; do
  check "report Summary: the \"$c\" cell carries \", plus [W] left out\" (or the rule sentence names it)" \
    "printf '%s\n' \"\$SUMM\" | grep -F '| $c |' | grep -qiE 'plus[^|]{0,20}left out' || printf '%s\n' \"\$AFTS\" | grep -F '$c' | grep -qiE 'plus[^.]{0,20}left out'"
done
check "report: \"Each type of user was tested:\" is qualified when sign-in or roles are left out" \
  'u=$(printf "%s\n" "$T3_REP" | paras | grep -F "Each type of user was tested" | grep -iE "$LO" | grep -iE "in place of|instead of"); [ -n "$u" ] && ! printf "%s\n" "$u" | gq -iE "(don.t|do not|never) (say|write)|even if|keep the line"'
check "report: \"Screenshots of each page (per role) are saved\" is qualified when sign-in or roles are left out" \
  's=$(printf "%s\n" "$T3_REP" | paras | grep -F "Screenshots of each page (per role)" | sents2 | grep -F "of the pages that could be opened" | grep -iE "$LO" | grep -iE "in place of|instead of"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "even if|keep|(don.t|do not|never) (say|write)"'
# the rule and the Status template agree: left-out tests are not counted as passing or failing; the item count is separate
check "report: no sentence says the Status line never counts left-out things while the template counts the items" \
  '! printf "%s\n" "$AFTS" | gq -iE "(never|not|n[^[:alnum:] ]t)[^.]{0,60}count[^.]{0,40}Status line"'
check "report: the rule says left-out tests are never counted as passing or failing" \
  'printf "%s\n" "$AFTS" | grep -F "Left out (your choice)" | grep -qiE "never counted[^.]{0,20}(passing or failing|passed or failed|pass or fail)"'
check "(control) the Status template still carries the separate count \"plus [L] item(s) left out\"" \
  'printf "%s\n" "$T3_REP" | grep "^> Status:" | grep -qF "plus [L] item(s) left out"'
# Phase 3's "Everything looks great!" fires only on the same trigger as Phase 5, or is qualified
check "Phase 3: \"Everything looks great!\" is qualified when anything is left out (same trigger as Phase 5)" \
  'printf "%s\n" "$T3_FIX" | paras | grep -F "Everything looks great" | grep -qiE "only (if|when)[^.;]{0,20}(nothing|no |none)[^.;]{0,15}left out"'

# ---- Task 3 fix round 3 ----
# the Login Testing Result column sums Login, Dashboard and Pages, so it carries the same ", plus [W] left out" reading
LOGT="$(between $TRY '## Login Testing' '## Pages Tested')"
t3_result_cols() {
  printf "%s\n" "$LOGT" | awk -F'|' '/^\| *\[Role/{n++; if($(NF-1) !~ /[Pp]lus[^|]{0,20}left out/) bad=1} END{exit !(n>0 && !bad)}'
}
check "report Login Testing: the Result column (every user-type row) carries \", plus [W] left out\" (or the rule sentence names it)" \
  't3_result_cols || printf "%s\n" "$AFTS" | grep -iE "Result column" | grep -qiE "plus[^.]{0,20}left out"'
# no screenshot is promised when none could be taken
check "report: the Screenshots line says, in place of the list, that none were taken when no page could be opened" \
  'u=$(printf "%s\n" "$T3_REP" | paras | grep -F "Screenshots of each page (per role)"); s=$(printf "%s\n" "$u" | sents2 | grep -iE "no (page|screenshot)" | grep -iE "in place of|instead of"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "even if|keep|(don.t|do not|never) (say|write)" && ! printf "%s\n" "$u" | gq -iE "even if no"'
check "Phase 5 (all passing, left out): the closing \"full report with screenshots\" is dropped or qualified when none were taken" \
  'printf "%s\n" "$ALLLO" | grep -qiE "(drop|omit|leave out)[^.;]{0,5}.with screenshots.[^.;]{0,40}(if|when)[^.;]{0,10}no screenshots"'
check "guardrails: \"Screenshots ... at least: login, dashboard per role\" has a left-out exception like gate 1" \
  'g=$(awk "/^<guardrails>/{on=1} on" $TRY | awk "/at least: login, dashboard per role/{on=1;print;next} on&&(/^- /||/^\$/||/^</){exit} on" | flat | grep -iE "$LO"); printf "%s\n" "$g" | grep -qiE "except[^i]|unless|follows" && ! printf "%s\n" "$g" | gq -iE "no exception"'
# "ALL PASSING" in a Phase 5 header is not "every test that ran passed" while the rule reserves All Passing for nothing left out
check "Phase 5: no header says \"ALL PASSING\" for \"every test that ran passed\"; both read \"every test passed, apart from a left-out item's tests\"" \
  'h=$(printf "%s\n" "$T3_HAND" | paras | grep -E "^If (ALL PASSING|every test (that ran )?passed(, apart from a left-out item.s tests)?)" | sed "s/:.*//"); [ -n "$h" ] && ! printf "%s\n" "$h" | gq -E "ALL PASSING|that ran" && [ "$(printf "%s\n" "$h" | grep -c "^If every test passed, apart from a left-out item.s tests, and ")" = 2 ]'
check "left-out mentions (Left Out section, Phase 5 [L] paragraphs) are never an ask: no ?, yes/no or wait for" \
  'inv=$(printf "%s\n" "$LOSEC"; printf "%s\n" "$T3_HAND" | paras | grep -F -- "$T3_L"); [ -n "$inv" ] && ! printf "%s\n" "$inv" | gq -iE "\?|yes/no|wait for"'

# ---- Task 3 adversarial round 1 ----
# every TODO.md write in try-it, with its continuation lines (deeper-indented sub-bullets and wrapped text)
t3_todo_write() { awk -v k="$1" 'index($0,k){on=1;print;next} on&&/^ {3,}[^ -]|^ {5,}/{print;next} {on=0}' $TRY | flat; }
check "try-it has exactly three TODO.md writes (2b.6, Phase 3, save-state); a new one fails here until it is pinned" \
  '[ "$(grep -ciE "(add|update|note|write|put|record|log)[^.]*TODO\.md" $TRY)" = 3 ]'
LOX='(never|not|exclud|without|skip)[^.;]{0,60}(left.out|belongs to a left)'
check "Phase 2 step 2b.6: the dependency findings added to TODO.md exclude any that belong to a left-out item" \
  'w=$(t3_todo_write "Add to TODO.md with severity"); printf "%s\n" "$w" | grep -qiE "$LOX" && ! printf "%s\n" "$w" | gq -iE "(never|not|don.t) (skip|omit|drop|leave)|not (just|only)|left.out[^.;]{0,30}(included|too)|(never|not) [a-z]+ing\b"'
check "save-state: the TODO.md write excludes a failure that belongs to a left-out item" \
  'w=$(t3_todo_write "Update \`TODO.md\` with any issues"); printf "%s\n" "$w" | grep -qiE "$LOX" && ! printf "%s\n" "$w" | gq -iE "(never|not) [a-z]+ing\b"'
check "Phase 3: \"Add unfixed issues to TODO.md\" is covered because left-out failures never count as unfixed" \
  'printf "%s\n" "$T3_FIX" | flat | grep -qiE "never count[^.;]{0,20}as unfixed"'
check "report Summary: the \"Dependency health\" cell has a left-out reading (\"Left out (your choice)\" or \", plus [W] left out\")" \
  'printf "%s\n" "$SUMM" | grep -F "| Dependency health |" | grep -qE "(/ |\[)Left out \(your choice\)\]|, plus \[W\] left out"'

# the app's start: "up and running" / "starts and runs" and the browser line need the start to have been checked
# a clause that gates on a left-out item having kept the app from starting
KEPT='(if|when)[^.;]{0,40}left.out item[^.;]{0,30}(kept|stopped|blocked|prevent)[^.;]{0,25}start'
check "Phase 5 (all passing, left out): a left-out item that kept the app from starting is handled, and \"even if\" does not waive it" \
  'printf "%s\n" "$ALLLO" | grep -qiE "$KEPT" && ! printf "%s\n" "$ALLLO" | gq -iE "even if[^.;]{0,40}left.out item[^.;]{0,30}(kept|stopped|blocked|prevent)|(except|unless|but not) (if|when)[^.;]{0,40}left.out item[^.;]{0,30}(kept|stopped|blocked|prevent)"'
check "Phase 5 (all passing, left out): when a left-out item kept the app from starting, it says the start could not be checked (not \"starts and runs\")" \
  'c=$(printf "%s\n" "$ALLLO" | grep -oiE "$KEPT.{0,200}"); printf "%s\n" "$c" | grep -qiE "(couldn.t|could not|can.t|cannot|unable).{0,25}(be )?(check|start|test)" && printf "%s\n" "$c" | grep -qiE "(in place of|instead of|not|never|drop|omit).{0,25}(Great news|up and running)"'
check "Phase 5 (all passing, left out): when a left-out item kept the app from starting, no \"open your browser / localhost\" line is given" \
  'c=$(printf "%s\n" "$ALLLO" | grep -oiE "$KEPT.{0,250}"); printf "%s\n" "$c" | grep -qiE "(drop|omit|leave out|no |without|skip).{0,40}(browser|localhost|open)"'

# ---- Task 3 fix round 6 ----
# up to N bytes of stdin from the first "a left-out item kept the app from starting" on (grep caps a bounded repeat at 255)
kept_after() { K="$KEPT" N="$1" perl -0777 -ne 'print substr($_,$-[0],$ENV{N}) if /$ENV{K}/i'; }
# 1. the root: a test a left-out item kept from running was not checked -- it is left_out, never a failure
T3_SMOKE="$(stepof $TRY smoke-test)"
check "Phase 2: a test a left-out item kept from running is marked left_out (not checked), even a check of something the app already had" \
  's=$(printf "%s\n" "$T3_SMOKE" | sents2 | grep -iE "left.out item[^.;]{0,40}(kept|stopped|blocked|prevent)[^.;]{0,30}(run|check|test)" | grep -F "left_out" | grep -iE "(even|including)[^.;]{0,60}(already had|app already|frontend|backend|existing)"); [ -n "$s" ] && printf "%s\n" "$s" | grep -qiE "(mark|record|list|treat)[^.;]{0,30}left_out" && printf "%s\n" "$s" | grep -qiE "never counts? as (failed|a failure)" && ! printf "%s\n" "$s" | gq -iE "(never|not|n.t) (mark|record|list|treat)[^.;]{0,15}left_out|except|unless|but not|even if[^.;]{0,30}fail|not .?left_out|(it|so|this) (is|counts as) a failure"'
check "Phase 2: that left_out rule says the test was not checked / is not a failure" \
  'printf "%s\n" "$T3_SMOKE" | sents2 | grep -F "left_out" | grep -iE "(kept|blocked|stopped|prevent)[^.;]{0,40}(run|check)" | grep -qiE "(was|were|is|are) not (checked|a failure|run)|never (ran|run|checked)|not (checked|a failure)"'

# 2. the report does not send the user to an app that did not start
HOWA="$(between $TRY '## How to Access Your App' '## Left Out by Your Choice')"
NEXTA="$(between $TRY '## What to Do Next' '```')"
check "report How to Access: when a left-out item kept the app from starting, says it could not be started, in place of the browser line" \
  'c=$(printf "%s\n" "$HOWA" | flat | kept_after 350); printf "%s\n" "$c" | grep -qiE "(in place of|instead of) (all|every)( of)? (the )?lines?\b|(in place of|instead of)[^.;]{0,20}(the browser|open your browser|this section)" &&printf "%s\n" "$c" | grep -qiE "(couldn.t|could not|can.t|cannot|wasn.t|not)[^.;]{0,25}(be )?(start|open)" && ! printf "%s\n" "$c" | gq -iE "even if|(keep|still (give|write|show))[^.;]{0,25}(open your browser|this section)|(don.t|do not|never) (say|write)|except[^.;]{0,30}(browser|open your)" && ! printf "%s\n" "$HOWA" | flat | gq -iE "(even|except|unless|but not) (if|when)[^.;]{0,40}left.out item[^.;]{0,30}(kept|stopped|blocked|prevent)"'
check "report What to Do Next: when a left-out item kept the app from starting, the browser and /ship-it lines are left out" \
  'c=$(printf "%s\n" "$NEXTA" | flat | kept_after 350); printf "%s\n" "$c" | grep -qiE "(leave out|drop|omit|skip|in place of|instead of)[^.;]{0,80}(browser|explore)" && printf "%s\n" "$c" | grep -qiE "(leave out|drop|omit|skip|in place of|instead of)[^.;]{0,120}ship-it|ship-it[^.;]{0,60}(left out|dropped|omitted)" && ! printf "%s\n" "$c" | gq -iE "even if|(keep|still (give|write|show))[^.;]{0,25}(browser|ship-it)|not (the )?.?/ship-it"'

# 3. same family
check "report Summary: the \"App starts up\" row has the left-out reading (an option, not just the words)" \
  'printf "%s\n" "$SUMM" | grep -F "| App starts up |" | grep -qE "(/ ?|\[)Left out \(your choice\)\]|, plus \[W\] left out"'
check "report: the Status line never reads \"0 of 0 Passing\" (when every test is left out)" \
  'printf "%s\n" "$AFTS" | grep -F "Status line" | grep -qiE "(\bnever|\bnot\b|n.t\b)[^.,;]{0,40}0 of 0|0 of 0[^.;]{0,30}(never|not)" && ! printf "%s\n" "$AFTS" | grep -F "Status line" | grep -iE "0 of 0" | gq -iE "(may|can|should|fine|ok|allowed)[^.;]{0,15}(read|say|show)|even if"'
check "Phase 5 closing lines (\"When you're done exploring\", \"stop the app\") are left out when a left-out item kept the app from starting" \
  'c=$(printf "%s\n" "$T3_HAND" | awk "/Always end with/{on=1} on" | flat | kept_after 350); printf "%s\n" "$c" | grep -qiE "(leave out|drop|omit|skip|without)[^.;]{0,60}(done exploring|stop the app|shut down)" && ! printf "%s\n" "$c" | gq -iE "even if|(keep|still (give|write|say))[^.;]{0,25}(done exploring|stop the app)|(don.t|do not|never) (leave|drop|omit|skip)|leave out nothing|(leave|drop|omit) none"'
check "explore phase (the \"happy / done\" reply): \"Your app is working just how you wanted it\" is not said when a left-out item kept the app from starting" \
  'c=$(printf "%s\n" "$T3_EXP" | flat | kept_after 350); printf "%s\n" "$c" | grep -qiE "(Awesome|working just how)" && printf "%s\n" "$c" | grep -qiE "(in place of|instead of|drop|omit|leave out|skip|not say|never say)[^.;]{0,30}(Awesome|working just how|that line)" &&! printf "%s\n" "$c" | gq -iE "even if|(still|keep)[^.;]{0,15}(say|use|celebrate)"'
check "2b.6: the 'Dependency Health' note in TRY-IT-REPORT.md excludes a left-out item's findings" \
  'w=$(t3_todo_write "Note in TRY-IT-REPORT.md"); printf "%s\n" "$w" | grep -qiE "(never|not|exclud|without|skip|read)[^.;]{0,50}left.out" && ! printf "%s\n" "$w" | gq -iE "(never|not|don.t) (skip|omit|drop|leave)|not (just|only)|left.out[^.;]{0,30}(included|too|also)|(never|not) [a-z]+ing\b|never as|not as|with the rest"'
check "2b.6: \"unless vulnerabilities couldn't be fixed\" never counts a fix the user left out as unfixable" \
  'w=$(t3_todo_write "Do NOT tell the user about this step" | sed "s/Do NOT tell//"); printf "%s\n" "$w" | grep -qiE "(never|not|exclud|without|skip)[^.;]{0,40}left.out" && ! printf "%s\n" "$w" | gq -iE "(never|not|don.t) (skip|omit|drop|leave)|left.out[^.;]{0,40}(count|too|also|included)|(never|not) [a-z]+ing\b"'
check "3b: \"awaiting safety updates from their maintainers\" excludes a left-out item's findings" \
  'w=$(grep -A3 -F "If unfixable issues remain" $TRY | flat); printf "%s\n" "$w" | grep -qiE "awaiting safety updates" && printf "%s\n" "$w" | grep -qiE "(never|not|exclud|without|skip)[^.;]{0,50}left.out" && ! printf "%s\n" "$w" | gq -iE "(never|not|don.t) (skip|omit|drop|leave)|not (just|only)|left.out[^.;]{0,40}(count|too|also|included)|(never|not) [a-z]+ing\b"'
check "<error-handling>: the missing docker-compose.yml path never generates a left-out item and points at the left-out pointer" \
  'b=$(awk "/If docker-compose.yml doesn.t exist/{on=1;next} on&&/^\*\*If /{exit} on" $TRY | flat); printf "%s\n" "$b" | grep -iE "left.out" | grep -qiE "(never|not|without) (generat|creat)" &&printf "%s\n" "$b" | grep -qiE "pointer|left-out-record\.md|Phase 0" && ! printf "%s\n" "$b" | gq -iE "even if|(also|still)[^.;]{0,20}(generat|creat)"'
check "Phase 5 (all passing, left out): the kept-from-starting sentence comes BEFORE \"open with Great news\" and replaces the whole opener and the \"I tested\" list" \
  'a=$(printf "%s\n" "$ALLLO" | grep -boiE "$KEPT" | head -1 | cut -d: -f1); b=$(printf "%s\n" "$ALLLO" | grep -boiE "open with .?.?.?Great news" | head -1 | cut -d: -f1); c=$(printf "%s\n" "$ALLLO" | kept_after 350); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && printf "%s\n" "$c" | grep -qiE "up and running" && printf "%s\n" "$c" | grep -qiE "(leave out|drop|omit|skip|without)[^.;]{0,90}I tested" && ! printf "%s\n" "$c" | gq -iE "(keep|still (list|give|write))[^.;]{0,25}I tested|(don.t|do not|never) (leave|drop|omit|skip)"'

# ---- Task 3 fix round 7 ----
# a gate that waives or flips "a left-out item kept the app from starting" (even if / except when / unless)
WAIVE='(even|except|unless|but not) (if|when)[^.;]{0,40}left.out item[^.;]{0,30}(kept|stopped|blocked|prevent)'
SOMEF="$(printf "%s\n" "$T3_HAND" | awk '/^If SOME FAILURES/{on=1} /Always end with/{exit} on' | flat)"
check "Phase 5 (SOME FAILURES): when a left-out item kept the app from starting, no \"Your app is running!\" and no browser steps" \
  'c=$(printf "%s\n" "$SOMEF" | kept_after 350); printf "%s\n" "$c" | grep -qiE "(\bno |drop|omit|leave out|without|skip|in place of|instead of)[^.;]{0,40}Your app is running" && printf "%s\n" "$c" | grep -qiE "(\bno |drop|omit|leave out|without|skip)[^.;]{0,60}(browser|explore your app)" && ! printf "%s\n" "$c" | gq -iE "(keep|still (say|give|write|show))[^.;]{0,30}(running|browser|explore)|(don.t|do not|never) (drop|omit|leave|skip)|\bnot ([a-z]+ )?.?(Your app is running|browser)|leave out nothing|(drop|omit) none" && ! printf "%s\n" "$SOMEF" | gq -iE "$WAIVE"'
check "explore phase (next steps): \"run /try-it again to fire it up\" is dropped when a left-out item kept the app from starting" \
  's=$(printf "%s\n" "$T3_EXP" | sents2 | grep -iE "$KEPT" | grep -iE "fire it up|come back anytime"); [ -n "$s" ] && printf "%s\n" "$s" | grep -qiE "(drop|omit|leave out|skip|without|in place of|instead of)[^.;,]{0,30}(fire it up|come back anytime)" && ! printf "%s\n" "$s" | gq -iE "$WAIVE|(keep|still (say|give|write|show))[^.;]{0,30}(fire it up|come back)|(don.t|do not|never) (drop|omit|leave|skip)|not (the )?.?(to )?(fire it up|come back)"'
check "report What to Do Next: \"If something doesn't look right, tell me and I'll fix it\" is left out too when a left-out item kept the app from starting" \
  'c=$(printf "%s\n" "$NEXTA" | flat | kept_after 350); printf "%s\n" "$c" | grep -qiE "(leave out|drop|omit|skip|in place of|instead of)[^.;]{0,120}(something doesn.t look right|tell me and I.ll fix)" && ! printf "%s\n" "$c" | gq -iE "(keep|still (give|write|show))[^.;]{0,40}(look right|fix it)|(don.t|do not|never) (leave|drop|omit|skip)|(not|never) (the )?.?(if )?something doesn.t look right|leave[^.;]{0,50}as it is" && ! printf "%s\n" "$NEXTA" | flat | gq -iE "$WAIVE"'
# step 7 and the failures[] "left_out" field agree: a test a left-out item kept from running is recorded there
FIELD="$(printf "%s\n" "$T3_SMOKE" | flat | grep -oE '"left_out": "[^"]*"' || true)"
check "Phase 2 step 7: the failures[] \"left_out\" field also names the left-out item that kept the test from running" \
  'printf "%s\n" "$FIELD" | grep -qiE "\b(or|and) (the )?(one )?that (kept|stopped|blocked|prevent)[^\"]{0,20}from (running|being run|run)" && ! printf "%s\n" "$FIELD" | gq -iE "(\bnever|\bnot\b|n.t\b|\bnor\b|except|unless|but not)[^\"]{0,30}(kept|stopped|blocked|prevent)"'
check "Phase 2 step 7: while left_out lives on failures[] entries, step 7 never calls such a test \"not a failure\"" \
  's=$(printf "%s\n" "$T3_SMOKE" | sents2 | grep -F "left_out" | grep -iE "(kept|blocked|stopped|prevent)[^.;]{0,40}(run|check)"); [ -n "$s" ] && { ! printf "%s\n" "$T3_SMOKE" | flat | gq -E "\"failures\": \[[^]]*\"left_out\"" || ! printf "%s\n" "$s" | gq -iE "(is|are|was|were|it.s) not a failure|never a failure|isn.t a failure|no failure"; }'

# ---- Task 3 fix round 8 ----
# sentences that never run across a blank line, so a gate and what it drops are read as one sentence
psents() { paras | sed 's/\. /.\
/g'; }
# "never / drop / in place of" followed directly by a list of quoted replies ("A", "B", or "C"): what comes right after it is what it negates
NEGQ="(\bnever|\bnot\b|n.t\b|drop|omit|leave out|skip|without|in place of|instead of)( (say|use|write|give|tell))? ((\"[^\"]{1,40}\"|'[^']{1,40}'),? (or |and |nor )?)*[\"']?"
# SOME FAILURES, no start: the gate also drops the closing "Just tell me ..." line, and the couldn't-check list says "other than the start"
SOMEG="$(printf "%s\n" "$T3_HAND" | awk '/^If SOME FAILURES/{on=1} /Always end with/{exit} on' | psents | grep -iE "$KEPT" || true)"
check "Phase 5 (SOME FAILURES): when a left-out item kept the app from starting, the closing \"Just tell me about anything that doesn't look right\" line is dropped too" \
  '[ -n "$SOMEG" ] && printf "%s\n" "$SOMEG" | grep -qiE "(drop|omit|leave out|skip|without)( the closing| the last)?( line)? .?Just tell me about anything|(drop|omit|leave out|skip|without)[^.;]{0,100}\b(and|or) (the |its )?(closing )?(line )?.?Just tell me about anything" && ! printf "%s\n" "$SOMEG" | gq -iE "$WAIVE|(keep|still|always)[^.;]{0,60}(Just tell me|look right)|(don.t|do not|never) (drop|omit|leave|skip)|leave out nothing|(drop|omit|leave) none"'
check "Phase 5 (SOME FAILURES): \"I couldn't check [only what they blocked ...]\" says \"other than the start\", so the start is mentioned once" \
  'b=$(printf "%s\n" "$SOMEF" | grep -oiE "couldn.t check \[only what they blocked[^]]*\]"); [ -n "$b" ] && ! printf "%s\n" "$b" | gq -viE "other than (the|your app.s|its) start" && ! printf "%s\n" "$b" | gq -iE "includ|\btoo\b|not other than"'
# Phase 3, no start: "I got most things working!" carries the kept-from-starting gate
FIXG="$(printf "%s\n" "$T3_FIX" | psents | grep -iE "$KEPT" | grep -iE "got most things working" || true)"
check "Phase 3: \"I got most things working!\" is dropped when a left-out item kept the app from starting (nothing ran)" \
  '[ -n "$FIXG" ] && printf "%s\n" "$FIXG" | grep -qiE "${NEGQ}I got most things working" && ! printf "%s\n" "$FIXG" | gq -iE "$WAIVE|(keep|still|always)[^.;]{0,40}.?I got most|(don.t|do not|never) (drop|omit|leave|skip)"'
# explore phase, no start: the change replies and the stop reply assume a running app
EXPG="$(printf "%s\n" "$T3_EXP" | psents | grep -iE "$KEPT" | grep -iE "Refresh|Try again now|Shutting down|start it again" || true)"
check "explore phase: the change replies (\"Refresh ...\", \"Try again now\") are not given when a left-out item kept the app from starting" \
  '[ -n "$EXPG" ] && printf "%s\n" "$EXPG" | grep -qiE "${NEGQ}Refresh" && printf "%s\n" "$EXPG" | grep -qiE "${NEGQ}Try again now" && ! printf "%s\n" "$EXPG" | gq -iE "$WAIVE|(keep|still|always)[^.;]{0,40}.?(Refresh|Try again)|(don.t|do not|never) (drop|omit|leave|skip)"'
check "explore phase: the stop reply (\"Shutting down your app\", \"start it again\") is not given when a left-out item kept the app from starting" \
  '[ -n "$EXPG" ] && printf "%s\n" "$EXPG" | grep -qiE "${NEGQ}Shutting down your app" && printf "%s\n" "$EXPG" | grep -qiE "${NEGQ}start it again" && ! printf "%s\n" "$EXPG" | gq -iE "$WAIVE|(keep|still|always)[^.;]{0,40}.?(Shutting down|start it again)|(don.t|do not|never) (drop|omit|leave|skip)"'

# ---- Task 3 fix round 9 ----
# review9 Minor 1: with no start, a change reply says what changed and that it couldn't be checked, never "Done!" / "Fixed!"
check "explore phase: when a left-out item kept the app from starting, a change reply says it couldn't be checked, never \"Done!\" or \"Fixed!\"" \
  '[ -n "$EXPG" ] && printf "%s\n" "$EXPG" | grep -qiE "say what you changed and that you couldn.t check it" && printf "%s\n" "$EXPG" | grep -qiE "${NEGQ}Done!" && printf "%s\n" "$EXPG" | grep -qiE "${NEGQ}Fixed!" && ! printf "%s\n" "$EXPG" | gq -iE "$WAIVE|(keep|still|always)[^.;]{0,40}.?(Done|Fixed)|(don.t|do not|never) (drop|omit|leave|skip)"'
# review9 Important, fix (a): the 10 kept-from-starting gate lines, pinned exactly (flattened). A text check can't catch an
# added contradicting sentence elsewhere; it does catch any in-place edit. A correct reword fails here until this list is edited.
# (The heredoc sits in a function, not inside $(...): macOS bash 3.2 misparses the apostrophes there.)
# review10: all 13 gate lines plus the 2 sign-in lines (15); the count guards the list itself, so an emptied pins() fails.
# review11: plus the 3 passed-or-failed sentences (2b, step 7, report rule) and the Dependency health row (19).
pins() { cat <<'PINEOF'
A test a left-out item kept from running (as when it kept the app from starting) was not checked: list it in `failures` with `left_out` set, even a check of something the app already had, like the frontend or backend starting; it never counts as failed.
"left_out": "the left-out item it belongs to (per left-out-record.md) or that kept it from running, or absent"
([Z] never counts left-out items. If a left-out item kept the app from starting, drop "I got most things working!" -- nothing ran.)
If a left-out item kept the app from starting, write in place of all the lines above: "Your app couldn't be started, because of what you chose to leave out."]
[If a left-out item kept the app from starting, leave out the browser, "If something doesn't look right" and /ship-it lines: nothing is running to explore or ship yet.]
If a left-out item kept the app from starting, say "I couldn't check that your app starts, because of what you chose to leave out." in place of "Your app is running! Most things are working great.", and drop "You can still explore your app right now:" and its browser instructions, and the closing "Just tell me about anything that doesn't look right" line -- nothing is running to open or look at.
any of them added."[only if a left-out item blocked tests: ' Because they're left out, I couldn't check [only what they blocked other than the start, in plain words].']
any of them added.'][only if a left-out item blocked tests: ' Because they're left out, I couldn't check [only what they blocked other than the start, in plain words].']
(If a left-out item kept the app from starting, nothing ran: say only "Got it!" in place of "Awesome!" and that line, leave **/ship-it** out of the next steps, and drop the "Come back anytime" line -- /try-it can't start it either.)
If a left-out item kept the app from starting, nothing is running: in any reply above, say what you changed and that you couldn't check it (to a stop request, say only that nothing is running), never "Done!", "Fixed!", "Refresh", "Try again now", or "Shutting down your app" and "start it again".
If a left-out item kept the app from starting, drop "I tested" and its list, say "I couldn't check that your app starts, because of what you chose to leave out." in place of the whole "Great news -- your app is up and running" line, and drop the browser steps (all of "Here's how to explore your app"), since nothing is running to open (as when Docker Compose is left out, so nothing builds).
**Always end with** this, except when a left-out item kept the app from starting (then leave out all of it, "When you're done exploring" included -- nothing is running):
If it belongs to a left-out item (the Phase 0 pointer), never generate it or say the message below: that item kept the app from starting, so skip startup and go on to the smoke test, where every test it kept from running is marked `left_out` (step 7).
[Leave out any sign-in line that a left-out item removed.
Either way, leave out any sign-in or per-user step a left-out item removed (as the report's How to Access does),
An audit that belongs to a left-out item (per `left-out-record.md`, as when X03 or X07 is on its line) reads "Left out (your choice)" even when it finds nothing: record it with `left_out` (step 7).
A test that belongs to a left-out item is listed in `failures` with `left_out` set too, whether it passed or failed: it never counts as passed or failed.
That holds whether it passed or failed: a clean dependency audit that belongs to a left-out item still reads **Left out (your choice)** in Dependency health, never Clean.
| Dependency health | [Clean / N vulnerabilities remaining / Left out (your choice)][, plus [W] left out (your choice)] |
PINEOF
}
TRYFLAT="$(flat < $TRY)"
check "the 19 pinned try-it lines (the kept-from-starting gates, the sign-in lines, the passed-or-failed rules, the Dependency health row) are exactly as written; a reword needs a disclosed test edit" \
  'miss=$(pins | while IFS= read -r p; do printf "%s" "$TRYFLAT" | gq -F -- "$p" || echo "$p"; done); [ "$(pins | grep -c .)" = 19 ] && [ -z "$miss" ] || { printf "  missing: %s\n" "$miss"; false; }'

# ---- Task 3 adversarial round 2 ----
# rule 2: a check that belongs to a left-out item (its ID on the item's line) reads Left out (your choice) whether it passed
# or failed -- never PASS or Clean, never in X of Y. adv2's session: dependency fixes (X03, X07) left out, the audit comes back clean.
# the "passed too" reach: "whether it passed or failed", "even when it passed / is clean / finds nothing", "pass or fail"
REACH='whether (or not )?(it|they|the [a-z]+) (passed|passes|pass|failed|fails|is clean|was clean|finds|found)|even (when|if) (it|they|the [a-z]+)( [a-z]+){0,2} (passed|passes|is clean|was clean|comes back clean|came back clean|finds nothing|found nothing)|even (when|if) clean|(^|[-,(:] ?)(pass or fail|passed or failed)\b|even a (passing|passed|clean)\b'
AUDR="$REACH|(a|the) (clean|passing|passed) (audit|dependency)|(finds|found) nothing"
# its opposite inside the same sentence: a carve-out for the passing case, or failures only
CARVE='(except|unless|but not|other than) (when |if )?(it |they |the [a-z]+ )?(passed|passes|pass|is clean|was clean|comes back clean|finds nothing)|only (when|if) (it|they) (fail|fails|failed)|(never|not|n.t) (mark|record|list|set|read|show)[^.;]{0,40}(pass|clean)'
# anywhere in try-it: a sentence that reads a left-out item's passing check as passed (PASS, Clean, its real result, or in X of Y)
t3_reads_passed() {
  sents2 < $TRY | grep -iE "belong|left.out" | grep -iE "pass|clean|found nothing|finds nothing" | perl -ne 'BEGIN{$f=1} $f=0 if /(?<!never )(?<!not )(?<!n.t )\b(reads?|shows?|reported as|marked|counts? as) (as )?\W{0,2}(PASS|Clean|passed)\b|(?<!never )(?<!not )(?<!n.t )\bcounts? (in|toward|towards) (the )?\W?X of Y|\b(real|actual) result/i; END{exit $f}'
}
check "Phase 2 step 7: a test that belongs to a left-out item is recorded with left_out whether it passed or failed, not only as a failure" \
  's=$(printf "%s\n" "$T3_SMOKE" | sents2 | grep -F left_out | grep -iE "belong" | grep -iE "$REACH"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$CARVE" && ! t3_reads_passed'
check "report rule: a test that belongs to a left-out item reads Left out (your choice) whether it passed or failed (not only one marked as a failure)" \
  's=$(printf "%s\n" "$AFTS" | grep -F "Left out (your choice)" | grep -iE "belong" | grep -iE "$REACH"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$CARVE" && ! t3_reads_passed'
check "report: a clean audit that belongs to a left-out item reads Left out (your choice) in Dependency health, never Clean" \
  'u=$( { printf "%s\n" "$SUMM" | grep -F "| Dependency health |"; printf "%s\n" "$AFTS"; } | grep -F "Left out (your choice)" | grep -iE "audit|Dependency health|dependenc|X03|X07" | grep -iE "$AUDR"); [ -n "$u" ] && ! printf "%s\n" "$u" | gq -iE "$CARVE" && ! t3_reads_passed'
T3_2B="$(printf "%s\n" "$T3_SMOKE" | awk '/^\*\*2b\./{on=1} /^\*\*3\./{exit} on')"
check "Phase 2 step 2b: an audit that belongs to a left-out item reads Left out (your choice) even when it finds nothing, not only its findings" \
  's=$(printf "%s\n" "$T3_2B" | sents2 | grep -F "Left out (your choice)" | grep -iE "audit|X03|X07|dependenc" | grep -iE "$AUDR"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$CARVE|only (its |the )?findings" && ! t3_reads_passed'

# review11 Minor: a passing left-out test was checked, so the rule gives the true reason it is never PASS
check "report rule: a left-out test is never PASS because its result is left out with it, not because it was not checked" \
  'printf "%s\n" "$AFTS" | grep -qF "never PASS (its result is left out with it)" && ! printf "%s\n" "$AFTS" | gq -F "never PASS (it was not checked)"'

# ---- Task 4: ship-it ----
# ship-it-guide names every left-out [BLOCK] item in its high-stakes production ask; it never silently blocks or passes one.
SHIP=.claude/make-it/references/ship-it-guide.md
# the guide's paragraphs about left-out items (one that names them, or any under a heading that does); the ones of those
# about the production ask; their sentences
T4_P="$(paras < $SHIP | awk -v lo="$LO" '/^#/{insec=(tolower($0) ~ lo)} insec || tolower($0) ~ lo' || true)"
t4p()  { printf "%s\n" "$T4_P" | grep . || true; }
t4ap() { t4p | grep -iE "\bask(s|ed)?\b|high-stakes|approval-block|\bpicks?\b|\bchooses?\b" || true; }
t4s()  { t4p | sed 's/\. /.\
/g'; }
t4as() { t4ap | sed 's/\. /.\
/g'; }
# narrow scope, for the positive checks: only the paragraphs that name a left-out item (as before 3545d53). The rejects,
# and the asker / moment checks, keep the wide scope above, so an opposite anywhere in the left-out section still fails them
t4pn()  { t4p | grep -iE "$LO" || true; }
t4apn() { t4ap | grep -iE "$LO" || true; }
t4sn()  { t4pn | sed 's/\. /.\
/g'; }
t4asn() { t4apn | sed 's/\. /.\
/g'; }
# a non-[BLOCK] item becomes one token, so its own "no" / "not" is never read as a negation
t4_nonb() { perl -pe 's/(\bnot\b|\bisn\x27t\b|\baren\x27t\b)( a| an)? `?\[BLOCK\]`?( items?)?|\bno `?\[BLOCK\]`?( checks?)?|\bwithout( a| any)? `?\[BLOCK\]`?( checks?)?|\bnon-`?\[BLOCK\]`?( items?)?/NONBLOCK/gi'; }
# what a line affirms: each negated clause removed, from the negation to the next . ; : ) or ", and/but/so/then/yet"
# (a file name's dot is not a stop). A negation inside an if/when clause ends at that clause's comma, so a negated
# condition never swallows the main clause ("If the user doesn't pick, ship them all" still affirms "ship them all").
t4_aff() { t4_nonb | perl -pe 's/\.(md|json|txt|yml)\b/\x01$1/g; s/\b(if|when|whenever|while|once|until)\b([^,.;:]*?)(\bnever\b|\bnot\b|n\x27t\b|\bneither\b|\bnor\b|\bnone\b|\bno\b)[^,.;:)]*/$1$2/gi; s/(\bnever\b|\bnot\b|n\x27t\b|\bneither\b|\bnor\b|\bnone\b|\bno\b)(?:(?!, (?:and|but|so|then|yet)\b)[^.;:)])*//gi; s/\x01/./g'; }
T4_QUAL='\bunless\b|\bexcept\b|\bbut not\b|\bother than\b'
# (gq is defined at the top: every negated check uses it)

# T4-1: the production checks read the record through the definition; the guide points at it, never restates it
check "ship-it-guide: a production-check sentence reads the left-out record through left-out-record.md" \
  'psents < $SHIP | t4_aff | awk "{L[NR]=\$0} END{for(i=1;i<=NR;i++) if(index(L[i],\"left-out-record.md\")){s=L[i]; gsub(/left-out-record\.md/,\"\",s); if(tolower(s) ~ /read|record/ && tolower(L[i-1]\" \"L[i]) ~ /production/) f=1}; exit !f}"'
check "ship-it-guide points at left-out-record.md and does not restate it (headings, reader rule, read steps; a [BLOCK]-item definition only beside the pointer)" \
  'grep -qF left-out-record.md $SHIP && ! grep -qE "$HEAD|^## How a skill reads it|^## The rule every reader follows|Mentioned, never offered|Never put back on its own|brings an item back|up to the next .## . heading" $SHIP && ! psents < $SHIP | grep -F "[BLOCK]" | grep -F build-standards | gq -vF left-out-record.md'

# T4-2: never silently blocked, never silently passed -- each "never" bound to its own verb, and no sentence affirms the opposite
# the [BLOCK] tag is never read as the verb "block"
t4x() { sed 's/\[BLOCK\]/[XB]/g'; }
T4_SIL='silently|without (the|this|that|an|its|a|asking)\b'
T4_ASKLESS='without (asking|a question|telling)|without (the|this|that|its|an|a)( [a-z-]+){0,2} ask\b|silently'
# the opposites, affirmed: either verb without the ask; a check that fails / skips the item outright; "ship anyway"; a default
# review3 Important 1: /ship-it is the actor too -- it skips the ask, sends the item straight to the gate, ships it as it is
T4_BLKX="\b(block|fail|stop|hold)[a-z]*\b[^.;:]{0,40}($T4_ASKLESS)|silently (block|fail|stop|hold)|\b(checks?|gate|preflight|CI|automation|ship-it)\b[^.;:]{0,30}\b(fails?|failed|blocks?|blocked|holds?|held|stops?|stopped) (the (ship|deploy|release)|it|them|each|every|the item|that item|an? left.out|left.out)\b"
T4_PASX="\b(pass|skip|ignor|wav)[a-z]*\b[^.;:]{0,40}($T4_ASKLESS)|\bship(s|ped)?\b[^.;:]{0,30}($T4_ASKLESS)|silently (pass|skip|ship|ignor|wav)|\bship(s|ped)?( it| them)?( all)? anyway\b|\bgo(es)? live anyway\b|\b(checks?|gate|preflight|CI|automation|ship-it)\b[^.;:]{0,30}\b(skips?|skipped|ignores?|ignored|waves?|waved|pass(es)?|passed) (it|them|each|every|the item|that item|an? left.out|left.out|over)\b|\bskip(s|ped|ping)? (the|this|that|its)( [a-z-]+)? ask\b|\bask\b[^.;:]{0,20}\b(is|gets) (skipped|dropped|bypassed)\b|\b(straight|directly) (to|into) (the )?(DevOps-owned |production )?(gate|preflight)\b|\bship(s|ped)? (each|every|it|them|the item)\b[^.;:]{0,40}\bas (it|they) (is|are)\b|\b(is|as|becomes) the default\b|\bby default\b|\bdefaults? to\b"
# a no-answer default: a sentence about the user not answering, with that phrase dropped, must not then ship, skip or block
# (a "nothing ..." clause counts as negated: "If the user doesn't answer, nothing ships" is fine)
T4_NOANS='\bno (answer|pick|reply|response|choice)\b|\b(doesn.t|does not|don.t|do not|didn.t|did not|can.t|cannot|won.t|will not|never) (answer|pick|choose|reply|respond|decide)s?\b|\b(without|with no) (an? |their |the user.s )?(answer|pick|reply|response|choice)\b|\b(is|are) (unsure|not sure|undecided|silent|away)\b'
t4_noans() { t4s | grep -iE "$T4_NOANS" | R="$T4_NOANS" perl -pe 's/$ENV{R}//gi' | t4_aff | perl -pe 's/\bnothing\b[^,.;:]*//gi' | t4x || true; }
T4_BLK="(\bnever|\bnot\b|\bneither|\bnor\b)( be| is| gets?)? silently (block|fail|stop|hold)[a-z]*|(\bnever|\bnot\b|n.t\b) (block|fail|stop|hold)[a-z]*[^.;:]{0,30}($T4_SIL)|(\bnone\b|\bno\b [a-z -]{0,30}checks?\b)[^.;:]{0,60}\b(block|fail|stop|hold)[a-z]*[^.;:]{0,60}without (the|this|that|an|its|a|asking)\b"
T4_PAS="(\bnever|\bnot\b|\bneither|\bnor\b)( be| is| gets?)? silently (pass|skip|ship|ignor|wav)[a-z]*|(\bnever|\bnot\b|n.t\b) (pass|skip|ship|ignore|wave)[a-z]*[^.;:]{0,30}($T4_SIL)|(\bnone\b|\bno\b [a-z -]{0,30}checks?\b)[^.;:]{0,60}\b(pass|skip|ignor|wav)[a-z]*[^.;:]{0,60}without (the|this|that|an|its|a|asking)\b"
check "production checks: a left-out [BLOCK] item is never silently blocked (none fails the ship on it without the ask)" \
  's=$(t4sn | grep -F "[BLOCK]" | t4x | grep -iE "$T4_BLK"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4s | t4_aff | t4x | gq -iE "$T4_BLKX" && ! t4_noans | gq -iE "\b(block|fail)(s|ed|ing)?\b"'
check "production checks: a left-out [BLOCK] item is never silently passed (none skips it or ships it without the ask)" \
  's=$(t4sn | grep -F "[BLOCK]" | t4x | grep -iE "$T4_PAS"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4s | t4_aff | t4x | gq -iE "$T4_PASX" && ! t4_noans | gq -iE "\bship(s|ped)?( it| them| anyway| with)\b|\bships\b|\bshipped\b|\b(skip|pass|wav)[a-z]*\b|\bdefault\b|\bgo(es)? (live|ahead)\b|\bdeploy[a-z]*\b"'

# T4-3: the production ask names each one -- the item, what it guards in plain words, that the user left it out -- and the user picks per item
check "the production ask names each left-out [BLOCK] item by name (never only a count)" \
  's=$(t4asn | t4_aff | grep -v NONBLOCK | grep -iE "\b(names?|naming) (each|every)\b|\bby (its )?name\b" | grep -iE "\[BLOCK\]|each one|every one"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4as | t4_aff | gq -iE "\b(a|the) (count|number|total) of\b|\bhow many\b|\bwithout naming\b" && ! t4s | t4_aff | gq -iE "\bonly the first\b|\bfirst (one|item)s? only\b|\bjust the first\b|\bthe first (one|item)\b[^.;:]{0,20}\b(when|if) there (are|is) (many|several|more)"'
T4_GUARD='what (it|each( one)?|the item|that item|they) (guards?|protects?|keeps? safe)|\b(which|it|that) (guards|protects)\b'
check "the production ask says what each one guards, in plain words (never its check IDs)" \
  't4asn | t4_aff | grep -iE "$T4_GUARD" | grep -qiE "plain (words|language|english)" && ! t4as | t4_aff | gq -iE "\bcheck IDs?\b|\bby (its )?(check )?IDs?\b|\b(its|their) IDs?\b"'
T4_LEFT='\b(the user|they|you) (left|chose to leave) (it|them|each( one)?|the item|that item|(\*\*)?\[[^]]*\](\*\*)?) out\b|\b(the user|they|you) left out (it|them|the item|that item|(\*\*)?\[[^]]*\](\*\*)?)|left out by (your|their|the user.s) choice|\byou chose to leave\b'
check "the production ask says the user left it out (their choice, never a failure)" \
  't4asn | t4_aff | grep -iE "\b(names?|naming|says?|tells?|guards?|shows?|you)\b|\[[^]]*item" | gq -iE "$T4_LEFT" && ! t4as | t4_aff | gq -iE "\bas (a |an )?(failed|failing|failure|missing|broken|error)\b|\b(is|was) (missing|broken|failing)\b" && ! t4as | t4_aff | gq -E "\bFAIL\b"'
T4_PICK='(for each|per item|each one|for every|item by item|one by one|one at a time)[^.;]{0,40}\b(picks?|chooses?|choose|answers?|decides?)\b|\b(picks?|chooses?|choose|answers?|decides?)\b[^.;]{0,40}(for each|per item|each one|for every|item by item|one by one|one at a time)'
T4_SHIPOPT='\bship (it |anyway |now )?with (\*\*)?\[[^]]+\](\*\*)?( still)? left out|\bship (it |anyway |now )?with (it|the item|that item|each one)( still)? left out[^.;:]{0,25}(\(named\)|\bby name|\bnam(ed|ing) it)'
T4_APPLYOPT='\b(apply|add|build) (it|them|(\*\*)?\[[^]]+\](\*\*)?|the item|that item|each one) (first|before)'
check "for each left-out [BLOCK] item the user picks: ship with [item] left out (named), or apply it first" \
  't4apn | t4_aff | flat | grep -iE "$T4_PICK" | grep -iE "$T4_SHIPOPT" | grep -qiE "$T4_APPLYOPT" && ! t4as | grep -iE "$T4_PICK" | gq -iE "$T4_QUAL"'
check "the per-item pick is never one answer for all of them (never batched)" \
  't4apn | t4_aff | gq -iE "$T4_PICK" && ! t4p | t4_aff | gq -iE "\b(one|a single) (answer|pick|choice|reply|yes|confirmation) (for|covers?) (all|every|them|the (whole )?list)|\ball at once\b|\bin one (go|batch)\b|\bbatch(ed|es)?\b|\bone question\b|\bask(s|ed)?( about (them|all|each)[a-z ]{0,20})? once\b|\btogether\b|\bthe whole list\b|\bcovers? (every|each|all)\b"'
check "the production ask is active confirmation (approval-block.md)" \
  't4apn | gq -F approval-block.md && t4asn | t4_aff | gq -iE "active confirmation"'
T4_PLAINYES='(\bnever|\bnot\b|n.t\b|\bno\b)[^.;:]{0,15}\bplain .?yes\b'
check "the production ask is never a plain yes" \
  's=$(t4asn | grep -iE "$T4_PLAINYES"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4p | t4_aff | gq -iE "\bplain .?yes\b|\b(a|one|their) .?yes.? (is|will be|counts as) (enough|fine|ok)|\byes/no\b|\by/n\b|\b(just |simply )?(answers?|says?|types?|repl(y|ies)|confirms?)( with)? .?yes\b|ok to proceed|\b(ok|okay)\b|\byes.? covers?\b"'

# T4-4: a left-out item that is not [BLOCK] does not add to the high-stakes ask; no sentence puts every left-out item in it
T4_OUT='(\bnever|\bnot\b|n.t\b|\bno\b|\bnone\b)[^.;:]{0,30}\b(add|adds|added|go|goes|in|into|join|joins|named|listed|part)\b[^.;:]{0,25}\bask\b|\b(stays?|kept|left) out of[^.;:]{0,20}\bask\b|\boutside[^.;:]{0,15}\bask\b'
check "a left-out item that is not [BLOCK] does not add to the high-stakes ask (and no sentence puts every left-out item in it)" \
  's=$(t4sn | t4_nonb | grep -F NONBLOCK | grep -iE "$T4_OUT"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4s | t4_aff | grep -F NONBLOCK | gq -iE "\b(adds?|added|goes|go|is|are)\b[^.;:]{0,20}\b(in|into|to)\b[^.;:]{0,20}\bask\b|\b(named|listed|included|asked)\b[^.;:]{0,20}\bask\b|\basked( about)?\b|\bthe same way\b" && ! t4s | t4_aff | grep -iE "\bask\b" | grep -iE "\b(every|each|all|any)( the| other)? left.out items?\b[^.;:]{0,40}\b(goes|go|is|are|gets?|added|named|listed|included|in)\b[^.;:]{0,20}\bask\b|\b(names?|lists?|includes?|shows?) (every|each|all|any)( the| other)? left.out items?\b" | gq -vF "[BLOCK]" && ! t4s | grep -iE "\bask\b" | gq -iE "\[BLOCK\].? or not|whether or not[^.;:]{0,30}\[BLOCK\]|not only[^.;:]{0,10}\[BLOCK\]"'

# T4-5: the desktop bundles that carry ship-it-guide.md carry the definition it now cites
for f in desktop/skills/make-it/refs.txt desktop/skills/handoff/refs.txt; do
  check "$f bundles left-out-record.md beside ship-it-guide.md" \
    "grep -qxF .claude/make-it/references/ship-it-guide.md $f && grep -qxF .claude/make-it/references/left-out-record.md $f"
done

# ---- Task 4 fix round 1 ----
# the guide as units, one per line: a paragraph, a list item, or one line of a code block. A list item under a heading or
# bold label that says what something does NOT do reads "never ...": that heading negates it.
t4_units() { awk '
  function out() { if (u != "") print u; u = "" }
  /^```/ { out(); fence = !fence; next }
  fence { print; next }
  /^#/ || /^\*\*[^*].*\*\*:?$/ { out(); neg = ($0 ~ /NOT do|[Dd]oes not do|[Nn]ever does/); print; next }
  /^[[:space:]]*$/ { out(); next }
  /^ *(- |\* |[0-9]+\. )/ { out(); u = $0; if (neg && u ~ /^ *(- |\* )/) { sub(/^ *(- |\* )/, "", u); u = "never " u }; next }
  { u = (u == "") ? $0 : u " " $0 }
  END { out() }' $SHIP; }
t4sent() { sed 's/\. /.\
/g'; }
T4_NEGW='(\bnever\b|\bnot\b|n.t\b|\bno\b|\bnone\b|\bneither\b|\bnor\b)'

# review1 Important 1: /ship-it itself asks, at its prod-ready Intent Classification, before the production gate
T4_ASKER='/ship-it( itself| alone)? (asks|raises)\b|/ship-it.s own\b[^.;:]{0,25}\bask\b|\bask(ed)? by /ship-it\b|\bit is /ship-it (that|who) asks\b'
T4_WHO_GATE='\b(DevOps|CI|automation|pipeline|preflight|gate|BOT|bot|reviewers?)\b'
# review2 Minor 6 (O): "/ship-it asks ..., or else the DevOps-owned gate or CI" opens the asker up after the verb
T4_NOTASKER="$T4_WHO_GATE[^.;:/]{0,20}\b(asks|raises)\b|$T4_WHO_GATE[^.;:/]{0,20}\b(can|will|may|should|must|then) ask\b|\bask(ed)? by (the )?(DevOps|CI|automation|pipeline|preflight|production gate|DevOps-owned gate|gate|reviewers?)\b|\b(asks|raises)\b[^.;:]{0,80}\b(or|and|otherwise|else)( else)?( by| from)?( the)? $T4_WHO_GATE"
check "the production ask is /ship-it's own: /ship-it itself asks it, never the DevOps-owned gate, CI or the reviewers" \
  't4s | t4_aff | gq -iE "$T4_ASKER" && ! t4s | t4_aff | gq -iE "$T4_NOTASKER"'
T4_WHEN='Intent Classification|intent:prod-ready|\bprod-ready\b'
T4_BEFORE='\bbefore\b[^.;:]{0,60}\b(production gate|DevOps-owned gate|production preflight|the gate)\b'
T4_LATE='\bafter\b[^.;:]{0,30}\b(production gate|DevOps-owned gate|production preflight|the gate)\b|\bask(s|ed)?\b[^.;:]{0,40}\b(at|during|in|from) the (DevOps-owned |production )?(gate|preflight)\b|\bask(s|ed)?\b[^.;:]{0,40}\b(at|during|in) the dev environment\b'
check "/ship-it asks at its prod-ready Intent Classification, before anything goes to the production gate (never at or after the gate)" \
  't4p | t4_aff | grep -iE "$T4_WHEN" | gq -iE "$T4_BEFORE" && ! t4s | t4_aff | gq -iE "$T4_LATE"'
T4_ROW="$(grep -E '^\| *`?\.make-it-state\.md`? *\|' $SHIP || true)"
check "the table of what /ship-it reads from .make-it-state.md lists the left-out record" \
  'printf "%s\n" "$T4_ROW" | t4_aff | grep -qiE "left.out (record|items?)|Left out by your choice|left-out-record\.md" && ! printf "%s\n" "$T4_ROW" | gq -iE "left.out[^|]{0,40}\b(skip|ignor)"'

# review1 Important 2: the pick travels -- into the PR's go-live checklist by name, and through the CI/CD contract
T4_BYNAME='\bby (its |their )?names?\b|\bnam(es|ing|ed) (each|every|it|them|the item|that item)\b'
T4_SHIPPICK='\bpicks?\b|\bchoices?\b|\bchose\b|\bship(s|ped)? with\b|\banswers?\b'
T4_NOLIST="$T4_NEGW( be| been| get| gets| go| goes| is| are)? (recorded|listed|named|written|added|noted|put|carried|shown|in|into|on)\b|go-live checklist (never|does not|doesn.t|won.t|will not) |(kept|left|stays?|omitted|removed|dropped)( out)? (of|off|from) the[^.;:]{0,15}go-live|without (its |the |their )?names?\b|\bonly (a |the )?(count|number|total)\b|\b(count|number|total)s? only\b|\bas (a |the )?(count|number|total)\b|\bunnamed\b"
check "each \"ship with [item] left out\" pick is recorded in the PR's go-live checklist, by name" \
  's=$(psents < $SHIP | t4_aff | grep -iE "go-live checklist" | grep -iE "$T4_BYNAME" | grep -iE "$T4_SHIPPICK"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! psents < $SHIP | grep -iE "go-live checklist" | gq -iE "$T4_NOLIST"'
T4_CHOSE='\b(chose|chooses|picked|picks|decided|decides) to ship\b|\bship(s|ped)? (it |them )?with (it|them|the item|that item|(\*\*)?\[[^]]+\](\*\*)?)( still)? left out\b|\bshipped (it |them )?(still )?left out\b|\bship(s|ped)? without (it|them)\b'
T4_REMED='\bremediat[a-z]*\b[^.;:,]{0,40}\bleft.out\b|\bremediat(e|es|ed|ing) (it|them)\b|\bleft.out\b[^.;:]{0,60}\b(is|are|gets?|be|get)( then)? (remediated|put back|added back|re-?added)\b|\bleft.out (item|\[BLOCK\] item)s?\b[^.;:]{0,60}\b(blocks?|fails?|holds?|stops?) (the )?(gate|ship|deploy|release|production)\b'
# the units that say it: a left-out item the user chose to ship with, its remediation, its putting back and its blocking.
# Each of the three is negated: in the unit, but gone from what the unit affirms (t4_aff); "report" stays affirmed.
T4_PUTBACK='\b(put|add|bring|brought)[a-z]*( it| them| the item)? back\b'
t4_ci() { t4_units | grep -iE "$LO" | grep -iE "$T4_CHOSE" | grep -iE "$T4_WHO_GATE" | grep -iE "\bremediat" | grep -iE "$T4_PUTBACK" \
  | grep -iE "\b(block|fail|hold|stop)[a-z]*\b[^.;:]{0,40}(on (its|their) own|by (itself|themselves)|\balone\b|\bon (it|them|that item|the item|an? left.out|each)\b)" || true; }
# review2 Minor 6 (G): the report names the item, never only a count
T4_COUNTONLY='\b(only|as|in) (a |the )?(count|number|total|tally)\b|\b(count|number|total)s? only\b|\bunnamed\b|\bwithout (its |the |their )?names?\b|\bnot by name\b'
check "CI/CD contract: a left-out item the user chose to ship with is reported by name -- never remediated or put back, and never blocks the gate on its own" \
  's=$(t4_ci); a=$(printf "%s\n" "$s" | t4_aff | t4x); [ -n "$s" ] && printf "%s\n" "$a" | grep -qiE "\breport(s|ed|ing)?\b[^.;:]{0,40}($T4_BYNAME)" && ! printf "%s\n" "$s" | gq -iE "$T4_COUNTONLY" && ! printf "%s\n" "$a" | gq -iE "\bremediat|$T4_PUTBACK|\b(block|fail|hold|stop)[a-z]*\b" && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4_units | grep -iE "$LO" | t4sent | t4_aff | gq -iE "$T4_REMED"'

# review1 Minor 5: the pointer covers the reader rules too, so /ship-it's own auto-fix loops never put an item back or call it FAIL
check "ship-it-guide's pointer to left-out-record.md also covers its reader rules (not only its read steps and the [BLOCK] test)" \
  'psents < $SHIP | grep -F left-out-record.md | t4_aff | grep -qiE "\brules? (that )?every reader follows\b|\breader.?s? rules?\b|\brules? (for|of) (every|each) reader\b"'
T4_AUTOFIX='\bauto-?fix(es|ing|ed)?\b|\bfix (loops?|cycles?)\b|\bauto-?remediat'
# review3 Minor 4: the reject reads every sentence in the left-out section (and every left-out unit), not only "auto-fix" ones
t4_secu() { t4_units | awk -v lo="$LO" '/^#/{insec=(tolower($0) ~ lo)} insec || tolower($0) ~ lo' || true; }
check "/ship-it's own auto-fixes (the package upgrades, the pre-push secret leak scan) never put a left-out item back or report its check as FAIL (and no sentence in the left-out section puts one back)" \
  's=$(t4_units | grep -iE "$LO" | t4sent | grep -iE "$T4_AUTOFIX" | grep -iE "$T4_NEGW[^.;:]{0,80}\b(put|add|bring)[a-z]*\b[^.;:]{0,30}\bback\b" | grep -iE "$T4_NEGW[^.;:]{0,120}\bFAIL\b"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4_secu | t4sent | t4_aff | gq -iE "\b(puts?|adds?|brings?)\b[^.;:]{0,30}\bback\b|\b(reports?|reads?|marks?|shows?|counts?)\b[^.;:]{0,30}\bas (a )?FAIL\b"'

# review1 Minor 7: the ask in a first-time builder's words
T4_ADDOPT='\bAdd (\*\*)?\[[^]]+\](\*\*)? first\b'
t4_addu() { t4_units | grep -iE "$T4_ADDOPT" | t4_aff || true; }
check "the ask's second option reads \"Add [item] first\" (the user's own word), never \"Apply it first\"" \
  't4_addu | grep -qiE "$T4_ADDOPT" && ! t4p | t4_aff | gq -iE "\bapply (it|them|this|that|the item|each one) first\b"'
T4_ADDER='/resume-it|\bthis session\b|\bI (add|will add|can add)\b|\bI.ll add\b|\b(added|built|applied) (here|now|right now|in this session|with /resume-it|by /resume-it)\b|/ship-it (adds|will add)\b'
T4_NEXTSTEP='\b(type|run|say)\b[^.;:]{0,30}/ship-it|/ship-it\b[^.;:]{0,20}\bagain\b'
check "\"Add [item] first\" says what happens next: who adds it, and what the user types after" \
  't4_addu | grep -iE "$T4_ADDER" | grep -qiE "$T4_NEXTSTEP"'
T4_WAIT='\bproduction waits\b|\bwaits?\b[^.;:]{0,40}\b(until|till)\b|\bnothing (goes|ships|is shipped|is deployed|reaches|moves)\b[^.;:]{0,30}\b(production|live|prod)\b|\b(on hold|held)\b[^.;:]{0,30}\buntil\b'
check "\"Add [item] first\" says production waits until it is in (nothing ships meanwhile)" \
  'u=$(t4_addu); printf "%s\n" "$u" | grep -qiE "$T4_WAIT" && ! printf "%s\n" "$u" | perl -pe "s/\bnothing\b[^,.;:]*//gi" | gq -iE "\b(ships?|shipped|goes live|go live|deploys?|goes ahead|go ahead|proceeds?|goes to production)\b[^.;:]{0,30}\b(meanwhile|anyway|in the meantime|while|now)\b|\b(add|added|build|built|applied)\b[^.;:]{0,15}\blater\b"'
T4_SHIPLBL='\bShip with (\*\*)?\[[^]]+\](\*\*)? left out'
T4_CONSEQ='\bmeans?\b|\banyone\b|\beveryone\b|\bconsequences?\b'
T4_UNDO='\bundo\b|\bundone\b|\btaken? (it |that |this )?back\b|\b(add|bring) (it|them|(\*\*)?\[[^]]+\](\*\*)?) (in |back )?later\b|\blater\b[^.;:]{0,30}/resume-it|/resume-it[^.;:]{0,40}\blater\b'
# review2 Minor 6 (I): "add it later" alone is not the whole undo; what people saw while it was live can't be taken back
T4_NOUNDO='\b(can.t|cannot|can not|won.t|will not|never)( ever)?( be)? (taken back|undone|undo|take[n]? (it|that|this|them) back)\b|\bno undo\b'
T4_NOSAY="$T4_NEGW[^.;:]{0,20}\b(say|tell|give|mention|state|explain)s?\b[^.;:]{0,30}\b(what|undo|how|consequences?|means)\b"
check "\"Ship with [item] left out\" says what that means while it is live, and the undo, with what can't be taken back (approval-block item 3)" \
  'u=$(t4_units | grep -E "$T4_SHIPLBL"); printf "%s\n" "$u" | grep -iE "$T4_CONSEQ" | grep -iE "$T4_UNDO" | grep -qiE "$T4_NOUNDO" && ! printf "%s\n" "$u" | gq -iE "$T4_NOSAY"'
T4_WHY='\bwhy (it|each( one)?|the item|that item|this item) (blocks|is a blocker|comes up|matters|must|has to|needs)\b|\b(must|has to|needs to|should) be (in place|there|added|on|working|in)\b[^.;:]{0,40}\bbefore\b'
check "the ask says why each named left-out [BLOCK] item blocks (it must be in place before going live)" \
  't4asn | t4_aff | gq -iE "$T4_WHY"'

# review1 Minor 8: in the make-it bundle, left-out-record.md sits under a comment that says ship-it-guide.md cites it
check "desktop/skills/make-it/refs.txt: left-out-record.md sits under a comment saying ship-it-guide.md cites it (not the @-imports comment)" \
  'c=$(awk "/^#/{c=\$0} \$0==\".claude/make-it/references/left-out-record.md\"{print c; exit}" desktop/skills/make-it/refs.txt); printf "%s\n" "$c" | grep -qiE "\b(cited|named|referenced|linked) (by|in|from) ship-it-guide\.md" && ! printf "%s\n" "$c" | gq -iE "@-import|\b(not|never)\b|n.t\b"'

# ---- Task 4 fix round 2 ----
# review2 Important 1: the two later paths into production reach the user by name
T4_DEVOK='ready for production'
T4_VIASHIP='\b(through|via|by|in) /ship-it\b|/ship-it( itself)? (asks|raises)\b'
T4_SAMEASK='\bthe same (way|ask)\b|\b(the|its|this|that) (production |left-out )?ask\b'
T4_STRAIGHT='\b(straight|directly|right)( on)? (to|into|on to) (the )?(DevOps-owned |production )?(gate|preflight|production|prod|DevOps)\b|\bskip(s|ping)? (the|this|that|its)( [a-z-]+)? ask\b|\bbypass[a-z]*\b'
t4_devs() { { t4s | grep -iE "dev environment"; psents < $SHIP | grep -iE "$T4_DEVOK"; } || true; }
check "the dev environment's \"ready for production\" comes through /ship-it's ask the same way (never straight to the production gate)" \
  's=$(t4s | t4_aff | grep -iE "$T4_DEVOK" | grep -iE "dev environment|\bdev\b" | grep -iE "$T4_VIASHIP" | grep -iE "$T4_SAMEASK"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4_devs | t4_aff | gq -iE "$T4_STRAIGHT|$T4_ASKLESS" && ! t4_devs | gq -iE "\bno( [a-z-]+){0,2} (ask|question)s?\b"'
# a sentence where DevOps (or the final review) holds the ship: what it affirms tells the user, by name
T4_HOLD='\b(DevOps|reviewers?|final review)\b[^.;:]{0,40}\b(hold|holds|holding|held)\b|\b(hold|holds|holding|held)\b[^.;:]{0,40}\bfinal review\b'
T4_TOLD='\b(told|tell|tells|notified|notifies|notify)\b[^.;:]{0,40}\bby (its |their |the item.s )?names?\b'
T4_UNTOLD='\bwithout (telling|notifying|naming|a word|a (PR )?comment)\b|\bsilently\b|\bnot by name\b|\bunnamed\b|\bas a count\b'
t4_holds() { { t4s; t4_units | grep -iE "$LO" | t4sent; } | while IFS= read -r l; do printf "%s\n" "$l" | t4_aff | gq -iE "$T4_HOLD" && printf "%s\n" "$l"; done; true; }
check "a DevOps hold on a left-out item at the final review: the user is told, by name (never a silent hold)" \
  's=$(t4_holds); [ -n "$s" ] && ! printf "%s\n" "$s" | t4_aff | gq -viE "$T4_TOLD" && ! printf "%s\n" "$s" | gq -iE "$T4_UNTOLD|$T4_QUAL"'

# review2 Minor 6 (P): the CI bullet's own clause -- a left-out item's checks don't count against "all checks"
T4_ALLCHK='\bcount(s|ed)?\b[^.;:]{0,15}\b(against|toward|towards|in|as)\b[^.;:]{0,5}all checks\b'
check "CI/CD contract: a left-out item's checks don't count against \"all checks\"" \
  's=$(t4_units | grep -iE "$LO" | t4sent | grep -iE "$T4_ALLCHK"); [ -n "$s" ] && printf "%s\n" "$s" | grep -qiE "$T4_NEGW[^.;:]{0,30}$T4_ALLCHK" && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! t4_units | grep -iE "$LO" | t4sent | t4_aff | gq -iE "$T4_ALLCHK"'

# review2 Minor 2: the auto-fix sentence names all of /ship-it's own fixes. E02-S21 (the owner's Split): those are the package
# upgrades and the pre-push secret leak scan; the NeMo remediation, the rest of the pre-push review and CI monitoring are no
# /ship-it steps any more (build-verify and /nemo-it cover them), so the sentence never names them
check "/ship-it's auto-fix sentence names all its own fixes: the package fixes and the pre-push secret leak scan (never the NeMo (AI-safety) remediation or CI monitoring, which /ship-it doesn't run)" \
  's=$(t4_units | grep -iE "$LO" | t4sent | grep -iE "$T4_AUTOFIX" | grep -iE "$T4_NEGW[^.;:]{0,80}\b(put|add|bring)[a-z]*\b[^.;:]{0,30}\bback\b"); [ -n "$s" ] && printf "%s\n" "$s" | grep -iE "\bpackages?\b|\bdependenc(y|ies)\b|\bvulnerab" | grep -iE "\bpre-push\b" | grep -qiE "\bsecret leak scan\b" && ! printf "%s\n" "$s" | gq -iE "\bNeMo\b|\bAI.safety\b|\bguardrails?\b|\bCI\b|\bmonitoring\b" && ! printf "%s\n" "$s" | gq -iE "\b(not|excluding|apart from|besides|outside)( in)?( the| its)? (packages?|dependenc|vulnerab|pre-push|secret leak scan)\b"'

# review2 Minor 3: the words a first-time builder reads, and the next step on each path
T4_JARGON='\b(its|the|an?|this|own) ask\b|\[BLOCK\]|high-stakes|active confirmation|left-out-record'
T4_CHECKSWITH='\b(checks?|confirms?)( it)? with you\b|\basks? you\b|\b(asks?|checks?)( with you)? (first|before)\b'
check "the ask's quoted words carry no guide jargon (\"its own ask\"); \"Add [item] first\" says /resume-it checks with the user before adding" \
  '! t4p | grep -oE "\"[^\"]+\"" | gq -iE "$T4_JARGON" && t4_addu | grep -qiE "$T4_CHECKSWITH"'
T4_STOPNOW='\b(stops?|stopping|ends?|ending)( right)? (here|now)\b|\bstops? for now\b'
check "\"Add [item] first\" says /ship-it stops here and nothing is sent, not only that nothing goes live (no PR, no dev deploy meanwhile)" \
  'u=$(t4_addu); printf "%s\n" "$u" | grep -qiE "$T4_STOPNOW" && printf "%s\n" "$u" | grep -qiE "\bnothing (is |gets )?sent\b" && ! printf "%s\n" "$u" | perl -pe "s/\bnothing\b[^,.;:]*//gi" | gq -iE "\b(still|also|then)\b[^.;:]{0,20}\b(opens?|creates?|sends?|pushes|deploys?)\b|\b(opens?|creates?|sends?) (the |a )?(PR|pull request)\b|\b(PR|pull request) (is |gets )?sent\b|\bdeploys? to dev\b|\bgoes to (dev|the dev environment)\b"'
check "the DevOps-hold PR comment gives the next step: /resume-it, then /ship-it again" \
  'h=$(t4p | t4_aff | grep -oiE "($T4_HOLD).*"); [ -n "$h" ] && ! printf "%s\n" "$h" | gq -vF /resume-it && ! printf "%s\n" "$h" | gq -viE "$T4_NEXTSTEP"'

# review2 Minor 4: where the ask happens, the guide points at its section
T4_SECPTR='Left-out items before production|#left-out-items-before-production'
check "Intent Classification points at Left-out items before production, on intent:prod-ready" \
  'awk "/^#/{on=(\$0==\"### Intent Classification\")} on" $SHIP | paras | t4_aff | grep -iE "prod-ready" | grep -qiE "$T4_SECPTR"'
# review3 Minor 3: and the confirmation goes via /ship-it, on the same line or row (never to DevOps directly)
T4_DIRECT='\bwithout /ship-it\b|\b(to|with) DevOps\b|\bdirectly\b|\bbypass[a-z]*\b'
check "the diagram's DEV ENVIRONMENT step confirms via /ship-it and points at Left-out items before production" \
  'd=$(awk "/^DEV ENVIRONMENT/{on=1} /^PRODUCTION GATE/{on=0} on" $SHIP); printf "%s\n" "$d" | flat | t4_aff | grep -qiE "$T4_SECPTR" && printf "%s\n" "$d" | t4_aff | grep -iE "$T4_DEVOK" | grep -qiE "$T4_VIASHIP" && ! printf "%s\n" "$d" | t4_aff | gq -iE "$T4_DIRECT"'
check "Phase Ownership's production-gate confirmation is via /ship-it and points at Left-out items before production" \
  'r=$(awk "/^## /{on=(\$0==\"## Phase Ownership\")} on" $SHIP | grep -E "^\|" | grep -iE "prod-ready|ready for production|production gate" | t4_aff); printf "%s\n" "$r" | grep -iE "$T4_SECPTR" | grep -qiE "$T4_VIASHIP" && ! printf "%s\n" "$r" | gq -iE "$T4_DIRECT"'

# review2 concern (review1 Minor 6): the definition points at the guide for the ask's form, never words it itself
check "definition's \"At ship, named\" points at ship-it-guide.md's Left-out items before production for the ask (never words it: no \"apply it first\")" \
  'b=$(rb "At ship"); printf "%s\n" "$b" | t4_aff | grep -F ship-it-guide.md | grep -qiE "$T4_SECPTR" && ! printf "%s\n" "$b" | gq -iE "\bapply (it|them) first\b"'

# ---- Task 4 fix round 3 ----
# review3 Minor 5: the Intent Classification pointer holds its condition -- only when the record has a left-out [BLOCK] item
T4_IFBLK='\b(if|when|whenever|only if|only when)\b[^,.;:]{0,40}\bleft.out `?\[BLOCK\]`? items?\b'
check "Intent Classification: the left-out ask comes next only if the record has a left-out [BLOCK] item (never unconditional)" \
  'p=$(awk "/^#/{on=(\$0==\"### Intent Classification\")} on" $SHIP | paras | grep -iE "prod-ready" | grep -iE "$T4_SECPTR"); [ -n "$p" ] && ! printf "%s\n" "$p" | t4_aff | gq -viE "$T4_IFBLK" && ! printf "%s\n" "$p" | gq -iE "$T4_QUAL|\bwhether or not\b|\balways\b|\bregardless\b|\beven (if|when)\b"'
# review3 Minor 6: the hold notice has a sender -- the automation tells the user which item -- and is in its user list
T4_SENDER='\b(automation|CI)\b[^.;:]{0,20}\b(tells|notifies)( the user| you)\b[^.;:]{0,10}\b(which (item|one)|the item.s name|nam(es|ing) (the|each) item)\b'
check "a DevOps hold at the final review: the automation tells the user which item (a named sender, never \"the user is told\")" \
  's=$(t4_holds); [ -n "$s" ] && ! printf "%s\n" "$s" | t4_aff | gq -viE "$T4_SENDER"'
T4_UNOTE="$(awk '/^\*\*Automation -> User notifications\*\*/{on=1;next} on&&/^$/{exit} on&&/^- /{if(u!="")print u; u=$0; next} on{u=u" "$0} END{if(u!="")print u}' $SHIP)"
check "the Automation -> User notifications list carries the hold notice: which item, by name, and the next step (/resume-it)" \
  'printf "%s\n" "$T4_UNOTE" | t4_aff | grep -iE "\b(hold|holds|holding|held)\b" | grep -iE "\bwhich (item|one)\b|\[[^]]*item[^]]*\]|\bby (its |the item.s )?name\b" | grep -qF /resume-it && ! printf "%s\n" "$T4_UNOTE" | gq -iE "$T4_UNTOLD"'

# ---- Task 4 adversarial round 1 ----
# adv1 #1: the PR's go-live checklist follows the user's current answer, not the first ship's pick
T4_REWRITE='\b(re-?writes?|rewritten|rewriting|updates?|updated|updating|rebuilds?|rebuilt|refresh(es|ed)?|redoes|redone|regenerates?|regenerated|replaces?|replaced)\b'
T4_EVERY='\b(each|every|any)( later| new)? (/ship-it|ship|re-?ship|run|time)\b|\bre-?ships?\b|\bagain\b'
# an item no longer left out is one token, so its "no longer" is never read as a negation
t4_back() { perl -pe 's/\bno longer left.out\b/BROUGHTBACK/gi'; }
T4_BACK='\b(the user|they|you) (has |have |had )?(since |later |now |then )?(added|adds|brought (it |them )?back|brings (it |them )?back)\b|\bsince added\b|\bbrought.back\b|BROUGHTBACK'
T4_OFF='\b(comes?|came|goes|drops?|dropped|taken|struck) off\b|\bloses? (its|their)\b|\b(removed|deleted|dropped|struck|cleared|taken) (from|off)\b|\b(removes?|deletes?|drops?|clears?|strikes?) (its|their|that|the|each)( go-live)? (lines?|entry|entries)\b'
T4_STALE='\b(stays?|stayed|remains?|remained|is kept|are kept|is left|are left|keeps?|kept|leaves?)\b[^.;:]{0,40}\bas (it|they) (is|are|was|were)\b|\bas (the )?first (ship|/ship-it|run|pick)[^.;:]{0,10}\b(wrote|left|made|recorded|had)\b|\b(stays?|remains?)\b[^.;:]{0,20}\b(on|in) the (go-live )?(checklist|PR)\b|\b(untouched|unchanged|as-is|for good|permanently|forever)\b|\bkeeps? (treating|counting|reading|reporting|exempting|listing)\b[^.;:]{0,30}\b(left.out|exempt)'
# the sentences of the units that carry the go-live checklist
t4_gl() { t4_units | grep -iE "go-live|checklist" | t4sent | t4_back || true; }
# any guide sentence about the go-live line or a left-out item that keeps the line as the first ship wrote it, or never rewrites it
# final fix review Important 1, re-review Important 1: a bare "lines" is read in every section but "## Infrastructure &
# Terraform" (r5 M6's false alarm, "The tfvars lines"), so "On a re-ship, the PR's lines stay as the first ship wrote them."
# fails in whatever section it is put
t4_stale() { local x; x=$( { t4_units | grep -iE "go-live|checklist|$LO" | t4sent | t4_back; t4_units | t4sent | t4_back | grep -iE "go-live|checklist|\b(the|those|these|its|their|that|such|both|each|every) lines?\b|$LO|BROUGHTBACK"
  awk '/^## /{off=($0=="## Infrastructure & Terraform")} !off' $SHIP | paras | t4sent | t4_back | grep -iE "\blines?\b"; } || true)
  { printf "%s\n" "$x" | t4_aff | grep -iE "$T4_STALE"; printf "%s\n" "$x" | grep -iE "$T4_NEGW[^.;:]{0,20}$T4_REWRITE[^.;:]{0,40}\b(go-live|checklist|lines?)\b|\b(go-live|checklist)\b[^.;:]{0,30}$T4_NEGW[^.;:]{0,15}$T4_REWRITE"; } || true; }
check "each /ship-it rewrites the go-live checklist's left-out lines from the record as it reads then (a re-ship too), never leaves them as the first ship wrote them" \
  't4_gl | t4_aff | grep -iE "$T4_REWRITE" | grep -iE "$T4_EVERY" | grep -qiE "\brecord\b" && [ -z "$(t4_stale)" ]'
check "an item the user has since added comes off the go-live checklist (its \"left out by the user's choice\" line goes)" \
  't4_gl | t4_aff | grep -iE "$T4_BACK" | grep -qiE "$T4_OFF" && [ -z "$(t4_stale)" ]'
T4_COUNTS='\b(its|their) checks\b[^.;:]{0,20}\bcount\b[^.;:]{0,30}\blike (any|every|each|the other|other)\b|\b(checked|counted|treated) like any( other)? `?\[BLOCK\]`? item'
check "a brought-back item's checks count like any [BLOCK] item's (CI never keeps exempting it as left out)" \
  's=$(t4_units | t4sent | t4_back | grep -iE "$T4_BACK" || true); printf "%s\n" "$s" | t4_aff | grep -qiE "$T4_COUNTS" && ! printf "%s\n" "$s" | gq -iE "\b(its|their) checks\b[^.;:]{0,20}$T4_NEGW[^.;:]{0,10}\bcount\b" && ! printf "%s\n" "$s" | t4_aff | gq -iE "\bkeeps? (treating|counting|reading|reporting|exempting|listing)\b[^.;:]{0,30}\b(left.out|exempt)|\bstill (exempt|left.out|treated as left.out)\b|\bexempt"'
T4_DEVCONF='\bdev environment|\bready for production\b'
T4_MIND='\bchange of mind\b|\bchanges? (their|his|her) mind\b|\bpicks?\b|\banswers?\b|\bAdd (\*\*)?\[[^]]+\](\*\*)? first\b'
check "a change of mind at the dev environment's confirmation updates the item's go-live line too" \
  't4_units | t4sent | t4_back | t4_aff | grep -iE "$T4_DEVCONF" | grep -iE "$T4_MIND" | grep -iE "$T4_REWRITE" | grep -qiE "go-live|checklist|\blines?\b" && [ -z "$(t4_stale)" ]'

# adv1 #2: the CI/CD contract says where the automation learns the user's picks: the PR's go-live checklist
T4_PICKS='\bwhich (items?|ones?)\b|\b(user.s )?(picks?|choices?)\b|\bchose\b'
t4_cicd() { t4_units | awk '/^## /{on=(index($0,"## CI/CD Automation Contract")==1)} on' | t4sent || true; }
# contract sentences that name another source for the picks, or infer them
t4_cicdx() { local a; a=$(t4_cicd | t4_aff); { printf "%s\n" "$a" | grep -iE "\b(learns?|reads?|takes?|gets?|finds?( out)?|knows?|works? out)\b[^.;:]{0,30}($T4_PICKS)[^.;:]{0,40}\bfrom\b" | grep -viF "go-live checklist"; printf "%s\n" "$a" | grep -iE "\b(infers?|inferred|guess(es|ed)?|assumes?|decides?)\b[^.;:]{0,40}($T4_PICKS)"; } || true; }
check "CI/CD contract: the automation learns which items the user chose to ship with from the PR's go-live checklist (never from elsewhere, never inferred)" \
  't4_cicd | t4_aff | grep -iE "go-live checklist" | grep -iE "\bPR\b" | grep -iE "\b(reads?|learns?|finds?|takes?|gets?|looks? (up|at|in))\b" | grep -qiE "$T4_PICKS" && [ -z "$(t4_cicdx)" ]'

# adv1 #3: a success line never claims a left-out item was checked: each says which item wasn't, because the user left it out
T4_SUCC='\b(checks?|everything|all)\b[^"]{0,20}\bpass(ed|es)?\b|\bpass(ed)? (all|every|each)\b'
T4_ITEMN='\[[^]]*item[^]]*\]|\bwhich (item|one)\b|\bby (its )?name\b'
T4_UNCHK='\b(could not|couldn.t|can.t|cannot|wasn.t|was not|were not|weren.t|isn.t|is not|not|never)( be| been| get| got| yet)* (checked|tested)\b|\bunchecked\b|\buntested\b'
# each success quote in the guide, with up to 250 characters after it in its paragraph (a code block is one paragraph),
# ending at the next list item or code branch ("- ", "+-- ", "-> ")
t4_succ() { paras < $SHIP | R="$T4_SUCC" perl -ne 'chomp; while (/"([^"]*)"/g) { my ($q, $a) = ($1, substr($_, $+[0], 250)); $a =~ s/ (- |\+-- |-> ).*//; print "\"$q\"$a\n" if $q =~ /$ENV{R}/i }'; }
# the success windows that lack the left-out item, its name, or that it wasn't checked
# final review X2 (r5 M1, M5): also a window whose instruction, outside its quotes, negates the exception ("never add:", "don't
# say:"), makes it optional ("you may add:", "if the user asks:") or narrows it to a left-out [BLOCK] item
T4_SUCCX="$T4_NEGW[^.;:]{0,25}\\b(add|adds|say|says|tell|tells|include|includes|append|mention)\\b|\\b(may|might|can|could|optionally)\\b[^.;:]{0,10}\\b(add|say)|\\bif (the user|they|you) asks?\\b|left-out \`?\\[BLOCK\\]\`? item"
t4_succmiss() { t4_succ | grep . | while IFS= read -r w; do printf "%s\n" "$w" | grep -qiE "$LO|\bleft (it|them) out\b" && printf "%s\n" "$w" | grep -qiE "$T4_ITEMN" && printf "%s\n" "$w" | grep -qiE "$T4_UNCHK" || printf "%s\n" "$w"
  printf "%s\n" "$w" | perl -pe 's/"[^"]*"//g' | gq -iE "$T4_SUCCX" && printf "%s\n" "$w"; done; true; }
# any guide sentence that reports a left-out item as passed or checked
t4_passclaim() { psents < $SHIP | t4_aff | grep -iE "\bleft.out (ones?|items?|checks?)( too| as well| included)\b|\bincluding (the |any |each )?left.out\b|\bleft.out (ones?|items?|checks?) (passed|pass|were checked|was checked|got checked)\b|\b(reports?|says?|tells?|shows?|marks?|counts?|lists?)\b[^.;:]{0,40}\bleft.out\b[^.;:]{0,30}\bas (passed|checked|a pass)\b|\bleft.out\b[^.;:]{0,40}\b(counts?|reads?|shows?|is reported|are reported|is listed) as (passed|checked)\b" || true; }
check "/ship-it's success lines (\"passed all checks\", \"All checks passed!\") never claim a left-out item was checked: each says which item wasn't, as left out by the user" \
  '[ -n "$(t4_succ)" ] && [ -z "$(t4_succmiss)" ] && [ -z "$(t4_passclaim)" ]'

# adv1 #4: the never-put-back bar on /ship-it's own auto-fixes holds on every /ship-it run, a dev-only ship included
T4_EVERYSHIP='\b(every|each|any)( /ship-it)? (ship|run|/ship-it|intent)\b|\bevery time\b|\bwhatever the intent\b|\bin any phase\b'
T4_PRODONLY='\b(for|on|at|in) the production ask\b|\bonly (for|on|at|in|when|with)\b[^.;:]{0,25}\b(production|prod-ready)\b|\b(on|for|at|in|with) (a |an |the )?`?(intent:)?prod-ready`?( ship| run)?\b'
# a scope that is not production is one token, so "not prod-ready" / "no production ask" is never read as a negation
t4_nonprod() { perl -pe 's/\bnot `?(intent:)?prod-ready`?|\b(no|without (a|the)) production ask\b/NONPROD/gi'; }
T4_AUTOW='\bauto-?fix|\bremediat|\bpackages?\b|\bupgrad|\bNeMo\b|\bAI.safety\b|\bpre-push\b|\bCI monitoring\b'
T4_USUAL='\b(as usual|as normal|as always|as before|normally|regardless|anyway|unchanged|freely)\b'
T4_DEVONLY='NONPROD|shareable|experiment|dev-only|\bdev\b'
# the units whose sentence bars /ship-it's own auto-fixes from putting a left-out item back
t4_barunit() { t4_units | grep -iE "$LO" | while IFS= read -r u; do printf "%s\n" "$u" | t4sent | grep -iE "$T4_AUTOFIX" | gq -iE "$T4_NEGW[^.;:]{0,80}\b(put|add|bring)[a-z]*\b[^.;:]{0,30}\bback\b" && printf "%s\n" "$u"; done; true; }
# any guide sentence where an auto-fix runs as usual on a ship that is not prod-ready, or reaches a left-out item anyway
t4_devfree() { t4_units | t4sent | t4_nonprod | t4_aff | grep -iE "$T4_AUTOW" | grep -iE "($T4_DEVONLY)[^.;:]*$T4_USUAL|$T4_USUAL[^.;:]*($T4_DEVONLY)|\b(even|also|still|too)\b[^.;:]{0,20}\b(for|on|to|when|if)\b[^.;:]{0,40}($LO)|($LO)[^.;:]{0,60}$T4_PUTBACK|$T4_PUTBACK[^.;:]{0,60}($LO)" || true; }
check "the never-put-back bar on /ship-it's own auto-fixes holds on every /ship-it run, not only for the production ask (a dev-only ship's package fixes too)" \
  'u=$(t4_barunit); [ -n "$u" ] && ! printf "%s\n" "$u" | t4_nonprod | t4_aff | gq -viE "$T4_EVERYSHIP" && ! printf "%s\n" "$u" | t4_nonprod | t4_aff | gq -iE "$T4_PRODONLY" && [ -z "$(t4_devfree)" ]'

# ---- Task 4 adversarial round 2 ----
# adv2 #1: a found secret is never sent, whatever is left out. On every ship the pre-push secret STOP holds for a left-out
# item: it names the item and the file:line (never the value), gives the "Add [item] first" next step (owner call 1, below),
# and never "Ship with [item] left out". A check that ran and found something is never reported as "not checked".
# tokens: a file:line and .env are one word each (their ":" and "." are no stops), and "wasn't checked" / "not checked" is
# one word, so a sentence that reports a check as not checked reads as saying so, never as a negation
# sentences: a stop inside a closing quote ('again." When') ends one too
t5_sent() { perl -pe 's/([.!?]["\x27]?) (?=\S)/$1\n/g'; }
t5_tok() { perl -pe 's/`?\bfile:line\b`?/FILELINE/gi; s/`?\.env\b`?/DOTENV/g; s/\b(wasn.t|was not|weren.t|were not|isn.t|is not|not)( been| be)? checked\b|\bunchecked\b/NOTCHECKED/gi'; }
T5_SECRET='\bsecrets?\b'
# the units about a secret a left-out item covers, each with the list items right after it; their sentences; the main units'
# sentences; and every guide sentence that names a secret and a left-out item
t5_secu() { t4_units | awk -v lo="$LO" '{l=tolower($0)} l ~ /secret/ && l ~ lo {on=1; print; next} on && /^ *(- |\* |[0-9]+\. )/ {print; next} {on=0}'; }
t5_secs() { t5_secu | t5_sent | t5_tok || true; }
# final fix review Important 2: the pre-push table is one unit; it is split into its rows (never dropped), so row 5's own
# sentences -- "There, /ship-it shows the user its value." included -- are read. Re-review Important 2: a row that names a
# secret or a left-out word is read (either, not both), so only one that names neither (row 2's kind) is not.
# E02-S21 (the owner's Split): the table is gone; its row 5 is now the "### Pre-push secret leak scan" section, read whole
t5_scan() { awk '/^#/{on=(index($0,"### Pre-push secret leak scan")==1)} on' $SHIP | paras; }
t5_secm() { { t5_secu | perl -pe 's/ (?=\| *[0-9]+ *\| \*\*)/\n/g'; t5_scan; } | grep -iE "$T5_SECRET|$LO" | t5_sent | t5_tok || true; }
t5_sls() { t4_units | t5_sent | t5_tok | grep -iE "$T5_SECRET" | grep -iE "$LO" || true; }
T5_STOP='\bstop(s|ped|ping)?\b[^.;:]{0,20}\b(before|ahead of)?( the| any| a)? push\b|\bSTOP\b[^.;:]{0,30}\bholds?\b'
T5_NOSEND="$T4_NEGW[^.;:]{0,25}\b(sent|sends?|push(es|ed)?|committed|commits?|uploaded|uploads?)\b"
T5_SENDX='\b(push(es|ed)?|commits?|committed|sends?|sent|uploads?|uploaded)\b (it|them|the secret|that secret|the key|the value|the file|anyway)\b|\b(push(es|ed)?|commits?|committed|sends?|sent|ships?|shipped)\b[^.;:]{0,30}\bas (it|they) (is|are)\b|\b(pushes|pushed|ships|shipped|sends|sent|goes|go) (on|ahead|anyway)\b|\bpush (ahead|anyway)\b'
# of the sentences on stdin, the ones that stop the push (affirmed) or never send the secret
t5_isstop() { while IFS= read -r l; do { printf "%s\n" "$l" | t4_aff | gq -iE "$T5_STOP" || printf "%s\n" "$l" | grep -qiE "$T5_NOSEND"; } && printf "%s\n" "$l"; done; true; }
t5_stops() { t5_sls | t5_isstop; }
# a table is one unit (the pre-push table): of a table, only its sentences that name the secret (or the label) count
t5_secp() { t5_secu | grep -v "^|" | t5_sent | t5_tok || true; }
# any sentence of the guard's prose, or any secret-and-left-out sentence, that pushes, sends or ships the secret anyway
# ("nothing ..." counts as negated); review7 Minor 2: the guard's prose too, so "If the user says so, /ship-it sends it" is read
t5_sendx() { { t5_secp; t5_sls; } | t4_aff | perl -pe 's/\bnothing\b[^,.;:]*//gi' | grep -iE "$T5_SENDX" || true; }
check "a found secret is never sent, whatever is left out: on a secret a left-out item covers, the secret leak scan stops before the push (never pushes it as it is)" \
  's=$(t5_stops); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && [ -z "$(t5_sendx)" ]'
T5_ALLSHIP="$T4_EVERYSHIP"
T5_ONLYPROD='\bonly\b[^.;:]{0,30}\b(prod-ready|production)\b|\b(prod-ready|production)( ships?| runs?)? only\b|\b(for|on|at|in) the production ask\b'
T5_NOTDEV="$T4_NEGW[^.;:]{0,30}\b(on|for|in|at|with) (a |an |the )?\`?(intent:)?(shareable|experiment|dev-only|dev)\b"
# the secret-and-left-out units that carry a STOP sentence and say it holds on every ship
t5_everyu() { t5_secu | grep -iE "$T5_SECRET" | grep -iE "$LO" | while IFS= read -r u; do s=$(printf "%s\n" "$u" | t5_sent | t5_tok); t=$(printf "%s\n" "$s" | grep -iE "$T5_SECRET" | grep -iE "$LO" | t5_isstop); [ -n "$t" ] && printf "%s\n" "$s" | t4_aff | gq -iE "$T5_ALLSHIP" && printf "%s\n" "$u"; done; true; }
t5_prodonly() { t5_sls | t4_aff | grep -iE "$T5_ONLYPROD" || true; t5_sls | grep -iE "$T5_NOTDEV" || true; }
check "the secret STOP for a left-out item holds on every ship, shareable and prod-ready alike (never only for production)" \
  '[ -n "$(t5_everyu)" ] && [ -z "$(t5_prodonly)" ]'
T5_NAMEIT='\bnam(e|es|ing)\b[^.;:]{0,15}\b(the|that|each|its)( left.out)? item\b|\bwhich( left.out)? item\b|\bby (its )?name\b|\bnam(e|es|ing) (it|(\*\*)?\[[^]]*\])'
T5_NOVAL="$T4_NEGW[^.;:]{0,20}\b(its|the|their)?( secret.s| key.s)? ?values?\b"
T5_VALX='\b(names?|shows?|quotes?|prints?|gives?|says?|includes?|repeats?|echo(es)?|pastes?|reads? out)\b[^.;:]{0,40}\b(its|the|their)( secret.s| key.s)? values?\b|\b(shows?|quotes?|prints?|repeats?|echo(es)?|pastes?|reads? out) (the |its |that )?(secret|key|token|password)s?\b'
t5_named() { t5_secs | t4_aff | grep -iE "$T5_NAMEIT" | grep -F FILELINE || true; }
t5_noval() { t5_secs | grep -iE "$T5_NOVAL" || true; }
t5_valx() { { t5_secm; t5_sls; } | t4_aff | grep -iE "$T5_VALX" || true; }
check "the secret STOP for a left-out item names the item and the file:line where the secret is, never its value" \
  '[ -n "$(t5_named)" ] && [ -n "$(t5_noval)" ] && [ -z "$(t5_valx)" ]'
T5_NOSHIP="$T4_NEGW[^.;:]{0,30}\b(offers?|offered|gives?|given|shows?|an option)\b[^.;:]{0,30}\bShip with\b|\bShip with\b[^.;:]{0,40}\b(is|are)( never| not|n.t)( be)? (offered|given|shown|an option)\b"
T5_SHIPX='\b(offers?|offered|gives?|shows?|asks?)\b[^.;:]{0,60}\bShip with\b|\bor (\*\*)?"?Ship with\b'
t5_noship() { t5_secs | grep -iE "$T5_SECRET" | grep -iE "$T5_NOSHIP" || true; }
t5_shipx() { { t5_secm; t5_sls; } | t4_aff | grep -iE "$T5_SHIPX" || true; }
check "once a secret is found, the STOP never offers \"Ship with [item] left out\"" \
  '[ -n "$(t5_noship)" ] && [ -z "$(t5_shipx)" ]'
# owner call 1 (after adv3 #1): the STOP is the whole answer. It gives the production ask's "Add [item] first" next step
# (/resume-it, then /ship-it again); /ship-it never moves the secret itself (a .env git still tracks got sent) and offers
# no choice. "Add [item] first" means that one thing everywhere in the guide.
# a quoted example item name ("Move the passwords and keys out of your code") is one token, so its words are no action;
# what /resume-it does is its own: from "/resume-it" up to where the actor changes back -- the next "/ship-it", "I",
# "itself", "meanwhile", or "and / then / but / while" + a move -- a sentence's words are no /ship-it action.
# review7 Minor 1: a sentence (or an example quote) that names .env is read whole, whoever acts: old check 4 read every
# move to .env, and the owner made /ship-it's "never moves it" stronger, not narrower
t5_eg() { perl -pe 's/\b(for example|e\.g\.,?|such as) "(?:(?!DOTENV)[^"])*"/EXITEM/gi'; }
t5_rsm() { perl -pe 'next if /DOTENV/; s{/resume-it\b(?:(?!/ship-it|\bI\b|\bitself\b|\bmeanwhile\b|\bafter(?:wards?| that)\b|\b(?:and|then|but|while|so)\b,?\s+(?:(?:it|then|also|\w+ly|for \w+,)\s+)*(?:mov|put|writ|cop|stor|shift|transfer|relocat|stash|remov|delet|strip|replac|rewrit|edit|tak)[a-z]*\b).)*}{RESUMEIT}g'; }
T5_RESUME='/resume-it\b[^.]{0,60}\badd (\*\*)?\[[^]]+\]'
T5_AGAIN='/ship-it\b[^.;:]{0,20}\bagain\b'
check "the secret STOP for a left-out item gives the ask's \"Add [item] first\" next step: run /resume-it and say \"add [item]\", then type /ship-it again" \
  '[ -n "$(t5_secs | t4_aff | grep -iE "$T5_RESUME")" ] && [ -n "$(t5_secs | t4_aff | grep -iE "$T5_AGAIN")" ]'
T5_MOVEX='\b(mov|put|writ|wrote|cop(y|ies|ied)|stor|shift|transfer|relocat|stash|remov|delet|strip|replac|rewrit|edit)[a-z]*\b[^.;:]{0,40}(\b(it|them|secrets?|keys?|values?|passwords?|tokens?)\b|DOTENV)|\btak(e|es|en|ing)\b[^.;:]{0,20}\b(secrets?|keys?)\b[^.;:]{0,20}\bout\b|\b(secrets?|keys?|it|they)\b[^.;:]{0,20}\b(is|are|gets?|was|were|be)( then| first| now)? (moved|put|written|copied|stored|shifted|transferred|relocated|stashed|removed|deleted|stripped|replaced|rewritten|edited|taken out)\b|\b(to|into) (a |the |your )?(private )?(DOTENV|settings file|environment variables?|env vars?|vault)\b'
t5_movx() { { t5_secp; t5_sls; } | t5_eg | t4_aff | t5_rsm | grep -iE "$T5_MOVEX" || true; }
check "/ship-it never moves the secret itself: no sentence about a secret a left-out item covers moves, writes or puts it anywhere (.env or otherwise)" \
  '[ -z "$(t5_movx)" ]'
# a choice: "or stop", "Ship with", an offered label, choice words; or a list of options right after the secret unit
# review7 Minor 2: the stop is no ask and can't be overridden -- "lets the user choose", "the user can override the stop",
# "If the user says so, ...", "pauses ... and asks", "until the user confirms", "an earlier pick still ships it"
T5_CHOICE="\bor (to |just )?(\*\*)?\"?stop\b|\bstop(\*\*)?\"? or\b|$T5_SHIPX|\b(offers?|offered)\b[^.;:|]{0,30}(\*\*[^*]+\*\*|$T4_ADDOPT)|\b(offers?|gives?|asks?|lets?|shows?)\b[^.;:]{0,30}\b(a choice|the choice|choices|options?|picks?|to (pick|choose))\b|\b(asks?|lets?)\b[^.;:]{0,30}\bwhich\b|\bwhether to\b|\b(lets?|letting|asks?)\b[^.;:]{0,30}\b(choose|decide|pick|select)\b|\b(the user|you|they)\b[^.;:]{0,20}\b(overrid|overrul|bypass)[a-z]*\b|\b(stop|guard)\b[^.;:]{0,20}\b(overridden|overruled|bypassed|lifted)\b|\b(if|when|once|until|unless|as soon as) (the user|you|they)\b[^.;:]{0,25}\b(says? so|insists?|wants?|agrees?|confirms?|okays?|approves?|allows?|accepts?|says? (yes|go|ok|okay))\b|\b(pauses?|waits?)\b[^.;:]{0,30}\b(asks?|for (the user|you|your|their|an? (answer|reply|yes|ok|okay|go-ahead|confirmation)))\b|\b(earlier|previous|prior)\b[^.;:]{0,30}\bpick\b[^.;:]{0,30}\b(still|ships?|sends?|holds?|stands?|wins?)\b"
# an ask of the user, read on what /ship-it does (/resume-it's own "it checks with you before it adds it" is allowed)
T5_UCHOICE='\b(the user|you|they)\b[^.;:]{0,20}\b(decides?|can (still |also )?(choose|decide|ship|send|push))\b'
T5_ASKU='\basks? (the user|you)\b|\bchecks? with (the user|you)\b|\basks?\b[^.;:]{0,20}\bfor (an? |the user.s |your |their )?(answer|reply|yes|ok|okay|go-ahead|confirmation|approval|permission)\b'
t5_secl() { t4_units | awk -v lo="$LO" '{l=tolower($0)} l ~ /secret/ && l ~ lo {on=1; next} on && /^ *(- |\* |[0-9]+\. )/ {print; next} {on=0}'; }
t5_choice() { { t5_secp; t5_sls; } | t4_aff | grep -iE "$T5_CHOICE" || true; { t5_secp; t5_sls; } | t4_aff | t5_rsm | grep -iE "$T5_ASKU|$T5_UCHOICE" || true; t5_secl | grep -E "^ *(- |\* |[0-9]+\. )(\*\*|\"|'|(Stop|Add|Ship|Move|Cancel|Skip)\b)" || true; }
check "the secret STOP for a left-out item offers no choice: no pick list, no \"or stop\", no \"Ship with\"" \
  '[ -z "$(t5_choice)" ]'
# a second meaning: /ship-it (or "I", now, here) does the adding, or the label is glossed with an action
T5_ADDSHIP="/ship-it\b[^.;:]{0,30}\b(adds?|will add|builds?|applies|moves?|puts?|writes?|fixes)\b|\bI( will| can|.ll)? (add|move|put|write|fix|apply|build)\b|\b(added|built|applied|moved|fixed|put|written) (here|now|right now|in this session|by /ship-it|during this ship|on this ship)\b|\badd(s|ed|ing)? (it|them|the item|that item)\b[^.;:]{0,15}\b(now|right now|right away|here)\b|$T4_ADDOPT(\*\*)? *(\(|--|:) *\"?(move|put|write|fix|build|apply|replace|remove|take)\b|$T5_MOVEX"
t5_addm() { { t4_units | grep -v "^|" | grep -iE "$T4_ADDOPT" | t5_sent; t4_units | grep "^|" | t5_sent | grep -iE "$T4_ADDOPT"; } | t5_tok | t5_eg | t4_aff | t5_rsm | grep -iE "$T5_ADDSHIP" || true; }
check "\"Add [item] first\" means one thing everywhere in the guide: /resume-it adds the item, never /ship-it" \
  '[ -z "$(t5_addm)" ]'
# review7 Minor 3: the pre-push secret leak scan (the table's row 101; since E02-S21 its own section) points at the guard.
# One of its sentences says a secret that belongs to a left-out item is never moved there, and it points at "Left-out items
# before production"
# (a "(see ...)" pointer is no part of the negated clause before it); no sentence of the row keeps its move for a left-out
# item's secret (or for every secret, left out or not)
t5_r101() { t5_scan | t5_sent | t5_tok || true; }
# final fix review Minor 9: "whichever item it belongs to" / "no matter which" widen the move too ("no matter" is one token,
# NOMATTER, so t4_aff never reads its "no" as a negation)
T5_R101X='\b(every|each|any|all)( the)? (secrets?|keys?)\b|\bwhatever\b|\bwhichever\b|NOMATTER|\bor not\b|\bregardless\b|\beven\b|\ball the same\b|\banyway\b|\btoo\b|\bas well\b|\balso\b'
check "the pre-push secret leak scan section (once row 101) says a secret that belongs to a left-out item is never moved there, and points at \"Left-out items before production\"" \
  's=$(t5_r101 | grep -iE "$T5_SECRET" | grep -iE "$LO" | grep -iE "$T4_NEGW[^.;:]{0,20}\bmov(e|es|ed)\b"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && t5_r101 | perl -pe "s/\((?=(see|follow|read)\b)/: /gi" | t4_aff | gq -iE "\b(see|follow|read|go to|per|under|in)\b[^.;:]{0,10}($T4_SECPTR)" && [ -z "$(t5_r101 | t5_eg | perl -pe "s/\bno matter\b/NOMATTER/gi" | t4_aff | t5_rsm | grep -iE "$T5_MOVEX" | grep -iE "$LO|$T5_R101X")" ]'
T5_FOUND='\b(found|finds|caught|catches|flagged|flags|turned up)\b'
T5_NOTCHK="$T4_NEGW[^.;:]{0,40}\b(reported|reports?|reads?|called|calls?|said|says?|shown|shows?|told|tells?|listed|lists?|marked|marks?)\b[^.;:]{0,25}NOTCHECKED"
T5_EVENX="\beven (when|if|though)\b[^.;:]{0,60}$T5_FOUND"
t5_foundok() { t4_units | t5_sent | t5_tok | grep -iE "$T5_FOUND" | grep -iE "$T5_NOTCHK" || true; }
# the units that say a left-out check "wasn't checked": none says it even when a check found something
t5_evenx() { t4_units | t5_tok | grep -F NOTCHECKED | t5_sent | t4_aff | grep -iE "$T5_EVENX" || true; }
# a secret-and-left-out sentence that reports the scan as not checked, or as left out
t5_unchkx() { t5_sls | t4_aff | grep -iE "NOTCHECKED|\b(check|scan)\b[^.;:]{0,15}\b(was|were|is|as) left out\b" || true; }
check "a check that ran and found something is never reported as \"not checked\" (never \"wasn't checked: you left it out\" for it)" \
  's=$(t5_foundok); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && [ -z "$(t5_evenx)" ] && [ -z "$(t5_unchkx)" ]'

# adv2 #2: when the DevOps team fixes (adds) an item the user chose to ship with, the notice the user gets names that item and
# asks them to keep it or take it out again; their answer updates the record (only the user's own answer brings it back)
T5_DFIX='\bDevOps( team)?\b[^.;:]{0,30}\b(fix(es|ed)?|adds?|added|builds?|built)\b'
# the units about a left-out item that carry a DevOps fix, and their DevOps-fix sentences
t5_dfu() { t4_units | grep -iE "$LO|$T4_CHOSE" | while IFS= read -r u; do printf "%s\n" "$u" | t5_sent | gq -iE "$T5_DFIX" && printf "%s\n" "$u"; done; true; }
t5_dfs() { t5_dfu | t5_sent | grep -iE "$T5_DFIX" || true; }
# "instead of the usual notice" names what it replaces: dropped before reading what a sentence affirms
t5_inst() { perl -pe 's/\b(instead of|in place of|rather than)\b[^,.;:]*//gi'; }
T5_DFNAME='\bwhich (item|one)\b|\bby (its |the item.s )?name\b|\bnam(es|ing) (the|that|each) item\b'
T5_PLAIN='\bWe made (a few|some) updates\b|\b(usual|plain|generic|standard|same|general)\b[^.;:]{0,20}\b(notice|notification|message|comment|note)\b'
t5_dfname() { t5_dfs | grep -iE "$LO|$T4_CHOSE" | t4_aff | grep -iE "\b(tells?|told|notif(y|ies|ied)|comment|notice|message)\b" | grep -iE "$T5_DFNAME" || true; }
t5_dfplain() { t5_dfs | t5_inst | t4_aff | grep -iE "$T5_PLAIN|$T4_UNTOLD" || true; }
check "when the DevOps team fixes (adds) an item the user chose to ship with, the notice the user gets names that item (never only the usual \"We made a few updates\")" \
  '[ -n "$(t5_dfname)" ] && [ -z "$(t5_dfplain)" ]'
T5_OBJ='(it|them|that item|the item|(\*\*)?\[[^]]*\](\*\*)?)'
T5_KEEPOUT="\bkeep $T5_OBJ[^.;:]{0,30}\bor\b[^.;:]{0,10}\btake $T5_OBJ (back )?out\b"
t5_keepout() { t5_dfu | t5_sent | t4_aff | grep -iE "$T5_KEEPOUT" | grep -iE "\bask|\?" || true; }
t5_noask() { t5_dfs | t4_aff | grep -iE "\bwithout (asking|a question)\b" || true; }
check "when the DevOps team fixes an item the user chose to ship with, the notice asks the user to keep it or take it out again" \
  '[ -n "$(t5_keepout)" ] && [ -z "$(t5_noask)" ]'
T5_ANSREC='\b(their|the user.s|your|that|this|the) (own )?(answer|pick|reply|choice)\b[^.;:]{0,40}\b(updates?|rewrites?|changes?|is written|goes)\b[^.;:]{0,40}\b(record|make-it-state|Left out by your choice)\b'
T5_RECX='\btreat(s|ed)? (it|the item|that item|them) as (added|brought back|back|in)\b|\b(DevOps|automation|CI|bot|the team)\b[^.;:]{0,30}\b(updates?|rewrites?|edits?|changes?|clears?|deletes?|removes?)\b[^.;:]{0,30}\b(record|make-it-state|its line|the line)\b|\b(record|line)\b[^.;:]{0,30}\b(on its own|automatically|by itself)\b'
t5_ansrec() { t5_dfu | t5_sent | t4_aff | grep -iE "$T5_ANSREC" || true; }
t5_recx() { t4_units | grep -iE "$LO|$T4_CHOSE" | t5_sent | t4_aff | grep -iE "$T5_RECX" || true; }
check "when the DevOps team fixes an item the user chose to ship with, the user's answer updates the left-out record (never DevOps's fix, never on its own)" \
  '[ -n "$(t5_ansrec)" ] && [ -z "$(t5_recx)" ]'


# ---- final review: Task 4 test strength (X2) ----
# r5 M5: the go-live checklist rewrite is never narrowed (a new PR, once DevOps approves, the next release, if the user asks), and
# no /ship-it save drops its lines
T4_GLNARROW='\b(new|first) PR\b|\b(once|after|only after|at the next)\b[^.;:]{0,20}\b(DevOps|approv|release)|\bif (the user|they) asks?\b'
t4_glx() { t4_gl | t4_aff | grep -iE "$T4_GLNARROW" || true; t4_units | t4sent | t4_aff | grep -iE '/ship-it save[^.;:]{0,20}\b(drops?|removes?|clears?)\b' || true; }
check "the go-live checklist rewrite is never narrowed (a new PR, once DevOps approves, the next release, if the user asks), and no /ship-it save drops its lines" \
  '[ -n "$(t4_gl)" ] && [ -z "$(t4_glx)" ]'
# r5 M5: CI/CD contract -- the go-live checklist is the only source for the picks: no "or from its own scan" after it, never only
# when someone turns it on
t4_cicdfb() { t4_cicd | t4_aff | grep -iF "go-live checklist" | perl -ne 'print if /go-live checklist(.*)/i && $1 =~ /\b(or|and)\b[^.;:]{0,20}\b(from|works?|infers?)\b|\b(when|if|once)\b[^.;:]{0,25}\b(turns? (it|that|this) on|enabled|configured|set up)\b/i' || true; }
check "CI/CD contract: the PR's go-live checklist is the automation's only source for the picks (no fallback after it, never only when turned on)" \
  '[ -n "$(t4_cicd | grep -iF "go-live checklist")" ] && [ -z "$(t4_cicdfb)" ]'
# r5 M5: the put-back bar is never narrowed to a left-out [BLOCK] item
check "the never-put-back bar on /ship-it's own auto-fixes covers every left-out item, never only a left-out [BLOCK] item" \
  'u=$(t4_barunit); [ -n "$u" ] && ! printf "%s\n" "$u" | t4sent | grep -iE "$T4_AUTOFIX" | gq -iE "left-out \`?\[BLOCK\]\`? item"'
# r4 M1: a left-out [BLOCK] item is never narrowed to a tier, or to one marked "(taken out)", in the section or the Intent line
T4_NARROWB='\[BLOCK\]`? items?\b[^.;:,]{0,30}\b(in|from|of|at) Tier\b|\bTier.?[0-9]`? `?\[BLOCK\]|\[BLOCK\]`? items?\b[^.;:,]{0,30}\btaken out\b'
t4_intp() { awk '/^#/{on=($0=="### Intent Classification")} on' $SHIP | paras | grep -iE "left-out ask|$T4_SECPTR" || true; }
check "a left-out [BLOCK] item is never narrowed (to a tier, or to one marked taken out) in the left-out section or the Intent line" \
  '[ -n "$(t4_intp)" ] && ! { t4s; t4_intp; } | t4_aff | gq -iE "$T4_NARROWB"'
# r4 M3: the DevOps hold notice always goes out, in a PR comment: never only if configured or turned on, never to a DevOps
# channel or review notes; the section's sentence says "PR comment", and the list it is in is the PR-comment list
T4_HOLDOPT='\b(if|where|when|once|unless)\b[^,.;:]{0,30}\b(configured|enabled|set up|opt(s|ed)? in)\b|\bturns? (it|that|this) on\b|\bchannels?\b|\breview notes\b'
t4_lsec() { awk '/^#/{on=($0=="### Left-out items before production")} on' $SHIP | paras | t4sent; }
check "a DevOps hold notice always goes out, in a PR comment (never only if configured or turned on, never to a DevOps channel or review notes)" \
  '[ -n "$(t4_holds)" ] && ! t4_holds | t4_aff | gq -iE "$T4_HOLDOPT" && [ -n "$(t4_lsec | t4_aff | grep -iE "$T4_HOLD")" ] && ! t4_lsec | t4_aff | grep -iE "$T4_HOLD" | gq -viE "\bPR comment\b" && grep -qF "**Automation -> User notifications** (via GitHub PR comments" $SHIP'
# r4 M4: every Intent Classification paragraph that names the left-out ask puts the [BLOCK] condition before "ask comes next", and
# none makes it unconditional ("always", "regardless", "or not", "whether or not", "even if"; read before t4_aff, which drops "not")
t4_intx() { t4_intp | grep -iE "\balways\b|\bregardless\b|\bor not\b|\beven (if|when)\b" || true
  t4_intp | grep -iE "left-out ask" | perl -ne 'print unless /\b(if|when|whenever|only if|only when)\b[^,.;:]{0,40}\bleft.out `?\[BLOCK\]`? items?\b.{0,120}?\bask comes next\b/i'; }
check "Intent Classification: every paragraph that names the left-out ask puts the [BLOCK] condition before \"ask comes next\", never always / regardless / or not" \
  '[ -n "$(t4_intp | grep -iE "left-out ask")" ] && [ -z "$(t4_intx)" ]'
# r6 M5: the DevOps-fix notice is negated at no site (each of the two sites is read on its own)
T5_DFNEG="$T4_NEGW[^.;:]{0,30}\\b(tells?|told|asks?|asked|names?|named|says?)\\b"
check "the DevOps-fix notice is negated at no site (never \"never tells\", \"never asks\", \"never names\")" \
  '[ -n "$(t5_dfs)" ] && ! t5_dfs | gq -iE "$T5_DFNEG"'

# ---- final review: the text fixes, definition / resume-it / try-it / ship-it-guide (I1, D1-D9, R1-R5, Y1-Y4, S1-S6) ----
# I1 + D1: rule 1 names all three asks that may name a left-out item; never "the one exception"
fr_rule1() { rb "Mentioned" | perl -ne 'print "$1\n" if /never goes in an ask \(([^)]*)\)/i'; }
check "rule 1: \"never goes in an ask\" names its exceptions -- the ship ask, /retrofit-it's fresh-build stop, read step 4's confirming question -- never \"the one exception\"" \
  'p=$(fr_rule1); printf "%s\n" "$p" | gq -iE "\bship ask\b" && printf "%s\n" "$p" | gq -iE "/retrofit-it.s fresh-build stop" && printf "%s\n" "$p" | gq -iE "\bstep 4.s (one )?confirming question\b" && ! rb "Mentioned" | gq -iE "\b(the one|the only|only one) exception\b"'
# I1: rule 3's "never blocks a step" names its carve-out, a found secret, and points at the guide
check "rule 3: \"never blocks a step\" except a found secret -- /ship-it stops and sends nothing (ship-it-guide.md, Left-out items before production)" \
  'b=$(rb "Never put back"); printf "%s\n" "$b" | gq -iE "never blocks a step[^.]{0,10}\bexcept a found secret\b" && printf "%s\n" "$b" | gq -F "(\`ship-it-guide.md\`, Left-out items before production)" && ! printf "%s\n" "$b" | gq -iE "\beven a found secret\b|\bsecret[^.]{0,30}\b(is|gets) (sent|shipped|pushed)\b"'
# D2: step 4's confirming question is asked (not "may"), unless-free: not needed only when the user named the item
check "read step 4: the skill asks one plain question to confirm it is that item (never \"may ask\"), not needed when the user named the item" \
  'q=$(printf "%s\n" "$S4" | grep -iF "plain question"); printf "%s\n" "$q" | gq -iE "\basks one plain question to confirm it is that item\b" && printf "%s\n" "$q" | gq -iE "\bnamed the item\b" && ! printf "%s\n" "$q" | gq -iE "\b(may|can|could|might|optionally)\b[^.;]{0,10}\bask"'
# D4: a take-out takes the item out first; a part that stays is never recorded; an item added by hand leaves the record
check "Where: a \"take it out\" takes the item out and writes its line; if part of it stays, the line names only what was taken out" \
  's=$(sec $DEF "## The left-out record" | sentences | grep -iE "take it out"); printf "%s\n" "$s" | gq -iE "\btakes it out and writes its line\b" && printf "%s\n" "$s" | gq -iE "\bif part of it stays in the app, the line names only what it took out\b" && ! printf "%s\n" "$s" | gq -iE "\bwrites its line (first|before)\b"'
check "read step 4: a user's word that they added an item themselves brings it back the same way (its lines are deleted)" \
  'printf "%s\n" "$S4" | grep -iE "added (an|the) item themselves" | gq -iE "\bbrings it back the same way\b"'
# D5: a TODO.md heading's items are its top-level lines, up to a heading of the same or higher level; step 4 deletes a grouped line
check "read step 2: a TODO.md heading's items are its top-level \`- \` lines (indented lines are part of them), up to a heading of the same or higher level; read step 4 deletes a grouped item's line under that heading" \
  's=$(step $DEF 2 | flat); printf "%s\n" "$s" | gq -iE "one item per top-level .- . line \(its indented lines are part of it\), up to the next heading of the same or higher level" && step $DEF 4 | flat | gq -iE "line in TODO\.md \(in a grouped list, its line under that heading\)" && ! printf "%s\n" "$s" | gq -iE "\bindented lines? (are|is|count as) (an? )?(items?|their own)"'
# D6: a bring-back goes through the item's own tier, never "the same tier" as the batch
check "read step 4: a bring-back goes through the same ask (its catch and its undo), at the tier approval-block.md gives that item on its own -- never \"at the same tier\"" \
  'printf "%s\n" "$S4" | grep -iE "catch-up" | gq -iE "same ask[^.]*\(its catch and its undo\), at the tier .approval-block\.md. gives that item on its own" && ! printf "%s\n" "$S4" | gq -iE "\bat the same tier\b"'
# D9: read step 2's older form reads plainly, and its lines keep the file's width
check "read step 2: \"With no such section ..., only the shapes older skills wrote count\" (no \"state file ... counts\", no \"two shapes\"), \"A status line, such as ..., never counts\", lines at most 100 wide" \
  's=$(step $DEF 2 | flat); printf "%s\n" "$s" | gq -F "With no such section (a file written before it existed), only the shapes older skills wrote count:" && printf "%s\n" "$s" | gq -iE "A status line, such as try-it.s .- Result: [^\`]*. under .## Try-It Status., never counts\." && ! printf "%s\n" "$s" | gq -iE "\btwo shapes\b|\bstate file with no such section[^.]*\bcounts\b" && [ -z "$(step $DEF 2 | awk "length > 100")" ]'

# R1: the ask's promise holds at ship too: only a mention next time, named before it goes live
check "resume-it ask: next time only a mention, not an ask -- and before it goes live the item is named so the user can decide" \
  'p=$(printf "%s\n" "$GAPS_TXT" | flat); printf "%s\n" "$p" | gq -iE "next time I.ll only mention it, not ask; before it goes live, I.ll name it so you can decide" && printf "%s\n" "$p" | t4_aff | gq -iE "before it goes live, I.ll name it so you can decide"'
# R2 + R5: the skill-wide pointer covers the test phase's report, and the record is read before step 6b
check "resume-it's skill-wide pointer: the test phase's pass/fail report reads a left-out item's tests as left-out-record.md says" \
  'ptr | t4_aff | gq -iE "test phase.s pass/fail report reads a left-out item.s tests as .?left-out-record\.md.? says"'
check "resume-it's skill-wide pointer: the record is read before step 6b (its dependency auto-fix runs before step 8 reads it)" \
  'p=$(ptr); printf "%s\n" "$p" | t4_aff | gq -iE "\bread the record\b[^.]{0,40}\bbefore step 6b\b" && ! printf "%s\n" "$p" | gq -iE "\bafter step 6b\b"'
# R3: a put-off item is not recorded; on "not now", each left-out item is named as step 6 does
check "resume-it catch-up: an item the user only puts off (\"later\", \"for now\") is not recorded; on \"not now\", each left-out item is named as step 6 does" \
  'w=$(printf "%s\n" "$CU_OUT" | flat | sentences); printf "%s\n" "$w" | grep -iE "tells you to leave out" | gq -iE "an item they only put off -- .later., .for now. -- is put off, not recorded" && printf "%s\n" "$w" | grep -iF "not now" | gq -iE "with items left out, name each one as step 6 below does"'
# R4: the scanner's left-out line: one per item, once per session, no ask
SCL="$(printf "%s\n" "$SCANNER" | flat | grep -oE 'Tell the user once per session[^"]*"[^"]*"' || true)"
check "resume-it scanner: a left-out item's findings get one plain line per item, once per session, that is no ask (no \"?\", no \"want me to\")" \
  'printf "%s\n" "$SCL" | gq -iE "once per session, one plain line per item, with no scan detail" && printf "%s\n" "$SCL" | gq -iE "\[N\] safety warning\(s\)[^\"]*about \[item\], which you left out, so I didn.t change it" && ! printf "%s\n" "$SCL" | gq -iE "\?|want me to|should I|shall I"'

# Y1: try-it reads TODO.md only with no section
check "try-it pointer: TODO.md is read only with no section (\"From .make-it-state.md (and, with no ... section, TODO.md too)\"), never as an equal source" \
  'printf "%s\n" "$PTR" | gq -E "^From \.make-it-state\.md \(and, with no .## Left out by your choice. section, TODO\.md too\), note every item" && ! printf "%s\n" "$PTR" | gq -E "^From \.make-it-state\.md and TODO\.md"'
# Y2: the SOME FAILURES header is never true of left-out failures alone
check "Phase 5: the SOME FAILURES header reads \"apart from a left-out item's tests\"" \
  'printf "%s\n" "$T3_HAND" | grep -E "^If SOME FAILURES" | gq -E "^If SOME FAILURES, apart from a left-out item.s tests \("'
# Y3: a fix whose re-test a left-out item blocks is never "Fixed!"
check "explore phase: when a left-out item keeps a fix's re-test from running, the reply says what changed and that it couldn't be checked, never \"Done!\" or \"Fixed!\"" \
  's=$(printf "%s\n" "$T3_EXP" | psents | grep -iE "left.out item keeps a fix.s re-test from running"); [ -n "$s" ] && printf "%s\n" "$s" | gq -iE "say what you changed and that you couldn.t check it" && printf "%s\n" "$s" | gq -iE "${NEGQ}Done!" && printf "%s\n" "$s" | gq -iE "${NEGQ}Fixed!" && ! printf "%s\n" "$s" | gq -iE "$WAIVE|(keep|still|always)[^.;]{0,40}.?(Done|Fixed)|(don.t|do not|never) (drop|omit|leave|skip)"'
# Y4: three wordings that said less than they mean
check "try-it: the Status line's every-test-left-out case, \"I tested\" (checked and not left out), and gate 1's exception (a failure marked left_out)" \
  'printf "%s\n" "$AFTS" | gq -F "never 0 of 0 Passing: when every test is left out" && printf "%s\n" "$ALLLO" | gq -E "only what was checked and isn.t left out" && awk "/^<guardrails>/{on=1} on" $TRY | flat | gq -F "except a failure marked \`left_out\`, which follows"'

# S1: the secret stop's "not checked" rule is that check's. E02-S21 (the owner's Split): /ship-it's CI-time success line is gone
# with its CI watch; its success line is the done message, which claims no check passed (none of /ship-it's says so).
# PR #62 review Important 1: the found-something rule left with those lines, but it is a left-out rule (left-out-record.md's
# reader rule), and the CI/CD contract's success line still says "[item] wasn't checked": that line carries it, right after
# the quote (what a check that ran found instead; for a secret, where it is, never its value)
check "ship-it-guide: the secret stop's \"not checked\" rule is scoped to that check (never \"a check that ran and found something\"), /ship-it's success line is its done message, which claims no check passed, and the CI/CD contract's success line says what a left-out item's check that ran found instead (for a secret: where it is, never its value)" \
  't5_secs | grep -F NOTCHECKED | gq -iE "\band that check is never reported as .?NOTCHECKED" && ! grep -qiE "\ba check that ran and found something\b" $SHIP && t4_units | grep -E "^[0-9]+\. Reports back:" | gq -F "\"Done! Your code is on its way.\"" && ! awk "BEGIN{on=1} /^## /{on=(index(\$0,\"## CI/CD Automation Contract\")!=1)} on" $SHIP | gq -iE "passed all checks|all checks pass(ed)?\b" && t4_units | awk "/^## /{on=(index(\$0,\"## CI/CD Automation Contract\")==1)} on" | grep -F "All checks passed!" | tr -s " " | gq -E "\"\[item\] wasn.t checked: you left it out\.\" If one of that item.s checks ran and found something, it says what that check found instead; for a secret, where it is \(\`file:line\`\), never its value \(\`left-out-record\.md\`\)\."'
# S2: the stop says why, in plain words
check "the secret stop says why in plain words: what was found, and that a sent key can be used by anyone who sees the code and can't be taken back" \
  's=$(t5_secs); printf "%s\n" "$s" | t4_aff | gq -iE "\bsays why in plain words\b" && printf "%s\n" "$s" | gq -iE "anyone who can see your code can use it" && printf "%s\n" "$s" | gq -iE "can.t be taken back" && ! printf "%s\n" "$s" | gq -iE "$T4_NEGW[^.;:]{0,20}\bsays? why\b"'
# S3: the DevOps-fix notice gives the next step. final fix review Minor 4: what "keep" means is the owner's call, so the user
# says which they mean. Re-review Minor 1: the comment's own two answers -- keep the team's fix, or take it out again
# (/resume-it's "take it out") -- never "keep [item] left out", never a bare "keep [item]"
check "the DevOps-fix notice gives the next step: /resume-it and say which -- \"keep the team's fix for [item]\" or \"take [item] out again\" (never \"keep [item] left out\", never a bare \"keep [item]\") -- then /ship-it again" \
  't5_dfs | gq -iE "with the next step: .Run /resume-it and say which you mean: .keep the team.s fix for \[item\]. or .take \[item\] out again., then type /ship-it again" && ! t5_dfs | gq -iE "\bkeep \[item\]([^ ]|$)|\bkeep \[item\] left.out\b"'
# S4: the guard's scope: every push, whatever the intent, /ship-it save included; never narrowed (review 6 M4's rejects)
check "the secret guard's scope: every push, whatever the intent, /ship-it save included (never a live key only, never only the production push)" \
  't5_secs | t4_aff | gq -iE "\bon every push, whatever the intent, /ship-it save included\b" && ! t5_secs | t4_aff | gq -iE "\b(live|real|production|prod)\b[^.;:]{0,10}\b(secrets?|keys?)\b|\bnot (a|on) [^.;:]{0,25}\b(test|save|experiment)\b|\bproduction push\b"'
# S5: the go-live lines are rewritten before the push, and the PR step (step 10 before E02-S21's Split) points at the section
check "the go-live lines are rewritten before /ship-it pushes, and the PR step's go-live checklist points at Left-out items before production" \
  't4_gl | t4_aff | gq -iE "\bEach /ship-it, before it pushes, rewrites those lines\b" && t4_units | grep -E "^[0-9]+\. Creates a PR\b" | tr -s " " | gq -F "go-live checklist (its left-out lines: see Left-out items before production)"'
# S6: the Intent condition says how to tell, right after the item
check "Intent Classification: the [BLOCK] condition says how to tell (\"(\`left-out-record.md\` says how to tell)\" right after the item)" \
  't4_intp | gq -E "left-out .\[BLOCK\]. item \(.left-out-record\.md. says how to tell\), /ship-it.s left-out ask comes next"'

# ---- final fix review: the text minors (rule 1's list, S1 residual, S4 on save, S1 values, S3's two meanings) ----
# Minor 2: rule 1's exceptions also name the DevOps-fix PR comment and /retrofit-it's pick-again ask, as a plain list (no
# "which names each left-out item, and read step 4's" garden path)
check "rule 1: \"never goes in an ask\" also names the DevOps-fix PR comment and /retrofit-it's ask to pick again (a list, never \"..., and read step 4's\")" \
  'p=$(fr_rule1); printf "%s\n" "$p" | gq -iE "\bthe automation.s PR comment when the DevOps team fixes it\b" && printf "%s\n" "$p" | gq -iE "/retrofit-it.s ask to pick again when a left-out item is needed by one they kept\b" && ! printf "%s\n" "$p" | gq -iE "left-out item, and read step 4"'
# Minor 1 + 7: both left-out success lines (the monitoring flow's and its list's) say what a check that ran found, instead of
# "could not be checked", and for a secret, where it is, never its value
fr_succ2() { awk '/Report success: "Your app passed all checks/{on=1;next} on&&/\+--/{exit} on' $SHIP | sed -E "s/^ *\| *//" | flat; echo
  awk '/^- \(On success\)/{on=1;print;next} on&&/^- /{exit} on' $SHIP | flat; echo; }
# E02-S21 (the owner's Split): both lines went with /ship-it's CI watch and its messages. None comes back, so none can call a
# check that ran "not checked" or show a secret's value
check "/ship-it's two CI-time success lines are gone (no monitoring flow, no \"(On success)\" message), so neither can say \"could not be checked\" for a check that ran, or show a secret's value" \
  '[ -z "$(fr_succ2 | tr -d " \n")" ] && ! grep -qiE "Report success:|^- \(On success\)|passed all checks and is ready for review|Your app is ready for review" $SHIP'
# Minor 6: the guard says the secret leak scan runs on /ship-it save too (its "No review." is not "no pre-push checks").
# Re-review Minor 2: the modes table's save row says so too, and never that save skips the pre-push checks or the scan
# PR #62 review Minor: since E02-S21's Split the pre-push checks are two, so the save row names them (was "the pre-push checks
# (the secret leak scan among them) still run")
check "the secret guard says the secret leak scan runs on /ship-it save too, and the modes table's save row says the dependency scan and the secret leak scan still run (never that save skips them)" \
  't5_secs | t4_aff | gq -F "/ship-it save included (the secret leak scan runs on save too):" && ! t5_secs | gq -iE "\b(skips?|skipped|without)\b[^.;:]{0,30}\b(scan|pre-push|check)[^.;:]{0,20}\bsave\b|\bsave\b[^.;:]{0,30}\b(skips?|skipped|without)\b" &&
   r=$(grep -E "^\| *./ship-it save. *\|" $SHIP || true) && printf "%s\n" "$r" | gq -F "No reviewers; the dependency scan and the secret leak scan still run." && ! printf "%s\n" "$r" | gq -iE "\b(skips?|skipped|skipping|without|bypass(es|ed)?|no)\b[^.;:|]{0,30}\b(scans?|pre-push|checks?)\b|\b(pre-push checks?|scan)\b[^.;:|]{0,20}\b(don.t|do not|doesn.t|does not|never|aren.t|are not|isn.t|is not)\b"'

# ---- Task 5: the record survives ----
# Every skill that rewrites .make-it-state.md keeps "## Left out by your choice" exactly as it is, by following
# left-out-record.md (a template is filled on a fixture, byte for byte). /retrofit-it writes the section at the plan pick, reads
# it first on a re-run (one plain mention, never in the numbered plan or an "all" pick), skips checks by the CURRENT record, and
# writes a check-in "take it out" into it. The section runs in a subshell whose stderr is caught: a bad regex fails the stderr
# check below instead of passing silently.
WRAP=.claude/commands/wrap-it.md
r5_all() {
# paragraphs, sentences and units (list items) of stdin, with the spaces of a wrapped, indented line squeezed
r5_pa() { paras | tr -s ' '; }
r5_ps() { psents | tr -s ' '; }
r5_un() { t3_units | tr -s ' '; }
# a file name's dots (".md", ".make-it-state") kept from ending a [^.;:] span; what a sentence affirms (t4_aff), so kept
r5_md() { perl -pe 's/\.(md|json)\b/_$1/g; s/\.make-it-state/make-it-state/g'; }
r5_aff() { t4_aff | r5_md; }
# one line per paragraph on stdin -> one line per sentence
r5_sents() { sed 's/\. /.\
/g'; }
# the first ```markdown template of stdin
r5_tpl() { awk '/^```markdown/{on=1;next} on&&/^```/{exit} on'; }
R5_KEEPV='\b(keep|keeps|kept|keeping|leave|leaves|leaving|preserves?|preserved|preserving|carry|carries|carried|carrying|copy|copies|copied|copying|stays?|remains?|retains?)\b'
R5_EXACT='exactly as (it|they) (is|are|was|were|stands?)\b|\bas (it|they) (is|are|was|were|stands?)( now| today)?( *[],.;:()]| --|$)|\bunchanged\b|\bbyte for byte\b|\bword for word\b|\bverbatim\b|\buntouched\b'
# the opposites: the whole file rewritten from this session; the section dropped, rewritten or regenerated
R5_WHOLE='\b(whole|entire|full)\b[^.;:]{0,25}\b(file|breadcrumb|state file|make-it-state_md)\b[^.;:]{0,40}\bfrom (this|the current) (session|run)\b|\b(re)?writ[a-z]* (the whole |the entire |all of )?(the file|it|make-it-state_md|the breadcrumb|the state file) from (this|the current) (session|run)\b'
R5_DROP="\\b(drop|delet|remov|omit|clear|empt|regenerat|rebuil|recreat|overwrit|replac|rewrit|refill|redo)[a-z]*( (the|its|this|that))?( section)? .?$SECTION|$SECTION.?( section)? (is|are|gets?|goes)( [a-z]+)? (dropped|deleted|removed|omitted|cleared|emptied|regenerated|rewritten|rebuilt|recreated|replaced|overwritten)\\b"

# the sentences that keep the section exactly as it is in what they affirm (no qualifier), in a paragraph citing left-out-record.md
r5_ksent() {
  r5_pa | grep -F "$SECTION" | grep -F left-out-record.md | r5_sents | grep -F "$SECTION" | while IFS= read -r s; do
    a=$(printf "%s\n" "$s" | r5_aff)
    if printf "%s\n" "$a" | gq -iE "($R5_KEEPV)[^.;:]{0,100}($R5_EXACT)" && ! printf "%s\n" "$a" | gq -iE "$T4_QUAL"; then printf "%s\n" "$s"; fi
  done; true
}
# the template holds the section as one keep placeholder under its heading, and the block cites left-out-record.md
r5_tkeep() {
  local b t; b=$(cat)
  t=$(printf "%s\n" "$b" | r5_tpl | awk -v h="$SECTION" '/^## /{on=($0==h); next} on' | flat | sed 's/^ *//; s/ *$//')
  case "$t" in \[*\]) ;; *) return 1;; esac
  printf "%s\n" "$t" | r5_aff | gq -iE "$R5_EXACT" && ! printf "%s\n" "$t" | r5_aff | gq -iE "$T4_QUAL" && printf "%s\n" "$b" | gq -F left-out-record.md
}
# a sentence that affirms an opposite (a whole-file rewrite from this session counts only where the sentence doesn't keep the section)
r5_keepx() {
  r5_ps | while IFS= read -r s; do
    a=$(printf "%s\n" "$s" | r5_aff)
    if printf "%s\n" "$a" | gq -iE "$R5_DROP"; then printf "%s\n" "$s"
    elif printf "%s\n" "$a" | gq -iE "$R5_WHOLE" && ! { printf "%s\n" "$s" | gq -F "$SECTION" && printf "%s\n" "$a" | gq -iE "$R5_EXACT"; }; then printf "%s\n" "$s"; fi
  done; true
}
r5_keepok() { { [ -n "$(printf "%s\n" "$1" | r5_ksent)" ] || printf "%s\n" "$1" | r5_tkeep; } && [ -z "$(printf "%s\n" "$1" | r5_keepx)" ]; }

WRAP5="$(between $WRAP '**5. Update .make-it-state.md:**' '</step>')"
RSAVE="$(stepof $RESUME save-state)"
TSAVE="$T3_SAVE"
TSTOP="$(awk '/^\*\*If user asks to stop the app:\*\*/{on=1;print;next} on&&/^\*\*/{exit} on' $TRY)"
PARTE="$(between $RETRO '**PART E: Declare success and hand off**' '</step>')"
DISC_PLAN="$(between $RETRO '<step name="discovery">' "**What I'll add:**")"
PLAN="$(stepof $RETRO plan)"
VERIFY6="$(between $RETRO '<step name="verify">' '**PART E')"
CHECKIN="$(between $RETRO '**5b. Phased retrofit' '**Adaptation rules for existing code:**')"
EH_DIS="$(between $RETRO '**If the user disagrees with a proposed change:**' '**If the risk score is Very High')"
EH_VH="$(between $RETRO '**If the risk score is Very High (61+):**' '</error-handling>')"
CLAR="$(stepof $RETRO clarification)"
DISC="$(stepof $RETRO discovery)"
check "(control) Task 5 anchors found (guards the checks below against a moved anchor)" \
  'n=0; for v in "$WRAP5" "$RSAVE" "$TSAVE" "$TSTOP" "$PARTE" "$DISC_PLAN" "$PLAN" "$VERIFY6" "$CHECKIN" "$EH_DIS" "$EH_VH" "$CLAR" "$DISC"; do [ -n "$v" ] || n=1; done; [ "$n" = 0 ]'

# T5-1: every rewrite keeps the section exactly as it is, by following left-out-record.md, and says no opposite
for x in "wrap-it step 5|WRAP5" "resume-it save-state|RSAVE" "try-it save-state|TSAVE" "try-it Phase 6 \"stop the app\"|TSTOP" "retrofit-it Part E|PARTE"; do
  check "${x%%|*}: keeps \"$SECTION\" exactly as it is, by following left-out-record.md, and never says to drop, regenerate or rewrite it from this session" \
    "r5_keepok \"\$${x##*|}\""
done
check "(control) none of the five rewrites restates the definition (its entry form or read-step wording)" \
  '! printf "%s\n" "$WRAP5" "$RSAVE" "$TSAVE" "$TSTOP" "$PARTE" | gq -E -- "-- checks [^ ]+.* -- left out|up to the next .## . heading|Only entries go in this section"'

# T5-1 on a fixture: fill each template on a state file that holds the section; the section comes through byte for byte, once.
# (The fixture is in a function: macOS bash 3.2 misparses a heredoc inside $(...). @SP@ and @TAB@ become two trailing spaces and
# a tab, so the bytes an editor might trim are made here, at run time.)
r5_fix() { cat <<'R5EOF'
# Project State -- Fixture App
> Last updated: 2026-10-01 09:00
> Last session: retrofit-it

## Current Status
Upgraded; the app runs in Docker.

## Left out by your choice

- Activity monitoring (who did what, and when)@TAB@-- checks L01-L08 -- left out 2026-10-01
- Notifications for the café menu -- checks none -- left out 2026-10-02 (taken out)
- Secure login, the sign-in screen only -- checks A01, A03 -- left out 2026-09-30@SP@

## Try-It Status
- Last run: 2026-10-02 10:00
- Result: 9 of 10 Passing, plus 3 item(s) left out by your choice
R5EOF
}
R5_FIX="$(r5_fix | sed "s/@SP@/  /; s/@TAB@/$(printf '\t')/"; echo .)"; R5_FIX="${R5_FIX%.}"
# r5_fill BLOCK MODE STATE: print STATE after the block's template is filled on it. Every [placeholder] becomes FILLER. The
# section's heading with one keep placeholder under it (as r5_tkeep reads it), or a line that names the section with a keep
# phrase, becomes STATE's section, verbatim. With no such spot, STATE's section is carried over only when the step says to keep
# it (r5_keepok). MODE "whole" writes the template as the file; "section" puts the template's sections in place of STATE's
# sections of the same name.
r5_fill() {
  local tpl keep=0
  tpl="$(printf "%s\n" "$1" | r5_tpl; echo .)"; tpl="${tpl%.}"
  [ -n "$(printf "%s" "$tpl" | tr -d '[:space:]')" ] || return 1
  r5_keepok "$1" && keep=1
  R5T="$tpl" R5F="$3" R5K="$keep" R5M="$2" R5H="$SECTION" R5X="$R5_EXACT" R5Q="$T4_QUAL" perl -e '
    my ($t, $f, $k, $m, $h, $x, $q) = @ENV{qw(R5T R5F R5K R5M R5H R5X R5Q)};
    my ($s) = $f =~ /^(\Q$h\E\n(?:(?!## ).*(?:\n|\z))*)/m; $s //= "";
    my ($done, @out) = (0);
    for my $p (split /^(?=## )/m, $t) {
      if ($p =~ /\A\Q$h\E\n(.*)\z/s) {
        (my $b = $1) =~ s/\s+/ /g; $b =~ s/^ | $//g;
        if ($b =~ /\A\[.*\]\z/ && $b =~ /$x/i && $b !~ /$q/i) { push @out, $s; $done = 1; next }
      }
      my @l = split /^/m, $p;
      for (@l) { if (!/^## / && index($_, $h) >= 0 && /$x/i) { $_ = $s; $done = 1 } else { s/\[[^\]\n]*\]/FILLER/g } }
      push @out, join "", @l;
    }
    my $o;
    if ($m eq "whole") { $o = join "", @out; $o .= ($o =~ /\n\z/ ? "" : "\n") . "\n" . $s if !$done && $k && $s ne "" }
    else {
      my (%tp, @ord); for (@out) { my ($hd) = /\A(.*)/; push @ord, $hd unless exists $tp{$hd}; $tp{$hd} = $_ }
      $o = "";
      for my $fp (split /^(?=## )/m, $f) { my ($hd) = $fp =~ /\A(.*)/; $o .= exists $tp{$hd} ? delete $tp{$hd} : $fp }
      $o .= $tp{$_} for grep { exists $tp{$_} } @ord;
    }
    print $o;'
}
# r5_same STATE: STATE holds the fixture's section once, byte for byte (heading through the line before the next "## " heading)
r5_same() {
  R5A="$1" R5F="$R5_FIX" R5H="$SECTION" perl -e '
    my ($a, $f, $h) = @ENV{qw(R5A R5F R5H)};
    sub lo { my ($d) = $_[0] =~ /^(\Q$h\E\n(?:(?!## ).*(?:\n|\z))*)/m; $d }
    my ($s, $g) = (lo($f), lo($a)); my $n = () = $a =~ /^\Q$h\E$/mg;
    exit((defined $s && defined $g && $g eq $s && $n == 1) ? 0 : 1);'
}
r5_survives() { local o; o="$(r5_fill "$1" "$2" "$R5_FIX"; echo .)" && r5_same "${o%.}"; }
check "wrap-it step 5: its template, filled on a state file that holds the section, keeps the section byte for byte, once" 'r5_survives "$WRAP5" whole'
check "resume-it save-state: its template, filled on that state file, keeps the section byte for byte, once" 'r5_survives "$RSAVE" whole'
check "(control) try-it save-state: its Try-It Status template, put into that state file, keeps the section byte for byte, once" 'r5_survives "$TSAVE" section'
check "the record survives a retrofit -> try-it -> wrap-it -> resume-it cycle (each template filled on the file the last one left), byte for byte" \
  'a="$(r5_fill "$TSAVE" section "$R5_FIX"; echo .)" && b="$(r5_fill "$WRAP5" whole "${a%.}"; echo .)" && c="$(r5_fill "$RSAVE" whole "${b%.}"; echo .)" && r5_same "${c%.}"'
check "(control) the fixture holds its trailing spaces, tab and UTF-8 bytes" \
  'printf "%s" "$R5_FIX" | gq -E "2026-09-30  \$" && printf "%s" "$R5_FIX" | gq "when)$(printf "\t")--" && printf "%s" "$R5_FIX" | gq -F "café"'

# T5-2: a /retrofit-it re-run reads the record first; a left-out item is mentioned once, never in the numbered plan or an "all" pick
r5_rp() { printf "%s\n%s\n" "$DISC_PLAN" "$PLAN" | r5_ps; }
R5_LOI='left.out (items?|ones?)|items? (the user|they) left out|items? in (the|that|this) record|anything (in the record|left out)|what (the user|they) left out|items? (in|under) .?'"$SECTION"
R5_PLANX='numbered|\bthe plan\b|What I.ll (add|adjust)|item numbers?|the (numbered )?list'
R5_ALLP='\[ITEM_COUNT\]|\ball (the )?items\b|"all"|\*\*all\b|\ball of them\b'
check "retrofit-it reads the record (left-out-record.md) before it builds the numbered plan" \
  '[ -n "$(printf "%s\n" "$DISC_PLAN" | grep -v "^@" | r5_ps | grep -F left-out-record.md | r5_aff | grep -iE "\b(read|reads|reading)\b" | grep -iE "read steps?|$SECTION|the record|left-out record|left out by your choice|make-it-state_md" || true)" ]'
r5_out() { r5_rp | grep -iE "($R5_LOI)[^.;:]{0,80}(\bnever\b|\bnot\b|n.t\b|out of|exclud|without|stays? out|kept out|keep (it|them) out)[^.;:]{0,40}($R5_PLANX)|(\bnever\b|\bno\b|\bnot\b|exclud[a-z]*|leave[s]? out|keep[s]? out)[^.;:]{0,20}($R5_LOI)[^.;:]{0,40}($R5_PLANX)" || true; }
r5_offerx() { r5_rp | while IFS= read -r s; do a=$(printf "%s\n" "$s" | r5_aff)
    if printf "%s\n" "$a" | gq -iE "($R5_LOI)[^.;:]{0,30}\b(is|are|gets?|get)( also| still| then)? (numbered|offered)\b|($R5_LOI)[^.;:]{0,40}\b(goes|go|is|are|get|gets|stays?)( [a-z]+)? (in|into|on) (the )?($R5_PLANX)"; then printf "%s\n" "$s"
    elif printf "%s\n" "$a" | gq -iE "\b(offer|list|number|show|present|put|include)[a-z]*\b[^.;:]{0,25}\b(every|each|all( the)?)\b[^.;:]{0,15}\b(items?|gaps?)\b[^.;:]{0,30}\b(in|into|on) (the )?(plan|numbered|list)\b" && ! printf "%s\n" "$s" | gq -iE "(except|but|other than|apart from|\bnot\b|never|without|exclud|out of|\bno\b)[^.;:]{0,30}($LO|record)"; then printf "%s\n" "$s"; fi
  done; true; }
check "retrofit-it plan: a left-out item is kept out of the numbered plan, and nothing offers every item in the plan" \
  's=$(r5_out); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && [ -z "$(r5_offerx)" ]'
r5_allin() { r5_rp | grep -iE "$R5_ALLP" | grep -iE "($R5_ALLP)[^.;:]{0,80}(\bnever\b|\bnot\b|n.t\b|\bonly\b|exclud|without|apart from|other than|except)[^.;:]{0,40}($LO|record)|($R5_LOI)[^.;:]{0,60}(\bnever\b|\bnot\b|n.t\b|out of|exclud|without|stays? out|kept out)[^.;:]{0,60}($R5_ALLP)" || true; }
r5_allx() { r5_rp | grep -iE "$R5_ALLP" | while IFS= read -r s; do a=$(printf "%s\n" "$s" | r5_aff)
    printf "%s\n" "$a" | gq -iE "($R5_ALLP)[^.;:]{0,40}\b(includ|bring|brings|cover|add)[a-z]*\b[^.;:]{0,30}($LO)|($R5_LOI)[^.;:]{0,40}\b(count|counts|counted|included|includes|come back|comes back|brought back)\b[^.;:]{0,30}($R5_ALLP)|($LO)[^.;:]{0,15}\b(ones? |items? )?(included|too|as well|also)\b" && printf "%s\n" "$s"
  done; true; }
check "retrofit-it plan: the \"all [ITEM_COUNT] items\" pick never covers or brings back a left-out item" \
  '[ -n "$(r5_allin)" ] && [ -z "$(r5_allx)" ]'
# (a unit: one list item or paragraph, its wrapped lines joined, so the mention may wrap; no question anywhere in it)
check "retrofit-it plan: a left-out item gets the one-line mention \"$PHRASE\", never in a numbered item or in the ask" \
  'u=$(printf "%s\n" "$PLAN" | r5_un | grep -iF "$PHRASE" || true); [ -n "$u" ] && ! printf "%s\n" "$u" | gq -E "^ *[0-9]+\. " && ! printf "%s\n" "$u" | gq -iE "\?|Tell me what to include|which should|want me to|should I"'

# T5-3: the section is written at the plan pick (so "Stop here" keeps it); a re-run adds to it there; Part E adds, never rewrites
r5_pickp() { printf "%s\n" "$PLAN" | r5_pa | grep -F "$SECTION" | grep -F left-out-record.md | grep -F "$STATE" || true; }
check "retrofit-it plan: the pick writes each left-out item under \"$SECTION\" in $STATE (left-out-record.md), not only at Part E" \
  's=$(r5_pickp | r5_sents | grep -F "$SECTION" | r5_aff | grep -iE "\b(write|writes|writing|written|add|adds|adding|added|record|records|recorded|put|puts|append|appends|goes|go)\b" || true); [ -n "$s" ] && ! r5_pickp | r5_sents | r5_aff | gq -iE "\b(only|not until|just)\b[^.;:]{0,20}\b(at|in|during|after|by) (Part E|Phase 6|the end|verification)\b|\bwait(s|ing)? (for|until) (Part E|Phase 6)\b"'
check "retrofit-it plan: on a re-run the pick adds its new leave-outs to the section already there, never replaces it" \
  'p=$(r5_pickp | r5_sents | r5_aff); printf "%s\n" "$p" | gq -iE "(re-?run|run (it )?again|earlier run|previous run|already (holds?|has|there|in it|written|recorded)|existing (lines?|entries|section)|lines (already )?there)[^.]{0,100}\b(add|adds|adding|append|appends|keep|keeps|kept)\b|\b(add|adds|adding|append|appends)\b[^.;:]{0,40}\b(to|after|below|beside|alongside)\b[^.;:]{0,30}\b(lines?|entries|section|record|it)\b[^.;:]{0,30}\b(already|there|existing|earlier)\b" && ! printf "%s\n" "$p" | gq -iE "\b(replac|rewrit|overwrit|regenerat|clear|empt|recreat)[a-z]*( (the|its|this|that))?( whole)? (.?$SECTION|section|record)\b|\bfrom (this|the current) (run|pick)\b[^.;:]{0,15}\b(alone|only)\b|\bfrom (this|the current) run.?s? (plan )?(pick|ask)\b"'
r5_pe() { printf "%s\n" "$PARTE" | r5_pa | r5_sents | grep -iE "$SECTION|\bthe section\b" || true; }
check "retrofit-it Part E: adds to the section (or finds its lines already written), never writes it from this run's pick alone" \
  'p=$(r5_pe | r5_aff); printf "%s\n" "$p" | gq -iE "\b(add|adds|adding|append|appends|appending)\b[^.;:]{0,30}\b(to|onto|after|below)\b[^.;:]{0,20}(\bit\b|the section|the lines|its lines|the record|$SECTION)|\balready\b[^.;:]{0,40}\b(written|there|holds?|has|in it|recorded)\b|\bwritten (at|in) the plan (pick|ask)\b" && ! printf "%s\n" "$p" | gq -iE "\bfrom (this|the current) run.?s? (plan )?(pick|ask)\b|\b(writ|rewrit|replac|fill|build)[a-z]*( (the|its|this|that))? (.?$SECTION|section|record)[^.;:]{0,40}\bfrom (this|the current) (run|pick)\b"'
r5_stop() { printf "%s\n" "$CHECKIN" | r5_pa | grep -F "**Stop here:**" | r5_sents || true; }
check "(control) retrofit-it \"Stop here\": nothing there drops, clears or rewrites the section" \
  '[ -n "$(r5_stop)" ] && [ -z "$(r5_stop | r5_aff | grep -iE "$R5_DROP|\b(drop|delet|remov|clear|empt|rewrit)[a-z]*( (the|its|this|that))? (section|record|left-out (lines?|record))\b" || true)" ]'

# T5-4: check-ins. Phase 6 skips by the CURRENT record; a bring-back at "Fix something first" runs its checks and Part E doesn't
# record it; a check-in "take it out" writes its line into the record, not only TODO.md
check "retrofit-it Phase 6: checks are skipped for the items in the current record, never by the plan pick (Phase 4)" \
  's=$(printf "%s\n" "$VERIFY6" | r5_ps | grep -iE "skip|stays? out" | r5_aff || true); printf "%s\n" "$s" | gq -iE "current record|record as it (is|stands) now|the record now|\bitems? (still )?in (the|that) (record|section)|$SECTION" && ! printf "%s\n" "$s" | gq -iE "\((the user.s )?plan (pick|ask)(, Phase 4)?\)|\b(items?|checks?)\b[^.;:]{0,25}\b(from|at|in|by) the (user.s )?plan (pick|ask)\b[^.;:]{0,40}\b(skip|stay out|skipped)|\bskip[a-z]*\b[^.;:]{0,60}\b(left out|picked|chosen) (at|in) the plan (pick|ask)\b"'
R5_BACK='(bring|brings|brought|bringing)[^.;:]{0,40}\bback\b|bring-back'
r5_ci() { printf "%s\n" "$CHECKIN" | r5_pa | while IFS= read -r p; do printf "%s\n" "$p" | r5_sents | grep -iE "$R5_BACK" | while IFS= read -r s; do
    printf "%s\n%s\n" "$s" "$p" | gq -iE "Fix something first|check-in" && printf "%s\n" "$s"; done; done; true; }
check "retrofit-it check-in: a left-out item brought back at \"Fix something first\" follows left-out-record.md read step 4 (its line leaves the record)" \
  's=$(r5_ci | r5_aff); printf "%s\n" "$s" | gq -iE "read step 4|left-out-record_md" && ! printf "%s\n" "$s" | gq -iE "\bback\b[^.;:]{0,60}\b(stays?|remains?|kept|is still|still)\b[^.;:]{0,15}(left out|in the record|in the section)"'
check "retrofit-it Phase 6: a left-out item brought back at a check-in runs its checks" \
  's=$(printf "%s\n" "$VERIFY6" | r5_ps | grep -iE "$R5_BACK" || true); { printf "%s\n" "$s" | r5_aff | gq -iE "\b(runs?|ran)\b[^.;:]{0,15}\b(its|their|the)\b[^.;:]{0,5}\bchecks?\b|\bchecks?\b[^.;:]{0,10}\b(run|runs|are run|is run|do run)\b|\b(is|are|gets?) (checked|verified)\b" || printf "%s\n" "$s" | gq -iE "\bback\b[^.;:]{0,80}\b(never|not|n.t|no longer)\b[^.;:]{0,15}\bskipped\b"; } && ! printf "%s\n" "$s" | r5_aff | gq -iE "\bback\b[^.;:]{0,80}\b(is |are |gets? |stays? )?(skipped|left out)\b"'
check "retrofit-it Part E: a left-out item brought back at a check-in is never recorded as left out" \
  's=$(printf "%s\n" "$PARTE" | r5_ps | grep -iE "$R5_BACK" || true); printf "%s\n" "$s" | gq -iE "\bback\b[^.;:]{0,80}(\bnever\b|\bnot\b|n.t\b|\bno\b|no longer)[^.;:]{0,40}\b(record|recorded|written|line|left out|in (it|the section|the record))|(\bnever\b|\bnot\b|n.t\b)[^.;:]{0,20}\b(record|write|add|list)[a-z]*\b[^.;:]{0,50}\bback\b" && ! printf "%s\n" "$s" | r5_aff | gq -iE "\bback\b[^.;:]{0,60}\b(is |are |gets? )?(recorded|written|added|listed|kept)\b[^.;:]{0,20}(as left out|in the (section|record)|under)"'
R5_TAKE='take[sn]?\b[^.;:]{0,25}\bout\b|taking[^.;:]{0,25}\bout\b|disagree|skip(s|ping)? (that|the|a) change'
check "retrofit-it check-in: \"take it out\" writes the item's line into the record (left-out-record.md), not only a TODO.md line" \
  's=$(printf "%s\n%s\n" "$CHECKIN" "$EH_DIS" | r5_pa | grep -F left-out-record.md | r5_sents | grep -iE "$R5_TAKE" | r5_aff || true); printf "%s\n" "$s" | gq -iE "\b(write|writes|writing|written|add|adds|adding|record|records|put|puts)\b[^.;:]{0,60}($SECTION|\bthe record\b|\bits line\b|\ba line\b)|$SECTION[^.;:]{0,40}\b(gets?|gains?)\b" && ! printf "%s\n%s\n" "$CHECKIN" "$EH_DIS" | r5_ps | r5_aff | gq -iE "TODO(_md)?[^.;:]{0,20}\b(only|alone)\b|\b(only|just)\b[^.;:]{0,30}\bTODO"'

# T5-5: the Very High fresh-build route carries the plan pick into the new project's record, or stops and asks
r5_fb() { { printf "%s\n" "$PLAN" | r5_pa | grep -iE "fresh build"; printf "%s\n" "$EH_VH" | r5_pa; } | r5_sents | grep -iE "fresh build|new (/make-it )?project|/make-it" || true; }
check "retrofit-it fresh build: the plan pick goes into the new project's record ($SECTION / left-out-record.md), or it stops and asks" \
  's=$(r5_fb | grep -iE "$LO|plan pick|\bpick\b" || true); printf "%s\n" "$s" | r5_aff | gq -iE "\b(carr(y|ies|ied|ying)|writ(e|es|ten|ing)|mov(e|es|ed|ing)|cop(y|ies|ied|ying)|record(s|ed|ing)?|put(s|ting)?|pass(es|ed|ing)?|start(s|ed|ing)?)\b[^.;:]{0,80}($SECTION|left-out-record_md|make-it-state_md|\bthe record\b|\bits record\b)|\bstops?\b[^.;:]{0,15}\band asks?\b|\bstops? (first )?(to|and) ask\b" && ! r5_fb | r5_aff | gq -iE "\b(build|builds|built)\b[^.;:]{0,30}\b(the )?(full|whole|entire) scaffold\b[^.;:]{0,40}($LO)|($LO)[^.;:]{0,40}\b(get|gets|are|is)? ?(built|added|generated) (anyway|too|as well|regardless)\b|\b(ignore|ignores|drop|drops|lose|loses)\b[^.;:]{0,30}($LO|the pick|the record)"'

# T5-6: a state file that holds only the record doesn't set off the "partial /make-it state" question
R5_ONLY='only|just|nothing( else)?( in it)? (but|than)'
r5_part() { { printf "%s\n" "$CLAR" | r5_un | grep -iE "partial"; printf "%s\n" "$DISC" | r5_pa | grep -iE "partial"; } | r5_sents || true; }
check "retrofit-it: a $STATE that holds only the record is not \"partial /make-it state\" (no question)" \
  's=$(r5_part | r5_md | grep -iE "\b($R5_ONLY)\b[^.;]{0,40}($SECTION|\bthe record\b|left-out record|left-out section)[^.;]{0,80}(\bnot\b|\bnever\b|n.t\b|\bno\b)[^.;]{0,40}(partial|question|\bask|\bcount|set off|trigger)|(\bnot\b|\bnever\b|n.t\b|\bno\b)[^.;]{0,40}(partial|\bask)[^.;]{0,80}\b($R5_ONLY)\b[^.;]{0,40}($SECTION|\bthe record\b|left-out record)" || true); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "$T4_QUAL" && ! r5_part | r5_aff | gq -iE "\b($R5_ONLY)\b[^.;:]{0,40}($SECTION|the record)[^.;:]{0,40}\b(is|counts as|means)\b[^.;:]{0,15}\bpartial\b"'

# T5-7: try-it save-state's Result and Frontend URL lines read left out as the Status line does: never "All Passing", and no URL,
# when a left-out item is why
R5_TS="$(printf "%s\n" "$TSAVE" | r5_un | r5_sents)"
r5_resptr() { printf "%s\n" "$R5_TS" | grep -F Result | r5_aff | grep -iE "\bResult\b[^.;:]{0,80}\b(as|like|same [a-z -]{0,20}as)\b[^.;:]{0,25}\b(the )?(report.s )?Status line\b|\bStatus line\b[^.;:]{0,60}\b(also|too)\b[^.;:]{0,20}\bResult\b" || true; }
check "try-it save-state: the Result line reads All Passing only when nothing is left out (stated, or as the report's Status line)" \
  'r=$(printf "%s\n" "$R5_TS" | grep -F "All Passing" | grep -F Result | grep -iE "All Passing[^.;:]{0,60}only (when|if)[^.;:]{0,30}(nothing|no |none)[^.;:]{0,25}left out|only (when|if)[^.;:]{0,30}(nothing|no |none)[^.;:]{0,25}left out[^.;:]{0,60}All Passing|(All Passing[^.;:]{0,40}\b(never|not)\b|\bnever\b[^.;:]{0,10}All Passing)[^.;:]{0,15}\b(while|when|if)\b[^.;:]{0,25}(anything|something|an item|any item|a left-out item)[^.;:]{0,20}left.out" || true); { [ -n "$r" ] || [ -n "$(r5_resptr)" ]; } && ! printf "%s\n" "$R5_TS" | grep -F "All Passing" | r5_aff | gq -iE "All Passing[^.;:]{0,60}\beven (if|when|though|while)\b|\beven (if|when|though|while)\b[^.;:]{0,40}left.out[^.;:]{0,60}All Passing|All Passing[^.;:]{0,60}\b(regardless|whether or not|either way|anyway)\b|All Passing[^.;:]{0,60}\b(every|all) (tests?|checks?) (that ran|run)\b|\b(every|all) (tests?|checks?) that ran[^.;:]{0,30}All Passing|All Passing[^.;:]{0,40}\b(with|despite)\b[^.;:]{0,30}left.out"'
check "try-it save-state: when a left-out item kept the app from starting, the Result line is never All Passing or X of Y" \
  's=$(printf "%s\n" "$R5_TS" | grep -iE "$KEPT|no tests? (was |were )?(checked|run)|nothing (was )?(checked|ran)" | grep -F Result || true); { [ -n "$(r5_resptr)" ] || printf "%s\n" "$s" | gq -iE "(in place of|instead of|never|not|n.t)[^.;:]{0,40}(All Passing|X of Y|0 of 0)|item\(s\) left out|couldn.t (be )?start"; } && ! printf "%s\n" "$R5_TS" | r5_aff | gq -iE "$WAIVE"'
check "try-it save-state: when a left-out item kept the app from starting, the Frontend URL line gives no URL" \
  's=$(printf "%s\n" "$R5_TS" | grep -iE "$KEPT" | grep -iE "URL|localhost" || true); { printf "%s\n" "$R5_TS" | grep -F URL | r5_aff | gq -iE "\bURL\b[^.;:]{0,80}\b(as|like)\b[^.;:]{0,30}How to Access" || printf "%s\n" "$s" | gq -iE "(in place of|instead of|\bno\b|drop|omit|leave out|without|never)[^.;:]{0,40}(URL|localhost|address|link)|(URL|localhost)[^.;]{0,60}(in place of|instead of|\bnone\b)|\bnone\b[^.;]{0,60}(URL|localhost)"; } && ! printf "%s\n" "$R5_TS" | r5_aff | gq -iE "$WAIVE|(keep|still (write|give|record|list|show))[^.;:]{0,25}(the )?(Frontend )?(URL|localhost)"'
# ---- Task 5 fix round 1 ----
# I-1 (review 1): every retrofit-it undo spares .make-it-state.md, the way it spares .env* and .make-it/: the full undo (own
# repo and nested) and "Before this step" (own repo). Run on a scratch repo by the text's own commands: the plan pick writes
# the record, the snapshot block runs, step 1, a check-in (a take-out writes its line; a bring-back deletes one), step 2,
# then the undo. The record must read as the check-in left it, and the upgrade's files must still go back.
R5_SNAP="$(awk 'index($0,"make the snapshot if there is none yet"){a=1} a&&/^```bash/{on=1;next} on&&/^```/{exit} on' $RETRO)"
R5_UNDO="$(awk 'index($0,"**Undo** --"){a=1} a&&/^```bash/{on=1;next} on&&/^```/{exit} on' $RETRO)"
# "Before this step" runs the full undo's own git restore / git clean / git commit lines, the step's start commit as the source
R5_STEPU="$(printf "%s\n" "$R5_UNDO" | awk '/git restore/{on=1} on{print} on&&/fail "/{exit}')"
R5_TAKE='- Secure login -- checks A01-A10 -- left out 2026-10-02 (taken out)'
# r5_repo HOW NEW: HOW = own-step (undo "Before this step") | own-full | nested (the full undo); NEW=1: nothing was left out
# at the pick, so the take-out starts the file after the snapshot (own-step then undoes step 1 at that same check-in, the
# line not yet saved). Prints the record after the undo (or @@NOFILE), then "@@FILES ok" when the upgrade's files went back.
# Isolated: its own temp folder, no global or system git config, no repo above it.
r5_repo() (
  how=$1 new=$2 rec=.make-it-state.md
  T=$(mktemp -d 2>/dev/null) && T=$(cd "$T" && pwd -P) || exit 0; trap 'rm -rf "$T"' EXIT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T" GIT_AUTHOR_NAME=t \
    GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
  A="$T/proj/app"; mkdir -p "$A" && cd "$T/proj" || exit 0
  [ "$how" = nested ] || cd "$A"
  { git -c init.defaultBranch=main init -q && printf 'node_modules/\n' > .gitignore && printf 'v0\n' > "$A/app.py" &&
    git add -A && git commit -qm init; } >/dev/null 2>&1 || { echo "@@SETUP"; exit 0; }
  cd "$A"
  [ "$new" = 1 ] || printf '# Project State -- Scratch\n\n## Left out by your choice\n\n%s\n%s\n' \
    '- Activity monitoring -- checks L01-L08 -- left out 2026-10-01' '- Notifications -- checks none -- left out 2026-10-01' > $rec
  o=$(bash -c "$R5_SNAP" 2>&1); case $o in *"snapshot: "*) ;; *) echo "@@SNAP $o"; exit 0;; esac
  src=$(git rev-parse HEAD 2>/dev/null) exp=v0
  printf 'v1\n' > app.py; printf 'one\n' > step1.txt
  [ "$how" = nested ] || { git add -A && git commit -qm "step 1"; } >/dev/null 2>&1
  if [ -f $rec ]; then printf '%s\n' "$R5_TAKE" >> $rec; else printf '## Left out by your choice\n\n%s\n' "$R5_TAKE" > $rec; fi
  [ "$new" = 1 ] || { grep -v '^- Activity monitoring' $rec > $rec.n; mv $rec.n $rec; }
  if [ "$how" != own-step ] || [ "$new" = 0 ]; then
    src=$(git rev-parse HEAD 2>/dev/null) exp=v1
    printf 'v2\n' > app.py; printf 'two\n' > step2.txt
    [ "$how" = nested ] || { git add -A && git commit -qm "step 2"; } >/dev/null 2>&1
  fi
  if [ "$how" = own-step ]; then
    o=$(R5W="$A" R5S="$src" bash -c 'fail() { echo "UNDO FAILED: $1"; exit 1; }; work=$R5W; tag=$R5S
'"$R5_STEPU" 2>&1)
  else exp=v0
    o=$(printf '%s\n' "$R5_UNDO" | perl -pe 's/\bapp=\[[^\]]*\]/app="\$R5A"/; s/\bwork=\[[^\]]*\]/work="\$R5A"/' | R5A="$A" bash 2>&1)
  fi
  case $o in *"UNDO FAILED"*) echo "@@UNDO $o"; exit 0;; esac
  if [ -f "$A/$rec" ]; then cat "$A/$rec"; else echo "@@NOFILE"; fi
  [ "$(cat "$A/app.py" 2>/dev/null)" = "$exp" ] && [ ! -e "$A/step2.txt" ] && { [ "$exp" = v1 ] || [ ! -e "$A/step1.txt" ]; } &&
    echo "@@FILES ok"; true
)
R5_OS0="$(r5_repo own-step 0)"; R5_OF0="$(r5_repo own-full 0)"; R5_NF0="$(r5_repo nested 0)"
R5_OS1="$(r5_repo own-step 1)"; R5_OF1="$(r5_repo own-full 1)"; R5_NF1="$(r5_repo nested 1)"
# the take-out's line is in the record after the undo / the brought-back item's deleted line stays deleted (the pick's other
# line stays); either way the upgrade's files went back
r5_kept() { printf "%s\n" "$1" | gq -xF -- "$R5_TAKE" && printf "%s\n" "$1" | gq -xF "@@FILES ok"; }
r5_gone() { ! printf "%s\n" "$1" | gq -F -- "- Activity monitoring" && printf "%s\n" "$1" | gq -xF -- "- Notifications -- checks none -- left out 2026-10-01" && printf "%s\n" "$1" | gq -xF "@@FILES ok"; }
# "Before this step" still runs the full undo's own lines (else the run above isn't testing what it says)
r5_btsame() { printf "%s\n" "$PLAN" | r5_pa | grep -F "**Before this step**" | sed 's/.*\*\*Before this step\*\*//' | r5_sents | awk 'NR==1' | gq -iE "\bsame\b[^.;]{0,20}git restore|make-it-state"; }
check "retrofit-it undo \"Before this step\" (own repo, the text's own commands on a scratch repo): a check-in take-out's line is still in the record" 'r5_btsame && r5_kept "$R5_OS0"'
check "retrofit-it undo \"Before this step\" (own repo, scratch repo): a check-in bring-back's deleted line doesn't come back" 'r5_btsame && r5_gone "$R5_OS0"'
check "retrofit-it full undo (own repo, scratch repo): a check-in take-out's line is still in the record" 'r5_kept "$R5_OF0"'
check "retrofit-it full undo (own repo, scratch repo): a check-in bring-back's deleted line doesn't come back" 'r5_gone "$R5_OF0"'
check "retrofit-it full undo (nested app, scratch repo): a check-in take-out's line is still in the record" 'r5_kept "$R5_NF0"'
check "retrofit-it full undo (nested app, scratch repo): a check-in bring-back's deleted line doesn't come back" 'r5_gone "$R5_NF0"'
check "retrofit-it undo \"Before this step\" right at the check-in (own repo): a take-out that started the record after the snapshot keeps it" 'r5_btsame && r5_kept "$R5_OS1"'
check "retrofit-it full undo (own repo): a take-out that started the record after the snapshot keeps it" 'r5_kept "$R5_OF1"'
check "retrofit-it full undo (nested app): a take-out that started the record after the snapshot keeps it" 'r5_kept "$R5_NF1"'

# I-2: the fresh-build stop fires when an item is left out at this pick OR is already in the record (a re-run); it names both
# EH_VH's top-level bullets, each with every line under it joined; the one with the fresh-build stop
R5_FBS="$(printf "%s\n" "$EH_VH" | awk '/^- /{if(u!="")print u; u=$0; next} {u=u" "$0} END{if(u!="")print u}' | grep -iF "fresh build" | grep -iE "\bstops?\b" | tr -s ' ' | r5_md || true)"
R5_REC="\\b(already )?in the record\\b|\\bthe record\\b|\\bthe left-out record\\b|left-out-record_md|\\b(an? |the )?(earlier|previous|first|last) runs?\\b|$SECTION"
# the this-run-only reading
R5_FBONLY="\\b(only|just)\\b[^.;:]{0,30}\\b(at |in |from )?(this|the current|today.s) (plan )?(pick|run|ask)\\b|\\b(this|the current) (pick|run)\\b[^.;:]{0,10}\\b(only|alone)\\b|($R5_REC)[^.;:]{0,60}\\b(don.t|doesn.t|do not|does not|never|not|no longer|aren.t|isn.t)\\b[^.;:]{0,30}\\b(count|counts|stop|stops|fire|fires|apply|applies|matter|matters|trigger|triggers)\\b|\\b(ignore|ignores|ignoring|skip|skips|skipping)\\b[^.;:]{0,30}($R5_REC)"
r5_fbstop() { printf "%s\n" "$R5_FBS" | r5_sents | grep -iE "\bstops?\b" | grep -iE "fresh build" || true; }
check "retrofit-it fresh build: the stop fires when an item is left out at this pick or is already in the record (a re-run), never on this run's pick alone" \
  'printf "%s\n" "$(r5_fbstop)" | r5_aff | gq -iE "\b(left|leaves?|leaving)\b[^.;:]{0,60}\bout\b[^.;:]{0,80}\b(or|and|plus|as well as|including)\b[^.;:]{0,50}($R5_REC)|($R5_REC)[^.;:]{0,60}\b(or|and|plus)\b[^.;:]{0,50}\b(left|leaves?|this pick|the pick)\b" && ! printf "%s\n" "$R5_FBS" | gq -iE "$R5_FBONLY"'
check "retrofit-it fresh build: the stop names each item from both (this pick and the record)" \
  's=$(printf "%s\n" "$R5_FBS" | r5_sents | grep -iE "\bname[sd]?\b" | r5_aff || true); printf "%s\n" "$s" | gq -iE "\bname[sd]?\b[^.;:]{0,60}\b(each|every|all)\b[^.;:]{0,80}(\bboth\b|\beither\b|$R5_REC)" && ! printf "%s\n" "$s" | gq -iE "\bname[sd]?\b[^.;:]{0,60}\bonly\b"'

# Minor 8: the fresh-build ask in the user's own words (what changes, what stays left out, the undo), a Not now (neither), a
# partial answer back to the same two routes, "step-by-step without them" back to the plan's record write and snapshot, and
# active confirmation (approval-block.md)
# its quoted user-facing text: each "..." pair in turn, 60 characters or more (so a short quote's closing mark never opens one)
r5_fbq() { printf "%s\n" "$R5_FBS" | perl -ne 'my @p = split /"/; for (my $i = 1; $i < @p; $i += 2) { print "$p[$i]\n" if length $p[$i] >= 60 }'; }
check "retrofit-it fresh-build ask: it gives the user's own words (quoted): what changes, what stays left out, and the undo" \
  'q=$(r5_fbq); printf "%s\n" "$q" | gq -iE "\b(add|adds|added|adding|build|builds|built|change|changes)\b" && printf "%s\n" "$q" | gq -iE "\b(stay|stays|remain|remains|still)\b[^.;:]{0,15}\bleft out\b" && printf "%s\n" "$q" | gq -iE "\bundo\b|\bundone\b|\b(put|puts|putting)\b[^.;:]{0,30}\bback\b|\btake (it|them|this) back\b|\bno undo\b"'
check "retrofit-it fresh-build ask: it offers **Not now** (neither route), which changes nothing" \
  'printf "%s\n" "$(r5_fbq)" | gq -F "Not now" && printf "%s\n" "$R5_FBS" | gq -iE "Not now[^.;]{0,80}(\bneither\b|change nothing|nothing (changes|is built|is changed)|build nothing|\bstop\b)" && ! printf "%s\n" "$R5_FBS" | r5_aff | perl -pe "s/\\bnothing\\b[^,.;:]*//gi" | gq -iE "Not now\**[^.;]{0,40}\b(build|builds|start|starts|run|runs|goes ahead|go ahead|continue|continues)\b"'
R5_PART='\bpartial\b|\bpart of (it|them|the items|those)\b|\bonly some\b|\bsome of (them|those|the items)\b|\bnot all\b|\bjust (one|some)\b'
check "retrofit-it fresh-build ask: a partial answer comes back to the same two routes (it can't be carried into a fresh build)" \
  's=$(printf "%s\n" "$R5_FBS" | r5_sents | grep -iE "$R5_PART" || true); printf "%s\n" "$s" | gq -iE "\bsame (two )?(routes?|choices|options|ask|question)\b|\b(ask|asks|asking) (again|once more)\b|\b(back|returns?|goes back) to (the|this|those) (same )?(two )?(routes?|choices|options|ask|question)\b" && ! printf "%s\n" "$s" | r5_aff | gq -iE "($R5_PART)[^.;:]{0,60}\b(build|builds|built|carry|carries|carried|keep|keeps|add|adds|added)\b[^.;:]{0,40}(\b(only|just) (those|that|them|the ones|what)\b|\binto the (new|fresh)\b)"'
check "retrofit-it fresh-build ask: \"step-by-step upgrade without them\" goes back to the plan step's record write and snapshot" \
  's=$(printf "%s\n" "$R5_FBS" | r5_sents | grep -iE "step-by-step" | grep -iE "snapshot" | r5_aff || true); printf "%s\n" "$s" | gq -iE "step-by-step[^.]{0,200}\b(record|left-out-record_md)\b[^.]{0,150}\bsnapshot\b|step-by-step[^.]{0,200}\bsnapshot\b[^.]{0,150}\brecord\b" && ! printf "%s\n" "$s" | gq -iE "\b(skip|skips|skipped|skipping|bypass|bypasses|bypassing)\b[^.;:]{0,30}\b(record|snapshot)\b"'
check "retrofit-it fresh-build ask: it is active confirmation, per approval-block.md (never a plain yes)" \
  'printf "%s\n" "$R5_FBS" | gq -iE "approval-block_md|approval block" && printf "%s\n" "$R5_FBS" | gq -iE "active confirmation|high-stakes" && ! printf "%s\n" "$R5_FBS" | r5_aff | gq -iE "plain yes[^.;:]{0,25}\b(is|counts|works|will do|does)\b[^.;:]{0,15}\b(an answer|enough|fine|ok)\b|\b(routine|consequential|low-stakes)\b|\bbatch(ed)?\b"'

# Minor 7: the wrap-it and resume-it placeholders say what goes there in each case: the section exactly as it is; with no
# section, the older lines moved in (per the definition); with nothing left out, nothing under the heading -- never "- None"
# the template's placeholder under the section heading, flat, one clause per line (split at ";" and ". ")
r5_ph() { printf "%s\n" "$1" | r5_tpl | awk -v h="$SECTION" '/^## /{on=($0==h); next} on' | flat | r5_md | sed 's/; /;\
/g; s/\. /.\
/g'; }
R5_NOSEC='\b(no|none|without|lacks?|missing)\b[^];]{0,30}\b(such )?(section|heading)\b|\b(has|have|holds?) none\b|\bolder file\b|\bbefore (it|the section) existed\b'
r5_movein() { r5_ph "$1" | grep -iE "$R5_NOSEC" | grep -iE "\bmov(e|es|ed|ing)\b[^];]{0,80}\b(in|into)\b" | grep -iE "\bolder\b|read step 2|TODO" | grep -viE "\b(never|not|don.t|do not|doesn.t|no longer)\b[^];]{0,15}\bmov" | grep -viE "$T4_QUAL" || true; }
R5_REGEN='\bfrom (this|the current|today.s) (session|run)\b|\b(regenerat|rebuil|recreat|rewrit)[a-z]*\b|\bfrom scratch\b|\bafresh\b'
r5_none() { r5_ph "$1" | grep -iE "\bnothing (is |was )?(left out|in it)\b|\bno (items?|entries|lines?) (is |are )?left out\b" | grep -iE "\bnothing\b[^];]{0,25}\b(under|below|beneath|after)\b|\bno (lines?|entries|text) (under|below)\b|\bjust the heading\b|\bthe heading (alone|only|on its own|by itself)\b|\b(leave|keep)s? (the heading|it|the section) (empty|bare)\b" | grep -iE "\b(never|not|no)\b[^];]{0,25}(- None|\bNone\b|filler|placeholder|any (other )?(line|text|entry))" || true; }
for x in "wrap-it step 5|WRAP5" "resume-it save-state|RSAVE"; do
  check "${x%%|*}: the record placeholder says what goes there when the file has no section: the older left-out lines (read step 2), moved in" \
    "[ -n \"\$(r5_movein \"\$${x##*|}\")\" ] && ! r5_ph \"\$${x##*|}\" | r5_aff | gq -iE \"\$R5_REGEN\""
  check "${x%%|*}: the record placeholder says that with nothing left out, nothing goes under the heading -- never \"- None\" or any filler line" \
    "[ -n \"\$(r5_none \"\$${x##*|}\")\" ] && ! r5_ph \"\$${x##*|}\" | r5_aff | gq -iE \"\\bNone\\b|\\(none\\)|\\bN/?A\\b|\\bfiller\\b\""
done

# Minor 5: try-it save-state's template lines themselves (Result, Frontend URL, Test users) carry the left-out reading, not only
# the lead sentence: never All Passing, a localhost URL, or test users for an app a left-out item kept from starting
r5_tl() { printf "%s\n" "$TSAVE" | r5_tpl | awk -v k="- $1:" 'index($0,k)==1{on=1;print;next} on&&(/^- /||/^$/){exit} on' | flat; }
R5_TLX="$WAIVE|\\beven (if|when|though|while)\\b|\\bregardless\\b|\\banyway\\b|\\bwhether or not\\b|\\balways\\b|\\b(keep|still (write|give|list|show|record))\\b"
check "try-it save-state template: the Result line itself reads as the report's Status line (never a bare All Passing)" \
  'l=$(r5_tl Result); [ -n "$l" ] && { printf "%s\n" "$l" | r5_aff | gq -F "Status line" || { printf "%s\n" "$l" | gq -iE "All Passing[^]/;]{0,15}only (when|if) nothing is left out" && printf "%s\n" "$l" | gq -iE "item\(s\) left out|left out by your choice"; }; } && ! printf "%s\n" "$l" | r5_aff | gq -iE "$R5_TLX"'
check "try-it save-state template: the Frontend URL line itself gives no URL when a left-out item kept the app from starting (or reads as How to Access)" \
  'l=$(r5_tl "Frontend URL"); [ -n "$l" ] && { printf "%s\n" "$l" | r5_aff | gq -F "How to Access" || { printf "%s\n" "$l" | gq -iE "$KEPT" && printf "%s\n" "$l" | gq -iE "\b(none|no URL|omit|drop|leave (it|the line|this line) out|in place of|instead of)\b"; }; } && ! printf "%s\n" "$l" | r5_aff | gq -iE "$R5_TLX"'
check "try-it save-state template: the Test users line itself drops the sign-in users a left-out item removed (or reads as How to Access)" \
  'l=$(r5_tl "Test users"); [ -n "$l" ] && { printf "%s\n" "$l" | r5_aff | gq -F "How to Access" || { printf "%s\n" "$l" | gq -iE "(sign-in|sign in|log ?in|login)[^]]{0,80}left.out|left.out[^]]{0,80}(sign-in|sign in|log ?in|login)" && printf "%s\n" "$l" | gq -iE "\b(none|omit|drop|leave (it|them|the line|this line)? ?out|leaving out|in place of|instead of)\b"; }; } && ! printf "%s\n" "$l" | r5_aff | gq -iE "$R5_TLX"'

# ---- Task 5 adversarial round 1 ----
# #1/#2: an app retrofitted before the section existed. Its state file holds the line the older Part E wrote, with no section,
# and TODO.md holds the item's line. Read step 2 counts both. Every reader (Phase 6) goes by the read steps, and every write that
# starts the section (the plan pick, a check-in take-out, Part E) moves those lines in first, as the definition's Where says.
# #3: the record is written right after the snapshot, so a clean-tree re-run's snapshot makes no commit. #4: wrap-it loads it.
RA1_OLD="$(printf '%s\n' '# Project State -- Cafe Menu' '> Last updated: 2026-10-01 09:00' '> Last session: retrofit-it' '' \
  '## Retrofit' '- Retrofit completed (not initial build)' '- Risk score 28, single-pass' \
  '- Activity monitoring (who did what, and when) -- left out by your choice' '' '## Remaining TODOs' '- Add the weekly specials page')"
RA1_TODO="$(printf '%s\n' '# TODO' '' '- [ ] Activity monitoring -- left out by your choice: you keep your own note of who changed what' \
  '- [ ] Add the weekly specials page')"
RA1_NEW='- Notifications -- checks N01-N08 -- left out 2026-10-19'
RA1_OUT='- Secure login -- checks A01-A10 -- left out 2026-10-19 (taken out)'
# ra1_rs2 STATE TODO [sec]: the items read step 2 reads, one name per line (each line counted; "sec": the section alone). An
# older state file's lines count as RA1_STL gives them (owner call 1: the reading step 2's text gives, below)
ra1_rs2() { RA_S="$1" RA_T="$2" RA_O="${3:-}" RA_H="$SECTION" RA_L="$RA1_STL" perl -e '
  my ($s, $t, $o, $h, $l) = @ENV{qw(RA_S RA_T RA_O RA_H RA_L)}; my @i;
  sub nm { (my $l = shift) =~ s/^\s*-\s*(\[[ xX]\]\s*)?//; $l }
  if ($s =~ /^\Q$h\E\n((?:(?!## ).*(?:\n|\z))*)/m) { push @i, map { nm($_) } grep { /^- / } split /\n/, $1 }
  elsif (!$o) {
    push @i, map { nm($_) } grep { !/^#/ && /$l/i } split /\n/, $s;
    my $on = 0; for (split /\n/, $t) { if (/^#/) { $on = /left out by your choice/i; next } push @i, nm($_) if /\S/ && ($on || /left out by your choice/i) }
  }
  print "$_\n" for @i;'; }
# ra1_wr MODE MOVE STATE TODO NEW: STATE after a write that starts the section. MOVE=1: the older lines step 2 read (state file and
# TODO.md, one entry per item) are moved in first; MOVE=0: the section holds only NEW and the older line stays where it was.
# MODE "whole" (Part E) writes the file from its own list, so a line it doesn't carry is gone.
# ponytail: the fixtures here hold no section yet, so only the write that starts it is modelled
ra1_wr() { RA_M="$1" RA_V="$2" RA_S="$3" RA_N="$5" RA_H="$SECTION" RA_L="$RA1_STL" RA_I="$(ra1_rs2 "$3" "$4")" perl -e '
  my ($m, $v, $s, $n, $h, $i, $l) = @ENV{qw(RA_M RA_V RA_S RA_N RA_H RA_I RA_L)}; my (@e, %seen);
  $s =~ s/\n*\z/\n/;
  if ($v) {
    for (split /\n/, $i) { (my $k = $_) =~ s/ --.*//; (my $key = lc $k) =~ s/ \(.*//; push @e, "- $k -- checks none -- left out 2026-10-19" unless $seen{$key}++ }
    $s = join "", grep { /^#/ || !/$l/i } split /^/m, $s;
  }
  $s = "# Project State -- Cafe Menu\n\n## Current Status\nRetrofit completed (not initial build).\n" if $m eq "whole";
  push @e, $n if length $n;
  $s .= "\n$h\n\n" . join("", map { "$_\n" } @e) if @e;
  print $s;'; }
# ra1_mv UNITS: 1 when the write these units give moves the older lines in when it starts the section: a sentence (in a unit citing
# left-out-record.md) affirms moving the older / read-step-2 / TODO.md lines in, or points at the definition's Where rule. 0 when
# none does, or any says the opposite (without moving, the older lines left where they are), or it restates Where's own wording.
RA1_MVIN='\bmov(e|es|ed|ing)\b[^.;:]{0,60}\b(in|into)\b'
RA1_MVSRC='\bolder\b|\bread step 2\b|\bTODO'
RA1_WHERE='\*\*Where:?\*\*|\bWhere:?\*\*|\bWhere\b (rule|says|part|paragraph)\b|(.s|\bits) \*{0,2}Where\b'
RA1_MVX='\b(without|never|not|don.t|doesn.t|do not|does not|no)\b[^.;:]{0,20}\bmov(e|es|ed|ing)\b|\b(leave|leaves|leaving)\b[^.;:]{0,30}\bolder\b[^.;:]{0,40}(\bwhere\b|\bput\b|in place|as (they|it) (are|is))|\bolder\b[^.;:]{0,40}\b(left|kept|stay|stays|stayed|remain|remains)\b[^.;:]{0,15}(\bwhere\b|\bput\b|in place|as (they|it) (are|is))|\b(section|it)\b[^.;:]{0,20}\b(holds?|has|gets?|with)\b[^.;:]{0,10}\bonly\b[^.;:]{0,25}\b(new|this run.s|this pick.s)\b'
# "with none (yet)", "there is no section": a condition (which file), not a negation of the move-in after it
ra1_nosec() { perl -pe 's/\b(with|has|have|holds?|is|there.s) (none|no (such )?(section|heading))( yet)?\b/$1 NOSEC/gi'; }
ra1_mv() {
  local s a; s=$(printf "%s\n" "$1" | grep -F left-out-record.md | r5_sents | r5_md | ra1_nosec || true); a=$(printf "%s\n" "$s" | r5_aff)
  if [ -z "$s" ] || printf "%s\n" "$s" | gq -iE "$RA1_MVX" || printf "%s\n" "$1" | gq -iE "takes the date it is moved|first moves that file.s older left-out lines|adds the section, to an older file or in a new one"; then echo 0
  elif printf "%s\n" "$a" | grep -iE "$RA1_MVIN" | grep -iE "$RA1_MVSRC" | grep -viE "$T4_QUAL" | gq . || printf "%s\n" "$a" | gq -E "$RA1_WHERE"; then echo 1
  else echo 0; fi
}
RA1_TAKE='take[sn]?\b[^.;:]{0,25}\bout\b|taking[^.;:]{0,25}\bout\b'
RA1_PICK="$(r5_pickp)"
RA1_TAKEB="$(printf "%s\n%s\n" "$CHECKIN" "$EH_DIS" | r5_un | grep -F left-out-record.md | grep -iE "$RA1_TAKE" || true)"
RA1_PE="$(printf "%s\n" "$PARTE" | r5_un | grep -F "$SECTION" | grep -F left-out-record.md || true)"
# (owner call 1, after round 3) RA1_STL: the older state-file lines read step 2 counts (a perl regex), by what its text says. The
# old reading ("on another line", "each such line ... is an item too"), in what a sentence affirms: any line saying the phrase.
# Else each shape older skills wrote that a sentence counts in what it affirms (`- [item] -- left out by your choice`: the
# phrase right after " -- "; a [placeholder] matches any text). Else none.
# oc1_ss: step 2, one sentence per line, its `code` spans as tokens (SHAPE<n> for such a shape, CODE for any other)
OC1_SH='^- .*\[[^]]+\].* -- left out by your choice\b'
oc1_ss() { step $DEF 2 | flat | S="$OC1_SH" perl -pe 'my $i = 0; s/`([^`]*)`/my $c = $1; $c =~ m{$ENV{S}} ? "SHAPE" . ++$i : "CODE"/ge' | r5_md | ra1_nosec | r5_sents; }
# oc1_shp: "SHAPE<n> REGEX" for each such shape, numbered as oc1_ss numbers it
oc1_shp() { step $DEF 2 | flat | S="$OC1_SH" perl -ne 'my $i = 0; while (/`([^`]*)`/g) { my $c = $1; next unless $c =~ m{$ENV{S}}; $i++; print "SHAPE$i ^\\s*", join(".+", map { quotemeta } split /\[[^\]]*\]/, $c, -1), "\n" }'; }
# (a status line affirmed as counting, try-it's Result line among them, is that reading too)
OC1_STAT='\b(status|result) lines?\b'
OC1_ANY="\\bon (another|any|any other|some other|a different) line\\b|\\beach such line\\b|\\b(any|every) (other )?line\\b[^.;:]{0,40}\\b(says?|saying|with)\\b|\\banywhere in (the|that|an older|the older) (state )?file\\b|${OC1_STAT}[^.;:]{0,60}\\b(counts?|counted|is an item|are items|items? too)\\b"
OC1_CNT='\b(counts?|counted|reads?|read as)\b|\b(is|are) (an |one )?items?\b|\bitems? too\b|\bshapes?\b'
oc1_any() { oc1_ss | r5_aff | grep -iE "$OC1_ANY" || true; }
oc1_cnt() { oc1_ss | while IFS= read -r s; do a=$(printf "%s\n" "$s" | r5_aff); printf "%s\n" "$a" | gq -iE "$OC1_CNT" && { printf "%s\n" "$a" | grep -oE "SHAPE[0-9]+" || true; }; done; true; }
oc1_stl() { local r; if [ -n "$(oc1_any)" ]; then echo 'left out by your choice'; return; fi
  r=$(oc1_cnt | sort -u | while read -r n; do oc1_shp | awk -v n="$n" '$1==n{sub(/^[^ ]+ /, ""); print}'; done | paste -sd'|' -)
  [ -n "$r" ] && echo "$r" || echo '(?!)'; }
RA1_STL="$(oc1_stl)"
check "(control) read step 2 reads an older file's line, and TODO.md only while there is no section: on the older-format fixture it finds Activity monitoring on both lines, the section alone finds nothing" \
  's=$(step $DEF 2 | flat); printf "%s\n" "$s" | gq -F "Only while there is no section" && [ "$RA1_STL" != "(?!)" ] && [ "$(ra1_rs2 "$RA1_OLD" "$RA1_TODO" | grep -c "^Activity monitoring")" = 2 ] && [ -z "$(ra1_rs2 "$RA1_OLD" "" sec)" ]'

# #1: Phase 6's skip list is the record as left-out-record.md's read steps read it, never the section as it stands now alone
ra1_p6ok() {
  local s a; s=$(printf "%s\n" "$VERIFY6" | r5_ps | grep -iE "stays? out|\bskip" || true); a=$(printf "%s\n" "$s" | r5_aff)
  printf "%s\n" "$a" | grep -iE "\bread steps\b|\bread steps? [12]\b" | gq -F left-out-record_md &&
  ! printf "%s\n" "$a" | gq -iE "\b(only|just)\b[^.;:()]{0,10}.?$SECTION|$SECTION.?[^.;:()]{0,30}\b(alone|only)\b" &&
  ! printf "%s\n" "$s" | gq -iE "\bolder\b[^.;:]{0,50}\b(don.t|do not|doesn.t|does not|never|not|no longer)\b[^.;:]{0,10}\b(count|counts|apply|applies|matter|matters)\b" &&
  ! { printf "%s\n" "$s" | grep -iE "$SECTION.? as it (is|stands) now" | grep -viE "\bolder\b|\bno (such )?section\b|read step 2|before (it|the section) existed" | gq .; }
}
check "retrofit-it Phase 6 on the older-format record (re-run, nothing new left out): it skips by the record as left-out-record.md's read steps read it, so Activity monitoring's checks are skipped (never the section as it stands now alone)" \
  '{ if ra1_p6ok; then ra1_rs2 "$RA1_OLD" "$RA1_TODO"; else ra1_rs2 "$RA1_OLD" "" sec; fi; } | gq "^Activity monitoring"'
check "retrofit-it Part E on the older-format record (nothing new left out): the state file it writes holds Activity monitoring under the section, moved in as left-out-record.md's Where says, never dropped" \
  'o=$(ra1_wr whole "$(ra1_mv "$RA1_PE")" "$RA1_OLD" "$RA1_TODO" ""); printf "%s\n" "$o" | gq -xF "$SECTION" && ra1_rs2 "$o" "" | gq "^Activity monitoring"'
# #2: the plan pick and a check-in take-out start the section the same way (older lines and TODO.md items moved in first)
check "retrofit-it plan pick on the older-format record (re-run, Notifications left out): after its write, read step 2 finds both Activity monitoring and Notifications" \
  'i=$(ra1_rs2 "$(ra1_wr append "$(ra1_mv "$RA1_PICK")" "$RA1_OLD" "$RA1_TODO" "$RA1_NEW")" "$RA1_TODO"); printf "%s\n" "$i" | gq "^Activity monitoring" && printf "%s\n" "$i" | gq "^Notifications "'
check "retrofit-it check-in take-out on the older-format record (nothing new left out at the pick): after its write, read step 2 finds both Activity monitoring and the item taken out" \
  'i=$(ra1_rs2 "$(ra1_wr append "$(ra1_mv "$RA1_TAKEB")" "$RA1_OLD" "$RA1_TODO" "$RA1_OUT")" "$RA1_TODO"); printf "%s\n" "$i" | gq "^Activity monitoring" && printf "%s\n" "$i" | gq "^Secure login .*(taken out)"'

# #3: run on a scratch repo by the text's own order (the plan-pick record write, then the snapshot block, or the other way round).
# A re-run on main with the app's own no-commit-to-branch hook (VC02/Q12): clean tree, one new leave-out.
# ra1_order: what the record-write paragraph affirms ("before/after the snapshot"), else where it sits against the snapshot's lead
ra1_order() {
  local a; a=$(printf "%s\n" "$RA1_PICK" | r5_sents | r5_aff)
  if printf "%s\n" "$a" | gq -iE "\bbefore (making )?(the|its|this) snapshot\b"; then echo before
  elif printf "%s\n" "$a" | gq -iE "\bafter (making )?(the|its|this) snapshot\b|\bonce the snapshot\b"; then echo after
  else printf "%s\n" "$PLAN" | awk -v s="$SECTION" -v f="$STATE" 'BEGIN{RS=""} !n&&index($0,"make the snapshot if there is none yet"){n=NR} !r&&index($0,s)&&index($0,"left-out-record.md")&&index($0,f){r=NR} END{print ((n && r > n) ? "after" : "before")}'
  fi
}
# ra1_repo MODE ORDER: MODE clean | dirty (an unsaved change, so the snapshot must save and the hook refuses). Prints @@LAST and the
# block's last line, @@NOCOMMIT when the snapshot made no commit, @@WRITTEN when the record gained the new line, @@UNTOUCHED when the
# record is as it was (content and index). Isolated: its own temp folder, no global or system git config, no repo above it.
ra1_repo() (
  mode=$1 order=$2 todo=${3:-} rec=.make-it-state.md
  T=$(mktemp -d 2>/dev/null) && T=$(cd "$T" && pwd -P) || exit 0; trap 'rm -rf "$T"' EXIT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T" GIT_AUTHOR_NAME=t \
    GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
  mkdir -p "$T/cafe" && cd "$T/cafe" || exit 0
  # the first run: the record, its snapshot tag, then its upgrade, landed on main
  { git -c init.defaultBranch=main init -q && printf 'node_modules/\n' > .gitignore && printf 'v0\n' > app.py &&
    printf '# Project State -- Cafe\n\n## Left out by your choice\n\n- Activity monitoring -- checks L01-L08 -- left out 2026-10-01\n' > $rec &&
    git add -A && git commit -qm "before the first run" && git tag -a pre-retrofit-cafe -m "Snapshot before /retrofit-it changes" &&
    printf 'v1\n' > app.py && git commit -qam "the first run's upgrade"; } >/dev/null 2>&1 || { echo "@@SETUP"; exit 0; }
  # the app's own hook refuses any commit on main (a stand-in for no-commit-to-branch); proven before the run
  mkdir -p .git/hooks && printf '#!/bin/sh\n[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = main ] && { echo "no-commit-to-branch: Failed"; exit 1; }\nexit 0\n' > .git/hooks/pre-commit &&
    chmod +x .git/hooks/pre-commit || { echo "@@SETUP"; exit 0; }
  ! git commit -q --allow-empty -m probe >/dev/null 2>&1 || { echo "@@HOOK"; exit 0; }
  [ "$mode" != dirty ] || printf 'v1, plus a change not saved yet\n' > app.py
  head=$(git rev-parse HEAD) was=$(cat $rec)
  # (fix round 2) TODO = pick | record: the TODO.md leave-out line, at the pick (before the snapshot) or with the record write
  tl='- [ ] Notifications -- left out by your choice: you tell guests about the specials yourself'
  [ "$todo" != pick ] || printf '%s\n' "$tl" >> TODO.md
  if [ "$order" = before ]; then printf '%s\n' "$RA1_NEW" >> $rec; [ "$todo" != record ] || printf '%s\n' "$tl" >> TODO.md; o=$(bash -c "$R5_SNAP" 2>&1)
  else o=$(bash -c "$R5_SNAP" 2>&1); case $(printf '%s\n' "$o" | tail -n 1) in "snapshot: "*) printf '%s\n' "$RA1_NEW" >> $rec; [ "$todo" != record ] || printf '%s\n' "$tl" >> TODO.md;; esac
  fi
  echo "@@LAST $(printf '%s\n' "$o" | tail -n 1)"
  [ "$(git rev-parse HEAD)" != "$head" ] || echo "@@NOCOMMIT"
  [ "$(cat $rec)" != "$was
$RA1_NEW" ] || echo "@@WRITTEN"
  [ "$(cat $rec)" != "$was" ] || [ -n "$(git status --porcelain -- $rec)" ] || echo "@@UNTOUCHED"
  true
)
RA1_ORD="$(ra1_order)"
RA1_CLEAN="$(ra1_repo clean "$RA1_ORD")"; RA1_DIRTY="$(ra1_repo dirty "$RA1_ORD")"
check "retrofit-it re-run on main (clean tree, the app's no-commit-to-branch hook, one new leave-out), in the text's order: the snapshot succeeds and makes no commit, and the record is written after it" \
  '[ "$RA1_ORD" = after ] && printf "%s\n" "$RA1_CLEAN" | gq -E "^@@LAST snapshot: tag pre-retrofit-cafe " && printf "%s\n" "$RA1_CLEAN" | gq -xF "@@NOCOMMIT" && printf "%s\n" "$RA1_CLEAN" | gq -xF "@@WRITTEN"'
check "retrofit-it: when the snapshot fails (an unsaved change the hook won't let it save), the record is untouched in the text's order, so \"I haven't changed anything\" is true" \
  'printf "%s\n" "$PLAN" | gq -F "so I haven'"'"'t changed anything" && printf "%s\n" "$RA1_DIRTY" | gq -E "^@@LAST SNAPSHOT FAILED" && printf "%s\n" "$RA1_DIRTY" | gq -xF "@@UNTOUCHED"'

# #4: wrap-it loads the definition (its execution_context, by path), as try-it, resume-it and retrofit-it do
ra1_ec() { awk '/<execution_context>/{on=1;next} /<\/execution_context>/{exit} on' "$1"; }
check "wrap-it loads left-out-record.md in its execution_context, by the path try-it, resume-it and retrofit-it load it by" \
  'l=$(ra1_ec $TRY | grep -F left-out-record.md || true); [ -n "$l" ] && [ "$(ra1_ec $RESUME | grep -F left-out-record.md)" = "$l" ] && [ "$(ra1_ec $RETRO | grep -F left-out-record.md)" = "$l" ] && ra1_ec $WRAP | gq -xF -- "$l"'

# ---- Task 5 adversarial round 1b: the worktree gap ----
# The record is written in the folder the work runs in (`work`: the app folder, or its worktree; the app folder for a nested
# app), right after Phase 5 makes its branch or worktree and before its first step. A worktree is made from a commit, so a
# record left unsaved in the app folder never reaches it, and Phase 6 there would run (and Part A auto-fix) the item's checks.
# Run on a scratch repo in the text's order: the snapshot block, the branch or worktree (`git worktree add -b`, as
# worktree-workflow.md's helper does), the record write at the point and in the folder its paragraph gives, step 1
# (committed), then Phase 6's read (read step 2) in the folder the work runs in.
RB_ITEM='- Activity monitoring -- checks L01-L08 -- left out 2026-10-19'
# rb_where: the folder the record-write paragraph names -- work (the folder the work runs in: the app folder, or its worktree),
# worktree (the worktree alone), app (the app folder alone), or unnamed
RB_WORK='`work`|\bthe folder (the |your )?(retrofit |upgrade )?work (runs|is done|happens) in\b|\bwhere(ver)? the (retrofit |upgrade )?work runs\b|\bapp folder,? or (in )?(its|the|a) worktree\b|\bworktree,? or (in )?(the|its) app folder\b'
RB_WT='\b(in|into|inside|to) (the|its|that|this|the new|Phase 5.s) worktree\b'
RB_APP='\b(in|into|inside|to) (the|your|their|its) (own )?app folder\b|\b(in|into) (the user.s|their|your) own folder\b|\bAPP_DIR\b'
rb_where() {
  local a; a=$(printf "%s\n" "$RA1_PICK" | r5_sents | r5_aff)
  if printf "%s\n" "$a" | gq -iE "$RB_WORK"; then echo work
  elif printf "%s\n" "$a" | gq -iE "$RB_WT"; then if printf "%s\n" "$a" | gq -iE "$RB_APP"; then echo work; else echo worktree; fi
  elif printf "%s\n" "$a" | gq -iE "$RB_APP"; then echo app
  else echo unnamed; fi
}
# rb_when: after-bw (after the branch or worktree is made, and before the first step), late (after it, with nothing placing it
# before the first step), or before-bw (nothing places it after: "right after the snapshot and before Phase 5")
RB_BW='(the |its |a |their |Phase 5.s )?(new )?(branch|worktree)( or (a |the |its )?(branch|worktree)|/worktree|/branch)?'
RB_AFTER="\\b(after|once|when)\\b ${RB_BW} (is |are |has been |have been |gets |get )?(made|created|set up|ready|in place)\\b|\\b(after|once|when)\\b[^.;:]{0,30}\\b(made|makes|make|created|creates|create|sets? up)\\b ${RB_BW}\\b"
RB_FIRST='\bbefore\b[^.;:]{0,30}\b(first|1st) (retrofit )?step\b|\bbefore step 1\b|\bright after\b[^.;:]{0,30}\b(branch|worktree)\b'
rb_when() {
  local a; a=$(printf "%s\n" "$RA1_PICK" | r5_sents | r5_aff)
  if printf "%s\n" "$a" | gq -iE "$RB_AFTER"; then if printf "%s\n" "$a" | gq -iE "$RB_FIRST"; then echo after-bw; else echo late; fi
  else echo before-bw; fi
}
# Phase 5's execution model still makes the branch or worktree the order above is measured against
RB_EXEC="$(stepof $RETRO retrofit | r5_pa | grep -F '**Execution model:**' || true)"
RB_WHERE="$(rb_where)"; RB_WHEN="$(rb_when)"
# where the scratch run writes the record: before the snapshot (the paragraph says so, as before 4db43bd), before the branch or
# worktree, after it, or after step 1
case $RB_WHEN in after-bw) RB_POS=post-bw;; late) RB_POS=post-step1;; *) [ "$RA1_ORD" = before ] && RB_POS=pre-snap || RB_POS=pre-bw;; esac
# rb_repo MODE: MODE worktree | branch | nested (first run, Activity monitoring left out). Prints @@BEFORE1 and the items Phase
# 6's read would find in the work folder just before step 1, then @@P6 and what it finds there after step 1; @@NOWHERE when the
# paragraph names a folder this mode doesn't have, @@NOFOLDER when it writes into a worktree not made yet. A paragraph that
# names no folder writes where the snapshot just ran (the app folder). Isolated: its own temp folder, no global or system git
# config, no repo above it.
rb_repo() (
  mode=$1 rec=.make-it-state.md
  T=$(mktemp -d 2>/dev/null) && T=$(cd "$T" && pwd -P) || exit 0; trap 'rm -rf "$T"' EXIT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T" GIT_AUTHOR_NAME=t \
    GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
  A="$T/proj/cafe"; W=$A; mkdir -p "$A" && cd "$T/proj" || exit 0
  [ "$mode" = nested ] || cd "$A"
  { git -c init.defaultBranch=main init -q && printf 'node_modules/\n' > .gitignore && printf 'v0\n' > "$A/app.py" &&
    git add -A && git commit -qm init; } >/dev/null 2>&1 || { echo "@@SETUP"; exit 0; }
  cd "$A"; [ "$mode" != worktree ] || W="$T/proj/cafe-worktrees/retrofit"
  rb_write() { local f=$A
    case $RB_WHERE in work) f=$W;; worktree) [ "$mode" = worktree ] && f=$W || { echo "@@NOWHERE"; return 0; };; esac
    [ -d "$f" ] || { echo "@@NOFOLDER"; return 0; }   # the text writes into a worktree not made yet
    printf '# Project State -- Cafe\n\n%s\n\n%s\n' "$SECTION" "$RB_ITEM" > "$f/$rec"; }
  [ "$RB_POS" != pre-snap ] || rb_write
  o=$(bash -c "$R5_SNAP" 2>&1); case $(printf '%s\n' "$o" | tail -n 1) in "snapshot: "*) ;; *) echo "@@SNAP $o"; exit 0;; esac
  [ "$RB_POS" != pre-bw ] || rb_write
  case $mode in worktree) git worktree add -q -b retrofit "$W" HEAD;; branch) git switch -q -c retrofit;; esac >/dev/null 2>&1 ||
    { echo "@@BW"; exit 0; }
  [ "$RB_POS" != post-bw ] || rb_write
  echo "@@BEFORE1"; ra1_rs2 "$(cat "$W/$rec" 2>/dev/null)" "$(cat "$W/TODO.md" 2>/dev/null)"
  cd "$W" && printf 'v1\n' > app.py && printf 'one\n' > step1.txt || { echo "@@STEP1"; exit 0; }
  [ "$mode" = nested ] || { git add -A && git commit -qm "step 1"; } >/dev/null 2>&1 || { echo "@@STEP1"; exit 0; }
  [ "$RB_POS" != post-step1 ] || rb_write
  echo "@@P6"; ra1_rs2 "$(cat "$W/$rec" 2>/dev/null)" "$(cat "$W/TODO.md" 2>/dev/null)"
  # (fix round 2) what a re-run in the user's own folder reads there
  echo "@@APP"; ra1_rs2 "$(cat "$A/$rec" 2>/dev/null)" "$(cat "$A/TODO.md" 2>/dev/null)"
  # (fix round 3) EXT: parte = on to Part E (its write in the folder it names, the section kept), then what /try-it reads in the
  # folder Part E invokes it in (@@TRY) and read step 2 in the folder Phase 7 sends the user to (@@P7); rerun = "Stop here",
  # then /retrofit-it again in the folder that line names: Phase 4's read (@@RE4), its snapshot (@@RESNAP), the new leave-out
  # added below the lines there, Phase 6's read (@@RE6). Folders: F3_PE, F3_TRY, F3_P7W, F3_STOP (work | app).
  case ${2:-} in
    parte) f=$A; [ "$F3_PE" != work ] || f=$W; printf '\n## Retrofit\n- Retrofit completed (not initial build)\n' >> "$f/$rec"
      f=$A; [ "$F3_TRY" != work ] || f=$W; echo "@@TRY"; ra1_rs2 "$(cat "$f/$rec" 2>/dev/null)" "$(cat "$f/TODO.md" 2>/dev/null)"
      f=$A; [ "$F3_P7W" != work ] || f=$W; echo "@@P7"; ra1_rs2 "$(cat "$f/$rec" 2>/dev/null)" "$(cat "$f/TODO.md" 2>/dev/null)";;
    rerun) f=$A; [ "$F3_STOP" != work ] || f=$W; cd "$f" || exit 0
      echo "@@RE4"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)"
      o=$(bash -c "$R5_SNAP" 2>&1); echo "@@RESNAP $(printf '%s\n' "$o" | tail -n 1)"
      if [ -f $rec ]; then printf '%s\n' "$RA1_NEW" >> $rec; else printf '# Project State -- Cafe\n\n%s\n\n%s\n' "$SECTION" "$RA1_NEW" > $rec; fi
      echo "@@RE6"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)";;
    # (adversarial round 2) rebranch = branch mode's "Stop here" (the app folder, on the branch), then /retrofit-it again there:
    # Phase 4's read, its snapshot, Phase 5's branch from the base the text names (A2_BASE), the new leave-out added below the lines
    # there, the app's file (@@REAPP) and Phase 6's read (@@RE6) on that branch
    rebranch) cd "$A" || exit 0
      echo "@@RE4"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)"
      o=$(bash -c "$R5_SNAP" 2>&1); echo "@@RESNAP $(printf '%s\n' "$o" | tail -n 1)"
      if [ "$A2_BASE" = head ]; then git switch -q -c retrofit-2; else git switch -q -c retrofit-2 main; fi >/dev/null 2>&1 || { echo "@@REBW"; exit 0; }
      if [ -f $rec ]; then printf '%s\n' "$RA1_NEW" >> $rec; else printf '# Project State -- Cafe\n\n%s\n\n%s\n' "$SECTION" "$RA1_NEW" > $rec; fi
      echo "@@REAPP $(cat app.py 2>/dev/null)"
      echo "@@RE6"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)";;
    # (fix round 4) wtrerun = worktree mode's "Stop here", then /retrofit-it again in the folder that line names: Phase 4's read,
    # its snapshot (@@KIND first when it made a new tag: a first run by the text's definition, else rerun), Phase 5's new worktree
    # from the base the Execution model gives a run of that kind (f4_base), the new leave-out added below the lines there, the
    # new work folder's app file (@@REAPP) and Phase 6's read there (@@RE6)
    wtrerun) f=$A; [ "$F3_STOP" != work ] || f=$W; cd "$f" || exit 0
      echo "@@RE4"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)"
      n=$(git tag | wc -l); o=$(bash -c "$R5_SNAP" 2>&1); echo "@@RESNAP $(printf '%s\n' "$o" | tail -n 1)"
      k=rerun; [ "$(git tag | wc -l)" = "$n" ] || k=first; echo "@@KIND $k"
      W2="$T/proj/cafe-worktrees/retrofit-2"; b=main; [ "$(f4_base $k)" != head ] || b=HEAD
      git worktree add -q -b retrofit-2 "$W2" $b >/dev/null 2>&1 && cd "$W2" || { echo "@@REBW"; exit 0; }
      if [ -f $rec ]; then printf '%s\n' "$RA1_NEW" >> $rec; else printf '# Project State -- Cafe\n\n%s\n\n%s\n' "$SECTION" "$RA1_NEW" > $rec; fi
      echo "@@REAPP $(cat app.py 2>/dev/null)"
      echo "@@RE6"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)";;
  esac
)
RB_WTO="$(rb_repo worktree)"; RB_BRO="$(rb_repo branch)"; RB_NEO="$(rb_repo nested)"
# rb_ok OUT: the paragraph names the folder, the run got through, the work folder holds the record just before step 1, and
# Phase 6's read there finds the item
rb_at() { printf "%s\n" "$1" | awk -v k="@@$2" '$0==k{on=1;next} /^@@/{on=0} on'; }
rb_ok() { [ "$RB_WHERE" != unnamed ] && ! printf "%s\n" "$1" | gq -E "^@@(SETUP|SNAP|BW|STEP1|NOWHERE|NOFOLDER)" &&
  rb_at "$1" BEFORE1 | gq "^Activity monitoring " && rb_at "$1" P6 | gq "^Activity monitoring "; }
check "retrofit-it in worktree mode, in the text's order (snapshot, worktree, record write, step 1, Phase 6's read): the worktree's $STATE holds the record before step 1, and Phase 6's read there finds the left-out item" \
  'rb_ok "$RB_WTO"'
check "retrofit-it in branch mode (same folder), in the text's order: the record is written after the branch is made, it is in the app folder before step 1, and Phase 6's read there finds the left-out item" \
  '[ "$RB_WHEN" = after-bw ] && rb_ok "$RB_BRO"'
check "retrofit-it on a nested app (no branch or worktree), in the text's order: the record is written in the app folder itself, the folder the work runs in, before step 1, and Phase 6's read there finds the left-out item" \
  'rb_ok "$RB_NEO"'
# the text: the write names that folder, and no sentence puts it in the app folder alone when the work runs in a worktree
rb_appx() { printf "%s\n%s\n" "$RA1_PICK" "$RB_EXEC" | r5_sents | grep -iE "\bworktree\b" | while IFS= read -r s; do
    a=$(printf "%s\n" "$s" | r5_aff)
    if printf "%s\n" "$a" | gq -iE "$RB_APP" && ! printf "%s\n" "$a" | gq -iE "$RB_WORK|$RB_WT"; then printf "%s\n" "$s"; fi
  done; true; }
check "retrofit-it: the record write names the folder the work runs in (\`work\`, or the worktree), never the app folder alone when the work runs in a worktree" \
  '{ [ "$RB_WHERE" = work ] || [ "$RB_WHERE" = worktree ]; } && [ -z "$(rb_appx)" ]'
check "retrofit-it: the record write comes after Phase 5's branch or worktree is made and before Phase 5's first step" \
  'printf "%s\n" "$RB_EXEC" | gq -iE "branch/worktree|branch or (a |the )?worktree" && [ "$RB_WHEN" = after-bw ]'

# ---- Task 5 fix round 2 ----
# I-1: Phase 5's Execution model itself triggers the plan step's record write (**Then write the record**) once the branch or
# worktree is made, before the first step, so an agent following Phase 5 (and its /subagent-it handoff) never has to carry a
# Phase 4 note across. I-2: worktree-mode "Stop here" names /retrofit-it as working in [WORKTREE_DIR] (run there), so a re-run
# reads the record where it was written. Minors: each write that starts the section says TODO.md items move in too; the
# take-out, the bring-back, Phase 6's read and Part E name the folder the work runs in; the TODO.md leave-out line goes with
# the record, after the snapshot; Part E writes no filler line when nothing is left out.
F2_EXEC="$(between $RETRO '**Execution model:**' '**Strategy selection' | r5_ps)"
f2_trig() { printf "%s\n" "$F2_EXEC" | grep -F "Then write the record" | r5_md || true; }
F2_AFTER="$RB_AFTER|\\b(after|once)\\b (making|creating|setting up) ${RB_BW}\\b"
# too late: once a step (or the last) is done, after step 1 or Phase 5, at Part E or Phase 6 (read after f2_early drops "before the first step")
F2_LATE='\b(after|once|when|until)\b[^.;:]{0,40}\b((last|final|first|1st|every|each|all( the)?|a|the|its) (retrofit )?steps?|step [0-9]+)\b[^.;:]{0,30}\b(done|committed|finished|complete|completed|ends?|ended|ran|passed)\b|\bafter (step [0-9]|the (first|last|final) step|Phase 5|the retrofit|the upgrade|the check-?ins?)\b|\b(at|in|during|until|by) (Part E|Phase 6|the end|verification)\b'
f2_early() { perl -pe 's/\bbefore\b[^.;:,()]{0,40}?\b(steps?( [0-9]+)?|Phase 5)\b//gi'; }
# where an agent following the Execution model alone writes the record: never (no trigger), post-bw, post-step1 (late), pre-bw
f2_pos() { local a; a=$(f2_trig | r5_aff)
  if [ -z "$(printf "%s" "$a" | tr -d '[:space:]')" ]; then echo never
  elif printf "%s\n" "$a" | f2_early | gq -iE "$F2_LATE"; then echo post-step1
  elif printf "%s\n" "$a" | gq -iE "$F2_AFTER"; then echo post-bw
  else echo pre-bw; fi; }
check "retrofit-it Phase 5's Execution model itself triggers the record write (**Then write the record**): once the branch or worktree is made and before the first step, never later" \
  'a=$(f2_trig | r5_aff); printf "%s\n" "$a" | gq -iE "$F2_AFTER" && printf "%s\n" "$a" | gq -iE "$RB_FIRST" && ! printf "%s\n" "$a" | f2_early | gq -iE "$F2_LATE"'
F2_POS="$(f2_pos)"; F2_WTO="$(RB_POS=$F2_POS; rb_repo worktree)"
check "retrofit-it in worktree mode by Phase 5's Execution model alone (snapshot, worktree, the record write it triggers, step 1, Phase 6's read): the worktree holds the record before step 1, and Phase 6's read there finds the left-out item" \
  'rb_ok "$F2_WTO"'

# I-2: the worktree line of "Stop here" (what the user is told), one clause per line (". ", "; ", " -- ")
f2_wtstop() { printf "%s\n" "$CHECKIN" | r5_pa | grep -F "**Stop here:**" | perl -ne 'print "$1\n" if /\[work in a worktree:\s*(.*?)\]\s*(\[nested|\[After|$)/' | perl -pe 's/(\. |; | -- )/\n/g' || true; }
F2_THERE='(\bthere\b|\b(in|from|inside) \[WORKTREE_DIR\])'
F2_OWN='\byour own folder\b|\[APP_DIR\]|\b(the|your) app folder\b'
f2_stopok() { local c a; c=$(f2_wtstop); a=$(printf "%s\n" "$c" | r5_aff)
  printf "%s\n" "$c" | gq -F /resume-it && printf "%s\n" "$c" | gq -F /ship-it &&
  printf "%s\n" "$a" | gq -iE "/retrofit-it\b[^.;]{0,60}\b(work|works|run|runs|working|running)\b[^.;]{0,25}$F2_THERE|\b(run|use|type|start)\b[^.;]{0,40}/retrofit-it\b[^.;]{0,60}$F2_THERE|\b(in|from) \[WORKTREE_DIR\][^.;]{0,40}/retrofit-it\b" &&
  ! printf "%s\n" "$a" | gq -iE "/retrofit-it\b[^.;]{0,80}($F2_OWN)|($F2_OWN)[^.;]{0,60}/retrofit-it\b"; }
check "retrofit-it \"Stop here\" in worktree mode: names /retrofit-it too (with /resume-it and /ship-it) as working in [WORKTREE_DIR], run there, never in the user's own folder" 'f2_stopok'
# (fix round 3) and the re-run itself runs there: its snapshot, the new leave-out added below the record's line, Phase 6's read
F3_STOP="$(f2_stopok && echo work || echo app)"; F3_RRO="$(rb_repo worktree rerun)"
f3_reok() { rb_ok "$1" && rb_at "$1" RE4 | gq "^Activity monitoring " && printf "%s\n" "$1" | gq -E "^@@RESNAP snapshot: " &&
  rb_at "$1" RE6 | gq "^Activity monitoring " && rb_at "$1" RE6 | gq "^Notifications "; }
check "retrofit-it worktree-mode \"Stop here\", then /retrofit-it again in the folder that line names (scratch repo): its first read of the record finds the left-out item, and the re-run there (its snapshot, a new leave-out added, Phase 6's read) finds both" \
  'rb_ok "$RB_WTO" && if f2_stopok; then rb_at "$RB_WTO" P6; else rb_at "$RB_WTO" APP; fi | gq "^Activity monitoring " && f3_reok "$F3_RRO"'

# Minor 1: an older file whose item is only in TODO.md (an older /resume-it wrote only there)
F2_TODO="$(printf '%s\n' "$RA1_TODO" '- [ ] Daily sales report -- left out by your choice: you total the till by hand')"
# f2_mvwhat UNITS: what the write these units give moves in when it starts the section, by the gloss beside its pointer: both
# (the older lines and the TODO.md items, or a bare **Where** pointer with no gloss), older (the older state-file lines alone), none
f2_mvwhat() { local s g; s=$(printf "%s\n" "$1" | grep -F left-out-record.md | r5_sents | r5_md | ra1_nosec | r5_aff || true)
  g=$(printf "%s\n" "$s" | grep -iE "$RA1_MVIN" | grep -iE "$RA1_MVSRC" || true)
  if [ -n "$g" ]; then
    if printf "%s\n" "$g" | gq -iE "\bTODO[a-z_]*( (items?|lines?|ones?))?,? (are |is )?(left|kept|stay|stays|staying|remain|remains)\b[^.;:()]{0,10}\b(where|behind|out|in place|as (they|it) (are|is))\b|\b(leave|leaves|leaving|keep|keeps|keeping) (the )?TODO[a-z_]*( (items?|lines?))? (where|behind|out|in place|as (they|it) (are|is))\b"; then echo older
    elif printf "%s\n" "$g" | gq -iE "\bolder\b[^.;:()]{0,40}\bTODO|\bTODO[^.;:()]{0,40}\b(older|mov)|\bmov[a-z]*\b[^.;:()]{0,40}\bTODO|\bread step 2\b"; then echo both; else echo older; fi
  elif printf "%s\n" "$s" | gq -E "$RA1_WHERE"; then echo both
  else echo none; fi; }
f2_mvwr() { case $2 in both) ra1_wr "$1" 1 "$RA1_OLD" "$F2_TODO" "$3";; older) ra1_wr "$1" 1 "$RA1_OLD" "" "$3";; *) ra1_wr "$1" 0 "$RA1_OLD" "$F2_TODO" "$3";; esac; }
# f2_tdok MODE UNITS NEW: read step 2 finds the TODO.md-only item before the write, and in the section the write starts
f2_tdok() { local o; o=$(f2_mvwr "$1" "$(f2_mvwhat "$2")" "$3"); ra1_rs2 "$RA1_OLD" "$F2_TODO" | gq "^Daily sales report" &&
  ra1_rs2 "$o" "" sec | gq "^Daily sales report" && ra1_rs2 "$o" "" sec | gq "^Activity monitoring"; }
check "retrofit-it plan pick, the gloss beside its **Where** pointer moves the older lines AND the TODO.md items in: on a fixture with a TODO.md-only item, read step 2 finds it in the new section after the write" \
  'f2_tdok append "$RA1_PICK" "$RA1_NEW"'
check "retrofit-it Part E, the same gloss: on that fixture, read step 2 finds the TODO.md-only item in the section Part E starts" \
  'f2_tdok whole "$RA1_PE" ""'
check "retrofit-it check-in take-out, the same gloss: on that fixture, read step 2 finds the TODO.md-only item in the section the take-out starts" \
  'f2_tdok append "$RA1_TAKEB" "$RA1_OUT"'

# Minor 2: each record read and write names the folder the work runs in, never the app folder alone in a worktree
F2_TOUT="$(printf "%s\n" "$EH_DIS" | r5_un | grep -iE "$RA1_TAKE" | grep -F left-out-record.md || true)"
F2_BACK="$(printf "%s\n" "$CHECKIN" | r5_pa | perl -ne 'print "$1\n" if /\*\*Fix something first:\*\*(.*?)\*\*Stop here:\*\*/' || true)"
F2_APP='\b(the|your|their|its) (own )?app folder\b|\b(the user.s|their|your) own folder\b|\bAPP_DIR\b'
F2_APPX="($F2_APP)[^.;]{0,60}\\b(even|still|always)\\b[^.;]{0,40}\\bworktree\\b|\\bworktree\\b[^.;]{0,60}\\b(still|always|even)\\b[^.;]{0,40}($F2_APP)"
f2_folder() { local s a; s=$(printf "%s\n" "$1" | flat | r5_sents | r5_md); a=$(printf "%s\n" "$s" | r5_aff)
  printf "%s\n" "$a" | gq -iE "$RB_WORK" && ! printf "%s\n" "$a" | gq -iE "$F2_APPX" &&
  [ -z "$(printf "%s\n" "$s" | grep -iE "\bworktree\b" | while IFS= read -r x; do y=$(printf "%s\n" "$x" | r5_aff)
    if printf "%s\n" "$y" | gq -iE "$F2_APP" && ! printf "%s\n" "$y" | gq -iE "$RB_WORK|$RB_WT"; then echo x; fi; done)" ]; }
for x in "check-in take-out (error-handling)|F2_TOUT" "check-in bring-back (\"Fix something first\", read step 4)|F2_BACK" "Phase 6 read of the record|SKIP" "Part E write of the state file|SAVE"; do
  check "retrofit-it ${x%%|*}: names the folder the work runs in (\`work\`), never the app folder alone when the work runs in a worktree" \
    "[ -n \"\$${x##*|}\" ] && f2_folder \"\$${x##*|}\""
done

# Minor 3: the plan step's TODO.md leave-out line: "record" when each sentence that writes it ties it to the record write (or
# sits in that paragraph), "pick" when any is at the pick or gives no time (it then sits in the pick paragraph), "none"
F2_TODOW='\b(go|goes|going|gone|written|write|writes|add|adds|added|list|lists|listed|put|puts|note|notes|noted)\b[^.;:]{0,20}\b(to|in|into|on) TODO_md\b'
F2_WITHREC='Then write the record|\b(with|alongside) the record\b|\bwhen (you write |it writes |writing )?the record\b|\bsame (time|place|folder|moment|point) as the record\b'
F2_AFTERSNAP='\bafter (making |taking )?(the|its|this) snapshot\b|\bonce the snapshot\b'
F2_TODONOW='\b(at|on|right at|right after) the (plan )?pick\b|\b(right away|immediately|at once)\b|\bbefore (making )?(the|its|this) snapshot\b'
f2_todopos() { local r
  r=$(printf "%s\n" "$PLAN" | r5_ps | r5_md | grep -E "TODO_md" | grep -iE "$LO" | grep -iE "$F2_TODOW" | while IFS= read -r s; do
    a=$(printf "%s\n" "$s" | r5_aff)
    if printf "%s\n" "$a" | gq -iE "$F2_TODONOW"; then echo pick
    elif printf "%s\n" "$a" | gq -iE "$F2_WITHREC" || { printf "%s\n" "$a" | gq -iE "$F2_AFTERSNAP" && printf "%s\n" "$a" | gq -iE "$RB_WORK"; } ||
      printf "%s\n" "$RA1_PICK" | r5_sents | r5_md | gq -xF -- "$s"; then echo record
    else echo pick; fi; done || true)
  case $r in "") echo none;; *pick*) echo pick;; *) echo record;; esac; }
F2_TPOS="$(f2_todopos)"; F2_TCLEAN="$(ra1_repo clean "$RA1_ORD" "$F2_TPOS")"
check "retrofit-it: the TODO.md leave-out line is written with the record (after the snapshot, in the folder the work runs in), never at the pick -- on the hooked clean-tree re-run, in the text's order, the snapshot succeeds and makes no commit" \
  '[ "$F2_TPOS" = record ] && printf "%s\n" "$F2_TCLEAN" | gq -E "^@@LAST snapshot: tag pre-retrofit-cafe " && printf "%s\n" "$F2_TCLEAN" | gq -xF "@@NOCOMMIT"'

# Minor 4: Part E's left-out bullet, one clause per line ("; ", ". ")
f2_pecl() { printf "%s\n" "$BULLET" | flat | r5_md | sed 's/; /;\
/g; s/\. /.\
/g'; }
F2_NONE='\bnothing (is |was )?(left out|in it)\b|\bno (items?|entries|lines?|leave-outs?) (is |are |were )?left out\b|\bnone (is |are |were )?left out\b|\bnothing to record\b'
F2_NOSEC='\b(no|write no|never write|don.t write|do not write|skip|omit|leave out)( the| a| that| its)? (section|heading)\b'
F2_EMPTY="\\bnothing\\b[^;]{0,25}\\b(under|below|beneath|after)\\b|\\bno (lines?|entries|text) (under|below)\\b|\\bjust the heading\\b|\\bthe heading (alone|only|on its own|by itself)\\b|$F2_NOSEC"
F2_NOFILL='\b(never|not|no|don.t|do not|without)\b[^;]{0,25}(- None|\bNone\b|\bfiller\b|\bplaceholder\b|any (other )?(line|text|entry))'
F2_FILL='\(none\)|- None|\bN/A\b|\bfiller\b|\bplaceholder\b|"None"|`None`'
f2_pefill() { f2_pecl | while IFS= read -r c; do
    if printf "%s\n" "$c" | gq -iE "$F2_FILL" && ! printf "%s\n" "$c" | gq -iE "$F2_NOFILL"; then printf "%s\n" "$c"; fi; done; true; }
check "retrofit-it Part E: with nothing left out it writes nothing under the heading (or no section) -- never \"- None\" or any filler line" \
  'c=$(f2_pecl | grep -iE "$F2_NONE" | grep -iE "$F2_EMPTY" || true); [ -n "$c" ] && { printf "%s\n" "$c" | gq -iE "$F2_NOFILL" || printf "%s\n" "$c" | gq -iE "$F2_NOSEC"; } && [ -z "$(f2_pefill)" ]'

# ---- Task 5 fix round 3 ----
# I-1 (review 4): in worktree mode the completion handoff names where the upgrade is. Phase 7 gives "Stop here"'s worktree
# bracket ([WORKTREE_DIR] has the upgrade; /ship-it, /resume-it and /retrofit-it run there), and Part E invokes /try-it in
# `work`. Then a scratch run to Part E, and a read in the folders /try-it and Phase 7 name. Minors: the record write and Phase 5's
# trigger name the TODO.md leave-out line; after an undo, the TODO.md leave-out lines come back from the record; and review 4's
# seven polarity mutants each fail a check (those seven checks pass today).
# the [work in a worktree: '...'] bracket of TEXT (its own [..] kept whole), one clause per line (". ", "; ", " -- ")
f3_wtb() { printf "%s\n" "$1" | flat | perl -ne 'while (/\[work in a worktree:\s*((?:[^\[\]]++|(\[(?:[^\[\]]++|(?2))*\]))*)\]/g) { print "$1\n" }' | perl -pe 's/(\. |; | -- )/\n/g'; }
F3_SHIP="$(stepof $RETRO ship-handoff)"
F3_CMDS='/ship-it|/resume-it|/retrofit-it'
f3_p7ok() { local c a x; c=$(f3_wtb "$F3_SHIP"); a=$(printf "%s\n" "$c" | r5_aff)
  printf "%s\n" "$a" | gq -iE "\bupgrade[a-z]*\b[^.;]{0,60}\[WORKTREE_DIR\]|\[WORKTREE_DIR\][^.;]{0,60}\bupgrade" || return 1
  for x in /ship-it /resume-it /retrofit-it; do printf "%s\n" "$a" | gq -iE "$x\b[^.;]{0,60}$F2_THERE|\b(in|from) \[WORKTREE_DIR\][^.;]{0,60}$x\b" || return 1; done
  ! printf "%s\n" "$a" | gq -iE "($F3_CMDS)\b[^.;]{0,80}($F2_OWN)|($F2_OWN)[^.;]{0,60}($F3_CMDS)\b"; }
check "retrofit-it Phase 7 in worktree mode: gives \"Stop here\"'s worktree bracket -- the upgrade is in [WORKTREE_DIR], and /ship-it, /resume-it and /retrofit-it run there, never in the user's own folder" 'f3_p7ok'
# a folder offered as an alternative to `work` ("in `work` or the app folder, whichever you are in")
F3_WORK="$RB_WORK|\\bthe folder (the |your )?(retrofit |upgrade )?work (ran|was done|happened) in\\b"
F3_ALT="(\`work\`|\\bthe folder (the )?work (runs|ran) in\\b)[^.;]{0,15}\\bor\\b[^.;]{0,20}($F2_APP)|($F2_APP)[^.;]{0,15}\\bor\\b[^.;]{0,20}\`work\`|\\bwhichever\\b|\\beither (folder|one|place)\\b|\\bwherever you are\\b"
f3_try() { printf "%s\n" "$PARTE" | r5_pa | r5_sents | r5_md | grep -iE "\binvok[a-z]*\b[^.;:]{0,30}/try-it|/try-it\b[^.;:]{0,30}\b(runs?|ran|starts?)\b" || true; }
f3_tryok() { local s a; s=$(f3_try); a=$(printf "%s\n" "$s" | r5_aff)
  [ -n "$s" ] && printf "%s\n" "$a" | gq -iE "$F3_WORK" && ! printf "%s\n" "$a" | gq -iE "$F2_APPX|$F3_ALT" && ! { printf "%s\n" "$a" | grep -iE "$F2_APP" | grep -viE "$RB_WORK" | gq .; }; }
check "retrofit-it Part E: invokes /try-it in \`work\` (the folder the work ran in), never the app folder alone" 'f3_tryok'
F3_PE="$(f2_folder "$SAVE" && echo work || echo app)"; F3_TRY="$(f3_tryok && echo work || echo app)"; F3_P7W="$(f3_p7ok && echo work || echo app)"
F3_PTO="$(rb_repo worktree parte)"
check "retrofit-it in worktree mode, run to Part E with no \"Stop here\" (scratch repo, the text's order), then /try-it in the folder Part E names and read step 2 in the folder Phase 7 sends the user to: the record is in both" \
  'rb_ok "$F3_PTO" && rb_at "$F3_PTO" TRY | gq "^Activity monitoring " && rb_at "$F3_PTO" P7 | gq "^Activity monitoring "'

# Minor 1: the record write and Phase 5's trigger name the TODO.md leave-out line (the move-in gloss, about older items, aside)
f3_nomv() { perl -pe 's/\([^()]*\bmov(e|es|ed|ing)\b[^()]*\)//g; s/[^.;:()]*\bTODO_md\b[^.;:()]*\bmov(e|es|ed|ing)\b[^.;:()]*//g; s/[^.;:()]*\bmov(e|es|ed|ing)\b[^.;:()]*\bTODO_md\b[^.;:()]*//g'; }
F3_TDV='\b(go|goes|going|write|writes|writing|written|add|adds|adding|added|put|puts|list|lists|listed)\b'
F3_TDL='\bTODO_md\b[^.;:]{0,40}\b(lines?|entr(y|ies)|left out|leave-outs?)\b|\b(lines?|entr(y|ies)|left out|leave-outs?|left-out)\b[^.;:]{0,40}\bTODO_md\b'
F3_HOLD='\b(later|wait|waits|waiting|hold|holds|holding|afterwards?|postpone[sd]?|defer[a-z]*)\b|\bat the (plan )?pick\b|\b(at|in|during|until|by|for) (Part E|Phase 6|the end|verification)\b|\bafter (step [0-9]|the (first|last|final) step|the check-?ins?)\b'
# stdin: sentences. 0 when one affirms a write that names the TODO.md leave-out line, and none puts that line off
f3_tdm() { local a; a=$(r5_md | f3_nomv | r5_aff | grep -F TODO_md || true)
  printf "%s\n" "$a" | gq -iE "$F3_TDV" && printf "%s\n" "$a" | gq -iE "$F3_TDL" && ! printf "%s\n" "$a" | gq -iE "$F3_HOLD"; }
check "retrofit-it plan step, **Then write the record**: names the TODO.md leave-out line along with the record (the older TODO.md items moved in don't count)" 'printf "%s\n" "$RA1_PICK" | r5_sents | f3_tdm'
check "retrofit-it Phase 5's trigger (**Then write the record**): names the TODO.md leave-out line along with the record" 'f2_trig | f3_tdm'

# Minor 2: after an undo (full, or "Before this step" at step 1), the TODO.md leave-out lines come back from the record. Run on a
# scratch repo in the text's order: the snapshot, the branch, the record and TODO.md written in `work` with both leave-outs, step 1
# (committed), then the undo's block. When its words say the TODO.md leave-out lines come back (or are kept), and the block didn't
# do it, each record item missing from TODO.md is written back there from the record, as an agent following them would.
F3_TD1='- [ ] Activity monitoring -- left out by your choice: you keep your own note of who changed what'
F3_TD2='- [ ] Notifications -- left out by your choice: you tell guests about the specials yourself'
F3_TDLN='\bTODO_md( leave-out| left-out)? (lines?|entr(y|ies))\b'
F3_TDBACK="\\b(keep|keeps|kept|keeping|spare|spares|spared|sparing)\\b[^.;:]{0,80}${F3_TDLN}|\\b(leave|leaves|leaving)\\b[^.;:]{0,100}${F3_TDLN}[^.;:]{0,20}\\balone\\b|${F3_TDLN}[^.;:]{0,60}\\b(come|comes|came|coming|brought|written|wrote|put|added)\\b[^.;:]{0,10}\\bback\\b|\\b(bring|brings|bringing|write|writes|writing|put|puts|add|adds|re-?add[a-z]*|re-?writ[a-z]*|restor[a-z]*)\\b[^.;:]{0,60}${F3_TDLN}[^.;:]{0,30}\\b(back|from the record)\\b|\\b(bring|brings|write|writes|put|puts|add|adds)\\b[^.;:]{0,10}\\bback\\b[^.;:]{0,60}${F3_TDLN}|${F3_TDLN}[^.;:]{0,20}\\bback from the record\\b"
F3_TDGONE="${F3_TDLN}[^.;:]{0,40}\\b(stay|stays|remain|remains|are|is|get|gets|go|goes)( [a-z]+)? (deleted|gone|removed|lost|dropped)\\b|\\b(delete|deletes|deleting|remove|removes|removing|drop|drops|dropping|lose|loses|losing)\\b[^.;:]{0,25}${F3_TDLN}"
F3_BOTH='\b(either|both|every|any|each)\b[^.;:]{0,15}\b(undo|undos|way|ways|case|cases)\b|\bin both\b'
# the undo's own words: from "**Undo** --" to the end of the plan step, its bash block left out, one sentence per line
F3_UPROSE="$(printf "%s\n" "$PLAN" | awk 'index($0,"**Undo** --"){on=1} on&&/^```/{b=!b; next} on&&!b' | r5_pa | r5_sents | r5_md)"
# full | step | both, once per sentence that says the TODO.md leave-out lines come back (a "**Before this step**" one: step)
f3_uback() { printf "%s\n" "$F3_UPROSE" | while IFS= read -r s; do a=$(printf "%s\n" "$s" | r5_aff)
    printf "%s\n" "$a" | gq -iE "$F3_TDBACK" && ! printf "%s\n" "$a" | gq -iE "$F3_TDGONE" || continue
    if printf "%s\n" "$s" | gq -iE "$F3_BOTH"; then echo both; elif printf "%s\n" "$s" | gq -F "**Before this step**"; then echo step; else echo full; fi
  done; true; }
F3_UB="$(f3_uback)"
# f3_undo HOW: own-full | own-step ("Before this step" at step 1) | nested. Prints @@REC (the section after the undo), @@TODO (its
# TODO.md), "@@FILES ok" when the upgrade's files went back. Isolated: its own temp folder, no global or system git config.
f3_undo() (
  how=$1 rec=.make-it-state.md back=0
  case $how in own-step) case $F3_UB in *step*|*both*) back=1;; esac;; *) case $F3_UB in *full*|*both*) back=1;; esac;; esac
  T=$(mktemp -d 2>/dev/null) && T=$(cd "$T" && pwd -P) || exit 0; trap 'rm -rf "$T"' EXIT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T" GIT_AUTHOR_NAME=t \
    GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
  A="$T/proj/cafe"; mkdir -p "$A" && cd "$T/proj" || exit 0
  [ "$how" = nested ] || cd "$A"
  { git -c init.defaultBranch=main init -q && printf 'node_modules/\n' > .gitignore && printf 'v0\n' > "$A/app.py" &&
    git add -A && git commit -qm init; } >/dev/null 2>&1 || { echo "@@SETUP"; exit 0; }
  cd "$A"
  o=$(bash -c "$R5_SNAP" 2>&1); case $(printf '%s\n' "$o" | tail -n 1) in "snapshot: "*) ;; *) echo "@@SNAP $o"; exit 0;; esac
  [ "$how" = nested ] || git switch -q -c retrofit >/dev/null 2>&1 || { echo "@@BW"; exit 0; }
  printf '# Project State -- Cafe\n\n%s\n\n%s\n%s\n' "$SECTION" "$RB_ITEM" "$RA1_NEW" > $rec
  printf '# TODO\n\n%s\n%s\n' "$F3_TD1" "$F3_TD2" > TODO.md
  src=$(git rev-parse HEAD 2>/dev/null); printf 'v1\n' > app.py; printf 'one\n' > step1.txt
  [ "$how" = nested ] || { git add -A && git commit -qm "step 1"; } >/dev/null 2>&1 || { echo "@@STEP1"; exit 0; }
  if [ "$how" = own-step ]; then
    o=$(R5W="$A" R5S="$src" bash -c 'fail() { echo "UNDO FAILED: $1"; exit 1; }; work=$R5W; tag=$R5S
'"$R5_STEPU" 2>&1)
  else o=$(printf '%s\n' "$R5_UNDO" | perl -pe 's/\bapp=\[[^\]]*\]/app="\$R5A"/; s/\bwork=\[[^\]]*\]/work="\$R5A"/' | R5A="$A" bash 2>&1); fi
  case $o in *"UNDO FAILED"*) echo "@@UNDO $o"; exit 0;; esac
  cd "$A" || exit 0
  [ "$back" != 1 ] || grep '^- ' $rec 2>/dev/null | sed 's/^- //; s/ -- checks .*//' | while IFS= read -r n; do
    grep -iF "left out by your choice" TODO.md 2>/dev/null | gq -F -- "$n" || printf -- '- [ ] %s -- left out by your choice\n' "$n" >> TODO.md; done
  echo "@@REC"; ra1_rs2 "$(cat $rec 2>/dev/null)" "" sec
  echo "@@TODO"; cat TODO.md 2>/dev/null
  [ "$(cat app.py 2>/dev/null)" = v0 ] && [ ! -e step1.txt ] && echo "@@FILES ok"; true
)
f3_uok() { printf "%s\n" "$1" | gq -xF "@@FILES ok" && rb_at "$1" REC | gq "^Activity monitoring " && rb_at "$1" REC | gq "^Notifications " &&
  rb_at "$1" TODO | grep -iF "left out by your choice" | gq -F "Activity monitoring" && rb_at "$1" TODO | grep -iF "left out by your choice" | gq -F "Notifications"; }
F3_UOF="$(f3_undo own-full)"; F3_UOS="$(f3_undo own-step)"; F3_UNF="$(f3_undo nested)"
check "retrofit-it full undo (own repo, scratch repo, the text's order): the record keeps both leave-outs, and TODO.md has both leave-out lines again, from the record" 'f3_uok "$F3_UOF"'
check "retrofit-it full undo (nested app, scratch repo): the record keeps both leave-outs, and TODO.md has both leave-out lines again, from the record" 'f3_uok "$F3_UNF"'
check "retrofit-it undo \"Before this step\" at step 1 (own repo, scratch repo): the record keeps both leave-outs, and TODO.md has both leave-out lines again, from the record" 'r5_btsame && f3_uok "$F3_UOS"'

# Minor 4: review 4's seven polarity mutants. Each check reads its own sentence; all seven pass on today's text.
# Phase 5's trigger, its pointer aside: it says to write the record (a write verb in what it affirms), and never to hold it
f3_trigw() { f2_trig | perl -pe 's/\*\*Then write the record\*\*//g' | r5_aff; }
F3_HOLDT='\b(hold|holds|holding|keep|keeps|keeping|save|saves|saving) (it|the record|them|that)\b[^.;:]{0,30}\b(for|until|till)\b|\b(wait|waits|waiting|later|afterwards?|postpone[sd]?|defer[a-z]*)\b|\bfor (Part E|Phase 6|the end)\b'
check "(mutant) retrofit-it Phase 5's trigger affirms the write itself (\"write the record there\"), never \"don't write it yet\" or \"hold it for Part E\"" \
  'a=$(f3_trigw); printf "%s\n" "$a" | gq -iE "\b(write|writes|writing)\b[^.;:()]{0,30}\b(the record|it)\b" && ! printf "%s\n" "$a" | gq -iE "$F3_HOLDT"'
check "(mutant) retrofit-it Phase 5's trigger is an instruction, never \"you can\" or \"if you have not written it already\"" \
  's=$(f2_trig | perl -pe "s/\*\*Then write the record\*\*//g"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "\bunless\b|\bif\b[^.;:]{0,40}\b(not|n.t|never|already)\b|\bif not already\b|\b(can|may|could|might|optionally)\b|\bif you (like|want|wish)\b"'
check "(mutant) retrofit-it Phase 5's trigger covers every plan (5a and 5b), never \"for a phased plan only\"" \
  's=$(f2_trig | perl -pe "s/\\b(5a|single-pass)( and | or |\\/)(5b|phased)\\b|\\b(5b|phased)( and | or |\\/)(5a|single-pass)\\b//gi"); [ -n "$s" ] && ! printf "%s\n" "$s" | gq -iE "\bonly\b|\b(phased|single-pass|5a|5b|multi-step)\b"'
# the plan step's TODO.md leave-out line (f2_todopos's sentences): each is tied to the record, none says now; each names its folder
f3_tds() { printf "%s\n" "$PLAN" | r5_ps | r5_md | grep -E "TODO_md" | grep -iE "$LO" | grep -iE "$F2_TODOW" || true; }
F3_NOW="\\bnow\\b|$F2_TODONOW|\\bbefore (writing |you write |it writes )?the record\\b|\\bthe record\\b[^.;:]{0,20}\\b(comes?|is written|goes|follows)\\b[^.;:]{0,10}\\b(later|after|afterwards)\\b|\\b(later|afterwards)\\b"
f3_tdnow() { local s; s=$(f3_tds); [ -n "$s" ] && [ -z "$(printf "%s\n" "$s" | while IFS= read -r x; do a=$(printf "%s\n" "$x" | r5_aff)
    if printf "%s\n" "$a" | gq -iE "$F3_NOW"; then echo x
    elif ! { printf "%s\n" "$a" | gq -iE "$F2_WITHREC" || printf "%s\n" "$RA1_PICK" | r5_sents | r5_md | gq -xF -- "$x"; }; then echo x; fi; done)" ]; }
check "(mutant) retrofit-it plan step: the TODO.md leave-out line is tied to the record, never written \"now (the record comes later)\"" 'f3_tdnow'
f3_tddir() { local s; s=$(f3_tds); [ -n "$s" ] && [ -z "$(printf "%s\n" "$s" | while IFS= read -r x; do a=$(printf "%s\n" "$x" | r5_aff)
    if printf "%s\n" "$a" | gq -iE "$F2_APPX|$F3_ALT" || { printf "%s\n" "$a" | gq -iE "$F2_APP" && ! printf "%s\n" "$a" | gq -iE "$RB_WORK|$RB_WT"; }; then echo x
    elif ! { printf "%s\n" "$a" | gq -iE "\b(the )?same folder\b|$RB_WORK|$RB_WT" || printf "%s\n" "$RA1_PICK" | r5_sents | r5_md | gq -xF -- "$x"; }; then echo x; fi; done)" ]; }
check "(mutant) retrofit-it plan step: the TODO.md leave-out line goes in the record's folder (\`work\`), never \"in the app folder, even in worktree mode\"" 'f3_tddir'
f3_noalt() { local v; for v in "$F2_TOUT" "$F2_BACK" "$SKIP" "$SAVE"; do
    [ -n "$v" ] && ! printf "%s\n" "$v" | flat | r5_sents | r5_md | r5_aff | gq -iE "$F3_ALT" || return 1; done; }
check "(mutant) retrofit-it take-out, bring-back, Phase 6 and Part E: each names \`work\` alone, never \"\`work\` or the app folder, whichever you are in\"" 'f3_noalt'
# the fresh-build "step-by-step" route: the database stop, then the snapshot, then the record write, in that order
f3_fbord() { printf "%s\n" "$R5_FBS" | r5_sents | grep -iE "step-by-step" | grep -iE "snapshot" | grep -iE "record write|write the record" | r5_aff |
  perl -ne '$_ = lc; my ($d, $s) = (index($_, "database stop"), index($_, "snapshot")); my $r = /record write|write the record/ ? $-[0] : -1;
    print(($d >= 0 && $d < $s && $s < $r && !/\brecord\b[^.;:]{0,40}\bbefore\b[^.;:]{0,20}\bsnapshot\b|\bsnapshot\b[^.;:]{0,30}\b(after|follows)\b[^.;:]{0,30}\brecord\b/) ? "ok\n" : "x\n")' || true; }
check "(mutant) retrofit-it fresh-build \"step-by-step upgrade without them\": its database stop, then the snapshot, then the record write -- in that order" \
  'o=$(f3_fbord); printf "%s\n" "$o" | gq -x ok && ! printf "%s\n" "$o" | gq -x x'

# ---- Task 5 adversarial round 2 ----
# #1: a re-run with Secure login in the record ("- Secure login -- checks A01-A10 -- left out 2026-10-18") on an app with its
# own login. Each login gate (the "Your login" block, the closing ask's login clause, the plain-yes rule's, guardrails rule 7)
# keeps a left-out secure login out in its own text, so the item gets only the one-line mention: no keep-or-replace ask, and no
# gate offers the new sign-in (bringing it back is read step 4's, which the read-first rule already points at).
A2_REC="$(printf '%s\n' '# Project State -- Cafe' '' "$SECTION" '' '- Secure login -- checks A01-A10 -- left out 2026-10-18')"
# what a login gate offers: keep the current login and add the new sign-in, or replace it
A2_OFFER='keep (it )?or replace|keep / replace|keep your current login|new (secure )?sign-in|replace it with the new one'
# the top-level [..] brackets of stdin, one per line (an inner [..] kept whole)
a2_br() { flat | perl -ne 'while (/(\[(?:[^\[\]]++|(?1))*\])/g) { print "$1\n" }'; }
# a2_gate PARA: the text that gates a login offer in PARA -- PARA itself when its own text (brackets aside) offers one, else each
# top-level [..] in it that does
a2_gate() { if printf "%s\n" "$1" | flat | perl -pe 's/(\[(?:[^\[\]]++|(?1))*\])//g' | gq -iE "$A2_OFFER"; then printf "%s\n" "$(printf "%s\n" "$1" | flat)"
  else printf "%s\n" "$1" | a2_br | grep -iE "$A2_OFFER" || true; fi; }
# a2_skip: stdin holds gate texts, one per line. 0 when there is one and each keeps a left-out secure login out in its own words
# ("and secure login is not left out", "unless secure login is in the record", "skip it when secure login is left out", "the
# record doesn't hold secure login", "if secure login is left out: none"), with no opposite ("even if / whether or not / also
# when ... left out", "not skipped")
a2_skip() { r5_md | A2_SEC="$SECTION" perl -ne '
  next unless /\S/;
  my $C = q{[^.;:\[\]]}; my $L = q{(?:login|log-in|sign-in|sign in)}; my $N = q{(?:\bnot\b|\bnever\b|n.t\b)};
  my $R = q{\b(?:the|its) (?:left-out )?record\b}; my $H = q{\b(?:holds?|has|have|names?|lists?|includes?|carr(?:y|ies))\b};
  my $I = "(?:left out|in $R|under .?\Q$ENV{A2_SEC}\E)"; my $B = q{\b(?:is|are|was|stays?|remains?)\b(?: still)?};
  my $LO = "(?:$L(?:$C){0,25}$B $I|$R(?:$C){0,15}$H(?:$C){0,20}$L)";
  my $skip = /$L(?:$C){0,25}$N(?:$C){0,25}$I/i
    || /\b(?:unless|except (?:when|if|where))\b(?:$C){0,40}$LO/i
    || /$R(?:$C){0,15}$N(?:$C){0,15}$H(?:$C){0,20}$L/i
    || /\b(?:skip|skips|skipped|omit|omits|omitted|drop|drops|dropped|none|nothing|neither|never|not|no)\b(?:$C){0,40}\b(?:when|if|while|where|for)\b(?:$C){0,40}$LO/i
    || /\b(?:when|if|while|where)\b(?:$C){0,40}$L(?:$C){0,25}$B $I(?:[^.;\[\]]){0,40}?\b(?:then )?(?:skip|none|nothing|neither|no|not asked|never asked|drop|omit)\b/i;
  my $opp = /\beven (?:if|when|though|while|where)\b(?:$C){0,60}(?:$I|$R)/i
    || /\bwhether\b(?:$C){0,60}(?:$I|$R)|$I(?:$C){0,20}\bor not\b|\bregardless\b|\beither way\b/i
    || /\b(?:also|still|too|as well|including)\b(?:$C){0,10}\b(?:when|if|while|where)\b(?:$C){0,50}(?:$I|$R)/i
    || /$N\s*(?:be |get |gets |is |are )?(?:skip|skipped|omit|omitted|dropped)\b/i;
  # (fix round 4) what follows the skip condition (after its ":" or "then", up to a bracket or ".", its negated clauses out)
  # never offers the sign-in again: "...: then they still pick keep or replace", "[If secure login is left out: ask keep or replace anyway.]"
  my $OF = q{(?:keep (?:it )?or replace|keep / replace|keep your current login|replace it with the new one)};
  my $t = /$LO(?:[^.;\[\]]){0,40}?(?::|\bthen\b)((?:[^.;\[\]]){0,120})/i ? $1 : "";
  $t =~ s/(?:\b(?:nothing|neither|never|no|not|none|nor)\b|n.t\b)[^.;:,]*//gi;
  $opp ||= $t =~ /\b(?:pick|picks|picked|choose|chooses|chose|ask|asks|asked|offer|offers|offered|still|also)\b(?:[^.;\[\]]){0,30}?$OF|$OF(?:[^.;\[\]]){0,30}?\b(?:anyway|still|too|as well|regardless)\b|\bI (?:can )?keep your current login\b|\badd(?:s|ed|ing)?\b(?:[^.;\[\]]){0,15}\bnew (?:secure )?sign-in/i;
  $n++; $ok++ if $skip && !$opp; END { exit(($n && $ok == $n) ? 0 : 1) }'; }
A2_GL="$(printf "%s\n" "$PLAN" | r5_pa | grep -F '**Your login:**' || true)"
A2_GA="$(printf "%s\n" "$PLAN" | r5_pa | grep -F 'Tell me what to include' || true)"
A2_GY="$(printf "%s\n" "$PLAN" | r5_pa | grep -F 'A plain yes is not an answer' || true)"
A2_G7="$(awk '/^7\. \*\*Auth wrapping/{on=1;print;next} on&&(/^$/||/^[0-9]+\. /||/^<\//){exit} on' $RETRO | flat)"
check "retrofit-it re-run, Secure login in the record, an app with its own login: the \"Your login\" block's own gate keeps a left-out secure login out (no keep-or-replace ask)" \
  '[ -n "$A2_GL" ] && a2_gate "$A2_GL" | a2_skip'
check "retrofit-it re-run, same fixture: the closing ask's login clause (\"keep it or replace it\") keeps a left-out secure login out in its own text" \
  '[ -n "$A2_GA" ] && a2_gate "$A2_GA" | a2_skip'
check "retrofit-it re-run, same fixture: the plain-yes rule's login clause (\"keep or replace\") keeps a left-out secure login out in its own text" \
  '[ -n "$A2_GY" ] && a2_gate "$A2_GY" | a2_skip'
check "retrofit-it guardrails rule 7 (the user picks keep or replace at the plan ask) keeps a left-out secure login out in its own text" \
  '[ -n "$A2_G7" ] && printf "%s\n" "$A2_G7" | a2_skip'
# every login offer the plan step makes (a2_gate of each paragraph that offers one), plus rule 7
a2_units() { printf "%s\n" "$PLAN" | r5_pa | grep -iE "$A2_OFFER" | while IFS= read -r p; do a2_gate "$p"; done; printf "%s\n" "$A2_G7"; }
check "retrofit-it re-run on that fixture (read step 2 reads Secure login from it): every login offer in the plan step and guardrails rule 7 -- the four gates all found -- keeps it out, so no gate offers the new sign-in" \
  'ra1_rs2 "$A2_REC" "" | gq "^Secure login " && [ "$(a2_units | grep -c . || true)" -ge 4 ] && a2_units | a2_skip'

# #2: an older-form record -- a TODO.md-only leave-out an older /resume-it wrote after run 1's snapshot (run 1 left nothing out, so
# no section) -- through a re-run with nothing new left out ("all items") and the full undo. **Then write the record** starts the
# section anyway, the older items moved in by the definition's Where rule, so the undo (which spares .make-it-state.md) keeps it.
A2_TDL='- [ ] Notifications -- left out by your choice: you tell guests about the specials yourself'
A2_EVEN='\beven (when|if|with|on|for)\b[^.;:]{0,40}\b(nothing|no (new )?(items?|leave-outs?|entries|lines?))\b|\bwhether or not\b[^.;:]{0,50}\bleft out\b|\bwith or without\b[^.;:]{0,30}\b(new )?(leave-outs?|items?)\b|\b(always|every (re-?run|run|time))\b'
A2_STV='\b(start|starts|starting|begin|begins)\b[^.;:]{0,15}\b(it|the section|the file|that section|its section)\b|\bmov(e|es|ed|ing)\b[^.;:]{0,60}\b(in|into)\b'
A2_ONLY='\bonly (when|if|once)\b[^.;:]{0,50}\b(left out|leave-outs?|leaves? (something|an item|items?) out)\b|\bnothing (new )?(is |was )?left out\b[^.;:]{0,30}\b(write|writes|start|starts|add|adds|move|moves|do|does) nothing\b|\b(write|writes|start|starts|add|adds|move|moves|do|does) nothing\b[^.;:]{0,30}\b(when|if)\b[^.;:]{0,20}\bnothing (new )?(is |was )?left out\b|\b(skip|skips|skipped)\b[^.;:]{0,30}\b(when|if)\b[^.;:]{0,20}\bnothing\b'
# a2_start: 1 when a sentence of the record paragraph starts the section with the older items moved in (older lines, TODO.md items,
# read step 2, or a Where pointer) even when nothing new is left out, and no sentence there does it only when something is
a2_start() { local s; s=$(printf "%s\n" "$RA1_PICK" | r5_sents | r5_md | ra1_nosec || true)
  if printf "%s\n" "$s" | r5_aff | gq -iE "$A2_ONLY"; then echo 0; return; fi
  printf "%s\n" "$s" | while IFS= read -r x; do a=$(printf "%s\n" "$x" | r5_aff)
    printf "%s\n" "$x" | gq -iE "$A2_EVEN" && ! printf "%s\n" "$x" | gq -iE "(\bnot\b|\bnever\b|n.t\b)[^.;:]{0,10}\b(even|always|every)\b" &&
      printf "%s\n" "$a" | gq -iE "$A2_STV" && printf "%s\n" "$x" | gq -iE "$RA1_MVSRC|$RA1_WHERE" &&
      # (fix round 4) its own trigger names the TODO.md items, and it starts the section at this write, never later ("Part E starts it")
      printf "%s\n" "$a" | gq -E '\bTODO' &&
      ! printf "%s\n" "$a" | perl -pe 's/\bPart E\b[^.;:,()]{0,15}\b(only )?(adds?|keeps?|appends?)\b//gi' | f2_early | gq -iE "$F2_LATE|\\b(Part E|Phase 6|Phase 7)\\b" && { echo 1; break; }
  done | grep . || echo 0; }
A2_ST="$(a2_start)"; A2_MW="$(f2_mvwhat "$RA1_PICK")"
# a2_undo HOW: own | nested. Run 1 (nothing left out), its snapshot and upgrade; the TODO.md-only line; the re-run: Phase 4's read
# (@@RE4), its snapshot (@@RESNAP), the branch (own repo), the record write the text gives with nothing new left out (A2_ST, what
# moves in by A2_MW), step 1 (committed), the full undo's block verbatim, the TODO.md write-back the undo's words give (F3_UB). Then
# read step 2 in the app folder (@@REC), its TODO.md (@@TODO), "@@FILES ok". Isolated: its own temp folder, no global or system git
# config, no repo above it.
a2_undo() (
  how=$1 rec=.make-it-state.md
  T=$(mktemp -d 2>/dev/null) && T=$(cd "$T" && pwd -P) || exit 0; trap 'rm -rf "$T"' EXIT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T" GIT_AUTHOR_NAME=t \
    GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
  A="$T/proj/cafe"; mkdir -p "$A" && cd "$T/proj" || exit 0
  [ "$how" = nested ] || cd "$A"
  { git -c init.defaultBranch=main init -q && printf 'node_modules/\n' > .gitignore && printf 'v0\n' > "$A/app.py" &&
    printf '# TODO\n\n- [ ] add a menu photo\n' > "$A/TODO.md" && git add -A && git commit -qm init; } >/dev/null 2>&1 || { echo "@@SETUP"; exit 0; }
  cd "$A"
  sv() { [ "$how" = nested ] || { git add -A && git commit -qm "$1"; } >/dev/null 2>&1; }
  o=$(bash -c "$R5_SNAP" 2>&1); case $(printf '%s\n' "$o" | tail -n 1) in "snapshot: "*) ;; *) echo "@@SNAP $o"; exit 0;; esac
  printf 'v1\n' > app.py; sv "the first run's upgrade" || { echo "@@RUN1"; exit 0; }
  printf '%s\n' "$A2_TDL" >> TODO.md; sv "resume-it: Notifications left out" || { echo "@@RESUME"; exit 0; }
  echo "@@RE4"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)"
  o=$(bash -c "$R5_SNAP" 2>&1); echo "@@RESNAP $(printf '%s\n' "$o" | tail -n 1)"
  [ "$how" = nested ] || git switch -q -c retrofit-2 >/dev/null 2>&1 || { echo "@@BW"; exit 0; }
  if [ "$A2_ST" = 1 ]; then mv=1 t=""; [ "$A2_MW" != none ] || mv=0; [ "$A2_MW" != both ] || t=$(cat TODO.md)
    r=$(ra1_wr append "$mv" '# Project State -- Cafe' "$t" ""); [ -z "$(ra1_rs2 "$r" "" sec)" ] || printf '%s\n' "$r" > $rec; fi
  printf 'v2\n' > app.py; printf 'one\n' > step1.txt; sv "step 1" || { echo "@@STEP1"; exit 0; }
  o=$(printf '%s\n' "$R5_UNDO" | perl -pe 's/\bapp=\[[^\]]*\]/app="\$R5A"/; s/\bwork=\[[^\]]*\]/work="\$R5A"/' | R5A="$A" bash 2>&1)
  case $o in *"UNDO FAILED"*) echo "@@UNDO $o"; exit 0;; esac
  cd "$A" || exit 0
  case $F3_UB in *full*|*both*) grep '^- ' $rec 2>/dev/null | sed 's/^- //; s/ -- checks .*//' | while IFS= read -r n; do
    grep -iF "left out by your choice" TODO.md 2>/dev/null | gq -F -- "$n" || printf -- '- [ ] %s -- left out by your choice\n' "$n" >> TODO.md; done;; esac
  echo "@@REC"; ra1_rs2 "$(cat $rec 2>/dev/null)" "$(cat TODO.md 2>/dev/null)"
  echo "@@TODO"; cat TODO.md 2>/dev/null
  [ "$(cat app.py 2>/dev/null)" = v0 ] && [ ! -e step1.txt ] && echo "@@FILES ok"; true
)
a2_uok() { rb_at "$1" RE4 | gq "^Notifications " && printf "%s\n" "$1" | gq -E "^@@RESNAP snapshot: " && printf "%s\n" "$1" | gq -xF "@@FILES ok" &&
  rb_at "$1" REC | gq "^Notifications " && rb_at "$1" TODO | grep -iF "left out by your choice" | gq -F Notifications; }
A2_UO="$(a2_undo own)"; A2_UN="$(a2_undo nested)"
check "retrofit-it re-run on an older-form record (a TODO.md-only leave-out written after run 1's snapshot), nothing new left out, then the full undo (own repo, scratch repo, the text's blocks verbatim): **Then write the record** started the section with the item moved in, so it is still left out after the undo, and its TODO.md line is back" \
  'a2_uok "$A2_UO"'
check "retrofit-it re-run on that older-form record, nothing new left out, then the full undo (nested app, scratch repo, the text's blocks verbatim): the item is still left out after the undo, and its TODO.md line is back" \
  'a2_uok "$A2_UN"'

# #3: a re-run makes its branch or worktree from the current HEAD (the upgrade so far, where "Stop here" left it), never fresh off
# main. Phase 5's Execution model gives the base: head when a sentence there makes the branch or worktree from the current HEAD (or
# the branch the earlier run left) and one says never fresh off main; else main (worktree-workflow.md rule 2, "Branch fresh off the
# latest default branch", which retrofit-it loads)
A2_HEAD='\b(from|off|on top of|based on)\b[^.;:]{0,20}\b(the )?(current )?HEAD\b|\bfrom (where|what) .?Stop here.? left\b|\bfrom (the )?(branch|worktree|\[BRANCH\])[^.;:]{0,30}\b(earlier|previous|first|last|other) run\b|\bfrom \[BRANCH\]|\bfrom the upgrade so far\b'
A2_MAIN='\b(fresh )?(off|from)\b[^.;:]{0,10}\b(the )?(latest )?(main|master|default branch|origin/main)\b'
A2_NOTMAIN="(\\bnever\\b|\\bnot\\b|n.t\\b|\\brather than\\b|\\binstead of\\b)[^.;:]{0,30}($A2_MAIN)"
a2_base() { local s; s=$(printf "%s\n" "$F2_EXEC" | r5_md || true)
  if printf "%s\n" "$s" | r5_aff | t5_inst | perl -pe 's/; /;\n/g' | grep -viE '\bfirst run\b' | gq -iE "$A2_MAIN"; then echo main
  elif printf "%s\n" "$s" | r5_aff | grep -iE '\b(branch|worktree)\b' | gq -iE "$A2_HEAD" && printf "%s\n" "$s" | gq -iE "$A2_NOTMAIN"; then echo head
  else echo main; fi; }
A2_BASE="$(a2_base)"; A2_RBO="$(rb_repo branch rebranch)"
check "retrofit-it branch-mode \"Stop here\" after step 1, then /retrofit-it again in the app folder (scratch repo, the text's order): the re-run's branch, made from the base Phase 5's Execution model names, holds the upgrade so far, and Phase 6's read there finds both Activity monitoring and the new Notifications" \
  'rb_ok "$A2_RBO" && rb_at "$A2_RBO" RE4 | gq "^Activity monitoring " && printf "%s\n" "$A2_RBO" | gq -E "^@@RESNAP snapshot: " && printf "%s\n" "$A2_RBO" | gq -xF "@@REAPP v1" && rb_at "$A2_RBO" RE6 | gq "^Activity monitoring " && rb_at "$A2_RBO" RE6 | gq "^Notifications "'

# #4: the definition's line on when /retrofit-it writes the record gives the new timing -- right after Phase 5 makes its branch or
# worktree, before step 1, with Part E only adding to it -- never "with the rest of the state (Phase 6, Part E)"
A2_DEFW="$(sec $DEF '## The left-out record' | flat | r5_md | perl -ne 'print "$1\n" if m{(/retrofit-it\b(?:(?!/resume-it\b|\.\s+[A-Z]).){0,300})}' || true)"
A2_PEADD='\bPart E\b[^.;:,()]{0,15}\b(only )?(adds?|keeps?|appends?)\b|\b(adds?|keeps?|appends?)\b[^.;:()]{0,20}\b(at|in) Part E\b'
a2_defok() { local a; a=$(printf "%s\n" "$A2_DEFW" | r5_aff); [ -n "$a" ] || return 1
  printf "%s\n" "$a" | gq -iE "$F2_AFTER" && printf "%s\n" "$a" | gq -iE "$RB_FIRST" || return 1
  # with the branch/worktree timing, "before step 1" and "Part E adds to it" taken out, nothing left makes the write late
  ! printf "%s\n" "$a" | R="$F2_AFTER" P="$A2_PEADD" perl -pe 's/$ENV{R}//gi; s/$ENV{P}//gi' | f2_early | gq -iE "$F2_LATE" &&
  [ "$(printf "%s\n" "$A2_DEFW" | grep -oiE '\bPart E\b' | grep -c . || true)" = "$(printf "%s\n" "$A2_DEFW" | grep -oiE "$A2_PEADD" | grep -c . || true)" ]; }
check "left-out-record.md: /retrofit-it writes the record right after Phase 5 makes its branch or worktree and before step 1 (Part E keeps it), never with the rest of the state at Phase 6 / Part E" 'a2_defok'

# ---- Task 5 fix round 4 ----
# Important (review 6): the branch or worktree is always made from the current HEAD (on a first run, the snapshot; on a re-run,
# where "Stop here" left the upgrade so far, a worktree included), never fresh off main, with no "On a re-run" (or other) scope.
# In [WORKTREE_DIR], where "Stop here" and Phase 7 send the user, the snapshot block makes that folder's own tag, so by the text's
# only definition of a re-run (the tag `pre-retrofit-<app folder name>`) the re-run there is a first run. Minors: Phase 5a step 4
# has no pick, and is skipped, for a left-out secure login; the "Your login" gate's record test leaves out one the user brings
# back at this ask; review 6's seven mutants each fail (a2_skip and a2_start above, and the checks below).
# a sentence with its (..) asides taken out
f4_np() { perl -pe '1 while s/\([^()]*\)//g'; }
# the scopes a clause can carry: a re-run only, a first run only, the user's own folder (or branch mode) only, any leading condition
F4_RERUN='\b(on|for|in|during|at|with) (a|the|this|your|any) (re-?run|second run|later run)\b|\bwhen (re-?running|running (it )?again|it is a re-?run|this is a re-?run)\b|\bif (this is |it is )?a re-?run\b|\bre-?runs? only\b'
F4_FIRST='\b(on|for|in|during|at|with) (a|the|this|your) first run\b|\b(when|if) (this is |it is )?(a |the )?first run\b|\bfirst runs? only\b'
F4_OWN='\b(in|from) (your|the user.s|their|the) own folder\b|\bin (the|your|their) app folder\b|\bin branch mode\b|\b(not|never) in a worktree\b|\boutside (a|the) worktree\b'
F4_LEAD='^ *(on|for|in|when|if|during|while|unless|where|with|once|after)\b(?![^,]{0,15}\b(every|each|any|all|both|either)\b)[^,]{0,60},'
# f4_hc: per Execution-model sentence that (in what it affirms) makes the branch or worktree from the current HEAD, one line:
# SCOPE|CLAUSE|SENTENCE (its own "|" taken out). The clause runs from the last ";" or ":" before the HEAD words to the next ".", ";" or ":".
# SCOPE: none; both (a first run and a re-run named: a gloss); rerun; first; or own (own folder, branch mode, a leading condition)
f4_hc() { printf "%s\n" "$F2_EXEC" | tr -d "|" | r5_md | f4_np | while IFS= read -r s; do
    printf "%s\n" "$s" | r5_aff | grep -iE '\b(branch|worktree)\b' | gq -iE "$A2_HEAD" || continue
    printf "%s\n" "$s" | H="$A2_HEAD" RR="$F4_RERUN" FR="$F4_FIRST" OW="$F4_OWN" LD="$F4_LEAD" perl -ne '
      chomp; next unless /$ENV{H}/i; my ($a, $b) = ($-[0], $+[0]);
      (my $p = substr($_, 0, $a)) =~ s/.*[;:]//s; (my $q = substr($_, $b)) =~ s/[.;:].*//s; my $c = $p . substr($_, $a, $b - $a) . $q;
      my $r = $c =~ /$ENV{RR}/i ? 1 : 0; my $f = $c =~ /$ENV{FR}/i ? 1 : 0;
      my $sc = $c =~ /$ENV{OW}/i ? "own" : ($r && $f) ? "both" : $r ? "rerun" : $f ? "first" : $p =~ /$ENV{LD}/i ? "own" : "none";
      print "$sc|$c|$_\n";'
  done; true; }
# f4_base KIND (first | rerun): the base Phase 5's Execution model gives a run of that kind in a worktree: main when an affirmed
# clause that reaches it makes the branch or worktree off main; head when a HEAD sentence reaches it and one says never off main
f4_base() { local o; [ "$1" = first ] && o=$F4_RERUN || o=$F4_FIRST
  if printf "%s\n" "$F2_EXEC" | r5_md | r5_aff | t5_inst | perl -pe 's/; /;\n/g' | grep -viE "$o|$F4_OWN" | gq -iE "$A2_MAIN"; then echo main
  elif f4_hc | gq -E "^(none|both|$1)[|]" && printf "%s\n" "$F2_EXEC" | gq -iE "$A2_NOTMAIN"; then echo head
  else echo main; fi; }
check "retrofit-it Phase 5's Execution model: the branch or worktree is always made from the current HEAD, never fresh off main -- no \"On a re-run\" (or other) scope a worktree re-run can miss" \
  'f4_hc | grep -E "^(none|both)[|]" | while IFS="|" read -r sc c s; do printf "%s\n" "$c" | gq -iE "\bbranch( or (a |the )?|/)worktree\b|\bworktree( or (a |the )?|/)branch\b" && printf "%s\n" "$s" | gq -iE "$A2_NOTMAIN" && echo y || true; done | gq . && ! printf "%s\n" "$F2_EXEC" | r5_md | r5_aff | t5_inst | gq -iE "$A2_MAIN"'
F4_WRO="$(rb_repo worktree wtrerun)"
check "retrofit-it worktree-mode \"Stop here\", then /retrofit-it again in [WORKTREE_DIR], where that line sends the user (scratch repo, the text's order): its snapshot there, its new worktree from the base the Execution model gives that run, a new leave-out added -- the new work folder holds the upgrade so far, and Phase 6's read there finds both left-out items" \
  'rb_ok "$F4_WRO" && rb_at "$F4_WRO" RE4 | gq "^Activity monitoring " && printf "%s\n" "$F4_WRO" | gq -E "^@@RESNAP snapshot: " && printf "%s\n" "$F4_WRO" | gq -xF "@@REAPP v1" && rb_at "$F4_WRO" RE6 | gq "^Activity monitoring " && rb_at "$F4_WRO" RE6 | gq "^Notifications "'

# Minor 1(a): Phase 5a step 4 (from "4. **Auth" to "5. **"), one sentence per line: with secure login left out (the record) there
# is no pick and the step is skipped, mock-oidc included; nothing there asks keep or replace for it
F4_S4="$(awk '/^4\. \*\*Auth \(Prompt/{on=1} on&&/^5\. \*\*/{exit} on' $RETRO)"
F4_SLO='\b(secure login|secure sign-in|the new sign-in)\b[^.;:]{0,30}\b(left out|in the record)\b|\bleft out\b[^.;:]{0,15}\bsecure login\b'
F4_SLN='\b(secure login|secure sign-in|the new sign-in)\b[^.;:]{0,25}(\bnot\b|\bnever\b|n.t\b)[^.;:]{0,10}\b(left out|in the record)\b'
F4_NOPICK='\bno (pick|choice)\b|\b(there is|there.s|there was|there were) no\b[^.;:]{0,15}\b(pick|choice)\b|\bnothing to (pick|follow)\b|\bno keep[- ]or[- ]replace\b'
F4_SKIP='\bskip[a-z]*\b[^.;:]{0,10}\b(this|the|that|its|the whole|the entire)\b[^.;:]{0,10}\b(auth )?step\b|\bskip[a-z]* step 4\b|\b(this|the auth|the) step( 4)? is skipped\b|\bstep 4 is skipped\b|\bskip[a-z]* (it all|all of (it|this|step 4))\b'
F4_ASK='\b(ask|asks|asking|offer|offers|offering|let (them|the user) pick|have (them|the user) pick|they pick|the user picks)\b[^.;:]{0,30}\b(keep (it )?or replace|keep / replace|keep-or-replace)\b|\bkeep (it )?or replace\b[^.;:]{0,20}\b(now|anyway|here|instead)\b'
f4_s4s() { printf "%s\n" "$F4_S4" | r5_un | r5_md | r5_sents | grep -iE "$F4_SLO" | grep -viE "$F4_SLN" || true; }
check "retrofit-it Phase 5a step 4: with secure login left out there is no pick and the step is skipped -- it never asks keep or replace for it" \
  's=$(f4_s4s); printf "%s\n" "$s" | while IFS= read -r x; do printf "%s\n" "$x" | gq -iE "$F4_NOPICK" && printf "%s\n" "$x" | r5_aff | gq -iE "$F4_SKIP" && echo y || true; done | gq . && ! printf "%s\n" "$s" | r5_aff | gq -iE "$F4_ASK"'
F4_MOCK="$(printf "%s\n" "$F4_S4" | r5_un | grep -iF mock-oidc || true)"
check "retrofit-it Phase 5a step 4: mock-oidc isn't added for a left-out secure login (the step's skip covers its \"Always\" line, or that line keeps it out itself)" \
  '[ -n "$F4_MOCK" ] && { f4_s4s | r5_aff | gq -iE "$F4_SKIP" || printf "%s\n" "$F4_MOCK" | flat | a2_skip; } && ! printf "%s\n" "$F4_MOCK" | r5_md | gq -iE "\beven (if|when|though|while)\b[^.;]{0,60}\b(left out|in the record)\b|\bwhether or not\b|\bregardless\b|\b(also|still|too)\b[^.;]{0,15}\b(when|if)\b[^.;]{0,40}\bleft out\b"'

# Minor 1(b): the "Your login" gate's record test (its first top-level [..] naming the login) leaves out a secure login the user
# brings back at this ask, so it gets its keep-or-replace pick: "(the record; one they bring back at this ask is not)"
F4_GLB="$(printf "%s\n" "$A2_GL" | a2_br | grep -iE '\blogin\b' | awk 'NR==1' | r5_md || true)"
check "retrofit-it plan, the \"Your login\" gate: a secure login the user brings back at this ask is not left out (the record test excludes it), so it gets its keep-or-replace pick" \
  'printf "%s\n" "$F4_GLB" | gq -iE "$R5_BACK" && printf "%s\n" "$F4_GLB" | gq -iE "\bback\b[^].;:]{0,40}(\b(is|are) (not|never)\b|\b(isn|aren).t\b|\bnot\b)|\bback\b[^].;:]{0,40}\b(counts?|is|are) (as )?(included|in the plan|picked)\b|\bback\b[^].;:]{0,40}\bgets?\b[^].;:]{0,20}\b(pick|choice|keep or replace)\b|\b(not|never|except|but not|other than|unless)\b[^].;:]{0,30}\b(brought|bring|brings|bringing)\b[^].;:]{0,15}\bback\b|\bbring-back\b[^].;:]{0,20}(\b(is|does) (not|never)\b|\b(isn|doesn).t\b)" && ! printf "%s\n" "$F4_GLB" | gq -iE "\bback\b[^].;:]{0,40}\b(is|are|stays?|remains?)( still)? (left out|in the record)\b|\bback\b[^].;:]{0,40}\b(still|too|also)\b|\b(even|including|also)\b[^].;:]{0,40}\b(brought|bring|brings)\b[^].;:]{0,15}\bback\b"'

# ---- Task 5 owner call 1 (after round 3): an older record is read only in the shapes older skills wrote ----
# Read step 2's older form (a state file with no section) counts only an older /retrofit-it Part E line, `- [item] -- left out by
# your choice` (the phrase right after " -- "), and TODO.md lines as today. A status line never counts: on an older project
# try-it's own "- Result: 5 of 5 Passing, plus 1 item(s) left out by your choice" was read as a second item, then moved into the
# section for good (task-5-adv3.md #1). Text: step 2's sentences (oc1_ss, `code` as tokens), in what each affirms (r5_aff).
check "read step 2: an older state file (no section) counts an older /retrofit-it Part E line in its shape, \`- [item] -- left out by your choice\` (the phrase right after \" -- \"), in what a sentence affirms" \
  'oc1_ss | while IFS= read -r s; do a=$(printf "%s\n" "$s" | r5_aff); printf "%s\n" "$a" | gq -E "SHAPE[0-9]" && printf "%s\n" "$a" | gq -iE "$OC1_CNT" && printf "%s\n" "$s" | gq -iE "Part E|/retrofit-it" && echo y || true; done | gq .'
check "read step 2: a status line (try-it's \`- Result: ...\` under \`## Try-It Status\`) never counts -- said, and no sentence affirms it counts" \
  's=$(oc1_ss | grep -iE "$OC1_STAT" || true); printf "%s\n" "$s" | gq -iE "${OC1_STAT}[^.;:]{0,60}\b(never|not|n.t|no longer)\b[^.;:]{0,20}\b(counts?|counted|an item|items?)\b|\b(no|never an?)\b[^.;:]{0,10}${OC1_STAT}[^.;:]{0,30}\b(counts?|is an item)\b" && ! printf "%s\n" "$s" | r5_aff | gq -iE "${OC1_STAT}[^.;:]{0,60}\b(counts?|counted|is an item|are items|items? too)\b"'
check "read step 2: the old reading is gone -- no sentence affirms that another line of an older state file saying \"left out by your choice\" is an item (\"on another line\", \"each such line\", or a status line that counts)" \
  '[ -n "$(oc1_ss)" ] && [ -z "$(oc1_any)" ]'

# The sessions (adv3 #1's exact input), each read by read step 2 as its text gives it (ra1_rs2; an older state-file line by
# RA1_STL): an older project, no section, TODO.md holding only Notifications. Session 1: /try-it -- its save-state block in place
# of Try-It Status only (r5_fill), the Result line as the report's Status line reads when the text says so (try-it's "> Status:"
# template, 5 of 5 Passing, with the items read). Session 2: /try-it, then /wrap-it (step 5 rewrites the file and starts the
# section, the older lines moved in when its placeholder says so: ra1_wr), then /resume-it (save-state, r5_fill).
OC1_S0="$(printf '%s\n' '# Project State -- Cafe Menu' '> Last updated: 2026-10-01 09:00' '> Last session: resume-it' '' \
  '## Current Status' '- The menu and the weekly specials page work' '' '## Remaining TODOs' '- Add a photo to each dish'; echo .)"; OC1_S0="${OC1_S0%.}"
OC1_TODO="$(printf '%s\n' '# TODO' '' '- [ ] Notifications -- left out by your choice: you tell guests about the specials yourself' '- [ ] Add a photo to each dish')"
# oc1_status L: try-it's report Status line, 5 of 5 Passing, with L items left out
oc1_status() { grep -m1 '^> Status: ' $TRY | sed 's/^> Status: //' | L="$1" perl -pe 's{\[All Passing / X of Y Passing\]}{$ENV{L} ? "5 of 5 Passing" : "All Passing"}e; s{\[if anything is left out: \x27(.*)\x27\]}{$ENV{L} ? $1 : ""}e; s/\[L\]/$ENV{L}/g'; }
# oc1_try STATE: STATE after a /try-it session on it
oc1_try() { local l o; l=$(ra1_rs2 "$1" "$OC1_TODO" | grep -c . || true); o="$(r5_fill "$TSAVE" section "$1"; echo .)"; o="${o%.}"
  if [ -n "$(r5_resptr)" ]; then printf "%s" "$o" | R="$(oc1_status "$l")" perl -pe 's/^- Result: FILLER$/- Result: $ENV{R}/'; else printf "%s" "$o"; fi; }
OC1_1="$(oc1_try "$OC1_S0"; echo .)"; OC1_1="${OC1_1%.}"
OC1_2T="$(oc1_try "$OC1_1"; echo .)"; OC1_2T="${OC1_2T%.}"
OC1_MV=0; [ -z "$(r5_movein "$WRAP5")" ] || OC1_MV=1
OC1_2W="$(ra1_wr whole "$OC1_MV" "$OC1_2T" "$OC1_TODO" ""; echo .)"; OC1_2W="${OC1_2W%.}"
OC1_2R="$(r5_fill "$RSAVE" whole "$OC1_2W"; echo .)"; OC1_2R="${OC1_2R%.}"
# oc1_one STATE: read step 2 there finds exactly one item, Notifications; oc1_sec STATE: the entries of its section
oc1_one() { local i; i=$(ra1_rs2 "$1" "$OC1_TODO"); [ "$(printf "%s\n" "$i" | grep -c .)" = 1 ] && printf "%s\n" "$i" | gq "^Notifications "; }
oc1_sec() { printf "%s\n" "$1" | awk -v h="$SECTION" '/^## /{on=($0==h); next} on && /^- /'; }
oc1_only() { printf "%s\n" "$1" | gq -xF "$SECTION" && [ "$(oc1_sec "$1" | grep -c .)" = 1 ] && oc1_sec "$1" | gq "^- Notifications -- "; }
check "(control) the older project's session 1: try-it's save-state, filled as its text says, writes \"- Result: 5 of 5 Passing, plus 1 item(s) left out by your choice\" under ## Try-It Status (the line adv3 #1 read as an item), and starts no section" \
  'printf "%s\n" "$OC1_1" | awk "/^## /{on=(\$0==\"## Try-It Status\")} on" | gq -xF -- "- Result: 5 of 5 Passing, plus 1 item(s) left out by your choice" && ! printf "%s\n" "$OC1_1" | gq -xF "$SECTION"'
check "older project, session 1 (/try-it): read step 2 finds exactly one item, Notifications, before it and after its save-state (its Result line is no item)" \
  'oc1_one "$OC1_S0" && oc1_one "$OC1_1"'
check "older project, session 2's /try-it: read step 2 finds exactly Notifications, so its Result line says \"plus 1 item(s)\", and after its save-state it still finds exactly Notifications" \
  'oc1_one "$OC1_1" && printf "%s\n" "$OC1_2T" | gq -xF -- "- Result: 5 of 5 Passing, plus 1 item(s) left out by your choice" && oc1_one "$OC1_2T"'
check "older project, session 2's /wrap-it: the section its step 5 starts holds only Notifications (no try-it Result line moved in), and read step 2 finds exactly it" \
  'oc1_only "$OC1_2W" && oc1_one "$OC1_2W"'
check "older project, session 2's /resume-it (after /wrap-it): its save-state keeps a section holding only Notifications, and read step 2 finds exactly it" \
  'oc1_only "$OC1_2R" && oc1_one "$OC1_2R"'
check "(control) read step 2, an older state file holding an older Part E line (\`- Activity monitoring (who did what, and when) -- left out by your choice\`), TODO.md empty: still exactly one item" \
  'i=$(ra1_rs2 "$RA1_OLD" ""); [ "$(printf "%s\n" "$i" | grep -c .)" = 1 ] && printf "%s\n" "$i" | gq -xF "Activity monitoring (who did what, and when) -- left out by your choice"'
OC1_TDH="$(printf '%s\n' '# TODO' '' '## Left out by your choice (I handle these myself)' '- Notifications: I tell guests about the specials' \
  '- Activity monitoring' '' '## Next' '- Add a photo to each dish')"
check "(control) read step 2, a TODO.md heading-form record (as today): each line under a TODO.md heading that says it is one item, the heading never -- on the older project it reads Notifications and Activity monitoring, one per line" \
  's=$(step $DEF 2 | flat); printf "%s\n" "$s" | gq -iE "under a TODO.md heading that says it" && printf "%s\n" "$s" | gq -iE "one item per top-level .- . line" && printf "%s\n" "$s" | gq -iE "the heading itself is never an item" && [ "$(ra1_rs2 "$OC1_S0" "$OC1_TDH" | tr "\n" "|")" = "Notifications: I tell guests about the specials|Activity monitoring|" ]'

# ---- final review: Task 5 / Task 1 oracle gaps (X3) ----
# T5 r7 N3: the Execution model's HEAD aside gives a re-run where "Stop here" left the upgrade so far -- never the earlier
# snapshot, its tag or main (f4_hc and f4_base read the sentence with its asides out, so the aside is read here)
f4_aside() { printf "%s\n" "$F2_EXEC" | r5_md | perl -ne 'while (/\(([^()]*\bre-?run\b[^()]*)\)/gi) { print "$1\n" }' | perl -pe 's/;\s*/\n/g' | grep -iE '\bre-?run\b' || true; }
check "retrofit-it Phase 5's Execution model: the HEAD aside gives a re-run where \"Stop here\" left the upgrade so far, never the earlier snapshot, its tag or main" \
  'a=$(f4_aside | r5_aff); printf "%s\n" "$a" | gq -iE "where .?Stop here.? left the upgrade so far" && ! printf "%s\n" "$a" | gq -iE "\b(tag|snapshot|main|master|default branch)\b"'
# T5 r7 N1, N11: step 4's and rule 7's left-out sign-in skip never reaches one the user brings back at the plan ask
F4_BBX='\b(even|including|also)\b[^.;:]{0,40}\b(brought|bring|brings|bringing)\b[^.;:]{0,15}\bback\b'
check "retrofit-it step 4 and guardrails rule 7: the left-out sign-in skip never covers one the user brings back at the plan ask (\"even one they brought back\")" \
  '[ -n "$F4_S4" ] && [ -n "$A2_G7" ] && ! { printf "%s\n" "$F4_S4"; printf "%s\n" "$A2_G7"; } | r5_un | r5_md | gq -iE "$F4_BBX"'
# T5 r7 N2: after step 4's skip, nothing adds mock-oidc anyway
check "retrofit-it Phase 5a step 4: after the left-out sign-in skip, nothing adds mock-oidc anyway (\"but still add mock-oidc\")" \
  '[ -n "$(f4_s4s)" ] && ! f4_s4s | r5_aff | gq -iE "\b(but|still|also|anyway|then)\b[^.;:]{0,30}\b(add|adds|wire|wires|copy|copies)\b[^.;:]{0,30}mock-oidc|mock-oidc\b[^.;:]{0,30}\b(still|anyway|too|as well)\b"'
# T5 r8 M1: no other sentence of read step 2 widens what counts. Only the shapes sentence (a SHAPE token and "only"), the TODO.md
# sentence ("Only while there is no section, a TODO.md ...") and the same-item sentence ("is one item") affirm a count
oc1_xcnt() { oc1_ss | while IFS= read -r s; do a=$(printf "%s\n" "$s" | r5_aff)
    printf "%s\n" "$a" | gq -iE '\b(counts?|counted)\b|\b(is|are) (an |one )?items?\b|\bitems? too\b' || continue
    { printf "%s\n" "$s" | gq -E 'SHAPE[0-9]' && printf "%s\n" "$s" | gq -iE '\bonly\b'; } || printf "%s\n" "$s" | gq -iE '^Only while there is (no section|NOSEC), a TODO|\bis one item\b' || printf "%s\n" "$s"
  done; true; }
check "read step 2: no other sentence widens what counts (only the shapes sentence, the TODO.md sentence and the same-item sentence affirm a count)" \
  '[ -n "$(oc1_ss)" ] && [ -z "$(oc1_xcnt)" ]'
# T5 r8 M1 (WRAP / RES): the wrap-it and resume-it placeholders select no lines of their own; they defer to read step 2
R5_SELX='"left out by your choice"|\blines?\b[^];]{0,40}\b(that|which) (say|says|holds?|contains?|mentions?|names?)\b|\b(any|every|each) (other )?lines?\b[^];]{0,30}\b(say|says|saying|holds?|holding|with)\b|\bwherever\b'
for x in "wrap-it step 5|WRAP5" "resume-it save-state|RSAVE"; do
  check "${x%%|*}: the record placeholder selects no lines of its own (no quoted phrase, no \"lines that say\" / \"any line\"); it defers to read step 2" \
    "[ -n \"\$(r5_ph \"\$${x##*|}\")\" ] && ! r5_ph \"\$${x##*|}\" | r5_aff | gq -iE \"\$R5_SELX\""
done
# T1 r9 M2: step 4's part case keeps the old line's date and its "(taken out)"; nothing there gives today's date or drops the marker
check "read step 4: the narrowed line keeps the old one's date and its \"(taken out)\", never today's date or no marker" \
  'printf "%s\n" "$S4" | grep -iE "new line" | grep -iE "\bkeeps?\b" | gq -F "(taken out)" && ! printf "%s\n" "$S4" | gq -iE "\btoday|no \"\(taken out\)\"|\bdrops? [^.]*\(taken out\)|without (its|the) \"?\(taken out\)"'

# ---- final review: the text fixes, retrofit-it (T1-T11) and the definition's Part E wording (D8) ----
# D8: "(Part E keeps it)", never "Part E only adds to it"
check "Where: /retrofit-it's write is kept by Part E (\"Part E keeps it\"), never \"Part E only adds to it\"" \
  'printf "%s\n" "$A2_DEFW" | gq -F "(Part E keeps it)" && ! printf "%s\n" "$A2_DEFW" | gq -iE "\bPart E\b[^.;:,()]{0,15}\b(only )?(adds?|appends?)\b"'
# T1: the read-first rule has no re-run label, and the record's items get a plain lead-in
check "retrofit-it plan: \"Read the record first\" is not gated by \"(a re-run)\" (it may hold items from /resume-it), and the record's items get a plain lead-in" \
  'printf "%s\n" "$PLAN" | flat | gq -F "**Read the record first** (it may hold items from an earlier run or from /resume-it)" && ! printf "%s\n" "$PLAN" | flat | gq -iE "Read the record first\*\* \(a re-?run\)" && printf "%s\n" "$PLAN" | grep -A1 -xF "**Left out by your choice earlier:**" | gq -F -- "- [the item, in the words the user saw] -- left out by your choice"'
# T2: the record is read before the gap inventory and the score; step names leave out its items; a record item needed by a kept one
GAP="$(stepof $RETRO gap-analysis)"
check "retrofit-it gap analysis: the record is read first, and a left-out item's gaps are not in the gap inventory or the risk score" \
  's=$(printf "%s\n" "$GAP" | r5_pa | r5_md | grep -F left-out-record_md); printf "%s\n" "$s" | gq -iE "\bread\b" && printf "%s\n" "$s" | gq -iE "\b(not|never)\b[^.;:]{0,20}\bin the gap inventory or the risk score\b" && ! printf "%s\n" "$s" | r5_aff | gq -iE "\b(counts?|counted|scored)\b[^.;:]{0,20}\b(too|as well|anyway)\b"'
check "retrofit-it phased steps: a step's name and its \"Tell user\" line leave out any item in the record (no \"Secure login is working!\" when it is left out)" \
  'printf "%s\n" "$PLAN" | r5_pa | gq -iE "leave out of each step.s name any item in the record" && printf "%s\n" "$CHECKIN" | r5_pa | gq -iE "in each step.s name and its .Tell user. line, leave out any item in the record"'
check "retrofit-it plan: picking again for a needed item says how to get back one already in the record (read step 4)" \
  'printf "%s\n" "$PLAN" | r5_pa | gq -iE "ask them to pick again \(one already in the record that they want back follows read step 4\)"'
# T3: the step-by-step route's snapshot line is true on a re-run too
check "retrofit-it fresh-build ask: the step-by-step snapshot line is true on a re-run too (it keeps the earlier run's snapshot)" \
  'printf "%s\n" "$R5_FBS" | gq -iE "\[first run: .I save a snapshot first, so I can put your files back.; re-run: .I keep the snapshot from your earlier run: putting the files back returns to before that run.\]"'
# T4 + T6: after either undo, in `work`, the missing TODO.md lines come back, and the state file notes the undo, its section kept
check "retrofit-it undo: after either undo, in \`work\`, each left-out item's missing TODO.md line comes back from the record, and the state file notes the files went back with the section kept as it is" \
  'printf "%s\n" "$F3_UPROSE" | gq -iE "After either undo, in .work., write each left-out item.s missing TODO_md line back from the record" && printf "%s\n" "$F3_UPROSE" | gq -iE "note in .?make-it-state_md.? that the files went back \(to before this step, or before the upgrade started\), keeping .## Left out by your choice. exactly as it is"'
# T5: the fresh-build stop reads the whole record, never "an earlier run"
check "retrofit-it fresh-build stop: the record is the whole record (read step 2), never narrowed to \"an earlier run\"" \
  'printf "%s\n" "$R5_FBS" | gq -iE "already in the record \(read step 2 of" && printf "%s\n" "$R5_FBS" | gq -iE "this time or earlier\]" && ! printf "%s\n" "$R5_FBS" | gq -iE "\b(from|on) an earlier run\b"'
# T7: the worktree brackets name all five commands that read or write the state file; the closing line says where
# (final fix review Minor 5: by folder -- "in this conversation (I run it in [WORKTREE_DIR])", never a bare "here")
t7_five() { local b c; for b in "$(f2_wtstop | paste -sd' ' -)" "$(f3_wtb "$F3_SHIP" | paste -sd' ' -)"; do for c in /retrofit-it /resume-it /try-it /wrap-it /ship-it; do printf "%s\n" "$b" | gq -F -- "$c" || return 1; done; done; }
check "retrofit-it worktree brackets name all five commands that read or write the state file (/retrofit-it, /resume-it, /try-it, /wrap-it, /ship-it), and the closing /ship-it line says where" \
  't7_five && printf "%s\n" "$F3_SHIP" | flat | gq -E "just type: \*\*/ship-it\*\*\[work in a worktree: . -- in this conversation \(I run it in \[WORKTREE_DIR\]\), or in \[WORKTREE_DIR\] next time.\]" && ! printf "%s\n" "$F3_SHIP" | flat | gq -E "/ship-it\*\*\[work in a worktree: . -- here\b"'
# T8: Phase 7's success list follows the record now
check "retrofit-it Phase 7: the success list is what is built and not in the record now (work's state file), never keyed to the plan pick" \
  'printf "%s\n" "$F3_SHIP" | flat | gq -E "\[Only what is built and not in the record now \(.work..s .\.make-it-state\.md.\) -- drop the line for any item in it\.\]" && ! printf "%s\n" "$F3_SHIP" | gq -F "[Only what they included at the plan ask"'
# T9: rule 7's left-out test leaves out a sign-in brought back at the plan ask
check "retrofit-it guardrails rule 7: a sign-in the user brings back at the plan ask is not left out (\"one they bring back at the plan ask is not\")" \
  'printf "%s\n" "$A2_G7" | r5_md | gq -iE "unless secure login is left out \(the record, .left-out-record_md.; one they bring back at the plan ask is not\)"'
# T10: step 4's skip is its first bullet; steps 7-8 add mock-oidc and its users only when secure login is not left out
check "retrofit-it Phase 5a step 4: the left-out sign-in skip is the step's first bullet, before \"If no auth exists\"" \
  'printf "%s\n" "$F4_S4" | r5_un | grep -E "^ *- " | head -1 | gq -F "**Secure login left out** (\`left-out-record.md\`): there is no pick; skip this whole step, mock-oidc included."'
F4_S78="$(awk '/^7\. \*\*Mock Services/{on=1} on&&/^9\. \*\*/{exit} on' $RETRO | r5_un | grep -iE '^ *- (\*\*mock-oidc|Ensure seed users match mock-oidc)' || true)"
check "retrofit-it steps 7-8: mock-oidc and its seed users are added only when secure login is not left out" \
  '[ "$(printf "%s\n" "$F4_S78" | grep -c .)" = 2 ] && printf "%s\n" "$F4_S78" | a2_skip'
# T11: the HEAD aside names a first run and a worktree plainly
check "retrofit-it Phase 5's Execution model: the HEAD aside says \"on a first run, the snapshot\" and \"in a worktree too\"" \
  'printf "%s\n" "$F2_EXEC" | flat | gq -F "(on a first run, the snapshot; on a re-run, where \"Stop here\" left the upgrade so far, in a worktree too)"'
# final fix review Minor 3: a record item the user brings back at the plan ask counts again -- the score and the route are
# recomputed with it before they pick -- and gap analysis points there (never "keeps the route", never "still not scored")
check "retrofit-it: a record item brought back at the plan ask counts again -- recompute the score and the route with it before they pick (gap analysis says so too)" \
  'printf "%s\n" "$PLAN" | r5_pa | gq -iF "an item they bring back at the plan ask counts again: recompute the score and the route with it before they pick" && printf "%s\n" "$GAP" | r5_pa | gq -F "(one they bring back at the plan ask counts again: see **Read the record first** in the plan)" && ! { printf "%s\n" "$PLAN"; printf "%s\n" "$GAP"; } | r5_pa | grep -iE "bring back at the plan ask" | r5_aff | gq -iE "\b(keeps?|kept|leaves?|left)\b[^.;:]{0,20}\b(the )?(score|route|risk level)\b|\b(score|route|risk level)\b[^.;:]{0,20}\b(stays?|kept|unchanged|as (it|they) (is|are|was|were))\b|\bstill\b[^.;:]{0,10}\b(not )?(scored|counted|out of)"'
}
exec 3>&1
R5_ERR="$( (fail=0; r5_all 2>&1 1>&3; exit $fail) )" || fail=1
exec 3>&-
check "Task 5 checks wrote nothing to stderr (a bad regex fails here, not silently)" '[ -z "$R5_ERR" ] || { printf "  stderr: %s\n" "$R5_ERR"; false; }'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
