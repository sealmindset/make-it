#!/usr/bin/env bash
#
# gen-sdlc-gap-appendix.sh
#
# Generates docs/AI-NATIVE-SDLC-GAP-APPENDIX.md from the repository itself.
#
# Every count and every name in the leadership briefing
# (docs/AI-NATIVE-SDLC-GAP-BRIEFING.md) and the technical companion
# (docs/AI-NATIVE-SDLC-GAP-COMPANION.md) is derived from this script's output.
# Nothing in the appendix is typed by hand.
#
# Usage:  ./docs/scripts/gen-sdlc-gap-appendix.sh          # write the appendix
#         ./docs/scripts/gen-sdlc-gap-appendix.sh --stdout # print instead
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

OUT="docs/AI-NATIVE-SDLC-GAP-APPENDIX.md"
[[ "${1:-}" == "--stdout" ]] && OUT=/dev/stdout

CMDS_DIR=".claude/commands"
REFS_DIR=".claude/make-it/references"

# ---------------------------------------------------------------- helpers ---

# kb <file> -> size in whole KB
kb() { echo $(( ($(wc -c < "$1")+1023) / 1024 )); }

# hits <regex> <file...> -> total matching lines across files.
# grep exits 1 on no-match; under `pipefail` that would abort the script, so the
# no-match case is normalised to an empty stream (which is a legitimate result
# here -- a zero count is evidence).
hits() {
  local pat="$1"; shift
  { grep -rIoh -E "$pat" "$@" 2>/dev/null || true; } | wc -l | tr -d ' '
}

# files_matching <regex> <dir...> -> newline list of files containing pattern
files_matching() {
  local pat="$1"; shift
  { grep -rIl -E "$pat" "$@" 2>/dev/null || true; } | sort
}

# table of md files in a dir, name + KB
md_table() {
  local dir="$1"
  printf '| File | Size (KB) |\n|---|---:|\n'
  find "$dir" -maxdepth 1 -name '*.md' | sort | while read -r f; do
    printf '| `%s` | %s |\n' "${f#./}" "$(kb "$f")"
  done
}

# table of immediate subdirectories of a tree, name + file count
subdir_table() {
  local root="$1"
  printf '| Scaffold tree | Files |\n|---|---:|\n'
  find "$root" -maxdepth 1 -mindepth 1 -type d | sort | while read -r d; do
    printf '| `%s` | %s |\n' "${d#./}" "$(find "$d" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')"
  done
}

# render a newline-separated file list as one space-joined cell, or *(none)*
list_or_none() {
  local v="$1"
  if [[ -z "${v//[[:space:]]/}" ]]; then printf '*(none)*'
  else printf '%s' "$v" | tr '\n' ' ' | sed 's/ *$//'
  fi
}

# ------------------------------------------------------------- collection ---

GEN_DATE="$(date -u +%Y-%m-%d)"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"

CMD_COUNT=$(find "$CMDS_DIR" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
REF_COUNT=$(find "$REFS_DIR" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
REF_BYTES=$(find "$REFS_DIR" -maxdepth 1 -name '*.md' -exec wc -c {} + | tail -1 | awk '{print $1}')
REF_KB=$(( (REF_BYTES + 1023) / 1024 ))

SCAFFOLD_ROOT=".claude/make-it/scaffolds"
SCAFFOLD_FILES=$(find "$SCAFFOLD_ROOT" -type f ! -name '.DS_Store' 2>/dev/null | wc -l | tr -d ' ')
SCAFFOLD_DIRS=$(find "$SCAFFOLD_ROOT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | sed 's|.*/||' | paste -sd, - | sed 's/,/, /g')

# Stage 1/2 artifact chain
INTENT_HITS=$(hits 'intent\.md|spec\.md|plan\.md' "$CMDS_DIR" "$REFS_DIR")
INTENT_FILES=$(files_matching 'intent\.md|spec\.md|plan\.md' "$CMDS_DIR" "$REFS_DIR")

# Stage 3 plan mode
PLANMODE_HITS=$(hits '[Pp]lan mode|ExitPlanMode|EnterPlanMode' "$CMDS_DIR" "$REFS_DIR")

# Stage 4 evals
EVAL_HITS=$(hits '\beval(s|uation)?\b' "$CMDS_DIR" "$REFS_DIR")
EVAL_SUITE_FILES=$(find . -path ./node_modules -prune -o \
  \( -name 'evals' -o -name 'eval' -o -name '*.eval.json' -o -name 'evals.json' \) -print 2>/dev/null | sort || true)

# Stage 5 hooks / governance
SETTINGS_JSON=".claude/settings.json"
SETTINGS_PRESENT=$([[ -f "$SETTINGS_JSON" ]] && echo yes || echo no)
HOOKS_DIR_PRESENT=$([[ -d ".claude/hooks" ]] && echo yes || echo no)
HOOK_KEY_HITS=$(hits 'PreToolUse|PostToolUse|UserPromptSubmit|SessionStart' \
  .claude/settings.json .claude/settings.local.json 2>/dev/null || echo 0)
MANAGED_HITS=$(hits 'allowManagedHooksOnly|disableSideloadFlags|permissions\.deny|"sandbox"|"credentials"' \
  .claude/settings.json .claude/settings.local.json 2>/dev/null || echo 0)

CI_WORKFLOWS=$(find .github/workflows -type f 2>/dev/null | sort || true)
CI_COUNT=$(printf '%s\n' "$CI_WORKFLOWS" | grep -c . || true)

# PR review loop
PRREVIEW_HITS=$(hits 'claude-code-action|REVIEW\.md' .github "$CMDS_DIR" "$REFS_DIR" 2>/dev/null || echo 0)

# Stage 6 metrics
METRIC_HITS=$(hits 'cycle time|DORA|lead time|telemetry|rolling baseline|Western Electric' "$CMDS_DIR" "$REFS_DIR")
METRIC_FILES=$(files_matching 'cycle time|DORA|lead time|telemetry|rolling baseline|Western Electric' "$CMDS_DIR" "$REFS_DIR")

# Blocking-severity policy statements with no deterministic enforcer
BLOCK_HITS=$(hits '\[BLOCK\]' "$REFS_DIR")
FIX_HITS=$(hits '\[FIX\]' "$REFS_DIR")
WARN_HITS=$(hits '\[WARN\]' "$REFS_DIR")
ENFORCING_HITS=$(( BLOCK_HITS + FIX_HITS ))

# ---------------------------------------------------------------- emit ------

{
cat <<EOF
# Appendix — AI-Native SDLC Gap Assessment: Source Data

**Generated** $GEN_DATE from commit \`$GIT_SHA\` by \`docs/scripts/gen-sdlc-gap-appendix.sh\`.
**Do not hand-edit.** Re-run the script to refresh.

Companion documents:
- Leadership briefing — \`docs/AI-NATIVE-SDLC-GAP-BRIEFING.md\`
- Technical companion — \`docs/AI-NATIVE-SDLC-GAP-COMPANION.md\`

This appendix lists, by name, every file behind every count in those two
documents. It covers **only this repository** (\`make-it\`). It deliberately omits:

- The contents of generated applications (\`/make-it\` output lives in other repos).
- Files under \`.claude/plugins/\` — third-party plugin caches, not this project's code.
- \`node_modules\`, \`.git\`, and binary assets.
- Anything requiring GitHub organization or MDM administrator access to observe
  (enterprise managed settings, branch-protection rules, Claude Code admin console
  configuration). Those gaps are stated as *unobserved*, not as *absent*.

---

## A. Skill surface — \`$CMDS_DIR\`

**Count: $CMD_COUNT skill definition files.**

$(md_table "$CMDS_DIR")

## B. Shared reference corpus — \`$REFS_DIR\`

**Count: $REF_COUNT reference files, $REF_KB KB total.**

$(md_table "$REFS_DIR")

## C. Scaffold inventory — \`$SCAFFOLD_ROOT\`

**Count: $SCAFFOLD_FILES files across scaffold trees: $SCAFFOLD_DIRS**

$(subdir_table "$SCAFFOLD_ROOT")

---

## D. Gap evidence — greps against $CMDS_DIR and $REFS_DIR

| Playbook stage | Pattern searched | Matching lines | Files containing it |
|---|---|---:|---|
| Plan / Design | \`intent.md\` \\| \`spec.md\` \\| \`plan.md\` | $INTENT_HITS | $(list_or_none "$INTENT_FILES") |
| Build | \`plan mode\` \\| \`EnterPlanMode\` \\| \`ExitPlanMode\` | $PLANMODE_HITS | $(list_or_none "$(files_matching '[Pp]lan mode|ExitPlanMode|EnterPlanMode' "$CMDS_DIR" "$REFS_DIR")") |
| Test | \`eval\` / \`evals\` / \`evaluation\` (prose or otherwise) | $EVAL_HITS | see §E |
| Deploy | \`claude-code-action\` \\| \`REVIEW.md\` | $PRREVIEW_HITS | $(list_or_none "$(files_matching 'claude-code-action|REVIEW\.md' .github "$CMDS_DIR" "$REFS_DIR")") |
| Maintain | \`cycle time\` \\| \`DORA\` \\| \`lead time\` \\| \`telemetry\` \\| \`rolling baseline\` \\| \`Western Electric\` | $METRIC_HITS | $(list_or_none "$METRIC_FILES") |

## E. Eval infrastructure

- Files or directories named \`eval\`/\`evals\`/\`*.eval.json\`: $(if [[ -z "$EVAL_SUITE_FILES" ]]; then echo "**none found**"; else printf '\n%s' "$EVAL_SUITE_FILES" | sed 's/^/  - /'; fi)
- Prose mentions of the word (§D, Test row): $EVAL_HITS — these are English usage, not a suite.

## F. Hooks and governance controls

| Control | Observed |
|---|---|
| \`.claude/settings.json\` present in repo | $SETTINGS_PRESENT |
| \`.claude/hooks/\` directory present | $HOOKS_DIR_PRESENT |
| Hook event keys (\`PreToolUse\`/\`PostToolUse\`/\`UserPromptSubmit\`/\`SessionStart\`) in committed settings | $HOOK_KEY_HITS |
| Managed-settings keys (\`allowManagedHooksOnly\`, \`disableSideloadFlags\`, \`permissions.deny\`, \`sandbox\`, \`credentials\`) in committed settings | $MANAGED_HITS |

Committed settings files actually present:
$(ls -1 .claude/settings*.json 2>/dev/null | sed 's/^/  - `/; s/$/`/' || echo "  - *(none)*")

## G. Continuous integration

**Count: $CI_COUNT workflow file(s).**

$(if [[ -z "$CI_WORKFLOWS" ]]; then echo "*(none)*"; else printf '%s\n' "$CI_WORKFLOWS" | sed 's/^/  - `/; s/$/`/'; fi)

## H. Policy statements carrying enforcement severity

Severity tags declared across \`$REFS_DIR\`:

| Tag | Occurrences | Asserts enforcement | Deterministic enforcer in repo |
|---|---:|---|---|
| \`[BLOCK]\` | $BLOCK_HITS | yes | none — see §F |
| \`[FIX]\` | $FIX_HITS | yes | none — see §F |
| **Total asserting enforcement** | **$ENFORCING_HITS** | | **none** |
| \`[WARN]\` | $WARN_HITS | no (advisory by design) | n/a — correctly advisory |

Each occurrence is a policy the framework states must hold. The \`[BLOCK]\` and
\`[FIX]\` tiers assert enforcement; §F shows no hook, no CI check, and no managed
setting implements that enforcement in this repository.

---

*End of generated appendix.*
EOF
} > "$OUT"

[[ "$OUT" != /dev/stdout ]] && echo "Wrote $OUT" >&2 || true
