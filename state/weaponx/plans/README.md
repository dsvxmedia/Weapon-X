# state/weaponx/plans/ — Multi-Stage Plan Ledger

One file per plan, written by the `weaponx-plan` skill (Phase 1.6). A *plan* is a single
large, open-ended idea that has been decomposed into a dependency-ordered sequence of
normal-sized bounded stages, each of which is dispatched through the standard `/weaponx`
five-move loop one at a time.

**Why one file per plan (not one running log like `discovery-log.md`):** a plan is a
specific multi-stage project with its own lifecycle — it starts, runs an ordered set of
stages, and ends (all stages done, or stopped at the first failure). That's fundamentally
different from `discovery-log.md`, which is an append-only *stream of independent discovery
events* with no shared lifecycle. One file per plan lets each plan's live per-stage status
be updated in place, keeps unrelated plans from tangling, and mirrors how each individual
`/weaponx` *run* already gets its own trace file in `state/weaponx/` rather than sharing one.

**Naming:** `<plan-slug>.md`

**What each plan file records** (see `.claude/skills/weaponx-plan/SKILL.md`, Move F, for the
authoritative schema — plain-language summary first, technical detail after, matching the
voice of the trace files in `state/weaponx/`):

- The original idea as the user gave it.
- The approved stage list, in order, with each stage's scope and its dependency reasoning
  (what it needs from the prior stage(s) and why) — exactly as approved at the single
  human-approval gate.
- Live per-stage status (`pending` / `in-progress` / `done` / `failed`), updated in place,
  each non-pending stage linking to that stage's own individual trace file in `state/weaponx/`.
- The overall plan verdict once the sequence ends (all done, or stopped-at-stage-N with why).

See `example-illustrative.md` in this directory for a hand-authored, clearly-labeled
illustration of a filled-in plan file (a modest "add a dark-mode toggle" example). It is
**not** a real run — it exists only to make the schema above concrete, since a description
isn't the same as seeing the artifact filled in.

These are instance data (this project's own plan history), not part of the portable engine.
The one exception is `example-illustrative.md`, which is deliberately generic, made-up
content (tied to no real project history) so it can serve as a portable reference.
