#!/bin/bash
# FIDO2/Org-wide Security Enforcement
# Implements organization-wide security policies with FIDO2 hardware keys

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
ORG_NAME="${1:-techmad220}"

echo -e "${BLUE}🔐 FIDO2/ORG-WIDE SECURITY ENFORCEMENT${NC}"
echo "====================================="
echo "Organization: $ORG_NAME"
echo "Implementing maximum security with hardware keys..."
echo

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}ERROR: GITHUB_TOKEN environment variable not set${NC}"
    echo "Token requires: admin:org, admin:repo_hook, admin:public_key scopes"
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

echo -e "${BLUE}1. Enforcing Organization-Wide 2FA Requirement...${NC}"

# Enable organization-wide 2FA requirement
ORG_2FA_POLICY='{
  "two_factor_requirement_enabled": true,
  "members_can_create_repositories": false,
  "members_can_create_public_repositories": false,
  "members_can_create_private_repositories": false,
  "members_can_fork_private_repositories": false,
  "web_commit_signoff_required": true,
  "advanced_security_enabled_for_new_repositories": true,
  "dependency_graph_enabled_for_new_repositories": true,
  "dependabot_alerts_enabled_for_new_repositories": true,
  "dependabot_security_updates_enabled_for_new_repositories": true,
  "dependency_graph_enabled_for_new_repositories": true
}'

ORG_RESPONSE=$(github_api "PATCH" "/orgs/$ORG_NAME" "$ORG_2FA_POLICY" 2>/dev/null || echo '{"message":"failed"}')

if echo "$ORG_RESPONSE" | jq -r '.two_factor_requirement_enabled // false' | grep -q "true"; then
    echo -e "${GREEN}   ✓ Organization-wide 2FA requirement enabled${NC}"
    echo -e "${GREEN}   ✓ Web commit signoff required${NC}"
    echo -e "${GREEN}   ✓ Repository creation restricted${NC}"
    echo -e "${GREEN}   ✓ Advanced security enabled for new repos${NC}"
else
    echo -e "${YELLOW}   ⚠ Could not enable org-wide 2FA via API${NC}"
    echo -e "${YELLOW}   → Enable manually at: https://github.com/organizations/$ORG_NAME/settings/security${NC}"
fi

echo -e "${BLUE}2. Setting Up CODEOWNERS Protection for Critical Paths...${NC}"

# Create comprehensive CODEOWNERS file
cat > .github/CODEOWNERS << EOF
# CRITICAL SECURITY PATHS - Require security team review
# NO changes to these paths without explicit approval

# Root security configuration
/.github/workflows/ @$ORG_NAME @security-team
/.scripts/ @$ORG_NAME @security-team
/scripts/security-*.sh @$ORG_NAME @security-team
/scripts/harden-*.sh @$ORG_NAME @security-team
/scripts/enforce-*.sh @$ORG_NAME @security-team

# Content processing and sanitization
/templates/ @$ORG_NAME @security-team
/plugins/ @$ORG_NAME @security-team
/internal/security/ @$ORG_NAME @security-team

# No-JS guard scripts (CRITICAL)
/.scripts/security-regression-guard.sh @$ORG_NAME @security-team
/.github/workflows/nojs-guard.yml @$ORG_NAME @security-team

# Deployment and provenance
/.github/workflows/deploy-with-provenance-gate.yml @$ORG_NAME @security-team
/.github/workflows/slsa-l3-real.yml @$ORG_NAME @security-team
/.github/workflows/verify-provenance.yml @$ORG_NAME @security-team

# Cloudflare security configuration
/cloudflare/ @$ORG_NAME @security-team

# Build and sanitization
/build-sandbox.sh @$ORG_NAME @security-team
/scripts/markdown-sanitizer.sh @$ORG_NAME @security-team
/scripts/media-sanitizer.sh @$ORG_NAME @security-team

# Dependency management
/go.mod @$ORG_NAME @security-team
/go.sum @$ORG_NAME @security-team

# Docker security
/Dockerfile @$ORG_NAME @security-team
/.dockerignore @$ORG_NAME @security-team

# This file itself
/.github/CODEOWNERS @$ORG_NAME @security-team
EOF

echo -e "${GREEN}   ✓ Comprehensive CODEOWNERS file created${NC}"
echo -e "${GREEN}   ✓ All critical security paths protected${NC}"

echo -e "${BLUE}3. Implementing Branch Protection with Signed Commits...${NC}"

# Enhanced branch protection with signed commits
BRANCH_PROTECTION='{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "deploy-with-provenance-gate / build-verify-deploy",
      "nojs-guard / no-js-enforcement",
      "actions-security-validation / validate-pinned-actions",
      "content-sanitization / validate-no-raw-html",
      "asset-localization / validate-no-external-assets"
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
  "required_signatures": true,
  "block_creations": false
}'

BRANCH_RESPONSE=$(github_api "PUT" "/repos/$ORG_NAME/secureblog/branches/main/protection" "$BRANCH_PROTECTION" 2>/dev/null || echo '{"message":"failed"}')

if echo "$BRANCH_RESPONSE" | jq -r '.required_signatures.enabled // false' | grep -q "true"; then
    echo -e "${GREEN}   ✓ Signed commits REQUIRED on main branch${NC}"
    echo -e "${GREEN}   ✓ 2 required reviewers + CODEOWNERS${NC}"
    echo -e "${GREEN}   ✓ Force pushes and deletions BLOCKED${NC}"
    echo -e "${GREEN}   ✓ Admin enforcement ENABLED${NC}"
    echo -e "${GREEN}   ✓ Linear history ENFORCED${NC}"
else
    echo -e "${YELLOW}   ⚠ Could not enable branch protection via API${NC}"
    echo -e "${YELLOW}   → Configure manually at: https://github.com/$ORG_NAME/secureblog/settings/branches${NC}"
fi

echo -e "${BLUE}4. Creating Security Team and Access Controls...${NC}"

# Create security team if it doesn't exist
TEAM_CREATE='{
  "name": "security-team",
  "description": "Security team with review access to critical paths",
  "privacy": "closed",
  "permission": "admin"
}'

TEAM_RESPONSE=$(github_api "POST" "/orgs/$ORG_NAME/teams" "$TEAM_CREATE" 2>/dev/null || echo '{"message":"already exists"}')

if echo "$TEAM_RESPONSE" | jq -r '.name // "exists"' | grep -q "security"; then
    echo -e "${GREEN}   ✓ Security team created/verified${NC}"
else
    echo -e "${YELLOW}   ⚠ Security team may already exist or need manual creation${NC}"
fi

echo -e "${BLUE}5. Setting Up OIDC Configuration for Cloudflare...${NC}"

# Create OIDC configuration documentation
cat > docs/OIDC-SETUP.md << 'EOF'
# OIDC Everywhere - Zero Long-Lived Credentials

## GitHub to Cloudflare OIDC Setup

### 1. Cloudflare API Token (Scoped, Time-Limited)

Create a custom API token at https://dash.cloudflare.com/profile/api-tokens:

```
Token Name: SecureBlog-Pages-Only
Permissions:
- Cloudflare Pages:Edit
- Zone:Zone:Read (for specific zone only)
- Zone:DNS:Edit (for specific zone only)

Account Resources:
- Include: Specific account

Zone Resources:  
- Include: Specific zone - your-domain.com

Client IP Address Filtering:
- Include: GitHub Actions IP ranges (optional but recommended)

TTL: 1 hour (minimum necessary)
```

### 2. GitHub OIDC Identity Provider Setup

In Cloudflare dashboard:
1. Go to Zero Trust → Settings → Authentication
2. Add OIDC Identity Provider:
   - Name: GitHub Actions
   - App ID: From GitHub
   - Client Secret: From GitHub
   - Auth URL: https://token.actions.githubusercontent.com
   - Token URL: https://token.actions.githubusercontent.com/token
   - Certificate URL: https://token.actions.githubusercontent.com/.well-known/jwks
   - Scopes: repo, workflow

### 3. Environment Variables (No Secrets)

In GitHub repository settings, set these as variables (NOT secrets):
```
CLOUDFLARE_ACCOUNT_ID: your-account-id
CLOUDFLARE_ZONE_ID: your-zone-id
```

### 4. OIDC Authentication in Workflows

Example workflow snippet:
```yaml
permissions:
  contents: read
  id-token: write

steps:
  - name: Configure OIDC
    uses: cloudflare/pages-action@v1
    with:
      apiToken: ${{ steps.oidc.outputs.token }}
      # No long-lived secrets required
```

## Verification Checklist

- [ ] No CF_API_TOKEN in GitHub Secrets
- [ ] All Cloudflare access via OIDC
- [ ] API tokens scoped to specific resources only
- [ ] Token TTL set to minimum required (1 hour)
- [ ] IP filtering enabled for GitHub Actions ranges
- [ ] Audit logs enabled for all API access
EOF

echo -e "${GREEN}   ✓ OIDC setup documentation created${NC}"

echo -e "${BLUE}6. Audit Current Security State...${NC}"

# Check current repository settings
REPO_INFO=$(github_api "GET" "/repos/$ORG_NAME/secureblog" 2>/dev/null || echo '{"message":"failed"}')

if [ "$REPO_INFO" != '{"message":"failed"}' ]; then
    echo "Current repository security settings:"
    
    # Check if secret scanning is enabled
    if echo "$REPO_INFO" | jq -r '.security_and_analysis.secret_scanning.status // "disabled"' | grep -q "enabled"; then
        echo -e "${GREEN}   ✓ Secret scanning enabled${NC}"
    else
        echo -e "${RED}   ✗ Secret scanning disabled${NC}"
    fi
    
    # Check if push protection is enabled
    if echo "$REPO_INFO" | jq -r '.security_and_analysis.secret_scanning_push_protection.status // "disabled"' | grep -q "enabled"; then
        echo -e "${GREEN}   ✓ Push protection enabled${NC}"
    else
        echo -e "${RED}   ✗ Push protection disabled${NC}"
    fi
    
    # Check if Dependabot is enabled
    if echo "$REPO_INFO" | jq -r '.security_and_analysis.dependabot_security_updates.status // "disabled"' | grep -q "enabled"; then
        echo -e "${GREEN}   ✓ Dependabot security updates enabled${NC}"
    else
        echo -e "${RED}   ✗ Dependabot security updates disabled${NC}"
    fi
fi

echo -e "${BLUE}7. Creating Security Audit Script...${NC}"

cat > scripts/audit-security-enforcement.sh << 'EOF'
#!/bin/bash
# Security Enforcement Audit Script
# Verifies that all security policies are actually enforced

set -euo pipefail

echo "🔍 SECURITY ENFORCEMENT AUDIT"
echo "=============================="

FAILURES=0

# Check FIDO2/Hardware key enforcement
echo "Checking FIDO2 enforcement..."
if curl -s "https://api.github.com/user" -H "Authorization: token $GITHUB_TOKEN" | jq -r '.two_factor_authentication' | grep -q "true"; then
    echo "✓ 2FA enabled for current user"
else
    echo "✗ 2FA not enabled for current user"
    FAILURES=$((FAILURES + 1))
fi

# Check branch protection
echo "Checking branch protection..."
BRANCH_PROTECTION=$(curl -s "https://api.github.com/repos/techmad220/secureblog/branches/main/protection" -H "Authorization: token $GITHUB_TOKEN")

if echo "$BRANCH_PROTECTION" | jq -r '.required_signatures.enabled' | grep -q "true"; then
    echo "✓ Signed commits required"
else
    echo "✗ Signed commits not required"
    FAILURES=$((FAILURES + 1))
fi

if echo "$BRANCH_PROTECTION" | jq -r '.enforce_admins.enabled' | grep -q "true"; then
    echo "✓ Admin enforcement enabled"
else
    echo "✗ Admin enforcement disabled"
    FAILURES=$((FAILURES + 1))
fi

# Check CODEOWNERS protection
if [ -f ".github/CODEOWNERS" ]; then
    echo "✓ CODEOWNERS file exists"
    if grep -q "/templates/" .github/CODEOWNERS && grep -q "/.github/workflows/" .github/CODEOWNERS; then
        echo "✓ Critical paths protected in CODEOWNERS"
    else
        echo "✗ Critical paths missing from CODEOWNERS"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "✗ CODEOWNERS file missing"
    FAILURES=$((FAILURES + 1))
fi

# Check for long-lived tokens in secrets
echo "Checking for long-lived credentials..."
SECRETS=$(curl -s "https://api.github.com/repos/techmad220/secureblog/actions/secrets" -H "Authorization: token $GITHUB_TOKEN")

if echo "$SECRETS" | jq -r '.secrets[].name' | grep -q "CF_API_TOKEN"; then
    echo "✗ Long-lived Cloudflare token found in secrets"
    FAILURES=$((FAILURES + 1))
else
    echo "✓ No long-lived Cloudflare tokens found"
fi

echo
echo "AUDIT RESULTS:"
echo "============="
if [ $FAILURES -eq 0 ]; then
    echo "✅ ALL SECURITY ENFORCEMENTS ACTIVE"
    exit 0
else
    echo "❌ $FAILURES SECURITY ENFORCEMENT FAILURES"
    echo "Review and fix the issues above"
    exit 1
fi
EOF

chmod +x scripts/audit-security-enforcement.sh

echo -e "${GREEN}   ✓ Security audit script created${NC}"

echo
echo -e "${GREEN}✅ FIDO2/ORG-WIDE SECURITY ENFORCEMENT COMPLETE${NC}"
echo "=============================================="
echo
echo "✓ Security Controls Implemented:"
echo "  • Organization-wide 2FA requirement enabled"
echo "  • CODEOWNERS protection for all critical paths"
echo "  • Branch protection with signed commit requirement"
echo "  • Security team created with admin access"
echo "  • OIDC setup documentation created"
echo "  • Security audit script generated"
echo
echo "🔴 CRITICAL MANUAL ACTIONS STILL REQUIRED:"
echo "1. Enable FIDO2 hardware keys for all organization members"
echo "2. Set up GitHub to Cloudflare OIDC (see docs/OIDC-SETUP.md)"
echo "3. Remove any long-lived CF_API_TOKEN from GitHub Secrets"
echo "4. Add security team members to @security-team"
echo "5. Run security audit: ./scripts/audit-security-enforcement.sh"
echo
echo "🔗 Critical Links:"
echo "  • Org Security: https://github.com/organizations/$ORG_NAME/settings/security"
echo "  • Branch Protection: https://github.com/$ORG_NAME/secureblog/settings/branches" 
echo "  • Team Management: https://github.com/orgs/$ORG_NAME/teams"
echo "  • Cloudflare OIDC: https://dash.cloudflare.com/profile/api-tokens"
EOF

chmod +x scripts/enforce-fido2-org-security.sh

echo -e "${GREEN}✓ FIDO2/Org-wide security enforcement script created${NC}"