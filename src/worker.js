// Cloudflare Worker with plugin-based security
import { securityPlugins } from './worker-plugins.js';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // Apply rate limiting plugin
    if (securityPlugins.rateLimit.enabled) {
      const rateLimitResult = securityPlugins.rateLimit.apply(
        request, 
        securityPlugins.rateLimit.config
      );
      if (rateLimitResult.blocked) {
        return rateLimitResult.response;
      }
    }
    
    // Only allow GET and HEAD methods
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response('Method Not Allowed', { status: 405 });
    }
    
    // Serve static files from R2
    let objectName = url.pathname.slice(1) || 'index.html';
    if (objectName.endsWith('/')) {
      objectName += 'index.html';
    }
    
    const object = await env.STATIC_ASSETS.get(objectName);
    
    if (!object) {
      // Try 404.html
      const notFound = await env.STATIC_ASSETS.get('404.html');
      const headers = new Headers();
      applySecurityHeaders(headers, '404.html');
      return new Response(notFound?.body || 'Not Found', { 
        status: 404,
        headers
      });
    }
    
    // Verify content integrity if enabled
    if (securityPlugins.integrity.enabled) {
      const content = await object.text();
      const isValid = await securityPlugins.integrity.verify(objectName, content, env);
      if (!isValid) {
        return new Response('Content integrity check failed', { status: 500 });
      }
    }
    
    const headers = new Headers(object.httpMetadata || {});
    
    // Apply security headers plugin
    applySecurityHeaders(headers, objectName);
    
    return new Response(object.body, {
      headers,
      status: 200,
    });
  }
};

function applySecurityHeaders(headers, filename) {
  // Apply security headers plugin
  if (securityPlugins.headers.enabled) {
    securityPlugins.headers.apply(headers, securityPlugins.headers.config);
  }
  
  // Apply cache plugin
  if (securityPlugins.cache.enabled) {
    securityPlugins.cache.apply(headers, filename, securityPlugins.cache.config);
  }
}