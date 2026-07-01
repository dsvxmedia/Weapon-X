# state/weaponx/ — Run Trace Ledger

One structured trace file per `/weaponx` run, written by Move 5 (Persistence) of the
`weaponx` orchestrator skill. This is the loop's memory of *what happened*, as distinct
from `memory/weaponx/MEMORY.md` (durable cross-task *facts*) and `benchmark/weaponx/`
(reusable *eval cases*).

**Naming:** `<task-slug>-<YYYY-MM-DD-HHmm>.md`

**Required sections in every trace file** (see `.claude/skills/weaponx/SKILL.md`, Move 5,
for the authoritative schema):

- Task description, inferred domain, timestamp, high-stakes flag + reason.
- Per-cycle log: attempt summary, tools/skills invoked, evaluator verdict(s),
  failure-taxonomy label when rejected, fixable surface identified.
- Cost: tokens/turns per cycle and total, wall-clock time.
- Final verdict: `PASS` / `hit-retry-cap` / `hit-budget-cap` / `escalated-on-disagreement`,
  with links to the resulting branch/PR or deliverable.
- Audit/handoff packet: what was attempted, what was actually checked and by which
  gstack skill, per-claim confidence tags (`verified` vs `asserted`), what remains
  uncertain, where to look first.

These files are committed to git — they're the substrate `weaponx-drift` and
`weaponx-calibrate` (Phase 1.5) read from, and they're what `weaponx-replay` reconstructs
a run from. Don't hand-edit them after the fact; if a verdict was wrong, record the
correction as a new entry (and in `benchmark/weaponx/` if it's a useful eval case) rather
than rewriting history.
