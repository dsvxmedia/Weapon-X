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

## 2026-06-30 — gstack: standalone dependency, not vendored; theory-alignment audit

User asked whether to clone gstack's source directly into this repo to "supercharge" the
loop. Recommendation given and taken: **standalone**, not vendored. Reasoning: the
engine/instance split exists specifically so `weaponx` stays portable; vendoring gstack
reverses that for no functional gain, since `weaponx` only ever calls gstack's skills, it
never needs to read or modify gstack's internals — and gstack is already installed and
available in this environment, so there was never actually a "download it" friction
problem to solve for this user, only for a hypothetical future fork without it (which
README documentation already covers, no runtime gate needed).

What the user actually valued was gstack's **principles and full end-to-end process** —
plain-outcome-first reporting, a wide catalog of well-scoped skills that compose. That
turned into two things: (1) rewriting Move 5's audit packet to lead with a plain-language
summary and push technical detail underneath, matching how gstack itself reports; (2)
auditing weaponx against all four research frameworks (the Loop Engineering paper, the AI
agent harness model, LLMOps, and eval) to find what was still missing, since the user
explicitly asked for that check rather than just taking the existing build on faith.

**Audit findings and fixes:**
- **Connectors (MCP) were entirely unaddressed** — the Loop Engineering paper's six parts
  include this explicitly (it decides "the loop's radius of vision") and nothing in
  `SKILL.md` said what to do when a task needs an external system. Added to Config,
  Discovery, and Generation: use whatever MCP connectors are already configured, don't
  build new integration code.
- **`BUDGET_CEILING` was discretion, not a number.** The paper is explicit that token
  blowout's guard is a *real* cap, not judgment. Set concrete starting defaults
  (~40 tool-calls/cycle, ~150/run) — flagged as unmeasured guesses to revise once real
  runs show whether they're too tight or too loose.
- **Comprehension rot had no guard at all.** The paper's defense is regular sampling —
  added `COMPREHENSION_SAMPLE_INTERVAL` (every 5th run) as a nudge in the plain-language
  summary, never a block.
- **gstack was underused relative to what it actually offers.** `investigate` now backs
  root-cause analysis when the same failure-taxonomy label repeats on a retry (instead of
  blindly retrying the same fix twice — this is the concrete mechanism that makes
  `hidden-retry-loop` actually catchable rather than just a label that exists);
  `handoff` now backs the Handoff move's task packaging; `context-save`/`context-restore`
  now back Persistence/Discovery's continuity; `retro` now backs the plain-language
  summary itself.

Everything else audited clean: harness-level concerns (memory, guardrails, notification)
and LLMOps-level concerns (trace, eval, diagnose, fix-and-redeploy) were already covered
by the original design. The gaps were specifically the parts of the theory that hadn't
come up yet in a single smoke-test run — a reminder that "it worked once" and "it matches
the theory" are different claims, and worth checking separately.

## 2026-06-30 — Second gap pass: four real ones, four smaller ones

Asked explicitly for another pass rather than assuming the first audit caught everything.
It didn't. The most important finding:

**The retry cap was silently bypassable.** `MAX_CYCLES` was written as a per-invocation
limit, so a task that hit `hit-retry-cap` could just be re-run and get a fresh budget for
free — which defeats the entire point of a hard cap being a circuit breaker. Fixed by
making `MAX_CYCLES` cumulative *per task*, not per invocation: Move 1 now carries the
cycle count forward from a prior capped trace, and if that carried-forward count already
meets the cap, the loop stops immediately and requires the human to explicitly raise it
rather than silently granting a new budget. General lesson worth remembering: any hard
cap needs to ask "what happens if the human just runs this again" — a cap that resets on
retry isn't actually a cap, it's a suggestion.

**Model-tiering was prose, not a mechanism.** The design has said since the first pass
that mechanical checks should run on a cheap model tier — but nothing ever told the
orchestrator to actually set `model: "haiku"` on the dispatch call, and the actual smoke
test confirmed it: neither sub-agent call used a model override. Fixed in Move 4 directly.
Lesson: a design document describing an intended behavior and a skill file instructing an
agent to perform that behavior are not the same thing, and the gap between them doesn't
show up until you check the actual tool calls a run made, not just whether the run
succeeded.

**No concurrency safety.** Two `/weaponx` invocations running at once had no protection
against colliding on worktree/branch names or racing on shared instance-data files. Fixed
with a same-task-slug collision check at the start of Handoff (numeric suffix on
collision) — deliberately lightweight, not a real locking system, since this is a
single-operator personal tool and the actual risk is low, but "low risk" isn't "no risk."

**Evaluator-b's independence relied on an instruction, not a guarantee.** It said "ignore
evaluator-a's output if you can see it" — which implies it might be visible at all. Fixed
by mandating parallel dispatch (both evaluators in the same message) so evaluator-b
structurally never has evaluator-a's output in its context, full stop.

**Smaller fixes, same pass:** mixed/ambiguous-domain tasks now get a named primary domain
plus an explicit call-out of the secondary component so Verification doesn't silently drop
half the task; `BUDGET_CEILING`'s tool-call count now explicitly includes the
orchestrator's own tool calls, not just sub-agents'; weak-PASS runs (majority `asserted`
claims) now get captured into `benchmark/weaponx/` tagged `weak-pass`, not just outright
rejections; and content pulled in through a connector is now explicitly flagged as
untrusted input, consistent with treating any fetched external content that way.

## 2026-06-30 — Retry-cap fix, verified for real (not just re-read and trusted)

Built a deliberately unsatisfiable fixture (two tests asserting contradictory outcomes for
the same input — no implementation can pass both) specifically so REJECT would be
guaranteed regardless of generator competence, then ran the exact bypass scenario the
earlier fix was supposed to close:

1. Invocation 1, `MAX_CYCLES=1`: generator correctly recognized the contradiction and
   made no changes rather than faking a pass. Evaluator (dispatched on the haiku tier —
   first real exercise of the model-tiering fix) independently confirmed REJECT.
   Cycle count hit 1/1 → `hit-retry-cap`, as expected.
2. Invocation 2, same task, same `MAX_CYCLES=1`: **this was the actual test.** Before the
   fix, this would have reset the cycle count to zero and spent a full second generate/
   verify cycle for free. Instead, Discovery found the prior `hit-retry-cap` trace,
   carried the cycle count forward, saw it already met the cap, and stopped immediately —
   zero sub-agent dispatches, zero cost. Confirmed correct.

One new, small finding from the run itself: the evaluator labeled this REJECT
`wrong-tool-choice` in its structured output, then explained in its own reasoning that
the real issue was task-impossibility — which is exactly what `other-with-detail` is for.
The taxonomy has the right category, the evaluator just didn't reach for it. Logged in
`memory/weaponx/MEMORY.md` as a durable fact rather than fixed by force — it's a one-off
labeling choice, not a structural problem, and one real data point isn't enough to justify
rewriting the evaluator's instructions yet. `benchmark/weaponx/retry-cap-double.md`
captures this specific case so `weaponx-calibrate` can later check whether the label
improves once there's more than one data point.

Also confirmed live: the notification-on-human-gate behavior was correctly *not* fired
during either invocation, because the notification tool's own guidance is explicit about
not paging someone who's clearly still watching — which was the right call here, but
worth remembering this hasn't yet been tested in a scenario where firing it actually was
the correct behavior (an unattended run). That's still an open validation gap, not a
closed one.

## 2026-06-30 — Remaining Phase 1 mechanisms pressure-tested

Closed out the rest of the untested paths from the second gap pass, three more real runs
plus two dry-runs of the Phase 1.5 tools:

**Model-tiering, PASS path.** `pass-path-fix` — a genuine off-by-one bug, unrelated to any
prior fixture — passed clean on cycle 1, evaluator on the haiku tier, every claim
`verified`. Combined with the retry-cap test's REJECT-path confirmation, model-tiering is
now validated on both outcomes, not just one.

**Parallel dual-evaluator consensus.** `high-stakes-discount-fix` — explicitly flagged
high-stakes by the user at invocation (the "user says so" trigger, not a protected-path
trigger). Both evaluators dispatched in the same message, both reached PASS independently
with zero disagreement — but the interesting result wasn't the agreement, it was that
evaluator B's risk-framed lens surfaced real findings (no bounds validation, float
precision on money, thin test coverage) that evaluator A's correctness-framed check
structurally could not have produced. That's a stronger validation of the design than a
forced disagreement would have been: it shows the two evaluators add independent value
even when they agree, not just when they don't. Consensus roughly doubled verification
cost versus a single evaluator (~31.6k vs ~15k tokens) — real, worth remembering when
deciding what actually qualifies as high-stakes, since it's not free.

**`weaponx-drift` dry run.** Correctly refused to report trends from 5 data points, most
of them deliberately engineered pressure-test fixtures rather than organic tasks. Flagged
that the 40% hit-cap rate would be misleading read at face value (both hit-caps are the
same intentionally-impossible task) and that the repeated `wrong-tool-choice` label
doesn't qualify as a cross-task recurring pattern under its own definition. This is the
tool behaving correctly under thin data, which was worth confirming before ever trusting
it under real data.

**`weaponx-calibrate` dry run.** Stopped immediately — one benchmark case exists, and
computing an "agreement rate" from n=1 would be actively misleading rather than just
unhelpful. Correct behavior per its own instructions. Real calibration signal needs
organic REJECTs/weak-PASSes from actual work, not more engineered-to-fail fixtures — worth
remembering not to pad the benchmark set artificially just to unblock this tool, since
that would defeat its purpose.

**State of Phase 1 + 1.5 after this pass:** every mechanism from both gap passes has now
been exercised at least once with a real run, not just re-read and trusted. The one
mechanism that still hasn't been tested in the scenario it's actually for is the
unattended notification path — can't test that honestly from inside an active
conversation, and it stays an open gap until there's a genuinely unattended run to
observe it on.

## 2026-06-30 — Phase 2 built: weaponx-discover

Moved to Phase 2 per direction, after (not instead of) finishing the Phase 1 pressure
testing above — deliberately in that order, consistent with the phased-rollout principle
this project keeps returning to: prove the loop before automating what feeds it.

**Design decision: discovery dispatches through the unmodified Phase 1 loop, not a
shortcut version of it.** Every candidate `weaponx-discover` finds gets handed to the
exact same `weaponx` skill a human would invoke by hand — same worktree isolation, same
generator/evaluator split, same retry cap, same never-merge boundary. Phase 2 only
automates *finding* work, not *shipping* it; the safety floor doesn't move. This was the
one design question worth deciding deliberately rather than defaulting: it would have been
easy to build a leaner, faster "just fix it" path for auto-discovered work on the theory
that it's lower-stakes since a human didn't ask for it specifically — that's backwards.
Auto-discovered work has *less* human context behind it than a hand-typed task, if
anything it deserves the same scrutiny, not less.

**Design decision: `MAX_CANDIDATES_PER_RUN` (default 3) is the Phase 2 equivalent of
`MAX_CYCLES`.** Without a hard cap on how many discovered candidates get dispatched in one
run, a discovery pass that finds a lot of plausible-looking work could fan out into an
expensive, unbounded batch — the token-blowout failure mode, one level up from the
per-task cap. Excess candidates get logged and deferred, not dropped.

**Design decision: excluded `sandbox/` from discovery sources explicitly.** This repo's
own pressure-test fixtures (the deliberately-broken `double()`, the contradictory tests)
would otherwise look exactly like real bugs to a naive commit/TODO scan. Discovering and
"fixing" them would be absurd — a good concrete example of why "find broken-looking code"
isn't the same as "find real work," and worth remembering if discovery sources ever expand.

**What's not done: scheduling is not activated.** The skill exists and runs on demand, but
nothing is invoking it on a cadence. Two reasons, both deliberate: (1) this repo has no
`origin` remote yet, so cloud scheduling (the more correct long-term answer, since it
doesn't need this machine to stay on) isn't available — same precondition already
documented for `ship`'s PR flow; local `/loop` is the only option right now, and it
requires the machine to stay on and expires after 7 days. (2) Turning on a recurring
trigger starts genuinely autonomous behavior that keeps running until someone turns it
off — that's a different category of action than building the skill, and activating it
silently would be exactly the kind of blast-radius mistake the whole safety model exists
to avoid making casually. Documented how to activate it in the skill file; not done
without a separate, explicit go-ahead.

## 2026-06-30 — First real (non-fixture) task, and it immediately justified itself

Directly called out: every run up to this point was a fixture built specifically to
demonstrate one mechanism. Pointed at real work instead — this repo's own missing
LICENSE, a genuine blocker to going public that had been identified in conversation but
not acted on. Correct instinct: the tool should be used on real problems, not asked about.

**It worked, and it found something no fixture would have.** The generator chose MIT
(correct, well-reasoned) but auto-filled the copyright holder from `git config`
(`dsvxmedia`) without treating it as a decision. Evaluator A verified internal consistency
(matches git config, matches canonical MIT text byte-for-byte) — PASS. Evaluator B
verified something categorically different — does this match who the user actually is —
and it didn't match this session's known identity, so REJECT. **First real disagreement
the loop has ever hit**, and it correctly escalated instead of averaging or picking a
side.

Turned out `dsvxmedia` was actually correct — confirmed by cross-referencing git remotes
across 6 of the user's other repos, all consistently under that GitHub account. But the
resolution matters as much as the finding: **an unconfirmed guess that happens to be right
is not the same as a verified fact**, and evaluator B was correct to block on it anyway.
This is the clearest validation yet of the whole verification-over-assumption philosophy
this project is built on — it would have been very easy to treat B's REJECT as a false
alarm once the value checked out, and that would have been the wrong lesson to take from
it. The value being correct doesn't retroactively make the unconfirmed version safe to
have shipped.

Logged as a durable fact in `memory/weaponx/MEMORY.md`: ambient config (git identity,
environment variables, etc.) is not a reliable source for anything that becomes
permanently public — treat it as a blocking question, not a plausible default, regardless
of how likely it is to be correct.
