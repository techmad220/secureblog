#!/usr/bin/env bash
# validate-security-headers.sh - Validate security headers configuration
set -euo pipefail

SITE_URL="${1:-https://secureblog.com}"
CONFIG_DIR="${2:-dist/public}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔒 Security Headers Validation${NC}"
echo "=============================="
echo "Site URL: $SITE_URL"
echo "Config Dir: $CONFIG_DIR"
echo ""

# Initialize results
validation_passed=true
total_checks=0
passed_checks=0
warnings=0
errors=0

# Arrays to store results
declare -a missing_headers=()
declare -a incorrect_headers=()
declare -a warning_headers=()
declare -a passed_headers=()

# Function to check a header
check_header() {
    local header_name="$1"
    local expected_pattern="$2"
    local severity="${3:-error}"  # error, warning, info
    local description="$4"
    
    ((total_checks++))
    
    echo "🔍 Checking: $header_name"
    
    # Get headers from site
    local headers
    if ! headers=$(curl -sI "$SITE_URL" --max-time 10 2>/dev/null); then
        echo -e "${RED}❌ Unable to fetch headers from $SITE_URL${NC}"
        echo "This may be expected if the site isn't deployed yet"
        echo "Checking configuration files instead..."
        return 1
    fi
    
    # Check if header exists
    local header_value
    header_value=$(echo "$headers" | grep -i "^$header_name:" | head -1 | cut -d: -f2- | sed 's/^ *//' | tr -d '\r\n' || echo "")
    
    if [ -z "$header_value" ]; then
        case $severity in
            "error")
                echo -e "${RED}❌ MISSING: $header_name${NC}"
                missing_headers+=("$header_name: $description")
                ((errors++))
                validation_passed=false
                ;;
            "warning")
                echo -e "${YELLOW}⚠️  MISSING: $header_name${NC}"
                warning_headers+=("$header_name: $description (missing)")
                ((warnings++))
                ;;
            *)
                echo -e "${BLUE}ℹ️  INFO: $header_name not found${NC}"
                ;;
        esac
        return 1
    fi
    
    # Check if header matches expected pattern
    if [[ "$header_value" =~ $expected_pattern ]]; then
        echo -e "${GREEN}✅ PASS: $header_name: $header_value${NC}"
        passed_headers+=("$header_name: $header_value")
        ((passed_checks++))
        return 0
    else
        case $severity in
            "error")
                echo -e "${RED}❌ INCORRECT: $header_name: $header_value${NC}"
                echo -e "${RED}   Expected pattern: $expected_pattern${NC}"
                incorrect_headers+=("$header_name: '$header_value' (expected: $expected_pattern)")
                ((errors++))
                validation_passed=false
                ;;
            "warning")
                echo -e "${YELLOW}⚠️  SUBOPTIMAL: $header_name: $header_value${NC}"
                echo -e "${YELLOW}   Recommended pattern: $expected_pattern${NC}"
                warning_headers+=("$header_name: '$header_value' (recommended: $expected_pattern)")
                ((warnings++))
                ;;
            *)
                echo -e "${BLUE}ℹ️  INFO: $header_name: $header_value${NC}"
                ;;
        esac
        return 1
    fi
}

# Function to check configuration files for header settings
check_config_files() {
    echo -e "${BLUE}🔍 Checking configuration files...${NC}"
    echo ""
    
    # Check .htaccess
    if [ -f "$CONFIG_DIR/.htaccess" ]; then
        echo "Found Apache .htaccess configuration:"
        
        # Check for CSP in .htaccess
        if grep -q "Content-Security-Policy" "$CONFIG_DIR/.htaccess"; then
            local csp_value
            csp_value=$(grep "Content-Security-Policy" "$CONFIG_DIR/.htaccess" | sed 's/.*Content-Security-Policy[[:space:]]*"\([^"]*\)".*/\1/')
            echo -e "${GREEN}✅ CSP configured: $csp_value${NC}"
            
            # Validate CSP has minimal required directives
            if [[ "$csp_value" =~ default-src[[:space:]]+\'none\' ]] || [[ "$csp_value" =~ default-src[[:space:]]+\'self\' ]]; then
                echo -e "${GREEN}✅ CSP has secure default-src${NC}"
            else
                echo -e "${YELLOW}⚠️  CSP default-src should be 'none' or 'self'${NC}"
            fi
        else
            echo -e "${RED}❌ No CSP found in .htaccess${NC}"
        fi
        
        # Check for HSTS
        if grep -q "Strict-Transport-Security" "$CONFIG_DIR/.htaccess"; then
            echo -e "${GREEN}✅ HSTS configured in .htaccess${NC}"
        else
            echo -e "${RED}❌ No HSTS found in .htaccess${NC}"
        fi
        
        # Check for X-Frame-Options
        if grep -q "X-Frame-Options" "$CONFIG_DIR/.htaccess"; then
            echo -e "${GREEN}✅ X-Frame-Options configured in .htaccess${NC}"
        else
            echo -e "${RED}❌ No X-Frame-Options found in .htaccess${NC}"
        fi
        
        echo ""
    fi
    
    # Check nginx config
    if [ -f "$CONFIG_DIR/nginx-cache.conf" ]; then
        echo "Found nginx configuration:"
        
        if grep -q "add_header.*Content-Security-Policy" "$CONFIG_DIR/nginx-cache.conf"; then
            echo -e "${GREEN}✅ CSP configured in nginx config${NC}"
        else
            echo -e "${YELLOW}⚠️  No CSP found in nginx config${NC}"
        fi
        
        if grep -q "add_header.*X-Frame-Options" "$CONFIG_DIR/nginx-cache.conf"; then
            echo -e "${GREEN}✅ X-Frame-Options configured in nginx config${NC}"
        else
            echo -e "${YELLOW}⚠️  No X-Frame-Options found in nginx config${NC}"
        fi
        
        echo ""
    fi
}

echo "🚀 Starting security headers validation..."
echo ""

# Test if site is reachable first
if curl -sI "$SITE_URL" --max-time 10 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Site is reachable: $SITE_URL${NC}"
    echo ""
    
    # CRITICAL SECURITY HEADERS
    echo -e "${BLUE}== CRITICAL SECURITY HEADERS ==${NC}"
    check_header "Content-Security-Policy" "default-src 'none'|default-src 'self'" "error" "Prevents XSS and code injection attacks"
    check_header "X-Frame-Options" "DENY|SAMEORIGIN" "error" "Prevents clickjacking attacks"
    check_header "X-Content-Type-Options" "nosniff" "error" "Prevents MIME type sniffing attacks"
    check_header "Strict-Transport-Security" "max-age=[0-9]+.*" "error" "Enforces HTTPS connections"
    check_header "Referrer-Policy" "strict-origin-when-cross-origin|no-referrer|strict-origin" "error" "Controls referrer information leakage"
    
    echo ""
    echo -e "${BLUE}== RECOMMENDED SECURITY HEADERS ==${NC}"
    check_header "X-XSS-Protection" "1; mode=block|0" "warning" "Legacy XSS protection (CSP is preferred)"
    check_header "Permissions-Policy" ".*" "warning" "Controls browser feature access"
    check_header "Cross-Origin-Embedder-Policy" "require-corp|credentialless" "warning" "Controls cross-origin embedding"
    check_header "Cross-Origin-Opener-Policy" "same-origin|same-origin-allow-popups" "warning" "Controls cross-origin window access"
    check_header "Cross-Origin-Resource-Policy" "same-origin|cross-origin" "warning" "Controls cross-origin resource access"
    
    echo ""
    echo -e "${BLUE}== CACHE AND PERFORMANCE HEADERS ==${NC}"
    check_header "Cache-Control" ".*" "info" "Controls caching behavior"
    check_header "Vary" ".*" "info" "Controls cache variation"
    
    echo ""
else
    echo -e "${YELLOW}⚠️  Site not reachable: $SITE_URL${NC}"
    echo "This is expected if the site hasn't been deployed yet"
    echo "Checking configuration files only..."
    echo ""
fi

# Check configuration files
check_config_files

# Detailed CSP validation if we can reach the site
if curl -sI "$SITE_URL" --max-time 10 >/dev/null 2>&1; then
    echo -e "${BLUE}🔍 Detailed CSP Analysis...${NC}"
    
    csp_header=$(curl -sI "$SITE_URL" | grep -i "Content-Security-Policy:" | cut -d: -f2- | sed 's/^ *//' | tr -d '\r\n')
    
    if [ -n "$csp_header" ]; then
        echo "CSP: $csp_header"
        echo ""
        
        # Check for dangerous CSP settings
        if [[ "$csp_header" =~ unsafe-inline ]]; then
            echo -e "${YELLOW}⚠️  WARNING: CSP allows 'unsafe-inline' - this reduces XSS protection${NC}"
        fi
        
        if [[ "$csp_header" =~ unsafe-eval ]]; then
            echo -e "${RED}❌ DANGER: CSP allows 'unsafe-eval' - this is dangerous${NC}"
        fi
        
        if [[ "$csp_header" =~ \\* ]]; then
            echo -e "${YELLOW}⚠️  WARNING: CSP uses wildcard (*) - consider being more specific${NC}"
        fi
        
        # Check required directives
        required_directives=("default-src" "script-src" "style-src" "img-src")
        for directive in "${required_directives[@]}"; do
            if [[ "$csp_header" =~ $directive ]]; then
                echo -e "${GREEN}✅ CSP includes $directive directive${NC}"
            else
                if [ "$directive" = "default-src" ]; then
                    echo -e "${RED}❌ CSP missing critical $directive directive${NC}"
                else
                    echo -e "${YELLOW}⚠️  CSP missing recommended $directive directive${NC}"
                fi
            fi
        done
    fi
    echo ""
fi

# Generate comprehensive report
REPORT_FILE="$CONFIG_DIR/security-headers-report.md"
cat > "$REPORT_FILE" << EOF
# Security Headers Validation Report

**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Site URL**: $SITE_URL
**Total Checks**: $total_checks
**Passed**: $passed_checks
**Warnings**: $warnings
**Errors**: $errors

## Summary

$(if [ "$validation_passed" = true ]; then
    echo "✅ **VALIDATION PASSED** - All critical security headers are properly configured"
else
    echo "❌ **VALIDATION FAILED** - Critical security headers are missing or misconfigured"
fi)

$(if [ ${#missing_headers[@]} -gt 0 ]; then
    echo "## Missing Headers (Critical)"
    echo ""
    printf '- %s\n' "${missing_headers[@]}"
    echo ""
fi)

$(if [ ${#incorrect_headers[@]} -gt 0 ]; then
    echo "## Incorrect Headers (Critical)"
    echo ""
    printf '- %s\n' "${incorrect_headers[@]}"
    echo ""
fi)

$(if [ ${#warning_headers[@]} -gt 0 ]; then
    echo "## Warning Headers (Recommended)"
    echo ""
    printf '- %s\n' "${warning_headers[@]}"
    echo ""
fi)

$(if [ ${#passed_headers[@]} -gt 0 ]; then
    echo "## Correctly Configured Headers"
    echo ""
    printf '- %s\n' "${passed_headers[@]}"
    echo ""
fi)

## Security Headers Checklist

### Critical Headers (Must Have)
- [ ] Content-Security-Policy: Prevents XSS and injection attacks
- [ ] X-Frame-Options: Prevents clickjacking
- [ ] X-Content-Type-Options: Prevents MIME sniffing
- [ ] Strict-Transport-Security: Enforces HTTPS
- [ ] Referrer-Policy: Controls referrer leakage

### Recommended Headers (Should Have)
- [ ] X-XSS-Protection: Legacy XSS protection
- [ ] Permissions-Policy: Controls browser features
- [ ] Cross-Origin-Embedder-Policy: Cross-origin embedding control
- [ ] Cross-Origin-Opener-Policy: Cross-origin window control
- [ ] Cross-Origin-Resource-Policy: Cross-origin resource control

### Performance Headers (Nice to Have)
- [ ] Cache-Control: Caching behavior
- [ ] Vary: Cache variation

## Recommendations

$(if [ ${#missing_headers[@]} -gt 0 ] || [ ${#incorrect_headers[@]} -gt 0 ]; then
    echo "### Immediate Actions Required"
    echo "1. Add missing critical security headers"
    echo "2. Fix incorrectly configured headers" 
    echo "3. Test all changes with this validation script"
    echo "4. Deploy and verify headers are applied correctly"
    echo ""
fi)

### Best Practices
1. Use \`default-src 'none'\` in CSP and explicitly allow only what's needed
2. Set \`X-Frame-Options: DENY\` unless you need embedding
3. Enable HSTS with \`preload\` and submit to browser preload lists
4. Use \`Referrer-Policy: strict-origin-when-cross-origin\` for privacy
5. Regularly test headers with tools like securityheaders.com

## Configuration Files Checked
- Apache: \`.htaccess\`
- Nginx: \`nginx-cache.conf\`

EOF

echo "📄 Detailed report saved to: $REPORT_FILE"

# Final summary
echo ""
echo -e "${BLUE}📊 VALIDATION SUMMARY${NC}"
echo "===================="
echo -e "Total Checks: $total_checks"
echo -e "${GREEN}Passed: $passed_checks${NC}"
echo -e "${YELLOW}Warnings: $warnings${NC}"
echo -e "${RED}Errors: $errors${NC}"
echo ""

if [ "$validation_passed" = true ]; then
    echo -e "${GREEN}✅ SECURITY HEADERS VALIDATION PASSED${NC}"
    echo -e "${GREEN}🛡️ All critical security headers are properly configured${NC}"
    exit 0
else
    echo -e "${RED}❌ SECURITY HEADERS VALIDATION FAILED${NC}"
    echo -e "${RED}🚨 Critical security headers are missing or misconfigured${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Action Required:${NC}"
    echo "  1. Review the errors listed above"
    echo "  2. Update your web server configuration"
    echo "  3. Deploy the changes"
    echo "  4. Re-run this validation script"
    echo ""
    echo -e "${BLUE}ℹ️  See detailed report: $REPORT_FILE${NC}"
    exit 1
fi