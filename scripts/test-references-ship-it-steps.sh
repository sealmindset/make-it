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
#   - The fallback AI model: no skill runs the NeMo tests against it today (card E02-S45). No sentence says one does (a
#     MUST, or a "neither ..." / "none today" / "not run" sentence, is no such claim), and guardrails.md says so plainly,
#     as "a known gap": shipped text names no card id (the board is private).
#   - The AI-safety attestation: only /nemo-it writes one. No sentence says one is generated without naming /nemo-it (or
#     /fix-it, which re-scans with it), but the CI quality-gate's "attestation artifact" and the lines card E02-S44 owns
#     (attestation_mode, docs/ai-safety-attestation.md and its template). nemo-it.md and fix-it.md are its own pages.
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
VERBS='runs?|checks?|flags?|includes?|creates?|generates?|writes?|overwrites?|produces?|adds?|puts?|scans?|tests?|greps?|requires?'
DOES="/ship-it\`? +($VERBS)\b|\b(during|each|every|on|by|in|at|from) \`?/ship-it\b|/ship-it\`? +(PR|pull request|run)\b|/ship-it\b[^:]*:\**[[:space:]]+([0-9]+\.|[-*+])[[:space:]].*\b($VERBS)\b|\bship-time\b|\bship time\b|\bat ship\b|\bduring ship\b|\badd[a-z]*\b[^.|]{0,20} to \`?/ship-it\b|\bat deploy( time)?\b|\bPR (with|includes?)\b"
# a table row that names /ship-it in any cell (the row is one sentence: its cells are who, when and what)
ROW="$T\\|.*/ship-it\\b"
STEP='\bNeMo([^-]|$)|\bPlaywright\b|full (test )?suite|test suite|test cases|attestation|risk[-_ ]flag|AI[- ]safety test|Prompt Safety Review|\bruns? against\b|\bDAST\b|OWASP ZAP|override=True|override: true|\bdotenv\b|ics_ot|\bOT security\b|sign-off'
# claims FILE...: each sentence that names /ship-it and one of the steps as something /ship-it does, as file:line<TAB>text
claims() { sents "$@" | nohist | perl -pe "s#$POINTER##g" | { grep -iE -e "$T.*($DOES)" -e "$ROW" || true; } | { grep -iE "$T.*($STEP)" || true; }; }
# fallback FILE...: each sentence that says a skill runs the NeMo tests against the fallback (or every) AI model
FB='fallback models?[^.|]*\b(safety-)?test(s|ed|ing)?\b|\b(runs?|tests?|tested|testing)\b[^.|]*\b(all configured|both( the)? primary|the fallback) models?\b|\bruns? against (all|both)\b|fallback model[^.]*build-verify|build-verify[^.]*fallback model'
FBOK='\bMUST\b|\bneither\b|\bnone today\b|\bno skill\b|\bnot (run|tested)\b'
fallback() { sents "$@" | nohist | { grep -iE "$T.*($FB)" || true; } | { grep -viE "$T.*($FBOK)" || true; }; }
# unattested FILE...: each sentence that says an AI-safety attestation is generated without naming /nemo-it
GEN='\b(generates?|generated|generating|generate|creates?|produces?|writes?)\b[^.|]{0,40}\battestation\b|\battestation\b( [A-Za-z/`.-]+){0,3} (is |was |are )?(generated|auto-generated|created|produced|written)\b|\battestation\b[^|]*\|[^|]*\bauto-generated\b'
GENOK='nemo-it|fix-it|quality|how the attestation|ai-safety-attestation\.md|attestation_mode|docs/attestations/YYYY'
unattested() { sents "$@" | nohist | { grep -iE "$T.*($GEN)" || true; } | { grep -viE "$T.*($GENOK)" || true; }; }

FILES="$(git grep -lIiE -e 'ship|attestation|fallback' -- .claude scripts README.md docs | grep -vxF "$GUIDE" | grep -vE '^scripts/test-[^/]*\.sh$')"
# /nemo-it and /fix-it write and re-scan the attestation; the ai-safety-attestation template is card E02-S44's
DFILES="$(printf "%s\n" $FILES | grep -vxE '\.claude/commands/(nemo|fix)-it\.md|\.claude/make-it/templates/ai-safety-attestation\.md')"

# 1. no reference names a /ship-it step it doesn't run
CLAIMS="$(claims $FILES)"
check "no reference outside ship-it-guide.md names the NeMo full run, the attestation, the risk_flag PR flag, the dotenv grep, the OT sign-off or DAST as a /ship-it step" \
  '[ -z "$CLAIMS" ] || { printf "%s\n" "$CLAIMS" | cut -c1-220 | sed "s/^/  claim: /"; false; }'
FALLBACK="$(fallback $FILES)"
check "no reference says a skill runs the NeMo tests against the fallback (or every) AI model: none does today" \
  '[ -z "$FALLBACK" ] || { printf "%s\n" "$FALLBACK" | cut -c1-220 | sed "s/^/  claim: /"; false; }'
FBSEC="$(awk '/^#/{on=($0 ~ /^#### AI Fallback Model Safety/)} on' .claude/make-it/references/guardrails.md | tr '\n' ' ' | tr -s ' ')"
check "guardrails.md keeps the fallback MUST and says plainly that neither build-verify nor /nemo-it runs the fallback model, a known gap, with no card id" \
  'printf "%s" "$FBSEC" | gq -F "MUST run against BOTH" && printf "%s" "$FBSEC" | gq -F "neither build-verify nor /nemo-it runs the fallback model" && printf "%s" "$FBSEC" | gq -F "a known gap" && ! printf "%s" "$FBSEC" | gq -E "\bE[0-9]{2}-S[0-9]+\b"'
UNATTESTED="$(unattested $DFILES)"
check "no reference says the AI-safety attestation is generated without naming /nemo-it (build-verify writes none)" \
  '[ -z "$UNATTESTED" ] || { printf "%s\n" "$UNATTESTED" | cut -c1-220 | sed "s/^/  claim: /"; false; }'

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
  'fb "- Build-verify runs against primary model only (speed); the full suite runs against ALL configured\n  models before /ship-it" && fb "| AI: Fallback model not safety-tested | Fallback model safety testing in build-verify | Prevented |" && fb "| Fallback model testing | NeMo Guardrails run against BOTH primary and fallback models | /nemo-it full test suite |" && fb "| Fallback model safety | [Prevented/Missing] | Build-verify checklist |" && ! fb "- If the app configures a fallback AI model, NeMo Guardrails tests MUST run against BOTH\n  the primary and fallback models" && ! fb "- Build-verify runs against primary model only (speed). Today neither build-verify nor /nemo-it runs the fallback model: a known gap"'
att() { printf "%b\n" "$1" > "$TMPD/a.md"; [ -n "$(unattested "$TMPD/a.md")" ]; }
check "(control) attestation: fails when it is generated with no /nemo-it (a build-verify checklist item, \"Implementation generates:\", \"Yes -- auto-generated\", a feature line); passes /nemo-it, the quality-gate artifact and card E02-S44 lines" \
  'att "**NeMo Guardrails:**\n- [ ] AI Safety Attestation generated in docs/" && att "**Implementation generates:**\n- Attestation document in docs/" && att "| AI safety attestation | Yes -- auto-generated in docs/attestations/ | [PRESENT / ABSENT] |" && att "- Generates GRC-required AI Safety Attestation in \`docs/\`" && ! att "- No AI Safety Attestation at build-verify: /nemo-it writes it (ship-it-guide.md, \"What make-it runs before /ship-it\")" && ! att "Generates \`quality-gate-report.json\` attestation artifact." && ! att "    - \"snapshot\": each run creates docs/attestations/YYYY-MM-DD-vN.md"'
ci() { printf "%b\n" "$1" > "$TMPD/c.md"; [ -n "$(cardids "$TMPD/c.md")" ]; }
check "(control) card ids: fails on \"a known gap (card E02-S45)\" and a code comment \"(E02-S5)\"; passes \"a known gap\", an id under Version History, and a plain word like E2E-S3" \
  'ci "- Today neither build-verify nor /nemo-it runs the fallback model: a known gap (card E02-S45)" && ci "# ponytail: one fixed window. Real agents ran up to 62 min (E02-S5); past this a wait nudges again." && ! ci "- Today neither build-verify nor /nemo-it runs the fallback model: a known gap" && ! ci "## Version History\n\n### v1.44.18\n- Ships card E02-S21" && ! ci "E2E-S3 and SE02-S4X are no card ids"'
check "(control) the pointer check fails on a section the guide doesn't have, and with no pointer at all" \
  'printf "%s\n" "(ship-it-guide.md, \"What make-it runs before /ship-it\") (ship-it-guide.md, \"What /ship-it runs for AI safety\")" > "$TMPD/q.md" && ! ptrs_ok "$TMPD/q.md" >/dev/null && printf "%s\n" "/nemo-it runs the full suite." > "$TMPD/q.md" && ! ptrs_ok "$TMPD/q.md"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
