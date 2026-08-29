# ScreenFix SEO and Footer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ScreenFix discoverable for damaged-screen use cases and replace the constrained footer divider with a full-width shell.

**Architecture:** Keep the site fully static. Extend the existing Python mutation-sensitive contract for exact SEO metadata, visible copy, sitemap structure, and footer layout; then make the smallest matching HTML/CSS/XML changes. Repository topics are updated only after the code is review-ready.

**Tech Stack:** Semantic HTML, CSS, XML sitemap, Python `unittest` and `xml.etree.ElementTree`, Node's built-in test runner, GitHub Pages, GitHub CLI.

---

### Task 1: SEO metadata, copy, and sitemap

**Files:**
- Create: `site/sitemap.xml`
- Modify: `site/index.html`
- Modify: `tests/site/test_site.py`

- [ ] **Step 1: Add failing SEO contract tests**

Add `sitemap.xml` to `EXPECTED_SITE_FILES`. Add exact constants for the canonical URL,
title, description, social title, social image, and social image alt. Add focused tests
that require:

```python
self.assertEqual(
    ["Use the Working Part of a Broken Screen | ScreenFix"],
    [node.text() for node in page.nodes("title")],
)
self.assertEqual(
    ["Use the working part of a damaged screen."],
    [node.text() for node in page.nodes("h1")],
)
```

Update the existing hard-coded document metadata, hero, and FAQ contracts in the same
RED increment: they must expect the approved title, description, H1, explanation, new
FAQ pair, and five-item FAQ count. This prevents the new focused tests from passing while
the existing full-page contract still expects old copy.

Require exactly one `<meta name="robots">` with the literal content
`index, follow, max-image-preview:large`. Reject duplicates, missing tokens, reordered or
additional tokens, `noindex`, `nofollow`, and case or whitespace mutations.

Add mutation cases for duplicate description/canonical/social fields, insecure or off-site
URLs, mismatched Open Graph/Twitter values, missing image dimensions, keyword stuffing,
and misleading physical-repair claims.

Add a strict sitemap test using `xml.etree.ElementTree`: the path must be a bounded
regular non-symlink UTF-8 file; the root must be `{http://www.sitemaps.org/schemas/sitemap/0.9}urlset`;
there must be exactly one `url/loc`; and it must equal
`https://far1h.github.io/ScreenFix/`. Reject extra elements and volatile `lastmod`,
`changefreq`, or `priority` fields.

- [ ] **Step 2: Run focused tests and capture RED**

Run:

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k 'SeoContractTests' -v
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k 'test_exact_site_tree' -v
```

Expected: failures for missing reviewed metadata/copy and missing `site/sitemap.xml`.

- [ ] **Step 3: Implement the minimum static SEO changes**

In `site/index.html`, add the exact title, description, robots, Open Graph, and Twitter
values from the design. Change only the approved hero heading/explanation and add the
approved FAQ question/answer. Keep the canonical and script/CSP graph unchanged.

Create `site/sitemap.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://far1h.github.io/ScreenFix/</loc>
  </url>
</urlset>
```

- [ ] **Step 4: Run focused tests and capture GREEN**

Run the commands from Step 2. Expected: all focused SEO and exact-tree tests pass with no
warnings or skips.

Then run:

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -v
```

Expected: the complete Python suite passes before Task 1 is committed.

- [ ] **Step 5: Commit Task 1**

```bash
git add site/index.html site/sitemap.xml tests/site/test_site.py
git diff --cached --check
git commit -m "feat: add ScreenFix search metadata"
```

### Task 2: Full-width footer shell

**Files:**
- Modify: `site/index.html`
- Modify: `site/styles.css`
- Modify: `tests/site/test_site.py`

- [ ] **Step 1: Add failing footer structure and cascade tests**

Require `footer.site-footer` to contain exactly one direct `.site-footer-inner` child.
Require all existing footer content and the final builder credit to live inside that
child. Update the fixed CSS vocabulary so `.site-footer` may own only `width` and
`border-top`, while `.site-footer-inner` owns the old maximum width, centered margin,
responsive padding, flex layout, gap, and font size.

At 375, 768, 1024, and 1440 pixels, require:

```text
.site-footer width = 100%
.site-footer border-top = 1px solid var(--rule)
.site-footer-inner max-width = 1200px
.site-footer-inner margin-inline = auto
.site-footer-inner padding-inline = 24px below 1024px and 48px at or above 1024px
.site-footer-inner used width <= viewport width
last main section border-bottom = 0
```

Add mutation tests that recreate the current constrained footer, remove the inner shell,
restore the final constrained section border, create a double divider, change either
reviewed gutter, or make the inner track overflow at any reviewed width.

- [ ] **Step 2: Run focused tests and capture RED**

Run:

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k 'footer' -v
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k 'StyleContractTests' -v
```

Expected: failures because the footer itself still owns the constrained content track and
the final FAQ section still draws the short border.

- [ ] **Step 3: Implement the two-level footer**

Wrap the existing footer children in `<div class="site-footer-inner">`. Move the shared
content-track rule from `.site-footer` to `.site-footer-inner`. Give `.site-footer` the
full-width top border. Move existing flex and typography declarations to the inner.
Update descendant selectors from `.site-footer p` to `.site-footer-inner p` as needed.
Add `main > section:last-child { border-bottom: 0; }`. Apply the 48-pixel desktop gutter
to `.site-footer-inner`, not `.site-footer`.

- [ ] **Step 4: Run focused tests and capture GREEN**

Run the commands from Step 2. Expected: all footer and style tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add site/index.html site/styles.css tests/site/test_site.py
git diff --cached --check
git commit -m "fix: extend the footer divider"
```

### Task 3: Repository discovery and complete verification

**Files:**
- No tracked file is required for repository topics.

- [ ] **Step 1: Run the complete local verification**

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -v
node --test tests/site/platform.test.mjs
git diff --check main...HEAD
```

Expected: the Python and Node suites pass with no failures, skips, or warnings; the diff
check is clean.

- [ ] **Step 2: Perform browser verification**

Serve `site/` on loopback. At desktop and 390-pixel mobile widths, verify the full-width
footer rule, aligned footer content, no double rule, no horizontal overflow, loaded
images, unchanged platform recommendation, correct rendered title/metadata, and no console
errors. Stop the local server afterward.

- [ ] **Step 3: Update GitHub repository topics**

Set the exact topics to:

```text
broken-monitor
damaged-screen
macos
screen-mask
window-management
windows
```

Read the repository metadata back and verify the existing description and homepage are
unchanged and all six topics are present.

- [ ] **Step 4: Request code review and fix Important findings**

Dispatch independent reviewers for correctness, simplicity, and project conventions.
Re-run all affected focused and full tests after any amendment.

- [ ] **Step 5: Create and monitor the pull request**

Push `feat/seo-and-footer`, create a PR titled `feat: improve ScreenFix discoverability`
with `Closes #11`, and include test/browser evidence. Wait for Pages validation and
security checks to pass.

- [ ] **Step 6: Finish after merge**

After the user merges, update local `main`, remove local and remote feature branches,
monitor the exact merge-SHA Pages deployment, and verify the live HTML, CSS,
`sitemap.xml`, and GitHub topics. Add a concise issue #11 closeout note that links the
live sitemap and states that submitting it through the repository owner's Google Search
Console account is an optional follow-up, then confirm the issue is closed. Remove
generated caches and leave one clean `main` worktree synchronized with `origin/main`.
