# proactive.engineer

<p align="center">
  <img src="proactive-engineer-hero.png" alt="Proactive Engineer" width="600">
</p>

<p align="center">
  <em>An AI that ships while you sleep</em>
</p>

An open-source AI teammate that quietly handles the work your team knows is important but never gets to. It connects to your Slack and GitHub, figures out what's worth doing, and opens PRs for your team to review. You stay in control — it just makes sure the backlog of "we should really do that" actually gets done.

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

## Setup with Claude Code

The easiest way to get started: paste this prompt into [Claude Code](https://docs.anthropic.com/en/docs/claude-code) on a fresh VM. Claude will handle the entire setup for you.

```
I need you to set up Proactive Engineer (https://github.com/refreshdotdev/proactive-engineer)
on this machine. It's an autonomous AI agent that monitors Slack and GitHub and opens PRs.

Here are my API keys:

- Slack App Token: xapp-...
- Slack Bot Token: xoxb-...
- GitHub App ID: ...
- GitHub App Installation ID: ...
- GitHub App Private Key: (paste the .pem contents here)
- Gemini API Key: ...

Steps:
1. Save the GitHub App private key to ~/github-app.pem
2. Run the install script:

AGENT_NAME=default \
AGENT_DISPLAY_NAME="Proactive Engineer" \
SLACK_APP_TOKEN="xapp-..." \
SLACK_BOT_TOKEN="xoxb-..." \
GITHUB_APP_ID="..." \
GITHUB_APP_INSTALLATION_ID="..." \
GITHUB_APP_PEM_PATH="$HOME/github-app.pem" \
GEMINI_API_KEY="..." \
  curl -fsSL https://proactive.engineer/install.sh | bash

3. Verify the agent is running with: openclaw --profile pe-default gateway status
4. Check Slack connectivity in the logs
```

Replace the placeholder values with your actual keys. Claude Code will run the commands, verify the setup, and troubleshoot any issues.

---

## Deploy to AWS (Recommended)

The best way to run Proactive Engineer is on a dedicated VM that stays on 24/7. We provide Terraform configs and a pre-built AMI so the agent is running within a minute of `terraform apply`.

### One-Shot Deploy

```bash
cd terraform/

# Copy the example and fill in your keys
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Slack, GitHub, and Gemini keys

# Deploy
terraform init
terraform apply
```

That's it. Terraform provisions the VM from a pre-built AMI (Node.js, OpenClaw, and the skill are already installed), injects your API keys, and starts the agent automatically. No SSH required.

After about 30 seconds, the agent connects to Slack and starts its first heartbeat cycle.

To check on it:

```bash
# SSH in (if you provided an SSH key)
ssh ubuntu@$(terraform output -raw public_ip)

# Check the agent
export PATH="$HOME/.npm-global/bin:$PATH"
openclaw --profile pe-default gateway status
journalctl --user -u openclaw-gateway-pe-default -f
```

### Build Your Own AMI

If you want to build the AMI yourself (e.g. for a different region):

```bash
cd packer/

packer init proactive-engineer.pkr.hcl

packer build \
  -var "vpc_id=vpc-xxx" \
  -var "subnet_id=subnet-xxx" \
  proactive-engineer.pkr.hcl
```

Then set `ami_id` in your `terraform.tfvars` to the new AMI ID.

### Tear Down

```bash
cd terraform/
terraform destroy
```

---

## What It Does

Every 30 minutes, Proactive Engineer checks in on your project and asks itself: *what's the most useful thing I could do right now?*

1. **Scan** — Reads across your Slack channels and GitHub repos to understand what's going on
2. **Reason** — Thinks through what it could help with: bug fixes, missing tests, documentation, dependency updates, CI improvements, scaffolding ideas people have been talking about
3. **Prioritize** — Picks the thing that's actually worth doing — high impact, low risk, not something someone else is already working on
4. **Execute** — Does the work. Opens a branch, writes the code, submits a PR
5. **Communicate** — Posts a short summary in Slack so your team knows what happened

```
⚡ [proactive-engineer] Added missing error handling to /api/payments
PR: github.com/yourco/backend/pull/247
Why: Saw 3 unhandled promise rejections in #alerts yesterday.
```

Your team reviews and merges (or closes) the PR. Over time, the agent learns what your team values and adjusts.

---

## Daily Digest

Every day at **9:00 AM** (via a cron job registered during install), the agent posts a transparency report to `#proactive-engineer`:

- **What it did** — PRs opened, with one-line summaries
- **What it considered but skipped** — and why (e.g. "someone is actively working on that file")
- **What it's watching** — conversations and issues it's tracking

---

## How It Learns

The agent remembers how your team works. It tracks which PRs get merged vs closed, what feedback people give, who owns what parts of the codebase, and what kinds of problems keep coming up. The more you work alongside it, the more useful it gets.

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

The agent is designed to be helpful without getting in the way:

- **$50/day API budget** — pauses and asks in Slack before exceeding
- **Never pushes to main** — always works on branches and opens PRs for human review
- **Never deploys** — its job ends at the PR. Your team decides what ships.
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

### GitHub App (Recommended)

A GitHub App gives the agent its own identity — commits and PRs show as "Proactive Engineer[bot]" instead of your personal account.

1. Go to [github.com/settings/apps](https://github.com/settings/apps) → **New GitHub App**
2. Fill in the name ("Proactive Engineer") and homepage URL ("https://proactive.engineer")
3. Uncheck **Active** under Webhook (we don't need webhooks)
4. Under **Repository permissions**, set:
   - **Contents**: Read and write
   - **Pull requests**: Read and write
   - **Issues**: Read and write
   - **Metadata**: Read-only (auto-selected)
5. Click **Create GitHub App**
6. On the app page, note the **App ID**
7. Scroll down to **Private keys** → **Generate a private key** → save the `.pem` file
8. Go to **Install App** (left sidebar) → install it on your account/org → select the repos you want the agent to access
9. After installing, note the **Installation ID** from the URL: `github.com/settings/installations/INSTALLATION_ID`

You'll need three values: **App ID**, **Installation ID**, and the **path to the .pem file**.

### Alternative: GitHub Personal Access Token

If you prefer simplicity over bot identity (commits will show as your account):

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Click **Generate new token** → **Fine-grained token** (recommended) or **Classic**
3. For classic tokens, select the `repo` scope
4. Copy the token — starts with `ghp_`

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
| GitHub App ID | numeric | github.com/settings/apps → your app |
| GitHub Installation ID | numeric | github.com/settings/installations → your app → URL |
| GitHub Private Key | `.pem` file | github.com/settings/apps → your app → Private keys |
| Gemini API Key | `AI...` | aistudio.google.com/apikey |

*Or, if using a PAT instead of a GitHub App:*

| Key | Format | Where to get it |
| --- | --- | --- |
| GitHub Token | `ghp_...` | github.com/settings/tokens |

### Optional Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `AGENT_NAME` | `default` | Short identifier for this agent (used in profile/service names) |
| `AGENT_DISPLAY_NAME` | `Proactive Engineer` | How this agent appears in Slack messages |

---

## Dashboard Access (Tailscale)

The agent runs on a VM, but you can access its web dashboard from any of your devices using [Tailscale](https://tailscale.com/) — a zero-config mesh VPN.

**On the VM:**

1. Install Tailscale:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

2. Add Tailscale config to your agent's `openclaw.json`:
   ```json
   {
     "gateway": {
       "auth": {
         "allowTailscale": true
       },
       "tailscale": {
         "mode": "serve"
       }
     }
   }
   ```

3. Restart the agent:
   ```bash
   openclaw --profile pe-<name> gateway restart
   ```

**On your laptop/phone:**

Install Tailscale, join the same Tailnet, and open the dashboard at `http://<vm-tailscale-hostname>:18789`. No port forwarding, no SSH tunnels — just works from any device on your Tailnet, fully encrypted.

---

## Engineering Standard

Proactive Engineer doesn't just do random chores. It operates against a defined [engineering competency framework](skills/proactive-engineer/competencies/software_engineer_competency.md) that covers everything from code quality and systems architecture to ownership, strategic judgment, and cross-team influence. The agent reads this competency framework on every cycle and holds itself to the behavioral profile described there: act before being asked, identify systemic issues, optimize for organizational health, reduce entropy across systems, and make the people around it more effective.

You can customize this framework to match your team's values by editing the competency file.

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
    workspace/
      HEARTBEAT.md                        # 30-min scan loop instructions
      IDENTITY.md                         # Agent name and vibe
      SOUL.md                             # Persona, boundaries, tone
      AGENTS.md                           # Operating instructions
    competencies/
      software_engineer_competency.md     # Engineering standard
terraform/                                # AWS EC2 deployment
  main.tf
  variables.tf
  outputs.tf
  user-data.sh
  terraform.tfvars.example
packer/                                   # Pre-built AMI
  proactive-engineer.pkr.hcl
  provision.sh
  configure-agent.sh
install.sh                                # One-command setup (supports named agents)
TESTING.md                                # How to verify it works
```

---

## Built On

Proactive Engineer is built on [OpenClaw](https://openclaw.ai/), an open-source personal AI assistant framework. This repo is a fork of OpenClaw with the proactive-engineer skill and tooling added.

---

## License

MIT
