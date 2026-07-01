---
name: weaponx-replay
description: Phase 1.5. Reconstructs a single weaponx run step-by-step from its trace record in state/weaponx/, for debugging one specific failure without re-reading an entire chat transcript. Use when the user asks "what actually happened on run X" or "why did this one fail."
---

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
