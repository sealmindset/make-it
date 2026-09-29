#!/usr/bin/env bash
# slack-notify.sh -- post a backlog status change to Slack. Optional: with no
# webhook configured it exits 0 and does nothing, so the board never depends on it.
#
# Webhook (an Incoming Webhook URL), read from, in order:
#   1. $BACKLOG_SLACK_WEBHOOK
#   2. $BACKLOG_DIR/.slack-webhook   (gitignored -- never commit it)
#
# Usage:
#   slack-notify.sh started <id> <title> [category] [priority]
#   slack-notify.sh done    <id> <title>
#   slack-notify.sh raw     "<mrkdwn text>"
set -euo pipefail

WEBHOOK="${BACKLOG_SLACK_WEBHOOK:-}"
if [[ -z "$WEBHOOK" && -n "${BACKLOG_DIR:-}" && -f "$BACKLOG_DIR/.slack-webhook" ]]; then
  WEBHOOK="$(tr -d '[:space:]' < "$BACKLOG_DIR/.slack-webhook")"
fi
if [[ -z "$WEBHOOK" ]]; then
  echo "slack-notify: no webhook configured; skipping." >&2
  exit 0
fi

mode="${1:-}"; shift || true
case "$mode" in
  started)
    text=":construction: *Now working on* \`${1:-}\` — ${2:-}"
    [[ -n "${3:-}" ]] && text+="  ·  _${3}_"
    [[ -n "${4:-}" ]] && text+="  ·  *${4}*"
    ;;
  done) text=":white_check_mark: *Completed* \`${1:-}\` — ${2:-}" ;;
  raw)  text="${1:-}" ;;
  *) echo "usage: slack-notify.sh {started|done|raw} ..." >&2; exit 2 ;;
esac

payload="$(jq -nc --arg t "$text" '{text:$t, mrkdwn:true}')"
out="$(mktemp)"; trap 'rm -f "$out"' EXIT
code="$(curl -sS -o "$out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  --data "$payload" "$WEBHOOK")" || { echo "slack-notify: curl failed" >&2; exit 1; }
[[ "$code" == "200" ]] || { echo "slack-notify: Slack returned HTTP $code: $(cat "$out")" >&2; exit 1; }
echo "slack-notify: posted ($mode)."
