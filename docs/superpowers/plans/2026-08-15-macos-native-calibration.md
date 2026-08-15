# Native macOS Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the complete approved ScreenFix calibration experience to the native Apple Silicon app, including mouse and trackpad editing, all-edge resize, deterministic snapping, transactional Save/Cancel, topology safety, and a newly packaged arm64 app.

**Architecture:** Keep hit testing, drag/resize, snapping, layout, and pointer state in deterministic `ScreenFixCore` values. Add one AppKit adapter consisting of a full-display nonactivating `NSPanel` and flipped `NSView`; the view renders the approved controls and forwards primary-pointer events into the pure state machine. `RuntimeController` owns the calibration session generation and commits edited bands only through the existing mask/config replacement transaction.

**Tech Stack:** Swift 5.7 language mode, AppKit on macOS 13+, the existing direct `swiftc` test runner, Core Graphics, POSIX shell, `codesign`, `ditto`, and `unzip`

---

## Scope and fixed decisions

Implement against commit `4aaa999` and read these sources first:

- `docs/screenfix-behavior-contract.md`
- `screenfix/geometry.lua`
- `screenfix/calibration.lua`
- the calibration and controller cases in `tests/geometry_test.lua`,
  `tests/calibration_test.lua`, and `tests/controller_test.lua`
- `native/macos/Sources/ScreenFixCore/`
- `native/macos/Sources/ScreenFixApp/RuntimeController.swift`
- `native/macos/Sources/ScreenFixApp/MenuBarController.swift`
- `native/macos/Tests/ScreenFixTests/`

The existing Hammerspoon implementation and its tests are the visual and behavioral
oracle except for the cross-axis snap defect corrected in Task 1. Preserve these
constants exactly:

```text
edge hit region              8 points
minimum band size           20 x 20 points
movement threshold           4 points, Euclidean
snap threshold              12 points, inclusive
minimum editor             260 x 180 points
button margin/gap/size       24 / 12 / 104 x 42 points
instruction frame            24,24,330,42 points
narrow instruction cutoff   378 points; height 58; font 13
normal instruction font      15 points
button font                  16 points
```

The exact menu order after this slice is:

```text
[optional disabled Paused: ...]
Disable | Enable
Calibrate
Select Monitor >
Reset to Defaults
Reload
--------------------
Quit
```

`Calibrate` is checked while editing. Selecting the checked item again is Cancel.
Do not add `Phase`, `coming soon`, `unavailable`, or other developer-progress rows to
the product menu.

This slice does not implement Accessibility window correction. Calibration uses only
events delivered to ScreenFix's own AppKit panel and must not request Accessibility,
Input Monitoring, Screen Recording, or administrator permission.

Apple's current primary documentation confirms that a custom `NSView` handles
`mouseDown`, `mouseDragged`, `mouseMoved`, and `mouseUp` directly; handled events should
not be forwarded to `super`. `NSTrackingArea` can deliver mouse-moved events and can
track the visible rectangle automatically. `NSScreen.screens` must be read fresh after
topology changes. The local SDK remains the final availability gate:

- https://developer.apple.com/documentation/appkit/nsview
- https://developer.apple.com/documentation/appkit/nstrackingarea
- https://developer.apple.com/documentation/appkit/nswindow/acceptsmousemovedevents
- https://developer.apple.com/documentation/appkit/nsscreen/screens

Context7 was queried first as required, but its Apple catalog returned no matching API
pages; the links above are Apple's primary references. Use the existing macOS 13 SDK
and compile probes rather than adopting APIs unavailable to the project's baseline.

## File structure

```text
native/macos/Sources/ScreenFixCore/
├── CalibrationGeometry.swift       Hit, move, resize, clamp, and snap rules.
├── CalibrationInteraction.swift    Held-drag and tap-move-tap state machine.
└── CalibrationLayout.swift         Pure approved control and drawing geometry.
native/macos/Sources/ScreenFixApp/
├── CalibrationPanelController.swift Transactional editor ownership.
├── CalibrationPanel.swift           Nonactivating full-display panel.
├── CalibrationView.swift            Drawing and AppKit event adapter.
├── MenuBarController.swift          Adds the real Calibrate action.
└── RuntimeController.swift          Owns calibration session transactions.
native/macos/Tests/ScreenFixTests/
├── CalibrationGeometryTests.swift
├── CalibrationInteractionTests.swift
├── CalibrationLayoutTests.swift
├── CalibrationPanelTests.swift
└── RuntimeCalibrationTests.swift
```

Register every new test array in `Tests/ScreenFixTests/Main.swift` in its RED commit.
Do not place AppKit in `ScreenFixCore`.

### Task 1: Port the exact hit, drag, resize, and snap geometry

**Files:**

- Modify: `screenfix/geometry.lua`
- Modify: `tests/geometry_test.lua`
- Create: `native/macos/Sources/ScreenFixCore/CalibrationGeometry.swift`
- Create: `native/macos/Tests/ScreenFixTests/CalibrationGeometryTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Correct the Lua oracle with focused RED tests**

The current Lua `isSnapCandidate` rejects a horizontal snap when an unrelated height is
below 20 points and rejects a vertical snap when an unrelated width is below 20 points.
That conflicts with the gesture contract: body snapping does not resize, horizontal
edge snapping changes only width, and vertical edge snapping changes only height.

Add focused Lua tests proving:

- a narrow or short body still snaps while preserving its existing size;
- left/right snapping accepts a short-height band when resulting width is at least 20;
- top/bottom snapping accepts a narrow-width band when resulting height is at least 20;
- left/right rejects a resulting width below 20 but does not inspect height;
- top/bottom rejects a resulting height below 20 but does not inspect width; and
- an affected dimension of exactly 20 points is legal within the existing
  `displayAxis * 2^-48` tolerance.

Run only the geometry suite and observe the new cases fail for the cross-axis check:

```bash
lua tests/run.lua 2>&1 | tee /tmp/screenfix-lua-red.log
```

Expected RED: the new axis-specific cases fail while existing cases remain diagnostic.
Then change `isSnapCandidate` to receive the active part: body checks only normalized
bounds, left/right check resulting width, and top/bottom check resulting height. Remove
or update the old test named `rejects every target when another dimension is below 20
points`; it encodes the defect and must not remain as a contradictory oracle.

Run `lua tests/run.lua` and require every Lua case to pass before porting the corrected
behavior to Swift. Commit this independent correction:

```bash
git add screenfix/geometry.lua tests/geometry_test.lua
git commit -m "fix: make calibration snap checks axis-specific"
```

- [ ] **Step 2: Define the wished-for Swift API in failing tests**

Use value types with these public shapes:

```swift
public struct PointD: Equatable {
    public let x: Double
    public let y: Double
}

public enum CalibrationPart: Equatable {
    case body, left, right, top, bottom
}

public struct CalibrationHit: Equatable {
    public let bandIndex: Int
    public let part: CalibrationPart
}

public enum CalibrationGeometry {
    public static func hitTest(
        point: PointD,
        frames: [RectD],
        handleSize: Double
    ) -> CalibrationHit?

    public static func drag(
        band: NormalizedRect,
        part: CalibrationPart,
        delta: PointD,
        displaySize: RectD,
        minimumSize: Double
    ) -> NormalizedRect

    public static func snap(
        rawBand: NormalizedRect,
        activeIndex: Int,
        part: CalibrationPart,
        bands: [NormalizedRect],
        displaySize: RectD,
        threshold: Double
    ) -> NormalizedRect
}
```

Test the existing Lua golden cases, not merely representative examples:

- all four handles and the body;
- handles before bodies and later-rendered bands before earlier bands;
- the existing same-band corner order;
- body movement clamped on all screen edges;
- each edge resize holds its opposite edge fixed and never crosses 20 points;
- an already malformed undersized edge moves only back toward validity;
- inputs are never mutated;
- body leading and trailing edges snap to both screen edges;
- all four resized edges snap only to their legal screen boundary;
- all body and resize edges snap to both corresponding edges of every peer;
- exactly 12 points snaps and 12.01 points does not;
- screen targets beat peer targets at equal distance;
- lower peer index, peer start before peer end, and active leading edge win remaining
  equal-distance ties;
- a snap that would leave the display or violate 20 points on the dimension changed by
  an edge resize is rejected, while body snaps never add a minimum-size check;
- short-height horizontal resizes, narrow-width vertical resizes, narrow/short body
  snaps, and exact-20 affected dimensions match the corrected Lua oracle; and
- `NaN`, infinity, invalid indexes, invalid parts, or malformed peers fail closed to a
  fresh copy.

Use the Lua tolerance rule, `displayAxis * 2^-48`, only to absorb represented
floating-point drift at the 12- and 20-point boundaries.

- [ ] **Step 3: Run the registered tests and prove RED**

```bash
native/macos/scripts/run-tests.sh --filter CalibrationGeometry
```

Expected: compile failure because the new geometry types do not exist. A test that is
not registered or passes immediately is not accepted as RED.

- [ ] **Step 4: Implement the minimal pure geometry**

Keep all calculations normalized, but measure hit, minimum-size, and snap thresholds in
logical display points. Generate snap targets in this exact order: screen start, screen
end where legal, then peer bands in ascending index with peer start before peer end.
Replace the best candidate only when it is strictly closer outside the tolerance; this
preserves deterministic ties. Candidate legality is part-specific: body checks bounds
only, left/right check width only, and top/bottom check height only.

- [ ] **Step 5: Prove GREEN and keep the corrected oracle green**

```bash
native/macos/scripts/run-tests.sh --filter CalibrationGeometry
native/macos/scripts/run-tests.sh
lua tests/run.lua
```

Expected: the focused matrix passes, all native tests pass, and all 354 Lua oracle tests
still pass.

- [ ] **Step 6: Commit**

```bash
git add native/macos/Sources/ScreenFixCore/CalibrationGeometry.swift \
  native/macos/Tests/ScreenFixTests/CalibrationGeometryTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: add native calibration geometry"
```

### Task 2: Implement both mouse and trackpad interaction styles

**Files:**

- Create: `native/macos/Sources/ScreenFixCore/CalibrationInteraction.swift`
- Create: `native/macos/Tests/ScreenFixTests/CalibrationInteractionTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write one failing reducer test per pointer transition**

Define a pure reducer whose state owns the working-band copy and optional drag:

```swift
public enum CalibrationPointerEvent: Equatable {
    case primaryDown(PointD)
    case primaryDragged(PointD)
    case pointerMoved(PointD)
    case primaryUp(PointD)
}

public enum CalibrationEffect: Equatable {
    case none, redraw, saveRequested, cancelRequested
}

public struct CalibrationInteraction {
    public private(set) var workingBands: [NormalizedRect]
    public private(set) var isLatched: Bool
    public mutating func handle(
        _ event: CalibrationPointerEvent,
        displaySize: RectD,
        controls: CalibrationControlLayout
    ) -> CalibrationEffect
}
```

Cover these sequences independently:

1. primary down, move fewer than 4 Euclidean points, up: latch the selected body or
   edge without moving it;
2. primary down, cross exactly 4 points while held, drag, up: move/resize and release;
3. after latching, ordinary pointer movement moves/resizes without holding, and the next
   primary down clears the latch without selecting another target;
4. body plus every edge works through both sequences;
5. diagonal movement uses Euclidean distance;
6. empty-space down clears no unrelated state;
7. Save and Cancel activate immediately even when a move is latched;
8. an unsnapped `rawBand` is updated independently from the visible snapped band, so
   moving beyond 12 points releases the snap without sticky accumulation; and
9. a reducer error or rejected candidate preserves the previous bands and remains able
   to handle the next valid event exactly once.

The reducer uses local top-left coordinates. It receives no `NSEvent`, `NSWindow`, or
`NSScreen` value.

- [ ] **Step 2: Prove RED**

```bash
native/macos/scripts/run-tests.sh --filter CalibrationInteraction
```

Expected: compile failure for the missing interaction reducer.

- [ ] **Step 3: Implement the minimal state machine**

On initial hit, store the selected index/part, press point, last point, and a copy of the
visible band as `rawBand`. Ignore movement until squared distance is at least `4 * 4`.
For each accepted movement, apply the delta to `rawBand`, snap a copy for display, retain
the unsnapped value, update `lastPoint`, and request one redraw. A click-release without
movement sets `latched = true`; pointer moves are processed only while latched.

- [ ] **Step 4: Prove GREEN and commit**

```bash
native/macos/scripts/run-tests.sh --filter CalibrationInteraction
native/macos/scripts/run-tests.sh
git add native/macos/Sources/ScreenFixCore/CalibrationInteraction.swift \
  native/macos/Tests/ScreenFixTests/CalibrationInteractionTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: add native calibration pointer state"
```

### Task 3: Reproduce the approved editor layout and AppKit panel

**Files:**

- Create: `native/macos/Sources/ScreenFixCore/CalibrationLayout.swift`
- Create: `native/macos/Sources/ScreenFixApp/CalibrationPanel.swift`
- Create: `native/macos/Sources/ScreenFixApp/CalibrationView.swift`
- Create: `native/macos/Sources/ScreenFixApp/CalibrationPanelController.swift`
- Create: `native/macos/Tests/ScreenFixTests/CalibrationLayoutTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/CalibrationPanelTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing pure layout tests**

`CalibrationControlLayout.make(width:height:)` must reject displays below 260 by 180.
For ordinary displays assert exact frames:

```text
Save        x=24, y=height-66, w=104, h=42
Cancel      x=140, y=height-66, w=104, h=42
Instruction x=24, y=24,        w=330, h=42
Dot         x=40, y=41,        w=8,   h=8
Text        x=58, y=24,        w=280, h=42, font=15
```

Button width is `min(104, floor((width - 48 - 12) / 2))`. Below 378 points wide, the
instruction width is `width - 48`, height 58, font 13, its dot is vertically centered,
and its text width is `instruction.width - 50`. Verify all controls stay inside the
canvas and never overlap.

- [ ] **Step 2: Prove layout RED, implement it, and prove GREEN**

```bash
native/macos/scripts/run-tests.sh --filter CalibrationLayout
```

Expected RED: the layout type is missing. Implement it in core, then rerun the focused
test and the full suite before continuing.

- [ ] **Step 3: Write failing panel ownership and property tests**

Introduce a narrow `CalibrationSurface` protocol and injected factory so most tests do
not show windows. Assert:

- a candidate editor is completely configured and ordered before an old editor closes;
- construction, rendering, ordering, visibility, tracking-area, or commit-guard failure
  closes only the candidate and preserves the active editor;
- a prepared editor is single-use;
- stop clears callbacks and interaction state before closing the panel and is idempotent;
- callbacks from a retired generation cannot Save, Cancel, redraw, or mutate bands;
- a panel frame exactly equals a selected screen's full frame, including a negative
  global origin, and `constrainFrameRect` does not move it into `visibleFrame`;
- the editor panel is borderless and nonactivating, stays above committed mask panels,
  joins all Spaces, is full-screen auxiliary, never appears in the window cycle, and
  has no shadow;
- the editor accepts primary pointer events without activating another application;
- the content view is flipped so `(0, 0)` is the selected display's visual top-left;
- `acceptsFirstMouse(for:)` returns true so the first primary press edits instead of
  merely activating ScreenFix;
- the window sets `acceptsMouseMovedEvents = true`; and
- `updateTrackingAreas()` replaces one `.mouseMoved + .activeAlways + .inVisibleRect`
  tracking area rather than accumulating them.

- [ ] **Step 4: Prove panel RED**

```bash
native/macos/scripts/run-tests.sh --filter CalibrationPanel
```

Expected: compile failure for the missing panel, view, and controller types.

- [ ] **Step 5: Implement the visual adapter**

Draw directly in `CalibrationView.draw(_:)` using these exact values:

```text
band fill       RGB 0.95, 0.12, 0.08, alpha 0.45
band stroke     RGB 1.00, 0.55, 0.15, alpha 1.00, width 3
handles         white, 8 points thick
Save            RGB 22/255, 163/255, 74/255, radius 9
Cancel          RGB 53/255, 58/255, 66/255, radius 9
instruction     black alpha 0.88, white stroke alpha 0.28, radius 10
instruction dot RGB 1.00, 100/255, 59/255, radius 4
instruction     "Drag red bands or white edges"
```

Use system semibold text, antialiasing, and measured glyph bounds to optically center
the Save/Cancel labels inside their pills. Do not recreate the earlier baseline-offset
bug with fixed text origins. Draw controls after bands and handles so they remain usable
where geometry overlaps them.

Override `mouseDown`, `mouseDragged`, `mouseMoved`, and `mouseUp`; do not call `super`
after handling. Convert `event.locationInWindow` into view coordinates and forward only
primary-button events to the reducer. A normal mouse and a built-in/external trackpad
must use the same path; no Shift key, right click, global event tap, or pressure API is
required.

- [ ] **Step 6: Prove GREEN and commit**

```bash
native/macos/scripts/run-tests.sh --filter CalibrationLayout
native/macos/scripts/run-tests.sh --filter CalibrationPanel
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
git add native/macos/Sources/ScreenFixCore/CalibrationLayout.swift \
  native/macos/Sources/ScreenFixApp/CalibrationPanel.swift \
  native/macos/Sources/ScreenFixApp/CalibrationView.swift \
  native/macos/Sources/ScreenFixApp/CalibrationPanelController.swift \
  native/macos/Tests/ScreenFixTests/CalibrationLayoutTests.swift \
  native/macos/Tests/ScreenFixTests/CalibrationPanelTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: add native calibration editor"
```

### Task 4: Integrate Calibrate, provisional monitor selection, Save, and Cancel

**Files:**

- Modify: `native/macos/Sources/ScreenFixCore/Models.swift`
- Modify: `native/macos/Sources/ScreenFixApp/RuntimeController.swift`
- Modify: `native/macos/Sources/ScreenFixApp/MenuBarController.swift`
- Modify: `native/macos/Sources/ScreenFixApp/AppDelegate.swift`
- Modify: `native/macos/Tests/ScreenFixTests/MenuStateTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/MenuModelTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/RuntimeCalibrationTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing menu tests**

Add `calibrating` and `calibrateEnabled` to the runtime/menu snapshot. Assert the exact
ordered identifiers:

```text
paused-status?; enabled-action; calibrate; select-monitor; reset-defaults;
reload; separator; quit
```

`Calibrate` is disabled without a saved connected display, enabled for a connected
saved display even when protection is disabled, and checked only while editing. Assert
that no identifier or title contains `phase`, `coming soon`, or `unavailable`.

- [ ] **Step 2: Write failing runtime calibration transactions**

Inject a `RuntimeCalibrationOwner` protocol. Use one event log and test:

- `toggleCalibration()` starts exactly one editor from a fresh live screen and a copy
  of the saved bands while keeping the three committed black masks;
- toggling again calls Cancel: revoke the session first, close the editor, keep config
  unchanged, and reconcile normal masks;
- Calibrate works for disabled saved configuration by temporarily showing masks under
  the editor; Save preserves `enabled = false` and then removes masks;
- Save validates three bands, prepares/orders replacement masks, saves configuration in
  `beforeRetire`, commits new masks, then closes the editor;
- save or candidate-mask failure keeps the editor, old config, old masks, and working
  bands live and reports one actionable error;
- Cancel never calls save and discards every working change;
- stale Save/Cancel callbacks after Cancel, stop, Reload, Reset, Disable, Select Monitor,
  or a replacement editor are exact no-ops;
- editor construction failure preserves the prior runtime and menu state;
- selecting a monitor creates enabled exact defaults as a provisional target and opens
  calibration without saving first;
- provisional selection first transactionally shows the target's three default masks,
  then orders the editor above them; editor startup failure restores the prior masks
  (or no masks on first run) and never saves;
- first-run Cancel returns to no config/no masks; replacement-monitor Cancel restores
  the prior config and masks;
- first-run or replacement-monitor Save persists only the chosen display and edited
  bands; and
- a selected submenu row that vanishes before resolution is the existing exact no-op.

Do not update `configuration` or retire the old editor/masks until the complete Save
transaction succeeds. Every closure captures both runtime generation and calibration
session token.

- [ ] **Step 3: Prove menu/runtime RED**

```bash
native/macos/scripts/run-tests.sh --filter Menu
native/macos/scripts/run-tests.sh --filter RuntimeCalibration
```

Expected: failures for the absent action/state/session integration.

- [ ] **Step 4: Implement the runtime session**

Keep one private session value containing token, target configuration, screen UUID, and
captured full frame. `selectDisplay(stableId:)` now resolves a fresh screen, constructs
provisional enabled defaults, and starts calibration. It must not persist or replace the
committed configuration until Save. Stage the provisional mask set first, then the
editor; retain enough prior state to transactionally restore the old mask set when
editor construction or Cancel occurs. A failure at either stage must never leave masks
on the wrong display.

For ordinary `toggleCalibration`, copy the current configuration. While calibrating,
the displayed masks use the provisional target, but the committed configuration remains
unchanged. Cancel invalidates the token before editor teardown, then reconciles the
committed configuration. Save performs the mask/config transaction first and invalidates
the session only after success.

Reset while editing cancels the working copy before applying fresh permanent defaults.
Disable/Enable, Reload, selecting another monitor, stop, and Quit invalidate calibration
before their existing work. Preserve the current proven Disable-save-failure behavior.

- [ ] **Step 5: Wire the real menu and dependency graph**

`MenuBarController` maps identifier `calibrate` to `runtime.toggleCalibration()`.
`AppDelegate` constructs one `CalibrationPanelController` and injects it into the
runtime. Menu targets never create windows or write configuration themselves.

- [ ] **Step 6: Prove GREEN and commit**

```bash
native/macos/scripts/run-tests.sh --filter Menu
native/macos/scripts/run-tests.sh --filter RuntimeCalibration
native/macos/scripts/run-tests.sh
git add native/macos/Sources native/macos/Tests
git commit -m "feat: integrate native calibration"
```

### Task 5: Make topology, wake, and teardown transaction-safe

**Files:**

- Modify: `native/macos/Sources/ScreenFixApp/RuntimeController.swift`
- Modify: `native/macos/Sources/ScreenFixApp/CalibrationPanelController.swift`
- Modify: `native/macos/Tests/ScreenFixTests/RuntimeCalibrationTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/CalibrationPanelTests.swift`

- [ ] **Step 1: Write failing lifecycle tests one at a time**

Cover the exact golden behavior:

- an identical UUID and identical full frame but replacement `NSScreen` instance keeps
  the active editor and merely refreshes the live screen binding;
- display origin, width, or height change cancels editing, discards unsaved bands, and
  rebuilds normal masks using the saved config on the new full frame;
- disconnect cancels editing before removing masks; reconnect restores saved masks but
  never resurrects the unsaved editor;
- wake follows the same rules as a screen-parameter change;
- missing, non-finite, or too-small full frames fail before editor allocation;
- an old editor callback cannot mutate after topology cancellation;
- notification, Save, and Cancel reentrancy cannot retire a newer editor;
- stop revokes notification callbacks, then calibration callbacks/tracking, then closes
  editor and masks; a second stop is inert; and
- Quit leaves no editor, mask, tracking area, or menu item.

- [ ] **Step 2: Prove RED**

```bash
native/macos/scripts/run-tests.sh --filter RuntimeCalibration
native/macos/scripts/run-tests.sh --filter CalibrationPanel
```

Expected: the new topology/reentrancy cases fail for the intended missing guards.

- [ ] **Step 3: Implement generation-checked reconciliation**

On every display/wake reconcile, resolve by UUID from a new `NSScreen.screens` snapshot.
Compare captured and current full frames exactly after validating finiteness and positive
size. Never clamp a negative origin. Increment the session generation before calling
external teardown, and check the generation after every factory, save, ordering, and
callback boundary.

- [ ] **Step 4: Prove GREEN and commit**

```bash
native/macos/scripts/run-tests.sh --filter RuntimeCalibration
native/macos/scripts/run-tests.sh --filter CalibrationPanel
native/macos/scripts/run-tests.sh
git add native/macos/Sources/ScreenFixApp native/macos/Tests/ScreenFixTests
git commit -m "fix: harden native calibration lifecycle"
```

### Task 6: Package and physically validate the calibrated app

**Files:**

- Modify: `README.md`
- Modify: `native/macos/README.md`
- Modify only if an assertion is missing: `native/macos/scripts/package-arm64.sh`

- [ ] **Step 1: Update concise documentation**

Remove the claim that native calibration is unavailable. Explain that Calibrate edits a
copy, Save persists it, Cancel or selecting checked Calibrate discards it, and normal
mouse/trackpad use requires no modifier key. Keep Accessibility window movement listed
as the remaining native limitation until the subsequent guard plan lands. Remove all
user-facing `Phase 1`, `Phase 2`, `phase one`, and `phase two` terminology from both
READMEs; describe available behavior and remaining limitations directly.

- [ ] **Step 2: Run all automated release gates**

```bash
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
native/macos/scripts/package-arm64.sh
lua tests/run.lua
codesign --verify --strict --verbose=2 native/macos/artifacts/ScreenFix.app
test "$(lipo -archs native/macos/artifacts/ScreenFix.app/Contents/MacOS/ScreenFix)" = arm64
vtool -show-build native/macos/artifacts/ScreenFix.app/Contents/MacOS/ScreenFix | grep -q 'minos 13.0'
unzip -t native/macos/artifacts/ScreenFix-macos-arm64.zip
LC_ALL=C shasum -a 256 native/macos/artifacts/ScreenFix-macos-arm64.zip
LC_ALL=C shasum -a 256 native/macos/artifacts/ScreenFix.app/Contents/MacOS/ScreenFix
! rg -n -i 'phase[[:space:]]*[0-9]|phase one|phase two' README.md native/macos/README.md
git diff --check
git status --short --branch
```

Expected: all tests pass; package assertions, ad-hoc signature, thin arm64 architecture,
macOS 13 deployment target, ZIP integrity, README terminology check, and diff check all
pass. Record both printed SHA-256 values immediately; do not reuse a hash from an older
package invocation.

- [ ] **Step 3: Perform physical mouse and trackpad UAT without risking user config**

The UAT must use the exact ZIP produced and hashed in Step 2, not an older app in
`/Applications` and not an app left open from an earlier build. In the same shell, bind
the hashes and extract that artifact into a new uniquely named temporary directory:

```bash
ZIP_PATH="$PWD/native/macos/artifacts/ScreenFix-macos-arm64.zip"
APP_PATH="$PWD/native/macos/artifacts/ScreenFix.app"
ZIP_SHA256="$(LC_ALL=C shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
EXE_SHA256="$(LC_ALL=C shasum -a 256 "$APP_PATH/Contents/MacOS/ScreenFix" | awk '{print $1}')"
UAT_DIR="$(mktemp -d "${TMPDIR%/}/screenfix-uat.XXXXXX")"
ditto -x -k "$ZIP_PATH" "$UAT_DIR"
test "$(LC_ALL=C shasum -a 256 "$UAT_DIR/ScreenFix.app/Contents/MacOS/ScreenFix" | awk '{print $1}')" = "$EXE_SHA256"
open "$UAT_DIR/ScreenFix.app"
printf 'UAT_ZIP_SHA256=%s\nUAT_EXE_SHA256=%s\nUAT_APP=%s\n' \
  "$ZIP_SHA256" "$EXE_SHA256" "$UAT_DIR/ScreenFix.app"
```

Quit every older ScreenFix process before `open`. If
`~/Library/Application Support/ScreenFix/config.json` exists, move it to a uniquely
named backup without overwriting anything; restore it only after quitting the UAT app.
Then verify on the Apple Silicon Mac:

1. first-run Select Monitor opens the editor without persisting before Save;
2. Save/Cancel and instruction pills match the approved positions and optical centering;
3. a mouse can held-drag every band body and all four white edges;
4. a trackpad can held-drag, and tap-release/move/tap works for every body and edge;
5. no Shift key, alternate click, long press, or Hammerspoon process is required;
6. movement begins at 4 points, sizes never fall below 20 points, and every edge clamps;
7. screen and peer snaps engage through 12 points, align to a clean seam, and release
   after moving beyond the threshold;
8. the editor and masks align on a negative-origin external monitor;
9. Cancel and checked-Calibrate discard edits; Save survives app relaunch;
10. Reset cancels an edit and restores exact 1215-to-1920 defaults;
11. disconnect or display-layout change cancels unsaved editing without orphan panels;
12. repeated Reload/Enable/Disable/Calibrate never duplicates panels or menu items; and
13. clicks reach ordinary apps through masks after exiting calibration.

After UAT, quit the extracted app, recompute both hashes, and require them to equal the
bound values:

```bash
test "$(LC_ALL=C shasum -a 256 "$ZIP_PATH" | awk '{print $1}')" = "$ZIP_SHA256"
test "$(LC_ALL=C shasum -a 256 "$UAT_DIR/ScreenFix.app/Contents/MacOS/ScreenFix" | awk '{print $1}')" = "$EXE_SHA256"
printf 'VERIFIED_ZIP_SHA256=%s\nVERIFIED_EXE_SHA256=%s\n' "$ZIP_SHA256" "$EXE_SHA256"
```

Record the temporary app/config paths and restore the original config byte-for-byte.
Do not delete or overwrite an unknown live configuration. Leave the uniquely named UAT
directory in place until the hashes and result are recorded; cleanup is a separate,
explicitly targeted action.

- [ ] **Step 4: Commit docs or any narrowly required package assertion**

```bash
git add README.md native/macos/README.md native/macos/scripts/package-arm64.sh
git commit -m "docs: explain native calibration"
```

Do not commit `native/macos/artifacts/`, `.build/`, user configuration, screenshots, or
UAT backups.

## Completion gate

This slice is complete only when all automated gates and physical mouse/trackpad UAT
pass. The handoff must report the exact ZIP and executable SHA-256 values from the final
package invocation and state that the ad-hoc ZIP hash is build-instance-specific because
its file timestamps are not normalized. The reported hashes must be the
`VERIFIED_ZIP_SHA256` and `VERIFIED_EXE_SHA256` values from the exact extracted artifact
used for physical UAT.
