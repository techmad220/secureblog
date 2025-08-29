#!/usr/bin/env bash
# Release verification script - validates downloaded SecureBlog releases
# Usage: ./scripts/release-verify.sh <version>
# Example: ./scripts/release-verify.sh v1.0.0
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  printf 'Usage: %s <version>\n' "$0" >&2
  printf 'Example: %s v1.0.0\n' "$0" >&2
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

printf "${GREEN}🔐 SecureBlog Release Verification${NC}\n"
printf "Version: %s\n\n" "$VERSION"

# Check prerequisites
MISSING_TOOLS=0
DOWNLOADER=""

# Check for wget or curl
if command -v wget &> /dev/null; then
  DOWNLOADER="wget -q"
elif command -v curl &> /dev/null; then
  DOWNLOADER="curl -sfL -O"
else
  printf "${RED}✗ Missing required tool: wget or curl${NC}\n" >&2
  MISSING_TOOLS=1
fi

# Check other required tools
for tool in sha256sum tar; do
  if ! command -v "$tool" &> /dev/null; then
    printf "${RED}✗ Missing required tool: %s${NC}\n" "$tool" >&2
    MISSING_TOOLS=1
  fi
done

# Cosign is optional but recommended
if ! command -v cosign &> /dev/null; then
  printf "${YELLOW}⚠ Optional tool missing: cosign (needed for signature verification)${NC}\n"
  printf "  Install: https://docs.sigstore.dev/cosign/installation\n"
fi

if [[ $MISSING_TOOLS -eq 1 ]]; then
  exit 1
fi

# Create temp directory for verification
VERIFY_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_DIR"' EXIT
cd "$VERIFY_DIR"

printf "📥 Downloading release artifacts...\n"

# GitHub release URL base
RELEASE_URL="https://github.com/techmad220/secureblog/releases/download/${VERSION}"

# Download artifacts
ARTIFACTS=(
  "dist-${VERSION}.tar.gz"
  "dist-${VERSION}.tar.gz.sha256"
  "dist-${VERSION}.tar.gz.sig"
  "dist-${VERSION}.tar.gz.crt"
  "secureblog-${VERSION}.sbom.json"
  "secureblog-${VERSION}.sbom.json.sha256"
)

for artifact in "${ARTIFACTS[@]}"; do
  printf "  Downloading %s..." "$artifact"
  if $DOWNLOADER "${RELEASE_URL}/${artifact}" 2>/dev/null; then
    printf " ✓\n"
  else
    printf " ${YELLOW}(optional)${NC}\n"
  fi
done

printf "\n"

# Step 1: Verify checksums
printf "1️⃣  Verifying SHA-256 checksums...\n"
if [[ -f "dist-${VERSION}.tar.gz.sha256" ]]; then
  if sha256sum -c "dist-${VERSION}.tar.gz.sha256" &>/dev/null; then
    printf "   ${GREEN}✓ dist archive checksum valid${NC}\n"
  else
    printf "   ${RED}✗ dist archive checksum FAILED${NC}\n" >&2
    exit 1
  fi
else
  printf "   ${YELLOW}⚠ No checksum file found${NC}\n"
fi

if [[ -f "secureblog-${VERSION}.sbom.json.sha256" ]]; then
  if sha256sum -c "secureblog-${VERSION}.sbom.json.sha256" &>/dev/null; then
    printf "   ${GREEN}✓ SBOM checksum valid${NC}\n"
  else
    printf "   ${RED}✗ SBOM checksum FAILED${NC}\n" >&2
  fi
fi

# Step 2: Verify Cosign signatures
printf "\n2️⃣  Verifying Cosign signatures...\n"
if [[ -f "dist-${VERSION}.tar.gz.sig" ]] && [[ -f "dist-${VERSION}.tar.gz.crt" ]]; then
  if cosign verify-blob \
    --certificate "dist-${VERSION}.tar.gz.crt" \
    --signature "dist-${VERSION}.tar.gz.sig" \
    --certificate-identity-regexp "^https://github.com/techmad220/secureblog" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    "dist-${VERSION}.tar.gz" &>/dev/null; then
    printf "   ${GREEN}✓ Cosign signature valid${NC}\n"
  else
    printf "   ${RED}✗ Cosign signature FAILED${NC}\n" >&2
    exit 1
  fi
else
  printf "   ${YELLOW}⚠ Signature files not found (pre-attestation release?)${NC}\n"
fi

# Step 3: Extract and verify content
printf "\n3️⃣  Extracting and verifying content...\n"
tar xzf "dist-${VERSION}.tar.gz"

# Check for integrity manifest
if [[ -f "dist/.integrity.manifest" ]]; then
  printf "   Found integrity manifest\n"
  cd dist
  if sha256sum --quiet --check .integrity.manifest 2>/dev/null; then
    printf "   ${GREEN}✓ All file hashes match manifest${NC}\n"
  else
    printf "   ${RED}✗ File integrity check FAILED${NC}\n" >&2
    exit 1
  fi
  cd ..
else
  printf "   ${YELLOW}⚠ No integrity manifest in dist${NC}\n"
fi

# Step 4: Run security regression guard
printf "\n4️⃣  Running security checks...\n"

# Check for JavaScript violations
JS_FOUND=0
if find dist -type f -name "*.js" -print -quit | grep -q .; then
  printf "   ${RED}✗ JavaScript files detected!${NC}\n" >&2
  JS_FOUND=1
fi

if grep -r '<script' dist --include="*.html" &>/dev/null; then
  printf "   ${RED}✗ <script> tags found in HTML!${NC}\n" >&2
  JS_FOUND=1
fi

if grep -rE '\bon(click|load|error)\s*=' dist --include="*.html" &>/dev/null; then
  printf "   ${RED}✗ Inline event handlers detected!${NC}\n" >&2
  JS_FOUND=1
fi

if [[ $JS_FOUND -eq 0 ]]; then
  printf "   ${GREEN}✓ No JavaScript/handlers detected${NC}\n"
fi

# Step 5: SBOM analysis (if present)
if [[ -f "secureblog-${VERSION}.sbom.json" ]]; then
  printf "\n5️⃣  Analyzing SBOM...\n"
  # Count packages
  PKG_COUNT=$(grep -c '"name"' "secureblog-${VERSION}.sbom.json" || echo "0")
  printf "   Found %s packages in dependency tree\n" "$PKG_COUNT"
  
  # Check for high-risk packages (example patterns)
  if grep -q '"name".*"crypto/md5"' "secureblog-${VERSION}.sbom.json" 2>/dev/null; then
    printf "   ${YELLOW}⚠ Weak crypto (md5) in dependencies${NC}\n"
  fi
  
  printf "   ${GREEN}✓ SBOM present for supply chain audit${NC}\n"
fi

# Summary
printf "\n${GREEN}═══════════════════════════════════════${NC}\n"
printf "${GREEN}📊 Verification Summary for %s${NC}\n" "$VERSION"
printf "${GREEN}═══════════════════════════════════════${NC}\n"

VERIFIED=1
[[ -f "dist-${VERSION}.tar.gz.sha256" ]] && printf "✅ SHA-256 checksum verified\n" || VERIFIED=0
[[ -f "dist-${VERSION}.tar.gz.sig" ]] && printf "✅ Cosign signature verified\n" || printf "⚠️  No signature (unsigned release)\n"
[[ -f "dist/.integrity.manifest" ]] && printf "✅ Integrity manifest verified\n" || printf "⚠️  No integrity manifest\n"
[[ $JS_FOUND -eq 0 ]] && printf "✅ No JavaScript detected\n" || { printf "❌ JavaScript violations found\n"; VERIFIED=0; }
[[ -f "secureblog-${VERSION}.sbom.json" ]] && printf "✅ SBOM available\n" || printf "⚠️  No SBOM included\n"

if [[ $VERIFIED -eq 1 ]]; then
  printf "\n${GREEN}✓ Release ${VERSION} verification PASSED${NC}\n"
  printf "Safe to deploy dist/ contents to production.\n"
else
  printf "\n${RED}✗ Release verification INCOMPLETE${NC}\n" >&2
  printf "Review warnings above before deployment.\n" >&2
  exit 1
fi

# Optional: Show extracted files
printf "\n📁 Extracted files in: %s/dist/\n" "$VERIFY_DIR"
printf "Run 'ls -la %s/dist/' to inspect contents\n" "$VERIFY_DIR"