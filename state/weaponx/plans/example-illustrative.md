# ILLUSTRATIVE EXAMPLE — not a real plan run

> **This file is a hand-authored illustration of the plan-state schema, NOT a record of an
> actual `weaponx-plan` run.** Every name, date, slug, and trace-file link below is
> fabricated to show the *shape* of a real plan file. Nothing here happened; no stage was
> dispatched; the linked trace files do not exist. Its only purpose is to make the Move F
> schema (see `.claude/skills/weaponx-plan/SKILL.md`) concrete for a reader — a schema
> description isn't the same as seeing the artifact filled in. A real plan file would live
> at `state/weaponx/plans/<plan-slug>.md`, be written at the Move C approval gate, and have
> its per-stage status updated in place as the sequence runs.

---

**Plan:** add a dark-mode toggle to the settings screen
**Slug:** `dark-mode-settings-toggle` (illustrative)
**Status:** in-progress — stage 2 of 4 running
**Approved at (Move C gate):** 2026-07-01 (illustrative date)

## The original idea (as the user gave it)

"Add dark mode to the app. There's a settings screen already — put the toggle there, remember
the choice, and make sure the existing screens actually respect it instead of staying light."

This arrived too big for a single `/weaponx <task>` call: it spans a theme/token layer, a
persisted user preference, a settings-screen control, and a sweep of existing screens to make
them theme-aware. So it was decomposed into four dependency-ordered stages and approved as one
unit at the single Move C gate.

## Scope disclosure presented at the approval gate

This plan has **4 stages**. Each stage runs as its own normal `/weaponx` task and can use up
to weaponx's own per-task budget ceiling (~150 tool-calls / 4 cycles). Worst case, this plan
could run to **4 × that ceiling** (~600 tool-calls) before it either finishes or stops on a
failed stage. That is a worst-case upper bound, not an estimate of typical cost — most stages
will not hit their own individual cap.

## The approved stage list (in order, with dependency reasoning)

### Stage 1 — Theme tokens + light/dark palette layer — `done`
**Scope:** Introduce a theme abstraction (semantic color tokens) with a light and a dark
palette, plus a single place the app reads the active theme from. No UI wired to it yet.
**Depends on:** nothing — this is the foundation every later stage consumes.
**Trace:** `state/weaponx/dark-mode-tokens-2026-07-01-0930.md` (illustrative — file not real)
**Verdict:** PASS

### Stage 2 — Persisted theme preference (read/write + default) — `in-progress`
**Scope:** Store the user's chosen theme durably, load it on launch, fall back to system/light
when unset. Exposes a read + a write the settings control (Stage 3) will call.
**Depends on:** Stage 1 — the persisted value is one of the theme tokens' modes; there is
nothing meaningful to persist until the theme layer that defines those modes exists.
**Trace:** `state/weaponx/dark-mode-preference-2026-07-01-1105.md` (illustrative — file not real)
**Verdict:** (pending — stage still running)

### Stage 3 — Settings-screen toggle wired to the preference — `pending`
**Scope:** Add the actual toggle control on the existing settings screen; flipping it writes
through the Stage 2 preference and updates the active theme live.
**Depends on:** Stage 2 — the toggle has nothing to write to until the persisted preference
read/write exists; wiring the control first would just be dead UI.

### Stage 4 — Sweep existing screens to respect the active theme — `pending`
**Scope:** Audit the existing screens still hardcoding light colors and move them onto the
Stage 1 semantic tokens so they actually change with the toggle.
**Depends on:** Stages 1 and 3 — the screens can only consume tokens once the token layer
exists (Stage 1) and only demonstrate the toggle end-to-end once the control drives the theme
(Stage 3).

## Overall plan verdict

**In progress.** Stage 1 done, Stage 2 running, Stages 3–4 pending. If any stage's trace ends
in `hit-retry-cap` / `hit-budget-cap` / `escalated-on-disagreement`, the whole sequence stops
here (Move E), the human is notified with what's done and what's pending, and resuming is a
fresh human-initiated action — later stages that depend on a failed one never auto-run.
