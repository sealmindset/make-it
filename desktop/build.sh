#!/usr/bin/env bash
# Builds dist/make-it-desktop/ from desktop/skills/*.
# Usage: build.sh [--check]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST="$REPO_ROOT/dist/make-it-desktop"
SKILLS_SRC="$SCRIPT_DIR/skills"
SKILLS="guardrails make-it debug-it nemo-it handoff"

CHECK=0
if [ "${1:-}" = "--check" ]; then
  CHECK=1
fi

# rewrite_file SRC DST BASENAMES
# Rewrites @~/.claude/make-it/<...>/<file> and @~/.claude/commands/<file> to
# references/<file> (dropping the @, Claude Code import syntax). Also rewrites
# plain-text ~/.claude/make-it/<...>/<file> mentions to references/<file>, but
# only when <file>'s basename is in the whitelist (i.e. actually copied into
# this skill's references/ folder) -- otherwise left alone for --check to flag.
rewrite_file() {
  local src="$1" dst="$2" basenames="$3"
  MAKE_IT_DESKTOP_BASENAMES="$basenames" perl -pe '
    BEGIN { %b = map { $_ => 1 } split(" ", $ENV{MAKE_IT_DESKTOP_BASENAMES}); }
    s{\@~/\.claude/make-it/[^\s)]+/([^/\s)]+)}{references/$1}g;
    s{\@~/\.claude/commands/([^/\s)]+)}{references/$1}g;
    s{~/\.claude/make-it/[^\s)]+/([^/\s)]+)}{ $b{$1} ? "references/$1" : $& }ge;
  ' "$src" > "$dst"
}

rm -rf "$DIST"
mkdir -p "$DIST/.claude-plugin"

VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
cat > "$DIST/.claude-plugin/plugin.json" <<EOF
{
  "name": "make-it-desktop",
  "version": "$VERSION",
  "description": "make-it guardrails for Claude Desktop and Cowork",
  "author": {
    "name": "sealmindset"
  }
}
EOF

MISSING_REFS=""

for name in $SKILLS; do
  src_dir="$SKILLS_SRC/$name"
  skill_md="$src_dir/SKILL.md"
  refs_file="$src_dir/refs.txt"
  out_dir="$DIST/skills/$name"
  refs_out="$out_dir/references"
  mkdir -p "$refs_out"

  if [ ! -f "$skill_md" ]; then
    echo "build.sh: missing $skill_md" >&2
    exit 1
  fi

  basenames=""
  if [ -f "$refs_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|'#'*) continue ;;
      esac
      src_path="$REPO_ROOT/$line"
      if [ ! -f "$src_path" ]; then
        MISSING_REFS="$MISSING_REFS
$name: $line (not found at $src_path)"
        continue
      fi
      basenames="$basenames $(basename "$line")"
    done < "$refs_file"
  fi

  if [ -f "$refs_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|'#'*) continue ;;
      esac
      src_path="$REPO_ROOT/$line"
      [ -f "$src_path" ] || continue
      rewrite_file "$src_path" "$refs_out/$(basename "$line")" "$basenames"
    done < "$refs_file"
  fi

  rewrite_file "$skill_md" "$out_dir/SKILL.md" "$basenames"
done

if [ -n "$MISSING_REFS" ]; then
  echo "build.sh: missing reference files listed in refs.txt:" >&2
  echo "$MISSING_REFS" >&2
  exit 1
fi

if [ "$CHECK" = "1" ]; then
  errors=""

  offenders="$(grep -rl '~/\.claude' "$DIST" 2>/dev/null || true)"
  if [ -n "$offenders" ]; then
    errors="$errors
Lingering ~/.claude references remain in:
$offenders"
  fi

  for name in $SKILLS; do
    out_dir="$DIST/skills/$name"
    refs_out="$out_dir/references"
    for f in "$out_dir/SKILL.md" "$refs_out"/*.md; do
      [ -f "$f" ] || continue
      refs="$(grep -oE 'references/[A-Za-z0-9_.-]+' "$f" 2>/dev/null | sort -u || true)"
      for ref in $refs; do
        base="$(basename "$ref")"
        if [ ! -f "$refs_out/$base" ]; then
          errors="$errors
$f links to $ref but $refs_out/$base does not exist"
        fi
      done
    done
  done

  bindirs="$(find "$DIST" -type d -name bin 2>/dev/null || true)"
  if [ -n "$bindirs" ]; then
    errors="$errors
Disallowed bin/ directories present:
$bindirs"
  fi

  if [ -n "$errors" ]; then
    echo "build.sh --check: FAILED" >&2
    echo "$errors" >&2
    exit 1
  fi
  echo "build.sh --check: OK"
fi
