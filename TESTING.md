# Testing Proactive Engineer

## Quick Smoke Test (local, no VM needed)

You can test the skill locally on any machine that has OpenClaw installed.

### 1. Install OpenClaw locally

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

### 2. Symlink the skill

```bash
ln -sf $(pwd)/skills/proactive-engineer ~/.openclaw/skills/proactive-engineer
```

### 3. Configure API keys

Add to `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "proactive-engineer": {
        "enabled": true,
        "env": {
          "SLACK_API_TOKEN": "xoxb-your-test-token",
          "GITHUB_TOKEN": "ghp_your-test-token",
          "GEMINI_API_KEY": "your-gemini-key"
        }
      }
    }
  }
}
```

### 4. Verify the skill loads

```bash
openclaw skills list
# Should show "proactive-engineer" in the list
```

### 5. Test via the OpenClaw dashboard

```bash
openclaw dashboard
```

In the chat UI, ask:
- "What skills do you have?" — should mention proactive-engineer
- "Run the proactive engineer scan" — should attempt to read Slack channels
- "What would you do if you had access to repo X?" — should reason about potential work

---

## Full Integration Test (on a VM)

### Prerequisites

- A fresh Ubuntu 22.04+ VM (AWS EC2 t3.medium recommended)
- A Slack workspace with a bot token that has channel read/write permissions
- A GitHub token with repo access
- A Gemini API key

### 1. Run the install script

```bash
SLACK_API_TOKEN=xoxb-... \
GITHUB_TOKEN=ghp_... \
GEMINI_API_KEY=... \
  curl -fsSL https://proactive.engineer/install.sh | bash
```

### 2. Verify the service is running

```bash
openclaw gateway status          # should say "running"
openclaw skills list             # should include "proactive-engineer"
systemctl --user status openclaw-gateway  # should be active
```

### 3. Check Slack connectivity

- The agent should be able to read messages from channels the bot is in
- Test by posting a message in a channel and asking the agent (via dashboard): "What was the last message in #general?"

### 4. Check GitHub connectivity

- Ask the agent: "List the open issues in [your-repo]"
- Ask: "Create a branch called test/proactive-engineer in [your-repo]" — verify it appears on GitHub

### 5. Test the core loop

Create a test scenario:
1. Create a small test repo with an obvious issue (e.g., a function with no error handling, or a missing README)
2. Post in Slack: "the error handling in api.js is really bad"
3. Wait for the agent to pick it up, open a PR, and post a summary in Slack

### 6. Test the daily digest

- Ask the agent: "Post your daily digest now"
- Verify it posts a structured summary to `#proactive-engineer` (or creates the channel)

### 7. Test persistence

```bash
sudo reboot
# After reboot, SSH back in:
openclaw gateway status  # should be running again
```

---

## What Success Looks Like

- [ ] `install.sh` completes without errors on a fresh Ubuntu VM
- [ ] OpenClaw gateway starts and stays running (systemd)
- [ ] The proactive-engineer skill is loaded
- [ ] Agent can read Slack messages
- [ ] Agent can interact with GitHub (list issues, create branches, open PRs)
- [ ] Agent reasons about what to do and prioritizes
- [ ] Agent posts updates to Slack after completing work
- [ ] Agent survives a reboot
- [ ] Daily digest works
