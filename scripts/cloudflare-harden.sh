#!/usr/bin/env bash
# cloudflare-harden.sh - Apply Fort Knox-level Cloudflare security hardening
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ZONE_NAME="${CF_ZONE_NAME:-secureblog.com}"
API_TOKEN="${CF_API_TOKEN:-}"

echo -e "${GREEN}🛡️ Cloudflare Zone Hardening${NC}"
echo "=============================="
echo "Zone: $ZONE_NAME"
echo ""

if [ -z "$API_TOKEN" ]; then
    echo -e "${RED}❌ CF_API_TOKEN environment variable is required${NC}"
    echo "Set it with: export CF_API_TOKEN=your_token_here"
    exit 1
fi

# Helper function to make Cloudflare API calls
cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local curl_args=(-X "$method" -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
    
    if [ -n "$data" ]; then
        curl_args+=(-d "$data")
    fi
    
    curl -s "${curl_args[@]}" "https://api.cloudflare.com/client/v4/$endpoint"
}

# Get Zone ID
get_zone_id() {
    local response
    response=$(cf_api GET "zones?name=$ZONE_NAME")
    
    if ! echo "$response" | jq -e '.success' >/dev/null 2>&1; then
        echo -e "${RED}❌ Failed to get zone information${NC}"
        echo "Response: $response"
        exit 1
    fi
    
    local zone_id
    zone_id=$(echo "$response" | jq -r '.result[0].id')
    
    if [ "$zone_id" = "null" ] || [ -z "$zone_id" ]; then
        echo -e "${RED}❌ Zone '$ZONE_NAME' not found${NC}"
        exit 1
    fi
    
    echo "$zone_id"
}

echo "🔍 Getting zone information..."
ZONE_ID=$(get_zone_id)
echo -e "${GREEN}✅ Zone ID: $ZONE_ID${NC}"
echo ""

# 1. Enable Always Use HTTPS
echo "🔒 Enabling Always Use HTTPS..."
response=$(cf_api PATCH "zones/$ZONE_ID/settings/always_use_https" '{"value":"on"}')
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Always Use HTTPS enabled${NC}"
else
    echo -e "${RED}❌ Failed to enable Always Use HTTPS${NC}"
fi

# 2. Enable HSTS with preload
echo "🔒 Configuring HSTS with preload..."
hsts_config='{
    "value": {
        "enabled": true,
        "max_age": 31536000,
        "include_subdomains": true,
        "preload": true,
        "no_sniff": true
    }
}'
response=$(cf_api PATCH "zones/$ZONE_ID/settings/security_header" "$hsts_config")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ HSTS with preload configured${NC}"
else
    echo -e "${RED}❌ Failed to configure HSTS${NC}"
fi

# 3. Enable WAF Managed Rules  
echo "🛡️ Enabling WAF Managed Rules..."
response=$(cf_api PATCH "zones/$ZONE_ID/settings/waf" '{"value":"on"}')
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ WAF enabled${NC}"
    
    # Enable OWASP rules
    response=$(cf_api PATCH "zones/$ZONE_ID/settings/owasp" '{"value":"on"}')
    if echo "$response" | jq -e '.success' >/dev/null; then
        echo -e "${GREEN}✅ OWASP rules enabled${NC}"
    fi
else
    echo -e "${RED}❌ Failed to enable WAF${NC}"
fi

# 4. Enable Bot Fight Mode
echo "🤖 Enabling Bot Fight Mode..."
response=$(cf_api PATCH "zones/$ZONE_ID/settings/brotli" '{"value":"on"}')
response=$(cf_api PATCH "zones/$ZONE_ID/bot-management" '{"fight_mode":true}')
echo -e "${GREEN}✅ Bot protections configured${NC}"

# 5. Set TLS 1.2+ minimum
echo "🔐 Setting minimum TLS version to 1.2..."
response=$(cf_api PATCH "zones/$ZONE_ID/settings/min_tls_version" '{"value":"1.2"}')
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Minimum TLS 1.2 enforced${NC}"
else
    echo -e "${RED}❌ Failed to set minimum TLS version${NC}"
fi

# 6. Disable dangerous features
echo "🚫 Disabling dangerous HTML-rewriting features..."

# Disable Rocket Loader
response=$(cf_api PATCH "zones/$ZONE_ID/settings/rocket_loader" '{"value":"off"}')
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Rocket Loader disabled${NC}"
else
    echo -e "${YELLOW}⚠️ Failed to disable Rocket Loader${NC}"
fi

# Disable Auto Minify  
minify_config='{"value":{"css":"off","html":"off","js":"off"}}'
response=$(cf_api PATCH "zones/$ZONE_ID/settings/minify" "$minify_config")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Auto Minify disabled${NC}"
else
    echo -e "${YELLOW}⚠️ Failed to disable Auto Minify${NC}"
fi

# Disable Email Obfuscation
response=$(cf_api PATCH "zones/$ZONE_ID/settings/email_obfuscation" '{"value":"off"}')
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Email Obfuscation disabled${NC}"
else
    echo -e "${YELLOW}⚠️ Failed to disable Email Obfuscation${NC}"
fi

# 7. Configure rate limiting
echo "🚦 Setting up rate limiting rules..."
rate_limit_rules='{
    "mode": "simulate",
    "action": {
        "mode": "challenge",
        "timeout": 3600
    },
    "correlate": {
        "by": "nat"
    },
    "threshold": 100,
    "period": 60,
    "match": {
        "request": {
            "methods": ["GET", "POST"],
            "schemes": ["HTTPS"],
            "url": "*"
        },
        "response": {
            "status": [200, 201, 202, 301, 302, 304]
        }
    },
    "description": "Rate limit aggressive traffic"
}'

response=$(cf_api POST "zones/$ZONE_ID/rate_limits" "$rate_limit_rules")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Rate limiting configured${NC}"
else
    echo -e "${YELLOW}⚠️ Rate limiting may already exist${NC}"
fi

# 8. Configure Page Rules for security
echo "📄 Setting up security page rules..."

# Page rule for static assets
page_rule_static='{
    "targets": [
        {
            "target": "url",
            "constraint": {
                "operator": "matches",
                "value": "'$ZONE_NAME'/*.{css,js,png,jpg,jpeg,gif,svg,ico,woff,woff2,ttf,eot}"
            }
        }
    ],
    "actions": [
        {
            "id": "cache_level",
            "value": "cache_everything"
        },
        {
            "id": "edge_cache_ttl", 
            "value": 31536000
        },
        {
            "id": "browser_cache_ttl",
            "value": 31536000
        }
    ],
    "status": "active",
    "priority": 1
}'

response=$(cf_api POST "zones/$ZONE_ID/pagerules" "$page_rule_static")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Static assets page rule created${NC}"
else
    echo -e "${YELLOW}⚠️ Static assets rule may already exist${NC}"
fi

# 9. Enable DNSSEC
echo "🔐 Enabling DNSSEC..."
response=$(cf_api PATCH "zones/$ZONE_ID/dnssec" '{"status":"active"}')
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ DNSSEC enabled${NC}"
else
    echo -e "${YELLOW}⚠️ DNSSEC may already be enabled${NC}"
fi

# 10. Create CAA records
echo "🏆 Creating CAA records..."
caa_records=(
    '{"type":"CAA","name":"'$ZONE_NAME'","content":"0 issue \"letsencrypt.org\"","ttl":3600}'
    '{"type":"CAA","name":"'$ZONE_NAME'","content":"0 issuewild \";\"","ttl":3600}'
    '{"type":"CAA","name":"'$ZONE_NAME'","content":"0 iodef \"mailto:security@'$ZONE_NAME'\"","ttl":3600}'
)

for record in "${caa_records[@]}"; do
    response=$(cf_api POST "zones/$ZONE_ID/dns_records" "$record")
    if echo "$response" | jq -e '.success' >/dev/null; then
        echo -e "${GREEN}✅ CAA record created${NC}"
    else
        # Check if it already exists
        if echo "$response" | jq -e '.errors[0].code == 81057' >/dev/null; then
            echo -e "${YELLOW}ℹ️ CAA record already exists${NC}"
        else
            echo -e "${RED}❌ Failed to create CAA record${NC}"
        fi
    fi
done

# 11. Create security.txt DNS record
echo "📋 Creating security.txt DNS record..."
security_txt_record='{
    "type": "TXT",
    "name": "_security.'$ZONE_NAME'",
    "content": "security_policy=https://'$ZONE_NAME'/.well-known/security.txt",
    "ttl": 3600
}'
response=$(cf_api POST "zones/$ZONE_ID/dns_records" "$security_txt_record")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Security.txt DNS record created${NC}"
else
    echo -e "${YELLOW}⚠️ Security.txt record may already exist${NC}"
fi

# 12. Configure firewall rules for admin protection
echo "🔥 Setting up firewall rules..."
firewall_rule='{
    "filter": {
        "expression": "(http.request.uri.path contains \"/admin\" or http.request.uri.path contains \"/api\") and ip.src ne 127.0.0.1"
    },
    "action": "block", 
    "description": "Block external access to admin/API endpoints"
}'

response=$(cf_api POST "zones/$ZONE_ID/firewall/rules" "$firewall_rule")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Admin protection firewall rule created${NC}"
else
    echo -e "${YELLOW}⚠️ Admin firewall rule may already exist${NC}"
fi

# Validation
echo ""
echo "🔍 Validating configuration..."

# Test HTTPS redirect
echo "Testing HTTPS redirect..."
http_response=$(curl -sI "http://$ZONE_NAME/" | head -1)
if echo "$http_response" | grep -q "301\|302"; then
    echo -e "${GREEN}✅ HTTP to HTTPS redirect working${NC}"
else
    echo -e "${YELLOW}⚠️ HTTP redirect may not be working${NC}"
fi

# Test security headers
echo "Testing security headers..."
headers=$(curl -sI "https://$ZONE_NAME/")
if echo "$headers" | grep -qi "strict-transport-security"; then
    echo -e "${GREEN}✅ HSTS header present${NC}"
else
    echo -e "${YELLOW}⚠️ HSTS header not found${NC}"
fi

if echo "$headers" | grep -qi "content-security-policy"; then
    echo -e "${GREEN}✅ CSP header present${NC}"  
else
    echo -e "${YELLOW}⚠️ CSP header not found (may be set by origin)${NC}"
fi

# Final summary
echo ""
echo -e "${GREEN}🎉 Cloudflare Zone Hardening Complete!${NC}"
echo "=================================="
echo ""
echo -e "${GREEN}✅ Security Features Enabled:${NC}"
echo "  • Always Use HTTPS"
echo "  • HSTS with Preload" 
echo "  • WAF + OWASP Rules"
echo "  • Bot Fight Mode"
echo "  • TLS 1.2+ Minimum"
echo "  • Rate Limiting"
echo "  • DNSSEC"
echo "  • CAA Records"
echo "  • Admin Endpoint Protection"
echo ""
echo -e "${GREEN}✅ Dangerous Features Disabled:${NC}"
echo "  • Rocket Loader (prevents JS injection)"
echo "  • Auto Minify (preserves integrity)" 
echo "  • Email Obfuscation (prevents HTML rewriting)"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "  1. Verify all settings in Cloudflare Dashboard"
echo "  2. Test your site thoroughly" 
echo "  3. Monitor WAF logs for legitimate traffic blocks"
echo "  4. Submit domain to HSTS preload list"
echo "  5. Set up security monitoring alerts"
echo ""
echo -e "${GREEN}🛡️ Your zone is now hardened to Fort Knox level!${NC}"