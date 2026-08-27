#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_PATH="$MACOS_DIR/Resources/ScreenFixAppIcon.svg"
OUTPUT_DIR="$MACOS_DIR/.build/manual-release"
OUTPUT_PATH="$OUTPUT_DIR/ScreenFix.icns"
WORKSPACE="$(mktemp -d)"
MASTER_PATH="$WORKSPACE/ScreenFix-1024.png"
ICONSET_PATH="$WORKSPACE/ScreenFix.iconset"
ROUND_TRIP_PATH="$WORKSPACE/ScreenFix-round-trip.iconset"
STAGED_PATH="$WORKSPACE/ScreenFix.icns"
PUBLISH_PATH=""

cleanup() {
    rm -rf "$WORKSPACE"
    if [[ -n "$PUBLISH_PATH" ]]; then
        rm -f "$PUBLISH_PATH"
    fi
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

command -v sips >/dev/null 2>&1 || {
    echo "sips is required" >&2
    exit 1
}
command -v iconutil >/dev/null 2>&1 || {
    echo "iconutil is required" >&2
    exit 1
}
test -f "$SOURCE_PATH" || {
    echo "missing icon source: $SOURCE_PATH" >&2
    exit 1
}

ICON_SPECS=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

mkdir -p "$ICONSET_PATH"
sips -s format png -z 1024 1024 "$SOURCE_PATH" --out "$MASTER_PATH" >/dev/null
assert_png_size "$MASTER_PATH" 1024

for spec in "${ICON_SPECS[@]}"; do
    filename="${spec%%:*}"
    size="${spec##*:}"
    sips -z "$size" "$size" "$MASTER_PATH" --out "$ICONSET_PATH/$filename" >/dev/null
    assert_png_size "$ICONSET_PATH/$filename" "$size"
done

iconutil --convert icns --output "$STAGED_PATH" "$ICONSET_PATH"
test -s "$STAGED_PATH"

iconutil --convert iconset --output "$ROUND_TRIP_PATH" "$STAGED_PATH"
for spec in "${ICON_SPECS[@]}"; do
    filename="${spec%%:*}"
    size="${spec##*:}"
    assert_png_size "$ROUND_TRIP_PATH/$filename" "$size"
done

mkdir -p "$OUTPUT_DIR"
PUBLISH_PATH="$(mktemp "$OUTPUT_DIR/.ScreenFix.icns.XXXXXX")"
cp "$STAGED_PATH" "$PUBLISH_PATH"
test -s "$PUBLISH_PATH"
mv -f "$PUBLISH_PATH" "$OUTPUT_PATH"
PUBLISH_PATH=""

printf '%s\n' "$OUTPUT_PATH"
