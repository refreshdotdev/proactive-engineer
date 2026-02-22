#!/usr/bin/env bash
set -euo pipefail

# Generates a fresh GitHub installation token from GitHub App credentials.
# Requires: bash, openssl, curl
#
# Environment variables:
#   GITHUB_APP_ID              - GitHub App ID
#   GITHUB_APP_INSTALLATION_ID - Installation ID
#   GITHUB_APP_PEM_PATH        - Path to the .pem private key file
#
# Outputs the token (ghs_...) to stdout.
# Also exports git author/committer identity for the bot.

: "${GITHUB_APP_ID:?Set GITHUB_APP_ID}"
: "${GITHUB_APP_INSTALLATION_ID:?Set GITHUB_APP_INSTALLATION_ID}"
: "${GITHUB_APP_PEM_PATH:?Set GITHUB_APP_PEM_PATH}"

[ -f "$GITHUB_APP_PEM_PATH" ] || { echo "Private key not found: $GITHUB_APP_PEM_PATH" >&2; exit 1; }

base64url() {
  openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'
}

now=$(date +%s)
iat=$((now - 60))
exp=$((now + 600))

header=$(echo -n '{"typ":"JWT","alg":"RS256"}' | base64url)
payload=$(echo -n "{\"iat\":${iat},\"exp\":${exp},\"iss\":\"${GITHUB_APP_ID}\"}" | base64url)

signature=$(
  openssl dgst -sha256 -sign "$GITHUB_APP_PEM_PATH" \
    <(echo -n "${header}.${payload}") | base64url
)

jwt="${header}.${payload}.${signature}"

response=$(curl -sf --request POST \
  --header "Authorization: Bearer $jwt" \
  --header "Accept: application/vnd.github+json" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --url "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens")

token=$(echo "$response" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$token" ]; then
  echo "Failed to get installation token. Response:" >&2
  echo "$response" >&2
  exit 1
fi

AGENT_LABEL="Proactive Engineer"
if [ -n "${AGENT_NAME:-}" ] && [ "$AGENT_NAME" != "default" ]; then
  AGENT_LABEL="Proactive Engineer ($AGENT_NAME)"
fi

export GIT_AUTHOR_NAME="$AGENT_LABEL"
export GIT_AUTHOR_EMAIL="proactive-engineer[bot]@users.noreply.github.com"
export GIT_COMMITTER_NAME="$AGENT_LABEL"
export GIT_COMMITTER_EMAIL="proactive-engineer[bot]@users.noreply.github.com"

echo "$token"
