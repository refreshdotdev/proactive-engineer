# proactive.engineer

An open-source AI agent that lives on a server alongside your team. It connects to your Slack and GitHub, looks at everything going on, figures out what's worth doing, and opens PRs for your team to review. You stay in control. It just makes sure the backlog of "we should really do that" actually gets done.

**[proactive.engineer](https://proactive.engineer)** / **[GitHub](https://github.com/refreshdotdev/proactive-engineer)**

---

## Install

One command. Run this on whatever machine you want the agent to live on:

```bash
curl -fsSL https://proactive.engineer/install.sh | bash
```

The script will ask for an agent name, a Slack display name, and your API keys (Slack, GitHub, Gemini). Then it installs everything and starts the agent as a background service with a 30-minute heartbeat loop.

You can also pass everything as environment variables to skip the prompts:

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

Paste this prompt into [Claude Code](https://docs.anthropic.com/en/docs/claude-code) on a fresh machine and it will handle the entire setup for you.

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

Replace the placeholders with your actual keys. Claude Code will run the commands, verify the setup, and troubleshoot if anything goes wrong.

---

## Deploy to Vercel Sandbox

Run your agent on [Vercel Sandbox](https://vercel.com/docs/vercel-sandbox). No AWS account, no VMs to manage. The agent runs in an isolated Firecracker microVM with snapshot-based persistence.

### Quick Start

```bash
cd vercel-sandbox/
npm install

# Connect to Vercel
vercel link
vercel env pull

# Add your API keys to .env.local (see .env.example)
# Then deploy:
npm run deploy
```

The deploy script spins up a microVM, installs OpenClaw and the agent, connects to your Slack and GitHub, and takes a snapshot. After deploy, the agent is live and responding in Slack.

### Keeping it running

Vercel Sandbox VMs timeout after about 5 hours. To keep the agent running continuously, deploy the built-in keepalive cron:

```bash
vercel env add SNAPSHOT_ID    # from deploy output
vercel env add CRON_SECRET    # any random string
vercel deploy --prod
```

A Vercel Cron Job restarts the agent from the latest snapshot every 5 hours. Memory, config, and session history are all preserved across restarts. It picks up exactly where it left off.

---

## Deploy to AWS

If you want the agent on a dedicated EC2 instance that runs 24/7, we include Terraform configs and a pre-built AMI. The agent is running within a minute of `terraform apply`.

```bash
cd terraform/

# Copy the example and fill in your keys
cp terraform.tfvars.example terraform.tfvars

# Deploy
terraform init
terraform apply
```

Terraform provisions the VM from a pre-built AMI (Node.js, OpenClaw, and the skill are already installed), injects your API keys, and starts the agent automatically. No SSH required.

To check on it:

```bash
ssh ubuntu@$(terraform output -raw public_ip)
export PATH="$HOME/.npm-global/bin:$PATH"
openclaw --profile pe-default gateway status
```

To build your own AMI (for example, in a different region):

```bash
cd packer/
packer init proactive-engineer.pkr.hcl
packer build -var "vpc_id=vpc-xxx" -var "subnet_id=subnet-xxx" proactive-engineer.pkr.hcl
```

To tear down:

```bash
cd terraform/
terraform destroy
```

---

## What It Does

Every 30 minutes, the agent checks in on your project and asks itself: what's the most useful thing I could do right now?

1. **Scan** - reads your Slack channels and GitHub repos to understand what's going on
2. **Reason** - thinks through what it could help with: bug fixes, missing tests, documentation, dependency updates, CI improvements, scaffolding ideas people have been talking about
3. **Prioritize** - picks the thing that's actually worth doing. High impact, low risk, not something someone else is already working on
4. **Execute** - does the work. Opens a branch, writes the code, submits a PR
5. **Communicate** - posts a short summary in Slack so your team knows what happened

```
⚡ [proactive-engineer] Added missing error handling to /api/payments
PR: github.com/yourco/backend/pull/247
Why: Saw 3 unhandled promise rejections in #alerts yesterday.
```

Your team reviews and merges (or closes) the PR. Over time, the agent learns what your team values and adjusts.

---

## Daily Digest

Every day at 9:00 AM, the agent posts a transparency report to `#proactive-engineer`:

- What it did (PRs opened, with one-line summaries)
- What it considered but skipped, and why (e.g. "someone is actively working on that file")
- What it's watching (conversations and issues it's tracking for later)

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

Each agent runs as a separate profile with its own service, workspace, and session history. All agents share the same Slack app and GitHub token but appear with different names in Slack.

Agents coordinate through public Slack channels. Before starting work, each agent posts what it's about to do in `#proactive-engineer` so others don't step on each other.

```
Machine
  |
  +-- Agent "backend"   (port 18789, Slack: "PE - Backend")
  +-- Agent "frontend"  (port 18799, Slack: "PE - Frontend")
  +-- Agent "infra"     (port 18809, Slack: "PE - Infra")
```

Manage individual agents:

```bash
openclaw --profile pe-backend gateway status
openclaw --profile pe-frontend gateway restart
openclaw --profile pe-infra dashboard
```

---

## Guardrails

- **$50/day API budget** - pauses and asks in Slack before going over
- **Never pushes to main** - always works on branches and opens PRs for human review
- **Never deploys** - its job ends at the PR. Your team decides what ships.
- **No large refactors without buy-in** - opens issues and asks first
- **Doesn't touch active work** - checks recent commits and open PRs before starting

---

## Setting Up Your Keys

### Slack Bot (2 tokens needed)

You need a Bot Token (`xoxb-...`) and an App Token (`xapp-...`).

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App** > **From an app manifest**
2. Select your workspace
3. Paste this manifest:

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

4. Click **Next** > **Create**
5. Go to **Basic Information** > **App-Level Tokens** > **Generate Token and Scopes**
6. Name it anything, add the scope `connections:write`, click **Generate**
7. Copy the **App Token** (starts with `xapp-`)
8. Go to **Install App** > **Install to Workspace** > **Allow**
9. Copy the **Bot User OAuth Token** (starts with `xoxb-`)
10. In Slack, invite the bot to your channels: `/invite @Proactive Engineer`

### GitHub App (recommended)

A GitHub App gives the agent its own identity. Commits and PRs show as "Proactive Engineer[bot]" instead of your personal account.

1. Go to [github.com/settings/apps](https://github.com/settings/apps) > **New GitHub App**
2. Name it and set the homepage URL to `https://proactive.engineer`
3. Uncheck **Active** under Webhook
4. Under **Repository permissions**, set Contents, Pull requests, and Issues to Read and write
5. Click **Create GitHub App**
6. Copy the **App ID** from the app page
7. Under **Private keys**, click **Generate a private key** and save the `.pem` file
8. Go to **Install App** > install on your account/org > select repos
9. Copy the **Installation ID** from the URL after installing

### Alternative: GitHub Personal Access Token

Simpler to set up, but commits show as your personal account.

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Generate a new token with `repo` scope
3. Copy the token (starts with `ghp_`)

### Gemini API Key

1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Create an API key
3. Copy it

### Keys summary

| Key | Format | Where to get it |
| --- | --- | --- |
| Slack App Token | `xapp-...` | api.slack.com/apps > Socket Mode > App-Level Tokens |
| Slack Bot Token | `xoxb-...` | api.slack.com/apps > OAuth & Permissions |
| GitHub App ID | numeric | github.com/settings/apps > your app |
| GitHub Installation ID | numeric | github.com/settings/installations > your app > URL |
| GitHub Private Key | `.pem` file | github.com/settings/apps > your app > Private keys |
| Gemini API Key | `AI...` | aistudio.google.com/apikey |

---

## Engineering Standard

The agent operates against a defined [engineering competency framework](skills/proactive-engineer/competencies/software_engineer_competency.md) that covers code quality, systems architecture, ownership, strategic judgment, and cross-team influence. You can customize it to match your team's values.

---

## Project Structure

```
skills/
  proactive-engineer/
    SKILL.md                              # Agent behavior definition
    workspace/
      HEARTBEAT.md                        # 30-min scan loop
      IDENTITY.md                         # Agent name and vibe
      SOUL.md                             # Persona, boundaries, tone
      AGENTS.md                           # Operating instructions
    competencies/
      software_engineer_competency.md     # Engineering standard
scripts/
  refresh-github-token.sh                 # GitHub App token refresh
  bin/
    gh                                    # gh wrapper (auto-injects App token)
    git-credential-github-app.sh          # Git credential helper
terraform/                                # AWS EC2 deployment
packer/                                   # Pre-built AMI
vercel-sandbox/                           # Vercel Sandbox deployment
install.sh                                # One-command setup
```

---

## Built On

Proactive Engineer is built on [OpenClaw](https://openclaw.ai/), an open-source AI assistant framework. This repo is a fork of OpenClaw with the proactive-engineer skill and deployment tooling added.

---

## License

MIT
