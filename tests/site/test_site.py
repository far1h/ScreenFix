from __future__ import annotations

import re
import shutil
import stat
import tempfile
import unittest
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "site" / "assets"

EXPECTED_SITE_FILES = {
    ".nojekyll",
    "index.html",
    "styles.css",
    "assets/screenfix-icon.svg",
    "assets/damaged-display.jpg",
    "assets/result-calibration.jpg",
    "assets/result-mask.jpg",
}

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
PUBLIC_VISIT_NUMBER = re.compile(
    r"^(?:(?:visits?|visitors?|views?)\s*:?\s*\d[\d,. ]*|\d[\d,. ]*\s+(?:visits?|visitors?|views?))$",
    re.IGNORECASE,
)
VOID_ELEMENTS = frozenset({"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"})


@dataclass
class HtmlNode:
    """Represent one parsed HTML element and its descendants."""

    tag: str
    attrs: dict[str, str | None]
    parent: HtmlNode | None = None
    children: list[HtmlNode] = field(default_factory=list)
    data: list[str] = field(default_factory=list)

    def text(self) -> str:
        """Return normalized descendant text."""
        chunks = [*self.data]
        for child in self.children:
            if child.tag not in {"script", "style"}:
                chunks.append(child.text())
        return " ".join(" ".join(chunks).split())


class LandingPageParser(HTMLParser):
    """Parse the landing page into a small semantic inspection model."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.doctype = ""
        self.elements: list[HtmlNode] = []
        self.stack: list[HtmlNode] = []
        self.errors: list[str] = []

    def handle_decl(self, decl: str) -> None:
        """Record the document type declaration."""
        self.doctype = decl.lower()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Record an element and connect it to its parent."""
        normalized_attrs: list[tuple[str, str | None]] = []
        attribute_names: set[str] = set()
        for name, value in attrs:
            normalized_name = name.lower()
            if normalized_name in attribute_names:
                raise ContractError(f"duplicate HTML attribute: {normalized_name}")
            attribute_names.add(normalized_name)
            normalized_attrs.append((normalized_name, value))
        parent = self.stack[-1] if self.stack else None
        node = HtmlNode(tag, dict(normalized_attrs), parent)
        if parent is not None:
            parent.children.append(node)
        self.elements.append(node)
        if tag not in VOID_ELEMENTS:
            self.stack.append(node)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Record an explicitly self-closing HTML void element."""
        if tag.lower() not in VOID_ELEMENTS:
            raise ContractError(f"self-closing HTML tag is not void: {tag.lower()}")
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        """Require properly nested closing tags."""
        if not self.stack or self.stack[-1].tag != tag:
            self.errors.append(f"unexpected closing tag: {tag}")
            return
        self.stack.pop()

    def handle_data(self, data: str) -> None:
        """Record element text for accessible-name and copy checks."""
        if self.stack:
            self.stack[-1].data.append(data)

    def nodes(self, tag: str) -> list[HtmlNode]:
        """Return every node with the requested tag."""
        return [node for node in self.elements if node.tag == tag]

    def by_id(self, identifier: str) -> list[HtmlNode]:
        """Return every node with the requested ID."""
        return [node for node in self.elements if node.attrs.get("id") == identifier]

    @property
    def landmarks(self) -> dict[str, list[HtmlNode]]:
        """Return the semantic page landmarks grouped by tag."""
        return {tag: self.nodes(tag) for tag in ("header", "nav", "main", "footer")}

    @property
    def headings(self) -> list[HtmlNode]:
        """Return all HTML headings in source order."""
        return [node for node in self.elements if re.fullmatch(r"h[1-6]", node.tag)]

    @property
    def ids(self) -> list[str]:
        """Return all element IDs in source order."""
        return [identifier for node in self.elements if (identifier := node.attrs.get("id"))]

    @property
    def links(self) -> list[HtmlNode]:
        """Return all anchors in source order."""
        return self.nodes("a")

    @property
    def images(self) -> list[HtmlNode]:
        """Return all images in source order."""
        return self.nodes("img")

    @property
    def scripts(self) -> list[HtmlNode]:
        """Return all scripts in source order."""
        return self.nodes("script")

    @property
    def details_summaries(self) -> list[tuple[HtmlNode, list[HtmlNode]]]:
        """Return native disclosure elements with their direct summaries."""
        return [
            (detail, [child for child in detail.children if child.tag == "summary"])
            for detail in self.nodes("details")
        ]

    @property
    def class_tokens(self) -> set[str]:
        """Return every token from class attributes."""
        return {
            token
            for node in self.elements
            for token in (node.attrs.get("class") or "").split()
        }

    @property
    def visible_text_nodes(self) -> list[str]:
        """Return normalized non-script and non-style text nodes."""
        return [
            normalized
            for node in self.elements
            if node.tag not in {"script", "style"}
            for value in node.data
            if (normalized := " ".join(value.split()))
        ]


def parse_landing_page(path: Path = ROOT / "site" / "index.html") -> LandingPageParser:
    """Parse one landing-page file and require balanced HTML elements."""
    parser = LandingPageParser()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    if parser.stack:
        parser.errors.append(f"unclosed tag: {parser.stack[-1].tag}")
    if parser.errors:
        raise ContractError("; ".join(parser.errors))
    return parser


def validate_landing_page(path: Path) -> None:
    """Validate mutation-sensitive landing-page semantics."""
    page = parse_landing_page(path)
    _validate_hero(page)
    _validate_marketing_exclusions(page)
    _validate_required_visibility(page)
    _validate_label_references(page)
    _validate_nonempty_aria_labels(page)
    _validate_public_counter(page)
    _validate_sections(page)
    _validate_references(page)
    _validate_script(page)
    _validate_faq(page)
    _validate_downloads(page)
    _validate_image_alts(page)


def _validate_hero(page: LandingPageParser) -> None:
    """Require the direct reviewed hero opening."""
    hero_copy = [node for node in page.elements if "hero-copy" in (node.attrs.get("class") or "").split()]
    if len(hero_copy) != 1:
        raise ContractError("hero copy must appear exactly once")
    substantive = [child for child in hero_copy[0].children if child.text()]
    if not substantive or substantive[0].tag != "h1":
        raise ContractError("hero heading must be first visible content")
    forbidden = {"eyebrow", "kicker", "preheading"}
    if page.class_tokens & forbidden:
        raise ContractError("hero heading must be first without promotional preheading")


def _validate_marketing_exclusions(page: LandingPageParser) -> None:
    """Reject standalone claims and generic proof-region patterns."""
    standalone_claims = {"Free and MIT licensed", "Runs locally", "No app telemetry"}
    if standalone_claims.intersection(page.visible_text_nodes):
        raise ContractError("standalone trust claim is forbidden")
    forbidden = ("trust-strip", "statistic-strip", "badge-cloud", "testimonial", "social-proof")
    names = page.class_tokens | set(page.ids)
    if any(term in name.lower() for name in names for term in forbidden):
        raise ContractError("generic marketing proof regions are forbidden")


def _validate_required_visibility(page: LandingPageParser) -> None:
    """Keep the reviewed header, content, and footer exposed to assistive technology."""
    scopes = page.nodes("header") + page.nodes("main") + page.nodes("footer")
    required_tags = {
        "a",
        "article",
        "details",
        "figcaption",
        "figure",
        "footer",
        "header",
        "img",
        "li",
        "main",
        "nav",
        "p",
        "section",
        "summary",
    }
    required_classes = {
        "download-option",
        "download-pair",
        "hero",
        "hero-copy",
        "hero-figure",
        "how-step",
        "step-number",
    }
    for node in page.elements:
        is_heading = re.fullmatch(r"h[1-6]", node.tag) is not None
        classes = set((node.attrs.get("class") or "").split())
        is_required = node.tag in required_tags or is_heading or bool(classes & required_classes)
        if is_required and _is_within_any(node, scopes) and _is_hidden(node):
            raise ContractError("required content must remain visible")


def _is_within_any(node: HtmlNode, ancestors: list[HtmlNode]) -> bool:
    """Return whether a node is or descends from one of the supplied elements."""
    current: HtmlNode | None = node
    while current is not None:
        if any(current is ancestor for ancestor in ancestors):
            return True
        current = current.parent
    return False


def _is_hidden(node: HtmlNode) -> bool:
    """Return whether HTML or ARIA hides a node through its ancestor chain."""
    current: HtmlNode | None = node
    while current is not None:
        aria_hidden = (current.attrs.get("aria-hidden") or "").strip().lower()
        if "hidden" in current.attrs or "inert" in current.attrs or aria_hidden == "true":
            return True
        current = current.parent
    return False


def _name_from_contents(node: HtmlNode, include_hidden: bool = False) -> str:
    """Return normalized text and descendant image alternatives for a name."""
    if not include_hidden and _is_hidden(node):
        return ""
    if node.tag == "img":
        return (node.attrs.get("alt") or "").strip()
    chunks = [*node.data]
    chunks.extend(
        _name_from_contents(child, include_hidden)
        for child in node.children
        if child.tag not in {"script", "style"}
    )
    return " ".join(" ".join(chunks).split())


def _validate_label_references(page: LandingPageParser) -> None:
    """Require every ARIA labelled-by token to resolve to one named element."""
    for node in page.elements:
        if "aria-labelledby" not in node.attrs:
            continue
        _labelledby_text(page, node)


def _labelledby_text(page: LandingPageParser, node: HtmlNode) -> str:
    """Resolve one element's labelled-by references to visible normalized text."""
    tokens = (node.attrs.get("aria-labelledby") or "").split()
    labels: list[str] = []
    for token in tokens:
        targets = page.by_id(token)
        if len(targets) != 1:
            raise ContractError("aria-labelledby target must resolve to one named element")
        label = _name_from_contents(targets[0], include_hidden=True).strip()
        if not label:
            raise ContractError("aria-labelledby target must resolve to one named element")
        labels.append(label)
    if not labels:
        raise ContractError("aria-labelledby target must resolve to one named element")
    return " ".join(labels)


def _validate_nonempty_aria_labels(page: LandingPageParser) -> None:
    """Reject blank labels where this page requires an explicit landmark name."""
    for node in page.elements:
        has_blank_label = (
            "aria-label" in node.attrs
            and not (node.attrs.get("aria-label") or "").strip()
        )
        if has_blank_label and node.tag != "a":
            raise ContractError("accessible name attribute must be non-empty")


def _validate_public_counter(page: LandingPageParser) -> None:
    """Reject known public visit-counter identifiers and data attributes."""
    prefixes = ("gc-number", "public-counter", "visit-counter", "visitor-counter")
    data_attributes = {
        "data-public-counter",
        "data-visit-counter",
        "data-visitor-counter",
        "data-gc-number",
    }
    for node in page.elements:
        identifiers = [(node.attrs.get("id") or "").lower()]
        identifiers.extend(token.lower() for token in (node.attrs.get("class") or "").split())
        if any(_is_counter_identifier(identifier, prefixes) for identifier in identifiers):
            raise ContractError("public visit counter markup is forbidden")
        attribute_names = {name.lower() for name in node.attrs}
        has_counter_data = bool(attribute_names & data_attributes)
        has_goatcounter_data = node.tag != "script" and any(
            name.startswith("data-goatcounter") for name in attribute_names
        )
        if has_counter_data or has_goatcounter_data:
            raise ContractError("public visit counter markup is forbidden")
    rendered_text = [node.text() for node in page.elements if node.tag not in {"script", "style"}]
    if any(PUBLIC_VISIT_NUMBER.fullmatch(text) for text in rendered_text):
        raise ContractError("rendered visit number is forbidden")


def _is_counter_identifier(identifier: str, prefixes: tuple[str, ...]) -> bool:
    """Return whether an ID or class token denotes a public counter."""
    return any(
        identifier == prefix or identifier.startswith((f"{prefix}-", f"{prefix}_"))
        for prefix in prefixes
    )


def _validate_script(page: LandingPageParser) -> None:
    """Require only the exact privacy-reviewed GoatCounter script."""
    if len(page.scripts) != 1:
        raise ContractError("landing page must contain exactly one script")
    expected = {
        "data-goatcounter": "https://farihmhmd.goatcounter.com/count",
        "async": None,
        "src": "https://gc.zgo.at/count.js",
    }
    if page.scripts[0].attrs != expected or page.scripts[0].text():
        raise ContractError("GoatCounter script attributes must match the privacy contract")


def _validate_references(page: LandingPageParser) -> None:
    """Require contained local references and explicit HTTPS external URLs."""
    references = [
        reference
        for node in page.elements
        for attribute in ("href", "src")
        if (reference := node.attrs.get(attribute))
    ]
    if any(reference.startswith("//") for reference in references):
        raise ContractError("protocol-relative URL is forbidden")
    for reference in references:
        parsed = urlsplit(reference)
        if parsed.scheme and parsed.scheme != "https":
            raise ContractError("external references must use HTTPS")
        if parsed.hostname in {"localhost", "127.0.0.1", "::1"}:
            raise ContractError("localhost references are forbidden")
        if not parsed.scheme and (parsed.netloc or parsed.path.startswith("/") or ".." in Path(parsed.path).parts):
            raise ContractError("internal reference escapes the site directory")
        if not parsed.scheme and parsed.fragment and parsed.fragment not in page.ids:
            raise ContractError("internal anchor does not resolve")
    if any(not _accessible_name(page, link) for link in page.links):
        raise ContractError("link accessible names must be descriptive")


def _accessible_name(page: LandingPageParser, node: HtmlNode) -> str:
    """Return the first available explicit or content-derived name."""
    aria_label = (node.attrs.get("aria-label") or "").strip()
    if aria_label:
        return aria_label
    if "aria-labelledby" in node.attrs:
        return _labelledby_text(page, node)
    return _name_from_contents(node)


def _validate_sections(page: LandingPageParser) -> None:
    """Require the six unique content sections in reviewed order."""
    section_ids = [node.attrs.get("id") for node in page.nodes("section") if node.attrs.get("id")]
    if len(section_ids) != len(set(section_ids)):
        raise ContractError("duplicate section ID is forbidden")
    expected = ["how", "results", "downloads", "privacy", "requirements", "faq"]
    if section_ids != expected:
        raise ContractError("section IDs do not match the approved order")


def _validate_faq(page: LandingPageParser) -> None:
    """Require four ordered native disclosures with answers."""
    faq_sections = page.by_id("faq")
    if len(faq_sections) != 1:
        raise ContractError("FAQ section must appear exactly once")
    faq_details = [node for node in faq_sections[0].children if node.tag == "details"]
    relationships = [
        (detail, summaries)
        for detail, summaries in page.details_summaries
        if any(detail is candidate for candidate in faq_details)
    ]
    questions = [summaries[0].text() if summaries else "" for _, summaries in relationships]
    expected = [
        "Does ScreenFix repair the damaged panel?",
        "Which windows may remain unchanged?",
        "Why does my operating system warn about ScreenFix?",
        "When does ScreenFix need macOS Accessibility permission?",
    ]
    if len(relationships) != 4 or any(not question for question in questions):
        raise ContractError("FAQ summary must be non-empty in each of four details")
    for detail, summaries in relationships:
        if len(summaries) != 1 or detail.children[0] is not summaries[0]:
            raise ContractError("FAQ summary must be non-empty and first in details")
        if not any(child.text() for child in detail.children[1:]):
            raise ContractError("FAQ answer must be non-empty")
    if questions != expected:
        raise ContractError("FAQ order does not match the approved contract")


def _validate_downloads(page: LandingPageParser) -> None:
    """Require stable native release filenames and placement."""
    windows_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64.exe"
    macos_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-macos-arm64.zip"
    fallback_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64-uncompressed.exe"
    primary = [
        node.attrs.get("href")
        for node in page.nodes("a")
        if "download-primary" in (node.attrs.get("class") or "").split()
    ]
    fallback = [
        node.attrs.get("href")
        for node in page.nodes("a")
        if "download-fallback" in (node.attrs.get("class") or "").split()
    ]
    if primary != [windows_url, macos_url, windows_url, macos_url] or fallback != [fallback_url]:
        raise ContractError("native download filename does not match the release contract")


def _validate_image_alts(page: LandingPageParser) -> None:
    """Require alt attributes and descriptions for product photographs."""
    for image in page.images:
        if "alt" not in image.attrs:
            raise ContractError("image alt attribute must describe each product photograph")
        if (image.attrs.get("alt") or "").strip():
            continue
        parent_classes = (image.parent.attrs.get("class") or "").split() if image.parent else []
        is_brand_icon = image.attrs.get("src") == "assets/screenfix-icon.svg" and "brand" in parent_classes
        if not is_brand_icon:
            raise ContractError("empty image alt is reserved for the brand icon")


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


class LandingPageContractTests(unittest.TestCase):
    def assert_mutation_rejected(self, old: str, new: str, message: str) -> None:
        """Mutate a temporary page copy and require a specific rejection."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            self.assertIn(old, source)
            path.write_text(source.replace(old, new, 1), encoding="utf-8")
            with self.assertRaisesRegex(ContractError, message):
                validate_landing_page(path)

    def test_exact_site_tree(self) -> None:
        site = ROOT / "site"
        actual = {
            path.relative_to(site).as_posix()
            for path in site.rglob("*")
            if path.is_symlink() or not path.is_dir()
        }
        self.assertEqual(EXPECTED_SITE_FILES, actual)
        for relative_path in EXPECTED_SITE_FILES:
            path = site / relative_path
            status = path.lstat()
            self.assertTrue(stat.S_ISREG(status.st_mode), relative_path)
            if relative_path == ".nojekyll":
                self.assertEqual(0, status.st_size)
            else:
                self.assertGreater(status.st_size, 0, relative_path)
        styles = (site / "styles.css").read_text(encoding="utf-8")
        self.assertIsNotNone(re.fullmatch(r"\s*/\*.*\*/\s*", styles, re.DOTALL))

    def test_document_metadata_landmarks_and_hero(self) -> None:
        page = parse_landing_page()
        self.assertEqual("doctype html", page.doctype)
        html = page.nodes("html")
        self.assertEqual(1, len(html))
        self.assertEqual("en", html[0].attrs.get("lang"))

        metas = page.nodes("meta")
        self.assertTrue(any(meta.attrs.get("charset", "").lower() == "utf-8" for meta in metas))
        self.assertTrue(
            any(
                meta.attrs.get("name") == "viewport"
                and meta.attrs.get("content") == "width=device-width, initial-scale=1"
                for meta in metas
            )
        )
        self.assertTrue(
            any(
                meta.attrs.get("name") == "description"
                and meta.attrs.get("content")
                == "ScreenFix masks a damaged vertical display strip and keeps ordinary windows in the usable space on either side."
                for meta in metas
            )
        )
        self.assertEqual(["ScreenFix — Work around a damaged screen"], [node.text() for node in page.nodes("title")])
        links = page.nodes("link")
        self.assertTrue(any(node.attrs.get("rel") == "canonical" and node.attrs.get("href") == "https://far1h.github.io/ScreenFix/" for node in links))
        self.assertTrue(any(node.attrs.get("rel") == "icon" and node.attrs.get("href") == "assets/screenfix-icon.svg" for node in links))
        self.assertTrue(any(node.attrs.get("rel") == "stylesheet" and node.attrs.get("href") == "styles.css" for node in links))

        for landmark, nodes in page.landmarks.items():
            self.assertEqual(1, len(nodes), landmark)
        main = page.nodes("main")[0]
        self.assertEqual("content", main.attrs.get("id"))
        skip_links = [node for node in page.nodes("a") if "skip-link" in (node.attrs.get("class") or "").split()]
        self.assertEqual([("#content", "Skip to content")], [(node.attrs.get("href"), node.text()) for node in skip_links])

        nav_links = [(node.text(), node.attrs.get("href")) for node in page.nodes("nav")[0].children if node.tag == "a"]
        self.assertEqual(
            [
                ("How it works", "#how"),
                ("Results", "#results"),
                ("Downloads", "#downloads"),
                ("Help", "#faq"),
                ("GitHub", "https://github.com/far1h/ScreenFix"),
            ],
            nav_links,
        )
        brand_images = [node for node in page.nodes("header")[0].children if node.tag == "a" for node in node.children if node.tag == "img"]
        self.assertEqual(1, len(brand_images))
        self.assertEqual("assets/screenfix-icon.svg", brand_images[0].attrs.get("src"))
        self.assertEqual("", brand_images[0].attrs.get("alt"))

        headings = page.nodes("h1")
        self.assertEqual(["Work around a damaged screen."], [heading.text() for heading in headings])
        hero_copy = [node for node in page.elements if "hero-copy" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(hero_copy))
        substantive_children = [child for child in hero_copy[0].children if child.text()]
        self.assertTrue(substantive_children)
        self.assertIs(headings[0], substantive_children[0])
        explanations = [node for node in hero_copy[0].children if "hero-explanation" in (node.attrs.get("class") or "").split()]
        self.assertEqual(
            ["ScreenFix blacks out the broken strip and keeps ordinary windows in the space that still works."],
            [node.text() for node in explanations],
        )

    def test_sections_steps_and_project_images(self) -> None:
        page = parse_landing_page()
        section_ids = ("how", "results", "downloads", "privacy", "requirements", "faq")
        self.assertEqual(6, len(page.nodes("section")))
        self.assertEqual(
            list(section_ids),
            [node.attrs["id"] for node in page.nodes("section") if node.attrs.get("id") in section_ids],
        )
        for identifier in section_ids:
            sections = page.by_id(identifier)
            self.assertEqual(1, len(sections), identifier)
            self.assertTrue(any(child.tag == "h2" and child.text() for child in sections[0].children), identifier)

        section_headings = [page.by_id(identifier)[0].children[0].text() for identifier in section_ids]
        self.assertEqual(
            [
                "Give the damage its own space.",
                "What it looks like in use.",
                "Download ScreenFix.",
                "ScreenFix stays on your computer.",
                "Requirements and limits.",
                "Questions before you download.",
            ],
            section_headings,
        )

        how = page.by_id("how")[0]
        steps = [node for node in how.children if node.tag == "article"]
        self.assertEqual(3, len(steps))
        expected_steps = [
            ("1", "Mark the damaged strip.", "Open calibration and drag the guides to mark the damaged strip on the selected display."),
            ("2", "Keep it dark.", "Save the calibration to place an opaque black mask over the damaged strip."),
            ("3", "Use the remaining space.", "ScreenFix keeps ordinary movable windows inside the usable space on either side."),
        ]
        actual_steps = []
        for step in steps:
            number = [node.text() for node in step.children if "step-number" in (node.attrs.get("class") or "").split()]
            heading = [node.text() for node in step.children if node.tag == "h3"]
            copy = [node.text() for node in step.children if node.tag == "p"]
            self.assertEqual((1, 1, 1), (len(number), len(heading), len(copy)))
            actual_steps.append((number[0], heading[0], copy[0]))
        self.assertEqual(expected_steps, actual_steps)

        hero_images = [node for node in page.nodes("img") if node.attrs.get("src") == "assets/damaged-display.jpg"]
        self.assertEqual(1, len(hero_images))
        self.assertEqual(
            {
                "alt": "Damaged display with a dark vertical strip through the screen",
                "width": "1200",
                "height": "900",
                "loading": "eager",
                "fetchpriority": "high",
            },
            {key: hero_images[0].attrs.get(key) for key in ("alt", "width", "height", "loading", "fetchpriority")},
        )

        figures = [node for node in page.by_id("results")[0].children if node.tag == "figure"]
        self.assertEqual(2, len(figures))
        expected_figures = [
            (
                "assets/result-calibration.jpg",
                "Three color bands marking the damaged display strip during calibration",
                "Calibration uses three bands to define the stepped damaged area.",
            ),
            (
                "assets/result-mask.jpg",
                "Black mask covering the saved damaged strip on the display",
                "After saving, an opaque mask keeps the damaged strip dark.",
            ),
        ]
        actual_figures = []
        for figure in figures:
            images = [child for child in figure.children if child.tag == "img"]
            captions = [child for child in figure.children if child.tag == "figcaption"]
            self.assertEqual((1, 1), (len(images), len(captions)))
            image = images[0]
            self.assertEqual(
                ("1200", "675", "lazy", "async"),
                tuple(image.attrs.get(key) for key in ("width", "height", "loading", "decoding")),
            )
            self.assertTrue(image.attrs.get("alt"))
            self.assertTrue(captions[0].text())
            actual_figures.append((image.attrs.get("src"), image.attrs.get("alt"), captions[0].text()))
        self.assertEqual(expected_figures, actual_figures)

    def test_hero_photo_uses_contextual_figure_and_caption(self) -> None:
        page = parse_landing_page()
        hero_figures = [
            node
            for node in page.nodes("figure")
            if "hero-figure" in (node.attrs.get("class") or "").split()
        ]
        self.assertEqual(1, len(hero_figures))
        images = [child for child in hero_figures[0].children if child.tag == "img"]
        captions = [child for child in hero_figures[0].children if child.tag == "figcaption"]
        self.assertEqual(1, len(images))
        self.assertEqual("assets/damaged-display.jpg", images[0].attrs.get("src"))
        self.assertEqual(
            ["The damaged display has a wide broken vertical strip through its center."],
            [caption.text() for caption in captions],
        )
        self.assertEqual(3, len(page.nodes("figure")))

    def test_generic_hero_has_no_aria_name_or_role(self) -> None:
        page = parse_landing_page()
        heroes = [node for node in page.elements if "hero" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(heroes))
        self.assertEqual("div", heroes[0].tag)
        self.assertTrue(
            {"aria-label", "aria-labelledby", "role"}.isdisjoint(heroes[0].attrs)
        )

    def test_native_downloads_are_primary_and_release_links_are_exact(self) -> None:
        page = parse_landing_page()
        windows_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64.exe"
        macos_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-macos-arm64.zip"
        fallback_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64-uncompressed.exe"
        releases_url = "https://github.com/far1h/ScreenFix/releases/latest"

        primary = [node for node in page.nodes("a") if "download-primary" in (node.attrs.get("class") or "").split()]
        self.assertEqual(
            [windows_url, macos_url, windows_url, macos_url],
            [node.attrs.get("href") for node in primary],
        )
        for link in primary:
            self.assertRegex(link.text(), r"Windows x64|macOS Apple Silicon")

        fallback = [node for node in page.nodes("a") if "download-fallback" in (node.attrs.get("class") or "").split()]
        self.assertEqual([(fallback_url, "Windows x64 uncompressed fallback")], [(node.attrs.get("href"), node.text()) for node in fallback])
        release_links = [node for node in page.nodes("a") if node.attrs.get("href") == releases_url]
        self.assertTrue(release_links)
        self.assertIn("Releases and versioned checksums", [node.text() for node in release_links])
        self.assertTrue(all("download-primary" not in (node.attrs.get("class") or "").split() for node in fallback + release_links))

        heroes = [node for node in page.elements if "hero" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(heroes))
        self.assertEqual("div", heroes[0].tag)
        hero = heroes[0]
        hero_links = [node for node in hero.children[0].children if node.tag == "a"]
        self.assertEqual([windows_url, macos_url, releases_url], [node.attrs.get("href") for node in hero_links])

        downloads = page.by_id("downloads")[0]
        pairs = [node for node in downloads.children if "download-pair" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(pairs))
        options = [node for node in pairs[0].children if node.tag == "article"]
        self.assertEqual(["Windows x64", "macOS Apple Silicon"], [node.children[0].text() for node in options])
        windows_copy = options[0].text()
        for phrase in ("Intel or AMD x64 Windows", "self-contained", "no separate .NET runtime", "no ZIP extraction", "SmartScreen", "unsigned", "behavior-identical"):
            self.assertIn(phrase, windows_copy)
        macos_copy = options[1].text()
        for phrase in ("macOS 13 or later", "Apple Silicon", "not Intel", "Control-click", "ad hoc signed", "Accessibility", "automatic window placement", "Masks and calibration continue to work"):
            self.assertIn(phrase, macos_copy)

    def test_privacy_requirements_faq_and_footer_copy(self) -> None:
        page = parse_landing_page()
        privacy = page.by_id("privacy")[0].text()
        for phrase in (
            "does not capture the screen",
            "read window contents",
            "use the network",
            "send telemetry",
            "landing page uses GoatCounter",
            "privacy-friendly aggregate visit measurement",
            "count visits",
            "broad country-level traffic",
            "does not set tracking cookies",
            "briefly process an IP address and user agent in memory",
            "site owner does not receive or retain visitors’ IP addresses",
        ):
            self.assertIn(phrase, privacy)
        self.assertIn("only third-party analytics service used by this website", privacy)
        self.assertIn("does not display a public visit counter", privacy)
        self.assertNotIn("only third-party request", privacy)

        requirements = page.by_id("requirements")[0].text()
        for phrase in (
            "Intel or AMD x64 Windows",
            "macOS 13 or later on Apple Silicon",
            "not Intel Macs",
            "unsigned",
            "SmartScreen",
            "ad hoc signed",
            "not notarized",
            "Gatekeeper",
            "Accessibility permission",
            "physical display damage",
            "ordinary movable windows",
            "ordinary maximized Windows windows",
            "full-screen",
            "administrator",
        ):
            self.assertIn(phrase, requirements)

        questions = [
            "Does ScreenFix repair the damaged panel?",
            "Which windows may remain unchanged?",
            "Why does my operating system warn about ScreenFix?",
            "When does ScreenFix need macOS Accessibility permission?",
        ]
        faq = page.by_id("faq")[0]
        details = [node for node in faq.children if node.tag == "details"]
        self.assertEqual(4, len(details))
        actual_questions = []
        for detail in details:
            summaries = [node for node in detail.children if node.tag == "summary"]
            self.assertEqual(1, len(summaries))
            self.assertIs(detail.children[0], summaries[0])
            self.assertTrue(summaries[0].text())
            answers = [node for node in detail.children[1:] if node.text()]
            self.assertTrue(answers)
            actual_questions.append(summaries[0].text())
        self.assertEqual(questions, actual_questions)

        footer = page.nodes("footer")[0]
        self.assertIn("ScreenFix is an open-source utility for working around a damaged display strip.", footer.text())
        footer_links = [(node.text(), node.attrs.get("href")) for node in footer.children if node.tag == "a"]
        self.assertEqual(
            [
                ("Source", "https://github.com/far1h/ScreenFix"),
                ("Releases", "https://github.com/far1h/ScreenFix/releases/latest"),
                ("Advanced Hammerspoon setup", "https://github.com/far1h/ScreenFix#install-the-hammerspoon-version"),
                ("MIT license", "https://github.com/far1h/ScreenFix/blob/main/LICENSE"),
            ],
            footer_links,
        )
        self.assertEqual(1, sum("Hammerspoon" in text for text in page.visible_text_nodes))

    def test_references_analytics_accessibility_and_marketing_exclusions(self) -> None:
        page = parse_landing_page()
        validate_landing_page(ROOT / "site" / "index.html")
        site = ROOT / "site"
        identifiers = page.ids
        self.assertEqual(len(identifiers), len(set(identifiers)))

        for node in page.elements:
            for attribute in ("href", "src"):
                reference = node.attrs.get(attribute)
                if not reference:
                    continue
                self.assertFalse(reference.startswith("//"), reference)
                parsed = urlsplit(reference)
                if parsed.scheme:
                    self.assertEqual("https", parsed.scheme, reference)
                    continue
                self.assertFalse(parsed.netloc, reference)
                if parsed.path:
                    self.assertNotIn("..", Path(parsed.path).parts, reference)
                    resolved = (site / parsed.path).resolve()
                    self.assertTrue(resolved.is_relative_to(site.resolve()), reference)
                    self.assertTrue(resolved.is_file(), reference)
                if parsed.fragment:
                    self.assertIn(parsed.fragment, identifiers, reference)

        for link in page.links:
            self.assertTrue(link.attrs.get("href"))
            self.assertTrue(link.text() or link.attrs.get("aria-label"))
        for image in page.images:
            self.assertIn("alt", image.attrs)
            if image.attrs.get("src") != "assets/screenfix-icon.svg":
                self.assertTrue(image.attrs.get("alt"))

        scripts = page.scripts
        self.assertEqual(1, len(scripts))
        self.assertIsNotNone(scripts[0].parent)
        self.assertEqual("head", scripts[0].parent.tag)
        self.assertEqual(
            {
                "data-goatcounter": "https://farihmhmd.goatcounter.com/count",
                "async": None,
                "src": "https://gc.zgo.at/count.js",
            },
            scripts[0].attrs,
        )
        self.assertEqual("", scripts[0].text())

        banned_regions = (
            "eyebrow",
            "kicker",
            "trust-strip",
            "statistic-strip",
            "badge-cloud",
            "testimonial",
            "social-proof",
            "visible-counter",
            "glass",
            "glow",
        )
        names = page.class_tokens | {node.attrs.get("id", "") for node in page.elements}
        for name in names:
            self.assertFalse(any(term in name.lower() for term in banned_regions), name)
        standalone_claims = {"Free and MIT licensed", "Runs locally", "No app telemetry"}
        self.assertTrue(standalone_claims.isdisjoint(page.visible_text_nodes))
        visible_copy = " ".join(page.visible_text_nodes).lower()
        for forbidden in ("testimonial", "customer rating", "trusted by", "fake proof"):
            self.assertNotIn(forbidden, visible_copy)

        headings = page.headings
        levels = [int(node.tag[1]) for node in headings]
        self.assertEqual(1, levels[0])
        self.assertTrue(all(current <= previous + 1 for previous, current in zip(levels, levels[1:])))

    def test_eyebrow_before_h1_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<h1 id="hero-title">',
            '<p class="eyebrow">Desktop utility</p>\n          <h1 id="hero-title">',
            "hero heading must be first",
        )

    def test_standalone_trust_claim_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<p class="hero-explanation">ScreenFix blacks out the broken strip and keeps ordinary windows in the space that still works.</p>',
            '<p class="hero-explanation">ScreenFix blacks out the broken strip and keeps ordinary windows in the space that still works.</p>\n          <p>Free and MIT licensed</p>',
            "standalone trust claim",
        )

    def test_second_script_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'src="https://gc.zgo.at/count.js"></script>',
            'src="https://gc.zgo.at/count.js"></script>\n    <script src="https://example.com/second.js"></script>',
            "exactly one script",
        )

    def test_protocol_relative_goatcounter_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'src="https://gc.zgo.at/count.js"',
            'src="//gc.zgo.at/count.js"',
            "protocol-relative URL",
        )

    def test_missing_goatcounter_async_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "      async\n",
            "",
            "GoatCounter script attributes",
        )

    def test_wrong_native_filename_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "ScreenFix-Windows-x64.exe",
            "ScreenFix-Windows.exe",
            "native download filename",
        )

    def test_internal_parent_escape_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'href="assets/screenfix-icon.svg"',
            'href="../screenfix-icon.svg"',
            "internal reference escapes",
        )

    def test_duplicate_section_id_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'id="results" aria-labelledby="results-title"',
            'id="how" aria-labelledby="results-title"',
            "duplicate section ID",
        )

    def test_reordered_faq_mutation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            first_start = source.index("        <details>\n          <summary>Does ScreenFix repair")
            second_start = source.index("        <details>\n          <summary>Which windows")
            third_start = source.index("        <details>\n          <summary>Why does")
            reordered = source[:first_start] + source[second_start:third_start] + source[first_start:second_start] + source[third_start:]
            path.write_text(reordered, encoding="utf-8")
            with self.assertRaisesRegex(ContractError, "FAQ order"):
                validate_landing_page(path)

    def test_empty_faq_summary_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "<summary>Does ScreenFix repair the damaged panel?</summary>",
            "<summary></summary>",
            "FAQ summary must be non-empty",
        )

    def test_missing_image_alt_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '          alt="Damaged display with a dark vertical strip through the screen"\n',
            "",
            "image alt attribute",
        )

    def test_public_counter_id_mutations_are_rejected(self) -> None:
        mutations = {
            "gc-number": '<span id="gc-number">123 visits</span>',
            "public-counter": '<div id="public-counter">123 visits</div>',
        }
        for name, markup in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    '    <footer class="site-footer">',
                    f"    {markup}\n    <footer class=\"site-footer\">",
                    "public visit counter markup",
                )

    def test_public_counter_class_and_data_mutations_are_rejected(self) -> None:
        mutations = {
            "gc-number-class": '<span class="gc-number"></span>',
            "public-counter-class": '<div class="public-counter"></div>',
            "public-counter-data": '<span data-public-counter="visits"></span>',
        }
        for name, markup in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    '    <footer class="site-footer">',
                    f"    {markup}\n    <footer class=\"site-footer\">",
                    "public visit counter markup",
                )

    def test_rendered_visit_number_mutations_are_rejected(self) -> None:
        mutations = {
            "count-first": "<span>123 visits</span>",
            "label-first": "<strong>Visits: 1,234</strong>",
        }
        for name, markup in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    '    <footer class="site-footer">',
                    f"    {markup}\n    <footer class=\"site-footer\">",
                    "rendered visit number",
                )

    def test_duplicate_html_attribute_mutations_are_rejected(self) -> None:
        mutations = {
            "script-src": (
                'src="https://gc.zgo.at/count.js"',
                'src="http://unsafe.example/count.js" SRC="https://gc.zgo.at/count.js"',
                "src",
            ),
            "anchor-href": (
                'href="https://github.com/far1h/ScreenFix">GitHub',
                'href="../escape" HREF="https://github.com/far1h/ScreenFix">GitHub',
                "href",
            ),
            "image-src": (
                'src="assets/damaged-display.jpg"',
                'src="../escape.jpg" Src="assets/damaged-display.jpg"',
                "src",
            ),
        }
        for name, (old, new, attribute) in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    old,
                    new,
                    f"duplicate HTML attribute: {attribute}",
                )

    def test_required_content_visibility_mutations_are_rejected(self) -> None:
        mutations = {
            "hidden-main": (
                '<main id="content">',
                '<main id="content" hidden>',
            ),
            "aria-hidden-hero-copy": (
                '<div class="hero-copy">',
                '<div class="hero-copy" aria-hidden="true">',
            ),
            "inert-downloads": (
                '<section id="downloads" aria-labelledby="downloads-title">',
                '<section id="downloads" aria-labelledby="downloads-title" inert>',
            ),
        }
        for name, (old, new) in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    old,
                    new,
                    "required content must remain visible",
                )

    def test_missing_aria_labelledby_target_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<section id="how" aria-labelledby="how-title">',
            '<section id="how" aria-labelledby="missing-title">',
            "aria-labelledby target must resolve",
        )

    def test_whitespace_aria_label_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<nav aria-label="Primary navigation">',
            '<nav aria-label="   ">',
            "accessible name attribute must be non-empty",
        )

    def test_link_labelledby_visible_text_is_accepted(self) -> None:
        markup = (
            '<span id="external-link-label">Project mirror</span>\n'
            '    <a href="https://example.com/project" aria-labelledby="external-link-label"></a>'
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            path.write_text(
                source.replace('    <footer class="site-footer">', f"    {markup}\n    <footer class=\"site-footer\">", 1),
                encoding="utf-8",
            )
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"visible aria-labelledby link name was rejected: {error}")

    def test_link_labelledby_hidden_text_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            old = '<a href="https://github.com/far1h/ScreenFix">GitHub</a>'
            new = (
                '<span id="github-link-label" hidden>GitHub repository</span>\n'
                '        <a href="https://github.com/far1h/ScreenFix" '
                'aria-labelledby="github-link-label"></a>'
            )
            self.assertIn(old, source)
            path.write_text(source.replace(old, new, 1), encoding="utf-8")
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"hidden referenced link label was rejected: {error}")

    def test_image_alt_only_link_name_is_accepted(self) -> None:
        markup = (
            '<a href="https://example.com/project">'
            '<img src="assets/screenfix-icon.svg" alt="Project mirror">'
            "</a>"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            path.write_text(
                source.replace('    <footer class="site-footer">', f"    {markup}\n    <footer class=\"site-footer\">", 1),
                encoding="utf-8",
            )
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"image-alt-only link name was rejected: {error}")

    def test_blank_aria_label_with_visible_link_text_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            old = '<a href="https://github.com/far1h/ScreenFix">GitHub</a>'
            new = '<a href="https://github.com/far1h/ScreenFix" aria-label="   ">GitHub</a>'
            self.assertIn(old, source)
            path.write_text(source.replace(old, new, 1), encoding="utf-8")
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"visible link fallback was rejected: {error}")

    def test_unnamed_external_link_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '    <footer class="site-footer">',
            '    <a href="https://example.com/project"></a>\n'
            '    <footer class="site-footer">',
            "link accessible names must be descriptive",
        )

    def test_empty_image_alt_is_limited_to_brand_icon(self) -> None:
        self.assert_mutation_rejected(
            '    <footer class="site-footer">',
            '    <img src="assets/screenfix-icon.svg" alt="">\n    <footer class="site-footer">',
            "empty image alt is reserved for the brand icon",
        )

    def test_non_void_self_closing_tag_mutations_are_rejected(self) -> None:
        mutations = {
            "script": (
                'src="https://gc.zgo.at/count.js"></script>',
                'src="https://gc.zgo.at/count.js" />',
            ),
            "div": (
                '    <footer class="site-footer">',
                '    <div class="empty" />\n    <footer class="site-footer">',
            ),
        }
        for tag, (old, new) in mutations.items():
            with self.subTest(tag=tag):
                self.assert_mutation_rejected(
                    old,
                    new,
                    f"self-closing HTML tag is not void: {tag}",
                )

    def test_self_closing_void_image_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            mutated = source.replace(
                '          >\n          <figcaption>The damaged display',
                '          />\n          <figcaption>The damaged display',
                1,
            )
            self.assertNotEqual(source, mutated)
            path.write_text(mutated, encoding="utf-8")
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"self-closing void image was rejected: {error}")


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
