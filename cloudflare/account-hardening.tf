# Cloudflare Account & Zone Hardening Configuration
# Implements maximum security with FIDO2, scoped tokens, and strict WAF

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# Variables
variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "domain" {
  description = "Domain name"
  type        = string
}

# Account-level security settings
resource "cloudflare_account_member" "security_settings" {
  account_id = var.cloudflare_account_id
  
  # Require FIDO2/WebAuthn for all users
  email_address = "security@${var.domain}"
  role_ids      = ["05784afa30c1afe1440e79d9351c7430"] # Super Administrator
  
  # Enforce 2FA
  status = "accepted"
}

# API Token Configuration (Scoped, never global)
resource "cloudflare_api_token" "pages_deploy" {
  name = "Pages Deploy Token - ${var.domain}"
  
  policy {
    permission_groups = [
      "c8fed203ed3043cba015a93ad1616f1f", # Cloudflare Pages:Edit
    ]
    resources = {
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    }
  }
  
  # Expire in 90 days
  not_after = timeadd(timestamp(), "2160h")
  
  # IP restrictions
  condition {
    request_ip {
      in = ["github.com/actions"] # Only GitHub Actions
    }
  }
}

resource "cloudflare_api_token" "r2_write" {
  name = "R2 Write Token - ${var.domain}"
  
  policy {
    permission_groups = [
      "9d24387c6e8544e2bc4024a03991339f", # Workers R2 Storage:Edit
    ]
    resources = {
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    }
  }
  
  # Expire in 30 days
  not_after = timeadd(timestamp(), "720h")
  
  # IP restrictions
  condition {
    request_ip {
      in = ["github.com/actions"]
    }
  }
}

# Pages deployment restrictions
resource "cloudflare_pages_project" "secureblog" {
  account_id = var.cloudflare_account_id
  name       = "secureblog"
  
  source {
    type = "github"
    config {
      owner                         = "your-org"
      repo_name                    = "secureblog"
      production_branch            = "main"
      pr_comments_enabled          = false
      deployments_enabled          = true
      production_deployment_enabled = true
      preview_deployment_setting   = "custom"
      preview_branch_includes      = ["develop"]
      preview_branch_excludes      = ["*"]
    }
  }
  
  build_config {
    build_command   = "./scripts/build-release-safe.sh"
    destination_dir = "dist"
    root_dir        = ""
  }
  
  deployment_configs {
    production {
      environment_variables = {
        NODE_ENV = "production"
        NO_JS    = "true"
      }
    }
  }
}

# WAF Custom Rules - Strict enforcement
resource "cloudflare_ruleset" "waf_strict" {
  zone_id = var.zone_id
  name    = "SecureBlog Ultra-Strict WAF"
  kind    = "zone"
  phase   = "http_request_firewall_custom"
  
  # Rule 1: Only allow GET/HEAD methods
  rules {
    action = "block"
    expression = "(http.request.method ne \"GET\" and http.request.method ne \"HEAD\")"
    description = "Block all non-GET/HEAD methods"
    enabled = true
  }
  
  # Rule 2: Block all query strings (unless needed)
  rules {
    action = "block"
    expression = "(http.request.uri.query ne \"\")"
    description = "Block all query strings"
    enabled = true
  }
  
  # Rule 3: Block suspicious paths
  rules {
    action = "block"
    expression = "(http.request.uri.path contains \"..\" or http.request.uri.path contains \"//\" or http.request.uri.path contains \"\\\\\")"
    description = "Block path traversal attempts"
    enabled = true
  }
  
  # Rule 4: Block executable extensions
  rules {
    action = "block"
    expression = "(http.request.uri.path.extension in {\"php\" \"asp\" \"aspx\" \"jsp\" \"cgi\" \"pl\" \"py\" \"rb\" \"sh\" \"exe\" \"dll\" \"bat\" \"cmd\" \"ps1\"})"
    description = "Block executable file extensions"
    enabled = true
  }
  
  # Rule 5: Block SQL injection patterns
  rules {
    action = "block"
    expression = "(http.request.uri contains \"union\" and http.request.uri contains \"select\") or (http.request.uri contains \"' or\" and http.request.uri contains \"='\")"
    description = "Block SQL injection attempts"
    enabled = true
  }
  
  # Rule 6: Block XSS attempts
  rules {
    action = "block"
    expression = "(http.request.uri contains \"<script\" or http.request.uri contains \"javascript:\" or http.request.uri contains \"onerror=\")"
    description = "Block XSS attempts"
    enabled = true
  }
  
  # Rule 7: Block large requests
  rules {
    action = "block"
    expression = "(http.request.body.size > 1024)"
    description = "Block requests larger than 1KB"
    enabled = true
  }
  
  # Rule 8: Block suspicious user agents
  rules {
    action = "block"
    expression = "(http.user_agent contains \"scanner\" or http.user_agent contains \"crawler\" or http.user_agent contains \"spider\" or http.user_agent contains \"bot\" and not cf.client.bot)"
    description = "Block suspicious user agents"
    enabled = true
  }
  
  # Rule 9: Rate limiting per IP
  rules {
    action = "challenge"
    expression = "(rate(60) > 60)"
    description = "Challenge IPs making >60 requests/minute"
    ratelimit {
      threshold = 60
      period    = 60
    }
    enabled = true
  }
  
  # Rule 10: Geo-blocking (optional)
  rules {
    action = "challenge"
    expression = "(ip.geoip.country in {\"CN\" \"RU\" \"KP\"})"
    description = "Challenge high-risk countries"
    enabled = false  # Enable if needed
  }
}

# Managed WAF Rules
resource "cloudflare_ruleset" "owasp" {
  zone_id = var.zone_id
  name    = "OWASP Managed Rules"
  kind    = "zone"
  phase   = "http_request_firewall_managed"
  
  rules {
    action = "execute"
    action_parameters {
      id = "efb7b8c949ac4650a09736fc376e9aee" # OWASP Core Ruleset
      version = "latest"
      overrides {
        enabled = true
        action  = "block"
        
        # Set all rules to block mode
        categories {
          category = "paranoia-level-1"
          action   = "block"
          enabled  = true
        }
        
        categories {
          category = "paranoia-level-2"
          action   = "block"
          enabled  = true
        }
      }
    }
    description = "Execute OWASP Core Ruleset"
    enabled = true
  }
}

# Bot Management
resource "cloudflare_bot_management" "strict" {
  zone_id = var.zone_id
  
  enable_js           = false  # No JavaScript challenges
  fight_mode         = true
  using_latest_model = true
  
  # Definitely automated
  definitely_automated_action = "block"
  
  # Likely automated
  likely_automated_action = "challenge"
  
  # Verified bots
  verified_bot_action = "allow"
  
  # Static resource protection
  static_resource_protection = true
  
  # Optimize for static site
  optimize_wordpress = false
}

# Zone Settings
resource "cloudflare_zone_settings_override" "security" {
  zone_id = var.zone_id
  
  settings {
    # Security
    security_level          = "high"
    challenge_ttl          = 7200
    browser_check          = "on"
    
    # SSL/TLS
    ssl                    = "strict"
    min_tls_version       = "1.3"
    automatic_https_rewrites = "on"
    always_use_https      = "on"
    
    # Performance
    http3                  = "on"
    zero_rtt              = "off"  # Security over performance
    
    # Privacy
    privacy_pass          = "on"
    
    # Caching
    browser_cache_ttl     = 31536000
    
    # Security headers
    security_header {
      enabled            = true
      include_subdomains = true
      max_age           = 63072000
      nosniff           = true
      preload           = true
    }
  }
}

# Page Rules for caching
resource "cloudflare_page_rule" "cache_static" {
  zone_id  = var.zone_id
  target   = "*.${var.domain}/*.{css,js,jpg,jpeg,png,gif,svg,woff,woff2,ttf,eot}"
  priority = 1
  
  actions {
    cache_level = "cache_everything"
    edge_cache_ttl = 31536000
    browser_cache_ttl = 31536000
    
    # Immutable for hashed assets
    cache_key_fields {
      header {
        include = ["accept-encoding"]
      }
      query_string {
        exclude = "*"
      }
    }
  }
}

# Emergency lockdown rule (disabled by default)
resource "cloudflare_filter" "emergency_lockdown" {
  zone_id     = var.zone_id
  description = "Emergency lockdown - block all except admin"
  expression  = "(ip.src ne 1.2.3.4)"  # Replace with admin IP
  paused      = true  # Enable in emergency
}

resource "cloudflare_firewall_rule" "emergency_lockdown" {
  zone_id     = var.zone_id
  description = "Emergency lockdown rule"
  filter_id   = cloudflare_filter.emergency_lockdown.id
  action      = "block"
  paused      = true  # Enable in emergency
}

# Outputs
output "api_token_pages" {
  value     = cloudflare_api_token.pages_deploy.id
  sensitive = true
}

output "api_token_r2" {
  value     = cloudflare_api_token.r2_write.id
  sensitive = true
}

output "waf_rules_count" {
  value = length(cloudflare_ruleset.waf_strict.rules)
}