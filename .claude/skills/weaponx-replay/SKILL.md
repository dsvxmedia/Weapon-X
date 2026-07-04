---
name: weaponx-replay
description: Phase 1.5. Reconstructs a single weaponx run step-by-step from its trace record in state/weaponx/, for debugging one specific failure without re-reading an entire chat transcript. Use when the user asks "what actually happened on run X" or "why did this one fail."
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

# Weapon X Replay

Purpose: turn a structured trace file back into a readable step-by-step account of one
run, fast, without requiring the human to dig through raw logs or remember a session that
may have happened days ago.

## Procedure

1. Locate the trace file in `state/weaponx/` matching the task the user is asking about
   (by slug, date, or description — ask for clarification if more than one plausibly
   matches rather than guessing).
2. Walk through it cycle by cycle:
   - What was attempted in this cycle, and which tools/skills were invoked.
   - What the evaluator (and, if high-stakes, the second evaluator) said — verdict,
     failure-taxonomy label if rejected, fixable surface identified.
   - What changed going into the next cycle as a direct result.
3. End with the final verdict, the audit/handoff packet as originally written, and the
   total cost (tokens/turns/wall-clock).
4. If the user's question is specifically "why did this fail," lead with the answer
   (the failure-taxonomy label and fixable surface from the final REJECT or hit-cap
   cycle) before walking through the full history — don't bury the answer at the bottom.

## What this does NOT do

It does not re-run the task. It does not modify the trace file. It is a read-only
reconstruction for human understanding — if the user wants to actually retry the task,
that's a new `/weaponx` invocation, not this skill.
