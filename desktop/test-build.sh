#!/usr/bin/env bash
# Self-check for desktop/build.sh: determinism, --check, and import/mention rewrite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$SCRIPT_DIR/build.sh"
TMP1="$(mktemp -d)"
TMP2="$(mktemp -d)"
TMPSKILLS="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP1" "$TMP2" "$TMPSKILLS"
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

echo "== rewrite fixture (temp copy of desktop/skills; tracked files untouched) =="
cp -R "$SCRIPT_DIR/skills" "$TMPSKILLS/skills"
FIXTURE="$TMPSKILLS/skills/guardrails/SKILL.md"
# @~/.claude/commands/debug-it.md is deliberately NOT added to refs.txt: an
# uncopied import must be left as-is so --check flags it (forces refs.txt
# completeness) -- exercised below.
cat >> "$FIXTURE" <<'EOF'

Imports:
@~/.claude/make-it/references/guardrails.md
@~/.claude/commands/debug-it.md

Plain mentions:
See `~/.claude/make-it/references/guardrails.md`. for details.
Check ~/.claude/make-it/VERSION for the installed version.
EOF

MAKE_IT_DESKTOP_SKILLS_DIR="$TMPSKILLS/skills" bash "$BUILD"
OUT="$REPO_ROOT/dist/make-it-desktop/skills/guardrails/SKILL.md"

assert_line() {
  local expected="$1"
  if ! grep -qF "$expected" "$OUT"; then
    echo "FAIL: expected line not found in $OUT: $expected" >&2
    exit 1
  fi
}

assert_line 'Imports:'
assert_line 'references/guardrails.md'
assert_line '`references/guardrails.md`.'
assert_line 'claude-code:make-it/VERSION'
if grep -q '@references/guardrails\|@claude-code:' "$OUT"; then
  echo "FAIL: rewrite left a stray @ attached to the replacement in $OUT" >&2
  exit 1
fi
echo "OK: import, backticked mention, and uncopied mention all rewrote correctly"

if MAKE_IT_DESKTOP_SKILLS_DIR="$TMPSKILLS/skills" bash "$BUILD" --check >/dev/null 2>&1; then
  echo "FAIL: --check should have failed on the uncopied @~/.claude/commands/debug-it.md import" >&2
  exit 1
fi
if ! grep -q 'debug-it.md' "$OUT"; then
  echo "FAIL: uncopied import basename missing from $OUT" >&2
  exit 1
fi
grep -q '@~/\.claude/commands/debug-it\.md' "$OUT"
echo "OK: --check correctly failed on the uncopied import (refs.txt completeness enforced)"

bash "$BUILD" >/dev/null
echo "ALL CHECKS PASSED"
