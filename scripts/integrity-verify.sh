#!/bin/bash
# Content integrity verification script - plugin-based and automated

set -euo pipefail

# Configuration
DIST_DIR="${1:-./dist}"
MANIFEST_PATH="${2:-$DIST_DIR/integrity-manifest.json}"
SIGNATURE_PATH="${3:-$MANIFEST_PATH.sig}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Plugin: Manifest verification
verify_manifest() {
    echo "🔍 Verifying content integrity..."
    
    if [ ! -f "$MANIFEST_PATH" ]; then
        echo -e "${RED}❌ Integrity manifest not found: $MANIFEST_PATH${NC}"
        return 1
    fi
    
    # Extract file hashes from manifest
    local files_json=$(jq -r '.files' "$MANIFEST_PATH")
    if [ -z "$files_json" ] || [ "$files_json" == "null" ]; then
        echo -e "${RED}❌ Invalid manifest format${NC}"
        return 1
    fi
    
    local total_files=$(echo "$files_json" | jq 'length')
    local verified=0
    local failed=0
    
    echo "📁 Checking $total_files files..."
    
    # Verify each file
    while IFS= read -r file; do
        local expected_hash=$(echo "$files_json" | jq -r ".\"$file\"")
        local full_path="$DIST_DIR/$file"
        
        if [ ! -f "$full_path" ]; then
            echo -e "${RED}  ❌ Missing: $file${NC}"
            ((failed++))
            continue
        fi
        
        local actual_hash=$(sha256sum "$full_path" | cut -d' ' -f1)
        
        if [ "$expected_hash" != "$actual_hash" ]; then
            echo -e "${RED}  ❌ Modified: $file${NC}"
            echo "     Expected: $expected_hash"
            echo "     Actual:   $actual_hash"
            ((failed++))
        else
            ((verified++))
        fi
    done < <(echo "$files_json" | jq -r 'keys[]')
    
    # Check for unexpected files
    local unexpected=0
    while IFS= read -r file; do
        # Skip manifest and signature files
        if [[ "$file" == "integrity-manifest.json" ]] || [[ "$file" == "integrity-manifest.json.sig" ]]; then
            continue
        fi
        
        if ! echo "$files_json" | jq -e ".\"$file\"" > /dev/null 2>&1; then
            echo -e "${YELLOW}  ⚠️  Unexpected file: $file${NC}"
            ((unexpected++))
        fi
    done < <(cd "$DIST_DIR" && find . -type f -printf '%P\n')
    
    # Summary
    echo ""
    echo "📊 Integrity Check Summary:"
    echo -e "  ${GREEN}✓ Verified: $verified files${NC}"
    if [ $failed -gt 0 ]; then
        echo -e "  ${RED}✗ Failed: $failed files${NC}"
    fi
    if [ $unexpected -gt 0 ]; then
        echo -e "  ${YELLOW}⚠ Unexpected: $unexpected files${NC}"
    fi
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    
    return 0
}

# Plugin: Signature verification (if Cosign is available)
verify_signature() {
    if ! command -v cosign &> /dev/null; then
        echo -e "${YELLOW}⚠️  Cosign not installed, skipping signature verification${NC}"
        return 0
    fi
    
    if [ ! -f "$SIGNATURE_PATH" ]; then
        echo -e "${YELLOW}⚠️  No signature file found${NC}"
        return 0
    fi
    
    echo "🔐 Verifying manifest signature..."
    
    if cosign verify-blob \
        --signature "$SIGNATURE_PATH" \
        --certificate-identity-regexp "https://github.com/techmad220/secureblog" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
        "$MANIFEST_PATH" 2>/dev/null; then
        echo -e "${GREEN}✓ Signature verified${NC}"
        return 0
    else
        echo -e "${RED}❌ Signature verification failed${NC}"
        return 1
    fi
}

# Plugin: Permission check
check_permissions() {
    echo "🔒 Checking file permissions..."
    
    local issues=0
    
    # Check for executable files (shouldn't be any in static site)
    while IFS= read -r file; do
        if [[ "$file" == *.sh ]] || [[ "$file" == *.exe ]]; then
            continue  # Skip expected executables
        fi
        echo -e "${YELLOW}  ⚠️  Executable file: $file${NC}"
        ((issues++))
    done < <(find "$DIST_DIR" -type f -executable -printf '%P\n')
    
    # Check for world-writable files
    while IFS= read -r file; do
        echo -e "${RED}  ❌ World-writable: $file${NC}"
        ((issues++))
    done < <(find "$DIST_DIR" -type f -perm -002 -printf '%P\n')
    
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}✓ No permission issues found${NC}"
    else
        echo -e "${YELLOW}⚠️  Found $issues permission issues${NC}"
    fi
    
    return 0
}

# Main execution
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   SecureBlog Integrity Verification"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local exit_code=0
    
    # Run verification plugins
    verify_manifest || exit_code=1
    echo ""
    
    verify_signature || exit_code=1
    echo ""
    
    check_permissions
    echo ""
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "   ✅ All integrity checks passed!"
        echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "   ❌ Integrity verification failed!"
        echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
    
    exit $exit_code
}

# Allow sourcing for testing
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi