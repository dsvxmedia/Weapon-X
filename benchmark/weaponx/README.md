# benchmark/weaponx/ — Reusable Eval Cases

The growing gold set the `weaponx` loop builds from its own history. Populated
automatically by Move 5 (Persistence) whenever a run is REJECTed, or whenever a human
overrides a PASS verdict after the fact.

This is what `weaponx-calibrate` (Phase 1.5) replays the evaluator against to check
whether its judgment is still trustworthy — so the accuracy of what gets captured here
matters more than the volume.

**Naming:** `<task-slug>.md`

**Each case records:**
- The original task and its domain.
- The artifact that was produced.
- The known-correct verdict and reasoning (either the evaluator's original REJECT
  reasoning, or the human's correction if they overrode a PASS).
- The failure-taxonomy label, if applicable.

**Do not hand-curate this into a "nice" benchmark.** Its value is that it reflects real
failures this specific loop actually produced, not idealized test cases — that's what
makes calibration checks meaningful instead of theoretical.
