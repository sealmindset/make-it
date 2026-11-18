#!/bin/sh
# Scaffold a threats-it project:  new_project.sh <YYYY-MM-DD> <slug>
# Creates $THREATS_IT_HOME/<date>-<slug>/ (default ~/threat-briefs) as a local git repository.
# Never push it: it will hold tenant evidence. For the same reason it is never created inside a folder
# that syncs to the cloud (iCloud Drive, including Documents and Desktop when iCloud syncs them,
# Dropbox, OneDrive, Google Drive): exit 3, nothing created. THREATS_IT_ORG names the organisation in the confidentiality marking.
set -eu
[ $# -eq 2 ] || { echo "usage: new_project.sh <YYYY-MM-DD> <slug>"; exit 2; }
here="$(cd "$(dirname "$0")/.." && pwd)"
ORG="${THREATS_IT_ORG:-Organisation}"
base="${THREATS_IT_HOME:-$HOME/threat-briefs}"

synced() {  # prints why "$1" syncs to the cloud, or nothing
  case "$1/" in
    "$HOME/Library/Mobile Documents/"*) echo "it is inside iCloud Drive"; return ;;
    "$HOME/Library/CloudStorage/"*) echo "it is inside a cloud storage folder"; return ;;
    */Dropbox/*|*/OneDrive*/*|*/"Google Drive"/*|*/"iCloud Drive"/*) echo "it is inside a Dropbox, OneDrive, Google Drive or iCloud Drive folder"; return ;;
  esac
  docs="${THREATS_IT_ICLOUD_DOCS:-$(defaults read com.apple.finder FXICloudDriveDocuments 2>/dev/null || echo 0)}"
  desk="${THREATS_IT_ICLOUD_DESKTOP:-$(defaults read com.apple.finder FXICloudDriveDesktop 2>/dev/null || echo 0)}"
  case "$1/" in
    "$HOME/Documents/"*) [ "$docs" = 1 ] && echo "iCloud syncs the Documents folder on this Mac" ;;
    "$HOME/Desktop/"*) [ "$desk" = 1 ] && echo "iCloud syncs the Desktop folder on this Mac" ;;
  esac
  return 0
}
# the folder as given, and where it really is (the nearest part of it that exists, links followed)
real="$base"; rest=""
while [ ! -d "$real" ] && [ "$real" != "/" ] && [ "$real" != "." ]; do rest="/$(basename "$real")$rest"; real="$(dirname "$real")"; done
real="$(cd "$real" 2>/dev/null && pwd -P)$rest"
why="$(synced "$base")"; [ -n "$why" ] || why="$(synced "$real")"
if [ -n "$why" ]; then
  echo "Not created: $base syncs to the cloud ($why), and this project will hold tenant evidence."
  echo "Set THREATS_IT_HOME (\"Projects folder\" in the organisation profile) to a folder that stays on this computer, for example ~/threat-briefs."
  exit 3
fi
dir="$base/$1-$2"
[ -e "$dir" ] && { echo "exists: $dir"; exit 1; }
mkdir -p "$dir"/data/raw "$dir"/data/curated "$dir"/data/derived "$dir"/scripts "$dir"/dist
cp "$here/templates/build.sh" "$dir/scripts/build.sh"
cp "$here/templates/pdf.css" "$dir/scripts/pdf.css"
cp "$here/scripts/html2text.py" "$dir/scripts/html2text.py"
chmod +x "$dir/scripts/build.sh"
printf '__pycache__/\n*.pyc\n.DS_Store\n' > "$dir/.gitignore"
cat > "$dir/README.md" <<EOF
# $1 $2 — threats-it assessment

**Internal — ${ORG} confidential** once tenant evidence is added. Keep this repository local.

| File | Audience |
|---|---|
| \`briefing.md\` → \`dist/briefing.pdf\` | Leadership |
| \`technical.md\` → \`dist/technical.pdf\` | Engineers |
| \`appendix.md\` → \`dist/appendix.pdf\` | Generated names and identifiers |
| \`dist/openvex.json\` | Tooling |

Rebuild: \`./scripts/build.sh\`. Raw evidence: \`data/raw/\` (untrusted, parsed only). Transcribed sources: \`data/curated/\`. Derived: \`data/derived/\`.
EOF
cd "$dir" && git init -q
echo "$dir"
