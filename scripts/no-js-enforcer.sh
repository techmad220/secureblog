#!/bin/bash
# No-JS Enforcer - Comprehensive JavaScript Detection
# Catches ALL JavaScript vectors including inline handlers, data URIs, and MIME types

set -euo pipefail

BUILD_DIR="${1:-dist}"
VIOLATIONS=0
CRITICAL_VIOLATIONS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 No-JavaScript Enforcement Check${NC}"
echo "===================================="
echo "Build directory: $BUILD_DIR"
echo ""

# Arrays to track violations
declare -a js_files=()
declare -a inline_handlers=()
declare -a javascript_urls=()
declare -a script_tags=()
declare -a dangerous_attrs=()
declare -a mime_violations=()

# Check 1: No .js files
echo -e "${BLUE}Checking for .js files...${NC}"
while IFS= read -r -d '' file; do
    js_files+=("$file")
    echo -e "${RED}  ✗ JavaScript file: $file${NC}"
    ((VIOLATIONS++))
    ((CRITICAL_VIOLATIONS++))
done < <(find "$BUILD_DIR" -name "*.js" -type f -print0 2>/dev/null)

if [ ${#js_files[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✓ No .js files found${NC}"
fi

# Check 2: No script tags in HTML
echo -e "\n${BLUE}Checking for <script> tags...${NC}"
while IFS= read -r file; do
    if grep -l '<script' "$file" 2>/dev/null; then
        script_tags+=("$file")
        echo -e "${RED}  ✗ <script> tag in: $file${NC}"
        grep -n '<script' "$file" | head -3
        ((VIOLATIONS++))
        ((CRITICAL_VIOLATIONS++))
    fi
done < <(find "$BUILD_DIR" -name "*.html" -type f 2>/dev/null)

if [ ${#script_tags[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✓ No <script> tags found${NC}"
fi

# Check 3: Inline event handlers (comprehensive list)
echo -e "\n${BLUE}Checking for inline event handlers...${NC}"
EVENT_HANDLERS=(
    "onabort" "onafterprint" "onanimationend" "onanimationiteration"
    "onanimationstart" "onbeforeprint" "onbeforeunload" "onblur"
    "oncanplay" "oncanplaythrough" "onchange" "onclick" "oncontextmenu"
    "oncopy" "oncut" "ondblclick" "ondrag" "ondragend" "ondragenter"
    "ondragleave" "ondragover" "ondragstart" "ondrop" "ondurationchange"
    "onemptied" "onended" "onerror" "onfocus" "onfocusin" "onfocusout"
    "onformdata" "onfullscreenchange" "onfullscreenerror" "ongotpointercapture"
    "onhashchange" "oninput" "oninvalid" "onkeydown" "onkeypress" "onkeyup"
    "onload" "onloadeddata" "onloadedmetadata" "onloadstart"
    "onlostpointercapture" "onmessage" "onmousedown" "onmouseenter"
    "onmouseleave" "onmousemove" "onmouseout" "onmouseover" "onmouseup"
    "onmousewheel" "onoffline" "ononline" "onorientationchange" "onpagehide"
    "onpageshow" "onpaste" "onpause" "onplay" "onplaying" "onpointercancel"
    "onpointerdown" "onpointerenter" "onpointerleave" "onpointermove"
    "onpointerout" "onpointerover" "onpointerup" "onpopstate" "onprogress"
    "onratechange" "onrejectionhandled" "onreset" "onresize" "onscroll"
    "onsearch" "onsecuritypolicyviolation" "onseeked" "onseeking" "onselect"
    "onselectionchange" "onselectstart" "onshow" "onslotchange" "onstalled"
    "onstorage" "onsubmit" "onsuspend" "ontimeupdate" "ontoggle"
    "ontouchcancel" "ontouchend" "ontouchmove" "ontouchstart"
    "ontransitioncancel" "ontransitionend" "ontransitionrun"
    "ontransitionstart" "onunhandledrejection" "onunload" "onvolumechange"
    "onwaiting" "onwebkitanimationend" "onwebkitanimationiteration"
    "onwebkitanimationstart" "onwebkittransitionend" "onwheel"
)

for handler in "${EVENT_HANDLERS[@]}"; do
    while IFS= read -r file; do
        if grep -qi "\s${handler}=" "$file" 2>/dev/null; then
            inline_handlers+=("$file:$handler")
            echo -e "${RED}  ✗ Inline $handler in: $file${NC}"
            grep -n -i "\s${handler}=" "$file" | head -1
            ((VIOLATIONS++))
            ((CRITICAL_VIOLATIONS++))
        fi
    done < <(find "$BUILD_DIR" -name "*.html" -type f 2>/dev/null)
done

if [ ${#inline_handlers[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✓ No inline event handlers found${NC}"
fi

# Check 4: javascript: URLs
echo -e "\n${BLUE}Checking for javascript: URLs...${NC}"
while IFS= read -r file; do
    if grep -qi 'javascript:' "$file" 2>/dev/null; then
        javascript_urls+=("$file")
        echo -e "${RED}  ✗ javascript: URL in: $file${NC}"
        grep -n -i 'javascript:' "$file" | head -3
        ((VIOLATIONS++))
        ((CRITICAL_VIOLATIONS++))
    fi
done < <(find "$BUILD_DIR" \( -name "*.html" -o -name "*.css" \) -type f 2>/dev/null)

if [ ${#javascript_urls[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✓ No javascript: URLs found${NC}"
fi

# Check 5: Dangerous data: URLs
echo -e "\n${BLUE}Checking for dangerous data: URLs...${NC}"
DANGEROUS_DATA_URLS=(
    "data:text/javascript"
    "data:application/javascript"
    "data:text/html"
    "data:application/x-javascript"
    "data:text/ecmascript"
    "data:application/ecmascript"
    "data:text/vbscript"
    "data:text/livescript"
)

for data_url in "${DANGEROUS_DATA_URLS[@]}"; do
    while IFS= read -r file; do
        if grep -qi "$data_url" "$file" 2>/dev/null; then
            dangerous_attrs+=("$file:$data_url")
            echo -e "${RED}  ✗ Dangerous data URL in: $file${NC}"
            grep -n -i "$data_url" "$file" | head -1
            ((VIOLATIONS++))
            ((CRITICAL_VIOLATIONS++))
        fi
    done < <(find "$BUILD_DIR" \( -name "*.html" -o -name "*.css" \) -type f 2>/dev/null)
done

if [ ${#dangerous_attrs[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✓ No dangerous data: URLs found${NC}"
fi

# Check 6: Script MIME types
echo -e "\n${BLUE}Checking for script MIME types...${NC}"
SCRIPT_MIMES=(
    "text/javascript"
    "application/javascript"
    "application/x-javascript"
    "text/ecmascript"
    "application/ecmascript"
    "text/livescript"
    "text/vbscript"
    "text/jscript"
)

for mime in "${SCRIPT_MIMES[@]}"; do
    while IFS= read -r file; do
        if grep -qi "type=['\"]${mime}" "$file" 2>/dev/null; then
            mime_violations+=("$file:$mime")
            echo -e "${RED}  ✗ Script MIME type in: $file${NC}"
            grep -n -i "type=['\"]${mime}" "$file" | head -1
            ((VIOLATIONS++))
        fi
    done < <(find "$BUILD_DIR" -name "*.html" -type f 2>/dev/null)
done

if [ ${#mime_violations[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✓ No script MIME types found${NC}"
fi

# Check 7: Import statements and modules
echo -e "\n${BLUE}Checking for ES6 imports and modules...${NC}"
MODULE_PATTERNS=(
    '<script.*type="module"'
    '<script.*type=.module.'
    'import\s.*from'
    'export\s.*from'
    'export\s.*default'
)

for pattern in "${MODULE_PATTERNS[@]}"; do
    while IFS= read -r file; do
        if grep -Ei "$pattern" "$file" 2>/dev/null; then
            echo -e "${RED}  ✗ Module/import in: $file${NC}"
            grep -n -Ei "$pattern" "$file" | head -1
            ((VIOLATIONS++))
            ((CRITICAL_VIOLATIONS++))
        fi
    done < <(find "$BUILD_DIR" -name "*.html" -type f 2>/dev/null)
done

# Check 8: WebAssembly
echo -e "\n${BLUE}Checking for WebAssembly...${NC}"
if find "$BUILD_DIR" -name "*.wasm" -type f 2>/dev/null | grep -q .; then
    echo -e "${RED}  ✗ WebAssembly files found${NC}"
    find "$BUILD_DIR" -name "*.wasm" -type f
    ((VIOLATIONS++))
    ((CRITICAL_VIOLATIONS++))
else
    echo -e "${GREEN}  ✓ No WebAssembly files found${NC}"
fi

# Check 9: Suspicious attributes
echo -e "\n${BLUE}Checking for suspicious attributes...${NC}"
SUSPICIOUS_ATTRS=(
    "contenteditable"
    "spellcheck"
    "draggable"
    "contextmenu"
    "accesskey"
    "tabindex=\"-1\""
)

for attr in "${SUSPICIOUS_ATTRS[@]}"; do
    while IFS= read -r file; do
        if grep -qi "$attr" "$file" 2>/dev/null; then
            echo -e "${YELLOW}  ⚠ Suspicious attribute '$attr' in: $file${NC}"
            ((VIOLATIONS++))
        fi
    done < <(find "$BUILD_DIR" -name "*.html" -type f 2>/dev/null)
done

# Check 10: CSP bypass attempts
echo -e "\n${BLUE}Checking for CSP bypass attempts...${NC}"
CSP_BYPASS_PATTERNS=(
    "unsafe-inline"
    "unsafe-eval"
    "unsafe-hashes"
    "data:.*script"
    "blob:.*script"
)

for pattern in "${CSP_BYPASS_PATTERNS[@]}"; do
    if grep -r -qi "$pattern" "$BUILD_DIR" 2>/dev/null; then
        echo -e "${RED}  ✗ CSP bypass pattern found: $pattern${NC}"
        grep -r -l -i "$pattern" "$BUILD_DIR" | head -3
        ((VIOLATIONS++))
    fi
done

# Generate report
echo -e "\n${BLUE}=== No-JavaScript Enforcement Report ===${NC}"
echo "========================================"
echo -e "Total violations:     ${VIOLATIONS}"
echo -e "Critical violations:  ${CRITICAL_VIOLATIONS}"
echo ""
echo "Checks performed:"
echo "  ✓ .js file detection"
echo "  ✓ <script> tag detection"
echo "  ✓ Inline event handler detection (${#EVENT_HANDLERS[@]} handlers)"
echo "  ✓ javascript: URL detection"
echo "  ✓ Dangerous data: URL detection"
echo "  ✓ Script MIME type detection"
echo "  ✓ ES6 module detection"
echo "  ✓ WebAssembly detection"
echo "  ✓ Suspicious attribute detection"
echo "  ✓ CSP bypass detection"

# Exit codes
if [ $CRITICAL_VIOLATIONS -gt 0 ]; then
    echo -e "\n${RED}❌ CRITICAL: JavaScript detected! Build must fail.${NC}"
    exit 2
elif [ $VIOLATIONS -gt 0 ]; then
    echo -e "\n${YELLOW}⚠️  WARNING: Suspicious patterns detected.${NC}"
    exit 1
else
    echo -e "\n${GREEN}✅ SUCCESS: No JavaScript detected. Site is JS-free!${NC}"
    exit 0
fi