# proactive.engineer

An open-source AI agent that lives on a VM alongside your team. It connects to your Slack and GitHub, reasons about everything it could do given the current state of your project, and decides what's actually worth doing next — then ships it as a PR for you to review.

**[proactive.engineer](https://proactive.engineer)** · **[GitHub](https://github.com/refreshdotdev/proactive-engineer)**

---

## Install

One command. Run this on the machine where you want the agent to live:

```bash
curl -fsSL https://proactive.engineer/install.sh | bash
```

The script will:
1. Ask for an **agent name** and **Slack display name**
2. Ask for your **Slack** (App Token + Bot Token), **GitHub**, and **Gemini** API keys
3. Install all dependencies automatically
4. Start the agent as a background service with a 30-minute heartbeat loop

You can also pass everything as environment variables for automated setups:

```bash
AGENT_NAME=backend \
AGENT_DISPLAY_NAME="PE - Backend" \
SLACK_APP_TOKEN=xapp-... \
SLACK_BOT_TOKEN=xoxb-... \
GITHUB_TOKEN=ghp_... \
GEMINI_API_KEY=... \
  curl -fsSL https://proactive.engineer/install.sh | bash
```

After that, walk away. The agent is alive.

---

## What It Does

Proactive Engineer wakes up every **30 minutes** via OpenClaw's heartbeat system and runs a continuous loop:

1. **Scan** — Reads across all your Slack channels and GitHub repos to understand what's happening
2. **Reason** — Generates a list of everything it *could* do: bug fixes, refactors, missing tests, documentation gaps, dependency updates, CI improvements, new project scaffolding
3. **Prioritize** — Ranks by impact, urgency, and confidence. Picks the thing that's actually worth doing right now
4. **Execute** — Does the work. Real code, real branches, real PRs
5. **Communicate** — Posts a concise summary to the relevant Slack channel under its configured display name

```
⚡ [proactive-engineer] Added missing error handling to /api/payments
PR: github.com/yourco/backend/pull/247
Why: Saw 3 unhandled promise rejections in #alerts yesterday.
```

---

## Daily Digest

Every day at **9:00 AM** (via a cron job registered during install), the agent posts a transparency report to `#proactive-engineer`:

- **What it did** — PRs opened, with one-line summaries
- **What it considered but skipped** — and why (e.g. "someone is actively working on that file")
- **What it's watching** — conversations and issues it's tracking

---

## How It Learns

The agent uses a built-in memory system. It remembers what kinds of PRs your team merges vs closes, what feedback you give it, who owns what areas of the codebase, and what patterns keep coming up. It gets better over time.

---

## Multiple Agents

Run the install script again to add more agents to the same machine. Each gets its own name, display identity, port, and isolated memory:

```bash
AGENT_NAME=frontend \
AGENT_DISPLAY_NAME="PE - Frontend" \
SLACK_APP_TOKEN=xapp-... \
SLACK_BOT_TOKEN=xoxb-... \
GITHUB_TOKEN=ghp_... \
GEMINI_API_KEY=... \
  curl -fsSL https://proactive.engineer/install.sh | bash
```

Each agent runs as a separate OpenClaw profile with its own systemd service, workspace, and session history. All agents share the same Slack app and GitHub token — they appear with different names in Slack via the `chat:write.customize` scope.

Agents coordinate through public Slack channels. Before starting work, each agent posts what it's about to do in `#proactive-engineer` so others don't duplicate effort.

```
Machine
  |
  +-- Agent "backend"   (port 18789, Slack: "PE - Backend")
  +-- Agent "frontend"  (port 18799, Slack: "PE - Frontend")
  +-- Agent "infra"     (port 18809, Slack: "PE - Infra")
```

Manage individual agents using the profile flag:

```bash
openclaw --profile pe-backend gateway status
openclaw --profile pe-frontend gateway restart
openclaw --profile pe-infra dashboard
```

---

## Guardrails

- **$50/day API budget** — pauses and asks in Slack before exceeding
- **Never pushes to main** — always works on branches and opens PRs
- **Never deploys** — its job ends at the PR
- **No large refactors without buy-in** — opens issues and asks first
- **Doesn't touch active work** — checks recent commits and open PRs before starting

---

## Configuration

Each agent's config lives at `~/.openclaw-pe-<name>/openclaw.json`. The install script writes this for you:

```json
{
  "gateway": {
    "port": 18789
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace-pe-backend",
      "heartbeat": { "every": "30m" }
    }
  },
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
          "GEMINI_API_KEY": "...",
          "AGENT_NAME": "backend",
          "AGENT_DISPLAY_NAME": "PE - Backend"
        }
      }
    }
  }
}
```

Restart after changing config:

```bash
openclaw --profile pe-<name> gateway restart
```

---

## Setting Up Your Keys

### Slack Bot (2 tokens needed)

You need a **Bot Token** (`xoxb-...`) and an **App Token** (`xapp-...`).

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App** → **From an app manifest**
2. Select your workspace
3. Paste this manifest (sets up all permissions, events, and socket mode automatically):

```json
{
  "display_information": {
    "name": "Proactive Engineer",
    "description": "An AI agent that ships while you sleep"
  },
  "features": {
    "bot_user": {
      "display_name": "Proactive Engineer",
      "always_online": true
    },
    "app_home": {
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "app_mentions:read",
        "channels:history",
        "channels:read",
        "channels:manage",
        "groups:history",
        "groups:read",
        "chat:write",
        "chat:write.customize",
        "im:history",
        "im:read",
        "im:write",
        "reactions:read",
        "reactions:write",
        "pins:read",
        "pins:write",
        "users:read",
        "emoji:read",
        "files:write"
      ]
    }
  },
  "settings": {
    "event_subscriptions": {
      "bot_events": [
        "message.channels",
        "message.groups",
        "message.im",
        "app_mention",
        "reaction_added",
        "member_joined_channel"
      ]
    },
    "socket_mode_enabled": true,
    "org_deploy_enabled": false
  }
}
```

4. Click **Next** → **Create**

**Get your two tokens:**

5. Go to **Basic Information** → **App-Level Tokens** → **Generate Token and Scopes**
6. Name it anything, add the scope `connections:write`, click **Generate**
7. Copy the **App Token** — starts with `xapp-`
8. Go to **Install App** (left sidebar) → **Install to Workspace** → **Allow**
9. Copy the **Bot User OAuth Token** — starts with `xoxb-`

**Invite the bot to your channels:**

10. In Slack, invite the bot: `/invite @Proactive Engineer`

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

### Optional Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `AGENT_NAME` | `default` | Short identifier for this agent (used in profile/service names) |
| `AGENT_DISPLAY_NAME` | `Proactive Engineer` | How this agent appears in Slack messages |

---

## Engineering Standard

The agent operates against a defined [engineering competency framework](skills/proactive-engineer/competencies/software_engineer_competency.md) that sets the bar for what "good" looks like. It holds itself to the behavioral profile described there: act before being asked, identify systemic issues, reduce entropy, make others more effective.

---

## Useful Commands

```bash
openclaw --profile pe-<name> gateway status       # Is the agent running?
openclaw --profile pe-<name> skills list           # Is the skill loaded?
openclaw --profile pe-<name> gateway restart       # Restart after config changes
openclaw --profile pe-<name> dashboard             # Open the web UI
journalctl --user -u openclaw-gateway-pe-<name> -f # Watch logs
```

---

## Project Structure

```
skills/
  proactive-engineer/
    SKILL.md                              # Agent behavior definition
    HEARTBEAT.md                          # 30-min scan loop instructions
    competencies/
      software_engineer_competency.md     # Engineering standard
install.sh                                # One-command setup (supports named agents)
TESTING.md                                # How to verify it works
```

---

## Built On

Proactive Engineer is built on [OpenClaw](https://openclaw.ai/), an open-source personal AI assistant framework. This repo is a fork of OpenClaw with the proactive-engineer skill and tooling added.

---

## License

MIT
