#!/usr/bin/env bash
set -euo pipefail

REPO="refreshdotdev/proactive-engineer"
BRANCH="main"
INSTALL_DIR="$HOME/.proactive-engineer"
BASE_PORT=18789

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[proactive-engineer]${NC} $1"; }
ok()    { echo -e "${GREEN}[proactive-engineer]${NC} $1"; }
warn()  { echo -e "${YELLOW}[proactive-engineer]${NC} $1"; }
err()   { echo -e "${RED}[proactive-engineer]${NC} $1" >&2; exit 1; }

prompt_key() {
  local var_name="$1"
  local label="$2"
  local hint="$3"
  local current="${!var_name:-}"

  if [ -n "$current" ]; then
    ok "$label: set via environment"
    return
  fi

  echo ""
  echo -e "  ${CYAN}$label${NC}"
  echo -e "  ${DIM}$hint${NC}"
  echo -n "  > "
  read -r value
  if [ -z "$value" ]; then
    err "$label is required."
  fi
  eval "export $var_name='$value'"
}

prompt_optional() {
  local var_name="$1"
  local label="$2"
  local hint="$3"
  local default="$4"
  local current="${!var_name:-}"

  if [ -n "$current" ]; then
    ok "$label: $current"
    return
  fi

  echo ""
  echo -e "  ${CYAN}$label${NC} ${DIM}(default: $default)${NC}"
  echo -e "  ${DIM}$hint${NC}"
  echo -n "  > "
  read -r value
  if [ -z "$value" ]; then
    value="$default"
  fi
  eval "export $var_name='$value'"
}

count_existing_profiles() {
  local count=0
  for d in "$HOME"/.openclaw-pe-*/; do
    [ -d "$d" ] && count=$((count + 1))
  done
  echo "$count"
}

# ── Banner ─────────────────────────────────────────────────────

clear 2>/dev/null || true
echo ""
echo -e "${CYAN}"
echo "  ┌──────────────────────────────────────────┐"
echo "  │                                          │"
echo "  │        proactive.engineer                │"
echo "  │        an AI that ships while you sleep   │"
echo "  │                                          │"
echo "  └──────────────────────────────────────────┘"
echo -e "${NC}"
echo -e "  This script sets up a Proactive Engineer agent on this"
echo -e "  machine. You can run it multiple times to add more agents."
echo ""
echo -e "  ${DIM}https://proactive.engineer${NC}"
echo -e "  ${DIM}https://github.com/refreshdotdev/proactive-engineer${NC}"
echo ""

# ── Agent Identity ─────────────────────────────────────────────

echo -e "${YELLOW}━━━ Agent Identity ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

prompt_optional "AGENT_NAME" \
  "Agent Name" \
  "A short identifier for this agent (letters, numbers, hyphens). Used in config paths and service names." \
  "default"

prompt_optional "AGENT_DISPLAY_NAME" \
  "Slack Display Name" \
  "How this agent appears in Slack messages. Use different names for different agents." \
  "Proactive Engineer"

PROFILE_NAME="pe-${AGENT_NAME}"
CONFIG_DIR="$HOME/.openclaw-${PROFILE_NAME}"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
WORKSPACE_DIR="$HOME/.openclaw/workspace-${PROFILE_NAME}"
SKILL_DIR="$HOME/.openclaw/skills/proactive-engineer"

NUM_EXISTING=$(count_existing_profiles)
AGENT_PORT=$((BASE_PORT + NUM_EXISTING * 10))

if [ -d "$CONFIG_DIR" ]; then
  info "Profile '${AGENT_NAME}' already exists. This will update it."
  EXISTING_PORT=$(grep -o '"port":[[:space:]]*[0-9]*' "$CONFIG_FILE" 2>/dev/null | grep -o '[0-9]*' || echo "")
  if [ -n "$EXISTING_PORT" ]; then
    AGENT_PORT=$EXISTING_PORT
  fi
fi

ok "Agent: ${AGENT_NAME} (display: ${AGENT_DISPLAY_NAME})"
ok "Port: ${AGENT_PORT}"

# ── Collect API keys ───────────────────────────────────────────

echo ""
echo -e "${YELLOW}━━━ Integration Keys ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Set these as env vars to skip prompts."
echo -e "  ${DIM}Setup guide: https://github.com/refreshdotdev/proactive-engineer#setting-up-your-keys${NC}"

prompt_key "SLACK_APP_TOKEN" \
  "Slack App Token" \
  "Starts with xapp-... — api.slack.com/apps → Socket Mode → App-Level Tokens"

prompt_key "SLACK_BOT_TOKEN" \
  "Slack Bot Token" \
  "Starts with xoxb-... — api.slack.com/apps → OAuth & Permissions"

# GitHub: prefer App (bot identity) over PAT
USE_GITHUB_APP=""
if [ -n "${GITHUB_APP_ID:-}" ] && [ -n "${GITHUB_APP_INSTALLATION_ID:-}" ] && [ -n "${GITHUB_APP_PEM_PATH:-}" ]; then
  USE_GITHUB_APP="yes"
  ok "GitHub App: configured via environment"
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  ok "GitHub Token: set via environment (PAT fallback)"
else
  echo ""
  echo -e "  ${CYAN}GitHub Authentication${NC}"
  echo -e "  ${DIM}A GitHub App gives the agent its own identity (commits show as 'Proactive Engineer[bot]').${NC}"
  echo -e "  ${DIM}A Personal Access Token is simpler but commits show as your account.${NC}"
  echo -n "  Use GitHub App? [Y/n] > "
  read -r gh_choice
  if [[ ! "$gh_choice" =~ ^[Nn] ]]; then
    USE_GITHUB_APP="yes"
    prompt_key "GITHUB_APP_ID" \
      "GitHub App ID" \
      "From github.com/settings/apps → your app → App ID"
    prompt_key "GITHUB_APP_INSTALLATION_ID" \
      "GitHub App Installation ID" \
      "From github.com/settings/installations → click your app → ID in the URL"
    prompt_key "GITHUB_APP_PEM_PATH" \
      "Path to Private Key (.pem file)" \
      "Downloaded when you created the app. E.g. ~/proactive-engineer.pem"
  else
    prompt_key "GITHUB_TOKEN" \
      "GitHub Personal Access Token" \
      "Starts with ghp_... — github.com/settings/tokens (needs repo scope)"
  fi
fi

prompt_key "GEMINI_API_KEY" \
  "Google Gemini API Key" \
  "From aistudio.google.com/apikey"

echo ""
echo -e "${YELLOW}━━━ Channel Restriction (optional) ━━━━━━━━━━━━━━${NC}"

RESTRICT_TO_CHANNEL="${RESTRICT_TO_CHANNEL:-}"

if [ -z "$RESTRICT_TO_CHANNEL" ]; then
  echo ""
  echo -e "  ${CYAN}Restrict to a single Slack channel?${NC} ${DIM}(optional)${NC}"
  echo -e "  ${DIM}Leave blank to monitor all channels the bot is in.${NC}"
  echo -n "  > "
  read -r RESTRICT_TO_CHANNEL
fi

if [ -n "$RESTRICT_TO_CHANNEL" ]; then
  # Strip leading # if present
  RESTRICT_TO_CHANNEL="${RESTRICT_TO_CHANNEL#\#}"
  ok "Channel restriction: #${RESTRICT_TO_CHANNEL}"
else
  info "No channel restriction — agent will monitor all channels it's in."
fi

echo ""
ok "All keys collected."

# ── Install OpenClaw ───────────────────────────────────────────

echo ""
echo -e "${YELLOW}━━━ Installing Dependencies ━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if ! command -v openclaw >/dev/null 2>&1; then
  info "Installing OpenClaw (handles Node.js, Git, npm)..."
  curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
  export PATH="$HOME/.local/bin:$PATH"
  command -v openclaw >/dev/null 2>&1 || err "OpenClaw installation failed. See https://docs.openclaw.ai/start/getting-started"
  ok "OpenClaw installed."
else
  ok "OpenClaw already installed."
fi

# ── Clone / update proactive-engineer ──────────────────────────

echo ""
echo -e "${YELLOW}━━━ Setting Up Proactive Engineer ━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -d "$INSTALL_DIR/.git" ]; then
  info "Updating source..."
  git -C "$INSTALL_DIR" pull --quiet origin "$BRANCH" 2>/dev/null || true
  ok "Updated."
else
  info "Downloading proactive-engineer..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$INSTALL_DIR"
  ok "Downloaded to $INSTALL_DIR"
fi

# Copy GitHub App private key if using App auth
if [ "$USE_GITHUB_APP" = "yes" ] && [ -n "${GITHUB_APP_PEM_PATH:-}" ]; then
  PEM_DEST="$INSTALL_DIR/github-app.pem"
  cp "$GITHUB_APP_PEM_PATH" "$PEM_DEST" 2>/dev/null || true
  chmod 600 "$PEM_DEST" 2>/dev/null || true
  export GITHUB_APP_PEM_PATH="$PEM_DEST"

  # Configure git credential helper and identity so all git/gh operations
  # automatically use the App token (prevents accidental personal auth)
  git config --global credential.helper "$INSTALL_DIR/scripts/bin/git-credential-github-app.sh"
  git config --global user.name "Proactive Engineer"
  git config --global user.email "proactive-engineer[bot]@users.noreply.github.com"
  ok "Private key copied. Git configured for App identity."

  # Upload the logo to the GitHub App automatically
  if [ -f "$INSTALL_DIR/scripts/upload-github-app-logo.sh" ]; then
    GITHUB_APP_ID="$GITHUB_APP_ID" GITHUB_APP_PEM_PATH="$PEM_DEST" \
      bash "$INSTALL_DIR/scripts/upload-github-app-logo.sh" 2>/dev/null || true
  fi
fi

# ── Branch Protection (optional) ──────────────────────────────

SETUP_BRANCH_PROTECTION="${SETUP_BRANCH_PROTECTION:-}"

if [ -z "$SETUP_BRANCH_PROTECTION" ]; then
  echo ""
  echo -e "  ${CYAN}Configure branch protection on your repos?${NC}"
  echo -e "  ${DIM}Prevents the bot from merging its own PRs by requiring human review.${NC}"
  echo -e "  ${DIM}Recommended. You can do this manually later — see the README.${NC}"
  echo -n "  [Y/n] > "
  read -r SETUP_BRANCH_PROTECTION
fi

if [[ "$SETUP_BRANCH_PROTECTION" =~ ^[Nn] ]]; then
  info "Skipping branch protection. See README for manual setup."
else
  echo ""
  echo -e "${YELLOW}━━━ Configuring Branch Protection ━━━━━━━━━━━━━━━${NC}"
  echo ""

  if [ -f "$INSTALL_DIR/scripts/configure-branch-protection.sh" ]; then
    if [ "$USE_GITHUB_APP" = "yes" ]; then
      GITHUB_APP_ID="$GITHUB_APP_ID" \
      GITHUB_APP_INSTALLATION_ID="$GITHUB_APP_INSTALLATION_ID" \
      GITHUB_APP_PEM_PATH="$GITHUB_APP_PEM_PATH" \
        bash "$INSTALL_DIR/scripts/configure-branch-protection.sh" \
        && ok "Branch protection configured." \
        || warn "Could not configure branch protection. See README for manual setup."
    else
      GITHUB_TOKEN="$GITHUB_TOKEN" \
        bash "$INSTALL_DIR/scripts/configure-branch-protection.sh" \
        && ok "Branch protection configured." \
        || warn "Could not configure branch protection. See README for manual setup."
    fi
  else
    warn "Branch protection script not found. Update proactive-engineer and re-run."
  fi
fi

# ── Symlink skill (shared across all agents) ───────────────────

info "Installing agent skill..."
mkdir -p "$(dirname "$SKILL_DIR")"
[ -L "$SKILL_DIR" ] && rm "$SKILL_DIR"
[ -d "$SKILL_DIR" ] && rm -rf "$SKILL_DIR"
ln -sf "$INSTALL_DIR/skills/proactive-engineer" "$SKILL_DIR"
ok "Skill installed."

# ── Install Tailscale (optional) ───────────────────────────────

SETUP_TAILSCALE="${SETUP_TAILSCALE:-}"
TAILSCALE_IP=""

if [ -z "$SETUP_TAILSCALE" ]; then
  echo ""
  echo -e "  ${CYAN}Set up Tailscale for dashboard access?${NC}"
  echo -e "  ${DIM}Lets you access the agent's web UI from any device on your Tailnet.${NC}"
  echo -e "  ${DIM}Skip this if you only need Slack. You can set it up later.${NC}"
  echo -n "  [y/N] > "
  read -r SETUP_TAILSCALE
fi

if [[ "$SETUP_TAILSCALE" =~ ^[Yy] ]]; then
  echo ""
  echo -e "${YELLOW}━━━ Setting Up Dashboard Access (Tailscale) ━━━━━${NC}"
  echo ""

  if ! command -v tailscale >/dev/null 2>&1; then
    info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    ok "Tailscale installed."
  else
    ok "Tailscale already installed."
  fi

  if ! sudo tailscale status >/dev/null 2>&1; then
    info "Starting Tailscale — follow the link below to authenticate:"
    echo ""
    sudo tailscale up
    echo ""
    ok "Tailscale connected."
  else
    ok "Tailscale already connected."
  fi

  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
  if [ -n "$TAILSCALE_IP" ]; then
    ok "Tailscale IP: $TAILSCALE_IP"
  fi
else
  info "Skipping Tailscale. You can set it up later — see the README."
fi

# ── Set up agent workspace + heartbeat ─────────────────────────

info "Setting up workspace for agent '${AGENT_NAME}'..."
mkdir -p "$WORKSPACE_DIR"
for f in HEARTBEAT.md IDENTITY.md SOUL.md AGENTS.md; do
  ln -sf "$INSTALL_DIR/skills/proactive-engineer/workspace/$f" "$WORKSPACE_DIR/$f" 2>/dev/null || \
  ln -sf "$INSTALL_DIR/skills/proactive-engineer/$f" "$WORKSPACE_DIR/$f" 2>/dev/null || true
done
ok "Workspace ready at $WORKSPACE_DIR"

# ── Write config ───────────────────────────────────────────────

mkdir -p "$CONFIG_DIR"

info "Writing configuration for agent '${AGENT_NAME}'..."

GATEWAY_EXTRA=""
if [ -n "$TAILSCALE_IP" ]; then
  GATEWAY_EXTRA=',
    "auth": { "allowTailscale": true },
    "tailscale": { "mode": "serve" }'
fi

# Determine GitHub env block
if [ "$USE_GITHUB_APP" = "yes" ]; then
  GITHUB_ENV_BLOCK="\"GITHUB_APP_ID\": \"${GITHUB_APP_ID}\",
    \"GITHUB_APP_INSTALLATION_ID\": \"${GITHUB_APP_INSTALLATION_ID}\",
    \"GITHUB_APP_PEM_PATH\": \"${GITHUB_APP_PEM_PATH}\""
else
  GITHUB_ENV_BLOCK="\"GITHUB_TOKEN\": \"${GITHUB_TOKEN}\""
fi

# Determine skill env block (conditionally include RESTRICT_TO_CHANNEL)
SKILL_ENV_EXTRA=""
if [ -n "$RESTRICT_TO_CHANNEL" ]; then
  SKILL_ENV_EXTRA=",
          \"RESTRICT_TO_CHANNEL\": \"${RESTRICT_TO_CHANNEL}\""
fi

cat > "$CONFIG_FILE" <<CONF
{
  "gateway": {
    "mode": "local",
    "port": ${AGENT_PORT}${GATEWAY_EXTRA}
  },
  "env": {
    ${GITHUB_ENV_BLOCK},
    "GEMINI_API_KEY": "${GEMINI_API_KEY}",
    "PATH": "${INSTALL_DIR}/scripts/bin:\${PATH}"
  },
  "agents": {
    "defaults": {
      "workspace": "${WORKSPACE_DIR}",
      "heartbeat": {
        "every": "30m"
      },
      "model": {
        "primary": "google/gemini-3.1-pro-preview"
      }
    }
  },
  "channels": {
    "slack": {
      "enabled": true,
      "appToken": "${SLACK_APP_TOKEN}",
      "botToken": "${SLACK_BOT_TOKEN}",
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
          "AGENT_NAME": "${AGENT_NAME}",
          "AGENT_DISPLAY_NAME": "${AGENT_DISPLAY_NAME}"${SKILL_ENV_EXTRA}
        }
      }
    }
  }
}
CONF
ok "Configuration saved to $CONFIG_FILE"

# ── Install daemon ─────────────────────────────────────────────

echo ""
echo -e "${YELLOW}━━━ Starting Background Service ━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Installing service for agent '${AGENT_NAME}'..."
openclaw --profile "$PROFILE_NAME" gateway install 2>/dev/null \
  || warn "Gateway install returned non-zero (may already be configured)."

if command -v loginctl >/dev/null 2>&1; then
  sudo loginctl enable-linger "$(whoami)" 2>/dev/null \
    || warn "Could not enable-linger — service may not survive logout."
fi

systemctl --user enable "openclaw-gateway-${PROFILE_NAME}" 2>/dev/null || true
systemctl --user restart "openclaw-gateway-${PROFILE_NAME}" 2>/dev/null || true

sleep 3

if openclaw --profile "$PROFILE_NAME" gateway status 2>/dev/null | grep -qi "running"; then
  ok "Agent '${AGENT_NAME}' is running."
else
  warn "Agent may still be starting. Check: openclaw --profile ${PROFILE_NAME} gateway status"
fi

# ── Register daily digest cron ─────────────────────────────────

info "Registering daily digest cron job..."
if [ -n "$RESTRICT_TO_CHANNEL" ]; then
  DIGEST_CHANNEL="#${RESTRICT_TO_CHANNEL}"
else
  DIGEST_CHANNEL="#proactive-engineer"
fi
openclaw --profile "$PROFILE_NAME" cron add \
  --name "daily-digest-${AGENT_NAME}" \
  --cron "0 9 * * *" \
  --session isolated \
  --message "Post your daily digest to ${DIGEST_CHANNEL}. Include: (1) What you did today (PRs with one-line summaries), (2) What you considered but chose not to do and why, (3) What you're watching. Post as '${AGENT_DISPLAY_NAME}'." \
  2>/dev/null || warn "Could not register daily digest cron (may need gateway running first)."
ok "Daily digest scheduled for 9am."

# ── Done ───────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Agent '${AGENT_NAME}' is installed and running.${NC}"
echo ""
echo -e "  Display name:  ${AGENT_DISPLAY_NAME}"
echo -e "  Profile:       ${PROFILE_NAME}"
echo -e "  Port:          ${AGENT_PORT}"
echo -e "  Heartbeat:     every 30 minutes"
echo -e "  Daily digest:  9:00 AM"
if [ -n "$TAILSCALE_IP" ]; then
echo -e "  Dashboard:     ${CYAN}http://${TAILSCALE_IP}:${AGENT_PORT}${NC}"
fi
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo ""
echo "    openclaw --profile ${PROFILE_NAME} gateway status"
echo "    openclaw --profile ${PROFILE_NAME} skills list"
echo "    openclaw --profile ${PROFILE_NAME} gateway restart"
echo "    openclaw --profile ${PROFILE_NAME} dashboard"
echo "    journalctl --user -u openclaw-gateway-${PROFILE_NAME} -f"
echo ""
echo -e "  ${CYAN}Add another agent:${NC}"
echo ""
echo "    AGENT_NAME=frontend AGENT_DISPLAY_NAME=\"PE - Frontend\" \\"
echo "    SLACK_APP_TOKEN=\$SLACK_APP_TOKEN SLACK_BOT_TOKEN=\$SLACK_BOT_TOKEN \\"
echo "    GITHUB_TOKEN=\$GITHUB_TOKEN GEMINI_API_KEY=\$GEMINI_API_KEY \\"
echo "      curl -fsSL https://proactive.engineer/install.sh | bash"
echo ""
echo -e "  ${DIM}Config:     $CONFIG_FILE${NC}"
echo -e "  ${DIM}Workspace:  $WORKSPACE_DIR${NC}"
echo -e "  ${DIM}Source:     $INSTALL_DIR${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
