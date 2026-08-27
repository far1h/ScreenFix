#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG_SOURCE="$SCRIPT_DIR/../src/ScreenFix.App/Resources/ScreenFixAppIcon.svg"
ICON_TOOL="$SCRIPT_DIR/icon_ico.py"
DEFAULT_OUTPUT="$SCRIPT_DIR/../src/ScreenFix.App/Resources/ScreenFix.ico"
OUTPUT="${1:-$DEFAULT_OUTPUT}"
EXPECTED_SIZES="16 20 24 32 40 48 64 128 256"
CANDIDATE=""

cleanup() {
  rm -rf "$FRAME_DIR"
  if [ -n "$CANDIDATE" ] && [ -e "$CANDIDATE" ]; then
    rm -f "$CANDIDATE"
  fi
}

command -v sips >/dev/null 2>&1 || {
  echo "sips is required to build the Windows app icon" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to build the Windows app icon" >&2
  exit 1
}

if [ -L "$OUTPUT" ]; then
  echo "output path is a symbolic link: $OUTPUT" >&2
  exit 1
fi
if [ -d "$OUTPUT" ]; then
  echo "output path is a directory: $OUTPUT" >&2
  exit 1
fi

OUTPUT_DIRECTORY="$(cd "$(dirname "$OUTPUT")" && pwd)"
OUTPUT="$OUTPUT_DIRECTORY/$(basename "$OUTPUT")"
FRAME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screenfix-icon-build.XXXXXX")"
trap cleanup EXIT

SOURCE_PNG="$FRAME_DIR/source.png"
sips -s format png --resampleHeightWidth 1024 1024 "$SVG_SOURCE" --out "$SOURCE_PNG" >/dev/null

PACK_ARGUMENTS=()
for SIZE in 16 20 24 32 40 48 64 128 256; do
  FRAME_PATH="$FRAME_DIR/$SIZE.png"
  sips --resampleHeightWidth "$SIZE" "$SIZE" "$SOURCE_PNG" --out "$FRAME_PATH" >/dev/null
  PACK_ARGUMENTS+=("$SIZE=$FRAME_PATH")
done

CANDIDATE="$(mktemp "$OUTPUT_DIRECTORY/.ScreenFix.ico.XXXXXX")"
python3 "$ICON_TOOL" pack "$CANDIDATE" "${PACK_ARGUMENTS[@]}"
ACTUAL_SIZES="$(python3 "$ICON_TOOL" validate "$CANDIDATE")"
if [ "$ACTUAL_SIZES" != "$EXPECTED_SIZES" ]; then
  echo "generated ICO has unexpected frame sizes: $ACTUAL_SIZES" >&2
  exit 1
fi

python3 "$ICON_TOOL" publish "$CANDIDATE" "$OUTPUT"
CANDIDATE=""
