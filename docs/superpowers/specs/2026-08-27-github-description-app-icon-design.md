# GitHub Description and macOS App Icon Design

## Scope

Resolve the repository's two open GitHub issues without changing ScreenFix runtime
behavior:

- Set the GitHub repository description to `Masks damaged display regions and keeps
  ordinary windows in the usable area on either side.`
- Add the user-selected Screen Patch application icon to the native macOS bundle so it
  appears in Finder and Applications.

The macOS app remains a menu-bar-only utility. `LSUIElement=true`, the `.accessory`
activation policy, and the existing `ScreenFixMenuIcon.png` status-item image remain
unchanged. There is no version bump or replacement of the published v1.0.2 artifact in
this change.

## Root Cause

The GitHub repository description is empty. This is repository metadata rather than a
tracked file.

The macOS bundle has no `CFBundleIconFile` or `CFBundleIconName` entry, and its Resources
directory contains only the 36-by-22 menu-bar image. The package therefore supplies no
Finder/Applications icon and macOS displays the default application icon. The existing
package checks validate the status-item image but cannot detect this omission.

## Icon Artwork

`native/macos/Resources/ScreenFixAppIcon.svg` is the single committed source of truth.
It uses the approved Screen Patch design: a warm orange-to-red rounded-square field, a
cream display, a dark central mask, and a simple stand. The artwork uses only embedded
SVG geometry, fills, strokes, and gradients. It has no text, fonts, linked files,
scripts, or external resources.

The composition must remain recognizable at 16 pixels. Small representations may lose
fine crack and stitch details, but the display, central mask, warm field, and stand must
remain distinct. The SVG is deterministic and reviewable; image generation is not used
for the final asset because it could reinterpret the selected geometry.

## Icon Build

`native/macos/scripts/build-app-icon.sh` converts the SVG to a complete temporary
`ScreenFix.iconset` using the macOS-provided `sips` tool. It creates Apple's ten
standard filenames for 16, 32, 128, 256, and 512 point icons and their `@2x`
representations, checks every PNG's exact pixel dimensions, and converts the iconset to
`ScreenFix.icns` with `iconutil`.

The script uses `set -euo pipefail`, resolves paths relative to itself, verifies required
tools and inputs, creates its workspace with `mktemp -d`, and removes it through a trap.
It writes the generated icon to `.build/manual-release` only after every representation
and the final non-empty ICNS file pass validation. It prints the final path on its last
line, matching the existing release-builder convention.

Generated PNGs, iconsets, ICNS files, app bundles, and ZIPs remain ignored artifacts.
Generating during packaging avoids committing an opaque binary that can drift from the
SVG source. This remains a macOS-only release step, consistent with the existing uses of
`swiftc`, `vtool`, `codesign`, `ditto`, and the arm64 host check.

## Bundle Integration

`native/macos/Resources/Info.plist` adds `CFBundleIconFile` with the exact value
`ScreenFix.icns`. A traditional ICNS resource is used because this repository manually
assembles the app bundle without Xcode or an asset-catalog compiler.

`native/macos/scripts/package-arm64.sh` runs the icon builder after the executable build,
rejects any reported path outside `.build/manual-release`, and copies the resulting file
to `ScreenFix.app/Contents/Resources/ScreenFix.icns`. Before signing, it verifies the
plist key, the non-empty icon resource, the unchanged menu icon, `LSUIElement=true`, and
the existing executable and platform constraints. After zipping, it requires the icon
resource under the single `ScreenFix.app/` archive root.

Signing remains last among bundle mutations so the app icon is covered by the ad-hoc
signature. No Swift target, source file, runtime dependency, or launch flow changes.

## Failure Handling

Icon generation and package assembly fail immediately if a required tool, source asset,
representation, dimension, plist value, bundle resource, signature, or ZIP entry is
missing or invalid. Temporary icon files are always removed. A failure cannot publish a
partial ICNS file or sign a bundle missing the icon.

Finder and Launch Services can cache application icons. Visual acceptance therefore uses
a freshly packaged and freshly extracted app rather than an older installed copy.

## Verification

Test-driven implementation starts with
`native/macos/scripts/test-package-arm64.sh`. Against the current code it must fail at the
missing `CFBundleIconFile` assertion, proving the open issue. After implementation it
must:

- run the real package command;
- verify `CFBundleIconFile=ScreenFix.icns` and `LSUIElement=true`;
- verify both the application ICNS and independent menu-bar PNG;
- expand the ICNS and validate all ten standard representation names and dimensions;
- verify the app's strict code signature and ZIP integrity;
- extract the ZIP, verify the icon entry and extracted signature, and confirm the bundle
  remains menu-bar-only; and
- inspect a fresh bundle in Finder/Applications at normal and small icon sizes.

The existing 244-test native suite and complete Lua suite run afterward as regression
coverage. The native macOS README adds only the new icon source/build/test commands and
keeps collaborator setup concise.

## GitHub Delivery

The description change is applied separately with `gh repo edit` and accepted only after
an exact `gh repo view --json description` readback. Issue #1 is closed only after that
readback succeeds.

Source changes are committed to `fix/remaining-github-issues`, pushed, and proposed in a
pull request targeting `main`. The PR body includes verification evidence and `Fixes #2`
so the app-icon issue closes on merge. It records issue #1 as a separately completed
repository-metadata change rather than claiming the PR carries that external state.
