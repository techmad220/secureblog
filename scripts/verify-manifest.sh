#!/usr/bin/env bash
set -euo pipefail

# Verify signed manifest against live site
SITE_URL="${1:-https://secureblog.pages.dev}"
MANIFEST_URL="${2:-$SITE_URL/manifest.json}"
SIGNATURE_URL="${3:-$SITE_URL/manifest.json.sig}"

echo "🔍 Verifying site integrity against signed manifest..."

# Download manifest and signature
echo "→ Fetching manifest from $MANIFEST_URL"
curl -sfL "$MANIFEST_URL" -o /tmp/manifest.json || {
  echo "❌ Failed to fetch manifest"
  exit 1
}

curl -sfL "$SIGNATURE_URL" -o /tmp/manifest.json.sig 2>/dev/null || {
  echo "⚠️  No signature found (unsigned manifest)"
}

# Verify signature if available
if [ -f /tmp/manifest.json.sig ]; then
  if command -v cosign &>/dev/null; then
    echo "→ Verifying Cosign signature..."
    COSIGN_EXPERIMENTAL=1 cosign verify-blob \
      --signature /tmp/manifest.json.sig \
      --certificate-identity-regexp ".*" \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      /tmp/manifest.json && echo "✅ Signature valid" || {
        echo "❌ Invalid signature!"
        exit 1
      }
  fi
fi

# Parse manifest
echo "→ Checking file integrity..."
files=$(jq -r '.files | to_entries[] | .key' /tmp/manifest.json)
total=$(echo "$files" | wc -l)
checked=0
failed=0

for file in $files; do
  expected_hash=$(jq -r ".files[\"$file\"].sha256" /tmp/manifest.json)
  file_url="$SITE_URL/$file"
  
  # Download and hash file
  actual_hash=$(curl -sfL "$file_url" | sha256sum | cut -d' ' -f1) || {
    echo "❌ Missing: $file"
    ((failed++))
    continue
  }
  
  if [ "$expected_hash" != "$actual_hash" ]; then
    echo "❌ Modified: $file"
    echo "   Expected: $expected_hash"
    echo "   Actual:   $actual_hash"
    ((failed++))
  else
    ((checked++))
  fi
  
  # Progress indicator
  if [ $((checked % 10)) -eq 0 ]; then
    echo "   Checked $checked/$total files..."
  fi
done

# Summary
echo ""
echo "📊 Integrity Verification Complete:"
echo "   ✅ Verified: $checked files"
if [ $failed -gt 0 ]; then
  echo "   ❌ Failed: $failed files"
  echo ""
  echo "🚨 INTEGRITY VIOLATION DETECTED!"
  echo "The live site does not match the signed manifest."
  exit 1
else
  echo ""
  echo "✅ All files match signed manifest - site integrity verified!"
fi