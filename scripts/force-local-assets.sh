#!/bin/bash
# Force All Assets to be Local - Block External Resources
# Implements fail-closed asset localization with comprehensive validation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTENT_DIR="${1:-content}"
TEMPLATES_DIR="${2:-templates}"
OUTPUT_DIR="${3:-dist}"
ASSETS_DIR="${4:-assets}"

echo -e "${BLUE}🔒 FORCING ALL ASSETS TO BE LOCAL${NC}"
echo "=================================="
echo "Content directory: $CONTENT_DIR"
echo "Templates directory: $TEMPLATES_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Assets directory: $ASSETS_DIR"
echo

EXTERNAL_RESOURCES=0
LOCALIZED_RESOURCES=0
FAILED_DOWNLOADS=0

# Create assets directory if it doesn't exist
mkdir -p "$ASSETS_DIR"/{images,fonts,styles,scripts}

# Function to download and localize external resources
localize_resource() {
    local url="$1"
    local file_path="$2"
    local resource_type="$3"
    
    echo "Localizing $resource_type: $url"
    
    # Determine local filename
    local filename
    filename=$(basename "$url" | sed 's/[?&].*$//')  # Remove query parameters
    
    # Add file extension if missing
    case "$resource_type" in
        "image")
            local local_path="$ASSETS_DIR/images/$filename"
            if [[ ! "$filename" =~ \.(jpg|jpeg|png|gif|webp|svg)$ ]]; then
                filename="${filename}.jpg"  # Default to jpg
                local_path="$ASSETS_DIR/images/$filename"
            fi
            ;;
        "font")
            local local_path="$ASSETS_DIR/fonts/$filename"
            if [[ ! "$filename" =~ \.(woff|woff2|ttf|otf|eot)$ ]]; then
                filename="${filename}.woff2"  # Default to woff2
                local_path="$ASSETS_DIR/fonts/$filename"
            fi
            ;;
        "style")
            local local_path="$ASSETS_DIR/styles/$filename"
            if [[ ! "$filename" =~ \.css$ ]]; then
                filename="${filename}.css"
                local_path="$ASSETS_DIR/styles/$filename"
            fi
            ;;
        *)
            echo -e "${RED}Unknown resource type: $resource_type${NC}"
            return 1
            ;;
    esac
    
    # Skip if already localized
    if [ -f "$local_path" ]; then
        echo "  ✓ Already localized: $local_path"
        return 0
    fi
    
    # Download the resource
    if curl -s -L --max-time 30 --max-filesize 10485760 -o "$local_path" "$url"; then  # 10MB max
        echo -e "${GREEN}  ✓ Downloaded: $local_path${NC}"
        
        # Validate downloaded file
        case "$resource_type" in
            "image")
                if file "$local_path" | grep -E "(JPEG|PNG|GIF|WebP)" >/dev/null; then
                    echo "  ✓ Valid image format"
                else
                    echo -e "${RED}  ✗ Invalid image format, removing${NC}"
                    rm -f "$local_path"
                    return 1
                fi
                ;;
            "font")
                if file "$local_path" | grep -E "(Web Open Font|TrueType|OpenType)" >/dev/null; then
                    echo "  ✓ Valid font format"
                else
                    echo -e "${RED}  ✗ Invalid font format, removing${NC}"
                    rm -f "$local_path"
                    return 1
                fi
                ;;
            "style")
                # Basic CSS validation
                if head -1 "$local_path" | grep -E "(^/\*|^@|^[a-zA-Z]|\.|#)" >/dev/null; then
                    echo "  ✓ Appears to be valid CSS"
                else
                    echo -e "${RED}  ✗ Does not appear to be CSS, removing${NC}"
                    rm -f "$local_path"
                    return 1
                fi
                ;;
        esac
        
        LOCALIZED_RESOURCES=$((LOCALIZED_RESOURCES + 1))
        
        # Update the file with local path
        local relative_path
        relative_path=$(realpath --relative-to="$(dirname "$file_path")" "$local_path")
        return 0
    else
        echo -e "${RED}  ✗ Failed to download: $url${NC}"
        FAILED_DOWNLOADS=$((FAILED_DOWNLOADS + 1))
        return 1
    fi
}

# Function to scan and replace external resources in a file
process_file() {
    local file="$1"
    local file_type="$2"
    
    echo "Processing $file_type: $file"
    
    local temp_file
    temp_file=$(mktemp)
    local changes_made=false
    
    # Patterns to match external resources
    case "$file_type" in
        "markdown")
            # Images in markdown: ![alt](https://example.com/image.jpg)
            while IFS= read -r line; do
                # Check for external images
                if echo "$line" | grep -E '\!\[.*\]\(https?://[^)]+\)' >/dev/null; then
                    echo "  Found external image in markdown"
                    # Extract URL and alt text
                    external_url=$(echo "$line" | sed -E 's/.*\!\[.*\]\((https?://[^)]+)\).*/\1/')
                    alt_text=$(echo "$line" | sed -E 's/.*\!\[([^]]*)\].*/\1/')
                    
                    EXTERNAL_RESOURCES=$((EXTERNAL_RESOURCES + 1))
                    
                    # Try to localize
                    if localize_resource "$external_url" "$file" "image"; then
                        # Replace with local path
                        local filename
                        filename=$(basename "$external_url" | sed 's/[?&].*$//')
                        local new_line
                        new_line=$(echo "$line" | sed -E "s|https?://[^)]+|/assets/images/$filename|")
                        echo "$new_line" >> "$temp_file"
                        changes_made=true
                        echo -e "${GREEN}  ✓ Replaced external image with local path${NC}"
                    else
                        echo -e "${RED}  ✗ Failed to localize image, build must fail${NC}"
                        rm -f "$temp_file"
                        return 1
                    fi
                else
                    echo "$line" >> "$temp_file"
                fi
            done < "$file"
            ;;
            
        "html"|"template")
            # Images: <img src="https://..."
            # Stylesheets: <link rel="stylesheet" href="https://..."
            # Fonts: Various font loading patterns
            
            while IFS= read -r line; do
                original_line="$line"
                
                # Check for external images
                if echo "$line" | grep -E '<img[^>]+src=["\']https?://[^"'\'']+["\']' >/dev/null; then
                    echo "  Found external image in HTML"
                    external_url=$(echo "$line" | sed -E 's/.*src=["\'"'"']([^"'\'']+)["\'"'"'].*/\1/')
                    
                    EXTERNAL_RESOURCES=$((EXTERNAL_RESOURCES + 1))
                    
                    if localize_resource "$external_url" "$file" "image"; then
                        filename=$(basename "$external_url" | sed 's/[?&].*$//')
                        line=$(echo "$line" | sed -E "s|src=[\"']https?://[^\"']+[\"']|src=\"/assets/images/$filename\"|")
                        changes_made=true
                        echo -e "${GREEN}  ✓ Replaced external image src${NC}"
                    else
                        echo -e "${RED}  ✗ Failed to localize image, build must fail${NC}"
                        rm -f "$temp_file"
                        return 1
                    fi
                fi
                
                # Check for external stylesheets
                if echo "$line" | grep -E '<link[^>]+href=["\']https?://[^"'\'']+["\'][^>]*rel=["\']stylesheet["\']' >/dev/null || \
                   echo "$line" | grep -E '<link[^>]+rel=["\']stylesheet["\'][^>]*href=["\']https?://[^"'\'']+["\']' >/dev/null; then
                    echo "  Found external stylesheet"
                    external_url=$(echo "$line" | sed -E 's/.*href=["\'"'"']([^"'\'']+)["\'"'"'].*/\1/')
                    
                    EXTERNAL_RESOURCES=$((EXTERNAL_RESOURCES + 1))
                    
                    if localize_resource "$external_url" "$file" "style"; then
                        filename=$(basename "$external_url" | sed 's/[?&].*$//')
                        if [[ ! "$filename" =~ \.css$ ]]; then
                            filename="${filename}.css"
                        fi
                        line=$(echo "$line" | sed -E "s|href=[\"']https?://[^\"']+[\"']|href=\"/assets/styles/$filename\"|")
                        changes_made=true
                        echo -e "${GREEN}  ✓ Replaced external stylesheet href${NC}"
                    else
                        echo -e "${RED}  ✗ Failed to localize stylesheet, build must fail${NC}"
                        rm -f "$temp_file"
                        return 1
                    fi
                fi
                
                # Check for external fonts (Google Fonts, etc.)
                if echo "$line" | grep -E 'href=["\']https?://fonts\.' >/dev/null; then
                    echo -e "${RED}  ✗ External font loading detected: Google Fonts or similar${NC}"
                    echo "  External fonts are not allowed for privacy and security"
                    echo "  Please download and host fonts locally"
                    rm -f "$temp_file"
                    return 1
                fi
                
                # Check for any other external resource loading
                if echo "$line" | grep -E '(src|href)=["\']https?://' >/dev/null && \
                   ! echo "$line" | grep -E 'rel=["\']nofollow' >/dev/null; then
                    echo -e "${YELLOW}  ⚠ Other external resource detected:${NC}"
                    echo "    $line"
                    echo "  This may need manual review"
                fi
                
                echo "$line" >> "$temp_file"
            done < "$file"
            ;;
    esac
    
    # Replace original file if changes were made
    if [ "$changes_made" = true ]; then
        mv "$temp_file" "$file"
        echo -e "${GREEN}  ✓ Updated file with local asset references${NC}"
    else
        rm -f "$temp_file"
    fi
    
    return 0
}

# Function to validate CSP compliance
validate_csp_compliance() {
    echo -e "${BLUE}Validating CSP compliance...${NC}"
    
    # Expected CSP policy
    local expected_csp="default-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; frame-ancestors 'none'; base-uri 'none'"
    
    echo "Expected CSP: $expected_csp"
    
    # Check all HTML files for external resource violations
    local violations=0
    
    find "$OUTPUT_DIR" -name "*.html" -type f | while read html_file; do
        echo "Checking CSP compliance: $html_file"
        
        # Check for violations
        if grep -E '(src|href)=["\']https?://' "$html_file" | grep -v 'rel="nofollow"' >/dev/null; then
            echo -e "${RED}  ✗ External resource found in final output:${NC}"
            grep -n -E '(src|href)=["\']https?://' "$html_file" | grep -v 'rel="nofollow"'
            violations=$((violations + 1))
        fi
        
        # Check for inline styles (should be minimal)
        if grep -E 'style=["\']' "$html_file" >/dev/null; then
            echo -e "${YELLOW}  ⚠ Inline styles found (may violate CSP):${NC}"
            grep -n -E 'style=["\']' "$html_file" | head -3
        fi
        
        # Check for data URLs (should be minimal and safe)
        if grep -E 'data:[^,]*javascript' "$html_file" >/dev/null; then
            echo -e "${RED}  ✗ Dangerous data URL found:${NC}"
            grep -n -E 'data:[^,]*javascript' "$html_file"
            violations=$((violations + 1))
        fi
    done
    
    return $violations
}

# Main processing
echo -e "${BLUE}1. Processing Markdown Files...${NC}"

if [ -d "$CONTENT_DIR" ]; then
    find "$CONTENT_DIR" -name "*.md" -type f | while read md_file; do
        if ! process_file "$md_file" "markdown"; then
            echo -e "${RED}Failed to process: $md_file${NC}"
            exit 1
        fi
    done
else
    echo "No content directory found"
fi

echo -e "${BLUE}2. Processing Template Files...${NC}"

if [ -d "$TEMPLATES_DIR" ]; then
    find "$TEMPLATES_DIR" -name "*.html" -o -name "*.htm" | while read template_file; do
        if ! process_file "$template_file" "template"; then
            echo -e "${RED}Failed to process: $template_file${NC}"
            exit 1
        fi
    done
else
    echo "No templates directory found"
fi

echo -e "${BLUE}3. Generating Asset Manifest...${NC}"

# Create asset manifest for integrity checking
cat > "$ASSETS_DIR/manifest.json" << EOF
{
  "generated": "$(date -Iseconds)",
  "assets": {
    "images": [$(find "$ASSETS_DIR/images" -type f -exec basename {} \; 2>/dev/null | sed 's/.*/"&"/' | paste -sd, -)],
    "fonts": [$(find "$ASSETS_DIR/fonts" -type f -exec basename {} \; 2>/dev/null | sed 's/.*/"&"/' | paste -sd, -)],
    "styles": [$(find "$ASSETS_DIR/styles" -type f -exec basename {} \; 2>/dev/null | sed 's/.*/"&"/' | paste -sd, -)]
  },
  "summary": {
    "external_resources_found": $EXTERNAL_RESOURCES,
    "localized_resources": $LOCALIZED_RESOURCES,
    "failed_downloads": $FAILED_DOWNLOADS
  }
}
EOF

echo -e "${GREEN}   ✓ Asset manifest created${NC}"

echo -e "${BLUE}4. Final Validation...${NC}"

# Validate that no external resources remain
final_violations=0

echo "Scanning for remaining external resources..."
if find "$CONTENT_DIR" "$TEMPLATES_DIR" -name "*.md" -o -name "*.html" -o -name "*.htm" | xargs grep -l 'https://' 2>/dev/null | head -1 > /dev/null; then
    echo -e "${RED}External resources still found in source files:${NC}"
    find "$CONTENT_DIR" "$TEMPLATES_DIR" -name "*.md" -o -name "*.html" -o -name "*.htm" | xargs grep -n 'https://' 2>/dev/null | head -10
    final_violations=$((final_violations + 1))
fi

# Check if build output exists and validate it too
if [ -d "$OUTPUT_DIR" ]; then
    if ! validate_csp_compliance; then
        final_violations=$((final_violations + 1))
    fi
fi

echo
echo -e "${BLUE}ASSET LOCALIZATION REPORT${NC}"
echo "=========================="
echo "External resources found: $EXTERNAL_RESOURCES"
echo -e "Successfully localized: ${GREEN}$LOCALIZED_RESOURCES${NC}"
echo -e "Failed downloads: ${RED}$FAILED_DOWNLOADS${NC}"

if [ -f "$ASSETS_DIR/manifest.json" ]; then
    echo
    echo "Asset manifest:"
    cat "$ASSETS_DIR/manifest.json" | jq '.'
fi

if [ $final_violations -gt 0 ] || [ $FAILED_DOWNLOADS -gt 0 ]; then
    echo
    echo -e "${RED}❌ ASSET LOCALIZATION FAILED${NC}"
    echo "External resources remain or downloads failed."
    echo "Build MUST fail to prevent external resource loading."
    echo
    echo "🔧 To fix:"
    echo "1. Download external resources manually to assets/ directory"
    echo "2. Update references in content/templates to use local paths"
    echo "3. Use only self-hosted assets for maximum security and privacy"
    exit 1
else
    echo
    echo -e "${GREEN}✅ ALL ASSETS SUCCESSFULLY LOCALIZED${NC}"
    echo "No external resources found, site is fully self-contained."
    echo "CSP policy 'img-src self; style-src self; font-src self' will be enforced."
    exit 0
fi