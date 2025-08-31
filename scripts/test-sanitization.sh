#!/bin/bash
# Comprehensive Markdown/HTML Sanitization Tests
# Tests for ALL JavaScript vectors, event handlers, and dangerous patterns

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_DIR="/tmp/sanitization-test-$$"
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo -e "${BLUE}🧪 COMPREHENSIVE SANITIZATION TESTS${NC}"
echo "===================================="

# Setup test environment
setup_tests() {
    mkdir -p "$TEST_DIR"/{content,templates,dist}
    echo "Test directory: $TEST_DIR"
}

# Cleanup test environment
cleanup_tests() {
    rm -rf "$TEST_DIR"
}

# Test result tracking
test_case() {
    local name="$1"
    local should_pass="$2"  # "pass" or "fail"
    local content="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Write test content
    echo "$content" > "$TEST_DIR/content/test.md"
    
    # Run sanitization
    if bash ./scripts/markdown-sanitizer.sh "$TEST_DIR/content" "$TEST_DIR/dist" >/dev/null 2>&1; then
        sanitization_passed=true
    else
        sanitization_passed=false
    fi
    
    # Run security regression guard
    if bash ./.scripts/security-regression-guard.sh "$TEST_DIR/dist" >/dev/null 2>&1; then
        security_passed=true
    else
        security_passed=false
    fi
    
    # Determine if test passed
    if [ "$should_pass" = "pass" ]; then
        # Content should be clean after sanitization
        if [ "$sanitization_passed" = true ] && [ "$security_passed" = true ]; then
            echo -e "  ${GREEN}✓${NC} $name"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "  ${RED}✗${NC} $name (should pass but failed)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        # Dangerous content should be blocked
        if [ "$security_passed" = false ]; then
            echo -e "  ${GREEN}✓${NC} $name (correctly blocked)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "  ${RED}✗${NC} $name (should be blocked but passed)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo -e "    ${YELLOW}Content:${NC} $(echo "$content" | head -1 | cut -c1-60)..."
        fi
    fi
}

echo -e "${BLUE}Testing Script Tags...${NC}"

test_case "Basic script tag" "fail" '<script>alert("xss")</script>'
test_case "Script with type" "fail" '<script type="text/javascript">alert("xss")</script>'
test_case "Script with src" "fail" '<script src="evil.js"></script>'
test_case "Case variations" "fail" '<ScRiPt>alert("xss")</ScRiPt>'
test_case "Script in markdown code block" "pass" '```html
<script>alert("safe in code block")</script>
```'

echo -e "${BLUE}Testing Event Handlers...${NC}"

# Test all major event handlers
event_handlers=(
    "onclick" "onload" "onerror" "onmouseover" "onmouseout" "onkeydown" "onkeyup"
    "onfocus" "onblur" "onchange" "onsubmit" "onreset" "ondblclick" "oncontextmenu"
    "onmousedown" "onmouseup" "onmousemove" "onmouseenter" "onmouseleave"
    "onkeypress" "oninput" "onscroll" "onresize" "onabort" "oncanplay" "oncanplaythrough"
    "ondurationchange" "onemptied" "onended" "onloadeddata" "onloadedmetadata"
    "onloadstart" "onpause" "onplay" "onplaying" "onprogress" "onratechange"
    "onseeked" "onseeking" "onstalled" "onsuspend" "ontimeupdate" "onvolumechange"
    "onwaiting" "ontoggle" "onwheel" "oncopy" "oncut" "onpaste" "ondrag" "ondragend"
    "ondragenter" "ondragleave" "ondragover" "ondragstart" "ondrop" "onanimationend"
    "onanimationiteration" "onanimationstart" "ontransitionend"
)

for handler in "${event_handlers[@]}"; do
    test_case "Event handler: $handler" "fail" "<div $handler=\"alert('xss')\">test</div>"
done

echo -e "${BLUE}Testing JavaScript URLs...${NC}"

test_case "javascript: URL in link" "fail" '<a href="javascript:alert(1)">click</a>'
test_case "javascript: URL in img" "fail" '<img src="javascript:alert(1)" alt="evil">'
test_case "javascript: with encoding" "fail" '<a href="java&#115;cript:alert(1)">click</a>'
test_case "javascript: case variations" "fail" '<a href="JaVaScRiPt:alert(1)">click</a>'

echo -e "${BLUE}Testing Data URLs...${NC}"

test_case "data: URL with javascript" "fail" '<img src="data:text/html,<script>alert(1)</script>" alt="evil">'
test_case "data: URL with base64 js" "fail" '<img src="data:text/javascript;base64,YWxlcnQoMSk=" alt="evil">'
test_case "Safe data: image URL" "pass" '<img src="data:image/png;base64,iVBORw0KGgoAAAANS..." alt="safe">'
test_case "data: URL text/html" "fail" '<iframe src="data:text/html,<html><script>alert(1)</script></html>"></iframe>'

echo -e "${BLUE}Testing Dangerous HTML Tags...${NC}"

dangerous_tags=(
    "iframe" "object" "embed" "applet" "frame" "frameset" 
    "audio" "video" "canvas" "svg" "math" "template"
)

for tag in "${dangerous_tags[@]}"; do
    test_case "Dangerous tag: $tag" "fail" "<$tag>content</$tag>"
done

echo -e "${BLUE}Testing Form Elements...${NC}"

form_elements=(
    "form" "input" "button" "select" "textarea" "keygen"
)

for element in "${form_elements[@]}"; do
    test_case "Form element: $element" "fail" "<$element>content</$element>"
done

echo -e "${BLUE}Testing CSS Injection...${NC}"

test_case "CSS with expression()" "fail" '<div style="width: expression(alert(1))">evil</div>'
test_case "CSS with javascript:" "fail" '<div style="background: url(javascript:alert(1))">evil</div>'
test_case "CSS with behavior:" "fail" '<div style="behavior: url(evil.htc)">evil</div>'
test_case "CSS with @import" "fail" '<style>@import url(javascript:alert(1))</style>'
test_case "CSS with -moz-binding" "fail" '<div style="-moz-binding: url(evil.xml#xss)">evil</div>'

echo -e "${BLUE}Testing Meta and Link Tags...${NC}"

test_case "Meta refresh with javascript:" "fail" '<meta http-equiv="refresh" content="0;url=javascript:alert(1)">'
test_case "Link with javascript:" "fail" '<link rel="stylesheet" href="javascript:alert(1)">'
test_case "Base tag with javascript:" "fail" '<base href="javascript:">'

echo -e "${BLUE}Testing SVG Scripts...${NC}"

test_case "SVG with script" "fail" '<svg><script>alert(1)</script></svg>'
test_case "SVG with onload" "fail" '<svg onload="alert(1)"><circle r="10"></circle></svg>'
test_case "SVG with animate" "fail" '<svg><animate onbegin="alert(1)"></animate></svg>'

echo -e "${BLUE}Testing HTML Comments...${NC}"

test_case "HTML comment with script" "fail" '<!-- <script>alert(1)</script> -->'
test_case "Conditional comment IE" "fail" '<!--[if IE]><script>alert(1)</script><![endif]-->'

echo -e "${BLUE}Testing Edge Cases...${NC}"

test_case "NULL byte injection" "fail" '<img src="java\x00script:alert(1)" alt="evil">'
test_case "URL encoding" "fail" '<img src="java%73cript:alert(1)" alt="evil">'
test_case "HTML entity encoding" "fail" '<img src="java&#115;cript:alert(1)" alt="evil">'
test_case "Hex entity encoding" "fail" '<img src="java&#x73;cript:alert(1)" alt="evil">'

echo -e "${BLUE}Testing Safe Content...${NC}"

test_case "Regular markdown text" "pass" 'This is normal markdown text with **bold** and *italic*.'
test_case "Safe HTML tags" "pass" '<p>This is a <strong>safe</strong> paragraph with <em>emphasis</em>.</p>'
test_case "Safe links" "pass" '<a href="https://example.com">Safe external link</a>'
test_case "Safe images" "pass" '<img src="/images/safe.jpg" alt="Safe image">'
test_case "Code blocks" "pass" '```javascript
// This is safe JavaScript in a code block
function hello() { console.log("hello"); }
```'
test_case "Inline code" "pass" 'Use `console.log()` for debugging.'

echo -e "${BLUE}Testing Mixed Content...${NC}"

test_case "Safe content with dangerous" "fail" 'This is safe text <script>alert(1)</script> with danger.'
test_case "Multiple dangerous elements" "fail" '<script>alert(1)</script><img src="javascript:alert(2)" onload="alert(3)">'

echo -e "${BLUE}Testing Sanitization Bypass Attempts...${NC}"

test_case "Nested script tags" "fail" '<scr<script>ipt>alert(1)</script>'
test_case "Script with newlines" "fail" '<scri\npt>alert(1)</scri\npt>'
test_case "Script with spaces" "fail" '< script >alert(1)</ script >'
test_case "Script with tabs" "fail" '<\tscript\t>alert(1)</\tscript\t>'

# Additional modern JavaScript patterns
echo -e "${BLUE}Testing Modern JS Patterns...${NC}"

test_case "ES6 template literals" "fail" '<script>`${alert(1)}`</script>'
test_case "Arrow functions" "fail" '<img onload="()=>alert(1)" alt="evil">'
test_case "Async/await" "fail" '<script>async function(){await alert(1)}</script>'
test_case "Destructuring" "fail" '<script>let{alert}=window;alert(1)</script>'

# WebAssembly and modern APIs
echo -e "${BLUE}Testing WebAssembly and APIs...${NC}"

test_case "WebAssembly instantiate" "fail" '<script>WebAssembly.instantiate()</script>'
test_case "Fetch API" "fail" '<script>fetch("evil.com")</script>'
test_case "Service Worker" "fail" '<script>navigator.serviceWorker.register("evil.js")</script>'

# Print results
echo
echo -e "${BLUE}TEST RESULTS${NC}"
echo "============"
echo "Total tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}✅ ALL SANITIZATION TESTS PASSED${NC}"
    echo "The sanitization system successfully blocks all tested attack vectors."
    exit_code=0
else
    echo -e "\n${RED}❌ SANITIZATION TESTS FAILED${NC}"
    echo "Some attack vectors were not properly blocked."
    echo "Review the failed tests and improve the sanitization logic."
    exit_code=1
fi

# Cleanup and exit
trap cleanup_tests EXIT

exit $exit_code