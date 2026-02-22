#!/bin/bash
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y curl git

curl -fsSL https://tailscale.com/install.sh | sh

curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
openclaw --version

git clone --depth 1 https://github.com/refreshdotdev/proactive-engineer.git "$HOME/.proactive-engineer"
mkdir -p "$HOME/.openclaw/skills"
ln -sf "$HOME/.proactive-engineer/skills/proactive-engineer" "$HOME/.openclaw/skills/proactive-engineer"

echo "=== AMI provisioning complete ==="
