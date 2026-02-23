#!/usr/bin/env bash
set -euo pipefail

# Uploads the Proactive Engineer logo to the GitHub App.
# Requires: GITHUB_APP_ID, GITHUB_APP_PEM_PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGO_PATH="$SCRIPT_DIR/../proactive-engineer-logo.png"

: "${GITHUB_APP_ID:?Set GITHUB_APP_ID}"
: "${GITHUB_APP_PEM_PATH:?Set GITHUB_APP_PEM_PATH}"

[ -f "$LOGO_PATH" ] || { echo "Logo not found: $LOGO_PATH" >&2; exit 1; }
[ -f "$GITHUB_APP_PEM_PATH" ] || { echo "PEM not found: $GITHUB_APP_PEM_PATH" >&2; exit 1; }

base64url() {
  openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'
}

now=$(date +%s)
iat=$((now - 60))
exp=$((now + 600))

header=$(echo -n '{"typ":"JWT","alg":"RS256"}' | base64url)
payload=$(echo -n "{\"iat\":${iat},\"exp\":${exp},\"iss\":\"${GITHUB_APP_ID}\"}" | base64url)
signature=$(openssl dgst -sha256 -sign "$GITHUB_APP_PEM_PATH" <(echo -n "${header}.${payload}") | base64url)
jwt="${header}.${payload}.${signature}"

echo "Uploading logo to GitHub App..."

LOGO_BASE64=$(base64 < "$LOGO_PATH" | tr -d '\n')

RESPONSE=$(curl -sf --request PATCH \
  --header "Authorization: Bearer $jwt" \
  --header "Accept: application/vnd.github+json" \
  --header "Content-Type: application/json" \
  --url "https://api.github.com/app" \
  --data "{\"name\":\"Proactive AI Engineer\",\"description\":\"An AI agent that ships while you sleep\"}" \
  2>&1) || true

# The logo upload uses multipart form data
curl -sf --request PATCH \
  --header "Authorization: Bearer $jwt" \
  --header "Accept: application/vnd.github+json" \
  --url "https://api.github.com/app" \
  --form "logo=@$LOGO_PATH" \
  > /dev/null 2>&1 && echo "Logo uploaded." || echo "Could not upload logo (may need manual upload in GitHub App settings)."
