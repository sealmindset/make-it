#!/usr/bin/env bash
# E02-S48: the secret pattern list (ship-it-guide.md, "### No secret in the record") also names a URL that carries a
# user name and password, `key=` (so API_KEY=...), and the Google, Slack and Stripe key prefixes. The list is stated
# once; the pre-push secret leak scan points at it and restates none of it.
# The list is prose an agent follows, not code. So this test pins the sentences whole, and it builds a regex from the
# guide's own words (the backticked prefixes, the token-start rule, the any-case rule, the URL and long-run shapes) and
# runs it on fixtures. Every fixture that looks like a secret is put together at run time; none is written here whole.
# A tripwire, not a proof: it shows the wording is there and reads the way this file reads it, nothing more.
# Usage: test-secret-pattern-shapes.sh [GUIDE]. With no GUIDE it checks the real guide.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -c reads all its input (grep -q quits early and SIGPIPEs the writer under pipefail)
has() { [ "$(printf '%s' "$1" | grep -cF -- "$2")" -gt 0 ]; }
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"' EXIT

G="${1:-.claude/make-it/references/ship-it-guide.md}"
# a section, from its heading (outside code fences) to the next heading, on one line
sec() { awk -v h="$1" '/^```/{f=!f} !f&&/^#/{on=(index($0,h)==1)} on' "$G" | tr '\n' ' ' | tr -s ' '; }
NS="$(sec '### No secret in the record')"
PP="$(sec '### Pre-push secret leak scan')"
ALL="$(tr '\n' ' ' < "$G" | tr -s ' ')"

LIST='The secret patterns are `sk-`, `sk-ant-`, `sk_live_`, `AKIA`, `AIza`, `ghp_`, `github_pat_`, `xoxb-`, `-----BEGIN`, `password=`, `token=`, `secret=`, `key=`, a URL that carries a user name and password, and a hex or base64 run of 32 or more characters.'
TOKEN='Each pattern matches only at the start of a token: where the text starts, or after a character that isn'"'"'t a letter or digit, so "risk-based" or "task-force" doesn'"'"'t match, and `key=` matches in "API_KEY=" but not in "monkey=".'
ANYCASE='The four patterns that end in `=` match in capitals or lower case.'
URLS='The URL pattern is a `user:pass@` between `://` and the host; a URL without one doesn'"'"'t match.'
POINT='What it looks for includes every secret pattern listed in No secret in the record (Go-live checklist) except the long-run pattern, which a lock file'"'"'s hashes would match: one list, stated there.'

check "the list: one sentence names every pattern, the old ones and sk_live_, AIza, xoxb-, key= and a URL that carries a user name and password" \
  'has "$NS" "$LIST"'
check "token start: a pattern matches only at the start of a token -- key= matches in \"API_KEY=\" but not in \"monkey=\"" \
  'has "$NS" "$TOKEN"'
check "any case: the four patterns that end in = match in capitals or lower case" \
  'has "$NS" "$ANYCASE"'
check "the URL pattern: a user:pass@ between :// and the host; a URL without one doesn't match" \
  'has "$NS" "$URLS"'
check "one list: the guide states \"The secret patterns are\" once, and the pre-push scan points at it (all but the long-run pattern)" \
  '[ "$(printf "%s" "$ALL" | grep -oF "The secret patterns are" | grep -c .)" = 1 ] && has "$PP" "$POINT"'
check "one list: the pre-push scan restates none of it (no AKIA, ghp_, github_pat_, AIza, xoxb-, sk_live_, password=, token=, secret=, key=)" \
  '[ -n "$PP" ] && [ "$(printf "%s" "$PP" | grep -cE "AKIA|ghp_|github_pat_|AIza|xoxb-|sk_live_|(password|token|secret|key)=")" = 0 ]'
check "nothing in the section takes a pattern back (no \"anywhere\", no \"only in lower case\", no \"is not a secret pattern\")" \
  '[ -n "$NS" ] && [ "$(printf "%s" "$NS" | grep -ciE "\banywhere\b|only in (lower case|capitals)|(is|are)(n.t| not| never) (a )?secret patterns?|case.sensitive")" = 0 ]'

# the regex the guide's own words give, run on the fixtures
PY='
import re, sys
ns, yes, no = sys.argv[1], sys.argv[2].split("\n"), sys.argv[3].split("\n")
m = re.search(r"The secret patterns are (.*?\.)(?= |$)", ns); lst = m.group(1) if m else ""
pre = re.findall(r"`([^`]+)`", lst)
eq, rest = [p for p in pre if p.endswith("=")], [p for p in pre if not p.endswith("=")]
a = "(?:^|[^A-Za-z0-9])" if "matches only at the start of a token" in ns else ""
alt = lambda ps: "(?:" + "|".join(re.escape(p) for p in ps) + ")"
parts = []
if rest: parts.append(a + alt(rest))
if eq: parts.append(a + ("(?i:" + alt(eq) + ")" if "match in capitals or lower case" in ns else alt(eq)))
if "a URL that carries a user name and password" in lst and "`user:pass@` between `://` and the host" in ns:
    parts.append(r"://[^/\s:@]+:[^/\s@]+@")
if re.search(r"hex or base64 run of 32 or more", lst): parts.append("[A-Fa-f0-9]{32,}|[A-Za-z0-9+/]{32,}")
pat = re.compile("|".join(parts)) if parts else None
missed = [x for x in yes if not (pat and pat.search(x))]
refused = [x for x in no if pat and pat.search(x)]
if sys.argv[4] == "yes":
    for i, x in enumerate(yes): print("  not matched: fixture %d" % (i + 1)) if x in missed else None   # never the value
    sys.exit(1 if missed or not pat else 0)
for x in refused: print("  refused: " + x)
sys.exit(1 if refused or not pat else 0)
'
# built at run time, each under 32 characters so only its own pattern can match it
F_URL="$(printf '%s%s%s%s%s' 'https://' 'deploy' ':' 'hunter2' '@db.example.com/app')"
F_APIKEY="$(printf '%s%s%s' 'API_' 'KEY=' 'abc123')"
F_KEY="$(printf '%s%s' 'key=' 'abc123')"
F_GOOGLE="$(printf '%s%s%s' 'AI' 'za' 'Sy0abc123')"
F_SLACK="$(printf '%s%s%s' 'xo' 'xb-' '1234-abcd')"
F_STRIPE="$(printf '%s%s%s' 'sk' '_live_' 'abc123')"
F_OLD="$(printf '%s%s' 'gh' 'p_abc123')"
YES="$(printf 'the staging database is at %s\nwe set %s in the host panel\nsee %s in the notes\nthe maps one is %s\nthe bot uses %s\npayments use %s for now\nthe old one was %s' \
  "$F_URL" "$F_APIKEY" "$F_KEY" "$F_GOOGLE" "$F_SLACK" "$F_STRIPE" "$F_OLD")"
NO="$(printf '%s\n' 'the key = value pairs are in the README' 'monkey=3 in the test data' 'the turnkey=ready flag is set' \
  'see https://example.com/path for the plan' 'the docs are at https://example.com:8443/docs/@team' 'mail pat@example.com when it is done' \
  'the token alone is not enough' 'our lawyer is writing them' 'a risk-based review is planned' 'Mr Aizawa signed off on it' \
  'xoxo, the team' 'the task_live_demo is on Friday' 'the API key lives in the host panel')"
check "the added shapes are refused: a URL with user:pass@, API_KEY=, key=, a Google AIza key, a Slack xoxb- token, a Stripe sk_live_ key (and ghp_ still is)" \
  'python3 -I -c "$PY" "$NS" "$YES" "$NO" yes'
check "ordinary text still passes: \"key = value\", \"monkey=3\", a plain URL, a URL with a port and an @ in its path, an email address, \"token\" alone, \"Aizawa\", \"xoxo\", \"task_live_demo\"" \
  'python3 -I -c "$PY" "$NS" "$YES" "$NO" no'

check "the whole run wrote nothing to stderr" '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
