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
exit $fail
