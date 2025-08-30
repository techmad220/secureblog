#!/usr/bin/env bash
set -euo pipefail

DIR="${1:-dist}"
OUT_TXT="${DIR}/_manifest.txt"
OUT_SIG="${OUT_TXT}.sig"

if [[ ! -d "$DIR" ]]; then
  echo "site dir not found: $DIR" >&2
  exit 1
fi

echo "[manifest] creating ${OUT_TXT}"
: > "$OUT_TXT"
# list all regular files, stable sort, and hash
while IFS= read -r -d '' f; do
  rel="${f#$DIR/}"
  sha256sum "$f" | awk -v path="$rel" '{print $1"  "path}' >> "$OUT_TXT"
done < <(find "$DIR" -type f -print0 | sort -z)

if command -v cosign >/dev/null 2>&1; then
  echo "[manifest] signing with cosign (keyless)"
  export COSIGN_EXPERIMENTAL=1
  cosign sign-blob --yes --output-signature "$OUT_SIG" "$OUT_TXT" || {
    echo "[manifest] cosign signing failed (continuing unsigned)"; exit 0;
  }
  echo "[manifest] wrote signature: $OUT_SIG"
else
  echo "[manifest] cosign not installed; manifest left unsigned."
fi