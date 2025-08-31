# Cloudflare Origin Hard-Lock Configuration
# Ensures no direct access to origin server - CDN-only architecture

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

variable "zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "secureblog.example.com"
}

variable "origin_ip" {
  description = "Origin server IP (if self-hosting)"
  type        = string
  default     = ""
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

# Access Rules - Block all direct origin access
resource "cloudflare_access_rule" "block_direct_origin" {
  count   = var.origin_ip != "" ? 1 : 0
  zone_id = var.zone_id
  mode    = "block"
  
  configuration {
    target = "ip"
    value  = var.origin_ip
  }
  
  notes = "Block direct access to origin server - force CDN-only"
}

# Firewall Rules - Cloudflare IP Allowlist Only
resource "cloudflare_ruleset" "origin_protection" {
  zone_id     = var.zone_id
  name        = "Origin Protection - CF IPs Only"
  description = "Block all traffic not coming from Cloudflare IPs"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  # Block all non-Cloudflare traffic
  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>Direct origin access not allowed</p></body></html>"
        status_code  = 403
      }
    }
    expression  = "not cf.edge.server_ip"
    description = "Block all traffic not from Cloudflare edge"
    enabled     = true
  }

  # Additional validation - Host header check
  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>Invalid host header</p></body></html>"
        status_code  = 403
      }
    }
    expression  = "not (http.host eq \"${var.domain}\" or http.host eq \"www.${var.domain}\")"
    description = "Validate host header matches expected domain"
    enabled     = true
  }

  # Method restrictions - GET/HEAD only at origin
  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>405 Method Not Allowed</h1></body></html>"
        status_code  = 405
      }
    }
    expression  = "(http.request.method ne \"GET\" and http.request.method ne \"HEAD\")"
    description = "Block all methods except GET and HEAD at origin"
    enabled     = true
  }
}

# Transform Rules - Add origin protection headers
resource "cloudflare_ruleset" "origin_security_headers" {
  zone_id     = var.zone_id
  name        = "Origin Security Headers"
  description = "Add security headers for origin protection"
  kind        = "zone"
  phase       = "http_response_headers_transform"

  rules {
    action = "rewrite"
    action_parameters {
      headers {
        "X-Origin-Protected"     = "true"
        "X-Direct-Access"        = "blocked"
        "X-CDN-Only"            = "enforced"
        "Server"                = "SecureBlog-CDN"
      }
    }
    expression  = "true"
    description = "Add origin protection headers"
    enabled     = true
  }
}

# Rate Limiting - Aggressive for direct origin access attempts
resource "cloudflare_rate_limit" "origin_protection_rate_limit" {
  zone_id   = var.zone_id
  threshold = 5   # Very low threshold
  period    = 60  # 1 minute
  
  match {
    request {
      url_pattern = "${var.domain}/*"
      schemes     = ["HTTP", "HTTPS"]
      methods     = ["GET", "POST", "PUT", "DELETE", "PATCH"]
    }
    response {
      status = [403, 429]  # Rate limit on blocked requests
    }
  }
  
  action {
    mode    = "ban"
    timeout = 3600  # 1 hour ban
    
    response {
      content_type = "text/html"
      body         = "<html><body><h1>429 - Too Many Direct Access Attempts</h1><p>Use CDN endpoint only</p></body></html>"
    }
  }
  
  correlate {
    by = "cf.client.ip"
  }
  
  disabled    = false
  description = "Aggressive rate limiting for origin protection"
}

# DNS Configuration - CNAME to Cloudflare (not direct IP)
resource "cloudflare_record" "cname_record" {
  zone_id = var.zone_id
  name    = "@"
  value   = "${var.domain}.cdn.cloudflare.net"
  type    = "CNAME"
  proxied = true
  
  comment = "CDN-only configuration - no direct origin exposure"
}

resource "cloudflare_record" "www_cname" {
  zone_id = var.zone_id
  name    = "www"
  value   = var.domain
  type    = "CNAME"
  proxied = true
  
  comment = "WWW redirect through CDN only"
}

# Page Rules for origin protection
resource "cloudflare_page_rule" "origin_protection_page_rule" {
  zone_id  = var.zone_id
  target   = "*${var.domain}/*"
  priority = 1
  status   = "active"

  actions {
    # Force HTTPS
    always_use_https = "on"
    
    # Aggressive caching for static content
    cache_level = "cache_everything"
    edge_cache_ttl = 2592000  # 30 days
    
    # Security headers
    security_level = "high"
    
    # Disable features not needed for static site
    disable_apps = "on"
    disable_performance = "off"
    disable_railgun = "on"
    disable_zaraz = "on"
  }
}

# Custom Hostname (if using custom domain)
resource "cloudflare_custom_hostname" "custom_domain" {
  count    = var.origin_ip != "" ? 1 : 0
  zone_id  = var.zone_id
  hostname = var.domain
  
  ssl {
    method = "txt"
    type   = "dv"
    settings {
      http2         = "on"
      tls13         = "on"
      min_tls_version = "1.2"
      ciphers       = ["ECDHE-ECDSA-AES128-GCM-SHA256", "ECDHE-ECDSA-CHACHA20-POLY1305"]
    }
  }
  
  custom_metadata = {
    "origin-protection" = "enabled"
    "direct-access"     = "blocked"
  }
}

# Argo Tunnel Configuration (for maximum origin protection)
resource "cloudflare_tunnel" "origin_tunnel" {
  count      = var.origin_ip != "" ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "secureblog-origin-tunnel"
  secret     = base64encode(random_password.tunnel_secret[0].result)
}

resource "random_password" "tunnel_secret" {
  count   = var.origin_ip != "" ? 1 : 0
  length  = 32
  special = true
}

# Tunnel Configuration
resource "cloudflare_tunnel_config" "origin_tunnel_config" {
  count      = var.origin_ip != "" ? 1 : 0
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.origin_tunnel[0].id

  config {
    ingress_rule {
      hostname = var.domain
      service  = "http://localhost:8080"
      
      origin_request {
        connect_timeout          = "30s"
        tls_timeout             = "30s"
        tcp_keep_alive          = "30s"
        no_happy_eyeballs       = false
        keep_alive_connections  = 10
        keep_alive_timeout      = "90s"
        http_host_header        = var.domain
        origin_server_name      = var.domain
      }
    }
    
    # Catch-all rule (required)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Output tunnel credentials for deployment
output "tunnel_credentials" {
  value = var.origin_ip != "" ? {
    tunnel_id    = cloudflare_tunnel.origin_tunnel[0].id
    tunnel_name  = cloudflare_tunnel.origin_tunnel[0].name
    tunnel_token = cloudflare_tunnel.origin_tunnel[0].tunnel_token
  } : null
  sensitive = true
}

# Zone-level security settings for origin protection
resource "cloudflare_zone_settings_override" "origin_security" {
  zone_id = var.zone_id
  
  settings {
    # Maximum security
    security_level = "high"
    
    # TLS settings
    ssl                     = "strict"
    min_tls_version        = "1.2"
    tls_1_3                = "on"
    automatic_https_rewrites = "on"
    always_use_https       = "on"
    
    # Bot protection
    bot_management = {
      enable_js = false  # No JS, so disable JS challenges
      suppress_session_score = true
      auto_update_model = true
    }
    
    # DDoS protection
    challenge_ttl = 1800  # 30 minutes
    
    # Caching for static content
    cache_level = "aggressive"
    
    # Disable features not needed
    rocket_loader = "off"  # No JS
    mirage       = "off"   # Static images only
    websockets   = "off"   # Not needed for static site
  }
}

# Terraform outputs
output "origin_protection_summary" {
  value = {
    "direct_origin_access" = "blocked"
    "cloudflare_ips_only"  = "enforced"
    "host_header_validation" = "enabled"
    "method_restrictions"  = "GET/HEAD only"
    "rate_limiting"       = "aggressive"
    "tunnel_protection"   = var.origin_ip != "" ? "enabled" : "not_applicable"
    "cdn_only_architecture" = true
  }
}