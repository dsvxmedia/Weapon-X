---
name: weaponx-discover
description: Phase 2. Scans for work on its own — recent commits, TODO/FIXME markers, flagged-open items in memory/LEARNING — and dispatches a capped number of the best candidates through the standard weaponx five-move loop. Intended to run on a schedule (see Scheduling below), but can also be invoked on demand as a health check. Never bypasses the never-merge/never-publish safety gate; it only automates *finding* work, not *shipping* it.
---

# Weapon X Discover

This is Phase 2: the piece that finds work on its own instead of waiting for a human to
name a task. It does not replace the five-move loop in `.claude/skills/weaponx/SKILL.md`
— every candidate it decides is worth doing gets dispatched through that same loop,
unmodified, with the same generator/evaluator split, the same retry cap, the same
never-merge boundary. This skill only automates Discovery's *input*, not the rest of the
pipeline's guarantees.

## Config

- `MAX_CANDIDATES_PER_RUN`: 3. Even if discovery finds ten things worth doing, only the
  top 3 get dispatched through the full loop in one run — the rest are logged and wait
  for the next scheduled run or explicit human triage. This exists specifically so a
  single discovery run can't fan out into an unbounded number of expensive dispatches;
  it's the Phase 2 equivalent of `MAX_CYCLES`.
- `LOOKBACK`: commits/changes since the last discovery run (read the discovery log to find
  the last run's timestamp; if none exists, default to the last 20 commits or 7 days,
  whichever is smaller, for the first run).

## Sources (adapted to what this repo actually has — no CI or issue tracker yet)

Read, in order:
1. **Recent commits** since `LOOKBACK` (`git log`) — look for anything that reads like
   unfinished work: a commit message mentioning a follow-up, a partial fix, a fixture
   added without a corresponding real fix.
2. **TODO / FIXME / XXX markers** in tracked source (grep, excluding `sandbox/` —
   pressure-test fixtures under `sandbox/` are deliberately broken by design and are not
   real work; discovering and "fixing" them would be a Nodding-Loop-adjacent mistake).
3. **Open items explicitly flagged in `memory/weaponx/MEMORY.md` or `LEARNING.md`** —
   e.g. a logged finding that says "not fixed yet" or "worth revisiting."
4. **This repo has no CI and no issue tracker yet** (no `origin` remote configured — same
   condition Handoff/Persistence already check for). Once a remote and CI/issues exist,
   extend this list to include failed CI runs and open issues, the way the Loop
   Engineering paper's reference triage skill does. Don't simulate or guess at issues that
   don't exist; report plainly that these sources are unavailable rather than silently
   skipping them.
5. **If a connector is configured** (Jira, Linear, GitHub Issues via MCP, etc.), use it —
   same principle as Move 1 of the main orchestrator: borrow what's connected, don't build
   new integration code here.

## Judge

For each candidate: is it actionable *now*, or noise? Concretely:
- Is it already tracked as an in-flight `state/weaponx/` run? Skip it — don't re-discover
  something already being worked.
- Does it require information or access this environment doesn't have? Skip it, note why.
- Is it something a human clearly intended to revisit later versus something incidentally
  mentioned in passing? Prefer the former.

Keep only what's worth dispatching. Rank by a rough sense of value vs. risk, and take the
top `MAX_CANDIDATES_PER_RUN`.

## Write the discovery log

Append to `state/weaponx/discovery-log.md` (create if absent, one running file — this is
different from per-task trace files, it's the record of discovery *runs* themselves):
timestamp, sources checked (and which were unavailable and why), full candidate list found,
which ones were dispatched this run, which were deferred and why.

## Dispatch

For each of the top `MAX_CANDIDATES_PER_RUN` candidates, invoke the `weaponx` skill on it
exactly as if a human had typed `/weaponx <task>` — same five moves, same worktree
isolation, same generator/evaluator split, same retry cap, same
never-merge-never-publish boundary. This skill does not shortcut or duplicate any of that
logic.

## Stop (the boundary this skill does not get to infer)

- Never dispatch more than `MAX_CANDIDATES_PER_RUN` per run, no matter how many good
  candidates are found.
- Never treat "I found it automatically" as higher trust than "a human asked for it" —
  everything dispatched here still goes through the exact same verification and still
  ends at an unmerged PR/draft, same as any on-demand `/weaponx` run.
- Never invent work to justify having run — if nothing actionable is found, say so
  plainly and stop. An empty discovery log is a correct result, not a failure to find
  something.
- If `sandbox/` pressure-test fixtures are the only thing that superficially looks like
  "broken code," that is not real work — exclude them explicitly (see Sources above).

## Scheduling (how this actually gets triggered)

This skill can be invoked two ways, and this repo currently only supports one of them:

- **Local, on-demand cadence** — `/loop` (session-scoped, requires the machine to stay on,
  recurring tasks expire after 7 days). This is what's available right now, since there's
  no `origin` remote and therefore no cloud/CI scheduling target yet. To activate:
  `/loop <interval> weaponx-discover` (e.g. `/loop 1h weaponx-discover`), or `/loop
  weaponx-discover` to let it self-pace.
- **Cloud scheduling** (GitHub Actions schedule trigger, or a Cloud Routine) — the more
  correct long-term answer, since it doesn't need this machine to stay on. **Not available
  yet** — needs a remote first, same precondition already documented for `ship`'s PR flow
  in the main orchestrator. Revisit once a remote exists.

Activating either scheduling mode is a deliberate decision with an ongoing cost (it starts
autonomous behavior that keeps running until turned off) — this skill file documents how,
it does not turn itself on.
