# Native macOS App Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real Hammerspoon-free Apple Silicon `ScreenFix.app` that conservatively remembers one display, renders the exact three permanent black masks, exposes honest Phase 1 menu controls, persists JSON configuration, and packages as `ScreenFix-macos-arm64.zip` using the installed Command Line Tools and Swift 5.7.

**Architecture:** Keep defaults, validation, display matching, persistence, and geometry in a deterministic `ScreenFixCore` Swift package target. A thin `ScreenFixApp` library maps fresh `NSScreen` values to that core, owns a menu-bar controller and three transactional click-through `NSPanel` masks, and a one-file launcher supplies the executable entry point. Because this host's incomplete Command Line Tools cannot load `PackageDescription` or XCTest, checked scripts compile the same target boundaries and dependency-free tests directly with `swiftc`; the SwiftPM manifest remains the canonical healthy-toolchain definition. A final script assembles and ad-hoc signs a conventional `.app` bundle, then rejects the release unless its plist, signature, file layout, deployment target, and only executable architecture are correct.

**Tech Stack:** Swift 5.7 compiler, SwiftPM-compatible package layout, a dependency-free Swift test runner, Foundation, AppKit, Core Graphics, POSIX shell, `codesign`, `plutil`, `lipo`, `vtool`, and `ditto`

---

## Scope, prerequisites, and release honesty

Read these first and treat them as requirements:

- `docs/screenfix-behavior-contract.md`
- `docs/superpowers/specs/2026-08-15-native-packaging-design.md`

Phase 1 is useful but intentionally incomplete. It must:

- run natively on macOS 13 or later on Apple Silicon without Hammerspoon;
- let the user select a connected display from the menu;
- persist the display UUID plus diagnostics and the exact permanent defaults;
- resolve the saved display by UUID first and only use a unique name-and-size fallback;
- draw exactly three opaque, black, nonactivating, click-through masks over the full
  selected display bounds;
- keep existing masks alive until all replacement panels are configured and ordered;
- support Enable/Disable, Select Monitor, Reset to Defaults, Reload, and Quit;
- reload after display changes and wake without caching `NSScreen.screens`;
- preserve an invalid configuration file for diagnosis; and
- produce `native/macos/artifacts/ScreenFix.app` and
  `native/macos/artifacts/ScreenFix-macos-arm64.zip`.

Phase 1 must not request Accessibility access, inspect or move other apps' windows, or
pretend calibration exists. The menu contains disabled `Calibrate (Phase 2)` and
`Window guard: unavailable in Phase 1` items. The fixed default masks work without any
privacy permission. Calibration, pointer gestures and snapping, Accessibility window
guarding, AX observers, automatic safe-window placement, Developer ID signing, and
notarization are Phase 2 or release-engineering work.

The available development host is the supported baseline for this plan:

```text
Apple Swift version 5.7.2
Target: arm64-apple-darwin22.2.0
Command Line Tools: /Library/Developer/CommandLineTools
macOS 13.1
```

Do not require the full Xcode application. Stop rather than silently changing the
deployment target or creating an x86_64 artifact if any prerequisite check fails.
The current app and tests must still build through the checked direct-compiler scripts;
repairing Command Line Tools is not a prerequisite for the Phase 1 artifact.

## File structure

Create this focused Phase 1 structure:

```text
native/macos/
├── .gitignore
├── Package.swift
├── README.md
├── Resources/
│   ├── Info.plist
│   └── ScreenFixMenuIcon.png
├── Sources/
│   ├── ScreenFixCore/
│   │   ├── ConfigStore.swift
│   │   ├── ConfigValidator.swift
│   │   ├── DefaultConfiguration.swift
│   │   ├── DisplaySelector.swift
│   │   ├── MaskGeometry.swift
│   │   └── Models.swift
│   ├── ScreenFixApp/
│   │   ├── AppDelegate.swift
│   │   ├── AppModule.swift
│   │   ├── DisplayCatalog.swift
│   │   ├── MaskPanelController.swift
│   │   ├── MenuBarController.swift
│   │   └── RuntimeController.swift
│   └── ScreenFixLauncher/
│       └── Main.swift
├── Tests/ScreenFixTests/
│   ├── Main.swift
│   ├── TestHarness.swift
│   ├── ConfigStoreTests.swift
│   ├── ConfigValidatorTests.swift
│   ├── DefaultConfigurationTests.swift
│   ├── DisplayCatalogTests.swift
│   ├── DisplaySelectorTests.swift
│   ├── MaskGeometryTests.swift
│   ├── MaskPanelTests.swift
│   ├── MenuModelTests.swift
│   ├── MenuStateTests.swift
│   └── RuntimeControllerTests.swift
└── scripts/
    ├── build-release.sh
    ├── run-tests.sh
    └── package-arm64.sh
```

`ScreenFixCore` must not import AppKit or Core Graphics. `ScreenFixApp` is an AppKit
library target and the sole OS adapter; `ScreenFixLauncher` is only the executable entry
point. This split lets the local SwiftPM test runner import app adapters without linking
two executable entry points. Keep source types `internal` unless another target requires
a public API. Use concise doc comments only where a boundary is not obvious.

The installed Command Line Tools have two proven omissions: `swift package dump-package`
fails with `no such module 'PackageDescription'`, and `swift test` reports
`XCTest not available`. Do not install full Xcode or hide those failures. Instead,
`ScreenFixTests` is a SwiftPM-compatible executable product with a tiny test registry,
throwing assertions, `--filter` support, nonzero exit on failure, and deterministic
`PASS`/`FAIL` plus summary output. `run-tests.sh` builds the core and app as static Swift
modules, links that same runner, and runs it with the installed compiler. The release
script uses the same module boundaries. A healthy Swift toolchain can also build the
declared products directly from `Package.swift` later.

Optional SwiftPM repair, outside this implementation, is to reinstall the matching
Command Line Tools package through Apple's Software Update or Apple Developer Downloads,
then point `xcode-select` at the repaired CLT directory. A human with administrator
authority performs that system change. Verify the repair before using SwiftPM:

```bash
find "$(xcode-select -p)/usr/lib/swift/pm/ManifestAPI" -name 'PackageDescription.swiftmodule' -print
swift package --package-path native/macos dump-package >/dev/null
swift run --package-path native/macos ScreenFixTests
swift build --package-path native/macos -c release --product ScreenFix
```

Do not fabricate files under `/Library/Developer`, and do not make repair a prerequisite
for `run-tests.sh`, `build-release.sh`, or `package-arm64.sh`.

The adapter choices use APIs present in the installed macOS 13 SDK and current official
Apple documentation: [`NSScreen.screens`](https://developer.apple.com/documentation/appkit/nsscreen/screens),
[`NSStatusBar.statusItem(withLength:)`](https://developer.apple.com/documentation/appkit/nsstatusbar/statusitem(withlength:)),
[`NSWindow.orderFrontRegardless()`](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()),
and [Foundation atomic data writes](https://developer.apple.com/documentation/foundation/data/write(to:options:)).
Compile probes and the package assertions remain mandatory because documentation lookup
does not prove availability in this particular incomplete toolchain.

### Task 1: Scaffold the Swift 5.7 package

**Files:**

- Create: `native/macos/.gitignore`
- Create: `native/macos/Package.swift`
- Create: `native/macos/Sources/ScreenFixCore/Models.swift`
- Create: `native/macos/Sources/ScreenFixLauncher/Main.swift`
- Create: `native/macos/Sources/ScreenFixApp/AppModule.swift`
- Create: `native/macos/Tests/ScreenFixTests/Main.swift`
- Create: `native/macos/Tests/ScreenFixTests/TestHarness.swift`
- Create: `native/macos/Tests/ScreenFixTests/PackageSmokeTests.swift`
- Create: `native/macos/scripts/build-release.sh`
- Create: `native/macos/scripts/run-tests.sh`

- [ ] **Step 1: Prove the required local tools are present**

Run from the repository root:

```bash
swift --version
test "$(uname -m)" = "arm64"
test "$(sw_vers -productVersion | cut -d. -f1)" -ge 13
test "$(xcode-select -p)" = "/Library/Developer/CommandLineTools"
for tool in codesign ditto file lipo plutil swift swiftc unzip vtool; do command -v "$tool"; done
find /Library/Developer/CommandLineTools/usr/lib/swift -name 'PackageDescription.swiftmodule' -print
find /Library/Developer/CommandLineTools/usr/lib/swift -name 'XCTest.swiftmodule' -print
```

Expected: Swift reports `Apple Swift version 5.7.2` and target
`arm64-apple-darwin22.2.0`; every command exits zero and the last two commands print no
matches, proving why SwiftPM/XCTest cannot be the executable path on this host. A newer compatible compiler
may run the package later, but the implementation must compile in Swift 5 language mode.

- [ ] **Step 2: Write the package manifest and the smallest test targets**

Create `Package.swift` with this exact target boundary:

```swift
// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "ScreenFix",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ScreenFixCore", targets: ["ScreenFixCore"]),
        .executable(name: "ScreenFix", targets: ["ScreenFixLauncher"]),
        .executable(name: "ScreenFixTests", targets: ["ScreenFixTests"]),
    ],
    targets: [
        .target(name: "ScreenFixCore"),
        .target(name: "ScreenFixApp", dependencies: ["ScreenFixCore"]),
        .executableTarget(name: "ScreenFixLauncher", dependencies: ["ScreenFixApp"]),
        .executableTarget(
            name: "ScreenFixTests",
            dependencies: ["ScreenFixCore", "ScreenFixApp"],
            path: "Tests/ScreenFixTests"
        ),
    ]
)
```

Ignore `.build/` and `artifacts/` only inside `native/macos`. Add an empty public
`ScreenFixConfiguration` placeholder in `Models.swift`, an empty public
`ScreenFixApplication.run()` placeholder in `AppModule.swift`, and a compile-safe `@main`
launcher that calls it. The test executable's `@main` registers one smoke `TestCase`.

`TestHarness.swift` defines `TestCase(name:body:)`, `expect`, generic `expectEqual`,
floating-point `expectEqual(_:_:accuracy:)`, and `expectThrows`. Its runner accepts an
optional `--filter substring`, executes matching cases, prints one line per case plus
`Executed N tests, F failures`, and exits nonzero if no test matches or any case fails.
Each later test file exposes one `[TestCase]` constant, and `Main.swift` explicitly
concatenates those arrays. This avoids reflection or test discovery unavailable in the
Command Line Tools-only environment.

Every task that creates or deletes a test file must update
`Tests/ScreenFixTests/Main.swift` in the same RED commit. A newly registered test must
fail before its production type exists; an unregistered test is not accepted as RED or
GREEN. Because this is an ordinary executable target rather than an XCTest target,
every production symbol exercised across a target boundary needs an explicit minimal
`public` declaration and every public value type needs an explicit `public init`.

- [ ] **Step 3: Add direct compiler scripts for the proven target boundaries**

Both scripts use `#!/bin/bash`, `set -euo pipefail`, absolute paths derived from their
own location, `-target arm64-apple-macosx13.0`, and `-swift-version 5`. They reject a
non-arm64 host and keep all intermediates under explicit ignored directories.

`run-tests.sh` must:

1. compile `Sources/ScreenFixCore/*.swift` with `-parse-as-library -emit-module
   -emit-library -static -module-name ScreenFixCore` into
   `.build/manual-tests/libScreenFixCore.a` and `ScreenFixCore.swiftmodule`;
2. compile `Sources/ScreenFixApp/*.swift` the same way as module `ScreenFixApp`, adding
   `-I .build/manual-tests` and linking no entry point;
3. compile `Tests/ScreenFixTests/*.swift` with `-parse-as-library`, both module search
   paths and static archives, plus `-framework AppKit -framework CoreGraphics`, into
   `.build/manual-tests/ScreenFixTests`;
4. assert the runner architecture is exactly arm64 with `lipo -archs`; and
5. execute the runner, forwarding every shell argument such as `--filter ConfigStore`.

`build-release.sh` repeats the core/app static-module steps under
`.build/manual-release` with `-O`, then compiles `Sources/ScreenFixLauncher/*.swift` with
`-parse-as-library`, both static archives, AppKit, and Core Graphics into
`.build/manual-release/ScreenFix`. It asserts that `file` reports a Mach-O arm64
executable, `lipo -archs` returns exactly `arm64`, and `vtool -show-build` reports macOS
minimum 13.0. Print the absolute executable path as the final output line.

Use this compile pattern in both scripts, adding `-O` only in the release script:

```bash
swiftc -target arm64-apple-macosx13.0 -swift-version 5 -parse-as-library \
  -emit-module -emit-library -static -module-name ScreenFixCore \
  -emit-module-path "$BUILD_DIR/ScreenFixCore.swiftmodule" \
  "${CORE_SOURCES[@]}" -o "$BUILD_DIR/libScreenFixCore.a"

swiftc -target arm64-apple-macosx13.0 -swift-version 5 -parse-as-library \
  -emit-module -emit-library -static -module-name ScreenFixApp -I "$BUILD_DIR" \
  -emit-module-path "$BUILD_DIR/ScreenFixApp.swiftmodule" \
  "${APP_SOURCES[@]}" -o "$BUILD_DIR/libScreenFixApp.a"
```

Link archive order as `libScreenFixApp.a` then `libScreenFixCore.a`. The test link input
is `"${TEST_SOURCES[@]}"`; the release link input is
`"${LAUNCHER_SOURCES[@]}"`. Both final link commands include `-parse-as-library`,
`-I "$BUILD_DIR"`, `-framework AppKit`, and `-framework CoreGraphics`. Recreate only the
exact derived `$BUILD_DIR` at the start of a script so removed tests or modules cannot
survive as stale objects.

Do not copy Swift libraries into the app. macOS 13 supplies the system Swift runtime;
the two ScreenFix modules are statically linked into one executable.

- [ ] **Step 4: Build and test the empty package layout**

Run:

```bash
chmod +x native/macos/scripts/build-release.sh native/macos/scripts/run-tests.sh
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
```

Expected: the runner prints one package smoke PASS and
`Executed 1 tests, 0 failures`; the release script prints an executable path and every
architecture/deployment assertion passes using only the installed Command Line Tools.

- [ ] **Step 5: Commit the scaffold**

```bash
git add native/macos
git commit -m "build: scaffold native macOS app"
```

### Task 2: Lock the exact defaults and absolute mask geometry

**Files:**

- Modify: `native/macos/Sources/ScreenFixCore/Models.swift`
- Create: `native/macos/Sources/ScreenFixCore/DefaultConfiguration.swift`
- Create: `native/macos/Sources/ScreenFixCore/MaskGeometry.swift`
- Create: `native/macos/Tests/ScreenFixTests/DefaultConfigurationTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/MaskGeometryTests.swift`
- Delete: `native/macos/Tests/ScreenFixTests/PackageSmokeTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing permanent-default tests**

Define tests before production types. Use `expectEqual(..., accuracy: 1e-12)` for
floating-point results and require these exact oracles:

```swift
let display = DisplayIdentity(
    stableId: "3F8D0E18-EXAMPLE",
    name: "Ultrawide",
    width: 3440,
    height: 1440,
    vendorId: 1,
    modelId: 2,
    serialNumber: 3
)
let config = DefaultConfiguration.make(for: display, enabled: true)

try expectEqual(config.schemaVersion, 1)
try expect(config.enabled)
try expectEqual(config.bands.count, 3)
try expectEqual(config.bands[0].x, 1215.0 / 3440.0, accuracy: 1e-12)
try expectEqual(config.bands[0].w, (1920.0 - 1215.0) / 3440.0, accuracy: 1e-12)
try expectEqual(config.bands.map(\.y), [0.0, 0.34, 0.73])
try expectEqual(config.bands.map(\.h), [0.34, 0.39, 0.27])
```

Also prove `enabled: false` is preserved and every invocation constructs a fresh value
without shared mutable band storage.

- [ ] **Step 2: Write failing local and absolute geometry tests**

For display-local top-left coordinates on a 3440 by 1440 display, assert every default
band starts at `x = 1215`, ends at `x = 1920`, and the frames are:

```text
{ x=1215, y=0,      w=705, h=489.6 }
{ x=1215, y=489.6,  w=705, h=561.6 }
{ x=1215, y=1051.2, w=705, h=388.8 }
```

Assert the first top is `0`, each adjacent pair touches exactly, and the last bottom is
`1440`. For `TopLeftDisplayBounds(x: -3440, y: -900, width: 3440, height: 1440)`, assert
the first absolute origin is `(-2225, -900)` without clamping a negative global origin.
Also assert normalized rectangles use half-open intersection: touching edges do not
intersect, while a one-point overlap does.

- [ ] **Step 3: Run the focused tests to prove RED**

Run:

```bash
native/macos/scripts/run-tests.sh --filter DefaultConfiguration
native/macos/scripts/run-tests.sh --filter MaskGeometry
```

Expected: FAIL because the model, exact defaults, intersection, and projection APIs do
not exist. Do not add production code before observing this failure.

- [ ] **Step 4: Implement the minimal immutable models and geometry**

Use `Codable`, `Equatable`, value-semantic structs with these public shapes:

```swift
public struct NormalizedRect: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct DisplayIdentity: Codable, Equatable {
    public let stableId: String
    public let name: String
    public let width: Double
    public let height: Double
    public let vendorId: UInt32?
    public let modelId: UInt32?
    public let serialNumber: UInt32?
    public init(
        stableId: String,
        name: String,
        width: Double,
        height: Double,
        vendorId: UInt32? = nil,
        modelId: UInt32? = nil,
        serialNumber: UInt32? = nil
    ) {
        self.stableId = stableId
        self.name = name
        self.width = width
        self.height = height
        self.vendorId = vendorId
        self.modelId = modelId
        self.serialNumber = serialNumber
    }
}

public struct ScreenFixConfiguration: Codable, Equatable {
    public let schemaVersion: Int
    public let enabled: Bool
    public let display: DisplayIdentity
    public let bands: [NormalizedRect]
    public init(
        schemaVersion: Int,
        enabled: Bool,
        display: DisplayIdentity,
        bands: [NormalizedRect]
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.display = display
        self.bands = bands
    }
}

public struct RectD: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    public var right: Double { x + width }
    public var bottom: Double { y + height }
    public func intersects(_ other: RectD) -> Bool {
        x < other.right && other.x < right && y < other.bottom && other.y < bottom
    }
}
```

`DefaultConfiguration.make` must form `1215.0 / 3440.0` and
`(1920.0 - 1215.0) / 3440.0` in code, never rounded literals. `MaskGeometry.localFrames`
multiplies normalized values by the selected display's current full width and height.
`absoluteTopLeftFrames` adds the supplied live top-left global origin after local
projection. Do not use a work area or `NSScreen.visibleFrame`.

Make the initializers above, `DefaultConfiguration.make`, and the tested
`MaskGeometry` methods explicitly public. Do not make unrelated implementation details
public merely to simplify the runner.

- [ ] **Step 5: Run focused and complete tests to prove GREEN**

Run:

```bash
native/macos/scripts/run-tests.sh --filter DefaultConfiguration
native/macos/scripts/run-tests.sh --filter MaskGeometry
native/macos/scripts/run-tests.sh
```

Expected: all default and geometry tests pass; the complete package remains green.

- [ ] **Step 6: Commit the core defaults and geometry**

```bash
git add native/macos/Sources/ScreenFixCore native/macos/Tests/ScreenFixTests
git commit -m "feat: add native macOS mask geometry"
```

### Task 3: Validate configuration and match displays conservatively

**Files:**

- Create: `native/macos/Sources/ScreenFixCore/ConfigValidator.swift`
- Create: `native/macos/Sources/ScreenFixCore/DisplaySelector.swift`
- Create: `native/macos/Tests/ScreenFixTests/ConfigValidatorTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/DisplaySelectorTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write the failing configuration-validation matrix**

Start from a valid default and assert `ConfigValidator.validate` accepts it. Then mutate
one field per test and require a typed `ConfigurationError` for:

- schema version `0` or `2`;
- an empty or whitespace-only `display.stableId`;
- non-finite or non-positive display width or height;
- any band count other than exactly three;
- non-finite `x`, `y`, `w`, or `h`;
- `x < 0`, `y < 0`, `w <= 0`, or `h <= 0`; and
- `x + w > 1` or `y + h > 1`.

Include `Double.nan`, `Double.infinity`, and `-Double.infinity` explicitly. Boundary
values whose right or bottom edge equals `1` must pass.

- [ ] **Step 2: Write failing conservative display-selection tests**

Define a pure `ConnectedDisplay` descriptor whose `stableId`, vendor, model, and serial
diagnostics are optional and whose name and full logical dimensions are always present.
Give it an explicit public initializer. Prove:

1. a stable-ID match wins even when another display has the same name and dimensions;
2. stable IDs compare case-insensitively because UUID string casing is not identity;
3. with no stable-ID match, exactly one name-and-dimensions match is selected;
4. zero fallback matches returns `nil`;
5. two fallback matches returns `nil`; and
6. a same-name display with different width or height returns `nil`.

Do not add a primary-screen, array-order, nearest-size, vendor/model, or serial fallback.

- [ ] **Step 3: Run the new tests to prove RED**

Run:

```bash
native/macos/scripts/run-tests.sh --filter ConfigValidator
native/macos/scripts/run-tests.sh --filter DisplaySelector
```

Expected: FAIL because the validator, typed errors, connected-display descriptor, and
selector do not exist.

- [ ] **Step 4: Implement only the tested validation and matching rules**

`ConfigValidator.validate(_:) throws` must call `isFinite` before comparisons and must
not repair invalid input. `DisplaySelector.select(saved:from:)` returns a
`ConnectedDisplay?`: search all non-`nil` UUIDs first, then return the fallback only if
the filtered name-and-exact-dimensions array has one element. Keep the original saved
UUID in persisted configuration when a unique diagnostic fallback is temporarily used.
Give `ConfigurationError`, `ConnectedDisplay`, its explicit initializer,
`ConfigValidator.validate`, and `DisplaySelector.select` the minimal public visibility
required by `ScreenFixTests` and `ScreenFixApp`.

- [ ] **Step 5: Run focused and complete tests to prove GREEN**

Run:

```bash
native/macos/scripts/run-tests.sh --filter ConfigValidator
native/macos/scripts/run-tests.sh --filter DisplaySelector
native/macos/scripts/run-tests.sh
```

Expected: every validation and ambiguity case passes with no app-target regression.

- [ ] **Step 6: Commit validation and display matching**

```bash
git add native/macos/Sources/ScreenFixCore native/macos/Tests/ScreenFixTests
git commit -m "feat: validate macOS configuration and display identity"
```

### Task 4: Persist JSON without destroying invalid input

**Files:**

- Create: `native/macos/Sources/ScreenFixCore/ConfigStore.swift`
- Create: `native/macos/Tests/ScreenFixTests/ConfigStoreTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing store tests against temporary directories**

Inject an explicit file URL in tests. Cover all of these independently:

- a missing file returns `nil` and does not create a default;
- save creates a missing `ScreenFix` directory and writes `config.json`;
- a valid configuration round-trips exactly;
- emitted UTF-8 JSON contains logical keys `schemaVersion`, `enabled`, `display`,
  `bands`, `x`, `y`, `w`, and `h`;
- decoding malformed JSON throws and leaves the original bytes unchanged;
- decoding structurally valid but contract-invalid JSON throws and leaves the original
  bytes unchanged; and
- a later valid save atomically replaces an older valid configuration.

Use a fresh `FileManager.default.temporaryDirectory` child per test. Register
`defer { try? FileManager.default.removeItem(at: exactTestDirectory) }` inside each test
body; there is no XCTest `tearDownWithError` lifecycle.

- [ ] **Step 2: Run the focused tests to prove RED**

Run:

```bash
native/macos/scripts/run-tests.sh --filter ConfigStore
```

Expected: FAIL because `ConfigStore` and its injectable URL do not exist.

- [ ] **Step 3: Implement the store with Foundation's atomic write**

Expose:

```swift
public final class ConfigStore {
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL
    public init(fileURL: URL, fileManager: FileManager = .default)
    public func load() throws -> ScreenFixConfiguration?
    public func save(_ configuration: ScreenFixConfiguration) throws
}
```

The default URL is exactly
`~/Library/Application Support/ScreenFix/config.json`, derived with
`FileManager.url(for:in:appropriateFor:create:)` or
`urls(for:in:)`, never by concatenating a home-directory string. `load` decodes and then
validates. `save` validates first, creates only the parent directory, encodes UTF-8 JSON
with sorted keys and pretty printing, appends one newline, and calls
`Data.write(to:options: .atomic)`. A failed load never calls save, renames, truncates, or
deletes the bad file.

- [ ] **Step 4: Run focused and complete tests to prove GREEN**

Run:

```bash
native/macos/scripts/run-tests.sh --filter ConfigStore
native/macos/scripts/run-tests.sh
```

Expected: all persistence tests pass and malformed bytes are preserved byte-for-byte.

- [ ] **Step 5: Commit JSON persistence**

```bash
git add native/macos/Sources/ScreenFixCore native/macos/Tests/ScreenFixTests
git commit -m "feat: persist native macOS configuration"
```

### Task 5: Adapt live displays and build three transactional mask panels

**Files:**

- Create: `native/macos/Sources/ScreenFixApp/DisplayCatalog.swift`
- Create: `native/macos/Sources/ScreenFixApp/MaskPanelController.swift`
- Create: `native/macos/Tests/ScreenFixTests/DisplayCatalogTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/MaskPanelTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing AppKit panel-property tests without showing a window**

Import `ScreenFixApp`. Have `MaskPanelFactory.make(frame:)` construct but not order a
panel, then assert with the dependency-free harness:

```swift
try expectEqual(panel.frame, frame)
try expect(panel.styleMask.contains(.nonactivatingPanel))
try expect(!panel.styleMask.contains(.titled))
try expect(!panel.styleMask.contains(.closable))
try expect(!panel.styleMask.contains(.miniaturizable))
try expect(!panel.styleMask.contains(.resizable))
try expect(panel.isOpaque)
try expectEqual(panel.backgroundColor, .black)
try expect(!panel.hasShadow)
try expect(panel.ignoresMouseEvents)
try expect(!panel.hidesOnDeactivate)
try expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
try expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
try expect(panel.collectionBehavior.contains(.stationary))
```

Initialize `NSApplication.shared` at the start of this test case, but never call
`run()` or order the returned panel. Close the panel with `defer`.

Also require a `MaskPanel` subclass whose `canBecomeKey` and `canBecomeMain` are both
`false`. Verify the chosen window level is above `NSWindow.Level.normal` but do not use
the screen-saver level or claim precedence over protected/system surfaces. Do not test
`styleMask.contains(.borderless)`: `.borderless` has raw value zero and that assertion
cannot detect a titled window.

- [ ] **Step 2: Write failing three-frame and replacement-ownership tests**

Inject a small `MaskWindow` protocol and factory into `MaskPanelController` so tests use
fakes and never display panels. Assert:

- preparing the three default local frames converted through a 3440 by 1440
  `NSScreen`-style full frame creates exactly three candidates;
- AppKit conversion is exactly
  `x = screen.minX + local.x` and
  `y = screen.maxY - local.y - local.height`;
- prepare configures all three candidates without ordering or closing an old window;
- candidate 2 or 3 failure closes only created candidates and leaves every old window
  open;
- discarding a prepared set closes only its candidates and leaves old windows open;
- commit orders and verifies all candidates before invoking an injected `beforeRetire`
  closure or closing any old window;
- an order/visibility failure on candidate 1, 2, or 3 closes every candidate, never runs
  `beforeRetire`, and leaves all old windows open;
- a throwing `beforeRetire` closure closes every shown candidate and leaves all old
  windows open;
- successful commit runs `beforeRetire` once, assigns the new committed set, and only
  then closes every old window;
- `removeAll()` is idempotent; and
- neither candidate nor committed masks accept mouse events.

Make the fake append `create-N`, `order-N`, `verify-N`, `before-retire`, and `close-N`
strings to one event log so transaction order is an exact assertion rather than an
inference. Expose a single-use `PreparedMasks` reference: after successful commit,
failed commit, or discard, a second terminal operation is inert.

- [ ] **Step 3: Write failing display-catalog adapter tests**

Give `DisplayCatalog` injectable screen-snapshot, UUID, and diagnostic providers. The
real screen provider is the only layer that touches `NSScreen`; tests supply lightweight
snapshots with direct display ID, name, full frame, visible frame, and an opaque
native-screen token.
Register `displayCatalogTests` in the runner and prove:

- calling `connectedDisplays()` twice invokes the screen provider twice and returns its
  changed second result, rather than caching the first enumeration;
- mixed-case UUID text is normalized to one documented lowercase representation;
- an unavailable UUID remains `nil` and is never synthesized from the direct display ID;
- logical width and height come from the full frame, not a supplied visible/work frame;
- negative full-frame origins are preserved on the app-side connected-screen value; and
- vendor, model, and serial values from the diagnostic provider map to the corresponding
  core `ConnectedDisplay` fields without becoming fallback selection rules.

- [ ] **Step 4: Run the AppKit tests to prove RED**

Run:

```bash
native/macos/scripts/run-tests.sh --filter MaskPanel
native/macos/scripts/run-tests.sh --filter DisplayCatalog
```

Expected: FAIL because display adapters, panel factory, window protocol, and transactional
controller do not exist. The test process must not show a panel.

- [ ] **Step 5: Implement fresh display enumeration**

`DisplayCatalog.connectedDisplays()` must read `NSScreen.screens` on every call. For each
screen:

1. read `NSScreenNumber` from `deviceDescription` as `CGDirectDisplayID`;
2. call `CGDisplayCreateUUIDFromDisplayID` and serialize the UUID string in a stable,
   case-normalized form;
3. record `localizedName`, `screen.frame.width`, and `screen.frame.height`;
4. record `CGDisplayVendorNumber`, `CGDisplayModelNumber`, and
   `CGDisplaySerialNumber` as diagnostics; and
5. retain the originating `NSScreen` only in the app adapter, never in core JSON.

If a UUID cannot be obtained, include the connected display with `stableId == nil` so
it can participate only in the contract's unique name-and-size fallback. Disable that
screen in the Select Monitor submenu because a new selection cannot persist a missing
stable identity. Do not cache a `CGDirectDisplayID`, UUID result, or `NSScreen` across
reconciliation.

Implement the injected providers used by the RED tests rather than adding a parallel
test-only catalog. The production screen provider maps a newly fetched
`NSScreen.screens` array into snapshots, the production UUID provider wraps
`CGDisplayCreateUUIDFromDisplayID`, and the diagnostic provider wraps the three
`CGDisplay*Number` calls. Keep opaque `NSScreen` ownership in the app-side result so the
mask controller can receive the exact current screen.

- [ ] **Step 6: Implement the tested panel behavior**

Convert the core's three top-left local frames to AppKit bottom-left frames only in
`MaskPanelController`. Use a borderless/nonactivating `NSPanel`, black background,
`isOpaque = true`, no shadow, `ignoresMouseEvents = true`,
`hidesOnDeactivate = false`, `.floating` level, and collection behavior
`[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.

`prepare(frames:on:)` validates exactly three finite positive frames before allocating
candidate 1, builds all candidates into a local array, and returns `PreparedMasks`
without showing them. On factory/configuration failure it closes only candidates, leaves
the committed array intact, and throws. `commit(_:beforeRetire:) throws` asks each
`MaskWindow` to `orderAndVerify() throws`; the real adapter calls
`orderFrontRegardless()` and then requires `isVisible == true`. Only after all three
verify does commit invoke the caller's throwing `beforeRetire` closure. A failure in
ordering, verification, or that closure closes all candidates and preserves the old
committed set. Success assigns the candidate array and then closes the old array.
`discard(_:)` closes only candidates. This provides an explicit failure seam even though
AppKit's `orderFrontRegardless()` has no return value, and lets Task 6 make config save
part of the same replacement transaction.

Give the catalog snapshot/provider types, catalog initializer, mask protocols,
factory/controller initializers, and properties used by `ScreenFixTests` explicit public
access. Keep the concrete committed-window array private.

- [ ] **Step 7: Run focused and complete tests to prove GREEN**

Run:

```bash
native/macos/scripts/run-tests.sh --filter MaskPanel
native/macos/scripts/run-tests.sh --filter DisplayCatalog
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
```

Expected: panel ownership tests pass without visible test windows; all core tests pass;
the release executable links AppKit and Core Graphics on Swift 5.7.

- [ ] **Step 8: Commit display and overlay adapters**

```bash
git add native/macos/Sources/ScreenFixApp native/macos/Tests/ScreenFixTests
git commit -m "feat: render native macOS masks"
```

### Task 6: Add the menu-bar lifecycle and honest Phase 1 controls

**Files:**

- Create: `native/macos/Sources/ScreenFixApp/AppDelegate.swift`
- Create: `native/macos/Sources/ScreenFixApp/MenuBarController.swift`
- Create: `native/macos/Sources/ScreenFixApp/RuntimeController.swift`
- Modify: `native/macos/Sources/ScreenFixApp/AppModule.swift`
- Modify: `native/macos/Sources/ScreenFixLauncher/Main.swift`
- Create: `native/macos/Tests/ScreenFixTests/MenuModelTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/MenuStateTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/RuntimeControllerTests.swift`
- Modify: `native/macos/Sources/ScreenFixCore/Models.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing pure menu-state tests**

Add a small `MenuState` value to core, derived from configuration, display connection,
and runtime error. Assert these exact Phase 1 semantics:

- no config: action title `Enable`, action disabled, Reset disabled, top status
  `Paused: select a monitor`;
- connected enabled config: title `Disable`, action enabled and checked, Reset enabled,
  no paused error;
- connected disabled config: title `Enable`, action enabled and unchecked, Reset
  enabled;
- disconnected enabled config: title `Disable`, action enabled and checked, Reset
  disabled, status `Paused: saved display is disconnected`;
- disconnected disabled config: title `Enable`, action enabled and unchecked, Reset
  disabled, with the same paused status;
- invalid reload: old runtime state remains, status starts `Paused: config error:`;
- `Calibrate (Phase 2)` is always disabled and unchecked; and
- `Window guard: unavailable in Phase 1` is always disabled.

Select Monitor and Reload are always enabled. Quit is always enabled.

In `MenuModelTests.swift`, test the exact ordered identifiers:

```text
paused-status?; window-guard-phase2; enabled-action; calibrate-phase2;
select-monitor; reset-defaults; reload; separator; quit
```

Assert `calibrate-phase2` and `window-guard-phase2` are disabled. Feed a display-provider
fake that returns display A on the first build and display B on the second; assert the
second Select Monitor submenu contains B and not A, proving each menu-open build calls
the provider again instead of caching `NSScreen.screens`. An unidentifiable display stays
visible but disabled, the current UUID is checked, and no entry is guessed as current.

- [ ] **Step 2: Run the menu-state tests to prove RED**

Run:

```bash
native/macos/scripts/run-tests.sh --filter MenuState
native/macos/scripts/run-tests.sh --filter MenuModel
```

Expected: FAIL because `MenuState` and the ordered menu model have not been defined.

- [ ] **Step 3: Implement the minimal menu-state and ordered-menu reducers and prove GREEN**

Implement both pure reducers without importing AppKit. Give their tested value types,
explicit initializers, and build functions public access; keep rendering helpers private.
Then run:

```bash
native/macos/scripts/run-tests.sh --filter MenuState
native/macos/scripts/run-tests.sh --filter MenuModel
```

Expected: all state/title/enabled/checked/status assertions pass.

- [ ] **Step 4: Write failing runtime transaction and lifecycle tests**

Inject protocols for the config store, fresh display catalog, prepared-mask owner, and
notification subscriptions. Use fakes with one shared event log. Register tests that
prove:

- startup with no file creates no panels and reports monitor selection;
- invalid configuration during startup creates no masks, preserves the bad file, and
  reports one config error;
- calling start twice creates only one notification subscription set and no duplicate
  masks;
- selecting a connected identified display executes `prepare`, three verified orders,
  `save` inside `beforeRetire`, and old closes in that order, then commits exact defaults;
- selection save failure executes `prepare`, verified orders, `save`, candidate closes,
  preserves prior in-memory config and masks, and reports one error;
- enabled Reset preserves enabled state and uses the same prepare/show/save/commit
  transaction;
- disabled Reset saves exact defaults without preparing masks and keeps masks absent;
- invalid Reload preserves old in-memory config and old masks;
- valid enabled Reload prepares and commits before replacing in-memory state;
- an order/visibility failure during selection, Reset, Reload, or reconcile closes
  candidates, does not run the save closure, and preserves old masks/config;
- candidate preparation failure never saves a new selection and preserves old state;
- a disconnected or ambiguous saved display removes masks and reports paused;
- repeated Reload or reconcile leaves exactly three committed masks, never six or nine;
- repeated `setEnabled(false)` logs mask removal only once before attempted persistence;
- repeated `setEnabled(true)` preserves enabled state and never duplicates masks;
- a display-change or wake callback calls the same reconcile path once;
- stop revokes notification tokens before removing masks, and a second stop is inert;
- quit stops once, invokes an injected termination closure once, and is inert when
  repeated; and
- a callback captured before stop carries the old generation and cannot reconcile after
  stop.

- [ ] **Step 5: Run runtime tests to prove RED**

Run:

```bash
native/macos/scripts/run-tests.sh --filter RuntimeController
```

Expected: FAIL because `RuntimeController` and its injectable boundaries do not exist.

- [ ] **Step 6: Implement one runtime owner**

`RuntimeController` owns `ConfigStore`, `DisplayCatalog`, `MaskPanelController`, current
configuration, runtime error, and observer tokens. Give it these idempotent operations:

```swift
func start()
func setEnabled(_ enabled: Bool)
func selectDisplay(stableId: String)
func resetToDefaults()
func reload()
func reconcile()
func stop()
func quit()
```

The rules are:

- startup loads the file; a missing file shows no masks and asks for monitor selection;
- valid enabled configuration plus an unambiguous live match transactionally replaces
  the three masks using the live full `NSScreen.frame`;
- a disconnected or ambiguous match immediately removes all masks and reports paused;
- `setEnabled(false)` immediately removes all masks, persists `enabled = false`, and is
  inert when already disabled;
- `setEnabled(true)` is inert when already enabled; otherwise it prepares a connected
  display's masks, commits with save in `beforeRetire`, and persists enabled without
  masks when the display is disconnected;
- selecting a display requires a non-`nil` UUID, prepares exact enabled-default masks,
  commits with desired-config save in `beforeRetire`; save failure closes only
  candidates and preserves prior runtime state;
- Reset creates exact defaults for the saved display, preserving its enabled state and
  using the same prepare/show/save/retire transaction when enabled; disabled Reset saves
  defaults without creating masks;
- Reload decodes and validates first; an invalid file preserves the old in-memory
  configuration and old committed masks and reports one config error;
- a candidate-panel failure preserves old committed masks and reports one mask error;
- successful reconciliation clears the prior error episode;
- stop removes notification callbacks first, removes masks second, and is safe twice;
- quit calls stop, then an injected termination closure once, and is safe twice.

Observe `NSApplication.didChangeScreenParametersNotification` and
`NSWorkspace.didWakeNotification`; both call the same `reconcile` path. Store observer
tokens and remove them before teardown. Call the supplied state-change closure after
every completed operation so the menu refreshes from one snapshot. Every observer
closure captures a monotonically increasing generation and returns immediately unless
it still matches the active generation.

Do not replace `currentConfiguration` until `MaskPanelController.commit` returns
successfully. Give only the injected protocol shapes, runtime initializer/operations,
and read-only snapshots used by the app and test runner explicit public access.

- [ ] **Step 7: Run runtime tests to prove GREEN**

Run:

```bash
native/macos/scripts/run-tests.sh --filter RuntimeController
native/macos/scripts/run-tests.sh
```

Expected: transaction ordering, failure preservation, callbacks, and idempotent teardown
all pass.

- [ ] **Step 8: Implement the menu without activating the app**

`MenuBarController` retains one `NSStatusItem` from
`NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`. Load
`ScreenFixMenuIcon.png` with `Bundle.main.url(forResource:withExtension:)`, set it to
template mode and 18 by 18 points, and use `SF` only as a development fallback if the
resource is absent.

Rebuild this exact menu from the runtime snapshot, preserving order:

```text
[optional disabled Paused: ...]
Window guard: unavailable in Phase 1      [disabled]
Disable | Enable                          [checked only while enabled]
Calibrate (Phase 2)                       [disabled]
Select Monitor >                          [fresh connected displays]
Reset to Defaults
Reload
----------------------------------------
Quit
```

Refresh `DisplayCatalog.connectedDisplays()` every time the menu opens. Check the saved
display by UUID; never preselect the first screen. Connected displays without UUIDs are
visible but disabled with `identity unavailable` appended. Target/action methods call
only `RuntimeController`; the Enable/Disable action passes the desired explicit boolean,
and Quit calls `runtime.quit()`. Menu methods do not create panels, write JSON, or call
`NSApplication.terminate` directly.

- [ ] **Step 9: Start the accessory app through AppDelegate**

`ScreenFixApplication.run()` in the app library must:

```swift
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
withExtendedLifetime(delegate) { app.run() }
```

The launcher `Main.main()` only calls `ScreenFixApplication.run()`.
`AppDelegate.applicationDidFinishLaunching` creates the store at the Application
Support URL, then constructs exactly one runtime and one menu controller and starts the
runtime. `applicationWillTerminate` calls runtime stop before releasing the status item.
Do not call `AXIsProcessTrusted`, create a Dock icon, open a main window, or request a
privacy permission in Phase 1.

- [ ] **Step 10: Build and run all tests**

Run:

```bash
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
```

Expected: all tests pass and the release executable builds with no unavailable-API or
Swift language-version errors.

- [ ] **Step 11: Commit the menu-bar lifecycle**

```bash
git add native/macos/Sources native/macos/Tests
git commit -m "feat: add native macOS menu lifecycle"
```

### Task 7: Build and assert the Apple Silicon app bundle

**Files:**

- Create: `native/macos/Resources/Info.plist`
- Create: `native/macos/Resources/ScreenFixMenuIcon.png`
- Create: `native/macos/scripts/package-arm64.sh`

- [ ] **Step 1: Prove packaging is RED before the script exists**

Run:

```bash
test ! -e native/macos/scripts/package-arm64.sh
./native/macos/scripts/package-arm64.sh
```

Expected: the first command passes and the second fails with `No such file or directory`.

- [ ] **Step 2: Add a versioned menu-only Info.plist**

Create an XML plist with these exact values:

```text
CFBundleExecutable = ScreenFix
CFBundleIdentifier = com.screenfix.ScreenFix
CFBundleName = ScreenFix
CFBundleDisplayName = ScreenFix
CFBundlePackageType = APPL
CFBundleShortVersionString = 0.1.0
CFBundleVersion = 1
LSMinimumSystemVersion = 13.0
LSUIElement = true
LSMultipleInstancesProhibited = true
NSHighResolutionCapable = true
NSPrincipalClass = NSApplication
```

Copy the existing reusable 36-by-36 transparent resource instead of inventing a new
asset:

```bash
cp assets/screenfix-menubar.png native/macos/Resources/ScreenFixMenuIcon.png
test "$(sips -g pixelWidth native/macos/Resources/ScreenFixMenuIcon.png 2>/dev/null | awk '/pixelWidth/ {print $2}')" = "36"
test "$(sips -g pixelHeight native/macos/Resources/ScreenFixMenuIcon.png 2>/dev/null | awk '/pixelHeight/ {print $2}')" = "36"
```

This is the status item resource, not a claim that a 36-pixel image is a full macOS app
icon set. A production `.icns` remains release polish.

- [ ] **Step 3: Implement the fail-fast packaging script**

Use `#!/bin/bash` and `set -euo pipefail`. Resolve the script directory, macOS package
directory, and repository root without depending on the caller's current directory.
Reject a non-arm64 host before building. Then:

1. run `$MACOS_DIR/scripts/build-release.sh` and use its final output line as the binary
   path;
2. assert that resolved binary stays under `$MACOS_DIR/.build/manual-release`;
3. remove only the explicit `$MACOS_DIR/artifacts/ScreenFix.app` and zip paths;
4. create `Contents/MacOS` and `Contents/Resources`;
5. copy the release `ScreenFix` binary, plist, and status icon into their conventional
   bundle locations;
6. make only `Contents/MacOS/ScreenFix` executable;
7. ad-hoc sign with
   `codesign --force --sign - --timestamp=none "$APP_PATH"`;
8. create the zip with
   `ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"`; and
9. print both absolute artifact paths.

Before zipping, fail unless every assertion below passes:

```bash
plutil -lint "$APP_PATH/Contents/Info.plist"
test "$(plutil -extract CFBundleExecutable raw "$APP_PATH/Contents/Info.plist")" = "ScreenFix"
test "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")" = "com.screenfix.ScreenFix"
test "$(plutil -extract LSMinimumSystemVersion raw "$APP_PATH/Contents/Info.plist")" = "13.0"
test "$(plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist")" = "true"
test "$(plutil -extract LSMultipleInstancesProhibited raw "$APP_PATH/Contents/Info.plist")" = "true"
test -x "$APP_PATH/Contents/MacOS/ScreenFix"
test -f "$APP_PATH/Contents/Resources/ScreenFixMenuIcon.png"
test "$(lipo -archs "$APP_PATH/Contents/MacOS/ScreenFix")" = "arm64"
file "$APP_PATH/Contents/MacOS/ScreenFix" | grep -q 'Mach-O 64-bit executable arm64'
vtool -show-build "$APP_PATH/Contents/MacOS/ScreenFix" | grep -q 'platform MACOS'
vtool -show-build "$APP_PATH/Contents/MacOS/ScreenFix" | grep -q 'minos 13.0'
test ! -d "$APP_PATH/Contents/Frameworks"
codesign --verify --strict --verbose=2 "$APP_PATH"
```

After zipping, use `unzip -t` and `unzip -Z1` to assert the archive is readable, all
entries live under `ScreenFix.app/`, and it contains the executable, plist, status icon,
and `_CodeSignature/CodeResources`. Reject any executable architecture besides exactly
`arm64`; a universal or accidental x86_64 result is not the requested artifact.

- [ ] **Step 4: Run the script to prove GREEN and inspect the artifacts**

Run:

```bash
chmod +x native/macos/scripts/package-arm64.sh
native/macos/scripts/package-arm64.sh
file native/macos/artifacts/ScreenFix.app/Contents/MacOS/ScreenFix
lipo -archs native/macos/artifacts/ScreenFix.app/Contents/MacOS/ScreenFix
codesign --display --verbose=2 native/macos/artifacts/ScreenFix.app 2>&1 | grep -E 'Identifier=|Signature='
unzip -t native/macos/artifacts/ScreenFix-macos-arm64.zip
```

Expected: package script succeeds; `file` and `lipo` report only arm64; signature reports
an ad-hoc identity; zip integrity reports no errors.

- [ ] **Step 5: Commit package inputs, not generated artifacts**

```bash
git add native/macos/Resources native/macos/scripts native/macos/.gitignore
git commit -m "build: package native macOS arm64 app"
```

`native/macos/artifacts/` stays ignored and is regenerated by the committed script.

### Task 8: Document installation, verify, and perform a live smoke test

**Files:**

- Modify: `README.md`
- Create: `native/macos/README.md`

- [ ] **Step 1: Correct the README for the artifact that now exists**

Remove the statement that the standalone app is not built. Keep the README concise and
add `native/macos/` to the file structure. Document:

```bash
native/macos/scripts/package-arm64.sh
```

as the collaborator build command, and these end-user steps:

1. extract `ScreenFix-macos-arm64.zip`;
2. drag `ScreenFix.app` to Applications;
3. Control-click and choose Open once for the ad-hoc test build;
4. choose the ScreenFix menu icon and Select Monitor; and
5. use Disable/Enable, Reset to Defaults, Reload, or Quit as needed.

State clearly that Phase 1 needs neither Hammerspoon nor Accessibility permission. It
uses the exact fixed 1215-to-1920 defaults on a 3440-wide display; calibration and window
movement are Phase 2. Also state that warning-free public distribution requires an Apple
Developer ID and notarization and that this local zip supports macOS 13+ Apple Silicon,
not Intel Macs.

Put detailed developer notes in `native/macos/README.md` so the root README stays short.
Record the observed host defect exactly: SwiftPM 5.7.1 cannot import
`PackageDescription`, XCTest is unavailable, and the two expected `.swiftmodule`
directories are absent from this CLT installation. Document `run-tests.sh` and
`build-release.sh` as the supported current-host commands, then include the optional
repair verification commands from the plan's prerequisite section. State that repair
means reinstalling the matching Apple Command Line Tools package and selecting it with
`xcode-select`; it does not require full Xcode and must be performed by a human with
administrator authority.

- [ ] **Step 2: Run the complete automated verification**

Run from the repository root:

```bash
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
native/macos/scripts/package-arm64.sh
lua tests/run.lua
git diff --check
git status --short
```

Expected: all Swift tests and all existing Lua tests pass; packaging assertions pass;
the diff check is silent; status shows only the intended README/native macOS changes or
is clean after their commits.

- [ ] **Step 3: Perform the first-launch menu smoke test**

Before opening, inspect rather than deleting an existing native config:

```bash
ls -l "$HOME/Library/Application Support/ScreenFix/config.json" 2>/dev/null || true
open native/macos/artifacts/ScreenFix.app
```

If the `ls` command prints an existing file, preserve it and mark the no-config
pre-selection check below as not applicable; this is then a saved-config/relaunch smoke
test. Do not claim first-launch behavior from that run. To perform the full first-launch branch, quit
ScreenFix first, move the exact config file to a uniquely named backup, run the smoke
test, quit again, move the smoke-created config beside that backup for inspection, and
restore the original path. Never overwrite either file. If no file exists, continue with
the full first-launch checks normally.

Verify manually on the Apple Silicon Mac:

- no Dock icon appears and exactly one ScreenFix status item appears;
- opening the same app bundle a second time leaves one `ScreenFix` process, one status
  item, and exactly three masks rather than duplicating resources;
- the menu says `Window guard: unavailable in Phase 1` and disables
  `Calibrate (Phase 2)`;
- on a genuine no-config first launch, no mask exists and Reset is disabled;
- Select Monitor lists current screens and does not force the first one;
- choosing the damaged display immediately creates exactly three black click-through
  panels spanning the default 1215-to-1920 region with no vertical gaps;
- clicking and trackpad gestures pass through every black panel to the app below;
- Disable removes all masks immediately and Enable restores them;
- Reset restores the exact defaults and preserves enabled state;
- Reload does not duplicate the menu item or panels;
- disconnecting the selected display removes masks and reports paused; an unambiguous
  reconnect restores them;
- Quit removes all masks and the menu item; and
- reopening the app reloads the saved selection without Hammerspoon running.

If another native ScreenFix configuration existed before the test, copy it to a named
backup before selection and restore it only after quitting. Never overwrite or delete an
unknown existing file merely to simplify the smoke test.

- [ ] **Step 4: Prove invalid-file preservation manually without risking the live file**

Rely on the temporary-directory unit test for corruption injection. Do not corrupt the
user's real Application Support file. Inspect the saved live JSON read-only:

```bash
plutil -convert json -o - "$HOME/Library/Application Support/ScreenFix/config.json"
```

Expected: schema version 1, a nonempty display UUID, enabled state, diagnostics, and
exactly three normalized bands.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md native/macos/README.md
git commit -m "docs: explain native macOS app installation"
```

- [ ] **Step 6: Run final release checks and record limitations**

Run:

```bash
native/macos/scripts/run-tests.sh
native/macos/scripts/package-arm64.sh
codesign --verify --strict --verbose=2 native/macos/artifacts/ScreenFix.app
test "$(lipo -archs native/macos/artifacts/ScreenFix.app/Contents/MacOS/ScreenFix)" = "arm64"
unzip -t native/macos/artifacts/ScreenFix-macos-arm64.zip
git diff --check
git status --short --branch
```

Expected: all checks pass and the feature branch is clean. Record these release
limitations in the handoff:

- artifact is ad-hoc signed and not notarized, so first launch may require Control-click
  Open;
- macOS 13+ Apple Silicon only;
- fixed exact default masks only in Phase 1;
- calibration and all pointer/edge/snap behavior are Phase 2;
- Accessibility window guard is Phase 2 and no permission is requested yet;
- no guarantee above secure, protected, system-owned, or exclusive full-screen content;
  and
- software masks cannot repair dead, leaking, or stuck physical pixels.
