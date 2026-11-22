#!/usr/bin/env bash
# Renders apps/mac/Assets/AppIcon.svg into the AppIcon asset catalog at every macOS size.
# Requires rsvg-convert (brew install librsvg). Generated PNGs are committed, so CI doesn't need it.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$APP_DIR/Assets/AppIcon.svg"
ICONSET="$APP_DIR/Macros/Assets.xcassets/AppIcon.appiconset"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg" >&2; exit 1; }

mkdir -p "$ICONSET"
rm -f "$ICONSET"/*.png

images=()
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((size * scale))
        suffix=$([[ $scale == 2 ]] && echo "@2x" || echo "")
        file="icon_${size}x${size}${suffix}.png"
        rsvg-convert -w "$px" -h "$px" "$SVG" -o "$ICONSET/$file"
        images+=("    { \"idiom\": \"mac\", \"size\": \"${size}x${size}\", \"scale\": \"${scale}x\", \"filename\": \"$file\" }")
    done
done

{
    echo '{'
    echo '  "images": ['
    (IFS=$'\n'; echo "${images[*]}" | sed '$!s/$/,/')
    echo '  ],'
    echo '  "info": { "author": "xcode", "version": 1 }'
    echo '}'
} >"$ICONSET/Contents.json"

cat >"$APP_DIR/Macros/Assets.xcassets/Contents.json" <<'JSON'
{
  "info": { "author": "xcode", "version": 1 }
}
JSON

echo "Wrote $(ls "$ICONSET"/*.png | wc -l | tr -d ' ') icons to ${ICONSET#"$APP_DIR"/}"
