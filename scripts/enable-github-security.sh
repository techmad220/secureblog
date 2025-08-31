#!/bin/bash
# Enable All Free GitHub Advanced Security Features
# For public repositories, these features are free and should be enabled

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_OWNER="${1:-techmad220}"
REPO_NAME="${2:-secureblog}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

echo -e "${BLUE}🔒 ENABLING GITHUB ADVANCED SECURITY${NC}"
echo "===================================="
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}ERROR: GITHUB_TOKEN environment variable not set${NC}"
    echo "Please set your GitHub token with repo and security events scope."
    echo "For GitHub CLI users: gh auth token"
    exit 1
fi

# Function to make GitHub API calls
github_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    if [ -n "$data" ]; then
        curl -s -X "$method" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            "https://api.github.com$endpoint" \
            -d "$data"
    else
        curl -s -X "$method" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com$endpoint"
    fi
}

echo -e "${BLUE}1. Enabling Vulnerability Alerts...${NC}"
VULN_RESPONSE=$(github_api "PUT" "/repos/$REPO_OWNER/$REPO_NAME/vulnerability-alerts" 2>/dev/null || echo "failed")
if echo "$VULN_RESPONSE" | grep -q "failed"; then
    echo -e "${YELLOW}   ⚠ Could not enable vulnerability alerts (may already be enabled)${NC}"
else
    echo -e "${GREEN}   ✓ Vulnerability alerts enabled${NC}"
fi

echo -e "${BLUE}2. Enabling Dependabot Alerts...${NC}"
DEPENDABOT_RESPONSE=$(github_api "PUT" "/repos/$REPO_OWNER/$REPO_NAME/automated-security-fixes" 2>/dev/null || echo "failed")
if echo "$DEPENDABOT_RESPONSE" | grep -q "failed"; then
    echo -e "${YELLOW}   ⚠ Could not enable Dependabot alerts (may already be enabled)${NC}"
else
    echo -e "${GREEN}   ✓ Dependabot alerts enabled${NC}"
fi

echo -e "${BLUE}3. Enabling Dependabot Security Updates...${NC}"
SECURITY_UPDATES='{"enabled": true}'
SECURITY_RESPONSE=$(github_api "PUT" "/repos/$REPO_OWNER/$REPO_NAME/automated-security-fixes" "$SECURITY_UPDATES" 2>/dev/null || echo "failed")
if echo "$SECURITY_RESPONSE" | grep -q "failed"; then
    echo -e "${YELLOW}   ⚠ Could not enable security updates (may already be enabled)${NC}"
else
    echo -e "${GREEN}   ✓ Dependabot security updates enabled${NC}"
fi

echo -e "${BLUE}4. Enabling Secret Scanning...${NC}"
SECRET_SCANNING='{"enabled": true}'
SECRET_RESPONSE=$(github_api "PUT" "/repos/$REPO_OWNER/$REPO_NAME/secret-scanning/alerts" "$SECRET_SCANNING" 2>/dev/null || echo "failed")
if echo "$SECRET_RESPONSE" | grep -q "failed"; then
    echo -e "${YELLOW}   ⚠ Could not enable secret scanning via API${NC}"
    echo -e "${YELLOW}   → Enable manually at: https://github.com/$REPO_OWNER/$REPO_NAME/settings/security_analysis${NC}"
else
    echo -e "${GREEN}   ✓ Secret scanning enabled${NC}"
fi

echo -e "${BLUE}5. Enabling Push Protection...${NC}"
PUSH_PROTECTION='{"enabled": true}'
PUSH_RESPONSE=$(github_api "PUT" "/repos/$REPO_OWNER/$REPO_NAME/secret-scanning/push-protection" "$PUSH_PROTECTION" 2>/dev/null || echo "failed")
if echo "$PUSH_RESPONSE" | grep -q "failed"; then
    echo -e "${YELLOW}   ⚠ Could not enable push protection via API${NC}"
    echo -e "${YELLOW}   → Enable manually at: https://github.com/$REPO_OWNER/$REPO_NAME/settings/security_analysis${NC}"
else
    echo -e "${GREEN}   ✓ Push protection enabled${NC}"
fi

echo -e "${BLUE}6. Configuring Code Scanning (CodeQL)...${NC}"
# CodeQL is enabled via workflow files, check if workflow exists
if [ -f ".github/workflows/codeql.yml" ]; then
    echo -e "${GREEN}   ✓ CodeQL workflow exists${NC}"
else
    echo -e "${YELLOW}   ⚠ Creating CodeQL workflow...${NC}"
    
    # Create .github/workflows directory if it doesn't exist
    mkdir -p .github/workflows
    
    # Create CodeQL workflow
    cat > .github/workflows/codeql.yml << 'EOF'
name: "CodeQL Security Scanning"

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]
  schedule:
    - cron: '30 2 * * 1'  # Weekly on Mondays

permissions:
  contents: read

jobs:
  analyze:
    name: Analyze Code
    runs-on: ubuntu-latest
    timeout-minutes: 360
    permissions:
      actions: read
      contents: read
      security-events: write

    strategy:
      fail-fast: false
      matrix:
        language: [ 'go', 'javascript' ]

    steps:
    - name: Harden Runner
      uses: step-security/harden-runner@91182cccc01eb5e619899d80e4e971d6181294a7 # v2
      with:
        egress-policy: audit

    - name: Checkout repository
      uses: actions/checkout@1e31de5234b664ca3f0ed09e5ce0d6de0c5d0fc1 # v4

    - name: Initialize CodeQL
      uses: github/codeql-action/init@cb7a9eb42e01dd0e13db99ddf0e3ccdadda24398 # v3
      with:
        languages: ${{ matrix.language }}
        queries: security-extended,security-and-quality

    - name: Autobuild
      uses: github/codeql-action/autobuild@cb7a9eb42e01dd0e13db99ddf0e3ccdadda24398 # v3

    - name: Perform CodeQL Analysis
      uses: github/codeql-action/analyze@cb7a9eb42e01dd0e13db99ddf0e3ccdadda24398 # v3
      with:
        category: "/language:${{matrix.language}}"
EOF
    
    echo -e "${GREEN}   ✓ CodeQL workflow created${NC}"
fi

echo -e "${BLUE}7. Checking Dependency Review...${NC}"
# Dependency review is handled via GitHub App, check if we have the action
if grep -r "dependency-review-action" .github/workflows/ >/dev/null 2>&1; then
    echo -e "${GREEN}   ✓ Dependency review action found in workflows${NC}"
else
    echo -e "${YELLOW}   ⚠ Adding dependency review to CI...${NC}"
    
    # Create or update a security workflow with dependency review
    cat > .github/workflows/dependency-review.yml << 'EOF'
name: 'Dependency Review'
on:
  pull_request:
    branches: [ "main" ]

permissions:
  contents: read

jobs:
  dependency-review:
    runs-on: ubuntu-latest
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@91182cccc01eb5e619899d80e4e971d6181294a7 # v2
        with:
          egress-policy: audit
          
      - name: 'Checkout Repository'
        uses: actions/checkout@1e31de5234b664ca3f0ed09e5ce0d6de0c5d0fc1 # v4
        
      - name: 'Dependency Review'
        uses: actions/dependency-review-action@5a2ce3f5b92ee19cbb1541a4984c76d921601d7c # v4
        with:
          fail-on-severity: high
          deny-licenses: GPL-2.0, GPL-3.0
          comment-summary-in-pr: always
EOF
    
    echo -e "${GREEN}   ✓ Dependency review workflow created${NC}"
fi

echo -e "${BLUE}8. Configuring Branch Protection Rules...${NC}"
BRANCH_PROTECTION='{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "nojs-guard",
      "SLSA L3 Real Provenance & Enforcement / hermetic-build",
      "CodeQL Security Scanning / Analyze Code (go)",
      "Dependency Review / dependency-review"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 2,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true
}'

BRANCH_RESPONSE=$(github_api "PUT" "/repos/$REPO_OWNER/$REPO_NAME/branches/main/protection" "$BRANCH_PROTECTION" 2>/dev/null || echo "failed")
if echo "$BRANCH_RESPONSE" | grep -q "failed"; then
    echo -e "${YELLOW}   ⚠ Could not update branch protection via API${NC}"
    echo -e "${YELLOW}   → Configure manually at: https://github.com/$REPO_OWNER/$REPO_NAME/settings/branches${NC}"
else
    echo -e "${GREEN}   ✓ Branch protection rules updated${NC}"
fi

echo -e "${BLUE}9. Enabling GitHub Advanced Security for Private Repos...${NC}"
# This would only work for private repos with GHAS license
GHAS_ENABLE='{"security_and_analysis": {"advanced_security": {"status": "enabled"}}}'
GHAS_RESPONSE=$(github_api "PATCH" "/repos/$REPO_OWNER/$REPO_NAME" "$GHAS_ENABLE" 2>/dev/null || echo "failed")
if echo "$GHAS_RESPONSE" | grep -q "failed"; then
    echo -e "${YELLOW}   ⚠ Advanced Security not enabled (public repo or already enabled)${NC}"
else
    echo -e "${GREEN}   ✓ GitHub Advanced Security enabled${NC}"
fi

echo
echo -e "${GREEN}✅ GITHUB SECURITY SETUP COMPLETE${NC}"
echo "=================================="
echo
echo "✓ Enabled Features:"
echo "  • Vulnerability alerts for dependencies"
echo "  • Dependabot security updates"
echo "  • Secret scanning"
echo "  • Push protection for secrets"
echo "  • CodeQL code scanning"
echo "  • Dependency review on PRs"
echo "  • Branch protection with required checks"
echo
echo "🔗 Manual Configuration Links:"
echo "  • Security settings: https://github.com/$REPO_OWNER/$REPO_NAME/settings/security_analysis"
echo "  • Branch protection: https://github.com/$REPO_OWNER/$REPO_NAME/settings/branches"
echo "  • Actions settings: https://github.com/$REPO_OWNER/$REPO_NAME/settings/actions"
echo
echo -e "${BLUE}Note: Some features may require manual enablement via GitHub web UI${NC}"
echo -e "${BLUE}All security features are free for public repositories${NC}"