#!/usr/bin/env bash
# operational-guardrails.sh - Fort Knox operational security checks
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FAILED_CHECKS=0
TOTAL_CHECKS=0

echo -e "${GREEN}🏛️ SecureBlog Operational Security Guardrails${NC}"
echo "=============================================="
echo ""

log_check() {
    local status="$1"
    local message="$2"
    ((TOTAL_CHECKS++))
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS:${NC} $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}❌ FAIL:${NC} $message"
        ((FAILED_CHECKS++))
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠️  WARN:${NC} $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${BLUE}ℹ️  INFO:${NC} $message"
    fi
}

# GitHub Security Settings
check_github_security() {
    echo -e "${BLUE}🔍 Checking GitHub Security Settings...${NC}"
    
    # Check if we can access GitHub API
    if command -v gh >/dev/null 2>&1; then
        # Check branch protection
        if gh api "repos/:owner/:repo/branches/main/protection" >/dev/null 2>&1; then
            log_check "PASS" "Branch protection rules are configured"
        else
            log_check "FAIL" "Branch protection rules not found - run: gh api repos/:owner/:repo/branches/main/protection --method PUT --input .github/branch-protection.json"
        fi
        
        # Check if secret scanning is enabled
        if gh api "repos/:owner/:repo" --jq '.security_and_analysis.secret_scanning.status' 2>/dev/null | grep -q "enabled"; then
            log_check "PASS" "Secret scanning is enabled"
        else
            log_check "FAIL" "Secret scanning is not enabled"
        fi
        
        # Check if dependency alerts are enabled
        if gh api "repos/:owner/:repo/vulnerability-alerts" >/dev/null 2>&1; then
            log_check "PASS" "Dependency vulnerability alerts are enabled"
        else
            log_check "FAIL" "Dependency vulnerability alerts are not enabled"
        fi
        
        # Check if code scanning is configured
        if gh api "repos/:owner/:repo/code-scanning/alerts" >/dev/null 2>&1; then
            log_check "PASS" "Code scanning (CodeQL) is configured"
        else
            log_check "WARN" "Code scanning alerts endpoint not accessible"
        fi
    else
        log_check "WARN" "GitHub CLI not installed - cannot check GitHub security settings"
    fi
}

# File Permissions Check
check_file_permissions() {
    echo -e "${BLUE}🔍 Checking Critical File Permissions...${NC}"
    
    # Check script permissions
    local critical_scripts=(
        "scripts/build-deterministic.sh"
        "scripts/security-regression-guard.sh"
        "scripts/deploy-secure.sh"
        "start-admin.sh"
    )
    
    for script in "${critical_scripts[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                log_check "PASS" "$script is executable"
            else
                log_check "FAIL" "$script is not executable - run: chmod +x $script"
            fi
            
            # Check for world-writable
            if [ ! -w "$script" ] || [ "$(stat -f %A "$script" 2>/dev/null || stat -c %a "$script" 2>/dev/null)" -lt 700 ]; then
                log_check "PASS" "$script has secure permissions"
            else
                log_check "WARN" "$script may have overly permissive permissions"
            fi
        else
            log_check "WARN" "$script not found"
        fi
    done
    
    # Check sensitive config files
    local sensitive_files=(
        ".env"
        ".env.local"
        "config/secrets.json"
    )
    
    for file in "${sensitive_files[@]}"; do
        if [ -f "$file" ]; then
            if [ "$(stat -f %A "$file" 2>/dev/null || stat -c %a "$file" 2>/dev/null)" -le 600 ]; then
                log_check "PASS" "$file has restrictive permissions (600)"
            else
                log_check "FAIL" "$file has overly permissive permissions - run: chmod 600 $file"
            fi
        fi
    done
}

# Environment Security Check
check_environment() {
    echo -e "${BLUE}🔍 Checking Environment Security...${NC}"
    
    # Check for development vs production indicators
    if [ "${NODE_ENV:-}" = "production" ] || [ "${GO_ENV:-}" = "production" ]; then
        log_check "PASS" "Environment set to production"
    else
        log_check "WARN" "Environment not set to production (NODE_ENV/GO_ENV)"
    fi
    
    # Check for debug modes
    if [ "${DEBUG:-}" = "true" ] || [ "${DEBUG_MODE:-}" = "true" ]; then
        log_check "FAIL" "Debug mode is enabled in environment"
    else
        log_check "PASS" "Debug mode is disabled"
    fi
    
    # Check admin password strength
    if [ -n "${ADMIN_PASSWORD:-}" ]; then
        if [ "${#ADMIN_PASSWORD}" -ge 20 ]; then
            log_check "PASS" "ADMIN_PASSWORD meets minimum length requirement"
        else
            log_check "FAIL" "ADMIN_PASSWORD is too short (minimum 20 characters)"
        fi
    else
        log_check "WARN" "ADMIN_PASSWORD not set (will use default)"
    fi
    
    # Check for required environment variables
    local required_vars=(
        "CF_API_TOKEN"
        "CF_ACCOUNT_ID"
        "CF_PAGES_PROJECT"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -n "${!var:-}" ]; then
            log_check "PASS" "$var is set"
        else
            log_check "WARN" "$var is not set (required for deployment)"
        fi
    done
}

# Dependency Security Check
check_dependencies() {
    echo -e "${BLUE}🔍 Checking Dependency Security...${NC}"
    
    # Check Go module verification
    if command -v go >/dev/null 2>&1; then
        if go mod verify >/dev/null 2>&1; then
            log_check "PASS" "Go modules verified successfully"
        else
            log_check "FAIL" "Go module verification failed"
        fi
        
        # Check for vulnerabilities
        if command -v govulncheck >/dev/null 2>&1; then
            if govulncheck ./... >/dev/null 2>&1; then
                log_check "PASS" "No known vulnerabilities in Go dependencies"
            else
                log_check "FAIL" "Vulnerabilities found in Go dependencies"
            fi
        else
            log_check "WARN" "govulncheck not installed - run: go install golang.org/x/vuln/cmd/govulncheck@latest"
        fi
    else
        log_check "WARN" "Go not installed - cannot check dependencies"
    fi
    
    # Check for package-lock.json or yarn.lock
    if [ -f "package-lock.json" ]; then
        log_check "PASS" "NPM dependencies are locked"
    elif [ -f "yarn.lock" ]; then
        log_check "PASS" "Yarn dependencies are locked"
    else
        log_check "INFO" "No JavaScript dependencies found"
    fi
}

# Build Security Check
check_build_security() {
    echo -e "${BLUE}🔍 Checking Build Security...${NC}"
    
    # Check for deterministic build script
    if [ -x "scripts/build-deterministic.sh" ]; then
        log_check "PASS" "Deterministic build script is executable"
    else
        log_check "FAIL" "Deterministic build script missing or not executable"
    fi
    
    # Check for security regression guard
    if [ -x "scripts/security-regression-guard.sh" ]; then
        log_check "PASS" "Security regression guard is executable"
    else
        log_check "FAIL" "Security regression guard missing or not executable"
    fi
    
    # Check SOURCE_DATE_EPOCH for reproducible builds
    if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        log_check "PASS" "SOURCE_DATE_EPOCH is set for reproducible builds"
    else
        log_check "WARN" "SOURCE_DATE_EPOCH not set - builds may not be reproducible"
    fi
    
    # Check for cosign availability
    if command -v cosign >/dev/null 2>&1; then
        log_check "PASS" "Cosign is available for signing"
    else
        log_check "WARN" "Cosign not installed - artifacts will not be signed"
    fi
}

# Network Security Check
check_network_security() {
    echo -e "${BLUE}🔍 Checking Network Security...${NC}"
    
    # Check if admin server is binding to localhost only
    if grep -q "127.0.0.1" cmd/admin-server/main.go; then
        log_check "PASS" "Admin server configured for localhost-only binding"
    else
        log_check "FAIL" "Admin server not configured for localhost-only binding"
    fi
    
    # Check for HTTPS enforcement
    if grep -q "HTTPS" nginx/security-headers.conf 2>/dev/null; then
        log_check "PASS" "HTTPS enforcement configured"
    else
        log_check "WARN" "HTTPS enforcement not found in nginx config"
    fi
    
    # Check for security headers
    if [ -f "nginx/security-headers.conf" ]; then
        if grep -q "Content-Security-Policy" nginx/security-headers.conf; then
            log_check "PASS" "Security headers configured"
        else
            log_check "FAIL" "Security headers incomplete"
        fi
    else
        log_check "WARN" "Security headers configuration not found"
    fi
}

# Operational Monitoring Check
check_monitoring() {
    echo -e "${BLUE}🔍 Checking Operational Monitoring...${NC}"
    
    # Check for security.txt
    if [ -f ".well-known/security.txt" ]; then
        log_check "PASS" "security.txt file exists"
    else
        log_check "FAIL" "security.txt file missing"
    fi
    
    # Check for CODEOWNERS
    if [ -f ".github/CODEOWNERS" ]; then
        log_check "PASS" "CODEOWNERS file exists for required approvals"
    else
        log_check "FAIL" "CODEOWNERS file missing"
    fi
    
    # Check for workflow files
    local required_workflows=(
        ".github/workflows/ci.yml"
        ".github/workflows/advanced-security.yml" 
        ".github/workflows/slsa-provenance.yml"
    )
    
    for workflow in "${required_workflows[@]}"; do
        if [ -f "$workflow" ]; then
            log_check "PASS" "$workflow exists"
        else
            log_check "FAIL" "$workflow missing"
        fi
    done
}

# Cloudflare Security Check
check_cloudflare_security() {
    echo -e "${BLUE}🔍 Checking Cloudflare Security (if deployed)...${NC}"
    
    if [ -f "cloudflare-config.json" ]; then
        log_check "PASS" "Cloudflare security configuration exists"
        
        # Check configuration for dangerous settings
        if grep -q '"rocket_loader.*false' cloudflare-config.json; then
            log_check "PASS" "Rocket Loader is disabled"
        else
            log_check "WARN" "Rocket Loader setting not found or not disabled"
        fi
        
        if grep -q '"auto_minify.*false' cloudflare-config.json; then
            log_check "PASS" "Auto minify is disabled" 
        else
            log_check "WARN" "Auto minify setting not found or not disabled"
        fi
    else
        log_check "WARN" "Cloudflare security configuration not found"
    fi
    
    # Check if site is live and secure
    if command -v curl >/dev/null 2>&1; then
        local site_url="https://secureblog.com"
        if curl -s -I "$site_url" >/dev/null 2>&1; then
            log_check "PASS" "Site is accessible via HTTPS"
            
            # Check security headers on live site
            local headers=$(curl -s -I "$site_url" 2>/dev/null)
            if echo "$headers" | grep -q "Content-Security-Policy"; then
                log_check "PASS" "Live site has CSP header"
            else
                log_check "FAIL" "Live site missing CSP header"
            fi
            
            if echo "$headers" | grep -q "Strict-Transport-Security"; then
                log_check "PASS" "Live site has HSTS header"
            else
                log_check "FAIL" "Live site missing HSTS header"
            fi
        else
            log_check "INFO" "Site not accessible (may not be deployed)"
        fi
    fi
}

# Generate Security Report
generate_report() {
    echo ""
    echo -e "${BLUE}📊 Security Guardrails Summary${NC}"
    echo "================================"
    echo ""
    
    local pass_rate=$(( (TOTAL_CHECKS - FAILED_CHECKS) * 100 / TOTAL_CHECKS ))
    
    echo "Total Checks: $TOTAL_CHECKS"
    echo "Failed Checks: $FAILED_CHECKS"
    echo "Pass Rate: ${pass_rate}%"
    echo ""
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "${GREEN}🎉 All critical security guardrails are in place!${NC}"
        echo -e "${GREEN}🛡️ SecureBlog is operating at Fort Knox security level${NC}"
        exit 0
    else
        echo -e "${RED}⚠️ $FAILED_CHECKS security issue(s) need attention${NC}"
        echo -e "${RED}🚨 Address failed checks before production deployment${NC}"
        exit 1
    fi
}

# Main execution
main() {
    check_github_security
    echo ""
    check_file_permissions  
    echo ""
    check_environment
    echo ""
    check_dependencies
    echo ""
    check_build_security
    echo ""
    check_network_security
    echo ""
    check_monitoring
    echo ""
    check_cloudflare_security
    echo ""
    generate_report
}

main "$@"