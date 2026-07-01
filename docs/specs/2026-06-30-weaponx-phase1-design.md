# Weapon X — Phase 1: On-Demand Challenge Loop (+ Phase 1.5 Trust & Drift Layer)

## Context

The user wants a personal "ultimate" Claude Code loop they can point at their hardest
tasks — software engineering, marketing/content work, or open-ended research — that
runs fast, stays token-efficient, and is safe enough to eventually open-source on
GitHub. This is the first build in a deliberately phased rollout (decided during
brainstorming): prove a single on-demand loop with a real, trusted generator/evaluator
split before adding scheduled discovery (Phase 2) or an always-on background fleet
(Phase 3). That ordering follows the one piece of advice every researched source
converged on — Spotify's Honk, Anthropic's Managed Agents, Boris Cherny's tips, the
Loop Engineering paper, and the "Agent Loops Clearly Explained" video all treat
verification as the load-bearing piece, and all of them only added parallelism/scheduling
after the evaluator had a track record.

After the initial design pass, the user pushed for more on two rounds of feedback:
first, that a runner + verifier is not enough — the real white space is making the loop
**measurable, debuggable, and trustworthy** to a human who doesn't want to babysit it;
second, a "GOD tier" pass adding cross-task memory, self-improving skills, evaluator
redundancy, honest confidence reporting, and a clean engine/instance split so the
orchestrator itself (not just this one repo's task history) is genuinely reusable.
Both rounds are fully incorporated below.

The project directory (`Weapon X/`, currently empty) becomes the loop's home and,
eventually, the open-source repo. The loop is built on top of the user's already-installed
`gstack` skill suite (`qa`, `review`, `code-review`, `design-review`, `canary`, `benchmark`,
`investigate`, `triage`, `ship`, `browse`, `dev`, `tdd`, plus the marketing/content skill
catalog) rather than reimplementing verification, QA, or shipping mechanics from scratch.

Research basis (transcripts pulled via yt-dlp + read in full this session):
- Spotify (Honk): judge took them 20–30% → 80% PR success early on; removed once harness
  + base model matured — verification via real CI builds matters more long-term than a judge.
- Boris Cherny: codebase Q&A before editing, CLAUDE.md hierarchy for context economy, give
  the agent a way to check its own work so it iterates instead of the human, headless `-p`
  SDK as a scriptable utility.
- Anthropic (Jess Yan): agents evolved from prompting-loop → permissioned, long-running
  actors; built-in eval loop should run in a separate context to avoid self-grading bias;
  vibe-test before formal eval.
- "Agent Loops Clearly Explained": a loop = reason → act → observe, with an explicit,
  objective stop condition; hard caps on retries/runtime to avoid multi-day runaway loops.
- LLMOps/Eval primer video: distinguishes procedural / semantic (durable-fact) / episodic
  memory; recommends proactive notification rather than silent waiting on a stuck
  permission prompt.
- Loop Engineering paper (HuaShu/Osmani synthesis): five moves (discovery, handoff,
  verification, persistence, scheduling), generator/evaluator separation, four silent costs
  (verification debt, comprehension rot, cognitive surrender, token blowout), "add
  parallelism last" growth order.

## Decisions Locked In During Brainstorming

- **Scope:** one domain-agnostic orchestrator, not three separate tools. Domain (code /
  content / research) is inferred per task; gstack skills supply the domain expertise.
- **Trigger (Phase 1 only):** on-demand invocation via `/weaponx <task>`. Scheduled
  discovery and always-on mode are explicitly out of scope for this build.
- **Safety gate:** the loop may plan, code, test, and open PRs/draft deliverables
  autonomously. It must **never** merge, deploy, or publish anything externally
  (no auto-merge, no auto-send, no auto-post) — that always waits for the human.
- **Autonomy promotion is manual only.** The system never raises its own trust level.
  The drift dashboard and calibration checks (Phase 1.5) surface evidence; the human
  decides if/when to loosen the safety gate. This also covers skill self-improvement
  (below): the loop may *suggest* a CLAUDE.md/skill edit, it never applies one itself.
- **Token strategy:** model-tiering (cheap/fast model for discovery + mechanical
  verification checks, strong model for generation and judgment-heavy evaluation, with
  sub-step routing inside generation too) + context hygiene (skills over prompt walls,
  state files over chat history, worktrees over redundant re-reads, targeted reads over
  full-file dumps) + hard retry/budget caps.
- **State file:** committed to git (`state/weaponx/`), structured trace format (not a flat
  status table), since that structure is the substrate Phase 1.5 depends on.
- **Engine vs. instance data is a first-class split**, so the orchestrator itself can be
  open-sourced and adopted by someone else without dragging this project's specific task
  history, memory, or benchmark cases along. See Files to create.
- **External repo:** none — not integrating any outside repo into this build.

## Architecture — the five moves

| Move | What it does | Built on |
|---|---|---|
| Discovery | Parse the task, infer domain, read the cross-task semantic memory file plus only the task-specific context actually needed (relevant state/benchmark entries, targeted reads) | New thin logic in `weaponx` skill + `Explore` agent pattern for targeted reads |
| Handoff | Code tasks: isolated git worktree. Content/research tasks: a scoped sub-agent with an explicit, objective definition of done | `EnterWorktree`/`--worktree`, `/goal`-style stop conditions written into the dispatch prompt |
| Generation | Does the actual work, dispatched to a sub-agent on the strong model tier, with trivial/mechanical sub-steps routed to the cheap tier | gstack `dev`/`tdd` (code), `copywriting`/`content-strategy` (marketing), `understand`/research skills (research) |
| Verification | A separate sub-agent, separate context, cheap/fast model tier for mechanical checks — assumes broken until proven, acts rather than reads, classifies any rejection into a fixed failure taxonomy. For high-stakes tasks, a second independent evaluator must agree before PASS | gstack `qa`/`review`/`code-review`/`design-review`/`canary`/`benchmark`, dispatched via `weaponx-evaluator` (+ `weaponx-evaluator-b` for consensus cases) |
| Persistence | A structured, confidence-tagged trace record + PR/deliverable + a human-readable audit/handoff packet + a proactive notification if waiting on the human — never auto-merged or auto-published | gstack `ship` (handles commit/branch/PR, stops short of merge), `PushNotification` |

**Loop control:** generation → verification → if REJECT, the evaluator's failure-taxonomy
label plus the smallest identifiable fixable surface (specific files/lines/claims) feeds
directly into the next generation cycle as a targeted repair instruction — not a generic
"try again." Hard cap of **4 generate/verify cycles** per task; on hitting the cap, the loop
stops, fires a notification, and produces the audit/handoff packet for the human rather
than continuing to spin. Budget ceiling (token/turn count) is configurable in the skill's
frontmatter with a conservative default, and acts as a second, independent circuit breaker.

**High-stakes consensus rule:** a task is treated as high-stakes (triggers dual-evaluator
consensus) if its successful completion would produce a PR touching a protected path, an
externally-visible deliverable, or is explicitly flagged by the user at invocation time.
On disagreement between the two evaluators, the loop does not average or pick a winner —
it stops and escalates to the human with both verdicts and reasoning attached. This is the
direct fix for "what if the judge itself is wrong": a second, differently-prompted/
differently-modeled judge catches it before the calibration check would (which only runs
periodically, after the fact).

**Model tiering specifics:**
- Discovery + mechanical evaluator checks (test pass/fail, lint, build success, score
  vs. threshold) → fast/cheap model tier.
- Generation's trivial/mechanical sub-steps (boilerplate, formatting, mechanical renames)
  → fast/cheap tier; the genuinely hard sub-steps and any subjective evaluation → strong
  tier. The orchestrator classifies sub-steps at dispatch time rather than tiering only at
  the move level.

## Cross-task semantic memory (new)

Separate from the per-task trace in `state/weaponx/`. `memory/weaponx/MEMORY.md` holds
durable, project-spanning facts: standing preferences, recurring constraints, "we tried X
before and it failed because Y." Read in full on every `/weaponx` invocation during
Discovery (kept deliberately short, same discipline as CLAUDE.md, so it doesn't become a
context-bloat liability itself). Written to as a side effect of Persistence: the
orchestrator flags durable-fact candidates surfaced during a run and appends them after
a lightweight dedup/consolidation pass — no separate database, no embeddings
infrastructure, consistent with this being a personal tool first.

## Persistence design (expanded per user feedback)

Each `/weaponx` run writes one structured trace record to `state/weaponx/` containing:

- Task description, inferred domain, timestamp, high-stakes flag (yes/no and why).
- Per-cycle log: what was attempted, tool calls made, evaluator verdict(s) — both, if
  consensus mode — and **failure taxonomy label** when rejected (wrong-tool-choice /
  missed-step / stale-context / hidden-retry-loop / corrupt-success /
  latency-or-cost-blowout / policy-violation / other-with-detail), plus the specific
  fixable surface identified for the next cycle.
- Cost accounting: tokens and turns spent per cycle and in total, wall-clock time.
- Final verdict: PASS / hit-retry-cap / hit-budget-cap / escalated-on-disagreement, with
  links to the resulting branch/PR or deliverable.
- A short **audit/handoff packet**: what was attempted, what was actually checked (which
  gstack skill ran, what it verified), and a **per-claim confidence tag** —
  `verified` (e.g. tests actually ran and passed) vs. `asserted` (generator's claim,
  not independently checked) — so a PASS doesn't read as uniformly trustworthy when parts
  of it weren't actually exercised. Plus what remains uncertain and where to look first.
- If the run ends waiting on a human gate (review, permission, retry-cap, disagreement),
  a notification fires immediately rather than the loop sitting silently until next
  checked.

On REJECT or on a human override of a PASS, the task + reasoning + correct answer is also
copied into `benchmark/weaponx/` as a reusable eval case. This capture is a cheap
persistence-time side effect in Phase 1; *actively using* that growing gold set to check
evaluator calibration is Phase 1.5.

## Files to create (Phase 1)

Split into **engine** (portable, no project-specific data — what someone else would copy
to adopt Weapon X) and **instance data** (this repo's own accumulated state/memory/
benchmarks — what they would not copy):

```
ENGINE (portable):
.claude/skills/weaponx/SKILL.md
    The orchestrator. Encodes the five-move sequence, the retry cap, the budget ceiling,
    domain inference, sub-step model routing, the diff-aware retry behavior, the
    high-stakes consensus trigger, and an explicit "Stop" section stating the
    never-merge/never-publish boundary and the manual-only autonomy-promotion rule
    (including: suggests skill/memory edits, never applies them) in writing.

.claude/agents/weaponx-evaluator.md
    Dedicated adversarial reviewer sub-agent. Separate from the generator by
    construction. Default stance: assume broken until proven. Classifies any rejection
    into the fixed failure taxonomy and identifies the smallest fixable surface.

.claude/agents/weaponx-evaluator-b.md
    Second, differently-framed (and where practical, differently-modeled) evaluator used
    only for high-stakes consensus checks — kept genuinely independent from
    weaponx-evaluator rather than a copy with a different name.

.claude/skills/weaponx-calibrate/SKILL.md   (Phase 1.5, see below)
.claude/skills/weaponx-drift/SKILL.md       (Phase 1.5, see below)
.claude/skills/weaponx-replay/SKILL.md      (Phase 1.5, see below)

README.md (repo root)
    Written with eventual public release in mind: what Weapon X is, prerequisites
    (gstack installed), how to invoke `/weaponx <task>`, the safety boundary (including
    that autonomy promotion is manual-only by design and self-improvement suggestions are
    never auto-applied), the phased roadmap, and an explicit note on which files are
    engine vs. instance data for anyone forking the repo.

INSTANCE DATA (this repo's own, not part of the portable engine):
memory/weaponx/MEMORY.md     — cross-task durable facts (kept short)
state/weaponx/                — one structured trace file per run
benchmark/weaponx/            — eval cases captured from rejections/overrides
```

No existing files are modified — this is a greenfield build in an empty directory.

## Phase 1.5 — Trust & Drift Layer (built after Phase 1 has run history)

Gated on `benchmark/weaponx/` and `state/weaponx/` having accumulated enough real runs to
be meaningful:

```
.claude/skills/weaponx-calibrate/SKILL.md
    Periodically (not per-run) replays weaponx-evaluator against the accumulated
    benchmark/weaponx/ gold set and reports its current pass/fail agreement rate, so
    drift in the evaluator itself gets caught, not just drift in generated output.

.claude/skills/weaponx-drift/SKILL.md
    Query/aggregation over state/weaponx/*.json: tokens-per-run over time, retry rate
    over time, rejection-cause distribution by failure taxonomy label. Also flags
    recurring failure causes across otherwise-unrelated tasks (e.g. repeated
    stale-context rejections) as a signal that a CLAUDE.md/skill is missing something —
    and *suggests* a specific edit for human review. It never edits the skill itself,
    consistent with the manual-promotion rule.

.claude/skills/weaponx-replay/SKILL.md
    Reconstructs a single run step-by-step from its trace record, for debugging a
    specific failure without re-reading an entire chat transcript.
```

These give the human the evidence (and, for skill gaps, a concrete suggested fix) to
decide when to loosen the safety gate or update project knowledge — they do not
themselves loosen it or apply it.

## Verification

1. Confirm `/weaponx` is invocable as a skill and correctly infers domain on three
   smoke-test tasks: one code task (e.g. "fix a failing test in a small sample repo"),
   one content task (e.g. "write a product announcement paragraph"), one research task
   (e.g. "summarize the tradeoffs of X").
2. Confirm the evaluator sub-agent runs in a separate context from the generator (it
   cannot see the generator's chain-of-thought/self-justification, only the artifact and
   the task's done-criteria).
3. Deliberately feed a task that should fail verification (e.g. code with a broken test)
   and confirm: the loop retries with the failure-taxonomy label and targeted fix surface
   attached, stops at the 4-cycle cap if still failing, fires a notification, and produces
   a clear audit/handoff packet with confidence tags rather than silently giving up or
   looping forever.
4. Force a high-stakes task into evaluator disagreement (e.g. craft a borderline case) and
   confirm the loop escalates to the human with both verdicts rather than averaging or
   silently picking one.
5. Confirm nothing merges, deploys, or publishes without an explicit human approval step.
6. Confirm the structured trace file is written and committed, the REJECT case was copied
   into `benchmark/weaponx/`, the semantic memory file picked up any durable-fact
   candidates from the run, and a second `/weaponx` invocation referencing related context
   reads from memory/state rather than re-deriving it from scratch (token-hygiene check).
7. Spot-check token/turn cost of one full run against the configured budget ceiling, and
   confirm at least one trivial sub-step in a generation run was actually routed to the
   cheap model tier (not just discovery/eval).
8. Confirm the engine/instance split holds: the `.claude/skills/weaponx*` and
   `.claude/agents/weaponx*` files contain no hardcoded references to this project's
   specific state, memory, or benchmark contents.
9. (Once enough runs exist) Smoke-test `weaponx-drift` and `weaponx-calibrate` against the
   accumulated data, including a check that a manufactured recurring-failure pattern
   correctly produces a suggested (not applied) CLAUDE.md/skill edit.

## Explicitly out of scope for this build (future phases)

- **Phase 2:** a `weaponx-discover` skill on a recurring trigger (cron / `ScheduleWakeup`
  / GitHub Actions schedule) that scans for work and feeds the same state file the
  orchestrator already reads from.
- **Phase 3:** parallel dispatch across multiple worktrees/sub-agents at once, once the
  evaluator's reject rate from Phase 1 is known and trusted enough to scale.
- **Autonomy auto-promotion:** deliberately not built. Trust-level changes, and skill/
  memory edits suggested by the drift layer, always stay a manual human decision.
