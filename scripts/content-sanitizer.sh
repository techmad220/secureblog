#!/usr/bin/env bash
# content-sanitizer.sh - Pre-publish content sanitizer to prevent XSS
set -euo pipefail

BUILD_DIR="${1:-dist/public}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🛡️ Content Security Sanitizer${NC}"
echo "=============================="
echo "Build directory: $BUILD_DIR"
echo ""

if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${RED}❌ Build directory not found: $BUILD_DIR${NC}"
    exit 1
fi

# Initialize counters
issues_found=0
files_processed=0
total_violations=0

# Arrays to store different types of issues
declare -a script_violations=()
declare -a event_handler_violations=()
declare -a dangerous_url_violations=()
declare -a inline_style_violations=()
declare -a html_injection_violations=()
declare -a suspicious_attributes=()

# Function to check for dangerous JavaScript patterns
check_javascript_patterns() {
    local file="$1"
    local violations=0
    
    # Check for script tags
    if grep -n -i '<script' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: <script> tags found in $file${NC}"
        script_violations+=("$file: <script> tags detected")
        ((violations++))
    fi
    
    # Check for event handlers (more comprehensive list)
    local event_handlers=(
        "onload" "onclick" "onmouseover" "onmouseout" "onmousedown" "onmouseup"
        "onsubmit" "onreset" "onselect" "onchange" "onblur" "onfocus"
        "onkeydown" "onkeypress" "onkeyup" "onerror" "onabort" "onresize"
        "onscroll" "onunload" "ondblclick" "oncontextmenu" "ondrag" "ondrop"
        "onpaste" "oncopy" "oncut" "oninput" "oninvalid" "ontouchstart"
        "ontouchend" "ontouchmove" "ontouchcancel" "onwheel" "onanimationend"
        "onanimationiteration" "onanimationstart" "ontransitionend"
    )
    
    for handler in "${event_handlers[@]}"; do
        if grep -n -i "${handler}\\s*=" "$file" 2>/dev/null; then
            echo -e "${RED}❌ CRITICAL: Event handler '$handler' found in $file${NC}"
            event_handler_violations+=("$file: $handler event handler")
            ((violations++))
        fi
    done
    
    return $violations
}

# Function to check for dangerous URLs
check_dangerous_urls() {
    local file="$1"
    local violations=0
    
    # Check for javascript: URLs
    if grep -n -i 'javascript:' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: javascript: URLs found in $file${NC}"
        dangerous_url_violations+=("$file: javascript: URL scheme")
        ((violations++))
    fi
    
    # Check for vbscript: URLs
    if grep -n -i 'vbscript:' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: vbscript: URLs found in $file${NC}"
        dangerous_url_violations+=("$file: vbscript: URL scheme")
        ((violations++))
    fi
    
    # Check for dangerous data: URLs (except safe image data)
    if grep -n -E 'data:(?!image/(png|jpg|jpeg|gif|webp|svg\+xml);base64,)' "$file" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  WARNING: Potentially dangerous data: URLs in $file${NC}"
        dangerous_url_violations+=("$file: potentially dangerous data: URL")
        # Note: This is a warning, not a blocking violation
    fi
    
    # Check for file: URLs
    if grep -n -i 'file://' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: file:// URLs found in $file${NC}"
        dangerous_url_violations+=("$file: file:// URL scheme")
        ((violations++))
    fi
    
    return $violations
}

# Function to check for inline styles that could contain JavaScript
check_inline_styles() {
    local file="$1"
    local violations=0
    
    # Check for expression() in CSS (IE-specific but dangerous)
    if grep -n -i 'expression\\s*(' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: CSS expression() found in $file${NC}"
        inline_style_violations+=("$file: CSS expression() detected")
        ((violations++))
    fi
    
    # Check for -moz-binding (Firefox-specific but dangerous)
    if grep -n -i '\\-moz\\-binding' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: -moz-binding CSS found in $file${NC}"
        inline_style_violations+=("$file: -moz-binding CSS detected")
        ((violations++))
    fi
    
    # Check for behavior: CSS (IE-specific but dangerous)
    if grep -n -i 'behavior\\s*:' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: CSS behavior property found in $file${NC}"
        inline_style_violations+=("$file: CSS behavior property detected")
        ((violations++))
    fi
    
    # Check for @import with javascript: or data:
    if grep -n -i '@import.*\\(javascript:\\|data:\\)' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: Dangerous @import found in $file${NC}"
        inline_style_violations+=("$file: dangerous @import statement")
        ((violations++))
    fi
    
    return $violations
}

# Function to check for dangerous HTML elements
check_dangerous_elements() {
    local file="$1"
    local violations=0
    
    local dangerous_elements=(
        "object" "embed" "iframe" "frame" "frameset" "applet"
        "link" "meta" "base" "form" "input" "button" "textarea" "select"
    )
    
    for element in "${dangerous_elements[@]}"; do
        if grep -n -i "<${element}\\s" "$file" 2>/dev/null || grep -n -i "<${element}>" "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠️  WARNING: Potentially dangerous <$element> element in $file${NC}"
            html_injection_violations+=("$file: <$element> element found")
            # Most of these are warnings unless they're clearly dangerous
            if [[ "$element" == "iframe" || "$element" == "object" || "$element" == "embed" ]]; then
                ((violations++))
            fi
        fi
    done
    
    return $violations
}

# Function to check for suspicious attributes
check_suspicious_attributes() {
    local file="$1"
    local violations=0
    
    local suspicious_attrs=(
        "srcdoc" "sandbox" "seamless" "allowscripts" "allowfullscreen"
        "contenteditable" "spellcheck" "translate" "hidden"
    )
    
    for attr in "${suspicious_attrs[@]}"; do
        if grep -n -i "${attr}\\s*=" "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠️  INFO: Suspicious attribute '$attr' in $file${NC}"
            suspicious_attributes+=("$file: $attr attribute")
            # These are informational, not blocking
        fi
    done
    
    return $violations
}

# Function to check for potential HTML injection
check_html_injection() {
    local file="$1"
    local violations=0
    
    # Check for unescaped template variables that could contain HTML
    if grep -n '{{[^}]*}}' "$file" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  INFO: Template variables found in $file - verify they're properly escaped${NC}"
        # This is informational since our template system should handle escaping
    fi
    
    # Check for suspicious comment patterns
    if grep -n '<!--.*<script.*-->' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: Script in HTML comment in $file${NC}"
        html_injection_violations+=("$file: script in HTML comment")
        ((violations++))
    fi
    
    # Check for CDATA sections with scripts
    if grep -n '<\\!\\[CDATA\\[.*<script' "$file" 2>/dev/null; then
        echo -e "${RED}❌ CRITICAL: Script in CDATA section in $file${NC}"
        html_injection_violations+=("$file: script in CDATA section")
        ((violations++))
    fi
    
    return $violations
}

# Main scanning function
scan_file() {
    local file="$1"
    local file_violations=0
    
    echo "Scanning: $(basename "$file")"
    
    # Run all security checks
    check_javascript_patterns "$file" && file_violations=$((file_violations + $?))
    check_dangerous_urls "$file" && file_violations=$((file_violations + $?))
    check_inline_styles "$file" && file_violations=$((file_violations + $?))
    check_dangerous_elements "$file" && file_violations=$((file_violations + $?))
    check_suspicious_attributes "$file" && file_violations=$((file_violations + $?))
    check_html_injection "$file" && file_violations=$((file_violations + $?))
    
    if [ $file_violations -gt 0 ]; then
        ((issues_found++))
        total_violations=$((total_violations + file_violations))
    fi
    
    ((files_processed++))
}

# Find and scan all HTML files
echo "🔍 Scanning HTML files for security violations..."
echo ""

while IFS= read -r -d '' file; do
    scan_file "$file"
done < <(find "$BUILD_DIR" -name "*.html" -type f -print0)

echo ""
echo "📊 Content Security Scan Results"
echo "================================="
echo ""

# Summary statistics
echo -e "${BLUE}Files processed: $files_processed${NC}"
echo -e "${BLUE}Files with issues: $issues_found${NC}"
echo -e "${BLUE}Total violations: $total_violations${NC}"
echo ""

# Detailed violation breakdown
if [ ${#script_violations[@]} -gt 0 ]; then
    echo -e "${RED}Script Violations (CRITICAL):${NC}"
    printf ' - %s\n' "${script_violations[@]}"
    echo ""
fi

if [ ${#event_handler_violations[@]} -gt 0 ]; then
    echo -e "${RED}Event Handler Violations (CRITICAL):${NC}"
    printf ' - %s\n' "${event_handler_violations[@]}"
    echo ""
fi

if [ ${#dangerous_url_violations[@]} -gt 0 ]; then
    echo -e "${RED}Dangerous URL Violations:${NC}"
    printf ' - %s\n' "${dangerous_url_violations[@]}"
    echo ""
fi

if [ ${#inline_style_violations[@]} -gt 0 ]; then
    echo -e "${RED}Inline Style Violations (CRITICAL):${NC}"
    printf ' - %s\n' "${inline_style_violations[@]}"
    echo ""
fi

if [ ${#html_injection_violations[@]} -gt 0 ]; then
    echo -e "${RED}HTML Injection Violations (CRITICAL):${NC}"
    printf ' - %s\n' "${html_injection_violations[@]}"
    echo ""
fi

if [ ${#suspicious_attributes[@]} -gt 0 ]; then
    echo -e "${YELLOW}Suspicious Attributes (INFO):${NC}"
    printf ' - %s\n' "${suspicious_attributes[@]}"
    echo ""
fi

# Generate detailed report
REPORT_FILE="$BUILD_DIR/content-security-report.md"
cat > "$REPORT_FILE" << EOF
# Content Security Scan Report

**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Directory**: $BUILD_DIR
**Files Processed**: $files_processed
**Files with Issues**: $issues_found
**Total Violations**: $total_violations

## Security Violations Summary

$(if [ ${#script_violations[@]} -gt 0 ]; then
    echo "### Script Violations (CRITICAL)"
    echo ""
    printf '- %s\n' "${script_violations[@]}"
    echo ""
fi)

$(if [ ${#event_handler_violations[@]} -gt 0 ]; then
    echo "### Event Handler Violations (CRITICAL)"
    echo ""
    printf '- %s\n' "${event_handler_violations[@]}"
    echo ""
fi)

$(if [ ${#dangerous_url_violations[@]} -gt 0 ]; then
    echo "### Dangerous URL Violations"
    echo ""
    printf '- %s\n' "${dangerous_url_violations[@]}"
    echo ""
fi)

$(if [ ${#inline_style_violations[@]} -gt 0 ]; then
    echo "### Inline Style Violations (CRITICAL)"
    echo ""
    printf '- %s\n' "${inline_style_violations[@]}"
    echo ""
fi)

$(if [ ${#html_injection_violations[@]} -gt 0 ]; then
    echo "### HTML Injection Violations (CRITICAL)"
    echo ""
    printf '- %s\n' "${html_injection_violations[@]}"
    echo ""
fi)

$(if [ ${#suspicious_attributes[@]} -gt 0 ]; then
    echo "### Suspicious Attributes (INFO)"
    echo ""
    printf '- %s\n' "${suspicious_attributes[@]}"
    echo ""
fi)

## Scan Details

This scan checks for:

- **Script Elements**: All \`<script>\` tags are blocked
- **Event Handlers**: All \`on*\` attributes (onclick, onload, etc.)
- **Dangerous URLs**: \`javascript:\`, \`vbscript:\`, \`file://\` schemes
- **CSS Injection**: \`expression()\`, \`-moz-binding\`, \`behavior:\`
- **HTML Elements**: Potentially dangerous elements like iframe, object, embed
- **Template Safety**: Unescaped template variables and CDATA scripts

## Security Policy

**Zero Tolerance**: Any CRITICAL violations will fail the build.
**Best Practice**: All violations should be reviewed and resolved.
**Safe Alternatives**: Use CSS classes instead of inline styles, external links instead of JavaScript URLs.

EOF

echo "📄 Detailed report saved to: $REPORT_FILE"

# Final verdict
echo ""
if [ $total_violations -eq 0 ]; then
    echo -e "${GREEN}✅ CONTENT SECURITY PASSED${NC}"
    echo -e "${GREEN}🛡️ No security violations found${NC}"
    echo -e "${GREEN}🚀 Content is safe for deployment${NC}"
    exit 0
else
    echo -e "${RED}❌ CONTENT SECURITY FAILED${NC}"
    echo -e "${RED}🚨 $total_violations security violations found${NC}"
    echo -e "${RED}🛑 BLOCKING DEPLOYMENT${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Fix Required:${NC}"
    echo "  1. Remove all <script> tags and event handlers"
    echo "  2. Replace javascript: and dangerous URLs"
    echo "  3. Remove CSS expressions and bindings"
    echo "  4. Use external stylesheets instead of inline styles"
    echo "  5. Validate all user-generated content"
    echo ""
    echo -e "${BLUE}ℹ️  See detailed report: $REPORT_FILE${NC}"
    exit 1
fi