#!/bin/bash
# Content Hash Assets Script
# Implements strict cache integrity with content-hashed paths
# Ensures immutable, content-addressed assets with long cache times

set -euo pipefail

DIST_DIR="${1:-dist}"
ASSETS_DIR="${DIST_DIR}/assets"
MANIFEST_FILE="${DIST_DIR}/asset-manifest.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Create assets directory if it doesn't exist
mkdir -p "${ASSETS_DIR}"

# Initialize manifest
echo "{" > "${MANIFEST_FILE}"
echo '  "version": "1.0.0",' >> "${MANIFEST_FILE}"
echo '  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",' >> "${MANIFEST_FILE}"
echo '  "assets": {' >> "${MANIFEST_FILE}"

FIRST_ASSET=true

# Function to hash a file and create content-addressed copy
hash_file() {
    local file="$1"
    local relative_path="${file#${DIST_DIR}/}"
    
    # Skip if already hashed or in assets directory
    if [[ "$file" == *"."*"."* ]] || [[ "$file" == "${ASSETS_DIR}"* ]]; then
        return
    fi
    
    # Calculate SHA-256 hash
    local hash=$(sha256sum "$file" | cut -d' ' -f1)
    local hash_short="${hash:0:16}"
    
    # Get file extension
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    local name="${filename%.*}"
    
    # Create hashed filename
    local hashed_name="${name}.${hash_short}.${extension}"
    local hashed_path="${ASSETS_DIR}/${hashed_name}"
    
    # Copy file to hashed location
    cp "$file" "$hashed_path"
    
    # Set proper permissions (read-only)
    chmod 444 "$hashed_path"
    
    # Add to manifest
    if [ "$FIRST_ASSET" = false ]; then
        echo "," >> "${MANIFEST_FILE}"
    fi
    FIRST_ASSET=false
    
    echo -n "    \"${relative_path}\": {" >> "${MANIFEST_FILE}"
    echo -n "\"hash\": \"${hash}\", " >> "${MANIFEST_FILE}"
    echo -n "\"path\": \"assets/${hashed_name}\", " >> "${MANIFEST_FILE}"
    echo -n "\"size\": $(stat -c%s "$file"), " >> "${MANIFEST_FILE}"
    echo -n "\"type\": \"${extension}\"}" >> "${MANIFEST_FILE}"
    
    log_info "Hashed: ${relative_path} -> assets/${hashed_name}"
    
    # Update references in HTML files
    update_references "$relative_path" "assets/${hashed_name}"
}

# Function to update references in HTML/CSS files
update_references() {
    local old_path="$1"
    local new_path="$2"
    
    # Escape special characters for sed
    local escaped_old=$(echo "$old_path" | sed 's/[[\.*^$()+?{|]/\\&/g')
    local escaped_new=$(echo "$new_path" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # Update all HTML files
    find "${DIST_DIR}" -name "*.html" -type f | while read -r html_file; do
        sed -i "s|${escaped_old}|${escaped_new}|g" "$html_file"
    done
    
    # Update all CSS files
    find "${DIST_DIR}" -name "*.css" -type f | while read -r css_file; do
        sed -i "s|${escaped_old}|${escaped_new}|g" "$css_file"
    done
}

# Process CSS files
log_info "Processing CSS files..."
find "${DIST_DIR}" -name "*.css" -type f ! -path "${ASSETS_DIR}/*" | while read -r css_file; do
    hash_file "$css_file"
done

# Process JavaScript files
log_info "Processing JavaScript files..."
find "${DIST_DIR}" -name "*.js" -type f ! -path "${ASSETS_DIR}/*" | while read -r js_file; do
    hash_file "$js_file"
done

# Process image files
log_info "Processing image files..."
find "${DIST_DIR}" \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.svg" -o -name "*.webp" \) -type f ! -path "${ASSETS_DIR}/*" | while read -r img_file; do
    hash_file "$img_file"
done

# Process font files
log_info "Processing font files..."
find "${DIST_DIR}" \( -name "*.woff" -o -name "*.woff2" -o -name "*.ttf" -o -name "*.eot" \) -type f ! -path "${ASSETS_DIR}/*" | while read -r font_file; do
    hash_file "$font_file"
done

# Close manifest JSON
echo "" >> "${MANIFEST_FILE}"
echo "  }," >> "${MANIFEST_FILE}"
echo '  "integrity": {' >> "${MANIFEST_FILE}"
echo '    "algorithm": "sha256",' >> "${MANIFEST_FILE}"
echo '    "required": true' >> "${MANIFEST_FILE}"
echo "  }" >> "${MANIFEST_FILE}"
echo "}" >> "${MANIFEST_FILE}"

# Generate integrity report
log_info "Generating integrity report..."
INTEGRITY_FILE="${DIST_DIR}/integrity.txt"
{
    echo "Asset Integrity Report"
    echo "====================="
    echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""
    echo "SHA-256 Checksums:"
    echo "------------------"
    find "${ASSETS_DIR}" -type f -exec sha256sum {} \; | sed "s|${DIST_DIR}/||g"
} > "${INTEGRITY_FILE}"

# Create nginx configuration for immutable caching
log_info "Creating nginx cache configuration..."
cat > "${DIST_DIR}/nginx-cache.conf" << 'EOF'
# Immutable asset caching configuration
# Content-addressed assets with long cache times

# Assets with hash in filename - immutable
location ~ ^/assets/.*\.[0-9a-f]{16}\.(css|js|png|jpg|jpeg|gif|svg|webp|woff|woff2|ttf|eot)$ {
    # Immutable caching - 1 year
    expires 365d;
    add_header Cache-Control "public, immutable, max-age=31536000";
    
    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    
    # Integrity verification
    add_header X-Asset-Hash "$1" always;
    
    # CORS for fonts
    if ($request_filename ~* \.(woff|woff2|ttf|eot)$) {
        add_header Access-Control-Allow-Origin "*";
    }
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    
    # Brotli compression
    brotli on;
    brotli_types text/css application/javascript application/json image/svg+xml;
}

# HTML files - must revalidate
location ~ \.(html|htm)$ {
    expires 0;
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
    
    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # CSP with hash verification
    add_header Content-Security-Policy "default-src 'none'; script-src 'self' 'sha256-SCRIPT_HASH'; style-src 'self' 'sha256-STYLE_HASH'; img-src 'self' data:; font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none';" always;
}

# Asset manifest - short cache
location = /asset-manifest.json {
    expires 5m;
    add_header Cache-Control "public, max-age=300, must-revalidate";
    add_header X-Content-Type-Options "nosniff" always;
}

# Integrity report - no cache
location = /integrity.txt {
    expires 0;
    add_header Cache-Control "no-cache, no-store";
    add_header Content-Type "text/plain; charset=utf-8";
}
EOF

# Create Cloudflare Worker for cache integrity
log_info "Creating Cloudflare Worker for cache integrity..."
cat > "${DIST_DIR}/cache-integrity-worker.js" << 'EOF'
// Cloudflare Worker for Cache Integrity
// Ensures content-hashed assets are served with proper headers

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    // Check if this is a hashed asset
    const hashedAssetRegex = /^\/assets\/.*\.[0-9a-f]{16}\.(css|js|png|jpg|jpeg|gif|svg|webp|woff|woff2|ttf|eot)$/;
    
    if (hashedAssetRegex.test(path)) {
      // Fetch the asset
      const response = await fetch(request);
      
      // Clone response to modify headers
      const newResponse = new Response(response.body, response);
      
      // Set immutable caching headers
      newResponse.headers.set('Cache-Control', 'public, immutable, max-age=31536000');
      newResponse.headers.set('X-Cache-Status', 'immutable');
      
      // Add integrity header
      const hashMatch = path.match(/\.([0-9a-f]{16})\./);
      if (hashMatch) {
        newResponse.headers.set('X-Content-Hash', hashMatch[1]);
      }
      
      // Add security headers
      newResponse.headers.set('X-Content-Type-Options', 'nosniff');
      newResponse.headers.set('X-Frame-Options', 'DENY');
      
      // Cache in Cloudflare edge for 1 year
      ctx.waitUntil(
        caches.default.put(request, newResponse.clone())
      );
      
      return newResponse;
    }
    
    // For HTML files, ensure no caching
    if (path.endsWith('.html') || path === '/') {
      const response = await fetch(request);
      const newResponse = new Response(response.body, response);
      
      // Prevent caching
      newResponse.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      newResponse.headers.set('Pragma', 'no-cache');
      newResponse.headers.set('Expires', '0');
      
      return newResponse;
    }
    
    // Default: pass through
    return fetch(request);
  }
};
EOF

# Remove original unhashed files (keeping only hashed versions)
log_info "Cleaning up unhashed assets..."
find "${DIST_DIR}" -name "*.css" -o -name "*.js" -type f ! -path "${ASSETS_DIR}/*" -delete

# Set proper permissions on all files
find "${DIST_DIR}" -type f -exec chmod 644 {} \;
find "${DIST_DIR}" -type d -exec chmod 755 {} \;

# Verify integrity
log_info "Verifying asset integrity..."
ERRORS=0
while IFS= read -r line; do
    if [[ "$line" =~ ^([a-f0-9]{64})[[:space:]]+(.+)$ ]]; then
        hash="${BASH_REMATCH[1]}"
        file="${BASH_REMATCH[2]}"
        
        if [ -f "${DIST_DIR}/${file}" ]; then
            actual_hash=$(sha256sum "${DIST_DIR}/${file}" | cut -d' ' -f1)
            if [ "$hash" != "$actual_hash" ]; then
                log_error "Integrity check failed for ${file}"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    fi
done < <(grep -E '^[a-f0-9]{64}' "${INTEGRITY_FILE}")

if [ $ERRORS -eq 0 ]; then
    log_info "✅ All assets have been successfully hashed and verified"
    log_info "📄 Manifest: ${MANIFEST_FILE}"
    log_info "🔒 Integrity: ${INTEGRITY_FILE}"
    log_info "⚡ Cache config: ${DIST_DIR}/nginx-cache.conf"
else
    log_error "❌ Asset integrity verification failed with $ERRORS errors"
fi
EOF

chmod +x scripts/content-hash-assets.sh