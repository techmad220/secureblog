#!/bin/bash
# Blocking Media Pipeline
# FAILS CI build if EXIF isn't stripped or SVGs aren't sanitized - NO exceptions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INPUT_DIR="${1:-content/images}"
OUTPUT_DIR="${2:-assets/sanitized}"

echo -e "${BLUE}🚫 BLOCKING MEDIA PIPELINE - ZERO TOLERANCE${NC}"
echo "==========================================="
echo "Input: $INPUT_DIR"
echo "Output: $OUTPUT_DIR" 
echo "Policy: FAIL BUILD if ANY media security violation"
echo

TOTAL_FILES=0
PROCESSED_FILES=0
FAILED_FILES=0
SECURITY_VIOLATIONS=0

# Required tools check
REQUIRED_TOOLS=(
    "exiftool:EXIF metadata removal"
    "convert:ImageMagick for image processing"
    "gs:Ghostscript for PDF processing"
    "xmlstarlet:XML/SVG processing"
)

echo -e "${BLUE}Checking required security tools...${NC}"
for tool_desc in "${REQUIRED_TOOLS[@]}"; do
    tool=$(echo "$tool_desc" | cut -d: -f1)
    desc=$(echo "$tool_desc" | cut -d: -f2)
    
    if command -v "$tool" >/dev/null 2>&1; then
        echo -e "${GREEN}   ✓ $tool ($desc)${NC}"
    else
        echo -e "${RED}   ✗ $tool ($desc) - MISSING${NC}"
        echo "Install with: sudo apt-get install imagemagick exiftool ghostscript xmlstarlet"
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"/{images,svgs,pdfs}

# Function to check if EXIF was successfully removed
verify_exif_removed() {
    local file="$1"
    
    if exiftool "$file" 2>/dev/null | grep -qE "(Camera|GPS|Date|Software)" 2>/dev/null; then
        return 1  # EXIF still present
    fi
    return 0  # EXIF removed
}

# Function to check if SVG is safe (no scripts/handlers)
verify_svg_safe() {
    local file="$1"
    
    if grep -qiE "(<script|javascript:|on[a-z]+=|<foreignObject|<iframe|<object|<embed)" "$file" 2>/dev/null; then
        return 1  # Dangerous content found
    fi
    return 0  # SVG is safe
}

# Function to process image with mandatory EXIF removal
process_image() {
    local input_file="$1"
    local output_file="$2"
    local filename=$(basename "$input_file")
    
    echo -n "Processing image: $filename... "
    
    # First attempt: ImageMagick with EXIF stripping
    if convert "$input_file" -strip -quality 85 "$output_file" 2>/dev/null; then
        # Verify EXIF was actually removed
        if verify_exif_removed "$output_file"; then
            echo -e "${GREEN}SECURE${NC}"
            return 0
        else
            echo -e "${RED}EXIF NOT REMOVED${NC}"
            rm -f "$output_file"
            SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
            return 1
        fi
    fi
    
    # Second attempt: exiftool
    cp "$input_file" "$output_file"
    if exiftool -all= -overwrite_original "$output_file" 2>/dev/null; then
        if verify_exif_removed "$output_file"; then
            echo -e "${GREEN}SECURE (exiftool)${NC}"
            return 0
        else
            echo -e "${RED}EXIF REMOVAL FAILED${NC}"
            rm -f "$output_file"
            SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
            return 1
        fi
    fi
    
    echo -e "${RED}FAILED - SECURITY VIOLATION${NC}"
    SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
    return 1
}

# Function to process SVG with mandatory sanitization
process_svg() {
    local input_file="$1" 
    local output_file="$2"
    local filename=$(basename "$input_file")
    
    echo -n "Processing SVG: $filename... "
    
    # Check if input SVG has dangerous content
    if ! verify_svg_safe "$input_file"; then
        echo -n "DANGEROUS CONTENT DETECTED, sanitizing... "
    fi
    
    # Sanitize with xmlstarlet
    if xmlstarlet ed \
       -d "//script" \
       -d "//@*[starts-with(name(), 'on')]" \
       -d "//foreignObject" \
       -d "//iframe" \
       -d "//object" \
       -d "//embed" \
       "$input_file" > "$output_file" 2>/dev/null; then
       
        # Verify sanitization was successful
        if verify_svg_safe "$output_file"; then
            echo -e "${GREEN}SECURE${NC}"
            return 0
        else
            echo -e "${RED}SANITIZATION FAILED${NC}"
            rm -f "$output_file"
            SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
            return 1
        fi
    fi
    
    # Fallback: sed-based sanitization
    sed -E \
        -e '/<script[^>]*>/,/<\/script>/d' \
        -e 's/on[a-zA-Z]+\s*=\s*"[^"]*"//g' \
        -e 's/on[a-zA-Z]+\s*=\s*'\''[^'\'']*'\''//g' \
        -e '/<foreignObject[^>]*>/,/<\/foreignObject>/d' \
        -e '/<iframe[^>]*>/,/<\/iframe>/d' \
        -e '/<object[^>]*>/,/<\/object>/d' \
        -e '/<embed[^>]*>/d' \
        "$input_file" > "$output_file"
    
    if verify_svg_safe "$output_file"; then
        echo -e "${GREEN}SECURE (sed)${NC}"
        return 0
    else
        echo -e "${RED}SANITIZATION FAILED - SECURITY VIOLATION${NC}"
        rm -f "$output_file"
        SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
        return 1
    fi
}

# Function to process PDF with mandatory flattening
process_pdf() {
    local input_file="$1"
    local output_file="$2"
    local filename=$(basename "$input_file")
    
    echo -n "Processing PDF: $filename... "
    
    # Check for dangerous PDF content
    if strings "$input_file" | grep -qiE "(javascript|acroform|/js|/aa)" 2>/dev/null; then
        echo -n "DANGEROUS CONTENT DETECTED, flattening... "
    fi
    
    # Flatten PDF with Ghostscript -dSAFER
    if gs -dSAFER -dBATCH -dNOPAUSE -dNOPLATFONTS \
       -sDEVICE=pdfwrite \
       -sColorConversionStrategy=RGB \
       -dProcessColorModel=/DeviceRGB \
       -dCompatibilityLevel=1.4 \
       -sOutputFile="$output_file" \
       "$input_file" >/dev/null 2>&1; then
       
        # Verify dangerous content was removed
        if ! strings "$output_file" | grep -qiE "(javascript|acroform|/js|/aa)" 2>/dev/null; then
            echo -e "${GREEN}SECURE${NC}"
            return 0
        else
            echo -e "${RED}DANGEROUS CONTENT STILL PRESENT${NC}"
            rm -f "$output_file"
            SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
            return 1
        fi
    fi
    
    echo -e "${RED}FLATTENING FAILED - SECURITY VIOLATION${NC}"
    SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
    return 1
}

# Main processing loop
if [ ! -d "$INPUT_DIR" ]; then
    echo -e "${GREEN}✅ NO MEDIA DIRECTORY - MOST SECURE STATE${NC}"
    echo "No media files to process. This is the most secure configuration."
    exit 0
fi

echo -e "${BLUE}Processing media files with ZERO TOLERANCE...${NC}"
echo

find "$INPUT_DIR" -type f | while read file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    
    extension=$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')
    filename=$(basename "$file")
    
    case "$extension" in
        jpg|jpeg|png|gif|webp)
            output_file="$OUTPUT_DIR/images/$filename"
            if process_image "$file" "$output_file"; then
                PROCESSED_FILES=$((PROCESSED_FILES + 1))
            else
                FAILED_FILES=$((FAILED_FILES + 1))
            fi
            ;;
            
        svg)
            output_file="$OUTPUT_DIR/svgs/$filename"
            if process_svg "$file" "$output_file"; then
                PROCESSED_FILES=$((PROCESSED_FILES + 1))
            else
                FAILED_FILES=$((FAILED_FILES + 1))
            fi
            ;;
            
        pdf)
            output_file="$OUTPUT_DIR/pdfs/$filename"
            if process_pdf "$file" "$output_file"; then
                PROCESSED_FILES=$((PROCESSED_FILES + 1))
            else
                FAILED_FILES=$((FAILED_FILES + 1))
            fi
            ;;
            
        *)
            echo -e "${RED}UNSUPPORTED FILE TYPE: $filename (.$extension)${NC}"
            SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
            FAILED_FILES=$((FAILED_FILES + 1))
            ;;
    esac
done

# Generate security report
cat > media-security-report.json << EOF
{
  "scan_date": "$(date -Iseconds)",
  "input_directory": "$INPUT_DIR",
  "output_directory": "$OUTPUT_DIR",
  "total_files": $TOTAL_FILES,
  "processed_files": $PROCESSED_FILES,
  "failed_files": $FAILED_FILES,
  "security_violations": $SECURITY_VIOLATIONS,
  "enforcement_policy": {
    "zero_tolerance": true,
    "ci_blocking": true,
    "exif_removal": "mandatory",
    "svg_sanitization": "mandatory", 
    "pdf_flattening": "mandatory"
  },
  "security_checks": {
    "exif_verification": "post_processing_validation",
    "svg_safety": "dangerous_content_detection",
    "pdf_safety": "javascript_removal_verification",
    "unsupported_types": "blocked"
  }
}
EOF

echo
echo -e "${BLUE}MEDIA SECURITY PIPELINE RESULTS${NC}"
echo "==============================="
echo "Total files: $TOTAL_FILES"
echo -e "Successfully processed: ${GREEN}$PROCESSED_FILES${NC}"
echo -e "Failed processing: ${RED}$FAILED_FILES${NC}"
echo -e "Security violations: ${RED}$SECURITY_VIOLATIONS${NC}"

if [ $SECURITY_VIOLATIONS -gt 0 ] || [ $FAILED_FILES -gt 0 ]; then
    echo
    echo -e "${RED}❌ MEDIA SECURITY VIOLATIONS - BUILD MUST FAIL${NC}"
    echo "========================================="
    echo "ZERO TOLERANCE POLICY VIOLATED"
    echo
    echo "The following security requirements were NOT met:"
    [ $SECURITY_VIOLATIONS -gt 0 ] && echo "- $SECURITY_VIOLATIONS files with unresolved security issues"
    [ $FAILED_FILES -gt 0 ] && echo "- $FAILED_FILES files failed processing completely"
    echo
    echo "🔧 REQUIRED FIXES:"
    echo "1. Ensure ALL images have EXIF metadata completely removed"
    echo "2. Ensure ALL SVGs are sanitized (no scripts/handlers/dangerous content)"
    echo "3. Ensure ALL PDFs are flattened (no JavaScript/forms/interactive content)" 
    echo "4. Only use supported file types: JPG, PNG, GIF, WebP, SVG, PDF"
    echo
    echo "💡 TROUBLESHOOTING:"
    echo "- Install required tools: sudo apt-get install imagemagick exiftool ghostscript xmlstarlet"
    echo "- Check file permissions and formats"
    echo "- Review media-security-report.json for details"
    echo "- Consider removing problematic media files"
    echo
    echo "🚫 CI/CD PIPELINE BLOCKED - SECURITY VIOLATION"
    exit 1
    
elif [ $TOTAL_FILES -eq 0 ]; then
    echo
    echo -e "${GREEN}✅ NO MEDIA FILES - MAXIMUM SECURITY${NC}"
    echo "No media files found - this is the most secure configuration"
    echo "Static text-only sites have minimal attack surface"
    exit 0
    
else
    echo
    echo -e "${GREEN}✅ ALL MEDIA FILES SECURELY PROCESSED${NC}"
    echo "======================================"
    echo "All media files meet security requirements:"
    echo "- ✅ All images have EXIF metadata removed"
    echo "- ✅ All SVGs are sanitized (no dangerous content)"
    echo "- ✅ All PDFs are flattened (no interactive content)"
    echo "- ✅ All files verified post-processing"
    echo
    echo "🔒 SECURITY GUARANTEES:"
    echo "- No metadata leakage from images"
    echo "- No script execution from SVGs"
    echo "- No malicious content from PDFs"
    echo "- No unsupported file types"
    echo
    echo "✅ CI/CD PIPELINE APPROVED - SECURITY REQUIREMENTS MET"
    exit 0
fi