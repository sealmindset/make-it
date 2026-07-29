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
MANIFEST_FILE="${MAKEIT_DIR}/CONTENT_MANIFEST"
CONTENT_SCRIPT="${MAKEIT_DIR}/scripts/content-manifest.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "  $*"; }
ok()    { echo "  + $*"; }
warn()  { echo "  WARN: $*"; }
fail()  { echo ""; echo "  ERROR: $*"; echo ""; exit 1; }

# abs_path resolves a path to absolute form without requiring it to exist
# (only its parent must exist). Used to compare source and destination.
abs_path() {
  local d b
  d="$(dirname "$1")"
  b="$(basename "$1")"
  if [ -d "$d" ]; then
    printf '%s/%s\n' "$(cd "$d" && pwd)" "$b"
  else
    printf '%s\n' "$1"
  fi
}

same_path() { [ "$(abs_path "$1")" = "$(abs_path "$2")" ]; }

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

# Download the published content manifest to $1. Returns non-zero if unavailable.
fetch_remote_manifest() {
  curl -fsSL "${GITHUB_RAW}/CONTENT_MANIFEST" -o "$1" 2>/dev/null && [ -s "$1" ]
}

# Compare the INSTALLED files against a manifest.
#   0 = content matches      1 = drift detected      2 = cannot determine
# On drift, the per-file detail from the verifier is echoed to stdout.
CONTENT_DETAIL=""
content_status() {
  local manifest="$1" rc=0
  [ -f "$manifest" ] || return 2
  [ -f "$CONTENT_SCRIPT" ] || return 2
  [ -d "$CLAUDE_DIR" ] || return 2

  CONTENT_DETAIL="$(bash "$CONTENT_SCRIPT" verify "$manifest" "$CLAUDE_DIR" 2>&1)" || rc=$?
  # The verifier exits 2 only when it cannot run at all (bad args / missing paths);
  # 1 means it ran and found drift. Keep those outcomes distinct.
  case "$rc" in
    0) return 0 ;;
    2) return 2 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Determine source: local repo or download from GitHub
# ---------------------------------------------------------------------------

detect_source() {
  # Check if we're running from inside the cloned repo.
  #
  # BASH_SOURCE[0] is only meaningful when this script is a real FILE on disk.
  # Under `curl ... | bash` there is no file: BASH_SOURCE is unset and $0 is
  # "bash", so `dirname` yields "." and SCRIPT_DIR would silently become the
  # CALLER'S cwd. If that cwd happens to hold a .claude/commands +
  # .claude/make-it pair -- which $HOME always does once installed -- we would
  # treat the install TARGET as the source and copy it onto itself.
  # So: only trust SCRIPT_DIR when we can prove we are a file, and never accept
  # $HOME or ~/.claude as a source tree.
  local src="${BASH_SOURCE[0]:-}"
  if [ -n "$src" ] && [ -f "$src" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$src")" 2>/dev/null && pwd || echo "")"
  else
    SCRIPT_DIR=""
  fi

  if [ -n "$SCRIPT_DIR" ] \
    && [ "$SCRIPT_DIR" != "$HOME" ] \
    && [ "$SCRIPT_DIR" != "$CLAUDE_DIR" ] \
    && [ -d "$SCRIPT_DIR/.claude/commands" ] \
    && [ -d "$SCRIPT_DIR/.claude/make-it" ]; then
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
  # Refuse to install a source tree onto itself. Without this, a mis-detected
  # REPO_DIR (e.g. $HOME) makes the copies below self-referential -- and the
  # `rm -rf "$MAKEIT_DIR"` further down would DELETE the very directory it is
  # about to copy from, destroying the installation. Fail loudly instead.
  if same_path "$REPO_DIR/.claude/commands" "$COMMANDS_DIR" \
    || same_path "$REPO_DIR/.claude/make-it" "$MAKEIT_DIR"; then
    fail "Refusing to install: source and destination are the same directory.
    source: $REPO_DIR
    target: $CLAUDE_DIR
  This means the installer could not tell where it was run from.
  Re-run from a real clone (bash install.sh), or:
    cd /tmp && curl -fsSL ${GITHUB_RAW}/install.sh | bash"
  fi

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

  # Install the content manifest so `check_update` can detect drift later, and
  # confirm the COMMITTED manifest actually describes the tree we just installed.
  # A stale manifest is exactly how a content-only release goes unnoticed, so say
  # so loudly rather than shipping a manifest that lies.
  if [ -f "$REPO_DIR/CONTENT_MANIFEST" ]; then
    cp "$REPO_DIR/CONTENT_MANIFEST" "$MANIFEST_FILE"
    if [ -f "$CONTENT_SCRIPT" ]; then
      local fresh
      fresh="$(mktemp)"
      if bash "$CONTENT_SCRIPT" generate "$REPO_DIR" >"$fresh" 2>/dev/null; then
        if ! diff -q "$REPO_DIR/CONTENT_MANIFEST" "$fresh" >/dev/null 2>&1; then
          warn "CONTENT_MANIFEST is out of date for this source tree."
          warn "Regenerate and commit it:"
          warn "  .claude/make-it/scripts/content-manifest.sh generate . > CONTENT_MANIFEST"
        fi
      fi
      rm -f "$fresh"
    fi
  else
    warn "No CONTENT_MANIFEST in source -- update checks will be version-only."
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
        demo-it)     desc="Demo tenant lifecycle for prospect onboarding" ;;
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
  local current remote tmp_manifest cstat
  current="$(installed_version)"
  remote="$(remote_version)"

  if [ "$remote" = "unknown" ]; then
    echo "Could not check for updates. Verify your internet connection."
    return 1
  fi

  # A version difference is decisive on its own.
  if [ "$current" != "$remote" ]; then
    echo "Update available: v${current} -> v${remote}"
    return 2
  fi

  # Same version string. That is NOT proof of being current: a release can ship
  # changed content without bumping VERSION, and local files can be edited after
  # install. Compare actual file content against the published manifest.
  tmp_manifest="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_manifest'" RETURN

  if ! fetch_remote_manifest "$tmp_manifest"; then
    echo "You're on v${current} (matching the latest published version)."
    echo "Note: could not fetch the content manifest, so this is a version-only"
    echo "check -- content changes shipped without a version bump would be missed."
    return 0
  fi

  cstat=0
  content_status "$tmp_manifest" || cstat=$?
  case "$cstat" in
    0)
      echo "You're already on the latest version (v${current}), and all content matches."
      return 0
      ;;
    1)
      echo "Update available: content differs from the published v${remote} release."
      echo "(Version strings match at v${current} -- this was found by content hash.)"
      [ -n "$CONTENT_DETAIL" ] && printf '%s\n' "$CONTENT_DETAIL"
      return 2
      ;;
    *)
      echo "You're on v${current} (matching the latest published version)."
      echo "Note: could not verify file content (verifier unavailable) -- this is a"
      echo "version-only check. Re-running the installer will refresh it."
      return 0
      ;;
  esac
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
