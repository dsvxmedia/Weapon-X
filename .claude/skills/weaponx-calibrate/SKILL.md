---
name: weaponx-calibrate
description: Phase 1.5. Checks whether the weaponx-evaluator is still trustworthy by replaying it against the accumulated benchmark/weaponx/ gold set. Run periodically (e.g. weekly, or before relying on the loop for something important) — never per-task, since that would double verification cost on every single run. Requires benchmark/weaponx/ to have enough accumulated cases to be meaningful (a handful of cases isn't a sample, it's noise).
---

# Weapon X Calibration Check

Purpose: catch drift in the **evaluator itself**, not just in generated output. A loop
can look healthy (lots of PASS verdicts) while the thing actually going stale is the
judge's standards — and nothing in the per-run trace would show you that, because each
run only sees the evaluator's verdict on itself, never the evaluator's track record.

## Procedure

1. Read every case in `benchmark/weaponx/`. Each case has a known correct verdict (the
   original REJECT reasoning, or the human's correction if they overrode a PASS).
2. Check there are enough cases for this to be a meaningful sample (use judgment — a
   handful of cases from one narrow task type tells you little; if the set is too thin,
   say so and stop rather than reporting a false sense of calibration).
3. Replay `weaponx-evaluator` against each case fresh — same artifact, same
   done-condition, no knowledge of the original verdict — and record its verdict.
4. Compare: how often does the evaluator now agree with the known-correct verdict?
   Break this down by failure-taxonomy category if the case count supports it (an
   evaluator that's drifted on `stale-context` cases specifically but solid everywhere
   else is a different problem than uniform drift).
5. Report the agreement rate plainly, with examples of any disagreements found —
   especially cases where the evaluator now PASSes something it (or a human) previously
   correctly rejected. That direction of drift (getting more lenient) is the dangerous
   one — a loop that gets stricter over time fails loud; one that gets more lenient fails
   silent.

## What this does NOT do

It does not retrain, fine-tune, or auto-correct the evaluator. It produces a report. If
the agreement rate looks bad, that's a signal for the human to look at the evaluator's
prompt/instructions in `.claude/agents/weaponx-evaluator.md` and decide whether to revise
it — same manual-only principle as everything else in this system.
