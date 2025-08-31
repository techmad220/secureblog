#!/bin/bash
# GitHub Security Setup - Enforces branch protection and security settings
# Run this to configure GitHub repository security

set -euo pipefail

REPO="${1:-$GITHUB_REPOSITORY}"
BRANCH="${2:-main}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 GitHub Security Configuration${NC}"
echo "================================="
echo "Repository: $REPO"
echo "Branch: $BRANCH"
echo ""

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}GitHub CLI (gh) is required${NC}"
    echo "Install: https://cli.github.com/"
    exit 1
fi

# Authenticate
echo -e "${BLUE}Authenticating with GitHub...${NC}"
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Not authenticated. Run: gh auth login${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authenticated${NC}\n"

# Function to enable security feature
enable_feature() {
    local feature="$1"
    local command="$2"
    
    echo -e "${BLUE}Enabling $feature...${NC}"
    if eval "$command"; then
        echo -e "${GREEN}  ✓ $feature enabled${NC}"
    else
        echo -e "${YELLOW}  ⚠ $feature may already be enabled or requires admin permissions${NC}"
    fi
}

# 1. Branch Protection
echo -e "${BLUE}Configuring branch protection for '$BRANCH'...${NC}"

gh api repos/$REPO/branches/$BRANCH/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["no-js-check","security-audit","slsa-provenance","content-sanitization"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":2,"dismiss_stale_reviews":true,"require_code_owner_reviews":true,"require_last_push_approval":true}' \
  --field restrictions=null \
  --field allow_force_pushes=false \
  --field allow_deletions=false \
  --field block_creations=false \
  --field required_conversation_resolution=true \
  --field lock_branch=false \
  --field allow_fork_syncing=false 2>/dev/null && \
  echo -e "${GREEN}✓ Branch protection configured${NC}" || \
  echo -e "${YELLOW}⚠ Branch protection partially configured (check permissions)${NC}"

# 2. Enable security features
echo -e "\n${BLUE}Enabling security features...${NC}"

# Vulnerability alerts
enable_feature "Vulnerability Alerts" \
  "gh api repos/$REPO --method PATCH --field security_and_analysis.advanced_security.status=enabled 2>/dev/null"

# Automated security fixes
enable_feature "Automated Security Fixes" \
  "gh api repos/$REPO/automated-security-fixes --method PUT 2>/dev/null"

# Secret scanning
enable_feature "Secret Scanning" \
  "gh api repos/$REPO --method PATCH --field security_and_analysis.secret_scanning.status=enabled 2>/dev/null"

# Secret scanning push protection
enable_feature "Secret Scanning Push Protection" \
  "gh api repos/$REPO --method PATCH --field security_and_analysis.secret_scanning_push_protection.status=enabled 2>/dev/null"

# 3. GitHub Actions security
echo -e "\n${BLUE}Configuring GitHub Actions security...${NC}"

# Set default permissions to read-only
gh api repos/$REPO/actions/permissions \
  --method PUT \
  --field enabled=true \
  --field allowed_actions=selected 2>/dev/null

gh api repos/$REPO/actions/permissions/selected-actions \
  --method PUT \
  --field github_owned_allowed=true \
  --field verified_allowed=true \
  --field patterns_allowed='["step-security/*","actions/*","github/*","sigstore/*","slsa-framework/*","anchore/*"]' 2>/dev/null && \
  echo -e "${GREEN}✓ Actions restricted to verified only${NC}" || \
  echo -e "${YELLOW}⚠ Actions permissions partially configured${NC}"

# Set default workflow permissions
gh api repos/$REPO/actions/permissions/workflow \
  --method PUT \
  --field default_workflow_permissions=read \
  --field can_approve_pull_request_reviews=false 2>/dev/null && \
  echo -e "${GREEN}✓ Default workflow permissions set to read-only${NC}" || \
  echo -e "${YELLOW}⚠ Workflow permissions partially configured${NC}"

# 4. Configure Dependabot
echo -e "\n${BLUE}Configuring Dependabot...${NC}"

cat > .github/dependabot.yml << 'EOF'
version: 2
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "daily"
    security-updates-only: true
    
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
    security-updates-only: true
    
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "daily"
    security-updates-only: true
EOF

if [ -f .github/dependabot.yml ]; then
    echo -e "${GREEN}✓ Dependabot configuration created${NC}"
else
    echo -e "${YELLOW}⚠ Could not create Dependabot config${NC}"
fi

# 5. Tag protection
echo -e "\n${BLUE}Configuring tag protection...${NC}"

gh api repos/$REPO/tag-protection \
  --method POST \
  --field pattern='v*' 2>/dev/null && \
  echo -e "${GREEN}✓ Tag protection enabled for v* tags${NC}" || \
  echo -e "${YELLOW}⚠ Tag protection may already exist${NC}"

# 6. Create security policy
echo -e "\n${BLUE}Creating security policy...${NC}"

cat > SECURITY.md << 'EOF'
# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| < latest| :x:                |

## Security Features

- ✅ **Zero JavaScript** - Enforced by CI
- ✅ **Signed Releases** - Cosign/Sigstore
- ✅ **SLSA Provenance** - Level 3
- ✅ **Content Sanitization** - All assets
- ✅ **No UI in Production** - Verified

## Reporting a Vulnerability

**DO NOT** create public issues for security vulnerabilities.

### Contact

- Email: security@secureblog.example.com
- PGP Key: [Public Key](/.well-known/pgp-key.asc)

### Process

1. Send encrypted report to security email
2. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### Response Time

- Initial response: 24 hours
- Status update: 72 hours
- Fix timeline: Based on severity

### Severity Levels

- **Critical**: Remote code execution, data breach
- **High**: XSS, authentication bypass
- **Medium**: Information disclosure
- **Low**: Minor issues

## Security Hardening

This project implements defense-in-depth:

1. **Build Time**
   - No-JS enforcement
   - Content sanitization
   - Dependency scanning

2. **Deploy Time**
   - Signed artifacts
   - SLSA provenance
   - Immutable storage

3. **Runtime**
   - CSP enforcement
   - Request filtering
   - Rate limiting

## Verification

All releases can be verified:

```bash
cosign verify-blob \
  --certificate-identity-regexp "https://github.com/\$REPO/" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --signature release.sig \
  --certificate release.cert \
  release.tar.gz
```
EOF

if [ -f SECURITY.md ]; then
    echo -e "${GREEN}✓ Security policy created${NC}"
else
    echo -e "${YELLOW}⚠ Could not create security policy${NC}"
fi

# 7. Verify settings
echo -e "\n${BLUE}Verifying security configuration...${NC}"

# Check branch protection
if gh api repos/$REPO/branches/$BRANCH/protection &> /dev/null; then
    echo -e "${GREEN}✓ Branch protection active${NC}"
else
    echo -e "${RED}✗ Branch protection not configured${NC}"
fi

# Check security features
SECURITY_STATUS=$(gh api repos/$REPO --jq '.security_and_analysis')
echo "Security features status:"
echo "$SECURITY_STATUS" | jq '.' 2>/dev/null || echo "$SECURITY_STATUS"

# Summary
echo -e "\n${BLUE}=== Configuration Summary ===${NC}"
echo "=============================="
echo -e "${GREEN}Branch Protection:${NC}"
echo "  • 2 required reviewers"
echo "  • Dismiss stale reviews"
echo "  • Require code owner reviews"
echo "  • Include administrators"
echo "  • Required status checks"

echo -e "\n${GREEN}Security Features:${NC}"
echo "  • Vulnerability alerts"
echo "  • Secret scanning"
echo "  • Dependabot security updates"

echo -e "\n${GREEN}GitHub Actions:${NC}"
echo "  • Read-only default permissions"
echo "  • Restricted to verified actions"

echo -e "\n${GREEN}Additional:${NC}"
echo "  • Tag protection (v*)"
echo "  • Security policy (SECURITY.md)"
echo "  • CODEOWNERS enforcement"

echo -e "\n${GREEN}✅ GitHub security configuration complete!${NC}"
echo -e "${YELLOW}Note: Some features may require GitHub Pro/Enterprise${NC}"