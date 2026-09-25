#!/usr/bin/env bash
# Publishes the built make-it-desktop plugin into a local clone of the private
# marketplace repo (sealmindset/make-it-desktop). Only ever writes inside that
# clone -- it never runs git commit/push.
#
# Usage: desktop/publish.sh <path-to-make-it-desktop-clone>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "publish.sh: usage: desktop/publish.sh <path-to-make-it-desktop-clone>" >&2
  exit 1
fi

if [ ! -d "$TARGET" ]; then
  echo "publish.sh: $TARGET is not a directory" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd -P)"

case "$TARGET" in
  "$REPO_ROOT"|"$REPO_ROOT"/*)
    echo "publish.sh: $TARGET is inside the make-it repo ($REPO_ROOT)." >&2
    echo "publish.sh: pass the path to a separate local clone of the make-it-desktop marketplace repo." >&2
    exit 1
    ;;
esac

if [ -f "$TARGET/.claude/commands/make-it.md" ]; then
  echo "publish.sh: $TARGET looks like the make-it repo itself (has .claude/commands/make-it.md)." >&2
  echo "publish.sh: pass the path to a separate local clone of the make-it-desktop marketplace repo." >&2
  exit 1
fi

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "publish.sh: $TARGET is not a git work tree." >&2
  echo "publish.sh: pass the path to a local clone of the make-it-desktop marketplace repo." >&2
  exit 1
fi

# Any make-it checkout (not just this one) is never a publish target.
if [ -f "$(git -C "$TARGET" rev-parse --show-toplevel)/.claude/commands/make-it.md" ]; then
  echo "publish.sh: $TARGET is inside a make-it checkout, not the marketplace clone." >&2
  exit 1
fi

for d in "$TARGET/plugins" "$TARGET/plugins/make-it-desktop" "$TARGET/.claude-plugin"; do
  if [ -L "$d" ]; then
    echo "publish.sh: $d is a symlink -- refusing to write through it." >&2
    exit 1
  fi
done

echo "== building the plugin =="
bash "$SCRIPT_DIR/build.sh"

VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
PLUGIN_DST="$TARGET/plugins/make-it-desktop"

echo "== syncing dist/make-it-desktop into $PLUGIN_DST =="
rm -rf "$PLUGIN_DST"
mkdir -p "$TARGET/plugins"
cp -R "$REPO_ROOT/dist/make-it-desktop" "$PLUGIN_DST"

echo "== writing $TARGET/.claude-plugin/marketplace.json (plugin version $VERSION) =="
mkdir -p "$TARGET/.claude-plugin"
cat > "$TARGET/.claude-plugin/marketplace.json" <<EOF
{
  "name": "make-it-desktop",
  "description": "make-it guardrails for Claude Desktop and Cowork",
  "owner": {
    "name": "sealmindset"
  },
  "plugins": [
    {
      "name": "make-it-desktop",
      "source": "./plugins/make-it-desktop",
      "description": "make-it guardrails for Claude Desktop and Cowork",
      "version": "$VERSION"
    }
  ]
}
EOF

if command -v claude >/dev/null 2>&1; then
  echo "== validating $TARGET =="
  claude plugin validate "$TARGET"
else
  echo "== claude CLI not found on PATH -- skipping validation =="
fi

echo "== done: $TARGET is ready to commit and push =="
