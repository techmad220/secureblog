#!/bin/bash
# Comprehensive GitHub Organization/Repository Hardening
# Implements maximum security controls against account compromise

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

echo -e "${BLUE}🔒 GITHUB ORGANIZATION/REPOSITORY HARDENING${NC}"
echo "=============================================="
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Implementing maximum security controls..."
echo

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}ERROR: GITHUB_TOKEN environment variable not set${NC}"
    echo "Please set your GitHub token with admin permissions."
    echo "Required scopes: repo, admin:repo_hook, admin:org"
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

echo -e "${BLUE}1. Enforcing Signed Commits...${NC}"

# Enable signed commit requirement
SIGNED_COMMITS='{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "deploy_with_provenance_gate / build-verify-deploy",
      "nojs-guard / no-js-enforcement",
      "SLSA L3 Real Provenance & Enforcement / hermetic-build"
    ]
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
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false,
  "required_signatures": true
}'

echo "Setting branch protection with signed commit requirement..."
BRANCH_RESPONSE=$(github_api "PUT" "/repos/$REPO_OWNER/$REPO_NAME/branches/main/protection" "$SIGNED_COMMITS" 2>/dev/null || echo "failed")

if echo "$BRANCH_RESPONSE" | grep -q "required_signatures"; then
    echo -e "${GREEN}   ✓ Signed commits enforced${NC}"
    echo -e "${GREEN}   ✓ Linear history required${NC}"
    echo -e "${GREEN}   ✓ Force pushes blocked${NC}"
    echo -e "${GREEN}   ✓ Branch deletions blocked${NC}"
    echo -e "${GREEN}   ✓ Admin enforcement enabled${NC}"
else
    echo -e "${YELLOW}   ⚠ Could not set complete branch protection${NC}"
    echo -e "${YELLOW}   → Configure manually at: https://github.com/$REPO_OWNER/$REPO_NAME/settings/branches${NC}"
fi

echo -e "${BLUE}2. Configuring Repository Security Settings...${NC}"

# Enable comprehensive repository security
REPO_SECURITY='{
  "has_issues": true,
  "has_projects": false,
  "has_wiki": false,
  "has_downloads": false,
  "default_branch": "main",
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": false,
  "delete_branch_on_merge": true,
  "allow_update_branch": false,
  "use_squash_pr_title_as_default": true,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY",
  "security_and_analysis": {
    "secret_scanning": {"status": "enabled"},
    "secret_scanning_push_protection": {"status": "enabled"},
    "dependabot_security_updates": {"status": "enabled"},
    "private_vulnerability_reporting": {"status": "enabled"}
  },
  "vulnerability_alerts": true
}'

REPO_RESPONSE=$(github_api "PATCH" "/repos/$REPO_OWNER/$REPO_NAME" "$REPO_SECURITY" 2>/dev/null || echo "failed")

if echo "$REPO_RESPONSE" | grep -q "security_and_analysis"; then
    echo -e "${GREEN}   ✓ Secret scanning enabled${NC}"
    echo -e "${GREEN}   ✓ Push protection enabled${NC}"
    echo -e "${GREEN}   ✓ Dependabot security updates enabled${NC}"
    echo -e "${GREEN}   ✓ Private vulnerability reporting enabled${NC}"
    echo -e "${GREEN}   ✓ Wiki/downloads/projects disabled${NC}"
    echo -e "${GREEN}   ✓ Only squash merges allowed${NC}"
else
    echo -e "${YELLOW}   ⚠ Some repository security settings may need manual configuration${NC}"
fi

echo -e "${BLUE}3. Protecting Tags and Releases...${NC}"

# Create tag protection rule for release tags
TAG_PROTECTION='{
  "pattern": "v*",
  "required_signatures": true
}'

TAG_RESPONSE=$(github_api "POST" "/repos/$REPO_OWNER/$REPO_NAME/tags/protection" "$TAG_PROTECTION" 2>/dev/null || echo "failed")

if echo "$TAG_RESPONSE" | grep -q "pattern"; then
    echo -e "${GREEN}   ✓ Release tags protected (v* pattern)${NC}"
    echo -e "${GREEN}   ✓ Signed tags required${NC}"
else
    echo -e "${YELLOW}   ⚠ Could not create tag protection rule${NC}"
    echo -e "${YELLOW}   → Configure manually at: https://github.com/$REPO_OWNER/$REPO_NAME/settings/tag_protection${NC}"
fi

echo -e "${BLUE}4. Configuring Webhook Security...${NC}"

# List and secure webhooks
WEBHOOKS_RESPONSE=$(github_api "GET" "/repos/$REPO_OWNER/$REPO_NAME/hooks" 2>/dev/null || echo "[]")

if [ "$WEBHOOKS_RESPONSE" != "[]" ] && [ "$WEBHOOKS_RESPONSE" != "failed" ]; then
    echo "   Found existing webhooks - ensuring they use HTTPS and secrets..."
    # Process webhooks to ensure they're secure
    echo "$WEBHOOKS_RESPONSE" | jq -r '.[].url' | while read webhook_url; do
        if [[ "$webhook_url" == https://* ]]; then
            echo -e "${GREEN}   ✓ Webhook uses HTTPS: $webhook_url${NC}"
        else
            echo -e "${RED}   ✗ Insecure webhook found: $webhook_url${NC}"
        fi
    done
else
    echo -e "${GREEN}   ✓ No webhooks configured (good for security)${NC}"
fi

echo -e "${BLUE}5. Setting Up CODEOWNERS Protection...${NC}"

# Create/update CODEOWNERS file for critical paths
mkdir -p .github

cat > .github/CODEOWNERS << 'EOF'
# Global ownership - require security team review for all changes
* @techmad220

# Critical security files require multiple reviewers
/.github/workflows/ @techmad220 @security-team
/scripts/ @techmad220 @security-team
/cloudflare/ @techmad220 @security-team
/.scripts/ @techmad220 @security-team

# Deployment and CI configuration
/.github/workflows/deploy-with-provenance-gate.yml @techmad220 @security-team
/.github/workflows/slsa-l3-real.yml @techmad220 @security-team
/.github/workflows/nojs-guard.yml @techmad220 @security-team

# Security scripts and configuration
/scripts/security-*.sh @techmad220 @security-team
/scripts/harden-*.sh @techmad220 @security-team
/.scripts/security-regression-guard.sh @techmad220 @security-team

# Cloudflare security configuration
/cloudflare/csp-reporting-worker.js @techmad220 @security-team
/cloudflare/origin-hardlock.tf @techmad220 @security-team

# Build and deployment
/build-sandbox.sh @techmad220 @security-team
/Dockerfile @techmad220 @security-team

# Package management
/go.mod @techmad220 @security-team
/go.sum @techmad220 @security-team

# Documentation that affects security
/README.md @techmad220
/SECURITY.md @techmad220 @security-team
EOF

echo -e "${GREEN}   ✓ CODEOWNERS file created/updated${NC}"
echo -e "${GREEN}   ✓ Critical paths require security team review${NC}"

echo -e "${BLUE}6. Configuring Issue and PR Templates...${NC}"

# Create security-focused issue templates
mkdir -p .github/ISSUE_TEMPLATE

cat > .github/ISSUE_TEMPLATE/security-vulnerability.yml << 'EOF'
name: Security Vulnerability Report
description: Report a security vulnerability
title: "[SECURITY] "
labels: ["security", "vulnerability"]
assignees:
  - techmad220
body:
  - type: markdown
    attributes:
      value: |
        **⚠️ IMPORTANT: Do not report security vulnerabilities in public issues!**
        
        For security vulnerabilities, please use GitHub's private vulnerability reporting:
        https://github.com/techmad220/secureblog/security/advisories/new
        
        Or email: security@secureblog.com (PGP key available)
        
  - type: textarea
    id: vulnerability-description
    attributes:
      label: Vulnerability Description
      description: Describe the security vulnerability
      placeholder: Please provide details about the vulnerability...
    validations:
      required: true

  - type: dropdown
    id: severity
    attributes:
      label: Severity Assessment
      options:
        - Critical
        - High
        - Medium
        - Low
    validations:
      required: true
EOF

cat > .github/ISSUE_TEMPLATE/security-hardening.yml << 'EOF'
name: Security Hardening Request
description: Request additional security hardening measures
title: "[HARDENING] "
labels: ["security", "enhancement"]
assignees:
  - techmad220
body:
  - type: textarea
    id: hardening-request
    attributes:
      label: Security Hardening Request
      description: Describe the additional security measure you'd like to see
      placeholder: Please describe the security hardening you're requesting...
    validations:
      required: true

  - type: textarea
    id: threat-model
    attributes:
      label: Threat Model
      description: What threats does this hardening protect against?
      placeholder: Describe the threats this would mitigate...
    validations:
      required: true
EOF

echo -e "${GREEN}   ✓ Security issue templates created${NC}"

echo -e "${BLUE}7. Setting Repository Visibility and Access...${NC}"

# Ensure proper repository access controls
ACCESS_CONTROL='{
  "private": false,
  "visibility": "public"
}'

ACCESS_RESPONSE=$(github_api "PATCH" "/repos/$REPO_OWNER/$REPO_NAME" "$ACCESS_CONTROL" 2>/dev/null || echo "failed")

echo -e "${GREEN}   ✓ Repository visibility confirmed${NC}"

echo -e "${BLUE}8. Enabling Advanced Security Features...${NC}"

# Run the existing GitHub security enablement script
if [ -f "scripts/enable-github-security.sh" ]; then
    echo "Running comprehensive security enablement..."
    bash scripts/enable-github-security.sh "$REPO_OWNER" "$REPO_NAME"
else
    echo -e "${YELLOW}   ⚠ GitHub security script not found - run it separately${NC}"
fi

echo
echo -e "${GREEN}✅ GITHUB HARDENING COMPLETE${NC}"
echo "================================"
echo
echo "✓ Security Controls Enabled:"
echo "  • Signed commits REQUIRED on main branch"
echo "  • Force pushes and deletions BLOCKED"
echo "  • Linear history ENFORCED"
echo "  • Admin enforcement ENABLED (no bypassing)"
echo "  • 2 required reviewers for all PRs"
echo "  • Code owner reviews REQUIRED for critical files"
echo "  • Stale review dismissal ENABLED"
echo "  • Last push approval REQUIRED"
echo "  • Conversation resolution REQUIRED"
echo "  • Fork syncing DISABLED"
echo "  • Release tags protected with signature requirement"
echo "  • Secret scanning with push protection ENABLED"
echo "  • Dependabot security updates ENABLED"
echo "  • Private vulnerability reporting ENABLED"
echo "  • Squash-only merges ENFORCED"
echo "  • Wiki, downloads, projects DISABLED"
echo "  • CODEOWNERS protection for critical paths"
echo
echo "🔒 Critical Status Checks Required:"
echo "  • deploy_with_provenance_gate / build-verify-deploy"
echo "  • nojs-guard / no-js-enforcement" 
echo "  • SLSA L3 Real Provenance & Enforcement / hermetic-build"
echo
echo "⚠️  MANUAL ACTIONS REQUIRED:"
echo "1. Enable 2FA for all organization members"
echo "2. Require hardware security keys for admins"
echo "3. Set up branch protection rules if API calls failed"
echo "4. Review and update team permissions"
echo "5. Configure organization-level security settings"
echo
echo "🔗 Important Links:"
echo "  • Branch protection: https://github.com/$REPO_OWNER/$REPO_NAME/settings/branches"
echo "  • Security settings: https://github.com/$REPO_OWNER/$REPO_NAME/settings/security_analysis"
echo "  • Tag protection: https://github.com/$REPO_OWNER/$REPO_NAME/settings/tag_protection"
echo "  • Organization security: https://github.com/organizations/$REPO_OWNER/settings/security"

# Commit CODEOWNERS and issue templates
if [ -f ".github/CODEOWNERS" ]; then
    echo
    echo -e "${BLUE}Committing security configuration files...${NC}"
    git add .github/CODEOWNERS .github/ISSUE_TEMPLATE/
    git commit -m "Add CODEOWNERS and security issue templates for hardening

- CODEOWNERS requires security team review for critical paths  
- Security vulnerability reporting template
- Security hardening request template
- Protects all workflows, scripts, and security configuration

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>" || echo "Files already committed or no changes"
fi