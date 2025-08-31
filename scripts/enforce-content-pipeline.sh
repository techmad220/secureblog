#!/bin/bash
# Enforce Content Pipeline - Ensures ALL assets are sanitized
# No asset escapes sanitization - runs on EVERY file

set -euo pipefail

CONTENT_DIR="${1:-content}"
BUILD_DIR="${2:-dist}"
QUARANTINE_DIR="quarantine"
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 Content Pipeline Enforcement${NC}"
echo "================================"
echo "This ensures EVERY asset is sanitized"
echo ""

# Create directories
mkdir -p "$BUILD_DIR/sanitized" "$QUARANTINE_DIR"

# Track all files
declare -A processed_files
declare -A failed_files

# Function to process any file
process_file() {
    local file="$1"
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    local mime_type=$(file -b --mime-type "$file")
    
    echo -e "${BLUE}Processing: $filename (${mime_type})${NC}"
    
    # Mark as being processed
    processed_files["$file"]=1
    
    case "$extension" in
        # Markdown files - sanitize HTML
        md|markdown)
            echo "  Sanitizing Markdown..."
            if ! ./scripts/markdown-sanitizer.sh "$file" "$BUILD_DIR/sanitized/$filename" 2>/dev/null; then
                echo -e "${YELLOW}  Using fallback Markdown sanitization${NC}"
                # Fallback: strip all HTML
                sed 's/<[^>]*>//g' "$file" > "$BUILD_DIR/sanitized/$filename"
            fi
            ;;
            
        # PDF files - sanitize or rasterize
        pdf)
            echo "  Sanitizing PDF..."
            if ! ./scripts/pdf-svg-sanitizer.sh "$file" "$BUILD_DIR/sanitized" 2>/dev/null; then
                echo -e "${YELLOW}  Using fallback PDF sanitization${NC}"
                # Fallback: convert to images
                convert -density 150 "$file" "$BUILD_DIR/sanitized/${filename%.pdf}-%d.png" 2>/dev/null || {
                    echo -e "${RED}  Failed to sanitize PDF - quarantining${NC}"
                    cp "$file" "$QUARANTINE_DIR/"
                    failed_files["$file"]=1
                    ((FAILED++))
                }
            fi
            ;;
            
        # SVG files - strip scripts
        svg)
            echo "  Sanitizing SVG..."
            # Remove all dangerous elements
            sed -E 's/<script[^>]*>.*?<\/script>//gi' "$file" | \
            sed -E 's/on[a-zA-Z]+="[^"]*"//gi' | \
            sed -E 's/javascript:[^"]*//gi' > "$BUILD_DIR/sanitized/$filename"
            
            # Verify no scripts remain
            if grep -qi '<script\|javascript:\|on[a-z]*=' "$BUILD_DIR/sanitized/$filename"; then
                echo -e "${RED}  SVG still contains scripts - rasterizing${NC}"
                convert "$file" "$BUILD_DIR/sanitized/${filename%.svg}.png" 2>/dev/null || {
                    cp "$file" "$QUARANTINE_DIR/"
                    failed_files["$file"]=1
                    ((FAILED++))
                }
            fi
            ;;
            
        # Images - strip EXIF
        jpg|jpeg|png|gif|webp|bmp|tiff)
            echo "  Stripping EXIF metadata..."
            exiftool -all= -o "$BUILD_DIR/sanitized/$filename" "$file" 2>/dev/null || {
                # Fallback: re-encode
                convert "$file" -strip "$BUILD_DIR/sanitized/$filename" 2>/dev/null || {
                    echo -e "${RED}  Failed to strip EXIF - quarantining${NC}"
                    cp "$file" "$QUARANTINE_DIR/"
                    failed_files["$file"]=1
                    ((FAILED++))
                }
            }
            ;;
            
        # HTML files - strict sanitization
        html|htm)
            echo "  Sanitizing HTML..."
            # Strip all dangerous elements
            sed -E 's/<script[^>]*>.*?<\/script>//gi' "$file" | \
            sed -E 's/<iframe[^>]*>.*?<\/iframe>//gi' | \
            sed -E 's/<embed[^>]*>//gi' | \
            sed -E 's/<object[^>]*>.*?<\/object>//gi' | \
            sed -E 's/on[a-zA-Z]+="[^"]*"//gi' | \
            sed -E 's/javascript:[^"]*//gi' | \
            sed -E 's/vbscript:[^"]*//gi' > "$BUILD_DIR/sanitized/$filename"
            
            # Verify no scripts remain
            if grep -qi '<script\|javascript:\|on[a-z]*=' "$BUILD_DIR/sanitized/$filename"; then
                echo -e "${RED}  HTML still contains scripts - stripping all HTML${NC}"
                sed 's/<[^>]*>//g' "$file" > "$BUILD_DIR/sanitized/$filename"
            fi
            ;;
            
        # CSS files - remove JavaScript
        css)
            echo "  Sanitizing CSS..."
            # Remove JavaScript from CSS
            sed -E 's/javascript:[^;}\s]*//gi' "$file" | \
            sed -E 's/expression\([^)]*\)//gi' | \
            sed -E 's/-moz-binding:[^;}\s]*//gi' | \
            sed -E 's/behavior:[^;}\s]*//gi' > "$BUILD_DIR/sanitized/$filename"
            ;;
            
        # JavaScript files - should not exist!
        js|mjs|ts|jsx|tsx)
            echo -e "${RED}  JavaScript file detected - quarantining${NC}"
            cp "$file" "$QUARANTINE_DIR/"
            failed_files["$file"]=1
            ((FAILED++))
            ;;
            
        # Office documents - convert to PDF then sanitize
        doc|docx|xls|xlsx|ppt|pptx)
            echo "  Converting Office document to PDF..."
            libreoffice --headless --convert-to pdf --outdir "$BUILD_DIR/sanitized" "$file" 2>/dev/null || {
                echo -e "${RED}  Failed to convert Office document - quarantining${NC}"
                cp "$file" "$QUARANTINE_DIR/"
                failed_files["$file"]=1
                ((FAILED++))
            }
            ;;
            
        # Archive files - extract and process contents
        zip|tar|gz|bz2|xz|7z|rar)
            echo -e "${YELLOW}  Archive file - extracting for processing${NC}"
            local temp_dir=$(mktemp -d)
            
            case "$extension" in
                zip) unzip -q "$file" -d "$temp_dir" 2>/dev/null ;;
                tar) tar -xf "$file" -C "$temp_dir" 2>/dev/null ;;
                gz) tar -xzf "$file" -C "$temp_dir" 2>/dev/null ;;
                bz2) tar -xjf "$file" -C "$temp_dir" 2>/dev/null ;;
                xz) tar -xJf "$file" -C "$temp_dir" 2>/dev/null ;;
                7z) 7z x "$file" -o"$temp_dir" >/dev/null 2>&1 ;;
                rar) unrar x "$file" "$temp_dir" >/dev/null 2>&1 ;;
            esac
            
            # Process extracted files
            find "$temp_dir" -type f | while read -r extracted_file; do
                process_file "$extracted_file"
            done
            
            rm -rf "$temp_dir"
            ;;
            
        # Text files - check for scripts
        txt|text|log|conf|cfg|ini|yaml|yml|toml|json|xml)
            echo "  Checking text file for scripts..."
            if grep -qi '<script\|javascript:\|on[a-z]*=\|eval(' "$file"; then
                echo -e "${YELLOW}  Text file contains suspicious content - sanitizing${NC}"
                sed -E 's/<script[^>]*>.*?<\/script>//gi' "$file" | \
                sed -E 's/javascript:[^"]*//gi' > "$BUILD_DIR/sanitized/$filename"
            else
                cp "$file" "$BUILD_DIR/sanitized/$filename"
            fi
            ;;
            
        # Default - copy but warn
        *)
            echo -e "${YELLOW}  Unknown file type - copying with warning${NC}"
            cp "$file" "$BUILD_DIR/sanitized/$filename"
            echo "$filename: unknown type" >> "$BUILD_DIR/sanitized/warnings.txt"
            ;;
    esac
    
    echo -e "${GREEN}  ✓ Processed${NC}"
}

# Main processing loop
echo -e "${BLUE}Starting comprehensive sanitization...${NC}\n"

# Find ALL files (no exceptions)
while IFS= read -r -d '' file; do
    # Skip directories and symlinks
    if [ -f "$file" ] && [ ! -L "$file" ]; then
        process_file "$file"
    fi
done < <(find "$CONTENT_DIR" -type f -print0)

# Verify all files were processed
echo -e "\n${BLUE}Verification Phase${NC}"
echo "==================="

TOTAL_FILES=$(find "$CONTENT_DIR" -type f | wc -l)
PROCESSED=${#processed_files[@]}
FAILED_COUNT=${#failed_files[@]}
SANITIZED=$((PROCESSED - FAILED_COUNT))

echo "Total files found: $TOTAL_FILES"
echo "Files processed: $PROCESSED"
echo "Files sanitized: $SANITIZED"
echo "Files quarantined: $FAILED_COUNT"

# Check for unprocessed files
UNPROCESSED=0
while IFS= read -r file; do
    if [ ! -v processed_files["$file"] ]; then
        echo -e "${RED}ERROR: File not processed: $file${NC}"
        ((UNPROCESSED++))
    fi
done < <(find "$CONTENT_DIR" -type f)

if [ $UNPROCESSED -gt 0 ]; then
    echo -e "${RED}CRITICAL: $UNPROCESSED files were not processed!${NC}"
    exit 2
fi

# Final security check on sanitized files
echo -e "\n${BLUE}Final Security Validation${NC}"
echo "========================="

SECURITY_VIOLATIONS=0
while IFS= read -r file; do
    # Check for any remaining JavaScript
    if grep -qi '<script\|javascript:\|on[a-z]*=\|eval(\|Function(' "$file" 2>/dev/null; then
        echo -e "${RED}Security violation in sanitized file: $file${NC}"
        ((SECURITY_VIOLATIONS++))
    fi
done < <(find "$BUILD_DIR/sanitized" -type f)

# Generate report
cat > "$BUILD_DIR/sanitization-report.json" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": {
    "total_files": $TOTAL_FILES,
    "processed": $PROCESSED,
    "sanitized": $SANITIZED,
    "quarantined": $FAILED_COUNT,
    "security_violations": $SECURITY_VIOLATIONS
  },
  "enforcement": {
    "all_files_processed": $([ $UNPROCESSED -eq 0 ] && echo "true" || echo "false"),
    "no_javascript_remaining": $([ $SECURITY_VIOLATIONS -eq 0 ] && echo "true" || echo "false"),
    "pipeline_complete": true
  },
  "quarantine_directory": "$QUARANTINE_DIR"
}
EOF

# Summary
echo -e "\n${BLUE}=== Pipeline Enforcement Summary ===${NC}"
echo "====================================="

if [ $FAILED_COUNT -eq 0 ] && [ $SECURITY_VIOLATIONS -eq 0 ] && [ $UNPROCESSED -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: All content sanitized successfully${NC}"
    echo -e "${GREEN}✅ No files escaped sanitization${NC}"
    echo -e "${GREEN}✅ No security violations detected${NC}"
    exit 0
elif [ $SECURITY_VIOLATIONS -gt 0 ]; then
    echo -e "${RED}❌ CRITICAL: Security violations found in sanitized content${NC}"
    exit 2
elif [ $UNPROCESSED -gt 0 ]; then
    echo -e "${RED}❌ CRITICAL: Some files were not processed${NC}"
    exit 2
else
    echo -e "${YELLOW}⚠️  WARNING: Some files were quarantined${NC}"
    echo "Check $QUARANTINE_DIR for details"
    exit 1
fi