#!/usr/bin/env python3

"""Pack, validate, extract, and safely publish the ScreenFix Windows icon."""

import argparse
import os
from pathlib import Path
import stat
import struct
import sys


EXPECTED_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ICON_HEADER = struct.Struct("<HHH")
ICON_ENTRY = struct.Struct("<BBBBHHII")
PNG_HEADER = struct.Struct(">I4sII")


class IconError(ValueError):
    """Report invalid icon input or an unsafe publication target."""


def png_dimensions(data: bytes) -> tuple[int, int]:
    """Return validated PNG IHDR dimensions."""
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE):
        raise IconError("icon payload is not a PNG")

    chunk_length, chunk_type, width, height = PNG_HEADER.unpack_from(data, 8)
    if chunk_length != 13 or chunk_type != b"IHDR":
        raise IconError("PNG does not begin with a valid IHDR chunk")
    if width == 0 or height == 0:
        raise IconError("PNG dimensions must be positive")
    return width, height


def decode_size(encoded: int) -> int:
    """Decode the ICO zero-byte representation of 256 pixels."""
    return 256 if encoded == 0 else encoded


def encode_size(size: int) -> int:
    """Encode 256 pixels as required by an ICO directory entry."""
    return 0 if size == 256 else size


def parse_ico(data: bytes) -> dict[int, bytes]:
    """Validate ICO structure and return PNG payloads by frame size."""
    if len(data) < ICON_HEADER.size:
        raise IconError("ICO header is truncated")

    reserved, icon_type, count = ICON_HEADER.unpack_from(data)
    if reserved != 0 or icon_type != 1 or count != len(EXPECTED_SIZES):
        raise IconError("ICO header does not describe the canonical icon")

    table_end = ICON_HEADER.size + count * ICON_ENTRY.size
    if len(data) < table_end:
        raise IconError("ICO directory is truncated")

    frames: dict[int, bytes] = {}
    ranges: list[tuple[int, int]] = []
    sizes: list[int] = []
    for index in range(count):
        entry_offset = ICON_HEADER.size + index * ICON_ENTRY.size
        width_byte, height_byte, colors, entry_reserved, planes, bits, length, offset = ICON_ENTRY.unpack_from(
            data, entry_offset
        )
        width = decode_size(width_byte)
        height = decode_size(height_byte)
        if width != height:
            raise IconError("ICO frame is not square")
        if colors != 0 or entry_reserved != 0 or planes != 1 or bits != 32:
            raise IconError("ICO directory entry metadata is invalid")
        if length == 0 or offset < table_end or offset + length > len(data):
            raise IconError("ICO payload range is invalid")

        payload = data[offset : offset + length]
        png_width, png_height = png_dimensions(payload)
        if (png_width, png_height) != (width, height):
            raise IconError("ICO frame dimensions do not match its PNG IHDR")

        sizes.append(width)
        ranges.append((offset, offset + length))
        if width in frames:
            raise IconError("ICO contains a duplicate frame size")
        frames[width] = payload

    if tuple(sizes) != EXPECTED_SIZES:
        raise IconError("ICO frame sizes are not the canonical ascending set")

    ordered_ranges = sorted(ranges)
    for previous, current in zip(ordered_ranges, ordered_ranges[1:]):
        if current[0] < previous[1]:
            raise IconError("ICO payload ranges overlap")
    return frames


def validate_file(path: Path) -> dict[int, bytes]:
    """Validate an ICO file and return its frames."""
    return parse_ico(path.read_bytes())


def parse_pack_item(value: str) -> tuple[int, Path]:
    """Parse one SIZE=PNG pack argument."""
    size_text, separator, path_text = value.partition("=")
    if not separator or not size_text.isdigit() or not path_text:
        raise IconError(f"invalid frame argument: {value}")
    return int(size_text), Path(path_text)


def pack(output: Path, items: list[str]) -> None:
    """Write a canonical ICO from validated PNG frames."""
    source_frames: dict[int, bytes] = {}
    for item in items:
        size, path = parse_pack_item(item)
        if size in source_frames:
            raise IconError(f"duplicate input frame: {size}")
        payload = path.read_bytes()
        if png_dimensions(payload) != (size, size):
            raise IconError(f"PNG frame does not match requested size: {size}")
        source_frames[size] = payload

    if tuple(sorted(source_frames)) != EXPECTED_SIZES:
        raise IconError("pack requires the canonical frame-size set")

    table_end = ICON_HEADER.size + len(EXPECTED_SIZES) * ICON_ENTRY.size
    entries: list[bytes] = []
    payloads: list[bytes] = []
    offset = table_end
    for size in EXPECTED_SIZES:
        payload = source_frames[size]
        encoded = encode_size(size)
        entries.append(ICON_ENTRY.pack(encoded, encoded, 0, 0, 1, 32, len(payload), offset))
        payloads.append(payload)
        offset += len(payload)

    output.write_bytes(ICON_HEADER.pack(0, 1, len(EXPECTED_SIZES)) + b"".join(entries + payloads))
    validate_file(output)


def extract(icon: Path, output_directory: Path, sizes: list[int]) -> None:
    """Extract selected PNG frames from a validated ICO."""
    frames = validate_file(icon)
    if not sizes:
        raise IconError("extract requires at least one frame size")
    output_directory.mkdir(parents=True, exist_ok=True)
    for size in sizes:
        if size not in frames:
            raise IconError(f"ICO does not contain frame: {size}")
        (output_directory / f"{size}.png").write_bytes(frames[size])


def reject_unsafe_destination(output: Path) -> None:
    """Reject a destination that could redirect or absorb publication."""
    try:
        metadata = output.lstat()
    except FileNotFoundError:
        return
    if stat.S_ISLNK(metadata.st_mode):
        raise IconError(f"output path is a symbolic link: {output}")
    if stat.S_ISDIR(metadata.st_mode):
        raise IconError(f"output path is a directory: {output}")
    if not stat.S_ISREG(metadata.st_mode):
        raise IconError(f"output path is not a regular file: {output}")


def publish(candidate: Path, output: Path) -> None:
    """Validate and atomically publish one candidate ICO."""
    candidate_metadata = candidate.lstat()
    if not stat.S_ISREG(candidate_metadata.st_mode):
        raise IconError(f"candidate is not a regular file: {candidate}")
    reject_unsafe_destination(output)
    validate_file(candidate)
    candidate.chmod(0o644)
    reject_unsafe_destination(output)
    os.replace(candidate, output)


def create_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    pack_parser = commands.add_parser("pack")
    pack_parser.add_argument("output", type=Path)
    pack_parser.add_argument("frames", nargs="+")

    validate_parser = commands.add_parser("validate")
    validate_parser.add_argument("icon", type=Path)

    extract_parser = commands.add_parser("extract")
    extract_parser.add_argument("icon", type=Path)
    extract_parser.add_argument("output_directory", type=Path)
    extract_parser.add_argument("sizes", type=int, nargs="+")

    publish_parser = commands.add_parser("publish")
    publish_parser.add_argument("candidate", type=Path)
    publish_parser.add_argument("output", type=Path)
    return parser


def run(arguments: argparse.Namespace) -> None:
    """Run the selected command."""
    if arguments.command == "pack":
        pack(arguments.output, arguments.frames)
    elif arguments.command == "validate":
        frames = validate_file(arguments.icon)
        print(" ".join(str(size) for size in frames))
    elif arguments.command == "extract":
        extract(arguments.icon, arguments.output_directory, arguments.sizes)
    elif arguments.command == "publish":
        publish(arguments.candidate, arguments.output)


def main() -> int:
    """Parse arguments and return a process status."""
    try:
        run(create_parser().parse_args())
    except (IconError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
