#!/bin/bash
# Deploy Cloudflare Origin Hard-Lock Configuration
# Ensures no direct access to origin server - CDN-only architecture

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN="${1:-secureblog.example.com}"
ORIGIN_IP="${2:-}"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

echo -e "${BLUE}🔒 DEPLOYING CLOUDFLARE ORIGIN HARD-LOCK${NC}"
echo "========================================"
echo "Domain: $DOMAIN"
echo "Origin IP: ${ORIGIN_IP:-'Not specified (CDN-only)'}"
echo

# Check required environment variables
if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo -e "${RED}ERROR: CLOUDFLARE_ZONE_ID environment variable not set${NC}"
    echo "Get your Zone ID from the Cloudflare dashboard"
    exit 1
fi

if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
    echo -e "${RED}ERROR: CLOUDFLARE_ACCOUNT_ID environment variable not set${NC}"
    echo "Get your Account ID from the Cloudflare dashboard"
    exit 1
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo -e "${RED}ERROR: CLOUDFLARE_API_TOKEN environment variable not set${NC}"
    echo "Create an API token with Zone:Edit and Zone:Read permissions"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Terraform not installed${NC}"
    echo "Install Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
    exit 1
fi

# Navigate to Cloudflare configuration directory
if [ ! -d "cloudflare" ]; then
    echo -e "${RED}ERROR: cloudflare directory not found${NC}"
    echo "Run this script from the project root directory"
    exit 1
fi

cd cloudflare

# Initialize Terraform
echo -e "${BLUE}Initializing Terraform...${NC}"
terraform init

# Create terraform.tfvars with configuration
echo -e "${BLUE}Creating Terraform configuration...${NC}"
cat > terraform.tfvars << EOF
zone_id = "$CLOUDFLARE_ZONE_ID"
domain = "$DOMAIN"
origin_ip = "$ORIGIN_IP"
cloudflare_account_id = "$CLOUDFLARE_ACCOUNT_ID"
EOF

# Set Cloudflare provider credentials
export TF_VAR_cloudflare_api_token="$CLOUDFLARE_API_TOKEN"

# Validate the configuration
echo -e "${BLUE}Validating Terraform configuration...${NC}"
terraform validate

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform validation failed${NC}"
    exit 1
fi

# Plan the deployment
echo -e "${BLUE}Planning Terraform deployment...${NC}"
terraform plan -out=origin-hardlock.plan

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform planning failed${NC}"
    exit 1
fi

# Ask for confirmation
echo
echo -e "${YELLOW}This will deploy origin hard-lock configuration to Cloudflare.${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo "  • Blocking direct origin access"
echo "  • Enforcing Cloudflare IPs only"
echo "  • Host header validation"
echo "  • Method restrictions (GET/HEAD only)"
echo "  • Aggressive rate limiting"
echo "  • Security headers enforcement"

if [ -n "$ORIGIN_IP" ]; then
    echo "  • Cloudflare Tunnel configuration"
fi

echo
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Apply the configuration
echo -e "${BLUE}Applying Terraform configuration...${NC}"
terraform apply origin-hardlock.plan

if [ $? -eq 0 ]; then
    echo
    echo -e "${GREEN}✅ ORIGIN HARD-LOCK DEPLOYED SUCCESSFULLY${NC}"
    echo "======================================"
    echo
    echo "✓ Protection Features Enabled:"
    echo "  • Direct origin access blocked"
    echo "  • Cloudflare IPs only enforced"
    echo "  • Host header validation enabled"
    echo "  • Method restrictions (GET/HEAD only)"
    echo "  • Aggressive rate limiting active"
    echo "  • Security headers enforced"
    
    if [ -n "$ORIGIN_IP" ]; then
        echo "  • Cloudflare Tunnel configured"
        echo
        echo "🔧 Tunnel Setup:"
        echo "To complete the setup, install cloudflared on your origin server:"
        echo "  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared"
        echo "  chmod +x cloudflared"
        echo "  sudo mv cloudflared /usr/local/bin/"
        echo
        echo "Get tunnel credentials:"
        terraform output -json tunnel_credentials | jq -r '.tunnel_token'
        echo
        echo "Run tunnel:"
        echo "  cloudflared tunnel run --token <tunnel_token>"
    fi
    
    echo
    echo "🌐 Your site is now CDN-only protected!"
    echo "Direct origin access will return 403 Forbidden"
    
else
    echo -e "${RED}❌ DEPLOYMENT FAILED${NC}"
    echo "Check the error messages above"
    exit 1
fi

# Clean up
rm -f origin-hardlock.plan