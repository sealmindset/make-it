#!/usr/bin/env bash
# E02-S21 (the owner's Split, 2026-10-21): ship-it-guide.md describes as /ship-it steps only what ship-it's SKILL.md runs,
# plus the safety steps it keeps for /ship-it, said once to be not run yet (card E02-S39 adds them).
# Contract these checks pin:
#   - The guide names each kept safety step: the secret leak scan before every push, /ship-it save included; the switch off
#     the builder's personal Claude token on a shareable or prod-ready ship; the billing ask; the left-out rules (the
#     production ask with a pick per item, auto-fixes that never put a left-out item back or report it as FAIL, the
#     left-out secret stop on every push, the left-out lines in the go-live checklist).
#   - One statement, once, says /ship-it doesn't run them yet and that card E02-S39 adds them.
#   - The dropped steps are no /ship-it steps: the NeMo run, the prompt-safety flag, the attestation and its PR summary,
#     the pre-push lint / env-var / migration / import / build checks, the CI watch, its auto-fix loop and its messages.
#     They are named only in "What make-it runs before /ship-it", which gives them to build-verify and /nemo-it, or says
#     no skill does them (never /ship-it, never a skill that doesn't exist).
# Usage: test-ship-it-guide.sh [GUIDE]. With no GUIDE it checks the real guide, then proves the checks fail on its opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT
flat() { tr '\n' ' ' | tr -s ' '; }
paras() { awk 'BEGIN{RS="";ORS="\n"} {gsub(/\n/," "); print}' | tr -s ' '; }
sents() { paras | perl -pe 's/([.!?]["\x27]?) (?=\S)/$1\n/g'; }

G="${1:-.claude/make-it/references/ship-it-guide.md}"
# a section: from its heading line to the next heading of any level
sec() { awk -v h="$1" '/^#/{on=(index($0,h)==1)} on' "$G"; }
MAKEIT_H='### What make-it runs before /ship-it'
MAKEIT="$(sec "$MAKEIT_H")"
NOTMAKEIT="$(awk -v h="$MAKEIT_H" '/^#/{off=(index($0,h)==1)} !off' "$G")"
LEFT="$(sec '### Left-out items before production' | flat)"

# 1. each kept safety step is named
SCAN="$(awk '/^#/{on=($0 ~ /^### .*[Ss]ecret leak scan/)} on' "$G")"
check "kept: the secret leak scan has its own section, before every push, /ship-it save included, stopping on a found secret (the personal Claude token among them)" \
  'printf "%s\n" "$SCAN" | head -1 | gq -iE "before every push, /ship-it save included" && printf "%s\n" "$SCAN" | gq -F "CLAUDE_CODE_OAUTH_TOKEN" && printf "%s\n" "$SCAN" | flat | gq -E "When it finds one, it STOPS"'
check "kept: a shareable or prod-ready ship moves off the builder's personal Claude token (claude_agent) only through the pick" \
  'flat < "$G" | gq -E "\`intent:shareable\` and \`intent:prod-ready\` move off claude_agent only through that pick"'
check "kept: the billing ask has its section, with a pick by name" \
  'sec "### The billing ask" | gq -F "Pick one by name"'
check "kept: the left-out rules -- the production ask with a pick per item, the auto-fix rule, the secret stop on every push, the go-live lines" \
  'printf "%s" "$LEFT" | gq -F "Each item gets its own pick" && printf "%s" "$LEFT" | gq -F "never put a left-out item back, and never report one of its checks as FAIL" && printf "%s" "$LEFT" | gq -E "on every push, whatever the intent, /ship-it save included.*stops before the push and sends nothing" && printf "%s" "$LEFT" | gq -F "records each \"Ship with [item] left out\" pick in the PR'"'"'s go-live checklist"'

# 2. one plain statement, once: /ship-it doesn't run them yet, and card E02-S39 adds them
NOTYET='\b(doesn.t|does not) run\b[^.]{0,40}\byet\b'
STMT="$(paras < "$G" | grep -F E02-S39 || true)"
STMTSEC="$(awk '/^#/{on=0} /^#/ && /\/ship-it doesn.t run yet/{on=1} on' "$G" | flat)"
check "stated once: one paragraph names card E02-S39 and says /ship-it doesn't run these yet (its SKILL.md has none of them)" \
  '[ "$(grep -o E02-S39 "$G" | wc -l | tr -d " ")" = 1 ] && printf "%s\n" "$STMT" | gq -iE "^/ship-it $NOTYET" && printf "%s\n" "$STMT" | gq -F "SKILL.md" && [ "$(sents < "$G" | grep -v "^#" | grep -ciE "$NOTYET")" = 1 ] && ! sents < "$G" | gq -iE "/ship-it (already|now) runs?\b"'
check "the statement lists each kept step, pointing at its section" \
  '( for p in "**The secret leak scan before every push**" "(Pre-push secret leak scan" "personal Claude token" "(AI Provider on Ship)" "**The billing ask**" "(The billing ask" "**The left-out rules** (Left-out items before production)"; do printf "%s" "$STMTSEC" | gq -F "$p" || exit 1; done )'

# 3. the dropped steps are no /ship-it steps: outside the make-it section the guide never names them
DROPPED='\bNeMo\b|attestation|risk_flag|prompt_audit_log|Prompt Safety Review|\bruff\b|flake8|eslint|\btsc\b|ast\.parse|docker compose build|env var cross-check|migration (alignment|chain)|Pre-Push Self-Review|Post-Push CI Monitoring|\bwatch(es)? (the )?CI\b|poll every|auto-fix cycles|CI is still running|being checked now|ready for review!'
check "dropped: outside \"What make-it runs before /ship-it\", the guide never names the NeMo run, the prompt-safety flag, the attestation, the pre-push lint / env / migration / import / build checks, or the CI watch and its messages" \
  '! printf "%s\n" "$NOTMAKEIT" | gq -iE "$DROPPED"'
check "dropped: /ship-it's numbered steps are the 8 that ship-it's SKILL.md runs, ending in its done message" \
  's=$(awk "/^\*\*Behind the scenes, \/ship-it:\*\*/{on=1;next} on&&/^$/{exit} on" "$G" | grep -E "^[0-9]+\. "); [ "$(printf "%s\n" "$s" | wc -l | tr -d " ")" = 8 ] && printf "%s\n" "$s" | gq -E "^8\. Reports back:"'

# 4. the make-it section gives each dropped step to build-verify or /nemo-it, or says no skill does it; never to /ship-it
check "make-it section: build-verify runs the NeMo basic suite; the attestation GRC asks for before production comes from /nemo-it" \
  'printf "%s\n" "$MAKEIT" | sents | grep -F build-verify | gq -F "NeMo Guardrails basic suite" && printf "%s\n" "$MAKEIT" | sents | grep -F attestation | grep -F /nemo-it | gq -iE "\bbefore production\b"'
check "make-it section: says so where no skill does it (the attestation summary in the PR, the risk_flag prompt edits at ship)" \
  'printf "%s\n" "$MAKEIT" | sents | gq -E "^No skill puts an attestation summary in the PR\.$" && printf "%s\n" "$MAKEIT" | sents | grep -F risk_flag | gq -E "\bno skill flags them\b"'
check "make-it section: /ship-it runs none of it, and every other skill it names is one of make-it's (none invented)" \
  'printf "%s\n" "$MAKEIT" | flat | gq -F "so /ship-it doesn'"'"'t repeat them" && ! printf "%s\n" "$MAKEIT" | sents | gq -E "/ship-it (runs|generates|writes|watches|flags|checks|fixes)\b" && k=$(printf "%s\n" "$MAKEIT" | grep -oE "/[a-z]+-it\b" | sort -u | grep -vxF /ship-it) && ( for x in $k; do [ -f ".claude/commands$x.md" ] || exit 1; done )'

# 5. controls (the real guide only): each plain opposite fails the checks above
if [ -z "${1:-}" ]; then
  opp() { cp "$G" "$TMPD/g.md"; perl -0pi -e "$1" "$TMPD/g.md"; ! cmp -s "$G" "$TMPD/g.md" && ! bash "$SELF" "$TMPD/g.md" >/dev/null 2>&1; }
  check "(control) fails with the statement gone (the guide silently untrue)" \
    'opp "s/\/ship-it doesn.t run these safety steps yet:[^\n]*\n[^\n]*\n//"'
  check "(control) fails with the statement turned round (\"/ship-it already runs these safety steps\")" \
    'opp "s/\/ship-it doesn.t run these safety steps yet/\/ship-it already runs these safety steps/"'
  check "(control) fails with a dropped step back as a /ship-it step (the NeMo run)" \
    'opp "s/^5\. Creates a branch/5. **Runs NeMo Guardrails full test suite** (if AI features exist)\n6. Creates a branch/m"'
  check "(control) fails with a kept step gone (the secret leak scan section)" \
    'opp "s/### Pre-push secret leak scan.*?(?=### What make-it)//s"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
