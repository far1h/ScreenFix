# ScreenFix Landing Page Design

## Scope

Resolve GitHub issue #7 by adding a small, download-first product page for ScreenFix at
the repository's default GitHub Pages URL:

`https://far1h.github.io/ScreenFix/`

The page explains the specific problem ScreenFix addresses, shows real results, and
links directly to the current native Windows and macOS release assets. It is a single
responsive page built with semantic HTML and CSS plus one small local ES module for an
advisory platform recommendation. It adds no application runtime code, frontend
framework, package manager, build dependency, custom domain, or client-side application
framework.

The page includes privacy-conscious visit analytics through GoatCounter as an
implementation detail. No visit count, analytics vendor, or visitor-tracking disclosure
appears in visible page copy. The ScreenFix desktop applications remain local utilities
with no app telemetry or network use.

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
├── platform.mjs
├── styles.css
├── assets/
│   ├── screenfix-icon.svg
│   ├── damaged-display.jpg
│   ├── how-mark-strip.jpg
│   ├── how-mask-strip.jpg
│   ├── how-use-space.jpg
│   ├── privacy-local.jpg
│   ├── requirements-platforms.jpg
│   ├── result-calibration.jpg
│   └── result-mask.jpg
tests/
└── site/
    ├── platform.test.mjs
    └── test_site.py
```

`index.html` is the only page. `styles.css` owns all presentation and responsive rules.
`platform.mjs` is the only first-party runtime module. It reads low-entropy browser
platform strings locally and only reorders and labels existing download choices. The
other runtime script is GoatCounter's hosted counter script. The SVG is a site-local,
script-free copy of the canonical Screen Patch icon, with a test requiring it to remain
identical to `native/macos/Resources/ScreenFixAppIcon.svg`. Three JPEGs are committed
sanitized derivatives of existing project photographs; five additional JPEGs are
generated editorial illustrations. Tests live outside `site/` so validator source cannot
become a public Pages asset.

`.nojekyll` tells GitHub Pages to publish the directory unchanged. There is no `CNAME`,
JavaScript bundle, source map, generated dependency directory, or checked-in release
binary. The local module is a reviewed source file rather than a generated bundle.

The root README remains concise. Its file tree adds `site/`, and a short collaborator
note gives the Python site-contract command and Node built-in platform-module command.
Installation and application behavior remain in their existing sections rather than
being duplicated in a second maintenance guide.

## Page Structure and Copy

The page uses this fixed information order:

1. A plain full-width header rule with the real ScreenFix icon, the `ScreenFix` name, and
   links to How it works, Results, Downloads, Help, and GitHub inside the aligned content
   grid. On narrow screens the brand occupies a centered row without an underline; the
   navigation remains visible below it.
2. A two-column, download-first hero. The left column contains the exact heading `Work
   around a damaged screen.` and the explanation `ScreenFix blacks out the broken strip
   and keeps ordinary windows in the space that still works.` It then presents separate
   Windows and macOS download actions plus a secondary Releases/checksums link. A
   sanitized crop of the real damaged display occupies the right column.
3. `Give the damage its own space.` followed by three numbered rows: mark the damaged
   strip, keep it dark, and use the remaining space. Each row includes one matching warm
   editorial cartoon that depicts the step without embedded text. These remain normal
   rows separated by rules, not three feature cards.
4. `What it looks like in use.` followed by two sanitized real project photographs: the
   three-band calibration and the saved mask. Factual captions identify the distinct
   states rather than presenting either as an ordinary fitted window or a product render.
5. `Download ScreenFix.` followed by one bordered Windows/macOS pair with requirements,
   installation notes, and platform-specific warnings placed beside the relevant action.
   SmartScreen, Windows fallback, and macOS Accessibility notes use smaller 15-pixel
   supporting copy.
6. A `#privacy` section headed `ScreenFix stays on your computer.` It pairs a local-only
   editorial illustration with one concise paragraph explaining that the app does not
   capture screen contents, use the network, or send telemetry. It contains no visible
   mention of GoatCounter, analytics, visits, visitors, or tracking.
7. A `#requirements` section headed `Requirements and limits.` It pairs a cross-platform
   editorial illustration with four ruled definition-list rows labelled `Windows`,
   `macOS`, `What ScreenFix does`, and `Window limitations`. The rows preserve supported
   systems, signing warnings, Accessibility behavior, physical-display limitations, and
   window exclusions without repeating installation steps.
8. A `#faq` section headed `Questions before you download.` It uses native `details` and
   `summary` elements for a compact factual set: whether ScreenFix repairs panel damage,
   which windows may remain unchanged, why the operating system may warn about the builds,
   and when macOS Accessibility permission is needed. The header's Help link points here.
9. A compact footer linking to source, Releases, the advanced Hammerspoon installation,
   and the MIT license, followed by `Built by farihmhmd.com` linked to
   `https://farihmhmd.com/` on its own final row.

There is no eyebrow or kicker above the hero heading. There is no row of standalone
claims such as `Free and MIT licensed`, `Runs locally`, or `No app telemetry`. Those facts
appear only inside the relevant explanatory prose lower on the page. The page also has no
testimonials, ratings, customer logos, statistics, badge cloud, generic three-card feature
grid, or corporate multi-column footer.

## Download Behavior

The primary actions are ordinary HTTPS links. Both platforms are present and visible in
the static HTML. A small local progressive enhancement inspects only browser-reported
platform strings to recommend Windows or macOS:

- `NavigatorUAData.platform` is used when available without requesting high-entropy
  values;
- `Navigator.platform` and then `Navigator.userAgent` provide Safari-compatible
  fallbacks;
- `NavigatorUAData.mobile`, Apple/Android mobile user-agent tokens, and a `MacIntel`
  platform with `Navigator.maxTouchPoints` greater than one are treated as unknown rather
  than being sent to a desktop build; and
- a Windows, macOS, or unknown result is computed entirely in the browser and is never
  stored or transmitted.

For a recognized desktop platform, the matching choice moves first in each existing
download group and reveals the pre-authored label `Recommended for this device`. The DOM
order and keyboard order stay aligned. The other platform remains equally visible and
usable. A classification of unknown, including blocked or absent signals, leaves the
source order unchanged. Browser-reported values are advisory and can be reduced or
spoofed, so a recognized result is never treated as proof that the binary is compatible.
The harmless fallback is that both downloads always remain visible. The module never
redirects, starts a download, hides an option, attaches a download handler, opens a new
window, changes a URL, uses storage, or makes a network request.

- Windows x64 recommended:
  `https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64.exe`
- macOS Apple Silicon:
  `https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-macos-arm64.zip`
- Windows x64 uncompressed fallback:
  `https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64-uncompressed.exe`
- Releases and versioned checksums:
  `https://github.com/far1h/ScreenFix/releases/latest`

The recommended Windows executable and macOS archive receive equal styling and remain
visible together in the hero. The advisory platform match changes only their order and
adds the recommendation label.
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
- The five cartoons form one coherent hand-drawn editorial series in the existing cream,
  coral, amber, and dark-plum palette. They use simple screen and window shapes, modest
  paper texture, no embedded words, no logos, no stock-photo characters, no glossy 3D
  rendering, and no generic AI-marketing motifs.
- The How illustrations live inside the existing numbered ruled rows. Privacy and
  Requirements use open two-column grids rather than bordered cards. Requirements keeps
  coral row numbers and larger labels to improve scanning without adding badges.
- Motion is limited to short button color/position feedback. There are no entrance
  animations, carousels, parallax effects, animated backgrounds, or cursor effects.

The layout stacks in source order on narrow screens. The header keeps its full-width rule,
centers the brand on its own row, and wraps the essential links without adding a
JavaScript hamburger. The hero text precedes its image; download and documentation
columns become one column; step, privacy, requirements, and result images remain readable
without horizontal scrolling. The layout is explicitly checked at 375, 768, 1024, and
1440 CSS pixels.

## Image Privacy, Generation, and Ownership

The site never references or copies the original photographs directly. It commits three
flattened JPEG derivatives:

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
photograph is at most 400,000 bytes, and all three photographs together are at most
1,000,000 bytes.

The approved generated illustration set contains five 1200-by-900 flattened JPEGs:

- `how-mark-strip.jpg` shows a monitor with three guides marking one damaged strip;
- `how-mask-strip.jpg` shows the same monitor with an opaque black mask over the strip;
- `how-use-space.jpg` shows ordinary windows arranged in usable space beside the strip;
- `privacy-local.jpg` shows ScreenFix working locally with window geometry only and no
  cloud or captured content; and
- `requirements-platforms.jpg` shows Windows and macOS-style displays working around the
  same kind of damaged strip without using protected platform logos.

The built-in image-generation tool creates one distinct asset per call from a shared
style brief. Generated originals are treated as source material: each selected output is
visually inspected, resized and flattened, stripped through the same JPEG sanitization
pipeline as the photographs, and only then copied into `site/assets/`. The illustrations
contain no embedded words, watermarks, real people, private information, UI brand marks,
or location clues. Each illustration is at most 250,000 bytes; the five illustrations
together are at most 1,100,000 bytes; all eight site JPEGs together are at most 1,500,000
bytes.

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
or HTML. Automated byte checks complement rather than replace the required original-size
visual review, because a photograph can expose readable content without carrying metadata
and a generated illustration can contain an unintended artifact without carrying
metadata.

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
fully usable if the analytics script is blocked or JavaScript is disabled.

Visible privacy copy discusses only ScreenFix itself: it does not capture the screen, read
window contents, use the network, or send telemetry. No visible page text names
GoatCounter or discusses analytics, visits, visitors, tracking cookies, IP addresses, or
user agents. Analytics data never changes content, gates downloads, influences platform
recommendations, or becomes part of automated behavior tests.

## Accessibility and Semantics

The document uses a skip link, one `h1`, ordered heading levels, `header`, `nav`, `main`,
labelled sections, figures, articles, definition lists, and `footer` where appropriate.
The brand icon is decorative beside visible text. Product photographs have concise alt
text describing the relevant damaged strip, calibration guides, or saved mask; captions
carry the extra explanation.

Every action is a real anchor with a descriptive accessible name. Keyboard focus uses a
visible warm outline. Tap targets are at least 44 CSS pixels high. Links are identifiable
without color alone, text contrast meets WCAG AA, and CSS includes a
`prefers-reduced-motion: reduce` path. Page structure and download availability do not
depend on hover, animation, JavaScript, or pointer precision. When platform enhancement
runs, it moves the actual DOM nodes rather than applying CSS visual order, keeping reading,
visual, and keyboard order aligned. Recommendation labels are visible text inside the
matching option and remain hidden for unknown platforms or when JavaScript is disabled.

## GitHub Pages Workflow

`.github/workflows/pages.yml` owns validation and deployment. An unfiltered
`pull_request:` trigger validates every pull request. Pushes to `main` and manual
dispatches run the same gate. All checkouts use the exact event source SHA rather than an
implicit moving branch.

The validation job runs on `ubuntu-latest` with only `contents: read` and executes:

```bash
python3 -m unittest discover -s tests/site -p 'test_*.py'
node --test tests/site/platform.test.mjs
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

`tests/site/test_site.py` uses only Python's standard library. `platform.test.mjs` uses
only Node's built-in test runner and imports the same browser module shipped by the site;
there is no package manifest or installed test dependency. The implemented suite verifies:

- the exact site tree contains only expected regular files and no symlinks;
- `.nojekyll` is present as an empty regular file; HTML, CSS, icon, local module, and all
  eight JPEGs are present as non-empty regular files;
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
- the exact GoatCounter script retains its endpoint, explicit HTTPS source, and `async`;
  the only other script is the exact local ES module, and there is no inline script,
  public counter element, unreviewed external host, or third runtime script;
- platform tests execute Windows, macOS, Safari fallback, touch-capable iPad, and unknown
  inputs. They prove signal precedence, idempotent DOM reordering, recommendation labels,
  aligned DOM/focus order, unchanged unknown behavior, and continued visibility of both
  options. Source mutation controls reject redirects, automatic clicks, changed URLs,
  hidden alternatives, dynamic code, timers, network APIs, cookies, storage, workers, and
  CSS-only reordering;
- CSS contains the approved tokens, focus-visible handling, reduced-motion handling, and
  responsive rules without external font or stylesheet requests. Standard-library
  contrast calculations require at least 4.5:1 for every normal, hover, and focus-state
  text/background pair and at least 3:1 for focus indicators against adjacent colors;
- the JPEG marker structure, exact dimensions, metadata exclusions, per-group and total
  budgets, source-asset separation, explicit HTML dimensions, alt text, lazy loading, and
  asynchronous decoding satisfy the photograph and generated-illustration contracts;
- privacy, platform requirements, signing warnings, physical limitations, app telemetry,
  source, MIT license, Releases, Hammerspoon guidance, and the `Built by farihmhmd.com`
  credit remain discoverable in visible copy, while analytics/vendor/tracking language is
  absent from all visible text;
- the Privacy section contains exactly the approved app-local paragraph and none of the
  visible terms `GoatCounter`, `analytics`, `visit`, `visitor`, `tracking`, `cookie`, `IP
  address`, or `user agent` in any case or plural form;
- the Requirements definition list contains exactly four rows in this order: `Windows`,
  `macOS`, `What ScreenFix does`, and `Window limitations`, with every approved platform,
  signing, Accessibility, damage, and excluded-window fact present in the corresponding
  row;
- exactly three download paragraphs use the 15-pixel supporting-note treatment: the
  Windows SmartScreen warning, Windows uncompressed-fallback note, and macOS Accessibility
  note. Mutation controls reject a missing category, an extra ordinary paragraph using
  the class, or an effective font size other than 15 pixels;
- the footer's final child is a dedicated credit row whose exact visible text is `Built by
  farihmhmd.com` and whose only link has the exact label `farihmhmd.com` and exact target
  `https://farihmhmd.com/`;
- the full-width header rule, centered underline-free mobile brand, 15-pixel supporting
  notes, illustrated ruled How rows, open Privacy grid, and illustrated four-row
  Requirements definition list retain effective values at 375, 768, 1024, and 1440 CSS
  pixels without generic cards or horizontal overflow;
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

After automated validation, manual acceptance opens the served page at 375×812, 768×1024,
1024×768, and 1440×900, navigates it entirely by keyboard, verifies the full-width header
rule and mobile brand treatment, inspects all eight JPEGs at original detail, and follows
the three native download links to current release assets. Windows, macOS, and unknown
platform states are exercised. The merged Pages deployment is then checked at the default
URL in a private browsing session with JavaScript enabled and disabled.

## Failure Handling

A missing asset, unresolved anchor, malformed or metadata-bearing image, unsafe platform
module, unexpected external script, stale release filename, inaccessible structure, or
weakened workflow permission fails the validation job before deployment.

Publishing uses a freshly assembled Pages artifact from the validated commit. If artifact
upload or deployment fails, the previously deployed Pages version remains the public
site; no partial directory is promoted. Manual dispatch provides a recovery path after a
transient Pages failure but cannot deploy a non-`main` ref.

If a future release renames a native asset, the direct-link test fails in the same change
that updates the page. If the local platform module fails, both downloads remain visible
in static source order. If GoatCounter is unavailable, the page and downloads continue to
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
