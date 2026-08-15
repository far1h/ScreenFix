# ScreenFix Native Behavior Contract

Status: approved assumption for the Windows and native macOS packages

This contract is the cross-platform source of truth for native ScreenFix. Platform
adapters may use different operating-system APIs, but they must preserve the behavior
below unless a limitation is explicitly listed.

## Coordinate and configuration model

- Store band rectangles normalized to the selected display's full bounds, not its
  work area. Each rectangle is `{ x, y, w, h }` in the inclusive range `0...1`, with
  positive width and height and `x + w <= 1`, `y + h <= 1`.
- Use a top-left display-local coordinate system in the pure geometry core. Platform
  adapters convert AppKit's bottom-left coordinates at their boundary.
- Treat rectangles as half-open for intersection. Touching edges do not overlap.
- Preserve exactly three bands and schema version `1`. Reject non-finite values,
  unknown schema versions, missing display identity, and any band outside the display.
- Convert normalized coordinates using the live full display bounds, including
  negative global origins. Windows rounds final native pixel bounds with
  `MidpointRounding.AwayFromZero`; macOS may retain fractional `CGFloat` values.

The permanent defaults are exact expressions, not rounded decimal literals:

```text
left  = 1215 / 3440
right = 1920 / 3440
width = (1920 - 1215) / 3440

band 1: x=left, y=0.00, w=width, h=0.34
band 2: x=left, y=0.34, w=width, h=0.39
band 3: x=left, y=0.73, w=width, h=0.27
```

On a 3440 by 1440 display, every default band therefore starts at `x=1215`, ends at
`x=1920`, and the three bands cover the complete display height without a gap.
Selecting a monitor starts with these defaults. Reset to Defaults restores these exact
bands for the saved monitor while preserving its enabled state.

The JSON configuration has this logical shape on both platforms:

```json
{
  "schemaVersion": 1,
  "enabled": true,
  "display": {
    "stableId": "platform display identity",
    "name": "display name",
    "width": 3440,
    "height": 1440
  },
  "bands": [
    { "x": 0.35319767441860467, "y": 0.0, "w": 0.20494186046511628, "h": 0.34 },
    { "x": 0.35319767441860467, "y": 0.34, "w": 0.20494186046511628, "h": 0.39 },
    { "x": 0.35319767441860467, "y": 0.73, "w": 0.20494186046511628, "h": 0.27 }
  ]
}
```

The displayed decimals are illustrative serialization. Code constructs the defaults
from the exact divisions above.

## Display identity

- Remember one damaged display. Match its platform stable ID first.
- Windows derives the stable ID from the active display-config target device path and
  retains its friendly name and full pixel dimensions as diagnostics.
- macOS persists the UUID returned by `CGDisplayCreateUUIDFromDisplayID` and retains
  vendor, model, serial, name, and dimensions for diagnostics. The transient direct
  display ID is never the persisted identity.
- If the stable ID is unavailable, fall back only when exactly one connected display
  matches both saved name and saved dimensions. Never guess among multiple matches.
- A disconnect removes overlays and pauses correction. A later unambiguous reconnect
  rebuilds the mask from normalized coordinates.

## Mask behavior

- Render exactly three opaque black rectangles on the selected display.
- Normal masks do not activate the app and are click-through.
- Keep masks above ordinary application content and present across virtual desktops or
  Spaces. Use the platform's supported full-screen companion behavior where available.
- Build every replacement off to the side. Configure and show all three candidates
  before retiring the committed set. If any step fails, destroy only the candidates,
  keep the old visible set, pause the guard, and expose one degraded-state notice per
  failure episode.
- Disable immediately removes every mask and stops every correction subscription.

## Calibration

Calibration edits a copy. Save validates and persists all three bands, then restores
normal protection. Cancel discards the copy. Choosing the checked Calibrate menu item
again is also Cancel and immediately returns to normal protection.

Each band has an 8-point hit region on its left, right, top, and bottom edge and a
20-point minimum width and height. Edges take priority over the body; later rendered
bands take priority when bands overlap.

Both pointer styles are mandatory for a mouse and a trackpad:

1. **Held drag:** primary press on a band or edge, move at least 4 logical points, then
   release. Movement or resizing ends on release.
2. **Tap-move-tap:** primary press and release without crossing the 4-point threshold
   latches the selected body or edge. Pointer movement then moves or resizes it without
   holding. The next primary press ends the latch.

No Shift key or alternate mouse button is required. A body drag clamps the whole band
inside the display. An edge drag keeps the opposite edge fixed and enforces the minimum
size.

Visible movement snaps within 12 platform logical points:

- A body may snap either horizontal edge to the left or right display edge and either
  vertical edge to the top or bottom display edge.
- A body may snap any of its edges to any corresponding edge of another band.
- A resized edge may snap to its matching display boundary and to corresponding edges
  of another band.
- Screen edges are considered before peer edges. Lower band index wins an otherwise
  equal peer tie. A candidate strictly closer than the current candidate wins.
- Keep the unsnapped raw drag position internally, so moving beyond the threshold
  releases a snap instead of accumulating sticky drift.

The calibration canvas supports a minimum 260 by 180 logical points. Smaller displays
fail before editor allocation. Save and Cancel stay at the bottom-left; the instruction
stays at the top-left. Their exact visual geometry follows the approved calibration
controls specification.

## Window guard

Observe existing windows at startup and newly created, shown, moved, or resized windows
afterward. Debounce all correction requests by 150 milliseconds.

A window is eligible only when it is visible, not minimized, an ordinary movable app
window, not full-screen, on the selected display, and intersects at least one mask band.
Never inspect window contents. Platform-owned, ScreenFix-owned, tool, menu, desktop,
secure, and non-movable windows are excluded.

For an eligible window:

1. Clamp its height and vertical position to the display work area.
2. From mask bands overlapping that adjusted vertical range, let `leftBoundary` be the
   smallest band left edge and `rightBoundary` the largest band right edge.
3. Build a left candidate between the work area's left edge and `leftBoundary`, and a
   right candidate between `rightBoundary` and the work area's right edge.
4. Preserve width and height where they fit. Reduce only what is required.
5. Compare candidates by total absolute movement, then total size reduction, then a
   fixed left-before-right rank. Choose the lexicographically smaller tuple.
6. Apply without animation or activation.

Record a successful target for 250 milliseconds so ScreenFix ignores its own resulting
event when frames are within 1 native point. If an app refuses the target, suppress
retries for that window for one second. Failure for one window must not pause others.

## Menu and lifecycle

The Windows tray menu and macOS menu-bar menu expose the same order and state:

1. an optional disabled `Paused: ...` status row;
2. `Disable` when enabled or `Enable` when disabled, checked while enabled;
3. `Calibrate`, checked while editing;
4. `Select Monitor`;
5. `Reset to Defaults`;
6. `Reload`, which rereads configuration and transactionally reconciles the runtime;
7. a separator and `Quit`.

Reset is disabled if the saved display is disconnected. Calibrate is disabled until a
saved display is connected. Select Monitor is always available.

Only one ScreenFix process may own resources for a user session. Startup, Reload,
display changes, sleep/wake, permission changes, Enable, Disable, and Quit must be
idempotent. Teardown revokes callbacks first, then stops hooks and timers, then closes
editors and overlays, and finally releases tray/menu resources. Late callbacks carry a
session generation token and cannot affect a replacement or stopped session.

Masks remain available when window-control permission is missing. The menu reports that
only window correction is paused. Granting permission or reconnecting a display triggers
normal reconciliation without duplicating hooks, overlays, or tray items.

## Platform limitations

- Software cannot repair dead, leaking, or stuck pixels. It can only black out pixels
  that still respond and keep useful windows away from the damaged region.
- Windows x64 is the only initial Windows artifact. It is for ordinary Intel and AMD
  64-bit PCs, not Windows on ARM. ScreenFix intentionally runs without administrator
  rights, so Windows integrity isolation can prevent it from moving elevated windows.
  Correcting a maximized ordinary window restores it into a safe normal frame.
  It cannot draw on the UAC secure desktop and cannot guarantee precedence over
  exclusive full-screen games, protected video, or system-owned topmost surfaces.
- The native macOS artifact initially supports macOS 13 or later on Apple Silicon only.
  Accessibility permission is required to move or resize other apps' windows, but not
  to render the mask. Some sandboxed, protected, or custom windows may reject
  Accessibility writes. Native full-screen windows are left unchanged.
- Unsigned Windows downloads can show SmartScreen. An ad-hoc-signed macOS zip can require
  the user to choose Open once. Warning-free public distribution requires a Windows code
  signing certificate and an Apple Developer ID plus notarization; those credentials
  are release inputs, not repository secrets.
- ScreenFix does not detect damage from a photo, capture screens, read window contents,
  use the network, or send telemetry.
