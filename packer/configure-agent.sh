#!/bin/bash
set -euo pipefail

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

AGENT_NAME="${AGENT_NAME:-default}"
AGENT_DISPLAY_NAME="${AGENT_DISPLAY_NAME:-Proactive Engineer}"
PROFILE_NAME="pe-$AGENT_NAME"
CONFIG_DIR="$HOME/.openclaw-$PROFILE_NAME"
WORKSPACE_DIR="$HOME/.openclaw/workspace-$PROFILE_NAME"
PORT="${PORT:-18789}"

: "${SLACK_APP_TOKEN:?Set SLACK_APP_TOKEN}"
: "${SLACK_BOT_TOKEN:?Set SLACK_BOT_TOKEN}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN}"
: "${GEMINI_API_KEY:?Set GEMINI_API_KEY}"

mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

for f in HEARTBEAT.md IDENTITY.md SOUL.md AGENTS.md; do
  ln -sf "$HOME/.proactive-engineer/skills/proactive-engineer/workspace/$f" "$WORKSPACE_DIR/$f" 2>/dev/null || true
done

cat > "$CONFIG_DIR/openclaw.json" << CONF
{
  "gateway": {
    "mode": "local",
    "port": $PORT,
    "auth": {
      "allowTailscale": true
    },
    "tailscale": {
      "mode": "serve"
    }
  },
  "env": {
    "GITHUB_TOKEN": "$GITHUB_TOKEN",
    "GEMINI_API_KEY": "$GEMINI_API_KEY"
  },
  "agents": {
    "defaults": {
      "workspace": "$WORKSPACE_DIR",
      "heartbeat": { "every": "30m" }
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
sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true

if ! sudo tailscale status >/dev/null 2>&1; then
  echo "Run 'sudo tailscale up' to connect Tailscale for dashboard access."
fi

systemctl --user enable "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true
systemctl --user start "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true

echo "Agent '$AGENT_NAME' ($AGENT_DISPLAY_NAME) configured and started on port $PORT."
