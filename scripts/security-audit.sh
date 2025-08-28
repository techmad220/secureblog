#!/bin/bash
# Comprehensive security audit script with plugin architecture

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Audit results
AUDIT_PASSED=0
AUDIT_WARNINGS=0
AUDIT_FAILED=0

# Plugin directory
PLUGIN_DIR="${PLUGIN_DIR:-./plugins/audit}"

# Load audit plugins
load_audit_plugins() {
    mkdir -p "$PLUGIN_DIR"
    
    for plugin in "$PLUGIN_DIR"/*.sh; do
        if [ -f "$plugin" ]; then
            source "$plugin"
            echo -e "${BLUE}✓ Loaded plugin: $(basename $plugin)${NC}"
        fi
    done
}

# Audit: No JavaScript Policy
audit_no_javascript() {
    echo -e "\n${BLUE}🔍 Auditing: No JavaScript Policy${NC}"
    
    local violations=0
    
    # Check templates for script tags
    if find templates content -name "*.html" -o -name "*.tmpl" 2>/dev/null | xargs grep -l '<script' 2>/dev/null; then
        echo -e "${RED}  ❌ Found <script> tags in templates${NC}"
        ((violations++))
    fi
    
    # Check for inline JavaScript
    if find templates content -name "*.html" -o -name "*.tmpl" 2>/dev/null | xargs grep -E 'on(click|load|error|submit|change)=' 2>/dev/null; then
        echo -e "${RED}  ❌ Found inline JavaScript handlers${NC}"
        ((violations++))
    fi
    
    # Check for javascript: URLs
    if find templates content dist -name "*.html" 2>/dev/null | xargs grep -l 'javascript:' 2>/dev/null; then
        echo -e "${RED}  ❌ Found javascript: URLs${NC}"
        ((violations++))
    fi
    
    # Check CSP allows no scripts
    if [ -f "security-headers.conf" ]; then
        if grep -q "script-src" security-headers.conf && ! grep -q "script-src 'none'" security-headers.conf; then
            echo -e "${RED}  ❌ CSP allows JavaScript execution${NC}"
            ((violations++))
        fi
    fi
    
    if [ $violations -eq 0 ]; then
        echo -e "${GREEN}  ✅ No JavaScript violations found${NC}"
        ((AUDIT_PASSED++))
    else
        echo -e "${RED}  ❌ Found $violations JavaScript violations${NC}"
        ((AUDIT_FAILED++))
    fi
}

# Audit: Security Headers
audit_security_headers() {
    echo -e "\n${BLUE}🔍 Auditing: Security Headers Configuration${NC}"
    
    local issues=0
    
    required_headers=(
        "Content-Security-Policy"
        "X-Frame-Options"
        "X-Content-Type-Options"
        "Strict-Transport-Security"
        "Referrer-Policy"
        "Permissions-Policy"
    )
    
    for header in "${required_headers[@]}"; do
        if ! grep -q "$header" security-headers.conf nginx-hardened.conf 2>/dev/null; then
            echo -e "${YELLOW}  ⚠️  Missing header: $header${NC}"
            ((issues++))
        fi
    done
    
    # Check HSTS preload
    if ! grep -q "preload" security-headers.conf nginx-hardened.conf 2>/dev/null; then
        echo -e "${YELLOW}  ⚠️  HSTS preload not configured${NC}"
        ((AUDIT_WARNINGS++))
    fi
    
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}  ✅ All security headers configured${NC}"
        ((AUDIT_PASSED++))
    else
        echo -e "${YELLOW}  ⚠️  $issues security headers missing${NC}"
        ((AUDIT_WARNINGS++))
    fi
}

# Audit: Dependency Security
audit_dependencies() {
    echo -e "\n${BLUE}🔍 Auditing: Dependencies${NC}"
    
    # Go dependencies
    if [ -f "go.mod" ]; then
        echo "  Checking Go dependencies..."
        
        # Check for vulnerabilities
        if command -v govulncheck &> /dev/null; then
            if govulncheck -json ./... 2>/dev/null | jq -e '.Vulns | length > 0' > /dev/null; then
                echo -e "${RED}  ❌ Vulnerable Go dependencies found${NC}"
                ((AUDIT_FAILED++))
            else
                echo -e "${GREEN}  ✅ No known Go vulnerabilities${NC}"
                ((AUDIT_PASSED++))
            fi
        else
            echo -e "${YELLOW}  ⚠️  govulncheck not installed${NC}"
            ((AUDIT_WARNINGS++))
        fi
        
        # Verify module integrity
        if ! go mod verify 2>/dev/null; then
            echo -e "${RED}  ❌ Go module verification failed${NC}"
            ((AUDIT_FAILED++))
        fi
    fi
    
    # GitHub Actions dependencies
    echo "  Checking GitHub Actions..."
    unpinned_actions=0
    for workflow in .github/workflows/*.yml; do
        if [ -f "$workflow" ]; then
            if grep -E "uses: [^@]+@(main|master|v[0-9]+)\s*$" "$workflow" > /dev/null; then
                echo -e "${YELLOW}  ⚠️  Unpinned actions in $(basename $workflow)${NC}"
                ((unpinned_actions++))
            fi
        fi
    done
    
    if [ $unpinned_actions -gt 0 ]; then
        echo -e "${YELLOW}  ⚠️  Found $unpinned_actions unpinned GitHub Actions${NC}"
        ((AUDIT_WARNINGS++))
    else
        echo -e "${GREEN}  ✅ All GitHub Actions are pinned${NC}"
        ((AUDIT_PASSED++))
    fi
}

# Audit: File Permissions
audit_file_permissions() {
    echo -e "\n${BLUE}🔍 Auditing: File Permissions${NC}"
    
    local issues=0
    
    # Check for world-writable files
    world_writable=$(find . -type f -perm -002 2>/dev/null | wc -l)
    if [ $world_writable -gt 0 ]; then
        echo -e "${RED}  ❌ Found $world_writable world-writable files${NC}"
        ((issues++))
    fi
    
    # Check for setuid/setgid files
    suid_files=$(find . -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | wc -l)
    if [ $suid_files -gt 0 ]; then
        echo -e "${RED}  ❌ Found $suid_files setuid/setgid files${NC}"
        ((issues++))
    fi
    
    # Check script permissions
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            perms=$(stat -c %a "$script")
            if [ "$perms" != "755" ] && [ "$perms" != "750" ] && [ "$perms" != "700" ]; then
                echo -e "${YELLOW}  ⚠️  Unusual permissions on $script: $perms${NC}"
                ((AUDIT_WARNINGS++))
            fi
        fi
    done
    
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}  ✅ File permissions look good${NC}"
        ((AUDIT_PASSED++))
    else
        echo -e "${RED}  ❌ File permission issues found${NC}"
        ((AUDIT_FAILED++))
    fi
}

# Audit: Secrets Detection
audit_secrets() {
    echo -e "\n${BLUE}🔍 Auditing: Secrets & Sensitive Data${NC}"
    
    local found_secrets=0
    
    # Pattern list for secrets
    patterns=(
        "password.*=.*['\"]"
        "secret.*=.*['\"]"
        "api[_-]?key.*=.*['\"]"
        "token.*=.*['\"]"
        "BEGIN.*PRIVATE KEY"
        "ssh-rsa"
        "ghp_[a-zA-Z0-9]{36}"
        "gho_[a-zA-Z0-9]{36}"
    )
    
    for pattern in "${patterns[@]}"; do
        if find . -type f -name "*.go" -o -name "*.js" -o -name "*.yml" -o -name "*.yaml" -o -name "*.conf" 2>/dev/null | \
           xargs grep -iE "$pattern" 2>/dev/null | \
           grep -v "example\|test\|fake\|dummy\|TODO" > /dev/null; then
            echo -e "${RED}  ❌ Potential secret found matching: $pattern${NC}"
            ((found_secrets++))
        fi
    done
    
    if [ $found_secrets -eq 0 ]; then
        echo -e "${GREEN}  ✅ No secrets detected${NC}"
        ((AUDIT_PASSED++))
    else
        echo -e "${RED}  ❌ Found $found_secrets potential secrets${NC}"
        ((AUDIT_FAILED++))
    fi
}

# Audit: Build Reproducibility
audit_build_reproducibility() {
    echo -e "\n${BLUE}🔍 Auditing: Build Reproducibility${NC}"
    
    if [ -f "go.mod" ]; then
        # Check for build flags
        if grep -q "trimpath" Makefile build.sh .github/workflows/*.yml 2>/dev/null; then
            echo -e "${GREEN}  ✅ Using -trimpath for reproducible builds${NC}"
            ((AUDIT_PASSED++))
        else
            echo -e "${YELLOW}  ⚠️  Not using -trimpath flag${NC}"
            ((AUDIT_WARNINGS++))
        fi
        
        # Check for mod=readonly
        if grep -q "mod=readonly" Makefile build.sh .github/workflows/*.yml 2>/dev/null; then
            echo -e "${GREEN}  ✅ Using -mod=readonly${NC}"
            ((AUDIT_PASSED++))
        else
            echo -e "${YELLOW}  ⚠️  Not using -mod=readonly${NC}"
            ((AUDIT_WARNINGS++))
        fi
    fi
    
    # Check for integrity manifest
    if [ -f "dist/integrity-manifest.json" ] || [ -f "scripts/generate-manifest.py" ]; then
        echo -e "${GREEN}  ✅ Integrity manifest system present${NC}"
        ((AUDIT_PASSED++))
    else
        echo -e "${YELLOW}  ⚠️  No integrity manifest system${NC}"
        ((AUDIT_WARNINGS++))
    fi
}

# Audit: TLS Configuration
audit_tls_config() {
    echo -e "\n${BLUE}🔍 Auditing: TLS Configuration${NC}"
    
    if [ -f "nginx-hardened.conf" ]; then
        # Check TLS version
        if grep -q "TLSv1.3" nginx-hardened.conf; then
            echo -e "${GREEN}  ✅ TLS 1.3 only${NC}"
            ((AUDIT_PASSED++))
        else
            echo -e "${RED}  ❌ Not using TLS 1.3 only${NC}"
            ((AUDIT_FAILED++))
        fi
        
        # Check OCSP stapling
        if grep -q "ssl_stapling on" nginx-hardened.conf; then
            echo -e "${GREEN}  ✅ OCSP stapling enabled${NC}"
            ((AUDIT_PASSED++))
        else
            echo -e "${YELLOW}  ⚠️  OCSP stapling not enabled${NC}"
            ((AUDIT_WARNINGS++))
        fi
    fi
}

# Generate audit report
generate_report() {
    local report_file="audit-report-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "summary": {
    "passed": $AUDIT_PASSED,
    "warnings": $AUDIT_WARNINGS,
    "failed": $AUDIT_FAILED,
    "score": $(( (AUDIT_PASSED * 100) / (AUDIT_PASSED + AUDIT_WARNINGS + AUDIT_FAILED) ))
  },
  "commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "branch": "$(git branch --show-current 2>/dev/null || echo 'unknown')"
}
EOF
    
    echo -e "\n${BLUE}📄 Report saved to: $report_file${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   SecureBlog Security Audit${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Load plugins
    load_audit_plugins
    
    # Run audit checks
    audit_no_javascript
    audit_security_headers
    audit_dependencies
    audit_file_permissions
    audit_secrets
    audit_build_reproducibility
    audit_tls_config
    
    # Summary
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   Audit Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ Passed: $AUDIT_PASSED${NC}"
    echo -e "${YELLOW}  ⚠️  Warnings: $AUDIT_WARNINGS${NC}"
    echo -e "${RED}  ❌ Failed: $AUDIT_FAILED${NC}"
    
    # Generate report
    generate_report
    
    # Exit code based on failures
    if [ $AUDIT_FAILED -gt 0 ]; then
        echo -e "\n${RED}❌ Security audit failed!${NC}"
        exit 1
    elif [ $AUDIT_WARNINGS -gt 0 ]; then
        echo -e "\n${YELLOW}⚠️  Security audit passed with warnings${NC}"
        exit 0
    else
        echo -e "\n${GREEN}✅ Security audit passed!${NC}"
        exit 0
    fi
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi