#!/bin/bash

# Secure deployment script with verification

set -euo pipefail

DEPLOY_HOST="${1:-}"
DEPLOY_PATH="${2:-/var/www/secureblog}"

if [ -z "$DEPLOY_HOST" ]; then
    echo "Local deployment mode (for testing)"
    DEPLOY_PATH="./local_deploy"
    rm -rf "$DEPLOY_PATH"
    mkdir -p "$DEPLOY_PATH"
    cp -r build/* "$DEPLOY_PATH/"
    
    echo "✅ Deployed locally to $DEPLOY_PATH"
    echo "📝 Add these headers to your web server:"
    cat build/_headers
    exit 0
fi

echo "🔒 Secure deployment to $DEPLOY_HOST"

# Verify build integrity before deployment
echo "🔍 Verifying build integrity..."
./secureblog -verify=true -output=build

# Create signed deployment package
echo "📦 Creating signed deployment package..."
tar -czf deploy.tar.gz build/
sha256sum deploy.tar.gz > deploy.tar.gz.sha256
gpg --armor --detach-sign deploy.tar.gz 2>/dev/null || echo "⚠️  GPG signing skipped"

# Deploy with verification
echo "🚀 Deploying to $DEPLOY_HOST..."
scp deploy.tar.gz deploy.tar.gz.sha256 "$DEPLOY_HOST:/tmp/"

ssh "$DEPLOY_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail

# Verify checksum
cd /tmp
sha256sum -c deploy.tar.gz.sha256

# Extract to staging
STAGING="/tmp/blog_staging_$$"
mkdir -p "$STAGING"
tar -xzf deploy.tar.gz -C "$STAGING"

# Atomic swap
DEPLOY_PATH="$2"
BACKUP_PATH="${DEPLOY_PATH}_backup_$(date +%s)"

if [ -d "$DEPLOY_PATH" ]; then
    mv "$DEPLOY_PATH" "$BACKUP_PATH"
fi

mv "$STAGING/build" "$DEPLOY_PATH"

# Set secure permissions
find "$DEPLOY_PATH" -type f -exec chmod 644 {} \;
find "$DEPLOY_PATH" -type d -exec chmod 755 {} \;

# Clean up
rm -f /tmp/deploy.tar.gz /tmp/deploy.tar.gz.sha256
rm -rf "$STAGING"

echo "✅ Deployment complete and verified"
REMOTE_SCRIPT

echo "🎉 Secure deployment successful!"