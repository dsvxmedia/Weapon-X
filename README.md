# Weapon X

A Claude Code challenge-loop: point it at your hardest task — software engineering,
content/marketing, or open-ended research — and it plans, generates, verifies its own
work with an independent skeptical evaluator, persists a full audit trail, and stops to
hand control back to you rather than merging, deploying, or publishing anything itself.

Built on top of the [`gstack`](https://gstack.dev) skill suite (`qa`, `review`, `ship`,
`canary`, `benchmark`, `investigate`, `triage`, `design-review`, and more) rather than
reimplementing verification, QA, or shipping mechanics from scratch.

## Why

Most "agent loops" are a generator that grades its own homework — which means they tend
to praise mediocre output, since the context it reasons in is already full of the reasons
it made the choices it made. Weapon X separates the two: a generator does the work, a
completely independent evaluator (different agent, different context, no visibility into
the generator's reasoning) checks it by actually running tests/builds/QA rather than just
reading the result, and a second evaluator weighs in on anything high-stakes before it's
allowed to PASS. Nothing merges or publishes without a human. Full rationale and research
basis: [`docs/specs/2026-06-30-weaponx-phase1-design.md`](docs/specs/2026-06-30-weaponx-phase1-design.md).

See [`LEARNING.md`](LEARNING.md) for the running log of *why* it's built this way and
what's been learned from actually using it — read that before changing how the loop
behaves.

## Prerequisites

- [Claude Code](https://claude.com/claude-code)
- The `gstack` skill suite installed (the orchestrator dispatches to its `qa`, `review`,
  `ship`, `design-review`, `canary`, `benchmark`, `dev`, `tdd`, and marketing/content
  skills depending on task domain)

## Usage

```
/weaponx <your hardest task>
```

The orchestrator infers the task's domain (code / content / research), states that
inference up front so you can correct it, and runs the five-move loop: discovery →
handoff → generation → verification → persistence. On completion you get an audit/handoff
packet — what was attempted, what was actually checked (vs. just asserted), and where to
look first — plus a PR or draft deliverable waiting for your review. It never merges,
deploys, or publishes on its own.

For anything you want extra scrutiny on, say so explicitly (or it auto-detects protected
paths / externally-visible deliverables) and a second, independently-framed evaluator
weighs in before a PASS is allowed to stand.

## Safety model

1. **Never auto-merge, auto-deploy, or auto-publish.** Always a human decision.
2. **Never auto-promotes its own autonomy.** No amount of clean runs changes its
   permissions on its own — that's a human decision, made outside the loop.
3. **Suggests, never applies, changes to its own knowledge.** If the drift layer
   (Phase 1.5) spots a recurring failure pattern, it proposes a `CLAUDE.md`/skill edit
   for you to review — it doesn't edit itself.
4. **Verification is never skipped under budget pressure.** Hitting the retry/budget cap
   produces an honest "stopped, here's why" report — never a forced, unverified PASS.

## Project layout

```
.claude/skills/weaponx/              the orchestrator — start here to understand the loop
.claude/skills/weaponx-calibrate/    Phase 1.5: is the evaluator still trustworthy?
.claude/skills/weaponx-drift/        Phase 1.5: cross-run cost/failure trend dashboard
.claude/skills/weaponx-replay/       Phase 1.5: reconstruct one run from its trace
.claude/agents/weaponx-evaluator.md      primary verifier (separate context, assumes broken)
.claude/agents/weaponx-evaluator-b.md    risk-framed second verifier (high-stakes only)
memory/weaponx/MEMORY.md             durable cross-task facts the loop has learned
state/weaponx/                       one structured trace file per run
benchmark/weaponx/                   real-failure eval cases, captured automatically
docs/specs/                          design specs — the "why" behind the architecture
CLAUDE.md                            project orientation for any Claude Code session here
LEARNING.md                          running decision/process log
```

`.claude/skills/weaponx*` and `.claude/agents/weaponx*` are the portable **engine** — if
you fork this, those are what you'd take. `memory/`, `state/`, and `benchmark/` are this
project's own accumulated instance data, not part of the engine.

## Status

**Phase 1** (on-demand `/weaponx <task>`) and **Phase 1.5** (trust/drift tooling, mostly
inert until enough run history accumulates) are built. Not yet built, by design — see the
design spec for why each is deferred:

- **Phase 2:** scheduled discovery (a recurring trigger that finds work on its own).
- **Phase 3:** parallel dispatch across multiple tasks at once.
- **Autonomy auto-promotion:** deliberately never built. See the safety model above.

## License

Not yet decided — currently private. Intended to be open-sourced once Phase 1 has proven
itself against real tasks.
