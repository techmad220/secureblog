#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-dist}"

# Collect candidate URLs from HTML and CSS (href/src/url())
mapfile -t LINKS < <(grep -RhoE 'href="[^"]+"|src="[^"]+"' "$ROOT" --include '*.html' \
  | sed -E 's/^(href|src)="([^"]+)".*$/\2/' )

mapfile -t CSSLINKS < <(grep -RhoE 'url\(([^)]+)\)' "$ROOT" --include '*.css' \
  | sed -E 's/url\((["'\'']?)([^)"'\'']+)\1\)/\2/g')

missing=0

check_path () {
  local p="$1"
  # Ignore anchors, queries, absolute schemes, mail/tel/data, and rootless fragments
  if [[ "$p" =~ ^(#|\?|mailto:|tel:|data:|https?://) ]]; then
    return 0
  fi
  # Normalize leading slash to ROOT
  local fs="${p#/}"
  # Strip query/fragment
  fs="${fs%%\?*}"
  fs="${fs%%\#*}"

  # Allow trailing slash (index.html)
  if [[ -e "$ROOT/$fs" ]]; then
    return 0
  fi
  if [[ -e "$ROOT/$fs/index.html" ]]; then
    return 0
  fi
  echo "❌ Missing: $p  (looked for: $ROOT/$fs and $ROOT/$fs/index.html)"
  missing=1
}

for l in "${LINKS[@]}"; do check_path "$l"; done
for l in "${CSSLINKS[@]}"; do check_path "$l"; done

if [[ $missing -ne 0 ]]; then
  echo "Link check failed."
  exit 1
fi
echo "✅ Link check passed"