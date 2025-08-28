#!/usr/bin/env bash
set -Eeuo pipefail

scan_paths=(templates content build dist)
patterns=(
  '<script[^>]*>'
  'javascript:'
  'on[a-z]+='
  'import\('
  'document\.|window\.|eval\('
)

found=0
for p in "${scan_paths[@]}"; do
  [ -d "$p" ] || continue
  while IFS= read -r -d '' f; do
    for pat in "${patterns[@]}"; do
      if grep -Eqi -- "$pat" "$f"; then
        echo "::error file=$f,line=1::NO-JS violation: pattern '$pat' detected"
        found=1
      fi
    done
  done < <(find "$p" -type f -print0)
done

if [ "$found" -ne 0 ]; then
  echo "NO-JS guard failed. Remove all scripts/JS handlers."
  exit 1
fi
echo "NO-JS guard passed."