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
#   push-bridge.sh send  --text "<message>" [--print-message-id]
#   push-bridge.sh edit  --message-id <id> --text "<new text>"
#   push-bridge.sh brief --id <decision-id> --text "<brief>" \
#                        [--option "A) ..."]... [--timeout <seconds>] [--recommended <letter>] \
#                        [--diff-file <path>]
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
# Set by _send_raw after a successful send — the sent message's Telegram
# message_id. A global, not stdout, so existing callers (do_brief, and
# do_send's own plain-text contract) see zero output-shape change; only a
# caller that explicitly reads this variable after calling opts in. Used by
# Stage 6's live-editing to capture the message_id to thread forward.
PUSH_LAST_MESSAGE_ID=""

_send_raw() {
  local text="$1"
  local reply_markup="${2:-}"
  local resp
  local -a curl_args=(-sS -X POST "$(api_url sendMessage)" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true")
  if [ -n "$reply_markup" ]; then
    curl_args+=(--data-urlencode "reply_markup=${reply_markup}")
  fi
  resp="$(curl "${curl_args[@]}")" || {
    echo "push-bridge: curl failed" >&2; exit 5; }

  if [ "$(printf '%s' "$resp" | jq -r '.ok')" != "true" ]; then
    echo "push-bridge: Telegram API error: $(printf '%s' "$resp" | jq -r '.description // "unknown"')" >&2
    exit 5
  fi
  PUSH_LAST_MESSAGE_ID="$(printf '%s' "$resp" | jq -r '.result.message_id')"
}

do_send() {
  local text="" print_id=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --text) text="$2"; shift 2 ;;
      # Opt-in only — existing callers see no output-shape change unless
      # they explicitly ask for the message_id (needed by push-dispatch.yml
      # to thread live-editing forward; see do_edit below).
      --print-message-id) print_id=1; shift ;;
      *) echo "push-bridge send: unknown arg '$1'" >&2; exit 3 ;;
    esac
  done
  if [ -z "$text" ]; then
    echo "push-bridge send: --text is required" >&2
    exit 3
  fi

  _send_raw "$(html_escape "$text")"
  if [ "$print_id" -eq 1 ]; then
    printf '%s' "$PUSH_LAST_MESSAGE_ID"
  fi
}

# ---------------------------------------------------------------------------
# edit — update an existing message's text in place (Stage 6, live status)
# ---------------------------------------------------------------------------
#
# Prints the CURRENT message_id to stdout on success — either the same one
# passed in (a real edit or a benign "not modified" no-op), or a NEW one if
# the edit failed and this fell back to a fresh send. Callers thread this
# value forward for the next edit rather than assuming the id never changes.

do_edit() {
  local message_id="" text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --message-id) message_id="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      *) echo "push-bridge edit: unknown arg '$1'" >&2; exit 3 ;;
    esac
  done
  if [ -z "$message_id" ] || [ -z "$text" ]; then
    echo "push-bridge edit: --message-id and --text are required" >&2
    exit 3
  fi

  local resp
  resp="$(curl -sS -X POST "$(api_url editMessageText)" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "message_id=${message_id}" \
    --data-urlencode "text=$(html_escape "$text")" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true")" || {
      echo "push-bridge edit: curl failed" >&2; exit 5; }

  if [ "$(printf '%s' "$resp" | jq -r '.ok')" = "true" ]; then
    printf '%s' "$message_id"
    return 0
  fi

  local desc
  desc="$(printf '%s' "$resp" | jq -r '.description // "unknown"')"
  case "$desc" in
    *"message is not modified"*)
      # Benign no-op — the edit already reflects the desired text (e.g. two
      # steps racing to write the same interim status). Not a failure.
      printf '%s' "$message_id"
      return 0
      ;;
  esac

  # Any other edit failure (message >48h old, deleted, invalid id) falls
  # back to a fresh send rather than losing the update — a new message is a
  # worse UX than one live-edited thread, but a silently-dropped status
  # update is worse still. Logged, not silent, so a pattern of fallbacks is
  # visible rather than invisible.
  echo "push-bridge edit: editMessageText failed ($desc), falling back to a fresh send" >&2
  _send_raw "$(html_escape "$text")"
  printf '%s' "$PUSH_LAST_MESSAGE_ID"
}

# ---------------------------------------------------------------------------
# brief — record a pending decision, then send its message with options
# ---------------------------------------------------------------------------

do_brief() {
  local id="" text="" timeout="900" recommended="" diff_file=""
  local -a options=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --option) options+=("$2"); shift 2 ;;
      --timeout) timeout="$2"; shift 2 ;;
      --recommended) recommended="$2"; shift 2 ;;
      # Stage 7: path to a file holding a raw (unescaped) unified diff to
      # attach to the brief. Optional — omit for a plain decision brief,
      # unchanged from before this stage.
      --diff-file) diff_file="$2"; shift 2 ;;
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

  # Stage 7: diff attachment. Escape via html_escape FIRST, then measure the
  # threshold on the POST-ESCAPE diff COMBINED with the rest of the already-
  # built body — never on the raw diff alone. Measuring pre-escape/diff-only
  # understates real length: &, <, > each expand to 4-5 chars as HTML
  # entities, and diffs are dense with exactly those characters from
  # ordinary code (generics, comparisons, JSX, &&). A symbol-heavy diff could
  # otherwise push the WHOLE message (options, buttons-adjacent text, all of
  # it) past Telegram's real 4096-char sendMessage cap and break the
  # approval flow at the exact moment this stage exists to make it more
  # informative. 3500 leaves real margin under 4096, not a cut-it-at-the-wire
  # threshold.
  local send_diff_as_file=0
  if [ -n "$diff_file" ] && [ -s "$diff_file" ]; then
    local diff_pre
    diff_pre=$'\n\n<pre>'"$(html_escape "$(cat "$diff_file")")"$'</pre>'
    if [ $(( ${#body} + ${#diff_pre} )) -le 3500 ]; then
      body+="$diff_pre"
    else
      send_diff_as_file=1
    fi
  fi

  # Inline keyboard: one tappable button per option, additive alongside the
  # text above — typing a reply must keep working (do_wait checks both).
  # callback_data is "<id>|<index>" (index into the options array as
  # persisted above), never full option text — stays well under Telegram's
  # 64-byte callback_data limit regardless of how long an option string is.
  # Button labels are RAW option text, never html_escape'd: Telegram renders
  # button labels as literal plain text with no HTML interpretation, so an
  # escaped label would show a literal "&amp;" instead of "&" on the button
  # face (see html_escape's own comment above).
  #
  # Omit reply_markup entirely when there are no options, rather than
  # sending an empty inline_keyboard array — Telegram rejects/mishandles an
  # empty keyboard, and do_brief's own contract already allows a
  # plain checkpoint with zero options.
  local reply_markup=""
  if [ "${#options[@]}" -gt 0 ]; then
    # NOTE: --args must come AFTER the filter string, not before — jq
    # treats everything following --args as positional data, so a filter
    # placed after it gets swallowed as data instead of parsed as the
    # program (confirmed the hard way: this exact bug shipped once and was
    # caught by a live pressure test, not the fixture suite, since the
    # fixtures test matching logic on synthetic responses, not this
    # construction step — worth remembering that gap).
    reply_markup="$(jq -cn --arg id "$id" \
      '{inline_keyboard: ($ARGS.positional | to_entries | map([{text: .value, callback_data: ($id + "|" + (.key|tostring))}]))}' \
      --args "${options[@]}")"
  fi

  _send_raw "$body" "$reply_markup"

  # Diff was too large to inline: upload it as a separate file instead of
  # dropping it silently. RAW (unescaped) content here on purpose — this is
  # a downloaded .diff file, not rendered HTML, so html_escape would corrupt
  # it (Telegram file uploads are not parse_mode text). Best-effort: if the
  # upload itself fails (network, Telegram-side size limit), log it loudly
  # rather than silently leaving the human with no diff and no explanation —
  # the brief message itself already went out above regardless.
  if [ "$send_diff_as_file" -eq 1 ]; then
    local doc_resp
    doc_resp="$(curl -sS -X POST "$(api_url sendDocument)" \
      -F "chat_id=${TELEGRAM_CHAT_ID}" \
      -F "caption=Diff too large to inline (decision id: ${id}) — attached as a file." \
      -F "document=@${diff_file};filename=diff.diff;type=text/plain")" || {
        echo "push-bridge brief: sendDocument curl failed, diff not delivered" >&2
        doc_resp=""
      }
    if [ -n "$doc_resp" ] && [ "$(printf '%s' "$doc_resp" | jq -r '.ok')" != "true" ]; then
      echo "push-bridge brief: sendDocument failed: $(printf '%s' "$doc_resp" | jq -r '.description // "unknown"')" >&2
    fi
  fi
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
  local options_json="[]"
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
    # Needed to resolve a button tap's index-only callback_data back to the
    # full option text, so the JSON this function emits looks the same
    # whether the operator typed a reply or tapped a button.
    options_json="$(jq -c '.options // []' "$pending_file" 2>/dev/null || echo '[]')"
  fi

  local deadline offset resp reply from_chat update_id
  deadline=$(( $(date +%s) + timeout ))
  offset=0

  # Reminder ping at ~60% of the timeout window if still unresolved — purely
  # additive UX (a nudge, not a resolution). Deliberately does NOT touch
  # resolution logic at all: on a genuine final timeout, behavior is
  # unchanged from before this stage — exit 4, pending file left in place,
  # nothing auto-selected, ever. Silence must never be treated as approval;
  # keeping this stage additive-only is what makes that guarantee hold by
  # construction, not by care taken while editing this function.
  local reminder_at reminded
  reminder_at=$(( $(date +%s) + timeout * 60 / 100 ))
  reminded=0

  echo "push-bridge wait: watching for reply to decision '${id}' (timeout ${timeout}s)..." >&2

  while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ "$reminded" -eq 0 ] && [ "$(date +%s)" -ge "$reminder_at" ]; then
      curl -sS -X POST "$(api_url sendMessage)" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "text=Still waiting on your reply to decision <code>$(html_escape "$id")</code>. No action taken yet — reply or tap an option when ready." \
        --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
      reminded=1
    fi
    # Telegram long-poll: block up to `interval` seconds server-side per call.
    # allowed_updates includes callback_query so a button tap on a brief's
    # inline keyboard arrives alongside typed text replies — both are
    # checked below in the same response, whichever matches first wins.
    resp="$(curl -sS -X POST "$(api_url getUpdates)" \
      --data-urlencode "offset=${offset}" \
      --data-urlencode "timeout=${interval}" \
      --data-urlencode 'allowed_updates=["message","callback_query"]')" || {
        echo "push-bridge wait: getUpdates curl failed, retrying..." >&2
        continue
      }

    if [ "$(printf '%s' "$resp" | jq -r '.ok')" != "true" ]; then
      echo "push-bridge wait: Telegram API error: $(printf '%s' "$resp" | jq -r '.description // "unknown"')" >&2
      exit 5
    fi

    # Advance the offset past everything we just received so we don't
    # reprocess — from ALL returned update ids, not just ones we act on.
    # Same class of bug as the multi-command poll-window drop fixed
    # elsewhere in this project: a button tap or text reply sitting
    # alongside something we don't act on this iteration must not get
    # silently re-delivered forever, or silently skipped by a narrower
    # offset advance.
    local last_update
    last_update="$(printf '%s' "$resp" | jq -r '.result | (map(.update_id) | max) // empty')"
    if [ -n "$last_update" ]; then
      offset=$(( last_update + 1 ))
    fi

    # Check for a button tap first. callback_data is "<id>|<index>" (see
    # do_brief); require the id prefix to match so a tap meant for a
    # DIFFERENT pending decision (if more than one is outstanding) can never
    # resolve this one. since_epoch is checked against the callback's own
    # message.date (the brief's post time — Telegram doesn't expose a
    # separate "tapped at" timestamp).
    local cb_data cb_id
    cb_data="$(printf '%s' "$resp" | jq -r \
      --arg chat "${TELEGRAM_CHAT_ID}" --argjson since "$since_epoch" --arg idpfx "${id}|" \
      '[.result[] | select(.callback_query != null) | select(.callback_query.message.chat.id|tostring == $chat) | select(.callback_query.message.date >= $since) | select(.callback_query.data | startswith($idpfx))] | last | .callback_query.data // empty')"

    if [ -n "$cb_data" ]; then
      cb_id="$(printf '%s' "$resp" | jq -r \
        --arg chat "${TELEGRAM_CHAT_ID}" --argjson since "$since_epoch" --arg idpfx "${id}|" \
        '[.result[] | select(.callback_query != null) | select(.callback_query.message.chat.id|tostring == $chat) | select(.callback_query.message.date >= $since) | select(.callback_query.data | startswith($idpfx))] | last | .callback_query.id')"
      from_chat="$(printf '%s' "$resp" | jq -r \
        --arg chat "${TELEGRAM_CHAT_ID}" --argjson since "$since_epoch" --arg idpfx "${id}|" \
        '[.result[] | select(.callback_query != null) | select(.callback_query.message.chat.id|tostring == $chat) | select(.callback_query.message.date >= $since) | select(.callback_query.data | startswith($idpfx))] | last | .callback_query.message.chat.id')"
      update_id="$(printf '%s' "$resp" | jq -r \
        --arg chat "${TELEGRAM_CHAT_ID}" --argjson since "$since_epoch" --arg idpfx "${id}|" \
        '[.result[] | select(.callback_query != null) | select(.callback_query.message.chat.id|tostring == $chat) | select(.callback_query.message.date >= $since) | select(.callback_query.data | startswith($idpfx))] | last | .update_id')"

      # Best-effort ack so the button's loading spinner clears client-side —
      # UX polish, not part of the resolution contract, never fatal.
      curl -sS -X POST "$(api_url answerCallbackQuery)" \
        --data-urlencode "callback_query_id=${cb_id}" >/dev/null 2>&1 || true

      # Resolve the index-only callback_data back to the full option text
      # via the pending file's own options array, so the emitted JSON is
      # identical whether the operator tapped or typed.
      local idx
      idx="${cb_data#"${id}|"}"
      reply="$(printf '%s' "$options_json" | jq -r --argjson i "$idx" '.[$i] // empty')"

      if [ -n "$reply" ]; then
        jq -c -n \
          --arg id "$id" \
          --arg reply "$reply" \
          --argjson from_chat_id "$from_chat" \
          --argjson update_id "$update_id" \
          --arg source "button" \
          '{id: $id, reply: $reply, from_chat_id: $from_chat_id, update_id: $update_id, source: $source}'

        rm -f "$pending_file" 2>/dev/null || true
        return 0
      fi
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
        --arg source "text" \
        '{id: $id, reply: $reply, from_chat_id: $from_chat_id, update_id: $update_id, source: $source}'

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
    echo "usage: push-bridge.sh {send|edit|brief|wait} [args...]" >&2
    exit 3
  fi
  local sub="$1"; shift
  case "$sub" in
    send)  require_config; do_send "$@" ;;
    edit)  require_config; do_edit "$@" ;;
    brief) require_config; do_brief "$@" ;;
    wait)  require_config; do_wait "$@" ;;
    -h|--help|help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      ;;
    *) echo "push-bridge.sh: unknown subcommand '$sub'" >&2; exit 3 ;;
  esac
}

main "$@"
