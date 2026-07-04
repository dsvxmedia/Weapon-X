# weaponx-auto-update-2026-07-04-0010

## Summary (read this first)

Built the auto-update mechanism you asked for — matching how gstack does it. Every
weaponx skill now checks, cheaply and silently, whether a newer version exists on GitHub
before doing its real work, and offers to update if so. A new `weaponx-upgrade` skill
does the actual pull, staged and swapped atomically so a failed update can never leave
your global install half-broken.

**It took two real rejection rounds, and one of them was genuinely serious.** The first
round found nothing wrong with the mechanism itself, but caught a real concurrency gap:
two upgrade attempts running at the same moment (a realistic scenario given this repo's
own local `/loop` scheduling can run alongside a separate interactive session) could have
silently corrupted your global skill install with no error shown. Fixed with a real
exclusive lock, tested against an actual forced concurrent run, not just reasoned about.

**The second round is the one worth reading carefully.** While re-verifying the fix, one
evaluator's own test setup had a bug that caused it to actually run test logic against
your *real* global install for a moment — overwriting the real `weaponx/SKILL.md` and
both evaluator agent files with fake test content, and creating two files that shouldn't
exist yet. The evaluator caught this, said it fixed it, and reported everything restored.
**That report was wrong.** When I checked independently afterward, `weaponx/SKILL.md` in
your real global install still had test content in it, and both bogus files were still
there. I found this by actually diffing your global install against this project's real
GitHub history, not by trusting the evaluator's account of its own cleanup. I fixed it
properly and confirmed it byte-for-byte before writing this summary. Nothing else in your
global install (the other five skills, `weaponx-plan`) was touched by this.

**The second evaluator never actually finished its review.** It hit the same Pro
subscription usage limit that's come up a couple of times tonight, mid-run, with no
verdict rendered — not a REJECT, just incomplete. Rather than silently treat one evaluator
as "good enough" and move on, I stopped and asked you directly. You told me to proceed.
This trace records that as an explicit, informed choice, not a silently lowered bar — the
one evaluator that did finish tested the fix unusually hard (forced a real two-process
race, forced a real mid-swap failure, confirmed a failed upgrade doesn't lock you out of
future ones), so the risk of proceeding on it alone is real but modest, not reckless.

**What's ready to use, and what needs your action:** all six merged skills now have the
version-check preamble; `weaponx-upgrade` exists and is tested against fake install
targets. The one thing that only works once this PR merges: the version check calls
GitHub's raw-content API for this repo, which won't return real content until `VERSION`
and the preambled skills are actually on `main`.

---

## Technical detail

**Task:** build a gstack-style auto-update mechanism — version-check preamble on every
weaponx skill, plus a dedicated `weaponx-upgrade` skill to perform the actual pull.

**Domain:** code. **High-stakes: yes** — core distribution/installer infrastructure; a
bug here has real blast radius against the user's global, cross-project skill install.
Dual-evaluator consensus required; see below for how that requirement was actually met.

**Timestamp:** 2026-07-02 ~06:45 through 2026-07-04 ~00:10 (spans the session-limit wait).

### Per-cycle log

**Cycle 1:**
- Generation: `VERSION` file (semver, `1.0.0` — chosen because the engine's changes are
  feature-shaped, not calendar-shaped, and semver can distinguish a breaking change from
  a typo fix in a way a date can't). Identical version-check preamble prepended to all six
  currently-merged skills (`weaponx`, `weaponx-discover`, `weaponx-calibrate`,
  `weaponx-drift`, `weaponx-replay`, `weaponx-push`) — confirmed byte-identical across all
  six via hash comparison. New `weaponx-upgrade` skill: shallow clone, stage-then-verify,
  atomic per-item swap with per-item backup and full rollback on failure. Shared version
  marker at `~/.claude/skills/weaponx-version` so all skills agree on one installed
  version rather than drifting independently. Deliberately did not run the real upgrade
  skill against the user's actual global install as part of building it — tested against
  fake targets instead, with destination redirected via `WEAPONX_SKILLS_DIR`/
  `WEAPONX_AGENTS_DIR` env vars specifically so this kind of test never needs to touch
  the real thing.
- Verification: `weaponx-evaluator`: **PASS** — extensively re-tested (happy path, broken
  source, malformed version, a genuinely forced mid-swap failure via `chflags uchg`,
  early-failure staging-dir-leak check), all against fake targets, byte-level snapshot
  diffs before/after each destructive test. `weaponx-evaluator-b`: **REJECT**, taxonomy
  `other-with-detail` (a concurrency race, not covered by the fixed taxonomy's more
  code-defect-shaped categories) — no exclusivity on the staging directory; second-
  granularity timestamp naming meant two concurrent invocations (a real path via this
  repo's own `/loop` local scheduling running alongside a separate session) could race,
  collide on staging/backup names, and let one process's rollback corrupt the other's
  already-successful swap. Real, concrete, not hypothetical — evaluator A's test matrix
  never exercised concurrent invocations at all, which is exactly why dual-evaluator
  consensus caught this and a single evaluator might not have.

**Cycle 2:**
- Generation: added an exclusive `mkdir`-based lock (no `-p`, so it's atomic) taken before
  the clone, released via `trap ... EXIT` on any exit path; switched staging-directory and
  backup naming from bare second-granularity timestamps to `mktemp -d` plus a
  timestamp+PID run id, as defense in depth beyond the lock. Also added an explicit
  accepted-risk note to LEARNING.md: no commit-hash pinning or signature verification on
  the clone, relying only on GitHub's branch protection on `main` — judged acceptable for
  a personal, single-maintainer tool, worth reconsidering if that ever changes.
- Verification round 1: `weaponx-evaluator`: **PASS** — actually forced two concurrent
  invocations against a fake target (one backgrounded with an injected pause after lock
  acquisition, a second fired mid-pause), confirmed the second correctly refused, confirmed
  the lock releases correctly after both a clean success and a genuine forced failure,
  confirmed a failed upgrade doesn't permanently lock out a subsequent clean one. Disclosed,
  mid-review, that its own test-harness extraction logic had accidentally pulled the
  illustrative example code block out of the skill file alongside the real script, which
  caused the resulting concatenated script to run for real against the evaluator's actual
  global install — caught via diff, self-reported as fully restored and confirmed clean.
  **That self-report was independently checked by the orchestrator (this trace) and found
  incomplete**: `weaponx/SKILL.md` in the real global install still contained the
  preamble/test content that should only exist in this uncommitted worktree, and two bogus
  artifacts (`~/.claude/skills/weaponx-upgrade/`, `~/.claude/skills/weaponx-version`)
  remained. Restored `weaponx/SKILL.md` from `origin/main` directly, deleted both bogus
  artifacts, re-verified byte-for-byte against `origin/main`, and confirmed the other five
  globally-installed skills were untouched throughout. `weaponx-evaluator-b`: **incomplete**
  — terminated mid-run on the same Pro subscription session-usage limit that surfaced
  earlier tonight during PUSH testing; produced no verdict, not a REJECT.
- Given the second evaluator never rendered a verdict, full dual-evaluator consensus for
  this cycle was not achieved through the normal mechanism. Reported this plainly rather
  than silently treating one PASS as sufficient, and asked the human directly how to
  proceed (wait for the session-limit reset, or explicitly accept the single completed
  evaluator's verdict for this cycle). The human chose to proceed. This is recorded here
  as an explicit, informed decision to relax the dual-evaluator requirement for this one
  cycle — not something the loop decided on its own.

### Cost

Generation: 2 sub-agent dispatches (cycle 1 full build, cycle 2 concurrency fix).
Verification: 3 completed evaluator dispatches across 2 cycles, plus 1 incomplete
(session-limit termination, no tokens-to-verdict since it never rendered one).
Plus orchestrator overhead: discovery, worktree setup, the global-install corruption
investigation and fix (a real, unplanned but necessary cost), applying the preamble to
the separate weaponx-plan branch, hash-chain computation, trace/commit/PR.

### Final verdict: PASS, on one completed high-stakes evaluator (weaponx-evaluator) plus
an explicit human decision to proceed without the second evaluator's verdict, given the
session-limit interruption. Not a unanimous dual-evaluator consensus in the normal sense
— recorded honestly as such, not glossed over.

### Deliverables

- `VERSION` (repo root), semver `1.0.0`.
- Version-check preamble on `weaponx`, `weaponx-discover`, `weaponx-calibrate`,
  `weaponx-drift`, `weaponx-replay`, `weaponx-push` (all six currently-merged skills).
- New `.claude/skills/weaponx-upgrade/SKILL.md`.
- `CLAUDE.md`, `LEARNING.md` updated with the versioning convention and full design
  rationale, including the concurrency fix and the accepted supply-chain-trust risk.
- Separately: the identical, already-verified preamble applied to `weaponx-plan`'s own
  still-open branch (PR #6), so all seven skills stay in sync once both PRs land.

Branch: `weaponx/auto-update`. PR: opened as part of this trace's persistence step.

### Per-claim confidence

- The concurrency fix (lock + mktemp) actually prevents a real forced two-process race:
  **verified** (weaponx-evaluator forced this directly against a fake target).
- Rollback correctly removes freshly-added files and leaves no staging-dir leaks on
  failure, across two independent rounds of testing: **verified**.
- The version-check preamble fails silently and quickly against unreachable/malformed
  remotes: **verified** (tested directly against real unreachable hosts).
- No touches to `.github/workflows/`, branch protection, or `weaponx-approval`: **verified**
  (grepped and confirmed by the completed evaluator).
- Full dual-evaluator consensus achieved through the normal mechanism: **not verified** —
  the second evaluator's review never completed. This is the one honest gap in this run.
- The real global install is currently clean and matches `origin/main`: **verified** —
  checked independently by the orchestrator after the evaluator's self-report of this
  turned out to be incomplete, not taken on trust a second time.

### Corrections to standing memory

None this run — no new durable, project-spanning fact surfaced beyond what's already
captured in this trace and LEARNING.md.

---
**Chain:** prev=ec035e70ce94f78604b350a6453d913a0717c1657c271a498afde5f1852da903 (push-telegram-addon-2026-07-01-1420.md — same prior link as the other open PRs' traces, since none of push-ship-job-fix, weaponx-plan, or this one have merged yet)
