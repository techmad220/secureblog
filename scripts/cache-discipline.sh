#!/usr/bin/env bash
# cache-discipline.sh - Implement immutable asset caching with content hashing
set -euo pipefail

BUILD_DIR="${1:-dist/public}"
ASSETS_DIR="$BUILD_DIR/assets"
MANIFEST_FILE="$BUILD_DIR/asset-manifest.json"

echo "🗂️ Implementing Cache Discipline with Immutable Assets"
echo "======================================================"
echo "Build directory: $BUILD_DIR"
echo ""

# Create assets directory if it doesn't exist
mkdir -p "$ASSETS_DIR"

# Generate content hashes and create immutable filenames
echo "🔍 Processing assets for immutable caching..."

declare -A asset_map
manifest_json="{"

process_files() {
    local pattern="$1"
    local file_type="$2"
    
    find "$BUILD_DIR" -name "$pattern" -not -path "*/assets/*" -type f | while read -r file; do
        if [ ! -f "$file" ]; then
            continue
        fi
        
        # Generate SHA-256 hash of file content
        file_hash=$(sha256sum "$file" | cut -d' ' -f1 | head -c 10)
        
        # Get relative path and filename
        rel_path=$(realpath --relative-to="$BUILD_DIR" "$file")
        filename=$(basename "$file")
        dirname=$(dirname "$rel_path")
        
        # Extract filename and extension
        if [[ "$filename" == *.* ]]; then
            name="${filename%.*}"
            ext="${filename##*.}"
            hashed_name="${name}-${file_hash}.${ext}"
        else
            name="$filename"
            ext=""
            hashed_name="${name}-${file_hash}"
        fi
        
        # Create hashed filename
        hashed_path="assets/$hashed_name"
        hashed_full_path="$BUILD_DIR/$hashed_path"
        
        # Copy file to hashed location
        cp "$file" "$hashed_full_path"
        
        # Store mapping for later reference
        echo "$rel_path -> $hashed_path"
        
        # Add to manifest (will be processed later)
        echo "\"$rel_path\": \"/$hashed_path\"" >> "$BUILD_DIR/.asset-map.tmp"
    done
}

# Process different asset types
echo "📄 Processing CSS files..."
process_files "*.css" "css"

echo "🖼️ Processing image files..."  
process_files "*.png" "image"
process_files "*.jpg" "image"
process_files "*.jpeg" "image" 
process_files "*.gif" "image"
process_files "*.svg" "image"
process_files "*.webp" "image"
process_files "*.ico" "image"

echo "🔤 Processing font files..."
process_files "*.woff" "font"
process_files "*.woff2" "font"
process_files "*.ttf" "font"
process_files "*.eot" "font"

# JavaScript should not exist in our zero-JS build, but check anyway
if find "$BUILD_DIR" -name "*.js" -not -path "*/assets/*" -type f | grep -q .; then
    echo "❌ CRITICAL: JavaScript files found in zero-JS build!"
    find "$BUILD_DIR" -name "*.js" -not -path "*/assets/*" -type f
    exit 1
fi

# Create asset manifest
echo "📋 Creating asset manifest..."
if [ -f "$BUILD_DIR/.asset-map.tmp" ]; then
    {
        echo "{"
        sed 's/$/,/' "$BUILD_DIR/.asset-map.tmp" | sed '$ s/,$//'
        echo "}"
    } > "$MANIFEST_FILE"
    rm "$BUILD_DIR/.asset-map.tmp"
else
    echo "{}" > "$MANIFEST_FILE"
fi

# Update HTML files to use hashed asset names
echo "🔗 Updating HTML files with hashed asset references..."
find "$BUILD_DIR" -name "*.html" -type f | while read -r html_file; do
    echo "Processing $(basename "$html_file")..."
    
    # Read asset manifest and update references
    if [ -f "$MANIFEST_FILE" ] && [ -s "$MANIFEST_FILE" ]; then
        # Use jq to process the manifest and update HTML
        jq -r 'to_entries[] | "\(.key) \(.value)"' "$MANIFEST_FILE" | while read -r original_path hashed_path; do
            if [ -n "$original_path" ] && [ -n "$hashed_path" ]; then
                # Update references in HTML
                sed -i "s|=\"$original_path\"|=\"$hashed_path\"|g" "$html_file"
                sed -i "s|=\"/$original_path\"|=\"$hashed_path\"|g" "$html_file"
                sed -i "s|url($original_path)|url($hashed_path)|g" "$html_file"
                sed -i "s|url(/$original_path)|url($hashed_path)|g" "$html_file"
            fi
        done
    fi
done

# Generate .htaccess for Apache (if needed)
echo "📝 Generating .htaccess for immutable caching..."
cat > "$BUILD_DIR/.htaccess" << 'EOF'
# Immutable asset caching - Fort Knox level
<IfModule mod_headers.c>
    # Cache hashed assets for 1 year (immutable)
    <FilesMatch "\.(css|js|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)-[a-f0-9]{10}\.(css|js|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)$">
        Header set Cache-Control "public, max-age=31536000, immutable"
        Header set ETag ""
        Header unset Last-Modified
    </FilesMatch>
    
    # HTML files - no cache
    <FilesMatch "\.html$">
        Header set Cache-Control "no-cache, no-store, must-revalidate"
        Header set Pragma "no-cache"
        Header set Expires "0"
    </FilesMatch>
    
    # Manifest files - short cache
    <FilesMatch "\.(json|xml)$">
        Header set Cache-Control "public, max-age=300"
    </FilesMatch>
    
    # Security headers
    Header always set X-Frame-Options "DENY"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Content-Security-Policy "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'"
</IfModule>

# Gzip compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/json
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
</IfModule>
EOF

# Generate nginx config
echo "📝 Generating nginx config for immutable caching..."
cat > "$BUILD_DIR/nginx-cache.conf" << 'EOF'
# Immutable asset caching configuration for nginx
location ~* \.(css|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)-[a-f0-9]{10}\.(css|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)$ {
    # Cache hashed assets for 1 year (immutable)
    expires 1y;
    add_header Cache-Control "public, immutable";
    add_header X-Cache-Status "IMMUTABLE";
    
    # Remove ETag for immutable content
    etag off;
    
    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    
    # Gzip compression
    gzip_static on;
    gzip_vary on;
}

# HTML files - no cache
location ~* \.html$ {
    expires -1;
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
    add_header X-Cache-Status "NO-CACHE";
    
    # Security headers for HTML
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'" always;
}

# Manifest and API files
location ~* \.(json|xml)$ {
    expires 5m;
    add_header Cache-Control "public, max-age=300";
    add_header X-Cache-Status "SHORT-CACHE";
}

# Fallback for other assets (non-hashed)
location ~* \.(css|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)$ {
    expires 1h;
    add_header Cache-Control "public, max-age=3600";
    add_header X-Cache-Status "STANDARD";
    
    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
}
EOF

# Create cache validation script
echo "📝 Creating cache validation script..."
cat > "$BUILD_DIR/validate-cache.sh" << 'EOF'
#!/usr/bin/env bash
# validate-cache.sh - Validate cache discipline implementation
set -euo pipefail

SITE_URL="${1:-https://secureblog.com}"

echo "🔍 Validating Cache Discipline Implementation"
echo "============================================="
echo "Site URL: $SITE_URL"
echo ""

# Test immutable assets
echo "Testing immutable asset caching..."
immutable_assets=$(find assets -name "*-[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9].*" 2>/dev/null || true)

if [ -n "$immutable_assets" ]; then
    echo "$immutable_assets" | while read -r asset; do
        echo "Testing: $asset"
        headers=$(curl -sI "$SITE_URL/$asset" || echo "")
        
        if echo "$headers" | grep -qi "cache-control.*immutable"; then
            echo "✅ Immutable cache header found"
        elif echo "$headers" | grep -qi "cache-control.*max-age=31536000"; then
            echo "✅ Long-term cache header found"
        else
            echo "❌ Missing immutable/long-term cache headers"
        fi
        
        if echo "$headers" | grep -qi "etag"; then
            echo "⚠️ ETag header found (should be removed for immutable content)"
        fi
        echo ""
    done
else
    echo "⚠️ No hashed assets found"
fi

# Test HTML caching
echo "Testing HTML cache headers..."
html_headers=$(curl -sI "$SITE_URL/" || echo "")
if echo "$html_headers" | grep -qi "cache-control.*no-cache"; then
    echo "✅ HTML no-cache header found"
else
    echo "❌ HTML should have no-cache headers"
fi

# Test security headers
echo "Testing security headers..."
if echo "$html_headers" | grep -qi "content-security-policy"; then
    echo "✅ CSP header found"
else
    echo "⚠️ CSP header missing"
fi

if echo "$html_headers" | grep -qi "x-frame-options.*deny"; then
    echo "✅ X-Frame-Options header found"
else
    echo "⚠️ X-Frame-Options header missing"
fi

echo "Cache validation complete!"
EOF

chmod +x "$BUILD_DIR/validate-cache.sh"

# Generate cache report
echo "📊 Generating cache discipline report..."
{
    echo "# Cache Discipline Report"
    echo "========================"
    echo ""
    echo "**Generated:** $(date)"
    echo "**Build Directory:** $BUILD_DIR"
    echo ""
    echo "## Asset Processing Summary"
    echo ""
    
    total_assets=$(find "$ASSETS_DIR" -type f 2>/dev/null | wc -l)
    echo "- **Total Hashed Assets:** $total_assets"
    
    if [ -f "$MANIFEST_FILE" ]; then
        mappings=$(jq '. | length' "$MANIFEST_FILE")
        echo "- **Asset Mappings:** $mappings"
    fi
    
    echo ""
    echo "## Cache Strategy"
    echo ""
    echo "- **Immutable Assets:** 1 year cache (31536000s) with immutable flag"
    echo "- **HTML Files:** No cache (no-cache, no-store, must-revalidate)"
    echo "- **Manifest Files:** 5 minute cache (300s)"
    echo "- **Security Headers:** Applied to all responses"
    echo ""
    echo "## File Structure"
    echo ""
    echo "```"
    find "$BUILD_DIR" -type f | head -20 | sed 's|^|  |'
    echo "```"
    echo ""
    echo "## Validation"
    echo ""
    echo "Run \`./validate-cache.sh https://your-domain.com\` to validate implementation."
    
} > "$BUILD_DIR/CACHE-REPORT.md"

# Clean up original non-hashed files (keep HTML)
echo "🧹 Cleaning up original asset files..."
find "$BUILD_DIR" -name "*.css" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.png" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.jpg" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.jpeg" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.gif" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.svg" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.ico" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.woff*" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.ttf" -not -path "*/assets/*" -type f -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.eot" -not -path "*/assets/*" -type f -delete 2>/dev/null || true

echo ""
echo "✅ Cache Discipline Implementation Complete!"
echo "==========================================="
echo ""
echo "📁 Generated Files:"
echo "  - $MANIFEST_FILE (asset mappings)"
echo "  - $BUILD_DIR/.htaccess (Apache config)"
echo "  - $BUILD_DIR/nginx-cache.conf (nginx config)"
echo "  - $BUILD_DIR/validate-cache.sh (validation script)"
echo "  - $BUILD_DIR/CACHE-REPORT.md (detailed report)"
echo ""
echo "🗂️ Assets processed: $(find "$ASSETS_DIR" -type f | wc -l) files"
echo ""
echo "🔍 Next Steps:"
echo "  1. Deploy with appropriate web server config"
echo "  2. Run validation script after deployment"
echo "  3. Monitor cache hit rates"
echo "  4. Verify immutable headers in production"
echo ""
echo "🚀 Immutable caching is now active!"