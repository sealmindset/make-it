#!/usr/bin/env bash
# /threats-it projects hold tenant evidence and are "never pushed". They must not be created in a
# folder that syncs to the cloud (E02-S50: the default was ~/Documents, which iCloud syncs).
set -uo pipefail
cd "$(dirname "$0")/.."
NP="$PWD/.claude/make-it/threats-it/scripts/new_project.sh"
H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
run() { env -i PATH="$PATH" HOME="$H" THREATS_IT_ICLOUD_DOCS=0 THREATS_IT_ICLOUD_DESKTOP=0 "$@" sh "$NP" 2026-01-01 demo 2>&1; }
refused() { # $1 label, rest: env assignments
  local label="$1"; shift
  local out; out="$(run "$@")"; local code=$?
  if [ $code -ne 0 ] && printf '%s' "$out" | grep -qi "syncs to the cloud" && ! find "$H" -type d -name "2026-01-01-demo" | grep -q .; then ok "$label"
  else bad "$label (exit $code: $out)"; fi
}
out="$(run)"; [ "$out" = "$H/threat-briefs/2026-01-01-demo" ] && [ -d "$out/.git" ] && ok "the default folder is ~/threat-briefs, outside Documents" || bad "default folder: $out"
rm -rf "$H/threat-briefs"
refused "iCloud Drive's own folder is refused"            THREATS_IT_HOME="$H/Library/Mobile Documents/com~apple~CloudDocs/briefs"
refused "a cloud-storage provider folder is refused"       THREATS_IT_HOME="$H/Library/CloudStorage/OneDrive-Work/briefs"
refused "a Dropbox folder is refused"                      THREATS_IT_HOME="$H/Dropbox/briefs"
refused "a Google Drive folder is refused"                 THREATS_IT_HOME="$H/Google Drive/briefs"
refused "Documents is refused when iCloud syncs it"        THREATS_IT_HOME="$H/Documents/threat-briefs" THREATS_IT_ICLOUD_DOCS=1
refused "Desktop is refused when iCloud syncs it"          THREATS_IT_HOME="$H/Desktop/briefs" THREATS_IT_ICLOUD_DESKTOP=1
mkdir -p "$H/real/Dropbox/briefs" && ln -s "$H/real/Dropbox/briefs" "$H/plain"
refused "a link into a synced folder is refused"           THREATS_IT_HOME="$H/plain"
out="$(run THREATS_IT_HOME="$H/Documents/threat-briefs")"; [ -d "$out/.git" ] && ok "Documents is fine when nothing syncs it" || bad "Documents with no sync: $out"
out="$(run THREATS_IT_HOME="$H/work/briefs")"; [ -d "$out/.git" ] && ok "an ordinary folder is used as given" || bad "ordinary folder: $out"
for f in .claude/commands/threats-it.md .claude/make-it/threats-it/references/environment-template.md CLAUDE.md "$NP"; do
  grep -q "Documents/threat-briefs" "$f" && bad "$f still names ~/Documents/threat-briefs" || ok "$(basename "$f") no longer names the Documents folder"
done
exit $fail
