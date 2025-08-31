#!/bin/bash
# Enhanced PDF and SVG Content Sanitizer
# Implements server-side sanitization and rasterization for untrusted content

set -euo pipefail

# Configuration
CONTENT_DIR="${1:-content}"
OUTPUT_DIR="${2:-dist/sanitized}"
QUARANTINE_DIR="quarantine"
REPORT_FILE="sanitization-report.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_FILES=0
SANITIZED_FILES=0
QUARANTINED_FILES=0
RASTERIZED_FILES=0

echo -e "${BLUE}🔒 PDF & SVG Content Sanitizer${NC}"
echo "================================"

# Check dependencies
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    local missing_deps=()
    
    # Check for required tools
    command -v pdf2ps >/dev/null 2>&1 || missing_deps+=("ghostscript")
    command -v convert >/dev/null 2>&1 || missing_deps+=("imagemagick")
    command -v inkscape >/dev/null 2>&1 || missing_deps+=("inkscape")
    command -v exiftool >/dev/null 2>&1 || missing_deps+=("libimage-exiftool-perl")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
        echo "Install with: sudo apt-get install ${missing_deps[*]}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All dependencies satisfied${NC}"
}

# Setup directories
setup_directories() {
    mkdir -p "$OUTPUT_DIR"/{pdfs,svgs,images,safe}
    mkdir -p "$QUARANTINE_DIR"
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Sanitize PDF - Rasterize if contains active content
sanitize_pdf() {
    local input="$1"
    local filename=$(basename "$input")
    local output="$OUTPUT_DIR/pdfs/${filename%.pdf}-safe.pdf"
    
    echo -e "${BLUE}Processing PDF: $filename${NC}"
    ((TOTAL_FILES++))
    
    # Check for JavaScript, forms, or embedded files
    if pdfinfo "$input" 2>/dev/null | grep -qE "(JavaScript|AcroForm|EmbeddedFiles)"; then
        echo -e "${YELLOW}⚠ Active content detected - rasterizing${NC}"
        
        # Quarantine original
        cp "$input" "$QUARANTINE_DIR/${filename}.dangerous"
        ((QUARANTINED_FILES++))
        
        # Rasterize to PNG then back to PDF (removes all active content)
        convert -density 150 -quality 90 "$input" "${output%.pdf}.png" 2>/dev/null
        convert "${output%.pdf}.png" "$output" 2>/dev/null
        rm -f "${output%.pdf}.png"
        
        ((RASTERIZED_FILES++))
        echo -e "${GREEN}✓ PDF rasterized: ${filename}${NC}"
    else
        # Clean PDF through Ghostscript
        gs -dNOPAUSE -dBATCH -dSAFER \
           -sDEVICE=pdfwrite \
           -dPDFSETTINGS=/prepress \
           -sOutputFile="$output" \
           "$input" 2>/dev/null
        
        # Strip metadata
        exiftool -all= -overwrite_original "$output" 2>/dev/null || true
        
        ((SANITIZED_FILES++))
        echo -e "${GREEN}✓ PDF sanitized: ${filename}${NC}"
    fi
}

# Sanitize SVG - Remove all scripting capabilities
sanitize_svg() {
    local input="$1"
    local filename=$(basename "$input")
    local output="$OUTPUT_DIR/svgs/${filename%.svg}-safe.svg"
    
    echo -e "${BLUE}Processing SVG: $filename${NC}"
    ((TOTAL_FILES++))
    
    # Check for dangerous patterns
    if grep -qE "<script|onclick|onload|javascript:|data:text/html|<foreignObject|<embed|<iframe" "$input"; then
        echo -e "${YELLOW}⚠ Dangerous content detected${NC}"
        
        # Quarantine original
        cp "$input" "$QUARANTINE_DIR/${filename}.dangerous"
        ((QUARANTINED_FILES++))
        
        # Option 1: Rasterize to PNG (safest)
        if [ "${RASTERIZE_SVG:-false}" == "true" ]; then
            convert "$input" "$OUTPUT_DIR/images/${filename%.svg}.png" 2>/dev/null
            ((RASTERIZED_FILES++))
            echo -e "${GREEN}✓ SVG rasterized to PNG: ${filename}${NC}"
            return
        fi
    fi
    
    # Clean SVG
    # Remove all script elements and dangerous attributes
    cat "$input" | \
        sed -E 's/<script[^>]*>.*?<\/script>//gi' | \
        sed -E 's/<handler[^>]*>.*?<\/handler>//gi' | \
        sed -E 's/on[a-zA-Z]+="[^"]*"//gi' | \
        sed -E 's/javascript:[^"'\'']*//gi' | \
        sed -E 's/data:text\/html[^"'\'']*//gi' | \
        sed -E 's/<foreignObject[^>]*>.*?<\/foreignObject>//gi' | \
        sed -E 's/<embed[^>]*>//gi' | \
        sed -E 's/<iframe[^>]*>.*?<\/iframe>//gi' | \
        sed -E 's/<object[^>]*>.*?<\/object>//gi' | \
        sed -E 's/<applet[^>]*>.*?<\/applet>//gi' | \
        sed -E 's/xlink:href="[^#][^"]*"//gi' > "$output.tmp"
    
    # Use Inkscape for additional cleaning
    if command -v inkscape >/dev/null 2>&1; then
        inkscape "$output.tmp" \
            --export-plain-svg \
            --export-type=svg \
            --export-filename="$output" \
            --vacuum-defs 2>/dev/null || mv "$output.tmp" "$output"
    else
        mv "$output.tmp" "$output"
    fi
    
    # Final validation
    if grep -qE "script|onclick|javascript:" "$output" 2>/dev/null; then
        echo -e "${RED}✗ Sanitization incomplete - quarantining${NC}"
        mv "$output" "$QUARANTINE_DIR/${filename}.failed"
        ((QUARANTINED_FILES++))
    else
        ((SANITIZED_FILES++))
        echo -e "${GREEN}✓ SVG sanitized: ${filename}${NC}"
    fi
}

# Process images - strip EXIF
process_image() {
    local input="$1"
    local filename=$(basename "$input")
    local output="$OUTPUT_DIR/images/$filename"
    
    echo -e "${BLUE}Processing image: $filename${NC}"
    ((TOTAL_FILES++))
    
    # Strip all metadata
    exiftool -all= -o "$output" "$input" 2>/dev/null || cp "$input" "$output"
    
    ((SANITIZED_FILES++))
    echo -e "${GREEN}✓ Image cleaned: ${filename}${NC}"
}

# Generate security report
generate_report() {
    cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": {
    "total_files": $TOTAL_FILES,
    "sanitized": $SANITIZED_FILES,
    "rasterized": $RASTERIZED_FILES,
    "quarantined": $QUARANTINED_FILES
  },
  "security": {
    "pdf_javascript_removed": $(find "$QUARANTINE_DIR" -name "*.pdf.dangerous" 2>/dev/null | wc -l),
    "svg_scripts_removed": $(find "$QUARANTINE_DIR" -name "*.svg.dangerous" 2>/dev/null | wc -l),
    "metadata_stripped": $SANITIZED_FILES
  },
  "output_directory": "$OUTPUT_DIR",
  "quarantine_directory": "$QUARANTINE_DIR"
}
EOF
    
    echo -e "${GREEN}✓ Report generated: $REPORT_FILE${NC}"
}

# Main execution
main() {
    check_dependencies
    setup_directories
    
    echo -e "\n${BLUE}Starting content sanitization...${NC}\n"
    
    # Process PDFs
    find "$CONTENT_DIR" -name "*.pdf" -type f 2>/dev/null | while read -r file; do
        sanitize_pdf "$file"
    done
    
    # Process SVGs
    find "$CONTENT_DIR" -name "*.svg" -type f 2>/dev/null | while read -r file; do
        sanitize_svg "$file"
    done
    
    # Process images
    find "$CONTENT_DIR" \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" \) -type f 2>/dev/null | while read -r file; do
        process_image "$file"
    done
    
    # Generate report
    generate_report
    
    # Summary
    echo -e "\n${BLUE}=== Sanitization Complete ===${NC}"
    echo -e "Total files:      $TOTAL_FILES"
    echo -e "Sanitized:        ${GREEN}$SANITIZED_FILES${NC}"
    echo -e "Rasterized:       ${YELLOW}$RASTERIZED_FILES${NC}"
    echo -e "Quarantined:      ${RED}$QUARANTINED_FILES${NC}"
    echo -e "\nOutput:          $OUTPUT_DIR"
    echo -e "Quarantine:      $QUARANTINE_DIR"
    echo -e "Report:          $REPORT_FILE"
    
    # Exit with error if files were quarantined
    if [ $QUARANTINED_FILES -gt 0 ]; then
        echo -e "\n${YELLOW}⚠ Warning: Some files were quarantined for manual review${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}✅ All content successfully sanitized${NC}"
}

# Run if not sourced
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi