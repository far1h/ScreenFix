# ScreenFix SEO and Footer Design

## Scope

Resolve GitHub issue #11 by making the existing ScreenFix landing page easier to find
for people searching for a way to use the working portion of a physically damaged
Windows or macOS display. The work also fixes the reported footer divider, which is
currently limited to the centered content width instead of spanning the viewport.

The result remains a dependency-free static GitHub Pages site. It adds no advertising,
new analytics, cookies, external fonts, client-side SEO code, build step, custom domain,
or claims that ScreenFix repairs damaged pixels.

## Root Causes

The page already has a sound crawlable baseline: one title, one description, a canonical
URL, semantic headings, descriptive images, and visible product explanations. It is not
currently indexed for the project name or URL, and its most prominent wording does not
clearly match the problem-shaped phrases people use when looking for this type of tool.
The page also lacks social sharing metadata and a sitemap, while the GitHub repository
has no discovery topics.

The footer divider looks truncated because the final FAQ section owns a bottom border
while that section is constrained by the shared 1200-pixel content track. The footer
element is constrained by the same rule and has no full-width outer shell.

## Search Intent and Copy

The page targets one honest intent cluster:

- use the working part of a broken or damaged screen;
- black out or ignore a damaged display strip;
- keep ordinary windows inside the usable screen area; and
- do this on Windows or Apple Silicon macOS without claiming physical repair.

The exact primary copy is:

- title: `Use the Working Part of a Broken Screen | ScreenFix`;
- meta description: `ScreenFix blacks out a damaged display strip and keeps ordinary
  windows inside the working part of a broken Windows or macOS screen.`;
- hero heading: `Use the working part of a damaged screen.`;
- hero explanation: `ScreenFix blacks out the broken strip and keeps ordinary windows
  inside the part of your screen that still works.`;
- FAQ question: `Can I use only the working part of a broken screen?`; and
- FAQ answer: `ScreenFix can black out a damaged strip and keep ordinary movable windows
  in the remaining usable space. It does not repair the panel, restore dead pixels, or
  control every full-screen, protected, custom, or fixed-size window.`

The copy remains direct and human rather than repeating keyword variants. Existing
platform, signing, Accessibility, full-screen, and protected-window limitations remain
visible and unchanged in meaning.

## Metadata and Crawl Artifacts

`site/index.html` contains exactly one reviewed value for each of the following:

- document title and meta description;
- canonical URL;
- robots directive with the exact value `index, follow, max-image-preview:large`;
- Open Graph type, title, description, URL, image, image dimensions, and image alt text;
- Twitter large-card type, title, description, image, and image alt text.

The exact social metadata relationships are:

- Open Graph title and Twitter title both equal
  `ScreenFix — Use the working part of a broken screen`;
- Open Graph description and Twitter description both equal the exact meta description;
- Open Graph URL equals the canonical URL;
- Open Graph image and Twitter image both equal
  `https://far1h.github.io/ScreenFix/assets/result-mask.jpg`;
- Open Graph image width and height are `1200` and `675`;
- Open Graph image alt and Twitter image alt both equal
  `ScreenFix mask keeping windows inside the usable part of a damaged display`;
- Open Graph type is `website`; and
- Twitter card type is `summary_large_image`.

The canonical URL remains `https://far1h.github.io/ScreenFix/`. Social image metadata
uses the existing privacy-reviewed `result-mask.jpg` through its absolute Pages URL, so
no new generated asset or external image request is required. Social descriptions match
the page's real behavior and do not add unsupported claims.

`site/sitemap.xml` is a small UTF-8 XML sitemap with the standard sitemap namespace and
exactly one URL: the canonical homepage. It omits volatile `lastmod`, priority, and
change-frequency values. A project-path `robots.txt` is intentionally not added because
crawlers request the robots file at the `far1h.github.io` origin root, which this project
site does not control. The repository-owned acceptance criterion is that the sitemap is
deployed and publicly reachable at
`https://far1h.github.io/ScreenFix/sitemap.xml`. Google Search Console submission requires
the owner's external account and is documented in the issue closeout as an optional
follow-up rather than presented as completed by this change.

Structured data is deferred. Google software-app rich-result eligibility expects
genuine rating or review information that ScreenFix does not yet have. The implementation
does not invent ratings, add misleading review data, or loosen the exact script and CSP
contracts for a lower-value JSON-LD block.

## Repository Discovery

The public repository keeps its existing accurate description and Pages homepage. Its
topics are updated to a small, problem-focused set such as `damaged-screen`,
`broken-monitor`, `screen-mask`, `window-management`, `windows`, and `macos`. Topics are
lowercase, factual, and limited to the product's actual behavior.

## Footer Layout

The footer becomes a two-level shell:

- `.site-footer` spans the viewport and owns the single top divider;
- `.site-footer-inner` owns the existing centered maximum width, responsive gutters,
  flex layout, links, description, and builder credit.

The final FAQ section no longer draws its own constrained bottom border, preventing a
double or truncated divider. Footer content stays aligned with the header and main page
at the existing 24-pixel and 48-pixel gutters. Content order, link targets, 44-pixel link
targets, colors, and builder credit remain unchanged.

## Testing

Tests are written before production changes and must first fail for the missing behavior.
They cover:

- exact, unique search and social metadata with HTTPS same-site URLs;
- natural visible intent wording and unchanged limitation meaning;
- a bounded, regular, non-symlink, UTF-8 sitemap with one canonical URL;
- the exact deployed site tree including `sitemap.xml`;
- a full-width footer shell with a constrained inner track and no constrained final
  section divider;
- responsive footer alignment and absence of horizontal overflow;
- rejection of duplicate, insecure, off-site, mismatched, misleading, or malformed SEO
  mutations; and
- continued Python site-contract and Node platform-module coverage.

Browser verification checks desktop and narrow mobile widths, the visible footer rule,
the unchanged page layout, loaded images, console errors, and rendered metadata. The
deployed Pages URL is checked again after merge.

## Delivery

Implementation is committed on a dedicated branch and delivered through a pull request
that links issue #11. The PR must pass the Pages validation and security checks. After
merge, the Pages deployment is monitored, the live HTML, CSS, sitemap, and repository
topics are verified, issue #11 is closed with a concise implementation note, and the
feature branch plus generated local artifacts are removed.
