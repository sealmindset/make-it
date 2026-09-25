#!/usr/bin/env bash
# Self-check for desktop/build.sh: determinism, --check, and import rewrite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$SCRIPT_DIR/build.sh"
FIXTURE="$SCRIPT_DIR/skills/guardrails/SKILL.md"
FIXTURE_BACKUP="$(mktemp)"
TMP1="$(mktemp -d)"
TMP2="$(mktemp -d)"

cp "$FIXTURE" "$FIXTURE_BACKUP"
cleanup() {
  cp "$FIXTURE_BACKUP" "$FIXTURE"
  rm -f "$FIXTURE_BACKUP"
  rm -rf "$TMP1" "$TMP2"
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

echo "== import rewrite fixture =="
printf '\nSee @~/.claude/make-it/references/guardrails.md for details.\n' >> "$FIXTURE"
bash "$BUILD"
OUT="$REPO_ROOT/dist/make-it-desktop/skills/guardrails/SKILL.md"
if grep -q '@~/\.claude' "$OUT"; then
  echo "FAIL: unrewritten @~/.claude import remains in $OUT" >&2
  exit 1
fi
if ! grep -q 'references/guardrails.md' "$OUT"; then
  echo "FAIL: expected rewritten references/guardrails.md not found in $OUT" >&2
  exit 1
fi
echo "OK: planted @~/.claude/make-it/references/guardrails.md import was rewritten"

cp "$FIXTURE_BACKUP" "$FIXTURE"
bash "$BUILD" >/dev/null
echo "ALL CHECKS PASSED"
