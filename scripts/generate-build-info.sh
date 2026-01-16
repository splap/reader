#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TIMESTAMP=$(date "+%d:%H:%M")
BUILD_INFO_PATH="$ROOT_DIR/Packages/ReaderKit/Sources/ReaderUI/BuildInfo.swift"

cat > "$BUILD_INFO_PATH" << SWIFT
import Foundation

enum BuildInfo {
    static let timestamp = "$TIMESTAMP"
}
SWIFT

echo "Generated BuildInfo.swift with timestamp: $TIMESTAMP"
