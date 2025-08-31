/**
 * Precision Content Security Policy Worker
 * Implements strict CSP with precise directives for images and CSS while maintaining security
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // Get response from origin
    const response = await fetch(request);
    
    // Create new response with security headers
    const newResponse = new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: new Headers(response.headers),
    });

    // Precision Content Security Policy
    // Default to nothing, explicitly allow what's needed
    const cspDirectives = [
      // Default: block everything not explicitly allowed
      "default-src 'none'",
      
      // Scripts: completely blocked (no JavaScript execution)
      "script-src 'none'",
      "script-src-elem 'none'", 
      "script-src-attr 'none'",
      
      // Styles: allow self-hosted CSS only
      "style-src 'self'",
      "style-src-elem 'self'",
      "style-src-attr 'none'", // No inline style attributes
      
      // Images: allow self and data URLs (for optimized images)
      "img-src 'self' data:",
      
      // Fonts: allow self-hosted fonts only
      "font-src 'self'",
      
      // Media: allow self-hosted media
      "media-src 'self'",
      
      // Objects/plugins: completely blocked
      "object-src 'none'",
      "plugin-types", // Empty = no plugins allowed
      
      // Frames: completely blocked
      "frame-src 'none'",
      "frame-ancestors 'none'",
      "child-src 'none'",
      
      // Workers/manifest: blocked
      "worker-src 'none'",
      "manifest-src 'none'",
      
      // Connections: only to self (no external API calls)
      "connect-src 'self'",
      
      // Base URI: restrict to self
      "base-uri 'self'",
      
      // Form actions: no forms allowed
      "form-action 'none'",
      
      // Navigation: restrict navigation
      "navigate-to 'self'",
      
      // Trusted Types: enforce if supported
      "require-trusted-types-for 'script'",
      "trusted-types 'none'",
      
      // Block mixed content
      "upgrade-insecure-requests",
      
      // Reporting
      "report-to csp-endpoint"
    ].join('; ');

    // Additional security headers
    const securityHeaders = {
      // Precision CSP
      'Content-Security-Policy': cspDirectives,
      
      // Backup CSP for older browsers
      'X-Content-Security-Policy': cspDirectives,
      'X-WebKit-CSP': cspDirectives,
      
      // Report-To configuration for CSP violations
      'Report-To': JSON.stringify({
        group: 'csp-endpoint',
        max_age: 86400,
        endpoints: [
          {
            url: `https://${url.hostname}/csp-report`
          }
        ],
        include_subdomains: true
      }),
      
      // Additional frame protection
      'X-Frame-Options': 'DENY',
      
      // Strict Transport Security with preload
      'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
      
      // Content type protection
      'X-Content-Type-Options': 'nosniff',
      
      // XSS protection (legacy but still useful)
      'X-XSS-Protection': '1; mode=block',
      
      // Referrer policy
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      
      // Cross-Origin policies
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Resource-Policy': 'same-origin',
      
      // Cache control for security
      'Cache-Control': 'private, no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
      'Expires': '0',
      
      // Remove server identification
      'Server': 'SecureBlog/1.0'
    };

    // Apply security headers
    Object.entries(securityHeaders).forEach(([key, value]) => {
      newResponse.headers.set(key, value);
    });

    // Remove potentially revealing headers
    const headersToRemove = [
      'x-powered-by',
      'server',
      'x-aspnet-version',
      'x-aspnetmvc-version',
      'x-frame-options', // We set our own
      'x-xss-protection', // We set our own
    ];

    headersToRemove.forEach(header => {
      newResponse.headers.delete(header);
    });

    return newResponse;
  }
};

/**
 * CSP Report Handler Worker
 * Handles CSP violation reports without storing personal data
 */
export const cspReportHandler = {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // Only handle POST requests to /csp-report
    if (request.method !== 'POST' || url.pathname !== '/csp-report') {
      return new Response('Not Found', { status: 404 });
    }

    try {
      const report = await request.json();
      
      // Sanitize report to remove PII
      const sanitizedReport = {
        timestamp: new Date().toISOString(),
        'blocked-uri': report['csp-report']?.[`blocked-uri`] || 'unknown',
        'violated-directive': report['csp-report']?.[`violated-directive`] || 'unknown',
        'effective-directive': report['csp-report']?.[`effective-directive`] || 'unknown',
        'document-uri': 'sanitized', // Don't log full URLs
        'source-file': 'sanitized',   // Don't log source files
        // Explicitly exclude: line-number, column-number, script-sample
      };

      // Log to console for debugging (no storage of personal data)
      console.log('CSP Violation (sanitized):', JSON.stringify(sanitizedReport));

      // In production, you could send this to a privacy-preserving analytics service
      // that aggregates violations without storing individual reports
      
      return new Response('OK', {
        status: 200,
        headers: {
          'Content-Type': 'text/plain',
          'Access-Control-Allow-Origin': url.origin,
          'Access-Control-Allow-Methods': 'POST',
          'Access-Control-Allow-Headers': 'Content-Type',
        }
      });
      
    } catch (error) {
      console.error('CSP report parsing error:', error);
      return new Response('Bad Request', { status: 400 });
    }
  }
};