#!/bin/bash
# Deploy-time Verification and Kill-Switch
# Verifies integrity before deploy and provides emergency controls

set -euo pipefail

ACTION="${1:-verify}"
DOMAIN="${2:-secureblog.example.com}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kill-switch configuration
EMERGENCY_ASN="AS13335"  # Cloudflare ASN for emergency
EMERGENCY_COUNTRY="US"   # Allowed country in emergency
CLOUDFLARE_ZONE_ID="${CF_ZONE_ID}"
CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"

# Function: Pre-deploy verification
pre_deploy_verify() {
    echo -e "${BLUE}🔍 Pre-Deploy Verification${NC}"
    echo "=========================="
    
    # 1. Verify manifest integrity
    echo -n "Verifying manifest... "
    if [ ! -f "dist/manifest.sha256" ]; then
        echo -e "${RED}FAIL - No manifest${NC}"
        exit 1
    fi
    
    cd dist
    if sha256sum -c manifest.sha256 > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL - Integrity check failed${NC}"
        exit 1
    fi
    cd ..
    
    # 2. Verify no JavaScript
    echo -n "Verifying no JavaScript... "
    if find dist -name "*.js" -o -name "*.mjs" | grep -q .; then
        echo -e "${RED}FAIL - JS files found${NC}"
        exit 1
    fi
    
    if grep -r "<script\|javascript:\|on[a-z]*=" dist --include="*.html" > /dev/null 2>&1; then
        echo -e "${RED}FAIL - JS in HTML${NC}"
        exit 1
    fi
    echo -e "${GREEN}PASS${NC}"
    
    # 3. Verify content sanitization
    echo -n "Verifying content sanitization... "
    
    # Check for EXIF data in images
    for img in $(find dist -name "*.jpg" -o -name "*.jpeg" -o -name "*.png"); do
        if exiftool "$img" | grep -q "GPS\|Location\|Creator"; then
            echo -e "${RED}FAIL - EXIF data found in $img${NC}"
            exit 1
        fi
    done
    
    # Check SVGs for scripts
    for svg in $(find dist -name "*.svg"); do
        if grep -qi "script\|javascript:\|on[a-z]*=" "$svg"; then
            echo -e "${RED}FAIL - Scripts in SVG: $svg${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}PASS${NC}"
    
    # 4. Verify signature
    echo -n "Verifying manifest signature... "
    if [ -f "dist/manifest.sig" ] && [ -f "public.key" ]; then
        if openssl dgst -sha256 -verify public.key -signature dist/manifest.sig dist/manifest.sha256 > /dev/null 2>&1; then
            echo -e "${GREEN}PASS${NC}"
        else
            echo -e "${RED}FAIL - Invalid signature${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}SKIP - No signature${NC}"
    fi
    
    # 5. Check SBOM
    echo -n "Checking SBOM... "
    if [ -f "dist/sbom.spdx.json" ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${YELLOW}WARNING - No SBOM${NC}"
    fi
    
    echo -e "\n${GREEN}✅ Pre-deploy verification complete${NC}"
    return 0
}

# Function: Post-deploy verification
post_deploy_verify() {
    echo -e "${BLUE}🔍 Post-Deploy Verification${NC}"
    echo "============================"
    
    # Wait for deployment to propagate
    echo "Waiting for deployment to propagate..."
    sleep 10
    
    # 1. Verify headers
    echo -n "Verifying security headers... "
    HEADERS=$(curl -sI "https://$DOMAIN")
    
    REQUIRED_HEADERS=(
        "content-security-policy"
        "x-frame-options"
        "strict-transport-security"
        "x-content-type-options"
        "referrer-policy"
    )
    
    MISSING=0
    for header in "${REQUIRED_HEADERS[@]}"; do
        if ! echo "$HEADERS" | grep -qi "$header"; then
            echo -e "\n  ${RED}Missing: $header${NC}"
            MISSING=$((MISSING + 1))
        fi
    done
    
    if [ $MISSING -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL - Missing $MISSING headers${NC}"
    fi
    
    # 2. Verify methods blocked
    echo -n "Verifying method restrictions... "
    POST_CODE=$(curl -X POST "https://$DOMAIN" -o /dev/null -w "%{http_code}" -s)
    if [ "$POST_CODE" = "405" ] || [ "$POST_CODE" = "403" ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL - POST returned $POST_CODE${NC}"
    fi
    
    # 3. Verify no JavaScript
    echo -n "Verifying no JavaScript in response... "
    if curl -s "https://$DOMAIN" | grep -E '<script|javascript:|on[a-z]+=' > /dev/null; then
        echo -e "${RED}FAIL - JavaScript detected${NC}"
    else
        echo -e "${GREEN}PASS${NC}"
    fi
    
    # 4. Test specific paths
    echo -n "Testing security.txt... "
    SECURITY_CODE=$(curl -o /dev/null -w "%{http_code}" -s "https://$DOMAIN/.well-known/security.txt")
    if [ "$SECURITY_CODE" = "200" ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${YELLOW}WARNING - No security.txt${NC}"
    fi
    
    echo -e "\n${GREEN}✅ Post-deploy verification complete${NC}"
}

# Function: Emergency kill-switch
activate_kill_switch() {
    echo -e "${RED}🚨 ACTIVATING EMERGENCY KILL-SWITCH${NC}"
    echo "======================================"
    
    # Create firewall rule to block all except emergency ASN
    RULE_BODY='{
        "filter": {
            "expression": "(ip.geoip.asnum ne '$EMERGENCY_ASN')",
            "paused": false,
            "description": "EMERGENCY: Block all except emergency ASN"
        },
        "action": "block",
        "priority": 1,
        "paused": false,
        "description": "Emergency kill-switch activated"
    }'
    
    # Apply rule via Cloudflare API
    curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/firewall/rules" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$RULE_BODY"
    
    echo -e "${RED}✓ Site blocked except for ASN: $EMERGENCY_ASN${NC}"
    
    # Also set to "Under Attack" mode
    curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/settings/security_level" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"value":"under_attack"}'
    
    echo -e "${RED}✓ Under Attack mode activated${NC}"
    
    # Create incident record
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Kill switch activated" >> emergency.log
    
    echo -e "\n${RED}Kill-switch active. To deactivate, run: $0 deactivate${NC}"
}

# Function: Deactivate kill-switch
deactivate_kill_switch() {
    echo -e "${YELLOW}🔓 Deactivating Kill-Switch${NC}"
    echo "============================"
    
    # Get and delete emergency rules
    RULES=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/firewall/rules" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
        jq -r '.result[] | select(.description | contains("Emergency")) | .id')
    
    for rule_id in $RULES; do
        curl -X DELETE "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/firewall/rules/$rule_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
        echo "✓ Removed rule: $rule_id"
    done
    
    # Reset security level
    curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/settings/security_level" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"value":"high"}'
    
    echo -e "${GREEN}✓ Kill-switch deactivated${NC}"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Kill switch deactivated" >> emergency.log
}

# Function: Rollback to previous version
rollback() {
    echo -e "${YELLOW}⏪ Rolling Back Deployment${NC}"
    echo "=========================="
    
    # Get previous deployment ID from Cloudflare Pages
    PREV_DEPLOYMENT=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/pages/projects/secureblog/deployments" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
        jq -r '.result[1].id')
    
    if [ -n "$PREV_DEPLOYMENT" ]; then
        # Rollback to previous deployment
        curl -X POST \
            "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/pages/projects/secureblog/deployments/$PREV_DEPLOYMENT/rollback" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
        
        echo -e "${GREEN}✓ Rolled back to deployment: $PREV_DEPLOYMENT${NC}"
    else
        echo -e "${RED}No previous deployment found${NC}"
        exit 1
    fi
}

# Main execution
case "$ACTION" in
    verify)
        pre_deploy_verify
        ;;
    post-verify)
        post_deploy_verify
        ;;
    deploy)
        pre_deploy_verify
        echo -e "\n${BLUE}Deploying...${NC}"
        npx wrangler pages deploy dist --project-name=secureblog
        post_deploy_verify
        ;;
    kill-switch)
        activate_kill_switch
        ;;
    deactivate)
        deactivate_kill_switch
        ;;
    rollback)
        rollback
        ;;
    monitor)
        while true; do
            echo -e "${BLUE}Monitoring deployment...${NC}"
            post_deploy_verify
            sleep 300  # Check every 5 minutes
        done
        ;;
    *)
        echo "Usage: $0 {verify|post-verify|deploy|kill-switch|deactivate|rollback|monitor} [domain]"
        exit 1
        ;;
esac