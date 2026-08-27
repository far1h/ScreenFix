#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../src/ScreenFix.App" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-app-icon.sh"
ICON_TOOL="$SCRIPT_DIR/icon_ico.py"
COMMITTED_ICON="$APP_DIR/Resources/ScreenFix.ico"
EXPECTED_SIZES="16 20 24 32 40 48 64 128 256"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screenfix-icon-test.XXXXXX")"

cleanup() {
  rm -rf "$TEST_DIR"
}

trap cleanup EXIT

assert_icon() {
  local icon_path="$1"
  local actual_sizes
  local actual_mode

  test -f "$icon_path"
  test -s "$icon_path"
  actual_sizes="$(python3 "$ICON_TOOL" validate "$icon_path")"
  test "$actual_sizes" = "$EXPECTED_SIZES"
  actual_mode="$(stat -f '%Lp' "$icon_path")"
  test "$actual_mode" = "644"
}

assert_png_size() {
  local png_path="$1"
  local expected_size="$2"
  local actual_width
  local actual_height

  actual_width="$(sips -g pixelWidth "$png_path" | awk '/pixelWidth:/ { print $2 }')"
  actual_height="$(sips -g pixelHeight "$png_path" | awk '/pixelHeight:/ { print $2 }')"
  test "$actual_width" = "$expected_size"
  test "$actual_height" = "$expected_size"
}

GENERATED_ICON="$TEST_DIR/generated.ico"
"$BUILD_SCRIPT" "$GENERATED_ICON"
assert_icon "$GENERATED_ICON"
assert_icon "$COMMITTED_ICON"

FIRST_HASH="$(cksum "$GENERATED_ICON")"
"$BUILD_SCRIPT" "$GENERATED_ICON"
SECOND_HASH="$(cksum "$GENERATED_ICON")"
test "$FIRST_HASH" = "$SECOND_HASH"

DIRECTORY_TARGET="$TEST_DIR/destination-directory"
DIRECTORY_CANDIDATE="$TEST_DIR/directory-candidate.ico"
mkdir "$DIRECTORY_TARGET"
cp "$GENERATED_ICON" "$DIRECTORY_CANDIDATE"
if python3 "$ICON_TOOL" publish "$DIRECTORY_CANDIDATE" "$DIRECTORY_TARGET"; then
  echo "publish unexpectedly accepted a directory target" >&2
  exit 1
fi
test -f "$DIRECTORY_CANDIDATE"
test -z "$(find "$DIRECTORY_TARGET" -mindepth 1 -maxdepth 1 -print -quit)"

SENTINEL="$TEST_DIR/sentinel"
SYMLINK_TARGET="$TEST_DIR/destination-symlink"
SYMLINK_CANDIDATE="$TEST_DIR/symlink-candidate.ico"
printf 'unchanged sentinel\n' > "$SENTINEL"
SENTINEL_HASH="$(cksum "$SENTINEL")"
ln -s "$SENTINEL" "$SYMLINK_TARGET"
cp "$GENERATED_ICON" "$SYMLINK_CANDIDATE"
if python3 "$ICON_TOOL" publish "$SYMLINK_CANDIDATE" "$SYMLINK_TARGET"; then
  echo "publish unexpectedly accepted a symbolic-link target" >&2
  exit 1
fi
test -f "$SYMLINK_CANDIDATE"
test "$(cksum "$SENTINEL")" = "$SENTINEL_HASH"

PREVIEW_DIR="$TEST_DIR/preview"
python3 "$ICON_TOOL" extract "$GENERATED_ICON" "$PREVIEW_DIR" 256 32 16
assert_png_size "$PREVIEW_DIR/256.png" 256
assert_png_size "$PREVIEW_DIR/32.png" 32
assert_png_size "$PREVIEW_DIR/16.png" 16

echo "Windows app icon generator tests passed"
