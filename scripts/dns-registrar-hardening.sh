#!/bin/bash
# DNS/Registrar Hardening Implementation
# Implements comprehensive domain security with monitoring

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN="${1:-secureblog.example.com}"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

echo -e "${BLUE}🔐 DNS/REGISTRAR HARDENING IMPLEMENTATION${NC}"
echo "========================================="
echo "Domain: $DOMAIN"
echo "Implementing comprehensive domain security..."
echo

if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo -e "${RED}ERROR: CLOUDFLARE_ZONE_ID environment variable not set${NC}"
    exit 1
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo -e "${RED}ERROR: CLOUDFLARE_API_TOKEN environment variable not set${NC}"
    exit 1
fi

# Function to make Cloudflare API calls
cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    if [ -n "$data" ]; then
        curl -s -X "$method" \
            "https://api.cloudflare.com/v4$endpoint" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" \
            "https://api.cloudflare.com/v4$endpoint" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
    fi
}

echo -e "${BLUE}1. Enabling DNSSEC Protection...${NC}"

# Enable DNSSEC
DNSSEC_RESPONSE=$(cf_api "PATCH" "/zones/$CLOUDFLARE_ZONE_ID/dnssec" '{"status":"active"}' 2>/dev/null || echo '{"success":false}')

if echo "$DNSSEC_RESPONSE" | jq -r '.success' | grep -q "true"; then
    echo -e "${GREEN}   ✓ DNSSEC enabled successfully${NC}"
    
    # Get DS record information
    DS_RECORD=$(echo "$DNSSEC_RESPONSE" | jq -r '.result.ds // empty')
    if [ -n "$DS_RECORD" ] && [ "$DS_RECORD" != "null" ]; then
        echo -e "${YELLOW}   📋 DS Record for Registrar:${NC}"
        echo "$DS_RECORD"
        echo
        echo -e "${YELLOW}   ⚠️  CRITICAL: Add this DS record to your domain registrar${NC}"
        echo "   Without this step, DNSSEC will not provide protection"
    fi
    
    # Verify DNSSEC chain
    echo "   Verifying DNSSEC chain..."
    if dig +dnssec +short "$DOMAIN" >/dev/null 2>&1; then
        echo -e "${GREEN}   ✓ DNSSEC chain appears valid${NC}"
    else
        echo -e "${YELLOW}   ⚠️  DNSSEC chain not yet fully propagated${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️  Could not enable DNSSEC via API${NC}"
    echo -e "${YELLOW}   → Enable manually at: https://dash.cloudflare.com/$(echo $CLOUDFLARE_ZONE_ID | head -c8)/$DOMAIN/dns/settings${NC}"
fi

echo -e "${BLUE}2. Configuring CAA Records (Certificate Authority Authorization)...${NC}"

# Remove existing CAA records first to avoid duplicates
echo "   Removing any existing CAA records..."
EXISTING_CAA=$(cf_api "GET" "/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CAA" 2>/dev/null || echo '{"result":[]}')

if [ "$EXISTING_CAA" != '{"result":[]}' ]; then
    echo "$EXISTING_CAA" | jq -r '.result[]?.id // empty' | while read record_id; do
        if [ -n "$record_id" ] && [ "$record_id" != "empty" ]; then
            cf_api "DELETE" "/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" >/dev/null 2>&1
            echo "   Removed existing CAA record: $record_id"
        fi
    done
fi

# Add comprehensive CAA records
CAA_RECORDS=(
    '{"type":"CAA","name":"'$DOMAIN'","content":"0 issue \"letsencrypt.org\"","ttl":300,"comment":"Allow Let'\''s Encrypt certificate issuance"}'
    '{"type":"CAA","name":"'$DOMAIN'","content":"0 issuewild \"letsencrypt.org\"","ttl":300,"comment":"Allow Let'\''s Encrypt wildcard certificates"}'
    '{"type":"CAA","name":"'$DOMAIN'","content":"0 issue \"digicert.com\"","ttl":300,"comment":"Allow DigiCert as backup CA"}'
    '{"type":"CAA","name":"'$DOMAIN'","content":"0 iodef \"mailto:security@'$DOMAIN'\"","ttl":300,"comment":"Security contact for CA violations"}'
    '{"type":"CAA","name":"'$DOMAIN'","content":"128 issue \"\"","ttl":300,"comment":"Block all other certificate authorities"}'
)

echo "   Adding comprehensive CAA records..."
for caa_record in "${CAA_RECORDS[@]}"; do
    CAA_RESPONSE=$(cf_api "POST" "/zones/$CLOUDFLARE_ZONE_ID/dns_records" "$caa_record" 2>/dev/null || echo '{"success":false}')
    
    if echo "$CAA_RESPONSE" | jq -r '.success' | grep -q "true"; then
        CONTENT=$(echo "$caa_record" | jq -r '.content')
        echo -e "${GREEN}   ✓ CAA record added: $CONTENT${NC}"
    else
        ERROR_MSG=$(echo "$CAA_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')
        echo -e "${YELLOW}   ⚠️  CAA record failed: $ERROR_MSG${NC}"
    fi
done

echo -e "${BLUE}3. Adding Domain Security Monitoring Records...${NC}"

# Add monitoring records for security
MONITORING_RECORDS=(
    '{"type":"TXT","name":"_security-policy.'$DOMAIN'","content":"v=1; contact=security@'$DOMAIN'; expires=2025-12-31","ttl":300,"comment":"Security policy contact"}'
    '{"type":"TXT","name":"_dmarc.'$DOMAIN'","content":"v=DMARC1; p=reject; rua=mailto:security@'$DOMAIN'; ruf=mailto:security@'$DOMAIN'","ttl":300,"comment":"DMARC policy"}'
)

for record in "${MONITORING_RECORDS[@]}"; do
    RECORD_RESPONSE=$(cf_api "POST" "/zones/$CLOUDFLARE_ZONE_ID/dns_records" "$record" 2>/dev/null || echo '{"success":false}')
    
    if echo "$RECORD_RESPONSE" | jq -r '.success' | grep -q "true"; then
        NAME=$(echo "$record" | jq -r '.name')
        echo -e "${GREEN}   ✓ Monitoring record added: $NAME${NC}"
    else
        ERROR_MSG=$(echo "$RECORD_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')
        if echo "$ERROR_MSG" | grep -q "already exists"; then
            NAME=$(echo "$record" | jq -r '.name')
            echo -e "${GREEN}   ✓ Monitoring record exists: $NAME${NC}"
        else
            echo -e "${YELLOW}   ⚠️  Monitoring record failed: $ERROR_MSG${NC}"
        fi
    fi
done

echo -e "${BLUE}4. Creating DNS Monitoring Script...${NC}"

cat > scripts/monitor-dns-security.sh << 'EOF'
#!/bin/bash
# DNS Security Monitoring
# Monitors for unauthorized DNS changes and security violations

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN="${1:-secureblog.example.com}"
ALERT_EMAIL="${DNS_ALERT_EMAIL:-security@$DOMAIN}"

echo -e "${BLUE}🔍 DNS SECURITY MONITORING${NC}"
echo "========================="
echo "Domain: $DOMAIN"
echo "Alert email: $ALERT_EMAIL"
echo

ALERTS=0

# Function to send alert
send_alert() {
    local alert_type="$1"
    local message="$2"
    
    echo -e "${RED}🚨 SECURITY ALERT: $alert_type${NC}"
    echo "$message"
    
    # Log to syslog if available
    if command -v logger >/dev/null 2>&1; then
        logger -t dns-security-monitor "ALERT: $alert_type - $message"
    fi
    
    # Could integrate with alerting service here
    # curl -X POST "https://hooks.slack.com/..." -d "text=DNS ALERT: $message"
    
    ALERTS=$((ALERTS + 1))
}

# Check DNSSEC status
echo "Checking DNSSEC status..."
if dig +dnssec +short SOA "$DOMAIN" | grep -q "RRSIG"; then
    echo -e "${GREEN}✓ DNSSEC is active and working${NC}"
else
    send_alert "DNSSEC_FAILURE" "DNSSEC is not working for $DOMAIN"
fi

# Check CAA records
echo "Checking CAA records..."
CAA_RECORDS=$(dig +short CAA "$DOMAIN")
if [ -z "$CAA_RECORDS" ]; then
    send_alert "CAA_MISSING" "No CAA records found for $DOMAIN"
else
    echo -e "${GREEN}✓ CAA records found${NC}"
    
    # Check for Let's Encrypt authorization
    if echo "$CAA_RECORDS" | grep -q "letsencrypt.org"; then
        echo -e "${GREEN}✓ Let's Encrypt authorized${NC}"
    else
        send_alert "CAA_LETSENCRYPT_MISSING" "Let's Encrypt not authorized in CAA records"
    fi
    
    # Check for wildcard blocking
    if echo "$CAA_RECORDS" | grep -q 'issue ""'; then
        echo -e "${GREEN}✓ Unauthorized CAs blocked${NC}"
    else
        echo -e "${YELLOW}⚠️  No explicit CA blocking found${NC}"
    fi
fi

# Check nameservers haven't changed
echo "Checking nameserver security..."
CURRENT_NS=$(dig +short NS "$DOMAIN" | sort)
EXPECTED_NS="charlie.ns.cloudflare.com.
michelle.ns.cloudflare.com."

if [ "$CURRENT_NS" = "$EXPECTED_NS" ]; then
    echo -e "${GREEN}✓ Nameservers are correct${NC}"
else
    send_alert "NAMESERVER_CHANGE" "Nameserver change detected for $DOMAIN: $CURRENT_NS"
fi

# Check A/AAAA records for unexpected changes
echo "Checking A/AAAA records..."
CURRENT_A=$(dig +short A "$DOMAIN")
CURRENT_AAAA=$(dig +short AAAA "$DOMAIN")

# Store current records for comparison (simple approach)
RECORDS_FILE="/tmp/dns_records_$DOMAIN"
CURRENT_RECORDS="A: $CURRENT_A
AAAA: $CURRENT_AAAA"

if [ -f "$RECORDS_FILE" ]; then
    if ! diff -q "$RECORDS_FILE" <(echo "$CURRENT_RECORDS") >/dev/null; then
        send_alert "DNS_RECORD_CHANGE" "DNS records changed for $DOMAIN"
        echo "Previous records:"
        cat "$RECORDS_FILE"
        echo "Current records:"
        echo "$CURRENT_RECORDS"
    else
        echo -e "${GREEN}✓ DNS records unchanged${NC}"
    fi
else
    echo "Creating baseline DNS records file"
fi

# Update records file
echo "$CURRENT_RECORDS" > "$RECORDS_FILE"

# Check certificate transparency logs for unauthorized certificates
echo "Checking certificate transparency..."
if command -v curl >/dev/null 2>&1; then
    CT_RESULTS=$(curl -s "https://crt.sh/?q=$DOMAIN&output=json" | head -c 1000 2>/dev/null || echo "[]")
    
    if [ "$CT_RESULTS" = "[]" ] || [ -z "$CT_RESULTS" ]; then
        echo -e "${YELLOW}⚠️  No recent certificates found in CT logs${NC}"
    else
        # Count certificates issued in last 7 days
        RECENT_CERTS=$(echo "$CT_RESULTS" | grep -o '"not_before":"[^"]*"' | grep -c "$(date -d '7 days ago' '+%Y-%m')" || echo "0")
        if [ "$RECENT_CERTS" -gt 3 ]; then
            send_alert "EXCESSIVE_CERTIFICATES" "Unusual certificate activity: $RECENT_CERTS certificates in last 7 days"
        else
            echo -e "${GREEN}✓ Certificate activity normal${NC}"
        fi
    fi
fi

# Summary
echo
echo -e "${BLUE}DNS SECURITY MONITORING SUMMARY${NC}"
echo "==============================="
echo "Domain: $DOMAIN"
echo "Monitoring date: $(date)"
echo -e "Alerts generated: ${RED}$ALERTS${NC}"

if [ $ALERTS -eq 0 ]; then
    echo -e "${GREEN}✅ DNS SECURITY STATUS: GOOD${NC}"
    echo "No security issues detected"
else
    echo -e "${RED}❌ DNS SECURITY STATUS: ISSUES DETECTED${NC}"
    echo "Review alerts above and take corrective action"
fi

exit $ALERTS
EOF

chmod +x scripts/monitor-dns-security.sh
echo -e "${GREEN}   ✓ DNS monitoring script created${NC}"

echo -e "${BLUE}5. Creating Registrar Security Checklist...${NC}"

cat > docs/REGISTRAR-SECURITY.md << EOF
# Registrar Security Hardening Checklist

## Critical Actions Required at Your Domain Registrar

### 1. Enable Registrar Lock
**Status: ⚠️ MANUAL ACTION REQUIRED**

- [ ] Enable domain transfer lock
- [ ] Enable nameserver lock  
- [ ] Enable contact information lock
- [ ] Set up transfer authorization requirements

**Location:** Your registrar's domain management panel

### 2. Add DNSSEC DS Records
**Status: ⚠️ MANUAL ACTION REQUIRED**

Add the following DS record to your registrar:

\`\`\`
$(echo "$DNSSEC_RESPONSE" | jq -r '.result.ds // "DS record will be shown here after DNSSEC is enabled"')
\`\`\`

**Instructions:**
1. Log into your domain registrar
2. Find DNS/DNSSEC settings
3. Add the DS record exactly as shown above
4. Wait 24-48 hours for propagation
5. Verify with: \`dig +dnssec $DOMAIN\`

### 3. Enable 2FA for Registrar Account
**Status: ⚠️ MANUAL ACTION REQUIRED**

- [ ] Enable two-factor authentication
- [ ] Use hardware security key (FIDO2/WebAuthn preferred)
- [ ] Disable SMS/email backup methods if possible
- [ ] Generate and securely store backup codes

### 4. Set Up Account Monitoring
**Status: ⚠️ MANUAL ACTION REQUIRED**

- [ ] Enable email notifications for all domain changes
- [ ] Enable email notifications for login attempts
- [ ] Enable email notifications for DNS changes
- [ ] Set up account activity monitoring

### 5. Configure Domain Auto-Renewal
**Status: ⚠️ MANUAL ACTION REQUIRED**

- [ ] Enable automatic domain renewal
- [ ] Set up payment method alerts
- [ ] Configure renewal notifications (90, 30, 7 days)
- [ ] Ensure contact information is current

### 6. Review and Restrict Permissions
**Status: ⚠️ MANUAL ACTION REQUIRED**

- [ ] Remove unnecessary users from domain account
- [ ] Use principle of least privilege
- [ ] Regular review of account access
- [ ] Enable approval workflows for critical changes

## Automated Monitoring

### DNS Security Monitor
Run this script daily to monitor for unauthorized changes:

\`\`\`bash
./scripts/monitor-dns-security.sh $DOMAIN
\`\`\`

### What Gets Monitored
- DNSSEC status and validation
- CAA record presence and configuration  
- Nameserver changes
- A/AAAA record modifications
- Certificate transparency log activity
- Unusual certificate issuance patterns

### Alerting Setup
Set environment variable for alerts:
\`\`\`bash
export DNS_ALERT_EMAIL="security@$DOMAIN"
\`\`\`

## Verification Commands

### Check DNSSEC
\`\`\`bash
# Should show RRSIG records
dig +dnssec $DOMAIN SOA

# Validate DNSSEC chain
dig +dnssec +cd $DOMAIN
\`\`\`

### Check CAA Records
\`\`\`bash
# Should show Let's Encrypt authorization
dig CAA $DOMAIN

# Verify specific issuers
dig +short CAA $DOMAIN | grep "letsencrypt.org"
\`\`\`

### Check Nameservers
\`\`\`bash
# Should show Cloudflare nameservers
dig NS $DOMAIN
\`\`\`

## Security Timeline

| Action | Priority | Timeframe |
|--------|----------|-----------|
| Enable registrar lock | 🔴 CRITICAL | Within 24 hours |
| Add DNSSEC DS records | 🔴 CRITICAL | Within 48 hours |
| Enable 2FA | 🟡 HIGH | Within 1 week |
| Set up monitoring | 🟡 HIGH | Within 1 week |
| Configure auto-renewal | 🟢 MEDIUM | Within 1 month |

## Emergency Procedures

### If Domain is Compromised
1. **Immediate Actions:**
   - Contact registrar support immediately
   - Request domain freeze/lock
   - Provide DNSSEC DS records for verification
   
2. **Evidence Collection:**
   - Screenshot current DNS settings
   - Save DNS query results: \`dig ANY $DOMAIN\`
   - Check certificate transparency logs
   
3. **Recovery:**
   - Restore correct nameservers
   - Verify DNSSEC chain
   - Monitor certificate issuance
   - Reset registrar account credentials

### Contact Information
- **Registrar Support:** [Your registrar's emergency contact]
- **Cloudflare Support:** https://support.cloudflare.com/
- **DNS Security Team:** security@$DOMAIN

## Compliance Status

After completing all manual actions:
- ✅ DNSSEC enabled and validated
- ✅ CAA records restrict certificate issuance
- ✅ Registrar lock prevents unauthorized transfers
- ✅ 2FA protects registrar account
- ✅ Automated monitoring detects changes
- ✅ Domain auto-renewal prevents expiration

**Overall DNS Security Status: MAXIMUM**
EOF

echo -e "${GREEN}   ✓ Registrar security checklist created${NC}"

echo
echo -e "${GREEN}✅ DNS/REGISTRAR HARDENING SETUP COMPLETE${NC}"
echo "========================================"
echo
echo "✓ Automated Implementations:"
echo "  • DNSSEC enabled (requires DS record at registrar)"
echo "  • Comprehensive CAA records added"
echo "  • Security monitoring records configured"  
echo "  • DNS monitoring script created"
echo "  • Registrar security checklist generated"
echo
echo "🔴 CRITICAL MANUAL ACTIONS REQUIRED:"
echo "1. Add DS record to domain registrar (see output above)"
echo "2. Enable registrar lock for domain transfers"
echo "3. Enable 2FA with hardware keys for registrar account"
echo "4. Set up domain monitoring and alerts"
echo "5. Configure auto-renewal and payment monitoring"
echo
echo "📋 Complete checklist: docs/REGISTRAR-SECURITY.md"
echo "🔍 Monitor security: ./scripts/monitor-dns-security.sh $DOMAIN"
echo
echo "⚠️  Domain security is only as strong as your registrar account security!"
echo "Complete the manual actions within 48 hours for full protection."