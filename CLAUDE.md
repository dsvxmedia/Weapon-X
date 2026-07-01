# Weapon X

A personal Claude Code loop: a challenge-loop orchestrator (`/weaponx <task>`) that plans,
generates, verifies, and persists its own work instead of producing a single best-effort
pass. Full design rationale lives in `docs/specs/2026-06-30-weaponx-phase1-design.md`.

## What this repo is, in one paragraph

`weaponx` is the orchestrating skill. It runs five moves — discovery, handoff,
generation, verification, persistence — per task. Verification is done by a separate
sub-agent (`weaponx-evaluator`, plus `weaponx-evaluator-b` for high-stakes consensus) that
never sees the generator's reasoning and defaults to assuming the work is broken until
proven otherwise. Nothing it produces merges, deploys, or publishes itself — that always
waits for a human. See `LEARNING.md` for the running log of why decisions were made and
what's been learned from actually using it.

## Directory map

```
.claude/skills/weaponx/              the orchestrator (the engine, portable)
.claude/skills/weaponx-discover/     Phase 2: finds work on its own, dispatches through weaponx
.claude/skills/weaponx-calibrate/    Phase 1.5: checks if the evaluator has drifted
.claude/skills/weaponx-drift/        Phase 1.5: cross-run trend/health dashboard
.claude/skills/weaponx-replay/       Phase 1.5: reconstructs one run from its trace
.claude/agents/weaponx-evaluator.md      primary verifier (separate context from generator)
.claude/agents/weaponx-evaluator-b.md    second, risk-framed verifier (high-stakes only)
memory/weaponx/MEMORY.md             durable cross-task facts (instance data, kept short)
state/weaponx/                       one structured trace file per run, plus discovery-log.md (instance data)
benchmark/weaponx/                   eval cases captured from real rejections (instance data)
docs/specs/                          design specs (this is where the "why" lives)
docs/examples/                       curated write-ups of real runs, kept after the raw
                                      branch is deleted — see LEARNING.md's 2026-06-30
                                      cleanup entry for why some runs get this and most don't
LEARNING.md                          running process/decision log — read before changing
                                      anything about how the loop itself works
```

**Engine vs. instance data:** everything under `.claude/skills/weaponx*` and
`.claude/agents/weaponx*` must stay portable — no hardcoded references to this project's
specific state, memory, or benchmark contents. Everything under `memory/`, `state/`, and
`benchmark/` is this project's own accumulated history and is not part of what a fork
would copy.

## Hard rules (do not relax these without updating LEARNING.md to explain why)

1. Never auto-merge, auto-deploy, or auto-publish. Open PRs/drafts; a human approves.
2. Never let the loop promote its own autonomy. Trust-level changes are a human decision,
   made outside the loop.
3. The orchestrator may *suggest* a `CLAUDE.md`/skill/memory edit (via `weaponx-drift`);
   it never applies one itself.
4. Verification is never skipped, even under budget pressure — an unverified PASS is
   worse than an honest `hit-budget-cap` stop.

## Current phase

Phase 1 (on-demand `/weaponx <task>`), Phase 1.5 (trust/drift tooling, most of it inert
until enough run history accumulates), and Phase 2 (`weaponx-discover` — finds work on its
own, dispatches it through the unmodified Phase 1 loop) are built. Phase 2's scheduling is
**not yet activated** — the skill exists but nothing is currently invoking it on a cadence;
see its own `SKILL.md` for how to turn it on with `/loop`, and why cloud scheduling isn't
available yet (no `origin` remote). Phase 3 (always-on/parallel dispatch across multiple
tasks at once) is explicitly not built — see the design spec before starting it.

## Working in this repo

- Read `LEARNING.md` before changing orchestrator/evaluator behavior — it likely already
  records why the current approach was chosen, including approaches that were tried and
  rejected.
- After any change to how the loop behaves (not just what it does), add an entry to
  `LEARNING.md` rather than only to git history — the point is a human (or future Claude
  session) can understand the system's evolution without archaeology through commits.
- This repo has no build step, no dependencies, and no tests yet — it's Claude Code
  configuration (skills + agent definitions), not application code. If/when Phase 2
  scheduling or non-skill tooling is added, this section should grow accordingly.
