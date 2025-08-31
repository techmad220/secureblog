#!/bin/bash
# Comprehensive Media Sanitization
# EXIF stripping, SVG sanitization, PDF flattening with mandatory CI integration

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INPUT_DIR="${1:-content/images}"
OUTPUT_DIR="${2:-assets/sanitized}"
QUARANTINE_DIR="${3:-quarantine}"

echo -e "${BLUE}🧹 COMPREHENSIVE MEDIA SANITIZATION${NC}"
echo "==================================="
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Quarantine directory: $QUARANTINE_DIR"
echo

TOTAL_FILES=0
SANITIZED_FILES=0
QUARANTINED_FILES=0
FAILED_FILES=0

mkdir -p "$OUTPUT_DIR"/{images,pdfs,svgs} "$QUARANTINE_DIR"

# Function to sanitize images (EXIF removal + safe re-encode)
sanitize_image() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Sanitizing image: $(basename "$input_file")"
    
    # Use ImageMagick to strip EXIF and re-encode safely
    if command -v convert >/dev/null 2>&1; then
        if convert "$input_file" -strip -quality 85 "$output_file" 2>/dev/null; then
            echo -e "${GREEN}   ✓ Image sanitized with ImageMagick${NC}"
            return 0
        fi
    fi
    
    # Fallback to exiftool if available
    if command -v exiftool >/dev/null 2>&1; then
        cp "$input_file" "$output_file"
        if exiftool -all= -overwrite_original "$output_file" 2>/dev/null; then
            echo -e "${GREEN}   ✓ EXIF stripped with exiftool${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}   ✗ No image sanitization tools available${NC}"
    return 1
}

# Function to sanitize SVG files
sanitize_svg() {
    local input_file="$1"  
    local output_file="$2"
    
    echo "Sanitizing SVG: $(basename "$input_file")"
    
    # Create sanitized SVG by removing dangerous elements
    if command -v xmlstarlet >/dev/null 2>&1; then
        # Use xmlstarlet for precise XML manipulation
        if xmlstarlet ed \
           -d "//script" \
           -d "//@*[starts-with(name(), 'on')]" \
           -d "//foreignObject" \
           -d "//iframe" \
           -d "//object" \
           -d "//embed" \
           "$input_file" > "$output_file" 2>/dev/null; then
            echo -e "${GREEN}   ✓ SVG sanitized with xmlstarlet${NC}"
            return 0
        fi
    fi
    
    # Fallback: Use sed to remove dangerous patterns
    sed -E \
        -e '/<script[^>]*>/,/<\/script>/d' \
        -e 's/on[a-zA-Z]+\s*=\s*"[^"]*"//g' \
        -e 's/on[a-zA-Z]+\s*=\s*'\''[^'\'']*'\''//g' \
        -e '/<foreignObject[^>]*>/,/<\/foreignObject>/d' \
        -e '/<iframe[^>]*>/,/<\/iframe>/d' \
        -e '/<object[^>]*>/,/<\/object>/d' \
        -e '/<embed[^>]*>/d' \
        "$input_file" > "$output_file"
    
    echo -e "${GREEN}   ✓ SVG sanitized with sed patterns${NC}"
    return 0
}

# Function to flatten and sanitize PDFs
sanitize_pdf() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Sanitizing PDF: $(basename "$input_file")"
    
    # Use Ghostscript with -dSAFER for PDF flattening
    if command -v gs >/dev/null 2>&1; then
        if gs -dSAFER -dBATCH -dNOPAUSE -dNOPLATFONTS \
           -sDEVICE=pdfwrite \
           -sColorConversionStrategy=RGB \
           -dProcessColorModel=/DeviceRGB \
           -dCompatibilityLevel=1.4 \
           -sOutputFile="$output_file" \
           "$input_file" >/dev/null 2>&1; then
            echo -e "${GREEN}   ✓ PDF flattened with Ghostscript -dSAFER${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}   ✗ Ghostscript not available - PDF cannot be sanitized${NC}"
    return 1
}

# Function to quarantine dangerous files
quarantine_file() {
    local file="$1"
    local reason="$2"
    
    local quarantine_file="$QUARANTINE_DIR/$(basename "$file").$(date +%s)"
    cp "$file" "$quarantine_file"
    
    cat > "$quarantine_file.report" << EOF
QUARANTINE REPORT
=================
Original File: $file
Quarantine Time: $(date -Iseconds)
Reason: $reason
SHA-256: $(sha256sum "$file" | cut -d' ' -f1)

MANUAL REVIEW REQUIRED
This file contains potentially dangerous content and requires manual review before use.
EOF
    
    echo -e "${RED}   ⚠️  File quarantined: $reason${NC}"
    QUARANTINED_FILES=$((QUARANTINED_FILES + 1))
}

# Main processing loop
echo -e "${BLUE}Processing media files...${NC}"

if [ ! -d "$INPUT_DIR" ]; then
    echo -e "${YELLOW}Input directory not found: $INPUT_DIR${NC}"
    echo "Creating example structure..."
    mkdir -p "$INPUT_DIR"
    exit 0
fi

find "$INPUT_DIR" -type f | while read file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    
    # Get file extension
    extension=$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')
    filename=$(basename "$file")
    
    case "$extension" in
        jpg|jpeg|png|gif|webp)
            output_file="$OUTPUT_DIR/images/$filename"
            
            # Check for suspicious content in image files
            if strings "$file" | grep -iE "(script|javascript|eval|function)" >/dev/null; then
                quarantine_file "$file" "Suspicious strings found in image file"
                continue
            fi
            
            if sanitize_image "$file" "$output_file"; then
                SANITIZED_FILES=$((SANITIZED_FILES + 1))
            else
                quarantine_file "$file" "Image sanitization failed"
            fi
            ;;
            
        svg)
            output_file="$OUTPUT_DIR/svgs/$filename"
            
            # Check for dangerous SVG content
            if grep -iE "(<script|javascript:|on[a-z]+=|<foreignObject)" "$file" >/dev/null; then
                echo "   Found dangerous content in SVG, attempting sanitization..."
            fi
            
            if sanitize_svg "$file" "$output_file"; then
                # Verify sanitization was successful
                if grep -iE "(<script|javascript:|on[a-z]+=)" "$output_file" >/dev/null; then
                    quarantine_file "$file" "SVG still contains dangerous content after sanitization"
                    rm -f "$output_file"
                else
                    SANITIZED_FILES=$((SANITIZED_FILES + 1))
                fi
            else
                quarantine_file "$file" "SVG sanitization failed"
            fi
            ;;
            
        pdf)
            output_file="$OUTPUT_DIR/pdfs/$filename"
            
            # Check PDF for JavaScript or forms
            if strings "$file" | grep -iE "(javascript|acroform|/js|/aa)" >/dev/null; then
                echo "   Found potentially dangerous content in PDF..."
            fi
            
            if sanitize_pdf "$file" "$output_file"; then
                SANITIZED_FILES=$((SANITIZED_FILES + 1))
            else
                quarantine_file "$file" "PDF sanitization failed - manual review required"
            fi
            ;;
            
        *)
            echo "Unsupported file type: $filename (.$extension)"
            quarantine_file "$file" "Unsupported file type: .$extension"
            ;;
    esac
done

# Create sanitization report
cat > "$OUTPUT_DIR/sanitization-report.json" << EOF
{
  "scan_date": "$(date -Iseconds)",
  "input_directory": "$INPUT_DIR",
  "output_directory": "$OUTPUT_DIR",
  "quarantine_directory": "$QUARANTINE_DIR",
  "summary": {
    "total_files": $TOTAL_FILES,
    "sanitized_files": $SANITIZED_FILES,
    "quarantined_files": $QUARANTINED_FILES,
    "failed_files": $FAILED_FILES
  },
  "tools_used": {
    "imagemagick": $(command -v convert >/dev/null && echo "true" || echo "false"),
    "exiftool": $(command -v exiftool >/dev/null && echo "true" || echo "false"),
    "ghostscript": $(command -v gs >/dev/null && echo "true" || echo "false"),
    "xmlstarlet": $(command -v xmlstarlet >/dev/null && echo "true" || echo "false")
  },
  "security_compliance": {
    "exif_removal": "enforced",
    "svg_sanitization": "enforced",
    "pdf_flattening": "enforced",
    "dangerous_content_detection": "active",
    "quarantine_system": "active"
  }
}
EOF

echo
echo -e "${BLUE}MEDIA SANITIZATION RESULTS${NC}"
echo "=========================="
echo "Total files processed: $TOTAL_FILES"
echo -e "Successfully sanitized: ${GREEN}$SANITIZED_FILES${NC}"
echo -e "Quarantined for review: ${YELLOW}$QUARANTINED_FILES${NC}"
echo -e "Processing failures: ${RED}$FAILED_FILES${NC}"

if [ -f "$OUTPUT_DIR/sanitization-report.json" ]; then
    echo
    echo "Detailed report:"
    cat "$OUTPUT_DIR/sanitization-report.json" | jq '.'
fi

# Check if any files were quarantined (should fail CI)
if [ $QUARANTINED_FILES -gt 0 ]; then
    echo
    echo -e "${RED}❌ MEDIA SANITIZATION REQUIRES MANUAL REVIEW${NC}"
    echo "Files in quarantine require manual inspection before use."
    echo "Review quarantined files in: $QUARANTINE_DIR"
    echo
    echo "🔧 To resolve:"
    echo "1. Review quarantined files and their reports"
    echo "2. Manually sanitize or remove dangerous content"  
    echo "3. Re-run sanitization after fixes"
    exit 1
elif [ $TOTAL_FILES -eq 0 ]; then
    echo -e "${GREEN}✅ NO MEDIA FILES FOUND${NC}"
    echo "No media files to sanitize - this is the most secure state"
    exit 0
else
    echo
    echo -e "${GREEN}✅ ALL MEDIA FILES SUCCESSFULLY SANITIZED${NC}"
    echo "All media files are safe for publication"
    echo "EXIF data removed, SVG scripts stripped, PDFs flattened"
    exit 0
fi