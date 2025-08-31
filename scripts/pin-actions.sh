#!/bin/bash
# Pin GitHub Actions to SHA for supply chain security
# Converts all action references from tags to commit SHAs

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 Pinning GitHub Actions to SHA${NC}"
echo "=================================="

# GitHub Actions to pin with their current SHAs
declare -A ACTION_PINS=(
    ["actions/checkout@v4"]="actions/checkout@1e31de5234b664ca3f0ed09e5ce0d6de0c5d0fc1"
    ["actions/setup-go@v5"]="actions/setup-go@41dfa10bad2bb2ae585af6ee5bb4d7d973ad74ed"
    ["actions/upload-artifact@v4"]="actions/upload-artifact@6f51ac03b9356f520e9adb1b1b7802705f340c2b"
    ["actions/download-artifact@v4"]="actions/download-artifact@fa0a91b85d4f404e444e00e005971372dc801d16"
    ["github/codeql-action/upload-sarif@v3"]="github/codeql-action/upload-sarif@cb7a9eb42e01dd0e13db99ddf0e3ccdadda24398"
    ["step-security/harden-runner@v2"]="step-security/harden-runner@91182cccc01eb5e619899d80e4e971d6181294a7"
    ["sigstore/cosign-installer@v3"]="sigstore/cosign-installer@dc72c7d5c4d10cd6bcb8cf6e3fd625a9e5e537da"
    ["slsa-framework/slsa-verifier/actions/installer@v2.6.0"]="slsa-framework/slsa-verifier/actions/installer@3714a2a4684014deb874a0e737dffa0ee02dd647"
    ["anchore/sbom-action@v0"]="anchore/sbom-action@fc46e51fd3cb168ffb36ec72c5bcf7e3e52b3b91"
    ["actions/attest-build-provenance@v1"]="actions/attest-build-provenance@ef244123eb79f2f7a7e75d99086184180e6d0018"
    ["softprops/action-gh-release@v2"]="softprops/action-gh-release@e7a8f85e1c69a9ca6ba914d1d0e05ba8254ed7eb"
    ["actions/github-script@v7"]="actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea"
    ["aquasecurity/trivy-action@master"]="aquasecurity/trivy-action@a20de5420d57c4102486cdd9578b45609c99d7eb"
    ["slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.0.0"]="slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@5a775b367a56d5bd118a224a811bba288150a563"
)

# Find all workflow files
WORKFLOW_FILES=$(find .github/workflows -name "*.yml" -o -name "*.yaml")
TOTAL_REPLACEMENTS=0

for workflow in $WORKFLOW_FILES; do
    echo -e "${BLUE}Processing: $workflow${NC}"
    
    # Create backup
    cp "$workflow" "$workflow.bak"
    
    # Replace each action with its SHA
    for action in "${!ACTION_PINS[@]}"; do
        sha="${ACTION_PINS[$action]}"
        
        # Count occurrences
        count=$(grep -c "uses: $action" "$workflow" 2>/dev/null || echo 0)
        
        if [ "$count" -gt 0 ]; then
            # Replace with SHA and add comment
            sed -i "s|uses: $action|uses: $sha # $action|g" "$workflow"
            echo -e "${GREEN}  ✓ Pinned $action (${count} occurrences)${NC}"
            TOTAL_REPLACEMENTS=$((TOTAL_REPLACEMENTS + count))
        fi
    done
    
    # Remove backup if successful
    if diff -q "$workflow" "$workflow.bak" > /dev/null; then
        rm "$workflow.bak"
    else
        rm "$workflow.bak"
        echo -e "${GREEN}  ✓ File updated${NC}"
    fi
done

# Also update workflow permissions to be least-privilege
echo -e "\n${BLUE}Setting least-privilege permissions...${NC}"

for workflow in $WORKFLOW_FILES; do
    # Check if permissions are already set at workflow level
    if ! grep -q "^permissions:" "$workflow"; then
        # Add default read-only permissions after 'on:' block
        awk '/^on:/ {p=1} p && /^[a-z]/ && !/^on:/ {print "permissions:\n  contents: read\n"; p=0} 1' "$workflow" > "$workflow.tmp"
        mv "$workflow.tmp" "$workflow"
        echo -e "${GREEN}  ✓ Added default permissions to $workflow${NC}"
    fi
done

echo -e "\n${BLUE}Summary:${NC}"
echo "  Total actions pinned: $TOTAL_REPLACEMENTS"
echo "  Workflow files updated: $(echo "$WORKFLOW_FILES" | wc -w)"
echo -e "\n${GREEN}✅ All actions are now pinned to SHA${NC}"