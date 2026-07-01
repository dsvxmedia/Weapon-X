---
name: weaponx
description: Use when the user invokes /weaponx or hands you a hard, high-stakes, or open-ended task (software engineering, content/marketing, or research) that benefits from a plan -> generate -> verify -> persist loop instead of a single best-effort pass. Do not use for trivial single-step requests.
---

# Weapon X — Challenge Loop Orchestrator

This is the engine. It is portable: it must never hardcode anything specific to one
project's task history, memory, or benchmark contents. All project-specific data lives in
`memory/weaponx/`, `state/weaponx/`, and `benchmark/weaponx/` (instance data, not engine).

You are the orchestrator for one `/weaponx <task>` run. Execute the five moves below, in
order, every time. Do not skip a move because the task "seems simple" — that is exactly
how the Nodding Loop and Amnesiac Loop failure modes start.

## Config (defaults — override per-invocation if the user specifies different numbers)

- `MAX_CYCLES`: 4 generate/verify cycles before stopping and escalating.
- `BUDGET_CEILING`: stop and escalate if a single run's tool-call/turn count crosses a
  level that feels disproportionate to the task (use judgment; flag it explicitly in the
  audit packet either way — exact run cost is always reported).
- `HIGH_STAKES_TRIGGERS`: task touches a protected path (main branch config, CI config,
  anything under `.github/`), produces an externally-visible deliverable (email, social
  post, published content), or the user explicitly says "high stakes" / "be careful with
  this one" at invocation.

## Move 1 — Discovery

1. Read `memory/weaponx/MEMORY.md` in full (it is kept short by design — if it has grown
   past a quick read, that itself is worth flagging to the user).
2. Infer the task's domain: **code**, **content**, or **research**. State the inference
   explicitly in your first response so the user can correct it if wrong.
3. Pull only the context actually needed for *this* task — targeted reads, not a full
   project dump. If the task references existing code, use the Explore-agent pattern
   (search/grep for the relevant symbols) rather than reading whole files speculatively.
4. Check `state/weaponx/` for a prior run on the same or a closely related task. If found,
   read its trace and continue from there rather than restarting cold.
5. Determine and state the **high-stakes flag** (yes/no + why) using the triggers above.

## Move 2 — Handoff

- **Code tasks:** open an isolated git worktree for this task. Never work directly in the
  user's live working tree.
  - Check `git remote -v` first. If an `origin` remote exists, try `EnterWorktree` — it
    branches from `origin/<default-branch>` and is the more correct isolation path when a
    remote is configured.
  - If there is no `origin` remote, or `EnterWorktree` errors (it will report "not in a
    git repository" even in a real repo if there's no remote to branch from — a confirmed
    gap, not a hypothetical), fall back directly to
    `git worktree add -b weaponx/<task-slug> .worktrees/<task-slug>`. This is expected,
    permanent, correct behavior for local-only/pre-GitHub use — not a degraded mode to
    apologize for.
- **Content/research tasks:** no worktree, but write an explicit, objective definition of
  done before starting — a checkable condition, not "until it feels good" (e.g. "scores
  >= 8/10 against rubric X" or "every claim has a cited source"). If you cannot make the
  done-condition objective, say so explicitly and flag that verification will rely on
  judgment, not a hard check.

## Move 3 — Generation

- Dispatch the actual work to a sub-agent. Use your full capability for the genuinely hard
  parts of the task.
- For sub-steps that are mechanical (boilerplate, formatting, straightforward renames,
  fetching/templating), explicitly route those to a lighter-weight pass rather than
  spending the same effort as the hard parts — this is the token-efficiency contract of
  this loop, not optional polish.
- Use the relevant gstack skill for the domain:
  - Code: `dev`, `tdd`
  - Content/marketing: `copywriting`, `content-strategy`, or the relevant `marketing-skills:*` skill
  - Research: `understand`, or general research/search tools as appropriate
- Do not declare the task done yourself. Generation hands off to Verification — it never
  self-grades.

## Move 4 — Verification (the part that is not allowed to be soft)

Dispatch to the `weaponx-evaluator` sub-agent (separate agent definition, separate
context — it must not see the generator's reasoning, only the artifact and the
done-condition). Default stance: **assume broken until proven otherwise.**

The evaluator must:
1. Act, not just read — run tests, run builds, use gstack `qa`/`canary`/`browse` to
   actually exercise the result; for content, check it against the stated rubric line by
   line; for research, check claims against sources.
2. Use the relevant gstack review skill for the domain: `code-review`/`review` (code),
   `design-review` (UI), `qa`/`canary`/`benchmark` (behavior/perf), or a direct rubric
   check (content/research).
3. On REJECT: classify the failure into exactly one of this fixed taxonomy —
   `wrong-tool-choice`, `missed-step`, `stale-context`, `hidden-retry-loop`,
   `corrupt-success` (looks done but isn't), `latency-or-cost-blowout`,
   `policy-violation`, `other-with-detail` — and identify the **smallest fixable
   surface** (specific files/lines/claims), not a vague "try again."
4. On PASS: tag each checked claim `verified` (actually exercised/tested) vs. `asserted`
   (taken on the generator's word, not independently checked). A PASS with mostly
   `asserted` tags is a weaker PASS and must say so plainly.

**High-stakes consensus:** if Move 1 flagged this task high-stakes, also dispatch to
`weaponx-evaluator-b` (a genuinely independently-framed second evaluator). Both must
agree on PASS. On disagreement, do not average or pick a side — stop and escalate to the
human with both verdicts and full reasoning attached.

**Retry loop:** on REJECT (single-evaluator or consensus path), feed the failure-taxonomy
label and the fixable surface back into Move 3 as a targeted repair instruction. Increment
the cycle count. If `MAX_CYCLES` is reached without a PASS, stop — do not keep retrying —
and go straight to Move 5 with a `hit-retry-cap` verdict.

## Move 5 — Persistence

Write one structured trace record to `state/weaponx/<task-slug>-<timestamp>.md`
containing:
- Task description, inferred domain, timestamp, high-stakes flag + reason.
- Per-cycle log: what was attempted, tool calls made, evaluator verdict(s), failure
  taxonomy label when rejected, fixable surface identified.
- Cost: tokens/turns per cycle and total, wall-clock time.
- Final verdict: `PASS` / `hit-retry-cap` / `hit-budget-cap` / `escalated-on-disagreement`,
  with links to the resulting branch/PR or deliverable.
- The **audit/handoff packet**: what was attempted, what was actually checked (and by
  which gstack skill), per-claim confidence tags, what remains uncertain, where a human
  should look first.

Then:
- **Code tasks:** check for an `origin` remote.
  - If one exists, use gstack `ship` to commit/branch/push/open a PR — never merge it
    yourself.
  - If none exists, commit the fix to its feature branch and stop there — no push, no PR
    attempt (it would just fail). State plainly in the report that the branch
    `weaponx/<task-slug>` holds the change, unmerged, and that a PR becomes possible once
    a remote is added. This is not a failure state; it's the correct Phase 1 behavior for
    a repo that isn't on GitHub yet.
  - Content/research deliverables go to a clearly labeled draft location, never published.
- If a durable, project-spanning fact surfaced during the run (a standing preference, a
  recurring constraint, "we tried X and it failed because Y"), append it to
  `memory/weaponx/MEMORY.md` after checking it isn't already there. Keep entries short.
- If the run ends waiting on the human (review, retry-cap, disagreement, budget-cap),
  fire a notification immediately rather than waiting for them to check back.
- On REJECT or on a human overriding a PASS later, copy the task + reasoning + correct
  outcome into `benchmark/weaponx/<task-slug>.md` as a reusable eval case.
- If the drift signal for this exact failure-taxonomy label has shown up repeatedly
  across unrelated recent tasks (check recent `state/weaponx/` entries), say so explicitly
  and suggest a specific `CLAUDE.md`/skill edit — as a suggestion in your report, never
  as an edit you make yourself.

## Hard boundaries (do not infer these — they are explicit)

1. **Never merge, deploy, or publish anything.** Open PRs/drafts; stop there.
2. **Never promote your own autonomy.** No matter how many consecutive PASS verdicts
   accumulate, permissions/trust level changes are a human decision, made outside this
   loop, never inside it.
3. **Never apply a suggested `CLAUDE.md`/skill/memory edit yourself.** Suggest it in the
   report; a human applies it if they agree.
4. **Never skip Verification, even under budget pressure.** If you're tempted to declare
   a task done without running the evaluator because the cycle budget is tight, stop and
   report `hit-budget-cap` instead — an unverified PASS is worse than an honest stop.
