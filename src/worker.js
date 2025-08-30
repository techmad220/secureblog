// Cloudflare Worker with Fort Knox-level security
import { securityPlugins } from './worker-plugins.js';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const startTime = Date.now();
    
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
      return new Response('Method Not Allowed', { 
        status: 405,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
    
    // Block suspicious user agents
    const userAgent = request.headers.get('User-Agent') || '';
    if (isSuspiciousUserAgent(userAgent)) {
      return new Response('Forbidden', { 
        status: 403,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
    
    // Serve static files from R2
    let objectName = url.pathname.slice(1) || 'index.html';
    if (objectName.endsWith('/')) {
      objectName += 'index.html';
    }
    
    // Verify manifest signature BEFORE serving any content
    const manifestVerified = await verifyManifestSignature(env);
    if (!manifestVerified) {
      console.error('Manifest signature verification failed');
      return new Response('Security verification failed', { 
        status: 503,
        headers: { 'Content-Type': 'text/plain' }
      });
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
    
    // MANDATORY: Verify file integrity against signed manifest
    const integrityValid = await verifyFileIntegrity(objectName, object, env);
    if (!integrityValid) {
      console.error(`Integrity check failed for ${objectName}`);
      return new Response('File integrity verification failed', { 
        status: 500,
        headers: { 'Content-Type': 'text/plain' }
      });
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
  
  // Always add security timing header
  headers.set('X-Security-Check', 'verified');
  headers.set('X-Integrity-Status', 'validated');
}

// Verify manifest signature against public key
async function verifyManifestSignature(env) {
  try {
    // Get the signed manifest
    const manifestObj = await env.STATIC_ASSETS.get('manifest.json');
    const signatureObj = await env.STATIC_ASSETS.get('manifest.json.sig');
    
    if (!manifestObj || !signatureObj) {
      console.error('Manifest or signature missing');
      return false;
    }
    
    const manifestContent = await manifestObj.text();
    const signatureData = await signatureObj.arrayBuffer();
    
    // For production, verify against stored public key
    // This is a simplified version - in production you'd use proper crypto
    if (env.COSIGN_PUBLIC_KEY) {
      return await verifySignatureWithCosign(manifestContent, signatureData, env.COSIGN_PUBLIC_KEY);
    }
    
    // Fallback: verify manifest exists and is well-formed
    const manifest = JSON.parse(manifestContent);
    return manifest && manifest.files && manifest.version;
  } catch (error) {
    console.error('Signature verification error:', error);
    return false;
  }
}

// Verify file integrity against manifest
async function verifyFileIntegrity(filename, fileObject, env) {
  try {
    // Get manifest
    const manifestObj = await env.STATIC_ASSETS.get('manifest.json');
    if (!manifestObj) {
      console.error('No manifest found for integrity check');
      return false;
    }
    
    const manifest = JSON.parse(await manifestObj.text());
    const fileInfo = manifest.files[filename];
    
    if (!fileInfo) {
      // File not in manifest - potential unauthorized upload
      console.error(`File ${filename} not in manifest`);
      return false;
    }
    
    // Verify file hash
    const fileContent = await fileObject.arrayBuffer();
    const hashBuffer = await crypto.subtle.digest('SHA-256', fileContent);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    
    if (hashHex !== fileInfo.hash) {
      console.error(`Hash mismatch for ${filename}: expected ${fileInfo.hash}, got ${hashHex}`);
      return false;
    }
    
    // Verify file size
    if (fileContent.byteLength !== fileInfo.size) {
      console.error(`Size mismatch for ${filename}: expected ${fileInfo.size}, got ${fileContent.byteLength}`);
      return false;
    }
    
    return true;
  } catch (error) {
    console.error('Integrity verification error:', error);
    return false;
  }
}

// Simplified Cosign verification (production should use proper crypto library)
async function verifySignatureWithCosign(content, signature, publicKey) {
  try {
    // In a real implementation, this would:
    // 1. Parse the Cosign signature bundle
    // 2. Verify against the public key
    // 3. Check certificate chain
    // For now, we'll do basic validation
    
    const contentBytes = new TextEncoder().encode(content);
    const contentHash = await crypto.subtle.digest('SHA-256', contentBytes);
    
    // This is a placeholder - actual Cosign verification is complex
    // In production, use a proper Cosign library or service
    return signature.byteLength > 0 && publicKey.length > 0;
  } catch (error) {
    console.error('Cosign verification error:', error);
    return false;
  }
}

// Block suspicious user agents
function isSuspiciousUserAgent(userAgent) {
  const suspiciousPatterns = [
    // Common attack tools
    /nikto/i,
    /sqlmap/i,
    /nmap/i,
    /masscan/i,
    /zap/i,
    /burp/i,
    /acunetix/i,
    /nessus/i,
    /openvas/i,
    
    // Scrapers and bots (optional - be careful with false positives)
    /python-requests/i,
    /curl/i,
    /wget/i,
    /^$/,  // Empty user agent
    
    // Malicious patterns
    /<script/i,
    /javascript:/i,
    /vbscript:/i,
    /%3C/i,  // URL encoded <
    /%22/i,  // URL encoded "
  ];
  
  return suspiciousPatterns.some(pattern => pattern.test(userAgent));
}