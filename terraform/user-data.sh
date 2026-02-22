#!/bin/bash
set -euo pipefail

exec > /var/log/proactive-engineer-setup.log 2>&1
echo "=== Proactive Engineer Setup Starting ==="
date

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl git

SETUP_USER="ubuntu"
SETUP_HOME="/home/$SETUP_USER"

sudo -u "$SETUP_USER" -i bash << 'USEREOF'
set -euo pipefail

export SLACK_APP_TOKEN="${slack_app_token}"
export SLACK_BOT_TOKEN="${slack_bot_token}"
export GITHUB_TOKEN="${github_token}"
export GEMINI_API_KEY="${gemini_api_key}"
export AGENT_NAME="${agent_name}"
export AGENT_DISPLAY_NAME="${agent_display_name}"

curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
export PATH="$HOME/.local/bin:$PATH"

REPO="refreshdotdev/proactive-engineer"
INSTALL_DIR="$HOME/.proactive-engineer"
PROFILE_NAME="pe-$AGENT_NAME"
CONFIG_DIR="$HOME/.openclaw-$PROFILE_NAME"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
WORKSPACE_DIR="$HOME/.openclaw/workspace-$PROFILE_NAME"
SKILL_DIR="$HOME/.openclaw/skills/proactive-engineer"

git clone --depth 1 https://github.com/$REPO.git "$INSTALL_DIR"

mkdir -p "$(dirname "$SKILL_DIR")"
ln -sf "$INSTALL_DIR/skills/proactive-engineer" "$SKILL_DIR"

mkdir -p "$WORKSPACE_DIR"
for f in HEARTBEAT.md IDENTITY.md SOUL.md AGENTS.md; do
  ln -sf "$INSTALL_DIR/skills/proactive-engineer/workspace/$f" "$WORKSPACE_DIR/$f" 2>/dev/null || true
done

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << CONF
{
  "gateway": {
    "mode": "local",
    "port": 18789
  },
  "env": {
    "GITHUB_TOKEN": "$GITHUB_TOKEN",
    "GEMINI_API_KEY": "$GEMINI_API_KEY"
  },
  "agents": {
    "defaults": {
      "workspace": "$WORKSPACE_DIR",
      "heartbeat": {
        "every": "30m"
      }
    }
  },
  "channels": {
    "slack": {
      "enabled": true,
      "appToken": "$SLACK_APP_TOKEN",
      "botToken": "$SLACK_BOT_TOKEN",
      "dmPolicy": "open",
      "allowFrom": ["*"]
    }
  },
  "skills": {
    "entries": {
      "proactive-engineer": {
        "enabled": true,
        "env": {
          "AGENT_NAME": "$AGENT_NAME",
          "AGENT_DISPLAY_NAME": "$AGENT_DISPLAY_NAME"
        }
      }
    }
  }
}
CONF

openclaw --profile "$PROFILE_NAME" gateway install 2>/dev/null || true

USEREOF

loginctl enable-linger "$SETUP_USER" 2>/dev/null || true

sudo -u "$SETUP_USER" -i bash -c '
  export PATH="$HOME/.local/bin:$PATH"
  systemctl --user enable openclaw-gateway-pe-${agent_name} 2>/dev/null || true
  systemctl --user start openclaw-gateway-pe-${agent_name} 2>/dev/null || true
'

echo "=== Proactive Engineer Setup Complete ==="
date
