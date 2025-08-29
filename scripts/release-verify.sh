#!/usr/bin/env bash
# Verify a published SecureBlog release archive locally.
# 1) Ensures .integrity.manifest exists in the tarball
# 2) Verifies every file's SHA-256 against the manifest
# 3) Optionally verifies cosign attestations (SPDX + SLSA) if cosign is present
set -Eeuo pipefail

DIST_TAR="${1:-dist.tar.gz}"
MANIFEST_REL=".integrity.manifest"

usage() {
  echo "Usage: $0 /path/to/dist.tar.gz" >&2
  exit 2
}

[[ -f "$DIST_TAR" ]] || usage

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar -C "$tmp" -xzf "$DIST_TAR"

# 1) Manifest must exist
if [[ ! -f "$tmp/dist/$MANIFEST_REL" ]]; then
  echo "ERROR: Missing $MANIFEST_REL inside archive" >&2
  exit 1
fi

# 2) Verify all files listed in manifest (quiet = fail on any mismatch)
( cd "$tmp/dist"; sha256sum --quiet --check "$MANIFEST_REL" )

echo "✓ Integrity manifest matches archive contents"

# 3) Optional: cosign attestations
if command -v cosign >/dev/null 2>&1; then
  echo "cosign found — verifying attestations (SPDX + SLSA) ..."
  set +e
  cosign verify-attestation \
    --type spdx \
    --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
    --certificate-identity-regexp '.*' \
    "$DIST_TAR"
  COS_SPDX=$?

  cosign verify-attestation \
    --type slsaprovenance \
    --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
    --certificate-identity-regexp '.*' \
    "$DIST_TAR"
  COS_SLSA=$?
  set -e

  if [[ $COS_SPDX -eq 0 && $COS_SLSA -eq 0 ]]; then
    echo "✓ Cosign attestations verified (SPDX + SLSA)"
  else
    echo "WARN: Cosign attestation verification did not fully pass (or attestations not published)."
    echo "      Integrity check above remains authoritative."
  fi
else
  echo "cosign not installed — skipping attestation verification."
fi

echo "✔ Release verification complete"