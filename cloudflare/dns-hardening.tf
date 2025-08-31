# DNS/Domain Hardening Configuration
# Implements registrar lock, DNSSEC, and CAA records

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# Zone configuration with security settings
resource "cloudflare_zone" "secureblog" {
  account_id = var.cloudflare_account_id
  zone       = var.domain_name
  plan       = "pro" # Pro plan for advanced security features
  type       = "full"
  
  # Security settings
  jump_start = false # Prevent automatic record import
}

# Enable DNSSEC
resource "cloudflare_zone_dnssec" "secureblog_dnssec" {
  zone_id = cloudflare_zone.secureblog.id
}

# Registrar lock (domain lock)
resource "cloudflare_zone_lockdown" "registrar_lock" {
  zone_id     = cloudflare_zone.secureblog.id
  description = "Registrar lock - prevent unauthorized transfers"
  
  configurations {
    target = "domain"
    value  = "locked"
  }
}

# CAA Records - Only allow specific Certificate Authorities
resource "cloudflare_record" "caa_letsencrypt" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "issue"
    value = "letsencrypt.org"
  }
  
  comment = "Only allow Let's Encrypt to issue certificates"
}

resource "cloudflare_record" "caa_cloudflare" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "issue"
    value = "pki.goog; cansignhttpexchanges=yes"
  }
  
  comment = "Allow Google Trust Services for Cloudflare Universal SSL"
}

# CAA record for wildcard prevention
resource "cloudflare_record" "caa_no_wildcard" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "issuewild"
    value = ";"
  }
  
  comment = "Prevent wildcard certificate issuance"
}

# CAA incident reporting
resource "cloudflare_record" "caa_iodef" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = "0"
    tag   = "iodef"
    value = "mailto:security@${var.domain_name}"
  }
  
  comment = "Report CAA violations to security team"
}

# DMARC record for email security
resource "cloudflare_record" "dmarc" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "_dmarc"
  type    = "TXT"
  value   = "v=DMARC1; p=reject; rua=mailto:dmarc@${var.domain_name}; ruf=mailto:forensics@${var.domain_name}; fo=1; pct=100; adkim=s; aspf=s"
  
  comment = "DMARC policy - reject all unauthorized email"
}

# SPF record - no email sending allowed
resource "cloudflare_record" "spf" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "@"
  type    = "TXT"
  value   = "v=spf1 -all"
  
  comment = "SPF - no authorized senders (static site)"
}

# DKIM null record
resource "cloudflare_record" "dkim_null" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "*._domainkey"
  type    = "TXT"
  value   = "v=DKIM1; p="
  
  comment = "DKIM null key - no email signing"
}

# Security TXT record
resource "cloudflare_record" "security_txt" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "_security"
  type    = "TXT"
  value   = "security_policy=https://${var.domain_name}/.well-known/security.txt"
  
  comment = "Security policy location"
}

# DANE TLSA records for certificate pinning
resource "cloudflare_record" "dane_tlsa" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "_443._tcp"
  type    = "TLSA"
  
  data {
    usage         = 3  # Domain-issued certificate
    selector      = 1  # Public key
    matching_type = 1  # SHA-256
    certificate   = var.tlsa_certificate_hash
  }
  
  comment = "DANE TLSA for certificate pinning"
}

# Zone settings for security
resource "cloudflare_zone_settings_override" "security_settings" {
  zone_id = cloudflare_zone.secureblog.id
  
  settings {
    # SSL/TLS
    ssl                      = "strict"
    min_tls_version         = "1.3"
    tls_1_3                 = "on"
    automatic_https_rewrites = "on"
    always_use_https        = "on"
    opportunistic_encryption = "on"
    
    # Security headers
    security_header {
      enabled            = true
      include_subdomains = true
      max_age           = 31536000
      nosniff           = true
      preload           = true
    }
    
    # HSTS
    security_level = "high"
    
    # Privacy
    privacy_pass = "on"
    
    # Bot management
    bot_management {
      enable_js      = true
      suppress_session_score = false
    }
    
    # Challenge passage
    challenge_ttl = 3600
    
    # Browser integrity check
    browser_check = "on"
    
    # Email obfuscation
    email_obfuscation = "on"
    
    # Hotlink protection
    hotlink_protection = "on"
    
    # IP Geolocation
    ip_geolocation = "on"
    
    # IPv6
    ipv6 = "on"
    
    # 0-RTT
    zero_rtt = "off" # Disabled for security
  }
}

# Rate limiting rules
resource "cloudflare_rate_limit" "api_limit" {
  zone_id = cloudflare_zone.secureblog.id
  
  threshold = 10
  period    = 60
  
  match {
    request {
      url_pattern = "/api/*"
    }
  }
  
  action {
    mode    = "challenge"
    timeout = 3600
  }
  
  description = "API rate limiting"
}

# Firewall rules for additional protection
resource "cloudflare_firewall_rule" "block_bad_bots" {
  zone_id     = cloudflare_zone.secureblog.id
  description = "Block known bad bots"
  
  filter_id = cloudflare_filter.bad_bots.id
  action    = "block"
  priority  = 1
}

resource "cloudflare_filter" "bad_bots" {
  zone_id     = cloudflare_zone.secureblog.id
  description = "Known bad bot user agents"
  
  expression = "(cf.client.bot) and not (cf.verified_bot)"
}

# WAF custom rules
resource "cloudflare_ruleset" "security_waf" {
  zone_id = cloudflare_zone.secureblog.id
  name    = "SecureBlog WAF Rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"
  
  rules {
    action = "block"
    expression = "(http.request.uri.path contains \"..\" or http.request.uri.path contains \"//\")"
    description = "Block path traversal attempts"
  }
  
  rules {
    action = "block"
    expression = "(http.request.uri.query contains \"<script\" or http.request.uri.query contains \"javascript:\")"
    description = "Block XSS attempts in query strings"
  }
}

# Variables
variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for the secure blog"
  type        = string
}

variable "tlsa_certificate_hash" {
  description = "SHA-256 hash of the TLS certificate for DANE"
  type        = string
  sensitive   = true
}

# Outputs
output "dnssec_status" {
  value = cloudflare_zone_dnssec.secureblog_dnssec.status
}

output "dnssec_ds_record" {
  value     = cloudflare_zone_dnssec.secureblog_dnssec.ds
  sensitive = false
}

output "zone_id" {
  value = cloudflare_zone.secureblog.id
}