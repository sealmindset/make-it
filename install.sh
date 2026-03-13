#!/usr/bin/env bash
# install.sh -- Install /make-it skills into Claude Code
#
# Usage:
#   git clone https://github.com/sealmindset/make-it.git
#   cd make-it
#   bash install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
MAKEIT_DIR="${CLAUDE_DIR}/make-it"

echo "Installing /make-it skills into Claude Code..."
echo ""

# Create directories
mkdir -p "$COMMANDS_DIR"

# Copy skill entry points
echo "  Copying skill commands..."
cp "$REPO_DIR/.claude/commands/make-it.md" "$COMMANDS_DIR/"
cp "$REPO_DIR/.claude/commands/try-it.md" "$COMMANDS_DIR/"
cp "$REPO_DIR/.claude/commands/resume-it.md" "$COMMANDS_DIR/"

# Copy references, templates, and scaffolds
echo "  Copying references, templates, and scaffolds..."
rm -rf "$MAKEIT_DIR"
cp -r "$REPO_DIR/.claude/make-it" "$MAKEIT_DIR"

echo ""
echo "Installed successfully!"
echo ""
echo "  Skills installed:"
echo "    /make-it    -- Build a new app from scratch"
echo "    /try-it     -- Spin up and test your app"
echo "    /resume-it  -- Continue working on your app"
echo ""
echo "  To get started:"
echo "    cd ~/Documents/GitHub"
echo "    claude"
echo "    /make-it"
echo ""
