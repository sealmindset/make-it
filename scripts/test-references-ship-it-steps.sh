#!/usr/bin/env bash
# E02-S41 (the owner's Split, E02-S21, shipped in v1.44.18): make-it's references never say /ship-it runs a step it doesn't.
# ship-it-guide.md gives the NeMo full run, the AI-safety attestation and the risk_flag PR flag to what make-it runs before
# /ship-it (build-verify, /nemo-it and /fix-it, or no skill) in "What make-it runs before /ship-it", and keeps the steps
# /ship-it will run later in "Safety steps /ship-it doesn't run yet". Every other reference points there.
# Contract these checks pin:
#   - Sentence by sentence, no tracked file under .claude/ or scripts/ but the guide names /ship-it AND one of those steps
#     (a NeMo or full-suite run, a run against the AI models, the attestation, risk_flag) as something /ship-it does:
#     /ship-it as the actor ("/ship-it runs ...", a table row whose first cell is /ship-it), as the time ("during /ship-it",
#     "each /ship-it run", "at ship", "ship-time"), or its PR holding it ("the /ship-it PR description includes ...").
#   - Meaning crosses line breaks: a list item reads with its lead-in ("When the user types /ship-it, the pipeline: 4. Runs
#     NeMo ..."), and on a page whose title names /ship-it, "it" is /ship-it.
#   - A pointer is no claim: "before /ship-it", the guide's two section names and a "no skill ..." clause are dropped first,
#     so "/nemo-it runs the full suite before /ship-it" passes.
#   - Version history is history: a section headed "Version History", "Changelog" or "vN..." is skipped.
#   - Each pointer at the guide's sections (ship-it-guide.md, "<section>") names a section the guide has.
# The sibling claims (a reference claims a step that doesn't happen), checked the same way:
#   - /ship-it (ship-it's SKILL.md v1.3.0, the guide's "What /ship-it Does") greps for no dotenv override, checks no
#     ics_ot_integration and asks for no OT sign-off, and runs no DAST: no reference says it does. A table row that names
#     /ship-it in a cell and one of the steps claims it; so does "add ... to /ship-it", "at deploy time", "the PR with ...",
#     and a sequence-diagram arrow from a /ship-it participant ("SI->>SI: NeMo ..." reads as "/ship-it runs NeMo ...").
#   - The fallback AI model (E02-S45): /nemo-it's AI-safety phase runs each configured model (step 0b) and reports per
#     model; no other skill does. No sentence gives that run to another skill (a MUST, or a "neither ..." / "not run"
#     sentence, is no such claim). guardrails.md points at /nemo-it with no gap note, and nemo-it.md's step keeps its
#     limits: only an app this scan started is restarted, no project file changes, a model not run is NOT TESTED.
#   - The AI-safety attestation: only /nemo-it writes one. No sentence says one is generated without naming /nemo-it (or
#     /fix-it, which re-scans with it), but the CI quality-gate's "attestation artifact". nemo-it.md and fix-it.md are its
#     own pages.
#   - The attestation_mode setting is gone (E02-S44: no skill read it): no file names it, and none names a file nothing
#     writes (docs/ai-safety-attestation.md, a dated file outside docs/attestations/nemo-it/).
#   - /nemo-it reports and never fixes (E02-S46): a sentence that names /nemo-it and a self-healing loop says the loop is
#     the build's. A tripwire, not a proof: it reads one sentence at a time and needs the word "self-healing", so the two
#     places where the loop is the next bullet after /nemo-it (guardrails.md, README.md) are pinned by name.
#   - TODO.md is a log of finished work and is not scanned for the gone setting.
#   - No card id (E01-S1 style) in any file the installer ships (.claude/), but under a Version History heading and in the
#     /backlog-it skill's own files (its command, bin/, backlog-board.md, its Confluence page), whose ids are made-up
#     examples of the id format. The board is private, so a real card id there points at nothing the reader can open.
# Scanned: the tracked files under .claude/ and scripts/, the root README.md and docs/. The test scripts are not scanned:
# they quote the opposites as controls.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

GUIDE=.claude/make-it/references/ship-it-guide.md

# file:line<TAB>sentence. A unit is a run of lines; a blank line, list item, table row, heading or code fence starts a new
# one. Units split into sentences after . ! or ? (never after a list number). A list item's first sentence carries its
# lead-in (the unit before the list, ending in ":"). On a page whose title names /ship-it, "it" is /ship-it. A table row is one
# sentence. A sequence-diagram arrow is its own unit and reads as its sender doing the message ("SI->>GH: X" with
# "participant SI as /ship-it" is "/ship-it runs X").
IFS= read -r -d '' SPLIT <<'PERL' || true
for my $f (@ARGV) {
  open my $fh, "<", $f or die "$f: $!\n";
  my ($t, @map, @units, %as) = ("");
  my $flush = sub { push @units, [$t, [@map]] if $t =~ /\S/; $t = ""; @map = (); };
  while (my $l = <$fh>) {
    chomp $l;
    if ($l !~ /\S/) { $flush->(); next }
    $as{$1} = $2 if $l =~ /^\s*participant\s+(\w+)\s+as\s+(.+?)\s*$/;
    $flush->() if $l =~ /^\s*(?:[-*+] |\d+\. |\||#|```|participant |Note |\w+\s*-+>>?[+-]?\s*\w+\s*:)/;
    $l =~ s/^\s+//;
    if ($l =~ /^```/) { $t = $l; push @map, [0, $.]; $flush->(); next }
    $l =~ s/^(\w+)\s*-+>>?[+-]?\s*\w+\s*:\s*/($as{$1} \/\/ $1) . " runs "/e;
    $t .= " " if length $t;
    push @map, [length $t, $.];
    $t .= $l;
  }
  $flush->();
  my ($title) = map { $_->[0] } grep { $_->[0] =~ /^# / } @units;
  my $subj = defined $title && $title =~ m{/ship-it\b};
  my $lead = "";
  for my $u (@units) {
    my ($s, $m) = @$u;
    my $item = $s =~ /^(?:[-*+] |\d+\. )/;
    $lead = "" unless $item;
    my $cut = $s;
    $cut =~ s/(?<!^\d)(?<!^\d\d)([.!?]["')\x27]?) (?=\S)/$1\n/g unless $s =~ /^\|/;
    my ($off, $first) = (0, 1);
    for my $x (split /\n/, $cut) {
      my $n = $m->[0][1]; $_->[0] <= $off and $n = $_->[1] for @$m;
      my $o = ($item && $first && $lead ne "" ? "$lead " : "") . $x;
      $o =~ s{(?<![\w/-])[Ii]t\b(?!-)}{/ship-it}g if $subj;
      print "$f:$n\t$o\n";
      $off += length($x) + 1; $first = 0;
    }
    $lead = $s if !$item && $s =~ /:\**$/;
  }
}
PERL
sents() { perl -e "$SPLIT" "$@"; }
# drop the sentences under a version-history heading
nohist() { awk -F'\t' '{split($1, a, ":")} a[1] != f {f = a[1]; h = 0} $2 ~ /^#/ {h = ($2 ~ /^##+ (v[0-9]|.*(Version History|Changelog))/)} !h'; }
# drop the pointers: they name /ship-it only to say what runs before it, or what it doesn't run yet
POINTER='What make-it runs before /ship-it|Safety steps /ship-it doesn.t run yet|What /ship-it Does|\b[Bb]efore `?/ship-it\b|\b(not|no) `?/ship-it\b|\b[Nn]o skill\b[^.;:]*'
T=$'\t'
VERBS='(re-?)?runs?|checks?|flags?|includes?|creates?|generates?|writes?|overwrites?|produces?|adds?|puts?|scans?|tests?|greps?|requires?|attaches|carries|holds|emits?|exercises?'
ADV='( +(also|then|now|still|always|again|automatically))?'
AP="('|\xe2\x80\x99)"
DOES="/ship-it\`?$ADV +($VERBS)\b|\b(during|each|every|on|by|in|at|from) \`?/ship-it\b|/ship-it\`?(${AP}s)? +(PR|pull request|run)\b|/ship-it\b[^:]*:\**[[:space:]]+([0-9]+\.|[-*+])[[:space:]].*\b($VERBS)\b|\bship-time\b|\bship time\b|\bat ship\b|\bduring ship\b|\badd[a-z]*\b[^.|]{0,20} to \`?/ship-it\b|\bat deploy( time)?\b|\bPR (with|includes?)\b"
# a table row that names /ship-it in any cell (the row is one sentence: its cells are who, when and what)
ROW="$T\\|.*/ship-it\\b"
STEP='\bNeMo([^-]|$)|\bPlaywright\b|full (test )?suite|test suite|test cases|attestation|risk[-_ ]flag|AI[- ]safety test|Prompt Safety Review|\bruns? against\b|\bDAST\b|OWASP ZAP|override=True|override: true|\bdotenv\b|ics_ot|\bOT security\b|sign-off'
# claims FILE...: each sentence that names /ship-it and one of the steps as something /ship-it does, as file:line<TAB>text
claims() { sents "$@" | nohist | perl -pe "s#$POINTER##g" | { grep -iE -e "$T.*($DOES)" -e "$ROW" || true; } | { grep -iE "$T.*($STEP)" || true; }; }
# fallback FILE...: each sentence that says a skill runs the NeMo tests against the fallback (or every) AI model
FB='fallback models?[^.|]*\b(safety-)?test(s|ed|ing)?\b|\b(runs?|tests?|tested|testing|exercis(es|ed|ing)|covers?)\b[^.|]*\b(all configured|both( the)? primary|the fallback) models?\b|\bruns? against (all|both)\b|fallback model[^.]*build-verify|build-verify[^.]*fallback model'
FBOK='\bMUST\b|\bneither\b|\bnone today\b|\bno skill\b|\bnot (run|tested)\b'
# /nemo-it is the one skill that runs it (its AI-safety phase, step 0b): a sentence that names /nemo-it and no other skill passes.
# A tripwire: it does not judge what such a sentence says about /nemo-it; step 0b's own limits are pinned below.
FBOTHER='build-verify|/ship-it|/make-it|/try-it|/resume-it'
fallback() { sents "$@" | nohist | { grep -iE "$T.*($FB)" || true; } | { grep -viE "$T.*($FBOK)" || true; } | awk -F'\t' -v o="$FBOTHER" 'BEGIN{IGNORECASE=1} { l=tolower($2) } l !~ /nemo-it/ || l ~ o'; }
# unattested FILE...: each sentence that says an AI-safety attestation is generated without naming /nemo-it
GEN='\b(generates?|generated|generating|generate|creates?|produces?|writes?|emits?|saves?)\b[^.|]{0,40}\battestation\b|\battestation\b( [A-Za-z/`.-]+){0,3} (is |was |are )?(generated|auto-generated|created|produced|written)\b|\battestation\b[^|]*\|[^|]*\bauto-generated\b'
GENOK='nemo-it|fix-it|quality'
unattested() { sents "$@" | nohist | { grep -iE "$T.*($GEN)" || true; } | { grep -viE "$T.*($GENOK)" || true; }; }

FILES="$(git grep -lIiE -e 'ship|attestation|fallback' -- .claude scripts README.md docs | grep -vxF "$GUIDE" | grep -vE '^scripts/test-[^/]*\.sh$')"
# /nemo-it and /fix-it write and re-scan the attestation
DFILES="$(printf "%s\n" $FILES | grep -vxE '\.claude/commands/(nemo|fix)-it\.md')"

# 1. no reference names a /ship-it step it doesn't run
CLAIMS="$(claims $FILES)"
check "no reference outside ship-it-guide.md names the NeMo full run, the attestation, the risk_flag PR flag, the dotenv grep, the OT sign-off or DAST as a /ship-it step" \
  '[ -z "$CLAIMS" ] || { printf "%s\n" "$CLAIMS" | cut -c1-220 | sed "s/^/  claim: /"; false; }'
FALLBACK="$(fallback $FILES)"
check "no reference says a skill other than /nemo-it runs the NeMo tests against the fallback (or every) AI model" \
  '[ -z "$FALLBACK" ] || { printf "%s\n" "$FALLBACK" | cut -c1-220 | sed "s/^/  claim: /"; false; }'
FBSEC="$(awk '/^#/{on=($0 ~ /^#### AI Fallback Model Safety/)} on' .claude/make-it/references/guardrails.md | tr '\n' ' ' | tr -s ' ')"
check "guardrails.md keeps the fallback MUST and points at /nemo-it: each configured model, a model not run is NOT TESTED and never passed, no gap note left" \
  'printf "%s" "$FBSEC" | gq -F "MUST run against BOTH" && printf "%s" "$FBSEC" | gq -F "/nemo-it runs the suite against each configured model" && printf "%s" "$FBSEC" | gq -F "NOT TESTED, never passed" && ! printf "%s" "$FBSEC" | gq -iE "known gap|not met yet|neither build-verify nor" && ! printf "%s" "$FBSEC" | gq -E "\bE[0-9]{2}-S[0-9]+\b"'
# /nemo-it's own page: the step that runs each model, and its limits
NM=.claude/commands/nemo-it.md
N0B="$(awk '/^\*\*0b\. Which model each run tests/{on=1; next} on && /^\*\*1\. Configure NeMo Guardrails/{on=0} on' "$NM" | tr '\n' ' ' | tr -s ' ')"
has() { printf "%s" "$N0B" | gq -F -- "$1"; }
sen() { has "$1" || { echo "  missing in step 0b: $1"; false; }; }
no0b() { ! printf "%s" "$N0B" | gq -iE -- "$1" || { echo "  must not be in step 0b: $1"; false; }; }
check "nemo-it.md step 0b: reports per model, and reads names from app-context.json and only counts from .env and the compose file" \
  'sen "one result block per model" && grep -E "AI_FAILOVER_PROVIDER" "$NM" | grep -E "grep " | gq -E "grep -cE" && ! grep -E "grep [^|]*\.env" "$NM" | grep -E "AI_" | gq -vE "grep -(c|o)"'
check "nemo-it.md step 0b: the second run needs all five conditions, each written whole" \
  'sen "only when all of these hold" && sen "this scan started the app itself in preflight step 7, with Docker Compose" && sen "An app that was already running is never stopped or restarted" && sen "\`PASSIVE_ONLY=false\`, and the production check was not passed with \"Go ahead\"" && sen "the hostile-code check found nothing" && no0b "already running on this computer|ask first"'
check "nemo-it.md step 0b: it stops one service, removes nothing, changes no project file and prints no settings" \
  'sen "\`docker compose stop <service>\`, never the whole project" && sen "No file in the project is changed: never \`.env\`, never a compose file" && no0b "compose down|[[:space:]]-v[[:space:]]|--volumes|compose config|[ \`]env[ \`]|printenv[^ ]|printenv [^A]|\bps e|/proc/|pkill|\bkill " && sen "every compose file \`START_COMMAND\` uses"'
check "nemo-it.md step 0b: the fallback counts only with the app's own evidence, and anything else is NOT TESTED, never a PASS" \
  'sen "shows only that the setting reached the container" && sen "It also needs the app'"'"'s own evidence" && sen "Without both, the fallback is NOT TESTED" && sen "Go straight to step 5" && sen "I could not confirm the app was answering from the fallback" && sen "NOT TESTED, never a PASS" && sen "I can only restart a Docker Compose app safely" && sen "I did not start this app, so I did not restart it" && no0b "record the run anyway|that is enough"'
check "nemo-it.md step 0b: the app is always put back, whatever happened" \
  'sen "Always, whatever happened in steps 2 to 4, put the app back" && no0b "only if the person asks|leave it on the fallback"'
check "nemo-it.md: the start ask itself says the two restarts, and the report tables no longer say no skill runs it" \
  'grep -F "**Starting your app.**" "$NM" | gq -F "restart the app twice during the scan" && ! gq -iE "None today: neither build-verify nor /nemo-it" "$NM" && gq -F "one table per model tested" "$NM"'

# the attestation_mode setting is gone, and so are the files only it named
gone() { sents "$@" | nohist | { grep -iE "$T.*(attestation_mode|attestation mode|ai-safety-attestation\.md|docs/attestations/YYYY)" || true; }; }
GFILES="$( { git grep -lIiE -e 'attestation_mode|attestation mode|ai-safety-attestation\.md|docs/attestations/YYYY' -- . ':!CONTENT_MANIFEST' ':!TODO.md' || true; } | grep -vE '^scripts/test-[^/]*\.sh$' || true)"
GONE="$(gone $GFILES)"
check "no file names the attestation_mode setting (no skill read it) or an attestation file nothing writes: /nemo-it writes docs/attestations/nemo-it/YYYY-MM-DD-vN.md" \
  '[ -z "$GONE" ] || { printf "%s\n" "$GONE" | cut -c1-220 | sed "s/^/  named: /"; false; }'
# /nemo-it reports and never fixes: a self-healing loop named beside it is given to the build
# "differences from standalone /nemo-it" is build-verify-security.md saying the loop is what /nemo-it lacks
BUILDS='(at build|build-verify)[^|.]{0,80}self-healing|self-healing[^|.]{0,80}(at build|build-verify)|differences from standalone /nemo-it'
healer() { sents "$@" | nohist | { grep -iE "$T.*nemo-it" || true; } | { grep -iE "$T.*self[- ]healing" || true; } | { grep -viE "$T.*($BUILDS)" || true; }; }
HEALER="$(healer $(git grep -lIi -e 'self-healing' -- .claude README.md docs | grep -vE '^scripts/test-[^/]*\.sh$'))"
check "no sentence gives a self-healing loop to /nemo-it: it never fixes, the loop is the build's" \
  '[ -z "$HEALER" ] || { printf "%s\n" "$HEALER" | cut -c1-220 | sed "s/^/  claim: /"; false; }'
NEMOSEC="$(awk '/^- 6 test categories/{on=1} /^### /{on=0} on' .claude/make-it/references/guardrails.md | tr '\n' ' ' | tr -s ' ')"
RMSEC="$(awk '/^- Full suite \(60\+ tests\) runs in/{on=1; next} on && /^- /{print; exit}' README.md)"
check "README.md's bullet after \"Full suite ... runs in /nemo-it\" says check AI09 has no fix-and-retest loop (it runs no test)" \
  'printf "%s" "$RMSEC" | gq -F "Check AI09 has no fix-and-retest loop" && ! printf "%s" "$RMSEC" | gq -iE "self-healing" && printf "%s" "$RMSEC" | gq -F "/nemo-it reports its failures and fixes nothing"'
BPSEC="$(awk '/^\*\*Remediation flow/{on=1} /^\*\*Attestation:\*\*/{on=0} on' .claude/make-it/references/design-blueprint.md | tr '\n' ' ' | tr -s ' ')"
check "design-blueprint.md's remediation flow: none in check AI09, /nemo-it reports and fixes nothing, and nothing goes into an attestation the build doesn't write" \
  'printf "%s" "$BPSEC" | gq -F "none in check AI09" && printf "%s" "$BPSEC" | gq -F "/nemo-it writes and runs its own NeMo Guardrails cases and reports what fails; it fixes nothing" && ! printf "%s" "$BPSEC" | gq -iE "document in attestation"'
check "guardrails.md's NeMo rule says check AI09 has no fix-and-retest loop and /nemo-it reports and fixes nothing" \
  'printf "%s" "$NEMOSEC" | gq -F "Check AI09 has no fix-and-retest loop" && ! printf "%s" "$NEMOSEC" | gq -iE "self-healing" && printf "%s" "$NEMOSEC" | gq -F "/nemo-it reports its failures and fixes nothing"'

# no card id in shipped text: cardids FILE... prints each sentence that names one (Version History skipped)
cardids() { sents "$@" | nohist | { grep -E "$T.*\bE[0-9]{2}-S[0-9]+\b" || true; }; }
# the /backlog-it skill's own files show the id format with made-up ids
IDFILES="$( { git grep -lIE -e 'E[0-9]{2}-S[0-9]+' -- .claude || true; } | grep -vE '^\.claude/(commands/backlog-it\.md|make-it/backlog/|make-it/references/backlog-board\.md|make-it/confluence-docs/16-backlog-it\.md)' || true)"
CARDIDS="$(cardids $IDFILES)"
check "no file the installer ships (.claude/) names a card id (the board is private), but Version History and the /backlog-it skill's own examples" \
  '[ -z "$CARDIDS" ] || { printf "%s\n" "$CARDIDS" | cut -c1-220 | sed "s/^/  card id: /"; false; }'

# 2. the pointers name sections the guide has, and there are some (a pointer may wrap across lines)
# ptrs_ok FILE...: the files point at "What make-it runs before /ship-it", and every section they point at is in the guide
ptrs_ok() {
  local p; p="$(cat "$@" | tr '\n' ' ' | tr -s ' ' | { grep -oE 'ship-it-guide\.md, "[^"]+"' || true; } | sed -E 's/^ship-it-guide\.md, "//; s/"$//' | sort -u)"
  printf "%s\n" "$p" | gq -xF "What make-it runs before /ship-it" &&
    ( printf "%s\n" "$p" | while IFS= read -r x; do grep -E '^#+ ' "$GUIDE" | sed -E 's/^#+ //' | gq -xF "$x" || { echo "  no section: $x"; exit 1; }; done )
}
check "each pointer (ship-it-guide.md, \"<section>\") names a section of the guide, and the references point at \"What make-it runs before /ship-it\"" \
  'ptrs_ok $FILES'

# 3. controls: each real shape of the claim fails, and each pointer shape passes
plant() { printf "%b\n" "$1" > "$TMPD/p.md"; [ -n "$(claims "$TMPD/p.md")" ]; }
check "(control) fails: \"/ship-it runs the NeMo full suite.\"" 'plant "/ship-it runs the NeMo full suite."'
check "(control) fails: a /ship-it run as the time (\"each /ship-it run creates the attestation\", \"During /ship-it\" in a table)" \
  'plant "- \"snapshot\": each /ship-it run creates docs/attestations/YYYY-MM-DD-vN.md" && plant "| Ship | During /ship-it | Full suite | 60 |" && plant "The NeMo Guardrails test for safety at build-time and ship-time." && plant "| NeMo suite | 18 tests at build, 60 at ship |"'
check "(control) fails: the /ship-it PR holding it, and a row whose first cell is /ship-it" \
  'plant "- Confirm /ship-it PR description includes risk_flag count" && plant "| \`/ship-it\` | Deploy -- creates PR with security checks, attestation, review |" && plant "- [ ] risk_flag audit entries flagged by /ship-it for security review"'
check "(control) fails: a list item under a /ship-it lead-in, and \"it\" on a page about /ship-it" \
  'plant "When the user types \`/ship-it\`, the deployment pipeline:\n\n1. Detects the repo\n2. Runs NeMo Guardrails full test suite" && plant "# /ship-it -- Go live\n\nAlong the way it generates a safety attestation."'
check "(control) fails: the run against the AI models (\"/ship-it runs against ALL configured models\")" \
  'plant "- Build-verify runs against primary model only (speed); /ship-it runs against ALL configured models"'
check "(control) passes: \"/nemo-it runs the full suite before /ship-it.\", a pointer, a \"no skill\" clause, a plain no, and version history" \
  '! plant "/nemo-it runs the full suite before /ship-it." && ! plant "- /nemo-it runs the FULL suite (60 tests) before /ship-it (ship-it-guide.md, \"What make-it runs before /ship-it\")" && ! plant "No skill flags risk_flag entries for security review at ship (ship-it-guide.md, \"What make-it runs before /ship-it\")." && ! plant "/ship-it doesn'"'"'t run the NeMo full suite." && ! plant "## Version History\n\n### v1.1.0\n- /ship-it runs the NeMo full suite before PR creation"'
check "(control) fails, the sibling /ship-it claims: the dotenv grep, the OT sign-off, DAST, \"add ... to /ship-it\", \"at deploy time\", Playwright tests" \
  'plant "Build-verify and /ship-it grep for \`override=True\` and \`override: true\` in dotenv calls." && plant "/ship-it checks for \`ics_ot_integration: true\` and requires explicit OT security review sign-off in the PR description." && plant "- ICS/OT detection: flag for OT security team review. /ship-it requires explicit sign-off before production." && plant "| DAST scanning | Every /ship-it deploy | OWASP ZAP |" && plant "| Phase 3: DAST | 60 days | Integrate OWASP ZAP into /nemo-it standalone. Add to /ship-it pre-deploy |" && plant "| Validation | blocklist, risk-flagged edits flagged for security review at deploy time |" && plant "| Playwright Security Tests | Browser-based security testing | Medium | /nemo-it standalone or /ship-it |"'
check "(control) fails: a table row naming /ship-it in any cell (\"Build-verify + /ship-it\", \"/ship-it flags these\" after a risk_flag sentence), Playwright, a /ship-it arrow and the PR holding it in a diagram" \
  'plant "| NeMo Guardrails | AI behavioral safety testing | Build-verify + /ship-it | Mandatory |" && plant "| NeMo Guardrails | \`/ship-it\` (if AI features) | 60+ test cases |" && plant "| Risk audit trail | Overrides logged with risk_flag=true. /ship-it flags these in PR description | Build-verify |" && plant "\`\`\`mermaid\nsequenceDiagram\n    participant SI as /ship-it\n    SI->>SI: Dependency scan\n    SI->>SI: NeMo Guardrails (if AI features)\n\`\`\`" && plant "    Note over GH: PR with labels, scans,<br/>attestation, go-live checklist"'
check "(control) passes, the sibling fixes: build-verify greps (check I10) before /ship-it, no skill asks for an OT sign-off, a row giving the full suite to /nemo-it before /ship-it, a /ship-it arrow that runs no step" \
  '! plant "Build-verify greps for \`override=True\` in dotenv calls (check I10), before /ship-it (ship-it-guide.md, \"What make-it runs before /ship-it\")." && ! plant "No skill asks for an OT security sign-off at ship (ship-it-guide.md, \"What /ship-it Does\")." && ! plant "| NeMo Guardrails | AI behavioral safety testing | Build-verify (basic) + /nemo-it (full suite), before /ship-it | Mandatory |" && ! plant "\`\`\`mermaid\nsequenceDiagram\n    participant SI as /ship-it\n    SI->>GH: Create branch, push, create PR\n\`\`\`"'
fb() { printf "%b\n" "$1" > "$TMPD/f.md"; [ -n "$(fallback "$TMPD/f.md")" ]; }
check "(control) fallback: fails when a skill runs the fallback model (the old wording, \"testing in build-verify\"); passes the MUST and a plain \"neither\"" \
  'fb "- Build-verify runs against primary model only (speed); the full suite runs against ALL configured\n  models before /ship-it" && fb "| AI: Fallback model not safety-tested | Fallback model safety testing in build-verify | Prevented |" && ! fb "| Fallback model testing | NeMo Guardrails run against BOTH primary and fallback models | /nemo-it full test suite |" && fb "| Fallback model testing | NeMo Guardrails run against BOTH primary and fallback models | Build-verify + /nemo-it |" && fb "Build-verify exercises the fallback model too." && ! fb "- Build-verify runs against primary model only (speed). /nemo-it runs the suite against each configured model, the fallback model included" && fb "Build-verify runs against primary model only at first; then build-verify and /nemo-it both run the suite against the fallback model." && fb "| Fallback model safety | [Prevented/Missing] | Build-verify checklist |" && ! fb "- If the app configures a fallback AI model, NeMo Guardrails tests MUST run against BOTH\n  the primary and fallback models" && ! fb "- Build-verify runs against primary model only (speed). Today neither build-verify nor /nemo-it runs the fallback model: a known gap"'
att() { printf "%b\n" "$1" > "$TMPD/a.md"; [ -n "$(unattested "$TMPD/a.md")" ]; }
check "(control) attestation: fails when it is generated with no /nemo-it (a build-verify checklist item, \"Implementation generates:\", \"Yes -- auto-generated\", a feature line); passes /nemo-it, the quality-gate artifact and card E02-S44 lines" \
  'att "**NeMo Guardrails:**\n- [ ] AI Safety Attestation generated in docs/" && att "**Implementation generates:**\n- Attestation document in docs/" && att "| AI safety attestation | Yes -- auto-generated in docs/attestations/ | [PRESENT / ABSENT] |" && att "- Generates GRC-required AI Safety Attestation in \`docs/\`" && ! att "- No AI Safety Attestation at build-verify: /nemo-it writes it (ship-it-guide.md, \"What make-it runs before /ship-it\")" && ! att "Generates \`quality-gate-report.json\` attestation artifact." && ! att "    - \"snapshot\": each run creates docs/attestations/YYYY-MM-DD-vN.md"'
gn() { printf "%b\n" "$1" > "$TMPD/g.md"; [ -n "$(gone "$TMPD/g.md")" ]; }
hl() { printf "%b\n" "$1" > "$TMPD/h.md"; [ -n "$(healer "$TMPD/h.md")" ]; }
check "(control) the rephrasings fail: \"also runs\", \"re-runs ... and attaches\", \"/ship-it's PR carries\", \"/nemo-it exercises the fallback model\", \"Build-verify emits the attestation\"" \
  'plant "/ship-it also runs the 60-case NeMo suite." && plant "/ship-it re-runs NeMo and attaches the attestation." && plant "/ship-it'"'"'s PR carries the attestation summary." && fb "/try-it exercises the fallback model too." && ! fb "/nemo-it exercises the fallback model too." && att "Build-verify emits the attestation."'
check "(control) the gone setting: fails on attestation_mode, the \"latest\" file and a dated file outside nemo-it/; passes /nemo-it's own path and Version History" \
  'gn "  attestation_mode: \"snapshot\" (default)" && gn "- \"latest\": each run overwrites docs/ai-safety-attestation.md" && gn "- Default: versioned snapshot (docs/attestations/YYYY-MM-DD-vN.md)" && gn "- Attestation mode configurable in app-context.json" && gn "populate the attestation template at templates/ai-safety-attestation.md" && att "Build-verify saves the attestation in docs/." && att "Create guardrails/README.md explaining:\n  - How the attestation is generated" && hl "| NeMo pass rate | 60 in /nemo-it | 100% (self healing) |" && ! gn "/nemo-it writes docs/attestations/nemo-it/YYYY-MM-DD-vN.md" && ! gn "## Version History\n\n### v1.70.8\n\n- The attestation_mode setting is gone."'
check "(control) the self-healing loop: fails beside /nemo-it with no owner; passes when the build owns it, and with no /nemo-it" \
  'hl "| MEASURE 2.5 | 18 tests at build (basic), 60 tests in /nemo-it before deploy (full). Self-healing loop: test, fix, retest (3 cycles) |" && hl "| NeMo pass rate | 18 tests at build, 60 in /nemo-it before deploy | 100% (self-healing) |" && ! hl "| NeMo pass rate | 18 at build, 60 in /nemo-it | 100% at build (self-healing); /nemo-it reports |" && ! hl "- This is a self-healing loop: test, fail, fix, rebuild, retest until green." && ! hl "**Key differences from standalone /nemo-it + /fix-it:**\n- Self-healing loop: scan, fix, re-scan (up to 3 cycles)" && hl "/nemo-it runs a self-healing loop of up to 3 cycles."'
ci() { printf "%b\n" "$1" > "$TMPD/c.md"; [ -n "$(cardids "$TMPD/c.md")" ]; }
check "(control) card ids: fails on \"a known gap (card E02-S45)\" and a code comment \"(E02-S5)\"; passes \"a known gap\", an id under Version History, and a plain word like E2E-S3" \
  'ci "- Today neither build-verify nor /nemo-it runs the fallback model: a known gap (card E02-S45)" && ci "# ponytail: one fixed window. Real agents ran up to 62 min (E02-S5); past this a wait nudges again." && ! ci "- Today neither build-verify nor /nemo-it runs the fallback model: a known gap" && ! ci "## Version History\n\n### v1.44.18\n- Ships card E02-S21" && ! ci "E2E-S3 and SE02-S4X are no card ids"'
check "(control) the pointer check fails on a section the guide doesn't have, and with no pointer at all" \
  'printf "%s\n" "(ship-it-guide.md, \"What make-it runs before /ship-it\") (ship-it-guide.md, \"What /ship-it runs for AI safety\")" > "$TMPD/q.md" && ! ptrs_ok "$TMPD/q.md" >/dev/null && printf "%s\n" "/nemo-it runs the full suite." > "$TMPD/q.md" && ! ptrs_ok "$TMPD/q.md"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
