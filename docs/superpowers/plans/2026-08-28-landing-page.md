# ScreenFix Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify the approved dependency-free ScreenFix landing page, deploy it safely through GitHub Pages after merge, and open a pull request that closes issue #7.

**Architecture:** Commit one semantic HTML page, one CSS file, the canonical icon, and three flattened privacy-safe JPEG crops under `site/`; keep the standard-library contract tests under `tests/site/` so no test source is published. An unfiltered pull-request job validates every commit with read-only permissions, while main-only publish and deploy jobs upload the exact `site/` tree and reserve Pages write/OIDC permissions for deployment.

**Tech Stack:** HTML5, CSS3, Python 3 standard library (`unittest`, `html.parser`, binary JPEG parsing), macOS `sips` plus `jpegtran` for one-time derivative generation, GitHub Actions, GitHub Pages, GoatCounter.

**Approved specification:** `docs/superpowers/specs/2026-08-28-landing-page-design.md`

**Execution workspace:** `/Users/farihmuhammad/Downloads/ScreenFix/.worktrees/landing-page` on `feat/landing-page`

---

## File Map

- Create `tests/site/test_site.py` — production-site contract, HTML collector, JPEG marker parser, contrast calculator, workflow contract, and mutation regressions.
- Create `site/.nojekyll` — hidden Pages control file included in the published artifact.
- Create `site/index.html` — the only page, with the approved content order and exact GoatCounter tag.
- Create `site/styles.css` — approved tokens, typography, responsive layout, focus states, and reduced-motion behavior.
- Create `site/assets/screenfix-icon.svg` — exact byte-for-byte canonical icon copy.
- Create `site/assets/damaged-display.jpg` — 1200×900 sanitized hero crop.
- Create `site/assets/result-calibration.jpg` — 1200×675 sanitized calibration crop.
- Create `site/assets/result-mask.jpg` — 1200×675 sanitized result crop.
- Create `.github/workflows/pages.yml` — all-PR validation and main-only Pages publish/deploy.
- Modify `README.md` — add the Pages URL, `site/` to the concise file map, and one dependency-free validation command.

Native Lua, Swift, C#, release scripts, release workflows, release assets, and version files are outside the implementation file map and must remain byte-identical.

---

### Task 0: Commit the approved specification and implementation plan

**Files:**
- Modify: `docs/superpowers/specs/2026-08-28-landing-page-design.md`
- Create: `docs/superpowers/plans/2026-08-28-landing-page.md`

- [ ] **Step 1: Validate and stage only the two documents**

```bash
git diff --check
git add docs/superpowers/specs/2026-08-28-landing-page-design.md \
  docs/superpowers/plans/2026-08-28-landing-page.md
git diff --cached --check
git diff --cached --name-only
```

Expected: exactly the corrected specification and this implementation plan are staged.

- [ ] **Step 2: Commit the reviewed plan**

```bash
git commit -m "docs: plan ScreenFix landing page"
git status --short
```

Expected: the commit succeeds and the worktree is clean before Task 1 begins.

---

### Task 1: Privacy-safe image contract and committed assets

**Files:**
- Create: `tests/site/test_site.py`
- Create: `site/assets/screenfix-icon.svg`
- Create: `site/assets/damaged-display.jpg`
- Create: `site/assets/result-calibration.jpg`
- Create: `site/assets/result-mask.jpg`

- [ ] **Step 1: Add the focused image-contract tests**

Start `tests/site/test_site.py` with short helpers and tests for only the four assets. Resolve paths from the test file rather than the current directory:

```python
from __future__ import annotations

import struct
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


class ContractError(AssertionError):
    """Reports a stable landing-page contract failure."""


def parse_jpeg(path: Path) -> tuple[int, int]:
    """Return JPEG dimensions after validating a metadata-free marker stream."""
    # Read once, require SOI, walk marker lengths safely, parse optional zero-thumbnail
    # JFIF APP0, accept structural DQT/SOF0/SOF2/DHT/DRI/SOS/RST/EOI markers only,
    # skip byte-stuffed entropy, require non-empty scan bytes and one terminal EOI,
    # and reject APP1–APP15, COM, malformed lengths, duplicate SOF/EOI, or trailing bytes.
    raise NotImplementedError


class ImageContractTests(unittest.TestCase):
    def test_canonical_icon_copy_is_exact_and_script_free(self) -> None:
        site_icon = (ASSETS / "screenfix-icon.svg").read_bytes()
        canonical = (ROOT / "native/macos/Resources/ScreenFixAppIcon.svg").read_bytes()
        self.assertEqual(canonical, site_icon)
        root = ET.fromstring(site_icon)
        self.assertEqual("{http://www.w3.org/2000/svg}svg", root.tag)
        for element in root.iter():
            local_tag = element.tag.rsplit("}", 1)[-1].lower()
            self.assertNotIn(local_tag, {"script", "foreignobject"})
            for raw_name, value in element.attrib.items():
                name = raw_name.rsplit("}", 1)[-1].lower()
                self.assertFalse(name.startswith("on"))
                self.assertNotIn(name, {"href", "src"})
                if "url(" in value:
                    self.assertRegex(value, r"^url\(#[A-Za-z][A-Za-z0-9_-]*\)$")

    def test_sanitized_jpegs_have_exact_dimensions_and_budgets(self) -> None:
        total = 0
        for name, dimensions in EXPECTED_IMAGES.items():
            path = ASSETS / name
            self.assertTrue(path.is_file() and not path.is_symlink())
            self.assertEqual(dimensions, parse_jpeg(path))
            total += path.stat().st_size
            self.assertLessEqual(path.stat().st_size, MAX_IMAGE_BYTES)
        self.assertLessEqual(total, MAX_TOTAL_IMAGE_BYTES)
```

- [ ] **Step 2: Run the focused tests and record RED**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k ImageContractTests -v
```

Expected: FAIL because the site asset files do not exist and `parse_jpeg` is not implemented. The failure must identify the missing asset/implementation, not an import-path error.

- [ ] **Step 3: Implement the bounded JPEG parser**

Implement `parse_jpeg` before generating images. Keep each helper focused:

```python
def read_u16(data: bytes, offset: int) -> int:
    """Read one big-endian JPEG integer inside validated bounds."""
    if offset < 0 or offset + 2 > len(data):
        raise ContractError("JPEG marker is truncated")
    return struct.unpack_from(">H", data, offset)[0]


def parse_jfif(payload: bytes) -> None:
    """Accept only a complete JFIF header without an embedded thumbnail."""
    if len(payload) != 14 or payload[:5] != b"JFIF\x00":
        raise ContractError("JPEG APP0 must be a zero-thumbnail JFIF record")
    if payload[-2:] != b"\x00\x00":
        raise ContractError("JPEG JFIF thumbnails are forbidden")
```

The scan parser must handle `FF00` byte stuffing and restart markers without treating scan bytes as metadata. Require SOF0 or SOF2 dimensions exactly once, at least one SOS with non-empty entropy bytes, and EOI as the final two bytes.

- [ ] **Step 4: Prove the parser rejects metadata and trailing bytes before using it**

Add in-memory mutation tests using a minimal synthetic JPEG fixture. Prove one rejection at a time for APP1/EXIF, APP2/ICC, APP13/IPTC, APP14, COM, nonzero JFIF thumbnail dimensions, malformed length, missing EOI, duplicate EOI, and bytes after EOI. Run the single new test after each case; expect RED until the corresponding parser rule exists and GREEN afterward.

- [ ] **Step 5: Create the canonical icon with `apply_patch`**

Read `native/macos/Resources/ScreenFixAppIcon.svg` completely and add the exact same bytes to `site/assets/screenfix-icon.svg` with `apply_patch`. Do not generate, rewrite, optimize, or reformat the SVG.

- [ ] **Step 6: Generate the three derivatives into a temporary directory**

Confirm `sips --help` and `jpegtran -version` first. Use an exact temporary directory and publish only final outputs:

```bash
asset_parent="${TMPDIR:-/tmp}"
asset_tmp="$(mktemp -d "$asset_parent/screenfix-site-assets.XXXXXX")"

cleanup_assets() {
  case "$asset_tmp" in
    "$asset_parent"/screenfix-site-assets.*) ;;
    *) printf 'refusing unexpected cleanup path: %s\n' "$asset_tmp" >&2; return 1 ;;
  esac
  if [ -L "$asset_tmp" ] || [ ! -d "$asset_tmp" ]; then
    printf 'refusing non-directory cleanup path: %s\n' "$asset_tmp" >&2
    return 1
  fi
  find "$asset_tmp" -depth -delete
}

trap cleanup_assets EXIT

sips --cropToHeightWidth 900 1200 --cropOffset 0 168 \
  --setProperty format jpeg --setProperty formatOptions 80 \
  assets/screenfix-damaged-display.png \
  --out "$asset_tmp/damaged-source.jpg"

sips --cropToHeightWidth 675 1200 --cropOffset 90 300 \
  --setProperty format jpeg --setProperty formatOptions 80 \
  assets/results/screenfix-result-1.jpg \
  --out "$asset_tmp/result-calibration-source.jpg"

sips --cropToHeightWidth 675 1200 --cropOffset 90 300 \
  --setProperty format jpeg --setProperty formatOptions 80 \
  assets/results/screenfix-result-2.jpg \
  --out "$asset_tmp/result-mask-source.jpg"

jpegtran -copy none -optimize -progressive \
  -outfile "$asset_tmp/damaged-display.jpg" "$asset_tmp/damaged-source.jpg"
jpegtran -copy none -optimize -progressive \
  -outfile "$asset_tmp/result-calibration.jpg" "$asset_tmp/result-calibration-source.jpg"
jpegtran -copy none -optimize -progressive \
  -outfile "$asset_tmp/result-mask.jpg" "$asset_tmp/result-mask-source.jpg"
```

Run the parser against the temporary outputs before moving the three exact files into `site/assets/`. If `sips` interprets offsets differently on the current host, stop after the first output, inspect it, identify the documented coordinate behavior, and correct the crop command rather than guessing.

- [ ] **Step 7: Inspect every derivative at full resolution**

Use `view_image` with original detail on all three output paths. Verify:

- no laptop screen, browser tab, document text, spreadsheet, clock, precise-location clue, or unrelated personal content is visible;
- the physical damage is central and recognizable in the hero;
- `result-calibration.jpg` shows the three calibration guides clearly;
- `result-mask.jpg` shows the saved black mask clearly; and
- no crop is blurred, unintentionally rotated, or missing the relevant monitor area.

If one crop fails, adjust only that crop from the original, regenerate it into the temporary directory, re-run its parser test, and inspect again.

- [ ] **Step 8: Run the focused asset tests GREEN**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k ImageContractTests -v
```

Expected: all image-contract and mutation tests PASS. Then run `git diff --check` and confirm the three JPEGs together remain within 1,000,000 bytes.

- [ ] **Step 9: Commit the verified asset slice**

```bash
git add tests/site/test_site.py site/assets
git commit -m "test: add privacy-safe landing assets"
```

---

### Task 2: Semantic page and exact content contract

**Files:**
- Modify: `tests/site/test_site.py`
- Create: `site/.nojekyll`
- Create: `site/index.html`
- Create: `site/styles.css` as a non-empty placeholder for Task 3

- [ ] **Step 1: Add the failing page-tree and HTML contract**

Add `LandingPageContractTests` plus a small `HTMLParser` subclass that records landmarks, headings, IDs, links, images, scripts, classes, visible text nodes, `details`, and `summary` relationships. Require the exact production tree:

```python
EXPECTED_SITE_FILES = {
    ".nojekyll",
    "index.html",
    "styles.css",
    "assets/screenfix-icon.svg",
    "assets/damaged-display.jpg",
    "assets/result-calibration.jpg",
    "assets/result-mask.jpg",
}

SECTION_ORDER = ("how", "results", "downloads", "privacy", "requirements", "faq")

PRIMARY_DOWNLOADS = {
    "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64.exe",
    "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-macos-arm64.zip",
}
WINDOWS_FALLBACK = (
    "https://github.com/far1h/ScreenFix/releases/latest/download/"
    "ScreenFix-Windows-x64-uncompressed.exe"
)
```

The contract requires:

- only expected regular files and no symlinks; `.nojekyll` must be exactly empty and
  every other expected file must be non-empty;
- `lang="en"`, skip link, header/nav/main/footer, exactly one H1;
- exact H1 and exact explanation from the spec;
- H1 first in `.hero-copy`, with no pre-heading text;
- all six section IDs once and in order, with visible headings;
- three numbered How rows;
- two local result figures with non-empty alt text and captions;
- exact primary/fallback/release URLs and descriptive labels;
- four FAQ `details`/`summary` pairs with non-empty answers;
- the Help link resolving to `#faq`;
- no forbidden class/ID token or standalone trust-strip phrase;
- every internal reference resolving inside `site/` without `..`;
- HTTPS-only external URLs; and
- exactly one script with the approved GoatCounter attributes, `async`, no inline body, and no visible counter.

- [ ] **Step 2: Run one page-contract test and record RED**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k test_exact_site_tree -v
```

Expected: FAIL because `.nojekyll`, `index.html`, and `styles.css` are absent.

- [ ] **Step 3: Add `.nojekyll`, a stylesheet placeholder, and the complete semantic HTML**

Create the empty `.nojekyll` and a comment-only, non-empty `site/styles.css` with
`apply_patch`. The placeholder makes the exact deploy tree valid while keeping Task 3's
style-token tests RED on missing rules rather than a missing file. Build `site/index.html`
with this source order:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ScreenFix — Work around a damaged screen</title>
  <meta name="description" content="ScreenFix masks a damaged vertical display strip and keeps ordinary windows in the usable space on either side.">
  <link rel="canonical" href="https://far1h.github.io/ScreenFix/">
  <link rel="icon" href="assets/screenfix-icon.svg" type="image/svg+xml">
  <link rel="stylesheet" href="styles.css">
  <script data-goatcounter="https://farihmhmd.goatcounter.com/count" async src="https://gc.zgo.at/count.js"></script>
</head>
<body>
  <a class="skip-link" href="#content">Skip to content</a>
  <header><!-- icon/name; how, results, downloads, help, GitHub --></header>
  <main id="content">
    <div class="hero"><div class="hero-copy"><h1>Work around a damaged screen.</h1><!-- exact explanation/downloads --></div><!-- hero figure --></div>
    <section id="how"><!-- three ordered rows --></section>
    <section id="results"><!-- two real figures --></section>
    <section id="downloads"><!-- bordered Windows/macOS articles --></section>
    <section id="privacy"><!-- app vs website analytics --></section>
    <section id="requirements"><!-- systems, signing, Accessibility, limitations --></section>
    <section id="faq"><!-- four native details/summary pairs --></section>
  </main>
  <footer><!-- project sentence; source, Releases, Hammerspoon, MIT --></footer>
</body>
</html>
```

Use the visible copy and factual claims from the approved mockup/spec. Do not add an eyebrow, slogan row, trust badges, testimonials, ratings, statistics, generic icons, OS detection, or first-party JavaScript. Use `loading="eager" fetchpriority="high"` with explicit 1200×900 dimensions for the hero image; use `loading="lazy" decoding="async"` and exact dimensions for result images.

- [ ] **Step 4: Run the page tests until every failure identifies only missing CSS**

Run each page test by full unittest name. Fix HTML facts one at a time. Do not loosen a test to accept different content. Expected intermediate result: all HTML/tree/link/script/FAQ/negative-marketing tests PASS; only stylesheet-dependent tests remain unimplemented.

- [ ] **Step 5: Add page mutation regressions**

Copy `index.html` into temporary directories and mutate one fact at a time. Prove rejection of an eyebrow before H1, `Free and MIT licensed` as a standalone node, a second script, protocol-relative GoatCounter source, missing `async`, wrong native filename, `../` asset escape, duplicate section ID, reordered FAQ, empty summary, and missing image alt text.

- [ ] **Step 6: Run the semantic page slice GREEN and commit**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k LandingPageContractTests -v
git diff --check
```

Expected: every non-CSS test PASS. Commit only the semantic slice:

```bash
git add tests/site/test_site.py site/.nojekyll site/index.html site/styles.css
git commit -m "feat: add ScreenFix landing page content"
```

---

### Task 3: Approved visual system, accessibility, and responsive CSS

**Files:**
- Modify: `tests/site/test_site.py`
- Modify: `site/styles.css`

- [ ] **Step 1: Add failing CSS-token, contrast, and interaction tests**

Add `StyleContractTests`. Parse literal custom-property values and compute WCAG relative luminance with standard-library functions:

```python
APPROVED_COLORS = {
    "--paper": "#F5F0E8",
    "--surface": "#FCFAF6",
    "--ink": "#27212B",
    "--muted": "#655D61",
    "--rule": "#CFC5BA",
    "--button": "#B83D31",
    "--button-hover": "#A92C4D",
    "--button-text": "#FFF7E8",
    "--focus": "#D9513B",
}
```

Require 5.25:1 or better for the Windows default, 6.25:1 or better for its hover state, 14.7:1 or better for the dark macOS button, 4.5:1 for body/link pairs, and 3:1 for focus indicators. Require `:focus-visible`, a 44-pixel minimum action height, `prefers-reduced-motion: reduce`, native system fonts, at least two responsive breakpoints covering 375/768/1024/1440 behavior, and no external `@import`, glow, blur, animation keyframes, or large background gradient.

- [ ] **Step 2: Run the focused style test and record RED**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k StyleContractTests -v
```

Expected: FAIL because the committed placeholder lacks the approved tokens, selectors,
contrast rules, focus behavior, and responsive layout.

- [ ] **Step 3: Implement the complete approved stylesheet**

Use native fonts and the approved tokens. Implement:

- `.wrap` with a 1200-pixel max width and fluid gutters;
- simple 78-pixel header, wrapping navigation, and visible skip link on focus;
- asymmetric desktop hero and one-column mobile hero;
- `clamp()` hero/section sizes without tiny uppercase labels;
- rectangular 6–8-pixel-radius buttons with no shadows;
- numbered How rows separated by rules rather than cards;
- asymmetric Results figures without a carousel;
- one bordered two-column Downloads block that stacks below 700 pixels;
- plain Privacy/Requirements documentation rows;
- border-separated FAQ details with visible summary focus;
- compact footer;
- image intrinsic sizing and no horizontal overflow; and
- reduced-motion removal of smooth scrolling/transitions.

Do not reintroduce any visual pattern prohibited by the specification.

- [ ] **Step 4: Run style tests one at a time and fix root causes**

First run token/contrast tests, then accessibility interaction tests, then responsive/forbidden-style tests. If contrast fails, compute the actual pair and correct the token/selector rather than lowering the threshold.

- [ ] **Step 5: Run the entire site contract GREEN**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_*.py' -v
git diff --check
```

Expected: all image, HTML, mutation, CSS, accessibility, and exact-tree tests PASS.

- [ ] **Step 6: Commit the visual slice**

```bash
git add tests/site/test_site.py site/styles.css
git commit -m "feat: style the ScreenFix landing page"
```

---

### Task 4: Least-privilege GitHub Pages workflow

**Files:**
- Modify: `tests/site/test_site.py`
- Create: `.github/workflows/pages.yml`

- [ ] **Step 1: Add the failing workflow contract and mutation controls**

Add `PagesWorkflowContractTests` with a helper that accepts workflow text. Require exact source fragments and forbid broader forms. The expected workflow shape is:

```yaml
name: ScreenFix Pages

on:
  pull_request:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: screenfix-pages
  cancel-in-progress: false

jobs:
  validate:
    permissions:
      contents: read
  publish:
    needs: validate
    if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')
    permissions:
      contents: read
      pages: read
  deploy:
    needs: publish
    if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')
    permissions:
      pages: write
      id-token: write
```

Mutation controls must reject: a pull-request `paths` filter, a non-main branch, missing
exact-SHA checkout, missing `persist-credentials: false`, missing `needs`, publish without
`pages: read`, upload without `include-hidden-files: true`, deploy with `contents`,
write/OIDC on another job, changed action majors, a validate job that does not build and
inspect an equivalent Pages tar, removed inspection of the upload action's actual tar, or
a deployment without the `github-pages` environment.

- [ ] **Step 2: Run the workflow contract and record RED**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k PagesWorkflowContractTests -v
```

Expected: FAIL because `.github/workflows/pages.yml` is absent.

- [ ] **Step 3: Implement the workflow with exact action majors**

Use `actions/checkout@v7`, `actions/configure-pages@v6`, `actions/upload-pages-artifact@v5`, and `actions/deploy-pages@v5`. Both checkout jobs use:

```yaml
with:
  ref: ${{ github.event.pull_request.head.sha || github.sha }}
  persist-credentials: false
```

Validation and publish both run:

```bash
python3 -m unittest discover -s tests/site -p 'test_*.py' -v
```

The PR `validate` job then creates and inspects an equivalent Pages archive so the exact
deploy-tree logic executes before merge:

```bash
set -euo pipefail
tar --dereference --hard-dereference --directory site \
  -cf "$RUNNER_TEMP/pages-validation.tar" .
find site -type f -print \
  | sed 's#^site/##' \
  | LC_ALL=C sort > "$RUNNER_TEMP/expected-pages-files.txt"
tar -tf "$RUNNER_TEMP/pages-validation.tar" \
  | sed 's#^\./##' \
  | grep -Ev '(^$|/$)' \
  | LC_ALL=C sort > "$RUNNER_TEMP/actual-pages-files.txt"
diff -u "$RUNNER_TEMP/expected-pages-files.txt" "$RUNNER_TEMP/actual-pages-files.txt"
```

Upload uses:

```yaml
with:
  path: site
  include-hidden-files: true
```

After upload, compare the exact artifact tar manifest:

```bash
set -euo pipefail
find site -type f -print \
  | sed 's#^site/##' \
  | LC_ALL=C sort > "$RUNNER_TEMP/expected-pages-files.txt"
tar -tf "$RUNNER_TEMP/artifact.tar" \
  | sed 's#^\./##' \
  | grep -Ev '(^$|/$)' \
  | LC_ALL=C sort > "$RUNNER_TEMP/actual-pages-files.txt"
diff -u "$RUNNER_TEMP/expected-pages-files.txt" "$RUNNER_TEMP/actual-pages-files.txt"
```

- [ ] **Step 4: Run workflow tests, exercise the PR archive locally, and validate YAML**

Run the workflow tests one at a time. The workflow keeps GNU tar's
`--hard-dereference` on `ubuntu-latest`; for the macOS local proof use the BSD-compatible
equivalent and require an empty diff:

```bash
local_tar="$(mktemp "${TMPDIR:-/tmp}/screenfix-pages.XXXXXX.tar")"
test -f "$local_tar" && test ! -L "$local_tar"
trap 'find "$local_tar" -maxdepth 0 -type f -delete' EXIT
tar --dereference -C site -cf "$local_tar" .
find site -type f -print \
  | sed 's#^site/##' \
  | LC_ALL=C sort > "${local_tar}.expected"
tar -tf "$local_tar" \
  | sed 's#^\./##' \
  | grep -Ev '(^$|/$)' \
  | LC_ALL=C sort > "${local_tar}.actual"
diff -u "${local_tar}.expected" "${local_tar}.actual"
find "${local_tar}.expected" "${local_tar}.actual" -maxdepth 0 -type f -delete
```

Then parse the workflow with Ruby's standard YAML parser while disabling aliases:

```bash
ruby -e 'require "yaml"; YAML.safe_load_file(".github/workflows/pages.yml", aliases: false); puts "valid YAML"'
```

Expected: mutation controls PASS and output is `valid YAML`.

- [ ] **Step 5: Run full site validation and commit**

```bash
python3 -m unittest discover -s tests/site -p 'test_*.py' -v
git diff --check
git add tests/site/test_site.py .github/workflows/pages.yml
git commit -m "ci: validate and deploy ScreenFix Pages"
```

---

### Task 5: Concise collaborator documentation

**Files:**
- Modify: `tests/site/test_site.py`
- Modify: `README.md`

- [ ] **Step 1: Add a failing README contract**

Require the default Pages URL exactly once, `site/` in the root file tree, and the exact validation command. Require the existing Releases URL and native installation headings to remain.

- [ ] **Step 2: Run the focused README test and record RED**

Run:

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k ReadmeContractTests -v
```

Expected: FAIL because the landing-page URL and validation command are absent.

- [ ] **Step 3: Make the smallest README edit**

Add one sentence near the existing Releases link:

```markdown
The product overview and direct native downloads are also available on the
[ScreenFix website](https://far1h.github.io/ScreenFix/).
```

Add `site/` to the concise file tree. In Collaborating, add only:

```bash
python3 -m unittest discover -s tests/site -p 'test_*.py' -v
```

Do not copy the landing-page FAQ, privacy text, or platform installation instructions into README.

- [ ] **Step 4: Run the README and full site tests GREEN**

```bash
python3 -m unittest discover -s tests/site -p 'test_site.py' -k ReadmeContractTests -v
python3 -m unittest discover -s tests/site -p 'test_*.py' -v
git diff --check
```

- [ ] **Step 5: Commit the documentation slice**

```bash
git add tests/site/test_site.py README.md
git commit -m "docs: link the ScreenFix landing page"
```

---

### Task 6: Full local verification and visual/privacy acceptance

**Files:**
- Verify only; modify a scoped file only when a failure proves its root cause.

- [ ] **Step 1: Run the entire dependency-free site suite twice**

```bash
python3 -m unittest discover -s tests/site -p 'test_*.py' -v
python3 -m unittest discover -s tests/site -p 'test_*.py' -v
```

Expected: identical PASS counts, no skipped tests, no network access.

- [ ] **Step 2: Serve the exact site tree and smoke-test HTTP delivery**

Start a temporary local server bound only to loopback:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory site
```

From another shell, require 200 for `/`, `styles.css`, the icon, and all three JPEGs; require the HTML response to contain the exact H1 and both primary URLs. Stop the server in all exit paths.

- [ ] **Step 3: Inspect source without treating it as rendered acceptance**

Inspect the actual `index.html`/`styles.css` alongside the approved visual companion.
Confirm source order, breakpoint definitions, explicit image dimensions, focus rules, and
the absence of the rejected eyebrow/trust strip. Record rendered acceptance as pending;
source inspection cannot prove clipping, overflow, keyboard order, or actual responsive
layout. The required four-width browser pass occurs from the public exact-SHA branch
preview in Task 7 and the PR must not open until that pass is complete.

- [ ] **Step 4: Re-inspect deployed image bytes and pixels**

Run the JPEG parser tests, list exact sizes and SHA-256 values, then use `view_image` at original detail on `site/assets/*.jpg`. Confirm the final committed pixels contain none of the private details removed in Task 1.

- [ ] **Step 5: Verify current release assets without downloading binaries**

Query `gh api repos/far1h/ScreenFix/releases/latest` once. Require the three filenames used
by the page contract to be a subset of the release's asset-name set; the versioned checksum
asset and any other intentional release files remain allowed. Then run
`curl -fsSIL --max-redirs 10` against each `/releases/latest/download/...` URL and require
a final successful response. HEAD-only requests validate availability without fetching
the approximately 169 MB of binaries, and the test deliberately does not assert the final
signed URL because GitHub's storage redirect does not preserve the asset filename in its
path.

- [ ] **Step 6: Run unchanged native regressions**

```bash
lua tests/run.lua
native/macos/scripts/run-tests.sh
```

Expected: complete Lua suite PASS and native macOS `Executed 244 tests, 0 failures`.

- [ ] **Step 7: Audit scope and repository hygiene**

```bash
git diff main...HEAD --check
git status --short
git log --oneline main..HEAD
git diff --stat main...HEAD
git diff --name-only main...HEAD
```

Require a clean worktree; only the spec, plan, site, site tests, Pages workflow, and README may differ from `main`. Confirm native source/version/release files are absent from the diff.

---

### Task 7: Independent review, GitHub verification, and pull request

**Files:**
- Modify only files implicated by verified review findings.

- [ ] **Step 1: Request independent code review**

Use `superpowers:requesting-code-review`. Give the reviewer the exact spec, plan, `main...HEAD` diff, and verification evidence. Ask for Critical/Important findings only across privacy, accessibility, content fidelity, workflow privilege boundaries, artifact shape, and maintainability.

- [ ] **Step 2: Evaluate and fix findings test-first**

Use `superpowers:receiving-code-review`. Reproduce each accepted finding with one focused RED test, apply the smallest root-cause fix, run the focused GREEN test, and then re-run the full site suite. Re-review until Ready YES or three review iterations are exhausted.

- [ ] **Step 3: Push the feature branch**

```bash
git push -u origin feat/landing-page
```

Read back `refs/heads/feat/landing-page` and require its SHA to equal local `HEAD`.

- [ ] **Step 4: Render and inspect the public exact-SHA branch preview**

Open this immutable public preview in the Browser surface after replacing `<sha>` with
the pushed full commit:

```text
https://raw.githack.com/far1h/ScreenFix/<sha>/site/index.html
```

First fetch the tiny `site/index.html` from `raw.githubusercontent.com` at the same full
SHA and require its SHA-256 to equal the local file, proving the immutable public source.
Inspect screenshots at 375×812, 768×1024, 1024×768, and 1440×900, resetting the viewport
afterward. At every width verify no horizontal overflow, readable body text, uncropped
focus rings, meaningful image crops, and download actions identifiable without color
alone. Navigate the complete page with Tab/Shift+Tab, verify skip-link behavior and visible
focus, and open/close every FAQ `details` item by keyboard. Check the console for
page-owned errors. If the immutable preview or browser control is unavailable, stop and
report rendered acceptance as incomplete rather than substituting source inspection.

- [ ] **Step 5: Open the issue-linked pull request**

Create a PR against `main` with a factual body containing:

- the dependency-free download-first page and approved visual direction;
- sanitized metadata-free crops and image budgets;
- exact Windows/macOS direct downloads and limitations;
- GoatCounter website-only disclosure;
- all-PR validation and main-only least-privilege Pages deployment;
- exact local test and native regression evidence;
- pending main-only deployment note; and
- `Fixes #7`.

Do not claim the public Pages URL is deployed before merge.

- [ ] **Step 6: Wait for and inspect the exact PR checks**

Use `gh pr checks --watch` and the Actions API. Require the run head SHA to equal local
`HEAD`, the site validation job to pass, and publish/deploy jobs to be absent or skipped
on the pull request. Inspect logs rather than trusting only the aggregate badge.
Because `README.md` changes trigger `.github/workflows/windows-native.yml`, require its
Windows job to pass at the same exact head SHA as well. Enumerate every check run attached
to the PR head and require every non-skipped result to be successful; do not declare the
PR verified from the Pages badge alone. Inspect both the Pages validation log and the
Windows-native log, plus any additional triggered failure, rather than trusting only the
aggregate check summary.

- [ ] **Step 7: Read back the final PR and issue state**

Require the PR to target `main`, use the feature head, remain open, include `Fixes #7`, and show no merge conflict. Issue #7 remains open until merge by design.

- [ ] **Step 8: Finish the branch cleanly**

Use `superpowers:finishing-a-development-branch`. Preserve the open feature worktree/branch for review, report the PR URL and exact pending-after-merge Pages step, and do not start the separate Astro approach-C branch until the approach-A PR is complete.
