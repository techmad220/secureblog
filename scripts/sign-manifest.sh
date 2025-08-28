#!/usr/bin/env bash
set -euo pipefail

# Generate and sign content manifest with Ed25519
BUILD_DIR="${1:-build}"
PRIVATE_KEY="${SIGN_KEY:-}"

echo "🔐 Generating signed content manifest..."

# Generate Ed25519 key if not provided
if [ -z "$PRIVATE_KEY" ]; then
  echo "→ Generating Ed25519 signing key..."
  openssl genpkey -algorithm ED25519 -out manifest.key 2>/dev/null || {
    # Fallback for older OpenSSL
    ssh-keygen -t ed25519 -f manifest.key -N "" -C "secureblog-manifest"
    mv manifest.key.pub manifest.pub
  }
  PRIVATE_KEY="manifest.key"
fi

# Generate manifest with SHA-256 hashes
echo "→ Computing content hashes..."
cd "$BUILD_DIR"

manifest_content=$(
  find . -type f -print0 | \
  while IFS= read -r -d '' file; do
    hash=$(sha256sum "$file" | cut -d' ' -f1)
    size=$(stat -c%s "$file")
    mtime=$(stat -c%Y "$file")
    echo "${file#./}|$hash|$size|$mtime"
  done | sort
)

# Create JSON manifest
cat > manifest.json <<EOF
{
  "version": "1.0",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "generator": "secureblog",
  "files": {
EOF

first=true
echo "$manifest_content" | while IFS='|' read -r path hash size mtime; do
  [ -z "$path" ] && continue
  
  if [ "$first" = true ]; then
    first=false
  else
    echo ","
  fi
  
  printf '    "%s": {\n' "$path"
  printf '      "sha256": "%s",\n' "$hash"
  printf '      "size": %d,\n' "$size"
  printf '      "mtime": %d\n' "$mtime"
  printf '    }'
done >> manifest.json

cat >> manifest.json <<EOF

  }
}
EOF

echo "→ Signing manifest..."

# Sign with Ed25519 (or Cosign if available)
if command -v cosign &>/dev/null; then
  # Use Cosign for keyless signing
  COSIGN_EXPERIMENTAL=1 cosign sign-blob \
    --yes \
    manifest.json > manifest.json.sig
  
  echo "✅ Manifest signed with Cosign (keyless)"
else
  # Use OpenSSL Ed25519
  openssl pkeyutl -sign -inkey "$PRIVATE_KEY" \
    -in manifest.json \
    -out manifest.json.sig 2>/dev/null || {
    # Fallback to ssh-keygen
    ssh-keygen -Y sign -f "$PRIVATE_KEY" -n manifest manifest.json
    mv manifest.json.sig manifest.json.ssh-sig
  }
  
  echo "✅ Manifest signed with Ed25519"
fi

# Add manifest to build
cd - >/dev/null

echo ""
echo "📋 Manifest Summary:"
echo "   Files: $(echo "$manifest_content" | wc -l)"
echo "   Location: $BUILD_DIR/manifest.json"
echo "   Signature: $BUILD_DIR/manifest.json.sig"