#!/usr/bin/env bash
# install.sh -- Install or update /make-it skills into Claude Code
#
# Install from a cloned repo:
#   git clone https://github.com/sealmindset/make-it.git
#   cd make-it && bash install.sh
#
# Install via curl (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash
#
# Update (same command either way):
#   curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash
#   -- or from the cloned repo: git pull && bash install.sh
#   -- or from inside Claude Code: /make-it update

set -euo pipefail

GITHUB_REPO="sealmindset/make-it"
GITHUB_BRANCH="main"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
CLAUDE_DIR="${HOME}/.claude"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
MAKEIT_DIR="${CLAUDE_DIR}/make-it"
VERSION_FILE="${MAKEIT_DIR}/VERSION"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "  $*"; }
ok()    { echo "  + $*"; }
warn()  { echo "  WARN: $*"; }
fail()  { echo ""; echo "  ERROR: $*"; echo ""; exit 1; }

installed_version() {
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE" | tr -d '[:space:]'
  else
    echo "none"
  fi
}

remote_version() {
  curl -fsSL "${GITHUB_RAW}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown"
}

# ---------------------------------------------------------------------------
# Determine source: local repo or download from GitHub
# ---------------------------------------------------------------------------

detect_source() {
  # Check if we're running from inside the cloned repo
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

  if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/.claude/commands" ] && [ -d "$SCRIPT_DIR/.claude/make-it" ]; then
    SOURCE="local"
    REPO_DIR="$SCRIPT_DIR"
  else
    SOURCE="remote"
    REPO_DIR=""
  fi
}

# ---------------------------------------------------------------------------
# Download repo to a temp directory (for curl installs)
# ---------------------------------------------------------------------------

download_repo() {
  TMPDIR_REPO="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_REPO"' EXIT

  echo ""
  echo "Downloading latest /make-it skills..."
  echo ""

  # Check for git first (preferred -- gets everything cleanly)
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 --branch "$GITHUB_BRANCH" \
      "https://github.com/${GITHUB_REPO}.git" "$TMPDIR_REPO/make-it" 2>/dev/null \
      || fail "Could not download from GitHub. Check your internet connection."
    REPO_DIR="$TMPDIR_REPO/make-it"
  else
    # Fallback: download tarball (no git required)
    curl -fsSL "https://github.com/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz" \
      -o "$TMPDIR_REPO/make-it.tar.gz" \
      || fail "Could not download from GitHub. Check your internet connection."
    tar -xzf "$TMPDIR_REPO/make-it.tar.gz" -C "$TMPDIR_REPO" \
      || fail "Could not extract download."
    REPO_DIR="$TMPDIR_REPO/make-it-${GITHUB_BRANCH}"
  fi

  # Verify download
  [ -d "$REPO_DIR/.claude/commands" ] || fail "Download incomplete -- .claude/commands not found."
  [ -d "$REPO_DIR/.claude/make-it" ]  || fail "Download incomplete -- .claude/make-it not found."
}

# ---------------------------------------------------------------------------
# Install skills
# ---------------------------------------------------------------------------

install_skills() {
  mkdir -p "$COMMANDS_DIR"
  mkdir -p "$MAKEIT_DIR"

  # Auto-discover all skill files (*.md) in commands directory
  echo "  Copying skill commands..."
  SKILL_COUNT=0
  for cmd_file in "$REPO_DIR/.claude/commands/"*.md; do
    if [ -f "$cmd_file" ]; then
      cmd_name="$(basename "$cmd_file")"
      target="$COMMANDS_DIR/$cmd_name"
      # Remove existing symlinks (from dev-link.sh) before copying
      [ -L "$target" ] && rm "$target"
      cp "$cmd_file" "$target"
      ok "$cmd_name"
      SKILL_COUNT=$((SKILL_COUNT + 1))
    fi
  done

  if [ "$SKILL_COUNT" -eq 0 ]; then
    fail "No skill files found in $REPO_DIR/.claude/commands/"
  fi

  # Copy references, templates, and scaffolds
  echo "  Copying references, templates, and scaffolds..."
  # Remove symlink (from dev-link.sh) or directory before copying
  [ -L "$MAKEIT_DIR" ] && rm "$MAKEIT_DIR"
  [ -d "$MAKEIT_DIR" ] && rm -rf "$MAKEIT_DIR"
  cp -r "$REPO_DIR/.claude/make-it" "$MAKEIT_DIR"

  # Verify
  [ -d "$MAKEIT_DIR/references" ] || fail "Copy failed -- references directory missing."

  # Write version file
  if [ -f "$REPO_DIR/VERSION" ]; then
    cp "$REPO_DIR/VERSION" "$VERSION_FILE"
  else
    echo "0.0.0" > "$VERSION_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------

report() {
  local new_ver
  new_ver="$(installed_version)"

  echo ""
  if [ "$ACTION" = "update" ]; then
    echo "Updated successfully! (v${OLD_VERSION} -> v${new_ver})"
  else
    echo "Installed successfully! (v${new_ver})"
  fi

  echo ""
  echo "  Skills installed:"

  # Auto-list installed skills from the commands directory
  for cmd_file in "$COMMANDS_DIR/"*-it.md; do
    if [ -f "$cmd_file" ]; then
      cmd_name="$(basename "$cmd_file" .md)"
      # Generate description based on skill name
      case "$cmd_name" in
        make-it)     desc="Build a new app from scratch" ;;
        try-it)      desc="Spin up and test your app" ;;
        resume-it)   desc="Continue working on your app" ;;
        retrofit-it) desc="Upgrade an existing app with production foundations" ;;
        wrap-it)     desc="Wrap up your session and shut down cleanly" ;;
        argo-it)     desc="Deploy to Kubernetes via Argo CD" ;;
        nemo-it)     desc="Security attestation (scan any app)" ;;
        fix-it)      desc="Auto-fix security findings from /nemo-it" ;;
        *)           desc="Custom skill" ;;
      esac
      printf "    /%-14s -- %s\n" "$cmd_name" "$desc"
    fi
  done

  echo ""
  echo "  Files copied to:"
  echo "    $COMMANDS_DIR/*.md"
  echo "    $MAKEIT_DIR/ (references, templates, scaffolds)"
  echo ""
  echo "  IMPORTANT: Restart Claude Code for changes to take effect."
  echo ""
  echo "  To get started:"
  echo "    cd ~/Documents/GitHub"
  echo "    claude"
  echo "    /make-it"
  echo ""
  echo "  To update later:"
  echo "    /make-it update    (from inside Claude Code)"
  echo "    -- or --"
  echo "    curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/install.sh | bash"
  echo ""
}

# ---------------------------------------------------------------------------
# Check for updates (called by /make-it update)
# ---------------------------------------------------------------------------

check_update() {
  local current remote
  current="$(installed_version)"
  remote="$(remote_version)"

  if [ "$remote" = "unknown" ]; then
    echo "Could not check for updates. Verify your internet connection."
    return 1
  fi

  if [ "$current" = "$remote" ]; then
    echo "You're already on the latest version (v${current})."
    return 0
  fi

  echo "Update available: v${current} -> v${remote}"
  return 2
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  # Determine if this is an install or update
  OLD_VERSION="$(installed_version)"
  if [ "$OLD_VERSION" = "none" ]; then
    ACTION="install"
  else
    ACTION="update"
  fi

  echo ""
  if [ "$ACTION" = "update" ]; then
    echo "Updating /make-it skills (currently v${OLD_VERSION})..."
  else
    echo "Installing /make-it skills into Claude Code..."
  fi
  echo ""

  # Get the source files
  detect_source
  if [ "$SOURCE" = "remote" ]; then
    download_repo
  fi

  # Install
  install_skills

  # Report
  report
}

# Support being called with "check" argument (used by /make-it update)
if [ "${1:-}" = "check" ]; then
  check_update
  exit $?
fi

main
