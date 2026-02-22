#!/usr/bin/env bash
set -euo pipefail

REPO="refreshdotdev/proactive-engineer"
BRANCH="main"
INSTALL_DIR="$HOME/.proactive-engineer"
SKILL_DIR="$HOME/.openclaw/skills/proactive-engineer"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[proactive-engineer]${NC} $1"; }
ok()    { echo -e "${GREEN}[proactive-engineer]${NC} $1"; }
warn()  { echo -e "${YELLOW}[proactive-engineer]${NC} $1"; }
err()   { echo -e "${RED}[proactive-engineer]${NC} $1" >&2; exit 1; }

echo ""
echo -e "${CYAN}"
echo "  proactive.engineer"
echo "  an AI that ships while you sleep"
echo -e "${NC}"

# ── Validate required env vars ─────────────────────────────────

MISSING=""
[ -z "${SLACK_API_TOKEN:-}" ]  && MISSING="$MISSING SLACK_API_TOKEN"
[ -z "${GITHUB_TOKEN:-}" ]     && MISSING="$MISSING GITHUB_TOKEN"
[ -z "${GEMINI_API_KEY:-}" ]   && MISSING="$MISSING GEMINI_API_KEY"

if [ -n "$MISSING" ]; then
  err "Missing required environment variables:$MISSING

Usage:
  SLACK_API_TOKEN=xoxb-... \\
  GITHUB_TOKEN=ghp_... \\
  GEMINI_API_KEY=... \\
    curl -fsSL https://proactive.engineer/install.sh | bash"
fi

# ── Install OpenClaw (handles Node.js, git, npm) ──────────────

if ! command -v openclaw >/dev/null 2>&1; then
  info "Installing OpenClaw..."
  curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v openclaw >/dev/null 2>&1; then
    err "OpenClaw installation failed. See https://docs.openclaw.ai/start/getting-started"
  fi
  ok "OpenClaw installed."
else
  ok "OpenClaw found."
fi

# ── Clone / update proactive-engineer ──────────────────────────

if [ -d "$INSTALL_DIR/.git" ]; then
  info "Updating proactive-engineer..."
  git -C "$INSTALL_DIR" pull --quiet origin "$BRANCH" 2>/dev/null || true
  ok "Updated."
else
  info "Cloning proactive-engineer..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$INSTALL_DIR"
  ok "Cloned to $INSTALL_DIR"
fi

# ── Symlink skill ──────────────────────────────────────────────

info "Installing skill..."
mkdir -p "$(dirname "$SKILL_DIR")"
[ -L "$SKILL_DIR" ] && rm "$SKILL_DIR"
[ -d "$SKILL_DIR" ] && rm -rf "$SKILL_DIR"
ln -sf "$INSTALL_DIR/skills/proactive-engineer" "$SKILL_DIR"
ok "Skill linked."

# ── Write config ───────────────────────────────────────────────

CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
  info "Merging into existing openclaw.json..."
  if command -v node >/dev/null 2>&1; then
    node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
if (!cfg.skills) cfg.skills = {};
if (!cfg.skills.entries) cfg.skills.entries = {};
cfg.skills.entries['proactive-engineer'] = {
  enabled: true,
  env: {
    SLACK_API_TOKEN: '$SLACK_API_TOKEN',
    GITHUB_TOKEN: '$GITHUB_TOKEN',
    GEMINI_API_KEY: '$GEMINI_API_KEY'
  }
};
fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2));
"
  else
    warn "Node not found — writing fresh config (existing config backed up)."
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"
  fi
else
  info "Writing openclaw.json..."
  cat > "$CONFIG_FILE" <<CONF
{
  "skills": {
    "entries": {
      "proactive-engineer": {
        "enabled": true,
        "env": {
          "SLACK_API_TOKEN": "$SLACK_API_TOKEN",
          "GITHUB_TOKEN": "$GITHUB_TOKEN",
          "GEMINI_API_KEY": "$GEMINI_API_KEY"
        }
      }
    }
  }
}
CONF
fi
ok "Config written."

# ── Install daemon (systemd on Linux) ─────────────────────────

info "Installing gateway service..."
openclaw gateway install 2>/dev/null || warn "Gateway install returned non-zero (may already be installed)."

if command -v loginctl >/dev/null 2>&1; then
  sudo loginctl enable-linger "$(whoami)" 2>/dev/null || warn "Could not enable-linger (may need sudo)."
fi

systemctl --user enable openclaw-gateway 2>/dev/null || true
systemctl --user restart openclaw-gateway 2>/dev/null || true
ok "Gateway service started."

# ── Verify ─────────────────────────────────────────────────────

sleep 3
info "Verifying..."

if openclaw gateway status 2>/dev/null | grep -qi "running"; then
  ok "Gateway is running."
else
  warn "Gateway may still be starting — check with: openclaw gateway status"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Proactive Engineer is installed and running.${NC}"
echo ""
echo "  Verify:  openclaw gateway status"
echo "  Skills:  openclaw skills list"
echo "  Logs:    journalctl --user -u openclaw-gateway -f"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
