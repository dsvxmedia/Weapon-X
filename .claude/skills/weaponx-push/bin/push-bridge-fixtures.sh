#!/usr/bin/env bash
#
# push-bridge-fixtures.sh — dependency-free fixture tests for the pure
# JSON-transform logic in push-bridge.sh (and, as later stages add more,
# push-poll.yml). No live Telegram/GitHub API needed — these are pure `jq`
# filters, so a synthetic payload in, an assertion on the output, is enough
# to catch a logic regression before it ever reaches a live pressure test.
#
# This exists because this project has hit this exact bug class — a jq/bash
# error in a pure data transform — multiple times already: the offset
# advance only covering acted-on updates (dropped a queued command), the
# newest-only options filter (silently dropped an older command in the same
# poll window). Pressure-testing catches these live, after the fact, in one
# session; this catches them before merge, for free, with no new dependency.
#
# Run this before every stage's live pressure test, not instead of it.
#
# Usage: bash push-bridge-fixtures.sh
# Exit 0 = all fixtures passed. Exit 1 = at least one failed (see stderr).

set -euo pipefail

FAILURES=0

assert_eq() {
  # $1 = test name, $2 = actual, $3 = expected
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1" >&2
    echo "  expected: $3" >&2
    echo "  actual:   $2" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: $1"
  fi
}

# ---------------------------------------------------------------------------
# Fixture 1: do_wait's callback_query matcher resolves a button tap
# correctly, and does NOT resolve it if the id prefix doesn't match (i.e.
# a tap meant for a different pending decision must never bleed through).
# ---------------------------------------------------------------------------

FIXTURE_1='{
  "ok": true,
  "result": [
    {"update_id": 1, "callback_query": {"id": "cbq1", "data": "other-decision|0",
      "message": {"chat": {"id": 8743279352}, "date": 2000}}},
    {"update_id": 2, "callback_query": {"id": "cbq2", "data": "my-decision|1",
      "message": {"chat": {"id": 8743279352}, "date": 2000}}}
  ]
}'

CB_DATA="$(printf '%s' "$FIXTURE_1" | jq -r \
  --arg chat "8743279352" --argjson since 1000 --arg idpfx "my-decision|" \
  '[.result[] | select(.callback_query != null) | select(.callback_query.message.chat.id|tostring == $chat) | select(.callback_query.message.date >= $since) | select(.callback_query.data | startswith($idpfx))] | last | .callback_query.data // empty')"

assert_eq "callback matcher: correct id-prefix match, ignores other decision's tap" \
  "$CB_DATA" "my-decision|1"

# ---------------------------------------------------------------------------
# Fixture 2: since_epoch guard rejects a callback_query from before the
# brief was posted (a stale tap on an old, unrelated keyboard).
# ---------------------------------------------------------------------------

CB_DATA_STALE="$(printf '%s' "$FIXTURE_1" | jq -r \
  --arg chat "8743279352" --argjson since 3000 --arg idpfx "my-decision|" \
  '[.result[] | select(.callback_query != null) | select(.callback_query.message.chat.id|tostring == $chat) | select(.callback_query.message.date >= $since) | select(.callback_query.data | startswith($idpfx))] | last | .callback_query.data // empty')"

assert_eq "callback matcher: since_epoch guard rejects a stale tap" \
  "$CB_DATA_STALE" ""

# ---------------------------------------------------------------------------
# Fixture 3: a single getUpdates response containing BOTH a text-reply
# update and a callback_query update together — the actual mixed-batch case
# Stage 3 adds support for, not just isolated happy-path taps or types.
# ---------------------------------------------------------------------------

FIXTURE_3='{
  "ok": true,
  "result": [
    {"update_id": 10, "message": {"chat": {"id": 8743279352}, "text": "some typed reply", "date": 2000}},
    {"update_id": 11, "callback_query": {"id": "cbq3", "data": "my-decision|0",
      "message": {"chat": {"id": 8743279352}, "date": 2000}}}
  ]
}'

CB_IN_MIXED="$(printf '%s' "$FIXTURE_3" | jq -r \
  --arg chat "8743279352" --argjson since 1000 --arg idpfx "my-decision|" \
  '[.result[] | select(.callback_query != null) | select(.callback_query.message.chat.id|tostring == $chat) | select(.callback_query.message.date >= $since) | select(.callback_query.data | startswith($idpfx))] | last | .callback_query.data // empty')"
TEXT_IN_MIXED="$(printf '%s' "$FIXTURE_3" | jq -r \
  --arg chat "8743279352" --argjson since 1000 \
  '[.result[] | select(.message.chat.id|tostring == $chat) | select(.message.text != null) | select(.message.date >= $since)] | last | .message.text // empty')"

assert_eq "mixed batch: callback_query correctly extracted alongside a text message" \
  "$CB_IN_MIXED" "my-decision|0"
assert_eq "mixed batch: text message still correctly extracted alongside a callback_query" \
  "$TEXT_IN_MIXED" "some typed reply"

# ---------------------------------------------------------------------------
# Fixture 4: offset advance covers ALL returned update ids, not just the
# ones matched/acted on — the same bug class as the multi-command drop
# fixed earlier in push-poll.yml. Applies equally here: an update this
# particular do_wait call doesn't act on (wrong chat, wrong decision id)
# must still be reflected in the next offset so it isn't redelivered forever.
# ---------------------------------------------------------------------------

LAST_UPDATE="$(printf '%s' "$FIXTURE_1" | jq -r '.result | (map(.update_id) | max) // empty')"
assert_eq "offset advance: computed from ALL updates in the batch, not just acted-on ones" \
  "$LAST_UPDATE" "2"

# ---------------------------------------------------------------------------
# Fixture 5: index resolution — a callback_data index correctly resolves
# back to the full option text via the pending file's persisted options.
# ---------------------------------------------------------------------------

OPTIONS_JSON='["A) do nothing","B) ship it","C) something else"]'
RESOLVED="$(printf '%s' "$OPTIONS_JSON" | jq -r --argjson i 1 '.[$i] // empty')"
assert_eq "index resolution: callback_data index 1 resolves to the correct option text" \
  "$RESOLVED" "B) ship it"

# ---------------------------------------------------------------------------
# Fixture 6: do_brief's reply_markup construction (the jq --args invocation
# in push-bridge.sh) actually parses its filter as a program, not data.
# Added after a real bug: --args placed BEFORE the filter string silently
# swallows the filter into $ARGS.positional instead of running it, and the
# fixtures above didn't catch it because they test the response-MATCHING
# logic, not this construction step — worth keeping both covered.
# ---------------------------------------------------------------------------

REPLY_MARKUP="$(jq -cn --arg id "test-decision" \
  '{inline_keyboard: ($ARGS.positional | to_entries | map([{text: .value, callback_data: ($id + "|" + (.key|tostring))}]))}' \
  --args "A) foo" "B) bar")"

assert_eq "reply_markup construction: produces valid inline_keyboard JSON, correct callback_data" \
  "$REPLY_MARKUP" '{"inline_keyboard":[[{"text":"A) foo","callback_data":"test-decision|0"}],[{"text":"B) bar","callback_data":"test-decision|1"}]]}'

# ---------------------------------------------------------------------------

if [ "$FAILURES" -gt 0 ]; then
  echo "" >&2
  echo "$FAILURES fixture(s) FAILED." >&2
  exit 1
fi
echo ""
echo "All fixtures passed."
