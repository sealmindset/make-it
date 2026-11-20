#!/usr/bin/env bash
# E02-S60: the NeMo Guardrails files a build generates (guardrails/config.yml, five Colang rails, six test files) are
# TEST-TIME files. Nothing make-it generates loads the rails at run time: no scaffold file and no build prompt uses
# NeMo's runtime classes, and nemoguardrails is a dev dependency. The rails are used only when someone runs the app's
# guardrail tests or /nemo-it. Documents read by compliance and security reviewers presented NeMo as a control acting
# on live requests ("topic boundary enforcement", "hallucination detection", "present and wired").
# Contract these checks pin:
#   - Each rewritten compliance row is exactly the line below: it names the control that does act at run time, and says
#     NeMo Guardrails is "tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)".
#   - Every sentence, list item or table cell in any tracked Markdown file that names NeMo next to an enforcing word
#     (enforces, blocks, prevents, detects, filters, mitigates, protects, stops, intercepts, redacts), or that has rails
#     loaded, or requests sent through them, is one of the exact units listed below. A new one fails until a person
#     adds it to the list: the list is the review.
#   - "present and wired" is gone (outside release notes), with "unwired" and the old AI09 title. One definition
#     replaces it, in check AI09 and in the governance doc: the guardrail files exist and the config references every
#     rail. Each place that said "present and wired" holds that wording.
#   - The governance doc, the pentest doc and the two READMEs do not call the 5 adversarial inputs of the prompt Test
#     step a NeMo check.
# A tripwire, not a proof, and no rule is added per bypass. It cannot catch: a claim split across two sentences; a claim
# that names the rails by file ("topic_control.co keeps the model on topic"); another enforcing word ("guards",
# "screens", "keeps"); a claim in a file that is not Markdown; a true listed sentence moved somewhere it is false;
# anything under a version-history heading. It does not check the verdict words: those are the owner's.
# Not checked: .claude/commands/nemo-it.md keeps "present and wired" once, about the app's safety controls (not the
# rails), in a table this card may not edit; the references and Prompt #10e still name the Test step "mini NeMo".
# Usage: test-nemo-rails-not-runtime.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on its opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

REF=.claude/make-it/references
BS=$REF/build-standards.md; GR=$REF/guardrails.md; BVS=$REF/build-verify-security.md; SG=$REF/ship-it-guide.md
BP=$REF/design-blueprint.md; RF=.claude/commands/retrofit-it.md
GOV=docs/AI-GOVERNANCE-HOMEGROWN.md; PEN=docs/PENTEST-READINESS.md; MR=.claude/make-it/README.md
# every tracked Markdown file but the two logs of finished work; a ROOT given on the command line is a plain copy with
# no git, so its files are found
if [ -z "${1:-}" ]; then FILES="$(git ls-files '*.md')"; else FILES="$(find . -name '*.md' | sed 's|^[.]/||' | sort)"; fi
FILES="$(printf "%s\n" "$FILES" | grep -vE '(^|/)(CHANGELOG|TODO)[.]md$')"

# one line per file, whitespace flattened: a sentence that wraps still matches
flat() { tr '\n' ' ' | tr -s ' '; }
# has FILE SENTENCE: the flattened file holds the whole sentence
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# units FILE...: file<TAB>unit, a unit being one sentence, list item, table cell or line of a code block; sections under
# a version-history heading are dropped (release notes quote the old wording as history)
units() {
  local f
  for f in "$@"; do
    awk '/^##+ /{h = ($0 ~ /^##+ (v[0-9]|.*(Version History|Changelog))/)} h {next} /^[[:space:]]*```/{c = !c} c || /^[[:space:]]*([-*+] |[0-9]+[.] |#|```|$)/{print "<BR>"} {print}' "$f" | flat |
      perl -pe 's/<BR>|\|/\n/g; s/([.!?]["\x27)]?) (?=\S)/$1\n/g' | sed -E 's/^ +//; s/ +$//' | awk -v f="$f" 'NF {print f "\t" $0}'
  done
}
U="$(units $FILES)"
# pick REGEX: the units that match (case ignored), as file<TAB>unit
pick() { printf "%s\n" "$U" | { grep -iE -- "$1" || true; }; }
# unlisted LIST: the units of LIST (file<TAB>unit) that are not in the allow list
unlisted() { printf "%s\n" "$1" | awk -F'\t' 'NR == FNR {a[$0] = 1; next} NF && !(substr($0, length($1) + 2) in a)' "$TMPD/allow" -; }
# none NAME LIST: LIST is empty
none() { [ -z "$2" ] || { printf "%s\n" "$2" | cut -c1-240 | sed "s/^/  $1: /"; false; }; }

FORM="tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)"
DEF="the guardrail files exist and the config references every rail"

# 1. each rewritten compliance row, the whole line (file<TAB>line)
cat > "$TMPD/rows" <<'ROWS_EOF'
docs/AI-GOVERNANCE-HOMEGROWN.md	| AI-specific risks are mitigated | Input sanitization, output validation and prompt injection resistance at run time; AI behavior is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) |
docs/AI-GOVERNANCE-HOMEGROWN.md	| **MAP 2.3** | Scientific integrity | AI outputs validated against schemas and value ranges (validateAgentOutput). The system prompt tells the model never to fabricate data; hallucination is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) |
docs/AI-GOVERNANCE-HOMEGROWN.md	| **A.5** | AI system impact assessment | Design phase classifies project type and activates appropriate guardrails. AI apps get mandatory additional controls (rate limiting, prompt management) and a NeMo Guardrails test suite, run when someone runs it (not a runtime filter) |
docs/AI-GOVERNANCE-HOMEGROWN.md	| **AI04: Data Poisoning** | Prompt template blocklist validation; immutable safety preamble; draft/test/publish workflow; risk_flag audit logging. Topic boundaries are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | AI10 | Yes |
docs/AI-GOVERNANCE-HOMEGROWN.md	| **AI09: Misinformation** | AI output validation rejects contradictory structured fields (e.g., riskTier=LOW with riskScore=5); the system prompt tells the model never to fabricate data. Hallucination (test category 6) is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | AI03, AI09 | Partial |
docs/AI-GOVERNANCE-HOMEGROWN.md	| **NeMo Guardrails (a test suite, not a runtime filter)** | Prompt injection tests (10 of /nemo-it's own cases, when someone runs /nemo-it; none run by build-verify's checks) + jailbreak resistance tests | Automated test suite, run when someone runs it |
docs/AI-GOVERNANCE-HOMEGROWN.md	| **NeMo Guardrails (a test suite, not a runtime filter)** | Tests for hallucination, toxicity/bias and PII leakage (10 of /nemo-it's own cases per category; none run by build-verify's checks) | Automated test suite, run when someone runs it |
docs/AI-GOVERNANCE-HOMEGROWN.md	| **Draft/Test/Publish workflow** | New edits save as draft. Test runs: blocklist + sanitize + test cases + 5 adversarial inputs sent to the AI with the draft prompt (3 injection, 2 jailbreak). Prompt #10e names that last step "mini NeMo"; it specifies no use of the NeMo Guardrails rails. Publish only after all pass | Build-verify: confirm separate Test/Publish actions |
docs/AI-GOVERNANCE-HOMEGROWN.md	│ AI Safety         │ NeMo tests   │ Playwright    │ AI Red Team  │
docs/PENTEST-READINESS.md	| AI-specific analysis | NeMo Guardrails test suite, run when someone runs it (not a runtime filter) + 15 wiring checks of the AI safety controls | Agentic tool-use boundaries not tested (NeMo Agent Toolkit gap) |
docs/PENTEST-READINESS.md	| Prompt injection | sanitizePromptInput, delimiter tags, anti-injection system prompt instructions; tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | Low for direct, **Medium for indirect** |
docs/PENTEST-READINESS.md	| **Direct Prompt Injection** | sanitizePromptInput() strips known patterns; `<user_input>` delimiter tags; anti-injection system prompt instructions; tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | **COVERED** | Attacker sends "ignore instructions" -- blocked by sanitizer + delimiter tags |
docs/PENTEST-READINESS.md	| **Harmful Content Generation** | No scaffold file or prompt template has a runtime filter for toxic or biased output. The safety preamble in all prompts tells the model to answer only on the app's topic; validateAgentOutput() strips script and HTML from free text, and its specification (Prompt #10e, Part 2) has no check for harmful content. Toxicity and bias are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | **COVERED** (verdict under owner review, E02-S60) | Agent generates toxic or biased recommendations -- no runtime filter is specified for them; the test suite finds them only when someone runs it |
docs/PENTEST-READINESS.md	| **Competitor/Reputational Attacks** | Safety preamble with domain scope instructions (a model instruction, not a filter); topic boundaries are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | **PARTIAL** | Agent recommends competitor products -- the domain scope instruction reduces risk, but NeMo Toolkit showed 80% ASR for indirect variants |
docs/PENTEST-READINESS.md	| **Hallucination** (agent fabricating facts) | validateAgentOutput() checks structured output schema + value ranges; the system prompt tells the model never to fabricate data; hallucination is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | **PARTIAL** | Agent fabricates data in free-text responses -- validation catches structured outputs but free-text hallucination is harder to detect |
docs/PENTEST-READINESS.md	| Competitor referral: 80% success rate | /make-it puts a domain scope instruction in the safety preamble of every prompt; topic boundaries are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) | **PARTIAL** -- a model instruction, not a filter; adaptive attacks may bypass |
docs/PENTEST-READINESS.md	| Vulnerability assessment | **COVERED** | Semgrep, Bandit, dependency scanners; AI behavior is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter) |
ROWS_EOF
check "each rewritten compliance row is exactly the reviewed line (17 rows: the governance doc and the pentest doc)" \
  '[ "$(grep -c . "$TMPD/rows")" = 17 ] && ( while IFS="	" read -r f l; do gq -xF -- "$l" "$f" || { echo "  no such line in $f: $(printf "%s" "$l" | cut -c1-160)"; exit 1; }; done < "$TMPD/rows" )'
check "the one form is used, whole, in the governance doc (4 times) and the pentest doc (7 times)" \
  '[ "$(grep -oF -- "$FORM" "$GOV" | grep -c .)" = 4 ] && [ "$(grep -oF -- "$FORM" "$PEN" | grep -c .)" = 7 ]'
check "the governance doc says once, in section 5.5, that nothing generated loads the rails at run time" \
  'has "$GOV" "Nothing make-it generates loads the rails at run time. The rails and the tests are test-time files, used only when someone runs the app'"'"'s guardrail tests; the controls that act on live requests are in sections 5.1 to 5.4." && has "$GR" "- These are test-time files: nothing generated loads the rails at run time (not a runtime filter). They are there for the app'"'"'s guardrail tests" && has "$BP" "These are test-time files: nothing generated loads the rails at run time (not a runtime filter). The comments above say what each rail does when the app'"'"'s guardrail tests use it."'

# 2. "present and wired" has one definition, and each place that said it holds that wording
check "check AI09 is titled by what it checks, and defines \"wired\" once: the files exist and the config references every rail" \
  '[ "$(grep -cE "^[*][*]AI09[*][*] [[]AI[]] [[]FIX[]] [*][*]NeMo Guardrails files present and referenced [(]code-level[)][*][*] -- " "$BS")" = 1 ] && has "$BS" "Where a document says the guardrails are \"wired\", it means only this: $DEF. Nothing make-it generates loads the rails at run time (not a runtime filter)." && has "$GOV" "Where this document says the guardrails are \"wired\", or names the guardrail \"wiring\", it means only that: $DEF."'
check "each place that said \"present and wired\" says the files exist and the config references every rail" \
  'has "$GOV" "Check AI09 confirms in code that $DEF; that result is never a behavioral PASS." && has "$GOV" "check AI09 confirms in code that $DEF, and that result is never a behavioral PASS." && has "$SG" "check AI09 confirms in code that $DEF, and that result is never a behavioral PASS." && has "$BVS" "Part A'"'"'s check AI09 is code-level ($DEF)." && has "$GR" "It reads the files to confirm that $DEF, and that result is never a behavioral PASS" && has "$GR" "A guardrail file that is missing, or a rail the config does not reference, is put right like any other [FIX] check." && has "$RF" "check AI09 confirms in code that $DEF." && has README.md "check AI09 confirms in code that $DEF, never a behavioral PASS"'
# .claude/commands/nemo-it.md is left out: its one "present and wired" is about the app's safety controls, not the rails
WIRED="$(pick "	.*(present and wired|\bunwired\b|NeMo Guardrails wiring [(]code-level[)])" | { grep -vE "^[.]claude/commands/nemo-it[.]md	" || true; })"
check "no file says \"present and wired\", \"unwired\" or the old AI09 title (release notes apart)" 'none "old wording" "$WIRED"'

# 3. a unit that names NeMo next to an enforcing word, or has rails loaded or requests sent through them, is one of
#    these exact units
cat > "$TMPD/allow" <<'ALLOW_EOF'
**NeMo Guardrails (a test suite, not a runtime filter)**
- MANDATORY for all apps with ai_features.needed = true -- these are runtime protections that complement the NeMo Guardrails test-time checks above
- These are test-time files: nothing generated loads the rails at run time (not a runtime filter).
/make-it puts a domain scope instruction in the safety preamble of every prompt; topic boundaries are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
AI apps get mandatory additional controls (rate limiting, prompt management) and a NeMo Guardrails test suite, run when someone runs it (not a runtime filter)
Hallucination (test category 6) is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
Input sanitization, output validation and prompt injection resistance at run time; AI behavior is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
NeMo Guardrails test suite, run when someone runs it (not a runtime filter) + 15 wiring checks of the AI safety controls
NeMo Guardrails: 6 test categories, 60 or more cases that /nemo-it writes itself and runs when someone runs /nemo-it with a live AI provider: recommended before each production deploy, and nothing in make-it enforces it.
Nothing make-it generates loads the rails at run time (not a runtime filter).
Nothing make-it generates loads the rails at run time.
Safety preamble with domain scope instructions (a model instruction, not a filter); topic boundaries are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
Semgrep, Bandit, dependency scanners; AI behavior is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
The system prompt tells the model never to fabricate data; hallucination is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
These are test-time files: nothing generated loads the rails at run time (not a runtime filter).
This section implements runtime protections that prevent the issues NeMo tests for from ever reaching production.
Topic boundaries are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
Toxicity and bias are tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
sanitizePromptInput() strips known patterns; `<user_input>` delimiter tags; anti-injection system prompt instructions; tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
sanitizePromptInput, delimiter tags, anti-injection system prompt instructions; tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
validateAgentOutput() checks structured output schema + value ranges; the system prompt tells the model never to fabricate data; hallucination is tested by the NeMo Guardrails suite when someone runs it (not a runtime filter)
ALLOW_EOF
# The NeMo Agent Toolkit is another product (a red-team tool the pentest doc maps to): its names are taken out before
# the match. "NeMo" is matched with its capitals, so "/nemo-it" alone is not a hit; the enforcing words are matched in
# any case. "block" and "detected" are left out on purpose ("in its own block", "if AI features are detected").
ENF='enforc(e|es|ed|ing|ement)|\bblock(s|ed|ing)\b|prevent|\bdetect(s|ing|ion)?\b|filter|mitigat|protect|\bstops\b|intercept|redact'
NE="$(unlisted "$(printf "%s\n" "$U" | sed -E 's/NeMo (Agent )?Toolkit(-style)?|NeMo Agent|NeMo Attack Vector//g' | { grep -E "	.*NeMo" || true; } | { grep -iE "	.*($ENF)" || true; })")"
check "every unit that names NeMo next to an enforcing word is a listed, reviewed sentence" 'none "not listed" "$NE"'
RT="$(unlisted "$(pick "	.*(loads? the rails|(rails|guardrails) (are|is) loaded|through the (rails|guardrails|NeMo)|run-?time (rails?|guardrails?)\b|\brails? (act|run|fire|apply|applies) (at run|on (every|each|live))|rails (on|for|to) (every|each|all|live) (request|message|response))")")"
check "every unit that has the rails loaded, or requests sent through them, is a listed, reviewed sentence" 'none "not listed" "$RT"'
check "the list has no dead entry: each listed unit is in a file" \
  'D="$(printf "%s\n" "$U" | cut -f2- | awk "NR == FNR {a[\$0] = 1; next} !(\$0 in a)" - "$TMPD/allow")"; none "dead" "$D"'

# 4. the prompt Test step's 5 adversarial inputs are not called a NeMo check in the documents reviewers read
MINI="$(pick "	.*(mini NeMo (Guardrails )?(safety )?check|adversarial NeMo)" | { grep -E "^(docs/|README[.]md	|[.]claude/make-it/README[.]md	)" || true; })"
check "the governance doc, the pentest doc and the two READMEs do not call the Test step's 5 adversarial inputs a NeMo check" \
  'none "old wording" "$MINI" && has "$GOV" "Prompt #10e names that last step \"mini NeMo\"; it specifies no use of the NeMo Guardrails rails." && has README.md "5 adversarial inputs sent to the AI with the draft prompt (3 injection + 2 jailbreak; Prompt #10e names this step \"mini NeMo\", and it specifies no use of the NeMo Guardrails rails)" && has README.md "that sends 5 adversarial inputs to the AI with every draft prompt before it can go live (it specifies no use of the NeMo Guardrails rails)." && has "$MR" "(Prompt #10e names this step \"mini NeMo\"; it specifies no use of the NeMo Guardrails rails)"'

# 5. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the Markdown files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  # add FILE AFTER LINE: the same, with LINE added after the first line that starts with AFTER
  add() { A="$2" L="$3" opp "$1" 's/^(\Q$ENV{A}\E[^\n]*\n)/$1$ENV{L}\n/m'; }
  check "(control) fails with \"NeMo Guardrails topic boundary enforcement\" back in the AI04 row" \
    'opp "$GOV" "s/risk_flag audit logging[.] Topic boundaries are tested by the NeMo Guardrails suite when someone runs it [(]not a runtime filter[)]/risk_flag audit logging; NeMo Guardrails topic boundary enforcement/"'
  check "(control) fails when a pentest row's control text is put back and its verdict kept (Hallucination, PARTIAL)" \
    'opp "$PEN" "s/validateAgentOutput[(][)] checks structured output schema [+] value ranges; the system prompt tells the model never to fabricate data; hallucination is tested by the NeMo Guardrails suite when someone runs it [(]not a runtime filter[)] [|] [*][*]PARTIAL/NeMo Guardrails hallucination detection; validateAgentOutput() checks structured output schema + value ranges | **PARTIAL/"'
  check "(control) fails when the runtime control named in a row is swapped for NeMo (the competitor rows)" \
    'opp "$PEN" "s/\/make-it puts a domain scope instruction in the safety preamble of every prompt;/\/make-it puts NeMo Guardrails rails in front of every prompt;/" && opp "$PEN" "s/Safety preamble with domain scope instructions [(]a model instruction, not a filter[)];/NeMo Guardrails rails keep the model on topic;/"'
  check "(control) fails with NeMo as a runtime enforcer in a sentence nobody listed: blocks (the pentest doc), enforces (DEVOPS-GUIDE.md), mitigates with a hyphen after NeMo (CLAUDE.md)" \
    'add "$PEN" "### 5.1 Attack Vector Mapping" "NeMo Guardrails blocks prompt injections at run time, before the model sees them." && add docs/DEVOPS-GUIDE.md "# " "NeMo Guardrails enforces topic boundaries in every generated app." && add CLAUDE.md "- The user NEVER needs" "- AI risks are mitigated at run time by the NeMo-Guardrails rails"'
  check "(control) fails with the rails loaded at run time, said with no enforcing word (the governance doc, README.md)" \
    'add "$GOV" "### 5.5 NeMo Guardrails Test Categories" "The app loads the rails on every request." && add README.md "# " "Each live message is sent through the guardrails before the model answers."'
  check "(control) fails with \"present and wired\" back in one reference, with \"unwired\" back, and with the old AI09 title" \
    'opp "$SG" "s/the guardrail files exist and the config references every rail/the guardrails are present and wired/" && opp "$GR" "s/A guardrail file that is missing, or a rail the config does not reference,/A missing or unwired guardrails file/" && opp "$BS" "s/NeMo Guardrails files present and referenced [(]code-level[)]/NeMo Guardrails wiring (code-level)/"'
  check "(control) fails with the definition changed to runtime wiring (check AI09, the governance doc)" \
    'opp "$BS" "s/it means only this: the guardrail files exist and the config references every rail/it means only this: the app routes requests through the rails/" && opp "$GOV" "s/it means only that: the guardrail files exist and the config references every rail/it means only that: the app sends each request through the rails/"'
  check "(control) fails with \"not a runtime filter\" dropped from one row, with \"Nothing generated loads the rails\" reversed, and with the mini NeMo check back" \
    'opp "$GOV" "s/hallucination is tested by the NeMo Guardrails suite when someone runs it [(]not a runtime filter[)]/hallucination is tested by the NeMo Guardrails suite/" && opp "$GOV" "s/Nothing make-it generates loads the rails at run time[.]/Every generated app loads the rails at run time./" && opp "$GOV" "s/[+] 5 adversarial inputs sent to the AI with the draft prompt [(]3 injection, 2 jailbreak[)][.]/+ mini NeMo check./"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
