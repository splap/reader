#!/bin/bash
TIMESTAMP=$(date "+%d:%H:%M")
BUILD_INFO_PATH="/Users/jamesmichels/src/reader/Packages/ReaderKit/Sources/ReaderUI/BuildInfo.swift"

cat > "$BUILD_INFO_PATH" << SWIFT
import Foundation

enum BuildInfo {
    static let timestamp = "$TIMESTAMP"
}
SWIFT

echo "Generated BuildInfo.swift with timestamp: $TIMESTAMP"
