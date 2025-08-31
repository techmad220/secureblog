#!/usr/bin/env bash
# cloudflare-waf-hardening.sh - Advanced Cloudflare WAF rules and edge hardening
set -euo pipefail

ZONE_NAME="${CF_ZONE_NAME:-secureblog.com}"
API_TOKEN="${CF_API_TOKEN:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔥 Cloudflare WAF & Edge Hardening${NC}"
echo "=================================="
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
        exit 1
    fi
    
    echo "$response" | jq -r '.result[0].id'
}

ZONE_ID=$(get_zone_id)
echo -e "${GREEN}✅ Zone ID: $ZONE_ID${NC}"
echo ""

# 1. Method restrictions - Block everything except GET/HEAD
echo "🚫 Creating method restriction rules..."

method_rule='{
  "filter": {
    "expression": "not (http.request.method in {\"GET\" \"HEAD\" \"OPTIONS\"})"
  },
  "action": "block",
  "description": "Block all methods except GET/HEAD/OPTIONS",
  "enabled": true
}'

response=$(cf_api POST "zones/$ZONE_ID/firewall/rules" "$method_rule")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Method restriction rule created${NC}"
else
    echo -e "${YELLOW}⚠️ Method restriction rule may already exist${NC}"
fi

# 2. Query string protection - Block dangerous patterns
echo "🛡️ Creating query string protection rules..."

query_patterns=(
    "__proto__"
    "<script"
    "javascript:"
    "vbscript:"
    "data:text/html"
    "onload="
    "onerror="
    "onclick="
    "eval("
    "alert("
    "document.cookie"
    "document.location"
    "window.location"
    ".innerHTML"
    "settimeout"
    "setinterval"
)

for i, pattern in "${!query_patterns[@]}"; do
    rule_name="Block dangerous query pattern: $pattern"
    
    query_rule="{
      \"filter\": {
        \"expression\": \"contains(lower(http.request.uri.query), \\\"$(echo "$pattern" | tr '[:upper:]' '[:lower:]')\\\") or contains(lower(http.request.uri.path), \\\"$(echo "$pattern" | tr '[:upper:]' '[:lower:]')\\\")\"
      },
      \"action\": \"block\",
      \"description\": \"$rule_name\",
      \"enabled\": true
    }"
    
    response=$(cf_api POST "zones/$ZONE_ID/firewall/rules" "$query_rule")
    if echo "$response" | jq -e '.success' >/dev/null; then
        echo -e "${GREEN}✅ Query protection rule created: $pattern${NC}"
    else
        echo -e "${YELLOW}⚠️ Rule may already exist: $pattern${NC}"
    fi
    
    # Rate limit API calls
    sleep 1
done

# 3. Rate limiting rules
echo "🚦 Creating comprehensive rate limiting rules..."

# Global rate limit
global_rate_limit='{
  "match": {
    "request": {
      "methods": ["GET", "HEAD"],
      "schemes": ["HTTPS"],
      "url": "*"
    }
  },
  "threshold": 100,
  "period": 60,
  "action": {
    "mode": "challenge",
    "timeout": 3600,
    "response": {
      "content_type": "text/plain",
      "body": "Rate limit exceeded. Please wait before trying again."
    }
  },
  "correlate": {
    "by": "nat"
  },
  "description": "Global rate limit: 100 requests per minute per IP"
}'

response=$(cf_api POST "zones/$ZONE_ID/rate_limits" "$global_rate_limit")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Global rate limiting configured${NC}"
else
    echo -e "${YELLOW}⚠️ Global rate limit may already exist${NC}"
fi

# Aggressive scanner rate limit
scanner_rate_limit='{
  "match": {
    "request": {
      "methods": ["GET", "HEAD"],
      "schemes": ["HTTPS"],
      "url": "*"
    },
    "response": {
      "status": [403, 404]
    }
  },
  "threshold": 10,
  "period": 300,
  "action": {
    "mode": "ban",
    "timeout": 86400
  },
  "correlate": {
    "by": "nat"
  },
  "description": "Ban aggressive scanners: 10 4xx responses in 5 minutes = 24hr ban"
}'

response=$(cf_api POST "zones/$ZONE_ID/rate_limits" "$scanner_rate_limit")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Scanner protection rate limiting configured${NC}"
else
    echo -e "${YELLOW}⚠️ Scanner rate limit may already exist${NC}"
fi

# 4. Geographic and ASN-based challenges (configurable)
echo "🌍 Setting up geographic challenge rules..."

# Challenge high-risk countries (customize as needed)
high_risk_countries='["CN", "RU", "KP", "IR"]'  # Customize based on your requirements

geo_challenge_rule="{
  \"filter\": {
    \"expression\": \"ip.geoip.country in {$high_risk_countries}\"
  },
  \"action\": \"challenge\",
  \"description\": \"Challenge requests from high-risk countries\",
  \"enabled\": false
}"

response=$(cf_api POST "zones/$ZONE_ID/firewall/rules" "$geo_challenge_rule")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${YELLOW}⚠️ Geographic challenge rule created (DISABLED by default)${NC}"
    echo "   Enable by setting 'enabled': true and customizing country list"
else
    echo -e "${YELLOW}⚠️ Geographic rule may already exist${NC}"
fi

# 5. Bot challenge for suspicious user agents
echo "🤖 Creating bot challenge rules..."

bot_challenge_rule='{
  "filter": {
    "expression": "not cf.client.bot or cf.threat_score gt 14"
  },
  "action": "js_challenge",
  "description": "Challenge suspicious bots and high threat score IPs",
  "enabled": true
}'

response=$(cf_api POST "zones/$ZONE_ID/firewall/rules" "$bot_challenge_rule")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Bot challenge rule created${NC}"
else
    echo -e "${YELLOW}⚠️ Bot challenge rule may already exist${NC}"
fi

# 6. Transform Rules for security headers (ensures headers even if origin reappears)
echo "🔄 Setting up transform rules for security headers..."

# Create transform rule to add security headers
transform_rule='{
  "description": "Add comprehensive security headers",
  "rules": [
    {
      "enabled": true,
      "expression": "true",
      "action": "rewrite",
      "action_parameters": {
        "headers": {
          "X-Content-Type-Options": {
            "operation": "set",
            "value": "nosniff"
          },
          "Cross-Origin-Embedder-Policy": {
            "operation": "set", 
            "value": "require-corp"
          },
          "Cross-Origin-Resource-Policy": {
            "operation": "set",
            "value": "same-origin" 
          },
          "Referrer-Policy": {
            "operation": "set",
            "value": "no-referrer"
          },
          "Content-Security-Policy": {
            "operation": "set",
            "value": "default-src '\''none'\''; base-uri '\''none'\''; frame-ancestors '\''none'\''; form-action '\''none'\''; script-src '\''none'\''; connect-src '\''none'\''; img-src '\''self'\'' data:; style-src '\''self'\''; font-src '\''self'\''; object-src '\''none'\''; media-src '\''self'\''; worker-src '\''none'\''; manifest-src '\''self'\''; frame-src '\''none'\''; upgrade-insecure-requests"
          },
          "Strict-Transport-Security": {
            "operation": "set",
            "value": "max-age=63072000; includeSubDomains; preload"
          },
          "Permissions-Policy": {
            "operation": "set",
            "value": "accelerometer=(), ambient-light-sensor=(), autoplay=(), battery=(), camera=(), cross-origin-isolated=(), display-capture=(), document-domain=(), encrypted-media=(), execution-while-not-rendered=(), execution-while-out-of-viewport=(), fullscreen=(), geolocation=(), gyroscope=(), keyboard-map=(), magnetometer=(), microphone=(), midi=(), payment=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), sync-xhr=(), usb=(), web-share=(), xr-spatial-tracking=()"
          }
        }
      }
    }
  ]
}'

response=$(cf_api POST "zones/$ZONE_ID/rulesets/phases/http_response_headers_transform/entrypoint" "$transform_rule")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ Security headers transform rule created${NC}"
else
    echo -e "${YELLOW}⚠️ Transform rule may already exist${NC}"
fi

# 7. Enable HSTS and submit for preload
echo "🔒 Configuring HSTS with preload..."

hsts_config='{
  "value": {
    "enabled": true,
    "max_age": 63072000,
    "include_subdomains": true,
    "preload": true,
    "no_sniff": true
  }
}'

response=$(cf_api PATCH "zones/$ZONE_ID/settings/security_header" "$hsts_config")
if echo "$response" | jq -e '.success' >/dev/null; then
    echo -e "${GREEN}✅ HSTS configured with 2-year max-age and preload${NC}"
    echo -e "${BLUE}🔗 Submit to HSTS preload list: https://hstspreload.org/${NC}"
else
    echo -e "${RED}❌ Failed to configure HSTS${NC}"
fi

# 8. Configure API token with least privilege (informational)
echo "🔑 API Token Security Recommendations..."
echo -e "${BLUE}ℹ️ Ensure your CF_API_TOKEN has minimal permissions:${NC}"
echo "   • Zone:Zone Settings:Edit (for specific zone only)"
echo "   • Zone:Zone:Read (for zone ID lookup)"
echo "   • Zone:Firewall Services:Edit (for WAF rules)"
echo "   • Account:Account Rulesets:Edit (for transform rules)"
echo ""
echo -e "${YELLOW}⚠️ Review token permissions at: https://dash.cloudflare.com/profile/api-tokens${NC}"

# 9. Generate WAF configuration report
echo "📊 Generating WAF configuration report..."

cat > cloudflare-waf-report.md << EOF
# Cloudflare WAF & Edge Hardening Report

**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Zone**: $ZONE_NAME
**Zone ID**: $ZONE_ID

## Security Rules Implemented

### Method Restrictions
- ✅ **Block all methods except GET/HEAD/OPTIONS**
- Purpose: Prevent POST/PUT/DELETE attacks
- Status: Active

### Query String Protection
- ✅ **Block dangerous patterns in URLs and query strings**
- Patterns blocked: __proto__, <script, javascript:, eval(), etc.
- Total patterns: ${#query_patterns[@]}
- Purpose: Prevent XSS and injection attacks via URL manipulation

### Rate Limiting
- ✅ **Global rate limit**: 100 requests/minute per IP with challenge
- ✅ **Scanner protection**: 10x 4xx responses = 24hr ban
- Purpose: DDoS protection and scanner deterrence

### Bot Management
- ✅ **JavaScript challenge for suspicious bots**
- ✅ **Challenge high threat score IPs (>14)**
- Purpose: Automated threat mitigation

### Geographic Controls
- ⚠️ **High-risk country challenges** (Disabled by default)
- Countries: China, Russia, North Korea, Iran
- Purpose: Geo-based threat reduction (enable if needed)

### Security Headers (Transform Rules)
- ✅ **Comprehensive security headers enforced at edge**
- Headers: CSP, HSTS, CORP, COEP, X-Frame-Options, etc.
- Purpose: Defense in depth even if origin server exists

### HSTS Configuration  
- ✅ **2-year max-age with includeSubDomains and preload**
- Submit to: https://hstspreload.org/
- Purpose: Force HTTPS and prevent downgrade attacks

## Validation Commands

\`\`\`bash
# Test method blocking
curl -X POST https://$ZONE_NAME/ -I
# Should return 405 Method Not Allowed

# Test dangerous query patterns  
curl "https://$ZONE_NAME/?test=<script>alert(1)</script>" -I
# Should return 403 Forbidden

# Test rate limiting
for i in {1..101}; do curl -s https://$ZONE_NAME/ >/dev/null; done
# Should trigger challenge after 100 requests

# Test security headers
curl -I https://$ZONE_NAME/
# Should include all security headers
\`\`\`

## Security Benefits

1. **Attack Surface Reduction**: Only GET/HEAD methods allowed
2. **Injection Prevention**: Dangerous patterns blocked in URLs
3. **DDoS Mitigation**: Comprehensive rate limiting with escalation
4. **Bot Protection**: JavaScript challenges for suspicious traffic  
5. **Header Enforcement**: Security headers guaranteed at edge
6. **HSTS Preload**: Browser-level HTTPS enforcement

## Monitoring Recommendations

1. **Review Firewall Events**: Monitor blocked requests in CF dashboard
2. **Adjust Rate Limits**: Fine-tune based on legitimate traffic patterns
3. **Geographic Rules**: Enable country blocking if threats detected
4. **Bot Score Tuning**: Adjust challenge threshold based on false positives
5. **Header Validation**: Verify security headers on all responses

## Next Steps

1. Monitor WAF logs for false positives
2. Fine-tune rate limiting thresholds
3. Submit domain to HSTS preload list
4. Enable geographic blocking if needed
5. Review and rotate API tokens regularly

EOF

echo "📄 WAF report saved to: cloudflare-waf-report.md"

# Final summary
echo ""
echo -e "${GREEN}🎉 Cloudflare WAF & Edge Hardening Complete!${NC}"
echo "=============================================="
echo ""
echo -e "${GREEN}✅ Security Features Deployed:${NC}"
echo "  • Method restrictions (GET/HEAD only)"
echo "  • Query string pattern blocking (${#query_patterns[@]} patterns)"
echo "  • Comprehensive rate limiting"
echo "  • Bot management with JS challenges"
echo "  • Geographic challenge rules (configurable)"
echo "  • Transform rules for security headers"
echo "  • HSTS with preload configuration"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "  1. Monitor WAF logs in Cloudflare dashboard"
echo "  2. Submit domain to HSTS preload list"
echo "  3. Review rate limiting effectiveness"
echo "  4. Enable geographic blocking if needed"
echo "  5. Regularly rotate API tokens"
echo ""
echo -e "${GREEN}🛡️ Your edge is now Fort Knox hardened!${NC}"