#!/usr/bin/env bash
# E07-S3: in any make-it project Claude reaches for the right skill without the person typing its name.
# Contract these checks pin:
#   - skill-triggers.md holds one "Section -- copy exactly" block, headed "## Which make-it skill, when".
#   - The block names every command make-it ships (a new skill can't be left out), and names no skill that doesn't exist
#     (/ship-it is the one outside name: it is installed separately).
#   - The skills that deploy, send or reach outside the computer (/ship-it, /argo-it, /demo-it, /threats-it) sit only in
#     the "Never start these on your own" paragraph, and that paragraph keeps "only when the person asks" and the skill's
#     own asks.
#   - Build step h writes the block into a new project's CLAUDE.md after the Learnings import, and build-standards S14
#     back-fills it the same way; the skills that run every check say S01-S15.
#   - Every command's description says when to use it ("Use when", "Use for", "Use to" or "Use mid-session"), and the
#     never-start skills in this repo say "Only when the user asks".
# A tripwire for the wording, not a proof of behavior: whether Claude really starts the skills is the card's live check.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

REF=.claude/make-it/references/skill-triggers.md
BS=.claude/make-it/references/build-standards.md
MK=.claude/commands/make-it.md
HEAD='## Which make-it skill, when'
NEVER='ship-it argo-it demo-it threats-it'

# block FILE: the fenced block under "## Section -- copy exactly"
block() { [ -f "$1" ] && awk '/^## Section -- copy exactly/{s=1; next} s && /^```markdown/{on=1; next} on && /^```/{exit} on' "$1" || true; }
BLOCK="$(block "$REF")"
check "skill-triggers.md has one copy-exactly block, headed \"$HEAD\"" \
  '[ "$(printf "%s\n" "$BLOCK" | head -1)" = "$HEAD" ] && [ "$(grep -c "^## Section -- copy exactly" "$REF")" = 1 ]'

CMDS="$(ls .claude/commands/*.md | sed -E 's#.*/##; s#\.md$##' | sort)"
NAMED="$(printf "%s\n" "$BLOCK" | grep -oE '/[a-z]+-it\b' | sed 's#^/##' | sort -u)"
check "the block names every command make-it ships" \
  'M="$(comm -23 <(printf "%s\n" "$CMDS") <(printf "%s\n" "$NAMED"))"; [ -z "$M" ] || { echo "  not named: $(echo $M)"; false; }'
check "the block names no skill that doesn't exist (but /ship-it, installed separately)" \
  'X="$(comm -13 <(printf "%s\n" "$CMDS") <(printf "%s\n" "$NAMED") | grep -vx ship-it || true)"; [ -z "$X" ] || { echo "  unknown: $(echo $X)"; false; }'

# the never paragraph: from its bold lead to the next blank line
NPARA="$(printf "%s\n" "$BLOCK" | awk '/^\*\*Never start these on your own\.\*\*/{on=1} on && !NF{exit} on' | tr '\n' ' ')"
REST="$(printf "%s\n" "$BLOCK" | awk '/^\*\*Never start these on your own\.\*\*/{on=1} on && !NF{on=0; next} !on')"
never_ok() { local s; for s in $NEVER; do printf "%s" "$NPARA" | gq -F "/$s" || { echo "  not in the never paragraph: /$s"; return 1; }
    ! printf "%s\n" "$REST" | gq -E "/$s\b" || { echo "  named outside the never paragraph: /$s"; return 1; }; done; }
check "the skills that deploy or reach outside (/ship-it, /argo-it, /demo-it, /threats-it) are named only in the never paragraph" 'never_ok'
check "the never paragraph says: only when the person asks for that outcome, and every ask the skill makes is kept" \
  'printf "%s" "$NPARA" | gq -F "only when the person asks for that outcome" && printf "%s" "$NPARA" | gq -F "keep every ask the skill makes"'
check "the block tells Claude to say which skill it started, and to start /debug-it before any fix" \
  'printf "%s\n" "$BLOCK" | tr "\n" " " | tr -s " " | gq -F "say in one line which one you started" && printf "%s\n" "$BLOCK" | gq -E "/debug-it\`?, before any fix"'

# each skill sits in exactly the group it was reviewed for (2026-11-19: /resolve-it ships by default and /git-it merges,
# so neither may be moved up without a new review)
grp() { printf "%s\n" "$BLOCK" | awk -v h="$1" 'index($0, "**" h)==1{on=1} on && !NF{exit} on' | grep -oE '/[a-z]+-it\b' | sed 's#^/##' | sort -u | tr '\n' ' '; }
check "each skill is in its reviewed group" \
  '[ "$(grp "Start it yourself")" = "clear-it debug-it dispatch-it git-it subagent-it " ] && [ "$(grp "Start it when the person")" = "backlog-it resume-it try-it wrap-it " ] && [ "$(grp "Suggest these")" = "deadcode-it fix-it make-it nemo-it resolve-it retrofit-it " ] && [ "$(grp "Never start these on your own")" = "argo-it demo-it ship-it threats-it " ] || { echo "  yourself: $(grp "Start it yourself")"; echo "  words: $(grp "Start it when the person")"; echo "  suggest: $(grp "Suggest these")"; echo "  never: $(grp "Never start these on your own")"; false; }'
STARTS="$(printf "%s\n" "$BLOCK" | awk '/^\*\*Start it /{on=1} /^\*\*Suggest these/{on=0} on')"
check "the two start groups promise nothing that leaves the computer: no live, deploy, ship or push, and a merge waits for the person" \
  '! printf "%s\n" "$STARTS" | gq -iE "\blive\b|deploy|\bship|\bpush" && printf "%s\n" "$STARTS" | tr "\n" " " | tr -s " " | gq -F "A merge into the main branch, and anything sent to GitHub, waits for the person" && printf "%s\n" "$STARTS" | gq -F "git step on this computer"'
check "/resolve-it is only suggested, and only as --propose; a no to a suggestion is kept" \
  'printf "%s\n" "$BLOCK" | gq -F "/resolve-it --propose" && [ "$(printf "%s\n" "$BLOCK" | grep -c "/resolve-it")" = 1 ] && printf "%s\n" "$BLOCK" | gq -F "A no is kept"'
check "the never paragraph has no way out, and a never-start skill that isn't installed stops the work" \
  '! printf "%s" "$NPARA" | gq -iE "unless|except|go ahead|clearly needs" && printf "%s\n" "$BLOCK" | tr "\n" " " | tr -s " " | gq -F "For a never-start skill, stop there"'
check "a running skill is not restarted, /dispatch-it says its agent count first, and /backlog-it needs a board" \
  'printf "%s\n" "$BLOCK" | tr "\n" " " | tr -s " " | gq -F "A skill that is already running is not started again" && printf "%s\n" "$BLOCK" | gq -F "say how many agents before starting" && printf "%s\n" "$BLOCK" | tr "\n" " " | tr -s " " | gq -F "when the project has a board"'

# Build step h and S14
TPL="$(awk '/^      # Project instructions/{on=1} on && /^      ```$/{exit} on' "$MK")"
check "Build step h puts [SKILLS_SECTION] after the Learnings import, and says where the block comes from" \
  'printf "%s\n" "$TPL" | awk "/@LEARNINGS.md/{l=NR} /\[SKILLS_SECTION\]/{s=NR} END{exit !(l && s && s>l)}" && gq -F "skill-triggers.md" "$MK" && gq -F "build-standards check S14" "$MK"'
S14="$(grep -E '^\*\*S14\*\* ' "$BS" || true)"
check "build-standards S14 back-fills the section: after the Learnings section, once, word for word from skill-triggers.md" \
  'printf "%s" "$S14" | gq -F "$HEAD" && printf "%s" "$S14" | gq -F "skill-triggers.md" && printf "%s" "$S14" | gq -F "word for word" && printf "%s" "$S14" | gq -F "appears once" && printf "%s" "$S14" | gq -F "after the \`## Learnings\` section"'
# E11 added S15 (the project specialist record); all three skills that run every check name S01-S15.
check "the skills that run every check say S01-S15, and none still says S01-S14 or S01-S13" \
  'gq -F "S01-S15" "$MK" && gq -F "S01-S15" .claude/commands/retrofit-it.md && gq -F "S01-S15" .claude/commands/resume-it.md && ! cat "$MK" .claude/commands/retrofit-it.md .claude/commands/resume-it.md | gq -E "S01-S1[34]"'

# descriptions
desc() { awk '/^---/{c++; next} c==1 && /^description:/{sub(/^description: */,""); print; exit}' "$1"; }
TRIG='Use (when|for|to|mid-session)\b|Only when the user asks'
no_trigger() { local f; for f in .claude/commands/*.md; do desc "$f" | gq -E "$TRIG" || echo "$(basename "$f" .md)"; done; }
check "every command's description says when to use it" \
  'X="$(no_trigger)"; [ -z "$X" ] || { echo "  no trigger: $(echo $X)"; false; }'
never_desc() { local s; for s in argo-it demo-it threats-it; do desc ".claude/commands/$s.md" | gq -F "Only when the user asks" && desc ".claude/commands/$s.md" | gq -F "never start it on your own" && ! desc ".claude/commands/$s.md" | gq -iE "\bor use when\b|Use (when|for|to)\b" || { echo "  $s"; return 1; }; done; }
check "/argo-it, /demo-it and /threats-it say \"Only when the user asks\" and \"never start it on your own\", with no second trigger" 'never_desc'
check "S14 and its neighbours: S14 runs last in the one CLAUDE.md change, and is named plainly in the catch-up list" \
  'printf "%s" "$S14" | gq -F "anywhere else" && printf "%s" "$S14" | gq -F "instructions that help me pick the right tool" && grep -E "^\*\*S13\*\* " "$BS" | gq -F "S14 last" && gq -F "S14 last" .claude/commands/resume-it.md'

# controls
check "(control) a description with no trigger fails, and one with \"Use when\" passes" \
  '! printf "%s\n" "Wrap up your work session. Just run /wrap-it when you are done." | gq -E "$TRIG" && printf "%s\n" "Wrap up. Use when the user says they are done for the day." | gq -E "$TRIG"'

check "the whole run wrote nothing to stderr" '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
