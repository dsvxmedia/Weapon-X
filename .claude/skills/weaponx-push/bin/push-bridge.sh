#!/usr/bin/env bash
#
# push-bridge.sh — PUSH local long-poll bridge for Weapon X.
#
# Dependency-free (bash + curl + jq only, no npm install). Two jobs:
#   1. send      — POST a plain-English message or decision brief to Telegram.
#   2. wait      — long-poll getUpdates for the operator's reply to a pending
#                  decision, then emit a single clean line of JSON to stdout and exit.
#
# It only ever talks to the one allow-listed chat id (TELEGRAM_CHAT_ID). Messages
# from any other chat are ignored — same security posture as the Second Mind bot.
#
# PUSH is optional. If TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID are not set, this
# script exits non-zero with a clear message and weaponx carries on exactly as it
# does today — nothing here is a hard dependency for the core engine.
#
# The `wait` subcommand is built to be watched by an orchestrating Claude Code
# session (via the Monitor tool): it prints exactly one line of JSON to stdout when
# a matching reply arrives, so stdout is trivially greppable for the result.
#
# Usage:
#   push-bridge.sh send  --text "<message>"
#   push-bridge.sh brief --id <decision-id> --text "<brief>" \
#                        [--option "A) ..."]... [--timeout <seconds>]
#   push-bridge.sh wait  --id <decision-id> [--timeout <seconds>] [--interval <seconds>]
#
# Exit codes:
#   0  success (message sent, or reply received and printed)
#   2  missing configuration (PUSH not set up) — caller should treat as "skip PUSH"
#   3  usage error
#   4  timed out waiting for a reply
#   5  Telegram API / network error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_DIR="${SCRIPT_DIR}/../.pending"
API_BASE="https://api.telegram.org"

# ---------------------------------------------------------------------------
# Config / preflight
# ---------------------------------------------------------------------------

require_config() {
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "push-bridge: PUSH not configured (TELEGRAM_BOT_TOKEN and/or TELEGRAM_CHAT_ID unset); skipping." >&2
    exit 2
  fi
  for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "push-bridge: required tool '$bin' not found on PATH." >&2
      exit 5
    fi
  done
}

api_url() {
  # $1 = method name (e.g. sendMessage)
  printf '%s/bot%s/%s' "$API_BASE" "$TELEGRAM_BOT_TOKEN" "$1"
}

# ---------------------------------------------------------------------------
# send — POST a message to the allow-listed chat
# ---------------------------------------------------------------------------

do_send() {
  local text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --text) text="$2"; shift 2 ;;
      *) echo "push-bridge send: unknown arg '$1'" >&2; exit 3 ;;
    esac
  done
  if [ -z "$text" ]; then
    echo "push-bridge send: --text is required" >&2
    exit 3
  fi

  local resp
  resp="$(curl -sS -X POST "$(api_url sendMessage)" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    --data-urlencode "disable_web_page_preview=true")" || {
      echo "push-bridge send: curl failed" >&2; exit 5; }

  if [ "$(printf '%s' "$resp" | jq -r '.ok')" != "true" ]; then
    echo "push-bridge send: Telegram API error: $(printf '%s' "$resp" | jq -r '.description // "unknown"')" >&2
    exit 5
  fi
}

# ---------------------------------------------------------------------------
# brief — record a pending decision, then send its message with options
# ---------------------------------------------------------------------------

do_brief() {
  local id="" text="" timeout="900"
  local -a options=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --option) options+=("$2"); shift 2 ;;
      --timeout) timeout="$2"; shift 2 ;;
      *) echo "push-bridge brief: unknown arg '$1'" >&2; exit 3 ;;
    esac
  done
  if [ -z "$id" ] || [ -z "$text" ]; then
    echo "push-bridge brief: --id and --text are required" >&2
    exit 3
  fi

  mkdir -p "$PENDING_DIR"

  # Persist the pending decision so a reply can be matched back to it later,
  # even from a different invocation (the `wait` subcommand reads this).
  local options_json
  options_json="$(printf '%s\n' "${options[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')"

  jq -n \
    --arg id "$id" \
    --arg chat_id "${TELEGRAM_CHAT_ID}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg timeout "$timeout" \
    --argjson options "$options_json" \
    '{id: $id, chat_id: $chat_id, timestamp: $ts, timeout_seconds: ($timeout|tonumber), options: $options}' \
    > "${PENDING_DIR}/${id}.json"

  # Compose the message body: the brief, the options, and always an explicit
  # free-text escape hatch so the operator is never boxed into approve/deny.
  local body="$text"
  if [ "${#options[@]}" -gt 0 ]; then
    body+=$'\n\nOptions:'
    local o
    for o in "${options[@]}"; do
      body+=$'\n'"• ${o}"
    done
  fi
  body+=$'\n\nReply with the option you want, or just tell me in your own words what to do instead.'
  body+=$'\n\n(decision id: '"${id}"')'

  do_send --text "$body"
}

# ---------------------------------------------------------------------------
# wait — long-poll getUpdates for a reply to a specific pending decision
# ---------------------------------------------------------------------------
#
# Emits exactly one line of JSON to stdout on success:
#   {"id":"<id>","reply":"<operator text>","from_chat_id":<n>,"update_id":<n>}
# Everything else (progress, warnings) goes to stderr so stdout stays clean
# for the watching orchestrator.

do_wait() {
  local id="" timeout="900" interval="2"
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      --timeout) timeout="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      *) echo "push-bridge wait: unknown arg '$1'" >&2; exit 3 ;;
    esac
  done
  if [ -z "$id" ]; then
    echo "push-bridge wait: --id is required" >&2
    exit 3
  fi

  # If a pending file exists and carries its own timeout, honor it unless the
  # caller overrode --timeout explicitly (caller value already parsed above wins).
  local pending_file="${PENDING_DIR}/${id}.json"
  if [ -f "$pending_file" ]; then
    local file_timeout
    file_timeout="$(jq -r '.timeout_seconds // empty' "$pending_file" 2>/dev/null || true)"
    if [ -n "$file_timeout" ] && [ "$timeout" = "900" ]; then
      timeout="$file_timeout"
    fi
  fi

  local deadline offset resp reply from_chat update_id
  deadline=$(( $(date +%s) + timeout ))
  offset=0

  echo "push-bridge wait: watching for reply to decision '${id}' (timeout ${timeout}s)..." >&2

  while [ "$(date +%s)" -lt "$deadline" ]; do
    # Telegram long-poll: block up to `interval` seconds server-side per call.
    resp="$(curl -sS -X POST "$(api_url getUpdates)" \
      --data-urlencode "offset=${offset}" \
      --data-urlencode "timeout=${interval}" \
      --data-urlencode 'allowed_updates=["message"]')" || {
        echo "push-bridge wait: getUpdates curl failed, retrying..." >&2
        continue
      }

    if [ "$(printf '%s' "$resp" | jq -r '.ok')" != "true" ]; then
      echo "push-bridge wait: Telegram API error: $(printf '%s' "$resp" | jq -r '.description // "unknown"')" >&2
      exit 5
    fi

    # Advance the offset past everything we just received so we don't reprocess.
    local last_update
    last_update="$(printf '%s' "$resp" | jq -r '.result | (map(.update_id) | max) // empty')"
    if [ -n "$last_update" ]; then
      offset=$(( last_update + 1 ))
    fi

    # Look only at messages from the allow-listed chat id. Any text reply from
    # that chat is treated as the operator's answer to the current decision —
    # Telegram plain messages don't reliably thread, so newest text from the
    # allow-listed operator is the signal.
    reply="$(printf '%s' "$resp" | jq -r \
      --arg chat "${TELEGRAM_CHAT_ID}" \
      '[.result[] | select(.message.chat.id|tostring == $chat) | select(.message.text != null)] | last | .message.text // empty')"

    if [ -n "$reply" ]; then
      from_chat="$(printf '%s' "$resp" | jq -r \
        --arg chat "${TELEGRAM_CHAT_ID}" \
        '[.result[] | select(.message.chat.id|tostring == $chat) | select(.message.text != null)] | last | .message.chat.id')"
      update_id="$(printf '%s' "$resp" | jq -r \
        --arg chat "${TELEGRAM_CHAT_ID}" \
        '[.result[] | select(.message.chat.id|tostring == $chat) | select(.message.text != null)] | last | .update_id')"

      # Clean single-line JSON result to stdout — this is what the orchestrator watches.
      jq -c -n \
        --arg id "$id" \
        --arg reply "$reply" \
        --argjson from_chat_id "$from_chat" \
        --argjson update_id "$update_id" \
        '{id: $id, reply: $reply, from_chat_id: $from_chat_id, update_id: $update_id}'

      # Best-effort cleanup of the pending marker.
      rm -f "$pending_file" 2>/dev/null || true
      return 0
    fi
  done

  echo "push-bridge wait: timed out after ${timeout}s with no reply to decision '${id}'." >&2
  exit 4
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  if [ $# -lt 1 ]; then
    echo "usage: push-bridge.sh {send|brief|wait} [args...]" >&2
    exit 3
  fi
  local sub="$1"; shift
  case "$sub" in
    send)  require_config; do_send "$@" ;;
    brief) require_config; do_brief "$@" ;;
    wait)  require_config; do_wait "$@" ;;
    -h|--help|help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      ;;
    *) echo "push-bridge.sh: unknown subcommand '$sub'" >&2; exit 3 ;;
  esac
}

main "$@"
