#!/usr/bin/env bash
# E02-S76: the scaffold's quality-gate workflow wrote `--arg branch "${{ github.head_ref }}"` inside a `run:` block.
# GitHub pastes a `${{ }}` expression into the script text before the shell runs it, so a branch named with shell code
# ran that code in the CI runner (Semgrep: yaml.github-actions.security.run-shell-injection).
# Contract these checks pin:
#   - No workflow make-it ships or templates has `${{` in a step's script text: the value of `run:` (one line, a `|`/`>`
#     block, or a plain value that continues on deeper lines) or of `script:` (actions/github-script, or a list of
#     commands). Expressions in `env:`, `with:`, `if:`, `uses:` and `defaults: run:` are allowed. Files read: every
#     tracked `.github/workflows/*.yml|yaml` (the repo's own, the scaffolds', the overlays'), and every ```yaml / ```yml
#     fence in every tracked Markdown file (the workflow templates in the commands and references).
#   - The attestation step still records the branch, through `env:` (BRANCH) and the quoted "$BRANCH".
#   - build-standards check Q16 exists once, [Tier 0] [BLOCK] [SECURITY FIX], is the last Q check, and says the rule,
#     why, the fix and that apps already built fail it; nothing in it says script-text expressions are fine.
#   - Every Code Quality range in make-it.md, resume-it.md, retrofit-it.md and DEVOPS-GUIDE.md reads Q01-Q16, and
#     resume-it's catch-up names Q16 as a security fix.
# A line scanner is a tripwire, not a YAML parser: a flow-style mapping (`{run: ...}`) or an anchor is not followed.
# Usage: test-workflow-no-expression-in-run.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on
# planted opposites. ROOT must be a git work tree (files come from `git ls-files`).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# the whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise)
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

BS=.claude/make-it/references/build-standards.md
MK=.claude/commands/make-it.md; RS=.claude/commands/resume-it.md; RF=.claude/commands/retrofit-it.md
DV=docs/DEVOPS-GUIDE.md
QG=.claude/make-it/scaffolds/fastapi-nextjs/.github/workflows/quality-gate.yml
has() { printf "%s" "$1" | gq -F -- "$2" || { echo "  missing: $2" | cut -c1-200; false; }; }

# The scanner. Prints "file:line: text" for every `${{` in script text, then "SCANNED <files> <script keys>" last.
cat > "$TMPD/scan.py" <<'PY'
import re, subprocess, sys

KEY = re.compile(r'^(\s*)(- +)?(run|script):(?:\s+(.*))?$')

def scan(lines, where):
    """lines: list of (lineno, text). Returns (hits, number of script keys seen)."""
    hits, keys, i = [], 0, 0
    while i < len(lines):
        no, text = lines[i]
        m = KEY.match(text)
        i += 1
        if not m:
            continue
        col = len(m.group(1)) + len(m.group(2) or "")
        name, value = m.group(3), (m.group(4) or "").strip()
        body = []
        while i < len(lines) and (lines[i][1].strip() == "" or len(lines[i][1]) - len(lines[i][1].lstrip()) > col):
            body.append(lines[i]); i += 1
        if name == "run" and value == "":
            # `defaults: run:` -- a mapping (shell, working-directory), not a script; its keys are still scanned
            i -= len(body)
            continue
        keys += 1
        if "${{" in value:
            hits.append(f"{where}:{no}: {text.strip()}")
        for bno, btext in body:
            if "${{" in btext:
                hits.append(f"{where}:{bno}: {btext.strip()}")
    return hits, keys

files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.splitlines()
hits, keys, scanned = [], 0, 0
for f in files:
    if re.search(r'(^|/)\.github/workflows/[^/]+\.ya?ml$', f):
        with open(f, encoding="utf-8") as fh:
            lines = list(enumerate(fh.read().split("\n"), 1))
        h, k = scan(lines, f); hits += h; keys += k; scanned += 1
    elif f.endswith(".md"):
        with open(f, encoding="utf-8") as fh:
            all_lines = fh.read().split("\n")
        fence, block = None, []
        for no, text in enumerate(all_lines, 1):
            s = text.strip()
            if fence is None:
                m = re.match(r'^(`{3,}|~{3,})\s*(yaml|yml)\s*$', s, re.I)
                if m:
                    fence, block = m.group(1), []
            elif s.startswith(fence) and s.strip("`~") == "":
                h, k = scan(block, f); hits += h; keys += k; scanned += 1
                fence = None
            else:
                block.append((no, text))
for h in hits:
    print(h)
print(f"SCANNED {scanned} {keys}")
PY
SCAN="$(python3 -I "$TMPD/scan.py")"
HITS="$(printf "%s\n" "$SCAN" | grep -v '^SCANNED ' || true)"
read -r _ NFILES NKEYS <<<"$(printf "%s\n" "$SCAN" | grep '^SCANNED ')"

# 1. the workflows
check "the scanner read workflows and script keys (not a vacuous pass: 10+ files, 40+ run/script keys)" \
  '[ "$NFILES" -ge 10 ] && [ "$NKEYS" -ge 40 ]'
check "the scaffold quality-gate workflow is one of the files read" 'git ls-files | gq -xF "$QG"'
check "no \${{ }} expression inside a run: or script: block in any shipped or templated workflow" \
  '[ -z "$HITS" ] || { printf "%s\n" "$HITS" | sed "s/^/  /" | cut -c1-200; false; }'
check "the attestation step still records the branch, from env: through the quoted \"\$BRANCH\"" \
  '[ "$(grep -cxF "          BRANCH: \${{ github.head_ref }}" "$QG")" = 1 ] && [ "$(grep -cxF "            --arg branch \"\$BRANCH\" \\" "$QG")" = 1 ] && [ "$(grep -cxF "            --arg commit \"\$COMMIT\" \\" "$QG")" = 1 ]'

# 2. the check
Q16="$(grep -E '^[*][*]Q16[*][*] ' "$BS" || true)"
check "Q16 exists once, is [Tier 0] [BLOCK] [SECURITY FIX], and is this check" \
  '[ "$(grep -cE "^[*][*]Q16[*][*] " "$BS")" = 1 ] && [ "$(grep -cF "**Q16** [Tier 0] [BLOCK] [SECURITY FIX] **No \`\${{ }}\` expression in a workflow step'"'"'s script text** -- " "$BS")" = 1 ]'
check "Q16 is the last Q check" '[ "$(grep -oE "^[*][*]Q[0-9]+[*][*]" "$BS" | tail -1)" = "**Q16**" ]'
check "Q16 says the rule" \
  'has "$Q16" "In every file under \`.github/workflows/\`, no \`\${{\` appears in a step'"'"'s script text: the value of \`run:\` (one line or a \`|\` or \`>\` block) or the \`script:\` input of \`actions/github-script\`."'
check "Q16 says why: GitHub pastes the value into the script, so text someone else chose runs as code" \
  'has "$Q16" "GitHub pastes an expression into the script before the shell runs it, so a value someone else chooses (a branch name, a pull request title, an issue or commit message) runs as code in the CI runner."'
check "Q16 says what is allowed" \
  'has "$Q16" "Expressions in \`env:\`, \`with:\`, \`if:\` and \`uses:\` are not script text and are fine."'
check "Q16 says the fix and that the output stays the same" \
  'has "$Q16" "**Fix:** move each expression out of the script into the step'"'"'s \`env:\` under an upper-case name and use the quoted variable instead (\`BRANCH: \${{ github.head_ref }}\` in \`env:\`, then \`\"\$BRANCH\"\` in the script; in \`script:\`, \`process.env.BRANCH\`), the way the scaffold'"'"'s \`quality-gate.yml\` does. The workflow'"'"'s output stays the same."'
check "Q16 says apps already built fail it and /resume-it presents it first" \
  'has "$Q16" "An app built before this check fails it: its \`quality-gate.yml\` puts the branch name into the attestation step'"'"'s shell command. /resume-it'"'"'s catch-up presents it first, as a security fix."'
check "Q16 says when it is N/A" 'has "$Q16" "N/A when the project has no \`.github/workflows/\`."'
check "nothing in Q16 allows script-text expressions or downgrades it" \
  '! printf "%s" "$Q16" | gq -E "(run:|script:|script text)[^.]*(are|is) (fine|allowed|ok)|\[WARN\]|\[FIX\]"'
check "build-standards still says once what [SECURITY FIX] means" \
  '[ "$(grep -cxF -- "- \`[SECURITY FIX]\` after the severity = the check closes a hole that is open now in apps already built." "$BS")" = 1 ]'

# 3. the ranges
check "make-it.md, retrofit-it.md, resume-it.md and DEVOPS-GUIDE.md read Q01-Q16" \
  'gq -F -- "- **Q01-Q16**: Code quality" "$MK" && gq -F -- "- **Q01-Q16**: Code quality" "$RF" && gq -F -- "**Code Quality (Q01-Q16):**" "$RS" && gq -F "code quality (Q01-Q16)" "$DV"'
check "no stale Q01-Q14 range is left in them" '[ "$(cat "$MK" "$RF" "$RS" "$DV" | grep -c "Q01-Q14")" = 0 ]'
check "resume-it's catch-up names Q16 as a security fix" \
  'gq -F "Q16 is a security fix: no \`\${{ }}\` expression in a step'"'"'s \`run:\` or \`script:\` text in \`.github/workflows/\` (\`[SECURITY FIX]\`, presented first)" "$RS"'

if [ -z "${1:-}" ]; then
  # Controls: each planted opposite must fail (or, for an allowed form, still pass) in a throwaway git copy.
  # only what this test reads: Markdown and workflow files
  mkcopy() { local d="$1"; rm -rf "$d"; mkdir -p "$d"
    git ls-files | grep -E '[.]md$|(^|/)[.]github/workflows/[^/]+[.]ya?ml$' | tar -cf - -T - | tar -xf - -C "$d"
    git -C "$d" init -q >/dev/null 2>&1; git -C "$d" add -A >/dev/null 2>&1; }
  # opp FILE PERL: the edit changes FILE and the copy fails
  opp() { local d="$TMPD/m"; mkcopy "$d"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  # same FILE PERL: the edit changes FILE and the copy still passes
  same() { local d="$TMPD/m"; mkcopy "$d"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && bash "$SELF" "$d" >/dev/null 2>&1; }
  check "(control) an unchanged copy passes, so each control below fails for its own edit" \
    'mkcopy "$TMPD/c"; bash "$SELF" "$TMPD/c" >/dev/null 2>&1'
  check "(control) fails with the branch name back in the attestation shell command" \
    'opp "$QG" "s/--arg branch \"\\\$BRANCH\"/--arg branch \"\\\${{ github.head_ref }}\"/"'
  check "(control) fails with an expression moved into a multi-line run block (the watermark step)" \
    'opp "$QG" "s/(          mv .make-it-framework)/          echo \"\\\${{ github.event.pull_request.title }}\"\n\$1/"'
  check "(control) fails with an expression in a one-line run in another scaffold workflow" \
    'd="$TMPD/m"; mkcopy "$d"; printf "%s\n" "on: pull_request" "jobs:" "  x:" "    runs-on: ubuntu-latest" "    steps:" "      - run: echo \${{ github.head_ref }}" > "$d/.claude/make-it/scaffolds/fastapi-nextjs/.github/workflows/other.yml"; git -C "$d" add -A >/dev/null 2>&1; ! bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with an expression in a github-script script: block" \
    'd="$TMPD/m"; mkcopy "$d"; printf "%s\n" "on: pull_request" "jobs:" "  x:" "    runs-on: ubuntu-latest" "    steps:" "      - uses: actions/github-script@v7" "        with:" "          script: |" "            console.log(\"\${{ github.event.issue.title }}\")" > "$d/.github/workflows/other.yml"; git -C "$d" add -A >/dev/null 2>&1; ! bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with an expression in a run block of a workflow template in a command (argo-it)" \
    'opp .claude/commands/argo-it.md "s/(          IMAGE_BASE_LC=\"\\\$\{IMAGE_BASE,,\}\")/          echo \"\\\${{ github.head_ref }}\"\n\$1/"'
  check "(control) still passes with an expression in if:, env: and with: (allowed)" \
    'same "$QG" "s/(      - name: Generate attestation\n)/      - name: allowed\n        if: \\\${{ github.head_ref != \x27\x27 }}\n        env:\n          X: \\\${{ github.head_ref }}\n        uses: actions\/checkout\@v4\n        with:\n          ref: \\\${{ github.head_ref }}\n\n\$1/"'
  check "(control) fails with the branch dropped from the attestation instead of moved to env:" \
    'opp "$QG" "s/          BRANCH: \\\$\{\{ github.head_ref \}\}\n//"'
  check "(control) fails with Q16 removed" 'opp "$BS" "s/^\*\*Q16\*\* [^\n]*\n\n?//m"'
  check "(control) fails with Q16 downgraded to [WARN], and with [SECURITY FIX] dropped" \
    'opp "$BS" "s/^\*\*Q16\*\* \[Tier 0\] \[BLOCK\]/**Q16** [Tier 0] [WARN]/m" && opp "$BS" "s/^\*\*Q16\*\* \[Tier 0\] \[BLOCK\] \[SECURITY FIX\]/**Q16** [Tier 0] [BLOCK]/m"'
  check "(control) fails with the rule reversed (script-text expressions are fine)" \
    'opp "$BS" "s/Expressions in \`env:\`, \`with:\`, \`if:\` and \`uses:\` are not script text and are fine[.]/Expressions in \`run:\` are fine too./"'
  check "(control) fails with the why dropped" \
    'opp "$BS" "s/GitHub pastes an expression into the script before the shell runs it, [^\n]*?CI runner[.] //"'
  check "(control) fails with a stale Q01-Q14 range back in make-it.md, and in resume-it.md" \
    'opp "$MK" "s/- \*\*Q01-Q16\*\*: Code quality/- **Q01-Q14**: Code quality/" && opp "$RS" "s/\*\*Code Quality \(Q01-Q16\):\*\*/**Code Quality (Q01-Q14):**/"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
