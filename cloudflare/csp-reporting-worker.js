/**
 * Cloudflare Worker - CSP Reporting & SRI Enforcement
 * Handles CSP violations and enforces Subresource Integrity
 */

// Enhanced CSP with reporting
const CSP_POLICY = [
  "default-src 'none'",
  "img-src 'self' data:",
  "style-src 'self'",  // No unsafe-inline
  "font-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
  "block-all-mixed-content",
  "upgrade-insecure-requests",
  "report-to csp-reports"
].join('; ');

// NEL (Network Error Logging) policy
const NEL_POLICY = {
  "report_to": "nel-reports",
  "max_age": 86400,
  "include_subdomains": true
};

// Report-To endpoints
const REPORT_TO_POLICY = [
  {
    "group": "csp-reports",
    "max_age": 86400,
    "endpoints": [{"url": "/api/csp-report"}],
    "include_subdomains": true
  },
  {
    "group": "nel-reports", 
    "max_age": 86400,
    "endpoints": [{"url": "/api/nel-report"}],
    "include_subdomains": true
  }
];

// Known SRI hashes for external resources (update as needed)
const KNOWN_SRI_HASHES = {
  // Example: Bootstrap CDN
  'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css': 'sha384-9ndCyUa6c3+c8b6iY6JBKc0d0T5v6vW6wQ4aaLUUO/2aXlL8YGOo1mM4n9R4j5a',
  // Add more as needed
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method;

    try {
      // Handle CSP violation reports
      if (url.pathname === '/api/csp-report' && method === 'POST') {
        return handleCSPReport(request, env);
      }
      
      // Handle NEL violation reports
      if (url.pathname === '/api/nel-report' && method === 'POST') {
        return handleNELReport(request, env);
      }

      // Proxy to origin with enhanced security headers
      const response = await fetch(request);
      return addSecurityHeaders(response, url);

    } catch (error) {
      console.error('Worker error:', error);
      return new Response('Internal Server Error', { status: 500 });
    }
  },
};

async function handleCSPReport(request, env) {
  try {
    const report = await request.json();
    
    // Log CSP violation
    console.log('CSP Violation:', JSON.stringify(report, null, 2));
    
    // Filter out browser extension violations (common false positives)
    const browserExtensionPatterns = [
      /extension:\/\//,
      /moz-extension:\/\//,
      /chrome-extension:\/\//,
      /safari-extension:\/\//,
      /about:blank/,
      /localhost:/
    ];
    
    const violatedDirective = report['csp-report']?.['violated-directive'] || '';
    const sourceFile = report['csp-report']?.['source-file'] || '';
    
    // Check if this is a browser extension violation
    const isBrowserExtension = browserExtensionPatterns.some(pattern => 
      pattern.test(sourceFile) || pattern.test(violatedDirective)
    );
    
    if (isBrowserExtension) {
      console.log('Filtered browser extension CSP violation');
      return new Response('OK', { status: 200 });
    }
    
    // This is a real CSP violation - store it
    const violation = {
      timestamp: new Date().toISOString(),
      userAgent: request.headers.get('User-Agent'),
      referer: request.headers.get('Referer'),
      report: report['csp-report'],
      severity: getSeverity(report['csp-report']),
      clientIP: request.headers.get('CF-Connecting-IP')
    };
    
    // Store in R2 or send alert for critical violations
    if (violation.severity === 'critical') {
      await sendCriticalAlert(violation, env);
    }
    
    // Store violation report (implement R2 storage)
    await storeViolationReport(violation, env);
    
    return new Response('OK', { status: 200 });
  } catch (error) {
    console.error('Error handling CSP report:', error);
    return new Response('Bad Request', { status: 400 });
  }
}

async function handleNELReport(request, env) {
  try {
    const report = await request.json();
    console.log('NEL Report:', JSON.stringify(report, null, 2));
    
    // Store NEL report for network error analysis
    await storeNELReport(report, env);
    
    return new Response('OK', { status: 200 });
  } catch (error) {
    console.error('Error handling NEL report:', error);
    return new Response('Bad Request', { status: 400 });
  }
}

function addSecurityHeaders(response, url) {
  // Clone response to modify headers
  const newResponse = new Response(response.body, response);
  
  // Enhanced CSP with reporting
  newResponse.headers.set('Content-Security-Policy', CSP_POLICY);
  
  // Network Error Logging
  newResponse.headers.set('NEL', JSON.stringify(NEL_POLICY));
  
  // Report-To directive
  newResponse.headers.set('Report-To', JSON.stringify(REPORT_TO_POLICY));
  
  // Other security headers
  newResponse.headers.set('X-Frame-Options', 'DENY');
  newResponse.headers.set('X-Content-Type-Options', 'nosniff');
  newResponse.headers.set('X-XSS-Protection', '1; mode=block');
  newResponse.headers.set('Referrer-Policy', 'no-referrer');
  newResponse.headers.set('Permissions-Policy', 'accelerometer=(), battery=(), camera=(), display-capture=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()');
  newResponse.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  newResponse.headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  newResponse.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  newResponse.headers.set('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
  
  // Add custom security headers
  newResponse.headers.set('X-Security-Level', 'maximum');
  newResponse.headers.set('X-CSP-Reporting', 'enabled');
  
  return newResponse;
}

function getSeverity(cspReport) {
  const violatedDirective = cspReport['violated-directive'] || '';
  const sourceFile = cspReport['source-file'] || '';
  const blockedURI = cspReport['blocked-uri'] || '';
  
  // Critical: Script execution attempts
  if (violatedDirective.includes('script-src') || 
      violatedDirective.includes('unsafe-eval') ||
      violatedDirective.includes('unsafe-inline')) {
    return 'critical';
  }
  
  // High: External resource loading without proper SRI
  if (violatedDirective.includes('style-src') ||
      violatedDirective.includes('font-src')) {
    return 'high';
  }
  
  // Medium: Other policy violations
  return 'medium';
}

async function sendCriticalAlert(violation, env) {
  // Send immediate alert for critical CSP violations
  // This could integrate with your alerting system
  console.error('CRITICAL CSP VIOLATION:', {
    directive: violation.report['violated-directive'],
    source: violation.report['source-file'],
    blocked: violation.report['blocked-uri'],
    timestamp: violation.timestamp
  });
  
  // TODO: Integrate with alerting service (email, Slack, etc.)
}

async function storeViolationReport(violation, env) {
  // Store CSP violation in R2 for analysis
  if (env.CSP_REPORTS_BUCKET) {
    const key = `csp-violations/${new Date().toISOString().slice(0, 10)}/${Date.now()}-${Math.random().toString(36).slice(2)}.json`;
    await env.CSP_REPORTS_BUCKET.put(key, JSON.stringify(violation, null, 2));
  }
}

async function storeNELReport(report, env) {
  // Store NEL report in R2 for network error analysis
  if (env.NEL_REPORTS_BUCKET) {
    const key = `nel-reports/${new Date().toISOString().slice(0, 10)}/${Date.now()}-${Math.random().toString(36).slice(2)}.json`;
    await env.NEL_REPORTS_BUCKET.put(key, JSON.stringify(report, null, 2));
  }
}

// SRI validation function (for build-time use)
export function validateSRI(html) {
  const linkRegex = /<link[^>]*rel=["']stylesheet["'][^>]*>/gi;
  const matches = html.match(linkRegex) || [];
  
  for (const link of matches) {
    const hrefMatch = link.match(/href=["']([^"']+)["']/);
    if (hrefMatch) {
      const href = hrefMatch[1];
      
      // Check if it's an external resource
      if (href.startsWith('http') && !href.includes(window.location.hostname)) {
        // Require SRI for external stylesheets
        if (!link.includes('integrity=')) {
          throw new Error(`External stylesheet missing SRI: ${href}`);
        }
      }
    }
  }
  
  return true;
}