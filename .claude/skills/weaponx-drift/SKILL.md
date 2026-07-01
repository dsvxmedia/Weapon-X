---
name: weaponx-drift
description: Phase 1.5. Aggregates across all weaponx run traces in state/weaponx/ to surface trends a single run can never show — rising token cost, rising retry rate, and recurring failure causes. Run on demand when the user wants a health check, or periodically once enough runs have accumulated.
---

# Weapon X Drift Dashboard

A single trace tells you about one task. This skill reads across all of them to answer
questions no single run can: is this loop getting more expensive over time? More
failure-prone? Failing for the same reason repeatedly across unrelated tasks?

## Procedure

1. Read every file in `state/weaponx/`. If there are too few runs to show a trend
   (use judgment — a handful of runs is a sample size of nothing), say so plainly and
   stop rather than manufacturing a trend line out of noise.
2. Compute and report:
   - **Tokens/turns per run over time** — is cost trending up for comparable task types?
   - **Retry rate over time** — what fraction of runs needed >1 generate/verify cycle,
     and is that fraction changing?
   - **Rejection-cause distribution** — tally failure-taxonomy labels across all REJECTs.
     A distribution dominated by one category (e.g. `stale-context`) is more actionable
     than a flat spread across all seven.
   - **Hit-cap rate** — how often runs hit `MAX_CYCLES` or the budget ceiling without a
     PASS. A rising rate here is an early warning the loop is being asked for tasks it
     can't currently close cleanly.
3. **Recurring failure pattern check:** if the same failure-taxonomy label shows up
   across multiple *unrelated* tasks (not just multiple cycles of the same task), that's
   a signal the problem isn't the generator's effort on any one task — it's missing
   project knowledge. In that case:
   - Name the specific recurring pattern and the tasks where it showed up.
   - Propose a specific, concrete edit to `CLAUDE.md` or the relevant skill that would
     plausibly close the gap (not a vague "improve context").
   - Present it as a **suggestion for the human to apply**, never apply it yourself —
     this skill only writes its own report, it does not edit `CLAUDE.md`, `MEMORY.md`,
     or any skill file.

## Output

A short report: the trends above, flagged concerns in plain language (not just numbers),
and any suggested edits. If nothing concerning shows up, say that plainly too — a clean
report is a real result, not a non-answer.
