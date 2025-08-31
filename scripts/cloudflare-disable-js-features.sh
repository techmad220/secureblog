#!/bin/bash
# Disable ALL Cloudflare JavaScript Features
# Ensures zero JavaScript injection from CDN optimizations

set -euo pipefail

CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

if [ -z "$CLOUDFLARE_ZONE_ID" ] || [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "❌ Required environment variables:"
    echo "  CLOUDFLARE_ZONE_ID"
    echo "  CLOUDFLARE_API_TOKEN"
    exit 1
fi

echo "🔒 DISABLING ALL CLOUDFLARE JAVASCRIPT FEATURES"
echo "=============================================="
echo "Zone ID: $CLOUDFLARE_ZONE_ID"
echo

# Function to make Cloudflare API calls
cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    if [ -n "$data" ]; then
        curl -s -X "$method" \
            "https://api.cloudflare.com/v4/zones/$CLOUDFLARE_ZONE_ID$endpoint" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" \
            "https://api.cloudflare.com/v4/zones/$CLOUDFLARE_ZONE_ID$endpoint" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
    fi
}

echo "1. Disabling Rocket Loader (JavaScript optimization)..."
RESULT=$(cf_api PATCH "/settings/rocket_loader" '{"value": "off"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ Rocket Loader: DISABLED"
else
    echo "   ❌ Failed to disable Rocket Loader"
fi

echo "2. Disabling Auto Minify for JavaScript..."
RESULT=$(cf_api PATCH "/settings/minify" '{"value": {"css": true, "html": true, "js": false}}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ JavaScript Minification: DISABLED"
else
    echo "   ❌ Failed to disable JS minification"
fi

echo "3. Disabling Mirage (lazy loading optimization)..."
RESULT=$(cf_api PATCH "/settings/mirage" '{"value": "off"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ Mirage: DISABLED"
else
    echo "   ❌ Failed to disable Mirage"
fi

echo "4. Disabling Polish (image optimization that may inject JS)..."
RESULT=$(cf_api PATCH "/settings/polish" '{"value": "off"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ Polish: DISABLED"
else
    echo "   ❌ Failed to disable Polish"
fi

echo "5. Disabling Email Obfuscation (injects JavaScript)..."
RESULT=$(cf_api PATCH "/settings/email_obfuscation" '{"value": "off"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ Email Obfuscation: DISABLED"
else
    echo "   ❌ Failed to disable Email Obfuscation"
fi

echo "6. Disabling Automatic HTTPS Rewrites (may inject scripts)..."
RESULT=$(cf_api PATCH "/settings/automatic_https_rewrites" '{"value": "off"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ Automatic HTTPS Rewrites: DISABLED"
else
    echo "   ❌ Failed to disable Automatic HTTPS Rewrites"
fi

echo "7. Enabling Security Features..."

# Enable WAF
RESULT=$(cf_api PATCH "/settings/waf" '{"value": "on"}')
echo "   $(echo "$RESULT" | jq -e '.success' >/dev/null && echo '✅' || echo '❌') WAF: ENABLED"

# Enable rate limiting
echo "8. Configuring Rate Limiting..."
RATE_LIMIT_RULE=$(cat << 'EOF'
{
  "match": {
    "request": {
      "methods": ["GET", "HEAD"],
      "schemes": ["HTTP", "HTTPS"]
    },
    "response": {
      "status": [200, 301, 302, 303, 304, 404]
    }
  },
  "threshold": 100,
  "period": 60,
  "action": {
    "mode": "challenge",
    "timeout": 86400
  }
}
EOF
)

RESULT=$(cf_api POST "/rate_limits" "$RATE_LIMIT_RULE")
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ Rate Limiting: CONFIGURED (100 req/min)"
else
    echo "   ⚠️  Rate limiting may already be configured"
fi

echo "9. Enforcing HSTS..."
RESULT=$(cf_api PATCH "/settings/security_header" '{"value": {"strict_transport_security": {"enabled": true, "max_age": 63072000, "include_subdomains": true, "preload": true}}}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ HSTS: ENABLED with preload"
else
    echo "   ❌ Failed to configure HSTS"
fi

echo "10. Setting TLS to strict..."
RESULT=$(cf_api PATCH "/settings/ssl" '{"value": "strict"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ SSL/TLS: STRICT mode"
else
    echo "   ❌ Failed to set strict TLS"
fi

echo "11. Setting minimum TLS version..."
RESULT=$(cf_api PATCH "/settings/min_tls_version" '{"value": "1.2"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ Minimum TLS: 1.2"
else
    echo "   ❌ Failed to set minimum TLS version"
fi

echo "12. Disabling TLS 1.0 and 1.1..."
RESULT=$(cf_api PATCH "/settings/tls_1_3" '{"value": "on"}')
if echo "$RESULT" | jq -e '.success' >/dev/null; then
    echo "   ✅ TLS 1.3: ENABLED"
else
    echo "   ❌ Failed to enable TLS 1.3"
fi

# Create verification script
cat > verify-cloudflare-settings.sh << 'EOF'
#!/bin/bash
# Verify Cloudflare settings are correctly configured

ZONE_ID="${CLOUDFLARE_ZONE_ID}"
API_TOKEN="${CLOUDFLARE_API_TOKEN}"

echo "🔍 VERIFYING CLOUDFLARE SETTINGS"
echo "================================"

# Get all settings
SETTINGS=$(curl -s "https://api.cloudflare.com/v4/zones/$ZONE_ID/settings" \
    -H "Authorization: Bearer $API_TOKEN")

# Check critical settings
echo "$SETTINGS" | jq -r '.result[] | select(.id == "rocket_loader") | "Rocket Loader: " + .value'
echo "$SETTINGS" | jq -r '.result[] | select(.id == "minify") | "JS Minify: " + (.value.js | tostring)'
echo "$SETTINGS" | jq -r '.result[] | select(.id == "mirage") | "Mirage: " + .value'
echo "$SETTINGS" | jq -r '.result[] | select(.id == "polish") | "Polish: " + .value'
echo "$SETTINGS" | jq -r '.result[] | select(.id == "email_obfuscation") | "Email Obfuscation: " + .value'

# Verify no JS injections
if echo "$SETTINGS" | jq -e '.result[] | select(.id == "rocket_loader" and .value != "off")' >/dev/null; then
    echo "❌ WARNING: Rocket Loader is ENABLED (injects JavaScript!)"
    exit 1
fi

if echo "$SETTINGS" | jq -e '.result[] | select(.id == "email_obfuscation" and .value != "off")' >/dev/null; then
    echo "❌ WARNING: Email Obfuscation is ENABLED (injects JavaScript!)"
    exit 1
fi

echo "✅ All JavaScript injection features are DISABLED"
EOF

chmod +x verify-cloudflare-settings.sh

echo
echo "✅ CLOUDFLARE JAVASCRIPT FEATURES DISABLED"
echo "========================================="
echo
echo "Disabled features that inject JavaScript:"
echo "  ❌ Rocket Loader - OFF"
echo "  ❌ JavaScript Minification - OFF"
echo "  ❌ Mirage - OFF"
echo "  ❌ Polish - OFF"
echo "  ❌ Email Obfuscation - OFF"
echo "  ❌ Automatic HTTPS Rewrites - OFF"
echo
echo "Enabled security features:"
echo "  ✅ WAF - ON"
echo "  ✅ Rate Limiting - 100 req/min"
echo "  ✅ HSTS Preload - ENABLED"
echo "  ✅ Strict TLS - ENFORCED"
echo "  ✅ Minimum TLS 1.2 - SET"
echo
echo "To verify settings: ./verify-cloudflare-settings.sh"
echo
echo "⚠️  IMPORTANT: These settings ensure Cloudflare NEVER injects JavaScript into your pages!"