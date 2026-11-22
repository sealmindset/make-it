#!/bin/sh
# Archive a source page raw, with a browser user agent, then convert it to text.
#   fetch_source.sh <url> <outdir> <name>
# Writes <outdir>/<name>.html, <outdir>/<name>.txt and appends a line to <outdir>/FETCH-LOG.tsv
# (UTC time, HTTP status, bytes, sha256, url). Exit 2 if the server refuses (>=400):
# then fall back to an API route (e.g. Zendesk JSON) or two independent WebFetch extractions,
# keeping only values that match (see references/sources.md).
set -eu
url="$1"; out="$2"; name="$3"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out"
# A failed fetch must never leave an earlier run's copy looking like this run's result.
rm -f "$out/$name.html" "$out/$name.txt"
code=$(curl -sSL --compressed --max-time 60 -o "$out/$name.html" -w "%{http_code}" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.9" "$url") || code=000   # curl already printed 000; `|| echo` made it 000000
if [ -f "$out/$name.html" ]; then
  bytes=$(wc -c < "$out/$name.html" | tr -d ' ')
  sha=$(shasum -a 256 "$out/$name.html" | cut -d' ' -f1)
else
  bytes=0; sha=-   # nothing was received: log it, then refuse below
fi
printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$code" "$bytes" "$sha" "$url" >> "$out/FETCH-LOG.tsv"
if [ "$code" -ge 400 ] 2>/dev/null || [ "$code" = "000" ]; then
  echo "REFUSED: HTTP $code for $url (see references/sources.md for fallbacks)" >&2
  exit 2
fi
python3 -I "$here/html2text.py" "$out/$name.html" > "$out/$name.txt"
echo "archived $url -> $out/$name.{html,txt} (HTTP $code, $bytes bytes)"
