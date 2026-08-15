# ScreenFix Hammerspoon Script Design

Status: approved

## Problem

The selected external ultrawide display has a vertically damaged center area. Content remains usable on the left and right, but ordinary windows can extend behind the damage. The user needs a simple macOS 13 Ventura solution that blacks out responsive pixels in the damaged area and keeps normal windows out of it.

Software cannot change physically dead, leaking, or stuck LCD pixels. The mask only turns responsive pixels black and prevents useful content from being placed behind the damaged region.

## Goals

- Run as a Hammerspoon Lua configuration rather than a standalone app.
- Start when Hammerspoon launches at login.
- Apply only to one remembered damaged monitor.
- Render a three-rectangle stepped black mask across all Spaces and full-screen apps.
- Let the user calibrate those rectangles directly on the display.
- Move or resize only normal windows that overlap the mask.
- Leave safe and full-screen windows unchanged.
- Support macOS 13 Ventura with the current stable Hammerspoon APIs.

## Non-goals

- Repairing the LCD hardware or controlling pixels that no longer respond.
- Tiling every open window into a grid.
- Replacing macOS Spaces or native full-screen behavior.
- Automatically detecting damage from a photograph.
- Managing windows on healthy displays.

## User experience

### First run

1. Hammerspoon requests Accessibility permission if it is not already trusted.
2. ScreenFix shows the connected displays and the user selects the damaged one.
3. Three black mask rectangles appear in calibration mode with visible resize and move handles.
4. The user drags the rectangles over the damaged top, middle, and lower regions.
5. Saving stores the selected display and normalized rectangle coordinates.
6. ScreenFix switches the mask to black, click-through normal mode and starts the window guard.

### Normal operation

A small Hammerspoon menu contains Enable/Disable, Calibrate, Select Monitor, and Reload. The mask is otherwise passive. When a normal window is created, shown, moved, or resized across the mask, ScreenFix selects a safe side using the documented nearest-side-first ordering.

The user enables Hammerspoon's Launch at login preference. No additional daemon, installer, network service, or account is required.

## Architecture

`init.lua` is the entry point. It loads the modules, owns the menu, and ensures an old configuration is stopped cleanly during Hammerspoon reloads.

| Module | Responsibility |
| --- | --- |
| `screenfix/screen_config.lua` | Load, validate, and save settings; find the selected display; observe display changes. |
| `screenfix/controller.lua` | Reconcile masks, correction, calibration, menus, and owned watcher lifecycles. |
| `screenfix/mask_overlay.lua` | Create, update, show, hide, and delete the three `hs.canvas` mask rectangles. |
| `screenfix/window_guard.lua` | Subscribe to `hs.window.filter` events and correct only overlapping windows. |
| `screenfix/calibration.lua` | Present direct manipulation handles, select a display, and commit or cancel edits. |
| `screenfix/geometry.lua` | Provide pure rectangle conversion, intersection, and safe-frame calculations. |

The implementation uses Hammerspoon's documented [`hs.canvas`](https://www.hammerspoon.org/docs/hs.canvas.html), [`hs.window.filter`](https://www.hammerspoon.org/docs/hs.window.filter.html), [`hs.screen`](https://www.hammerspoon.org/docs/hs.screen.html), [`hs.caffeinate.watcher`](https://www.hammerspoon.org/docs/hs.caffeinate.watcher.html), and [`hs.settings`](https://www.hammerspoon.org/docs/hs.settings.html) APIs.

## Saved configuration

`hs.settings` stores one versioned table:

```lua
{
  schemaVersion = 1,
  enabled = true,
  screen = {
    uuid = "display UUID",
    name = "fallback display name",
    width = 3440,
    height = 1440,
  },
  bands = {
    { x = 0.43, y = 0.00, w = 0.16, h = 0.34 },
    { x = 0.46, y = 0.34, w = 0.11, h = 0.39 },
    { x = 0.48, y = 0.73, w = 0.07, h = 0.27 },
  },
}
```

Band coordinates are normalized to the selected screen's `fullFrame()`. This keeps the mask aligned when the display origin or scale changes. The display UUID is the primary identity; name and resolution are a conservative fallback for reconnect cases in which the UUID is unavailable.

## Mask behavior

Each band is an opaque black `hs.canvas`. Normal mode exposes no mouse-tracked elements, so pointer input passes through to the underlying application. The canvases use the Hammerspoon window behaviors needed to join all Spaces and accompany full-screen Spaces. Their level must keep the mask above application content without hiding calibration controls.

Mask replacement is transactional: ScreenFix constructs and configures every replacement canvas before deleting the committed set. A construction or configuration failure deletes only partial replacements, keeps the prior visible mask unchanged, pauses window correction, and reports one notification per failure episode. The menu shows `Paused: Mask rendering failed` until rendering succeeds or the mask is disabled or disconnected.

Calibration mode draws each editable band with a translucent red fill, bright orange-red outline, and high-contrast white handles above the persistent black mask. A noninteractive `Drag red bands or white edges` instruction identifies the targets without covering Save or Cancel. Only the transparent full-canvas background tracks input; every visual element remains untracked so pointer events reach that background. The editor canvas uses the `assistiveTechHigh` window level so controls remain above normal `screenSaver` mask canvases even when topology reconciliation rebuilds them. The level is configured transactionally before input callbacks and display; a construction or level failure preserves the committed editor. Save validates that all bands have positive size and remain within the selected screen. Cancel restores the last saved configuration.

## Window correction

The window guard listens for created, moved or resized, and newly visible window events. Subscription immediately includes already-allowed windows, so startup does not wait for a later event to protect them. All callbacks use the same debounce to avoid repeated corrections while macOS and an application are still updating a frame.

A window is eligible only when it:

- is visible and not minimized;
- is a normal, movable application window;
- is not full screen;
- is on the selected damaged display; and
- intersects at least one absolute mask rectangle.

For an eligible window, the geometry module builds left and right candidates from the bands that overlap the window's vertical range. A left candidate ends at the leftmost relevant band edge. A right candidate begins at the rightmost relevant band edge. Both candidates are clamped to the display's usable `frame()`, which excludes the menu bar and Dock.

Each candidate first preserves the window's current width and height. If it cannot fit, only the required dimension is reduced. ScreenFix selects between candidates by comparing this tuple in order: total horizontal and vertical movement, total width and height reduction, then side rank with left before right. This nearest-side-first ordering follows live user feedback: a window dragged toward one side must stay on that side, shrinking only as needed, instead of being forced across the mask to preserve its size. Reduction resolves equal movement costs, and the fixed side rank resolves an otherwise exact tie.

ScreenFix applies the chosen candidate with no animation and records a short per-window cooldown. The cooldown and a frame tolerance prevent ScreenFix from reacting to its own `setFrame` event.

If an application refuses the requested frame, ScreenFix leaves it alone and suppresses immediate retries. Other windows remain protected.

## Display and permission changes

An `hs.screen.watcher` reacts to connection, disconnection, arrangement, and scaling changes. An owned `hs.caffeinate.watcher` performs the same reconciliation after `systemDidWake` and `screensDidWake`; unrelated power events are ignored. Both watcher lifecycles are mandatory, error-contained, and reload-safe.

- When the selected display disappears, ScreenFix deletes the mask canvases, pauses correction, and shows one notification.
- When it returns, ScreenFix resolves the saved identity, rebuilds the mask from normalized coordinates, and resumes correction.
- If no saved display matches, ScreenFix remains paused and offers Select Monitor. It never guesses when multiple displays are present.
- Without Accessibility permission, mask rendering remains available but window correction stays paused. The menu indicates the condition and provides instructions for System Settings.
- Invalid or unsupported saved settings are not applied. ScreenFix preserves them for diagnosis and opens calibration with safe defaults.

## Privacy and safety

ScreenFix runs locally. It does not capture the screen, inspect window contents, use the network, or write outside Hammerspoon settings. It observes window metadata needed for geometry only. Disable immediately removes the overlays and stops window subscriptions.

## Verification

Pure geometry tests use a small assertion runner without an external Lua test framework. Cases cover:

- no intersection;
- top, middle, and lower band intersections;
- a tall window intersecting all bands;
- left and right selection using the nearest-side-first ordering;
- a nearer candidate that requires shrinking beating a farther candidate that preserves size;
- deterministic left-side selection when movement and resize costs are identical;
- oversized windows that require shrinking;
- negative display origins in multi-monitor arrangements;
- display scale and origin changes; and
- cooldown frame tolerance.

Manual verification on macOS 13 Ventura covers:

- first-run permission flow;
- direct calibration, Save, and Cancel;
- Hammerspoon reload and login restoration;
- monitor disconnect and reconnect;
- display scaling and arrangement changes;
- window creation, dragging wide windows left and right, and confirming each stays on the nearest safe side even when that side requires shrinking;
- full-screen windows and multiple Spaces;
- minimized, system, and non-movable windows; and
- disabling and re-enabling from the menu.

## Acceptance criteria

- Three saved black rectangles cover the damaged regions on the selected display.
- The mask remains present across Spaces and over a full-screen application.
- Pointer interaction passes through the normal mask.
- A normal window overlapping the mask moves to the safe candidate selected by the documented nearest-side-first ordering within one event cycle.
- A safe window does not move.
- A full-screen window is not resized or moved.
- Disconnecting the display leaves no orphaned overlays and reconnecting restores the saved mask.
- Sleep/wake reconciliation tears down stale display resources and rebuilds them after reconnect.
- A failed mask replacement preserves the committed canvases, pauses correction, and reports its degraded state without notification spam.
- Missing Accessibility permission does not prevent the black mask from working.
- Reloading Hammerspoon does not duplicate canvases, watchers, subscriptions, or menu items.

## Planned file structure

```text
.
├── init.lua
├── screenfix/
│   ├── calibration.lua
│   ├── geometry.lua
│   ├── mask_overlay.lua
│   ├── screen_config.lua
│   └── window_guard.lua
├── tests/
│   └── geometry_test.lua
└── README.md
```
