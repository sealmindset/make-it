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

# Download the published verifier to $1. Returns non-zero if unavailable.
#
# The check must NOT depend on the verifier already being installed: an install
# that predates this feature has no verifier, which is exactly the install whose
# content is most likely stale. Depending on the local copy there would fall back
# to a version-only check and hide the update. So fetch it.
fetch_remote_verifier() {
  curl -fsSL "${GITHUB_RAW}/.claude/make-it/scripts/content-manifest.sh" -o "$1" 2>/dev/null && [ -s "$1" ]
}

# Compare the INSTALLED files against a manifest.
#   0 = content matches      1 = drift detected      2 = cannot determine
# On drift, the per-file detail from the verifier is echoed to stdout.
CONTENT_DETAIL=""
content_status() {
  local manifest="$1" verifier="${2:-}" rc=0
  [ -f "$manifest" ] || return 2
  [ -d "$CLAUDE_DIR" ] || return 2

  # Prefer a freshly-fetched verifier; fall back to the installed one.
  [ -n "$verifier" ] && [ -f "$verifier" ] || verifier="$CONTENT_SCRIPT"
  [ -f "$verifier" ] || return 2

  CONTENT_DETAIL="$(bash "$verifier" verify "$manifest" "$CLAUDE_DIR" 2>&1)" || rc=$?
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
# /threats-it moved to its own repository (https://github.com/sealmindset/threats-it)
# ---------------------------------------------------------------------------

# An update removes make-it's old copy -- ~/.claude/commands/threats-it.md and ~/.claude/make-it/threats-it/ --
# but only the files that are still exactly what make-it installed (the CONTENT_MANIFEST of that install says
# so). A file someone changed is kept where it is and named. A command the separate /threats-it installer wrote
# (its ~/.claude/threats-it-support/INSTALLED records it) is not make-it's and is left alone. The organisation
# profile in ~/.claude/threats-it/ is never read, moved or removed.
THREATS_NOTE=""
THREATS_KEPT=()
THREATS_DROP_CMD=0
THREATS_INSTALL="curl -fsSL https://raw.githubusercontent.com/sealmindset/threats-it/main/install.sh | bash"
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
# was_installed FILE PATH-IN-MANIFEST MANIFEST: 0 when the manifest records exactly this file's content
was_installed() { [ -f "$3" ] && [ -f "$1" ] && [ ! -L "$1" ] && [ "$(awk -v p="$2" -v h="$(sha256 "$1")" '$2 == p && $1 == h' "$3" | grep -c .)" -gt 0 ]; }
# Call after the new make-it folder is built in $1 and before it is swapped in: kept files are copied into it.
plan_threats_it_retirement() {
  local new="$1" old="$MAKEIT_DIR/CONTENT_MANIFEST" cmd="$COMMANDS_DIR/threats-it.md" f rel removed=0 separate=0
  [ -f "$CLAUDE_DIR/threats-it-support/INSTALLED" ] && separate=1
  if [ -e "$cmd" ] || [ -L "$cmd" ]; then
    if was_installed "$cmd" "commands/threats-it.md" "$CLAUDE_DIR/threats-it-support/INSTALLED"; then :   # the separate install's
    elif was_installed "$cmd" "commands/threats-it.md" "$old"; then THREATS_DROP_CMD=1; removed=1
    else THREATS_KEPT+=("$cmd"); fi
  fi
  if [ -d "$MAKEIT_DIR/threats-it" ] && [ ! -L "$MAKEIT_DIR" ]; then
    while IFS= read -r f; do
      rel="${f#"$MAKEIT_DIR"/}"
      case "$rel" in */__pycache__/*) continue ;; esac   # written by Python when the scripts ran, not by anyone
      if was_installed "$f" "make-it/$rel" "$old"; then removed=1; continue; fi
      mkdir -p "$new/$(dirname "$rel")" && cp -pP "$f" "$new/$rel" \
        || fail "Could not keep your changed file $f. Nothing was changed."
      THREATS_KEPT+=("$f")
    done < <(find "$MAKEIT_DIR/threats-it" \( -type f -o -type l \) | LC_ALL=C sort)
  fi
  # say what happened this run: nothing once the separate install is there, or once nothing is left to do
  # (one case speaks beside it: a make-it update from before the move had put make-it's command back over the
  # separate install's, and that command is gone now, so the separate installer must be run again)
  if [ "$separate" = 1 ]; then
    [ "$THREATS_DROP_CMD" = 1 ] && THREATS_NOTE="make-it removed its old copy of the /threats-it command, which had replaced yours; put yours back with: $THREATS_INSTALL"
    return 0
  fi
  if [ "$removed" = 1 ]; then
    THREATS_NOTE="/threats-it has moved to its own repository, so make-it removed its old copy; to keep using it, install it with: $THREATS_INSTALL"
    [ "${#THREATS_KEPT[@]}" -eq 0 ] || THREATS_NOTE="$THREATS_NOTE (kept, because they were changed or added: ${THREATS_KEPT[*]})"
  elif [ "${#THREATS_KEPT[@]}" -gt 0 ]; then
    THREATS_NOTE="/threats-it has moved to its own repository; make-it kept these files of its old copy because they were changed or added: ${THREATS_KEPT[*]}. To keep using it, install it with: $THREATS_INSTALL"
  fi
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
  # Keep the answers the hostile-code check remembered (cleared files, "this project is mine",
  # "stop"): they live in this folder, and replacing it used to delete them on every update.
  # The new folder is built beside the old one, answers included, and only then swapped in: a
  # failure on the way leaves the old folder, and its answers, where they were.
  NEW_DIR="$MAKEIT_DIR.new.$$"
  rm -rf "$NEW_DIR"
  cp -r "$REPO_DIR/.claude/make-it" "$NEW_DIR"
  # (and whether the user removed the force-push guard: force-push-guard.state)
  for kept in "$MAKEIT_DIR"/hostile-code-*.json "$MAKEIT_DIR"/force-push-guard.state; do
    # an ordinary file only: a link is not followed, and its answers are asked again
    if [ -f "$kept" ] && [ ! -L "$kept" ]; then
      cp -p "$kept" "$NEW_DIR"/ || { rm -rf "$NEW_DIR"; fail "Could not keep $(basename "$kept"). Nothing was changed."; }
    fi
  done
  plan_threats_it_retirement "$NEW_DIR"
  [ -L "$MAKEIT_DIR" ] && rm "$MAKEIT_DIR"
  [ -d "$MAKEIT_DIR" ] && rm -rf "$MAKEIT_DIR"
  mv "$NEW_DIR" "$MAKEIT_DIR"
  [ "$THREATS_DROP_CMD" = 1 ] && rm -f "$COMMANDS_DIR/threats-it.md"

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
# The guard that refuses Claude's `git push --force` (a Claude Code hook)
# ---------------------------------------------------------------------------

# Adds ~/.claude/make-it/hooks/no-force-push.sh to ~/.claude/settings.json as a PreToolUse hook. The
# helper merges: everything already in the file stays, a copy is kept before the first change, a
# second install adds nothing, an older make-it entry is replaced. A file it can't read is left
# alone, and the install says so. Once the user removes the guard (--remove-force-push-guard, or by
# deleting it from settings.json), later installs leave it out until --add-force-push-guard.
GUARD_FLAG="${MAKEIT_FORCE_PUSH_GUARD:-}"
GUARD_NOTE=""
REMOVE_HOW="curl -fsSL ${GITHUB_RAW}/install.sh | bash -s -- --remove-force-push-guard"

# python3 that really runs. On a Mac without the developer tools, /usr/bin/python3 is a stand-in
# that opens an install dialog instead of running, so it is not even started there.
python_works() {
  command -v python3 >/dev/null 2>&1 || return 1
  if [ "$(uname -s)" = Darwin ] && [ "$(command -v python3)" = /usr/bin/python3 ] \
    && ! xcode-select -p >/dev/null 2>&1; then
    return 1
  fi
  python3 -c '' >/dev/null 2>&1
}

install_force_push_guard() {
  local hook="$MAKEIT_DIR/hooks/no-force-push.sh" q out mode=auto
  case "$GUARD_FLAG" in add) mode=add ;; remove) mode=remove ;; esac
  [ -f "$hook" ] || fail "The guard that stops git push --force is missing from this download ($hook)."
  if ! python_works; then
    GUARD_NOTE="1 step not done: the guard that stops Claude from running git push --force was not added, because Python 3 isn't working on this computer. Install Python 3 (on a Mac: xcode-select --install), then run this installer again."
    warn "$GUARD_NOTE"
    return 0
  fi
  q="'$(printf '%s' "$hook" | sed "s/'/'\\\\''/g")'"
  # Runs the hook only while its file is there: removing make-it turns the guard off instead of
  # blocking every command; any other failure of the hook still blocks (onFailure: block).
  out="$(python3 -I "$MAKEIT_DIR/scripts/add-no-force-push-hook.py" "$CLAUDE_DIR/settings.json" \
    "bash -c '[ -f \"\$0\" ] || exit 0; exec \"\$BASH\" \"\$0\"' $q" \
    "$hook" "$MAKEIT_DIR/force-push-guard.state" "$mode")" \
    || fail "The skills are installed, but the guard that stops git push --force is not changed (see the line above)."
  ok "$out"
  case "$out" in
    Added*|Updated*)
      info "It stops Claude from running git push --force (or -f, --mirror, or a +branch push) in every project on this computer; git push --force-with-lease still works."
      info "To remove it: $REMOVE_HOW" ;;
    *"stays off"*)
      info "To add it back: curl -fsSL ${GITHUB_RAW}/install.sh | bash -s -- --add-force-push-guard" ;;
  esac
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
        backlog-it)  desc="Project board: work items, bug queue, parallel fixes" ;;
        deadcode-it) desc="Find and safely remove code your app no longer uses" ;;
        threats-it)  desc="Installed on its own (github.com/sealmindset/threats-it)" ;;
        *)           desc="Custom skill" ;;
      esac
      printf "    /%-14s -- %s\n" "$cmd_name" "$desc"
    fi
  done

  echo ""
  echo "  Files copied to:"
  echo "    $COMMANDS_DIR/*.md"
  echo "    $MAKEIT_DIR/ (references, templates, scaffolds)"
  if [ -n "$GUARD_NOTE" ]; then
    echo ""
    echo "  $GUARD_NOTE"
  fi
  if [ -n "$THREATS_NOTE" ]; then
    echo ""
    echo "  $THREATS_NOTE"
  fi
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
  local current remote tmp_manifest tmp_verifier cstat
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
  tmp_verifier="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_manifest' '$tmp_verifier'" RETURN

  if ! fetch_remote_manifest "$tmp_manifest"; then
    echo "You're on v${current} (matching the latest published version)."
    echo "Note: could not fetch the content manifest, so this is a version-only"
    echo "check -- content changes shipped without a version bump would be missed."
    return 0
  fi

  # Best-effort: if this fails, content_status falls back to the installed copy.
  fetch_remote_verifier "$tmp_verifier" || true

  cstat=0
  content_status "$tmp_manifest" "$tmp_verifier" || cstat=$?
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
  install_force_push_guard

  # Report
  report
}

# --add-force-push-guard / --remove-force-push-guard (or MAKEIT_FORCE_PUSH_GUARD=add|remove)
case "${1:-}" in
  --add-force-push-guard) GUARD_FLAG=add ;;
  --remove-force-push-guard) GUARD_FLAG=remove ;;
esac

# Support being called with "check" argument (used by /make-it update)
if [ "${1:-}" = "check" ]; then
  check_update
  exit $?
fi

main
