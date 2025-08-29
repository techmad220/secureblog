#!/usr/bin/env bash
# E2E link/asset crawler - ensures all hrefs and srcs exist
set -Eeuo pipefail
IFS=$'\n\t'

DIST="${1:-dist}"
FAIL=0

if [[ ! -d "$DIST" ]]; then
  printf 'ERROR: dist directory not found: %s\n' "$DIST" >&2
  exit 2
fi

printf '🔍 E2E Link & Asset Check\n'

# Extract all hrefs and srcs from HTML files
LINKS_FILE=$(mktemp)
trap 'rm -f "$LINKS_FILE"' EXIT

# Find all HTML files
find "$DIST" -type f -name "*.html" | while read -r html_file; do
  # Extract href and src attributes (excluding mailto:, tel:, https://, http://, //)
  grep -oE '(href|src)="[^"]*"' "$html_file" 2>/dev/null | \
    sed 's/^[^"]*"//; s/"$//' | \
    grep -v '^mailto:' | \
    grep -v '^tel:' | \
    grep -v '^https://' | \
    grep -v '^http://' | \
    grep -v '^//' | \
    grep -v '^#' | \
    grep -v '^$' | \
    while read -r link; do
      echo "$html_file:$link"
    done
done > "$LINKS_FILE"

# Check each link exists
if [[ -s "$LINKS_FILE" ]]; then
  while IFS=: read -r html_file link; do
    # Resolve relative paths
    if [[ "$link" == /* ]]; then
      # Absolute path from site root
      target="$DIST${link}"
    else
      # Relative path from HTML file location
      dir=$(dirname "$html_file")
      target="$dir/$link"
    fi
    
    # Remove fragment identifiers
    target="${target%%#*}"
    
    # Remove query strings
    target="${target%%\?*}"
    
    # Check if file exists
    if [[ ! -e "$target" ]]; then
      # Try adding index.html for directories
      if [[ ! -e "${target}/index.html" ]]; then
        printf 'FAIL: Broken link in %s -> %s (resolved: %s)\n' \
          "${html_file#$DIST/}" "$link" "${target#$DIST/}" >&2
        FAIL=1
      fi
    fi
  done < "$LINKS_FILE"
fi

# Check for orphaned files (files not linked from anywhere)
printf '\n📊 Coverage check...\n'
ORPHANS=0
find "$DIST" -type f \( -name "*.html" -o -name "*.css" -o -name "*.xml" -o -name "*.txt" \) | while read -r file; do
  # Skip special files
  basename=$(basename "$file")
  if [[ "$basename" == "robots.txt" ]] || \
     [[ "$basename" == "sitemap.xml" ]] || \
     [[ "$basename" == "rss.xml" ]] || \
     [[ "$basename" == ".integrity.manifest" ]] || \
     [[ "$basename" == "index.html" ]]; then
    continue
  fi
  
  # Check if file is referenced anywhere
  rel_path="${file#$DIST/}"
  if ! grep -q "$rel_path" "$LINKS_FILE" 2>/dev/null; then
    printf 'INFO: Orphaned file (not linked): %s\n' "$rel_path"
    ORPHANS=$((ORPHANS + 1))
  fi
done

# Summary
printf '\n'
if [[ $FAIL -eq 1 ]]; then
  printf '❌ E2E check FAILED - broken links detected\n' >&2
  exit 1
fi

if [[ $ORPHANS -gt 0 ]]; then
  printf '⚠️  Found %d orphaned files (not critical)\n' "$ORPHANS"
fi

printf '✅ E2E check PASSED - all links valid\n'