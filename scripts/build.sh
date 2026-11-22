#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${HARBOR_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/Harbor.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/Harbor" "$app_path/Contents/MacOS/Harbor"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
printf 'Built: %s\n' "$app_path"
