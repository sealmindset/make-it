#!/usr/bin/env bash
# Self-check for desktop/build.sh: determinism, --check, and import/mention rewrite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$SCRIPT_DIR/build.sh"
TMP1="$(mktemp -d)"
TMP2="$(mktemp -d)"
TMPSKILLS="$(mktemp -d)"
TMPSKILLS_NEG="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP1" "$TMP2" "$TMPSKILLS" "$TMPSKILLS_NEG"
}
trap cleanup EXIT

echo "== determinism: build twice, diff =="
bash "$BUILD"
cp -R "$REPO_ROOT/dist/make-it-desktop" "$TMP1/out"
bash "$BUILD"
cp -R "$REPO_ROOT/dist/make-it-desktop" "$TMP2/out"
diff -r "$TMP1/out" "$TMP2/out"
echo "OK: two builds are byte-identical"

echo "== --check mode =="
bash "$BUILD" --check
echo "OK: --check passed on clean build"

assert_line() {
  local file="$1" expected="$2"
  if ! grep -qF "$expected" "$file"; then
    echo "FAIL: expected line not found in $file: $expected" >&2
    exit 1
  fi
}

echo "== rewrite fixture (temp copy of desktop/skills; tracked files untouched) =="
cp -R "$SCRIPT_DIR/skills" "$TMPSKILLS/skills"
FIXTURE="$TMPSKILLS/skills/guardrails/SKILL.md"
cat >> "$FIXTURE" <<'EOF'

Imports:
@~/.claude/make-it/references/guardrails.md

Plain mentions:
See `~/.claude/make-it/references/guardrails.md`. for details.
Check ~/.claude/make-it/VERSION for the installed version.
Also see ~/.claude/make-it/references/build-standards.md for background.
EOF

MAKE_IT_DESKTOP_SKILLS_DIR="$TMPSKILLS/skills" bash "$BUILD"
OUT="$REPO_ROOT/dist/make-it-desktop/skills/guardrails/SKILL.md"

# The @ import line, rewritten to a standalone line -- distinct from the
# backticked plain-mention assertion below.
if [ "$(grep -A1 -F 'Imports:' "$OUT" | tail -1)" != 'references/guardrails.md' ]; then
  echo "FAIL: @~/.claude import line not rewritten to a standalone 'references/guardrails.md' line in $OUT" >&2
  exit 1
fi
assert_line "$OUT" '`references/guardrails.md`.'
assert_line "$OUT" 'claude-code:make-it/VERSION'
assert_line "$OUT" 'claude-code:make-it/references/build-standards.md'
if grep -q '@references/guardrails\|@claude-code:' "$OUT"; then
  echo "FAIL: rewrite left a stray @ attached to the replacement in $OUT" >&2
  exit 1
fi
echo "OK: import, backticked mention, and uncopied mentions all rewrote correctly"

if ! MAKE_IT_DESKTOP_SKILLS_DIR="$TMPSKILLS/skills" bash "$BUILD" --check; then
  echo "FAIL: --check should pass -- claude-code:make-it/references/build-standards.md is not a real references/ link" >&2
  exit 1
fi
echo "OK: --check does not false-flag the claude-code: fallback as a references/ link"

echo "== negative fixture: uncopied @ import must be left as-is, --check must fail =="
cp -R "$SCRIPT_DIR/skills" "$TMPSKILLS_NEG/skills"
FIXTURE_NEG="$TMPSKILLS_NEG/skills/guardrails/SKILL.md"
# @~/.claude/commands/debug-it.md is deliberately NOT added to refs.txt: an
# uncopied import must be left as-is so --check flags it (forces refs.txt
# completeness).
printf '\n@~/.claude/commands/debug-it.md\n' >> "$FIXTURE_NEG"

MAKE_IT_DESKTOP_SKILLS_DIR="$TMPSKILLS_NEG/skills" bash "$BUILD"
OUT_NEG="$REPO_ROOT/dist/make-it-desktop/skills/guardrails/SKILL.md"
assert_line "$OUT_NEG" '@~/.claude/commands/debug-it.md'

CHECK_ERR="$(mktemp)"
if MAKE_IT_DESKTOP_SKILLS_DIR="$TMPSKILLS_NEG/skills" bash "$BUILD" --check 2>"$CHECK_ERR"; then
  echo "FAIL: --check should have failed on the uncopied @~/.claude/commands/debug-it.md import" >&2
  rm -f "$CHECK_ERR"
  exit 1
fi
if ! grep -q 'commands/debug-it.md' "$CHECK_ERR"; then
  echo "FAIL: --check error output does not mention commands/debug-it.md:" >&2
  cat "$CHECK_ERR" >&2
  rm -f "$CHECK_ERR"
  exit 1
fi
rm -f "$CHECK_ERR"
echo "OK: --check correctly failed on the uncopied import (refs.txt completeness enforced)"

if ! bash "$BUILD" >/dev/null; then
  echo "FAIL: final restore build of the real desktop/skills failed" >&2
  exit 1
fi
echo "ALL CHECKS PASSED"
