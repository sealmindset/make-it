#!/usr/bin/env bash
# The make-it watermark check, for any CI system (Jenkins, GitLab CI, Azure DevOps, a shell).
# Run it from the project's root, on the commit that was pushed (not a trial merge with the base
# branch: a merge is different content, and no seal matches it).
#
#   bash scripts/watermark-check.sh
#
# Needs bash, git, python3 and network access to the make-it repository. Leaves nothing in the project.
# Exit: 0 pass (or security review needed, see CHANGED_SECURITY_FILES), 1 fail, 2 the check is set up wrong.
#
# Settings (environment):
#   MAKE_IT_REPO_URL        where make-it releases are fetched from (a mirror is fine)
#   ALLOWED_RELEASES        "<version> <sha256 of that release's CONTENT_MANIFEST>", one per line or
#                           separated by ";". Set by an organization's own pipeline: only these releases
#                           pass, and the hostile-code check runs too. Unset: any release from 1.60.0.
#   CHANGED_SECURITY_FILES  review (default: pass with a notice) or block (fail)
#   BASE_SHA                the base branch's commit (40 hex). Unset: taken from CHANGE_TARGET (Jenkins).
set -euo pipefail

MAKE_IT_REPO_URL="${MAKE_IT_REPO_URL:-https://github.com/sealmindset/make-it.git}"
ALLOWED_RELEASES="${ALLOWED_RELEASES:-}"
CHANGED_SECURITY_FILES="${CHANGED_SECURITY_FILES:-review}"
BASE_SHA="${BASE_SHA:-}"
APP="$PWD"

fail() { echo "make-it check: $1" >&2; exit "${2:-1}"; }

case "$CHANGED_SECURITY_FILES" in review|block) ;; *) fail "CHANGED_SECURITY_FILES must be review or block." 2 ;; esac

# The project is not trusted: the record is read as data, as a plain file, never through a link.
set +e
version="$(python3 -I - "$APP/.make-it/manifest.json" <<'PY'
import json, os, re, stat, sys
try:
    st = os.lstat(sys.argv[1])
    if not stat.S_ISREG(st.st_mode) or st.st_size > 1_000_000:
        sys.exit(1)
    with open(sys.argv[1], encoding="utf-8") as f:
        v = json.load(f)["framework"]["version"]
    if not isinstance(v, str) or not re.fullmatch(r"\d{1,4}\.\d{1,4}\.\d{1,4}", v):
        sys.exit(1)
    # 1.60.0 is the first release that checks the seal: a project must not be able to pick an older one
    if tuple(map(int, v.split("."))) < (1, 60, 0):
        sys.exit(3)
    print(v)
except Exception:
    sys.exit(1)
PY
)"
rc=$?
set -e
case "$rc" in
  0) ;;
  3) fail "This project names a make-it release older than 1.60.0, which cannot check the seal. Update make-it, run /resume-it, then push again." ;;
  *) fail "This project has no usable make-it build record. Run /resume-it in this project, then push again." ;;
esac

want=""
if [ -n "$ALLOWED_RELEASES" ]; then
  want="$(printf '%s\n' "$ALLOWED_RELEASES" | tr ';' '\n' | awk -v v="$version" '$1==v {print $2; exit}')"
  [ -n "$want" ] || fail "make-it $version is not an allowed release. Update make-it, run /resume-it, then push again."
fi

# make-it is fetched outside the project: the seal counts every new file in it.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 --branch "v$version" -c advice.detachedHead=false "$MAKE_IT_REPO_URL" "$tmp/make-it" 2>"$tmp/clone.err" \
  || { cat "$tmp/clone.err" >&2; fail "Could not fetch make-it v$version from $MAKE_IT_REPO_URL." 2; }
fw="$tmp/make-it/.claude/make-it"

if [ -n "$want" ]; then
  got="$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$tmp/make-it/CONTENT_MANIFEST")"
  [ "$got" = "$want" ] || fail "The make-it release does not match the allowed list."
  python3 -I "$fw/scripts/hostile-code-check.py" "$APP" || fail "The hostile-code check did not pass."
fi

# The same git guards watermark.py uses: nothing in the project's git settings may run a command.
if [ -z "$BASE_SHA" ] && [ -n "${CHANGE_TARGET:-}" ]; then
  BASE_SHA="$(GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 git -C "$APP" -c safe.bareRepository=explicit -c protocol.allow=never \
    -c core.fsmonitor=false --no-replace-objects rev-parse -q --verify "refs/remotes/origin/${CHANGE_TARGET}^{commit}" 2>/dev/null || true)"
  [ -n "$BASE_SHA" ] || echo "make-it check: origin/${CHANGE_TARGET} is not in this checkout, so a changed security file cannot be matched against the base branch."
fi
base=()
if [ -n "$BASE_SHA" ]; then
  printf '%s' "$BASE_SHA" | grep -Eq '^[0-9a-f]{40}$' || fail "BASE_SHA must be a full 40-character commit id." 2
  base=(--base-ref "$BASE_SHA")
fi

set +e
python3 -I "$fw/scripts/watermark.py" verify --app "$APP" --framework "$fw" ${base[@]+"${base[@]}"}
rc=$?
set -e

case "$rc" in
  0) echo "make-it check: passed (make-it $version)." ;;
  3) if [ "$CHANGED_SECURITY_FILES" = review ]; then
       echo "make-it check: SECURITY REVIEW NEEDED. Security files differ from the make-it release; this change needs the security reviewers' approval."
     else
       fail "Security files differ from the make-it release."
     fi ;;
  *) echo "make-it check: if this build checked out a merge with the base branch, build the pull request's own commit instead." >&2
     fail "failed. See the lines above." ;;
esac
