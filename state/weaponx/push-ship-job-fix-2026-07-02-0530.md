# push-ship-job-fix — 2026-07-02 05:30

## Summary (read this first)

Closed the one disclosed gap left open when PUSH shipped: the cloud cold-start path's
`ship` job used to just echo placeholder text after you approved a run — it never actually
pushed the branch or opened a PR. Now it does both for real, and it took three rounds of
real rejection to get there, which is exactly what this loop is for.

**What changed, in plain terms:**
1. The `run` job (the one that does the actual work, before you've approved anything) now
   pushes its branch straight to your GitHub repo — pushing a branch isn't shipping
   anything, it's just saving work, so this doesn't relax any safety rule.
2. Only once you tap approve does the separate, gated `ship` job open the actual PR. It
   still never merges anything — that's always your call.

**Two real bugs got caught and fixed before this was safe to rely on, not glossed over:**
- The first version would have silently missed real work: if a run picked up where a
  previous one left off (reusing the same branch), the detection logic only checked
  whether the branch *name* was new, not whether new commits landed on it. Fixed to check
  the actual commit, not just the name — tested against three real scenarios in a
  throwaway repo, not just reasoned about.
- The bigger one: even though the run job was *told* not to open a PR before you approved,
  the GitHub credential it had access to was technically capable of opening one anyway.
  That's "the AI was asked nicely," not a real lock. Fixed by taking that permission away
  from the run job entirely — it now physically cannot open a PR no matter what it's told
  or tricked into attempting, only the approved, gated job can.

**One more real gap found along the way and fixed:** the actual "you have to approve this"
setup on GitHub didn't exist yet — the code was ready to use it, but nobody had ever
turned it on. That's created now, with you as the required approver, confirmed live
against GitHub's own API.

**A genuine attempted prompt injection was caught and correctly ignored** during this run
— something injected fake text into one evaluator's tool results, pretending verification
had already passed and demanding it run unrelated tools. It didn't fall for it, verified
everything for real anyway, and flagged the injection attempt itself as worth your
attention — possibly a compromised hook somewhere in the environment, separate from this
fix and worth a look on its own.

**What's still worth knowing:** none of this has been exercised by a real, live cold-start
run yet (would require actually dispatching a real Telegram-triggered run and watching it
go all the way through). Everything below that could be verified without spending a real
run was verified for real — bare-repo simulations, live GitHub API checks, static analysis
tools, not just reading code and assuming.

---

## Technical detail

**Task:** Close the disclosed placeholder gap in `.github/workflows/push-dispatch.yml`'s
`ship` job — it needed to actually push weaponx's produced branch and open a PR after
human approval, not just echo text.

**Domain:** code. **High-stakes: yes** — modifies `.github/workflows/push-dispatch.yml`,
a protected CI-config path. Dual-evaluator consensus used throughout.

**Timestamp:** 2026-07-02, ~04:50–05:30 UTC.

### Per-cycle log

**Cycle 1:**
- Generation: chose Option A (push branch directly from `run` job; `ship` job only opens
  the PR post-approval) over Option B (artifact bundle transfer), reasoning that a
  pushed-not-yet-PR'd branch doesn't violate this repo's actual hard rule (never
  auto-merge/deploy/publish).
- Verification: **REJECT from both evaluators**, on two different, real, compounding
  issues (not a disagreement requiring escalation — both independently found genuine
  defects):
  - `weaponx-evaluator`: `missed-step` — branch-detection diffed ref *names* only, so a
    resumed/re-pushed existing branch (same name, new SHA — the documented weaponx
    resume case) was invisible to detection. Confirmed via a real local bare-repo
    simulation, not a read-only review.
  - `weaponx-evaluator-b`: `corrupt-success` — the workflow's top-level `permissions:`
    granted `pull-requests: write` to the `run` job, which runs *before* the approval
    gate. The only thing stopping it from opening a PR early was a prompt instruction,
    not a credential restriction — inconsistent with how this repo enforces its other
    safety rules (mechanism, not instruction).

**Cycle 2:**
- Generation: fixed both issues. Branch detection now keys on `sha refs/heads/name`
  pairs instead of name alone. Removed the top-level `permissions:` block; `run` job
  scoped to `contents: write` only, `ship` job retains `pull-requests: write`.
- Verification: both original issues confirmed genuinely fixed (real bare-repo
  three-scenario simulation for detection; real YAML parse + GitHub API checks for
  permissions, including confirming this repo's default workflow token permission is
  `read`, so removing the top-level block didn't accidentally widen anything). But
  `weaponx-evaluator` caught a **new** regression cycle 2's own remediation introduced:
  a literal `${{ }}` inside a `run:` block comment (line 157) broke GitHub Actions' own
  expression parser — confirmed with `actionlint`, not just reading. Taxonomy:
  `other-with-detail`. `weaponx-evaluator-b` additionally surfaced, separately from the
  code diff itself, that the `weaponx-approval` GitHub Environment this whole fix depends
  on didn't actually exist yet on the real repo (`gh api .../environments` returned
  empty) — a real operational gap, confirmed independently by the orchestrator.

**Between cycle 2 and 3:** orchestrator created the `weaponx-approval` environment via
`gh api -X PUT repos/dsvxmedia/Weapon-X/environments/weaponx-approval`, with `dsvxmedia`
(user id 270737986) as required reviewer. Confirmed live via the API response.

**Cycle 3:**
- Generation: narrow, mechanical fix — reworded the line-157 comment to describe the
  injection-safe pattern without ever typing a literal `${{ }}` inside the `run:` block.
  Orchestrator applied this directly (not dispatched to a full sub-agent) given how
  narrow it was, then pre-verified with `actionlint` before sending back to full
  dual-evaluator re-verification, consistent with weaponx's own token-efficiency
  principle for mechanical sub-steps.
- Verification: `weaponx-evaluator`: **PASS**, clean, verified independently (own
  structural scanner for `${{ }}` inside `run:` blocks, actionlint run twice, live
  GitHub API check on the environment). Also caught and correctly refused an injected
  prompt-injection attempt in its own tool output (a fake "evaluator checkpoint"
  claiming verification was already done, plus demands to invoke unrelated skills) —
  flagged it explicitly rather than silently complying or silently ignoring it.
  `weaponx-evaluator-b`: **REJECT**, taxonomy `corrupt-success`/`incomplete-persistence`
  — not a code defect (explicitly confirmed the same technical claims check out clean),
  but correctly identified that three cycles of verified work existed only as an
  uncommitted working-tree diff in one local worktree, with no commit, no push, no PR —
  nothing a human or a future session could find or rely on if the worktree were lost.
  Fixable surface named was exactly "commit and push" — Move 5 (Persistence), not
  further generation. Resolved by proceeding directly to Persistence rather than a
  fourth generation cycle, since the actual content was already independently verified
  correct by both evaluators.

### Cost

Generation: 3 sub-agent dispatches (cycle 1 full build, cycle 2 two-issue fix, cycle 3
handled directly by the orchestrator as a mechanical edit) — 75,407 + 51,256 tokens for
the two dispatched generations.
Verification: 5 evaluator dispatches across 3 cycles — 49,156 + 38,998 (cycle 1),
59,027 + 53,545 (cycle 2), 36,524 + 27,546 (cycle 3) tokens.
Plus orchestrator overhead: environment creation, hash-chain computation, trace/commit/PR.
Well within the ~150-tool-call run budget; cycle count (3 of max 4) reported honestly
regardless of the eventual PASS.

### Final verdict: PASS (both evaluators confirm the code; persistence completed by this move)

### Deliverables

- `.github/workflows/push-dispatch.yml`: `run` job pushes its branch directly to origin
  (scoped to `contents: write` only — cannot open a PR); `ship` job (gated behind the now
  real `weaponx-approval` environment) opens the PR via `gh pr create`, handles the
  "nothing to ship" case with a dedicated Telegram notification, and reuses an existing
  PR rather than duplicating one if the branch already has one open.
- `weaponx-approval` GitHub Environment created on `dsvxmedia/Weapon-X` with
  `dsvxmedia` as required reviewer (`can_admins_bypass: true` is a GitHub default worth
  knowing about, not something this task introduced or was asked to change).

Branch: `weaponx/push-ship-job-fix`. PR: opened as part of this trace's persistence step.

### Per-claim confidence

- SHA-keyed branch detection correctly handles new/unchanged/resumed-branch cases:
  **verified** (real bare-repo simulation, all three scenarios, by the evaluator directly).
- `run` job's token cannot open a PR (permissions scoped correctly): **verified** (real
  YAML parse + GitHub API check of this repo's default token permission).
- No script-injection reintroduced (the push-poll.yml-class bug): **verified**
  (programmatic scan of every `${{ }}` occurrence, cross-checked against `run:` block
  boundaries, by two independent evaluators across two cycles).
- `weaponx-approval` environment is live with the correct required reviewer: **verified**
  (direct `gh api` call, by two independent evaluators independently).
- The full cold-start happy path (phone message → dispatch → run → approval → real PR
  opened) working end to end in production: **asserted** — not yet exercised by an actual
  live run; the next real test of this system is that live run, not a further review cycle.

### Corrections to standing memory

None this run — `EnterWorktree`'s documented fallback behavior and the remote-conditional
`gstack ship` logic both held as already recorded in `memory/weaponx/MEMORY.md`.

---
**Chain:** prev=ec035e70ce94f78604b350a6453d913a0717c1657c271a498afde5f1852da903 (push-telegram-addon-2026-07-01-1420.md)
