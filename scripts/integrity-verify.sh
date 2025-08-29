#!/usr/bin/env bash
# Verify dist/ content matches .integrity.manifest
# Usage: scripts/integrity-verify.sh [DIST_DIR]
set -Eeuo pipefail
IFS=$'\n\t'

DIST="${1:-dist}"
MANIFEST="$DIST/.integrity.manifest"

if [[ ! -d "$DIST" ]]; then
  printf 'ERROR: dist directory not found: %s\n' "$DIST" >&2
  exit 2
fi
if [[ ! -f "$MANIFEST" ]]; then
  printf 'ERROR: manifest not found: %s\n' "$MANIFEST" >&2
  exit 3
fi

( cd "$DIST"
  sha256sum --quiet --check ".integrity.manifest"
)
printf 'Integrity verify: PASS (%s)\n' "$DIST"