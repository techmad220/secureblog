#!/bin/bash

# Ultra-secure build script with integrity verification

set -euo pipefail

echo "🔒 Starting secure blog build..."

# Build in isolated environment
echo "📦 Building in container..."
docker run --rm \
    -v $(pwd):/app \
    -w /app \
    --network none \
    --read-only \
    --tmpfs /tmp \
    golang:1.21-alpine sh -c "
        go mod download
        go build -ldflags='-s -w' -trimpath -o secureblog cmd/main.go
    " 2>/dev/null || {
        echo "⚠️  Docker not available, building locally..."
        go build -ldflags="-s -w" -trimpath -o secureblog cmd/main.go
    }

# Run the builder
./secureblog -content=content -output=build -sign=true

# Verify the build
./secureblog -verify=true -output=build

# Create deployment package with checksums
echo "📦 Creating deployment package..."
tar -czf deploy.tar.gz build/
sha256sum deploy.tar.gz > deploy.tar.gz.sha256

echo "✅ Secure build complete!"
echo "📊 Build statistics:"
echo "   - Files generated: $(find build -type f | wc -l)"
echo "   - Total size: $(du -sh build | cut -f1)"
echo "   - Integrity manifest: build/integrity.txt"
echo "   - Security headers: build/_headers"
echo ""
echo "🚀 Deploy with: ./deploy.sh"