#!/usr/bin/env bash
# /threats-it treats AI as part of the attacker (owner, 2026-11-17). Slice 1: every chain is rated
# for a person alone against a person with AI help, as an assessment, with sourced claims only.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
R=.claude/make-it/threats-it/references
flat() { tr '\n' ' ' | tr -s ' '; }
has() { if [ "$(flat < "$2" | grep -cF -- "$1")" -gt 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
hasnt() { if [ "$(flat < "$2" | grep -ciE -- "$1")" -eq 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
C=$R/attack-chains.md
has 'Who can do this now: the AI-assisted attacker (required for every chain)' "$C" "every chain gets a who-can-do-this-now table"
has '**Stage | A person alone: skill, time | With AI help: skill, time | AI acting on its own: time | Why it changes, or doesn' "$C" "the table compares a person alone, a person with AI help, and an AI acting on its own"
has 'an AI agent running the chain itself, with a person only starting it or nobody at all' "$C" "an AI acting on its own is its own attacker"
has 'it tries combinations at machine speed' "$C" "machine-speed trial and error is named"
has 'it uses what each failed try showed in the next one' "$C" "learning between tries is named"
has 'How fast <Org> would notice and act' "$C" "the window sets the attack against the response"
has 'If the chain can finish before anyone would act, say that in those words' "$C" "a chain that outruns the response is said plainly"
has 'Would the tries be seen?' "$C" "the noise of failed tries is checked"
has 'a time-to-compromise figure ("under N hours") with no archived source' "$R/fact-check.md" "the fact-check looks for unsourced time-to-compromise figures"
has 'quote it with its source and its conditions, or leave it out' "$R/sources.md" "a general time-to-compromise figure needs a source"
has 'an order of magnitude only' "$C" "time is an order of magnitude"
has 'Never a number' "$C" "time is never a number"
has 'With AI help moves only with a reason tied to that stage' "$C" "the AI rating needs a reason per stage"
has 'It does not change a stage that waits on something else' "$C" "stages AI does not change are named"
has 'Assessment, not measurement' "$C" "the table is headed as an assessment"
has 'It is never evidence that AI was used in this attack' "$C" "a rating is not evidence AI was used"
has 'What still stands in the way' "$C" "the limiting stage is named"
has 'Never write that a chain is unlikely because it needs a sophisticated attacker' "$C" "sophistication is never the reason a chain is unlikely"
has 'Who could do this now' "$R/report-standard.md" "the briefing carries one line per chain"
has 'Marked as an assessment' "$R/report-standard.md" "the briefing line is marked as an assessment"
has 'Never name an outage or a breach as AI-driven unless a primary source attributes it' "$R/sources.md" "no incident is called AI-driven without a source"
has 'our assessment; no published source archived' "$R/sources.md" "an unsourced capability claim says so"
has 'a statement that AI was used in this attack, or in any named incident, with no archived source' "$R/fact-check.md" "the fact-check looks for unsourced AI claims"
has 'a time more precise than minutes / hours / days / weeks' "$R/fact-check.md" "the fact-check looks for false precision"
has 'who can do this now' .claude/commands/threats-it.md "the skill's step 4 asks for the table"
has 'never a claim that AI was used unless a source says so' .claude/commands/threats-it.md "the skill's step 4 keeps the sourcing rule"
# the organisation's own security testing is not an attacker (owner, 2026-11-17)
T=$R/tenant-assessment.md
has "own security testing is not an attacker" "$T" "own security testing is never reported as an attacker"
has 'AuditGitHub and the scanners it runs' "$T" "AuditGitHub and its scanners are named"
has 'a name alone proves nothing' "$T" "exclusion is by recorded identifier, not by name"
has 'matches no recorded identifier is hunted like everything else' "$T" "a look-alike is still hunted"
has 'Excluded activity is counted, never dropped silently' "$T" "what was left out is counted and said"
has 'a finding is used only after this run' "$T" "the tool's findings are leads to confirm"
has 'Own security tooling' "$R/environment-template.md" "the profile records the tools and their identifiers"
has 'our own security testing left out of the hunt, by tool and count' "$R/report-standard.md" "the report says what was left out"
exit $fail
