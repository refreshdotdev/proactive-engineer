#!/usr/bin/env bash
set -euo pipefail

REPO="refreshdotdev/proactive-engineer"
BRANCH="main"
INSTALL_DIR="$HOME/.proactive-engineer"
SKILL_DIR="$HOME/.openclaw/skills/proactive-engineer"
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
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
echo -e "  This script will set up Proactive Engineer on this machine."
echo -e "  It installs everything needed and starts the agent as a"
echo -e "  background service that runs continuously."
echo ""
echo -e "  ${DIM}https://proactive.engineer${NC}"
echo -e "  ${DIM}https://github.com/refreshdotdev/proactive-engineer${NC}"
echo ""

# ── Collect API keys ───────────────────────────────────────────

echo -e "${YELLOW}━━━ Integration Keys ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Proactive Engineer needs API keys to connect to your"
echo -e "  team's tools. Set them as env vars to skip these prompts."
echo ""
echo -e "  ${DIM}Setup guide: https://github.com/refreshdotdev/proactive-engineer#setting-up-your-keys${NC}"

prompt_key "SLACK_APP_TOKEN" \
  "Slack App Token" \
  "Starts with xapp-... — api.slack.com/apps → Socket Mode → App-Level Tokens"

prompt_key "SLACK_BOT_TOKEN" \
  "Slack Bot Token" \
  "Starts with xoxb-... — api.slack.com/apps → OAuth & Permissions"

prompt_key "GITHUB_TOKEN" \
  "GitHub Personal Access Token" \
  "Starts with ghp_... — github.com/settings/tokens (needs repo scope)"

prompt_key "GEMINI_API_KEY" \
  "Google Gemini API Key" \
  "From aistudio.google.com/apikey"

echo ""
ok "All keys collected."

# ── Install OpenClaw ───────────────────────────────────────────

echo ""
echo -e "${YELLOW}━━━ Installing Dependencies ━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if ! command -v openclaw >/dev/null 2>&1; then
  info "Installing OpenClaw (this handles Node.js, Git, and npm)..."
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
  info "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --quiet origin "$BRANCH" 2>/dev/null || true
  ok "Updated."
else
  info "Downloading proactive-engineer..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$INSTALL_DIR"
  ok "Downloaded to $INSTALL_DIR"
fi

# ── Symlink skill ──────────────────────────────────────────────

info "Installing agent skill..."
mkdir -p "$(dirname "$SKILL_DIR")"
[ -L "$SKILL_DIR" ] && rm "$SKILL_DIR"
[ -d "$SKILL_DIR" ] && rm -rf "$SKILL_DIR"
ln -sf "$INSTALL_DIR/skills/proactive-engineer" "$SKILL_DIR"
ok "Skill installed."

# ── Write config ───────────────────────────────────────────────

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ] && command -v node >/dev/null 2>&1; then
  info "Updating configuration..."
  node -e "
const fs = require('fs');
const p = '$CONFIG_FILE';
const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));

// Slack channel config
if (!cfg.channels) cfg.channels = {};
cfg.channels.slack = {
  enabled: true,
  appToken: process.env.SLACK_APP_TOKEN,
  botToken: process.env.SLACK_BOT_TOKEN
};

// Skill config
if (!cfg.skills) cfg.skills = {};
if (!cfg.skills.entries) cfg.skills.entries = {};
cfg.skills.entries['proactive-engineer'] = {
  enabled: true,
  env: {
    GITHUB_TOKEN: process.env.GITHUB_TOKEN,
    GEMINI_API_KEY: process.env.GEMINI_API_KEY
  }
};

fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
"
else
  info "Writing configuration..."
  cat > "$CONFIG_FILE" <<CONF
{
  "channels": {
    "slack": {
      "enabled": true,
      "appToken": "$SLACK_APP_TOKEN",
      "botToken": "$SLACK_BOT_TOKEN"
    }
  },
  "skills": {
    "entries": {
      "proactive-engineer": {
        "enabled": true,
        "env": {
          "GITHUB_TOKEN": "$GITHUB_TOKEN",
          "GEMINI_API_KEY": "$GEMINI_API_KEY"
        }
      }
    }
  }
}
CONF
fi
ok "Configuration saved."

# ── Install daemon ─────────────────────────────────────────────

echo ""
echo -e "${YELLOW}━━━ Starting Background Service ━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Installing background service..."
openclaw gateway install 2>/dev/null || warn "Gateway install returned non-zero (may already be configured)."

if command -v loginctl >/dev/null 2>&1; then
  sudo loginctl enable-linger "$(whoami)" 2>/dev/null || warn "Could not enable-linger — service may not survive logout without this."
fi

systemctl --user enable openclaw-gateway 2>/dev/null || true
systemctl --user restart openclaw-gateway 2>/dev/null || true

sleep 3

if openclaw gateway status 2>/dev/null | grep -qi "running"; then
  ok "Agent is running."
else
  warn "Agent may still be starting up. Check with: openclaw gateway status"
fi

# ── Done ───────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}Proactive Engineer is installed and running.${NC}"
echo ""
echo -e "  It will now continuously monitor your Slack and GitHub,"
echo -e "  reason about what needs doing, and open PRs with its work."
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo ""
echo "    openclaw gateway status       Check if the agent is running"
echo "    openclaw skills list          Verify the skill is loaded"
echo "    journalctl --user -u openclaw-gateway -f   Watch logs"
echo "    openclaw dashboard            Open the web UI"
echo ""
echo -e "  ${DIM}Config:  $CONFIG_FILE${NC}"
echo -e "  ${DIM}Skill:   $SKILL_DIR${NC}"
echo -e "  ${DIM}Source:   $INSTALL_DIR${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
