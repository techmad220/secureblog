#!/bin/bash
# DNS & TLS Hygiene Setup - One-time configuration
# Configures DNSSEC, CAA records, and HSTS preload

set -euo pipefail

DOMAIN="${1:-secureblog.example.com}"
REGISTRAR="${2:-cloudflare}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 DNS & TLS Security Configuration${NC}"
echo "====================================="
echo "Domain: $DOMAIN"
echo "Registrar: $REGISTRAR"
echo ""

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is required but not installed${NC}"
        exit 1
    fi
}

# Check prerequisites
check_command "dig"
check_command "curl"
check_command "jq"

# 1. DNSSEC Configuration
echo -e "${BLUE}1. Configuring DNSSEC...${NC}"

# Check current DNSSEC status
echo "Checking current DNSSEC status..."
DNSSEC_STATUS=$(dig +dnssec "$DOMAIN" | grep -c "ad" || true)

if [ "$DNSSEC_STATUS" -gt 0 ]; then
    echo -e "${GREEN}  ✓ DNSSEC already enabled${NC}"
else
    echo -e "${YELLOW}  ⚠ DNSSEC not enabled${NC}"
    
    cat > dnssec-enable.md << EOF
# Enable DNSSEC

## At Your Registrar ($REGISTRAR):
1. Log into your domain registrar
2. Navigate to DNS settings for $DOMAIN
3. Enable DNSSEC
4. Copy the DS records

## At Cloudflare:
1. Go to DNS > Settings
2. Enable DNSSEC
3. Add DS records from registrar
4. Wait for propagation (up to 24 hours)

## Verify:
dig +dnssec $DOMAIN
# Look for 'ad' flag (authenticated data)
EOF
    
    echo -e "${YELLOW}  Instructions saved to: dnssec-enable.md${NC}"
fi

# 2. CAA Records
echo -e "\n${BLUE}2. Configuring CAA Records...${NC}"

# Check existing CAA records
echo "Checking existing CAA records..."
CAA_RECORDS=$(dig +short CAA "$DOMAIN")

if [ -n "$CAA_RECORDS" ]; then
    echo -e "${GREEN}  ✓ CAA records found:${NC}"
    echo "$CAA_RECORDS"
else
    echo -e "${YELLOW}  ⚠ No CAA records found${NC}"
    echo "  Creating CAA record configuration..."
    
    cat > caa-records.tf << 'EOF'
# CAA Records - Only allow Let's Encrypt to issue certificates

resource "cloudflare_record" "caa_letsencrypt" {
  zone_id = var.zone_id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "issue"
    value = "letsencrypt.org"
  }
  
  comment = "Only Let's Encrypt can issue certificates"
}

resource "cloudflare_record" "caa_letsencrypt_wildcard" {
  zone_id = var.zone_id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "issuewild"
    value = "letsencrypt.org"
  }
  
  comment = "Only Let's Encrypt can issue wildcard certificates"
}

resource "cloudflare_record" "caa_no_others" {
  zone_id = var.zone_id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "issue"
    value = ";"
  }
  
  comment = "Explicitly deny all other CAs"
}

resource "cloudflare_record" "caa_iodef" {
  zone_id = var.zone_id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "iodef"
    value = "mailto:security@${var.domain}"
  }
  
  comment = "Report CAA violations"
}
EOF
    
    # Manual DNS commands
    cat > caa-manual.sh << EOF
#!/bin/bash
# Manual CAA record creation

# Via Cloudflare API
curl -X POST "https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records" \\
  -H "Authorization: Bearer \$CF_API_TOKEN" \\
  -H "Content-Type: application/json" \\
  --data '{
    "type": "CAA",
    "name": "@",
    "data": {
      "flags": 0,
      "tag": "issue",
      "value": "letsencrypt.org"
    }
  }'

# Via CLI
cf dns create $DOMAIN CAA "0 issue letsencrypt.org"
cf dns create $DOMAIN CAA "0 issuewild letsencrypt.org"
cf dns create $DOMAIN CAA "0 iodef mailto:security@$DOMAIN"
EOF
    
    chmod +x caa-manual.sh
    echo -e "${GREEN}  ✓ CAA configuration created${NC}"
fi

# 3. HSTS Preload
echo -e "\n${BLUE}3. HSTS Preload Configuration...${NC}"

# Check if domain is on HSTS preload list
echo "Checking HSTS preload status..."
HSTS_STATUS=$(curl -s "https://hstspreload.org/api/v2/status?domain=$DOMAIN" | jq -r '.status' 2>/dev/null || echo "unknown")

case "$HSTS_STATUS" in
    "preloaded")
        echo -e "${GREEN}  ✓ Domain is already on HSTS preload list${NC}"
        ;;
    "pending")
        echo -e "${YELLOW}  ⚠ Domain is pending addition to preload list${NC}"
        ;;
    *)
        echo -e "${YELLOW}  ⚠ Domain not on HSTS preload list${NC}"
        
        # Check current headers
        echo "  Checking current HSTS header..."
        HSTS_HEADER=$(curl -sI "https://$DOMAIN" | grep -i "strict-transport-security" || true)
        
        if [ -n "$HSTS_HEADER" ]; then
            echo "  Current header: $HSTS_HEADER"
            
            # Check if header meets requirements
            if echo "$HSTS_HEADER" | grep -q "max-age=63072000.*includeSubDomains.*preload"; then
                echo -e "${GREEN}  ✓ HSTS header meets preload requirements${NC}"
                echo ""
                echo -e "${BLUE}  Submit for preload at:${NC}"
                echo "  https://hstspreload.org/?domain=$DOMAIN"
                echo ""
                echo "  Automated submission:"
                cat > submit-hsts.sh << EOF
#!/bin/bash
# Submit domain for HSTS preload

curl -X POST "https://hstspreload.org/api/v2/submit" \\
  -H "Content-Type: application/json" \\
  -d '{
    "domain": "$DOMAIN",
    "includeSubDomains": true
  }'
EOF
                chmod +x submit-hsts.sh
                echo "  Run: ./submit-hsts.sh"
            else
                echo -e "${RED}  ✗ HSTS header does not meet requirements${NC}"
                echo "  Required: Strict-Transport-Security: max-age=63072000; includeSubDomains; preload"
            fi
        else
            echo -e "${RED}  ✗ No HSTS header found${NC}"
            echo "  Add to nginx/Cloudflare:"
            echo "  Strict-Transport-Security: max-age=63072000; includeSubDomains; preload"
        fi
        ;;
esac

# 4. Additional DNS Security
echo -e "\n${BLUE}4. Additional DNS Security Records...${NC}"

# DMARC record (no email = reject all)
echo "Checking DMARC record..."
DMARC=$(dig +short TXT "_dmarc.$DOMAIN")
if [ -z "$DMARC" ]; then
    echo -e "${YELLOW}  ⚠ No DMARC record found${NC}"
    echo "  Recommended: v=DMARC1; p=reject; fo=1"
else
    echo -e "${GREEN}  ✓ DMARC: $DMARC${NC}"
fi

# SPF record (no email = hard fail all)
echo "Checking SPF record..."
SPF=$(dig +short TXT "$DOMAIN" | grep "v=spf1" || true)
if [ -z "$SPF" ]; then
    echo -e "${YELLOW}  ⚠ No SPF record found${NC}"
    echo "  Recommended: v=spf1 -all"
else
    echo -e "${GREEN}  ✓ SPF: $SPF${NC}"
fi

# 5. Registrar Security
echo -e "\n${BLUE}5. Registrar Security Configuration...${NC}"

cat > registrar-security.md << EOF
# Registrar Security Checklist

## Domain Lock
- [ ] Enable registrar lock/domain lock
- [ ] Require 2FA for unlock
- [ ] Set up transfer lock

## Account Security
- [ ] Enable 2FA/MFA on registrar account
- [ ] Use hardware security key (FIDO2)
- [ ] Set up account alerts

## WHOIS Privacy
- [ ] Enable WHOIS privacy/proxy
- [ ] Use security@ email for contacts

## Auto-renewal
- [ ] Enable auto-renewal
- [ ] Set expiry alerts 90 days in advance
EOF

echo -e "${GREEN}  ✓ Registrar security checklist created${NC}"

# 6. Verification Script
echo -e "\n${BLUE}6. Creating Verification Script...${NC}"

cat > verify-dns-tls.sh << 'EOF'
#!/bin/bash
# Verify DNS & TLS Configuration

DOMAIN="${1:-secureblog.example.com}"

echo "🔍 DNS & TLS Verification for $DOMAIN"
echo "======================================"

# DNSSEC
echo -n "DNSSEC: "
if dig +dnssec "$DOMAIN" | grep -q "ad"; then
    echo "✅ Enabled (authenticated)"
else
    echo "❌ Not enabled or not authenticated"
fi

# CAA Records
echo -n "CAA Records: "
CAA=$(dig +short CAA "$DOMAIN")
if [ -n "$CAA" ]; then
    echo "✅ Present"
    echo "$CAA" | sed 's/^/  /'
else
    echo "❌ Missing"
fi

# HSTS Header
echo -n "HSTS Header: "
HSTS=$(curl -sI "https://$DOMAIN" | grep -i "strict-transport-security" || true)
if [ -n "$HSTS" ]; then
    if echo "$HSTS" | grep -q "max-age=63072000.*includeSubDomains.*preload"; then
        echo "✅ Preload-ready"
    else
        echo "⚠️  Present but not preload-ready"
    fi
    echo "  $HSTS"
else
    echo "❌ Missing"
fi

# HSTS Preload Status
echo -n "HSTS Preload: "
STATUS=$(curl -s "https://hstspreload.org/api/v2/status?domain=$DOMAIN" | jq -r '.status' 2>/dev/null || echo "error")
case "$STATUS" in
    "preloaded") echo "✅ On preload list" ;;
    "pending") echo "⏳ Pending addition" ;;
    *) echo "❌ Not on list" ;;
esac

# TLS Version
echo -n "TLS Version: "
TLS_VERSION=$(echo | openssl s_client -connect "$DOMAIN:443" 2>/dev/null | grep "Protocol" | awk '{print $3}')
if [[ "$TLS_VERSION" == "TLSv1.3" ]] || [[ "$TLS_VERSION" == "TLSv1.2" ]]; then
    echo "✅ $TLS_VERSION"
else
    echo "⚠️  $TLS_VERSION (should be TLS 1.2+)"
fi

# Certificate CA
echo -n "Certificate Issuer: "
ISSUER=$(echo | openssl s_client -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -issuer | sed 's/.*O=\([^,]*\).*/\1/')
echo "$ISSUER"

echo ""
echo "Run full security check: ./scripts/security-self-check.sh"
EOF

chmod +x verify-dns-tls.sh

echo -e "${GREEN}  ✓ Verification script created${NC}"

# Summary
echo -e "\n${BLUE}=== DNS & TLS Security Summary ===${NC}"
echo "===================================="

echo -e "\n${GREEN}Required Actions:${NC}"
echo "1. Enable DNSSEC at registrar and Cloudflare"
echo "2. Add CAA records (only Let's Encrypt)"
echo "3. Submit to HSTS preload: https://hstspreload.org"
echo "4. Enable domain lock at registrar"
echo "5. Configure 2FA with hardware keys"

echo -e "\n${GREEN}Files Created:${NC}"
echo "• dnssec-enable.md - DNSSEC instructions"
echo "• caa-records.tf - CAA Terraform config"
echo "• caa-manual.sh - Manual CAA commands"
echo "• submit-hsts.sh - HSTS preload submission"
echo "• registrar-security.md - Security checklist"
echo "• verify-dns-tls.sh - Verification script"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Run: terraform apply -target=module.caa_records"
echo "2. Visit: https://hstspreload.org/?domain=$DOMAIN"
echo "3. Run: ./verify-dns-tls.sh $DOMAIN"