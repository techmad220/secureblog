#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-dist}"

fail=0

# Any <script> tag (strict no-JS)
if grep -RInE '<script\b' "$ROOT" --include '*.html' >/dev/null 2>&1; then
  echo "❌ Found <script> tags in $ROOT"
  grep -RInE '<script\b' "$ROOT" --include '*.html' || true
  fail=1
fi

# Inline event handlers (onclick=, onload=, etc.)
if grep -RInE 'on[a-zA-Z]+\s*=' "$ROOT" --include '*.html' >/dev/null 2>&1; then
  echo "❌ Found inline event handlers (on*) in HTML"
  grep -RInE 'on[a-zA-Z]+\s*=' "$ROOT" --include '*.html' || true
  fail=1
fi

# javascript: URLs
if grep -RInE 'javascript:' "$ROOT" --include '*.html' --include '*.css' >/dev/null 2>&1; then
  echo "❌ Found javascript: URLs"
  grep -RInE 'javascript:' "$ROOT" --include '*.html' --include '*.css' || true
  fail=1
fi

# modulepreload or "as=script" hints
if grep -RInE 'rel=["'\'']modulepreload|as=["'\'']script' "$ROOT" --include '*.html' >/dev/null 2>&1; then
  echo "❌ Found modulepreload/as=script hints"
  grep -RInE 'rel=["'\'']modulepreload|as=["'\'']script' "$ROOT" --include '*.html' || true
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "✅ No-JS guard passed"