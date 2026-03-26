#!/usr/bin/env bash
# dev-link.sh -- Symlink the repo into ~/.claude for development
#
# Instead of copying files (like install.sh does), this creates symlinks
# so that edits in the repo are immediately live in Claude Code.
# Run this once after cloning; after that, `git pull` is all you need.
#
# Usage:
#   cd ~/Documents/GitHub/make-it
#   bash dev-link.sh
#
# To undo (go back to installed copies):
#   bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
MAKEIT_DIR="${CLAUDE_DIR}/make-it"

# Verify we're in the repo
if [ ! -d "$SCRIPT_DIR/.claude/commands" ] || [ ! -d "$SCRIPT_DIR/.claude/make-it" ]; then
  echo "ERROR: Run this from the make-it repo root."
  exit 1
fi

echo ""
echo "Linking /make-it skills for development..."
echo ""

# Ensure target directories exist
mkdir -p "$COMMANDS_DIR"

# Link make-it references/templates/scaffolds directory
if [ -L "$MAKEIT_DIR" ]; then
  echo "  ~/.claude/make-it is already a symlink -- replacing"
  rm "$MAKEIT_DIR"
elif [ -d "$MAKEIT_DIR" ]; then
  echo "  ~/.claude/make-it is a directory -- removing copy"
  rm -rf "$MAKEIT_DIR"
fi
ln -s "$SCRIPT_DIR/.claude/make-it" "$MAKEIT_DIR"
echo "  + ~/.claude/make-it -> $SCRIPT_DIR/.claude/make-it"

# Link each skill command file
for cmd_file in "$SCRIPT_DIR/.claude/commands/"*-it.md; do
  if [ -f "$cmd_file" ]; then
    name="$(basename "$cmd_file")"
    target="$COMMANDS_DIR/$name"
    if [ -L "$target" ] || [ -f "$target" ]; then
      rm "$target"
    fi
    ln -s "$cmd_file" "$target"
    echo "  + ~/.claude/commands/$name -> $cmd_file"
  fi
done

echo ""
echo "Done! Repo is now live-linked to Claude Code."
echo "  - Edits in the repo take effect immediately"
echo "  - git pull syncs collaborator changes instantly"
echo "  - To undo: bash install.sh (reverts to copies)"
echo ""
