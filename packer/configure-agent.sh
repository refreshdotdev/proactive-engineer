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
: "${GEMINI_API_KEY:?Set GEMINI_API_KEY}"

# GitHub: App or PAT
GITHUB_ENV_BLOCK=""
if [ -n "${GITHUB_APP_ID:-}" ] && [ -n "${GITHUB_APP_INSTALLATION_ID:-}" ] && [ -n "${GITHUB_APP_PEM_PATH:-}" ]; then
  GITHUB_ENV_BLOCK="\"GITHUB_APP_ID\": \"$GITHUB_APP_ID\",
    \"GITHUB_APP_INSTALLATION_ID\": \"$GITHUB_APP_INSTALLATION_ID\",
    \"GITHUB_APP_PEM_PATH\": \"$GITHUB_APP_PEM_PATH\""
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  GITHUB_ENV_BLOCK="\"GITHUB_TOKEN\": \"$GITHUB_TOKEN\""
else
  echo "Set GITHUB_APP_ID+GITHUB_APP_INSTALLATION_ID+GITHUB_APP_PEM_PATH or GITHUB_TOKEN" >&2
  exit 1
fi
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
    ${GITHUB_ENV_BLOCK},
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
      "groupPolicy": "open",
      "channels": { "*": { "requireMention": true } },
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

if systemctl --user is-system-running >/dev/null 2>&1; then
  systemctl --user enable "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true
  systemctl --user start "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true
else
  nohup bash -c "export PATH=\"$HOME/.npm-global/bin:$HOME/.local/bin:\$PATH\" && openclaw --profile $PROFILE_NAME gateway --port $PORT" > /tmp/openclaw-$PROFILE_NAME.log 2>&1 &
  disown
  CRON_CMD="@reboot export PATH=\"$HOME/.npm-global/bin:$HOME/.local/bin:\$PATH\" && openclaw --profile $PROFILE_NAME gateway --port $PORT >> /tmp/openclaw-$PROFILE_NAME.log 2>&1"
  (crontab -l 2>/dev/null | grep -v "openclaw.*$PROFILE_NAME"; echo "$CRON_CMD") | crontab -
fi

echo "Agent '$AGENT_NAME' ($AGENT_DISPLAY_NAME) configured and started on port $PORT."
