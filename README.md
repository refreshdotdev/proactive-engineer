# proactive.engineer

An open-source AI agent that lives on a VM alongside your team. It connects to your Slack and GitHub, reasons about everything it could do given the current state of your project, and decides what's actually worth doing next — then ships it as a PR for you to review.

**[proactive.engineer](https://proactive.engineer)** · **[GitHub](https://github.com/refreshdotdev/proactive-engineer)**

---

## Install

One command. Run this on the machine where you want the agent to live (a VM, a server, your dev box — anywhere with a persistent connection):

```bash
curl -fsSL https://proactive.engineer/install.sh | bash
```

The script will:
1. Ask for your **Slack** (App Token + Bot Token), **GitHub**, and **Gemini** API keys
2. Install all dependencies automatically
3. Download Proactive Engineer
4. Start it as a background service that runs continuously

You can also pass keys as environment variables for automated setups:

```bash
SLACK_APP_TOKEN=xapp-... \
SLACK_BOT_TOKEN=xoxb-... \
GITHUB_TOKEN=ghp_... \
GEMINI_API_KEY=... \
  curl -fsSL https://proactive.engineer/install.sh | bash
```

After that, walk away. The agent is alive.

---

## What It Does

Proactive Engineer runs a continuous loop:

1. **Scan** — Reads across all your Slack channels and GitHub repos to understand what's happening
2. **Reason** — Generates a list of everything it *could* do: bug fixes, refactors, missing tests, documentation gaps, dependency updates, CI improvements, new project scaffolding
3. **Prioritize** — Ranks by impact, urgency, and confidence. Picks the thing that's actually worth doing right now
4. **Execute** — Does the work. Real code, real branches, real PRs
5. **Communicate** — Posts a concise summary to the relevant Slack channel

```
⚡ [proactive-engineer] Added missing error handling to /api/payments
PR: github.com/yourco/backend/pull/247
Why: Saw 3 unhandled promise rejections in #alerts yesterday.
```

---

## Daily Digest

Once a day, the agent posts a transparency report to `#proactive-engineer`:

- **What it did** — PRs opened, with one-line summaries
- **What it considered but skipped** — and why (e.g. "someone is actively working on that file")
- **What it's watching** — conversations and issues it's tracking

---

## How It Learns

The agent uses a built-in memory system. It remembers what kinds of PRs your team merges vs closes, what feedback you give it, who owns what areas of the codebase, and what patterns keep coming up. It gets better over time.

---

## Multi-Agent

Running multiple Proactive Engineers on the same team? They coordinate through public Slack channels. Each agent posts what it's about to work on before starting, so they don't duplicate effort. If no coordination channel exists, they'll create `#proactive-engineer`.

---

## Guardrails

- **$50/day API budget** — pauses and asks in Slack before exceeding
- **Never pushes to main** — always works on branches and opens PRs
- **Never deploys** — its job ends at the PR
- **No large refactors without buy-in** — opens issues and asks first
- **Doesn't touch active work** — checks recent commits and open PRs before starting

---

## Configuration

All config lives in `~/.openclaw/openclaw.json`. The install script writes this for you, but you can edit it anytime:

```json
{
  "channels": {
    "slack": {
      "enabled": true,
      "appToken": "xapp-...",
      "botToken": "xoxb-..."
    }
  },
  "skills": {
    "entries": {
      "proactive-engineer": {
        "enabled": true,
        "env": {
          "GITHUB_TOKEN": "ghp_...",
          "GEMINI_API_KEY": "..."
        }
      }
    }
  }
}
```

Restart after changing config:

```bash
openclaw gateway restart
```

---

## Setting Up Your Keys

### Slack Bot (2 tokens needed)

You need a **Bot Token** (`xoxb-...`) and an **App Token** (`xapp-...`).

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App** → **From scratch**
2. Give it a name (e.g. "Proactive Engineer") and select your workspace

**Enable Socket Mode:**

3. Go to **Socket Mode** (left sidebar) and toggle it **on**
4. Go to **Basic Information** → **App-Level Tokens** → **Generate Token and Scopes**
5. Name it anything, add the scope `connections:write`, click **Generate**
6. Copy the **App Token** — starts with `xapp-`

**Set Bot Permissions:**

7. Go to **OAuth & Permissions** (left sidebar)
8. Under **Bot Token Scopes**, add these:

| Scope | Why |
| --- | --- |
| `channels:history` | Read messages in public channels |
| `channels:read` | List channels |
| `groups:history` | Read messages in private channels |
| `groups:read` | List private channels |
| `chat:write` | Send messages |
| `im:history` | Read DMs |
| `im:read` | List DMs |
| `im:write` | Open DMs |
| `reactions:read` | Read reactions |
| `reactions:write` | Add reactions |
| `pins:read` | Read pinned messages |
| `pins:write` | Pin messages |
| `users:read` | Look up users |
| `emoji:read` | Read custom emoji |
| `files:write` | Upload files |
| `channels:manage` | Create channels (for `#proactive-engineer`) |

**Install and copy token:**

9. Scroll up and click **Install to Workspace** → **Allow**
10. Copy the **Bot User OAuth Token** — starts with `xoxb-`

**Subscribe to events:**

11. Go to **Event Subscriptions** (left sidebar), toggle **on**
12. Under **Subscribe to bot events**, add: `message.channels`, `message.groups`, `message.im`, `app_mention`, `reaction_added`, `member_joined_channel`
13. Click **Save Changes**

**Enable App Home:**

14. Go to **App Home** (left sidebar), enable the **Messages Tab**

**Invite the bot:**

15. In Slack, invite the bot to channels: `/invite @Proactive Engineer`

### GitHub Personal Access Token

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Click **Generate new token** → **Fine-grained token** (recommended) or **Classic**
3. For classic tokens, select these scopes:

| Scope | Why |
| --- | --- |
| `repo` | Full access to repos (clone, branch, PR) |

4. Set an expiration (or no expiration for a persistent agent)
5. Click **Generate token**
6. Copy the token — starts with `ghp_`

### Gemini API Key

1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Click **Create API Key**
3. Select or create a Google Cloud project
4. Copy the key

---

### Required Keys Summary

| Key | Format | Where to get it |
| --- | --- | --- |
| Slack App Token | `xapp-...` | api.slack.com/apps → Socket Mode → App-Level Tokens |
| Slack Bot Token | `xoxb-...` | api.slack.com/apps → OAuth & Permissions |
| GitHub Token | `ghp_...` | github.com/settings/tokens |
| Gemini API Key | `AI...` | aistudio.google.com/apikey |

---

## Engineering Standard

The agent operates against a defined [engineering competency framework](skills/proactive-engineer/competencies/software_engineer_competency.md) that sets the bar for what "good" looks like. It holds itself to the behavioral profile described there: act before being asked, identify systemic issues, reduce entropy, make others more effective.

---

## Useful Commands

```bash
openclaw gateway status          # Is the agent running?
openclaw skills list             # Is the skill loaded?
openclaw gateway restart         # Restart after config changes
openclaw dashboard               # Open the web UI
journalctl --user -u openclaw-gateway -f  # Watch logs
```

---

## Project Structure

```
skills/
  proactive-engineer/
    SKILL.md                              # Agent behavior definition
    competencies/
      software_engineer_competency.md     # Engineering standard
install.sh                                # One-command setup
TESTING.md                                # How to verify it works
```

---

## Built On

Proactive Engineer is built on [OpenClaw](https://openclaw.ai/), an open-source personal AI assistant framework. This repo is a fork of OpenClaw with the proactive-engineer skill and tooling added.

---

## License

MIT
