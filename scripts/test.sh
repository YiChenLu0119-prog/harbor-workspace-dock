#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${HARBOR_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test
