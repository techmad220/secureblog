// Plugin-based security configuration
export const securityPlugins = {
  // Security headers plugin
  headers: {
    enabled: true,
    config: {
      'Content-Security-Policy': {
        'default-src': ["'none'"],
        'base-uri': ["'none'"],
        'form-action': ["'none'"],
        'frame-ancestors': ["'none'"],
        'img-src': ["'self'"],
        'style-src': ["'self'", "'unsafe-inline'"],
        'font-src': ["'self'"]
      },
      'Referrer-Policy': 'no-referrer',
      'Permissions-Policy': 'accelerometer=(), battery=(), camera=(), display-capture=(), geolocation=(), gyroscope=(), microphone=(), payment=(), usb=()',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'same-origin',
      'X-Frame-Options': 'DENY',
      'X-Content-Type-Options': 'nosniff',
      'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload'
    },
    apply(headers, config) {
      Object.entries(config).forEach(([key, value]) => {
        if (key === 'Content-Security-Policy') {
          const csp = Object.entries(value)
            .map(([directive, sources]) => `${directive} ${sources.join(' ')}`)
            .join('; ');
          headers.set(key, csp);
        } else {
          headers.set(key, value);
        }
      });
    }
  },
  
  // Cache control plugin
  cache: {
    enabled: true,
    config: {
      static: {
        extensions: ['css', 'js', 'svg', 'jpg', 'jpeg', 'png', 'webp', 'ico', 'woff', 'woff2'],
        headers: 'public, max-age=31536000, immutable'
      },
      html: {
        extensions: ['html', 'htm'],
        headers: 'public, max-age=3600'
      }
    },
    apply(headers, filename, config) {
      const ext = filename.split('.').pop().toLowerCase();
      for (const [type, settings] of Object.entries(config)) {
        if (settings.extensions.includes(ext)) {
          headers.set('Cache-Control', settings.headers);
          break;
        }
      }
    }
  },
  
  // Rate limiting plugin
  rateLimit: {
    enabled: true,
    config: {
      requests: 30,
      window: 60, // seconds
      blockDuration: 300 // seconds
    },
    clients: new Map(),
    apply(request, config) {
      const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
      const now = Date.now();
      const client = this.clients.get(clientIP) || { requests: [], blocked: 0 };
      
      if (client.blocked > now) {
        return { blocked: true, response: new Response('Too Many Requests', { status: 429 }) };
      }
      
      client.requests = client.requests.filter(time => time > now - config.window * 1000);
      
      if (client.requests.length >= config.requests) {
        client.blocked = now + config.blockDuration * 1000;
        this.clients.set(clientIP, client);
        return { blocked: true, response: new Response('Too Many Requests', { status: 429 }) };
      }
      
      client.requests.push(now);
      this.clients.set(clientIP, client);
      return { blocked: false };
    }
  },
  
  // Content integrity plugin
  integrity: {
    enabled: true,
    config: {
      manifestPath: '/integrity-manifest.json'
    },
    async verify(objectName, content, env) {
      try {
        const manifest = await env.STATIC_ASSETS.get('integrity-manifest.json');
        if (!manifest) return true;
        
        const hashes = JSON.parse(await manifest.text());
        const fileHash = hashes[objectName];
        if (!fileHash) return true;
        
        const encoder = new TextEncoder();
        const data = encoder.encode(content);
        const hashBuffer = await crypto.subtle.digest('SHA-256', data);
        const hashHex = Array.from(new Uint8Array(hashBuffer))
          .map(b => b.toString(16).padStart(2, '0'))
          .join('');
        
        return hashHex === fileHash;
      } catch (e) {
        return true; // Fail open for availability
      }
    }
  }
};

// Plugin loader
export function loadPlugin(name) {
  return securityPlugins[name];
}

// Apply all enabled plugins
export async function applyPlugins(request, response, env, ctx) {
  const enabledPlugins = Object.entries(securityPlugins)
    .filter(([_, plugin]) => plugin.enabled);
  
  for (const [name, plugin] of enabledPlugins) {
    if (plugin.apply) {
      const result = await plugin.apply.call(plugin, request, response, env, ctx);
      if (result?.blocked) {
        return result.response;
      }
    }
  }
  
  return response;
}