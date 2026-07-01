# Weapon X

A Claude Code challenge-loop: point it at your hardest task — software engineering,
content/marketing, or open-ended research — and it plans, generates, verifies its own
work with an independent skeptical evaluator, persists a full audit trail, and stops to
hand control back to you rather than merging, deploying, or publishing anything itself.

The core idea: the agent that writes never grades its own work. A separate evaluator,
running in its own context with no visibility into the generator's reasoning, checks the
result by actually running it, not just reading it. Anything flagged high-stakes gets a
second, independently-framed evaluator too, and the two have to agree before anything is
allowed to pass.

## Why

Generation stopped being the bottleneck a while ago. Verification is: one 2026 analysis
of AI-assisted development found code churn up 861%, the incident-to-PR ratio up 242.7%,
and median review time up 441.5% — reviewers couldn't keep pace, so code started merging
unread, and that became normal. That's the actual problem, not "can an agent write code."

Most "agent loops" make it worse by having the same agent that wrote the code decide if
the code is good — which means they tend to praise mediocre output, since the context it
reasons in is already full of the reasons it made the choices it made. Weapon X separates
the two: a generator does the work, a completely independent evaluator (different agent,
different context, no visibility into the generator's reasoning) checks it by actually
running tests/builds/QA rather than just reading the result, and a second evaluator weighs
in on anything high-stakes before it's allowed to PASS. Nothing merges or publishes
without a human — and on this repo, that's enforced by GitHub branch protection and a
local pre-push hook, not just an instruction. Full rationale and research basis:
[`docs/specs/2026-06-30-weaponx-phase1-design.md`](docs/specs/2026-06-30-weaponx-phase1-design.md).

See [`LEARNING.md`](LEARNING.md) for the running log of *why* it's built this way and
what's been learned from actually using it — read that before changing how the loop
behaves.

## Prerequisites

- [Claude Code](https://claude.com/claude-code)
- A skill suite covering test/build verification, code review, and PR mechanics — the
  orchestrator dispatches to it for the actual QA, review, and shipping work rather than
  reimplementing that from scratch. Built and tested against
  [`gstack`](https://gstack.dev); any comparable suite should work with light edits to
  `.claude/skills/weaponx/SKILL.md`.

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
.claude/skills/weaponx-discover/     Phase 2: finds work on its own, dispatches through weaponx
.claude/skills/weaponx-calibrate/    Phase 1.5: is the evaluator still trustworthy?
.claude/skills/weaponx-drift/        Phase 1.5: cross-run cost/failure trend dashboard
.claude/skills/weaponx-replay/       Phase 1.5: reconstruct one run from its trace
.claude/agents/weaponx-evaluator.md      primary verifier (separate context, assumes broken)
.claude/agents/weaponx-evaluator-b.md    risk-framed second verifier (high-stakes only)
memory/weaponx/MEMORY.md             durable cross-task facts the loop has learned
state/weaponx/                       one structured trace file per run
benchmark/weaponx/                   real-failure eval cases, captured automatically
docs/specs/                          design specs — the "why" behind the architecture
docs/examples/                       curated write-ups of real runs worth reading in full
CLAUDE.md                            project orientation for any Claude Code session here
LEARNING.md                          running decision/process log
```

`.claude/skills/weaponx*` and `.claude/agents/weaponx*` are the portable **engine** — if
you fork this, those are what you'd take. `memory/`, `state/`, and `benchmark/` are this
project's own accumulated instance data, not part of the engine.

## Status

**Phase 1** (on-demand `/weaponx <task>`), **Phase 1.5** (trust/drift tooling, mostly inert
until enough run history accumulates), and **Phase 2** (`weaponx-discover` — scans commits/
TODOs/flagged items, dispatches a capped number of candidates through the unmodified
Phase 1 loop) are built. **Phase 2's scheduling is not yet turned on** — the skill exists
and can be run on demand, but nothing is invoking it on a recurring cadence yet; see
`.claude/skills/weaponx-discover/SKILL.md` for how to activate it with `/loop` (cloud
scheduling needs a remote, which this repo doesn't have yet). Not yet built, by design:

- **Phase 3:** parallel dispatch across multiple tasks at once.
- **Autonomy auto-promotion:** deliberately never built. See the safety model above.

## License

[MIT](LICENSE). It's the most permissive, widely-recognized license, which best serves the
goal of letting anyone freely fork, reuse, and adopt this engine with no copyleft strings —
a good fit for a small config/prompt repo with no application code or compiled dependencies.
