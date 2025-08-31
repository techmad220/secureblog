#!/bin/bash
# Configure ALL Required Status Checks for Maximum Security
# This makes ALL security checks MANDATORY - no exceptions

set -euo pipefail

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO="${1:-techmad220/secureblog}"
OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GITHUB_TOKEN required with admin:repo scope"
    exit 1
fi

echo "🔒 CONFIGURING REQUIRED STATUS CHECKS"
echo "====================================="
echo "Repository: $REPO"
echo

# All checks that MUST pass before merge
REQUIRED_CHECKS=(
    # Zero JavaScript enforcement
    "Block All JavaScript (Required)"
    "Verify CSP Headers Match Golden Config"
    
    # Content sanitization
    "Sanitize All Content (Required)"
    
    # Supply chain security
    "Verify Signed Commits (Required)"
    "Generate SBOM (Required)"
    "Generate SLSA Provenance (Required)"
    "Verify External Dependencies (Required)"
    "Supply Chain Lock Summary"
    
    # Drift detection
    "Detect Configuration Drift (Required)"
    
    # Standard security checks
    "security-regression-guard"
    "govulncheck"
    "staticcheck"
    "gitleaks"
    "link-check"
    "integrity-verification"
)

echo "Required status checks: ${#REQUIRED_CHECKS[@]}"
printf "  - %s\n" "${REQUIRED_CHECKS[@]}"
echo

# Create branch protection configuration
cat > branch-protection.json << EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": $(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .),
    "checks": []
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 2,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true,
    "bypass_pull_request_allowances": {
      "users": [],
      "teams": [],
      "apps": []
    }
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false,
  "required_signatures": true
}
EOF

echo "Applying branch protection to main branch..."

# Apply branch protection via GitHub API
curl -X PUT \
  "https://api.github.com/repos/$REPO/branches/main/protection" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  -d @branch-protection.json

echo
echo "✅ BRANCH PROTECTION CONFIGURED"
echo "==============================="
echo
echo "Security requirements now ENFORCED:"
echo "  ✅ ${#REQUIRED_CHECKS[@]} required status checks"
echo "  ✅ Admin enforcement (no bypass)"
echo "  ✅ 2 required reviewers"
echo "  ✅ CODEOWNERS review required"
echo "  ✅ Linear history enforced"
echo "  ✅ Signed commits required"
echo "  ✅ Force push protection"
echo "  ✅ Conversation resolution required"
echo
echo "⚠️  IMPORTANT: These checks are now MANDATORY"
echo "No code can reach main without passing ALL checks"
echo
echo "To verify in GitHub:"
echo "1. Go to Settings > Branches > main"
echo "2. Confirm all status checks are listed"
echo "3. Confirm 'Include administrators' is checked"
echo "4. Test by creating a PR with JavaScript (should be blocked)"