# Comprehensive Cloudflare WAF Rules and Zone Hardening
# Maximum security configuration for static blog

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# Variables
variable "zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "secureblog.example.com"
}

# Rate Limiting Rules
resource "cloudflare_rate_limit" "global_rate_limit" {
  zone_id   = var.zone_id
  threshold = 100
  period    = 60
  match {
    request {
      url_pattern = "${var.domain}/*"
      schemes     = ["HTTP", "HTTPS"]
      methods     = ["GET", "HEAD"]
    }
  }
  action {
    mode    = "ban"
    timeout = 300
    response {
      content_type = "text/html"
      body         = "<html><body><h1>429 - Rate Limited</h1><p>Too many requests. Try again later.</p></body></html>"
    }
  }
  correlate {
    by = "cf.client.ip"
  }
  disabled                = false
  description            = "Global rate limit - 100 req/min per IP"
  bypass_url_patterns    = ["${var.domain}/.well-known/*"]
}

# WAF Custom Rules
resource "cloudflare_ruleset" "waf_custom_rules" {
  zone_id     = var.zone_id
  name        = "SecureBlog WAF Custom Rules"
  description = "Maximum security WAF rules for static blog"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>Method not allowed</p></body></html>"
        status_code  = 403
      }
    }
    expression  = "(http.request.method ne \"GET\" and http.request.method ne \"HEAD\")"
    description = "Block all methods except GET and HEAD"
    enabled     = true
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>404 Not Found</h1></body></html>"
        status_code  = 404
      }
    }
    expression  = "(http.request.uri.path matches \".*\\.(php|asp|aspx|jsp|cgi|pl|py|rb|sh|exe|dll|bat|cmd|ps1)$\")"
    description = "Block executable file extensions"
    enabled     = true
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>404 Not Found</h1></body></html>"
        status_code  = 404
      }
    }
    expression  = "(http.request.uri.path matches \".*\\.(js|mjs|jsx|ts|tsx)$\")"
    description = "Block JavaScript files (should not exist)"
    enabled     = true
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>404 Not Found</h1></body></html>"
        status_code  = 404
      }
    }
    expression  = "(http.request.uri.path matches \"^/\\..*\" and not http.request.uri.path matches \"^/\\.well-known/.*\")"
    description = "Block hidden files except .well-known"
    enabled     = true
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>Admin access blocked</p></body></html>"
        status_code  = 403
      }
    }
    expression  = "(http.request.uri.path matches \"^/(admin|wp-admin|administrator|phpmyadmin|cpanel|webmail|roundcube)/.*\")"
    description = "Block common admin paths"
    enabled     = true
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>SQL injection attempt blocked</p></body></html>"
        status_code  = 403
      }
    }
    expression  = "(http.request.uri.query matches \".*(['\\\"]|(\\\\x27)|(\\\\x2F)|(union|select|insert|delete|update|drop|create|alter|exec|script)\\\\s).*\")"
    description = "Block SQL injection attempts"
    enabled     = true
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>XSS attempt blocked</p></body></html>"
        status_code  = 403
      }
    }
    expression  = "(http.request.uri.query matches \".*(script|javascript|vbscript|onload|onerror|onclick).*\")"
    description = "Block XSS attempts in query strings"
    enabled     = true
  }

  rules {
    action = "challenge"
    expression  = "(ip.geoip.country ne \"US\" and ip.geoip.country ne \"CA\" and ip.geoip.country ne \"GB\")"
    description = "Challenge requests from outside allowed countries"
    enabled     = false  # Disable by default, enable if needed
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>Bot blocked</p></body></html>"
        status_code  = 403
      }
    }
    expression  = "(cf.client.bot and not cf.verified_bot_category in {\"Search Engine Crawler\" \"Social Media Agent\" \"Monitoring & Analytics\"})"
    description = "Block malicious bots, allow legitimate ones"
    enabled     = true
  }

  rules {
    action = "block"
    action_parameters {
      response {
        content_type = "text/html"
        content      = "<html><body><h1>403 Forbidden</h1><p>Request too large</p></body></html>"
        status_code  = 413
      }
    }
    expression  = "(http.request.body.size gt 1024)"
    description = "Block requests with body larger than 1KB"
    enabled     = true
  }
}

# Zone-level security settings
resource "cloudflare_zone_settings_override" "security_settings" {
  zone_id = var.zone_id
  settings {
    always_online            = "on"
    always_use_https        = "on"
    automatic_https_rewrites = "on"
    brotli                  = "on"
    browser_cache_ttl       = 14400  # 4 hours
    browser_check           = "on"
    cache_level             = "aggressive"
    challenge_ttl           = 1800   # 30 minutes
    development_mode        = "off"
    early_hints             = "on"
    email_obfuscation       = "on"
    hotlink_protection      = "on"
    http3                   = "on"
    ip_geolocation          = "on"
    ipv6                    = "on"
    min_tls_version         = "1.2"
    mirage                  = "on"
    opportunistic_encryption = "on"
    opportunistic_onion     = "on"
    polish                  = "lossless"
    prefetch_preload        = "on"
    privacy_pass            = "on"
    proxy_read_timeout      = "100"
    pseudo_ipv4             = "off"
    rocket_loader           = "off"  # Disabled - we have no JS
    security_level          = "high"
    server_side_exclude     = "on"
    sort_query_string_for_cache = "on"
    ssl                     = "strict"
    tls_1_3                 = "on"
    true_client_ip_header   = "off"
    universal_ssl           = "on"
    visitor_ip              = "on"
    waf                     = "on"
    webp                    = "on"
    websockets              = "off"  # Not needed for static site
    zero_rtt                = "on"
  }
}

# Security headers via Page Rules
resource "cloudflare_page_rule" "security_headers" {
  zone_id  = var.zone_id
  target   = "${var.domain}/*"
  priority = 1
  status   = "active"

  actions {
    always_online = "on"
    cache_level   = "cache_everything"
    edge_cache_ttl = 2592000  # 30 days
    
    forwarding_url {
      status_code = 301
      url         = "https://${var.domain}/$1"
    }
  }
}

# DDoS Protection (L7)
resource "cloudflare_zone_lockdown" "admin_lockdown" {
  zone_id     = var.zone_id
  description = "Block admin paths completely"
  urls        = [
    "${var.domain}/admin*",
    "${var.domain}/wp-admin*", 
    "${var.domain}/administrator*"
  ]
  configurations {
    target = "ip"
    value  = "0.0.0.0/0"  # Block all IPs
  }
  paused = false
}

# Access Rules - Block known bad IPs/ASNs
resource "cloudflare_access_rule" "block_tor" {
  zone_id     = var.zone_id
  mode        = "block"
  configuration {
    target = "country"
    value  = "T1"  # Tor exit nodes
  }
  notes = "Block Tor exit nodes"
}

# Bot Management
resource "cloudflare_bot_management" "bot_settings" {
  zone_id                      = var.zone_id
  enable_js                    = false  # No JS, so disable
  suppress_session_score      = true
  auto_update_model           = true
  using_latest_model          = true
}

# Transform Rules for additional security headers
resource "cloudflare_ruleset" "transform_response_headers" {
  zone_id     = var.zone_id
  name        = "Add Security Headers"
  description = "Add comprehensive security headers"
  kind        = "zone"
  phase       = "http_response_headers_transform"

  rules {
    action = "rewrite"
    action_parameters {
      headers {
        "Content-Security-Policy" = "default-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; block-all-mixed-content; upgrade-insecure-requests"
        "X-Frame-Options" = "DENY"
        "X-Content-Type-Options" = "nosniff"
        "X-XSS-Protection" = "1; mode=block"
        "Referrer-Policy" = "no-referrer"
        "Permissions-Policy" = "accelerometer=(), battery=(), camera=(), display-capture=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()"
        "Cross-Origin-Opener-Policy" = "same-origin"
        "Cross-Origin-Embedder-Policy" = "require-corp"
        "Cross-Origin-Resource-Policy" = "same-origin"
        "Strict-Transport-Security" = "max-age=63072000; includeSubDomains; preload"
        "X-Security-Level" = "maximum"
        "X-Static-Only" = "true"
      }
    }
    expression  = "true"
    description = "Add security headers to all responses"
    enabled     = true
  }
}

# Output important values
output "zone_id" {
  value = var.zone_id
}

output "security_level" {
  value = "maximum"
}

output "waf_rules_count" {
  value = length(cloudflare_ruleset.waf_custom_rules.rules)
}