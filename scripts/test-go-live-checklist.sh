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
check "rule 1 (trigger): a production workflow is a job on deployment.environments.production (default production), a deploy-prod job, a reusable caller's environment-prod, or none yet (every one ship-it generates deploys to production on merge)" \
  'says "deployment\.environments\.production" "+default[^.]{0,5}production" && says "+deploy-prod" && says "+environment-prod" && says "no workflow" "+generat" "+deploys? to production on merge"'
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

# controls (the real guide only)
if [ -z "${1:-}" ]; then
  CLEAN='{"schema": 1, "items": {
  "terms_privacy": {"state": "skipped", "reason": "pages come next week", "date": "2026-10-24", "evidence": "http://localhost:3000/terms"},
  "security_audit": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""},
  "restore_test": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""},
  "load_test": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""},
  "live_payment": {"state": "skipped", "reason": "coming soon", "date": "2026-10-24", "evidence": ""}}}'
  PLANT="${CLEAN/http:\/\/localhost:3000\/terms/https://x/?token=ghp_abcdefghijklmnopqrstuvwxyz0123456789}"
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

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
