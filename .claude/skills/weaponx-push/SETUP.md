# PUSH setup checklist

PUSH is optional. Skip all of this and weaponx works exactly as it does today. Do these
steps only if you want Telegram checkpoints and phone-driven decision briefs.

You need to do these yourself — they require your own Telegram and GitHub accounts and
credentials. Nothing here can be created by the agent on your behalf.

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

The headless dispatch workflow also needs an Anthropic API key to run Claude Code:

```sh
gh secret set ANTHROPIC_API_KEY --body "sk-ant-..."
```

(`GITHUB_TOKEN` is provided automatically by Actions — you do not set it.)

Verify they landed:

```sh
gh secret list
```

The workflow YAML references these as `${{ secrets.TELEGRAM_BOT_TOKEN }}`,
`${{ secrets.TELEGRAM_CHAT_ID }}`, and `${{ secrets.ANTHROPIC_API_KEY }}` — no token is
ever hardcoded.

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

## Known gaps / TODOs for the human

- **Sending a real Telegram message cannot be tested without a real bot token** — the
  script's syntax and pending-file logic are verified, but the actual round-trip needs your
  bot. Do step 5 once to confirm the round-trip on your account.
- **The `ship` job's PR-opening step is a documented placeholder.** The weaponx branch is
  produced inside the `run` job's runner and is not automatically handed to the `ship` job;
  wiring the real branch push + PR creation across jobs is left as a follow-up so the
  human-approval gate could be wired correctly first. See the note in `push-dispatch.yml`.
