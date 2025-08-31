// edge-runtime-gates.js - Cloudflare Worker with strict security gates
// Deploy this to Cloudflare Workers to add edge-level security

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const method = request.method;
    const userAgent = request.headers.get('user-agent') || '';
    const cf = request.cf || {};
    
    // Security gates configuration
    const SECURITY_CONFIG = {
      // Method restrictions
      allowedMethods: ['GET', 'HEAD', 'OPTIONS'],
      
      // Request size limits (1KB as specified)
      maxBodySize: 1024, // 1KB
      maxQueryStringLength: 256,
      maxUrlLength: 2048,
      
      // Rate limiting (per minute)
      rateLimit: {
        requests: 60,    // 60 requests per minute per IP
        burstLimit: 10,  // 10 requests in 10 seconds
      },
      
      // Geographic restrictions (if needed)
      blockedCountries: [], // Add country codes to block
      
      // ASN blocking (if needed)  
      blockedASNs: [], // Add ASN numbers to block malicious networks
      
      // Bot protection
      requireJsChallenge: false, // Set to true to challenge suspicious bots
      
      // Content Security Policy
      csp: "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'none'; script-src 'none'; object-src 'none'; frame-src 'none'; worker-src 'none'; frame-ancestors 'none'; form-action 'none'; upgrade-insecure-requests",
      
      // Security headers
      securityHeaders: {
        'X-Frame-Options': 'DENY',
        'X-Content-Type-Options': 'nosniff', 
        'X-XSS-Protection': '1; mode=block',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
        'Permissions-Policy': 'geolocation=(), microphone=(), camera=(), payment=(), usb=(), bluetooth=(), accelerometer=(), gyroscope=(), magnetometer=()',
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Resource-Policy': 'same-origin'
      }
    };
    
    try {
      // Gate 1: Method validation
      if (!SECURITY_CONFIG.allowedMethods.includes(method)) {
        console.log(`Blocked method: ${method} from ${cf.colo}`);
        return new Response('Method Not Allowed', {
          status: 405,
          headers: {
            'Allow': SECURITY_CONFIG.allowedMethods.join(', '),
            ...SECURITY_CONFIG.securityHeaders
          }
        });
      }
      
      // Gate 2: URL length validation
      if (request.url.length > SECURITY_CONFIG.maxUrlLength) {
        console.log(`Blocked oversized URL: ${request.url.length} bytes`);
        return new Response('Request-URI Too Long', {
          status: 414,
          headers: SECURITY_CONFIG.securityHeaders
        });
      }
      
      // Gate 3: Query string length validation
      if (url.search.length > SECURITY_CONFIG.maxQueryStringLength) {
        console.log(`Blocked oversized query string: ${url.search.length} bytes`);
        return new Response('Query String Too Long', {
          status: 413,
          headers: SECURITY_CONFIG.securityHeaders
        });
      }
      
      // Gate 4: Request body size validation (for non-GET requests)
      if (['POST', 'PUT', 'PATCH'].includes(method)) {
        const contentLength = parseInt(request.headers.get('content-length') || '0');
        if (contentLength > SECURITY_CONFIG.maxBodySize) {
          console.log(`Blocked oversized body: ${contentLength} bytes`);
          return new Response('Payload Too Large', {
            status: 413,
            headers: SECURITY_CONFIG.securityHeaders
          });
        }
      }
      
      // Gate 5: Geographic blocking
      if (SECURITY_CONFIG.blockedCountries.includes(cf.country)) {
        console.log(`Blocked country: ${cf.country}`);
        return new Response('Access Denied', {
          status: 403,
          headers: SECURITY_CONFIG.securityHeaders
        });
      }
      
      // Gate 6: ASN blocking
      if (SECURITY_CONFIG.blockedASNs.includes(cf.asn)) {
        console.log(`Blocked ASN: ${cf.asn}`);
        return new Response('Access Denied', {
          status: 403,
          headers: SECURITY_CONFIG.securityHeaders
        });
      }
      
      // Gate 7: Rate limiting (simple implementation)
      const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
      const rateLimitKey = `rate_limit:${clientIP}`;
      const burstKey = `burst:${clientIP}`;
      
      // Note: In production, you'd use Cloudflare's KV or Durable Objects for persistence
      // This is a simplified version for demonstration
      
      // Gate 8: Bot challenge (if configured)
      if (SECURITY_CONFIG.requireJsChallenge) {
        const botScore = cf.botManagement?.score || 0;
        if (botScore > 30) { // Cloudflare bot scores: 1-99 (higher = more likely bot)
          console.log(`Potential bot detected: score ${botScore}`);
          // You could return a challenge page here
        }
      }
      
      // Gate 9: Suspicious pattern detection
      const suspiciousPatterns = [
        /\.\.\//, // Path traversal
        /[<>'"]/, // Potential XSS chars in URL
        /javascript:/i, // JavaScript URLs
        /data:text\/html/i, // Data URLs with HTML
        /vbscript:/i, // VBScript URLs
      ];
      
      for (const pattern of suspiciousPatterns) {
        if (pattern.test(url.pathname + url.search)) {
          console.log(`Blocked suspicious pattern in URL: ${url.pathname + url.search}`);
          return new Response('Bad Request', {
            status: 400,
            headers: SECURITY_CONFIG.securityHeaders
          });
        }
      }
      
      // Gate 10: Static file enforcement
      // Only allow requests to known static file types or index pages
      const allowedExtensions = ['.html', '.css', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.eot', '.webp'];
      const allowedPaths = ['/', '/index.html', '/robots.txt', '/sitemap.xml', '/security.txt', '/.well-known/security.txt'];
      
      const isStaticFile = allowedExtensions.some(ext => url.pathname.endsWith(ext));
      const isAllowedPath = allowedPaths.includes(url.pathname);
      
      if (!isStaticFile && !isAllowedPath) {
        console.log(`Blocked non-static path: ${url.pathname}`);
        return new Response('Not Found', {
          status: 404,
          headers: SECURITY_CONFIG.securityHeaders
        });
      }
      
      // All gates passed - proceed to origin
      console.log(`Request approved: ${method} ${url.pathname} from ${cf.country}/${cf.colo}`);
      
      // Fetch from origin (or serve from cache)
      const response = await fetch(request);
      
      // Clone response to modify headers
      const modifiedResponse = new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers
      });
      
      // Apply security headers to all responses
      Object.entries(SECURITY_CONFIG.securityHeaders).forEach(([key, value]) => {
        modifiedResponse.headers.set(key, value);
      });
      
      // Set Content-Security-Policy
      modifiedResponse.headers.set('Content-Security-Policy', SECURITY_CONFIG.csp);
      
      // Add HSTS for HTTPS responses
      if (url.protocol === 'https:') {
        modifiedResponse.headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
      }
      
      // Cache control for static assets
      if (isStaticFile && !url.pathname.endsWith('.html')) {
        // Long cache for versioned static assets
        if (url.pathname.match(/-[a-f0-9]{10}\./)) {
          modifiedResponse.headers.set('Cache-Control', 'public, max-age=31536000, immutable');
          modifiedResponse.headers.set('X-Cache-Status', 'IMMUTABLE');
        } else {
          // Standard cache for other static files
          modifiedResponse.headers.set('Cache-Control', 'public, max-age=3600');
          modifiedResponse.headers.set('X-Cache-Status', 'STATIC');
        }
      } else {
        // No cache for HTML files
        modifiedResponse.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
        modifiedResponse.headers.set('Pragma', 'no-cache');
        modifiedResponse.headers.set('X-Cache-Status', 'NO-CACHE');
      }
      
      // Add security telemetry headers
      modifiedResponse.headers.set('X-Security-Gates', 'PASSED');
      modifiedResponse.headers.set('X-CF-Country', cf.country || 'unknown');
      modifiedResponse.headers.set('X-CF-Colo', cf.colo || 'unknown');
      
      return modifiedResponse;
      
    } catch (error) {
      console.error('Edge security error:', error);
      
      // Return secure error response
      return new Response('Internal Server Error', {
        status: 500,
        headers: SECURITY_CONFIG.securityHeaders
      });
    }
  }
};

// Rate limiting helper (would use KV/DO in production)
class RateLimiter {
  constructor(maxRequests, windowMs) {
    this.maxRequests = maxRequests;
    this.windowMs = windowMs;
    this.requests = new Map();
  }
  
  isAllowed(key) {
    const now = Date.now();
    const windowStart = now - this.windowMs;
    
    if (!this.requests.has(key)) {
      this.requests.set(key, []);
    }
    
    const userRequests = this.requests.get(key);
    
    // Remove old requests
    while (userRequests.length > 0 && userRequests[0] < windowStart) {
      userRequests.shift();
    }
    
    // Check if under limit
    if (userRequests.length < this.maxRequests) {
      userRequests.push(now);
      return true;
    }
    
    return false;
  }
}