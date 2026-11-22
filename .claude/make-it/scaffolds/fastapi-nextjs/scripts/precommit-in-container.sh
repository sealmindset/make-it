#!/usr/bin/env bash
# precommit-in-container.sh <eslint|prettier> <folder> -- a pre-commit hook for the frontend checks.
#
# eslint and prettier need the app's own packages, which live in the container, not on this
# computer. This runs the check in a container made from the Dockerfile's `deps` stage (the stage
# that installs them; Docker reuses the build's copy, so it is quick after the first build), with
# the folder mounted read-only. Nothing is installed on this computer.
#
# When Docker isn't installed or running, or the packages can't be prepared, it prints one line
# saying the check was skipped and lets the save go on: CI runs the same check on every pull
# request. A real lint or format failure still stops the save. The security hooks (gitleaks,
# no-commit-to-branch, large files, merge markers) don't use this script and never skip.
set -u
what=${1:-}; dir=${2:-.}
cd "$(git rev-parse --show-toplevel)" || exit 1
skip() {
  echo "SKIPPED: the $what check of your frontend code, because $1. Your save goes on; CI runs this check on every pull request."
  exit 0
}
case $what in
  eslint)   cmd='/app/node_modules/.bin/eslint --max-warnings 0 .' ;;
  prettier) cmd='/app/node_modules/.bin/prettier --check .' ;;
  *) echo "precommit-in-container.sh: unknown check '$what'" >&2; exit 1 ;;
esac
command -v docker >/dev/null 2>&1 || skip "Docker isn't installed"
docker info >/dev/null 2>&1 || skip "Docker isn't running"
prefix=$(sed -n 's/^DOCKER_HUB_PREFIX=//p' .env 2>/dev/null | tail -1)
img="$(basename "$PWD" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-')precommit-deps"
docker build -q --target deps --build-arg DOCKER_HUB_PREFIX="$prefix" -t "$img" "$dir" >/dev/null 2>&1 \
  || skip "its packages couldn't be prepared in Docker"
docker run --rm --network none -v "$PWD/$dir:/app/src:ro" -w /app/src "$img" sh -c "$cmd"
rc=$?
# 125-127: Docker itself couldn't start the check (not a finding in the code)
case $rc in 125|126|127) skip "Docker couldn't start it" ;; esac
exit $rc
