#!/bin/bash
# Security Self-Check Script
# Comprehensive verification of all security controls

set -euo pipefail

DOMAIN="${1:-secureblog.example.com}"
BUILD_DIR="${2:-dist}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

echo -e "${BLUE}🔍 Security Self-Check for $DOMAIN${NC}"
echo "======================================="
echo ""

# Function to perform check
check() {
    local name="$1"
    local command="$2"
    local expected="${3:-}"
    
    echo -n "Checking $name... "
    
    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((CHECKS_PASSED++))
        return 0
    else
        if [ -n "$expected" ]; then
            echo -e "${RED}❌ FAIL${NC} (expected: $expected)"
        else
            echo -e "${RED}❌ FAIL${NC}"
        fi
        ((CHECKS_FAILED++))
        return 1
    fi
}

# Function for warning checks
check_warn() {
    local name="$1"
    local command="$2"
    
    echo -n "Checking $name... "
    
    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${YELLOW}⚠️  WARNING${NC}"
        ((CHECKS_WARNING++))
        return 1
    fi
}

# 1. Headers Check
echo -e "${BLUE}1. Security Headers${NC}"
echo "-------------------"

# Fetch headers
HEADERS=$(curl -sI "https://$DOMAIN" 2>/dev/null || echo "")

if [ -n "$HEADERS" ]; then
    check "HSTS" "echo '$HEADERS' | grep -i 'strict-transport-security.*max-age=63072000.*includeSubDomains.*preload'"
    check "CSP" "echo '$HEADERS' | grep -i 'content-security-policy.*default-src.*none'"
    check "X-Frame-Options" "echo '$HEADERS' | grep -i 'x-frame-options.*deny'"
    check "X-Content-Type-Options" "echo '$HEADERS' | grep -i 'x-content-type-options.*nosniff'"
    check "Referrer-Policy" "echo '$HEADERS' | grep -i 'referrer-policy.*no-referrer'"
    check "Permissions-Policy" "echo '$HEADERS' | grep -i 'permissions-policy'"
    check "CORP" "echo '$HEADERS' | grep -i 'cross-origin-resource-policy'"
    check "COOP" "echo '$HEADERS' | grep -i 'cross-origin-opener-policy'"
    check "COEP" "echo '$HEADERS' | grep -i 'cross-origin-embedder-policy'"
else
    echo -e "${YELLOW}Cannot reach $DOMAIN - checking local files${NC}"
fi

echo ""

# 2. Method Restrictions
echo -e "${BLUE}2. Method Restrictions${NC}"
echo "----------------------"

if [ -n "$HEADERS" ]; then
    echo -n "Testing POST method... "
    POST_RESPONSE=$(curl -sX POST "https://$DOMAIN" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    if [ "$POST_RESPONSE" = "405" ] || [ "$POST_RESPONSE" = "403" ]; then
        echo -e "${GREEN}✅ BLOCKED (${POST_RESPONSE})${NC}"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}❌ ALLOWED (${POST_RESPONSE})${NC}"
        ((CHECKS_FAILED++))
    fi
    
    echo -n "Testing PUT method... "
    PUT_RESPONSE=$(curl -sX PUT "https://$DOMAIN" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    if [ "$PUT_RESPONSE" = "405" ] || [ "$PUT_RESPONSE" = "403" ]; then
        echo -e "${GREEN}✅ BLOCKED (${PUT_RESPONSE})${NC}"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}❌ ALLOWED (${PUT_RESPONSE})${NC}"
        ((CHECKS_FAILED++))
    fi
fi

echo ""

# 3. JavaScript Detection
echo -e "${BLUE}3. JavaScript Detection${NC}"
echo "-----------------------"

check "No .js files" "! find '$BUILD_DIR' -name '*.js' -o -name '*.mjs' | grep -q ."
check "No <script> tags" "! grep -r '<script' '$BUILD_DIR' --include='*.html' 2>/dev/null | grep -q ."
check "No inline handlers" "! grep -rE 'on(click|load|error|mouseover)=' '$BUILD_DIR' --include='*.html' 2>/dev/null | grep -q ."
check "No javascript: URLs" "! grep -ri 'javascript:' '$BUILD_DIR' 2>/dev/null | grep -q ."

echo ""

# 4. Content Verification
echo -e "${BLUE}4. Content Verification${NC}"
echo "-----------------------"

if [ -f "$BUILD_DIR/manifest.sha256" ]; then
    check "Manifest exists" "test -f '$BUILD_DIR/manifest.sha256'"
    check "Manifest valid" "cd '$BUILD_DIR' && sha256sum -c manifest.sha256 --quiet 2>/dev/null"
else
    check_warn "Manifest exists" "test -f '$BUILD_DIR/manifest.sha256'"
fi

echo ""

# 5. CSP Validation
echo -e "${BLUE}5. CSP Policy Validation${NC}"
echo "------------------------"

if [ -n "$HEADERS" ]; then
    CSP_HEADER=$(echo "$HEADERS" | grep -i "content-security-policy" | cut -d: -f2- || echo "")
    
    if [ -n "$CSP_HEADER" ]; then
        # Check that images and CSS are allowed
        check "CSP allows images" "echo '$CSP_HEADER' | grep -q \"img-src.*'self'\""
        check "CSP allows CSS" "echo '$CSP_HEADER' | grep -q \"style-src.*'self'\""
        check "CSP blocks scripts" "echo '$CSP_HEADER' | grep -q \"default-src.*'none'\""
        check "CSP blocks inline" "! echo '$CSP_HEADER' | grep -q 'unsafe-inline'"
        check "CSP blocks eval" "! echo '$CSP_HEADER' | grep -q 'unsafe-eval'"
    fi
fi

echo ""

# 6. DNS Security
echo -e "${BLUE}6. DNS Security${NC}"
echo "---------------"

check_warn "DNSSEC enabled" "dig +dnssec '$DOMAIN' | grep -q 'ad'"
check_warn "CAA records" "dig +short CAA '$DOMAIN' | grep -q 'letsencrypt'"

echo ""

# 7. TLS Configuration
echo -e "${BLUE}7. TLS Configuration${NC}"
echo "--------------------"

if command -v testssl &> /dev/null; then
    TLS_VERSION=$(echo | openssl s_client -connect "$DOMAIN:443" 2>/dev/null | grep "Protocol" | awk '{print $3}')
    check "TLS 1.2+" "[[ '$TLS_VERSION' == 'TLSv1.2' ]] || [[ '$TLS_VERSION' == 'TLSv1.3' ]]"
else
    check_warn "TLS check" "command -v testssl"
fi

echo ""

# 8. Build Verification
echo -e "${BLUE}8. Build Verification${NC}"
echo "---------------------"

check "Build directory exists" "test -d '$BUILD_DIR'"
check "No executables" "! find '$BUILD_DIR' -type f -executable | grep -q ."
check "No hidden files" "! find '$BUILD_DIR' -name '.*' | grep -q ."

echo ""

# 9. Cache Headers
echo -e "${BLUE}9. Cache Configuration${NC}"
echo "----------------------"

if [ -n "$HEADERS" ]; then
    # Test a hashed asset
    HASHED_ASSET=$(find "$BUILD_DIR" -name "*.[0-9a-f]*.*" -type f | head -1 || echo "")
    if [ -n "$HASHED_ASSET" ]; then
        ASSET_PATH=${HASHED_ASSET#$BUILD_DIR}
        ASSET_HEADERS=$(curl -sI "https://$DOMAIN$ASSET_PATH" 2>/dev/null || echo "")
        check_warn "Immutable caching" "echo '$ASSET_HEADERS' | grep -i 'cache-control.*immutable'"
    fi
    
    # Test HTML (should not be cached)
    HTML_HEADERS=$(curl -sI "https://$DOMAIN/index.html" 2>/dev/null || echo "")
    check "HTML not cached" "echo '$HTML_HEADERS' | grep -i 'cache-control.*no-cache'"
fi

echo ""

# 10. Quick Manifest Check
echo -e "${BLUE}10. Quick Security Checks${NC}"
echo "-------------------------"

# Test commands from the requirements
echo "Testing live domain responses..."

# Check headers
echo -n "Headers present: "
HEADER_COUNT=$(curl -sI "https://$DOMAIN" 2>/dev/null | grep -ci "strict-transport\|content-security\|x-frame\|x-content-type\|referrer\|permissions\|cross-origin" || echo "0")
if [ "$HEADER_COUNT" -ge 7 ]; then
    echo -e "${GREEN}✅ $HEADER_COUNT security headers${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${YELLOW}⚠️  Only $HEADER_COUNT security headers${NC}"
    ((CHECKS_WARNING++))
fi

# Check for scripts in HTML
echo -n "No scripts in HTML: "
SCRIPT_CHECK=$(curl -s "https://$DOMAIN" 2>/dev/null | grep -E '<script|onload|onclick' || echo "")
if [ -z "$SCRIPT_CHECK" ]; then
    echo -e "${GREEN}✅ Clean${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}❌ Scripts found${NC}"
    ((CHECKS_FAILED++))
fi

echo ""

# Summary
echo -e "${BLUE}=== Security Check Summary ===${NC}"
echo "================================"
echo -e "Checks passed:  ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Checks failed:  ${RED}$CHECKS_FAILED${NC}"
echo -e "Warnings:       ${YELLOW}$CHECKS_WARNING${NC}"
echo ""

# Overall status
if [ $CHECKS_FAILED -eq 0 ]; then
    if [ $CHECKS_WARNING -eq 0 ]; then
        echo -e "${GREEN}✅ ALL SECURITY CHECKS PASSED${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠️  PASSED WITH WARNINGS${NC}"
        echo "Review warnings for production deployment"
        exit 0
    fi
else
    echo -e "${RED}❌ SECURITY CHECKS FAILED${NC}"
    echo "Fix failures before deployment!"
    exit 1
fi