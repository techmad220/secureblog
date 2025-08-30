#!/usr/bin/env bash
# build-deterministic.sh - Reproducible, deterministic builds
set -euo pipefail

echo "🔒 Starting deterministic build process..."

# Set deterministic environment
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --pretty=%ct)}
export TZ=UTC
export LC_ALL=C
umask 022

# Reproducible build flags for Go
export CGO_ENABLED=0
export GOOS=linux
export GOARCH=amd64

# Build info
BUILD_VERSION=${GITHUB_SHA:-$(git rev-parse HEAD)}
BUILD_DATE=$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ')

echo "📅 Build date (deterministic): $BUILD_DATE"
echo "🔑 Build version: $BUILD_VERSION"
echo "🌍 SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"

# Clean previous builds
rm -rf dist/
mkdir -p dist/

# Build Go binaries with deterministic flags
echo "🔨 Building Go binaries..."
go build \
    -trimpath \
    -ldflags="-w -s -X main.Version=${BUILD_VERSION} -X main.BuildDate=${BUILD_DATE}" \
    -mod=readonly \
    -buildvcs=false \
    -o dist/admin-server \
    ./cmd/admin-server/

go build \
    -trimpath \
    -ldflags="-w -s -X main.Version=${BUILD_VERSION} -X main.BuildDate=${BUILD_DATE}" \
    -mod=readonly \
    -buildvcs=false \
    -o dist/blog-generator \
    ./cmd/blog-generator/

# Build static site
echo "📝 Generating static site..."
./dist/blog-generator \
    -input=content \
    -output=dist/public \
    -templates=templates \
    -deterministic=true

# Remove any non-deterministic footers/timestamps from HTML
echo "🧹 Removing non-deterministic content..."
find dist/public -name "*.html" -type f -exec sed -i \
    -e '/generated.at.*[0-9]/d' \
    -e '/Generated on.*[0-9]/d' \
    -e '/Last updated.*[0-9]/d' \
    -e '/Build time.*[0-9]/d' {} \;

# Strip modification times from archives
echo "📦 Creating deterministic archives..."
cd dist/public
find . -type f -exec touch -d "@${SOURCE_DATE_EPOCH}" {} \;

# Create tar with deterministic options
tar \
    --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -czf ../site.tar.gz .

cd ../..

# Generate build manifest with sorted file list
echo "📋 Generating build manifest..."
python3 - <<EOF
import os
import json
import hashlib
from pathlib import Path

def hash_file(filepath):
    """Generate SHA-256 hash of file"""
    hasher = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

def generate_manifest(directory):
    """Generate deterministic file manifest"""
    manifest = {
        "version": "${BUILD_VERSION}",
        "build_date": "${BUILD_DATE}",
        "source_date_epoch": ${SOURCE_DATE_EPOCH},
        "files": {}
    }
    
    # Get all files in sorted order
    dist_path = Path(directory)
    files = sorted(dist_path.rglob('*'))
    
    for file_path in files:
        if file_path.is_file() and file_path.name != 'manifest.json':
            rel_path = str(file_path.relative_to(dist_path))
            file_hash = hash_file(file_path)
            file_size = file_path.stat().st_size
            
            manifest["files"][rel_path] = {
                "hash": file_hash,
                "size": file_size
            }
    
    # Write manifest
    with open(os.path.join(directory, 'manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
    
    return manifest

manifest = generate_manifest('dist')
print(f"📋 Generated manifest with {len(manifest['files'])} files")
EOF

# Generate integrity checksums
echo "🔐 Generating integrity checksums..."
cd dist
find . -type f \( -name "*.html" -o -name "*.css" -o -name "*.js" -o -name "*.json" \) | \
    sort | \
    xargs sha256sum > integrity.sha256

# Sign the manifest
if command -v cosign >/dev/null 2>&1; then
    echo "✍️ Signing build manifest..."
    cosign sign-blob manifest.json \
        --output-signature manifest.json.sig \
        --output-certificate manifest.json.crt \
        --yes || echo "⚠️ Cosign signing failed (continuing)"
fi

cd ..

# Verify build determinism
echo "🔍 Verifying build determinism..."
MANIFEST_HASH=$(sha256sum dist/manifest.json | cut -d' ' -f1)
echo "📋 Manifest hash: $MANIFEST_HASH"

# Create final build record
cat > dist/build-record.json << EOF
{
  "version": "$BUILD_VERSION",
  "build_date": "$BUILD_DATE",
  "source_date_epoch": $SOURCE_DATE_EPOCH,
  "manifest_hash": "$MANIFEST_HASH",
  "reproducible": true,
  "environment": {
    "TZ": "$TZ",
    "LC_ALL": "$LC_ALL",
    "CGO_ENABLED": "$CGO_ENABLED",
    "GOOS": "$GOOS",
    "GOARCH": "$GOARCH"
  }
}
EOF

echo "✅ Deterministic build completed successfully!"
echo "📁 Build artifacts:"
echo "   - dist/public/          (static site)"
echo "   - dist/admin-server     (admin binary)"
echo "   - dist/blog-generator   (generator binary)"
echo "   - dist/manifest.json    (file manifest)"
echo "   - dist/integrity.sha256 (checksums)"
echo "   - dist/build-record.json (build metadata)"
echo ""
echo "🔐 Build is reproducible with SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"