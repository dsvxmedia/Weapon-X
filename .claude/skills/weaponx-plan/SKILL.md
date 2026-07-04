---
name: weaponx-plan
description: Phase 1.6. Takes a large, open-ended idea (too big for one bounded task) and turns it into something weaponx can actually execute — brainstorm/clarify with gstack office-hours, produce a real architectural plan with autoplan/plan-eng-review, decompose it into a dependency-ordered sequence of normal-sized stages, get exactly ONE human approval on the whole plan, then dispatch each stage sequentially through the unmodified /weaponx five-move loop. Never parallel, never auto-merge. Stops the whole sequence if any stage fails rather than proceeding on a broken dependency.
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

# Weapon X Plan — Large-Idea Decomposer

This is the layer that sits **above** the core five-move loop in
`.claude/skills/weaponx/SKILL.md`, not a replacement for it — the same relationship
`weaponx-discover` has to that loop. `weaponx-discover` automates *finding* one bounded
task; `weaponx-plan` automates *decomposing one huge idea* into many bounded tasks. Both
still dispatch every unit of real work through the same unmodified `weaponx` loop, with the
same generator/evaluator split, the same retry cap, the same never-merge boundary.

## What makes this different in kind from a normal `/weaponx <task>` call

A normal `/weaponx <task>` invocation expects something **already scoped to one bounded
task** — "add a LICENSE file," "fix the retry-cap double-count," "wire up the Telegram
bridge." The core loop's whole design (a single worktree, one trace file, a `MAX_CYCLES`
retry budget, one `BUDGET_CEILING`) is sized for exactly that: one bounded piece of work
that four generate/verify cycles can plausibly converge on.

`weaponx-plan` exists for the opposite input: a **genuinely large, open-ended idea** — the
motivating example was "build a complex iOS app," but this skill is deliberately
domain-agnostic and must work for any large idea in any domain (a multi-service backend, a
research program with many sub-questions, a full marketing-site launch, whatever). You do
**not** fire an idea that size at a single `/weaponx` call. That would ask one 4-cycle retry
loop to converge on something that is really many tasks' worth of work, against a budget
ceiling that was never sized for it. Nobody has evidence that works, and the architecture
doesn't support it.

So this skill's job is: take the big idea, plan it properly, cut it into normal-sized
bounded stages, get one human sign-off, and then run those stages one at a time through the
loop that already works.

## The core design insight (read this before anything else)

**Decomposition is the fix for the budget-ceiling problem — not raising the ceiling.**

The obvious-but-wrong move would be: "a big idea needs more cycles / more tool-calls, so
bump `MAX_CYCLES` and `BUDGET_CEILING` for this run." That's wrong because it doesn't
actually make a huge, multi-part task convergeable — it just lets one undifferentiated loop
thrash longer and spend more before failing, with no natural checkpoints and one giant
worktree holding everything at once.

Instead, `weaponx-plan` cuts the idea into stages **each sized to be a normal, single
bounded `/weaponx <task>` on its own.** Once every stage is normal-sized again, the
*existing* per-task defaults (`MAX_CYCLES: 4`, `BUDGET_CEILING: ~40/cycle, ~150/run`) are
correct as-is for each stage. The ceiling never needed raising; the *unit of work* needed
shrinking. Each stage gets its own fresh cycle budget, its own worktree, its own trace
file, its own evaluator dispatch — exactly as if a human had typed `/weaponx <that stage>`.
Future readers (including a fork): this is why you will not find a raised budget number
anywhere in this skill.

## Move A — Take the idea and plan it (using gstack's real planning skills)

Do not reimplement planning logic here. Use the planning skills that already exist, the way
`weaponx`'s own Generation move names `dev`/`tdd`/`copywriting` as its mechanism rather than
reimplementing them:

1. **Brainstorm / clarify the idea** with gstack `office-hours` — surface the real intent,
   the constraints, the unknowns, the parts the user hasn't specified yet. A large idea
   almost always arrives underspecified; this is where that gets resolved, in conversation,
   before any architecture is drawn.
2. **Produce a real architectural plan** with gstack `autoplan` (the auto-review planning
   pipeline) or `plan-eng-review` (eng-manager-mode plan review) — whichever fits the
   domain. This is the actual architectural thinking: what the pieces are, how they fit,
   what has to exist before what. Let the planning skill do this; `weaponx-plan`'s job is to
   *drive* it and then *consume its output*, not to be a second planner.

The output of Move A is a real plan — not yet a stage list. Move B turns it into one.

## Move B — Decompose into a dependency-ordered sequence of bounded stages

Take the architectural plan from Move A and cut it into **discrete stages**, where each
stage is:

- **Sized like one normal `/weaponx <task>` invocation** — bounded enough that a single
  generate/verify loop with the standard cycle/budget defaults can plausibly converge on it.
  If a candidate "stage" is obviously still too big for one bounded loop, split it again.
  (This is the whole point — see "The core design insight" above.)
- **Ordered by real dependency, not convenience.** A stage that produces something a later
  stage consumes must come first — a data model before the UI that reads it, an API contract
  before the client that calls it, a research finding before the writeup that cites it. Write
  down, for each stage, *what it depends on from the prior stage(s) and why*. That dependency
  reasoning is not decoration — it's what makes the sequential ordering auditable by the human
  at the approval gate, and it's what tells you which later stages must be abandoned if an
  earlier one fails (Move E).

**Hard constraint — stages run strictly sequentially, one at a time, never in parallel.**
Phase 3 (always-on / parallel dispatch across multiple tasks at once) is explicitly
documented in this repo as **not built yet** (see `CLAUDE.md` "Current phase" and the design
spec). `weaponx-plan` must not become a quiet backdoor into building it. Even when two stages
look independent, this skill dispatches them one after another and waits for each to finish
and pass before starting the next. "These two don't depend on each other, so run them
together" is exactly the Phase 3 move that is out of scope here — do not make it.

## Move C — Get exactly ONE human approval on the assembled plan (the load-bearing gate)

**This is the single most important gate in this skill, and it is not allowed to be soft** —
the same way Verification is "the part that is not allowed to be soft" in the core loop.
Everything after this gate runs semi-autonomously across multiple stages with no further
per-stage sign-off, so this one approval is the human's whole window of control over the
staged run. Get it right.

Present the human the **complete assembled plan** to approve as a single unit:

- The original idea as they gave it.
- The full ordered stage list, and for each stage: what it does, and what it depends on from
  the prior stage(s) and why.
- The explicit note that, once approved, these stages will run sequentially and
  semi-autonomously through the standard `/weaponx` loop, each unmerged/undrafted at the end
  (never auto-shipped), and that the sequence stops on the first stage that fails.
- **A required aggregate-scope summary line — this is not optional framing.** Because this
  is the *only* approval (the single-approval design deliberately removes every subsequent
  per-stage checkpoint to avoid approval fatigue), the human must not have to mentally
  multiply out what they're signing off on. State it explicitly: the **total stage count**,
  and the **worst-case cumulative budget** — e.g. "this plan has N stages; each runs as its
  own `/weaponx` task and can use up to weaponx's own per-task budget ceiling
  (~150 tool-calls / 4 cycles), so worst case this plan could run to **N × that ceiling**
  before it finishes or stops on a failure." Phrase it honestly as a **worst-case upper
  bound, not an estimate of typical cost** — most stages won't hit their own individual cap,
  and the summary line must say so rather than implying N × ceiling is the expected spend.
  Presenting the itemized stage list is not a substitute for this line: the itemization
  shows *what* each stage is, the summary line shows *how much unattended time/budget the
  single approval is authorizing in total*. Omitting it is not allowed.

Then get exactly **one** approval:

- **If PUSH is configured** (`TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are *both* set in
  the environment): send the plan as a decision brief over Telegram, reusing the exact
  optional-only-if-configured pattern already used in `weaponx/SKILL.md`'s Move 4/5:
  `.claude/skills/weaponx-push/bin/push-bridge.sh brief --id <plan-slug> --text "<the plan
  + a clear recommendation + 'approve / revise / cancel' plus the implicit free-text 'or
  tell me what to change instead' path>"`, then
  `.claude/skills/weaponx-push/bin/push-bridge.sh wait --id <plan-slug>` for the reply that
  resumes the skill. **If PUSH is not configured, the bridge exits with a "skipping" status
  and the loop proceeds exactly as it does today** — PUSH is never a dependency here.
- **If PUSH is not configured:** this is a normal in-session decision point. Use
  `AskUserQuestion` (or the equivalent explicit-confirmation pattern this repo's skills use
  for a real decision) to get an unambiguous approve / revise / cancel. Do not infer approval
  from silence or from an earlier "go ahead" that predates the assembled stage list — the
  approval must be on *this* stage list, in *this* order.

If the human revises, update the plan and re-present it — but this is still **one approval
gate on the final plan**, not per-stage approval (see LEARNING.md for why per-stage approval
was deliberately rejected). Only dispatch once you hold an explicit yes on the assembled
plan. Write the plan-level state file (see Move F) at this point, before dispatching anything.

## Move D — Dispatch each stage through the UNMODIFIED `/weaponx` loop, sequentially

Once approved, for each stage in order:

1. Invoke the `weaponx` skill on that stage's task text **exactly as an on-demand
   `/weaponx <task>` call would be** — do not reimplement discovery, handoff, generation,
   verification, or persistence here. The stage's task text goes in as the task; the core
   loop does the rest.
2. Each stage keeps **its own normal `MAX_CYCLES` / `BUDGET_CEILING`, its own worktree, its
   own trace file under `state/weaponx/`, its own evaluator dispatch** (including
   dual-evaluator consensus if that stage independently trips a `HIGH_STAKES_TRIGGERS`
   condition — that determination is the core loop's to make, per-stage, not this skill's to
   pre-empt).
3. Wait for that stage's final verdict before starting the next stage. Never start stage N+1
   while stage N is still in flight — that would be parallel dispatch (out of scope, Move B).

**Hard constraint on this skill:** nothing about the core loop's guarantees gets weakened or
bypassed for staged work. Generator/evaluator separation, never-merge/never-publish, the
retry cap, verification-is-never-skipped — all of it holds identically for a stage dispatched
by `weaponx-plan` as for a stage a human typed by hand. `weaponx-plan` adds a layer *on top
of* the loop; it does not get to reach *inside* it.

**How this skill learns a stage's outcome — by reading, not by being told.** `weaponx-plan`
determines whether a stage passed or failed by reading that stage's own `state/weaponx/`
trace file **after the fact** (its final verdict line: `PASS` / `hit-retry-cap` /
`hit-budget-cap` / `escalated-on-disagreement`). It does **not** require the core loop to
know it's being called as part of a plan, and it does not modify `weaponx`, `weaponx-discover`,
or any evaluator definition to report completion "upward." This is deliberate: keeping
`weaponx-plan` a pure consumer of trace files means the core five moves stay genuinely
unmodified, and a stage dispatched inside a plan is byte-for-byte the same run as a stage a
human dispatched alone. (See the report/LEARNING.md entry for why this after-the-fact-read
approach was chosen over a hook in the core loop's Persistence step.)

## Move E — Failure handling: one failed stage stops the whole sequence

If any stage's trace ends in `hit-retry-cap`, `hit-budget-cap`, or a `REJECT`/
`escalated-on-disagreement` that the core loop's own retry logic could not resolve within
its cycle cap:

- **STOP the whole sequence.** Do not start the next stage. Do not silently proceed as if
  the failed dependency had succeeded — a later stage that depends on a failed one must
  **never** run. (A stage that provably depended on nothing from the failed one *still* does
  not auto-run here; stopping is the safe default, and resuming is a human decision, same
  spirit as the core loop's "cap that resets on re-invocation isn't a cap.")
- **Notify the human immediately** — same pattern as `weaponx`'s Move 5. Tell them: which
  stage failed, why (the failure verdict and, where the trace has it, the failure-taxonomy
  label and fixable surface), what's already **done** (the passed stages, with links to their
  traces), and what's still **pending**. If PUSH is configured, send this as a decision brief
  (`push-bridge.sh brief` + `wait`) so the human can decide from their phone whether to fix
  the failed stage and resume, revise the remaining plan, or abandon it. If PUSH is not
  configured, surface the same information in-session immediately rather than waiting to be
  asked.

Resuming after a fix is a fresh, explicit human-initiated action — this skill stops and hands
control back; it does not retry the failed stage on its own beyond the cycle budget the core
loop already spent.

## Move F — Track plan-level state

Create **one file per plan** at `state/weaponx/plans/<plan-slug>.md`.

**Why one-file-per-plan and not a single running log** (like `discovery-log.md`): a plan is
a specific multi-stage *project* with its own lifecycle — it starts, runs through an ordered
set of stages, and ends (all done, or stopped at a failure). That is fundamentally different
from `discovery-log.md`, which is a *stream of independent discovery events* with no shared
lifecycle, correctly kept as one append-only running file. Giving each plan its own file lets
its live per-stage status be updated in place as stages complete, keeps unrelated plans from
tangling in one log, and matches how each *run* already gets its own trace file rather than
sharing one. State this same reasoning in the file's own header comment so a future reader
sees why the choice was made.

Each plan file records (keep the established `state/weaponx/` voice — plain-language summary
first, technical detail after, matching the same convention `weaponx`'s own `SKILL.md` Move 5
describes for its trace files: lead with the outcome in plain language, then the technical
detail underneath. For a concrete, portable illustration of a filled-in plan file, see
`state/weaponx/plans/example-illustrative.md` — a hand-authored, clearly-labeled example, not
a real run):

- **The original idea** as the user gave it.
- **The approved stage list**, in order — each stage's scope and its dependency reasoning
  (what it needs from the prior stage(s) and why), exactly as approved at the Move C gate.
- **Live per-stage status:** `pending` / `in-progress` / `done` / `failed`, updated in place
  as the sequence runs, each `done`/`failed`/`in-progress` stage linking to that stage's own
  individual trace file under `state/weaponx/` once it exists.
- **The overall plan verdict** once the sequence ends: all stages done, or stopped-at-stage-N
  with which stage failed and why.

This is genuinely new state-tracking territory for this repo — there is no exact prior
pattern to copy. Use judgment on the exact layout, but keep it consistent with the tone and
structure of the existing `state/weaponx/` files (outcome first, detail after).

## Portability (same rule as every other engine skill)

`weaponx-plan` lives under the portable engine (`.claude/skills/weaponx-plan/`), alongside
`weaponx` and `weaponx-discover`. It must not hardcode anything specific to *this* project's
own accumulated state, memory, or benchmark contents — same rule documented for every engine
skill in root `CLAUDE.md`. It references `state/weaponx/` and `state/weaponx/plans/` as
*locations* (fine — those paths are part of the engine's contract), never any specific
project's stage lists or plan history.

## Hard boundaries (explicit — do not infer or relax these)

1. **Exactly one human approval gate**, on the full assembled plan, before any stage is
   dispatched (Move C). No per-stage auto-approval, and no dispatching before the gate.
2. **Stages run strictly sequentially, never in parallel** (Move B/D). This skill is not a
   backdoor to Phase 3.
3. **Every stage goes through the unmodified `weaponx` loop** — no core-loop guarantee
   (generator/evaluator split, never-merge, retry cap, verification-never-skipped) is
   weakened, bypassed, or re-implemented for staged work (Move D).
4. **One stage failing stops the whole sequence** — no proceeding on a failed dependency, and
   an immediate human notification (Move E).
5. **Never merge, deploy, or publish** — inherited whole from the core loop. Every stage ends
   at an unmerged PR / unpublished draft, and the plan as a whole never ships anything itself.
   Approving the *plan* at Move C is approval to *run the stages*, not to merge their output;
   each stage's own PR/draft still awaits a human exactly as any `/weaponx` run does.
