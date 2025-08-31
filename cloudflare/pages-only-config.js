/**
 * Cloudflare Pages Configuration - No Workers, Pure Static
 * Zero logic at edge = zero edge risk
 */

// _headers file for Cloudflare Pages (no Worker needed)
export const headersConfig = `
# Global headers for all paths
/*
  Content-Security-Policy: default-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; block-all-mixed-content; upgrade-insecure-requests
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  X-XSS-Protection: 1; mode=block
  Referrer-Policy: no-referrer
  Permissions-Policy: accelerometer=(), battery=(), camera=(), display-capture=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Resource-Policy: same-origin
  Strict-Transport-Security: max-age=63072000; includeSubDomains; preload

# HTML files - no cache
/*.html
  Cache-Control: no-cache, no-store, must-revalidate
  Pragma: no-cache
  Expires: 0

# Hashed assets - immutable
/*.*.css
  Cache-Control: public, max-age=31536000, immutable
  
/*.*.js
  Cache-Control: public, max-age=31536000, immutable

# Images - long cache
/*.jpg
  Cache-Control: public, max-age=2592000
  
/*.jpeg
  Cache-Control: public, max-age=2592000
  
/*.png
  Cache-Control: public, max-age=2592000
  
/*.gif
  Cache-Control: public, max-age=2592000
  
/*.svg
  Cache-Control: public, max-age=2592000
  
/*.webp
  Cache-Control: public, max-age=2592000

# Fonts - long cache with CORS
/*.woff
  Cache-Control: public, max-age=2592000
  Access-Control-Allow-Origin: *
  
/*.woff2
  Cache-Control: public, max-age=2592000
  Access-Control-Allow-Origin: *
  
/*.ttf
  Cache-Control: public, max-age=2592000
  Access-Control-Allow-Origin: *
  
/*.eot
  Cache-Control: public, max-age=2592000
  Access-Control-Allow-Origin: *
`;

// _redirects file for Cloudflare Pages
export const redirectsConfig = `
# Block executable extensions
/*.php 404
/*.asp 404
/*.aspx 404
/*.jsp 404
/*.cgi 404
/*.pl 404
/*.py 404
/*.rb 404
/*.sh 404
/*.exe 404
/*.dll 404
/*.bat 404
/*.cmd 404
/*.ps1 404

# Block JavaScript files (shouldn't exist)
/*.js 404
/*.mjs 404
/*.jsx 404
/*.ts 404
/*.tsx 404

# Block hidden files
/.* 404

# Security.txt exception
/.well-known/security.txt /.well-known/security.txt 200
`;

// Build configuration for Cloudflare Pages
export const buildConfig = {
  "build_command": "./scripts/build-sandbox-hardened.sh",
  "build_output_directory": "dist",
  "node_version": "20",
  "environment_variables": {
    "NODE_ENV": "production",
    "NO_JS": "true",
    "HERMETIC": "true"
  }
};

// Deployment script for Pages (no Worker)
export const deployScript = `#!/bin/bash
# Deploy to Cloudflare Pages - Static Only, No Workers

set -euo pipefail

# Verify manifest before deploy
echo "Verifying manifest..."
cd dist
sha256sum -c manifest.sha256 || exit 1
cd ..

# Create _headers file
cat > dist/_headers << 'EOF'
${headersConfig}
EOF

# Create _redirects file
cat > dist/_redirects << 'EOF'
${redirectsConfig}
EOF

# Deploy to Pages (no Worker)
npx wrangler pages deploy dist \
  --project-name=secureblog \
  --branch=main \
  --commit-dirty=false \
  --commit-hash=$GITHUB_SHA \
  --compatibility-date=2024-01-01

echo "✓ Deployed to Cloudflare Pages (static only, no Workers)"
`;

// Verification script
export const verifyDeployment = `#!/bin/bash
# Verify deployment headers and security

DOMAIN="$1"

echo "Verifying deployment..."

# Check headers on main page
HEADERS=$(curl -sI "https://$DOMAIN")

# Verify all security headers
REQUIRED_HEADERS=(
  "content-security-policy"
  "x-frame-options"
  "x-content-type-options"
  "strict-transport-security"
  "referrer-policy"
  "permissions-policy"
  "cross-origin-opener-policy"
  "cross-origin-embedder-policy"
  "cross-origin-resource-policy"
)

for header in "\${REQUIRED_HEADERS[@]}"; do
  if ! echo "$HEADERS" | grep -qi "$header"; then
    echo "ERROR: Missing header: $header"
    exit 1
  fi
done

# Verify no JavaScript
if curl -s "https://$DOMAIN" | grep -E '<script|javascript:|on[a-z]+='; then
  echo "ERROR: JavaScript detected"
  exit 1
fi

# Verify methods blocked
if [ "$(curl -X POST "https://$DOMAIN" -o /dev/null -w "%{http_code}" -s)" != "405" ]; then
  echo "ERROR: POST method not blocked"
  exit 1
fi

echo "✓ All security checks passed"
`;

// Create all configuration files
export function createPagesConfig() {
  const fs = require('fs');
  
  // Write _headers
  fs.writeFileSync('dist/_headers', headersConfig);
  console.log('✓ Created _headers file');
  
  // Write _redirects
  fs.writeFileSync('dist/_redirects', redirectsConfig);
  console.log('✓ Created _redirects file');
  
  // Write wrangler.toml for Pages
  const wranglerConfig = `
name = "secureblog"
compatibility_date = "2024-01-01"

[site]
bucket = "./dist"

[env.production]
route = "secureblog.example.com/*"

# No Workers, Pages only
# workers_dev = false

[build]
command = "./scripts/build-sandbox-hardened.sh"
watch_paths = ["content/**", "templates/**"]

[build.upload]
format = "service-worker"
rules = [
  { type = "CompiledWasm", globs = ["**/*.wasm"], fallthrough = false },
  { type = "Text", globs = ["**/*.txt", "**/*.md"], fallthrough = true },
  { type = "Data", globs = ["**/*.json"], fallthrough = true }
]
`;
  
  fs.writeFileSync('wrangler-pages.toml', wranglerConfig);
  console.log('✓ Created wrangler-pages.toml');
  
  console.log('\n✅ Cloudflare Pages configuration complete');
  console.log('No Workers = No edge logic = Minimal attack surface');
}