# Native macOS Window Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete native macOS parity by keeping ordinary application windows out of the saved mask bands while preserving masks and calibration when Accessibility permission or an individual application is unavailable.

**Architecture:** Add pure display assignment, eligibility, and correction reducers to `ScreenFixCore`. Wrap the public macOS Accessibility C API behind small injectable adapters, own one `AXObserver` session per regular application, and route copied notifications to a generation-checked main-thread guard with per-window debounce, self-event suppression, and refusal cooldown. `RuntimeController` starts the guard only for a trusted, enabled, connected, non-calibrating session and continues rendering masks in every permission state.

**Tech Stack:** Swift 5.7 language mode, AppKit, ApplicationServices Accessibility, Core Graphics, Core Foundation run loops, Foundation timers, the existing direct test runner, `codesign`, and `ditto`

---

## Prerequisite and scope

Execute this plan only after every task in
`docs/superpowers/plans/2026-08-15-macos-native-calibration.md` is green and committed.
Read these sources first:

- `docs/screenfix-behavior-contract.md`
- `screenfix/geometry.lua` and its corrected-frame tests
- `screenfix/window_guard.lua` and `tests/window_guard_test.lua`
- the implemented native calibration/runtime files and tests

This plan uses only public, stable APIs available in the macOS 13 SDK. Context7 was
queried first but returned no matching Apple API pages, so the following current Apple
primary references and the installed SDK headers are authoritative:

- https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate
- https://developer.apple.com/documentation/applicationservices/axnotificationconstants_h
- https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition
- https://developer.apple.com/documentation/applicationservices/kaxpositionattribute
- https://developer.apple.com/documentation/applicationservices/axvaluetype
- https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications
- https://developer.apple.com/documentation/appkit/nsworkspace/didterminateapplicationnotification
- https://developer.apple.com/documentation/coregraphics/cgdisplaybounds(_:)

Do not use private `_AX` functions or an undocumented `AXFullScreen` attribute. Detect
native/borderless full-screen windows conservatively from their fresh frame matching a
live full display frame within one point. A false-negative correction is safer than
moving a potentially full-screen or special window.

No user-facing menu or README may contain development phase labels. While permission is
missing, show one disabled status row:

```text
Window correction paused: Allow Accessibility in System Settings
```

The black masks and Calibrate stay functional. Do not add a fake command, administrator
requirement, screen capture, telemetry, or content inspection.

## File structure

```text
native/macos/Sources/ScreenFixCore/
├── DisplayAssignment.swift          Assigns AX frames conservatively to displays.
├── WindowCorrection.swift           Pure safe-frame candidate selection.
└── WindowEligibility.swift          Pure ordinary-window exclusion rules.
native/macos/Sources/ScreenFixApp/
├── AccessibilityTrustController.swift  Prompt/check/change monitoring.
├── AXClient.swift                      Typed public AX reads and writes.
├── AXObserverRegistry.swift            Per-app observer/run-loop ownership.
├── WindowGuardController.swift         Debounce, correction, cooldown, teardown.
├── DisplayCatalog.swift                Adds top-left full/work frames.
├── RuntimeController.swift             Guard lifecycle integration.
└── AppDelegate.swift                   Constructs the native adapters.
native/macos/Tests/ScreenFixTests/
├── DisplayAssignmentTests.swift
├── WindowCorrectionTests.swift
├── WindowEligibilityTests.swift
├── AccessibilityTrustTests.swift
├── AXClientTests.swift
├── AXObserverRegistryTests.swift
├── WindowGuardTests.swift
└── RuntimeWindowGuardTests.swift
```

Register every new test array in `Tests/ScreenFixTests/Main.swift` in the same RED
commit. Keep `ScreenFixCore` free of AppKit, ApplicationServices, and Core Graphics.

### Task 1: Prove APIs and add top-left full/work display frames

**Files:**

- Modify: `native/macos/Sources/ScreenFixApp/DisplayCatalog.swift`
- Modify: `native/macos/Tests/ScreenFixTests/DisplayCatalogTests.swift`
- Modify: `native/macos/scripts/run-tests.sh`
- Modify: `native/macos/scripts/build-release.sh`

- [ ] **Step 1: Compile-probe the exact public Accessibility calls**

Create a temporary probe outside the repository with `mktemp`; import
`ApplicationServices` and type-check calls to:

```swift
AXIsProcessTrustedWithOptions
AXUIElementCreateApplication
AXUIElementCopyAttributeValue
AXUIElementIsAttributeSettable
AXUIElementSetAttributeValue
AXValueCreate
AXValueGetValue
AXObserverCreate
AXObserverAddNotification
AXObserverRemoveNotification
AXObserverGetRunLoopSource
```

Compile it with the existing target:

```bash
swiftc -target arm64-apple-macosx13.0 -swift-version 5 \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics \
  "$PROBE_PATH" -o "$PROBE_BINARY"
```

Also inspect the selected SDK's `AXUIElement.h`, `AXAttributeConstants.h`,
`AXRoleConstants.h`, and `AXNotificationConstants.h`. Expected: every API and constant
used by this plan exists without deprecation diagnostics. Delete only the exact
`mktemp` directory after recording the successful command.

- [ ] **Step 2: Write failing display-coordinate tests**

Extend `ConnectedScreen` with pure `topLeftFullFrame` and `topLeftVisibleFrame` values.
Inject a `CGDisplayBounds` provider into `DisplayCatalog`. Test:

- primary display full bounds begin at top-left `(0, 0)`;
- a display left, above, or below primary preserves its negative/positive Core Graphics
  origin;
- full frame comes from `CGDisplayBounds(directDisplayId)` rather than `visibleFrame`;
- visible work bounds use the AppKit insets between `screen.frame` and
  `screen.visibleFrame`, applied to the corresponding Core Graphics full bounds;
- a top menu-bar inset and bottom/side Dock inset map to the correct top-left edges;
- width/height remain logical points on Retina snapshots; and
- every provider is called from a fresh `connectedDisplays()` snapshot.

- [ ] **Step 3: Prove RED**

```bash
native/macos/scripts/run-tests.sh --filter DisplayCatalog
```

Expected: new assertions fail because top-left full/work frames and the bounds provider
do not exist.

- [ ] **Step 4: Implement the adapter and link ApplicationServices**

Use `CGDisplayBounds` because Apple defines its origin relative to the upper-left of the
main display, the same global system used by `kAXPositionAttribute`. Derive work bounds
only from local insets; never mix an AppKit global `y` directly with an AX global `y`.
Add `-framework ApplicationServices` to both direct compiler scripts.

- [ ] **Step 5: Prove GREEN and commit**

```bash
native/macos/scripts/run-tests.sh --filter DisplayCatalog
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
git add native/macos/Sources/ScreenFixApp/DisplayCatalog.swift \
  native/macos/Tests/ScreenFixTests/DisplayCatalogTests.swift \
  native/macos/scripts/run-tests.sh native/macos/scripts/build-release.sh
git commit -m "feat: add native accessibility display frames"
```

### Task 2: Port deterministic safe-window correction

**Files:**

- Create: `native/macos/Sources/ScreenFixCore/WindowCorrection.swift`
- Create: `native/macos/Tests/ScreenFixTests/WindowCorrectionTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing pure geometry tests**

Define:

```swift
public enum WindowCorrection {
    public static func target(
        window: RectD,
        workArea: RectD,
        masks: [RectD]
    ) -> RectD?

    public static func framesNear(_ lhs: RectD, _ rhs: RectD, tolerance: Double) -> Bool
}
```

Port every corrected-frame and frames-near oracle from `tests/geometry_test.lua`:

- no mask intersection returns `nil`;
- clamp height/y into the work area first;
- if that vertical clamp clears the masks, return the clamped frame;
- use every mask overlapping the adjusted vertical span;
- build left and right regions from the smallest mask left and largest mask right;
- preserve size where it fits and reduce only what is necessary;
- compare total absolute movement, then size reduction, then fixed left-before-right;
- support one missing safe side and return `nil` when neither has positive width;
- keep deterministic negative global coordinates; and
- accept at most one-point self-event drift.

Add non-finite, zero-size, and invalid-work-area tests that fail closed without producing
a target.

- [ ] **Step 2: Prove RED, implement, prove GREEN**

```bash
native/macos/scripts/run-tests.sh --filter WindowCorrection
```

Expected RED: missing type. Implement the minimal pure algorithm, then run the focused
and full native suites plus `lua tests/run.lua`.

- [ ] **Step 3: Commit**

```bash
git add native/macos/Sources/ScreenFixCore/WindowCorrection.swift \
  native/macos/Tests/ScreenFixTests/WindowCorrectionTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: add native window correction geometry"
```

### Task 3: Define conservative display assignment and eligibility

**Files:**

- Create: `native/macos/Sources/ScreenFixCore/DisplayAssignment.swift`
- Create: `native/macos/Sources/ScreenFixCore/WindowEligibility.swift`
- Create: `native/macos/Tests/ScreenFixTests/DisplayAssignmentTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/WindowEligibilityTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing display-assignment tests**

Assign a window to the display with the largest positive intersection area. Require a
unique winner: equal-area ties, zero overlap, missing stable IDs, invalid frames, and
ambiguous mirrored bounds return `nil`. Test displays at negative x/y origins and a
window spanning the selected and another display.

- [ ] **Step 2: Write failing pure eligibility tests**

Use an immutable `WindowFacts` containing owner PID, ScreenFix PID, owner regular/hidden
state, role, subrole, minimized state, frame, position/size settable flags, assigned
display ID, selected display ID, and live full display frames. An eligible window must:

- belong to another `.regular`, non-hidden, live application;
- have `kAXWindowRole` and `kAXStandardWindowSubrole`;
- be non-minimized;
- have finite positive position and size;
- allow both position and size writes;
- be uniquely assigned to the selected display; and
- not match any full display frame within one point.

Reject ScreenFix-owned, system-wide, desktop, menu, sheet, dialog, utility/floating,
unknown, non-movable, minimized, hidden, disconnected-display, full-screen, and malformed
windows independently. Missing or errored facts are ineligible, never guessed.

- [ ] **Step 3: Prove RED, implement, prove GREEN, and commit**

```bash
native/macos/scripts/run-tests.sh --filter DisplayAssignment
native/macos/scripts/run-tests.sh --filter WindowEligibility
```

After observing RED, implement only the tested reducers and run the full suite.

```bash
git add native/macos/Sources/ScreenFixCore/DisplayAssignment.swift \
  native/macos/Sources/ScreenFixCore/WindowEligibility.swift \
  native/macos/Tests/ScreenFixTests/DisplayAssignmentTests.swift \
  native/macos/Tests/ScreenFixTests/WindowEligibilityTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: classify native guard windows"
```

### Task 4: Add honest Accessibility permission state and UX

**Files:**

- Create: `native/macos/Sources/ScreenFixApp/AccessibilityTrustController.swift`
- Create: `native/macos/Tests/ScreenFixTests/AccessibilityTrustTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing trust lifecycle tests**

Inject trust check, prompt check, clock/scheduler, and state callback. Prove:

- `reconcile(needsPermission: false)` never prompts and idempotently stops trust
  polling, because disabled or disconnected ScreenFix has no guard permission need;
- the first enabled+connected guard request calls
  `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt = true` once per app
  run when untrusted;
- the asynchronous prompt return value is treated only as the current state;
- while permission is needed, later checks use prompt `false` and a two-second timer;
- false-to-true and true-to-false transitions invoke one state callback;
- unchanged checks do not rebuild runtime state;
- a superseded timer callback is inert;
- stop invalidates callbacks before cancelling the timer and is idempotent; and
- restart has a new generation and never accepts an old callback.

Do not call `tccutil`, edit the TCC database, loop prompts, or request permission when
the user has no enabled connected saved display.

- [ ] **Step 2: Prove RED**

```bash
native/macos/scripts/run-tests.sh --filter AccessibilityTrust
```

- [ ] **Step 3: Implement public trust checks**

Build the prompt dictionary with the SDK's imported
`kAXTrustedCheckOptionPrompt.takeUnretainedValue()` key and `kCFBooleanTrue`. Poll with
`AXIsProcessTrustedWithOptions(nil)`. Keep the timer on the main run loop; it is a state
monitor, not a window-event debounce.

- [ ] **Step 4: Prove GREEN and commit**

```bash
native/macos/scripts/run-tests.sh --filter AccessibilityTrust
native/macos/scripts/run-tests.sh
git add native/macos/Sources/ScreenFixApp/AccessibilityTrustController.swift \
  native/macos/Tests/ScreenFixTests/AccessibilityTrustTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: monitor native accessibility trust"
```

### Task 5: Wrap typed AX reads/writes and per-application observers

**Files:**

- Create: `native/macos/Sources/ScreenFixApp/AXClient.swift`
- Create: `native/macos/Sources/ScreenFixApp/AXObserverRegistry.swift`
- Create: `native/macos/Tests/ScreenFixTests/AXClientTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/AXObserverRegistryTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing typed AX-client tests**

Inject the C-call boundary and test typed reads for strings, booleans, arrays,
`CGPoint`, and `CGSize`; settable checks; and writes using `AXValueCreate` with
`.cgPoint`/`.cgSize`. Require exact `AXError.success`; type mismatch, absent value,
invalid element, `cannotComplete`, `apiDisabled`, and non-finite geometry become typed
failures without force casts or leaked unmanaged values.

Represent window identity with a retained wrapper whose equality uses `CFEqual` and
whose hash uses `CFHash`, paired with owner PID. Do not depend on private window IDs,
pointer addresses, titles, or array order.

- [ ] **Step 2: Prove AX client RED, implement, and prove GREEN**

```bash
native/macos/scripts/run-tests.sh --filter AXClient
```

- [ ] **Step 3: Write failing observer-registry ownership tests**

Inject running-app enumeration, workspace notifications, AX observer factory,
notification registration/removal, run-loop source attachment, and event sink. Test:

- startup enumerates current `.regular` apps, excluding ScreenFix and terminated apps;
- each PID gets at most one observer and application element;
- current `kAXWindowsAttribute` windows are emitted once for seeding;
- app-level window-created/focused-window notifications are registered;
- each current/new window registers moved, resized, minimized, deminiaturized, and
  destroyed notifications;
- `notificationUnsupported` for one notification is nonfatal, while an observer/source
  failure rolls back only that app;
- `NSWorkspace.didLaunchApplicationNotification` adds a regular app and terminate
  removes its observer/window registrations;
- activation or unhide rechecks the live application facts and reseeds its current
  `kAXWindowsAttribute` array, so a merely shown existing window is not missed;
- callbacks copy PID, retained element, notification, and generation before dispatching
  to the main queue;
- stale callbacks after app removal, stop, or restart are inert;
- stop revokes workspace callbacks, invalidates generation, removes run-loop sources and
  registrations, then releases observers; and
- repeated start/stop leaves no sources or duplicate registrations.

Subscribe to `NSWorkspace.didActivateApplicationNotification` and
`didUnhideApplicationNotification` as shown-window lifecycle hints in addition to
launch/termination; eligibility still comes from fresh AX/application facts, not from
the notification alone. Use one observer per application. Apple's AX docs require adding
`AXObserverGetRunLoopSource(observer)` to a run loop before notifications arrive; use
the main run loop common modes so menu tracking cannot indefinitely delay corrections.

- [ ] **Step 4: Prove observer RED, implement, and prove GREEN**

```bash
native/macos/scripts/run-tests.sh --filter AXObserverRegistry
native/macos/scripts/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add native/macos/Sources/ScreenFixApp/AXClient.swift \
  native/macos/Sources/ScreenFixApp/AXObserverRegistry.swift \
  native/macos/Tests/ScreenFixTests/AXClientTests.swift \
  native/macos/Tests/ScreenFixTests/AXObserverRegistryTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: observe native application windows"
```

### Task 6: Implement debounce, correction, self-suppression, and cooldown

**Files:**

- Create: `native/macos/Sources/ScreenFixApp/WindowGuardController.swift`
- Create: `native/macos/Tests/ScreenFixTests/WindowGuardTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing guard scheduling tests**

Inject observer registry, AX client, display snapshot provider, timer scheduler, and
monotonic clock. With one event log, prove:

- start seeds all existing windows through the same 150-millisecond debounce;
- created, focused, moved, resized, and deminiaturized events debounce per retained
  window identity;
- a newer event cancels/replaces the old timer and the old callback cannot clear it;
- destroyed/terminated windows cancel timers and clear state;
- scheduling failure retains no phantom pending entry;
- target display/mask updates cancel or supersede old pending timers, are idempotent,
  and do not duplicate observers;
- stop invalidates generation before cancelling timers and observers; and
- one app/window failure never stops correction for another.

- [ ] **Step 2: Write failing fresh-eligibility and write tests**

At timer fire, re-read every eligibility fact and frame. Assert:

- safe, excluded, disconnected, or no-longer-existing windows receive no write;
- an intersecting eligible window receives the pure target;
- size is written before position, then the actual position/size are read back;
- no animation or application activation API is called;
- a confirmed frame within one point records a recent target for exactly 250 ms;
- the resulting self-notification is consumed only when its fresh frame is within one
  point, and unrelated events are not suppressed;
- write error, missing post-write frame, or refused frame enters a one-second cooldown;
- events during cooldown do not write; a later event after expiry may retry;
- expired recent/cooldown state is pruned before a reused identity is evaluated; and
- `kAXErrorAPIDisabled` reports lost permission to runtime while preserving masks.

Do not retry immediately inside one correction. Some apps enforce minimum sizes or
reject writes; that is a per-window refusal, not a global guard failure.

- [ ] **Step 3: Prove RED**

```bash
native/macos/scripts/run-tests.sh --filter WindowGuard
```

- [ ] **Step 4: Implement the main-thread guard**

Keep `pending`, `recentTargets`, and `blockedUntil` dictionaries private. A successful
write sequence is:

1. read fresh facts/frame/work area/masks;
2. compute the pure target;
3. write size, then position;
4. read actual position and size;
5. accept only when all four fields are within one point; and
6. record the confirmed target with `now + 0.25`.

Every timer and observer callback checks the session generation before and after
external AX calls. Never retain an `NSScreen` or work area across display reconciliation.

- [ ] **Step 5: Prove GREEN and commit**

```bash
native/macos/scripts/run-tests.sh --filter WindowGuard
native/macos/scripts/run-tests.sh
git add native/macos/Sources/ScreenFixApp/WindowGuardController.swift \
  native/macos/Tests/ScreenFixTests/WindowGuardTests.swift \
  native/macos/Tests/ScreenFixTests/Main.swift
git commit -m "feat: correct native application windows"
```

### Task 7: Integrate guard state with masks, calibration, and lifecycle

**Files:**

- Modify: `native/macos/Sources/ScreenFixCore/Models.swift`
- Modify: `native/macos/Sources/ScreenFixApp/RuntimeController.swift`
- Modify: `native/macos/Sources/ScreenFixApp/AppDelegate.swift`
- Modify: `native/macos/Tests/ScreenFixTests/MenuStateTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/MenuModelTests.swift`
- Create: `native/macos/Tests/ScreenFixTests/RuntimeWindowGuardTests.swift`
- Modify: `native/macos/Tests/ScreenFixTests/Main.swift`

- [ ] **Step 1: Write failing menu-state tests**

When enabled+connected but untrusted, assert the single disabled permission status row
appears while Disable, Calibrate, Select Monitor, Reset, Reload, and Quit retain their
normal enabled/checked state. Permission status clears automatically after trust. Config,
mask, and disconnect errors take priority over permission guidance. Assert no menu title
contains a development phase label.

- [ ] **Step 2: Write failing runtime integration tests**

Inject trust and guard owners and cover:

- startup always renders masks first, then starts the guard only when enabled,
  connected, trusted, and not calibrating;
- untrusted startup keeps masks/editor usable, shows permission guidance, prompts only
  when permission is needed, and has no AX observers;
- trust grant callback starts one guard without Reload; trust loss stops it without
  removing masks;
- Calibrate stops observers/timers before opening the editor; Save/Cancel restores one
  guard only after normal masks reconcile;
- Disable invalidates/stops guard before removing masks and saving; a failed Disable save
  retains enabled config/masks and safely rebuilds one guard;
- display disconnect, topology change, and wake revoke guard callbacks before masks;
- reconnect resolves fresh top-left full/work frames and starts one new generation;
- Reload with invalid config preserves prior masks/guard; valid config replacement
  commits masks before swapping the guard target;
- mask replacement failure preserves old guard target and masks;
- stale trust, observer, timer, calibration, wake, and display callbacks cannot affect a
  stopped or replacement session;
- Quit teardown order is runtime callbacks, trust timer, AX observers, debounce timers,
  calibration editor, masks, menu; and
- every start/reload/enable/disable/calibrate/wake cycle remains idempotent.

- [ ] **Step 3: Prove RED**

```bash
native/macos/scripts/run-tests.sh --filter Menu
native/macos/scripts/run-tests.sh --filter RuntimeWindowGuard
```

- [ ] **Step 4: Implement one runtime reconciliation path**

Derive guard eligibility from the same immutable snapshot used to build menu state.
Compute absolute masks with `ConnectedScreen.topLeftFullFrame` and work area from
`topLeftVisibleFrame`. Start/retarget the guard only after committed masks are known
visible. Permission and individual-window failures never set the mask runtime error.

- [ ] **Step 5: Construct production adapters and prove GREEN**

`AppDelegate` creates exactly one trust controller, AX client, observer registry, and
window guard. No global singleton may outlive runtime stop.

```bash
native/macos/scripts/run-tests.sh --filter RuntimeWindowGuard
native/macos/scripts/run-tests.sh
native/macos/scripts/build-release.sh
git add native/macos/Sources native/macos/Tests
git commit -m "feat: integrate native window guard"
```

### Task 8: Package, document, and physically validate full parity

**Files:**

- Modify: `README.md`
- Modify: `native/macos/README.md`
- Modify if required for a missing gate: `native/macos/scripts/package-arm64.sh`

- [ ] **Step 1: Update concise user/developer documentation**

Describe masks, calibration, and automatic safe-window placement as available. Explain
the Accessibility prompt, the permission status row, System Settings grant, automatic
permission recheck, ad-hoc signing warning, macOS 13+ Apple Silicon limit, and protected/
custom/full-screen window limitations. Remove obsolete development-phase wording and
keep collaborator build/test commands.

- [ ] **Step 2: Run complete automated release verification**

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

Record the hashes from this exact package invocation.

- [ ] **Step 3: Perform permission UAT from the freshly hashed ZIP**

Use the same non-destructive process/config backup and exact-ZIP extraction sequence in
the calibration plan. Quit and verify no older ScreenFix process, back up the live config
with its SHA-256 before launch, extract the just-hashed ZIP to a new `mktemp` directory,
verify the extracted executable hash, and open only that extracted app.

With throwaway TextEdit documents/windows containing no unsaved user work, verify:

1. masks and Calibrate work before Accessibility permission is granted;
2. permission guidance appears only when correction is needed and the system prompt is
   not repeated;
3. granting ScreenFix in Privacy & Security starts correction without Reload;
4. an existing ordinary window intersecting a band is seeded and corrected after 150 ms;
5. new, shown, moved, and resized ordinary windows correct to the deterministic nearest
   safe side;
6. safe windows do not move and corrected windows do not jitter from self-events;
7. hidden, minimized, dialog/tool, ScreenFix-owned, other-display, and native/borderless
   full-screen windows remain unchanged;
8. if a safe throwaway ordinary app that rejects AX writes is available, its refusal
   does not block other apps and it retries only after one second; otherwise record
   "not physically observed" and cite the injected refusal/cooldown test result;
9. calibration pauses correction, retains masks, and Save/Cancel restores it once;
10. Disable removes masks and observers; Enable restores both;
11. disconnect/reconnect, display-layout change, wake, Reload, and repeated app launch do
    not duplicate masks, observers, timers, or menu items; and
12. Quit removes every owned panel, observer, timer, and status item.

Do not automate TCC database changes or test on windows containing valuable unsaved
work. Ad-hoc rebuilds may require removing/regranting the specific extracted app in
System Settings; record this as a development-signing limitation, not an app defect.

- [ ] **Step 4: Restore user state and bind the final handoff to UAT bytes**

Use the calibration plan's exact sequence: menu-Quit and verify no process, move any
test-created config to a unique non-overwriting path, restore the original config, prove
its SHA-256 matches, and recompute the ZIP/extracted executable hashes. Report only the
hashes verified after physical UAT. Leave temporary files until results are recorded.

- [ ] **Step 5: Commit documentation or a narrowly required package gate**

```bash
git add README.md native/macos/README.md native/macos/scripts/package-arm64.sh
git commit -m "docs: explain native window correction"
```

## Completion gate

Do not call native macOS parity complete until the full Swift/Lua suites, arm64/macOS 13
package assertions, Accessibility permission transitions, exact extracted-ZIP physical
UAT, and user-config restoration checks all pass. The final report must state the
build-instance-specific ZIP SHA-256, stable executable SHA-256, ad-hoc/not-notarized
status, and any applications observed to reject AX writes.
