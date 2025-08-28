#!/bin/bash
# Secure deployment script using OIDC for Cloudflare

set -euo pipefail

# Plugin-based deployment configuration
DEPLOY_CONFIG="${DEPLOY_CONFIG:-./deploy.config.json}"
PLUGIN_DIR="${PLUGIN_DIR:-./plugins/deploy}"

# Load deployment plugins
load_plugin() {
    local plugin_name="$1"
    local plugin_file="$PLUGIN_DIR/$plugin_name.sh"
    
    if [ -f "$plugin_file" ]; then
        source "$plugin_file"
        echo "✓ Loaded plugin: $plugin_name"
    else
        echo "⚠️  Plugin not found: $plugin_name"
        return 1
    fi
}

# Pre-deployment checks
pre_deploy_checks() {
    echo "🔍 Running pre-deployment checks..."
    
    # Verify build integrity
    if [ -f "./scripts/integrity-verify.sh" ]; then
        ./scripts/integrity-verify.sh || {
            echo "❌ Integrity verification failed"
            exit 1
        }
    fi
    
    # Check for sensitive data
    if grep -r "SECRET\|PASSWORD\|TOKEN\|KEY" dist/ 2>/dev/null | grep -v "integrity-manifest"; then
        echo "❌ Potential secrets found in build"
        exit 1
    fi
    
    echo "✅ Pre-deployment checks passed"
}

# Deploy to Cloudflare R2 using OIDC
deploy_to_r2() {
    echo "📦 Deploying to Cloudflare R2..."
    
    # Use wrangler with OIDC token (no long-lived credentials)
    if [ -n "${CF_API_TOKEN:-}" ]; then
        # GitHub Actions OIDC token
        export CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"
    elif [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
        # Already configured
        echo "Using existing Cloudflare credentials"
    else
        echo "❌ No Cloudflare credentials found"
        echo "   Set CF_API_TOKEN or use GitHub Actions OIDC"
        exit 1
    fi
    
    # Upload to R2 bucket
    npx wrangler r2 object put secureblog-static/ \
        --file ./dist \
        --content-type "application/octet-stream" \
        --cache-control "public, max-age=3600" \
        || {
            echo "❌ Failed to upload to R2"
            exit 1
        }
    
    # Deploy worker
    npx wrangler deploy \
        --env production \
        --compatibility-date "$(date +%Y-%m-%d)" \
        || {
            echo "❌ Failed to deploy worker"
            exit 1
        }
    
    echo "✅ Deployed to Cloudflare"
}

# Deploy with GitHub OIDC
deploy_with_github_oidc() {
    echo "🔐 Deploying with GitHub OIDC..."
    
    # This runs in GitHub Actions with OIDC
    if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
        echo "❌ Not running in GitHub Actions with OIDC"
        exit 1
    fi
    
    # Get OIDC token from GitHub
    OIDC_TOKEN=$(curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
        "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r '.value')
    
    # Exchange for Cloudflare API token (configure in Cloudflare API Tokens)
    CF_API_TOKEN=$(curl -X POST https://api.cloudflare.com/client/v4/oidc/token \
        -H "Content-Type: application/json" \
        -d "{\"oidc_token\": \"$OIDC_TOKEN\", \"account_id\": \"$CLOUDFLARE_ACCOUNT_ID\"}" \
        | jq -r '.result.api_token')
    
    export CF_API_TOKEN
    deploy_to_r2
}

# Deploy to backup/mirror (optional)
deploy_to_mirror() {
    local MIRROR_HOST="${1:-}"
    
    if [ -z "$MIRROR_HOST" ]; then
        echo "⚠️  No mirror host configured, skipping"
        return 0
    fi
    
    echo "🔄 Deploying to mirror: $MIRROR_HOST"
    
    # Use SSH with forced command and no PTY
    # Requires setup: ssh-keygen -t ed25519 -f deploy_key -C "deploy@secureblog"
    # Add to authorized_keys: command="/usr/local/bin/deploy-receive.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 ...
    
    rsync -avz --delete \
        -e "ssh -i ./deploy_key -o StrictHostKeyChecking=yes -o PasswordAuthentication=no" \
        ./dist/ \
        "deploy@$MIRROR_HOST:/var/www/secureblog-mirror/" \
        || {
            echo "⚠️  Mirror deployment failed (non-critical)"
        }
}

# Post-deployment verification
post_deploy_verify() {
    local SITE_URL="${1:-https://secureblog.com}"
    
    echo "🔍 Verifying deployment..."
    
    # Check site is accessible
    if ! curl -sf "$SITE_URL" > /dev/null; then
        echo "❌ Site not accessible: $SITE_URL"
        return 1
    fi
    
    # Verify security headers
    headers=$(curl -sI "$SITE_URL")
    
    required_headers=(
        "Content-Security-Policy"
        "X-Frame-Options"
        "X-Content-Type-Options"
        "Strict-Transport-Security"
    )
    
    for header in "${required_headers[@]}"; do
        if ! echo "$headers" | grep -qi "^$header:"; then
            echo "❌ Missing security header: $header"
            return 1
        fi
    done
    
    # Verify integrity manifest is served
    if ! curl -sf "$SITE_URL/integrity-manifest.json" > /dev/null; then
        echo "⚠️  Integrity manifest not accessible"
    fi
    
    echo "✅ Deployment verified successfully"
}

# Main deployment orchestration
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   SecureBlog Deployment (OIDC)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Load plugins
    load_plugin "pre-deploy"
    load_plugin "cloudflare"
    load_plugin "post-deploy"
    
    # Run deployment steps
    pre_deploy_checks
    
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        deploy_with_github_oidc
    else
        deploy_to_r2
    fi
    
    # Optional mirror deployment
    deploy_to_mirror "${MIRROR_HOST:-}"
    
    # Verify deployment
    post_deploy_verify "${SITE_URL:-https://secureblog.com}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   ✅ Deployment completed!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Allow sourcing for testing
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi