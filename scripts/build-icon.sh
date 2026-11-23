#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_path="${1:-$PWD/dist/AppIcon.icns}"
icon_temp="$(mktemp -d "${TMPDIR:-/tmp}/harbor-icon.XXXXXX")"
trap 'rm -rf "$icon_temp"' EXIT
iconset="$icon_temp/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$output_path")"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$output_path"
