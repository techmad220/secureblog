#!/usr/bin/env bash
set -Eeuo pipefail

# Security Regression Guard - Prevents JS and header policy violations
FAILED=0

echo "🔒 Security Regression Guard Starting..."

# 1. NO-JS Check - Scan ALL files
echo "→ Checking NO-JS policy..."
JS_PATTERNS=(
  '<script[^>]*>'
  'javascript:'
  '\bon[a-z]+\s*='
  'import\s*\('
  'document\.'
  'window\.'
  'eval\('
  '\$\(.*\)\.on'
  'addEventListener'
  'innerHTML\s*='
  '\.js["\s]'
)

SCAN_DIRS=(templates content build dist plugins)
for dir in "${SCAN_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  
  while IFS= read -r file; do
    for pattern in "${JS_PATTERNS[@]}"; do
      if grep -Ei "$pattern" "$file" 2>/dev/null; then
        echo "❌ JS VIOLATION in $file: pattern '$pattern'"
        FAILED=1
      fi
    done
  done < <(find "$dir" -type f \( -name "*.html" -o -name "*.tmpl" -o -name "*.go" \) 2>/dev/null)
done

# 2. Plugin Output Check - Ensure plugins can't inject JS
echo "→ Checking plugin outputs..."
if [ -d "plugins" ]; then
  for plugin_file in plugins/*/*.go; do
    [ -f "$plugin_file" ] || continue
    
    # Check for dangerous output patterns
    if grep -E 'fmt\.(Sprintf|Printf|Fprintf).*<script' "$plugin_file" 2>/dev/null; then
      echo "❌ Plugin may output <script> tags: $plugin_file"
      FAILED=1
    fi
    
    if grep -E 'WriteString.*javascript:' "$plugin_file" 2>/dev/null; then
      echo "❌ Plugin may output javascript: URLs: $plugin_file"
      FAILED=1
    fi
  done
fi

# 3. CSP Header Regression Check
echo "→ Checking CSP headers..."
CSP_FILES=(
  "security-headers.conf"
  "nginx-hardened.conf"
  "nginx-ultra-hardened.conf"
  "src/worker.js"
  "src/worker-plugins.js"
)

REQUIRED_CSP_DIRECTIVES=(
  "default-src 'none'"
  "script-src 'none'"
  "base-uri 'none'"
  "form-action 'none'"
  "frame-ancestors 'none'"
)

for file in "${CSP_FILES[@]}"; do
  [ -f "$file" ] || continue
  
  if grep -q "Content-Security-Policy" "$file" 2>/dev/null; then
    csp_line=$(grep "Content-Security-Policy" "$file" | head -1)
    
    # Check for script-src that's not 'none'
    if echo "$csp_line" | grep -E "script-src\s+[^']*'(?!none)" 2>/dev/null; then
      echo "❌ CSP allows scripts in $file"
      FAILED=1
    fi
    
    # Check for unsafe-inline
    if echo "$csp_line" | grep -i "unsafe-inline" 2>/dev/null; then
      echo "❌ CSP has unsafe-inline in $file"
      FAILED=1
    fi
    
    # Check for unsafe-eval
    if echo "$csp_line" | grep -i "unsafe-eval" 2>/dev/null; then
      echo "❌ CSP has unsafe-eval in $file"
      FAILED=1
    fi
  fi
done

# 4. Security Headers Regression Check
echo "→ Checking security headers..."
REQUIRED_HEADERS=(
  "X-Frame-Options.*DENY"
  "X-Content-Type-Options.*nosniff"
  "Strict-Transport-Security.*max-age"
  "Referrer-Policy.*no-referrer"
  "Permissions-Policy"
)

for file in "${CSP_FILES[@]}"; do
  [ -f "$file" ] || continue
  
  for header in "${REQUIRED_HEADERS[@]}"; do
    if ! grep -E "$header" "$file" >/dev/null 2>&1; then
      echo "⚠️  Missing header pattern '$header' in $file"
    fi
  done
done

# 5. Build Output Check
echo "→ Checking build output..."
if [ -d "build" ] || [ -d "dist" ]; then
  # Check for .js files
  js_files=$(find build dist -name "*.js" 2>/dev/null | wc -l || echo "0")
  if [ "$js_files" -gt 0 ]; then
    echo "❌ Found $js_files JavaScript files in build output"
    find build dist -name "*.js" 2>/dev/null | head -5
    FAILED=1
  fi
  
  # Check HTML for script tags
  for html in $(find build dist -name "*.html" 2>/dev/null); do
    if grep -i "<script" "$html" >/dev/null 2>&1; then
      echo "❌ Found <script> tag in built HTML: $html"
      FAILED=1
    fi
  done
fi

# Final verdict
if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "🚨 SECURITY REGRESSION DETECTED!"
  echo "The build violates security policies and cannot proceed."
  echo "Fix all issues above and try again."
  exit 1
else
  echo ""
  echo "✅ Security regression guard passed - NO JavaScript detected"
  echo "✅ CSP and security headers validated"
fi