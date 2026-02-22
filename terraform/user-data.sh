#!/bin/bash
set -euo pipefail

exec > /var/log/proactive-engineer-setup.log 2>&1
echo "=== Proactive Engineer Setup Starting ==="
date

SETUP_USER="ubuntu"
SETUP_HOME="/home/$SETUP_USER"

export SLACK_APP_TOKEN="${slack_app_token}"
export SLACK_BOT_TOKEN="${slack_bot_token}"
export GITHUB_TOKEN="${github_token}"
export GITHUB_APP_ID="${github_app_id}"
export GITHUB_APP_INSTALLATION_ID="${github_app_installation_id}"
export GEMINI_API_KEY="${gemini_api_key}"
export AGENT_NAME="${agent_name}"
export AGENT_DISPLAY_NAME="${agent_display_name}"

# Write GitHub App PEM if provided
GITHUB_APP_PEM_PATH=""
if [ -n "$GITHUB_APP_ID" ] && [ -n "${github_app_pem}" ]; then
  GITHUB_APP_PEM_PATH="$SETUP_HOME/.proactive-engineer/github-app.pem"
  mkdir -p "$SETUP_HOME/.proactive-engineer"
  echo '${github_app_pem}' > "$GITHUB_APP_PEM_PATH"
  chmod 600 "$GITHUB_APP_PEM_PATH"
  chown "$SETUP_USER:$SETUP_USER" "$GITHUB_APP_PEM_PATH"
fi

# Enable linger so systemd user services survive logout
loginctl enable-linger "$SETUP_USER" 2>/dev/null || true

if [ -f "$SETUP_HOME/configure-agent.sh" ]; then
  # Pre-built AMI: just run the configure script
  echo "Pre-built AMI detected. Running configure-agent.sh..."
  sudo -u "$SETUP_USER" \
    SLACK_APP_TOKEN="$SLACK_APP_TOKEN" \
    SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
    GITHUB_TOKEN="$GITHUB_TOKEN" \
    GITHUB_APP_ID="$GITHUB_APP_ID" \
    GITHUB_APP_INSTALLATION_ID="$GITHUB_APP_INSTALLATION_ID" \
    GITHUB_APP_PEM_PATH="$GITHUB_APP_PEM_PATH" \
    GEMINI_API_KEY="$GEMINI_API_KEY" \
    AGENT_NAME="$AGENT_NAME" \
    AGENT_DISPLAY_NAME="$AGENT_DISPLAY_NAME" \
    PATH="/home/ubuntu/.npm-global/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    bash /home/ubuntu/configure-agent.sh
else
  # Stock Ubuntu: full install
  echo "Stock Ubuntu detected. Running full install..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl git

  # Install Tailscale
  curl -fsSL https://tailscale.com/install.sh | sh

  sudo -u "$SETUP_USER" -i bash -c "
    export SLACK_APP_TOKEN='$SLACK_APP_TOKEN'
    export SLACK_BOT_TOKEN='$SLACK_BOT_TOKEN'
    export GITHUB_TOKEN='$GITHUB_TOKEN'
    export GITHUB_APP_ID='$GITHUB_APP_ID'
    export GITHUB_APP_INSTALLATION_ID='$GITHUB_APP_INSTALLATION_ID'
    export GITHUB_APP_PEM_PATH='$GITHUB_APP_PEM_PATH'
    export GEMINI_API_KEY='$GEMINI_API_KEY'
    export AGENT_NAME='$AGENT_NAME'
    export AGENT_DISPLAY_NAME='$AGENT_DISPLAY_NAME'
    export SETUP_TAILSCALE='y'

    curl -fsSL https://raw.githubusercontent.com/refreshdotdev/proactive-engineer/main/install.sh | bash
  "
fi

echo "=== Proactive Engineer Setup Complete ==="
date
