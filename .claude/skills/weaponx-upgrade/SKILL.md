---
name: weaponx-upgrade
description: Pulls the latest Weapon X engine (skills + evaluator agents) from dsvxmedia/Weapon-X main and installs it over the local copy, staging everything first and swapping atomically so a failed pull never leaves a half-updated install. Invoked by any weaponx* skill's version-check preamble when the user accepts an update, or on demand. Only ever touches ~/.claude/skills/weaponx* and ~/.claude/agents/weaponx* (or a named local project copy) — never memory/, state/, benchmark/, CI, or anything it merges/deploys/publishes.
---

# Weapon X Upgrade

This skill applies an engine update: it re-copies the current `weaponx*` skills and the
`weaponx-evaluator*` agent definitions from `main` on GitHub over your installed copy, and
bumps the local version marker.

Its blast radius is **strictly local-filesystem file copying.** It never merges, deploys,
or publishes anything, never touches `.github/workflows/`, branch protection, the
`weaponx-approval` environment, or a project's `memory/` / `state/` / `benchmark/` data.

## Failure philosophy (the loud half of the asymmetry)

The version-check preamble in every `weaponx*` skill fails **silently** — checking for an
update has no consequences, so a network blip just means "say nothing." This skill is the
opposite: **applying** an update has real consequences, so every failure here is **loud and
explicit**, and the previous working install is always left intact. The two halves are
deliberately asymmetric; see the 2026-07-02 LEARNING.md entry.

The mechanism that makes "previous install always intact" true: **nothing live is touched
until a complete, verified copy exists in staging.** The network/clone/verify phase writes
only to throwaway staging directories. Only after staging passes verification does the swap
phase run, and the swap keeps backups of every replaced item until *all* swaps succeed,
rolling them back if any step fails.

## Step 1 — Choose the target (global vs. a local project copy)

Default target is the **global** install (`~/.claude/skills/weaponx*` and
`~/.claude/agents/weaponx*`) — that's what the preamble's "update now" path means.

- If the user invoked this skill with an explicit argument (`global`, or `local` / a path),
  honor it without asking.
- Otherwise, if the current working directory is inside a git project that has its own
  `.claude/skills/weaponx*`, use **AskUserQuestion** to ask which to update: "the global
  install (`~/.claude`)" or "this project's local copy (`<cwd>/.claude`)". Do not guess.
- Never update both silently in one run — updating a local project copy is an explicit,
  separate choice, not an ambiguous default.

Set the two destination variables accordingly and export them before running Step 2:

```bash
# GLOBAL (default):
export WEAPONX_SKILLS_DIR="$HOME/.claude/skills"
export WEAPONX_AGENTS_DIR="$HOME/.claude/agents"

# LOCAL project copy (only if the user chose it) — <project> is the chosen project root:
# export WEAPONX_SKILLS_DIR="<project>/.claude/skills"
# export WEAPONX_AGENTS_DIR="<project>/.claude/agents"
```

## Step 2 — Stage, verify, then swap atomically

Run the script below. It is written so that:

- **Only one upgrade to a given destination runs at a time.** Before it clones anything, it
  takes an exclusive lock (`.weaponx-upgrade.lock`, created with a bare `mkdir` — atomic and
  exclusive on POSIX). A second invocation that fires within the same wall-clock second (e.g.
  a `/loop`-scheduled run and an interactive session both accepting an update) refuses loudly
  instead of racing into the same staging dir, colliding on backups, or having one run's
  rollback clobber the other's completed swap. The lock is released on **any** exit — success,
  handled failure, or unexpected error — so one failed run never locks out all future ones.
- The clone and all verification happen against throwaway directories. Any failure there
  exits **before** a single live file is touched, and says so.
- Staging for the final swap lives **under the destination's own parent** (`.weaponx-stage-*`
  inside `WEAPONX_SKILLS_DIR` / `WEAPONX_AGENTS_DIR`) and is created with `mktemp -d`, so the
  final move into place is a same-filesystem directory rename — atomic per item, not a copy
  that can be interrupted half-written — and the staging name is unique per run, never
  time-derived, so it cannot collide even if the lock were somehow bypassed.
- Every replaced item is backed up (`*.wxbak-<run>`, where `<run>` is unique per invocation)
  and the backups are only deleted after **all** swaps succeed. If any swap fails, it rolls
  every backup back and exits loud.
- The version marker is written **last**, only after every file swap has already succeeded,
  so the marker can never claim a version the files don't actually match.

It copies whatever `weaponx*` skill directories and `weaponx*` agent files exist on `main`
(not a hardcoded list), so it also installs `weaponx-upgrade` itself and any future
`weaponx*` skill — while still hard-requiring a minimum floor (the core `weaponx` skill,
both evaluator agents, and a valid `VERSION`) to be present and non-empty before it will
touch anything.

```bash
set -u
REPO="https://github.com/dsvxmedia/Weapon-X.git"
SKILLS_DIR="${WEAPONX_SKILLS_DIR:-$HOME/.claude/skills}"
AGENTS_DIR="${WEAPONX_AGENTS_DIR:-$HOME/.claude/agents}"
VERSION_MARKER="$SKILLS_DIR/weaponx-version"
TS="$(date +%Y%m%d-%H%M%S)"
RUN="$TS-$$"   # unique per invocation (timestamp + PID): no two concurrent runs can collide on it

# Ensure the install dirs exist so the lock and staging can live on the destination
# filesystem. This is benign: it creates (at most) empty parent dirs, never a live install
# file, so the "nothing live touched until staging verifies" guarantee still holds.
mkdir -p "$SKILLS_DIR" "$AGENTS_DIR" || {
  echo "UPGRADE FAILED: could not create install dirs. Nothing changed."; exit 1; }

# --- exclusive lock: refuse to run if another weaponx-upgrade is already in progress ---
# `mkdir` (no -p) is atomic and exclusive on every POSIX filesystem: it fails if the dir
# already exists. That's the property we need — two invocations can't both acquire it. The
# lock lives inside SKILLS_DIR, so it serializes upgrades to *this* destination only (a
# global upgrade and a separate local-project upgrade target different dirs and don't race).
LOCK_DIR="$SKILLS_DIR/.weaponx-upgrade.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "UPGRADE FAILED: another weaponx-upgrade appears to be in progress."
  echo "(lock held at $LOCK_DIR). Your install is untouched — nothing was changed."
  echo "If you are certain no other upgrade is running, clear the stale lock with:"
  echo "  rmdir \"$LOCK_DIR\""
  exit 1
fi
# Release the lock on ANY exit (success, handled failure, or unexpected error), not just the
# happy path — so a single failed/rolled-back upgrade never leaves the system permanently
# locked out of upgrading. `rmdir` only removes the (always-empty) lock dir, never files.
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# --- clone into a throwaway temp dir (network phase — live install untouched) ---
CLONE="$(mktemp -d "${TMPDIR:-/tmp}/weaponx-clone-$RUN.XXXXXX")" || {
  echo "UPGRADE FAILED: could not create temp dir. Nothing changed."; exit 1; }
cleanup_clone() { rm -rf "$CLONE" 2>/dev/null; }

if ! git clone --depth 1 "$REPO" "$CLONE/repo" 2>"$CLONE/clone.err"; then
  echo "UPGRADE FAILED: git clone of $REPO failed. Your install is untouched."
  echo "----- clone error -----"; cat "$CLONE/clone.err"; echo "-----------------------"
  cleanup_clone; exit 1
fi

SRC_SKILLS="$CLONE/repo/.claude/skills"
SRC_AGENTS="$CLONE/repo/.claude/agents"
NEW_VERSION="$(head -1 "$CLONE/repo/VERSION" 2>/dev/null | tr -d '[:space:]')"

# --- verify the minimum required set is present and non-empty in the clone ---
verify_fail() {
  echo "UPGRADE FAILED: staging verification failed ($1). Your install is untouched."
  cleanup_clone; exit 1
}
case "$NEW_VERSION" in ''|*[!0-9.]*) verify_fail "VERSION missing or malformed" ;; esac
[ -s "$SRC_SKILLS/weaponx/SKILL.md" ]        || verify_fail "core weaponx/SKILL.md missing/empty"
[ -s "$SRC_AGENTS/weaponx-evaluator.md" ]    || verify_fail "weaponx-evaluator.md missing/empty"
[ -s "$SRC_AGENTS/weaponx-evaluator-b.md" ]  || verify_fail "weaponx-evaluator-b.md missing/empty"

# --- copy the weaponx* set into staging dirs that sit on the destination filesystem ---
# `mktemp -d` guarantees a unique staging dir per invocation regardless of timing, so even if
# the lock above were somehow bypassed, two runs could never share a staging dir. The dirs are
# created *under the destination's own parent* so the later swap is a same-filesystem rename.
SKILL_STAGE="$(mktemp -d "$SKILLS_DIR/.weaponx-stage-$RUN.XXXXXX")" || {
  echo "UPGRADE FAILED: could not create skill staging dir. Your install is untouched."; cleanup_clone; exit 1; }
AGENT_STAGE="$(mktemp -d "$AGENTS_DIR/.weaponx-stage-$RUN.XXXXXX")" || {
  echo "UPGRADE FAILED: could not create agent staging dir. Your install is untouched."; rm -rf "$SKILL_STAGE"; cleanup_clone; exit 1; }
cleanup_all() { rm -rf "$CLONE" "$SKILL_STAGE" "$AGENT_STAGE" 2>/dev/null; }

SKILL_NAMES=""; AGENT_NAMES=""
for d in "$SRC_SKILLS"/weaponx*/; do
  [ -d "$d" ] || continue
  n="$(basename "$d")"
  [ -s "$d/SKILL.md" ] || { echo "UPGRADE FAILED: staged $n/SKILL.md missing/empty. Install untouched."; cleanup_all; exit 1; }
  cp -R "$d" "$SKILL_STAGE/$n"   || { echo "UPGRADE FAILED: could not stage skill $n. Install untouched."; cleanup_all; exit 1; }
  [ -s "$SKILL_STAGE/$n/SKILL.md" ] || { echo "UPGRADE FAILED: staged copy of $n verified empty. Install untouched."; cleanup_all; exit 1; }
  SKILL_NAMES="$SKILL_NAMES $n"
done
for f in "$SRC_AGENTS"/weaponx*.md; do
  [ -e "$f" ] || continue
  n="$(basename "$f")"
  [ -s "$f" ] || { echo "UPGRADE FAILED: staged agent $n empty. Install untouched."; cleanup_all; exit 1; }
  cp "$f" "$AGENT_STAGE/$n" || { echo "UPGRADE FAILED: could not stage agent $n. Install untouched."; cleanup_all; exit 1; }
  [ -s "$AGENT_STAGE/$n" ]  || { echo "UPGRADE FAILED: staged copy of agent $n verified empty. Install untouched."; cleanup_all; exit 1; }
  AGENT_NAMES="$AGENT_NAMES $n"
done
# Staging dirs already exist by now, so clean them (not just the clone) on this failure.
[ -n "$SKILL_NAMES" ] || { echo "UPGRADE FAILED: staging verification failed (no weaponx* skills found in clone). Your install is untouched."; cleanup_all; exit 1; }

# ==================== SWAP PHASE (past here, live files change) ====================
OLD_VERSION="$(head -1 "$VERSION_MARKER" 2>/dev/null | tr -d '[:space:]')"; [ -n "$OLD_VERSION" ] || OLD_VERSION="unknown"
BACKUPS=""          # newline-separated backup paths of REPLACED items (each ends in .wxbak-$RUN)
ADDED=""            # newline-separated live paths of NEWLY-ADDED items (no prior version existed)
UPDATED_SKILLS=""; UPDATED_AGENTS=""

rollback() {
  echo "UPGRADE FAILED during swap: $1"
  echo "Rolling back to the previous install..."
  # Remove freshly-added items first (they had no prior version — restoring means deleting them),
  # so a rollback can't leave a brand-new skill/agent behind in an otherwise-reverted install.
  printf '%s\n' "$ADDED" | while IFS= read -r a; do [ -n "$a" ] && rm -rf "$a" 2>/dev/null; done
  # Then restore every replaced item from its backup.
  printf '%s\n' "$BACKUPS" | while IFS= read -r b; do
    [ -n "$b" ] || continue
    live="${b%.wxbak-$RUN}"
    rm -rf "$live" 2>/dev/null
    mv "$b" "$live" 2>/dev/null
  done
  echo "Rolled back. Your previous working install is restored and untouched by the failure."
  cleanup_all; exit 1
}

# swap_in <staged_path> <live_path>: back up live (if any) then atomic-rename staged into place
swap_in() {
  staged="$1"; live="$2"
  if [ -e "$live" ]; then
    mv "$live" "$live.wxbak-$RUN" || rollback "could not back up $(basename "$live")"
    BACKUPS="$BACKUPS
$live.wxbak-$RUN"
  else
    ADDED="$ADDED
$live"   # no prior version — a fresh add; rollback must delete this, not restore it
  fi
  mv "$staged" "$live" || rollback "could not move new $(basename "$live") into place"
}

# 1) skills
for n in $SKILL_NAMES; do
  swap_in "$SKILL_STAGE/$n" "$SKILLS_DIR/$n"
  UPDATED_SKILLS="$UPDATED_SKILLS $n"
done
# 2) agents
for n in $AGENT_NAMES; do
  swap_in "$AGENT_STAGE/$n" "$AGENTS_DIR/$n"
  UPDATED_AGENTS="$UPDATED_AGENTS $n"
done
# 3) version marker LAST — only after every file swap already succeeded
printf '%s\n' "$NEW_VERSION" > "$VERSION_MARKER.tmp-$RUN" || rollback "could not write version marker"
mv "$VERSION_MARKER.tmp-$RUN" "$VERSION_MARKER" || rollback "could not move version marker into place"

# --- success: drop backups + staging ---
printf '%s\n' "$BACKUPS" | while IFS= read -r b; do [ -n "$b" ] && rm -rf "$b" 2>/dev/null; done
cleanup_all

echo "UPGRADE OK"
echo "version: ${OLD_VERSION} -> ${NEW_VERSION}"
echo "skills updated:$UPDATED_SKILLS"
echo "agents updated:$UPDATED_AGENTS"
echo "target skills dir: $SKILLS_DIR"
echo "target agents dir: $AGENTS_DIR"
```

## Step 3 — Report plainly

Read the script's output and tell the user, in plain language:

- **On `UPGRADE OK`:** "Updated Weapon X from v<old> to v<new>." List which skills and
  which agent files changed (from `skills updated:` / `agents updated:`) and which target
  (global vs. the named local project). If this run was triggered from another skill's
  preamble, then return to that skill and continue its normal work.
- **On any `UPGRADE FAILED ...`:** state exactly what went wrong (quote the failure line),
  and confirm explicitly that the previous install is intact — either because nothing live
  was touched (clone/verify phase) or because the swap phase rolled back. Do **not** retry
  silently; tell the user they can re-run `weaponx-upgrade` once the cause (usually network)
  is resolved.

## Boundaries (same as the core loop's — do not infer around them)

- Only ever writes under `WEAPONX_SKILLS_DIR` / `WEAPONX_AGENTS_DIR` (default `~/.claude`).
  Never writes to `memory/`, `state/`, `benchmark/`, or a project's own tracked source.
- Never merges, deploys, publishes, force-pushes, or touches `.github/workflows/`, branch
  protection, or the `weaponx-approval` environment.
- Never edits `CLAUDE.md`, other skills' logic, or memory as a side effect — it only
  replaces the `weaponx*` engine files with their upstream `main` versions.
