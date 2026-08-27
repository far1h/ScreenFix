#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$MACOS_DIR/artifacts/ScreenFix.app"
ZIP_PATH="$MACOS_DIR/artifacts/ScreenFix-macos-arm64.zip"
WORKSPACE="$(mktemp -d)"
ICONSET_PATH="$WORKSPACE/ScreenFix.iconset"
EXTRACT_DIR="$WORKSPACE/extracted"
EXTRACTED_APP_PATH="$EXTRACT_DIR/ScreenFix.app"

cleanup() {
    rm -rf "$WORKSPACE"
}

assert_png_size() {
    local path="$1"
    local expected="$2"
    local width
    local height

    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    test "$width" = "$expected"
    test "$height" = "$expected"
}

trap cleanup EXIT

"$SCRIPT_DIR/package-arm64.sh"

test -d "$APP_PATH"
test -f "$ZIP_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
ICNS_PATH="$APP_PATH/Contents/Resources/ScreenFix.icns"
MENU_ICON_PATH="$APP_PATH/Contents/Resources/ScreenFixMenuIcon.png"

test "$(plutil -extract CFBundleIconFile raw "$INFO_PLIST")" = "ScreenFix.icns"
test "$(plutil -extract LSUIElement raw "$INFO_PLIST")" = "true"
test -s "$ICNS_PATH"
test -f "$MENU_ICON_PATH"

iconutil -c iconset "$ICNS_PATH" -o "$ICONSET_PATH"
assert_png_size "$ICONSET_PATH/icon_16x16.png" 16
assert_png_size "$ICONSET_PATH/icon_16x16@2x.png" 32
assert_png_size "$ICONSET_PATH/icon_32x32.png" 32
assert_png_size "$ICONSET_PATH/icon_32x32@2x.png" 64
assert_png_size "$ICONSET_PATH/icon_128x128.png" 128
assert_png_size "$ICONSET_PATH/icon_128x128@2x.png" 256
assert_png_size "$ICONSET_PATH/icon_256x256.png" 256
assert_png_size "$ICONSET_PATH/icon_256x256@2x.png" 512
assert_png_size "$ICONSET_PATH/icon_512x512.png" 512
assert_png_size "$ICONSET_PATH/icon_512x512@2x.png" 1024

codesign --verify --strict --verbose=2 "$APP_PATH"

unzip -t "$ZIP_PATH" >/dev/null
ZIP_ENTRIES="$(unzip -Z1 "$ZIP_PATH")"
grep -Fqx 'ScreenFix.app/Contents/Resources/ScreenFix.icns' <<< "$ZIP_ENTRIES"

mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

EXTRACTED_INFO_PLIST="$EXTRACTED_APP_PATH/Contents/Info.plist"
EXTRACTED_ICNS_PATH="$EXTRACTED_APP_PATH/Contents/Resources/ScreenFix.icns"

test -d "$EXTRACTED_APP_PATH"
test "$(plutil -extract CFBundleIconFile raw "$EXTRACTED_INFO_PLIST")" = "ScreenFix.icns"
test "$(plutil -extract LSUIElement raw "$EXTRACTED_INFO_PLIST")" = "true"
test -s "$EXTRACTED_ICNS_PATH"
codesign --verify --strict --verbose=2 "$EXTRACTED_APP_PATH"
