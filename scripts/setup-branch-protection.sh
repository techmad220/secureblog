#!/usr/bin/env bash
# setup-branch-protection.sh - Configure GitHub branch protection rules
# Requires: gh CLI and appropriate permissions
# Usage: bash scripts/setup-branch-protection.sh

set -euo pipefail

REPO="techmad220/secureblog"
BRANCH="main"

echo "🔒 Setting up branch protection for $REPO:$BRANCH"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed"
    echo "Install from: https://cli.github.com/"
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi

echo "→ Configuring branch protection rules..."

# Enable branch protection with comprehensive settings
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$REPO/branches/$BRANCH/protection" \
  -f "required_status_checks[strict]=true" \
  -f "required_status_checks[contexts][]=CI (secure)" \
  -f "required_status_checks[contexts][]=CodeQL / Analyze (go)" \
  -f "required_status_checks[contexts][]=nojs-guard / guard" \
  -f "required_status_checks[contexts][]=link-audit / link-audit" \
  -f "enforce_admins=true" \
  -f "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  -f "required_pull_request_reviews[require_code_owner_reviews]=true" \
  -f "required_pull_request_reviews[required_approving_review_count]=1" \
  -f "required_pull_request_reviews[require_last_push_approval]=true" \
  -f "restrictions=null" \
  -f "allow_force_pushes=false" \
  -f "allow_deletions=false" \
  -f "block_creations=false" \
  -f "required_conversation_resolution=true" \
  -f "lock_branch=false" \
  -f "allow_fork_syncing=false"

echo "✅ Branch protection enabled with:"
echo "   • Required status checks (CI, CodeQL, no-JS, links)"
echo "   • Dismiss stale reviews"
echo "   • Require code owner reviews"
echo "   • Require approval from last pusher"
echo "   • No force pushes"
echo "   • No branch deletion"
echo "   • Require conversation resolution"

# Optional: Add CODEOWNERS file
if [ ! -f .github/CODEOWNERS ]; then
    echo "→ Creating CODEOWNERS file..."
    mkdir -p .github
    cat > .github/CODEOWNERS << 'EOF'
# Code owners for SecureBlog
# These owners will be requested for review when someone opens a pull request

# Global owners
* @techmad220

# Security-critical files
/.github/workflows/ @techmad220
/.scripts/ @techmad220
/scripts/security*.sh @techmad220
/security-headers.conf @techmad220
/nginx*.conf @techmad220
EOF
    echo "✅ CODEOWNERS file created"
fi

echo ""
echo "🎉 Branch protection successfully configured!"
echo ""
echo "View settings at: https://github.com/$REPO/settings/branches"