---
name: weaponx-push
description: Optional Telegram add-on for Weapon X. Sends plain-English checkpoint updates while a weaponx run is in progress, and delivers decision briefs at human-gates (retry-cap hit, evaluator disagreement, PR ready) that the operator can answer from their phone to resume the loop. Optional instance tooling — a fork without PUSH configured is not broken.
---

<!-- WEAPONX-VERSION-CHECK-PREAMBLE (identical in every weaponx* skill; keep in sync) -->
## Version check (run first — courtesy only, never a blocker)

Before doing this skill's real work, run the block below **once**. It compares the locally
installed Weapon X version against `main` on GitHub. It is a nice-to-have notification, so
its whole failure philosophy is: **any problem = stay silent and proceed.** It must never
hang, error out, or block the skill's actual work.

```bash
# Read the single shared local marker all weaponx* skills agree on.
_WX_LOCAL=$(head -1 ~/.claude/skills/weaponx-version 2>/dev/null | tr -d '[:space:]')
# Fetch the current published VERSION over plain unauthenticated HTTPS, short timeout.
_WX_REMOTE=$(curl -fsS --connect-timeout 2 --max-time 4 \
  https://raw.githubusercontent.com/dsvxmedia/Weapon-X/main/VERSION 2>/dev/null \
  | head -1 | tr -d '[:space:]')
# Guard against a malformed remote (must look like a dotted numeric version); else treat as absent.
case "$_WX_REMOTE" in ''|*[!0-9.]*) _WX_REMOTE="" ;; esac
# Only speak up when both are known AND they differ.
if [ -n "$_WX_LOCAL" ] && [ -n "$_WX_REMOTE" ] && [ "$_WX_LOCAL" != "$_WX_REMOTE" ]; then
  echo "WEAPONX_UPDATE_AVAILABLE $_WX_LOCAL $_WX_REMOTE"
fi
```

Then:
- **If the block printed `WEAPONX_UPDATE_AVAILABLE <local> <remote>`:** surface a real
  confirmation with **AskUserQuestion** — "A newer version of Weapon X is available
  (v<local> -> v<remote>). Update now?" (options: "Update now" / "Not now"). If the user
  picks "Update now", invoke the `weaponx-upgrade` skill, then return here and continue this
  skill's normal work. If they pick "Not now", or AskUserQuestion cannot be presented for
  any reason, just continue — do not re-ask, do not block.
- **If the block printed nothing** (up to date, no marker yet, network/timeout/curl failure,
  or malformed remote): say nothing about updates and proceed straight to the skill's normal
  work. This silence-on-failure is deliberate and asymmetric with `weaponx-upgrade`, which
  fails **loudly** — see that skill and the 2026-07-02 LEARNING.md entry for why.
<!-- END WEAPONX-VERSION-CHECK-PREAMBLE -->

# Weapon X PUSH

PUSH is an **optional** add-on that puts a human in the loop over Telegram, so the operator
can step away from a running weaponx session (lunch, a walk, being asleep) and still stay
in control. It does two things and only two things:

1. **Checkpoint updates** — short, plain-English ("5th grade level", readable, not terse)
   messages sent at the end of a move/cycle while a run is in progress, so the operator
   knows what's happening without watching the terminal. Cadence is deliberately low: end
   of a move or cycle, not every tool call. Do not over-notify.
2. **Decision briefs at human-gates** — when the loop hits a point that is a human's call
   (retry-cap reached, the two evaluators disagreed, a PR is ready for review), PUSH sends
   a brief that always includes: a plain-English explanation of what's being decided, a
   clear recommendation, 2-4 concrete options, and — always — an explicit "or just tell me
   in your own words what to do instead" path. The operator's reply resumes the loop. A
   brief is never a bare approve/deny with no room for a different instruction.

PUSH does not change any of weaponx's guarantees. It never merges, deploys, or publishes;
it never grants the loop more autonomy; it is a notification-and-reply layer bolted onto
the existing five-move loop, not a new decision-maker.

## This is optional instance tooling, not part of the portable engine

PUSH extends the portable engine (`.claude/skills/weaponx/`); it is **not** required by it.
If `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are unset, every PUSH step in the
orchestrator is skipped and weaponx behaves exactly as it does today — same traces, same
`PushNotification`, same never-merge boundary. A fork of Weapon X that never configures
PUSH is **not broken**; it just doesn't get the Telegram layer. Never make PUSH a hard
dependency for the core loop.

The PUSH *skill* (this directory: the bridge script + these docs) is reasonably portable —
someone forking Weapon X could reuse it by setting the two env vars. The PUSH *GitHub
Actions workflows* (`.github/workflows/push-*.yml`) are specific to this repo's CI and its
`weaponx-approval` environment, so they are the least portable part and are best treated as
this instance's own wiring rather than reusable engine.

## Config (env vars — same single-allow-listed-chat pattern as the Second Mind bot)

- `TELEGRAM_BOT_TOKEN` — the bot token from @BotFather.
- `TELEGRAM_CHAT_ID` — the operator's own numeric chat id. The bot only ever sends to, and
  only ever accepts replies from, this one chat id. Any message from any other chat is
  ignored. One token, one chat id, no broadcast.

If either is unset, PUSH is off. See `SETUP.md` for how to obtain both.

## Two delivery paths (both exist; they are not the same thing)

### Path 1 — local long-poll bridge (a session is actively running on the operator's machine)

For when the operator has a live weaponx session going and has just stepped away. A
dependency-free bash script (`bin/push-bridge.sh`, curl + jq only, no `npm install` — it
matches this repo's zero-build-step nature) does the talking:

- `push-bridge.sh send --text "<message>"` — post a checkpoint to Telegram.
- `push-bridge.sh brief --id <id> --text "<brief>" --option "A) ..." --option "B) ..."` —
  record a pending decision under `.pending/<id>.json` and send the brief with its options
  and the free-text escape hatch.
- `push-bridge.sh wait --id <id> [--timeout <s>]` — long-poll `getUpdates` for the
  operator's reply and print exactly one clean line of JSON to stdout when it arrives:
  `{"id":...,"reply":"...","from_chat_id":...,"update_id":...}`.

The orchestrating Claude Code session runs `wait` in the background and watches its stdout
for that single JSON line (the **Monitor** tool is the mechanism — this skill only
guarantees the clean, watchable stdout contract; it does not implement the watching side).

Pending decisions are tracked as small JSON files under `.pending/<id>.json` (id, options,
timestamp, chat_id, timeout) so a reply can be matched back to its decision. This is
instance-runtime state, not committed — `.pending/` is gitignored.

### Path 2 — GitHub Actions cold-start (no local session; kick off a task from a phone)

For starting a brand-new task when nothing is running locally:

- `.github/workflows/push-poll.yml` — a `schedule:`-triggered workflow (~every 5 min) that
  polls Telegram for new `/weaponx <task>` messages from the allow-listed chat id and, on
  finding one, triggers `push-dispatch.yml` via `workflow_dispatch` with the task text.
  GitHub's schedule trigger is best-effort (latency, occasional skips under load) — that's
  an accepted tradeoff for a cold-start convenience path, documented in the workflow itself.
- `.github/workflows/push-dispatch.yml` — `workflow_dispatch`-triggered with a `task`
  input. Runs weaponx headless (`claude -p "/weaponx <task>"`) inside the runner, and
  pushes status/decision messages over Telegram directly (curl) so cold-start runs are not
  silent. Its shipping step depends on the `weaponx-approval` GitHub Environment, so a human
  must approve in the GitHub UI before anything ships — the never-auto-ship boundary,
  enforced rather than merely instructed, for the cloud path too.

## How this wires into the loop

The orchestrator (`.claude/skills/weaponx/SKILL.md`) calls PUSH at two points, and only if
configured: a checkpoint after Verification (Move 4), and a decision brief / PR-ready
checkpoint in Persistence (Move 5). These are strictly additive — they run *in addition to*
the existing `PushNotification` and trace-file behavior, never instead of it. If PUSH isn't
configured, the bridge script exits with a clear "skipping" status and the loop moves on.

## What PUSH deliberately does not do

- It does not merge, deploy, or publish — a decision brief for a ready PR ends at "open the
  PR for review", never at "merge it".
- It does not raise the loop's trust level or autonomy based on replies — the operator can
  approve one specific decision; that is not the same as granting standing autonomy.
- It does not become a hard dependency. Unconfigured means off, not broken.
