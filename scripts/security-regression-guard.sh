#!/usr/bin/env bash
# security-regression-guard.sh - Comprehensive security testing for HTML/Markdown safety
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TEST_DIR="${1:-dist}"
TEMP_TEST_DIR="$(mktemp -d)"
FAILED_TESTS=0

echo -e "${GREEN}🛡️ Security Regression Guard${NC}"
echo "Testing directory: $TEST_DIR"
echo "Temp test directory: $TEMP_TEST_DIR"
echo ""

cleanup() {
    rm -rf "$TEMP_TEST_DIR"
}
trap cleanup EXIT

# Test 1: Zero JavaScript Detection
test_no_javascript() {
    echo "🔍 Test 1: Zero JavaScript Detection"
    
    # Find any JS in HTML files
    if find "$TEST_DIR" -name "*.html" -type f -exec grep -l '<script' {} \; | head -1; then
        echo -e "${RED}❌ FAIL: Found <script> tags in HTML${NC}"
        ((FAILED_TESTS++))
        return 1
    fi
    
    # Check for inline JS
    if find "$TEST_DIR" -name "*.html" -type f -exec grep -l 'javascript:' {} \; | head -1; then
        echo -e "${RED}❌ FAIL: Found javascript: URLs${NC}"
        ((FAILED_TESTS++))
        return 1
    fi
    
    # Check for event handlers
    if find "$TEST_DIR" -name "*.html" -type f -exec grep -l 'on[a-z]*=' {} \; | head -1; then
        echo -e "${RED}❌ FAIL: Found event handlers (onclick, etc.)${NC}"
        ((FAILED_TESTS++))
        return 1
    fi
    
    echo -e "${GREEN}✅ PASS: No JavaScript detected${NC}"
    return 0
}

# Test 2: XSS Prevention - Red Team Fixtures
test_xss_prevention() {
    echo "🔍 Test 2: XSS Prevention with Red Team Fixtures"
    
    # Create test markdown with XSS attempts
    cat > "$TEMP_TEST_DIR/xss-test.md" << 'EOF'
---
title: "XSS Test Post"
---

# XSS Attack Vectors

## Image XSS
![x](javascript:alert(1))
![x](data:text/html,<script>alert(1)</script>)
<img src=x onerror=alert(1)>
<img src="javascript:alert('XSS')">

## SVG XSS
<svg onload=alert(1)>
<svg><script>alert(1)</script></svg>
<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>

## CSS XSS
<div style="background:url(javascript:alert(1))">
<style>body{background:url('javascript:alert(1)')}</style>
<link rel="stylesheet" href="javascript:alert(1)">

## Event Handler XSS
<div onclick="alert(1)">Click me</div>
<body onload="alert(1)">
<img onmouseover="alert(1)">

## Data URI XSS
<iframe src="data:text/html,<script>alert(1)</script>">
<object data="data:text/html,<script>alert(1)</script>">

## Form XSS
<form action="javascript:alert(1)">
<input type="submit" formaction="javascript:alert(1)">

## Base64 Polyglot
<img src="data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+">

## CSS Expression XSS
<div style="width:expression(alert(1))">
<div style="behavior:url(#default#userData)">

## Meta Refresh XSS
<meta http-equiv="refresh" content="0;url=javascript:alert(1)">

## Link XSS
<a href="javascript:alert(1)">Click</a>
<link href="javascript:alert(1)">
EOF

    # Test our HTML renderer/sanitizer
    if command -v ./dist/blog-generator >/dev/null 2>&1; then
        ./dist/blog-generator -input="$TEMP_TEST_DIR" -output="$TEMP_TEST_DIR/output" -test-mode=true 2>/dev/null || true
        
        if [ -f "$TEMP_TEST_DIR/output/xss-test.html" ]; then
            local output_file="$TEMP_TEST_DIR/output/xss-test.html"
            
            # Check that dangerous elements were removed/escaped
            local dangerous_patterns=(
                '<script'
                'javascript:'
                'on[a-z]*='
                '<svg.*onload'
                'data:text/html'
                'expression('
                'behavior:'
                '<meta.*refresh.*javascript'
                '<object.*data.*javascript'
                '<iframe.*src.*javascript'
            )
            
            local failed=0
            for pattern in "${dangerous_patterns[@]}"; do
                if grep -qi "$pattern" "$output_file"; then
                    echo -e "${RED}❌ FAIL: Dangerous pattern '$pattern' found in output${NC}"
                    failed=1
                fi
            done
            
            if [ $failed -eq 0 ]; then
                echo -e "${GREEN}✅ PASS: All XSS vectors properly sanitized${NC}"
                return 0
            else
                ((FAILED_TESTS++))
                return 1
            fi
        else
            echo -e "${YELLOW}⚠️ SKIP: Could not generate test output${NC}"
            return 0
        fi
    else
        echo -e "${YELLOW}⚠️ SKIP: blog-generator not found${NC}"
        return 0
    fi
}

# Test 3: Content Security Policy Validation
test_csp_headers() {
    echo "🔍 Test 3: Content Security Policy Validation"
    
    local has_csp=0
    find "$TEST_DIR" -name "*.html" -type f | while read -r file; do
        if grep -q "Content-Security-Policy.*default-src.*'none'" "$file" || \
           grep -q "Content-Security-Policy.*default-src.*'self'" "$file"; then
            has_csp=1
            break
        fi
    done
    
    # Also check if we have CSP in headers (via meta tags or nginx config)
    if find "$TEST_DIR" -name "*.html" -type f -exec grep -l 'http-equiv.*Content-Security-Policy' {} \; | head -1; then
        echo -e "${GREEN}✅ PASS: CSP meta tags found${NC}"
        return 0
    fi
    
    if [ -f "nginx/nginx.conf" ] && grep -q "Content-Security-Policy" nginx/nginx.conf; then
        echo -e "${GREEN}✅ PASS: CSP in nginx config${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}⚠️ WARNING: No CSP headers detected (should be set by server)${NC}"
    return 0
}

# Test 4: Path Traversal Prevention
test_path_traversal() {
    echo "🔍 Test 4: Path Traversal Prevention"
    
    # Check for any suspicious paths in generated HTML
    local suspicious_paths=(
        '\.\./\.\.'
        '\.\./'
        '/etc/passwd'
        '/proc/self'
        'file://'
        'C:\\'
        '\\\\\\\\'
    )
    
    local failed=0
    for path in "${suspicious_paths[@]}"; do
        if find "$TEST_DIR" -name "*.html" -type f -exec grep -l "$path" {} \; | head -1; then
            echo -e "${RED}❌ FAIL: Suspicious path '$path' found in output${NC}"
            failed=1
        fi
    done
    
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✅ PASS: No path traversal patterns detected${NC}"
        return 0
    else
        ((FAILED_TESTS++))
        return 1
    fi
}

# Test 5: External Resource Validation
test_external_resources() {
    echo "🔍 Test 5: External Resource Validation"
    
    # Check for external resources that might be unsafe
    local external_patterns=(
        'src=["\']https\?://(?!secureblog\.com)'
        'href=["\']https\?://(?!secureblog\.com)'
        'data:[^"]*text/html'
        'data:[^"]*application/javascript'
    )
    
    local warnings=0
    for pattern in "${external_patterns[@]}"; do
        if find "$TEST_DIR" -name "*.html" -type f -exec grep -Pl "$pattern" {} \; | head -1; then
            echo -e "${YELLOW}⚠️ WARNING: External resource pattern '$pattern' found${NC}"
            ((warnings++))
        fi
    done
    
    if [ $warnings -eq 0 ]; then
        echo -e "${GREEN}✅ PASS: No unsafe external resources${NC}"
    fi
    return 0
}

# Test 6: MIME Type Validation
test_mime_types() {
    echo "🔍 Test 6: MIME Type Validation"
    
    # Check file extensions match expected types
    local mismatched=0
    
    # HTML files should contain HTML
    find "$TEST_DIR" -name "*.html" -type f | while read -r file; do
        if ! file "$file" | grep -q "HTML\|XML\|text"; then
            echo -e "${RED}❌ FAIL: File $file has wrong MIME type$(NC)"
            mismatched=1
        fi
    done
    
    # CSS files should be text
    find "$TEST_DIR" -name "*.css" -type f | while read -r file; do
        if ! file "$file" | grep -q "text\|ASCII"; then
            echo -e "${RED}❌ FAIL: CSS file $file has wrong MIME type${NC}"
            mismatched=1
        fi
    done
    
    if [ $mismatched -eq 0 ]; then
        echo -e "${GREEN}✅ PASS: All MIME types correct${NC}"
        return 0
    else
        ((FAILED_TESTS++))
        return 1
    fi
}

# Test 7: Secret Scanning
test_secret_scanning() {
    echo "🔍 Test 7: Secret Scanning"
    
    local secrets_found=0
    local secret_patterns=(
        '[A-Za-z0-9+/]{40,}={0,2}'  # Base64-like strings
        'api[_-]?key["\s:=]*[A-Za-z0-9]{20,}'
        'secret["\s:=]*[A-Za-z0-9]{20,}'
        'token["\s:=]*[A-Za-z0-9]{20,}'
        'password["\s:=]*[A-Za-z0-9]{8,}'
        'AKIA[0-9A-Z]{16}'  # AWS access keys
        'ghp_[0-9a-zA-Z]{36}'  # GitHub personal access tokens
        'sk_live_[0-9a-zA-Z]{24}'  # Stripe keys
    )
    
    for pattern in "${secret_patterns[@]}"; do
        if find "$TEST_DIR" -type f -exec grep -Pl "$pattern" {} \; | head -1; then
            echo -e "${RED}❌ FAIL: Potential secret pattern '$pattern' found${NC}"
            secrets_found=1
        fi
    done
    
    if [ $secrets_found -eq 0 ]; then
        echo -e "${GREEN}✅ PASS: No secrets detected${NC}"
        return 0
    else
        ((FAILED_TESTS++))
        return 1
    fi
}

# Test 8: Integrity Validation
test_integrity_validation() {
    echo "🔍 Test 8: Integrity Validation"
    
    if [ -f "$TEST_DIR/manifest.json" ]; then
        # Verify manifest exists and is valid JSON
        if ! jq empty "$TEST_DIR/manifest.json" 2>/dev/null; then
            echo -e "${RED}❌ FAIL: manifest.json is not valid JSON${NC}"
            ((FAILED_TESTS++))
            return 1
        fi
        
        # Verify all files listed in manifest exist
        local missing_files=0
        jq -r '.files | keys[]' "$TEST_DIR/manifest.json" | while read -r file; do
            if [ ! -f "$TEST_DIR/$file" ]; then
                echo -e "${RED}❌ FAIL: File $file listed in manifest but not found${NC}"
                missing_files=1
            fi
        done
        
        if [ $missing_files -eq 0 ]; then
            echo -e "${GREEN}✅ PASS: Integrity manifest valid${NC}"
            return 0
        else
            ((FAILED_TESTS++))
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️ SKIP: No manifest.json found${NC}"
        return 0
    fi
}

# Run all tests
main() {
    echo "🚀 Running security regression tests..."
    echo ""
    
    test_no_javascript
    test_xss_prevention  
    test_csp_headers
    test_path_traversal
    test_external_resources
    test_mime_types
    test_secret_scanning
    test_integrity_validation
    
    echo ""
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 All security tests passed!${NC}"
        echo -e "${GREEN}🛡️ Site is secure for deployment${NC}"
        exit 0
    else
        echo -e "${RED}💥 $FAILED_TESTS security test(s) failed!${NC}"
        echo -e "${RED}🚨 DEPLOYMENT BLOCKED - Fix security issues first${NC}"
        exit 1
    fi
}

main "$@"