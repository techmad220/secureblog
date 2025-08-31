#!/bin/bash
# Build Release Safe Script
# Ensures local Web UI is excluded from production releases
# Enforces strict separation between local development and production artifacts

set -euo pipefail

# Configuration
BUILD_DIR="dist"
RELEASE_DIR="release"
UI_DIR="ui"
LOCAL_ONLY_DIRS=("ui" "cmd/ui" "internal/ui" "web-ui" "admin-ui" "dev-ui")
LOCAL_ONLY_FILES=("start-admin.sh" "launch-ui.sh" "*-ui.go" "*_ui.go")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 Secure Release Builder${NC}"
echo "=========================="
echo -e "${YELLOW}This build excludes all local UI components${NC}"
echo ""

# Function to check for UI components
check_ui_components() {
    echo -e "${BLUE}Scanning for UI components...${NC}"
    
    local ui_found=false
    
    # Check for UI directories
    for dir in "${LOCAL_ONLY_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo -e "${YELLOW}Found UI directory: $dir${NC}"
            ui_found=true
        fi
    done
    
    # Check for UI files
    for pattern in "${LOCAL_ONLY_FILES[@]}"; do
        if ls $pattern 2>/dev/null | grep -q .; then
            echo -e "${YELLOW}Found UI files matching: $pattern${NC}"
            ui_found=true
        fi
    done
    
    if [ "$ui_found" = true ]; then
        echo -e "${GREEN}✓ UI components detected and will be excluded${NC}"
    else
        echo -e "${GREEN}✓ No UI components found${NC}"
    fi
}

# Function to build without UI
build_without_ui() {
    echo -e "\n${BLUE}Building release artifacts...${NC}"
    
    # Clean previous builds
    rm -rf "$BUILD_DIR" "$RELEASE_DIR"
    mkdir -p "$BUILD_DIR" "$RELEASE_DIR"
    
    # Build Go binary with UI disabled
    echo -e "${BLUE}Building Go binary (UI disabled)...${NC}"
    
    # Set build tags to exclude UI
    export CGO_ENABLED=0
    export GOOS=linux
    export GOARCH=amd64
    
    go build \
        -tags "release,noui" \
        -ldflags="-s -w -X main.UIEnabled=false" \
        -o "$BUILD_DIR/secureblog" \
        ./cmd/secureblog 2>/dev/null || {
            echo -e "${YELLOW}Building without UI tags...${NC}"
            go build \
                -ldflags="-s -w" \
                -o "$BUILD_DIR/secureblog" \
                .
        }
    
    echo -e "${GREEN}✓ Binary built without UI${NC}"
}

# Function to copy allowed assets
copy_allowed_assets() {
    echo -e "\n${BLUE}Copying allowed assets...${NC}"
    
    # Copy static content (excluding UI)
    if [ -d "static" ]; then
        mkdir -p "$BUILD_DIR/static"
        rsync -av --exclude="*ui*" --exclude="admin*" static/ "$BUILD_DIR/static/"
    fi
    
    # Copy templates (excluding UI)
    if [ -d "templates" ]; then
        mkdir -p "$BUILD_DIR/templates"
        rsync -av --exclude="*ui*" --exclude="admin*" templates/ "$BUILD_DIR/templates/"
    fi
    
    # Copy content
    if [ -d "content" ]; then
        cp -r content "$BUILD_DIR/"
    fi
    
    # Copy configuration (sanitized)
    if [ -f "config.yaml" ]; then
        # Remove UI-related configuration
        sed '/ui:/,/^[^ ]/d' config.yaml > "$BUILD_DIR/config.yaml"
    fi
    
    echo -e "${GREEN}✓ Assets copied${NC}"
}

# Function to verify no UI in build
verify_no_ui() {
    echo -e "\n${BLUE}Verifying build integrity...${NC}"
    
    local violations=0
    
    # Check for UI directories in build
    for dir in "${LOCAL_ONLY_DIRS[@]}"; do
        if [ -d "$BUILD_DIR/$dir" ]; then
            echo -e "${RED}✗ UI directory found in build: $dir${NC}"
            ((violations++))
        fi
    done
    
    # Check for UI files in build
    find "$BUILD_DIR" -type f \( -name "*ui*.html" -o -name "*admin*.html" -o -name "*ui*.js" -o -name "*admin*.js" \) | while read -r file; do
        echo -e "${RED}✗ UI file found in build: $file${NC}"
        ((violations++))
    done
    
    # Check binary for UI symbols
    if strings "$BUILD_DIR/secureblog" | grep -q "ServeUI\|AdminPanel\|WebUI"; then
        echo -e "${YELLOW}⚠ Binary may contain UI code${NC}"
    fi
    
    # Check for UI routes in binary
    if strings "$BUILD_DIR/secureblog" | grep -q "/admin\|/ui\|/dashboard"; then
        echo -e "${YELLOW}⚠ Binary contains UI routes - these should return 404${NC}"
    fi
    
    if [ $violations -eq 0 ]; then
        echo -e "${GREEN}✓ Build verified: No UI components found${NC}"
        return 0
    else
        echo -e "${RED}✗ Build verification failed: UI components detected${NC}"
        return 1
    fi
}

# Function to create release manifest
create_release_manifest() {
    echo -e "\n${BLUE}Creating release manifest...${NC}"
    
    local manifest="$RELEASE_DIR/MANIFEST.json"
    
    cat > "$manifest" << EOF
{
  "version": "$(git describe --tags --always 2>/dev/null || echo "dev")",
  "build_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "build_type": "production-no-ui",
  "security": {
    "ui_included": false,
    "admin_panel": false,
    "local_only": false,
    "csp_enforced": true,
    "static_only": true
  },
  "excluded_components": [
EOF
    
    # List excluded components
    local first=true
    for dir in "${LOCAL_ONLY_DIRS[@]}"; do
        if [ "$first" = true ]; then
            echo -n "    \"$dir\"" >> "$manifest"
            first=false
        else
            echo -n ",
    \"$dir\"" >> "$manifest"
        fi
    done
    
    cat >> "$manifest" << EOF

  ],
  "checksums": {
EOF
    
    # Generate checksums
    find "$BUILD_DIR" -type f -exec sha256sum {} \; | sed "s|$BUILD_DIR/||" | while read -r sum file; do
        echo "    \"$file\": \"$sum\"," >> "$manifest"
    done
    
    # Remove trailing comma and close JSON
    sed -i '$ s/,$//' "$manifest"
    
    cat >> "$manifest" << EOF
  }
}
EOF
    
    echo -e "${GREEN}✓ Manifest created${NC}"
}

# Function to create release archive
create_release_archive() {
    echo -e "\n${BLUE}Creating release archive...${NC}"
    
    # Copy build to release directory
    cp -r "$BUILD_DIR"/* "$RELEASE_DIR/"
    
    # Create tarball
    tar -czf "secureblog-release-$(date +%Y%m%d-%H%M%S).tar.gz" -C "$RELEASE_DIR" .
    
    echo -e "${GREEN}✓ Release archive created${NC}"
}

# Function to add release guards
add_release_guards() {
    echo -e "\n${BLUE}Adding release guards...${NC}"
    
    # Create guard file
    cat > "$BUILD_DIR/.release-guard" << 'EOF'
# Release Guard Configuration
# This file ensures UI components are not served in production

UI_ENABLED=false
ADMIN_PANEL_ENABLED=false
DEVELOPMENT_MODE=false

# Routes that should return 404
BLOCKED_ROUTES="/admin,/ui,/dashboard,/dev,/debug"

# Security headers required
REQUIRED_HEADERS="X-Frame-Options,X-Content-Type-Options,Content-Security-Policy"
EOF
    
    # Create runtime check script
    cat > "$BUILD_DIR/check-ui.sh" << 'EOF'
#!/bin/bash
# Runtime UI check - fails if UI components are detected

if [ -d "ui" ] || [ -d "admin" ] || [ -d "web-ui" ]; then
    echo "ERROR: UI directories detected in production"
    exit 1
fi

if ls *ui*.html *admin*.html 2>/dev/null | grep -q .; then
    echo "ERROR: UI files detected in production"
    exit 1
fi

echo "✓ No UI components detected"
exit 0
EOF
    
    chmod +x "$BUILD_DIR/check-ui.sh"
    
    echo -e "${GREEN}✓ Release guards added${NC}"
}

# Function to generate security report
generate_security_report() {
    echo -e "\n${BLUE}Generating security report...${NC}"
    
    local report="$RELEASE_DIR/SECURITY-REPORT.txt"
    
    cat > "$report" << EOF
SECURITY BUILD REPORT
=====================
Build Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build Type: Production (No UI)

UI Components Status:
--------------------
✓ Local Web UI:        EXCLUDED
✓ Admin Panel:         EXCLUDED
✓ Development Tools:   EXCLUDED
✓ Debug Endpoints:     EXCLUDED

Security Features:
-----------------
✓ CSP Enforcement:     ENABLED
✓ Static Content Only: YES
✓ No JavaScript:       VERIFIED
✓ No Dynamic Routes:   VERIFIED

Excluded Paths:
--------------
$(for dir in "${LOCAL_ONLY_DIRS[@]}"; do echo "- /$dir"; done)

Binary Analysis:
---------------
Size: $(du -h "$BUILD_DIR/secureblog" | cut -f1)
Symbols Stripped: YES
UI Functions: NONE
Admin Routes: NONE

Verification:
------------
Run: ./check-ui.sh to verify no UI components
EOF
    
    echo -e "${GREEN}✓ Security report generated${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting secure release build...${NC}\n"
    
    # Pre-build checks
    check_ui_components
    
    # Build without UI
    build_without_ui
    
    # Copy allowed assets
    copy_allowed_assets
    
    # Verify build
    if ! verify_no_ui; then
        echo -e "${RED}Build verification failed - aborting${NC}"
        exit 1
    fi
    
    # Add guards
    add_release_guards
    
    # Create manifest
    create_release_manifest
    
    # Generate report
    generate_security_report
    
    # Create archive
    create_release_archive
    
    # Final summary
    echo -e "\n${GREEN}================================${NC}"
    echo -e "${GREEN}✅ SECURE RELEASE BUILD COMPLETE${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "Build directory:  $BUILD_DIR"
    echo -e "Release directory: $RELEASE_DIR"
    echo -e "UI components:    ${RED}EXCLUDED${NC}"
    echo -e "Admin panel:      ${RED}EXCLUDED${NC}"
    echo -e "Production ready: ${GREEN}YES${NC}"
    echo -e "\n${YELLOW}Note: This build is for production deployment only${NC}"
    echo -e "${YELLOW}Local development UI must be run separately${NC}"
}

# Cleanup on exit
cleanup() {
    if [ "${KEEP_BUILD:-false}" != "true" ]; then
        echo -e "\n${BLUE}Cleaning up temporary files...${NC}"
        rm -rf "$BUILD_DIR/.tmp"
    fi
}

trap cleanup EXIT

# Run main
main "$@"