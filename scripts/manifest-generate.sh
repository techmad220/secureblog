#!/usr/bin/env bash
# Create integrity manifest for dist/ (relative paths)
# Usage: scripts/manifest-generate.sh [DIST_DIR]
set -Eeuo pipefail
IFS=$'\n\t'

DIST="${1:-dist}"
MANIFEST="$DIST/.integrity.manifest"

if [[ ! -d "$DIST" ]]; then
  printf 'ERROR: dist directory not found: %s\n' "$DIST" >&2
  exit 2
fi

tmp="$(mktemp)"
( cd "$DIST"
  # Exclude the manifest itself
  find . -type f ! -path './.integrity.manifest' -print0 \
    | sort -z \
    | xargs -0 sha256sum > "$tmp"
  mv "$tmp" ".integrity.manifest"
)
printf 'Wrote %s\n' "$MANIFEST"