/**
 * CSP Reporter Worker
 * Handles Content Security Policy violation reports
 * Stores reports in R2 for analysis without third-party dependencies
 */

export default {
  async fetch(request, env, ctx) {
    // Only accept POST requests to the reporting endpoint
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { 
        status: 405,
        headers: { 'Allow': 'POST' }
      });
    }
    
    // Verify the request is for CSP reporting
    const url = new URL(request.url);
    if (url.pathname !== '/csp-report' && url.pathname !== '/.well-known/csp-report') {
      return new Response('Not found', { status: 404 });
    }
    
    // Rate limiting per IP
    const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
    const rateLimitKey = `rate:${clientIP}:${Math.floor(Date.now() / 60000)}`; // Per minute
    
    const rateLimit = await env.CSP_RATE_LIMIT.get(rateLimitKey);
    if (rateLimit && parseInt(rateLimit) > 10) { // Max 10 reports per minute per IP
      return new Response('Rate limit exceeded', { status: 429 });
    }
    
    try {
      // Parse CSP report
      const contentType = request.headers.get('content-type') || '';
      let report;
      
      if (contentType.includes('application/csp-report')) {
        // Standard CSP report format
        const body = await request.json();
        report = body['csp-report'] || body;
      } else if (contentType.includes('application/reports+json')) {
        // Reporting API format
        const reports = await request.json();
        report = reports[0]?.body || reports[0];
      } else {
        return new Response('Invalid content type', { status: 400 });
      }
      
      // Validate report structure
      if (!report || typeof report !== 'object') {
        return new Response('Invalid report format', { status: 400 });
      }
      
      // Sanitize and enrich report
      const sanitizedReport = sanitizeReport(report);
      const enrichedReport = await enrichReport(sanitizedReport, request, env);
      
      // Check for known false positives
      if (isFalsePositive(enrichedReport)) {
        return new Response('OK (filtered)', { status: 204 });
      }
      
      // Store report in R2
      const reportId = generateReportId();
      const timestamp = new Date().toISOString();
      const reportKey = `csp-reports/${timestamp.slice(0, 10)}/${reportId}.json`;
      
      await env.CSP_REPORTS_BUCKET.put(reportKey, JSON.stringify(enrichedReport), {
        httpMetadata: {
          contentType: 'application/json',
        },
        customMetadata: {
          timestamp: timestamp,
          ip: clientIP,
          userAgent: request.headers.get('user-agent') || 'unknown',
          severity: calculateSeverity(enrichedReport)
        }
      });
      
      // Update rate limit
      await env.CSP_RATE_LIMIT.put(rateLimitKey, '1', { 
        expirationTtl: 60 
      });
      
      // Aggregate statistics
      await updateStatistics(env, enrichedReport);
      
      // Check for critical violations
      if (isCriticalViolation(enrichedReport)) {
        await alertOnCriticalViolation(env, enrichedReport);
      }
      
      // Return success response
      return new Response('OK', { 
        status: 204,
        headers: {
          'X-Report-Id': reportId
        }
      });
      
    } catch (error) {
      console.error('CSP report processing error:', error);
      
      // Log error to R2 for debugging
      const errorKey = `csp-reports/errors/${Date.now()}.json`;
      await env.CSP_REPORTS_BUCKET.put(errorKey, JSON.stringify({
        error: error.message,
        stack: error.stack,
        timestamp: new Date().toISOString()
      }));
      
      return new Response('Internal server error', { status: 500 });
    }
  }
};

function sanitizeReport(report) {
  // Remove potentially sensitive data
  const sanitized = { ...report };
  
  // Redact sensitive URL parameters
  const sensitiveParams = ['token', 'key', 'secret', 'password', 'api', 'auth'];
  
  ['blocked-uri', 'document-uri', 'source-file', 'referrer'].forEach(field => {
    if (sanitized[field]) {
      try {
        const url = new URL(sanitized[field]);
        sensitiveParams.forEach(param => {
          if (url.searchParams.has(param)) {
            url.searchParams.set(param, '[REDACTED]');
          }
        });
        sanitized[field] = url.toString();
      } catch {
        // Not a valid URL, leave as is
      }
    }
  });
  
  // Truncate long fields
  ['script-sample', 'original-policy'].forEach(field => {
    if (sanitized[field] && sanitized[field].length > 500) {
      sanitized[field] = sanitized[field].substring(0, 500) + '...[truncated]';
    }
  });
  
  return sanitized;
}

async function enrichReport(report, request, env) {
  const enriched = {
    ...report,
    metadata: {
      timestamp: new Date().toISOString(),
      reportId: generateReportId(),
      ip: request.headers.get('CF-Connecting-IP') || 'unknown',
      country: request.headers.get('CF-IPCountry') || 'unknown',
      userAgent: request.headers.get('user-agent') || 'unknown',
      referer: request.headers.get('referer') || 'none',
      rayId: request.headers.get('CF-RAY') || 'unknown'
    },
    analysis: {
      severity: 'low',
      category: 'unknown',
      actionRequired: false
    }
  };
  
  // Categorize violation
  if (report['violated-directive']) {
    const directive = report['violated-directive'].split(' ')[0];
    
    if (directive === 'script-src' || directive === 'script-src-elem') {
      enriched.analysis.category = 'script-injection';
      enriched.analysis.severity = 'high';
      enriched.analysis.actionRequired = true;
    } else if (directive === 'connect-src') {
      enriched.analysis.category = 'data-exfiltration';
      enriched.analysis.severity = 'medium';
    } else if (directive === 'img-src' || directive === 'media-src') {
      enriched.analysis.category = 'resource-loading';
      enriched.analysis.severity = 'low';
    } else if (directive === 'style-src') {
      enriched.analysis.category = 'style-injection';
      enriched.analysis.severity = 'medium';
    } else if (directive === 'frame-ancestors') {
      enriched.analysis.category = 'clickjacking';
      enriched.analysis.severity = 'high';
      enriched.analysis.actionRequired = true;
    }
  }
  
  return enriched;
}

function isFalsePositive(report) {
  // Filter known false positives
  const blockedUri = report['blocked-uri'] || '';
  const sourceFile = report['source-file'] || '';
  
  // Browser extensions
  if (blockedUri.startsWith('chrome-extension://') ||
      blockedUri.startsWith('moz-extension://') ||
      blockedUri.startsWith('safari-extension://') ||
      sourceFile.includes('extension://')) {
    return true;
  }
  
  // Common browser injections
  const falsePositivePatterns = [
    'translate.google',
    'googletagmanager',
    'google-analytics',
    'doubleclick',
    'facebook.com/tr',
    'grammarly',
    'lastpass',
    '1password',
    'dashlane',
    'honey',
    'adblock'
  ];
  
  for (const pattern of falsePositivePatterns) {
    if (blockedUri.includes(pattern) || sourceFile.includes(pattern)) {
      return true;
    }
  }
  
  // Inline violations from browser DevTools
  if (blockedUri === 'inline' && report['script-sample']?.includes('DevTools')) {
    return true;
  }
  
  return false;
}

function isCriticalViolation(report) {
  // Identify critical security violations that need immediate attention
  const severity = report.analysis?.severity || 'low';
  const category = report.analysis?.category || 'unknown';
  
  // Critical: script injection attempts
  if (category === 'script-injection' && 
      !report['blocked-uri'].startsWith('self') &&
      !report['blocked-uri'].startsWith('inline')) {
    return true;
  }
  
  // Critical: clickjacking attempts
  if (category === 'clickjacking') {
    return true;
  }
  
  // Critical: data exfiltration to unknown domains
  if (category === 'data-exfiltration' && 
      !isKnownDomain(report['blocked-uri'])) {
    return true;
  }
  
  return false;
}

function isKnownDomain(uri) {
  // List of known/allowed domains
  const knownDomains = [
    'cloudflare.com',
    'github.com',
    'githubusercontent.com'
  ];
  
  try {
    const url = new URL(uri);
    return knownDomains.some(domain => url.hostname.endsWith(domain));
  } catch {
    return false;
  }
}

async function updateStatistics(env, report) {
  // Update daily statistics in Durable Object
  const id = env.CSP_STATS.idFromName('daily-stats');
  const stub = env.CSP_STATS.get(id);
  
  await stub.fetch(new Request('https://stats.internal/update', {
    method: 'POST',
    body: JSON.stringify({
      directive: report['violated-directive']?.split(' ')[0],
      category: report.analysis?.category,
      severity: report.analysis?.severity,
      timestamp: report.metadata?.timestamp
    })
  }));
}

async function alertOnCriticalViolation(env, report) {
  // Send alert for critical violations
  // This could trigger a webhook, email, or store in a priority queue
  
  const alertKey = `csp-reports/critical/${Date.now()}.json`;
  await env.CSP_REPORTS_BUCKET.put(alertKey, JSON.stringify(report), {
    customMetadata: {
      alert: 'critical',
      timestamp: new Date().toISOString()
    }
  });
  
  // Optionally trigger webhook
  if (env.ALERT_WEBHOOK_URL) {
    await fetch(env.ALERT_WEBHOOK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Alert-Type': 'csp-violation'
      },
      body: JSON.stringify({
        severity: 'critical',
        report: report,
        timestamp: new Date().toISOString()
      })
    });
  }
}

function generateReportId() {
  return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function calculateSeverity(report) {
  return report.analysis?.severity || 'low';
}

// Durable Object for statistics aggregation
export class CSPStatistics {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }
  
  async fetch(request) {
    const url = new URL(request.url);
    
    if (url.pathname === '/update' && request.method === 'POST') {
      const data = await request.json();
      await this.updateStats(data);
      return new Response('OK');
    }
    
    if (url.pathname === '/stats' && request.method === 'GET') {
      const stats = await this.getStats();
      return new Response(JSON.stringify(stats), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    return new Response('Not found', { status: 404 });
  }
  
  async updateStats(data) {
    const date = new Date().toISOString().slice(0, 10);
    const key = `stats:${date}`;
    
    let stats = await this.state.storage.get(key) || {
      total: 0,
      byDirective: {},
      byCategory: {},
      bySeverity: { low: 0, medium: 0, high: 0, critical: 0 }
    };
    
    stats.total++;
    stats.byDirective[data.directive] = (stats.byDirective[data.directive] || 0) + 1;
    stats.byCategory[data.category] = (stats.byCategory[data.category] || 0) + 1;
    stats.bySeverity[data.severity] = (stats.bySeverity[data.severity] || 0) + 1;
    
    await this.state.storage.put(key, stats);
  }
  
  async getStats() {
    const date = new Date().toISOString().slice(0, 10);
    const key = `stats:${date}`;
    return await this.state.storage.get(key) || {};
  }
}