#!/usr/bin/env bash
# content-manifest.sh -- deterministic content manifest for the /make-it install surface.
#
# WHY THIS EXISTS
#   `/make-it update` used to decide "is there an update?" by comparing VERSION
#   strings alone. A release that changed content without bumping VERSION was
#   therefore invisible: update reported "no update needed" while real changes
#   were outstanding. A content manifest makes drift detectable regardless of
#   what VERSION says.
#
# WHY A MANIFEST AND NOT A SINGLE TREE HASH
#   The installed tree is NOT identical to the repo's tree. Users legitimately
#   keep their own skills in ~/.claude/commands (aws-it.md, jarvis.md, ...), and
#   install.sh writes VERSION + CONTENT_MANIFEST into ~/.claude/make-it. Hashing
#   the whole installed tree would therefore report drift forever. So the
#   manifest lists only repo-owned paths, and `verify` checks exactly those --
#   extra local files are ignored by construction.
#
# USAGE
#   content-manifest.sh generate <root>              # root contains .claude/  -> manifest on stdout
#   content-manifest.sh verify   <manifest> <claude_dir>
#   content-manifest.sh digest   <manifest>          # one-line sha256 of the manifest
#
# Paths in the manifest are relative to the .claude/ directory, e.g.
#   commands/make-it.md
#   make-it/references/guardrails.md
# so the same manifest describes the repo (<repo>/.claude/...) and the install
# (~/.claude/...).

set -euo pipefail

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "ERROR: no sha256 tool found (need shasum or sha256sum)" >&2
    exit 1
  fi
}

# Files that exist in a working tree but are never part of the published surface.
is_excluded() {
  case "$1" in
    *.DS_Store) return 0 ;;
    settings.local.json | */settings.local.json) return 0 ;;
    make-it/VERSION | make-it/CONTENT_MANIFEST) return 0 ;;
    *) return 1 ;;
  esac
}

generate() {
  local root="${1:-.}"
  local base="$root/.claude"

  [ -d "$base/commands" ] || { echo "ERROR: $base/commands not found" >&2; exit 1; }
  [ -d "$base/make-it" ] || { echo "ERROR: $base/make-it not found" >&2; exit 1; }

  # Only the two directories install.sh actually installs.
  {
    find "$base/commands" -maxdepth 1 -type f -name '*.md'
    find "$base/make-it" -type f
  } | {
    while IFS= read -r f; do
      rel="${f#"$base"/}"
      is_excluded "$rel" && continue
      printf '%s  %s\n' "$(sha256_of "$f")" "$rel"
    done
  } | LC_ALL=C sort -k2
}

verify() {
  local manifest="$1" claude_dir="$2"
  local drift=0 missing=0 differs=0 checked=0 want rel f got

  [ -f "$manifest" ] || { echo "ERROR: manifest not found: $manifest" >&2; exit 2; }
  [ -d "$claude_dir" ] || { echo "ERROR: not a directory: $claude_dir" >&2; exit 2; }

  # Redirect from the file (not a pipe) so the counters survive the loop.
  while read -r want rel; do
    [ -n "${want:-}" ] && [ -n "${rel:-}" ] || continue
    checked=$((checked + 1))
    f="$claude_dir/$rel"
    if [ ! -f "$f" ]; then
      echo "  MISSING  $rel"
      missing=$((missing + 1))
      drift=$((drift + 1))
      continue
    fi
    got="$(sha256_of "$f")"
    if [ "$got" != "$want" ]; then
      echo "  DIFFERS  $rel"
      differs=$((differs + 1))
      drift=$((drift + 1))
    fi
  done <"$manifest"

  if [ "$drift" -eq 0 ]; then
    echo "content matches manifest ($checked files)"
    return 0
  fi
  echo "content drift: $differs changed, $missing missing (of $checked tracked files)"
  return 1
}

digest() {
  local manifest="$1"
  [ -f "$manifest" ] || { echo "ERROR: manifest not found: $manifest" >&2; exit 2; }
  sha256_of "$manifest"
}

case "${1:-}" in
  generate) shift; generate "${1:-.}" ;;
  verify)   shift; verify "${1:?manifest required}" "${2:?claude_dir required}" ;;
  digest)   shift; digest "${1:?manifest required}" ;;
  *)
    cat >&2 <<EOF
usage:
  $(basename "$0") generate <root>                 # root contains .claude/
  $(basename "$0") verify   <manifest> <claude_dir>
  $(basename "$0") digest   <manifest>
EOF
    exit 2
    ;;
esac
