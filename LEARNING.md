# Learning Log

A running, human-readable record of *why* Weapon X is built the way it is — decisions
made, alternatives rejected, and what actually using the loop teaches over time. This is
not the same thing as `memory/weaponx/MEMORY.md` (terse, machine-written facts the
orchestrator accumulates from runs) or `state/weaponx/` (one trace per task). This file is
for the slower, human-level lessons: design choices, course corrections, and things that
turned out to matter more or less than expected.

**Convention:** append new entries at the bottom, dated, newest at the end. Don't edit or
delete old entries even if they turn out to be wrong in hindsight — record the correction
as a new entry instead. The point is to preserve the actual history of how understanding
evolved, including the wrong turns, not to maintain a tidy "current truth" document (that's
what `CLAUDE.md` is for).

---

## 2026-06-30 — Initial design: from "not sure what to build" to a phased loop

Started from five YouTube videos (Spotify's Honk, an LLMOps/eval primer, Anthropic's
Managed Agents, Boris Cherny's Claude Code tips, and a reaction video on the Loop
Engineering moment) plus a Loop Engineering field-study PDF and the user's own prior
brainstorm on LLMOps/eval product gaps. Pulled transcripts via `yt-dlp` (audio captions,
not full frame-by-frame video analysis) specifically to keep the research phase token-light
— matches the project's own stated goal of token efficiency, so the research method and
the thing being researched were consistent from the start.

**Key decision: phase the build instead of going straight for the ambitious end-state.**
The user initially wanted all three trigger modes (on-demand, scheduled, always-on) and
all three task domains (code, content, research) from day one. Every real-world source
researched — especially Spotify, who runs this at the largest scale — only added
scheduling/parallelism *after* their verification step was proven trustworthy on simpler
cases. Recommended and got agreement on: build one domain-agnostic, on-demand orchestrator
first (Phase 1), defer scheduled discovery (Phase 2) and always-on/parallel (Phase 3).

**Key decision: generator/evaluator separation is the one piece that isn't optional.**
Every single source converged on this independently — Spotify's Honk, Anthropic's Jess
Yan, the LLMOps primer, the Loop Engineering paper. An agent grading its own work praises
it; a separate evaluator in a separate context, defaulting to "assume broken," does not
have that bias. Built as two distinct files (`weaponx` orchestrator vs.
`weaponx-evaluator` agent) from the start rather than one skill that both writes and
checks its own work.

**Key decision: safety gate = never auto-merge/deploy/publish, autonomy promotion is
manual-only.** The user chose this explicitly when offered an "auto-promote after clean
runs" alternative. Reasoning at the time: the drift/calibration tooling (Phase 1.5) is
designed to produce *evidence*, not *authority* — it tells a human when trust might be
warranted, it never grants itself more trust. This is the rule most worth re-reading
before ever touching it later, because the practical benefit of auto-promotion (less
babysitting) is exactly the kind of short-term convenience that's easy to rationalize and
hard to walk back once code is already merging itself.

**Round 2 feedback: "this is still mostly a runner + verifier."** The user pushed back
that a working loop isn't enough — the unaddressed gap is making it *measurable,
debuggable, and trustworthy to someone who doesn't want to babysit it*. This is what
turned a flat PASS/REJECT state file into a structured trace schema (failure taxonomy,
fixable-surface identification, confidence-tagged claims) and added Phase 1.5
(`weaponx-calibrate`, `weaponx-drift`, `weaponx-replay`) as an explicit, separately-scoped
layer — deliberately *not* folded into Phase 1's always-on behavior, because running
calibration checks per-task would double verification cost for a signal that isn't even
meaningful until enough runs have accumulated. Lesson: "make it trustworthy" and "make it
trustworthy on every single run" are different asks, and conflating them is exactly how
you get token blowout.

**Round 3 feedback: a "GOD tier" pass.** Added cross-task semantic memory
(`memory/weaponx/MEMORY.md`, separate from per-task state — durable facts vs. run
history), a skill self-improvement signal (drift detection can *suggest* a `CLAUDE.md`/
skill edit, never apply one — same manual-only principle as autonomy promotion, applied
to knowledge instead of permissions), dual-evaluator consensus for high-stakes tasks
(because a single evaluator is still a single point of failure until the next periodic
calibration check catches it — too late for something that already shipped), per-claim
confidence tagging (`verified` vs `asserted`, so a PASS doesn't imply more was checked
than actually was), proactive notification instead of silent waiting on a human gate, and
the engine/instance-data split (so the orchestrator itself, not just this project's task
history, is what gets open-sourced).

**What's still unproven, going in:** none of this has run against a real task yet. The
failure taxonomy, the retry cap of 4, the high-stakes trigger list — these are reasonable
starting guesses based on the research, not validated numbers. The first real runs should
be watched closely, and this log is exactly where to record if/when any of those defaults
turn out to be wrong.

## 2026-06-30 — First real run: a one-line bug fix, and two mechanism gaps found

Ran the loop end to end for the first time: a deliberately tiny, low-stakes fixture
(`sandbox/smoke-test/`, a one-character operator bug in `add()`). Chosen deliberately
small so any failure would be in the loop's *mechanism*, not obscured by task difficulty.
Result: clean PASS in 1 of 4 cycles, all evaluator claims `verified` rather than merely
`asserted`. Full trace: `state/weaponx/smoke-test-fix-add-2026-06-30-1600.md`.

Two real gaps surfaced immediately, both now recorded in `memory/weaponx/MEMORY.md` so
future runs don't rediscover them the hard way:

1. **The built-in `EnterWorktree` tool doesn't work in this repo yet.** It errored "not
   in a git repository" even though plain `git` commands worked fine in the same
   directory — root cause is almost certainly that it defaults to branching from
   `origin/<default-branch>`, and this repo has no `origin` configured yet (by design —
   it isn't pushed to GitHub). Fell back to `git worktree add` directly. This means Move
   2 (Handoff) as written in `SKILL.md` is *not yet accurate* about how isolation
   actually happens pre-GitHub — it should say so explicitly rather than presenting the
   tool call as though it always works. Left as a known gap rather than fixed immediately,
   since fixing it well probably means deciding whether Phase 1 should require a remote as
   a precondition at all, which is a real design question, not a typo.

2. **`gstack ship`'s PR step assumes a remote exists.** Same root cause. Didn't attempt
   to force it — instead, Persistence committed to a feature branch and left it unmerged,
   which is arguably the *correct* behavior for a repo that isn't on GitHub yet, not a
   workaround. Worth deciding explicitly later: is "commit to an unmerged branch, no PR"
   permanent graceful-degradation behavior for local-only use, or should Phase 1 assume a
   remote and treat its absence as a setup error? Left open on purpose — recording the
   question is more valuable right now than guessing at the answer from one data point.

**Lesson for next time:** both gaps were about the *scaffolding around* the loop (git
remote state), not the loop's actual reasoning — the five-move sequence, the
generator/evaluator separation, and the confidence tagging all worked exactly as designed
on the first try. That's a mild update against the pre-run worry that the failure
taxonomy or retry cap would need immediate rework; it's a point *for* the worry that
"what does Phase 1 assume about repo/remote state" wasn't specified clearly enough in the
original design and should be nailed down before the second run, ideally on a task where
it isn't a low-stakes local fixture.

## 2026-06-30 — Resolved: remote-or-not is a permanent branch, not a precondition

Closed the open question from the first run. Decision: `weaponx` never *requires* a
remote to function. Move 2 (Handoff) and Move 5 (Persistence) now check `git remote -v`
explicitly and branch: if `origin` exists, use `EnterWorktree` and gstack `ship`'s real
push/PR flow (the more correct path when it's available); if not, fall back to plain
`git worktree add` and stop at an unmerged local branch, and say so plainly rather than
treating it as a degraded outcome. Reasoning: this is a personal tool meant to be useful
from the first commit, before it's ever pushed anywhere — requiring a remote as a
precondition would mean it can't be smoke-tested or trusted locally before the user
decides to open-source it, which inverts the actual order of how this project is meant to
grow (prove it locally first, publish once it's proven). Encoded directly in
`.claude/skills/weaponx/SKILL.md` rather than left as a runtime judgment call, so future
runs don't have to rediscover this reasoning each time.
