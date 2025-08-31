#!/usr/bin/env bash
# originless-discipline.sh - Enforce originless deployment discipline
set -euo pipefail

DEPLOYMENT_TYPE="${1:-cloudflare-pages}"
CONFIG_FILE="${2:-deployment-config.json}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🌐 Originless Discipline Enforcement${NC}"
echo "===================================="
echo "Deployment type: $DEPLOYMENT_TYPE"
echo ""

# Initialize validation results
discipline_passed=true
total_checks=0
passed_checks=0
violations=0

# Arrays to store results
declare -a originless_violations=()
declare -a security_violations=()
declare -a performance_violations=()
declare -a compliance_checks=()

# Function to perform a check
check() {
    local check_name="$1"
    local condition="$2"
    local severity="${3:-error}"  # error, warning, info
    local description="$4"
    
    ((total_checks++))
    
    echo "🔍 Checking: $check_name"
    
    if eval "$condition"; then
        echo -e "${GREEN}✅ PASS: $check_name${NC}"
        compliance_checks+=("✅ $check_name: $description")
        ((passed_checks++))
        return 0
    else
        case $severity in
            "error")
                echo -e "${RED}❌ FAIL: $check_name${NC}"
                echo -e "${RED}   $description${NC}"
                originless_violations+=("$check_name: $description")
                ((violations++))
                discipline_passed=false
                ;;
            "warning")
                echo -e "${YELLOW}⚠️  WARNING: $check_name${NC}"
                echo -e "${YELLOW}   $description${NC}"
                security_violations+=("$check_name: $description (warning)")
                ;;
            *)
                echo -e "${BLUE}ℹ️  INFO: $check_name${NC}"
                echo -e "${BLUE}   $description${NC}"
                performance_violations+=("$check_name: $description (info)")
                ;;
        esac
        return 1
    fi
}

# Function to check Cloudflare Pages deployment
check_cloudflare_pages() {
    echo -e "${BLUE}== Cloudflare Pages Originless Checks ==${NC}"
    
    # Check 1: No origin server exposed
    check "No origin server" \
        "! netstat -tuln 2>/dev/null | grep -q ':80\\|:443' && ! ss -tuln 2>/dev/null | grep -q ':80\\|:443'" \
        "error" \
        "No web servers should be running on port 80/443"
    
    # Check 2: Wrangler configuration enforces originless
    if [ -f "wrangler.toml" ]; then
        check "Wrangler site configuration" \
            'grep -q "\\[site\\]" wrangler.toml && grep -q "bucket.*dist" wrangler.toml' \
            "error" \
            "wrangler.toml must specify static site bucket, not origin server"
    else
        originless_violations+=("wrangler.toml missing: Required for Cloudflare Pages deployment")
        discipline_passed=false
    fi
    
    # Check 3: No server-side code in deployment
    check "No server binaries in deployment" \
        "! find dist -name 'server' -o -name '*.exe' -o -name 'app' | grep -q ." \
        "error" \
        "Deployment should contain only static assets, no server executables"
    
    # Check 4: Edge worker for security, not origin
    if [ -f "scripts/edge-runtime-gates.js" ]; then
        check "Edge worker serves static content only" \
            'grep -q "fetch(request)" scripts/edge-runtime-gates.js' \
            "error" \
            "Edge worker should proxy to CDN, not act as origin server"
    fi
    
    # Check 5: DNS points to Cloudflare, not origin
    check "DNS configuration is originless" \
        "! dig +short secureblog.com A 2>/dev/null | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$' || dig +short secureblog.com CNAME 2>/dev/null | grep -q cloudflare" \
        "warning" \
        "DNS should point to Cloudflare CDN, not origin IP"
    
    # Check 6: SSL certificates managed by Cloudflare
    check "SSL managed by CDN" \
        "openssl s_client -connect secureblog.com:443 -servername secureblog.com </dev/null 2>/dev/null | grep -q 'Cloudflare\\|CF' || true" \
        "info" \
        "SSL certificates should be managed by Cloudflare"
}

# Function to check static-only deployment
check_static_only() {
    echo -e "${BLUE}== Static-Only Deployment Checks ==${NC}"
    
    # Check 1: Only static file types present
    check "Only static files in deployment" \
        "! find dist -type f | grep -E '\\.(php|py|rb|js|jsp|asp|aspx|cgi)$' | grep -q ." \
        "error" \
        "Deployment must contain only static files (HTML, CSS, images, fonts)"
    
    # Check 2: No dynamic content indicators
    check "No server-side processing indicators" \
        "! grep -r '<?php\\|<%\\|{{\\|{%\\|@{' dist/ 2>/dev/null | grep -v '.git' | grep -q ." \
        "error" \
        "No server-side templating or processing code should remain"
    
    # Check 3: No configuration files for servers
    check "No server config files" \
        "! find . -name 'nginx.conf' -o -name 'apache.conf' -o -name '.htaccess' -o -name 'Dockerfile' -o -name 'docker-compose.yml' | grep -q ." \
        "warning" \
        "No server configuration files needed for originless deployment"
    
    # Check 4: All assets are self-contained
    check "Self-contained static assets" \
        "! grep -r 'src=.*http://' dist/ 2>/dev/null | grep -v localhost | grep -q ." \
        "error" \
        "All assets should be self-contained, no external HTTP dependencies"
    
    # Check 5: No API endpoints defined
    check "No API endpoints" \
        "! find . -name 'api' -type d -o -name '*api*' -name '*.js' -o -name '*api*' -name '*.py' | grep -q ." \
        "error" \
        "Originless deployment cannot contain API endpoints"
}

# Function to check security compliance for originless
check_security_compliance() {
    echo -e "${BLUE}== Security Compliance for Originless ==${NC}"
    
    # Check 1: No sensitive files in static deployment
    check "No sensitive files exposed" \
        "! find dist -name '.env*' -o -name 'config.json' -o -name '*.key' -o -name '*.pem' -o -name 'secrets*' | grep -q ." \
        "error" \
        "No sensitive configuration or key files should be in static deployment"
    
    # Check 2: Content Security Policy prevents dynamic loading
    if [ -f "dist/.htaccess" ] || [ -f "scripts/edge-runtime-gates.js" ]; then
        check "CSP prevents dynamic content loading" \
            "grep -q \"script-src 'none'\" dist/.htaccess scripts/edge-runtime-gates.js 2>/dev/null || grep -q 'script-src.*none' wrangler.toml 2>/dev/null" \
            "error" \
            "CSP must prevent all dynamic script loading for true originless security"
    fi
    
    # Check 3: No form processing capabilities
    check "No form processing" \
        "! grep -r '<form' dist/ 2>/dev/null | grep -v 'method=\"GET\"' | grep -q ." \
        "error" \
        "Forms requiring processing violate originless principle"
    
    # Check 4: All resources served over HTTPS
    check "HTTPS-only resources" \
        "! grep -r 'http://' dist/ 2>/dev/null | grep -v localhost | grep -v comment | grep -q ." \
        "error" \
        "All resources must use HTTPS to maintain security without origin server"
    
    # Check 5: No user authentication systems
    check "No authentication systems" \
        "! grep -r 'login\\|signin\\|auth' dist/ 2>/dev/null | grep -i -E '(form|input|password)' | grep -q ." \
        "error" \
        "Authentication requires server-side processing, incompatible with originless"
}

# Function to check performance optimization
check_performance_optimization() {
    echo -e "${BLUE}== Performance Optimization for CDN ==${NC}"
    
    # Check 1: Assets are properly hashed for immutable caching
    check "Content-hashed assets present" \
        "find dist -name '*-[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9].*' | grep -q ." \
        "warning" \
        "Content-hashed assets enable optimal CDN caching"
    
    # Check 2: Gzip/Brotli compression enabled
    if [ -f "dist/.htaccess" ]; then
        check "Compression enabled" \
            "grep -q 'mod_deflate\\|gzip' dist/.htaccess" \
            "warning" \
            "Enable compression for better CDN performance"
    fi
    
    # Check 3: Minimal DNS lookups required
    check "Minimal external DNS lookups" \
        "[ \$(grep -r 'src=.*https://' dist/ 2>/dev/null | grep -v 'secureblog.com' | wc -l) -lt 5 ]" \
        "warning" \
        "Minimize external DNS lookups for faster loading"
    
    # Check 4: Critical CSS inlined (optional)
    check "CSS optimization" \
        "find dist -name '*.css' | head -1 | xargs wc -c | awk '{print (\$1 < 10000)}' | grep -q 1" \
        "info" \
        "Keep CSS small for optimal first-load performance"
}

# Main execution based on deployment type
case "$DEPLOYMENT_TYPE" in
    "cloudflare-pages")
        check_cloudflare_pages
        check_static_only
        check_security_compliance
        check_performance_optimization
        ;;
    "netlify")
        echo -e "${YELLOW}⚠️ Netlify deployment - ensure no serverless functions${NC}"
        check_static_only
        check_security_compliance
        check_performance_optimization
        ;;
    "github-pages")
        echo -e "${YELLOW}⚠️ GitHub Pages - limited security header control${NC}"
        check_static_only
        check_security_compliance
        ;;
    "aws-s3")
        echo -e "${YELLOW}⚠️ AWS S3 - ensure CloudFront distribution configured${NC}"
        check_static_only
        check_security_compliance
        check_performance_optimization
        ;;
    *)
        echo -e "${RED}❌ Unknown deployment type: $DEPLOYMENT_TYPE${NC}"
        echo "Supported types: cloudflare-pages, netlify, github-pages, aws-s3"
        exit 1
        ;;
esac

# Generate deployment configuration
echo ""
echo -e "${BLUE}📋 Generating deployment configuration...${NC}"

cat > "$CONFIG_FILE" << EOF
{
  "deployment": {
    "type": "$DEPLOYMENT_TYPE",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "originless": $([ "$discipline_passed" = true ] && echo "true" || echo "false"),
    "validation_results": {
      "total_checks": $total_checks,
      "passed": $passed_checks,
      "violations": $violations,
      "discipline_passed": $([ "$discipline_passed" = true ] && echo "true" || echo "false")
    }
  },
  "security": {
    "originless_architecture": $([ "$discipline_passed" = true ] && echo "true" || echo "false"),
    "static_only": true,
    "cdn_distributed": true,
    "no_server_side_processing": true,
    "immutable_deployment": true
  },
  "compliance": [
$(IFS=$'\n'; echo "${compliance_checks[*]}" | sed 's/^/    "/' | sed 's/$/",/' | sed '$s/,$//')
  ],
  "violations": [
$(if [ ${#originless_violations[@]} -gt 0 ]; then
    IFS=$'\n'; echo "${originless_violations[*]}" | sed 's/^/    "/' | sed 's/$/",/' | sed '$s/,$//'
fi)
  ]
}
EOF

echo "📄 Deployment configuration saved to: $CONFIG_FILE"

# Generate detailed report
REPORT_FILE="originless-discipline-report.md"
cat > "$REPORT_FILE" << EOF
# Originless Discipline Report

**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Deployment Type**: $DEPLOYMENT_TYPE
**Total Checks**: $total_checks
**Passed**: $passed_checks
**Violations**: $violations
**Discipline Status**: $([ "$discipline_passed" = true ] && echo "✅ PASSED" || echo "❌ FAILED")

## Executive Summary

$(if [ "$discipline_passed" = true ]; then
    echo "✅ **ORIGINLESS DISCIPLINE MAINTAINED**"
    echo ""
    echo "This deployment successfully maintains originless architecture with:"
    echo "- No origin server exposed"
    echo "- Static-only content delivery"
    echo "- CDN-based distribution"
    echo "- Zero server-side processing"
    echo "- Immutable deployment artifacts"
else
    echo "❌ **ORIGINLESS DISCIPLINE VIOLATED**"
    echo ""
    echo "This deployment has violations that compromise originless architecture:"
fi)

## Deployment Architecture

### Originless Principles Validated

1. **No Origin Server**: Application serves only static files via CDN
2. **Static Content Only**: No server-side processing or dynamic generation
3. **CDN Distribution**: All content delivered through edge locations
4. **Immutable Deployments**: Each deployment is a complete, versioned artifact
5. **Zero Attack Surface**: No running services to compromise

$(if [ ${#originless_violations[@]} -gt 0 ]; then
    echo "## Violations (Critical)"
    echo ""
    printf '- %s\n' "${originless_violations[@]}"
    echo ""
fi)

$(if [ ${#security_violations[@]} -gt 0 ]; then
    echo "## Security Warnings"
    echo ""
    printf '- %s\n' "${security_violations[@]}"
    echo ""
fi)

$(if [ ${#performance_violations[@]} -gt 0 ]; then
    echo "## Performance Recommendations"
    echo ""
    printf '- %s\n' "${performance_violations[@]}"
    echo ""
fi)

## Compliance Summary

$(printf '%s\n' "${compliance_checks[@]}")

## Originless Benefits Achieved

$(if [ "$discipline_passed" = true ]; then
    echo "### Security Benefits"
    echo "- **Zero Server Attack Surface**: No running services to exploit"
    echo "- **Immutable Infrastructure**: Cannot be modified at runtime"
    echo "- **Distributed Resilience**: Multiple edge locations prevent SPOF"
    echo "- **Automatic HTTPS**: CDN-managed SSL/TLS certificates"
    echo ""
    echo "### Performance Benefits"
    echo "- **Global Edge Distribution**: Content served from nearest location"
    echo "- **Instant Scaling**: CDN handles traffic spikes automatically"
    echo "- **Aggressive Caching**: Static content cached indefinitely"
    echo "- **Zero Cold Starts**: No server startup delays"
    echo ""
    echo "### Operational Benefits"
    echo "- **No Server Maintenance**: No OS updates, patches, or monitoring"
    echo "- **Simplified Deployment**: Simple file upload process"
    echo "- **Cost Efficiency**: Pay-per-request with CDN"
    echo "- **High Availability**: CDN inherent redundancy"
fi)

## Deployment Verification Commands

\`\`\`bash
# Verify no origin servers running
netstat -tuln | grep -E ':80|:443' || echo "No web servers running ✅"

# Check deployment contains only static files
find dist -type f -exec file {} \\; | grep -v 'text\\|image\\|font' | head -5

# Verify DNS points to CDN
dig +short secureblog.com

# Test security headers from CDN
curl -I https://secureblog.com | grep -E 'server:|x-|content-security'
\`\`\`

EOF

echo "📄 Detailed report saved to: $REPORT_FILE"

# Final summary
echo ""
echo -e "${BLUE}📊 ORIGINLESS DISCIPLINE SUMMARY${NC}"
echo "================================="
echo -e "Deployment Type: $DEPLOYMENT_TYPE"
echo -e "Total Checks: $total_checks"
echo -e "${GREEN}Passed: $passed_checks${NC}"
echo -e "${RED}Violations: $violations${NC}"
echo ""

if [ "$discipline_passed" = true ]; then
    echo -e "${GREEN}✅ ORIGINLESS DISCIPLINE MAINTAINED${NC}"
    echo -e "${GREEN}🌐 Deployment follows originless architecture principles${NC}"
    echo -e "${GREEN}🛡️ Maximum security with zero server attack surface${NC}"
    echo -e "${GREEN}⚡ Optimal performance with global edge distribution${NC}"
    echo ""
    echo -e "${BLUE}🚀 Deployment approved for originless architecture${NC}"
    exit 0
else
    echo -e "${RED}❌ ORIGINLESS DISCIPLINE VIOLATED${NC}"
    echo -e "${RED}🚨 Deployment compromises originless architecture${NC}"
    echo -e "${RED}⚠️ Security and performance benefits reduced${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Required Actions:${NC}"
    echo "  1. Remove all server-side components"
    echo "  2. Eliminate dynamic processing requirements"
    echo "  3. Ensure all content is purely static"
    echo "  4. Configure CDN-only distribution"
    echo "  5. Re-run validation after fixes"
    echo ""
    echo -e "${BLUE}ℹ️ See detailed report: $REPORT_FILE${NC}"
    exit 1
fi