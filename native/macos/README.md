# Native macOS ScreenFix

This directory builds the Hammerspoon-free ScreenFix menu-bar app for macOS 13 or later
on Apple Silicon.

## Build and test

From the repository root:

```bash
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
native/macos/scripts/package-arm64.sh
```

The package command creates ignored local artifacts at:

```text
native/macos/artifacts/ScreenFix.app
native/macos/artifacts/ScreenFix-macos-arm64.zip
```

The zip is ad-hoc signed. Extract it, drag `ScreenFix.app` to Applications, then
Control-click the app and choose Open once. A Developer ID signature and Apple
notarization are required for warning-free public distribution.

## Behavior

The app remembers one display by its Core Graphics UUID, persists JSON in
`~/Library/Application Support/ScreenFix/config.json`, and draws three opaque,
click-through black masks. The permanent defaults span exactly 1215–1920 on a
3440-wide display. **Calibrate** edits a working copy: drag a red band from its center
or resize it from any white edge, then choose **Save** to persist it. **Cancel** or
choosing the checked **Calibrate** item discards the working copy. A mouse can hold and
drag; a trackpad can tap, move, and tap again. Neither input style needs a modifier key.

The masks and calibration editor work without Accessibility permission. Automatic
window placement needs permission in **System Settings > Privacy & Security >
Accessibility**. When permission is missing, the menu shows one disabled guidance row
while the normal controls remain available. ScreenFix rechecks permission and starts
window correction automatically after access is granted; Reload is not required.

ScreenFix moves ordinary movable application windows to the deterministic nearest safe
side of the saved bands. It does not inspect window contents or activate applications.
Protected, custom, tool, full-screen, minimized, hidden, other-display, and non-movable
windows are excluded. A fixed-size standard window is moved only when its correction
preserves size. Applications that reject Accessibility writes are left unchanged without
blocking other applications.

## Current Command Line Tools limitation

On the development host, Swift Package Manager 5.7.1 cannot import
`PackageDescription`, XCTest is unavailable, and both expected `.swiftmodule`
directories are absent from the installed Command Line Tools. The checked
`run-tests.sh` and `build-release.sh` scripts compile the same target boundaries directly
with Swift 5.7 and are the supported commands on this host.

Reinstalling the matching Apple Command Line Tools package and selecting it with
`xcode-select` may repair SwiftPM. A human with administrator authority must perform that
system change; full Xcode is not required. Verify a repair with:

```bash
find "$(xcode-select -p)/usr/lib/swift/pm/ManifestAPI" -name 'PackageDescription.swiftmodule' -print
swift package --package-path native/macos dump-package >/dev/null
swift run --package-path native/macos ScreenFixTests
swift build --package-path native/macos -c release --product ScreenFix
```
