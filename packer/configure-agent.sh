#!/bin/bash
set -euo pipefail

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

AGENT_NAME="${AGENT_NAME:-default}"
AGENT_DISPLAY_NAME="${AGENT_DISPLAY_NAME:-Proactive Engineer}"
PROFILE_NAME="pe-$AGENT_NAME"
CONFIG_DIR="$HOME/.openclaw-$PROFILE_NAME"
WORKSPACE_DIR="$HOME/.openclaw/workspace-$PROFILE_NAME"
INSTALL_DIR="$HOME/.proactive-engineer"
SKILL_DIR="$HOME/.openclaw/skills/proactive-engineer"
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
  git config --global credential.helper "$INSTALL_DIR/scripts/bin/git-credential-github-app.sh"
  git config --global user.name "Proactive Engineer"
  git config --global user.email "proactive-engineer[bot]@users.noreply.github.com"
  # Auto-upload logo to GitHub App
  if [ -f "$INSTALL_DIR/scripts/upload-github-app-logo.sh" ]; then
    GITHUB_APP_ID="$GITHUB_APP_ID" GITHUB_APP_PEM_PATH="$GITHUB_APP_PEM_PATH" \
      bash "$INSTALL_DIR/scripts/upload-github-app-logo.sh" 2>/dev/null || true
  fi
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  GITHUB_ENV_BLOCK="\"GITHUB_TOKEN\": \"$GITHUB_TOKEN\""
else
  echo "Set GITHUB_APP_ID+GITHUB_APP_INSTALLATION_ID+GITHUB_APP_PEM_PATH or GITHUB_TOKEN" >&2
  exit 1
fi

# Configure branch protection (best-effort, non-fatal)
if [ -f "$INSTALL_DIR/scripts/configure-branch-protection.sh" ]; then
  GITHUB_APP_ID="${GITHUB_APP_ID:-}" \
  GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-}" \
  GITHUB_APP_PEM_PATH="${GITHUB_APP_PEM_PATH:-}" \
  GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    bash "$INSTALL_DIR/scripts/configure-branch-protection.sh" 2>&1 || true
fi

# Symlink skill
mkdir -p "$(dirname "$SKILL_DIR")"
[ -L "$SKILL_DIR" ] && rm "$SKILL_DIR"
[ -d "$SKILL_DIR" ] && rm -rf "$SKILL_DIR"
ln -sf "$INSTALL_DIR/skills/proactive-engineer" "$SKILL_DIR"

# Setup workspace
mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"
for f in HEARTBEAT.md IDENTITY.md SOUL.md AGENTS.md; do
  ln -sf "$INSTALL_DIR/skills/proactive-engineer/workspace/$f" "$WORKSPACE_DIR/$f" 2>/dev/null || true
done

# Determine skill env extras
SKILL_ENV_EXTRA=""
if [ -n "${RESTRICT_TO_CHANNEL:-}" ]; then
  SKILL_ENV_EXTRA="${SKILL_ENV_EXTRA},
          \"RESTRICT_TO_CHANNEL\": \"${RESTRICT_TO_CHANNEL}\""
fi
if [ -n "${ADVISORY_ONLY:-}" ]; then
  SKILL_ENV_EXTRA="${SKILL_ENV_EXTRA},
          \"ADVISORY_ONLY\": \"${ADVISORY_ONLY}\""
fi

# Determine Slack channels config
if [ -n "${RESTRICT_TO_CHANNEL:-}" ]; then
  SLACK_CHANNELS_BLOCK="\"${RESTRICT_TO_CHANNEL}\": { \"allow\": true, \"requireMention\": false }"
  SLACK_GROUP_POLICY="allowlist"
else
  SLACK_CHANNELS_BLOCK="\"*\": { \"requireMention\": true }"
  SLACK_GROUP_POLICY="open"
fi

# Write config
cat > "$CONFIG_DIR/openclaw.json" << CONF
{
  "gateway": {
    "mode": "local",
    "port": $PORT
  },
  "env": {
    ${GITHUB_ENV_BLOCK},
    "GEMINI_API_KEY": "$GEMINI_API_KEY",
    "PATH": "$INSTALL_DIR/scripts/bin:\${PATH}"
  },
  "agents": {
    "defaults": {
      "workspace": "$WORKSPACE_DIR",
      "heartbeat": { "every": "30m" },
      "model": { "primary": "google/gemini-3.1-pro-preview" }
    }
  },
  "channels": {
    "slack": {
      "enabled": true,
      "appToken": "$SLACK_APP_TOKEN",
      "botToken": "$SLACK_BOT_TOKEN",
      "groupPolicy": "$SLACK_GROUP_POLICY",
      "channels": { $SLACK_CHANNELS_BLOCK },
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
          "AGENT_DISPLAY_NAME": "$AGENT_DISPLAY_NAME"${SKILL_ENV_EXTRA}
        }
      }
    }
  }
}
CONF

# Start the gateway — try systemd first, fall back to nohup+cron
sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true

if systemctl --user is-system-running >/dev/null 2>&1; then
  openclaw --profile "$PROFILE_NAME" gateway install 2>/dev/null || true
  systemctl --user enable "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true
  systemctl --user start "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true
else
  # systemd user bus not available (cloud-init context) — use nohup + cron
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

  # Try systemd again with XDG_RUNTIME_DIR set
  if systemctl --user is-system-running >/dev/null 2>&1; then
    openclaw --profile "$PROFILE_NAME" gateway install 2>/dev/null || true
    systemctl --user enable "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true
    systemctl --user start "openclaw-gateway-$PROFILE_NAME" 2>/dev/null || true
  else
    # Direct nohup fallback
    nohup bash -c "export PATH=\"$HOME/.npm-global/bin:$HOME/.local/bin:$INSTALL_DIR/scripts/bin:\$PATH\" && export GITHUB_APP_ID=\"${GITHUB_APP_ID:-}\" && export GITHUB_APP_INSTALLATION_ID=\"${GITHUB_APP_INSTALLATION_ID:-}\" && export GITHUB_APP_PEM_PATH=\"${GITHUB_APP_PEM_PATH:-}\" && openclaw --profile $PROFILE_NAME gateway --port $PORT" > /tmp/openclaw-$PROFILE_NAME.log 2>&1 &
    disown

    # Cron for reboot persistence
    CRON_CMD="@reboot export PATH=\"$HOME/.npm-global/bin:$HOME/.local/bin:$INSTALL_DIR/scripts/bin:\$PATH\" && export GITHUB_APP_ID=\"${GITHUB_APP_ID:-}\" && export GITHUB_APP_INSTALLATION_ID=\"${GITHUB_APP_INSTALLATION_ID:-}\" && export GITHUB_APP_PEM_PATH=\"${GITHUB_APP_PEM_PATH:-}\" && openclaw --profile $PROFILE_NAME gateway --port $PORT >> /tmp/openclaw-$PROFILE_NAME.log 2>&1"
    (crontab -l 2>/dev/null | grep -v "openclaw.*$PROFILE_NAME"; echo "$CRON_CMD") | crontab -
  fi
fi

echo "Agent '$AGENT_NAME' ($AGENT_DISPLAY_NAME) configured and started on port $PORT."
