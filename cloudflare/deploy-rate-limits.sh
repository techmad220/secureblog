#!/usr/bin/env bash
# Deploy Cloudflare rate limiting rules via API
set -Eeuo pipefail

# Required environment variables
: "${CF_ZONE_ID:?Need CF_ZONE_ID}"
: "${CF_API_TOKEN:?Need CF_API_TOKEN}"

API_BASE="https://api.cloudflare.com/client/v4"

echo "🔒 Deploying CDN rate limiting rules..."

# 1. Create rate limiting rules
curl -X POST "$API_BASE/zones/$CF_ZONE_ID/rate_limits" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "match": {
      "request": {
        "url": "*"
      }
    },
    "threshold": 100,
    "period": 60,
    "action": {
      "mode": "challenge"
    }
  }'

# 2. Enable DDoS protection
curl -X PATCH "$API_BASE/zones/$CF_ZONE_ID/settings/security_level" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value": "high"}'

# 3. Configure WAF
curl -X PATCH "$API_BASE/zones/$CF_ZONE_ID/settings/waf" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value": "on"}'

# 4. Set up firewall rules
curl -X POST "$API_BASE/zones/$CF_ZONE_ID/firewall/rules" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '[
    {
      "filter": {
        "expression": "(http.user_agent contains \"bot\" and not http.user_agent contains \"Googlebot\")"
      },
      "action": "block",
      "description": "Block bad bots"
    },
    {
      "filter": {
        "expression": "(ip.geoip.country in {\"CN\" \"RU\" \"KP\"} and not ip.src in $allow_list)"
      },
      "action": "challenge",
      "description": "Challenge high-risk countries"
    }
  ]'

# 5. Enable Bot Fight Mode
curl -X PUT "$API_BASE/zones/$CF_ZONE_ID/bot_management" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "fight_mode": true,
    "enable_js": false
  }'

echo "✅ CDN rate limiting deployed"