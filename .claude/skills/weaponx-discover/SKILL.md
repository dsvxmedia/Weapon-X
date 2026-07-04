---
name: weaponx-discover
description: Phase 2. Scans for work on its own — recent commits, TODO/FIXME markers, flagged-open items in memory/LEARNING — and dispatches a capped number of the best candidates through the standard weaponx five-move loop. Intended to run on a schedule (see Scheduling below), but can also be invoked on demand as a health check. Never bypasses the never-merge/never-publish safety gate; it only automates *finding* work, not *shipping* it.
---

<!-- WEAPONX-VERSION-CHECK-PREAMBLE (identical in every weaponx* skill; keep in sync) -->
## Version check (run first — courtesy only, never a blocker)

Before doing this skill's real work, run the block below **once**. It compares the locally
installed Weapon X version against `main` on GitHub. It is a nice-to-have notification, so
its whole failure philosophy is: **any problem = stay silent and proceed.** It must never
hang, error out, or block the skill's actual work.

```bash
# Read the single shared local marker all weaponx* skills agree on.
_WX_LOCAL=$(head -1 ~/.claude/skills/weaponx-version 2>/dev/null | tr -d '[:space:]')
# Fetch the current published VERSION over plain unauthenticated HTTPS, short timeout.
_WX_REMOTE=$(curl -fsS --connect-timeout 2 --max-time 4 \
  https://raw.githubusercontent.com/dsvxmedia/Weapon-X/main/VERSION 2>/dev/null \
  | head -1 | tr -d '[:space:]')
# Guard against a malformed remote (must look like a dotted numeric version); else treat as absent.
case "$_WX_REMOTE" in ''|*[!0-9.]*) _WX_REMOTE="" ;; esac
# Only speak up when both are known AND they differ.
if [ -n "$_WX_LOCAL" ] && [ -n "$_WX_REMOTE" ] && [ "$_WX_LOCAL" != "$_WX_REMOTE" ]; then
  echo "WEAPONX_UPDATE_AVAILABLE $_WX_LOCAL $_WX_REMOTE"
fi
```

Then:
- **If the block printed `WEAPONX_UPDATE_AVAILABLE <local> <remote>`:** surface a real
  confirmation with **AskUserQuestion** — "A newer version of Weapon X is available
  (v<local> -> v<remote>). Update now?" (options: "Update now" / "Not now"). If the user
  picks "Update now", invoke the `weaponx-upgrade` skill, then return here and continue this
  skill's normal work. If they pick "Not now", or AskUserQuestion cannot be presented for
  any reason, just continue — do not re-ask, do not block.
- **If the block printed nothing** (up to date, no marker yet, network/timeout/curl failure,
  or malformed remote): say nothing about updates and proceed straight to the skill's normal
  work. This silence-on-failure is deliberate and asymmetric with `weaponx-upgrade`, which
  fails **loudly** — see that skill and the 2026-07-02 LEARNING.md entry for why.
<!-- END WEAPONX-VERSION-CHECK-PREAMBLE -->

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
4. **This repo now has an `origin` remote** (`dsvxmedia/Weapon-X`), but no issue tracker or
   CI that this skill reads from yet. Once CI/issues exist, extend this list to include
   failed CI runs and open issues, the way the Loop Engineering paper's reference triage
   skill does. Don't simulate or guess at issues that don't exist; report plainly that
   these sources are unavailable rather than silently skipping them.
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
  recurring tasks expire after 7 days). To activate: `/loop <interval> weaponx-discover`
  (e.g. `/loop 1h weaponx-discover`), or `/loop weaponx-discover` to let it self-pace.
- **Cloud scheduling** (GitHub Actions schedule trigger, or a Cloud Routine) — the more
  correct long-term answer, since it doesn't need this machine to stay on. This is now
  **technically unblocked**: the repo has a real `origin` remote (`dsvxmedia/Weapon-X`), so
  a GitHub Actions `schedule:` trigger is possible — the PUSH add-on
  (`.claude/skills/weaponx-push/`) already ships exactly this kind of scheduled poller for
  its cold-start path. What's *not* done is a discover-specific scheduled workflow: none is
  turned on by default, and wiring one (a `schedule:`-triggered job that invokes
  `weaponx-discover` headless) is deliberately left as an explicit opt-in, not something
  this skill enables on its own.

Activating either scheduling mode is a deliberate decision with an ongoing cost (it starts
autonomous behavior that keeps running until turned off) — this skill file documents how,
it does not turn itself on.
