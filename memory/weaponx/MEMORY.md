# Weapon X — Cross-Task Memory

Durable, project-spanning facts the loop has learned across runs: standing preferences,
recurring constraints, "we tried X before and it failed because Y." Read in full by the
`weaponx` orchestrator on every invocation — kept deliberately short, same discipline as
`CLAUDE.md`. If this file grows long enough that it stops being a quick read, that's a
signal to consolidate it, not a reason to keep appending.

This is instance data, not engine — it is specific to this project's accumulated
experience and is not part of what gets copied if `weaponx` is adopted elsewhere.

Entries are appended by the `weaponx` orchestrator during Move 5 (Persistence), after
checking the fact isn't already recorded. Format: one short bullet per fact, newest at
the bottom, optionally tagged with the task/date it came from.

---

- `EnterWorktree` fails with "not in a git repository" in this repo as long as no
  `origin` remote is configured (it defaults to branching from `origin/<default-branch>`).
  Fall back to plain `git worktree add -b <branch> <path>` until a remote exists.
  (from: smoke-test-fix-add, 2026-06-30)
- `gstack ship`'s PR-creation step needs a remote. Without one, Persistence should commit
  to a feature branch and leave it unmerged rather than attempting a PR — this is expected
  Phase 1 behavior pre-GitHub, not a failure. (from: smoke-test-fix-add, 2026-06-30)
