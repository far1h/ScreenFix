from __future__ import annotations

import re
import stat
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "site" / "assets"

EXPECTED_IMAGES = {
    "damaged-display.jpg": (1200, 900),
    "result-calibration.jpg": (1200, 675),
    "result-mask.jpg": (1200, 675),
}
MAX_IMAGE_BYTES = 400_000
MAX_TOTAL_IMAGE_BYTES = 1_000_000
SVG_NAMESPACE = "http://www.w3.org/2000/svg"
ALLOWED_SVG_TAGS = frozenset({"svg", "defs", "linearGradient", "stop", "rect", "path"})
LOCAL_CSS_URL = re.compile(r"#[A-Za-z][A-Za-z0-9_-]*")
CSS_URL = re.compile(r"url\((.*?)\)", re.IGNORECASE)


class ContractError(AssertionError):
    """Reports a stable landing-page contract failure."""


class _SvgTreeBuilder(ET.TreeBuilder):
    """Build SVG XML while rejecting every processing instruction."""

    def pi(self, target: str, text: str | None) -> None:
        """Reject stylesheet and other XML processing instructions."""
        raise ContractError("SVG processing instructions are forbidden")


def validate_svg(svg: bytes) -> None:
    """Validate the site icon's XML namespace and active-content boundaries."""
    try:
        parser = ET.XMLParser(target=_SvgTreeBuilder())
        root = ET.fromstring(svg, parser=parser)
    except ET.ParseError as error:
        raise ContractError("SVG XML is malformed") from error
    if root.tag != f"{{{SVG_NAMESPACE}}}svg":
        raise ContractError("SVG root namespace is invalid")
    for element in root.iter():
        if not element.tag.startswith(f"{{{SVG_NAMESPACE}}}"):
            raise ContractError("SVG element namespace is invalid")
        local_tag = element.tag.rsplit("}", 1)[-1]
        if local_tag not in ALLOWED_SVG_TAGS:
            raise ContractError("SVG element is not allowed")
        for raw_name, value in element.attrib.items():
            if raw_name.startswith("{") and not raw_name.startswith(f"{{{SVG_NAMESPACE}}}"):
                raise ContractError("SVG attribute namespace is invalid")
            name = raw_name.rsplit("}", 1)[-1].lower()
            if name.startswith("on") or name in {"href", "src", "style"}:
                raise ContractError("SVG external references are forbidden")
            _validate_css_urls(value)
        _validate_css_urls(element.text or "")
        _validate_css_urls(element.tail or "")


def _validate_css_urls(value: str) -> None:
    """Allow CSS URL references only when they target a local fragment."""
    if "\\" in value:
        raise ContractError("SVG CSS escapes are forbidden")
    if re.search(r"@import\b", value, re.IGNORECASE):
        raise ContractError("SVG CSS imports are forbidden")
    matches = CSS_URL.findall(value)
    if value.lower().count("url(") != len(matches):
        raise ContractError("SVG CSS URL is malformed")
    for target in matches:
        normalized = target.strip()
        if len(normalized) >= 2 and normalized[0] == normalized[-1] and normalized[0] in {'"', "'"}:
            normalized = normalized[1:-1]
        if LOCAL_CSS_URL.fullmatch(normalized) is None:
            raise ContractError("SVG CSS URL must use a local fragment")


def parse_jpeg(source: Path | bytes) -> tuple[int, int]:
    """Return JPEG dimensions after validating a metadata-free marker stream."""
    data = _read_jpeg_path(source) if isinstance(source, Path) else source
    width, height = _walk_jpeg(data)
    return width, height


def _read_jpeg_path(path: Path) -> bytes:
    """Read one bounded regular JPEG file without following symlinks."""
    path_status = path.lstat()
    if not stat.S_ISREG(path_status.st_mode):
        raise ContractError("JPEG path must be a regular non-symlink file")
    if path_status.st_size > MAX_IMAGE_BYTES:
        raise ContractError("JPEG file exceeds the size limit")
    return path.read_bytes()


def read_u16(data: bytes, offset: int) -> int:
    """Read one big-endian JPEG integer inside validated bounds."""
    if offset < 0 or offset + 2 > len(data):
        raise ContractError("JPEG marker is truncated")
    return int.from_bytes(data[offset : offset + 2], "big")


def _segment(data: bytes, offset: int) -> tuple[bytes, int]:
    """Return one bounded length-delimited marker payload and its end."""
    length = read_u16(data, offset)
    if length < 2:
        raise ContractError("JPEG marker length is invalid")
    end = offset + length
    if end > len(data):
        raise ContractError("JPEG marker is truncated")
    return data[offset + 2 : end], end


def _entropy_span(data: bytes, offset: int) -> tuple[int, int]:
    """Find the next marker and count entropy bytes safely."""
    count = 0
    while offset < len(data):
        if data[offset] != 0xFF:
            offset += 1
            count += 1
            continue
        if offset + 1 >= len(data):
            return len(data), count
        code = data[offset + 1]
        if code == 0x00:
            offset += 2
            count += 1
            continue
        if 0xD0 <= code <= 0xD7:
            offset += 2
            continue
        return offset, count
    return offset, count


def parse_jfif(payload: bytes) -> None:
    """Accept only a complete JFIF header without an embedded thumbnail."""
    if len(payload) != 14 or payload[:5] != b"JFIF\x00":
        raise ContractError("JPEG APP0 must be a zero-thumbnail JFIF record")
    if payload[5:7] not in {b"\x01\x00", b"\x01\x01", b"\x01\x02"}:
        raise ContractError("JPEG JFIF version is unsupported")
    if payload[7] > 2:
        raise ContractError("JPEG JFIF density unit is invalid")
    if read_u16(payload, 8) == 0 or read_u16(payload, 10) == 0:
        raise ContractError("JPEG JFIF densities must be positive")
    if payload[-2:] != b"\x00\x00":
        raise ContractError("JPEG JFIF thumbnails are forbidden")


def _parse_frame(payload: bytes) -> tuple[int, int]:
    """Return positive dimensions from one complete JPEG frame header."""
    if len(payload) < 6:
        raise ContractError("JPEG frame header is truncated")
    if payload[0] != 8:
        raise ContractError("JPEG frame precision must be 8-bit")
    component_count = payload[5]
    if component_count == 0 or len(payload) != 6 + 3 * component_count:
        raise ContractError("JPEG frame header length is invalid")
    component_ids: set[int] = set()
    sample_blocks = 0
    for offset in range(6, len(payload), 3):
        component_id = payload[offset]
        if component_id == 0 or component_id in component_ids:
            raise ContractError("JPEG frame component IDs must be unique and nonzero")
        component_ids.add(component_id)
        sampling = payload[offset + 1]
        horizontal = sampling >> 4
        vertical = sampling & 0x0F
        if not 1 <= horizontal <= 4 or not 1 <= vertical <= 4:
            raise ContractError("JPEG frame sampling factors must be between 1 and 4")
        sample_blocks += horizontal * vertical
        if payload[offset + 2] > 3:
            raise ContractError("JPEG frame quantization selector is unsupported")
    if sample_blocks > 10:
        raise ContractError("JPEG frame MCU has too many sample blocks")
    height = read_u16(payload, 1)
    width = read_u16(payload, 3)
    if width == 0 or height == 0:
        raise ContractError("JPEG frame dimensions must be positive")
    return width, height


def _validate_scan_header(payload: bytes, frame_marker: int, frame_components: frozenset[int]) -> None:
    """Require a complete scan header with at least one component."""
    if len(payload) < 4:
        raise ContractError("JPEG scan header is truncated")
    component_count = payload[0]
    if component_count == 0 or len(payload) != 4 + 2 * component_count:
        raise ContractError("JPEG scan header length is invalid")
    selectors = payload[1 : 1 + 2 * component_count : 2]
    if any(selector not in frame_components for selector in selectors):
        raise ContractError("JPEG scan references an unknown frame component")
    if len(selectors) != len(set(selectors)):
        raise ContractError("JPEG scan component selectors are duplicated")
    for table_selector in payload[2 : 1 + 2 * component_count : 2]:
        if table_selector >> 4 > 3 or table_selector & 0x0F > 3:
            raise ContractError("JPEG scan Huffman table selector is unsupported")
    if frame_marker == 0xC0 and payload[-3:] != b"\x00\x3f\x00":
        raise ContractError("JPEG baseline scan fields are invalid")
    if frame_marker == 0xC2:
        _validate_progressive_scan(component_count, payload[-3:])


def _validate_progressive_scan(component_count: int, fields: bytes) -> None:
    """Require legal progressive spectral and approximation fields."""
    spectral_start, spectral_end, approximation = fields
    high = approximation >> 4
    low = approximation & 0x0F
    if spectral_start > spectral_end or spectral_end > 63:
        raise ContractError("JPEG progressive spectral range is invalid")
    if spectral_start == 0 and spectral_end != 0:
        raise ContractError("JPEG progressive DC scan range is invalid")
    if spectral_start > 0 and component_count != 1:
        raise ContractError("JPEG progressive AC scan must have one component")
    if high > 13 or low > 13 or high not in {0, low + 1}:
        raise ContractError("JPEG progressive approximation is invalid")


def _update_progressive_state(payload: bytes, state: dict[tuple[int, int], int]) -> None:
    """Track coefficient initialization and successive approximation."""
    component_count = payload[0]
    components = payload[1 : 1 + 2 * component_count : 2]
    spectral_start, spectral_end, approximation = payload[-3:]
    high = approximation >> 4
    low = approximation & 0x0F
    keys = tuple(
        (component, coefficient)
        for component in components
        for coefficient in range(spectral_start, spectral_end + 1)
    )
    if high == 0 and any(key in state for key in keys):
        raise ContractError("JPEG progressive coefficient is initialized twice")
    if high > 0:
        if any(key not in state for key in keys):
            raise ContractError("JPEG progressive refinement precedes initialization")
        if any(state[key] != high for key in keys):
            raise ContractError("JPEG progressive refinement transition is skipped")
    for key in keys:
        state[key] = low


def _validate_quantization_tables(payload: bytes) -> None:
    """Require complete 8-bit or 16-bit JPEG quantization tables."""
    if not payload:
        raise ContractError("JPEG DQT marker is empty")
    offset = 0
    while offset < len(payload):
        table_info = payload[offset]
        precision = table_info >> 4
        if precision not in {0, 1} or table_info & 0x0F > 3:
            raise ContractError("JPEG DQT table selector is invalid")
        offset += 1 + 64 * (precision + 1)
        if offset > len(payload):
            raise ContractError("JPEG DQT table is truncated")


def _validate_huffman_tables(payload: bytes) -> None:
    """Require complete DC or AC JPEG Huffman tables."""
    if not payload:
        raise ContractError("JPEG DHT marker is empty")
    offset = 0
    while offset < len(payload):
        if offset + 17 > len(payload):
            raise ContractError("JPEG DHT table is truncated")
        table_info = payload[offset]
        table_class = table_info >> 4
        if table_class > 1 or table_info & 0x0F > 3:
            raise ContractError("JPEG DHT table selector is invalid")
        code_counts = payload[offset + 1 : offset + 17]
        available_codes = 1
        for count in code_counts:
            available_codes = 2 * available_codes - count
            if available_codes < 0:
                raise ContractError("JPEG DHT tree is oversubscribed")
        symbol_count = sum(code_counts)
        if symbol_count == 0:
            raise ContractError("JPEG DHT table is empty")
        maximum_symbols = 12 if table_class == 0 else 162
        if symbol_count > maximum_symbols:
            raise ContractError("JPEG DHT has too many symbols")
        offset += 17 + symbol_count
        if offset > len(payload):
            raise ContractError("JPEG DHT symbols are truncated")


def _walk_jpeg(data: bytes) -> tuple[int, int]:
    """Walk bounded JPEG marker segments and return frame dimensions."""
    if not data.startswith(b"\xff\xd8"):
        raise ContractError("JPEG SOI marker is missing")
    offset = 2
    dimensions: tuple[int, int] | None = None
    frame_components: frozenset[int] = frozenset()
    frame_marker: int | None = None
    progressive_state: dict[tuple[int, int], int] = {}
    saw_eoi = False
    saw_jfif = False
    saw_sos = False
    while offset < len(data):
        if data[offset] != 0xFF:
            raise ContractError("JPEG marker prefix is missing")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            raise ContractError("JPEG marker is truncated")
        marker = data[offset]
        offset += 1
        if marker == 0xD9:
            saw_eoi = True
            if data[offset:] == b"\xff\xd9":
                raise ContractError("JPEG EOI marker is duplicated")
            if offset != len(data):
                raise ContractError("JPEG data follows the EOI marker")
            break
        if marker == 0xD8:
            raise ContractError("JPEG SOI marker is duplicated")
        if 0xD0 <= marker <= 0xD7:
            raise ContractError("JPEG restart marker is outside entropy data")
        if 0xE1 <= marker <= 0xEF or marker == 0xFE:
            raise ContractError("JPEG metadata marker is forbidden")
        if marker not in {0xC0, 0xC2, 0xC4, 0xDA, 0xDB, 0xDD, 0xE0}:
            raise ContractError("JPEG marker is not allowed")
        payload, offset = _segment(data, offset)
        if marker in {0xC0, 0xC2}:
            if dimensions is not None:
                raise ContractError("JPEG frame marker is duplicated")
            dimensions = _parse_frame(payload)
            frame_components = frozenset(payload[6::3])
            frame_marker = marker
        elif marker == 0xE0:
            if saw_jfif:
                raise ContractError("JPEG JFIF marker is duplicated")
            parse_jfif(payload)
            saw_jfif = True
        elif marker == 0xDD and len(payload) != 2:
            raise ContractError("JPEG DRI marker length is invalid")
        elif marker == 0xC4:
            _validate_huffman_tables(payload)
        elif marker == 0xDB:
            _validate_quantization_tables(payload)
        elif marker == 0xDA:
            if dimensions is None:
                raise ContractError("JPEG scan precedes the frame header")
            if frame_marker is None:
                raise ContractError("JPEG frame type is missing")
            _validate_scan_header(payload, frame_marker, frame_components)
            if frame_marker == 0xC2:
                _update_progressive_state(payload, progressive_state)
            saw_sos = True
            offset, entropy_count = _entropy_span(data, offset)
            if entropy_count == 0:
                raise ContractError("JPEG entropy data is empty")
    if dimensions is None:
        raise ContractError("JPEG frame is missing")
    if not saw_eoi:
        raise ContractError("JPEG EOI marker is missing")
    if not saw_sos:
        raise ContractError("JPEG SOS marker is missing")
    return dimensions


def minimal_jpeg() -> bytes:
    """Return a minimal structural JPEG fixture with one entropy byte."""
    dqt = b"\xff\xdb\x00\x43\x00" + b"\x01" * 64
    dc_table = b"\x00\x01" + b"\x00" * 15 + b"\x00"
    ac_table = b"\x10\x01" + b"\x00" * 15 + b"\x00"
    dht_payload = dc_table + ac_table
    dht = b"\xff\xc4" + (len(dht_payload) + 2).to_bytes(2, "big") + dht_payload
    return (
        b"\xff\xd8"
        + dqt
        + b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        + dht
        + b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        + b"\x01"
        + b"\xff\xd9"
    )


def progressive_jpeg(*scan_fields: bytes) -> bytes:
    """Return a progressive fixture with the requested scan field triples."""
    if not scan_fields:
        raise ValueError("at least one scan is required")
    jpeg = minimal_jpeg().replace(b"\xff\xc0", b"\xff\xc2", 1)
    first_scan = scan_fields[0] + b"\x01\xff\xd9"
    jpeg = jpeg.replace(b"\x00\x3f\x00\x01\xff\xd9", first_scan, 1)
    additional = b"".join(
        b"\xff\xda\x00\x08\x01\x01\x00" + fields + bytes([index + 2])
        for index, fields in enumerate(scan_fields[1:])
    )
    return jpeg[:-2] + additional + b"\xff\xd9"


def jfif_payload(
    version: tuple[int, int] = (1, 1),
    units: int = 0,
    x_density: int = 1,
    y_density: int = 1,
) -> bytes:
    """Return a complete zero-thumbnail JFIF payload."""
    return (
        b"JFIF\x00"
        + bytes((*version, units))
        + x_density.to_bytes(2, "big")
        + y_density.to_bytes(2, "big")
        + b"\x00\x00"
    )


def with_segment(jpeg: bytes, marker: int, payload: bytes) -> bytes:
    """Insert one length-delimited marker immediately after SOI."""
    segment = b"\xff" + bytes([marker]) + (len(payload) + 2).to_bytes(2, "big") + payload
    return jpeg[:2] + segment + jpeg[2:]


class ImageContractTests(unittest.TestCase):
    def test_oversized_jpeg_path_is_rejected_before_reading(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "oversized.jpg"
            with path.open("wb") as oversized:
                oversized.seek(MAX_IMAGE_BYTES)
                oversized.write(b"\x00")
            with self.assertRaisesRegex(ContractError, "JPEG file exceeds the size limit"):
                parse_jpeg(path)

    def test_directory_jpeg_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            directory = temporary / "directory.jpg"
            directory.mkdir()
            with self.assertRaisesRegex(ContractError, "regular non-symlink"):
                parse_jpeg(directory)

    def test_symlink_jpeg_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            target = temporary / "target.jpg"
            target.write_bytes(minimal_jpeg())
            symlink = temporary / "symlink.jpg"
            try:
                symlink.symlink_to(target)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation is unavailable: {error}")
            with self.assertRaisesRegex(ContractError, "regular non-symlink"):
                parse_jpeg(symlink)

    def test_svg_animation_elements_are_rejected(self) -> None:
        mutations = {
            "set": (
                b'<svg xmlns="http://www.w3.org/2000/svg">'
                b'<set attributeName="href" to="https://example.invalid"/>'
                b"</svg>"
            ),
            "animate": (
                b'<svg xmlns="http://www.w3.org/2000/svg">'
                b'<animate attributeName="opacity" from="0" to="1"/>'
                b"</svg>"
            ),
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), self.assertRaises(ContractError):
                validate_svg(mutation)

    def test_svg_escaped_css_import_is_rejected(self) -> None:
        unsafe = (
            b'<svg xmlns="http://www.w3.org/2000/svg">'
            b'<style>@\\69mport "https://example.com/site.css";</style>'
            b"</svg>"
        )
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_escaped_css_url_is_rejected(self) -> None:
        unsafe = b'<svg xmlns="http://www.w3.org/2000/svg"><rect fill="u\\72l(https://example.com/a)"/></svg>'
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_style_attribute_is_rejected(self) -> None:
        unsafe = b'<svg xmlns="http://www.w3.org/2000/svg"><rect style="fill:#fff"/></svg>'
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_stylesheet_processing_instruction_is_rejected(self) -> None:
        unsafe = (
            b'<?xml-stylesheet href="https://example.com/site.css" type="text/css"?>'
            b'<svg xmlns="http://www.w3.org/2000/svg"/>'
        )
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_external_css_import_is_rejected(self) -> None:
        unsafe = (
            b'<svg xmlns="http://www.w3.org/2000/svg">'
            b'<style>@import "https://example.com/site.css";</style>'
            b"</svg>"
        )
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_local_fragment_url_is_accepted(self) -> None:
        safe = (
            b'<svg xmlns="http://www.w3.org/2000/svg">'
            b'<defs><linearGradient id="safe"/></defs>'
            b'<rect fill="url(#safe)"/>'
            b"</svg>"
        )
        validate_svg(safe)

    def test_svg_external_css_url_is_rejected(self) -> None:
        unsafe = b'<svg xmlns="http://www.w3.org/2000/svg"><style>.x{fill:url(https://example.com/a)}</style></svg>'
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_active_content_mutations_are_rejected(self) -> None:
        mutations = {
            "script": b'<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>',
            "foreignObject": b'<svg xmlns="http://www.w3.org/2000/svg"><foreignObject/></svg>',
            "event": b'<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>',
            "href": b'<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.com/a"/></svg>',
            "src": b'<svg xmlns="http://www.w3.org/2000/svg"><image src="https://example.com/a"/></svg>',
            "namespace": b'<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="urn:example"><x:item/></svg>',
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), self.assertRaises(ContractError):
                validate_svg(mutation)

    def test_canonical_icon_copy_is_exact_and_script_free(self) -> None:
        site_icon = (ASSETS / "screenfix-icon.svg").read_bytes()
        canonical = (ROOT / "native/macos/Resources/ScreenFixAppIcon.svg").read_bytes()
        self.assertEqual(canonical, site_icon)
        validate_svg(site_icon)

    def test_minimal_jpeg_is_accepted(self) -> None:
        self.assertEqual((1, 1), parse_jpeg(minimal_jpeg()))

    def test_progressive_jpeg_is_accepted(self) -> None:
        self.assertEqual((1, 1), parse_jpeg(progressive_jpeg(b"\x00\x00\x00")))

    def test_progressive_initial_then_refinement_is_accepted(self) -> None:
        valid = progressive_jpeg(b"\x00\x00\x01", b"\x00\x00\x10")
        self.assertEqual((1, 1), parse_jpeg(valid))

    def test_progressive_refinement_before_initial_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(progressive_jpeg(b"\x00\x00\x10"))

    def test_progressive_duplicate_initial_coverage_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(progressive_jpeg(b"\x00\x00\x00", b"\x00\x00\x00"))

    def test_progressive_skipped_refinement_transition_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(progressive_jpeg(b"\x00\x00\x02", b"\x00\x00\x10"))

    def test_zero_thumbnail_jfif_is_accepted(self) -> None:
        jfif = b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        self.assertEqual((1, 1), parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif)))

    def test_jfif_supported_boundary_fields_are_accepted(self) -> None:
        boundary = jfif_payload(version=(1, 2), units=2, x_density=1, y_density=65_535)
        self.assertEqual((1, 1), parse_jpeg(with_segment(minimal_jpeg(), 0xE0, boundary)))

    def test_jfif_version_100_is_accepted(self) -> None:
        try:
            dimensions = parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif_payload(version=(1, 0))))
        except ContractError as error:
            self.fail(f"valid JFIF 1.00 record was rejected: {error}")
        self.assertEqual((1, 1), dimensions)

    def test_jfif_version_is_validated(self) -> None:
        for version in ((0, 99), (1, 3), (2, 0)):
            with self.subTest(version=version), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif_payload(version=version)))

    def test_jfif_density_unit_is_validated(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif_payload(units=3)))

    def test_jfif_densities_must_be_positive(self) -> None:
        for densities in ((0, 1), (1, 0)):
            payload = jfif_payload(x_density=densities[0], y_density=densities[1])
            with self.subTest(densities=densities), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), 0xE0, payload))

    def test_stuffed_entropy_and_restart_markers_are_accepted(self) -> None:
        entropy = b"\x01\xff\x00\xe1\xff\xd0\x02"
        mutated = minimal_jpeg().replace(b"\x01\xff\xd9", entropy + b"\xff\xd9", 1)
        self.assertEqual((1, 1), parse_jpeg(mutated))

    def test_restart_marker_outside_entropy_is_rejected(self) -> None:
        misplaced = minimal_jpeg()[:2] + b"\xff\xd0" + minimal_jpeg()[2:]
        with self.assertRaises(ContractError):
            parse_jpeg(misplaced)

    def test_malformed_marker_length_is_rejected(self) -> None:
        malformed = minimal_jpeg().replace(b"\xff\xdb\x00\x43", b"\xff\xdb\x00\x01", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(malformed)

    def test_app1_exif_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE1, b"Exif\x00\x00"))

    def test_app2_icc_profile_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE2, b"ICC_PROFILE\x00"))

    def test_app13_iptc_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xED, b"Photoshop 3.0\x00"))

    def test_app14_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xEE, b"Adobe"))

    def test_all_other_app_markers_are_rejected(self) -> None:
        for marker in (*range(0xE3, 0xED), 0xEF):
            with self.subTest(marker=marker), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), marker, b"metadata"))

    def test_comment_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xFE, b"comment"))

    def test_jfif_thumbnail_is_rejected(self) -> None:
        jfif = b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x01\x01"
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif))

    def test_missing_eoi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg()[:-2])

    def test_duplicate_eoi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg() + b"\xff\xd9")

    def test_bytes_after_eoi_are_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg() + b"trailing")

    def test_missing_soi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(b"\x00\x00" + minimal_jpeg()[2:])

    def test_duplicate_sof_is_rejected(self) -> None:
        frame = b"\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC0, frame))

    def test_zero_frame_dimension_is_rejected(self) -> None:
        zero_width = minimal_jpeg().replace(b"\x08\x00\x01\x00\x01", b"\x08\x00\x01\x00\x00", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(zero_width)

    def test_non_eight_bit_frame_precision_is_rejected(self) -> None:
        invalid = minimal_jpeg().replace(b"\xff\xc0\x00\x0b\x08", b"\xff\xc0\x00\x0b\x0c", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_zero_frame_sampling_factor_is_rejected(self) -> None:
        for sampling in (b"\x10", b"\x01"):
            invalid = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01" + sampling + b"\x00", 1)
            with self.subTest(sampling=sampling), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_frame_sampling_factor_four_is_accepted(self) -> None:
        for sampling in (b"\x41", b"\x14"):
            boundary = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01" + sampling + b"\x00", 1)
            with self.subTest(sampling=sampling):
                self.assertEqual((1, 1), parse_jpeg(boundary))

    def test_frame_sampling_factor_five_is_rejected(self) -> None:
        for sampling in (b"\x51", b"\x15"):
            invalid = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01" + sampling + b"\x00", 1)
            with self.subTest(sampling=sampling), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_frame_mcu_sample_block_total_is_bounded(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        oversized = b"\xff\xc0\x00\x11\x08\x00\x01\x00\x01\x03\x01\x22\x00\x02\x22\x00\x03\x22\x00"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg().replace(frame, oversized, 1))

    def test_frame_component_ids_must_be_unique_and_nonzero(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        zero_id = frame[:-3] + b"\x00\x11\x00"
        duplicate_id = b"\xff\xc0\x00\x0e\x08\x00\x01\x00\x01\x02\x01\x11\x00\x01\x11\x00"
        for name, invalid_frame in {"zero": zero_id, "duplicate": duplicate_id}.items():
            invalid = minimal_jpeg().replace(frame, invalid_frame, 1)
            with self.subTest(name=name), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_frame_quantization_selector_must_be_supported(self) -> None:
        invalid = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01\x11\x04", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_missing_sos_is_rejected(self) -> None:
        no_scan = minimal_jpeg().replace(b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00\x01", b"", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(no_scan)

    def test_empty_entropy_data_is_rejected(self) -> None:
        empty_scan = minimal_jpeg().replace(b"\x3f\x00\x01\xff\xd9", b"\x3f\x00\xff\xd9", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(empty_scan)

    def test_unlisted_structural_marker_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xDC, b"\x00\x01"))

    def test_duplicate_soi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg()[:2] + b"\xff\xd8" + minimal_jpeg()[2:])

    def test_duplicate_jfif_is_rejected(self) -> None:
        jfif = b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        duplicate = with_segment(with_segment(minimal_jpeg(), 0xE0, jfif), 0xE0, jfif)
        with self.assertRaises(ContractError):
            parse_jpeg(duplicate)

    def test_malformed_sof_length_is_rejected(self) -> None:
        valid_frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        short_frame = b"\xff\xc0\x00\x07\x08\x00\x01\x00\x01"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg().replace(valid_frame, short_frame, 1))

    def test_malformed_sos_length_is_rejected(self) -> None:
        valid_scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        malformed_scan = b"\xff\xda\x00\x06\x00\x00\x3f\x00"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg().replace(valid_scan, malformed_scan, 1))

    def test_baseline_scan_spectral_selection_is_validated(self) -> None:
        invalid = minimal_jpeg().replace(b"\x00\x3f\x00\x01\xff\xd9", b"\x01\x3f\x00\x01\xff\xd9", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_scan_selector_must_reference_frame_component(self) -> None:
        invalid = minimal_jpeg().replace(b"\xff\xda\x00\x08\x01\x01\x00", b"\xff\xda\x00\x08\x01\x02\x00", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_scan_component_selectors_must_be_unique(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        two_component_frame = b"\xff\xc0\x00\x0e\x08\x00\x01\x00\x01\x02\x01\x11\x00\x02\x11\x00"
        scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        duplicate_scan = b"\xff\xda\x00\x0a\x02\x01\x00\x01\x00\x00\x3f\x00"
        invalid = minimal_jpeg().replace(frame, two_component_frame, 1).replace(scan, duplicate_scan, 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_scan_huffman_table_selectors_must_be_supported(self) -> None:
        for tables in (b"\x40", b"\x04"):
            invalid = minimal_jpeg().replace(b"\xff\xda\x00\x08\x01\x01\x00", b"\xff\xda\x00\x08\x01\x01" + tables, 1)
            with self.subTest(tables=tables), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_progressive_scan_fields_are_validated(self) -> None:
        progressive = minimal_jpeg().replace(b"\xff\xc0", b"\xff\xc2", 1)
        invalid_fields = {
            "dc_end": b"\x00\x01\x00",
            "spectral_order": b"\x05\x04\x00",
            "approximation_low": b"\x01\x3f\x0e",
            "approximation_high": b"\x01\x3f\xe0",
            "approximation_step": b"\x01\x3f\x20",
        }
        for name, fields in invalid_fields.items():
            invalid = progressive.replace(b"\x00\x3f\x00\x01\xff\xd9", fields + b"\x01\xff\xd9", 1)
            with self.subTest(name=name), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_progressive_ac_scan_has_one_component(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        progressive_frame = b"\xff\xc2\x00\x0e\x08\x00\x01\x00\x01\x02\x01\x11\x00\x02\x11\x00"
        scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        ac_scan = b"\xff\xda\x00\x0a\x02\x01\x00\x02\x00\x01\x3f\x00"
        invalid = minimal_jpeg().replace(frame, progressive_frame, 1).replace(scan, ac_scan, 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_malformed_dri_length_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xDD, b""))

    def test_malformed_dqt_length_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xDB, b""))

    def test_malformed_dht_length_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC4, b""))

    def test_oversubscribed_huffman_tree_is_rejected(self) -> None:
        payload = b"\x00\x03" + b"\x00" * 15 + b"\x00\x01\x02"
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC4, payload))

    def test_excessive_huffman_symbol_count_is_rejected(self) -> None:
        dc_counts = b"\x00" * 3 + b"\x0d" + b"\x00" * 12
        ac_counts = b"\x00" * 7 + b"\xa3" + b"\x00" * 8
        payloads = {
            "dc": b"\x00" + dc_counts + bytes(range(13)),
            "ac": b"\x10" + ac_counts + bytes(range(163)),
        }
        for table_class, payload in payloads.items():
            with self.subTest(table_class=table_class), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), 0xC4, payload))

    def test_empty_huffman_table_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC4, b"\x00" * 17))

    def test_sos_before_sof_is_rejected(self) -> None:
        scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00\x01"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg()[:2] + scan + minimal_jpeg()[2:])

    def test_sanitized_jpegs_have_exact_dimensions_and_budgets(self) -> None:
        total = 0
        for name, dimensions in EXPECTED_IMAGES.items():
            path = ASSETS / name
            self.assertTrue(path.is_file() and not path.is_symlink())
            self.assertEqual(dimensions, parse_jpeg(path))
            size = path.stat().st_size
            total += size
        self.assertLessEqual(total, MAX_TOTAL_IMAGE_BYTES)
