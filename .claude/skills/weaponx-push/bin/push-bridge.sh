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

iso_to_epoch() {
  # $1 = UTC ISO8601 timestamp, e.g. 2026-08-07T10:15:00Z. Tries GNU date
  # first (Linux/GitHub Actions runners), falls back to BSD date (macOS).
  local ts="$1"
  date -u -d "$ts" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null
}

html_escape() {
  # $1 = raw text destined for a Telegram parse_mode=HTML message BODY.
  # Telegram's HTML mode requires escaping exactly these three characters
  # outside markup/attribute contexts — no more, no less. Escaping quotes
  # too would be wrong (unnecessary) and escaping less would let a literal
  # "<" in ordinary text (code snippets, comparisons, generics) be
  # misparsed as the start of a tag, breaking the whole send.
  #
  # NEVER pass this function's output back through itself, and never use it
  # on text meant for an inline-keyboard BUTTON LABEL — Telegram renders
  # button labels as literal plain text with no HTML interpretation, so an
  # escaped string would show a literal "&amp;" on the button face instead
  # of "&". Keep raw-for-label and escaped-for-body as separate variables,
  # never the same string reused in both places.
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# send — POST a message to the allow-listed chat
# ---------------------------------------------------------------------------

# _send_raw: the actual curl POST, parse_mode=HTML, NO escaping — trusts the
# caller has already prepared a safe body. Two callers:
#   - do_send (below): escapes its whole --text argument first, since its
#     existing real callers (e.g. weaponx's orchestrator) pass plain dynamic
#     text and expect plain-text semantics, same as before this stage.
#   - do_brief: composes a body itself from html_escape'd dynamic pieces
#     plus literal HTML markup it adds directly (e.g. Stage 2's <b> bolding);
#     it must call _send_raw directly, never do_send, or its already-escaped
#     text would be escaped a second time.
# Splitting this out is what makes "escape once, at exactly one point per
# caller" possible instead of double-escaping or leaving a gap.
_send_raw() {
  local text="$1"
  local resp
  resp="$(curl -sS -X POST "$(api_url sendMessage)" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true")" || {
      echo "push-bridge: curl failed" >&2; exit 5; }

  if [ "$(printf '%s' "$resp" | jq -r '.ok')" != "true" ]; then
    echo "push-bridge: Telegram API error: $(printf '%s' "$resp" | jq -r '.description // "unknown"')" >&2
    exit 5
  fi
}

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

  _send_raw "$(html_escape "$text")"
}

# ---------------------------------------------------------------------------
# brief — record a pending decision, then send its message with options
# ---------------------------------------------------------------------------

do_brief() {
  local id="" text="" timeout="900" recommended=""
  local -a options=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --option) options+=("$2"); shift 2 ;;
      --timeout) timeout="$2"; shift 2 ;;
      --recommended) recommended="$2"; shift 2 ;;
      *) echo "push-bridge brief: unknown arg '$1'" >&2; exit 3 ;;
    esac
  done
  if [ -z "$id" ] || [ -z "$text" ]; then
    echo "push-bridge brief: --id and --text are required" >&2
    exit 3
  fi

  # --recommended must match a given --option's leading letter (e.g. "A) do
  # X" -> letter "A"). Fail LOUD here, not gracefully — this is a caller
  # (a SKILL.md prompt) bug, not untrusted runtime input, so surfacing it
  # immediately is correct; silently not-highlighting would be a worse
  # failure than an error.
  if [ -n "$recommended" ]; then
    local matched=0 o
    for o in "${options[@]}"; do
      case "$o" in "${recommended})"*) matched=1 ;; esac
    done
    if [ "$matched" -ne 1 ]; then
      echo "push-bridge brief: --recommended '$recommended' matches no given --option" >&2
      exit 3
    fi
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
  # Every dynamic piece (text, each option) goes through html_escape before
  # concatenation; the literal boilerplate strings below contain no
  # &/</> and don't need it. Calls _send_raw directly (not do_send) since
  # this body is already fully escaped — do_send would escape it again.
  local body
  body="$(html_escape "$text")"
  if [ "${#options[@]}" -gt 0 ]; then
    body+=$'\n\nOptions:'
    for o in "${options[@]}"; do
      local prefix=""
      if [ -n "$recommended" ]; then
        case "$o" in "${recommended})"*) prefix="<b>★ Recommended — </b>" ;; esac
      fi
      body+=$'\n'"• ${prefix}$(html_escape "$o")"
    done
  fi
  body+=$'\n\nReply with the option you want, or just tell me in your own words what to do instead.'
  body+=$'\n\n(decision id: '"$(html_escape "$id")"')'

  _send_raw "$body"
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
  local since_epoch="0"
  if [ -f "$pending_file" ]; then
    local file_timeout file_ts
    file_timeout="$(jq -r '.timeout_seconds // empty' "$pending_file" 2>/dev/null || true)"
    if [ -n "$file_timeout" ] && [ "$timeout" = "900" ]; then
      timeout="$file_timeout"
    fi
    # Only match a reply sent at or after this decision's brief went out — a
    # stale unread message in the chat (e.g. a reply to an earlier decision,
    # or a leftover message from before PUSH was working) must never be
    # mistaken for the answer to *this* decision. Falls back to no guard
    # (since_epoch=0) if the timestamp is missing or unparseable, matching
    # the previous, unguarded behavior rather than failing closed.
    file_ts="$(jq -r '.timestamp // empty' "$pending_file" 2>/dev/null || true)"
    if [ -n "$file_ts" ]; then
      since_epoch="$(iso_to_epoch "$file_ts" || echo 0)"
      [ -n "$since_epoch" ] || since_epoch="0"
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

    # Look only at messages from the allow-listed chat id, sent at or after
    # this decision's brief was posted (since_epoch — see above). Any
    # matching text reply is treated as the operator's answer to the current
    # decision — Telegram plain messages don't reliably thread, so newest
    # in-window text from the allow-listed operator is the signal.
    reply="$(printf '%s' "$resp" | jq -r \
      --arg chat "${TELEGRAM_CHAT_ID}" --argjson since "$since_epoch" \
      '[.result[] | select(.message.chat.id|tostring == $chat) | select(.message.text != null) | select(.message.date >= $since)] | last | .message.text // empty')"

    if [ -n "$reply" ]; then
      from_chat="$(printf '%s' "$resp" | jq -r \
        --arg chat "${TELEGRAM_CHAT_ID}" --argjson since "$since_epoch" \
        '[.result[] | select(.message.chat.id|tostring == $chat) | select(.message.text != null) | select(.message.date >= $since)] | last | .message.chat.id')"
      update_id="$(printf '%s' "$resp" | jq -r \
        --arg chat "${TELEGRAM_CHAT_ID}" --argjson since "$since_epoch" \
        '[.result[] | select(.message.chat.id|tostring == $chat) | select(.message.text != null) | select(.message.date >= $since)] | last | .update_id')"

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
