from __future__ import annotations

import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path

from test_site import (
    CANONICAL_URL,
    HERO_HEADING,
    MAX_SITEMAP_BYTES,
    ROBOTS_DIRECTIVE,
    ROOT,
    SEO_DESCRIPTION,
    SEO_FAQ_ANSWER,
    SEO_TITLE,
    SITEMAP,
    SITEMAP_NAMESPACE,
    ContractError,
    LandingPageParser,
    _validate_faq,
    _validate_search_copy,
    _validate_seo_metadata,
    parse_landing_page,
    parse_landing_page_source,
    validate_sitemap,
)


class SeoContractTests(unittest.TestCase):
    def setUp(self) -> None:
        """Load the reviewed production sources used by focused mutations."""
        self.html = (ROOT / "site" / "index.html").read_text(encoding="utf-8")
        self.sitemap = SITEMAP.read_text(encoding="utf-8")

    def assert_page_mutation_rejected(
        self,
        old: str,
        new: str,
        validator: Callable[[LandingPageParser], None],
    ) -> None:
        """Apply one production-page mutation and require focused rejection."""
        self.assertIn(old, self.html)
        mutated = self.html.replace(old, new, 1)
        self.assertNotEqual(self.html, mutated)
        with self.assertRaises(ContractError):
            validator(parse_landing_page_source(mutated))

    def assert_sitemap_mutation_rejected(self, old: str, new: str) -> None:
        """Apply one sitemap mutation and require focused rejection."""
        self.assertIn(old, self.sitemap)
        mutated = self.sitemap.replace(old, new, 1)
        self.assertNotEqual(self.sitemap, mutated)
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "sitemap.xml"
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaises(ContractError):
                validate_sitemap(path)

    def test_live_metadata_copy_and_sitemap_match_the_reviewed_contract(self) -> None:
        """Require exact production metadata, search copy, FAQ, and sitemap content."""
        page = parse_landing_page()
        _validate_seo_metadata(page)
        _validate_search_copy(page)
        _validate_faq(page)
        validate_sitemap()

    def test_search_and_social_metadata_fields_are_unique(self) -> None:
        """Reject duplicates across title, description, canonical, robots, and social fields."""
        fields = [
            ("title", f"<title>{SEO_TITLE}</title>"),
            (
                "description",
                "<meta\n"
                '      name="description"\n'
                f'      content="{SEO_DESCRIPTION}"\n'
                "    >",
            ),
            ("canonical", f'<link rel="canonical" href="{CANONICAL_URL}">'),
            ("robots", f'<meta name="robots" content="{ROBOTS_DIRECTIVE}">'),
        ]
        page = parse_landing_page()
        for meta in page.nodes("meta"):
            identifier = meta.attrs.get("property") or meta.attrs.get("name") or ""
            if identifier.startswith(("og:", "twitter:")):
                attribute = "property" if "property" in meta.attrs else "name"
                fields.append(
                    (
                        identifier,
                        f'<meta {attribute}="{identifier}" content="{meta.attrs["content"]}">',
                    )
                )
        for name, markup in fields:
            with self.subTest(name=name):
                self.assert_page_mutation_rejected(
                    markup,
                    f"{markup}\n    {markup}",
                    _validate_seo_metadata,
                )

    def test_metadata_safety_relationship_and_image_mutations_are_rejected(self) -> None:
        """Reject unsafe URLs, mismatches, wrong robots, and malformed image metadata."""
        mutations = {
            "robots": (
                f'content="{ROBOTS_DIRECTIVE}"',
                'content="noindex, follow, max-image-preview:large"',
            ),
            "insecure canonical": (
                f'href="{CANONICAL_URL}"',
                'href="http://far1h.github.io/ScreenFix/"',
            ),
            "off-site social URL": (
                f'name="twitter:image" content="{CANONICAL_URL}assets/result-mask.jpg"',
                'name="twitter:image" content="https://example.com/result-mask.jpg"',
            ),
            "description mismatch": (
                f'name="twitter:description" content="{SEO_DESCRIPTION}"',
                'name="twitter:description" content="Different description"',
            ),
            "image width": (
                'property="og:image:width" content="1200"',
                'property="og:image:width" content="1201"',
            ),
            "image alt mismatch": (
                'name="twitter:image:alt" content="ScreenFix mask keeping windows inside the usable part of a damaged display"',
                'name="twitter:image:alt" content="Different image description"',
            ),
        }
        for name, (old, new) in mutations.items():
            with self.subTest(name=name):
                self.assert_page_mutation_rejected(old, new, _validate_seo_metadata)

    def test_keyword_stuffing_and_misleading_repair_copy_are_rejected(self) -> None:
        """Reject spammy intent copy and unsupported physical-repair claims."""
        mutations = {
            "keyword stuffing": (
                HERO_HEADING,
                f"{HERO_HEADING} Broken screen damaged screen usable screen.",
                _validate_search_copy,
            ),
            "repair claim": (
                SEO_FAQ_ANSWER,
                "ScreenFix repairs the panel, restores dead pixels, and controls every window.",
                _validate_faq,
            ),
        }
        for name, (old, new, validator) in mutations.items():
            with self.subTest(name=name):
                self.assert_page_mutation_rejected(old, new, validator)

    def test_sitemap_structure_and_global_markup_mutations_are_rejected(self) -> None:
        """Reject malformed, extra, volatile, commented, or styled sitemap structures."""
        root = f'<urlset xmlns="{SITEMAP_NAMESPACE}">'
        loc = f"    <loc>{CANONICAL_URL}</loc>"
        mutations = {
            "pre-root processing instruction": (
                root,
                '<?xml-stylesheet type="text/xsl" href="https://example.com/sitemap.xsl"?>\n'
                + root,
            ),
            "post-root processing instruction": (
                "</urlset>",
                "</urlset>\n<?xml-stylesheet type=\"text/xsl\" href=\"style.xsl\"?>",
            ),
            "pre-root comment": (root, "<!-- sitemap -->\n" + root),
            "post-root comment": ("</urlset>", "</urlset>\n<!-- sitemap -->"),
            "wrong namespace": (SITEMAP_NAMESPACE, "https://example.com/sitemap"),
            "wrong canonical": (CANONICAL_URL, "https://far1h.github.io/Other/"),
            "extra loc": (loc, f"{loc}\n{loc}"),
            "extra URL": (
                "  </url>\n</urlset>",
                f"  </url>\n  <url><loc>{CANONICAL_URL}</loc></url>\n</urlset>",
            ),
            "lastmod": ("  </url>", "    <lastmod>2026-08-29</lastmod>\n  </url>"),
            "changefreq": ("  </url>", "    <changefreq>monthly</changefreq>\n  </url>"),
            "priority": ("  </url>", "    <priority>1.0</priority>\n  </url>"),
            "malformed XML": ("</urlset>", ""),
        }
        for name, (old, new) in mutations.items():
            with self.subTest(name=name):
                self.assert_sitemap_mutation_rejected(old, new)

    def test_sitemap_file_shape_size_and_encoding_mutations_are_rejected(self) -> None:
        """Reject directories, symlinks, oversized files, and non-UTF-8 bytes."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            with self.assertRaisesRegex(ContractError, "regular non-symlink"):
                validate_sitemap(directory)

            target = directory / "target.xml"
            target.write_text(self.sitemap, encoding="utf-8")
            symlink = directory / "symlink.xml"
            symlink.symlink_to(target)
            with self.assertRaisesRegex(ContractError, "regular non-symlink"):
                validate_sitemap(symlink)

            oversized = directory / "oversized.xml"
            oversized.write_bytes(b" " * (MAX_SITEMAP_BYTES + 1))
            with self.assertRaisesRegex(ContractError, "bounded"):
                validate_sitemap(oversized)

            non_utf8 = directory / "non-utf8.xml"
            non_utf8.write_bytes(b"\xff")
            with self.assertRaisesRegex(ContractError, "UTF-8"):
                validate_sitemap(non_utf8)
