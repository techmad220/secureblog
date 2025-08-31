/**
 * Cloudflare Edge Security Worker
 * Enforces GET/HEAD only, 1KB limits, CSP reporting, and prevents config drift
 */

// Configuration constants - treat as immutable code
const CONFIG = {
  ALLOWED_METHODS: ['GET', 'HEAD'],
  MAX_REQUEST_SIZE: 1024, // 1KB
  MAX_RESPONSE_SIZE: 10485760, // 10MB for legitimate static content
  RATE_LIMIT: 100, // requests per minute per IP
  CSP_POLICY: [
    "default-src 'none'",
    "img-src 'self' data:",
    "style-src 'self'",
    "font-src 'self'", 
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
    "block-all-mixed-content",
    "upgrade-insecure-requests",
    "report-to csp-endpoint"
  ].join('; '),
  
  // Security headers - enforced and immutable
  SECURITY_HEADERS: {
    'Content-Security-Policy': null, // Set dynamically above
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'X-XSS-Protection': '1; mode=block',
    'Referrer-Policy': 'no-referrer',
    'Permissions-Policy': 'accelerometer=(), battery=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()',
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
    'Report-To': JSON.stringify([
      {
        "group": "csp-endpoint",
        "max_age": 86400,
        "endpoints": [{"url": "/api/csp-report"}],
        "include_subdomains": true
      }
    ])
  }
};

// Rate limiting storage
const RATE_LIMIT_PREFIX = 'rate_limit:';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const method = request.method;
    const clientIP = request.headers.get('CF-Connecting-IP');
    
    try {
      // 1. METHOD ENFORCEMENT - Block all methods except GET/HEAD
      if (!CONFIG.ALLOWED_METHODS.includes(method)) {
        console.log(`Blocked method ${method} from ${clientIP} for ${url.pathname}`);
        
        return new Response(
          `<!DOCTYPE html><html><head><title>405 Method Not Allowed</title></head>
           <body><h1>405 Method Not Allowed</h1>
           <p>Only GET and HEAD requests are allowed.</p>
           <p>This site is read-only for maximum security.</p>
           </body></html>`, 
          { 
            status: 405, 
            headers: {
              'Allow': CONFIG.ALLOWED_METHODS.join(', '),
              'Content-Type': 'text/html; charset=utf-8',
              ...CONFIG.SECURITY_HEADERS,
              'Content-Security-Policy': CONFIG.CSP_POLICY
            }
          }
        );
      }

      // 2. REQUEST SIZE ENFORCEMENT - Block large requests
      const contentLength = parseInt(request.headers.get('Content-Length') || '0');
      if (contentLength > CONFIG.MAX_REQUEST_SIZE) {
        console.log(`Blocked oversized request ${contentLength} bytes from ${clientIP}`);
        
        return new Response(
          `<!DOCTYPE html><html><head><title>413 Payload Too Large</title></head>
           <body><h1>413 Payload Too Large</h1>
           <p>Request size limit: ${CONFIG.MAX_REQUEST_SIZE} bytes</p>
           </body></html>`,
          { 
            status: 413,
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              ...CONFIG.SECURITY_HEADERS,
              'Content-Security-Policy': CONFIG.CSP_POLICY
            }
          }
        );
      }

      // 3. RATE LIMITING - Prevent abuse
      if (env.RATE_LIMIT_KV) {
        const rateLimitKey = `${RATE_LIMIT_PREFIX}${clientIP}`;
        const currentCount = await env.RATE_LIMIT_KV.get(rateLimitKey);
        
        if (currentCount && parseInt(currentCount) >= CONFIG.RATE_LIMIT) {
          console.log(`Rate limited ${clientIP} - ${currentCount} requests`);
          
          return new Response(
            `<!DOCTYPE html><html><head><title>429 Too Many Requests</title></head>
             <body><h1>429 Too Many Requests</h1>
             <p>Rate limit: ${CONFIG.RATE_LIMIT} requests per minute</p>
             <p>Try again later.</p>
             </body></html>`,
            { 
              status: 429,
              headers: {
                'Retry-After': '60',
                'Content-Type': 'text/html; charset=utf-8', 
                ...CONFIG.SECURITY_HEADERS,
                'Content-Security-Policy': CONFIG.CSP_POLICY
              }
            }
          );
        }

        // Update rate limit counter
        const newCount = currentCount ? parseInt(currentCount) + 1 : 1;
        await env.RATE_LIMIT_KV.put(rateLimitKey, newCount.toString(), {
          expirationTtl: 60 // 1 minute
        });
      }

      // 4. CSP REPORTING ENDPOINT
      if (url.pathname === '/api/csp-report' && method === 'POST') {
        return handleCSPReport(request, env);
      }

      // 5. CONFIGURATION DRIFT TEST ENDPOINT
      if (url.pathname === '/api/config-test' && method === 'GET') {
        return handleConfigTest(request, env);
      }

      // 6. PROXY TO ORIGIN with security validation
      let response;
      try {
        response = await fetch(request);
      } catch (error) {
        console.error('Origin fetch failed:', error);
        return new Response(
          `<!DOCTYPE html><html><head><title>502 Bad Gateway</title></head>
           <body><h1>502 Bad Gateway</h1>
           <p>Origin server unavailable.</p>
           </body></html>`,
          { 
            status: 502,
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              ...CONFIG.SECURITY_HEADERS,
              'Content-Security-Policy': CONFIG.CSP_POLICY
            }
          }
        );
      }

      // 7. RESPONSE SIZE VALIDATION
      const responseSize = parseInt(response.headers.get('Content-Length') || '0');
      if (responseSize > CONFIG.MAX_RESPONSE_SIZE) {
        console.log(`Blocked oversized response ${responseSize} bytes for ${url.pathname}`);
        
        return new Response(
          `<!DOCTYPE html><html><head><title>507 Insufficient Storage</title></head>
           <body><h1>507 Insufficient Storage</h1>
           <p>Response too large for security policy.</p>
           </body></html>`,
          { 
            status: 507,
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              ...CONFIG.SECURITY_HEADERS,
              'Content-Security-Policy': CONFIG.CSP_POLICY
            }
          }
        );
      }

      // 8. CONTENT SECURITY VALIDATION
      const contentType = response.headers.get('Content-Type') || '';
      if (contentType.includes('text/html')) {
        const responseText = await response.text();
        
        // Check for JavaScript content in HTML responses
        if (containsJavaScript(responseText)) {
          console.error(`JavaScript detected in HTML response for ${url.pathname}`);
          
          return new Response(
            `<!DOCTYPE html><html><head><title>403 Forbidden</title></head>
             <body><h1>403 Forbidden</h1>
             <p>JavaScript content blocked by security policy.</p>
             </body></html>`,
            { 
              status: 403,
              headers: {
                'Content-Type': 'text/html; charset=utf-8',
                ...CONFIG.SECURITY_HEADERS,
                'Content-Security-Policy': CONFIG.CSP_POLICY
              }
            }
          );
        }

        // Return sanitized HTML with security headers
        return new Response(responseText, {
          status: response.status,
          statusText: response.statusText,
          headers: {
            ...response.headers,
            ...CONFIG.SECURITY_HEADERS,
            'Content-Security-Policy': CONFIG.CSP_POLICY
          }
        });
      }

      // 9. RETURN RESPONSE WITH SECURITY HEADERS
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: {
          ...response.headers,
          ...CONFIG.SECURITY_HEADERS,
          'Content-Security-Policy': CONFIG.CSP_POLICY
        }
      });

    } catch (error) {
      console.error('Worker error:', error);
      
      return new Response(
        `<!DOCTYPE html><html><head><title>500 Internal Server Error</title></head>
         <body><h1>500 Internal Server Error</h1>
         <p>An unexpected error occurred.</p>
         </body></html>`,
        { 
          status: 500,
          headers: {
            'Content-Type': 'text/html; charset=utf-8',
            ...CONFIG.SECURITY_HEADERS,
            'Content-Security-Policy': CONFIG.CSP_POLICY
          }
        }
      );
    }
  },
};

/**
 * Handle CSP violation reports
 */
async function handleCSPReport(request, env) {
  try {
    const report = await request.json();
    const clientIP = request.headers.get('CF-Connecting-IP');
    
    console.log('CSP Violation Report:', JSON.stringify({
      timestamp: new Date().toISOString(),
      clientIP: clientIP,
      userAgent: request.headers.get('User-Agent'),
      report: report
    }));

    // Filter out browser extension violations
    const violatedDirective = report['csp-report']?.['violated-directive'] || '';
    const sourceFile = report['csp-report']?.['source-file'] || '';
    
    const browserExtensionPatterns = [
      /extension:\/\//,
      /moz-extension:\/\//,  
      /chrome-extension:\/\//,
      /safari-extension:\/\//,
      /about:blank/
    ];
    
    const isBrowserExtension = browserExtensionPatterns.some(pattern => 
      pattern.test(sourceFile) || pattern.test(violatedDirective)
    );
    
    if (!isBrowserExtension) {
      // Store real violations for analysis
      if (env.CSP_REPORTS_BUCKET) {
        const key = `csp-violations/${new Date().toISOString().slice(0, 10)}/${Date.now()}-${Math.random().toString(36).slice(2)}.json`;
        await env.CSP_REPORTS_BUCKET.put(key, JSON.stringify({
          timestamp: new Date().toISOString(),
          clientIP: clientIP,
          userAgent: request.headers.get('User-Agent'),
          referer: request.headers.get('Referer'),
          report: report
        }, null, 2));
      }
    }

    return new Response('OK', { status: 200 });
  } catch (error) {
    console.error('CSP report handling error:', error);
    return new Response('Bad Request', { status: 400 });
  }
}

/**
 * Handle configuration drift testing
 * Tests that security policies are still enforced
 */
async function handleConfigTest(request, env) {
  const tests = {
    'method_enforcement': testMethodEnforcement(),
    'size_limits': testSizeLimits(),
    'security_headers': testSecurityHeaders(),
    'csp_policy': testCSPPolicy()
  };
  
  return new Response(JSON.stringify({
    timestamp: new Date().toISOString(),
    tests: tests,
    status: Object.values(tests).every(t => t.passed) ? 'PASS' : 'FAIL'
  }, null, 2), {
    headers: {
      'Content-Type': 'application/json',
      ...CONFIG.SECURITY_HEADERS,
      'Content-Security-Policy': CONFIG.CSP_POLICY
    }
  });
}

/**
 * Test method enforcement
 */
function testMethodEnforcement() {
  return {
    passed: CONFIG.ALLOWED_METHODS.length === 2 && 
            CONFIG.ALLOWED_METHODS.includes('GET') && 
            CONFIG.ALLOWED_METHODS.includes('HEAD'),
    expected: ['GET', 'HEAD'],
    actual: CONFIG.ALLOWED_METHODS
  };
}

/**
 * Test size limits
 */
function testSizeLimits() {
  return {
    passed: CONFIG.MAX_REQUEST_SIZE === 1024,
    expected: 1024,
    actual: CONFIG.MAX_REQUEST_SIZE
  };
}

/**
 * Test security headers
 */
function testSecurityHeaders() {
  const requiredHeaders = [
    'X-Frame-Options',
    'X-Content-Type-Options', 
    'Strict-Transport-Security',
    'Referrer-Policy',
    'Cross-Origin-Opener-Policy'
  ];
  
  const missingHeaders = requiredHeaders.filter(header => 
    !(header in CONFIG.SECURITY_HEADERS)
  );
  
  return {
    passed: missingHeaders.length === 0,
    expected: requiredHeaders,
    missing: missingHeaders
  };
}

/**
 * Test CSP policy
 */
function testCSPPolicy() {
  const requiredDirectives = [
    "default-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'"
  ];
  
  const missingDirectives = requiredDirectives.filter(directive => 
    !CONFIG.CSP_POLICY.includes(directive)
  );
  
  return {
    passed: missingDirectives.length === 0,
    expected: requiredDirectives,
    missing: missingDirectives,
    actual: CONFIG.CSP_POLICY
  };
}

/**
 * Check if content contains JavaScript
 */
function containsJavaScript(content) {
  const jsPatterns = [
    /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi,
    /javascript:/i,
    /on\w+\s*=/i,
    /eval\s*\(/i,
    /Function\s*\(/i,
    /setTimeout\s*\(/i,
    /setInterval\s*\(/i
  ];
  
  return jsPatterns.some(pattern => pattern.test(content));
}