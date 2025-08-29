#!/usr/bin/env bash
# Strict no-JS + no-inline-handlers gate for generated site
# PRODUCTION: Run on dist/ output ONLY (not source files)
set -Eeuo pipefail
IFS=$'\n\t'

DIST="${1:-dist}"
FAIL=0

if [[ ! -d "$DIST" ]]; then
  printf 'ERROR: dist directory not found: %s\n' "$DIST" >&2
  exit 2
fi

# 1. Reject ANY .js files
if find "$DIST" -type f -name "*.js" -print -quit | grep -q .; then
  printf 'FAIL: JavaScript files detected in %s\n' "$DIST" >&2
  find "$DIST" -type f -name "*.js" -print >&2
  FAIL=1
fi

# 2. Reject <script> tags in HTML
if grep -r '<script' "$DIST" --include="*.html" 2>/dev/null; then
  printf 'FAIL: <script> tags found in HTML\n' >&2
  FAIL=1
fi

# 3. Reject inline event handlers (onclick, onload, etc.)
if grep -rE '\bon(click|load|error|change|submit|keydown|keyup|mousedown|mouseup|mouseover|mouseout|focus|blur|input|scroll|resize|select|touchstart|touchend|touchmove|dragstart|dragend|drop|hashchange|popstate|storage|unload|beforeunload|pageshow|pagehide|animationstart|animationend|transitionend|message|online|offline|wheel|contextmenu|copy|cut|paste|play|pause|ended|volumechange|seeking|seeked|ratechange|durationchange|loadstart|progress|suspend|abort|stalled|loadedmetadata|loadeddata|waiting|playing|canplay|canplaythrough|timeupdate)\s*=' "$DIST" --include="*.html" 2>/dev/null; then
  printf 'FAIL: Inline event handlers detected\n' >&2
  FAIL=1
fi

# 4. Reject javascript: and data: URIs in href/src attributes
if grep -rE '(href|src)\s*=\s*["'\'']?\s*(javascript|data):' "$DIST" --include="*.html" 2>/dev/null; then
  printf 'FAIL: javascript: or data: URIs found\n' >&2
  FAIL=1
fi

# 5. Reject WebAssembly files
if find "$DIST" -type f -name "*.wasm" -print -quit | grep -q .; then
  printf 'FAIL: WebAssembly files detected in %s\n' "$DIST" >&2
  find "$DIST" -type f -name "*.wasm" -print >&2
  FAIL=1
fi

# 6. Reject service worker registration
if grep -r 'navigator\.serviceWorker' "$DIST" --include="*.html" 2>/dev/null; then
  printf 'FAIL: Service worker registration detected\n' >&2
  FAIL=1
fi

# 7. Reject import/export statements (ES6 modules)
if grep -rE '^\s*(import|export)\s+' "$DIST" --include="*.html" 2>/dev/null; then
  printf 'FAIL: ES6 module syntax detected\n' >&2
  FAIL=1
fi

if [[ $FAIL -eq 1 ]]; then
  printf '\n❌ Security regression guard FAILED\n' >&2
  exit 1
fi

printf '✅ Security regression guard PASSED (no JS/handlers in %s)\n' "$DIST"