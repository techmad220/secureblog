#!/usr/bin/env bash
# e2e-link-check.sh — verify internal links, assets, and anchors in a static build.
# Usage: bash scripts/e2e-link-check.sh [DIST_DIR]
set -euo pipefail

DIST="${1:-dist}"
[ -d "$DIST" ] || { echo "ERR: build dir '$DIST' not found"; exit 2; }

fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

is_external() {
  case "$1" in
    http://*|https://*|mailto:*|tel:*|data:*|javascript:* ) return 0 ;;
    * ) return 1 ;;
  esac
}

norm_path() {
  # $1 = base dir; $2 = link path (already stripped of ? and #)
  python3 - "$1" "$2" << 'PY' 2>/dev/null || awk -v b="$1" -v p="$2" 'BEGIN{print b "/" p}'
import os,sys
b=os.path.abspath(sys.argv[1]); p=sys.argv[2]
if p.startswith('/'): print(os.path.abspath(os.path.join(os.path.abspath(sys.argv[1]), p.lstrip('/')))); sys.exit(0)
print(os.path.abspath(os.path.join(b,p)))
PY
}

# Gather html files
mapfile -t htmls < <(find "$DIST" -type f -name '*.html' | sort)

# Quick policy checks (should be redundant with your CI)
if grep -RIlq --include="*.html" -E '<script\b|\.js\b' "$DIST"; then
  echo "ERR: Found <script> tag or .js reference in built HTML (policy violation)."
  fail=1
fi

# Build a set of referenced files to spot orphans
: > "$tmp/referenced.txt"

check_ref() {
  local page="$1" base dir link target fpath anchor
  base="$(dirname "$page")"
  link="$2"

  # strip query and preserve anchor
  local nohash="${link%%#*}"
  local anchor=""
  if [[ "$link" == *"#"* ]]; then anchor="${link#*#}"; fi
  local noqs="${nohash%%\?*}"

  # external? ignore
  if is_external "$link"; then return 0; fi
  # empty or pure hash => internal anchor on same page
  if [[ -z "$noqs" ]]; then
    if [[ -n "$anchor" ]] && ! grep -Eq "id=[\"']${anchor}[\"']|name=[\"']${anchor}[\"']" "$page"; then
      echo "BROKEN ANCHOR: $page -> #$anchor"
      fail=1
    fi
    return 0
  fi

  # normalize to filesystem path
  fpath="$(norm_path "$base" "$noqs")"
  # constrain to DIST root
  case "$fpath" in
    "$DIST"/*) ;;
    *) echo "WARN: path escapes dist: $page -> $link"; fail=1; return 0 ;;
  esac

  if [[ ! -e "$fpath" ]]; then
    echo "MISSING: $page -> $link (resolved: ${fpath#$DIST/})"
    fail=1
    return 0
  fi

  # track as referenced
  echo "${fpath#$DIST/}" >> "$tmp/referenced.txt"

  # check anchor in target file if present
  if [[ -n "$anchor" && -f "$fpath" && "$fpath" == *.html ]]; then
    if ! grep -Eq "id=[\"']${anchor}[\"']|name=[\"']${anchor}[\"']" "$fpath"; then
      echo "BROKEN ANCHOR: $page -> ${link}"
      fail=1
    fi
  fi
}

extract_attrs() {
  # print href/src/srcset candidates from an HTML file
  # tolerant grep-based extractor; skips quotes later
  grep -Eoi 'href=("[^"]*"|'\''[^'\'']*'\'')|src=("[^"]*"|'\''[^'\'']*'\'')|srcset=("[^"]*"|'\''[^'\'']*'\'')' -- "$1" \
  | sed -E 's/^[a-z]+=\s*//I;s/^"//;s/"$//;s/^'\''//;s/'\''$//'
}

process_srcset() {
  # split srcset into individual URLs (ignore descriptors)
  sed -E 's/ *, */\n/g' | awk '{print $1}'
}

echo "Scanning ${#htmls[@]} HTML file(s) in $DIST ..."
for page in "${htmls[@]}"; do
  while IFS= read -r val; do
    case "$val" in
      *","* ) # likely srcset
        while IFS= read -r u; do check_ref "$page" "$u"; done < <(printf "%s\n" "$val" | process_srcset)
        ;;
      * ) check_ref "$page" "$val" ;;
    esac
  done < <(extract_attrs "$page")
done

# Orphan detection (files never referenced by any HTML)
sort -u "$tmp/referenced.txt" > "$tmp/ref_sorted.txt" || true
mapfile -t built < <(cd "$DIST" && find . -type f ! -name '.integrity.manifest' ! -name 'search-index.json' -printf '%P\n' | sort)
if [[ ${#built[@]} -gt 0 ]]; then
  while IFS= read -r f; do
    if ! grep -qxF "$f" "$tmp/ref_sorted.txt"; then
      case "$f" in
        *.html|*.css|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.webp)
          echo "ORPHAN: $f"
          ;;
      esac
    fi
  done < <(printf "%s\n" "${built[@]}")
fi

if [[ $fail -ne 0 ]]; then
  echo "FAIL: link/asset/anchor audit found issues."
  exit 1
fi
echo "OK: all internal links, assets, and anchors verified."