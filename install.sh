#!/usr/bin/env bash
# install.sh -- Install /make-it skills into Claude Code
#
# Usage:
#   git clone https://github.com/sealmindset/make-it.git
#   cd make-it
#   bash install.sh
#
# Or one-liner:
#   git clone https://github.com/sealmindset/make-it.git && cd make-it && bash install.sh

set -euo pipefail

# Resolve the repo directory (where this script lives)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
MAKEIT_DIR="${CLAUDE_DIR}/make-it"

echo ""
echo "Installing /make-it skills into Claude Code..."
echo ""

# Verify we're running from the cloned repo
if [ ! -d "$REPO_DIR/.claude/commands" ]; then
  echo "ERROR: Cannot find .claude/commands in $REPO_DIR"
  echo ""
  echo "Make sure you've cloned the repo and are running from inside it:"
  echo "  git clone https://github.com/sealmindset/make-it.git"
  echo "  cd make-it"
  echo "  bash install.sh"
  exit 1
fi

if [ ! -d "$REPO_DIR/.claude/make-it" ]; then
  echo "ERROR: Cannot find .claude/make-it in $REPO_DIR"
  echo "The repo may be incomplete. Try cloning again."
  exit 1
fi

# Create target directories
mkdir -p "$COMMANDS_DIR"
mkdir -p "$MAKEIT_DIR"

# Copy skill entry points
echo "  Copying skill commands..."
for cmd in make-it.md try-it.md resume-it.md retrofit-it.md; do
  if [ -f "$REPO_DIR/.claude/commands/$cmd" ]; then
    cp "$REPO_DIR/.claude/commands/$cmd" "$COMMANDS_DIR/"
    echo "    + $cmd"
  else
    echo "    WARN: $cmd not found in repo, skipping"
  fi
done

# Copy references, templates, and scaffolds
echo "  Copying references, templates, and scaffolds..."
rm -rf "$MAKEIT_DIR"
cp -r "$REPO_DIR/.claude/make-it" "$MAKEIT_DIR"

# Verify the copy worked
if [ ! -d "$MAKEIT_DIR/references" ]; then
  echo ""
  echo "ERROR: Copy failed -- $MAKEIT_DIR/references does not exist."
  echo "Try running manually:"
  echo "  mkdir -p ~/.claude/make-it"
  echo "  cp -r $REPO_DIR/.claude/make-it/* ~/.claude/make-it/"
  exit 1
fi

echo ""
echo "Installed successfully!"
echo ""
echo "  Skills installed:"
echo "    /make-it      -- Build a new app from scratch"
echo "    /try-it       -- Spin up and test your app"
echo "    /resume-it    -- Continue working on your app"
echo "    /retrofit-it  -- Upgrade an existing app with production foundations"
echo ""
echo "  Files copied to:"
echo "    $COMMANDS_DIR/make-it.md"
echo "    $COMMANDS_DIR/try-it.md"
echo "    $COMMANDS_DIR/resume-it.md"
echo "    $MAKEIT_DIR/ (references, templates, scaffolds)"
echo ""
echo "  IMPORTANT: Restart Claude Code for the skills to take effect."
echo ""
echo "  To get started:"
echo "    cd ~/Documents/GitHub"
echo "    claude"
echo "    /make-it"
echo ""
