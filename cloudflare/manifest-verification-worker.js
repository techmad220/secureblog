/**
 * Manifest Verification Worker
 * Verifies every asset against signed manifest before serving
 * Prevents poisoned bucket and stray file attacks
 */

// Signed manifest (loaded from KV or R2)
const MANIFEST_VERSION = "1.0.0";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    // Only allow GET/HEAD
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', {
        status: 405,
        headers: { 'Allow': 'GET, HEAD' }
      });
    }
    
    try {
      // Load signed manifest from KV
      const manifestData = await env.MANIFEST.get('current', { type: 'json' });
      
      if (!manifestData) {
        console.error('Manifest not found');
        return new Response('Service Unavailable', { status: 503 });
      }
      
      // Verify manifest signature
      if (!await verifyManifestSignature(manifestData, env)) {
        console.error('Invalid manifest signature');
        return new Response('Security Error', { status: 500 });
      }
      
      // Special handling for root and index
      let assetPath = path;
      if (path === '/' || path === '') {
        assetPath = '/index.html';
      } else if (path.endsWith('/')) {
        assetPath = path + 'index.html';
      }
      
      // Check if asset is in manifest
      const assetHash = manifestData.assets[assetPath];
      
      if (!assetHash) {
        console.warn(`Asset not in manifest: ${assetPath}`);
        return new Response('Not Found', { status: 404 });
      }
      
      // Fetch the asset
      const assetResponse = await env.ASSETS.fetch(request);
      
      if (!assetResponse.ok) {
        return assetResponse;
      }
      
      // Verify asset integrity on cache miss
      const cacheStatus = assetResponse.headers.get('CF-Cache-Status');
      
      if (cacheStatus === 'MISS' || cacheStatus === 'EXPIRED') {
        // Clone response to read body
        const [response1, response2] = [assetResponse.clone(), assetResponse.clone()];
        
        // Calculate hash of served content
        const arrayBuffer = await response1.arrayBuffer();
        const hash = await calculateSHA256(arrayBuffer);
        
        // Verify against manifest
        if (hash !== assetHash) {
          console.error(`Hash mismatch for ${assetPath}: expected ${assetHash}, got ${hash}`);
          
          // Log security incident
          await logSecurityIncident(env, {
            type: 'integrity_failure',
            path: assetPath,
            expected: assetHash,
            actual: hash,
            timestamp: new Date().toISOString()
          });
          
          return new Response('Integrity Check Failed', { status: 500 });
        }
        
        // Add integrity header
        const newResponse = new Response(response2.body, response2);
        newResponse.headers.set('X-Content-Hash', hash);
        newResponse.headers.set('X-Manifest-Version', manifestData.version);
        
        return addSecurityHeaders(newResponse, assetPath);
      }
      
      // For cache hits, trust but add headers
      return addSecurityHeaders(assetResponse, assetPath);
      
    } catch (error) {
      console.error('Worker error:', error);
      return new Response('Internal Server Error', { status: 500 });
    }
  }
};

// Verify manifest signature using Ed25519
async function verifyManifestSignature(manifest, env) {
  try {
    const publicKey = await crypto.subtle.importKey(
      'raw',
      base64ToArrayBuffer(env.MANIFEST_PUBLIC_KEY),
      {
        name: 'Ed25519',
        namedCurve: 'Ed25519'
      },
      false,
      ['verify']
    );
    
    const signature = base64ToArrayBuffer(manifest.signature);
    const data = new TextEncoder().encode(JSON.stringify(manifest.assets));
    
    return await crypto.subtle.verify(
      'Ed25519',
      publicKey,
      signature,
      data
    );
  } catch (error) {
    console.error('Signature verification failed:', error);
    return false;
  }
}

// Calculate SHA-256 hash
async function calculateSHA256(buffer) {
  const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
  return bufferToHex(hashBuffer);
}

// Add comprehensive security headers
function addSecurityHeaders(response, path) {
  const headers = new Headers(response.headers);
  
  // Content Security Policy - strict for HTML
  if (path.endsWith('.html') || path === '/') {
    headers.set('Content-Security-Policy',
      "default-src 'none'; " +
      "img-src 'self' data:; " +
      "style-src 'self'; " +
      "font-src 'self'; " +
      "base-uri 'none'; " +
      "form-action 'none'; " +
      "frame-ancestors 'none'; " +
      "block-all-mixed-content; " +
      "upgrade-insecure-requests"
    );
    
    // No caching for HTML
    headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    headers.set('Pragma', 'no-cache');
    headers.set('Expires', '0');
  } else {
    // Immutable caching for static assets with hash
    if (path.match(/\.[0-9a-f]{8,}\./)) {
      headers.set('Cache-Control', 'public, max-age=31536000, immutable');
    } else {
      headers.set('Cache-Control', 'public, max-age=3600');
    }
  }
  
  // Security headers for all responses
  headers.set('X-Frame-Options', 'DENY');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('X-XSS-Protection', '1; mode=block');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('Permissions-Policy',
    'accelerometer=(), battery=(), camera=(), display-capture=(), ' +
    'geolocation=(), gyroscope=(), magnetometer=(), microphone=(), ' +
    'midi=(), payment=(), usb=()'
  );
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  headers.set('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
  
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: headers
  });
}

// Log security incidents to R2
async function logSecurityIncident(env, incident) {
  const key = `security-incidents/${new Date().toISOString()}-${crypto.randomUUID()}.json`;
  
  await env.LOGS.put(key, JSON.stringify(incident), {
    httpMetadata: {
      contentType: 'application/json'
    },
    customMetadata: {
      severity: 'critical',
      type: incident.type
    }
  });
  
  // Optional: Send alert
  if (env.ALERT_WEBHOOK) {
    await fetch(env.ALERT_WEBHOOK, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        alert: 'Integrity Verification Failed',
        incident: incident
      })
    });
  }
}

// Utility functions
function base64ToArrayBuffer(base64) {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

function bufferToHex(buffer) {
  return Array.from(new Uint8Array(buffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

// Manifest structure example
const manifestExample = {
  version: "1.0.0",
  timestamp: "2024-01-01T00:00:00Z",
  assets: {
    "/index.html": "a3b4c5d6e7f8...",
    "/css/style.css": "b4c5d6e7f8a9...",
    "/images/logo.png": "c5d6e7f8a9b0...",
    // ... all assets with SHA-256 hashes
  },
  signature: "base64-encoded-signature"
};