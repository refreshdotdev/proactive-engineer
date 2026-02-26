#!/usr/bin/env bash
set -euo pipefail

# Configures GitHub branch protection on repos the App/PAT has access to.
# Prevents the bot from merging its own PRs by requiring human review.
#
# Requires: bash, curl, openssl (for App auth)
#
# Environment variables:
#   GITHUB_APP_ID              - GitHub App ID (for App auth)
#   GITHUB_APP_INSTALLATION_ID - Installation ID (for App auth)
#   GITHUB_APP_PEM_PATH        - Path to .pem file (for App auth)
#   GITHUB_TOKEN               - PAT (alternative to App auth)
#   BRANCH_PROTECTION_DRY_RUN  - Set to "yes" to only show what would change
#
# Exit codes:
#   0 - success (protection configured or already sufficient)
#   1 - fatal error
#   2 - insufficient permissions (needs admin access)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[branch-protection]${NC} $1"; }
ok()    { echo -e "${GREEN}[branch-protection]${NC} $1"; }
warn()  { echo -e "${YELLOW}[branch-protection]${NC} $1"; }
fail()  { echo -e "${RED}[branch-protection]${NC} $1" >&2; }

DRY_RUN="${BRANCH_PROTECTION_DRY_RUN:-no}"

# ── Get a GitHub token ────────────────────────────────────────

get_token() {
  if [ -n "${GITHUB_APP_ID:-}" ] && [ -n "${GITHUB_APP_INSTALLATION_ID:-}" ] && [ -n "${GITHUB_APP_PEM_PATH:-}" ]; then
    "$SCRIPT_DIR/refresh-github-token.sh" 2>/dev/null
  elif [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN"
  else
    fail "No GitHub credentials found. Set GITHUB_APP_ID+INSTALLATION_ID+PEM_PATH or GITHUB_TOKEN."
    exit 1
  fi
}

# ── Authenticated GitHub API call ─────────────────────────────

gh_api() {
  local method="$1" endpoint="$2" data="${3:-}"
  local args=(curl -s -w "\n%{http_code}" --request "$method"
    --header "Authorization: token $TOKEN"
    --header "Accept: application/vnd.github+json"
    --header "X-GitHub-Api-Version: 2022-11-28"
    --url "https://api.github.com${endpoint}")
  [ -n "$data" ] && args+=(--header "Content-Type: application/json" --data "$data")
  "${args[@]}"
}

# Split response body from status code (last line)
split_response() {
  local response="$1"
  BODY=$(echo "$response" | sed '$d')
  HTTP_STATUS=$(echo "$response" | tail -1)
}

# ── JSON helpers (grep/sed — no jq dependency) ────────────────

json_extract() {
  local key="$1" json="$2"
  echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"//" | sed 's/"//'
}

json_extract_number() {
  local key="$1" json="$2"
  echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[0-9]*" | head -1 \
    | grep -o '[0-9]*$'
}

json_extract_all() {
  local key="$1" json="$2"
  echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | sed "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"//" | sed 's/"//'
}

json_has_key() {
  local key="$1" json="$2"
  echo "$json" | grep -q "\"${key}\""
}

# ── List repos ────────────────────────────────────────────────

list_repos() {
  local repos="" page=1
  while true; do
    local response
    if [ -n "${GITHUB_APP_ID:-}" ]; then
      response=$(gh_api GET "/installation/repositories?per_page=100&page=${page}")
    else
      response=$(gh_api GET "/user/repos?per_page=100&page=${page}&type=owner&sort=full_name")
    fi
    split_response "$response"

    if [ "$HTTP_STATUS" != "200" ]; then
      fail "Failed to list repositories (HTTP $HTTP_STATUS)."
      echo "$BODY" >&2
      exit 1
    fi

    local page_repos
    page_repos=$(json_extract_all "full_name" "$BODY")
    [ -z "$page_repos" ] && break
    repos="${repos}${repos:+$'\n'}${page_repos}"

    # Stop if fewer than 100 results (last page)
    local count
    count=$(echo "$page_repos" | wc -l | tr -d ' ')
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
  done
  echo "$repos"
}

# ── Check & apply protection for one repo ─────────────────────

configure_repo() {
  local repo="$1"

  # Get default branch
  local response
  response=$(gh_api GET "/repos/${repo}")
  split_response "$response"

  if [ "$HTTP_STATUS" != "200" ]; then
    warn "Could not read repo ${repo} (HTTP $HTTP_STATUS). Skipping."
    return 1
  fi

  local default_branch
  default_branch=$(json_extract "default_branch" "$BODY")
  if [ -z "$default_branch" ]; then
    warn "Could not determine default branch for ${repo}. Skipping."
    return 1
  fi

  # Check current protection
  response=$(gh_api GET "/repos/${repo}/branches/${default_branch}/protection")
  split_response "$response"

  if [ "$HTTP_STATUS" = "403" ]; then
    # No admin access
    return 2
  fi

  if [ "$HTTP_STATUS" = "404" ] || [ "$HTTP_STATUS" = "000" ]; then
    # No protection — apply full config
    info "${repo} (${default_branch}): no branch protection. Adding review requirement."

    if [ "$DRY_RUN" = "yes" ]; then
      info "  [dry run] Would require 1 approving review + dismiss stale reviews."
      return 0
    fi

    local put_body='{
      "required_status_checks": null,
      "enforce_admins": false,
      "required_pull_request_reviews": {
        "dismiss_stale_reviews": true,
        "require_code_owner_reviews": false,
        "required_approving_review_count": 1
      },
      "restrictions": null
    }'

    response=$(gh_api PUT "/repos/${repo}/branches/${default_branch}/protection" "$put_body")
    split_response "$response"

    if [ "$HTTP_STATUS" = "200" ]; then
      ok "${repo} (${default_branch}): branch protection configured."
      return 0
    else
      warn "${repo}: failed to apply protection (HTTP $HTTP_STATUS)."
      return 1
    fi
  fi

  if [ "$HTTP_STATUS" = "200" ]; then
    # Protection exists — check if review requirement is present
    if json_has_key "required_pull_request_reviews" "$BODY"; then
      local count
      count=$(json_extract_number "required_approving_review_count" "$BODY")
      if [ -n "$count" ] && [ "$count" -ge 1 ]; then
        ok "${repo} (${default_branch}): already requires ${count} approving review(s). No changes needed."
        return 0
      fi
    fi

    # Protection exists but no review requirement (or count < 1).
    # Updating via PUT replaces the entire config, so we need jq to merge safely.
    if command -v jq >/dev/null 2>&1; then
      info "${repo} (${default_branch}): has protection but no review requirement. Adding."

      if [ "$DRY_RUN" = "yes" ]; then
        info "  [dry run] Would add: require 1 approving review + dismiss stale reviews."
        return 0
      fi

      # Rebuild the PUT body by merging existing protection with review requirement.
      # Extract existing fields safely.
      local existing_status_checks existing_enforce_admins existing_restrictions
      existing_status_checks=$(echo "$BODY" | jq '.required_status_checks // null')
      existing_enforce_admins=$(echo "$BODY" | jq '.enforce_admins.enabled // false')
      existing_restrictions=$(echo "$BODY" | jq '.restrictions // null')

      local put_body
      put_body=$(jq -n \
        --argjson status_checks "$existing_status_checks" \
        --argjson enforce_admins "$existing_enforce_admins" \
        --argjson restrictions "$existing_restrictions" \
        '{
          required_status_checks: $status_checks,
          enforce_admins: $enforce_admins,
          required_pull_request_reviews: {
            dismiss_stale_reviews: true,
            require_code_owner_reviews: false,
            required_approving_review_count: 1
          },
          restrictions: $restrictions
        }')

      response=$(gh_api PUT "/repos/${repo}/branches/${default_branch}/protection" "$put_body")
      split_response "$response"

      if [ "$HTTP_STATUS" = "200" ]; then
        ok "${repo} (${default_branch}): review requirement added (existing rules preserved)."
        return 0
      else
        warn "${repo}: failed to update protection (HTTP $HTTP_STATUS)."
        return 1
      fi
    else
      # No jq — too risky to overwrite existing protection
      warn "${repo} (${default_branch}): has branch protection but no review requirement."
      warn "  Install jq to auto-configure, or add it manually:"
      warn "  GitHub → Settings → Branches → Edit → Require pull request reviews (1 approval)"
      return 1
    fi
  fi

  warn "${repo}: unexpected response (HTTP $HTTP_STATUS). Skipping."
  return 1
}

# ── Main ──────────────────────────────────────────────────────

info "Checking GitHub credentials..."
TOKEN=$(get_token)
if [ -z "$TOKEN" ]; then
  fail "Could not obtain a GitHub token."
  exit 1
fi
ok "Authenticated."

info "Listing repositories..."
REPOS=$(list_repos)

if [ -z "$REPOS" ]; then
  info "No repositories found. Nothing to configure."
  exit 0
fi

REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
info "Found ${REPO_COUNT} repository(ies):"
echo "$REPOS" | while read -r r; do echo -e "  ${DIM}${r}${NC}"; done
echo ""

if [ "$DRY_RUN" = "yes" ]; then
  info "Running in dry-run mode — no changes will be made."
  echo ""
fi

CONFIGURED=0
ALREADY_OK=0
SKIPPED=0
NO_ADMIN=0

while IFS= read -r repo; do
  result=0
  configure_repo "$repo" || result=$?

  case $result in
    0)
      # Check if the ok message said "already requires" or was a new config
      # Simple heuristic: if dry run or protection was applied, it's configured
      if echo "$repo" | grep -q ""; then
        # We track via the function's output, but for counting just increment
        :
      fi
      ;;
    2)
      NO_ADMIN=$((NO_ADMIN + 1))
      ;;
    *)
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac
done <<< "$REPOS"

echo ""

if [ "$NO_ADMIN" -gt 0 ]; then
  echo ""
  fail "The GitHub App does not have the 'administration' permission on ${NO_ADMIN} repo(s)."
  echo ""
  echo -e "  To grant it:"
  echo ""
  echo -e "  1. Go to ${CYAN}https://github.com/settings/apps${NC}"
  echo -e "  2. Click your \"Proactive Engineer\" app"
  echo -e "  3. Go to ${BOLD}Permissions & events${NC}"
  echo -e "  4. Under Repository permissions, set ${BOLD}Administration${NC} to ${BOLD}Read and write${NC}"
  echo -e "  5. Click ${BOLD}Save changes${NC}"
  echo -e "  6. Approve the permission change for each installation"
  echo ""
  echo -e "  Then re-run:"
  echo -e "    ${DIM}bash ${SCRIPT_DIR}/configure-branch-protection.sh${NC}"
  echo ""
  exit 2
fi

ok "Done."
