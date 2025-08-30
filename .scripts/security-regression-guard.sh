#!/usr/bin/env bash
# Fail the build if any JavaScript or risky embeds are found.
# Scans templates/ and dist/ by default.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")"
SCAN_PATHS=("${ROOT}/templates" "${ROOT}/dist")

if [[ $# -gt 0 ]]; then
  SCAN_PATHS=("$@")
fi

echo "[guard] scanning paths:"
printf '  - %s\n' "${SCAN_PATHS[@]}"

# Patterns that should never appear in a zero-JS site.
BAD_HTML_REGEX='(<script\b|javascript:|on[a-z]+\s*=|<iframe\b|<object\b|<embed\b|<applet\b|<canvas\b|<audio\b|<video\b|<form\b|fetch\s*\(|navigator\.|document\.cookie|<svg[^>]*onload=)'
BAD_CSS_REGEX='url\s*\(\s*["'\'']?\s*javascript:|@import'

FOUND=0

scan_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    # HTML/XML/RSS
    if grep -RInE --include='*.htm' --include='*.html' --include='*.xml' --include='*.rss' "$BAD_HTML_REGEX" "$dir" >/tmp/guard_html_hits 2>/dev/null; then
      echo "[guard] ❌ forbidden HTML/JS patterns found:"
      cat /tmp/guard_html_hits
      FOUND=1
    fi
    # CSS
    if grep -RInE --include='*.css' "$BAD_CSS_REGEX" "$dir" >/tmp/guard_css_hits 2>/dev/null; then
      echo "[guard] ❌ forbidden CSS patterns found:"
      cat /tmp/guard_css_hits
      FOUND=1
    fi
  fi
}

for p in "${SCAN_PATHS[@]}"; do
  scan_dir "$p"
done

# Check security headers file exists and has a locked-down CSP.
HEADERS_FILE="${ROOT}/security-headers.conf"
if [[ -f "$HEADERS_FILE" ]]; then
  if ! grep -Eq "^Content-Security-Policy:\s*default-src 'none';" "$HEADERS_FILE"; then
    echo "[guard] ❌ CSP not strict enough in security-headers.conf (expect \"default-src 'none';\")."
    FOUND=1
  fi
else
  echo "[guard] ⚠️ security-headers.conf not found; skipping CSP check."
fi

if [[ "$FOUND" -ne 0 ]]; then
  echo "[guard] failing build due to security regressions."
  exit 1
fi

echo "[guard] ✅ no forbidden constructs detected."