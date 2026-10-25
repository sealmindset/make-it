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
# The test scripts are not scanned: they quote the opposites as controls.
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
# lead-in (the unit before the list, ending in ":"). On a page whose title names /ship-it, "it" is /ship-it.
IFS= read -r -d '' SPLIT <<'PERL' || true
for my $f (@ARGV) {
  open my $fh, "<", $f or die "$f: $!\n";
  my ($t, @map, @units) = ("");
  my $flush = sub { push @units, [$t, [@map]] if $t =~ /\S/; $t = ""; @map = (); };
  while (my $l = <$fh>) {
    chomp $l;
    if ($l !~ /\S/) { $flush->(); next }
    $flush->() if $l =~ /^\s*(?:[-*+] |\d+\. |\||#|```)/;
    $l =~ s/^\s+//;
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
    (my $cut = $s) =~ s/(?<!^\d)(?<!^\d\d)([.!?]["')\x27]?) (?=\S)/$1\n/g;
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
POINTER='What make-it runs before /ship-it|Safety steps /ship-it doesn.t run yet|\b[Bb]efore `?/ship-it\b|\b[Nn]o skill\b[^.;:]*'
T=$'\t'
VERBS='runs?|checks?|flags?|includes?|creates?|generates?|writes?|overwrites?|produces?|adds?|puts?|scans?|tests?'
DOES="/ship-it\`? +($VERBS)\b|\b(during|each|every|on|by|in|at|from) \`?/ship-it\b|/ship-it\`? +(PR|pull request|run)\b|$T\| *\`?/ship-it\b[^|]*\|[^|]*\b($VERBS)\b|/ship-it\b[^:]*:\**[[:space:]]+([0-9]+\.|[-*+])[[:space:]].*\b($VERBS)\b|\bship-time\b|\bship time\b|\bat ship\b|\bduring ship\b"
STEP='\bNeMo\b|full (test )?suite|test suite|test cases|attestation|risk_flag|risk flag|AI[- ]safety test|Prompt Safety Review|\bruns? against\b'
# claims FILE...: each sentence that names /ship-it and one of the steps as something /ship-it does, as file:line<TAB>text
claims() { sents "$@" | nohist | perl -pe "s#$POINTER##g" | { grep -iE "$DOES" || true; } | { grep -iE "$STEP" || true; }; }

FILES="$(git grep -lIi -e ship -- .claude scripts | grep -vxF "$GUIDE" | grep -vE '^scripts/test-[^/]*\.sh$')"

# 1. no reference names a /ship-it step it doesn't run
CLAIMS="$(claims $FILES)"
check "no reference outside ship-it-guide.md names the NeMo full run, the attestation or the risk_flag PR flag as a /ship-it step" \
  '[ -z "$CLAIMS" ] || { printf "%s\n" "$CLAIMS" | cut -c1-220 | sed "s/^/  claim: /"; false; }'

# 2. the pointers name sections the guide has, and there are some (a pointer may wrap across lines)
# ptrs_ok FILE...: the files point at "What make-it runs before /ship-it", and every section they point at is in the guide
ptrs_ok() {
  local p; p="$(cat "$@" | tr '\n' ' ' | tr -s ' ' | { grep -oE 'ship-it-guide\.md, "[^"]+"' || true; } | sed -E 's/^ship-it-guide\.md, "//; s/"$//' | sort -u)"
  printf "%s\n" "$p" | gq -xF "What make-it runs before /ship-it" &&
    ( printf "%s\n" "$p" | while IFS= read -r x; do gq -xF "### $x" "$GUIDE" || { echo "  no section: $x"; exit 1; }; done )
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
check "(control) the pointer check fails on a section the guide doesn't have, and with no pointer at all" \
  'printf "%s\n" "(ship-it-guide.md, \"What make-it runs before /ship-it\") (ship-it-guide.md, \"What /ship-it runs for AI safety\")" > "$TMPD/q.md" && ! ptrs_ok "$TMPD/q.md" >/dev/null && printf "%s\n" "/nemo-it runs the full suite." > "$TMPD/q.md" && ! ptrs_ok "$TMPD/q.md"'

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
