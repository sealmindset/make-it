#!/bin/sh
# Rebuild the report pair from archived data. Markdown is the source of truth; dist/*.pdf are build products.
#   raw data -> derived JSON (project scripts) -> appendix.md -> pair check -> PDFs
# Tenant evidence is collected separately (online, read-only) with the threats-it scripts.
set -eu
cd "$(dirname "$0")/.."
SKILL="${THREATS_IT:-$HOME/.claude/make-it/threats-it}"

# Project-specific derivation steps (create these per threat; each reads data/raw and writes data/derived)
for step in scripts/extract.py scripts/assess.py scripts/appendix.py; do
  [ -f "$step" ] && python3 -I "$step"
done
if [ -f data/derived/vex.json ]; then
  python3 -I "$SKILL/scripts/openvex.py" data/derived/vex.json dist/openvex.json \
    --author "${VEX_AUTHOR:-${THREATS_IT_ORG:-Your Organisation} Information Security}" --id-base "${VEX_ID_BASE:-urn:threats-it:vex:$(basename "$PWD")}"
fi
if [ -f data/derived/headline.json ]; then
  python3 -I "$SKILL/scripts/check_pair.py" briefing.md technical.md data/derived/headline.json
else
  python3 -I "$SKILL/scripts/check_pair.py" briefing.md technical.md
fi

mkdir -p dist
for doc in briefing technical appendix; do
  [ -f "$doc.md" ] || continue
  pandoc "$doc.md" --from markdown+pipe_tables+yaml_metadata_block --standalone \
    --css scripts/pdf.css --metadata pagetitle="$doc" --pdf-engine=weasyprint -o "dist/$doc.pdf" 2>&1 | grep -v '^WARNING' || true
  echo "built dist/$doc.pdf"
done
