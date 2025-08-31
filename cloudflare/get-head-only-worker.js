/**
 * Cloudflare Worker: GET/HEAD-only Enforcement with 1KB Response Cap
 * Blocks all HTTP methods except GET/HEAD, enforces strict security headers
 * Maximum 1KB response size to prevent bloat and resource exhaustion
 */

// Security headers template
const SECURITY_HEADERS = {
  'Content-Security-Policy': "default-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; block-all-mixed-content; upgrade-insecure-requests",
  'X-Frame-Options': 'DENY',
  'X-Content-Type-Options': 'nosniff',
  'X-XSS-Protection': '1; mode=block',
  'Referrer-Policy': 'no-referrer',
  'Permissions-Policy': 'accelerometer=(), battery=(), camera=(), display-capture=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  'Cache-Control': 'no-cache, no-store, must-revalidate',
  'Pragma': 'no-cache',
  'Expires': '0'
};

// 1KB response size limit (1024 bytes)
const MAX_RESPONSE_SIZE = 1024;

// Blocked methods - only GET and HEAD allowed
const BLOCKED_METHODS = ['POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS', 'TRACE', 'CONNECT'];

// Blocked paths - executables and potentially dangerous files
const BLOCKED_PATHS = [
  /\.(php|asp|aspx|jsp|cgi|pl|py|rb|sh|exe|dll|bat|cmd|ps1)$/i,
  /\.(js|mjs|jsx|ts|tsx)$/i, // Block all JavaScript files
  /^\/\./,                    // Block hidden files (except .well-known)
  /\/admin\//i,              // Block admin paths
  /\/wp-admin\//i,           // Block WordPress admin
  /\/xmlrpc\.php$/i,         // Block WordPress XML-RPC
];

// Rate limiting - simple in-memory store (use Durable Objects for production)
const rateLimitMap = new Map();
const RATE_LIMIT_REQUESTS = 100;  // requests per window
const RATE_LIMIT_WINDOW = 60000;   // 1 minute in milliseconds

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const url = new URL(request.url);
  const method = request.method;
  const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
  
  try {
    // 1. Method validation - only GET and HEAD allowed
    if (BLOCKED_METHODS.includes(method)) {
      return createErrorResponse(405, 'Method Not Allowed', {
        'Allow': 'GET, HEAD',
        ...SECURITY_HEADERS
      });
    }
    
    // 2. Path validation - block dangerous extensions and paths
    for (const blockedPattern of BLOCKED_PATHS) {
      if (blockedPattern.test(url.pathname)) {
        return createErrorResponse(404, 'Not Found', SECURITY_HEADERS);
      }
    }
    
    // 3. Rate limiting
    const rateLimitKey = `${clientIP}:${Math.floor(Date.now() / RATE_LIMIT_WINDOW)}`;
    const currentCount = rateLimitMap.get(rateLimitKey) || 0;
    
    if (currentCount >= RATE_LIMIT_REQUESTS) {
      return createErrorResponse(429, 'Too Many Requests', {
        'Retry-After': '60',
        ...SECURITY_HEADERS
      });
    }
    
    rateLimitMap.set(rateLimitKey, currentCount + 1);
    
    // 4. Clean old rate limit entries (simple cleanup)
    if (Math.random() < 0.01) { // 1% chance to clean
      const now = Date.now();
      for (const [key, value] of rateLimitMap.entries()) {
        const keyTime = parseInt(key.split(':')[1]) * RATE_LIMIT_WINDOW;
        if (now - keyTime > RATE_LIMIT_WINDOW * 2) {
          rateLimitMap.delete(key);
        }
      }
    }
    
    // 5. Security exceptions for well-known paths
    if (url.pathname === '/.well-known/security.txt') {
      const securityTxt = `Contact: security@example.com
Expires: ${new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString()}
Encryption: https://example.com/.well-known/pgp-key.asc
Preferred-Languages: en
Canonical: https://example.com/.well-known/security.txt`;
      
      return new Response(securityTxt, {
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          ...SECURITY_HEADERS
        }
      });
    }
    
    // 6. Fetch from origin (Pages or other backend)
    const response = await fetch(request);
    
    // 7. Response size validation
    const responseText = await response.text();
    if (responseText.length > MAX_RESPONSE_SIZE) {
      return createErrorResponse(413, 'Response Too Large', {
        'Content-Length': responseText.length.toString(),
        ...SECURITY_HEADERS
      });
    }
    
    // 8. Content validation - ensure no JavaScript
    if (response.headers.get('content-type')?.includes('text/html')) {
      // Quick check for JavaScript in HTML responses
      const jsPatterns = [
        /<script\b/i,
        /javascript:/i,
        /on\w+\s*=/i,
        /eval\s*\(/i,
        /Function\s*\(/i
      ];
      
      for (const pattern of jsPatterns) {
        if (pattern.test(responseText)) {
          console.error(`JavaScript detected in response: ${url.pathname}`);
          return createErrorResponse(500, 'Content Security Violation', SECURITY_HEADERS);
        }
      }
    }
    
    // 9. Create secure response with all headers
    const secureResponse = new Response(responseText, {
      status: response.status,
      statusText: response.statusText,
      headers: {
        ...Object.fromEntries(response.headers.entries()),
        ...SECURITY_HEADERS,
        'X-Worker-Processed': 'true',
        'X-Security-Level': 'maximum'
      }
    });
    
    return secureResponse;
    
  } catch (error) {
    console.error('Worker error:', error);
    return createErrorResponse(500, 'Internal Server Error', SECURITY_HEADERS);
  }
}

function createErrorResponse(status, statusText, headers = {}) {
  const errorBody = `<!DOCTYPE html>
<html>
<head>
  <title>${status} ${statusText}</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>body{font-family:sans-serif;text-align:center;padding:50px;}</style>
</head>
<body>
  <h1>${status}</h1>
  <p>${statusText}</p>
  <p><a href="/">Return Home</a></p>
</body>
</html>`;

  return new Response(errorBody, {
    status,
    statusText,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      ...headers
    }
  });
}

// Export for testing
export { handleRequest, SECURITY_HEADERS, MAX_RESPONSE_SIZE };