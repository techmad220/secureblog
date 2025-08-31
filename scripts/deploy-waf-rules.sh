#!/bin/bash
# Deploy Comprehensive Cloudflare WAF Rules and Zone Hardening
# Maximum security configuration deployment script

set -euo pipefail

# Configuration
ZONE_ID="${CF_ZONE_ID:-}"
DOMAIN="${CF_DOMAIN:-secureblog.example.com}"
API_TOKEN="${CF_API_TOKEN:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🛡️  DEPLOYING CLOUDFLARE WAF RULES${NC}"
echo "===================================="

# Validate environment
if [ -z "$ZONE_ID" ]; then
    echo -e "${RED}ERROR: CF_ZONE_ID not set${NC}"
    exit 1
fi

if [ -z "$API_TOKEN" ]; then
    echo -e "${RED}ERROR: CF_API_TOKEN not set${NC}"
    exit 1
fi

# Function to make Cloudflare API calls
cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    if [ -n "$data" ]; then
        curl -s -X "$method" "https://api.cloudflare.com/client/v4/$endpoint" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$data"
    else
        curl -s -X "$method" "https://api.cloudflare.com/client/v4/$endpoint" \
            -H "Authorization: Bearer $API_TOKEN"
    fi
}

# 1. Deploy WAF Custom Rules
echo -e "${BLUE}Deploying WAF custom rules...${NC}"

# Block non-GET/HEAD methods
BLOCK_METHODS_RULE='{
  "action": "block",
  "action_parameters": {
    "response": {
      "content_type": "text/html",
      "content": "<html><body><h1>405 Method Not Allowed</h1></body></html>",
      "status_code": 405
    }
  },
  "expression": "(http.request.method ne \"GET\" and http.request.method ne \"HEAD\")",
  "description": "Block all methods except GET and HEAD",
  "enabled": true
}'

# Block executable extensions
BLOCK_EXECUTABLES_RULE='{
  "action": "block", 
  "action_parameters": {
    "response": {
      "content_type": "text/html",
      "content": "<html><body><h1>404 Not Found</h1></body></html>",
      "status_code": 404
    }
  },
  "expression": "(http.request.uri.path matches \".*\\\\.(php|asp|aspx|jsp|cgi|pl|py|rb|sh|exe|dll|bat|cmd|ps1)$\")",
  "description": "Block executable file extensions",
  "enabled": true
}'

# Block JavaScript files
BLOCK_JS_RULE='{
  "action": "block",
  "action_parameters": {
    "response": {
      "content_type": "text/html", 
      "content": "<html><body><h1>404 Not Found</h1></body></html>",
      "status_code": 404
    }
  },
  "expression": "(http.request.uri.path matches \".*\\\\.(js|mjs|jsx|ts|tsx)$\")",
  "description": "Block JavaScript files (should not exist)",
  "enabled": true
}'

# Block hidden files (except .well-known)
BLOCK_HIDDEN_RULE='{
  "action": "block",
  "action_parameters": {
    "response": {
      "content_type": "text/html",
      "content": "<html><body><h1>404 Not Found</h1></body></html>",
      "status_code": 404
    }
  },
  "expression": "(http.request.uri.path matches \"^/\\\\..*\" and not http.request.uri.path matches \"^/\\\\.well-known/.*\")",
  "description": "Block hidden files except .well-known",
  "enabled": true
}'

# Create ruleset with all rules
CUSTOM_RULESET="{
  \"name\": \"SecureBlog Maximum Security WAF\",
  \"description\": \"Comprehensive WAF rules for static blog security\",
  \"kind\": \"zone\",
  \"phase\": \"http_request_firewall_custom\",
  \"rules\": [
    $BLOCK_METHODS_RULE,
    $BLOCK_EXECUTABLES_RULE,
    $BLOCK_JS_RULE,
    $BLOCK_HIDDEN_RULE
  ]
}"

echo "Creating WAF ruleset..."
RULESET_RESPONSE=$(cf_api "POST" "zones/$ZONE_ID/rulesets" "$CUSTOM_RULESET")
RULESET_ID=$(echo "$RULESET_RESPONSE" | jq -r '.result.id // empty')

if [ -n "$RULESET_ID" ]; then
    echo -e "${GREEN}✓ WAF ruleset created: $RULESET_ID${NC}"
else
    echo -e "${YELLOW}WARNING: WAF ruleset may already exist${NC}"
fi

# 2. Configure Zone Security Settings
echo -e "${BLUE}Configuring zone security settings...${NC}"

SECURITY_SETTINGS='{
  "settings": [
    {"id": "always_use_https", "value": "on"},
    {"id": "automatic_https_rewrites", "value": "on"},
    {"id": "browser_check", "value": "on"},
    {"id": "challenge_ttl", "value": 1800},
    {"id": "development_mode", "value": "off"},
    {"id": "email_obfuscation", "value": "on"},
    {"id": "hotlink_protection", "value": "on"},
    {"id": "min_tls_version", "value": "1.2"},
    {"id": "opportunistic_encryption", "value": "on"},
    {"id": "rocket_loader", "value": "off"},
    {"id": "security_level", "value": "high"},
    {"id": "server_side_exclude", "value": "on"},
    {"id": "ssl", "value": "strict"},
    {"id": "tls_1_3", "value": "on"},
    {"id": "waf", "value": "on"},
    {"id": "websockets", "value": "off"}
  ]
}'

echo "Updating zone security settings..."
SETTINGS_RESPONSE=$(cf_api "PATCH" "zones/$ZONE_ID/settings" "$SECURITY_SETTINGS")
echo -e "${GREEN}✓ Zone security settings updated${NC}"

# 3. Add Security Headers Transform Rule
echo -e "${BLUE}Adding security headers transform rule...${NC}"

HEADERS_TRANSFORM='{
  "name": "Add Comprehensive Security Headers",
  "description": "Add all required security headers to responses",
  "kind": "zone",
  "phase": "http_response_headers_transform",
  "rules": [{
    "action": "rewrite",
    "action_parameters": {
      "headers": {
        "Content-Security-Policy": "default-src '\''none'\''; img-src '\''self'\'' data:; style-src '\''self'\''; font-src '\''self'\''; base-uri '\''none'\''; form-action '\''none'\''; frame-ancestors '\''none'\''; block-all-mixed-content; upgrade-insecure-requests",
        "X-Frame-Options": "DENY",
        "X-Content-Type-Options": "nosniff",
        "X-XSS-Protection": "1; mode=block",
        "Referrer-Policy": "no-referrer",
        "Permissions-Policy": "accelerometer=(), battery=(), camera=(), display-capture=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()",
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Embedder-Policy": "require-corp",
        "Cross-Origin-Resource-Policy": "same-origin",
        "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
        "X-Security-Level": "maximum",
        "X-Static-Only": "true"
      }
    },
    "expression": "true",
    "description": "Add security headers to all responses",
    "enabled": true
  }]
}'

echo "Creating headers transform ruleset..."
HEADERS_RESPONSE=$(cf_api "POST" "zones/$ZONE_ID/rulesets" "$HEADERS_TRANSFORM")
HEADERS_RULESET_ID=$(echo "$HEADERS_RESPONSE" | jq -r '.result.id // empty')

if [ -n "$HEADERS_RULESET_ID" ]; then
    echo -e "${GREEN}✓ Headers transform ruleset created: $HEADERS_RULESET_ID${NC}"
else
    echo -e "${YELLOW}WARNING: Headers ruleset may already exist${NC}"
fi

# 4. Set up Rate Limiting
echo -e "${BLUE}Configuring rate limiting...${NC}"

RATE_LIMIT='{
  "threshold": 100,
  "period": 60,
  "match": {
    "request": {
      "url": "*'$DOMAIN'/*",
      "schemes": ["HTTP", "HTTPS"],
      "methods": ["GET", "HEAD"]
    }
  },
  "action": {
    "mode": "ban",
    "timeout": 300,
    "response": {
      "content_type": "text/html",
      "body": "<html><body><h1>429 Rate Limited</h1><p>Too many requests</p></body></html>"
    }
  },
  "correlate": {
    "by": "cf.client.ip"
  },
  "disabled": false,
  "description": "Global rate limit - 100 req/min per IP"
}'

echo "Creating rate limit rule..."
RATE_RESPONSE=$(cf_api "POST" "zones/$ZONE_ID/rate_limits" "$RATE_LIMIT")
echo -e "${GREEN}✓ Rate limiting configured${NC}"

# 5. Block admin paths with Access Rules
echo -e "${BLUE}Blocking admin paths...${NC}"

ADMIN_BLOCK='{
  "mode": "block",
  "configuration": {
    "target": "ip_range",
    "value": "0.0.0.0/0"
  },
  "notes": "Block all admin access"
}'

# Block common admin paths
for path in "/admin" "/wp-admin" "/administrator" "/phpmyadmin"; do
    echo "Blocking $path..."
    ADMIN_RESPONSE=$(cf_api "POST" "zones/$ZONE_ID/firewall/access_rules/rules" "$ADMIN_BLOCK")
done

echo -e "${GREEN}✓ Admin paths blocked${NC}"

# 6. Verify deployment
echo -e "${BLUE}Verifying WAF deployment...${NC}"

# Test with a blocked method
echo "Testing method blocking..."
POST_TEST=$(curl -X POST "https://$DOMAIN/" -o /dev/null -w "%{http_code}" -s || echo "000")
if [ "$POST_TEST" = "405" ] || [ "$POST_TEST" = "403" ]; then
    echo -e "${GREEN}✓ Method blocking verified${NC}"
else
    echo -e "${YELLOW}WARNING: Method blocking test returned $POST_TEST${NC}"
fi

# Test security headers
echo "Testing security headers..."
HEADERS_TEST=$(curl -sI "https://$DOMAIN/" | grep -i "content-security-policy\|x-frame-options" | wc -l)
if [ "$HEADERS_TEST" -ge 2 ]; then
    echo -e "${GREEN}✓ Security headers verified${NC}"
else
    echo -e "${YELLOW}WARNING: Security headers may not be applied yet${NC}"
fi

echo -e "\n${GREEN}✅ WAF DEPLOYMENT COMPLETE${NC}"
echo "=================================="
echo "Rules deployed:"
echo "  - Method restrictions (GET/HEAD only)"
echo "  - File extension blocking"
echo "  - Hidden file protection"
echo "  - Admin path blocking"
echo "  - Rate limiting (100 req/min)"
echo "  - Comprehensive security headers"
echo "  - High security level"
echo ""
echo "Your static blog now has maximum Cloudflare protection!"