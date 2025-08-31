#!/usr/bin/env bash
# github-org-hardening.sh - GitHub organization security hardening
set -euo pipefail

ORG_NAME="${GITHUB_ORG:-secureblog}"
REPO_NAME="${GITHUB_REPO:-secureblog}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔐 GitHub Organization Security Hardening${NC}"
echo "=========================================="
echo "Organization: $ORG_NAME"
echo "Repository: $REPO_NAME"
echo ""

# Check if GitHub CLI is available and authenticated
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) not found${NC}"
    echo "Install with: curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
    echo "             echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null"
    echo "             sudo apt update && sudo apt install gh"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI not authenticated${NC}"
    echo "Run: gh auth login"
    exit 1
fi

echo -e "${GREEN}✅ GitHub CLI authenticated${NC}"

# 1. Enable signed commits requirement
echo "🔏 Configuring signed commits requirement..."

gh api --method PATCH "/repos/$ORG_NAME/$REPO_NAME/branches/main/protection" \
    --field required_status_checks='{"strict":true,"checks":[{"context":"Attestation Verification","app_id":15368}]}' \
    --field enforce_admins=true \
    --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":true,"require_last_push_approval":true}' \
    --field restrictions='{"users":[],"teams":[],"apps":[]}' \
    --field required_signatures=true \
    --field allow_force_pushes=false \
    --field allow_deletions=false \
    --field block_creations=false \
    --field required_conversation_resolution=true \
    --field lock_branch=false \
    --field allow_fork_syncing=false

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Branch protection with signed commits enabled${NC}"
else
    echo -e "${YELLOW}⚠️ Branch protection may already be configured${NC}"
fi

# 2. Configure tag protection
echo "🏷️ Setting up tag protection..."

gh api --method POST "/repos/$ORG_NAME/$REPO_NAME/tags/protection" \
    --field pattern='v*' \
    --field required=true

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Tag protection enabled for version tags${NC}"
else
    echo -e "${YELLOW}⚠️ Tag protection may already exist${NC}"
fi

# 3. Repository security settings
echo "🛡️ Configuring repository security settings..."

# Enable security advisories
gh api --method PATCH "/repos/$ORG_NAME/$REPO_NAME" \
    --field security_and_analysis='{"advanced_security":{"status":"enabled"},"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"dependency_graph":{"status":"enabled"},"vulnerability_alerts":{"status":"enabled"}}'

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Security features enabled${NC}"
else
    echo -e "${YELLOW}⚠️ Security features may already be enabled${NC}"
fi

# 4. Disable vulnerable features
echo "🚫 Disabling insecure features..."

gh api --method PATCH "/repos/$ORG_NAME/$REPO_NAME" \
    --field allow_merge_commit=false \
    --field allow_rebase_merge=true \
    --field allow_squash_merge=true \
    --field delete_branch_on_merge=true \
    --field allow_auto_merge=false \
    --field allow_update_branch=false

echo -e "${GREEN}✅ Insecure merge options disabled${NC}"

# 5. Set up teams and permissions (informational)
echo "👥 Team and Permission Recommendations..."
echo -e "${BLUE}ℹ️ Recommended GitHub teams:${NC}"
echo "  • @secureblog/security-team (admin access, required for security reviews)"
echo "  • @secureblog/devops (maintain access for infrastructure)"
echo "  • @secureblog/content-team (write access for content)"
echo "  • @secureblog/code-reviewers (triage access for general reviews)"
echo ""
echo -e "${YELLOW}⚠️ Create these teams manually in GitHub UI or via API${NC}"

# 6. Organization-level settings recommendations
echo "🏢 Organization Security Recommendations..."
cat > github-org-security-checklist.md << CHECKLIST
# GitHub Organization Security Checklist

**Organization**: $ORG_NAME
**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Repository-Level Security (Completed)

- ✅ **Branch protection on main branch**
  - Require signed commits
  - Require pull request reviews (1+ approver)
  - Require code owner reviews
  - Dismiss stale reviews
  - Require conversation resolution
  - No force pushes or deletions

- ✅ **Tag protection for version tags (v*)**
  - Prevents unauthorized releases
  - Protects version history integrity

- ✅ **Advanced security features enabled**
  - Secret scanning with push protection
  - Dependency vulnerability alerts
  - Advanced security features

- ✅ **Secure merge settings**
  - Squash and rebase merges only
  - Auto-delete branches on merge
  - No auto-merge or update branch

## Organization-Level Settings (Manual Configuration Required)

### Access Control
- [ ] **Two-factor authentication required** for all members
- [ ] **Member base permissions**: Read only (restrict by default)
- [ ] **Outside collaborators**: Restricted or disabled
- [ ] **Repository creation**: Limited to owners/specified teams

### Team Structure
- [ ] **@secureblog/security-team**: Admin access, code owners for security files
- [ ] **@secureblog/devops**: Maintain access for infrastructure
- [ ] **@secureblog/content-team**: Write access for content
- [ ] **@secureblog/code-reviewers**: Triage access for general reviews

### Security Policies
- [ ] **Default repository permissions**: Private
- [ ] **Dependency insights**: Enabled
- [ ] **GitHub Actions**: Restrict to organization and verified creators
- [ ] **Pages**: Restricted visibility (private or internal only)
- [ ] **Projects**: Restricted visibility

### Audit and Compliance
- [ ] **Audit log monitoring**: Set up automated alerts
- [ ] **Member activity monitoring**: Regular reviews
- [ ] **Access reviews**: Quarterly permission audits
- [ ] **GitHub Advanced Security**: Enterprise features enabled

## Actions to Take

1. **Configure Organization Settings**
   - Go to https://github.com/orgs/$ORG_NAME/settings/security
   - Enable two-factor authentication requirement
   - Set member base permissions to "Read"

2. **Create Security Teams**
   - Create teams listed above with appropriate permissions
   - Add team members based on principle of least privilege

3. **Set Up Monitoring**
   - Configure audit log alerts for sensitive actions
   - Set up Slack/email notifications for security events
   - Monitor dependency alerts and act on them promptly

4. **Regular Maintenance**
   - Quarterly access reviews
   - Monthly security settings audit
   - Update security policies as needed

## Verification Commands

\`\`\`bash
# Check branch protection
gh api "/repos/$ORG_NAME/$REPO_NAME/branches/main/protection"

# List organization security settings
gh api "/orgs/$ORG_NAME" | jq '.two_factor_requirement_enabled'

# Check repository security features
gh api "/repos/$ORG_NAME/$REPO_NAME" | jq '.security_and_analysis'
\`\`\`

CHECKLIST

echo -e "${GREEN}📄 Organization security checklist saved to: github-org-security-checklist.md${NC}"

# Final summary
echo ""
echo -e "${GREEN}🎉 GitHub Repository Security Hardening Complete!${NC}"
echo "=================================================="
echo ""
echo -e "${GREEN}✅ Repository Security Configured:${NC}"
echo "  • Signed commits required on main branch"
echo "  • Branch protection with required reviews"
echo "  • Tag protection for version releases"
echo "  • Advanced security features enabled"
echo "  • Secure merge and branch settings"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "  1. Configure organization-level settings manually"
echo "  2. Create and configure security teams"
echo "  3. Set up audit log monitoring"
echo "  4. Review checklist in github-org-security-checklist.md"
echo ""
echo -e "${YELLOW}⚠️ Note: Organization-level settings require owner permissions${NC}"
echo -e "${GREEN}🛡️ Repository is now hardened against unauthorized changes!${NC}"
