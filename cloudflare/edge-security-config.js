/**
 * Cloudflare Edge Security Configuration
 * Enforces strict security policies at the edge
 */

// Edge Worker with comprehensive security controls
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // 1. Method enforcement - GET/HEAD only
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', {
        status: 405,
        headers: {
          'Allow': 'GET, HEAD',
          'Content-Type': 'text/plain'
        }
      });
    }
    
    // 2. Request size limit (1KB)
    const contentLength = request.headers.get('content-length');
    if (contentLength && parseInt(contentLength) > 1024) {
      return new Response('Request Too Large', { status: 413 });
    }
    
    // 3. Path validation - no directory traversal
    if (url.pathname.includes('..') || url.pathname.includes('//')) {
      return new Response('Bad Request', { status: 400 });
    }
    
    // 4. Query string validation
    const queryString = url.search;
    if (queryString.length > 100) {
      return new Response('Query String Too Long', { status: 414 });
    }
    
    // Dangerous patterns in query
    const dangerousPatterns = [
      /<script/i,
      /javascript:/i,
      /%00/,
      /%2e%2e/i,
      /\x00/,
      /<iframe/i,
      /on\w+=/i
    ];
    
    for (const pattern of dangerousPatterns) {
      if (pattern.test(queryString)) {
        return new Response('Malicious Query Detected', { status: 400 });
      }
    }
    
    // 5. Block dangerous file extensions
    const blockedExtensions = [
      '.php', '.asp', '.aspx', '.jsp', '.cgi', '.pl',
      '.py', '.rb', '.sh', '.exe', '.dll', '.bat',
      '.cmd', '.com', '.pif', '.scr', '.vbs', '.ws'
    ];
    
    const lowerPath = url.pathname.toLowerCase();
    for (const ext of blockedExtensions) {
      if (lowerPath.endsWith(ext)) {
        return new Response('Forbidden File Type', { status: 403 });
      }
    }
    
    // 6. Rate limiting by IP
    const clientIP = request.headers.get('CF-Connecting-IP');
    const rateLimitKey = `rl:${clientIP}:${Math.floor(Date.now() / 60000)}`;
    
    const rateLimit = await env.RATE_LIMITER.get(rateLimitKey);
    const requestCount = rateLimit ? parseInt(rateLimit) : 0;
    
    if (requestCount > 60) { // 60 requests per minute
      return new Response('Rate Limit Exceeded', {
        status: 429,
        headers: {
          'Retry-After': '60',
          'X-RateLimit-Limit': '60',
          'X-RateLimit-Remaining': '0'
        }
      });
    }
    
    await env.RATE_LIMITER.put(rateLimitKey, (requestCount + 1).toString(), {
      expirationTtl: 60
    });
    
    // 7. Fetch the origin response
    const response = await fetch(request);
    
    // 8. Clone and enhance response with security headers
    const newResponse = new Response(response.body, response);
    
    // Comprehensive security headers
    newResponse.headers.set('Content-Security-Policy', 
      "default-src 'none'; " +
      "img-src 'self' data:; " +
      "style-src 'self' 'unsafe-inline'; " +
      "font-src 'self'; " +
      "base-uri 'none'; " +
      "form-action 'none'; " +
      "frame-ancestors 'none'; " +
      "block-all-mixed-content; " +
      "upgrade-insecure-requests"
    );
    
    newResponse.headers.set('X-Frame-Options', 'DENY');
    newResponse.headers.set('X-Content-Type-Options', 'nosniff');
    newResponse.headers.set('X-XSS-Protection', '1; mode=block');
    newResponse.headers.set('Referrer-Policy', 'no-referrer');
    newResponse.headers.set('Permissions-Policy', 
      'accelerometer=(), battery=(), camera=(), display-capture=(), ' +
      'geolocation=(), gyroscope=(), magnetometer=(), microphone=(), ' +
      'midi=(), payment=(), usb=(), interest-cohort=()'
    );
    newResponse.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    newResponse.headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
    newResponse.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
    
    // HSTS with preload
    newResponse.headers.set('Strict-Transport-Security', 
      'max-age=63072000; includeSubDomains; preload'
    );
    
    // Cache control for static assets
    if (url.pathname.match(/\.(css|js|jpg|jpeg|png|gif|svg|woff|woff2|ttf|eot)$/)) {
      newResponse.headers.set('Cache-Control', 'public, max-age=31536000, immutable');
    } else if (url.pathname.endsWith('.html') || url.pathname === '/') {
      newResponse.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      newResponse.headers.set('Pragma', 'no-cache');
      newResponse.headers.set('Expires', '0');
    }
    
    return newResponse;
  }
};

// WAF Rules Configuration (Terraform)
export const wafRules = `
resource "cloudflare_ruleset" "waf_custom" {
  zone_id = var.zone_id
  name    = "SecureBlog WAF Rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"
  
  # Rule 1: Block SQL injection attempts
  rules {
    action = "block"
    expression = "(http.request.uri.query contains \"union\" and http.request.uri.query contains \"select\") or http.request.uri.query contains \"' or '1'='1\""
    description = "Block SQL injection"
  }
  
  # Rule 2: Block XSS attempts
  rules {
    action = "block"
    expression = "http.request.uri.query contains \"<script\" or http.request.uri.query contains \"javascript:\" or http.request.uri.query contains \"onerror=\""
    description = "Block XSS attempts"
  }
  
  # Rule 3: Block path traversal
  rules {
    action = "block"
    expression = "http.request.uri.path contains \"..\" or http.request.uri.path contains \"//\" or http.request.uri.path contains \"%2e%2e\""
    description = "Block path traversal"
  }
  
  # Rule 4: Block command injection
  rules {
    action = "block"
    expression = "http.request.uri contains \"|\" or http.request.uri contains \"&\" or http.request.uri contains \";\" or http.request.uri contains \"$\""
    description = "Block command injection"
  }
  
  # Rule 5: Rate limit by ASN
  rules {
    action = "challenge"
    expression = "(ip.geoip.asnum eq 13335) and (rate(60) > 100)"
    description = "Rate limit high-traffic ASNs"
  }
  
  # Rule 6: Block suspicious user agents
  rules {
    action = "block"
    expression = "http.user_agent contains \"scanner\" or http.user_agent contains \"nikto\" or http.user_agent contains \"sqlmap\""
    description = "Block scanning tools"
  }
  
  # Rule 7: Enforce request limits
  rules {
    action = "block"
    expression = "http.request.uri.query.length > 500 or http.request.body.size > 1024"
    description = "Enforce size limits"
  }
  
  # Rule 8: Block null bytes
  rules {
    action = "block"
    expression = "http.request.uri contains \"%00\" or http.request.uri contains \"\\x00\""
    description = "Block null byte injection"
  }
}

# Managed WAF rules
resource "cloudflare_ruleset" "waf_managed" {
  zone_id = var.zone_id
  name    = "Managed WAF"
  kind    = "zone"
  phase   = "http_request_firewall_managed"
  
  rules {
    action = "execute"
    action_parameters {
      id = "efb7b8c949ac4650a09736fc376e9aee" # Cloudflare OWASP Core Ruleset
      overrides {
        action = "block"
        enabled = true
      }
    }
    description = "Execute OWASP Core Ruleset"
  }
}

# Rate limiting rules
resource "cloudflare_rate_limit" "global" {
  zone_id = var.zone_id
  
  threshold = 100
  period    = 60
  
  action {
    mode    = "challenge"
    timeout = 3600
  }
  
  description = "Global rate limit"
}

# DDoS protection
resource "cloudflare_zone_settings_override" "ddos" {
  zone_id = var.zone_id
  
  settings {
    security_level = "high"
    challenge_ttl  = 3600
    
    # Enable DDoS protection
    ddos_protection = "on"
    
    # Bot fight mode
    bot_management {
      enable_js = true
      fight_mode = true
    }
  }
}
`;

// Page Rules for additional security
export const pageRules = `
# Always HTTPS
resource "cloudflare_page_rule" "always_https" {
  zone_id = var.zone_id
  target  = "*\${var.domain}/*"
  priority = 1
  
  actions {
    always_use_https = true
  }
}

# Security headers for all responses
resource "cloudflare_page_rule" "security_headers" {
  zone_id = var.zone_id
  target  = "*\${var.domain}/*"
  priority = 2
  
  actions {
    security_header {
      enabled            = true
      include_subdomains = true
      max_age           = 63072000
      nosniff           = true
      preload           = true
    }
  }
}

# Cache everything except HTML
resource "cloudflare_page_rule" "cache_static" {
  zone_id = var.zone_id
  target  = "*\${var.domain}/*.(css|js|jpg|jpeg|png|gif|svg|woff|woff2)"
  priority = 3
  
  actions {
    cache_level = "cache_everything"
    edge_cache_ttl = 31536000
    browser_cache_ttl = 31536000
  }
}

# No cache for HTML
resource "cloudflare_page_rule" "no_cache_html" {
  zone_id = var.zone_id
  target  = "*\${var.domain}/*.html"
  priority = 4
  
  actions {
    cache_level = "bypass"
  }
}
`;