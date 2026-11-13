#!/usr/bin/env bash
# E05-S2 Task 1: ship-it-guide.md carries the go-live checklist contract, in one section, "## Go-live checklist", right
# after "### Left-out items before production". Every production /ship-it shows five go-live items and keeps their state
# in a committed `.ship-it-go-live.json`; it is a checklist, not a gate.
# Contract these checks pin (one group per rule of the task brief, each by its meaning, polarity-bound):
#   1. trigger: SHIP MODE into main whatever the intent label, when the workflow deploys to production (four signals);
#      AWS and VLF always; SAVE never; a re-run asks nothing (only a new request asks; owner, 2026-10-21)
#   2. when: after intent classification and the left-out ask, before the first commit, in the same push
#   3. the record: file, owner, shape (the example parses: five keys in order, four fields), failure handling
#   4. asked again: skipped or missing on every production /ship-it; done and na quiet; na remembered
#   5. the asks: high-stakes (approval-block.md), decision-ready; items 2-5 recorded skipped, reason `coming soon`
#   6. item 1: where it looks (deployment.dev_url, else the local app; never starts it), served, topics, the lawyer line
#   7. the PR section: five lines after "Before going live"; the left-out lines in their own list; AWS/VLF final message
#   8. left-out separation (left-out-record.md) and no secret in the record (the pattern list spelled out)
#   and the guide's other "go-live checklist" mentions point at the section instead of restating it.
# Usage: test-go-live-checklist.sh [GUIDE]. With no GUIDE it checks the real guide, then runs its controls.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail (a negated check goes green); gq reads all.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT
flat() { tr '\n' ' ' | tr -s ' '; }

G="${1:-.claude/make-it/references/ship-it-guide.md}"
H='## Go-live checklist'
# the section: from its heading (outside code fences) to the next "## " heading
SEC="$(awk -v h="$H" '/^```/{f=!f} !f&&/^## /{on=($0==h)} on' "$G")"
# units: a paragraph or a list item, code fences and headings left out; then one sentence per line
units() { awk '/^```/{f=!f; if(u!="")print u; u=""; next} f{next}
  /^[[:space:]]*$/ || /^#/ {if(u!="")print u; u=""; next}
  /^ *([-*] |[0-9]+\. )/ {if(u!="")print u; u=$0; next}
  {u=(u=="")?$0:u" "$0} END{if(u!="")print u}' | tr -s ' '; }
sents() { perl -pe 's/([.!?]["\x27)]?) (?=\S)/$1\n/g'; }
# each line "RAW<US>AFF": AFF is RAW with every negated clause cut (never/not/no/n't ... up to , . ; :), so a "+pattern"
# (matched on AFF) is only met where the text affirms it -- the rule's plain opposite ("is never asked") misses it
pair() { perl -ne 'chomp; my $r = $_; s/\.(?=\w)/\x01/g; s/\b(?:never|not|no|none|nothing|neither|nor|cannot|without)\b[^,.;:]*//gi; s/\b\w+n\x27t\b[^,.;:]*//gi; s/\x01/./g; print "$r\x1f$_\n"'; }
PAIRS="$(printf '%s\n' "$SEC" | units | sents | pair)"
UPAIRS="$(printf '%s\n' "$SEC" | units | pair)"
FLAT="$(printf '%s\n' "$SEC" | awk '/^```/{f=!f;next} !f' | flat)"
# sel P...: the sentences that match every pattern (ERE, any case); "+P" is matched on the affirmed text only
sel() { local s="$PAIRS" p; for p in "$@"; do
  case "$p" in +*) s="$(printf '%s\n' "$s" | grep -iE -- $'\x1f'".*(${p#+})" || true)";; *) s="$(printf '%s\n' "$s" | grep -iE -- "$p" || true)";; esac
  done; printf '%s' "$s"; }
says()  { [ -n "$(sel "$@")" ]; }
usays() { local PAIRS="$UPAIRS"; says "$@"; }
infl()  { printf '%s' "$FLAT" | gq -iE -- "$1"; }

# the record's checks: the shape the example must have, and the test's own secret check (constraint 6's pattern list)
export SECRET_RE='sk-|AKIA|ghp_|github_pat_|-----BEGIN|(?i:password|token|secret)=|[A-Fa-f0-9]{32,}|[A-Za-z0-9+/]{32,}={0,2}'
PY='
import json, os, re, sys
keys = ["terms_privacy", "security_audit", "restore_test", "load_test", "live_payment"]
d = json.loads(sys.stdin.read()); items = d["items"]; sec = re.compile(os.environ["SECRET_RE"])
if sys.argv[1] == "shape":
    ok = (list(d) == ["schema", "items"] and d["schema"] == 1 and list(items) == keys
          and all(sorted(v) == ["date", "evidence", "reason", "state"] and all(isinstance(x, str) for x in v.values())
                  and v["state"] in ("done", "skipped", "na") and re.fullmatch(r"\d{4}-\d{2}-\d{2}", v["date"])
                  for v in items.values())
          and all(items[k]["state"] == "skipped" and items[k]["reason"] == "coming soon" for k in keys[1:]))
else:
    ok = all(len(v["reason"]) <= 200 and not sec.search(v["reason"]) and not sec.search(v["evidence"])
             and not re.search(r"\?|//[^/\s]*@", v["evidence"]) for v in items.values())
sys.exit(0 if ok else 1)
'
rec() { python3 -I -c "$PY" "$1" 2>/dev/null; }
# the section's example record: its fenced block that holds "schema"
JSON="$(printf '%s\n' "$SEC" | awk '/^```/{if(f){if(b~/"schema"/){printf "%s",b; exit} b=""} f=!f; next} f{b=b $0 "\n"}')"

# 0. one section, right after the left-out section
HEADS="$(awk '/^```/{f=!f;next} !f&&/^#/' "$G")"
check "placement: one \"$H\" heading, the first heading after \"### Left-out items before production\"" \
  '[ "$(printf "%s\n" "$HEADS" | grep -cxF "$H")" = 1 ] && [ "$(printf "%s\n" "$HEADS" | grep -A1 -xF "### Left-out items before production" | tail -1)" = "$H" ]'

# 1. the trigger
check "rule 1 (trigger): in SHIP MODE a request into main runs it, whatever its intent label, when the repo's workflow deploys to production" \
  'says "SHIP MODE" "+\bmain\b" "+\b(whatever|any|regardless of|every)\b[^.]{0,20}\bintent\b" "+deploys? to production"'
# (re-pointed by R3, final review: the owner's 2026-10-18 answer counts a workflow with a production deploy job, so the
# no-workflow bullet may say either "deploys to production on merge" or "has a production deploy job"; R3's own check
# below pins that it agrees with the Workflow Generation table; A4 adds "carries a production deploy on merge")
check "rule 1 (trigger): a production workflow is a job on deployment.environments.production (default production), a deploy-prod job, a reusable caller's environment-prod, or none yet (every one ship-it generates deploys to production on merge, has a production deploy job, or carries a production deploy on merge)" \
  'says "deployment\.environments\.production" "+default[^.]{0,5}production" && says "+deploy-prod" && says "+environment-prod" && says "no workflow" "+generat" "+deploys? to production on merge|\bproduction deploy (job|on merge)\b"'
check "rule 1 (trigger): AWS and VLF modes always run it; SAVE mode never does" \
  'says "\bAWS\b" "\bVLF\b" "+\balways\b" && says "(\bSAVE\b|/ship-it save\b)[^.;]{0,30}\b(never|not|doesn.t|does not)\b" && ! says "+(\bSAVE\b|/ship-it save\b)[^.;]{0,30}\b(runs?|triggers?|asks?|shows?)\b"'
check "rule 1 (trigger): a re-run (RE-RUN, a request already open) asks nothing -- only a new request asks -- and the PR section stays as written (owner, 2026-10-21)" \
  'says "\bRE-?RUN\b|\bre-?runs?\b|already open" "\b(asks nothing|nothing is asked|no asks?|(doesn.t|does not|never|won.t) ask|(is|are) not asked|isn.t asked|aren.t asked)\b" && says "+\bonly (a|the) new (request|/ship-it)\b" && says "\bas written\b|\b(stays?|remains?|is left|left) (the same|unchanged|alone)\b"'

# 2. when
check "rule 2 (when): after intent classification and the left-out ask, before the first commit, so the record goes out in the same push" \
  'says "+\bafter\b[^.]{0,80}\bintent classification\b" "+left-out ask" "+\bbefore the first commit\b" && says "+\bsame push\b"'

# 3. the record
check "rule 3 (record): .ship-it-go-live.json sits at the repo root, committed, owned by ship-it -- not in .ship-it.yml (DevOps owns it) or app-context.json (ship-it works without make-it)" \
  'usays "\.ship-it-go-live\.json" "+repo root|root of the repo|repository root|repo.s root" "+\bcommitted\b" "+ship-it owns it|owned by /?ship-it" && says "\.ship-it\.yml" "DevOps" "app-context\.json" "without make-it" "\b(can.t|cannot|not|never)\b"'
check "rule 3 (record): the example parses and is exactly {schema:1, items:{the five keys in order:{state, reason, date, evidence}}} (items 2-5 skipped, coming soon); states done|skipped|na; no history array, the git log is the history" \
  '[ -n "$JSON" ] && printf "%s" "$JSON" | rec shape && says "\`done\`" "\`skipped\`" "\`na\`" && says "no history" "+git log"'
check "rule 3 (record): an unknown key is ignored; a missing item or an unknown state is asked; an unreadable file -- say so in one line, ask all five, rewrite it (git keeps the old one)" \
  'says "+unknown key" "+\bignored\b" && says "+missing" "+unknown state" "+\b(is|are|gets?) asked\b|\basks? (it|them)\b" && says "unreadable|can.t be read|cannot be read|malformed|broken|invalid" "+one line" "+all five" "+\brewrites?\b" "+\bgit\b"'

# 4. asked again (the control at the end deletes this sentence and expects this check red)
AGAIN=( '`?skipped`?' '\bmissing\b' '+\b(are|is|get|gets) asked( again)?\b' '+\b(every|each) production /ship-it\b' )
AGAIN_L='rule 4 (asked again): skipped or missing items are asked on every production /ship-it'
check "$AGAIN_L" 'says "${AGAIN[@]}"'
check "rule 4 (asked again): done and na stay quiet with one PR line each; na is remembered; an item changes only when the user asks" \
  'says "\`done\`" "\`na\`" "+\bquiet\b" "+one (PR )?line" && says "\`na\`" "+\bremembered\b" && says "+\bchanges? only when the user asks\b|\bonly the user.{0,30}\bchange"'

# 5. the asks
check "rule 5 (asks): high-stakes active confirmation (approval-block.md) -- a pick per item, never one answer for all; a skip needs a reason the user types, no default reason, never a plain yes" \
  'infl "approval-block\.md" && says "+active confirmation" && says "+\bown pick\b" && says "never one answer for all|never (one|a single) (answer|pick) for (all|every)" && says "\bskip" "+\breason\b" "+\b(types?|typed)\b" && says "no default reason" && says "\b(never|not|no|nor) (a )?plain yes\b|\bplain yes\b[^.]{0,20}\b(isn.t|is not|never)\b"'
check "rule 5 (asks): every ask is decision-ready -- what changes, the evidence, the blast radius and undo, what is unusual, the one thing to check" \
  'usays "decision-ready" "+what changes" "+\bevidence\b" "+blast radius" "+\bundo\b" "+unusual" "+one thing to check"'
check "rule 5 (asks): items 2-5 are not asked -- recorded skipped with the exact reason \`coming soon\` -- and ship-it says so in one line" \
  'says "\bitems? 2.{1,4}5\b|\bitems 2 (to|through) 5\b|\bthe other four\b" "not asked|(aren.t|are not|never) asked|no ask" "+\`?skipped\`?" "+\`coming soon\`" && says "\`coming soon\`|\bitems? 2.{1,4}5\b" "+\bone line\b"'
check "rule 5 (asks): it is a checklist, not a gate -- no answer stops the request" \
  'says "\bnot a gate\b|\bno answer\b[^.]{0,30}\b(stops|blocks)\b|\bnever (stops|blocks)\b[^.]{0,20}\brequest\b"'

# 6. item 1, terms & privacy
check "rule 6 (item 1, where): the base URL is deployment.dev_url in .ship-it.yml (DevOps fills it) when set, otherwise the local app -- the frontend port from app.services, else the port docker-compose publishes; ship-it never starts the app" \
  'infl "deployment\.dev_url.{0,250}\b(otherwise|else|until)\b.{0,120}\blocal app" && says "deployment\.dev_url" "+DevOps" && says "+frontend" "+app\.services" && says "+docker.?compose" "+publish" && says "\bnever starts?\b[^.]{0,15}\b(the )?app\b|\b(doesn.t|does not) start\b[^.]{0,15}\b(the )?app\b" && ! says "+\bstarts? (the|your) app\b"'
check "rule 6 (item 1, served): GET /terms and /privacy; a page is served when it returns 200 and the final URL is still that path; a redirect to sign-in is not served" \
  'says "\bGETs?\b" "/terms" "/privacy" && says "+\b200\b" "+final URL" "+\b(still|same|that) path\b" && says "redirect" "sign.?in" "\bnot served\b|\bisn.t served\b"'
check "rule 6 (item 1, topics): terms mention user content and arbitration, privacy mentions personal data; done only when both pages are served and all three topics are found" \
  'says "+terms" "+user content" "+arbitration" && says "+privacy" "+personal data" && says "\`done\`" "+\bonly (when|if)\b" "+\bboth pages\b" "+\b(all )?three topics\b|\ball three\b"'
check "rule 6 (item 1, done): the user is told to have a lawyer review the pages; the PR line reads \"pages found -- not a legal review\"; make-it and ship-it never write, draft or suggest terms or privacy wording" \
  'says "+\blawyer\b" "+\breview" && printf "%s" "$FLAT" | gq -F "\"pages found -- not a legal review\"" && says "\bnever\b" "\bwrites?\b" "\bdrafts?\b" "\bsuggests?\b" "terms|privacy" "\b(wording|text)\b" "\bmake-it\b"'
check "rule 6 (item 1, otherwise): ship-it names what is missing, and the user picks skipped with a reason they type, or na" \
  'says "+\bnames? what.{0,15}missing\b" "\`skipped\`" "+\b(types?|typed)\b" "\`na\`"'

# 7. the PR section
check "rule 7 (PR): the PR's ## Go-live checklist has five lines in item order, \`state -- reason (date)\`, after \"Before going live\" (still the DevOps setup list)" \
  'says "## Go-live checklist" "+five lines" "+item order|in order" && infl "\[?state\]? -- \[?reason\]? \(\[?date\]?\)" && says "+\bafter\b[^.]{0,6}\"?\**Before going live" "+DevOps setup"'
check "rule 7 (PR): the left-out lines go under the same heading, in their own list; AWS and VLF have no PR, so the five lines go in the final message" \
  'says "+left-out lines" "+same heading" "+own list" && says "\bAWS\b" "\bVLF\b" "no PR|no pull request" "+final message"'
STEP="$(awk '/^\*\*Behind the scenes, \/ship-it:\*\*/{on=1;next} on&&/^$/{exit} on' "$G" | awk '/^[0-9]+\. /{p=($0 ~ /^[0-9]+\. Creates a PR/)} p' | flat)"
check "rule 7 (PR): the PR step names both \"Before going live\" and the go-live checklist, points at Go-live checklist, and no longer limits it to intent:prod-ready" \
  'printf "%s" "$STEP" | gq -F "Before going live" && printf "%s" "$STEP" | gq -E "(\(|\bsee )(the )?Go-live checklist\b" && ! printf "%s" "$STEP" | gq -iE "prod-ready[^.;]{0,15}go-live checklist"'

# 8. left-out separation (constraint 5) and no secret in the record (constraint 6)
check "rule 8 (left-out): the go-live record is not the left-out record -- a go-live skip never goes under ## Left out by your choice, and a left-out item never becomes a go-live ask" \
  'says "not the left-out record" && says "## Left out by your choice" "\b(never|not)\b" "go-live|skip" && says "left-out item" "\bnever\b[^.]{0,40}\b(becomes?|turns? into|is)\b[^.]{0,20}\bgo-live ask|\bnever\b[^.]{0,30}\b(asked|an ask)\b"'
check "rule 8 (left-out): a go-live check that belongs to a left-out item (read step 3 of left-out-record.md) reads \"Left out (your choice)\" -- never FAIL, never done" \
  'says "Left out \(your choice\)" "\bnever FAIL\b" "\bnever\b[^.]{0,30}\`?done\b" && infl "read step 3" && infl "left-out-record\.md"'
check "rule 8 (left-out): the left-out ask and the secret stop come first and keep their own rules; after \"Add [item] first\" the checklist doesn't run" \
  'says "left-out ask" "secret stop" "+\b(before|first)\b" "+own rules" && says "Add \[item\] first" "\b(doesn.t|does not|never|won.t) run"'
check "rule 8 (secrets): fixed fields only; reason is the user's own words, at most 200 characters, refused and asked again without the secret when it matches a pattern; ship-it runs that check itself before the commit" \
  'says "+fixed fields" && says "reason" "+user.s own words" "+200 characters" && says "+\brefused\b" "+asked again" "without the secret" && says "+\bbefore the commit\b" "\b(check|secret)"'
check "rule 8 (secrets): the section spells out the pattern list -- sk-, sk-ant-, AKIA, ghp_, github_pat_, -----BEGIN, password=, token=, secret=, a hex or base64 run of 32+" \
  '( for p in "sk-" "sk-ant-" "AKIA" "ghp_" "github_pat_" "-----BEGIN" "password=" "token=" "secret="; do printf "%s" "$FLAT" | gq -F -- "$p" || exit 1; done ) && says "\bhex\b" "base64" "\b32\b"'
check "rule 8 (secrets): evidence is a URL with no query string and no user:pass@, or a repo-relative path; never amounts, card, bank or account details, or row data" \
  'says "evidence" "no query string|without (a )?query string" "user:pass@" "repo-relative" && says "\bnever\b" "amounts" "\bcard\b" "\bbank\b" "account" "row data"'
check "rule 8 (secrets): the example record holds nothing the test's own secret check flags (patterns, a query string, user:pass@, a reason over 200 characters)" \
  '[ -n "$JSON" ] && printf "%s" "$JSON" | rec secrets'

# the rest of the guide points at the section; it doesn't restate it
OUT="$(awk -v h="$H" '/^```/{f=!f} !f&&/^## /{off=($0==h)} !off' "$G" | units)"
GL="$(printf '%s\n' "$OUT" | grep -iF 'go-live checklist' || true)"
RESTATE='\.ship-it-go-live\.json|terms_privacy|security_audit|restore_test|load_test|live_payment|`coming soon`|state\]? -- \[?reason|not a legal review'
check "other mentions: each \"go-live checklist\" elsewhere in the guide (the PR step, the left-out section, the CI/CD contract) points at Go-live checklist, and none restates it" \
  '[ "$(printf "%s\n" "$GL" | grep -c .)" -ge 3 ] && ! printf "%s\n" "$GL" | grep -vE "(\(|\bsee )(the )?Go-live checklist\b" | gq . && ! printf "%s\n" "$OUT" | gq -iE "$RESTATE"'
check "only the guide names .ship-it-go-live.json among the skills and references (resume-it.md reads it through the guide)" \
  '[ "$(grep -rlF --exclude-dir=worktrees ".ship-it-go-live.json" .claude | grep -vxF .claude/commands/resume-it.md | sort)" = ".claude/make-it/references/ship-it-guide.md" ]'

# ---- fix round 1: the coordinator's four calls (task-1-fix1-brief.md); the guide stays true to /ship-it v1.3.0 ----
# call 1: ship-it v1.3.0 doesn't run the checklist yet, so the not-yet list names it in a bullet of its own
NOTYET_SEC="$(awk '/^#/{on=(index($0,"### Safety steps /ship-it doesn")==1)} on' "$G" | units)"
check "fix 1 (not-yet list): \"Safety steps /ship-it doesn't run yet\" lists the go-live checklist in its own bullet, pointing at Go-live checklist" \
  'printf "%s\n" "$NOTYET_SEC" | grep -E "^- \*\*[^*]*[Gg]o-live checklist[^*]*\*\*" | gq -E "\((see )?(the )?Go-live checklist\b"'
# call 2: VLF may commit the record (owner, 2026-10-21), but VLF's allowed list doesn't hold it today (Task 3 adds it),
# so no sentence anywhere in the guide says, in the present tense, that the list holds it
GPAIRS="$(units < "$G" | sents | pair)"
gsays() { local PAIRS="$GPAIRS"; says "$@"; }
VLFNOW='\b(is|are|sits|stays|already)\b[^.;:]{0,40}\b(on|in)( the| its| VLF.s| the VLF)? allow(ed)?[- ]list\b|\ballow(ed)?[- ]list\b[^.;:]{0,20}\b(holds|has|includes|lists|admits|contains|already|covers)\b'
check "fix 2 (VLF): VLF mode still commits the record, and no sentence says VLF's allowed list already holds it" \
  'says "+\bVLF\b[^.;:]{0,30}\b(commits?|may (also )?commit|can commit|will commit|is allowed to commit)\b[^.;:]{0,12}\.?(\bit\b|\bthe record\b|ship-it-go-live)" && ! gsays "+$VLFNOW"'
# call 3: a go-live item that belongs to a left-out item is quiet only while the item is left out; brought back, it is
# asked; and the asked-again sentence itself names both kinds it doesn't ask
check "fix 3 (left-out bound): a go-live item of a left-out item isn't asked while the item is left out; once brought back it is asked; the asked-again rule names its two exceptions (coming soon, Left out (your choice))" \
  'says "\b(isn.t|is not|not|never) asked\b[^.;]{0,40}\bwhile\b[^.;]{0,40}\bleft out\b" && says "\bbr(ing|ings|ought)\b[^.;]{0,25}\bback\b|\badd(s|ed)?\b[^.;]{0,25}\bback\b" "+\basked\b" && says "${AGAIN[@]}" "\b(except|but not|other than|apart from|unless)\b" "coming soon" "Left out \(your choice\)"'
# fix round 2 (re-review 1, Important 2 residual): the reason "Left out (your choice)" outlives the left-out state, so the
# asked-again rule's exception for it holds only while the item is still left out -- every asked-again sentence that names
# it carries that bound, and none says the opposite ("even once brought back", "whether or not", "no longer left out")
ASKBOUND='Left out \(your choice\)"?[^.;]{0,60}\b(while|as long as|so long as)\b[^.;]{0,40}\bleft out\b|Left out \(your choice\)"?[^.;]{0,60}\buntil\b[^.;]{0,40}\b(brought|comes) back\b'
ASKUNB='\beven\b[^.;]{0,15}\b(once|after|when|if|though)\b|\b(whether|regardless)\b[^.;]{0,40}\bleft out\b|\b(no longer|not|isn.t) left out\b|\b(not|never|isn.t|aren.t) asked\b[^.;]{0,30}\b(once|after|when|if)\b[^.;]{0,30}\bbr(ought|ing|ings)\b'
askbound() { local s; s="$(sel "${AGAIN[@]}" 'Left out \(your choice\)' | cut -d $'\x1f' -f1)"
  [ -n "$s" ] && ! printf '%s\n' "$s" | grep -viE "$ASKBOUND" | gq . && ! printf '%s\n' "$s" | gq -iE "$ASKUNB"; }
check "fix round 2 (Asking bound): the asked-again rule's \"Left out (your choice)\" exception holds only while the item is still left out (never \"even once brought back\", never unbounded)" \
  'askbound'
# call 4: the .ship-it.yml example documents deployment.dev_url -- an empty or placeholder value (never a host), with a
# comment (on its line or right above it) that DevOps fills it in and the go-live checklist reads it
YML="$(awk '/^## /{on=($0=="## .ship-it.yml Configuration")} on' "$G" | awk '/^```/{if(f)exit; f=1; next} f')"
DEVL="$(printf '%s\n' "$YML" | awk '/^[^ #]/{d=($0 ~ /^deployment:/)} d && /^ +dev_url:/{print; exit}')"
DEVC="$(printf '%s\n' "$YML" | awk '/^[^ #]/{d=($0 ~ /^deployment:/)} d && /^ +dev_url:/{print c; exit} {c=($0 ~ /^ *#/)?c" "$0:""}')"
devurl_ok() { local v c; [ -n "$DEVL" ] || return 1
  v="$(printf '%s' "$DEVL" | sed -E 's/^ *dev_url:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d "\"'")"
  { [ -z "$v" ] || printf '%s' "$v" | gq -E '^[[<{].*[]>}]$'; } && ! printf '%s' "$v" | gq -iE '://|\.[a-z]{2,}|localhost|[0-9]\.[0-9]' || return 1
  c="$DEVC $(printf '%s' "$DEVL" | sed -n 's/^[^#]*#//p')"
  printf '%s' "$c" | gq -F DevOps && printf '%s' "$c" | gq -iE '\bfill' && printf '%s' "$c" | gq -iE 'go-live'; }
check "fix 4 (dev URL): the .ship-it.yml example has deployment.dev_url, empty or a placeholder (no host), with a comment that DevOps fills it in and the go-live checklist reads it" \
  'devurl_ok'

# ---- adversarial round 1: ten counterexamples on their exact inputs (task-1-adv1.md; calls in task-1-adv1-fix-brief.md) ----
# Behaviour checks read the rule's operative words from the guide, then run that rule on the counterexample's input.
PY2='
import json, re, sys
from urllib.parse import urlsplit
m = sys.argv[1]
if m == "evidence":                        # the components the guide keeps, applied to a URL with user:pass, query, fragment
    t = sys.argv[2].lower(); u = urlsplit(sys.argv[3]); pw = sys.argv[4]
    has = lambda *w: any(re.search(r"\b" + x + r"\b", t) for x in w)
    out = u.scheme + "://" if has("scheme", "protocol") else ""
    if has("user", "username", "credentials", "login"):
        out += (u.username or "") + (":" + u.password if has("password") and u.password else "") + "@"
    out += (u.hostname or "") if has("host", "hostname", "domain") else ""
    out += ":" + str(u.port) if has("port") and u.port else ""
    out += u.path if has("path") else ""
    out += "?" + u.query if has("query") and u.query else ""
    out += "#" + u.fragment if has("fragment") and u.fragment else ""
    ok = out == "https://dev.example.com/terms" and pw not in out
elif m == "served":                        # served = final path is /terms (a trailing slash allowed?, query/fragment ignored?)
    s, q = sys.argv[2] == "1", sys.argv[3] == "1"
    def served(url):
        u = urlsplit(url); p = u.path if q else u.path + ("?" + u.query if u.query else "") + ("#" + u.fragment if u.fragment else "")
        return p == "/terms" or (s and p == "/terms/")
    ok = all(served(x) == e for x, e in [("http://localhost:3000/terms/", True), ("http://localhost:3000/terms?lang=en", True),
             ("http://localhost:3000/terms/#top", True), ("http://localhost:3000/login?next=/terms", False), ("http://localhost:3000/terms//", False)])
elif m == "join":                          # dev_url + /terms (trailing slash not doubled?, a path in dev_url kept?)
    nd, pk = sys.argv[2] == "1", sys.argv[3] == "1"
    def join(b):
        b = b.rstrip("/") if nd else b
        if not pk: u = urlsplit(b); b = u.scheme + "://" + u.netloc
        return b + "/terms"
    ok = all(join(x) == e for x, e in [("https://dev.example.com/app/", "https://dev.example.com/app/terms"),
             ("https://dev.example.com/app", "https://dev.example.com/app/terms"), ("https://dev.example.com/", "https://dev.example.com/terms")])
elif m == "unreadable":                    # the definition of "unreadable" in the guide, applied to an empty, a truncated, a schema-2 file
    t = " ".join(x.group(1) for x in re.finditer(r"unreadable\b[^.;]{0,15}?\b(?:when|if|means)\b([^.;]*)", sys.argv[2].lower()))
    E = "empty" in t; J = re.search(r"valid json|not json|isn.t json|pars", t) is not None
    O = "object" in t; S = re.search(r"schema[^.;]{0,30}\b1\b", t) is not None
    def bad(x):
        if x.strip() == "": return E or J
        try: d = json.loads(x)
        except ValueError: return J
        if not isinstance(d, dict): return O
        return S and d.get("schema") != 1
    ok = all(bad(x) for x in ["", "{\"schema\": 1, \"items\": [", "{\"schema\": 2, \"items\": {}}", "[]"]) and not bad("{\"schema\": 1, \"items\": {}}")
sys.exit(0 if ok else 1)
'
py2() { python3 -I -c "$PY2" "$@" 2>/dev/null; }
AFF="$(printf '%s\n' "$PAIRS" | cut -d $'\x1f' -f2)"

# call 1: topics are read from the visible text -- tags AND the contents of <script>, <style>, <noscript> removed -- so a page
# whose words sit only in a client payload (the scaffold's "use client" sign-in layout) finds no topics and isn't done
C1E="$(printf '%s\n' "$AFF" | perl -ne 'print "$1\n" while /(?:remov|strip|drop|delet)\w*\b[^.;:]{0,20}?\bcontents?\s+of\s+([^.;:]*)/gi; print "$1\n" while /([^.;:]*?)\bcontents?\b[^.;:]{0,15}\b(?:removed|stripped|dropped|deleted)\b/gi' | grep -oE '<[a-z]+>' | tr -d '<>' | sort -u || true)"
c1_strip() { local e x; x="$(cat)"; for e in $C1E; do x="$(printf '%s' "$x" | perl -0pe "s/<$e\\b[^>]*>.*?<\\/$e\\s*>//gis")"; done; printf '%s' "$x" | perl -0pe 's/<[^>]*>/ /g'; }
c1_done() { local t p; t="$(printf '%s' "$1" | c1_strip)"; p="$(printf '%s' "$2" | c1_strip)"
  printf '%s' "$t" | gq -iE 'user content' && printf '%s' "$t" | gq -iE 'arbitration' && printf '%s' "$p" | gq -iE 'personal data'; }
T_AUTH='<html><head><style>.s{}</style></head><body><div class="spinner">Loading</div><script>self.__next_f.push([1,"Terms. By posting user content you agree to arbitration."])</script></body></html>'
P_AUTH='<html><body><div class="spinner">Loading</div><script>self.__next_f.push([1,"Privacy. How we use personal data."])</script></body></html>'
T_PUB='<html><body><main><h1>Terms</h1><p>Your user content stays yours. Disputes go to arbitration.</p></main><script>boot()</script></body></html>'
P_PUB='<html><body><main><h1>Privacy</h1><p>How we use personal data.</p></main></body></html>'
check "adv 1 (client payload): the topic rule removes tags and the contents of <script>, <style> and <noscript>; on pages whose words sit only in a <script> payload it finds no topics (not done), on public pages it finds all three" \
  '( for e in script style noscript; do printf "%s\n" "$C1E" | gq -xF "$e" || exit 1; done ) && ! c1_done "$T_AUTH" "$P_AUTH" && c1_done "$T_PUB" "$P_PUB"'

# call 2: a re-run whose PR has no "## Go-live checklist" never asked, so it runs the checklist as a new request does
# (the draft that /ship-it save opened, shipped later); the re-run rule itself stays
c2_ok() { local s; s="$(sel '\bRE-?RUN\b|\bre-?runs?\b' 'no `?## Go-live checklist|without (a |the )?`?## Go-live checklist|never asked|hasn.t been asked' '\b(as|like) (a |any )?(new|first) request\b' | cut -d $'\x1f' -f1)"
  [ -n "$s" ] && ! printf '%s\n' "$s" | gq -iE '\b(doesn.t|does not|never|won.t) (run|ask)\b' && usays '/ship-it save|\bSAVE\b' '\bdraft\b' '+\b(runs?|asks?)\b'; }
check "adv 2 (save, then ship): a re-run whose PR has no ## Go-live checklist runs the checklist as a new request does (the /ship-it save draft is the example)" 'c2_ok'

# call 3: "coming soon" is recorded only on items 2-5 that are missing or skipped; a done or na the user set stays as it is;
# the one line names only what it recorded this time; the PR line shows each item as the record holds it
check "adv 3 (hand-set done/na on items 2-5): coming soon only for missing or skipped ones, a done or na stays as it is, the one line names only those recorded this time, the PR line shows the record" \
  'says "\bitems? 2.{1,4}5\b" "\brecorded\b" "\`coming soon\`" "\b(that|which|when|if|while|only)\b[^.;:]{0,25}\bmissing\b|\bmissing or \`?skipped\`?" && ! says "\bitems? 2.{1,4}5\b" "\`coming soon\`" "\bmissing\b" "\b(whether|regardless|even (if|when|a|an|the))\b" && { says "\`done\`" "\`na\`" "+\b(stays?|kept|left|remains?) (as (it is|they are|set)|unchanged)\b" || says "\`done\`" "\`na\`" "\b(isn.t|is not|never|aren.t|are not) (overwritten|changed|replaced|touched)\b"; } && says "+\bonly\b[^.;]{0,50}\b(recorded|marked)\b" "+\bthis (time|run)\b|\bon this run\b|\bjust now\b" && says "\bPR\b" "+\bas the record holds (it|them)\b|\bas (it is|they are) (in|on) the record\b|\bas recorded\b"'

# call 4: evidence keeps scheme, host and path only -- applied to the dev.example.com terms URL with a basic-auth user and
# password, a query and a fragment (the URL and password are built at run time: no credential literal in this file), the query and the fragment never reach the record
C4K="$(printf '%s\n' "$AFF" | grep -iE 'evidence' | perl -ne 'print "$1\n" while /\b(?:written|recorded|kept|stored|saved)\s+as\s+([^.;:]*?)\s+only\b/gi' || true)"
C4PW="$(printf '%s%s' Sta9 ing-pw)"
C4U="$(printf '%s://%s%s%s@%s/terms?x-vercel-protection-bypass=%s#top' https preview : "$C4PW" dev.example.com abc123)"
check "adv 4 (credentials in evidence): evidence URLs are written as scheme, host and path only (user:pass@, query and fragment removed, never shown); on the dev.example.com terms URL with a basic-auth user and password, a query and a fragment, the record gets https://dev.example.com/terms" \
  '[ -n "$C4K" ] && py2 evidence "$C4K" "$C4U" "$C4PW" && says "user:pass@" "+\bquery\b" "+\bfragment\b" "+\b(removed|stripped|dropped)\b" && says "user:pass@|credentials" "\bnever (shown|shows?|displayed|said)\b"'

# call 5: "Skip for now" (or "skip") with no reason typed gets a request for the reason; nothing is recorded until one is
# typed; the pick's label, an empty string or a default reason is never recorded
c5_ok() { local s; s="$(sel 'Skip for now|\bskip\b' '\b(no|without( a| any)?) reason\b|\breason (isn.t|is not|wasn.t) typed' '\bask(s|ed)? (them |the user )?for (the|a|their) reason\b|\brequest(s)? for (the|a|their) reason\b|\basks? (them |the user )?to type (the|a|their) reason\b' | cut -d $'\x1f' -f1)"
  [ -n "$s" ] && ! printf '%s\n' "$s" | gq -iE '\b(never|not|doesn.t|does not|won.t|isn.t)\b[^.;]{0,20}\b(ask|asks|asked|request|requests|answered)\b' && says '\bnothing\b[^.;]{0,20}\b(recorded|written|saved)\b[^.;]{0,30}\buntil\b' && says '\b(label|Skip for now)\b' '\bempty\b' '\bdefault\b' '\bnever\b[^.;]{0,40}\b(recorded|written|used|stored|saved)\b'; }
check "adv 5 (skip without a reason): a skip pick with no reason typed is answered with a request for the reason; nothing is recorded until one is typed; the label, empty or a default is never recorded" 'c5_ok'

# call 6: with no production signal the checklist doesn't run, but the left-out lines still go in the PR under
# ## Go-live checklist, with one line that the five items weren't asked because the request doesn't deploy to production
check "adv 6 (left-out lines, no checklist): when the checklist doesn't run, the left-out lines still go under ## Go-live checklist, with one line saying the five items weren't asked (the request doesn't deploy to production)" \
  'gsays "(checklist|it) (doesn.t|does not) run|no production signal|(doesn.t|does not) deploy to production" "left-out lines" "+\bleft-out lines\b[^.;]{0,20}\b(still )?(go|goes|are put|are listed)\b" "## Go-live checklist" && gsays "\bfive\b[^.;]{0,40}\b(weren.t|were not|aren.t|are not|not) asked\b" "\b(doesn.t|does not|won.t) deploy to production\b"'

# call 7: "that path" allows one trailing slash and ignores a query or fragment the server adds; joining dev_url and /terms
# never doubles a slash and keeps a path in dev_url -- both run on the counterexamples' URLs
SLASH=0; QF=0; ND=0; PK=0
{ says 'trailing slash' '\bpath\b' '\bwith or without\b' || says 'trailing slash' '\bpath\b' '+\ballowed\b|\beither\b'; } && SLASH=1
says '\b(query|fragment)\b' '\b(doesn.t|does not|don.t|do not|never) change the path\b|\bpath\b[^.;]{0,30}\bignor' && QF=1
says 'trailing slash' 'dev_url|dev URL' '\b(isn.t|is not|never|not|no) doubled\b|\bnever doubles?\b' && ND=1
says '\bpath\b' 'dev_url|dev URL' '+\b(kept|keeps?)\b' && PK=1
check "adv 7 (trailing slash): /terms -> /terms/ (and ?lang=en, #top) is served, /terms// and /login?next=/terms are not; dev_url + /terms keeps dev_url's path and never doubles a slash (https://dev.example.com/app/ -> .../app/terms)" \
  'py2 served "$SLASH" "$QF" && py2 join "$ND" "$PK"'

# call 8: the local app is asked at the host port Docker publishes for the frontend (docker compose port), never at
# .ship-it.yml's port (the container port); nothing published -> nothing answered, asked as today; .env is never read
check "adv 8 (local port): the host port comes from docker compose port for the frontend service, .ship-it.yml's port is the container port, nothing published means nothing answered (asked as today), .env is never read" \
  'infl "docker compose port" && says "app\.services" "+\`port\`[^.;]{0,30}\b(is|means)\b[^.;]{0,15}\bcontainer port\b|\bcontainer port\b[^.;]{0,30}\`port\`" && says "+\bhost port\b|\bpublish" "docker compose port|\bDocker\b" && says "nothing (is )?published|no published port|(isn.t|is not) published" "\basks?\b" && says "\bnever\b[^.;]{0,20}\breads?\b[^.;]{0,10}\.env|(doesn.t|does not) read \`?\.env" && ! says "+\bport from \`?\.ship-it\.yml\`?[^;]{0,60}\belse\b"'

# call 9: a typed reason over 200 characters is asked again, shorter, never cut; a stored one over 200 is treated as missing
check "adv 9 (reason over 200): a typed reason over 200 characters gets a request for a shorter one and is never cut; a stored reason over 200 is treated as missing, so it is asked" \
  'says "\b200\b" "+\bshorter\b" && says "\b200\b" "\bnever\b[^.;]{0,15}\b(cut|truncated|shortened|trimmed)\b|\b(isn.t|is not) (cut|truncated|shortened)\b" && says "\bstored\b|\bin the record\b|\bon file\b" "\b200\b" "+\btreated as missing\b|\bas (if|though) (it were )?missing\b|\bis asked\b"'

# call 10: "unreadable" means empty, not valid JSON, not an object, or schema not 1 -- run on the three counterexample files
check "adv 10 (what unreadable means): by the guide's own definition an empty file, truncated JSON, a non-object and schema 2 are unreadable; a valid schema-1 record is not" \
  'py2 unreadable "$FLAT"'

# fix round 3 (re-review 3, Important 1; the correction in task-1-adv1-fix-brief.md): evidence keeps the port it checked --
# scheme, host, port (when the URL has one) and path only. The section's own rule (C4K, read above) runs on a local URL with
# a basic-auth user and password (built at run time), a query and a fragment, and must give http://localhost:3000/terms;
# every "scheme ... path only" phrase in the section, the ask's bracket included, names the port
PY3='
import re, sys
from urllib.parse import urlsplit
t, u, pw, want = sys.argv[1].lower(), urlsplit(sys.argv[2]), sys.argv[3], sys.argv[4]
has = lambda *w: any(re.search(r"\b" + x + r"\b", t) for x in w)
out = ((u.scheme + "://" if has("scheme", "protocol") else "") + ((u.username or "") + "@" if has("user", "username", "credentials", "login") else "")
       + ((u.hostname or "") if has("host", "hostname", "domain") else "") + (":" + str(u.port) if has("port") and u.port else "")
       + (u.path if has("path") else "") + ("?" + u.query if has("query") and u.query else "") + ("#" + u.fragment if has("fragment") and u.fragment else ""))
sys.exit(0 if out == want and pw not in out else 1)
'
F3PW="$(printf '%s%s' Lo9 cal-pw)"
F3U="$(printf '%s://%s%s%s@%s/terms?x=1#f' http tester : "$F3PW" localhost:3000)"
F3PH="$(printf '%s' "$FLAT" | grep -oiE '\bscheme,[^.;:]{0,60}\bpath only\b' || true)"
check "fix round 3 (evidence keeps the port): the section's evidence rule on the local URL with a basic-auth user and password, ?x=1 and #f gives http://localhost:3000/terms; the rule and the ask's bracket both name the port" \
  '[ -n "$C4K" ] && python3 -I -c "$PY3" "$C4K" "$F3U" "$F3PW" "http://localhost:3000/terms" 2>/dev/null && [ "$(printf "%s\n" "$F3PH" | grep -c .)" -ge 2 ] && ! printf "%s\n" "$F3PH" | grep -viE "\bport\b" | gq . && printf "%s" "$FLAT" | grep -oE "\[[^]]*\bscheme\b[^]]*\]" | gq -iE "\bport\b"'

# ---- adversarial round 2: eight counterexamples on their exact inputs (task-1-adv2.md; calls in task-1-adv2-fix-brief.md) ----
# As in round 1, a behaviour check reads the rule's switches from the guide's wording, then runs the rule on the input.
PY4='
import json, os, re, sys
from urllib.parse import urlsplit
m = sys.argv[1]
if m == "served":                          # base URL with a path: the served path is the base path joined with /terms
    bp, sl, qf = (x == "1" for x in sys.argv[2:5])
    def served(base, final):
        want = (urlsplit(base).path.rstrip("/") if bp else "") + "/terms"
        u = urlsplit(final); p = u.path if qf else u.path + ("?" + u.query if u.query else "") + ("#" + u.fragment if u.fragment else "")
        return p == want or (sl and p == want + "/")
    B = "https://dev.example.com/app"
    ok = all(served(b, f) == e for b, f, e in [(B, B + "/terms", True), (B, B + "/terms/", True), (B, B + "/terms?x=1#f", True),
             (B, "https://dev.example.com/terms", False), (B, B + "/login?next=/app/terms", False),
             ("http://localhost:3000", "http://localhost:3000/terms", True), ("http://localhost:3000", "http://localhost:3000/terms/", True)])
elif m == "asked":                         # the coming-soon exception: items 2-5 only, or keyed on the reason text alone
    i25 = sys.argv[2] == "1"
    def asked(item, state, reason):
        return state in ("skipped", "missing") and not (reason == "coming soon" and (item >= 2 if i25 else True))
    ok = asked(1, "skipped", "coming soon") and not asked(2, "skipped", "coming soon") and asked(1, "skipped", "our lawyer is writing them")
elif m == "stored":                        # a stored done item 2 whose reason holds a ?token= URL, on an item that is not asked
    cover, empty, kept, novalue = (x == "1" for x in sys.argv[2:6]); url = sys.argv[6]
    old = {"state": "done", "reason": "pentest finished, report at " + url}
    new = {"state": old["state"] if kept else "skipped", "reason": "" if (cover and empty) else old["reason"]}
    line = "I cleared the reason of item 2 (security audit)" + ("" if novalue else ": " + old["reason"])
    sec = re.compile(os.environ["SECRET_RE"])
    ok = new["state"] == "done" and not sec.search(new["reason"]) and url.split("=", 1)[1] not in line
elif m == "anchor":                        # the guide pattern list, anchored at a token start or not, on ordinary words
    a = sys.argv[2] == "1"; pre = [p for p in sys.argv[3].split("\n") if p]
    alt = "|".join(re.escape(p) for p in pre)
    pat = re.compile(("(?:^|[^A-Za-z0-9])(?:" + alt + ")" if a else "(?:" + alt + ")") + "|[A-Fa-f0-9]{32,}|[A-Za-z0-9+/]{32,}")
    no, yes = sys.argv[4].split("\n"), sys.argv[5].split("\n")
    ok = bool(pre) and not any(pat.search(x) for x in no) and all(pat.search(x) for x in yes)
sys.exit(0 if ok else 1)
'
py4() { python3 -I -c "$PY4" "$@" 2>/dev/null; }

# call 1: "that path" is the base URL's own path joined with /terms (https://dev.example.com/app -> /app/terms), one trailing
# slash allowed, query and fragment ignored; /app/terms on that dev URL is served, /terms there is not
A1B=0; A1S=0; A1Q=0
says 'that path|final URL|served' 'base URL|dev_url' '+\b(own )?path\b[^.;]{0,20}\b(joined with|plus|followed by)\b[^.;]{0,10}`?/terms' && A1B=1
{ says 'trailing slash' '\bwith or without\b' || says 'trailing slash' '+\bmay end\b|\ballowed\b|\beither\b'; } && A1S=1
{ says '\b(query|fragment)\b' '+\bignored\b' || says '\b(query|fragment)\b' '\b(doesn.t|does not|don.t|do not|never) change the path\b'; } && A1Q=1
check "adv2 1 (dev URL with a path): the served path is the base URL's path joined with /terms; on https://dev.example.com/app a final /app/terms (/, ?x=1#f) is served, /terms is not; with no base path it stays /terms" \
  'py4 served "$A1B" "$A1S" "$A1Q"'

# call 2: the coming-soon exception covers items 2-5 only -- a skipped item 1 is asked whatever its reason says, "coming soon" too
A2I=0; [ -n "$(sel "${AGAIN[@]}" 'coming soon' | grep -iE 'items? 2.{1,4}5[^.;]{0,40}coming soon|coming soon[^.;]{0,40}items? 2.{1,4}5' || true)" ] && A2I=1
check "adv2 2 (coming soon typed for item 1): the asked-again exception names items 2-5, so item 1 skipped with the reason \"coming soon\" is asked; item 2 with it is not; and a skipped item 1 is asked whatever its reason says" \
  'py4 asked "$A2I" && says "\bitem 1\b" "\`?skipped\`?|\bskip" "+\b(whatever|any)\b[^.;]{0,20}\breason\b|\bregardless of\b[^.;]{0,20}\breason\b"'

# call 3: no .ship-it.yml yet -- the frontend is app.services' service when that file exists, else the compose service named
# frontend, else the only service that publishes a port; no service or port found: nothing is requested and the user hears
# "I couldn't find where your app runs on this computer"; "didn't answer" only when a request was really sent and failed
check "adv2 3 (no .ship-it.yml yet): the frontend is app.services' service when the file exists, else the compose service named frontend, else the only service publishing a port; none found -> nothing requested, \"I couldn't find where your app runs\"; \"didn't answer\" only after a real request" \
  'says "\.ship-it\.yml" "+\b(exists|is there)\b" && says "compose" "+\bservice (named|called) \`?frontend\`?" && says "+\bonly service\b[^.;]{0,40}\bpublish" && infl "app\.services.{0,250}\bservice (named|called) \`?frontend.{0,250}\bonly service\b" && says "\bnothing is requested\b|\bno request is (made|sent)\b|\bsends nothing\b" && says "couldn.t (find|tell) where (your|the) app runs" && says "didn.t answer" "\bonly (when|if)\b[^.;]{0,50}\b(request|sent)\b"'

# call 4: the no-secret check covers every item, items 2-5 included; a stored match on an item not asked is written empty,
# the state stays, and one line names the item and field, never the value -- run on a stored done item 2 whose reason holds
# a ?token= URL (built at run time)
A4C=0; A4E=0; A4K=0; A4V=0
says '\b(every|each|all five)\b[^.;]{0,20}\bitems?\b' 'reason' 'evidence' '+\bitems 2.{1,4}5\b[^.;]{0,15}\b(included|too)\b|\bincluding items 2.{1,4}5\b' && A4C=1
says '\bstored\b|\bin the record\b' '\b(isn.t|is not|not) asked\b' '+\bwritten empty\b|\bcleared\b|\bemptied\b' && A4E=1
says '\bstate\b' '+\b(stays?|is kept|kept)\b' && A4K=1
says '\bone line\b' '\bwhich item\b' '\bwhich field\b' '\bnever the value\b|\bnever (shows|says|names|repeats) the value\b|\bwithout the value\b' && A4V=1
A4U="$(printf 'https://%s/r?%s=%s%s' vault.example.com token abc 123)"
check "adv2 4 (secret in an item not asked): a stored done item 2 whose reason holds a ?token= URL gets its reason written empty, keeps its state done, and the one line names the item and field, never the value" \
  'py4 stored "$A4C" "$A4E" "$A4K" "$A4V" "$A4U"'

# call 5: a pattern matches only at the start of a token -- "risk-based review", "task-force", "desk-check" (and "ask-me-later")
# don't match; a run-time " sk-" plus a long run, "=sk-..." and "\"sk-..." do; the pattern list is the guide's own
A5A=0
{ says 'pattern|match' '+\bstart of (a |the )?(token|word)\b' || says 'pattern|match' '\b(isn.t|is not|not) a letter or (a )?digit\b'; } && ! says 'pattern|match' '+\banywhere\b' && A5A=1
A5P="$(sel 'secret patterns' | cut -d $'\x1f' -f1 | grep -oE '`[^`]+`' | tr -d '`' | sort -u || true)"
A5SK="$(printf '%s%s' s k-)"; A5RUN="$(printf 'a%.0s' {1..40})"
A5NO="$(printf '%s\n' 'risk-based review is scheduled for next month' 'the task-force has not signed off yet' 'our desk-check happens Friday' 'ask-me-later')"
A5YES="$(printf '%s\n' " ${A5SK}${A5RUN}" "=${A5SK}abc1" "\"${A5SK}abc1" "${A5SK}abc1")"
check "adv2 5 (ordinary words): with the guide's own pattern list, matched only at the start of a token, \"risk-based review\", \"task-force\", \"desk-check\" don't match; \" sk-\" plus a long run, \"=sk-\" and \"\\\"sk-\" do" \
  'py4 anchor "$A5A" "$A5P" "$A5NO" "$A5YES"'

# call 6: an item 2-5 that belongs to a left-out item reads "Left out (your choice)", which wins over coming soon
check "adv2 6 (one reason per item): when an item 2-5 belongs to a left-out item, \"Left out (your choice)\" wins over coming soon" \
  'says "\bitems? 2.{1,4}5\b|left-out item" "Left out \(your choice\)\"?[^.;]{0,25}\b(wins|takes precedence|comes first|is used)\b[^.;]{0,25}\b(over|before|instead of|rather than)\b[^.;]{0,5}\`?coming soon"'

# call 7: two lists under one heading, each under its own plain label ("go-live items", "items you left out"); the CI/CD
# contract reads the user's left-out picks only from the left-out label
check "adv2 7 (two lists, one heading): the five lines and the left-out lines each sit under their own label (go-live items, items you left out); the CI/CD contract reads left-out picks only from the left-out label" \
  'says "\blabels?\b" "+go-live items" "+items you left out" && gsays "\bautomation\b" "+\breads?\b" "items you left out" "+\bonly\b"'

# call 8: step 7 -- the heading holds the five lines on a production request, and the left-out lines whenever the user left
# items out, production or not
check "adv2 8 (step 7): the PR step says the heading holds the five go-live lines on a production request and the left-out lines whenever the user left items out, production or not" \
  'printf "%s" "$STEP" | gq -iE "\bfive( go-live)? lines\b[^.;]{0,40}\bproduction request\b|\bproduction request\b[^.;]{0,40}\bfive( go-live)? lines\b" && printf "%s" "$STEP" | gq -iE "\bleft-out lines\b[^.;]{0,60}\b(whenever|production or not|whether or not)\b"'

# ---- owner call on adversarial round 3, finding 1: "Start from main's copy" (task-1-owner-call-brief.md) ----
# A scratch git fixture with a bare origin; the guide's own read command (`git show origin/<default branch>:...`) runs on it,
# and the merge rule the guide states (its switches read from the wording, as in rounds 1-2) decides what the record holds.
# (R9, final review: isolated as test-left-out-record.sh's fixtures are -- run from a git hook, an exported GIT_DIR,
# GIT_WORK_TREE or GIT_INDEX_FILE would make every `gx -C <fixture>` act on the real repository; a subshell unsets them,
# and no repo above the scratch folder is ever found)
TMPP="$(cd "$TMPD" && pwd -P)"
gx() ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$TMPD:$TMPP"
  git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" 2>/dev/null )
OCREC='.ship-it-go-live.json'
oc_rec() { python3 -I -c 'import json, sys; print(json.dumps({"schema": 1, "items": json.loads(sys.argv[1])}))' "$1"; }
oc_put() { printf '%s\n' "$2" > "$1/$OCREC" && gx -C "$1" add "$OCREC" && gx -C "$1" commit -qm "$3"; }
# the guide's read command: a backticked `git show origin/<ref>:.ship-it-go-live.json`; the ref placeholder becomes main
oc_ref() { printf '%s' "$FLAT" | grep -oE '`git show origin/(<[^>`]+>|\[[^]`]+\]|[A-Za-z0-9_.-]+):\.ship-it-go-live\.json`' | head -1 | sed -E 's/^`git show origin\/(<[^>]+>|\[[^]]+\]|[A-Za-z0-9_.-]+):.*/\1/'; }
OCREF=$(oc_ref || true)
case "$OCREF" in '<'*|'['*) OCREF=main;; esac
OCFETCH=0; says '+\bfetch(es|ing)?\b' 'default branch|that branch|\bmain\b' && OCFETCH=1
# what /ship-it reads as main's copy, from the clone in $1: "" when it can't (no ref, no file, no read command in the guide)
oc_main() { [ -n "$OCREF" ] || return 0; [ "$OCFETCH" = 1 ] && gx -C "$1" fetch -q origin "$OCREF"; gx -C "$1" show "origin/$OCREF:$OCREC" || true; }
OC="$TMPD/oc"; mkdir -p "$OC"
oc_origin() { rm -rf "$OC/$1"; mkdir -p "$OC/$1"; gx init -q --bare "$OC/$1/origin.git" && gx clone -q "$OC/$1/origin.git" "$OC/$1/a" && printf 'app\n' > "$OC/$1/a/README" && gx -C "$OC/$1/a" add README && gx -C "$OC/$1/a" commit -qm init && gx -C "$OC/$1/a" push -q origin main && gx clone -q "$OC/$1/origin.git" "$OC/$1/b" && gx -C "$OC/$1/b" checkout -qb feature-b; }
PY5='
import json, sys
f = dict(x.split("=") for x in sys.argv[1].split(","))
on = lambda k: f.get(k) == "1"
def load(t):
    if t is None or t == "": return None
    try: d = json.loads(t)
    except ValueError: return "BAD"
    if not isinstance(d, dict) or d.get("schema") != 1 or not isinstance(d.get("items"), dict): return "BAD"
    return d["items"]
m, b = load(sys.argv[2] if sys.argv[2] != "-" else None), load(sys.argv[3] if sys.argv[3] != "-" else None)
if m == "BAD" and not on("unread"): m, b = None, None   # without the rule: the record is unreadable, all five are missing
if m == "BAD": m = None
if b is None and m is not None: merged = m if on("norec") else {}
elif m is None: merged = b or {}
else:
    merged = {}
    for k in sorted(set(m) | set(b)):
        x, y = m.get(k), b.get(k)
        if x and y:
            if on("newer"): merged[k] = y if y["date"] > x["date"] else x if y["date"] < x["date"] else (y if on("tie") else x)
            else: merged[k] = y
        elif y: merged[k] = y
        elif x and on("oneside"): merged[k] = x
want = json.loads(sys.argv[4])
sys.exit(0 if {k: (v["state"], v["date"]) for k, v in merged.items()} == {k: tuple(v) for k, v in want.items()} else 1)
'
oc_merge() { python3 -I -c "$PY5" "$1" "$2" "$3" "$4" 2>/dev/null; }
OCNA='"terms_privacy": {"state": "na", "reason": "does not apply", "date": "2026-10-20", "evidence": ""}'
# the records, as top-level literals (bash 3.2 brace-expands a {...} literal nested in "$(... "...")")
OC1M="{$OCNA}"
OC2M='{"terms_privacy": {"state": "na", "reason": "does not apply", "date": "2026-10-20", "evidence": ""}, "security_audit": {"state": "done", "reason": "audit passed", "date": "2026-10-22", "evidence": ""}, "restore_test": {"state": "done", "reason": "restored", "date": "2026-10-10", "evidence": ""}, "load_test": {"state": "done", "reason": "load test passed", "date": "2026-10-23", "evidence": ""}}'
OC2B='{"terms_privacy": {"state": "skipped", "reason": "pages next week", "date": "2026-10-21", "evidence": ""}, "security_audit": {"state": "skipped", "reason": "coming soon", "date": "2026-10-22", "evidence": ""}, "live_payment": {"state": "skipped", "reason": "coming soon", "date": "2026-10-21", "evidence": ""}, "load_test": {"state": "skipped", "reason": "coming soon", "date": "2026-10-19", "evidence": ""}}'
OC2W='{"terms_privacy": ["skipped", "2026-10-21"], "security_audit": ["skipped", "2026-10-22"], "restore_test": ["done", "2026-10-10"], "live_payment": ["skipped", "2026-10-21"], "load_test": ["done", "2026-10-23"]}'
OC3B='{"terms_privacy": {"state": "skipped", "reason": "pages next week", "date": "2026-10-21", "evidence": ""}}'
OC5C='{"terms_privacy": {"state": "skipped", "reason": "pages next week", "date": "2026-10-23", "evidence": ""}, "security_audit": {"state": "done", "reason": "audit passed", "date": "2026-10-25", "evidence": ""}}'
OC5D='{"terms_privacy": {"state": "na", "reason": "does not apply", "date": "2026-10-24", "evidence": ""}, "security_audit": {"state": "skipped", "reason": "coming soon", "date": "2026-10-20", "evidence": ""}}'
OC1W='{"terms_privacy": ["na", "2026-10-20"]}'
OC3W='{"terms_privacy": ["skipped", "2026-10-21"]}'
OC5W='{"terms_privacy": ["na", "2026-10-24"], "security_audit": ["done", "2026-10-25"]}'

# rule 1: read main's copy first (fetch, then the guide's `git show`; a read only); a branch cut before the record reached
# main has none, so the record starts from main's -- item 1's na stays, and item 1 isn't asked
OCN=0; says '\bno record\b|\bhas no record\b|\bno file\b' '+\bstarts? from\b[^.;]{0,15}\b(main.s|the default branch.s)' && OCN=1
oc_case1() { local mc
  oc_origin c1 && oc_put "$OC/c1/a" "$(oc_rec "$OC1M")" "record" && gx -C "$OC/c1/a" push -q origin main || return 1
  [ ! -e "$OC/c1/b/$OCREC" ] || return 1
  mc="$(oc_main "$OC/c1/b")"; [ -z "$(gx -C "$OC/c1/b" status --porcelain)" ] && [ "$(gx -C "$OC/c1/b" symbolic-ref --short HEAD)" = feature-b ] || return 1
  oc_merge "norec=$OCN,newer=1,tie=1,oneside=1,unread=1" "${mc:--}" - "$OC1W"; }
check "owner 1 (start from main's copy): on a branch cut before the record reached main, the guide's fetch and \`git show origin/<default branch>:.ship-it-go-live.json\` read main's record (nothing checked out, merged or pushed); the record starts from it, so item 1's na stays and isn't asked" \
  'says "default branch|main.s copy" "+\breads?\b" "+\bbefore (it )?asks?\b|\bbefore asking\b" && says "\bnothing\b[^.;]{0,30}\bchecked out\b" "\bmerged\b" "\bpushed\b" && oc_case1'

# rule 2: both sides have an item -> the newer date counts, a tie goes to the branch; an item only one side has comes from it
OCW=0; OCT=0; OCO=0
says '\bboth\b' '+\bnewer `?date`?\b' '+\b(counts?|wins?)\b' && OCW=1
says '\btie\b' '+\bbranch.s\b|\bthe branch\b' && OCT=1
says '\bonly one side\b|\bone side has\b' '+\bfrom that side\b' && OCO=1
oc_case2() { local mc
  oc_origin c2 && oc_put "$OC/c2/a" "$(oc_rec "$OC2M")" "main record" && gx -C "$OC/c2/a" push -q origin main || return 1
  oc_put "$OC/c2/b" "$(oc_rec "$OC2B")" "branch record" || return 1
  mc="$(oc_main "$OC/c2/b")"
  oc_merge "norec=1,newer=$OCW,tie=$OCT,oneside=$OCO,unread=1" "${mc:--}" "$(cat "$OC/c2/b/$OCREC")" "$OC2W"; }
check "owner 2 (which answer counts): main and the branch both hold items -- the newer date wins (item 1: the branch's later skip; item 4: main's later done), a tie goes to the branch (item 2), an item only main has comes from main (item 3's done stays quiet)" 'oc_case2'

# rule 2, last bullet: an unreadable main copy counts as no main copy; the merged record gets the no-secret, unreadable and
# shape rules -- run on main copies that are truncated JSON and schema 2
OCU=0; says 'unreadable' 'main.s copy|copy (on|from) main' '\bcounts? as no main copy\b|\bcounts? as none\b|\bas if there were no main copy\b' && ! says 'unreadable' 'main.s copy' '\b(doesn.t|does not|never|isn.t) count' && OCU=1
oc_case3() { local mc t
  for t in '{"schema": 1, "items": [' '{"schema": 2, "items": {}}'; do
    oc_origin c3 && oc_put "$OC/c3/a" "$t" "bad main record" && gx -C "$OC/c3/a" push -q origin main || return 1
    oc_put "$OC/c3/b" "$(oc_rec "$OC3B")" "branch record" || return 1
    mc="$(oc_main "$OC/c3/b")"; [ -n "$mc" ] || return 1
    oc_merge "norec=1,newer=1,tie=1,oneside=1,unread=$OCU" "$mc" "$(cat "$OC/c3/b/$OCREC")" "$OC3W" || return 1
  done; }
check "owner 3 (unreadable main copy): a main copy that is truncated JSON or schema 2 counts as no main copy -- the branch's record stands, not five missing items; the merged record gets the no-secret, unreadable and shape rules" \
  'oc_case3 && says "\bmerged\b" "secret" "unreadable|shape"'

# rule 3: main's copy can't be read -- the checklist goes on with the branch's own record and never stops the request; one
# plain line only when GitHub couldn't be reached (a broken origin), nothing said when main simply has no file
OCG=0; OCL=0; OCQ=0; OCS=0
says "can.t be read|couldn.t be (read|reached)|unreachable|no network" '+\b(goes|carries) on\b|\bcontinues\b' "+\bbranch.s own record\b|\bits own record\b" && OCG=1
says "couldn.t be reached|unreachable|can.t (be )?reach" '+\bone (plain )?line\b' && OCL=1
says '\bno file (on|in|there)\b|\bno file on main\b|\bno record on main\b' '\bnormal\b|\bnothing (is )?said\b|\bsays nothing\b|\bsaid nothing\b' && OCQ=1
says '\bnever stops the request\b|\bnothing stops\b' && OCS=1
oc_case4() { local fetched shown lines
  oc_origin c4 && oc_put "$OC/c4/b" "$(oc_rec "$OC1M")" "branch record" || return 1
  # no file on main (GitHub reachable): the branch's record, nothing said
  fetched=0; gx -C "$OC/c4/b" fetch -q origin main && fetched=1; shown="$(oc_main "$OC/c4/b")"
  [ "$fetched" = 1 ] && [ -z "$shown" ] || return 1
  lines=$([ "$OCQ" = 1 ] && echo 0 || echo 1); [ "$lines" = 0 ] && [ "$OCG" = 1 ] && [ "$OCS" = 1 ] || return 1
  # GitHub unreachable (origin moved away): the branch's record, one plain line, nothing stops
  mv "$OC/c4/origin.git" "$OC/c4/gone.git"
  fetched=0; gx -C "$OC/c4/b" fetch -q origin main && fetched=1
  [ "$fetched" = 0 ] || return 1
  lines=$([ "$OCL" = 1 ] && echo 1 || echo 0); [ "$lines" = 1 ] && [ "$OCG" = 1 ] && [ "$OCS" = 1 ]; }
check "owner 4 (GitHub unreachable): with no file on main the checklist goes on with the branch's record and says nothing; with origin unreachable it goes on, says so in one plain line, and nothing stops the request" 'oc_case4'

# rule 4: a clash in .ship-it-go-live.json on the second PR is settled per item by the newer date (a real add/add-free
# content conflict: two branches change item 1 and item 2 differently); never a gate
# (re-pointed by R1, final review: the by-hand line, exact, is the rule the fixture runs; "re-running /ship-it after
# updating from main settles it" left with the rest of /ship-it settling its own file)
OC_BYHAND='"Your go-live record changed on two branches. To settle it, keep, for each item, the line with the newer date."'
OC_CLASH='A clash is still possible: when two open branches both change an answer, git shows a conflict in `.ship-it-go-live.json` on the second PR.'
OCC=0; printf '%s' "$FLAT" | gq -F -- "$OC_BYHAND" && OCC=1
oc_case5() { local base ours theirs
  oc_origin c5 && base="$(oc_rec "$OC1M")" && oc_put "$OC/c5/a" "$base" "record" && gx -C "$OC/c5/a" push -q origin main || return 1
  gx -C "$OC/c5/b" checkout -q main && gx -C "$OC/c5/b" pull -q origin main && gx -C "$OC/c5/b" checkout -qb feature-d || return 1
  oc_put "$OC/c5/a" "$(oc_rec "$OC5C")" "branch c, merged" && gx -C "$OC/c5/a" push -q origin main || return 1
  oc_put "$OC/c5/b" "$(oc_rec "$OC5D")" "branch d" || return 1
  gx -C "$OC/c5/b" fetch -q origin main; ! gx -C "$OC/c5/b" merge -q origin/main >/dev/null || return 1
  ours="$(gx -C "$OC/c5/b" show ":2:$OCREC")"; theirs="$(gx -C "$OC/c5/b" show ":3:$OCREC")"; [ -n "$ours" ] && [ -n "$theirs" ] || return 1
  oc_merge "norec=1,newer=$OCC,tie=1,oneside=1,unread=1" "$theirs" "$ours" "$OC5W"; }
check "owner 5 (a clash; re-pointed by R1): two branches change the record and git shows a conflict on the second PR -- the guide's exact clash sentence, never a gate; its exact by-hand line (keep, for each item, the line with the newer date) settles it (item 1 from this branch, item 2 from main)" \
  'oc_case5 && printf "%s" "$FLAT" | gq -F -- "$OC_CLASH" && usays "conflict|clash" "\bnever a gate\b|\bnot a gate\b"'
# R1 (final review, owner): how the skills handle that conflict is not designed yet; until then it is settled by hand.
# Nothing in the section has /ship-it settle its own file, read the two sides, stage the result, complete or continue the
# user's update, or stop on other conflicted files.
R1_SHIPV='/ship-it\b[^.;:]{0,40}\b(settles?|settling|resolves?|completes?|continues?|stages?|finishes?)\b|\b(two|both) sides\b|--diff-filter=U|\bconflict markers\b|\bstage numbers\b|\bother (conflicted )?files?\b[^.;]{0,20}\b(in conflict|conflicted)\b|\bany other file is conflicted\b|\bwhen /ship-it isn.t run\b'
check "R1 (guide, the clash settled by hand): a sentence says how the skills handle that conflict is not designed yet and that until it is, it is settled by hand; no sentence has /ship-it settle, resolve, stage, complete or continue it, read the two sides, or stop on other conflicted files" \
  'says "\bnot designed yet\b" "conflict|clash" "+\bby hand\b" && ! printf "%s\n" "$PAIRS" | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$R1_SHIPV"'

# rule 5: a re-run, like a new request, reads main's copy the same way when it runs
check "owner 6 (re-run): a re-run that runs the checklist reads main's copy the same way a new request does" \
  'usays "\bre-?run\b|RE-RUN" "+main.s copy|the default branch" "+\bthe same way\b"'

# ---- owner call 2: "Settle its own file" (task-1-owner-call-brief.md, "## Owner call 2"; re-review 6) ----
# (R1, final review: the settle rule left this release -- its checks 1-3 and their git-conflict helpers are removed;
# checks 4 and 5 pin the which-answer-counts rule, which stays)
PY6='
import json, sys
m_ = sys.argv[1]; f = dict(x.split("=") for x in sys.argv[2].split(",") if x); on = lambda k: f.get(k) == "1"
def load(t):
    if t in (None, "-", ""): return None
    try: d = json.loads(t)
    except ValueError: return "BAD"
    if not isinstance(d, dict) or d.get("schema") != 1 or not isinstance(d.get("items"), dict): return "BAD"
    return d["items"]
def merge(m, b):
    if m == "BAD": m = None                                # an unreadable main copy counts as none (owner call 1)
    if b == "BAD":
        if not on("ubr"): return {}                        # without the rule: the record is unreadable, all five missing
        b = None
    if b is None: return m or {}
    if m is None: return b
    out = {}
    for k in sorted(set(m) | set(b)):
        x, y = m.get(k), b.get(k)
        if x and y: out[k] = (y if y["date"] > x["date"] else x if y["date"] < x["date"] else (y if on("tie") else x)) if on("newer") else y
        else: out[k] = y or x
    return out
got = merge(load(sys.argv[3]), load(sys.argv[4]))
want = json.loads(sys.argv[-1])
sys.exit(0 if isinstance(got, dict) and {k: (v["state"], v["date"]) for k, v in got.items()} == {k: tuple(v) for k, v in want.items()} else 1)
'
py6() { python3 -I -c "$PY6" "$@" 2>/dev/null; }
OS_UBR=0
says 'unreadable' '\bbranch' '\bcounts? as no branch record\b' '+\bmain supplies\b' && OS_UBR=1

# 4. an unreadable branch file beside a readable main copy counts as no branch record: main supplies the items
os_case4() { local mc
  oc_origin s4 && oc_put "$OC/s4/a" "$(oc_rec "$OC1M")" record && gx -C "$OC/s4/a" push -q origin main || return 1
  oc_put "$OC/s4/b" '{"schema": 1, "items": [' "broken branch record" || return 1
  mc="$(oc_main "$OC/s4/b")"; [ -n "$mc" ] || return 1
  py6 merge "ubr=$OS_UBR,newer=1,tie=1" "$mc" "$(cat "$OC/s4/b/$OCREC")" "$OC1W"; }
check "owner call 2, 4 (unreadable branch file): a truncated branch record beside main's readable copy counts as no branch record, so main supplies the items (item 1's na stays, not five missing items)" 'os_case4'

# 5. an unreadable main copy: nothing is said about it (and it never gets the unreadable notice)
check "owner call 2, 5 (unreadable main copy): nothing is said about an unreadable main copy, and the \"I couldn't read your go-live record\" notice is never about it" \
  'says "unreadable" "main(.s)? copy" "\bnothing (is )?said\b|\bsays nothing\b|\bsilently\b" && ! says "main(.s)? copy" "couldn.t read your go-live record"'

# ---- final review (final-review-fix-brief.md, 2026-11-11): R3-R7, the guide's spec fixes ----
# R3: the trigger's no-workflow bullet and the Workflow Generation table agree -- the empty-provider (placeholder) row
# says, on its affirmed text, that the placeholder still has the production deploy job (`deploy-prod`), as the
# workflow /ship-it generates does; a "deploys to production" bullet beside a bare "placeholder / pending" row is red
WGROW="$(awk '/^```/{f=!f} !f&&/^#/{on=($0=="### Workflow Generation")} on' "$G" | grep -E '^\|[^|]*infra\.provider: ""' || true)"
WGAFF="$(printf '%s\n' "$WGROW" | cut -d '|' -f3- | pair | cut -d $'\x1f' -f2)"
TRIGB="$(printf '%s\n' "$SEC" | units | grep -iE '^- no workflow' || true)"
# (made whole by A4/M3: beside a placeholder row, the trigger bullet must name the placeholder too -- "every workflow it
# generates deploys to production on merge." put back is red)
check "R3 (generated workflow): the no-workflow trigger bullet claims a production deploy and the Workflow Generation table's empty-provider placeholder row says it still has the production deploy job (deploy-prod); beside that placeholder row the bullet names the placeholder, so the two agree" \
  '[ -n "$WGROW" ] && [ -n "$TRIGB" ] && printf "%s\n" "$TRIGB" | pair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "deploys? to production|\bproduction deploy (job|on merge)\b|deploy-prod" && { ! printf "%s\n" "$WGROW" | gq -iE "placeholder|pending" || { printf "%s\n" "$WGAFF" | gq -iE "\`?deploy-prod\`?( job)?|\bproduction deploy job\b" && printf "%s\n" "$TRIGB" | pair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bplaceholder\b"; }; } && printf "%s\n" "$WGAFF" | gq -iE "deploy-prod|\bproduction deploy job\b"'
# M1 (A4): the bullet names the three forms every generated workflow takes -- a deploy-prod job, a caller passing
# environment-prod, the placeholder job for an empty infra.provider -- and never claims a deploy-prod job (or "a production
# deploy job") for every generated workflow (the reusable caller and the Container Apps set have none)
M1_ALL='\bevery\b[^.;]{0,50}\b(has|have|carries|gets|includes)\b (a |its |one )?(`?deploy-prod`? job|production deploy job)'
check "M1 (the three forms): the no-workflow trigger bullet names a deploy-prod job, a caller that passes environment-prod, and the placeholder job for an empty infra.provider, and never claims a deploy-prod job for every generated workflow" \
  'printf "%s\n" "$TRIGB" | pair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "deploy-prod.? job" && printf "%s\n" "$TRIGB" | pair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bcaller\b[^.;]{0,30}environment-prod" && printf "%s\n" "$TRIGB" | pair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "infra\.provider[^.;]{0,40}\bplaceholder( job)?\b|\bplaceholder( job)?\b[^.;]{0,40}infra\.provider" && ! printf "%s\n" "$TRIGB" | gq -iE "$M1_ALL"'
# R4: the re-run exception keys on the five item lines, not the heading: a re-run runs the checklist as a new request
# does when its PR has no five go-live item lines -- no section, or one whose Go-live items list only says the five
# weren't asked; a PR that already carries the five item lines is not asked again
check "R4 (re-run, the five lines): a re-run whose PR has no five go-live item lines -- no section, or one whose Go-live items list only says the five weren't asked -- runs the checklist as a new request does; a PR that already carries the five lines is not asked again on a re-run" \
  'says "\bre-?runs?\b|RE-RUN" "\bfive\b[^.;]{0,25}\blines\b" "## Go-live checklist" "weren.t asked|were not asked" "+\bas a new request\b" && says "\balready (carries|has|holds|shows)\b[^.;]{0,20}\bfive\b" "\bre-?run\b" "\b(not|never|isn.t)\b[^.;]{0,10}\basked( again)?\b|\basks nothing\b"'
# R5: the long-run pattern is not applied to evidence (an ordinary path matches it); every other pattern and the URL
# rules still apply to it; reason is unchanged. The rule's switch is read from the guide, then run on a URL with a long
# path (not flagged), a ghp_-style value built at run time in evidence (still flagged) and a long run in a reason (flagged)
R5E=0; says '\bevidence\b' 'long-run|\b32\b|hex or base64 run' '\b(not|never)\b[^.;]{0,15}\b(applied|appl(y|ies)|used|checked)\b[^.;]{0,15}\bevidence\b|\bexcept\b[^.;]{0,20}\bevidence\b' && R5E=1
PY10='
import re, sys
e5, anch = sys.argv[1] == "1", sys.argv[2] == "1"; pre = [p for p in sys.argv[3].split("\n") if p]; a = sys.argv[4:]
alt = "|".join(re.escape(p) for p in pre)
lead = re.compile(("(?:^|[^A-Za-z0-9])(?:" + alt + ")") if anch else "(?:" + alt + ")"); run = re.compile("[A-Fa-f0-9]{32,}|[A-Za-z0-9+/]{32,}")
ev = lambda x: bool(lead.search(x)) or (not e5 and bool(run.search(x)))
rs = lambda x: bool(lead.search(x)) or bool(run.search(x))
sys.exit(0 if pre and not ev(a[0]) and ev(a[1]) and rs(a[2]) else 1)
'
R5LONG="https://dev.example.com/legal/termsofservice/currentversion2026"
R5GHP="https://dev.example.com/r/ghp""_$(printf 'Zx9%.0s' {1..12})"
R5RUN="see run $(printf 'q%.0s' {1..40})"
check "R5 (evidence and the long-run pattern): the long-run pattern is not applied to evidence, every other pattern and the URL rules still are, reason keeps every pattern -- on evidence a URL with a long path isn't flagged, a run-time ghp_ value still is; a long run in a reason still is" \
  'python3 -I -c "$PY10" "$R5E" "$A5A" "$A5P" "$R5LONG" "$R5GHP" "$R5RUN" 2>/dev/null && says "\bevidence\b|\bit\b" "\b(every|all|each) other pattern|\bother patterns\b" "\bURL rules\b|\bquery\b" "+\bstill appl(y|ies)\b" && ! says "\breason\b" "long-run|\b32\b" "\b(not|never)\b[^.;]{0,15}\b(applied|appl(y|ies))\b[^.;]{0,15}\`?reason\b"'
# R6: the frontend is the app.services entry named frontend when .ship-it.yml exists and has one -- never "the one
# app.services names" (the guide's own example lists backend and frontend, so that picks none)
check "R6 (which service is the frontend): the frontend is the app.services entry named frontend, when .ship-it.yml exists and has one; nothing says it is \"the one app.services names\"" \
  'says "+app\.services\`?[^.;]{0,15}\b(entry|service) (named|called) \`?frontend\b" "\.ship-it\.yml" "+\bhas one\b|\bexists\b" && ! says "+\bthe one\b[^.;]{0,30}app\.services\`? names\b"'
# R7: Asking's first paragraph says what the section means -- only item 1 is asked; items 2-5 are recorded coming soon
ASK1="$(printf '%s\n' "$SEC" | awk '/^```/{f=!f} !f&&/^#/{on=($0=="### Asking")} on' | units | sed -n 1p)"
ASK1P="$(printf '%s\n' "$ASK1" | sents | pair)"
check "R7 (Asking, first paragraph): it says only item 1 is asked and items 2-5 are recorded coming soon, and none of its sentences affirms that an item 2-5 is asked" \
  'PAIRS="$ASK1P" says "+\bonly item 1\b[^.;]{0,20}\b(is )?asked\b|\bitem 1 is the only (item|one)\b[^.;]{0,15}\basked\b" && PAIRS="$ASK1P" says "\bitems? 2.{1,4}5\b" "\`coming soon\`" "+\brecorded\b" && ! printf "%s\n" "$ASK1P" | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bitems? 2.{1,4}5\b[^.;]{0,15}\b(are|is|get|gets) asked\b"'
# M5 (A4): Asking's asked-again sentence after the lead can no longer be read as "a missing item 2-5 is asked": every
# sentence of its first paragraph that affirms a "skipped or missing" item is asked names item 1 as its subject, never "an
# item" or "any item"
M5_GEN='(^|[.;:] )(an|any|each|every) item\b[^.;]{0,40}\bmissing\b|\b(an|any|each|every) (item|one) that is `?skipped`? or missing\b'
check "M5 (Asking, asked again): in Asking's first paragraph, each sentence that affirms a skipped or missing item is asked is about item 1, and none says \"an item that is skipped or missing\" is asked" \
  'm5=$(printf "%s\n" "$ASK1P" | grep -iE "skipped.? or missing|missing or .?skipped" | cut -d $'"'"'\x1f'"'"' -f2 | grep -iE "\b(is|are|gets?) asked\b" || true); [ -n "$m5" ] && ! printf "%s\n" "$m5" | grep -viE "\bitem 1\b" | gq . && ! printf "%s\n" "$ASK1P" | cut -d $'"'"'\x1f'"'"' -f1 | gq -iE "$M5_GEN"'
# A3: the record rules say /ship-it never starts a merge or rebase itself; no sentence of the section has /ship-it merge,
# rebase or pull (the guard that went with "owner call 2, 3 (wording)", re-homed)
A3P="$(printf '%s\n' "$SEC" | awk '/^```/{f=!f} !f&&/^#/{on=($0=="### The record")} on' | units | sents | pair)"
check "A3 (no merge or rebase): the guide's record rules say \"/ship-it never starts a merge or rebase itself\", and no sentence of the Go-live checklist section has /ship-it merge, rebase or pull" \
  'PAIRS="$A3P" says "/ship-it never starts a merge or (a )?rebase itself" && ! printf "%s\n" "$PAIRS" | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "/ship-it\b[^.;:]{0,25}\b(merges|merging|rebases|rebasing|pulls|pulling)\b"'

# ---- E05-S2 Task 2: resume-it's readiness check lists the open go-live items (task-2-brief.md) ----
# resume-it only reads `.ship-it-go-live.json` (/ship-it owns it), the way the guide's Go-live checklist says the answer
# counts, and the NEXT-STEPS template's "## For Production" gets "### Go-live checklist". RESUME_IT points these at a copy.
R="${RESUME_IT:-.claude/commands/resume-it.md}"
RC="$(awk '/<step name="readiness-check">/{on=1} on; on&&/<\/step>/{exit}' "$R")"
RC2F="$(printf '%s\n' "$RC" | awk '/^\*\*2\. /{on=1} /^\*\*3\. /{on=0} on' | awk '/^```/{f=!f;next} !f' | flat)"
# the NEXT-STEPS template (the fence that opens "# [PROJECT_NAME] -- What's Needed"), its "## For Production", and in that
# "### Go-live checklist"; template units are lines, a line that opens no list item, bracket or heading continues the one above
TPL="$(printf '%s\n' "$RC" | awk '/^```/{if(f){if(b ~ /^# \[PROJECT_NAME\] -- What.s Needed/){printf "%s", b; exit} b=""} f=!f; next} f{b=b $0 "\n"}')"
PROD="$(printf '%s\n' "$TPL" | awk '/^## /{on=($0=="## For Production")} on')"
GLT="$(printf '%s\n' "$PROD" | awk '/^##/{on=($0=="### Go-live checklist")} on' | sed 1d)"
tunits() { awk '/^[[:space:]]*$/{if(u!="")print u; u=""; next} /^[[:space:]]*([-*>#[]|[0-9]+\.)/{if(u!="")print u; u=$0; next}
  {u=(u=="")?$0:u" "$0} END{if(u!="")print u}' | tr -s ' '; }
TGL="$(printf '%s\n' "$GLT" | tunits)"
# the go-live units: the readiness check's blocks (code left out) that say go-live, with the list blocks right after one,
# cut into units; plus the template's go-live lines
RGL="$( { printf '%s\n' "$RC" | awk '/^```/{f=!f;next} !f' | awk 'BEGIN{RS=""} {l=($0 ~ /^[[:space:]]*([-*] |[0-9]+\. )/);
  s=(tolower($0) ~ /go-live/) || (l && p); if(s) print $0 "\n"; p=s}' | units; printf '%s\n' "$TGL"; } | grep . || true)"
# like pair, but a negated clause also ends at ")", "]" and " -- " (template lines); RP_STRONG=1 cuts past commas too
rpair() { RP_E="$([ "${RP_STRONG:-}" = 1 ] && echo '[^.;:)\]]' || echo '[^,.;:)\]]')" perl -ne 'chomp; my $r = $_; my $e = $ENV{RP_E};
  s/\.(?=\w)/\x01/g; s/\b(?:never|not|no|none|nothing|neither|nor|cannot|without)\b(?:(?! -- )$e)*//gi; s/\b\w+n\x27t\b(?:(?! -- )$e)*//gi;
  s/\x01/./g; print "$r\x1f$_\n"'; }
raff() { RP_STRONG=1 rpair | cut -d $'\x1f' -f2; }
RPAIRS="$(printf '%s\n' "$RGL" | sents | rpair)"; RUPAIRS="$(printf '%s\n' "$RGL" | rpair)"; TPAIRS="$(printf '%s\n' "$TGL" | sents | rpair)"
rsays()  { local PAIRS="$RPAIRS"; says "$@"; }
rusays() { local PAIRS="$RUPAIRS"; says "$@"; }
tsays()  { local PAIRS="$TPAIRS"; says "$@"; }

# 1. step 2 names the record and points at the guide's section; nothing it says about the go-live items restates the rules
GPTR='(ship-it-guide\.md`?|\bthe (ship-it )?guide(.s)?)[^.;#]{0,30}(`?## )?"?Go-live checklist\b|\bGo-live checklist"?`?[^.;#]{0,25}\b(in|of) [^ ]*ship-it-guide\.md'
GLRESTATE='terms_privacy|security_audit|restore_test|load_test|live_payment|\bschema\b|\bsk-|AKIA|ghp_|github_pat_|-----BEGIN|password=|token=|secret=|/terms\b|/privacy\b|\barbitration\b|personal data|user content|deploy-prod|environment-prod|deployment\.environments|not a legal review|state\]? -- \[?reason'
check "resume-it 1 (the record, by pointer): the readiness check's step 2 names .ship-it-go-live.json and points at ship-it-guide.md's Go-live checklist (which exists); no go-live line restates its rules (item keys, schema, secret patterns, item 1's pages and topics, trigger signals, the PR line)" \
  '[ "$(grep -cxF "$H" "$G")" -ge 1 ] && printf "%s" "$RC2F" | gq -F ".ship-it-go-live.json" && printf "%s" "$RC2F" | gq -E "$GPTR" && ! printf "%s\n" "$RGL" | gq -iE "$GLRESTATE"'

# 2. read only: it says it never writes or stages the file because /ship-it owns it; no paragraph, list item or template
# line naming the file (or the go-live record) tells it to write, stage, commit or change it ("it" included), unless the
# one doing it is /ship-it or the user; no code line writes or stages it
NEVERW='\b(never|not|doesn.t|does not|don.t|do not|won.t)\b[^.;]{0,25}\b(writes?|stages?|commits?|changes?|edits?|updates?)\b'
OWNS='/?ship-it\b[^.;]{0,10}\bowns\b|\bowned by /?ship-it\b|\bonly /?ship-it\b[^.;]{0,15}\b(writes|changes|updates)\b'
WRITE_PL='
my $v = qr/\b(?:write|writes|stage|stages|commit|commits|update|updates|edit|edits|rewrite|rewrites|overwrite|overwrites|save|saves|change|changes|modify|modifies|delete|deletes|remove|removes|mark|marks|settle|settles|fix|fixes|create|creates)\b/i;
my $o = qr/(?:\s+(?:back|out))?(?:\s+(?:to|into|in))?\s+(?:it\b|the (?:go-live )?(?:record|file)\b|(?:main.s|the branch.s|its|the merged|that) (?:copy|record|file)\b|`?\.ship-it-go-live\.json)/i;
while (<STDIN>) { chomp; my ($raw, $aff) = split /\x1f/, $_, 2;
  while ($aff =~ /$v$o|$v[^,.;:]{0,40}\b(?:to|into|in)\s+`?\.ship-it-go-live\.json|\bgit (?:add|commit|rm|checkout|restore)\b/g) {
    my $pre = substr($aff, 0, $-[0]); $pre =~ s/^.*(?:[,;:(]|\. | -- )//s;
    next if $pre =~ /(?<![.\w-])\/?ship-it(?![-\w])|\bonly it\b|\b(?:the user|you|they)\b/i;
    print "$raw\n"; last } }'
RFILE="$( { units < "$R"; printf '%s\n' "$TGL"; } | grep -iE '\.ship-it-go-live\.json|go-live record' || true)"
# (R2, final review: the owner's exact serious line tells the user to "remove it from the file"; that quoted line, and
# only it, word for word, is taken out before the write guard reads -- the same words anywhere else still turn it red.
# R8: in a sentence about a bundle committed "exactly as" received, "the only case/time ... resume-it commits" is the one
# commit R8 states; it is taken out of that sentence alone (here and in owner call 4's write guard) -- any other write
# verb there, or a commit outside it, is red)
# (A2, addendum: the line's last clause is now "-- it may already be in your saved history.")
OD_SER="A serious safety warning says a password or key is in your go-live record. /ship-it owns that file, so I didn't change it. Before we go on: remove it from the file, and replace that password or key with a new one -- it may already be in your saved history."
r8_mask() { sents | perl -pe 's/\bonly (case|time)\b[^.;]{0,50}\bcommits?\b/ONLYCASE/gi if /\bbundle\b/i && /\bexactly as\b/i'; }
RFILEW="$(printf '%s\n' "$RFILE" | L="$OD_SER" perl -pe 's/"\Q$ENV{L}\E"/SERLINE/g' | r8_mask)"
FENCEW="$(awk '/^```/{f=!f;next} f' "$R" | grep -F '.ship-it-go-live.json' | grep -E '\bgit (add|commit|rm|mv|checkout|restore|stash)\b|>>? *.?(\./)?\.ship-it-go-live\.json|\btee\b|\bsed -i\b' || true)"
check "resume-it 2 (read only): resume-it names .ship-it-go-live.json and says it never writes or stages it (/ship-it owns it); nothing that names the file tells it to write, stage, commit or change it, in prose or in code" \
  'printf "%s\n" "$RFILE" | gq -F ".ship-it-go-live.json" && printf "%s\n" "$RGL" | grep -iE "$NEVERW" | gq -iE "$OWNS" && [ -z "$(printf "%s\n" "$RFILEW" | RP_STRONG=1 rpair | perl -e "$WRITE_PL")" ] && [ -z "$FENCEW" ]'

# 3. the NEXT-STEPS template: "### Go-live checklist" inside "## For Production", with its lines
check "resume-it 3 (template): the NEXT-STEPS template's ## For Production holds ### Go-live checklist" \
  '[ -n "$TPL" ] && printf "%s\n" "$PROD" | gq -xF "### Go-live checklist"'
NOFILE='\bnot started\b|\bno (go-live )?(record|file)\b|\bno `?\.ship-it-go-live\.json|\b(record|file|\.ship-it-go-live\.json)`? (doesn.t|does not|isn.t|is not) (exist|there)\b'
# (re-pointed by the owner call, task-2-owner-call-brief.md call 2: the open lines no longer say "asked again at your next
# /ship-it to production"; the skipped line ends "still open", the not-answered line is bare, both exact)
OC_SKL='- [ ] [Item]: skipped -- "[reason]" ([date]) -- still open'
OC_MSL='- [ ] [Item]: not answered yet'
check "resume-it 3a (open items): each skipped or missing item is listed, a skipped one with its reason and date -- the owner call's exact lines, \"$OC_SKL\" and \"$OC_MSL\"; every other open line ends \"still open\"" \
  'tsays "+\`?skipped\`?" "+\breason\b" "+\bdate\b|YYYY-MM-DD" "+\bstill open\b" && printf "%s\n" "$GLT" | gq -xF -- "$OC_SKL" && printf "%s\n" "$GLT" | gq -xF -- "$OC_MSL" && rsays "+\`?skipped\`?( items?)? (or|and|/) \`?missing\`?|\`?missing\`?( items?)? (or|and|/) \`?skipped\`?" && ! printf "%s\n" "$TGL" | grep -E "^[[:space:]]*[-*] \[ \]" | grep -viE "$NOFILE" | grep -vxF -- "$OC_MSL" | grep -vE -- "-- still open$" | gq .'
CS_READS='coming soon`?"?[^.;]{0,80}\b(reads?|read as|shows?|shown as|says?|listed as|as)\b[^.;]{0,3}"?`?not built yet|coming soon`?"?\)? ?(--|:) ?"?not built yet|not built yet"?`?[^.;]{0,30}coming soon'
CS_TODO='coming soon`?"?[^.;,]{0,40}\b(is|are|as|reads?( as)?|listed as)\b[^.;,]{0,10}\b(a |an )?to-?do\b'
check "resume-it 3b (coming soon): a coming soon item reads \"not built yet\" -- never a to-do (no checkbox, never \"asked again\")" \
  'rsays "$CS_READS" && ! printf "%s\n" "$TGL" | grep -iE "coming soon|not built yet" | gq -iE "^[[:space:]]*[-*] \[[ xX]\]|asked again" && ! rsays "+$CS_TODO"'
DN_NOT='\b(aren.t|are not|isn.t|is not|not|never)\b[^.;]{0,20}\b(listed|shown|included|written)\b|\b(don.t|do not|never) (list|show|include)\b|\bomit'
DN_LIST='`?\b(done|na)\b`?[^.;]{0,30}\b(are|is) (also )?(listed|shown|included)\b|\b(list|lists|show|shows|include|includes)\b[^.;]{0,40}`(done|na)`'
check "resume-it 3c (done and na): done and na items aren't listed, and no line lists one" \
  'rsays "\`?\bdone\b\`?" "\`na\`|\bna\b|\bn/a\b|doesn.t apply" "$DN_NOT" && ! rsays "+$DN_LIST" && ! printf "%s\n" "$TGL" | gq -iE "^[[:space:]]*[-*] \[[xX]\]|(--|:)[[:space:]]*\`?(done|na)\`?([^[:alnum:]_]|$)"'
# the no-file line is true today: /ship-it v1.3.0 doesn't run the checklist (the guide's "Safety steps /ship-it doesn't
# run yet"), so the line keeps that not-yet truth, and none of its sentences promises an ask without a qualifier
NY='Safety steps /ship-it doesn.t run yet|/ship-it\b[^.;]{0,60}\b(doesn.t|does not|won.t|can.t|cannot|isn.t|is not|not|has no|hasn.t)\b[^.;]{0,50}\byet\b|\b(doesn.t|does not|isn.t|is not|not)\b[^.;]{0,40}/ship-it\b[^.;]{0,30}\byet\b|\b(doesn.t|does not|isn.t|is not|aren.t|are not|not)\b[^.;]{0,15}\b(run|runs|ask|asks|asked|built|part of|in|have|has)\b[^.;]{0,40}\byet\b|\b(later|future|newer|next|upcoming) (/?ship-it )?(release|version)\b'
PROMISE='\b(asks|runs|checks|goes through|will (ask|run|check|go through))\b|\b(is|are|gets?|you.re|you are|will be) asked\b'
QUAL='\b(once|until|later|future|newer|upcoming)\b|\bwhen\b[^.;]{0,40}\b(adds?|ships?|gets?|does|is (updated|released)|runs? (it|the (go-live )?checklist))\b|\bnext (ship-it |/ship-it )?(release|version)\b'
NFU="$(printf '%s\n' "$RGL" | grep -iE "$NOFILE" || true)"
# the line itself: every sentence of a template no-file line, the no-file sentences in prose, and a quoted "Not started" line
NFL="$( { printf '%s\n' "$TGL" | grep -iE "$NOFILE"; printf '%s\n' "$RGL" | sents | grep -iE "$NOFILE"; printf '%s\n' "$RGL" | grep -oiE '"[^"]*not started[^"]*"'; } || true)"
nofile_ok() { printf '%s\n' "$TGL" | gq -iE "$NOFILE" && printf '%s\n' "$NFU" | gq -iE "$NY" \
  && ! printf '%s\n' "$NFU" | grep -iE '\bnot started\b' | grep -viE "$NY" | gq . \
  && ! printf '%s\n' "$NFL" | sents | rpair | grep -iE $'\x1f'".*($PROMISE)" | cut -d $'\x1f' -f1 | grep -viE "$QUAL" | gq .; }
NOFILE_L="resume-it 3d (no file, true today): the template's no-file line keeps the guide's not-yet truth (today's /ship-it doesn't run the checklist yet), and none of its sentences promises, unqualified, that /ship-it asks"
check "$NOFILE_L" 'nofile_ok'

# 4. a normal open item, not a left-out item (left-out-record.md); listed, never a fix offered unasked
NOTLO='\b(not|never|isn.t|is not)\b (a |an )?left-out items?\b|\bnot the left-out record\b'
LOAFF='\b(is|are|as) (a |an )?left-out items?\b|(--|:) left out by your choice|\b(is|are|as|goes|go|put|puts|write|writes|written|list|lists|listed)\b[^.;,]{0,25}left out by your choice'
check "resume-it 4a (not left out): a go-live item is a normal open item, not a left-out item, and never listed the left-out way" \
  'rsays "$NOTLO" "+\bopen items?\b" && ! rsays "+$LOAFF"'
NOFIX='\b(never|not|doesn.t|does not|don.t|do not|won.t)\b[^.;]{0,30}\b(offers?|suggests?|proposes?)\b[^.;]{0,30}\bfix'
UNASKED='\bunasked\b|\b(unless|until|only (when|if))\b[^.;]{0,30}\basks?\b'
OFFER='\b(offer|offers|offering|suggest|suggests|propose|proposes)\b[^.;]{0,40}\b(fix|fixes|to fix|to add|to build|to write)\b'
check "resume-it 4b (no fix unasked): resume-it lists a go-live item but never offers a fix unasked" \
  'rsays "$NOFIX" "$UNASKED" && ! rsays "+$OFFER"'

# 5. main's copy, as the guide says, read only
MAINC='main.s copy|copy (on|from|of) main|the default branch|origin/'
RONLY='\bread-only\b|\bonly reads?\b|\breads? (it )?only\b|\bjust reads?\b|\bnothing is (checked out|merged|pushed|written)\b'
RW='\bgit (checkout|switch|merge|pull|rebase|push|stash|reset|add|commit|restore|cherry-pick)\b|\bchecks? out\b|\bswitch(es)? to\b|\bpulls? (main|from|origin)\b|\bpush(es)? (to|it|the)\b|\bmerges? (main|origin[^ ]*|the default branch) (into|in)\b'
check "resume-it 5 (main's copy): resume-it reads main's copy merged with the branch's, as ship-it-guide.md's Go-live checklist says, read only (nothing checked out, merged, pulled or pushed)" \
  'rsays "$MAINC" "+\b(merged?|combined?) with\b|\bnewer\b" "+\bbranch.s\b|\bthe branch\b|\bthis branch\b" && rusays "$MAINC" "ship-it-guide\.md|\bthe guide\b|\(The record\)" && rsays "$RONLY" && ! printf "%s\n" "$RGL" | raff | gq -iE "$RW"'

# ---- Task 2 fix round 1 (task-2-fix1-brief.md, calls 1-2): the reason slot never copies a secret; an unreadable record ----
# The new checks read a wider go-live text: a block that says go-live and the blocks after it, up to the next block that
# opens with a bold lead ("**"), a heading or a tag; plus the template's go-live lines (RGL, used above, stays as it was)
RGLW="$( { printf '%s\n' "$RC" | awk '/^```/{f=!f;next} !f' | awk 'BEGIN{RS=""} {g=(tolower($0) ~ /go-live/); b=($0 ~ /^(\*\*|#|<)/);
  s=g || (p && !b); if(s) print $0 "\n"; p=s}' | units; printf '%s\n' "$TGL"; } | grep . || true)"
RPW="$(printf '%s\n' "$RGLW" | sents | rpair)"; RUPW="$(printf '%s\n' "$RGLW" | rpair)"
rwsays()  { local PAIRS="$RPW"; says "$@"; }
rwusays() { local PAIRS="$RUPW"; says "$@"; }
# 6. The reader rule's switches are read from resume-it's go-live text, then the rule renders the template's own skipped
# line for fake stored reasons (built at run time) and is matched against the guide's own secret patterns (A5P, A5A)
NSRE='\b(is|are|gets?) (never|not) (copied|shown|written|put|included|repeated)\b|\bnever (copy|copies|show|shows|write|writes|put|puts|repeat|repeats)\b[^.;:]{0,25}\b(reasons?|values?|it|them)\b|\b(isn.t|aren.t) (copied|shown|written|put|included|repeated)\b'
RNS=0; rwsays '\breasons?\b' 'secret|refuse' "$NSRE" && RNS=1
RNSL=0; printf '%s\n' "$RGLW" | gq -iF '(reason not shown)' && RNSL=1
RLEN=0; rwusays '\breasons?\b' '\b200\b' '+\b(counts?|is treated|treated|is read|reads?) as missing\b|\bas (if|though) (it were )?missing\b' && RLEN=1
SKL="$(printf '%s\n' "$TGL" | grep -iE '^[[:space:]]*[-*] .*\bskipped\b.*\[reason\]' | sed -n 1p || true)"
MSL="$(printf '%s\n' "$TGL" | grep -E '^[[:space:]]*[-*] \[ \]' | grep -viE "\bskipped\b|$NOFILE" | sed -n 1p || true)"
PY7='
import re, sys
ns, nsl, ln, anch = (x == "1" for x in sys.argv[2:6]); pre = [p for p in sys.argv[6].split("\n") if p]; skl, msl = sys.argv[7], sys.argv[8]
alt = "|".join(re.escape(p) for p in pre)
pat = re.compile(("(?:^|[^A-Za-z0-9])(?:" + alt + ")" if anch else "(?:" + alt + ")") + "|[A-Fa-f0-9]{32,}|[A-Za-z0-9+/]{32,}") if pre else None
def render(reason):                        # the NEXT-STEPS line resume-it writes for a stored skipped item with this reason
    if ln and len(reason) > 200: return msl
    hide = ns and nsl and pat is not None and pat.search(reason) is not None
    return re.sub(r"\[date\]", "2026-10-24", re.sub(r"\[reason\]", lambda m: "(reason not shown)" if hide else reason, skl, flags=re.I), flags=re.I)
a = sys.argv[9:]
if sys.argv[1] == "secret":                # a[0], a[1]: reasons holding a secret; a[2], a[3]: their secret parts; a[4]: a clean reason
    ok = "[reason]" in skl.lower() and all("(reason not shown)" in render(r) and s not in render(r) for r, s in ((a[0], a[2]), (a[1], a[3]))) \
         and a[4] in render(a[4]) and "(reason not shown)" not in render(a[4])
else:                                      # a[0]: a clean reason over 200 characters, a[1]: a word only it holds
    ok = bool(msl) and "[reason]" in skl.lower() and a[1] not in render(a[0])
sys.exit(0 if ok else 1)
'
py7() { python3 -I -c "$PY7" "$1" "$RNS" "$RNSL" "$RLEN" "$A5A" "$A5P" "$SKL" "$MSL" "${@:2}" 2>/dev/null; }
F6SK="$(printf '%s%s' s k-)$(printf 'a%.0s' {1..40})"; F6R1="pentest notes at $F6SK"
F6TV="$(printf '%s=%s' token abc123)"; F6R2="$(printf 'report at https://%s/r?%s' vault.example.com "$F6TV")"
F6LONG="LONGMARK$(printf ' the pages wait on our lawyer%.0s' {1..8})"
PARTIAL='\b(first|last) (few|[0-9]+) (characters|chars|letters)\b|\bmask(ed|s|ing)?\b|\bpartly\b|\bpart of (it|the (reason|value|evidence))\b|\btruncat\w*|\bshorten\w*|\bcut (it|the reason|to)\b'
check "resume-it 6a (reason slot, secret): a stored reason the guide's No secret rule would refuse is never copied into NEXT-STEPS.md -- the line reads \"(reason not shown)\", never the value or part of it (evidence too, if the template shows it); on reasons holding a run-time \" sk-\" run and a ?token= URL the template's line hides both, and a clean reason shows" \
  'py7 secret "$F6R1" "$F6R2" "$F6SK" "$F6TV" "our lawyer is writing them" && ! printf "%s\n" "$RGLW" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$PARTIAL" && { ! printf "%s\n" "$TGL" | gq -iE "\bevidence\b" || rwsays "\bevidence\b" "$NSRE"; }'
check "resume-it 6b (reason slot, over 200): a stored reason over 200 characters counts as missing, as the guide says -- on a clean 240-character reason the item gets the template's not-answered line, never the reason or part of it" \
  'py7 long "$F6LONG" LONGMARK'

# 7. An unreadable branch record with no readable main copy: all five not answered yet, never the no-file line (a record
# exists); no line of resume-it's own about GitHub. "Not started" and "no-file line" are kept whole before the negation cut.
UNREAD='unreadable|can.t be read|cannot be read|isn.t readable|not readable'
UPR="$(printf '%s\n' "$RGLW" | sed -e 's/[Nn]ot started/NOTSTARTED/g' -e 's/no-file line/NOFILELINE/g' | sents | rpair)"
ursays() { local PAIRS="$UPR"; says "$@"; }
check "resume-it 7a (unreadable record): an unreadable branch record with no readable main copy lists all five items as not answered yet, and never shows the no-file line (a record exists)" \
  'rwsays "$UNREAD" "\bmain\b|default branch" "+\ball five\b" "not answered yet|\bmissing\b" && ursays "$UNREAD" "\b(never|not|isn.t|no)\b[^.;]{0,40}\"?(NOTSTARTED|NOFILELINE)" && ! ursays "$UNREAD" "+\b(shows?|lists?|gives?|uses?|writes?|gets?)\b[^.;]{0,15}\"?(NOTSTARTED|NOFILELINE)"'
GHRE='github|\breach|network|offline'
GHSAY='\b(say|says|add|adds|write|writes|show|shows|tell|tells|note|notes|mention|mentions|give|gives|repeat|repeats)\b (so|that|it|the user)\b|\b(say|says|add|adds|write|writes|show|shows|give|gives|repeat|repeats)\b (a|an|one|the|its own|the guide.s)( [a-z-]+){0,2} (line|notice|note|warning)\b'
GHQ='"[^"]*(github|reach)[^"]*"'
check "resume-it 7b (GitHub unreachable): resume-it says, in a few words, that it adds no line of its own when GitHub can't be reached, and never adds one" \
  'rwsays "$GHRE" "\b(no|never|nothing|doesn.t|does not|don.t|without)\b[^.;]{0,40}\b(line|say|says|said|notice|mention|repeat|note|word)|\b(say|says|add|adds|mention|mentions)\b (nothing|no line|no notice|no word)" && ! rwsays "$GHRE" "+$GHSAY" && ! printf "%s\n" "$RGLW" | gq -iE "$GHQ"'

# ---- Task 2 adversarial round 1 (task-2-adv1.md; calls in task-2-adv1-fix-brief.md): eight counterexamples, exact inputs ----
# The go-live text is read with its fixed placeholders kept whole ("(no date)", "(no reason given)", "(reason not shown)",
# "Not started", "no-file line") so the negation cut can't eat them; a behavior check reads the rule's switches from that
# text, then renders the template's own skipped line (SKL) or not-answered line (MSL) for the counterexample's record.
PRGLW="$(printf '%s\n' "$RGLW" | sed -e 's/(no date)/NODATE/g' -e 's/(no reason given)/NOREASON/g' -e 's/(reason not shown)/RNOTSHOWN/g' -e 's/[Nn]ot started/NOTSTARTED/g' -e 's/no-file line/NOFILELINE/g')"
PRP="$(printf '%s\n' "$PRGLW" | sents | rpair)"
prsays() { local PAIRS="$PRP"; says "$@"; }
# a second, verb-aware reading: a negated phrase inside a clause ("that isn't a real date", "without a reason") ends at the
# main verb that follows it ("shows", "counts", "is listed"), unless the negation governs that verb ("never shows", "isn't
# shown"), which is cut as before; a switch is on when either reading affirms it, and the plain opposite is cut by both
rpairv() { perl -ne 'chomp; my $r = $_; my $e = q|[^,.;:)\]]|;
  my $mv = qr/(?:shows?|reads?|counts?|appears?|becomes?|(?:is|are) (?:shown|listed|read|treated|written))\b/i;
  s/\.(?=\w)/\x01/g;
  s{\b((?:never|not|no|none|nothing|neither|nor|cannot|without)\b|\w+n\x27t\b)((?:(?! -- )$e)*)}{ my $x = $2;
    $x =~ /^\s+(?:$mv|show|shown|read|count|counted|appear|become|be\b|listed|copied)/i ? "" : $x =~ /\s(?=$mv)/ ? substr($x, $-[0]) : "" }gie;
  s/\x01/./g; print "$r\x1f$_\n"'; }
PRPV="$(printf '%s\n' "$PRGLW" | sents | rpairv)"
prvsays() { local PAIRS="$PRPV"; says "$@"; }
p2says() { prsays "$@" || prvsays "$@"; }
A8DT=0; p2says '\bdates?\b' 'YYYY-MM-DD' '+NODATE' && A8DT=1
A8US=0; { p2says 'unknown state|\bstate\b[^.;]{0,30}\bunknown\b' '+\b(counts?|treated|is read|reads?|listed) as missing\b' && p2says '\bobject\b' '+\b(counts?|treated|is read|reads?|listed) as missing\b'; } && A8US=1
A8NR=0; p2says '\bskipped\b' '\b(no|empty|without|missing)\b[^.;]{0,25}\breasons?\b|\breasons?\b[^.;]{0,25}\b(empty|missing)\b' '+NOREASON' && A8NR=1
# (adv1 4's line, changed by adversarial round 2's call 3: "marked left out by your choice; not left out now" on any item not
# left out now, in place of "left out earlier, since brought back"; the line is kept whole before the negation cut)
LOLINE='marked left out by your choice; not left out now'
PRPL="$(printf '%s\n' "$PRGLW" | sed "s/$LOLINE/MARKEDLO/g" | sents)"
plsays() { local PAIRS; PAIRS="$(printf '%s\n' "$PRPL" | rpair)"; says "$@" || { PAIRS="$(printf '%s\n' "$PRPL" | rpairv)"; says "$@"; }; }
A8LO=0; plsays '+MARKEDLO' '\b(isn.t|is not|not|no longer) left out\b|\bbrought back\b|\bwhether or not\b' 'left-out (reason|words)|\breasons?\b[^.;]{0,40}\bleft[- ]out\b|left out \(your choice\)' && A8LO=1
A8NL=0; p2says '\breasons?\b' '+\b(line breaks?|newlines?)\b[^.;]{0,20}\bbecomes? (a )?spaces?\b|\bon one line\b' && A8NL=1
A8Q=0; { printf '%s' "$SKL" | gq -E "[\"']\[reason\][\"']" || p2says '\breasons?\b' '+\bquoted\b|\bin (double )?quotes\b|\bquotation marks\b'; } && A8Q=1
PY8='
import json, re, sys
m = sys.argv[1]; on = dict(x.split("=") for x in sys.argv[2].split(",")); on = {k: v == "1" for k, v in on.items()}
skl, msl, lo = sys.argv[3], sys.argv[4], sys.argv[5]; a = sys.argv[6:]
def render(it):                            # the NEXT-STEPS line resume-it writes for one stored item, by the rule as written
    if not isinstance(it, dict) or it.get("state") not in ("done", "skipped", "na"):
        if on["us"]: return msl
        it = it if isinstance(it, dict) else {"state": str(it)}
    r, d = it.get("reason"), it.get("date", "")
    if r is None or r == "": r = "(no reason given)" if on["nr"] else ""
    elif on["lo"] and r == lo: r = "marked left out by your choice; not left out now"
    if on["nl"]: r = re.sub(r"[\r\n]+", " ", r)
    if on["dt"] and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", d or ""): d = "(no date)"
    line = skl if re.search(r"[\"\x27]\[reason\][\"\x27]", skl) or not on["q"] else re.sub(r"\[reason\]", "\"[reason]\"", skl, flags=re.I)
    line = re.sub(r"\bskipped\b", it.get("state", ""), line, count=1)
    return re.sub(r"\[date\]", lambda _: d, re.sub(r"\[reason\]", lambda _: r, line, flags=re.I), flags=re.I)
S = lambda **k: dict({"state": "skipped", "reason": "our lawyer is writing them", "date": "2026-10-24", "evidence": ""}, **k)
if m == "date":                            # a[0]: a run-time ghp_ run held in date
    x, y = render(S(date=a[0])), render(S())
    ok = "(no date)" in x and a[0] not in x and a[0][:4] not in x and "2026-10-24" in y and "(no date)" not in y
elif m == "state":                         # an unknown state (capitalised, made up) or an item that is not an object: missing
    ok = bool(msl) and all(render(i) == msl for i in (S(state="Skipped", reason="lawyer"), S(state="pending"), "skipped", ["skipped"]))
elif m == "reason":                        # a skipped item with no reason key, or an empty reason
    ok = all("(no reason given)" in render(i) and not re.search(r"--\s*([\"\x27]\s*[\"\x27])?\s*\((\d|no date)", render(i)) for i in (
        {"state": "skipped", "date": "2026-10-24", "evidence": ""}, S(reason="")))
elif m == "leftout":                       # the reserved left-out reason on an item brought back: plain words, a normal open line
    x = render(S(state="skipped", reason=lo, date="2026-10-20"))
    ok = lo not in x and "marked left out by your choice; not left out now" in x and re.match(r"\s*[-*] \[ \]", x) is not None
elif m == "newline":                       # a[0]: a reason with a line break and a checked box: one line, the reason quoted
    x = render(S(reason=a[0]))
    ok = "\n" not in x and "\r" not in x and ("\"" + re.sub(r"[\r\n]+", " ", a[0]) + "\"") in x
sys.exit(0 if ok else 1)
'
py8() { python3 -I -c "$PY8" "$1" "us=$A8US,nr=$A8NR,lo=$A8LO,nl=$A8NL,dt=$A8DT,q=$A8Q" "$SKL" "$MSL" "Left out (your choice)" "${@:2}" 2>/dev/null; }
A8GHP="ghp""_$(printf 'AbCd%.0s' {1..9})"
check "adv1 1 (date slot): a shown date is only a real YYYY-MM-DD date, anything else shows (no date) -- on a stored date holding a run-time ghp_ run the template's line reads (no date) and never the value or part of it; a real date still shows" \
  'py8 date "$A8GHP"'
# call 2: no record on the branch and no readable main copy (none there, unreadable, or GitHub unreachable): the no-file line
check "adv1 2 (no record, main unreadable or unreachable): with no record on the branch and none readable on main -- missing, unreadable or GitHub unreachable -- resume-it shows the no-file line" \
  'p2says "\bbranch\b" "\bmain\b" "readable|can.t be read" "\breach|GitHub|network" "+NOTSTARTED|NOFILELINE"'
check "adv1 3 (unknown state, missing reason): an unknown state (\"Skipped\", \"pending\") or an item that isn't an object counts as missing and gets the not-answered line; a skipped item with no reason, or an empty one, shows (no reason given), never an empty slot" \
  'py8 state && py8 reason'
check "adv1 4 (left-out words, brought back): a stored reason of exactly the reserved left-out words, on an item not left out now (here, brought back), shows \"marked left out by your choice; not left out now\" on a normal open line, never those words" \
  'py8 leftout'
# call 5: the no-file line, never "first" (re-pointed by the owner call, call 2: the later-release clause and its "next
# production deploy" are gone; the template's no-file line is the owner call's exact line)
A8NF="$( { printf '%s\n' "$TGL" | grep -iE "$NOFILE"; printf '%s\n' "$NFU"; printf '%s\n' "$NFL"; } || true)"
OC_NFL="- Not started -- /ship-it doesn't run this checklist yet."
check "adv1 5 (\"first\" deploy): the template's no-file line is the owner call's \"$OC_NFL\", and no no-file line or sentence says \"first ... deploy\"" \
  'printf "%s\n" "$GLT" | grep -iE "$NOFILE" | gq -xF -- "$OC_NFL" && ! printf "%s\n" "$A8NF" | gq -iE "\bfirst\b[^.;]{0,15}\b(production )?deploy"'
# call 6 (re-pointed by the owner call, call 2): the template keeps its open lines, and none of them -- nor any go-live
# sentence, on its affirmed text -- says "asked again" (so none says when /ship-it asks)
A8AG="$( { printf '%s\n' "$TGL"; printf '%s\n' "$RGLW" | sents; } | grep -iE 'asked again (at|when|on|in)\b' || true)"
check "adv1 6 (\"next /ship-it\"): the template's open lines say nothing of a next /ship-it -- no template line says \"asked again\", and no go-live sentence affirms \"asked again at/when/on/in ...\"" \
  'printf "%s\n" "$TGL" | gq -E "^[[:space:]]*[-*] \[ \]" && ! printf "%s\n" "$TGL" | gq -iE "asked again" && ! printf "%s\n" "$A8AG" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "asked again"'
check "adv1 7 (reason on one line): a reason's line breaks become spaces and it shows as quoted text -- on \"done\", a line break and \"- [x] Security / Compliance: all approved\" the template's line stays one line with the reason in quotes" \
  'py8 newline "$(printf "done\n- [x] Security / Compliance: all approved")"'
# call 8: never staged in any step; a Desktop bundle's first commit keeps the file exactly as it came, unedited
A8BU="$(printf '%s\n' "$RGLW" | sents | grep -iE '\bbundle' | grep -iE '\b(first|initial) commit' || true)"
check "adv1 8 (never staged): resume-it says it never stages a change to .ship-it-go-live.json in any step, and a Claude Desktop bundle's first commit keeps the file exactly as it came, without editing it" \
  'rwsays "\.ship-it-go-live\.json|go-live record" "\b(never|not|no|doesn.t|does not)\b[^.;]{0,25}\bstages?\b" "\b(any|every|no) (other )?(step|commit)s?\b|\banywhere\b" && printf "%s\n" "$A8BU" | gq -iE "\bas it came\b|\bunedited\b|\bwithout edit|\bunchanged\b|\bexactly as\b" && ! printf "%s\n" "$A8BU" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bedit(s|ed|ing)?\b|\bfix(es|ed|ing)?\b|\brewrit|\btid(y|ies|ied)\b|\bnormali[sz]|\bupdat"'

# ---- Task 2 adversarial round 2 (task-2-adv2.md; calls in task-2-adv2-fix-brief.md): four counterexamples, exact inputs ----
GLN='\.ship-it-go-live\.json|go-live (record|file|answers)'
WU="$(units < "$R")"
SCU="$(awk '/<step name="security-scanner-remediation">/{on=1} on; on&&/<\/step>/{exit}' "$R" | awk '/^```/{f=!f;next} !f' | units)"
# call 1, side doors: the scanner step carries the go-live carve-out (like the left-out one): a finding on the record is not
# fixed, whatever its severity, and the user hears once, with no value, the line for its tier (the guide's No-secret rule
# pointed at outside it); the catch-up doesn't apply a gap on it (X01); whether either holds up work is R2's two tiers,
# below; the commit offer never stages it, commits the rest and says it left it for /ship-it
A9NOTFIX='\b(not|never|isn.t)\b[^.;]{0,20}\b(fixed|fix|applied|apply|changed|edited)\b'
A9SEV='whatever (its|the) severity|any severity|regardless of (its |the )?severity|even (when|if)[^.;]{0,15}critical'
A9HOLD='\b(doesn.t|does not|never|not|won.t)\b[^.;]{0,15}\b(hold|holds|block|blocks)\b'
# (re-pointed by the owner call, call 3: the "/ship-it clears ... next production run" pins (A9CLEAR, A9NEXT) are replaced by
# the owner call's exact scanner line, which says only that /ship-it owns the file)
OC_SCAN="A safety warning is about an answer in your go-live record. /ship-it owns that file, so I didn't change it; you can change that answer in the file yourself."
A9NOVAL='\bno value\b|\bnever (names?|shows?|says?|quotes?) (the|a|any|its) value\b|\bwithout (the|a|any) value\b|\bnames? no value\b|\bno scan detail\b'
A9APPLY='\b(apply|applies|applying)\b[^.;]{0,30}\b(it|the (diff|fix|record|file))\b|\bfix(es)? (it|the (record|file|finding))\b'
# (re-pointed by R2, final review, owner: two tiers. Less serious (Medium or Low): not fixed, doesn't hold up the work,
# the scanner line. Serious (Critical or High, or a [BLOCK] catch-up gap): not fixed, holds up the work as any Critical or
# High finding does, the serious line. SCG: the scanner step's go-live units, from a unit that names the record up to the
# next bold lead; the two exact lines become LESSLINE / SERLINE, and TIER_PL names the tier each one is said under (the
# last tier word before it in its unit; "less serious" is the lower tier, never "serious")
SCG="$(printf '%s\n' "$SCU" | L1="$OC_SCAN" L2="$OD_SER" perl -pe 's/"\Q$ENV{L1}\E"/LESSLINE/g; s/"\Q$ENV{L2}\E"/SERLINE/g' \
  | G="$GLN" awk '{m=(tolower($0) ~ ENVIRON["G"]) || /LESSLINE|SERLINE/} m{on=1} on&&!m&&/^\*\*/{on=0} on')"
SCS="$(printf '%s\n' "$SCG" | sed -E 's/[Ll]ess serious/LESSSER/g' | sents)"
TIER_PL='while (<STDIN>) { my $u = $_; while ($u =~ /(LESSLINE|SERLINE)/g) { my ($m, $pre, $t) = ($1, substr($u, 0, $-[0]), "none");
  while ($pre =~ /\b(LESSSER|less serious|medium|low)\b|\b(serious|critical|high)\b|(\[BLOCK\])/gi) { $t = defined $1 ? "less" : "serious" }
  print "$m $t\n" } }'
LESST='LESSSER|\bMedium\b|\bLow\b'
SERT='\bCritical\b|\bHigh\b|\bserious\b|\[BLOCK\]'
HOLDA='\bhold(s|ing)? (up|back)\b|\bblocks?\b'
tiers() { printf '%s\n' "$1" | sed -E 's/[Ll]ess serious/LESSSER/g' | perl -e "$TIER_PL" | sort -u | tr '\n' ' '; }
a9_scan() { printf '%s\n' "$SCG" | grep -iE "$GLN" | grep -iE '\bfindings?\b' | grep -iE "$A9NOTFIX" | grep -iE "$A9SEV" | gq . \
  && [ "$(tiers "$SCG")" = "LESSLINE less SERLINE serious " ] \
  && printf '%s\n' "$SCS" | grep -iE "$LESST" | gq -iE "$A9HOLD" && ! printf '%s\n' "$SCS" | grep -iE "$LESST" | rpair | cut -d $'\x1f' -f2 | gq -iE "$HOLDA" \
  && printf '%s\n' "$SCS" | grep -iE "$SERT" | grep -viE "$LESST" | rpair | cut -d $'\x1f' -f2 | gq -iE "$HOLDA" \
  && printf '%s\n' "$SCG" | gq -iE 'No.secret' && printf '%s\n' "$SCG" | gq -iE "$A9NOVAL" && ! printf '%s\n' "$SCG" | gq -iE '\[(the )?(value|secret|key|token)\]'; }
CUS2="$(printf '%s\n' "$WU" | grep -iE "$GLN" | grep -iE 'catch-up|build-standards|\bX01\b|\bgaps?\b' | sed -E 's/[Ll]ess serious/LESSSER/g' | sents)"
a9_catchup() { printf '%s\n' "$WU" | grep -iE "$GLN" | grep -iE 'catch-up|build-standards|\bX01\b|\bgaps?\b' | gq -iE "$A9NOTFIX" \
  && printf '%s\n' "$CUS2" | grep -viE '\[BLOCK\]' | gq -iE "$A9HOLD" \
  && printf '%s\n' "$CUS2" | grep -F '[BLOCK]' | rpair | cut -d $'\x1f' -f2 | gq -iE "$HOLDA" \
  && ! printf '%s\n' "$CUS2" | grep -F '[BLOCK]' | gq -iE "$A9HOLD"; }
a9_commit() { printf '%s\n' "$WU" | grep -iE "$GLN" | grep -iE 'uncommitted|unsaved|commit (them|offer)' | grep -iE '\b(never|not|doesn.t|does not|won.t)\b[^.;]{0,25}\bstag' \
  | grep -iE '\bthe rest\b' | grep -iE '\b(left|leaves?|leaving)\b[^.;]{0,40}\bfor /ship-it\b' | grep -iE '\bone (plain )?line\b|"[^"]*for /ship-it[^"]*"' | gq .; }
check "adv2 1 (side doors; re-pointed by R2): the scanner step never fixes a finding on .ship-it-go-live.json, whatever its severity; a less serious one (Medium or Low) doesn't hold up work and gets the scanner line, a serious one (Critical or High) holds up work and gets the serious line, with no value (No-secret rule); the catch-up doesn't apply a gap on it (X01): a less serious gap doesn't hold up work, a [BLOCK] gap does; the commit offer never stages it, commits the rest and says it left it for /ship-it" \
  'a9_scan && a9_catchup && a9_commit && ! printf "%s\n" "$WU" | grep -iE "$GLN" | RP_STRONG=1 rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$A9APPLY"'

# calls 2 and 3 render the template's own line for the counterexample's item, the rule's switches read from the go-live text
# (the call-3 line kept whole as MARKEDLO; plsays reads it both ways, as adv1 does)
A9QL=0; { plsays '\bleft[- ]out\b' '\b(now|currently|still|while)\b' '\b(whatever|regardless of|no matter)\b[^.;]{0,25}\breasons?\b|\bany (stored )?reason\b' '+\bquiet\b' \
  || plsays '\bleft[- ]out\b' '\b(now|currently|still|while)\b' '\b(whatever|regardless of|no matter)\b[^.;]{0,25}\breasons?\b|\bany (stored )?reason\b' '\b(not|never|isn.t)\b[^.;]{0,10}\b(listed|shown)\b'; } && A9QL=1
A9ANY=0; plsays 'MARKEDLO' '\b(isn.t|is not|not) left out now\b|\bwhether or not\b|\bnever (really )?left out\b|\bany item\b' && A9ANY=1
PY9='
import re, sys
ql, lo_on, anyc = (x == "1" for x in sys.argv[2:5]); skl, lo = sys.argv[5], sys.argv[6]; line3 = "marked left out by your choice; not left out now"
def render(it, left_out_now, was_left_out):  # None when the item is not listed
    if ql and left_out_now: return None
    r = it["reason"]
    if lo_on and r == lo and not left_out_now and (anyc or was_left_out): r = line3
    return re.sub(r"\[date\]", it["date"], re.sub(r"\[reason\]", lambda _: r, skl, flags=re.I), flags=re.I)
item1 = {"state": "skipped", "reason": "our lawyer is writing them", "date": "2026-10-20", "evidence": ""}
if sys.argv[1] == "quiet":                 # item 1, a user reason, its left-out item left out now: not listed; not left out: listed
    y = render(item1, False, False)
    ok = render(item1, True, False) is None and y is not None and "our lawyer is writing them" in y
else:                                      # the reserved words, never left out (no left-out record): the call-3 line
    x = render(dict(item1, reason=lo, date="2026-10-24"), False, False)
    ok = x is not None and line3 in x and lo not in x and "since brought back" not in x and re.match(r"\s*[-*] \[ \]", x) is not None
sys.exit(0 if ok else 1)
'
py9() { python3 -I -c "$PY9" "$1" "$A9QL" "$A8LO" "$A9ANY" "$SKL" "Left out (your choice)" 2>/dev/null; }
check "adv2 2 (quiet while left out): item 1, skipped with the user's reason, while its left-out item is left out now (left-out-record.md), is not listed -- never asked again, never a to-do, whatever its reason -- and the same item not left out is listed" \
  'py9 quiet && ! plsays "\bleft[- ]out\b" "\b(now|currently|still)\b" "+\basked again\b|\b(is|are) listed\b|\bto-?do\b"'
check "adv2 3 (reserved words, no left-out record): the reserved left-out words on an item never left out show \"marked left out by your choice; not left out now\" on a normal open line, and the go-live text never says \"since brought back\"" \
  'py9 reserved && ! printf "%s\n" "$RGLW" | gq -iF "since brought back"'

# call 4: on an unreadable record resume-it never repeats the guide's "I couldn't read your go-live record, so I'm going
# through it again" (/ship-it's line): a sentence says so, and no quoted line of resume-it's own goes through it again,
# rewrites or asks again unless a negation stands right before the quote
A9P="$(printf '%s\n' "$WU" | sed -e 's/going through it again/GOINGAGAIN/g' -e "s/couldn.t read your go-live record/COULDNTREAD/g")"
A9QG='
my $bad = 0;
while (<STDIN>) { next unless /unreadable|can.t be read|COULDNTREAD/i;
  while (/"([^"]*)"/g) { my ($q, $s) = ($1, $-[0]); next unless $q =~ /GOINGAGAIN|going through|go through it|rewrit|ask(ing|ed)?\b[^"]{0,20}\bagain/i;
    my $pre = substr($_, 0, $s); $pre =~ s/^.*[.!?]\s//s; $pre = substr($pre, -45) if length($pre) > 45;
    $bad = 1 unless $pre =~ /\b(never|not|no)\b|n\x27t\b/i } }
exit $bad;'
check "adv2 4 (unreadable record, chat line): resume-it says it never repeats the guide's \"I couldn't read your go-live record, so I'm going through it again\", and no quoted line of its own says it goes through it again" \
  'printf "%s\n" "$A9P" | grep -iE "unreadable|can.t be read|COULDNTREAD" | sents | gq -iE "\b(never|not|doesn.t|does not|don.t)\b[^.;]{0,25}\b(repeats?|says?|uses?|copies|quotes?)\b[^.;]{0,40}(GOINGAGAIN|COULDNTREAD|(the guide.s|/ship-it.s) (line|notice|words|sentence))" && printf "%s\n" "$A9P" | perl -e "$A9QG"'

# ---- Task 2 owner call (task-2-owner-call-brief.md, 2026-11-11): /resume-it never says what /ship-it will do ----
# The user-facing go-live lines: every "..." or `...` span in a unit of resume-it.md that names the go-live record (a span
# right after a negated speech verb -- "never repeats /ship-it's line ("...")" -- is a quoted counter-example, not resume-it's
# line; "names no value: "..."" is not such a negation),
# every template go-live line, and what the prose tells the user about it (the words after "tell the user" or "say in one
# line", quotes taken out). On the affirmed
# text none may say what /ship-it will do: ask, ask again, clear, go through, run later, a later release.
OCU="$(printf '%s\n' "$WU" | grep -iE 'go-live|\.ship-it-go-live\.json' || true)"
OC_SPANS='
while (<STDIN>) { chomp; my $u = $_;
  while ($u =~ /"([^"]*)"|`([^`]*)`/g) { my ($q, $s) = (defined $1 ? $1 : $2, $-[0]);
    my $pre = substr($u, 0, $s); $pre =~ s/^.*[.!?]\s//s; $pre = substr($pre, -45) if length($pre) > 45;
    print "$q\n" unless $pre =~ /(\b(never|not)\b|n\x27t\b)[^"]{0,30}\b(repeat|say|use|quote|copy|write|show)s?\b[^"]{0,30}$/i } }'
OC_UF="$( { printf '%s\n' "$OCU" | perl -e "$OC_SPANS"; printf '%s\n' "$TGL"
  printf '%s\n' "$OCU" | sed -E 's/"[^"]*"//g' | sents \
  | perl -ne 'print "$1\n" if /\b(?:tells? (?:the user|them|you)|the user hears|says? (?:to the user|in one line))\b(.*)$/i'; } | grep . || true)"
OC_FUT='\basked again\b|\b(asks?|asked|asking)\b|\bwill\b|\b[a-z]+[^[:alnum:][:space:]]ll\b|\bclear(s|ed|ing)?\b|\bgo(es|ing)? through\b|\bruns? (it|them|this checklist|the checklist)? ?later\b|\b(later|next|future|newer|upcoming)\b[^.;"]{0,25}\b(release|version|/ship-it|production (run|request|deploy))\b'
OC_RULE='\b(never|doesn.t|does not|don.t|do not)\b[^.;]{0,30}\bsays?\b[^.;]{0,15}\bwhat /ship-it will do\b'
check "owner call 1 (own words only): beside the read-only rule a sentence says resume-it never says what /ship-it will do, and no user-facing go-live line (a quoted or template line, or what it tells the user) says what /ship-it will do -- asks, asked again, clears, goes through, a later release (\"/ship-it doesn't run this checklist yet\" is allowed)" \
  'rwusays "\bonly reads the go-live record\b" "$OC_RULE" && [ -n "$OC_UF" ] && ! printf "%s\n" "$OC_UF" | RP_STRONG=1 rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$OC_FUT"'
# call 3: the scanner line, exact, with no value or scan detail in it, said once per session in all -- the scanner step says
# it once per session, and the catch-up says it only if the scanner step hasn't (never a second time)
OC_CU="$(printf '%s\n' "$WU" | grep -iE "$GLN" | grep -iE 'catch-up|build-standards|\bX01\b|\bgaps?\b' || true)"
OC_ONCE='\bonce per session in all\b|\b(doesn.t|does not|don.t|do not|never|not)\b[^.;]{0,20}\b(say|says|said|repeat|repeats|repeated|tell|tells)\b[^.;]{0,20}\b(it )?again\b|\bonly (if|when|unless)\b[^.;]{0,40}\bscanner step\b[^.;]{0,25}\b(didn.t|did not|hasn.t|has not|hadn.t)\b'
OC_TWICE='\b(also|again|too|as well)\b[^.;]{0,30}\b(say|says|tell|tells|repeat|repeats)\b|\b(say|says|tell|tells|repeat|repeats)\b[^.;]{0,60}\b(again|too|as well|a second time|each time)\b'
# (re-pointed by R2, final review: two exact lines now -- the scanner line for a less serious finding, the serious line
# for a serious one -- each said once per session in all, scanner step and catch-up together)
check "owner call 3 (scanner line; re-pointed by R2): the scanner step says exactly \"$OC_SCAN\" for a less serious finding and the serious line for a serious one, each once per session in all -- no value, no scan detail, no placeholder -- and the catch-up never says one a second time" \
  '( for m in LESSLINE SERLINE; do printf "%s\n" "$SCG" | grep -F "$m" | grep -iE "\bonce per session in all\b" | grep -iE "$A9NOVAL" | grep -viE "\[(the )?(value|secret|key|token|field|item)\]" | gq . || exit 1; done ) && [ -n "$OC_CU" ] && printf "%s\n" "$OC_CU" | sents | gq -iE "$OC_ONCE" && ! printf "%s\n" "$OC_CU" | sents | RP_STRONG=1 rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$OC_TWICE"'
# call 4: the user asks resume-it to fix it -- one line that /ship-it owns that file and the user can change the answer in
# the file themselves; nothing else offered; resume-it still never writes the record
OC_FIXU="$(printf '%s\n' "$WU" | grep -iE '\b(the user|they|you)\b[^.;]{0,25}\basks?\b[^.;]{0,50}\b(fix|change|correct|clear|edit)' | grep -iE '/?ship-it\b[^.;]{0,10}\bowns\b|\bowned by /?ship-it\b' | grep -iE '\b(the user|they|you)\b[^.;]{0,15}\bcan (change|edit)\b[^.;]{0,40}\b(themselves|yourself|in the file)\b' || true)"
OC_DOIT='(^|[.;:,] |\b(and|then|so) )(change|edit|fix|update|write|rewrite|clear|correct)\b|\b(resume-it|I)\b (will )?(change|edit|fix|update|write|rewrite|clear|correct)(s|es)?\b'
check "owner call 4 (asked to fix it): when the user asks resume-it to fix the record, it answers in one line that /ship-it owns that file and the user can change the answer in the file themselves, offers nothing else, and never writes the record" \
  '[ -n "$OC_FIXU" ] && printf "%s\n" "$OC_FIXU" | gq -iE "\bone (plain )?line\b" && printf "%s\n" "$OC_FIXU" | gq -iE "\b(offers?|offering) nothing else\b|\bnothing else\b" && ! printf "%s\n" "$OC_FIXU" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$OFFER|$OC_DOIT" && [ -z "$(printf "%s\n" "$OC_FIXU" | r8_mask | RP_STRONG=1 rpair | perl -e "$WRITE_PL")" ] && printf "%s\n" "$RGL" | grep -iE "$NEVERW" | gq -iE "$OWNS"'
# call 5: one name for the file in what the user reads -- "go-live record"; the commit-offer line is exact
OC_COMMIT='I left your go-live record for /ship-it, which owns it.'
check "owner call 5 (one name): the commit offer says \"$OC_COMMIT\", and no line of resume-it.md says \"go-live answers file\"" \
  'printf "%s\n" "$WU" | gq -F -- "\"$OC_COMMIT\"" && ! gq -iF "go-live answers file" "$R"'
# call 6: the unreadable line, exact, said only when no copy of the record can be read; when main's copy can be read,
# nothing is said about the branch's file
OC_UNR="I couldn't read your go-live record, so the list shows none of its answers."
OC_UNRU="$(printf '%s\n' "$WU" | grep -F -- "\"$OC_UNR\"" || true)"
OC_SCOPE='\bno copy\b[^.;]{0,30}\b(can be read|is readable|readable)\b|\bonly when\b[^.;]{0,80}\bmain\b[^.;]{0,30}\b(has none|none|unreadable|can.t be read)\b|\bmain has none or (it is |is )?unreadable\b'
OC_UNSCOPED='\b(even (when|if)|whenever|whether or not|always)\b[^.;]{0,60}\b(main|copy|readable)\b|\b(main.s copy|main)\b[^.;]{0,25}\b(can be read|is readable)\b[^.;]{0,40}\b(say|says|tell|tells)\b[^.;]{0,15}\b(it|that|this|the line|so)\b'
check "owner call 6 (unreadable line): resume-it says \"$OC_UNR\" only when no copy of the record can be read, and when main's copy can be read it says nothing about the branch's file" \
  '[ -n "$OC_UNRU" ] && printf "%s\n" "$OC_UNRU" | gq -iE "$OC_SCOPE" && ! printf "%s\n" "$OC_UNRU" | sents | RP_STRONG=1 rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$OC_UNSCOPED" && printf "%s\n" "$OCU" | sents | grep -iE "main.s copy[^.;]{0,20}\b(can be read|is readable)\b" | gq -iE "\bsays nothing\b|\bnothing about\b|\bno line\b"'

# ---- Task 2 owner calls A-D (conflicted go-live record): removed by R1, final review (the owner took the conflict
# rules out of this release; they get their own design card) ----

# ---- final review (final-review-fix-brief.md, 2026-11-11): R1, R2 and R8 in resume-it ----
# R1: the conflict passage, its lead-in sentence and the read-only rule's pointer are gone; the commit offer stays word
# for word
R1_COMMIT='On a yes to Uncommitted changes, never stage `.ship-it-go-live.json`: commit the rest, and if that file has changes, say in one line: "I left your go-live record for /ship-it, which owns it."'
R1_CONF='\bconflict|\bunmerged\b|\bunfinished\b|--abort\b|\bmerely changed\b'
check "R1 (resume-it, the conflict rules out): the commit offer's sentence stays word for word; no unit that names the go-live record speaks of a conflict, an unmerged or unfinished update, an abort, or a record \"merely changed\"" \
  'printf "%s\n" "$WU" | gq -F -- "$R1_COMMIT" && ! printf "%s\n" "$WU" | grep -iE "$GLN" | gq -iE "$R1_CONF"'
# R2: the serious line, exact, said under the serious tier in the scanner step; the catch-up gives it for a [BLOCK] gap
# (re-pointed by A2: the serious tier is a Critical or High finding that a password or key is in the record, and the X01
# [BLOCK] gap; any other finding or gap takes the less serious line; the serious line is introduced "in these words", not
# "in one plain line"; made whole by M3: the catch-up's [BLOCK] sentence must name the serious line itself -- "as a
# serious finding does", or "the less serious line, also for a [BLOCK] gap", is red)
check "R2 (the serious line): the scanner step says exactly \"$OD_SER\", in these words, for a Critical or High finding that a password or key is in the record, never for a less serious one; any other finding takes the less serious line; the catch-up gives the serious line for the X01 [BLOCK] gap and the less serious line for any other gap" \
  '[ "$(tiers "$SCG")" = "LESSLINE less SERLINE serious " ] && printf "%s\n" "$SCS" | grep -F SERLINE | gq -iE "\bin these words\b" && ! printf "%s\n" "$SCS" | grep -F SERLINE | gq -iE "\bone (plain )?line\b" && printf "%s\n" "$SCS" | grep -iE "\bCritical or High\b" | grep -viE "$LESST" | gq -iE "\bpassword or key\b" && printf "%s\n" "$SCS" | grep -iE "\bany other finding\b" | gq -iE "LESSSER|LESSLINE" && printf "%s\n" "$CUS2" | grep -F "[BLOCK]" | grep -F X01 | gq -iE "\bserious line\b|SERLINE" && printf "%s\n" "$CUS2" | grep -iE "\bany other gaps?\b|\bother gaps\b" | gq -iE "LESSSER line|\bscanner line\b"'
# R2: the hold and how it ends (re-pointed by A1: resume-it re-reads the file and goes on once the record on disk no
# longer holds the password or key the finding names -- it does not wait for the scanner's report -- or on the user's
# go-on; a finding whose value is gone from the record on disk doesn't hold and is not said again; the catch-up's [BLOCK]
# gap ends the same way; "no longer shows" is red anywhere; step 3 no longer sets the record's findings aside)
A1_END='\bon disk\b[^.;]{0,15}\bno longer (holds?|has|contains)\b[^.;]{0,40}\bpassword or key\b'
check "R2 (the hold and how it ends): resume-it re-reads the file and goes on once the record on disk no longer holds the password or key the finding names, without waiting for the scanner's report; a finding whose value is gone from the record on disk doesn't hold and isn't said again; the catch-up's [BLOCK] gap ends the same way; nothing says \"no longer shows\"; no sentence says a finding of any severity doesn't hold up the work; step 3 no longer sets the record's findings aside" \
  'printf "%s\n" "$SCS" | grep -iE "$A1_END" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bgo(es)? on\b|\bresolved\b|\bends?\b" && printf "%s\n" "$SCS" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bre-?reads?\b[^.;:]{0,15}\b(the )?(file|record)\b" && printf "%s\n" "$SCS" | gq -iE "\b(not|never|doesn.t|does not|don.t)\b[^.;]{0,15}\bwait\b[^.;]{0,30}\bscanner" && printf "%s\n" "$SCS" | grep -iE "\bon disk\b" | grep -iE "\b(doesn.t|does not|not|never) hold\b" | gq -iE "\b(not|never|isn.t) said again\b|\b(doesn.t|does not|don.t) say it again\b" && printf "%s\n" "$CUS2" | grep -F "[BLOCK]" | gq -iE "$A1_END" && ! printf "%s\n" "$WU" | grep -iE "$GLN|\bfindings?\b" | gq -iE "\bno longer shows?\b" && ! { printf "%s\n" "$SCS"; printf "%s\n" "$CUS2"; } | grep -iE "$A9SEV" | gq -iE "$A9HOLD" && ! printf "%s\n" "$WU" | grep -E "^\*\*3\. After all critical/high" | gq -iE "go-live record.s findings aside|go-live record[^.;)]{0,40}\baside\b"'
# R2: the user's own "go on" (re-pointed by A1: a go-on given once holds for the session, scanner step and catch-up
# alike; the finding is listed as open in that session's wrap-up summary -- "your summary" is red; never suggested)
GOSUG='\b(suggest|suggests|offer|offers|propose|proposes|recommend|recommends)\b[^.;]{0,40}\b(go(ing)? on|to go on|skip(ping)?|mov(e|ing) on|leav(e|ing) it)\b'
check "R2 (the user's go on): if the user says to go on without removing it, resume-it goes on; that go-on holds for the session, in the scanner step and the catch-up alike; the finding is listed as open in that session's wrap-up summary; a sentence says it never suggests going on, and none affirms it does" \
  'printf "%s\n" "$SCS" | grep -iE "\b(the user|they|you)\b[^.;]{0,15}\bsays? to go on\b" | grep -iE "\bwithout removing\b" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bgo(es)? on\b" && printf "%s\n" "$SCS" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | grep -iE "\bgo-?on\b|\bgo on\b" | grep -iE "\b(holds?|stands?|counts?) for the (whole )?session\b|\bfor the rest of the session\b" | gq -iE "\bscanner step\b[^.;]{0,30}\bcatch-up\b|\bcatch-up\b[^.;]{0,30}\bscanner step\b" && printf "%s\n" "$SCS" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "\bopen\b[^.;]{0,40}\bwrap-up summary\b" && ! printf "%s\n" "$SCS" | gq -iE "\byour summary\b" && printf "%s\n" "$SCS" | gq -iE "\b(never|not|doesn.t|does not|don.t)\b[^.;]{0,15}\b(suggest|offer|propose)s?\b" && ! printf "%s\n" "$SCS" | rpair | cut -d $'"'"'\x1f'"'"' -f2 | gq -iE "$GOSUG"'
# R2b: while a finding or gap is open on the record, every stored reason from it shows as (reason not shown) in
# NEXT-STEPS.md, whatever the guide's patterns say (otherwise the flagged value is copied into a file made for sharing)
check "R2b (open finding, reasons hidden): while a finding or gap is open on the record, the readiness check shows every stored reason from it as (reason not shown) in NEXT-STEPS.md, whatever the guide's patterns say -- never only the matching ones" \
  'prsays "+\b(finding|gap)\b[^.;]{0,30}\bis open\b" "RNOTSHOWN" "+\b(every|each|all|any)\b[^.;]{0,15}\b(stored )?reasons?\b" "\b(whatever|regardless of|no matter)\b[^.;]{0,30}\bpatterns?\b" && ! prsays "\b(finding|gap)\b[^.;]{0,30}\bis open\b" "RNOTSHOWN" "+\bonly (when|if)\b[^.;]{0,30}\b(match|pattern)"'
# R2c: a finding or gap on the record is never added to TODO.md and never counted or offered as something to tackle
R2C_TODO='\b(never|not|isn.t)\b[^.;]{0,25}\b(added|put|written|listed)\b[^.;]{0,10}\b(to|in|on|into)\b[^.;]{0,5}`?TODO\.md'
R2C_CNT='\b(never|not|isn.t)\b[^.;]{0,20}\bcounted\b[^.;]{0,25}\boffered\b|\b(never|not|isn.t)\b[^.;]{0,20}\boffered\b[^.;]{0,25}\bcounted\b'
r2c_ok() { local f g; f="$(printf '%s\n' "$SCS")"; g="$( { printf '%s\n' "$CUS2"; printf '%s\n' "$SCS" | grep -iE '\bgaps?\b'; } )"
  printf '%s\n' "$f" | gq -iE "$R2C_TODO" && printf '%s\n' "$f" | gq -iE "$R2C_CNT" && printf '%s\n' "$g" | gq -iE "$R2C_TODO" && printf '%s\n' "$g" | gq -iE "$R2C_CNT" \
  && ! { printf '%s\n' "$SCS"; printf '%s\n' "$CUS2"; } | rpair | cut -d $'\x1f' -f2 | gq -iE '\b(add|adds|added|put|puts|write|writes|list|lists)\b[^.;]{0,30}TODO\.md'; }
check "R2c (no to-do): a finding or gap on the record is never added to TODO.md and never counted or offered as something to tackle -- in the scanner step and in the catch-up -- and no sentence adds one to TODO.md" 'r2c_ok'
# R8: a Desktop bundle's first commit -- committing a bundle exactly as it was received is not a change to the record,
# and it is the only case in which resume-it commits the file
check "R8 (the bundle's first commit): committing a Claude Desktop bundle exactly as it was received is not a change to the go-live record, and it is the only case in which resume-it commits the file" \
  'rwusays "\bbundle" "\b(first|initial) commit" "\bexactly as (it was received|it came|received)\b" "\b(is not|isn.t|not) a change to the (go-live )?record\b" "+\bonly (case|time)\b[^.;]{0,50}\bcommits?\b"'

# Call B: the guide's record rules ("### The record") say /ship-it writes the record ending in a single newline, with no
# trailing spaces, so formatters leave it as written; then a fixture record is written the way they say and run through
# an end-of-file check and a trailing-whitespace check, modelled on pre-commit-hooks' fixers (nothing installed)
RECS="$(printf '%s\n' "$SEC" | awk '/^```/{f=!f} !f&&/^#/{on=($0=="### The record")} on' | units | sents | pair)"
recsays() { local PAIRS="$RECS"; says "$@"; }
B_NL='+\bend(s|ing)? (in|with) (a )?(single|one)( final)? newline\b'
B_TS='\b(no|without( any)?) trailing (spaces|whitespace)\b'
check "owner call B1 (the record's last byte): the guide's record rules say /ship-it writes the record ending in a single newline, with no trailing spaces, so a repo's formatters leave it as written" \
  'recsays "+/ship-it\b[^.;]{0,10}\bwrites?\b" "$B_NL" "$B_TS" "+\bformatters?\b[^.;]{0,20}\bleave\b"'
BNL=0; recsays "+/ship-it\b[^.;]{0,10}\bwrites?\b" "$B_NL" && BNL=1
BTS=0; recsays "+/ship-it\b[^.;]{0,10}\bwrites?\b" "$B_TS" && BTS=1
PYB='
import json, sys
nl, ts = sys.argv[1] == "1", sys.argv[2] == "1"
s = json.dumps(json.loads(sys.argv[3]), indent=2, separators=(", ", ": "))   # leaves ", " at line ends, no final newline
if ts: s = "\n".join(l.rstrip() for l in s.split("\n"))
if nl: s = s.rstrip("\n") + "\n"
eof = lambda t: t if t == "" else t.rstrip("\r\n") + "\n"                                      # end-of-file-fixer
tw = lambda t: "".join(l.rstrip("\r\n").rstrip() + l[len(l.rstrip("\r\n")):] for l in t.splitlines(True))  # trailing-whitespace
bare = s.rstrip("\n")
sys.exit(0 if eof(s) == s and tw(s) == s and eof(bare) != bare else 1)
'
check "owner call B2 (fixer-proof): the guide's example record, written the way its record rules say, is left unchanged by an end-of-file check and a trailing-whitespace check; the same record without its final newline is not" \
  '[ -n "$JSON" ] && python3 -I -c "$PYB" "$BNL" "$BTS" "$JSON" 2>/dev/null'

# controls (the real guide only)
if [ -z "${1:-}" ]; then
  CLEAN='{"schema": 1, "items": {
  "terms_privacy": {"state": "skipped", "reason": "pages come next week", "date": "2026-10-24", "evidence": "http://localhost:3000/terms"},
  "security_audit": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""},
  "restore_test": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""},
  "load_test": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""},
  "live_payment": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""}}}'
  # the planted token is built at run time, so no token-shaped literal sits in the source (GitGuardian scans the repo)
  TOK="ghp""_$(printf 'a%.0s' {1..36})"
  PLANT="${CLEAN/http:\/\/localhost:3000\/terms/https://x/?token=$TOK}"
  check "(control) the test's secret check passes a clean record and flags a planted one (evidence https://x/?token=ghp_...), which still parses" \
    'printf "%s" "$CLEAN" | rec shape && printf "%s" "$CLEAN" | rec secrets && [ "$PLANT" != "$CLEAN" ] && printf "%s" "$PLANT" | rec shape && ! printf "%s" "$PLANT" | rec secrets'
  # mutation: delete the asked-again sentence(s) from a copy; the copy's run must print rule 4's FAIL
  again_gone() { local s out; cp "$G" "$TMPD/m.md"
    while IFS= read -r s; do [ -n "$s" ] || continue
      S="$s" perl -0pi -e 'my $r = join q(\s+), map { quotemeta } split q( ), $ENV{S}; s/$r//' "$TMPD/m.md"
    done <<< "$(sel "${AGAIN[@]}" | cut -d $'\x1f' -f1)"
    ! cmp -s "$G" "$TMPD/m.md" || return 1
    out="$(bash "$SELF" "$TMPD/m.md" || true)"; printf "%s\n" "$out" | gq -xF "FAIL $AGAIN_L"; }
  check "(control) deleting the asked-again sentence turns its check red" 'again_gone'
fi

# Task 2 control (no GUIDE argument): the brief's first no-file line, which promises a step /ship-it v1.3.0
# doesn't run, put in place of the template's no-file line(s) on a copy, must turn the no-file check red
if [ -z "${1:-}" ]; then
  nofile_gone() { local l out; cp "$R" "$TMPD/r.md"
    while IFS= read -r l; do [ -n "$l" ] || continue
      L="$l" perl -pi -e 's/^\Q$ENV{L}\E$/- Not started -- \/ship-it asks it before your first production deploy./' "$TMPD/r.md"
    done <<< "$(printf '%s\n' "$GLT" | grep -iE "$NOFILE" || true)"
    ! cmp -s "$R" "$TMPD/r.md" || return 1
    out="$(RESUME_IT="$TMPD/r.md" bash "$SELF" "$G" || true)"; printf '%s\n' "$out" | gq -xF "FAIL $NOFILE_L"; }
  check "(control) the brief's unqualified no-file line (\"/ship-it asks it before your first production deploy\") in place of the template's turns the no-file check red" 'nofile_gone'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
