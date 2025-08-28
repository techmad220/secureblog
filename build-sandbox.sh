#!/usr/bin/env bash
set -euo pipefail

# Build with plugins sandboxed - no network, no env access
echo "🔒 Building with sandboxed plugins..."

# Disable all network access during build
export GOWORK=off
export CGO_ENABLED=0
export GOPROXY=off
export GOSUMDB=off

# Clear sensitive environment
unset GITHUB_TOKEN
unset CI_TOKEN
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset CLOUDFLARE_API_TOKEN

# Build in network namespace (no internet)
if command -v unshare &>/dev/null; then
  echo "→ Building in network-isolated namespace..."
  unshare -n bash -c '
    # Verify no network
    if ping -c 1 8.8.8.8 &>/dev/null; then
      echo "❌ Network still accessible!"
      exit 1
    fi
    
    # Build
    go build -trimpath -ldflags="-w -s" -mod=readonly ./cmd
    make build
  '
else
  # Fallback without namespace
  echo "→ Building with network disabled (GOPROXY=off)..."
  go build -trimpath -ldflags="-w -s" -mod=readonly ./cmd
  make build
fi

# Run security regression guard
echo "→ Checking for JavaScript in build output..."
bash .scripts/security-regression-guard.sh

# Sign manifest
echo "→ Signing content manifest..."
bash scripts/sign-manifest.sh build

echo "✅ Build complete with sandboxed plugins"