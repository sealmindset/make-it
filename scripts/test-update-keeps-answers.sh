#!/usr/bin/env bash
# Updating make-it must not delete the answers the hostile-code check remembered (owner's clears,
# "this project is mine", "stop"). They live in the install folder, which the installer replaces.
set -euo pipefail
cd "$(dirname "$0")/.."
H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
mkdir -p "$H/.claude/make-it"
echo '{"kept":"cleared"}'  > "$H/.claude/make-it/hostile-code-cleared.json"
echo '{"kept":"projects"}' > "$H/.claude/make-it/hostile-code-projects.json"
echo stale > "$H/.claude/make-it/old-file-from-an-earlier-release"
HOME="$H" bash install.sh >/dev/null 2>&1 || { echo "FAIL the installer did not finish"; exit 1; }
fail=0
for f in cleared projects; do
  if [ "$(cat "$H/.claude/make-it/hostile-code-$f.json" 2>/dev/null)" = "{\"kept\":\"$f\"}" ]; then echo "ok   $f answers kept"
  else echo "FAIL $f answers lost by the update"; fail=1; fi
done
[ ! -e "$H/.claude/make-it/old-file-from-an-earlier-release" ] && echo "ok   the rest of the folder is still replaced" || { echo "FAIL stale files survive"; fail=1; }
[ -f "$H/.claude/make-it/references/hostile-code.md" ] && echo "ok   the new release is installed" || { echo "FAIL install incomplete"; fail=1; }
# a failed update leaves the old folder and its answers where they were (review 2026-11-17)
H2="$(mktemp -d)"; mkdir -p "$H2/.claude/make-it"
echo '{"kept":"cleared"}' > "$H2/.claude/make-it/hostile-code-cleared.json"; chmod 000 "$H2/.claude/make-it/hostile-code-cleared.json"
echo old > "$H2/.claude/make-it/marker-of-the-old-install"
if HOME="$H2" bash install.sh >/dev/null 2>&1; then echo "FAIL the installer went on although it could not keep an answers file"; fail=1
elif [ -e "$H2/.claude/make-it/marker-of-the-old-install" ] && [ -e "$H2/.claude/make-it/hostile-code-cleared.json" ]; then echo "ok   a failed update changes nothing"
else echo "FAIL a failed update lost the old folder or its answers"; fail=1; fi
chmod 600 "$H2/.claude/make-it/hostile-code-cleared.json"; rm -rf "$H2"
# a linked answers file is not followed
H3="$(mktemp -d)"; mkdir -p "$H3/.claude/make-it"; echo SECRET > "$H3/outside.txt"
ln -s "$H3/outside.txt" "$H3/.claude/make-it/hostile-code-cleared.json"
HOME="$H3" bash install.sh >/dev/null 2>&1 || true
if [ -e "$H3/.claude/make-it/hostile-code-cleared.json" ]; then echo "FAIL a linked answers file was followed"; fail=1; else echo "ok   a linked answers file is not followed"; fi
rm -rf "$H3"
exit $fail
