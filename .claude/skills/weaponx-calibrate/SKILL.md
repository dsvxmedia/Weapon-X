---
name: weaponx-calibrate
description: Phase 1.5. Checks whether the weaponx-evaluator is still trustworthy by replaying it against the accumulated benchmark/weaponx/ gold set. Run periodically (e.g. weekly, or before relying on the loop for something important) — never per-task, since that would double verification cost on every single run. Requires benchmark/weaponx/ to have enough accumulated cases to be meaningful (a handful of cases isn't a sample, it's noise).
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

# Weapon X Calibration Check

Purpose: catch drift in the **evaluator itself**, not just in generated output. A loop
can look healthy (lots of PASS verdicts) while the thing actually going stale is the
judge's standards — and nothing in the per-run trace would show you that, because each
run only sees the evaluator's verdict on itself, never the evaluator's track record.

## Procedure

1. Read every case in `benchmark/weaponx/`. Each case has a known correct verdict (the
   original REJECT reasoning, or the human's correction if they overrode a PASS).
2. Check there are enough cases for this to be a meaningful sample (use judgment — a
   handful of cases from one narrow task type tells you little; if the set is too thin,
   say so and stop rather than reporting a false sense of calibration).
3. Replay `weaponx-evaluator` against each case fresh — same artifact, same
   done-condition, no knowledge of the original verdict — and record its verdict.
4. Compare: how often does the evaluator now agree with the known-correct verdict?
   Break this down by failure-taxonomy category if the case count supports it (an
   evaluator that's drifted on `stale-context` cases specifically but solid everywhere
   else is a different problem than uniform drift).
5. Report the agreement rate plainly, with examples of any disagreements found —
   especially cases where the evaluator now PASSes something it (or a human) previously
   correctly rejected. That direction of drift (getting more lenient) is the dangerous
   one — a loop that gets stricter over time fails loud; one that gets more lenient fails
   silent.

## What this does NOT do

It does not retrain, fine-tune, or auto-correct the evaluator. It produces a report. If
the agreement rate looks bad, that's a signal for the human to look at the evaluator's
prompt/instructions in `.claude/agents/weaponx-evaluator.md` and decide whether to revise
it — same manual-only principle as everything else in this system.
