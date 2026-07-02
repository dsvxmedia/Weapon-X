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

- `EnterWorktree` fails with "not in a git repository" in this repo. Originally assumed
  this was solely because no `origin` remote existed; retested after `origin`
  (dsvxmedia/Weapon-X) was added and the same error still occurs. The missing-remote
  precondition was necessary but not sufficient — something else about this environment
  also blocks it. Always fall back to plain `git worktree add -b <branch> <path>`; don't
  assume adding a remote alone fixes this. (from: smoke-test-fix-add, 2026-06-30;
  corrected: push-telegram-addon, 2026-07-01)
- `gstack ship`'s PR-creation step needs a remote. Without one, Persistence should commit
  to a feature branch and leave it unmerged rather than attempting a PR — this is expected
  Phase 1 behavior pre-GitHub, not a failure. (from: smoke-test-fix-add, 2026-06-30)
- When a task turns out to be unsatisfiable/contradictory as specified (not a code defect,
  the spec itself conflicts), the evaluator should use `other-with-detail`, not force-fit
  a category like `wrong-tool-choice`. A live run picked the wrong label for exactly this
  case. (from: retry-cap-double, 2026-06-30)
- Ambient config (like `git config user.name`) is not a reliable source for
  legally/publicly significant attribution. It should be treated as a blocking question
  for the human, not a plausible-default fill-in — internal consistency (matches the repo's
  own git config) is not the same as correctness (matches what the human actually wants on
  a public document). A live run on adding a LICENSE hit exactly this: `dsvxmedia` matched
  git config but not the user's known identity, and the two evaluators split on whether
  that mattered. (from: add-license, 2026-06-30)
