#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-dist}"
[ -d "$ROOT" ] || { echo "dist dir '$ROOT' not found"; exit 1; }

fail() { echo "SECURITY REGRESSION: $*"; exit 2; }

# 1) Absolutely no script tags
if grep -RIl --include='*.html' -E '<\s*script\b' "$ROOT"; then
  fail "<script> tag detected"
fi

# 2) No inline event handlers (onclick=, onload=, etc.)
if grep -RIl --include='*.html' -E '\son[a-z]+\s*=' "$ROOT"; then
  fail "inline event handler detected"
fi

# 3) No javascript: URLs
if grep -RIl --include='*.{html,css}' -E 'javascript:' "$ROOT"; then
  fail "javascript: URL detected"
fi

# 4) No iframes or srcdoc
if grep -RIl --include='*.html' -E '<\s*iframe\b|srcdoc=' "$ROOT"; then
  fail "iframe/srcdoc detected"
fi

# 5) CSP must be maximal (default-src 'none'; no script-src)
CSP_EXPECT="default-src 'none'"
while IFS= read -r -d '' f; do
  # Allow meta http-equiv CSP or header injection via your edge/nginx
  if grep -qi '<meta[^>]*http-equiv=["'\'']Content-Security-Policy["'\'']' "$f"; then
    grep -qi "$CSP_EXPECT" "$f" || fail "CSP meta not strict in $f"
  fi
done < <(find "$ROOT" -type f -name '*.html' -print0)

echo "[OK] Security regression guard passed"