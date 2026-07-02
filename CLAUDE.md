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
.claude/skills/weaponx-plan/         Phase 1.6: decomposes one large idea into a sequence of
                                     bounded stages, each dispatched through weaponx unmodified
.claude/skills/weaponx-discover/     Phase 2: finds work on its own, dispatches through weaponx
.claude/skills/weaponx-calibrate/    Phase 1.5: checks if the evaluator has drifted
.claude/skills/weaponx-drift/        Phase 1.5: cross-run trend/health dashboard
.claude/skills/weaponx-replay/       Phase 1.5: reconstructs one run from its trace
.claude/skills/weaponx-push/         optional add-on: Telegram checkpoints + decision briefs
                                     (bash/curl/jq bridge + two GitHub Actions workflows;
                                     gated behind config, not part of the portable core)
.github/workflows/push-poll.yml      PUSH Path 2: polls Telegram for cold-start /weaponx cmds
.github/workflows/push-dispatch.yml  PUSH Path 2: runs weaponx headless, human-gated ship
.claude/agents/weaponx-evaluator.md      primary verifier (separate context from generator)
.claude/agents/weaponx-evaluator-b.md    second, risk-framed verifier (high-stakes only)
memory/weaponx/MEMORY.md             durable cross-task facts (instance data, kept short)
state/weaponx/                       one structured trace file per run, plus discovery-log.md;
                                     plans/ holds one file per weaponx-plan multi-stage plan (instance data)
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

**PUSH is an optional add-on, deliberately outside that portable core.** It sits between
the two categories: `.claude/skills/weaponx-push/` (the bash/curl/jq bridge + its docs) is
reasonably portable — a fork could reuse it by setting `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_CHAT_ID` — but its GitHub Actions workflows (`.github/workflows/push-*.yml`) are
specific to this repo's CI and its `weaponx-approval` environment, so the workflows are best
treated as this instance's wiring rather than reusable engine. The reason for placing PUSH
outside the core rather than inside it: the engine must never gain a hard dependency on an
external service, so PUSH is gated entirely behind config — unset the two env vars and every
PUSH step is skipped and weaponx behaves exactly as it does today. A fork without PUSH
configured is not broken.

## Hard rules (do not relax these without updating LEARNING.md to explain why)

1. Never auto-merge, auto-deploy, or auto-publish. Open PRs/drafts; a human approves.
   On `main`, this is enforced, not just instructed: GitHub branch protection
   (`enforce_admins=true`, required PRs, no force-push/deletion) plus a local
   `.githooks/pre-push` hook (`git config core.hooksPath .githooks` to install it in a
   fresh clone) both reject a direct push. Confirmed by testing an actual push, not
   assumed from configuration.
2. Never let the loop promote its own autonomy. Trust-level changes are a human decision,
   made outside the loop.
3. The orchestrator may *suggest* a `CLAUDE.md`/skill/memory edit (via `weaponx-drift`);
   it never applies one itself.
4. Verification is never skipped, even under budget pressure — an unverified PASS is
   worse than an honest `hit-budget-cap` stop.

## Current phase

Phase 1 (on-demand `/weaponx <task>`), Phase 1.5 (trust/drift tooling, most of it inert
until enough run history accumulates), Phase 1.6 (`weaponx-plan` — decomposes one large,
open-ended idea into a dependency-ordered sequence of normal-sized stages and dispatches
them one at a time through the unmodified Phase 1 loop), and Phase 2 (`weaponx-discover` —
finds work on its own, dispatches it through the unmodified Phase 1 loop) are built.

`weaponx-plan` is numbered **1.6** deliberately: it's not a new autonomy tier and not a
diagnostic tool, so it doesn't belong in 1.5 or 2. It's best understood as an *extension of
Phase 1* — it makes the same on-demand, human-initiated Phase 1 loop reachable for inputs
that are too big to hand it directly, by decomposing them into stages that each *are* normal
Phase 1 tasks. It adds no new autonomy (still one human approval up front, still never
merges, still runs strictly sequentially — it is explicitly not a backdoor into Phase 3's
parallel dispatch), which is why it sits just above Phase 1 rather than being its own major
phase. Phase 2's scheduling is
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
- The core engine has no build step, no dependencies, and no tests — it's Claude Code
  configuration (skills + agent definitions), not application code. The one exception is
  the **optional PUSH add-on** (`.claude/skills/weaponx-push/`), which introduces a
  dependency-free bash/curl/jq bridge script and two GitHub Actions workflows. These are
  still zero-`npm`-install and are gated entirely behind config (`TELEGRAM_BOT_TOKEN` /
  `TELEGRAM_CHAT_ID`), so they are not required by the core engine — unconfigured means off,
  not broken. If/when further non-skill tooling is added, this section should keep growing
  accordingly.
