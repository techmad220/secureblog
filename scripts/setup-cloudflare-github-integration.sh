#!/bin/bash
# Setup Cloudflare Native GitHub Integration (NO API TOKENS!)
# Uses Cloudflare's native integration - zero long-lived secrets

set -euo pipefail

echo "🔒 CLOUDFLARE NATIVE GITHUB INTEGRATION SETUP"
echo "============================================="
echo
echo "This script guides you through setting up tokenless deployment"
echo "using Cloudflare's native GitHub integration."
echo
echo "BENEFITS:"
echo "  ✅ NO API tokens stored in GitHub"
echo "  ✅ OAuth-based authentication"
echo "  ✅ Automatic branch deployments"
echo "  ✅ Preview environments"
echo "  ✅ Zero long-lived secrets"
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Connect GitHub to Cloudflare Pages"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "1. Go to: https://dash.cloudflare.com/pages"
echo "2. Click 'Create a project'"
echo "3. Select 'Connect to GitHub'"
echo "4. Authorize Cloudflare Pages app"
echo "5. Select repository: secureblog"
echo "6. Configure build settings:"
echo "   - Framework preset: None"
echo "   - Build command: make build-static"
echo "   - Build output directory: dist/"
echo "   - Root directory: /"
echo "   - Environment variables:"
echo "     JAVASCRIPT_ALLOWED=false"
echo "     BUILD_MODE=production"
echo
read -p "Press ENTER when GitHub connection is complete..."

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Configure Zero-Trust Access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "1. Go to: https://one.dash.cloudflare.com/access"
echo "2. Create application:"
echo "   - Type: Self-hosted"
echo "   - Application name: SecureBlog Admin"
echo "   - Session duration: 24 hours"
echo "   - Application domain: secureblog.pages.dev"
echo "3. Add policies:"
echo "   - Require hardware key authentication"
echo "   - Require GitHub organization membership"
echo "   - Require specific email domains"
echo "4. Enable additional settings:"
echo "   - Purpose justification: Required"
echo "   - App Launcher visibility: Hidden"
echo
read -p "Press ENTER when Zero-Trust is configured..."

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Remove ALL API Tokens"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Checking for existing secrets in GitHub..."

# Check if gh CLI is available
if command -v gh &> /dev/null; then
    echo "Listing repository secrets..."
    gh secret list --repo techmad220/secureblog || true
    
    echo
    echo "To remove API tokens:"
    echo "  gh secret delete CLOUDFLARE_API_TOKEN --repo techmad220/secureblog"
    echo "  gh secret delete CLOUDFLARE_ACCOUNT_ID --repo techmad220/secureblog"
    echo
    echo "These are NO LONGER NEEDED with native integration!"
else
    echo "Install GitHub CLI to manage secrets: https://cli.github.com/"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Configure Deployment Hooks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "In Cloudflare Pages settings, configure:"
echo "1. Deployment hooks:"
echo "   - Before build: Verify signed commits"
echo "   - After build: Generate attestations"
echo "   - Before deploy: Verify CSP headers"
echo "   - After deploy: Live security verification"
echo "2. Build configuration:"
echo "   - Production branch: main"
echo "   - Preview branches: All non-production branches"
echo "   - Build caching: Enabled"
echo "   - Build frequency: All commits"
echo
read -p "Press ENTER when hooks are configured..."

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Verify Integration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Create test file to trigger deployment
cat > test-integration.md << 'EOF'
# Integration Test
This file tests the Cloudflare Pages native integration.
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

echo "Creating test commit to verify integration..."
git add test-integration.md
git commit -m "Test Cloudflare Pages native integration (tokenless)"
git push origin main

echo
echo "Monitor deployment at:"
echo "  https://dash.cloudflare.com/pages/view/secureblog"
echo
echo "After successful deployment, remove test file:"
echo "  git rm test-integration.md"
echo "  git commit -m 'Remove integration test file'"
echo "  git push origin main"
echo

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TOKENLESS DEPLOYMENT CONFIGURED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Security improvements:"
echo "  ✅ NO long-lived API tokens"
echo "  ✅ OAuth-based authentication only"
echo "  ✅ Automatic branch deployments"
echo "  ✅ Zero-Trust access control"
echo "  ✅ Hardware key enforcement"
echo
echo "Next steps:"
echo "1. Remove any remaining API tokens from GitHub secrets"
echo "2. Revoke all Cloudflare API tokens"
echo "3. Enable audit logging in Cloudflare"
echo "4. Configure deployment notifications"
echo
echo "Documentation:"
echo "  https://developers.cloudflare.com/pages/platform/git-integration/"
echo "  https://developers.cloudflare.com/cloudflare-one/identity/devices/warp/"