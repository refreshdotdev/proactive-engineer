#!/bin/bash
set -euo pipefail

exec > /var/log/proactive-engineer-setup.log 2>&1
echo "=== Proactive Engineer Setup Starting ==="
date

SETUP_USER="ubuntu"
SETUP_HOME="/home/$SETUP_USER"
INSTALL_DIR="$SETUP_HOME/.proactive-engineer"

# Variables from Terraform templatefile
SLACK_APP_TOKEN="${slack_app_token}"
SLACK_BOT_TOKEN="${slack_bot_token}"
GITHUB_TOKEN="${github_token}"
GITHUB_APP_ID="${github_app_id}"
GITHUB_APP_INSTALLATION_ID="${github_app_installation_id}"
GEMINI_API_KEY="${gemini_api_key}"
AGENT_NAME="${agent_name}"
AGENT_DISPLAY_NAME="${agent_display_name}"

# Write GitHub App PEM if provided
GITHUB_APP_PEM_PATH=""
if [ -n "$GITHUB_APP_ID" ] && [ -n "${github_app_pem}" ]; then
  GITHUB_APP_PEM_PATH="$INSTALL_DIR/github-app.pem"
  mkdir -p "$INSTALL_DIR"
  cat > "$GITHUB_APP_PEM_PATH" << 'PEMEOF'
${github_app_pem}
PEMEOF
  chmod 600 "$GITHUB_APP_PEM_PATH"
  chown "$SETUP_USER:$SETUP_USER" "$GITHUB_APP_PEM_PATH"
  chown "$SETUP_USER:$SETUP_USER" "$INSTALL_DIR"
fi

# Enable linger so user services survive logout
loginctl enable-linger "$SETUP_USER" 2>/dev/null || true

# Ensure XDG_RUNTIME_DIR exists for the user
XDG_DIR="/run/user/$(id -u $SETUP_USER)"
mkdir -p "$XDG_DIR" 2>/dev/null || true
chown "$SETUP_USER:$SETUP_USER" "$XDG_DIR" 2>/dev/null || true

if [ -f "$SETUP_HOME/configure-agent.sh" ]; then
  echo "Pre-built AMI detected. Running configure-agent.sh..."

  # Update the repo to get latest skill/scripts
  if [ -d "$INSTALL_DIR/.git" ]; then
    sudo -u "$SETUP_USER" git -C "$INSTALL_DIR" pull --quiet origin main 2>/dev/null || true
  fi

  # Use the repo's configure-agent.sh (latest), not the AMI-baked one
  CONFIGURE_SCRIPT="$INSTALL_DIR/packer/configure-agent.sh"
  if [ ! -f "$CONFIGURE_SCRIPT" ]; then
    CONFIGURE_SCRIPT="$SETUP_HOME/configure-agent.sh"
  fi

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
    XDG_RUNTIME_DIR="$XDG_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_DIR/bus" \
    PATH="/home/ubuntu/.npm-global/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    bash "$CONFIGURE_SCRIPT"

else
  echo "Stock Ubuntu detected. Running full install..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl git

  # Write a temporary env file for the user script
  cat > "$SETUP_HOME/.pe-env" << ENVEOF
export SLACK_APP_TOKEN="$SLACK_APP_TOKEN"
export SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN"
export GITHUB_TOKEN="$GITHUB_TOKEN"
export GITHUB_APP_ID="$GITHUB_APP_ID"
export GITHUB_APP_INSTALLATION_ID="$GITHUB_APP_INSTALLATION_ID"
export GITHUB_APP_PEM_PATH="$GITHUB_APP_PEM_PATH"
export GEMINI_API_KEY="$GEMINI_API_KEY"
export AGENT_NAME="$AGENT_NAME"
export AGENT_DISPLAY_NAME="$AGENT_DISPLAY_NAME"
ENVEOF
  chown "$SETUP_USER:$SETUP_USER" "$SETUP_HOME/.pe-env"

  sudo -u "$SETUP_USER" \
    XDG_RUNTIME_DIR="$XDG_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_DIR/bus" \
    bash -c '
      source "$HOME/.pe-env"
      curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
      export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
      git clone --depth 1 https://github.com/refreshdotdev/proactive-engineer.git "$HOME/.proactive-engineer"
      bash "$HOME/.proactive-engineer/packer/configure-agent.sh"
      rm -f "$HOME/.pe-env"
    '
fi

echo "=== Proactive Engineer Setup Complete ==="
date
