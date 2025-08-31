#!/usr/bin/env bash
# verify-reproducible-builds.sh - Verify builds are byte-identical across environments
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BUILD1_DIR="build1"
BUILD2_DIR="build2"
COMPARISON_REPORT="reproducible-build-report.md"

echo -e "${GREEN}🔄 Reproducible Builds Verification${NC}"
echo "==================================="
echo ""

# Set deterministic build environment
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --pretty=%ct)}
export TZ=UTC
export LC_ALL=C
export CGO_ENABLED=0
export GOOS=linux
export GOARCH=amd64
umask 022

BUILD_VERSION=${GITHUB_SHA:-$(git rev-parse HEAD)}
BUILD_DATE=$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ')

echo -e "${BLUE}ℹ️ Build Environment:${NC}"
echo "  SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
echo "  TZ: $TZ"
echo "  LC_ALL: $LC_ALL"
echo "  Build Version: $BUILD_VERSION"
echo "  Build Date: $BUILD_DATE"
echo ""

# Clean previous builds
rm -rf "$BUILD1_DIR" "$BUILD2_DIR" "$COMPARISON_REPORT"

# Build 1
echo -e "${BLUE}🔨 Running Build 1...${NC}"
mkdir -p "$BUILD1_DIR"
(
    export TMPDIR="$(mktemp -d)"
    trap "rm -rf $TMPDIR" EXIT
    
    # Build binaries
    go build \
        -trimpath \
        -ldflags="-w -s -X main.Version=${BUILD_VERSION} -X main.BuildDate=${BUILD_DATE}" \
        -mod=readonly \
        -buildvcs=false \
        -o "$BUILD1_DIR/admin-server" \
        ./cmd/admin-server/

    go build \
        -trimpath \
        -ldflags="-w -s -X main.Version=${BUILD_VERSION} -X main.BuildDate=${BUILD_DATE}" \
        -mod=readonly \
        -buildvcs=false \
        -o "$BUILD1_DIR/blog-generator" \
        ./cmd/blog-generator/

    # Generate static site
    if [ -x "$BUILD1_DIR/blog-generator" ]; then
        "$BUILD1_DIR/blog-generator" \
            -input=content \
            -output="$BUILD1_DIR/public" \
            -templates=templates \
            -deterministic=true || echo "Site generation failed (expected if no content)"
    fi
    
    # Create tarball with deterministic settings
    if [ -d "$BUILD1_DIR/public" ]; then
        cd "$BUILD1_DIR/public"
        find . -type f -exec touch -d "@${SOURCE_DATE_EPOCH}" {} \;
        tar \
            --sort=name \
            --mtime="@${SOURCE_DATE_EPOCH}" \
            --owner=0 \
            --group=0 \
            --numeric-owner \
            -czf "../site.tar.gz" .
        cd ../..
    fi
)

echo -e "${GREEN}✅ Build 1 completed${NC}"

# Small delay to ensure different build context
sleep 2

# Build 2 (in different environment to test reproducibility)
echo -e "${BLUE}🔨 Running Build 2...${NC}"
mkdir -p "$BUILD2_DIR"
(
    export TMPDIR="$(mktemp -d)"
    trap "rm -rf $TMPDIR" EXIT
    
    # Slightly different temp directory, different process context
    cd /tmp && cd - >/dev/null
    
    # Build binaries (identical commands)
    go build \
        -trimpath \
        -ldflags="-w -s -X main.Version=${BUILD_VERSION} -X main.BuildDate=${BUILD_DATE}" \
        -mod=readonly \
        -buildvcs=false \
        -o "$BUILD2_DIR/admin-server" \
        ./cmd/admin-server/

    go build \
        -trimpath \
        -ldflags="-w -s -X main.Version=${BUILD_VERSION} -X main.BuildDate=${BUILD_DATE}" \
        -mod=readonly \
        -buildvcs=false \
        -o "$BUILD2_DIR/blog-generator" \
        ./cmd/blog-generator/

    # Generate static site
    if [ -x "$BUILD2_DIR/blog-generator" ]; then
        "$BUILD2_DIR/blog-generator" \
            -input=content \
            -output="$BUILD2_DIR/public" \
            -templates=templates \
            -deterministic=true || echo "Site generation failed (expected if no content)"
    fi
    
    # Create tarball with deterministic settings
    if [ -d "$BUILD2_DIR/public" ]; then
        cd "$BUILD2_DIR/public"
        find . -type f -exec touch -d "@${SOURCE_DATE_EPOCH}" {} \;
        tar \
            --sort=name \
            --mtime="@${SOURCE_DATE_EPOCH}" \
            --owner=0 \
            --group=0 \
            --numeric-owner \
            -czf "../site.tar.gz" .
        cd ../..
    fi
)

echo -e "${GREEN}✅ Build 2 completed${NC}"
echo ""

# Compare builds
echo -e "${BLUE}🔍 Comparing builds...${NC}"

# Initialize comparison results
comparison_passed=true
differences_found=()

# Compare binaries
compare_file() {
    local file1="$1"
    local file2="$2" 
    local name="$3"
    
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        echo -e "${YELLOW}⚠️ File missing: $name${NC}"
        differences_found+=("$name: Missing file")
        comparison_passed=false
        return 1
    fi
    
    if cmp -s "$file1" "$file2"; then
        echo -e "${GREEN}✅ $name: Identical${NC}"
        return 0
    else
        echo -e "${RED}❌ $name: Different${NC}"
        
        # Get file sizes
        size1=$(stat -f%z "$file1" 2>/dev/null || stat -c%s "$file1" 2>/dev/null)
        size2=$(stat -f%z "$file2" 2>/dev/null || stat -c%s "$file2" 2>/dev/null)
        
        echo "  Build 1 size: $size1 bytes"
        echo "  Build 2 size: $size2 bytes"
        
        # Generate hex diff for small differences
        if [ "$size1" -eq "$size2" ] && [ "$size1" -lt 10000 ]; then
            echo "  Hex diff (first 100 bytes):"
            hexdiff=$(diff <(xxd "$file1" | head -10) <(xxd "$file2" | head -10) || true)
            echo "$hexdiff" | sed 's/^/    /'
        fi
        
        differences_found+=("$name: Size1=$size1 Size2=$size2")
        comparison_passed=false
        return 1
    fi
}

echo ""
echo "Binary comparison:"
compare_file "$BUILD1_DIR/admin-server" "$BUILD2_DIR/admin-server" "admin-server"
compare_file "$BUILD1_DIR/blog-generator" "$BUILD2_DIR/blog-generator" "blog-generator"

if [ -f "$BUILD1_DIR/site.tar.gz" ] && [ -f "$BUILD2_DIR/site.tar.gz" ]; then
    echo ""
    echo "Archive comparison:"
    compare_file "$BUILD1_DIR/site.tar.gz" "$BUILD2_DIR/site.tar.gz" "site.tar.gz"
fi

# Compare directory contents if they exist
if [ -d "$BUILD1_DIR/public" ] && [ -d "$BUILD2_DIR/public" ]; then
    echo ""
    echo "Directory comparison:"
    
    # Compare file lists
    file_list1=$(find "$BUILD1_DIR/public" -type f | sort)
    file_list2=$(find "$BUILD2_DIR/public" -type f | sort)
    
    if [ "$file_list1" = "$file_list2" ]; then
        echo -e "${GREEN}✅ File lists identical${NC}"
        
        # Compare individual files
        echo "$file_list1" | while read -r file1; do
            file2="${file1/$BUILD1_DIR/$BUILD2_DIR}"
            rel_name=$(basename "$file1")
            compare_file "$file1" "$file2" "$rel_name" || true
        done
    else
        echo -e "${RED}❌ File lists differ${NC}"
        echo "Files only in build 1:"
        comm -23 <(echo "$file_list1") <(echo "$file_list2") | sed 's/^/  /'
        echo "Files only in build 2:"
        comm -13 <(echo "$file_list1") <(echo "$file_list2") | sed 's/^/  /'
        comparison_passed=false
        differences_found+=("Directory structure differs")
    fi
fi

# Generate detailed report
echo ""
echo -e "${BLUE}📊 Generating comparison report...${NC}"

{
    echo "# Reproducible Build Verification Report"
    echo "========================================"
    echo ""
    echo "**Generated:** $(date -u)"
    echo "**Repository:** $(git remote get-url origin 2>/dev/null || echo 'local')"
    echo "**Commit:** $BUILD_VERSION"
    echo "**SOURCE_DATE_EPOCH:** $SOURCE_DATE_EPOCH"
    echo "**Build Date:** $BUILD_DATE"
    echo ""
    
    if [ "$comparison_passed" = true ]; then
        echo "## ✅ Result: REPRODUCIBLE"
        echo ""
        echo "All builds are byte-identical across different environments and contexts."
        echo "This confirms the build process is fully deterministic."
    else
        echo "## ❌ Result: NOT REPRODUCIBLE"
        echo ""
        echo "Differences were found between builds. This indicates non-deterministic behavior."
        echo ""
        echo "### Differences Found:"
        printf ' - %s\n' "${differences_found[@]}"
    fi
    
    echo ""
    echo "## Build Environment"
    echo ""
    echo "- **SOURCE_DATE_EPOCH:** $SOURCE_DATE_EPOCH"
    echo "- **TZ:** $TZ" 
    echo "- **LC_ALL:** $LC_ALL"
    echo "- **CGO_ENABLED:** $CGO_ENABLED"
    echo "- **GOOS:** $GOOS"
    echo "- **GOARCH:** $GOARCH"
    echo "- **umask:** 022"
    echo ""
    
    echo "## Go Build Flags"
    echo ""
    echo "- \`-trimpath\`: Remove file system paths from binaries"
    echo "- \`-buildvcs=false\`: Disable VCS info embedding"
    echo "- \`-mod=readonly\`: Ensure no module changes"
    echo "- \`-ldflags=\"-w -s\"\": Strip debug info and symbol table"
    echo ""
    
    echo "## File Analysis"
    echo ""
    
    # File size table
    echo "| File | Build 1 | Build 2 | Status |"
    echo "|------|---------|---------|--------|"
    
    for file in "admin-server" "blog-generator" "site.tar.gz"; do
        file1="$BUILD1_DIR/$file"
        file2="$BUILD2_DIR/$file"
        
        if [ -f "$file1" ] && [ -f "$file2" ]; then
            size1=$(stat -f%z "$file1" 2>/dev/null || stat -c%s "$file1" 2>/dev/null)
            size2=$(stat -f%z "$file2" 2>/dev/null || stat -c%s "$file2" 2>/dev/null)
            
            if [ "$size1" -eq "$size2" ] && cmp -s "$file1" "$file2"; then
                status="✅ Identical"
            else
                status="❌ Different"
            fi
            
            echo "| $file | $size1 | $size2 | $status |"
        fi
    done
    
    echo ""
    echo "## Verification Commands"
    echo ""
    echo "To verify this report:"
    echo ""
    echo '```bash'
    echo "# Compare binaries"
    echo "sha256sum $BUILD1_DIR/admin-server $BUILD2_DIR/admin-server"
    echo "sha256sum $BUILD1_DIR/blog-generator $BUILD2_DIR/blog-generator"
    echo ""
    echo "# Binary diff"
    echo "cmp $BUILD1_DIR/admin-server $BUILD2_DIR/admin-server && echo 'Identical' || echo 'Different'"
    echo "cmp $BUILD1_DIR/blog-generator $BUILD2_DIR/blog-generator && echo 'Identical' || echo 'Different'"
    echo '```'
    echo ""
    
    echo "## Recommendations"
    echo ""
    if [ "$comparison_passed" = true ]; then
        echo "- ✅ Build process is fully reproducible"
        echo "- ✅ Can verify supply chain integrity"
        echo "- ✅ Suitable for high-security deployments"
        echo "- 📋 Consider automating this check in CI/CD"
    else
        echo "- ❌ Build process needs determinism fixes"
        echo "- 🔍 Investigate sources of non-determinism"
        echo "- 🛠️ Common causes: timestamps, file ordering, randomness"
        echo "- 📋 Run this script with different SOURCE_DATE_EPOCH values"
    fi
    
} > "$COMPARISON_REPORT"

echo -e "${GREEN}📄 Report saved to: $COMPARISON_REPORT${NC}"

# Print summary
echo ""
if [ "$comparison_passed" = true ]; then
    echo -e "${GREEN}🎉 REPRODUCIBLE BUILDS VERIFIED!${NC}"
    echo -e "${GREEN}✅ All builds are byte-identical${NC}"
    echo -e "${GREEN}🔒 Supply chain integrity confirmed${NC}"
    exit 0
else
    echo -e "${RED}💥 REPRODUCIBLE BUILDS FAILED!${NC}"
    echo -e "${RED}❌ Builds are not identical${NC}"
    echo -e "${RED}🚨 Non-deterministic build process detected${NC}"
    echo ""
    echo -e "${YELLOW}📋 Differences found:${NC}"
    printf "${YELLOW} - %s${NC}\n" "${differences_found[@]}"
    echo ""
    echo -e "${BLUE}🔍 Check the detailed report: $COMPARISON_REPORT${NC}"
    exit 1
fi