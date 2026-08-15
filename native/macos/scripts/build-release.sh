#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$MACOS_DIR/.build/manual-release"

test "$(uname -m)" = "arm64"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

CORE_SOURCES=("$MACOS_DIR"/Sources/ScreenFixCore/*.swift)
APP_SOURCES=("$MACOS_DIR"/Sources/ScreenFixApp/*.swift)
LAUNCHER_SOURCES=("$MACOS_DIR"/Sources/ScreenFixLauncher/*.swift)

swiftc -target arm64-apple-macosx13.0 -swift-version 5 -O -parse-as-library \
  -emit-module -emit-library -static -module-name ScreenFixCore \
  -emit-module-path "$BUILD_DIR/ScreenFixCore.swiftmodule" \
  "${CORE_SOURCES[@]}" -o "$BUILD_DIR/libScreenFixCore.a"

swiftc -target arm64-apple-macosx13.0 -swift-version 5 -O -parse-as-library \
  -emit-module -emit-library -static -module-name ScreenFixApp -I "$BUILD_DIR" \
  -emit-module-path "$BUILD_DIR/ScreenFixApp.swiftmodule" \
  "${APP_SOURCES[@]}" -o "$BUILD_DIR/libScreenFixApp.a"

swiftc -target arm64-apple-macosx13.0 -swift-version 5 -O -parse-as-library \
  -I "$BUILD_DIR" "${LAUNCHER_SOURCES[@]}" \
  "$BUILD_DIR/libScreenFixApp.a" "$BUILD_DIR/libScreenFixCore.a" \
  -framework AppKit -framework CoreGraphics \
  -o "$BUILD_DIR/ScreenFix"

file "$BUILD_DIR/ScreenFix" | grep -q 'Mach-O 64-bit executable arm64'
test "$(lipo -archs "$BUILD_DIR/ScreenFix")" = "arm64"
vtool -show-build "$BUILD_DIR/ScreenFix" | grep -q 'minos 13.0'
printf '%s\n' "$BUILD_DIR/ScreenFix"
