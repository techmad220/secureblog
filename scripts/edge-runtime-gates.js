// edge-runtime-gates.js - Fort Knox Cloudflare Worker with strict security gates
export default {
  async fetch(req, env, ctx) {
    // Only GET/HEAD methods allowed
    const method = req.method.toUpperCase();
    if (method !== "GET" && method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { "Allow": "GET, HEAD" }
      });
    }

    // Block dangerous query patterns immediately
    const url = new URL(req.url);
    const queryString = url.search.toLowerCase();
    const dangerousPatterns = [
      '__proto__',
      '<script',
      'javascript:',
      'vbscript:',
      'data:text/html',
      'onload=',
      'onerror=',
      'onclick=',
      'eval(',
      'alert(',
      'document.cookie',
      'document.location'
    ];
    
    for (const pattern of dangerousPatterns) {
      if (queryString.includes(pattern) || url.pathname.toLowerCase().includes(pattern)) {
        console.log(`Blocked dangerous pattern: ${pattern} in ${url.pathname}${url.search}`);
        return new Response("Blocked by security policy", { 
          status: 451,
          headers: { "Content-Type": "text/plain" }
        });
      }
    }

    // 1KB query string limit
    if (url.search.length > 1024) {
      return new Response("Query string too large", { status: 413 });
    }

    let response;
    
    try {
      // Fetch from bound asset (Pages/ASSETS) or origin
      response = env.ASSETS ? await env.ASSETS.fetch(req) : await fetch(req);
    } catch (error) {
      console.error('Fetch error:', error);
      return new Response("Service Unavailable", { status: 503 });
    }

    // Clone to inspect & modify headers
    const newHeaders = new Headers(response.headers);

    // Fort Knox security headers (enforced at edge)
    newHeaders.set("Content-Security-Policy",
      "default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'; script-src 'none'; connect-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; object-src 'none'; media-src 'self'; worker-src 'none'; manifest-src 'self'; frame-src 'none'; upgrade-insecure-requests");
    
    newHeaders.set("X-Content-Type-Options", "nosniff");
    newHeaders.set("X-Frame-Options", "DENY");
    newHeaders.set("Referrer-Policy", "no-referrer");
    newHeaders.set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload");
    
    // Comprehensive Permissions Policy
    newHeaders.set("Permissions-Policy", "accelerometer=(), ambient-light-sensor=(), autoplay=(), battery=(), camera=(), cross-origin-isolated=(), display-capture=(), document-domain=(), encrypted-media=(), execution-while-not-rendered=(), execution-while-out-of-viewport=(), fullscreen=(), geolocation=(), gyroscope=(), keyboard-map=(), magnetometer=(), microphone=(), midi=(), payment=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), sync-xhr=(), usb=(), web-share=(), xr-spatial-tracking=()");
    
    // Cross-origin policies
    newHeaders.set("Cross-Origin-Embedder-Policy", "require-corp");
    newHeaders.set("Cross-Origin-Opener-Policy", "same-origin");
    newHeaders.set("Cross-Origin-Resource-Policy", "same-origin");

    // Cache policy: immutable for hashed assets, no-store for HTML
    const contentType = response.headers.get("Content-Type") || "";
    const pathname = url.pathname;
    
    if (contentType.includes("text/html")) {
      newHeaders.set("Cache-Control", "no-store, no-cache, must-revalidate");
      newHeaders.set("Pragma", "no-cache");
      newHeaders.set("Expires", "0");
    } else if (/\-[0-9a-f]{8,}\.(css|png|jpg|jpeg|webp|svg|woff2?|ttf|eot|ico|gif)$/i.test(pathname)) {
      // Content-hashed immutable assets
      newHeaders.set("Cache-Control", "public, max-age=31536000, immutable");
      newHeaders.set("X-Cache-Status", "IMMUTABLE");
    } else if (/\.(css|png|jpg|jpeg|webp|svg|woff2?|ttf|eot|ico|gif)$/i.test(pathname)) {
      // Regular static assets
      newHeaders.set("Cache-Control", "public, max-age=3600");
      newHeaders.set("X-Cache-Status", "STATIC");
    }

    // Zero-JS body guard for HTML (belt and suspenders)
    if (contentType.includes("text/html")) {
      try {
        const body = await response.text();
        const lowered = body.toLowerCase();
        
        // Detect any JavaScript that might have slipped through
        const jsPatterns = [
          '<script',
          'javascript:',
          'vbscript:',
          'onload=',
          'onclick=',
          'onerror=',
          'onmouseover=',
          'onfocus=',
          'onblur=',
          'onsubmit=',
          'document.location',
          'document.cookie',
          'window.location',
          'eval(',
          'settimeout(',
          'setinterval(',
          'innerhtml='
        ];
        
        for (const pattern of jsPatterns) {
          if (lowered.includes(pattern)) {
            console.log(`SECURITY VIOLATION: JavaScript detected in HTML: ${pattern}`);
            return new Response("Blocked by zero-JS policy - JavaScript detected", { 
              status: 451, 
              headers: newHeaders 
            });
          }
        }
        
        // Check for suspicious CSS patterns
        const cssPatterns = [
          'expression(',
          '-moz-binding',
          'behavior:',
          'javascript:',
          '@import',
          'url(javascript:',
          'url(data:text/html'
        ];
        
        for (const pattern of cssPatterns) {
          if (lowered.includes(pattern)) {
            console.log(`SECURITY VIOLATION: Dangerous CSS detected: ${pattern}`);
            return new Response("Blocked by security policy - Dangerous CSS detected", { 
              status: 451, 
              headers: newHeaders 
            });
          }
        }
        
        return new Response(body, { status: response.status, headers: newHeaders });
      } catch (error) {
        console.error('Body inspection error:', error);
        return new Response("Content inspection failed", { status: 500, headers: newHeaders });
      }
    }

    // For non-HTML responses, return with security headers
    return new Response(response.body, { status: response.status, headers: newHeaders });
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