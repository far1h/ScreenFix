# Native macOS ScreenFix

This directory builds the Hammerspoon-free ScreenFix Phase 1 menu-bar app for macOS 13
or later on Apple Silicon.

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

## Phase 1 behavior

The app remembers one display by its Core Graphics UUID, persists JSON in
`~/Library/Application Support/ScreenFix/config.json`, and draws three opaque,
click-through black masks. The permanent defaults span exactly 1215–1920 on a
3440-wide display. It supports Enable/Disable, Select Monitor, Reset to Defaults,
Reload, and Quit.

Phase 1 does not request Accessibility permission. Calibration and automatic window
movement are not included yet; the menu shows only controls that currently work.

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
