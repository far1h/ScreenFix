# ScreenFix Landing Page Design

## Scope

Resolve GitHub issue #7 by adding a small, download-first product page for ScreenFix at
the repository's default GitHub Pages URL:

`https://far1h.github.io/ScreenFix/`

The page explains the specific problem ScreenFix addresses, shows real results, and
links directly to the current native Windows and macOS release assets. It is a single
responsive page built with semantic HTML and CSS. It adds no application runtime code,
frontend framework, package manager, build dependency, user-agent detection, custom
domain, or client-side application logic.

The page includes privacy-conscious visit analytics through GoatCounter. This is website
analytics only; the ScreenFix desktop applications remain local utilities with no app
telemetry or network use.

The native applications, release workflow, release filenames, version numbers, and
existing source images are unchanged. A later Astro experiment belongs on a separate
branch after this static implementation has its own pull request; it is not part of this
change.

## Root Cause

The repository has product documentation and ready-to-run release assets but no public
landing page. GitHub Pages is not configured, the repository homepage is empty, and issue
#7 has no implementation beyond its title. A visitor currently has to understand the
repository README before reaching the correct native download.

The source photographs are also unsuitable for direct publication in a Pages artifact.
The result JPEGs contain location metadata, and the photographs expose incidental browser
and document details. A landing page must use new sanitized crops rather than copying the
existing files.

## Architecture

The complete site lives under `site/`:

```text
site/
├── .nojekyll
├── index.html
├── styles.css
├── assets/
│   ├── screenfix-icon.svg
│   ├── damaged-display.jpg
│   ├── result-calibration.jpg
│   └── result-mask.jpg
tests/
└── site/
    └── test_site.py
```

`index.html` is the only page. `styles.css` owns all presentation and responsive rules.
The only runtime script is GoatCounter's hosted counter script. The SVG is a site-local,
script-free copy of the canonical Screen Patch icon, with a test requiring it to remain
identical to `native/macos/Resources/ScreenFixAppIcon.svg`. The three JPEGs are committed
sanitized derivatives of the existing project photographs. Tests live outside `site/` so
validator source cannot become a public Pages asset.

`.nojekyll` tells GitHub Pages to publish the directory unchanged. There is no `CNAME`,
JavaScript bundle, source map, generated dependency directory, or checked-in release
binary.

The root README remains concise. Its file tree adds `site/`, and a short collaborator
note gives the dependency-free validation command. Installation and application behavior
remain in their existing sections rather than being duplicated in a second maintenance
guide.

## Page Structure and Copy

The page uses this fixed information order:

1. A plain header with the real ScreenFix icon, the `ScreenFix` name, and links to How it
   works, Results, Downloads, Help, and GitHub.
2. A two-column, download-first hero. The left column contains the exact heading `Work
   around a damaged screen.` and the explanation `ScreenFix blacks out the broken strip
   and keeps ordinary windows in the space that still works.` It then presents separate
   Windows and macOS download actions plus a secondary Releases/checksums link. A
   sanitized crop of the real damaged display occupies the right column.
3. `Give the damage its own space.` followed by three numbered rows: mark the damaged
   strip, keep it dark, and use the remaining space. These are normal rows separated by
   rules, not three feature cards.
4. `What it looks like in use.` followed by two sanitized real project photographs: the
   three-band calibration and the saved mask. Factual captions identify the distinct
   states rather than presenting either as an ordinary fitted window or a product render.
5. `Download ScreenFix.` followed by one bordered Windows/macOS pair with requirements,
   installation notes, and platform-specific warnings placed beside the relevant action.
6. A `#privacy` section headed `ScreenFix stays on your computer.` It explains the app's
   local behavior separately from the landing page's GoatCounter visit measurement.
7. A `#requirements` section headed `Requirements and limits.` It consolidates supported
   systems, signing warnings, Accessibility behavior, physical-display limitations, and
   the classes of windows that may remain unchanged without repeating installation steps.
8. A `#faq` section headed `Questions before you download.` It uses native `details` and
   `summary` elements for a compact factual set: whether ScreenFix repairs panel damage,
   which windows may remain unchanged, why the operating system may warn about the builds,
   and when macOS Accessibility permission is needed. The header's Help link points here.
9. A compact footer linking to source, Releases, the advanced Hammerspoon installation,
   and the MIT license.

There is no eyebrow or kicker above the hero heading. There is no row of standalone
claims such as `Free and MIT licensed`, `Runs locally`, or `No app telemetry`. Those facts
appear only inside the relevant explanatory prose lower on the page. The page also has no
testimonials, ratings, customer logos, statistics, badge cloud, generic three-card feature
grid, or corporate multi-column footer.

## Download Behavior

The primary actions are ordinary HTTPS links. The page does not inspect the visitor's
operating system or hide either platform.

- Windows x64 recommended:
  `https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64.exe`
- macOS Apple Silicon:
  `https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-macos-arm64.zip`
- Windows x64 uncompressed fallback:
  `https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64-uncompressed.exe`
- Releases and versioned checksums:
  `https://github.com/far1h/ScreenFix/releases/latest`

The recommended Windows executable and macOS archive receive equal placement in the hero.
The Windows fallback is a subordinate link inside the Windows download details. Checksums
link to the release page because the checksum asset's filename includes the release
version and therefore has no stable version-independent download name.

The Windows copy states that the executable targets ordinary Intel/AMD x64 Windows, is
self-contained, needs no separate .NET runtime or ZIP extraction, and may show SmartScreen
because it is unsigned. The uncompressed build is described as a behavior-identical
fallback for startup or extraction trouble. The page does not promise movement of
administrator-launched windows.

The macOS copy states macOS 13 or later, Apple Silicon rather than Intel, Control-click
Open for the ad hoc signed build, and Accessibility permission for automatic window
placement. It distinguishes this permission-dependent placement from masks and
calibration, which continue to work without the permission. It does not imply that the
download is notarized.

## Visual Design

The approved direction is quiet, warm, and editorial rather than SaaS-like. It uses the
existing Screen Patch artwork and real project photography as the identity.

- Background: warm paper `#F5F0E8`; main surface `#FCFAF6`.
- Primary text: `#27212B`; secondary text: `#655D61`; rules: `#CFC5BA`.
- Primary Windows action: `#B83D31` with `#FFF7E8` text, changing to `#A92C4D` on
  hover. Their contrast ratios are 5.26:1 and 6.25:1. The macOS action uses `#27212B`
  with `#FFF7E8` text for 14.73:1 contrast.
- `#D9513B` remains a non-text accent and focus-outline color, where it maintains at least
  3:1 contrast against the approved paper and surface backgrounds. Text links use the
  darker `#A92C4D` rather than the non-text accent.
- The icon retains its compact amber/coral/wine gradient. Large page backgrounds do not
  use gradients.
- Typography uses the native system sans-serif stack. No font request is needed for the
  page to render.
- Hero type is large and direct, but remains approximately two lines on a typical desktop.
  Body text never falls below 14 pixels, and normal copy is 16–20 pixels.
- The content width is approximately 1200 pixels, with 24-pixel mobile gutters and
  40–56-pixel desktop gutters.
- Sections are separated by thin rules. Borders use small 4–8-pixel radii. Buttons are
  solid rectangles rather than pills. Shadows are absent or minimal.
- Motion is limited to short button color/position feedback. There are no entrance
  animations, carousels, parallax effects, animated backgrounds, or cursor effects.

The layout stacks in source order on narrow screens. The header wraps to essential links
without adding a JavaScript hamburger. The hero text precedes its image; download and
documentation columns become one column; result images remain readable without horizontal
scrolling. The layout is explicitly checked at 375, 768, 1024, and 1440 CSS pixels.

## Image Privacy and Ownership

The site never references or copies the original photographs directly. It commits three
new, flattened JPEG derivatives:

- `damaged-display.jpg` comes from `assets/screenfix-damaged-display.png` and shows the
  damaged display without unnecessary surrounding browser or sheet details.
- `result-calibration.jpg` comes from `assets/results/screenfix-result-1.jpg` and shows
  the three-band calibration guides without readable private content or surrounding
  location clues.
- `result-mask.jpg` comes from `assets/results/screenfix-result-2.jpg` and shows the saved
  mask result under the same privacy constraints.

Every crop is visually inspected at full size before commit. Pixel orientation is baked
in before metadata is removed. `damaged-display.jpg` is exactly 1200 by 900 pixels;
`result-calibration.jpg` and `result-mask.jpg` are each exactly 1200 by 675 pixels. Each
file is at most 400,000 bytes, and all three together are at most 1,000,000 bytes.

The derivatives contain no EXIF, GPS, XMP, IPTC, comment, thumbnail, text, or color-profile
payloads. The validator accepts only SOI, EOI, DQT, baseline or progressive SOF, DHT, DRI,
SOS, and restart markers, plus one optional APP0 segment that must be a parsed JFIF record
with zero thumbnail dimensions. It rejects APP1 through APP15, COM, non-JFIF APP0 data,
duplicate or malformed structural segments, absent or duplicate EOI, and any bytes after
EOI. Entropy-coded scan data is bounded by the enclosing SOS/EOI structure rather than
interpreted as metadata.

The dependency-free validator parses JPEG markers itself. It enforces the marker
allowlist, exact dimensions, per-file and aggregate byte limits, non-empty scan data,
regular-file ownership, and separation from source-image filenames inside the site tree
or HTML. Automated byte checks complement rather than replace the required visual privacy
review, because a crop can expose readable content without carrying metadata.

The original tracked photographs and their Git history remain unchanged and outside this
issue. Sanitizing the Pages copies prevents the website artifact from redistributing the
original metadata; it does not claim to erase metadata already present in repository
history.

## Privacy and Analytics

The page includes exactly one external script:

```html
<script
  data-goatcounter="https://farihmhmd.goatcounter.com/count"
  async
  src="https://gc.zgo.at/count.js"></script>
```

The explicit HTTPS source avoids protocol-relative behavior. There is no public counter
widget, advertising pixel, cookie banner, or second analytics provider. The page remains
fully usable if the script is blocked or JavaScript is disabled.

The privacy copy distinguishes the product from the website:

- ScreenFix itself does not capture the screen, read window contents, use the network, or
  send telemetry.
- This landing page uses GoatCounter to count visits and estimate broad country-level
  traffic. GoatCounter does not set tracking cookies. It may briefly process an IP address
  and user agent in memory for unique-visit and country estimates, but the site owner does
  not receive or retain visitors' IP addresses.

No analytics data changes content, gates downloads, or becomes part of automated tests.

## Accessibility and Semantics

The document uses a skip link, one `h1`, ordered heading levels, `header`, `nav`, `main`,
labelled sections, figures, articles, definition lists, and `footer` where appropriate.
The brand icon is decorative beside visible text. Product photographs have concise alt
text describing the relevant damaged strip, calibration guides, or saved mask; captions
carry the extra explanation.

Every action is a real anchor with a descriptive accessible name. Keyboard focus uses a
visible warm outline. Tap targets are at least 44 CSS pixels high. Links are identifiable
without color alone, text contrast meets WCAG AA, and CSS includes a
`prefers-reduced-motion: reduce` path. Page structure and downloads do not depend on
hover, animation, JavaScript, or pointer precision.

## GitHub Pages Workflow

`.github/workflows/pages.yml` owns validation and deployment. An unfiltered
`pull_request:` trigger validates every pull request. Pushes to `main` and manual
dispatches run the same gate. All checkouts use the exact event source SHA rather than an
implicit moving branch.

The validation job runs on `ubuntu-latest` with only `contents: read` and executes:

```bash
python3 -m unittest discover -s tests/site -p 'test_*.py'
```

The validation job then creates an unuploaded temporary tar from `site/` with the same
hidden-file and symlink-dereference behavior used for Pages publication. Its normalized
regular-file manifest must exactly match the validated site tree, including `.nojekyll`.
This proves the deploy-tree logic on pull requests without granting artifact or Pages
permissions.

Pull requests stop after validation. They never configure Pages, upload a Pages artifact,
request an OIDC token, or receive Pages write permission.

For a successful push to `main`, or a manual run whose ref is exactly `main`, a separate
publish job checks out and validates the same SHA, runs `actions/configure-pages@v6`, and
uses `actions/upload-pages-artifact@v5` with `site/` as its path and
`include-hidden-files: true`. The publish job receives exactly `contents: read` and
`pages: read`; Pages read access is required because `configure-pages` reads the
repository's Pages configuration. A final deploy job uses `actions/deploy-pages@v5` in
the `github-pages` environment. Only that final job receives `pages: write` and
`id-token: write`; it does not receive repository contents access.

After upload, the publish job inspects the composite action's artifact tar from
`RUNNER_TEMP`. Its sorted manifest must exactly match the regular files under `site/`,
including `.nojekyll`, and must contain no tests, symlinks, `.git`, `.github`, or
unexpected hidden files. Allowing hidden files is safe only because the validator first
requires an exact site tree and the artifact manifest is independently compared.

The workflow uses `actions/checkout@v7`. Actions are pinned to their current stable major
versions, making Dependabot-compatible update boundaries explicit without pinning to a
moving branch name. Pages deployments share one concurrency group so an older deployment
cannot overwrite a newer validated artifact.

No workflow rewrites repository settings or creates a custom domain. After merge, Pages
must be configured once in repository settings with GitHub Actions as its source if the
first deploy reports that Pages is not enabled.

## Validation

`tests/site/test_site.py` uses only Python's standard library. Tests start RED against the
current repository because `site/index.html` and the Pages workflow do not exist. The
implemented suite then verifies:

- the exact site tree contains only expected regular files and no symlinks;
- `.nojekyll` is present as an empty regular file; HTML, CSS, icon, and all three JPEGs
  are present as non-empty regular files;
- the site icon is byte-identical to the canonical application-icon SVG and contains no
  script or external reference;
- HTML parses cleanly, declares English, includes one exact hero heading, uses semantic
  landmarks and ordered headings, and contains the required section anchors;
- the hero heading is the first substantive element in its copy column, with no preceding
  eyebrow, kicker, category, badge, or promotional text. No class or ID may introduce an
  eyebrow, kicker, trust strip, statistic strip, badge cloud, testimonial, or social-proof
  region, and no rendered text node may equal the standalone claims `Free and MIT
  licensed`, `Runs locally`, or `No app telemetry`;
- every internal asset/anchor reference resolves, every external URL is HTTPS, and there
  are no `file:`, `data:`, protocol-relative, or localhost URLs;
- primary and fallback release URLs match the stable filenames exactly, and every link has
  a descriptive non-empty accessible label;
- GoatCounter is the only script, with the exact endpoint, explicit HTTPS source, and
  `async`; there is no inline script or public counter element;
- CSS contains the approved tokens, focus-visible handling, reduced-motion handling, and
  responsive rules without external font or stylesheet requests. Standard-library
  contrast calculations require at least 4.5:1 for every normal, hover, and focus-state
  text/background pair and at least 3:1 for focus indicators against adjacent colors;
- the JPEG marker structure, dimensions, metadata exclusions, and source-asset separation
  satisfy the image privacy contract;
- privacy, platform requirements, signing warnings, physical limitations, app telemetry,
  page analytics, source, MIT license, Releases, and Hammerspoon guidance all remain
  discoverable in visible copy;
- the six content anchors appear once and in the approved order: `how`, `results`,
  `downloads`, `privacy`, `requirements`, and `faq`. Each has a visible heading; the FAQ
  contains the four required questions as keyboard-operable native `details`/`summary`
  pairs with non-empty answers, and the header's Help link resolves to `#faq`; and
- the Pages workflow has the required triggers, exact stable action majors, read-only PR
  validation with local archive inspection, main-only publish condition, `site/` artifact
  path, hidden-file input and actual artifact inspection, scoped publish/deploy
  permissions, environment, and dependency ordering. Mutation controls prove that PR path
  filters, missing PR archive inspection, non-main publication, missing `needs`, missing
  hidden-file inclusion, and broadened job permissions are rejected.

After automated validation, manual acceptance opens the served page at desktop and mobile
widths, navigates it entirely by keyboard, verifies that the photographs expose no private
details, and follows the three native download links to current release assets. The merged
Pages deployment is then checked at the default URL in a private browsing session with
JavaScript enabled and disabled.

## Failure Handling

A missing asset, unresolved anchor, malformed or metadata-bearing image, unexpected
external script, stale release filename, inaccessible structure, or weakened workflow
permission fails the validation job before deployment.

Publishing uses a freshly assembled Pages artifact from the validated commit. If artifact
upload or deployment fails, the previously deployed Pages version remains the public
site; no partial directory is promoted. Manual dispatch provides a recovery path after a
transient Pages failure but cannot deploy a non-`main` ref.

If a future release renames a native asset, the direct-link test fails in the same change
that updates the page. If GoatCounter is unavailable, the page and downloads continue to
work without an error banner or retry loop.

## Delivery

Implementation remains on `feat/landing-page` and is proposed in one pull request against
`main`. The pull request includes the local validation command, the successful Pages
workflow run, desktop/mobile visual evidence, and `Fixes #7` so the issue closes only after
the landing page and deployment workflow merge.

The PR does not create a release, alter repository release assets, or enable Pages through
an undocumented side channel. Any required one-time Pages repository setting is performed
after the reviewed workflow is present, then read back before the deployment is considered
complete.
