# benchmark/weaponx/ — Reusable Eval Cases

The growing gold set the `weaponx` loop builds from its own history. Populated
automatically by Move 5 (Persistence) whenever a run is REJECTed, whenever a human
overrides a PASS verdict after the fact, or whenever a run lands a **weak PASS** (most
checked claims tagged `asserted` rather than `verified`) — weak passes are real signal
about where verification is thin, even without being an outright failure.

This is what `weaponx-calibrate` (Phase 1.5) replays the evaluator against to check
whether its judgment is still trustworthy — so the accuracy of what gets captured here
matters more than the volume.

**Naming:** `<task-slug>.md`

**Each case is tagged** `reject` / `override` / `weak-pass` and records:
- The original task and its domain.
- The artifact that was produced.
- The known-correct verdict and reasoning (the evaluator's original reasoning, or the
  human's correction if they overrode a PASS, or the confidence breakdown if weak-pass).
- The failure-taxonomy label, if applicable (reject/override cases only).

**Do not hand-curate this into a "nice" benchmark.** Its value is that it reflects real
failures this specific loop actually produced, not idealized test cases — that's what
makes calibration checks meaningful instead of theoretical.
