#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOSITORY_ROOT="$(cd "$MACOS_DIR/../.." && pwd)"
RELEASE_DIR="$MACOS_DIR/.build/manual-release"
ARTIFACTS_DIR="$MACOS_DIR/artifacts"
APP_PATH="$ARTIFACTS_DIR/ScreenFix.app"
ZIP_PATH="$ARTIFACTS_DIR/ScreenFix-macos-arm64.zip"

test "$(uname -m)" = "arm64"
test -d "$REPOSITORY_ROOT/.git" || git -C "$REPOSITORY_ROOT" rev-parse --git-dir >/dev/null

BUILD_OUTPUT="$("$MACOS_DIR/scripts/build-release.sh")"
BINARY_PATH="$(printf '%s\n' "$BUILD_OUTPUT" | tail -n 1)"
case "$BINARY_PATH" in
    "$RELEASE_DIR"/*) ;;
    *) printf 'Unexpected release path: %s\n' "$BINARY_PATH" >&2; exit 1 ;;
esac
test -f "$BINARY_PATH"

rm -rf "$APP_PATH"
rm -f "$ZIP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/ScreenFix"
cp "$MACOS_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$MACOS_DIR/Resources/ScreenFixMenuIcon.png" "$APP_PATH/Contents/Resources/ScreenFixMenuIcon.png"
chmod 755 "$APP_PATH/Contents/MacOS/ScreenFix"

plutil -lint "$APP_PATH/Contents/Info.plist"
test "$(plutil -extract CFBundleExecutable raw "$APP_PATH/Contents/Info.plist")" = "ScreenFix"
test "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")" = "com.screenfix.ScreenFix"
test "$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")" = "1.0.0"
test "$(plutil -extract LSMinimumSystemVersion raw "$APP_PATH/Contents/Info.plist")" = "13.0"
test "$(plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist")" = "true"
test "$(plutil -extract LSMultipleInstancesProhibited raw "$APP_PATH/Contents/Info.plist")" = "true"
test -x "$APP_PATH/Contents/MacOS/ScreenFix"
test -f "$APP_PATH/Contents/Resources/ScreenFixMenuIcon.png"
test "$(sips -g pixelWidth "$APP_PATH/Contents/Resources/ScreenFixMenuIcon.png" 2>/dev/null | awk '/pixelWidth/ {print $2}')" = "36"
test "$(sips -g pixelHeight "$APP_PATH/Contents/Resources/ScreenFixMenuIcon.png" 2>/dev/null | awk '/pixelHeight/ {print $2}')" = "22"
test "$(lipo -archs "$APP_PATH/Contents/MacOS/ScreenFix")" = "arm64"
file "$APP_PATH/Contents/MacOS/ScreenFix" | grep -q 'Mach-O 64-bit executable arm64'
vtool -show-build "$APP_PATH/Contents/MacOS/ScreenFix" | grep -q 'platform MACOS'
vtool -show-build "$APP_PATH/Contents/MacOS/ScreenFix" | grep -q 'minos 13.0'
test ! -d "$APP_PATH/Contents/Frameworks"

codesign --force --sign - --timestamp=none "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
unzip -t "$ZIP_PATH" >/dev/null

while IFS= read -r entry; do
    case "$entry" in
        ScreenFix.app/*) ;;
        *) printf 'Unexpected zip entry: %s\n' "$entry" >&2; exit 1 ;;
    esac
done < <(unzip -Z1 "$ZIP_PATH")

ZIP_ENTRIES="$(unzip -Z1 "$ZIP_PATH")"
printf '%s\n' "$ZIP_ENTRIES" | grep -q '^ScreenFix.app/Contents/MacOS/ScreenFix$'
printf '%s\n' "$ZIP_ENTRIES" | grep -q '^ScreenFix.app/Contents/Info.plist$'
printf '%s\n' "$ZIP_ENTRIES" | grep -q '^ScreenFix.app/Contents/Resources/ScreenFixMenuIcon.png$'
printf '%s\n' "$ZIP_ENTRIES" | grep -q '^ScreenFix.app/Contents/_CodeSignature/CodeResources$'

printf '%s\n' "$APP_PATH" "$ZIP_PATH"
