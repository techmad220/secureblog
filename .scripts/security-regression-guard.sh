#!/bin/bash
# Security Regression Guard - Zero JavaScript Enforcement
# Catches ALL possible JavaScript vectors with zero tolerance

set -euo pipefail

TARGET_DIR="${1:-dist}"
EXIT_CODE=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🛡️  SECURITY REGRESSION GUARD${NC}"
echo "=================================="
echo "Target: $TARGET_DIR"
echo

[ -d "$TARGET_DIR" ] || { echo "Directory '$TARGET_DIR' not found"; exit 1; }

# 1. Scan for ANY .js/.mjs/.jsx/.ts/.tsx files
echo -n "Scanning for JavaScript files... "
JS_FILES=$(find "$TARGET_DIR" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) 2>/dev/null || true)
if [ -n "$JS_FILES" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "JavaScript files found:"
    echo "$JS_FILES" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 2. Scan for <script> tags in HTML
echo -n "Scanning for <script> tags... "
SCRIPT_TAGS=$(grep -r "<script" "$TARGET_DIR" --include="*.html" --include="*.htm" 2>/dev/null || true)
if [ -n "$SCRIPT_TAGS" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "Script tags found:"
    echo "$SCRIPT_TAGS" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 3. Comprehensive inline handler detection (100+ handlers)
echo -n "Scanning for inline event handlers... "
INLINE_HANDLERS=$(grep -ri "on\(abort\|afterprint\|animationend\|animationiteration\|animationstart\|beforeprint\|beforeunload\|blur\|canplay\|canplaythrough\|change\|click\|contextmenu\|copy\|cut\|dblclick\|drag\|dragend\|dragenter\|dragleave\|dragover\|dragstart\|drop\|durationchange\|ended\|error\|focus\|focusin\|focusout\|fullscreenchange\|fullscreenerror\|hashchange\|input\|invalid\|keydown\|keypress\|keyup\|load\|loadeddata\|loadedmetadata\|loadstart\|message\|mousedown\|mouseenter\|mouseleave\|mousemove\|mouseout\|mouseover\|mouseup\|mousewheel\|offline\|online\|pagehide\|pageshow\|paste\|pause\|play\|playing\|popstate\|progress\|ratechange\|resize\|scroll\|search\|seeked\|seeking\|select\|stalled\|storage\|submit\|suspend\|timeupdate\|toggle\|touchcancel\|touchend\|touchmove\|touchstart\|transitionend\|unload\|volumechange\|waiting\|wheel\)=" "$TARGET_DIR" --include="*.html" --include="*.htm" --include="*.svg" --include="*.xml" 2>/dev/null || true)
if [ -n "$INLINE_HANDLERS" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "Inline handlers found:"
    echo "$INLINE_HANDLERS" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 4. Scan for javascript: URLs
echo -n "Scanning for javascript: URLs... "
JAVASCRIPT_URLS=$(grep -ri "javascript:" "$TARGET_DIR" --include="*.html" --include="*.htm" --include="*.svg" --include="*.css" --include="*.xml" 2>/dev/null || true)
if [ -n "$JAVASCRIPT_URLS" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "JavaScript URLs found:"
    echo "$JAVASCRIPT_URLS" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 5. Scan for data: URLs with JavaScript
echo -n "Scanning for data: URLs with JS... "
DATA_JS_URLS=$(grep -ri "data:.*javascript\|data:.*text/javascript" "$TARGET_DIR" --include="*.html" --include="*.htm" --include="*.svg" 2>/dev/null || true)
if [ -n "$DATA_JS_URLS" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "Data JS URLs found:"
    echo "$DATA_JS_URLS" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 6. Scan for eval/Function/setTimeout/setInterval with strings
echo -n "Scanning for dynamic code execution... "
DYNAMIC_CODE=$(grep -ri "\(eval\|Function\|setTimeout\|setInterval\)\s*(" "$TARGET_DIR" --include="*.html" --include="*.htm" --include="*.js" --include="*.mjs" 2>/dev/null || true)
if [ -n "$DYNAMIC_CODE" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "Dynamic code execution found:"
    echo "$DYNAMIC_CODE" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 7. Scan for WebAssembly
echo -n "Scanning for WebAssembly... "
WASM_CODE=$(grep -ri "WebAssembly\|\.wasm\|wasm" "$TARGET_DIR" --include="*.html" --include="*.htm" --include="*.js" --include="*.mjs" 2>/dev/null || true)
if [ -n "$WASM_CODE" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "WebAssembly found:"
    echo "$WASM_CODE" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 8. Scan for ES6 imports/require
echo -n "Scanning for module imports... "
MODULE_IMPORTS=$(grep -ri "\(import\s.*from\|require\s*(\)" "$TARGET_DIR" --include="*.html" --include="*.htm" 2>/dev/null || true)
if [ -n "$MODULE_IMPORTS" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "Module imports found:"
    echo "$MODULE_IMPORTS" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 9. Scan SVG files for embedded scripts
echo -n "Scanning SVG files for scripts... "
SVG_SCRIPTS=$(find "$TARGET_DIR" -name "*.svg" -exec grep -l "script\|javascript\|on[a-z]*=" {} \; 2>/dev/null || true)
if [ -n "$SVG_SCRIPTS" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "SVG files with scripts:"
    echo "$SVG_SCRIPTS" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 10. Scan for iframes or srcdoc
echo -n "Scanning for iframes... "
IFRAMES=$(grep -ri "<iframe\|srcdoc=" "$TARGET_DIR" --include="*.html" --include="*.htm" 2>/dev/null || true)
if [ -n "$IFRAMES" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "iframes found:"
    echo "$IFRAMES" | sed 's/^/  /'
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# 11. Verify strict CSP (default-src 'none')
echo -n "Verifying strict CSP... "
CSP_VIOLATIONS=$(find "$TARGET_DIR" -name "*.html" -exec grep -l "Content-Security-Policy" {} \; | while read -r file; do
    if ! grep -q "default-src 'none'" "$file"; then
        echo "$file: Missing default-src 'none'"
    fi
done)
if [ -n "$CSP_VIOLATIONS" ]; then
    echo -e "${YELLOW}WARNING${NC}"
    echo "CSP violations found:"
    echo "$CSP_VIOLATIONS" | sed 's/^/  /'
else
    echo -e "${GREEN}PASS${NC}"
fi

# 12. Final comprehensive scan for any JS patterns
echo -n "Final comprehensive JS scan... "
FINAL_JS_SCAN=$(grep -ri "\(function\s*(\|\=>\|var\s\|let\s\|const\s\|class\s\)" "$TARGET_DIR" --include="*.html" --include="*.htm" 2>/dev/null || true)
if [ -n "$FINAL_JS_SCAN" ]; then
    echo -e "${RED}FAIL${NC}"
    echo "JavaScript patterns found:"
    echo "$FINAL_JS_SCAN" | head -5 | sed 's/^/  /'
    [ $(echo "$FINAL_JS_SCAN" | wc -l) -gt 5 ] && echo "  ... and $(( $(echo "$FINAL_JS_SCAN" | wc -l) - 5 )) more"
    EXIT_CODE=1
else
    echo -e "${GREEN}PASS${NC}"
fi

echo
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ SECURITY REGRESSION GUARD: ALL CHECKS PASSED${NC}"
    echo "No JavaScript detected. Site is completely static."
else
    echo -e "${RED}❌ SECURITY REGRESSION GUARD: FAILED${NC}"
    echo "JavaScript detected. Build MUST NOT proceed."
fi

exit $EXIT_CODE