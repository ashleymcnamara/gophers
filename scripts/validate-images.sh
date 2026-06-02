#!/usr/bin/env bash
#
# validate-images.sh — checks image files for corruption, extension mismatches,
# and oversized files. Used by the Image Validation CI workflow.
#
# Usage:
#   ./scripts/validate-images.sh          # scan all images in repo
#   ./scripts/validate-images.sh --pr <base-sha>  # scan only changed images in a PR

set -euo pipefail

MAX_SIZE_BYTES=$((5 * 1024 * 1024))  # 5 MB
MAX_SIZE_HUMAN="5 MB"
ERRORS=0

check_image() {
  local file="$1"
  local ext="${file##*.}"
  ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

  # Skip if file doesn't exist (deleted in PR)
  if [ ! -f "$file" ]; then
    return
  fi

  local mime
  mime=$(file --brief --mime-type "$file")

  # --- Check: extension vs actual content ---
  case "$ext" in
    png)
      if [ "$mime" != "image/png" ]; then
        echo "❌ MISMATCH: $file has .png extension but is actually $mime"
        ((ERRORS++))
      fi
      ;;
    jpg|jpeg)
      if [ "$mime" != "image/jpeg" ]; then
        echo "❌ MISMATCH: $file has .$ext extension but is actually $mime"
        ((ERRORS++))
      fi
      ;;
    gif)
      if [ "$mime" != "image/gif" ]; then
        echo "❌ MISMATCH: $file has .gif extension but is actually $mime"
        ((ERRORS++))
      fi
      ;;
  esac

  # --- Check: corruption ---
  case "$ext" in
    png)
      if ! pngcheck -q "$file" > /dev/null 2>&1; then
        echo "❌ CORRUPT: $file failed PNG integrity check"
        ((ERRORS++))
      fi
      ;;
    jpg|jpeg)
      if ! jpeginfo -c "$file" 2>&1 | grep -q "\[OK\]"; then
        echo "❌ CORRUPT: $file failed JPEG integrity check"
        ((ERRORS++))
      fi
      ;;
  esac

  # --- Check: file size ---
  local size
  size=$(stat --format="%s" "$file" 2>/dev/null || stat -f "%z" "$file" 2>/dev/null)
  if [ "$size" -gt "$MAX_SIZE_BYTES" ]; then
    local size_mb
    size_mb=$(echo "scale=1; $size / 1024 / 1024" | bc)
    echo "⚠️  OVERSIZED: $file is ${size_mb} MB (limit: $MAX_SIZE_HUMAN)"
    ((ERRORS++))
  fi
}

# Gather file list
if [ "${1:-}" = "--pr" ] && [ -n "${2:-}" ]; then
  BASE_SHA="$2"
  echo "🔍 Checking images changed since $BASE_SHA..."
  # Null-delimited to handle spaces in filenames
  while IFS= read -r -d '' file; do
    check_image "$file"
  done < <(git diff -z --name-only --diff-filter=AM "$BASE_SHA" -- \
    '*.png' '*.jpg' '*.jpeg' '*.gif' \
    '*.PNG' '*.JPG' '*.JPEG' '*.GIF')
else
  echo "🔍 Scanning all images in repository..."
  while IFS= read -r -d '' file; do
    check_image "$file"
  done < <(find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \) -print0)
fi

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "💥 Found $ERRORS image issue(s). See above for details."
  exit 1
else
  echo "✅ All images passed validation."
fi
