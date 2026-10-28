#!/bin/sh
# Scaffold a threats-it project:  new_project.sh <YYYY-MM-DD> <slug>
# Creates $THREATS_IT_HOME/<date>-<slug>/ (default ~/Documents/threat-briefs) as a local git repository.
# Never push it: it will hold tenant evidence. THREATS_IT_ORG names the organisation in the confidentiality marking.
set -eu
[ $# -eq 2 ] || { echo "usage: new_project.sh <YYYY-MM-DD> <slug>"; exit 2; }
here="$(cd "$(dirname "$0")/.." && pwd)"
ORG="${THREATS_IT_ORG:-Organisation}"
dir="${THREATS_IT_HOME:-$HOME/Documents/threat-briefs}/$1-$2"
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
