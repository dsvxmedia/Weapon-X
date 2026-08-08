# PUSH setup checklist

PUSH is optional. Skip all of this and weaponx works exactly as it does today. Do these
steps only if you want Telegram checkpoints and phone-driven decision briefs.

You need to do these yourself — they require your own Telegram and GitHub accounts and
credentials. Nothing here can be created by the agent on your behalf.

## Capability status

The features below (Stages 1-9 of the PUSH feature expansion) landed as separate,
sequentially-stacked PRs rather than one atomic change, so a reader picking this doc up
mid-rollout could otherwise be confused about what's actually live yet. This table is a
**snapshot as of when this doc was last edited**, not a live view — it will go stale the
moment any of these PRs merge without this table being updated in the same PR. If you need
the current, authoritative answer, check `gh pr list --state merged --search
"push-"` (what's actually landed on `main`) rather than trusting this table blindly.

| # | Capability | Stage | PR | Status (snapshot) |
|---|------------|-------|----|--------------------|
| 1 | HTML-formatted messages (bold, code blocks, literal `&`/`<`/`>`) | 1 | #16 | Open, awaiting merge |
| 2 | Recommended-option marking (★ on a brief's suggested choice) | 2 | #17 | Open, awaiting merge |
| 3 | Tappable inline-keyboard buttons on decision briefs | 3 | #18 | Open, awaiting merge |
| 4 | Safe timeout reminder (~60% of a brief's window, no auto-resolve ever) | 4 | #19 | Open, awaiting merge |
| 5 | Telegram-driven ship approval (see section 7 below) | 5 | #20 | Open, awaiting merge |
| 6 | Live-editing single status message (Path 2 cold-start only) | 6 | #21 | Open, awaiting merge |
| 7 | Diff attached to the approval brief (inline or file, by size) | 7 | #22 | Open, awaiting merge |
| 8 | Phone command router (`/status`, `/cancel`, `/history`) | 8 | #23 | Open, awaiting merge |
| 9 | Budget-crossing checkpoint notice (~75% of `BUDGET_CEILING`) | 9 | #24 | Open, awaiting merge |

Everything in steps 1-6 below (Telegram bot, chat id, secrets, the `weaponx-approval`
environment, both test paths) is Stage 0's original core setup and has been live and
pressure-tested since before this table existed — it does not depend on any row above being
merged. Steps 1-4, 6, 8, and 9 above need nothing beyond that core setup once merged; only
Stage 5 (row 5 — Telegram-driven ship approval, section 7 below) needs its own additional
setup, and it's explicitly optional.

## 1. Create a Telegram bot and get its token

1. In Telegram, open a chat with **@BotFather**.
2. Send `/newbot`, follow the prompts (give it a name and a username ending in `bot`).
3. BotFather replies with a token that looks like `123456789:AAExxxxxxxxxxxxxxxxxxxxxxxxxx`.
   That is your `TELEGRAM_BOT_TOKEN`. Keep it secret — anyone with it can control the bot.

## 2. Get your own numeric chat id

1. In Telegram, open a chat with **@userinfobot** and send it any message.
2. It replies with your account details, including a numeric **Id** (e.g. `987654321`).
   That number is your `TELEGRAM_CHAT_ID`.
3. Send your new bot a `/start` (or any) message once, so it's allowed to message you back.

The bot will only ever talk to, and only ever accept replies from, this one chat id.

## 3. Add the secrets to the GitHub repo (for Path 2 — the cloud cold-start path)

From the repo root, using the `gh` CLI (exact syntax):

```sh
gh secret set TELEGRAM_BOT_TOKEN --body "123456789:AAExxxxxxxxxxxxxxxxxxxxxxxxxx"
gh secret set TELEGRAM_CHAT_ID   --body "987654321"
```

The headless dispatch workflow also needs Claude Code authentication — **pick one**, not
both:

**Option A — subscription (Pro/Max), no metered API billing (recommended if you have one):**

```sh
claude setup-token
```

This must be run in your own terminal, not through an agent session — it opens a browser
for an OAuth login and cannot complete non-interactively. It prints a token valid for 1
year. Then:

```sh
gh secret set CLAUDE_CODE_OAUTH_TOKEN --body "<the token setup-token printed>"
```

**Option B — metered API key**, from https://console.anthropic.com/settings/keys:

```sh
gh secret set ANTHROPIC_API_KEY --body "sk-ant-..."
```

`push-dispatch.yml` checks for `CLAUDE_CODE_OAUTH_TOKEN` first and falls back to
`ANTHROPIC_API_KEY`; it fails with a clear error at the start of the run if neither is set,
rather than failing cryptically partway through.

(`GITHUB_TOKEN` is provided automatically by Actions — you do not set it.)

Verify they landed:

```sh
gh secret list
```

The workflow YAML references these as `${{ secrets.TELEGRAM_BOT_TOKEN }}`,
`${{ secrets.TELEGRAM_CHAT_ID }}`, `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}`, and
`${{ secrets.ANTHROPIC_API_KEY }}` — no token is ever hardcoded.

## 4. Create the `weaponx-approval` GitHub Environment (the human ship-gate)

The dispatch workflow's `ship` job depends on a protected environment so a human must
approve before anything ships.

Click-path:
1. Repo on GitHub -> **Settings** -> **Environments** -> **New environment**.
2. Name it exactly `weaponx-approval` and create it.
3. In the environment's settings, enable **Required reviewers** and add **yourself**.
4. Save.

`gh` equivalent (create the environment and add yourself as a required reviewer — replace
`<your-user-id>` with your numeric GitHub user id, from `gh api user --jq .id`):

```sh
gh api -X PUT "repos/:owner/:repo/environments/weaponx-approval" \
  -f "wait_timer=0" \
  -F "reviewers[][type]=User" \
  -F "reviewers[][id]=<your-user-id>"
```

With this in place, the `ship` job pauses until you approve it in the GitHub UI. Until then
it blocks — that is the enforced never-auto-ship boundary for the cloud path.

## 5. Test Path 1 locally (a live session on your machine)

Export the two vars in your shell, then exercise the bridge directly:

```sh
export TELEGRAM_BOT_TOKEN="123456789:AAE..."
export TELEGRAM_CHAT_ID="987654321"

# Send a checkpoint — you should receive it in Telegram:
.claude/skills/weaponx-push/bin/push-bridge.sh send --text "PUSH test: hello from weaponx"

# Post a decision brief, then wait for your reply (reply in Telegram within the timeout):
.claude/skills/weaponx-push/bin/push-bridge.sh brief \
  --id test-1 --text "This is a test decision." \
  --option "A) looks good" --option "B) stop"
.claude/skills/weaponx-push/bin/push-bridge.sh wait --id test-1 --timeout 120
```

When you reply in Telegram, `wait` prints a single line of JSON with your reply text and
exits 0. With the vars unset, every command instead prints "PUSH not configured … skipping"
and exits 2 — that is the "PUSH is off, carry on" path the orchestrator relies on.

## 6. Test Path 2 (cold-start from a phone)

1. Confirm the secrets and environment from steps 3-4 are in place.
2. From your phone, send your bot: `/weaponx <some small task>`.
3. Within a few minutes (schedule latency is expected — see the caveat in `push-poll.yml`),
   `push-poll.yml` should pick it up and trigger `push-dispatch.yml`. You can watch under
   the repo's **Actions** tab, or trigger the poll immediately with
   `gh workflow run push-poll.yml`.
4. You should receive a "starting a weaponx run" Telegram message, and later a "waiting on
   your approval" message. Approve the `ship` job in the GitHub UI to proceed.

## 7. Optional: Telegram-driven ship approval (skip if GitHub's own UI/Mobile is fine)

Everything above (buttons, recommended-option marking, live status, diffs, phone commands,
budget notices) works without this section. Do this only if you want to approve/reject a
`ship` job by replying in Telegram, instead of switching to GitHub's web UI or the GitHub
Mobile app (which already gives you a free, zero-setup native approval notification — a
completely valid choice if you'd rather skip this section entirely).

**One-time setup, ~15 minutes, plus a small recurring touch every 90 days:**

1. **Create a second, dedicated GitHub account** (not your main one) — a spare email works,
   e.g. a Gmail `+alias` (`you+approvals@gmail.com` still lands in your normal inbox, but
   reads as a different address to GitHub). This account holds a credential capable of
   approving deployments, kept fully isolated from your primary identity — if it ever
   leaks, it can only ever act on this one repo, never anything else you own.

2. **Add it as a collaborator** with read access:
   ```sh
   gh api repos/:owner/:repo/collaborators/<bot-username> -X PUT -f permission=pull
   ```
   Log into the new account and accept the invite at
   `https://github.com/<owner>/<repo>/invitations`.

3. **Add it as a second required reviewer** on `weaponx-approval` (alongside your primary
   account — this does not remove the existing one; both approve independently):
   ```sh
   gh api -X PUT "repos/:owner/:repo/environments/weaponx-approval" \
     -F "wait_timer=0" \
     -F "reviewers[][type]=User" -F "reviewers[][id]=<your-user-id>" \
     -F "reviewers[][type]=User" -F "reviewers[][id]=<bot-user-id>"
   ```
   (Get either user id from `gh api users/<username> --jq .id`.)

4. **Generate a classic PAT for the dedicated account** — **not** a fine-grained token.
   This was tried first and doesn't work: fine-grained tokens can only target repositories
   the token's own account *owns* (or an org it belongs to); a repo you're merely a
   collaborator on — which is exactly this setup — never appears as a selectable option,
   confirmed against GitHub's own docs, not a UI bug or a stale page. GitHub's REST API
   docs are also explicit that the specific endpoint this relies on
   (`POST .../actions/runs/{run_id}/pending_deployments`) requires the full `repo` scope on
   a classic token regardless — there is no narrower classic scope (e.g. `repo_deployment`
   alone) that covers it.

   While logged into the dedicated account, go to
   `https://github.com/settings/tokens/new` (the classic token page — not
   `/settings/personal-access-tokens/new`, which is fine-grained and won't work here):
   - Note: something like `weaponx-approval-relay`
   - Expiration: 90 days (you'll regenerate it under this same dedicated account when it
     lapses — a deliberate small recurring cost, not an oversight)
   - Scopes: check the top-level **`repo`** box
   - Generate, copy the value (`ghp_...`) — shown once

5. **Store it as the secret:**
   ```sh
   gh secret set WEAPONX_APPROVAL_REVIEWER_PAT --body "ghp_..."
   ```

**Kill switch:** delete this one secret at any time
(`gh secret delete WEAPONX_APPROVAL_REVIEWER_PAT`) to instantly revert to GitHub-UI/Mobile-only
approval — nothing else about PUSH changes or breaks.

**Test it for real:** trigger a real `push-dispatch.yml` run, wait for the Approve/Reject
brief, tap one, and confirm in the Actions tab that the `ship` job's status actually changed
(not just that a Telegram message claimed success). If you want to test the failure path
too: temporarily set the secret to an obviously invalid value and confirm you get a clear
"couldn't relay, use the GitHub UI/Mobile app" message instead of silence — then set it back
to the real token.

## Known gaps / TODOs for the human

Both items previously listed here were resolved and pressure-tested for real on
2026-08-07 (see `LEARNING.md`): the Path 1 round-trip is confirmed working end-to-end
against a live bot, and the `ship` job's branch-push + PR-opening flow is real, not a
placeholder (see the "Detect the branch weaponx pushed" step in `push-dispatch.yml`).

One thing worth knowing, not a gap:

- **Use a bot dedicated to PUSH, never one shared with another webhook-based
  integration.** Telegram will not let a bot use `getUpdates` (what both `push-bridge.sh`
  and `push-poll.yml` do) while it has any webhook registered — the conflict silently
  broke both PUSH paths here for an extended period until it was diagnosed. If you ever
  see a `Conflict: can't use getUpdates method while webhook is active` error, run
  `deleteWebhook` against your bot token and confirm with `getWebhookInfo` that its `url`
  field comes back empty.
