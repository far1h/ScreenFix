# ScreenFix Hammerspoon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Hammerspoon Lua utility that masks a calibrated damaged display region and keeps ordinary windows inside the usable left and right areas.

**Architecture:** Pure geometry code calculates mask intersections and deterministic safe frames. Small Hammerspoon adapters persist monitor-specific calibration, render click-through canvases, observe window events, and provide direct calibration. A controller owns lifecycle and menu state so reloads never duplicate resources.

**Tech Stack:** Lua 5.4 for fast unit tests, Hammerspoon 1.x APIs (`hs.canvas`, `hs.window.filter`, `hs.screen`, `hs.settings`, `hs.chooser`, `hs.menubar`), macOS 13 Ventura.

---

Use `@superpowers:test-driven-development` for every task. If a test or runtime behavior is surprising, stop and use `@superpowers:systematic-debugging`. Before declaring the implementation complete, use `@superpowers:verification-before-completion`.

## Prerequisites

The current machine has Homebrew but does not yet have Lua or Hammerspoon.

```bash
brew install lua
brew install --cask hammerspoon
lua -v
test -d /Applications/Hammerspoon.app
```

Expected: `lua -v` reports Lua 5.4.x and the final command exits with status 0. Do not configure Accessibility permission until Task 8, when there is working behavior to verify.

## File map

| File | Responsibility |
| --- | --- |
| `init.lua` | Locate the project modules, stop a previous runtime, and start one controller. |
| `screenfix/controller.lua` | Coordinate settings, selected display, overlays, guard, calibration, watchers, and menu. |
| `screenfix/geometry.lua` | Pure rectangle conversion, intersection, editor hit-testing, and safe-frame selection. |
| `screenfix/screen_config.lua` | Validate and persist versioned settings; identify and watch the damaged monitor. |
| `screenfix/mask_overlay.lua` | Own normal-mode black canvases and their Spaces behavior. |
| `screenfix/window_guard.lua` | Filter, debounce, correct, and suppress retries for application windows. |
| `screenfix/calibration.lua` | Select a monitor and directly move or resize three mask bands. |
| `tests/test_helper.lua` | Minimal dependency-free Lua test registration and assertions. |
| `tests/fake_hs.lua` | Focused Hammerspoon fakes used by adapter tests. |
| `tests/*_test.lua` | Unit tests grouped by production module. |
| `tests/run.lua` | Load all suites and return a nonzero status on failure. |
| `README.md` | Concise explanation, file structure, installation, initialization, and use. |

`screenfix/controller.lua` is the implementation of the entry-point orchestration described in the design. Extracting it keeps `init.lua` declarative and makes lifecycle behavior testable.

### Task 1: Test harness and rectangle primitives

**Files:**
- Create: `tests/test_helper.lua`
- Create: `tests/run.lua`
- Create: `tests/geometry_test.lua`
- Create: `screenfix/geometry.lua`

- [ ] **Step 1: Create the test runner and write the first failing geometry tests**

Implement `tests/test_helper.lua` with `test(name, fn)`, `equal(actual, expected)`, `rect(actual, expected)`, and `run()`. `run()` prints one `PASS` or `FAIL` line per test and returns `0` only when every test passes.

Create `tests/run.lua`:

```lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local test = require("tests.test_helper")

require("tests.geometry_test")

os.exit(test.run())
```

Create `tests/geometry_test.lua` with these initial cases:

```lua
local test = require("tests.test_helper")
local geometry = require("screenfix.geometry")

test.test("absoluteBands maps normalized values onto a negative-origin screen", function()
  local bands = geometry.absoluteBands(
    { x = -3440, y = 0, w = 3440, h = 1440 },
    { { x = 0.40, y = 0.25, w = 0.20, h = 0.50 } }
  )
  test.rect(bands[1], { x = -2064, y = 360, w = 688, h = 720 })
end)

test.test("intersects requires positive overlap", function()
  test.equal(geometry.intersects(
    { x = 0, y = 0, w = 100, h = 100 },
    { x = 100, y = 0, w = 50, h = 50 }
  ), false)
  test.equal(geometry.intersects(
    { x = 0, y = 0, w = 100, h = 100 },
    { x = 99, y = 0, w = 50, h = 50 }
  ), true)
end)
```

- [ ] **Step 2: Run the tests to prove the module is missing**

Run: `lua tests/run.lua`

Expected: FAIL while loading `screenfix.geometry` because the module does not exist.

- [ ] **Step 3: Implement the minimal rectangle primitives**

Create `screenfix/geometry.lua` with this public surface:

```lua
local M = {}

local function copyRect(rect)
  return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

function M.intersects(a, b)
  return a.x < b.x + b.w
    and b.x < a.x + a.w
    and a.y < b.y + b.h
    and b.y < a.y + a.h
end

function M.absoluteBands(fullFrame, bands)
  local result = {}
  for index, band in ipairs(bands) do
    result[index] = {
      x = fullFrame.x + band.x * fullFrame.w,
      y = fullFrame.y + band.y * fullFrame.h,
      w = band.w * fullFrame.w,
      h = band.h * fullFrame.h,
    }
  end
  return result
end

function M.copyRect(rect)
  return copyRect(rect)
end

return M
```

- [ ] **Step 4: Run the focused tests**

Run: `lua tests/run.lua`

Expected: 2 PASS lines and exit status 0.

- [ ] **Step 5: Commit the increment**

```bash
git add screenfix/geometry.lua tests/test_helper.lua tests/geometry_test.lua tests/run.lua
git commit -m "test: add ScreenFix geometry harness"
```

### Task 2: Deterministic safe-frame selection

**Files:**
- Modify: `tests/geometry_test.lua`
- Modify: `screenfix/geometry.lua`

- [ ] **Step 1: Add failing tests for mask-aware correction**

Add one test at a time for:

1. returning `nil` when a window does not intersect any band;
2. preserving size on the nearest side when both sides fit;
3. choosing the nearest side even when it requires shrinking;
4. keeping a mirrored right-dragged window on the right while preserving its size;
5. shrinking an oversized window only as much as required on its nearest side;
6. using left as the exact cost tie-breaker;
7. combining every band that overlaps a tall window's final vertical span; and
8. `framesNear` accepting sub-point drift but rejecting material changes.

Live user feedback showed that resize-first ordering forced a window dragged left across the mask to the distant right side. The nearest-side-first regression must use this negative-origin display layout:

```lua
test.test("correctedFrame keeps a wide left-dragged window on the nearest safe side", function()
  local actual = geometry.correctedFrame(
    { x = -700, y = 100, w = 1400, h = 700 },
    { x = -951, y = 25, w = 3440, h = 1415 },
    { { x = 214, y = 0, w = 755, h = 1440 } }
  )
  test.rect(actual, { x = -951, y = 100, w = 1165, h = 700 })
end)
```

- [ ] **Step 2: Run each new test and observe the expected failure before implementation**

Run after each added case: `lua tests/run.lua`

Expected: the new case fails because `correctedFrame` or `framesNear` is missing or incomplete; existing cases remain green.

- [ ] **Step 3: Implement candidate construction and lexicographic comparison**

Add focused private helpers `clamp`, `overlappingBands`, `buildCandidate`, `candidateCost`, and `lessCost`. Expose:

```lua
function M.correctedFrame(windowFrame, usableFrame, maskRects)
  local overlapsMask = false
  for _, mask in ipairs(maskRects) do
    if M.intersects(windowFrame, mask) then
      overlapsMask = true
      break
    end
  end
  if not overlapsMask then return nil end

  local height = math.min(windowFrame.h, usableFrame.h)
  local y = clamp(windowFrame.y, usableFrame.y,
    usableFrame.y + usableFrame.h - height)
  local verticalFrame = { x = windowFrame.x, y = y, w = windowFrame.w, h = height }
  local relevant = overlappingBands(verticalFrame, maskRects)

  local left = buildCandidate("left", windowFrame, usableFrame, relevant, y, height)
  local right = buildCandidate("right", windowFrame, usableFrame, relevant, y, height)
  if not left then return right and right.frame or nil end
  if not right then return left.frame end
  return lessCost(left.cost, right.cost) and left.frame or right.frame
end

function M.framesNear(a, b, tolerance)
  tolerance = tolerance or 1
  return math.abs(a.x - b.x) <= tolerance
    and math.abs(a.y - b.y) <= tolerance
    and math.abs(a.w - b.w) <= tolerance
    and math.abs(a.h - b.h) <= tolerance
end
```

`buildCandidate` must:

- derive the left boundary from the minimum relevant mask `x`;
- derive the right boundary from the maximum relevant mask `x + w`;
- clamp both regions to `usableFrame`;
- preserve width when it fits and otherwise reduce it to region width;
- clamp `x` to the selected region; and
- return `{ frame = ..., cost = { movement, reduction, sideRank } }` where `sideRank` is 0 for left and 1 for right.

`lessCost` compares tuple entries in order. Movement is `abs(old.x - new.x) + abs(old.y - new.y)` and reduction is `(old.w - new.w) + (old.h - new.h)`.

- [ ] **Step 4: Run the geometry suite**

Run: `lua tests/run.lua`

Expected: every geometry case passes, including negative display origins and the nearest-side-first oracle.

- [ ] **Step 5: Commit the increment**

```bash
git add screenfix/geometry.lua tests/geometry_test.lua
git commit -m "feat: calculate deterministic safe window frames"
```

### Task 3: Versioned monitor configuration

**Files:**
- Create: `tests/fake_hs.lua`
- Create: `tests/screen_config_test.lua`
- Create: `screenfix/screen_config.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing configuration tests with injected fakes**

Add `require("tests.screen_config_test")` to the runner. The tests must prove:

- defaults contain exactly three valid normalized bands;
- malformed, out-of-range, and wrong-version settings return an error;
- save writes one table to `screenfix.config`;
- UUID matching wins;
- name plus full-frame resolution is accepted only when exactly one screen matches;
- an absent or ambiguous monitor returns `nil`; and
- a screen watcher is retained, started once, and stopped cleanly.

Construct the module with dependencies instead of replacing global state:

```lua
local store = {}
local config = ScreenConfig.new({
  settings = {
    get = function(key) return store[key] end,
    set = function(key, value) store[key] = value end,
  },
  allScreens = function() return fakeScreens end,
  newScreenWatcher = function(callback) return fakeWatcher(callback) end,
})
```

- [ ] **Step 2: Run the suite to prove the adapter is missing**

Run: `lua tests/run.lua`

Expected: FAIL loading `screenfix.screen_config`.

- [ ] **Step 3: Implement strict configuration validation and screen lookup**

Create `screenfix/screen_config.lua` with:

```lua
local M = {}
M.KEY = "screenfix.config"

local ScreenConfig = {}
ScreenConfig.__index = ScreenConfig

function M.new(deps)
  return setmetatable({ deps = deps, watcher = nil }, ScreenConfig)
end

function ScreenConfig:defaultForScreen(screen)
  local frame = screen:fullFrame()
  return {
    schemaVersion = 1,
    enabled = true,
    screen = {
      uuid = screen:getUUID(),
      name = screen:name(),
      width = frame.w,
      height = frame.h,
    },
    bands = {
      { x = 0.43, y = 0.00, w = 0.16, h = 0.34 },
      { x = 0.46, y = 0.34, w = 0.11, h = 0.39 },
      { x = 0.48, y = 0.73, w = 0.07, h = 0.27 },
    },
  }
end
```

Implement `validate(value)`, `load()`, `save(value)`, `findScreen(value)`, `watch(callback)`, and `stopWatching()`. `validate` returns `nil, errorMessage` rather than throwing. Require exactly three bands, finite numeric values, positive sizes, and `x + w <= 1`, `y + h <= 1`.

- [ ] **Step 4: Run all tests**

Run: `lua tests/run.lua`

Expected: configuration and geometry suites pass.

- [ ] **Step 5: Commit the increment**

```bash
git add screenfix/screen_config.lua tests/fake_hs.lua tests/screen_config_test.lua tests/run.lua
git commit -m "feat: persist monitor-specific mask settings"
```

### Task 4: Normal-mode black mask overlay

**Files:**
- Create: `tests/mask_overlay_test.lua`
- Create: `screenfix/mask_overlay.lua`
- Modify: `tests/fake_hs.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing overlay lifecycle tests**

Extend the canvas fake so every constructor and chained method is recorded. Test that `show(screen, bands)`:

- requires an injected `hideDockIcon`, invokes it once before the first display lookup or canvas construction, and does not repeat it on rebuild;
- returns `nil, error` without changing the current canvases when `hideDockIcon`, `screen:fullFrame()`, or `geometry.absoluteBands` raises;
- converts normalized bands using `screen:fullFrame()`;
- creates exactly three opaque black rectangle canvases;
- assigns `canJoinAllSpaces`, `fullScreenAuxiliary`, and `stationary` behaviors;
- sets the `screenSaver` level;
- defines no mouse tracking attributes in normal mode;
- deletes old canvases only after display lookup succeeds;
- builds into a temporary collection, cleans every partial canvas with protected deletion on allocation or configuration failure, and retains no partial mask;
- returns `true` after a successful build; and
- lets `hide()` and `delete()` clean up idempotently.

- [ ] **Step 2: Run the suite and observe the missing-module failure**

Run: `lua tests/run.lua`

Expected: FAIL loading `screenfix.mask_overlay`.

- [ ] **Step 3: Implement the overlay owner**

`MaskOverlay.new` requires `canvas`, `geometry`, and `hideDockIcon` dependencies. `show` returns `true` on success or `nil, error` on failure. Use this object boundary:

```lua
local M = {}
local Overlay = {}
Overlay.__index = Overlay

local function deleteCanvases(canvases)
  for _, canvas in ipairs(canvases) do
    pcall(function()
      canvas:delete()
    end)
  end
end

local function configureCanvas(canvas)
  canvas[1] = {
    type = "rectangle",
    action = "fill",
    fillColor = { white = 0, alpha = 1 },
    frame = { x = 0, y = 0, w = "100%", h = "100%" },
  }
  canvas:clickActivating(false)
  canvas:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary", "stationary" })
  canvas:level("screenSaver")
  canvas:show()
end

local function createCanvases(canvasModule, frames)
  local created = {}
  local built, buildError = pcall(function()
    for _, frame in ipairs(frames) do
      local canvas = canvasModule.new(frame)
      if not canvas then
        error("canvas construction failed", 0)
      end

      created[#created + 1] = canvas
      configureCanvas(canvas)
    end
  end)

  if not built then
    deleteCanvases(created)
    return nil, buildError
  end

  return created
end

function M.new(deps)
  return setmetatable({ deps = deps, canvases = {}, hidden = true, prepared = false }, Overlay)
end

function Overlay:show(screen, bands)
  if not self.prepared then
    local prepared, prepareError = pcall(self.deps.hideDockIcon)
    if not prepared then
      return nil, prepareError
    end

    self.prepared = true
  end

  local framesAvailable, frames = pcall(function()
    local fullFrame = screen:fullFrame()
    return self.deps.geometry.absoluteBands(fullFrame, bands)
  end)
  if not framesAvailable then
    return nil, frames
  end

  self:delete()

  local created, buildError = createCanvases(self.deps.canvas, frames)
  if not created then
    return nil, buildError
  end

  self.canvases = created
  self.hidden = false
  return true
end
```

Add short `hide()` and `delete()` methods. `delete()` must use `deleteCanvases`, clear the Lua references, and be safe when called repeatedly.

- [ ] **Step 4: Run all unit tests**

Run: `lua tests/run.lua`

Expected: overlay, configuration, and geometry tests pass.

- [ ] **Step 5: Commit the increment**

```bash
git add screenfix/mask_overlay.lua tests/fake_hs.lua tests/mask_overlay_test.lua tests/run.lua
git commit -m "feat: render persistent black mask bands"
```

### Task 5: Window eligibility and correction

**Files:**
- Create: `tests/window_guard_test.lua`
- Create: `screenfix/window_guard.lua`
- Modify: `tests/fake_hs.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing tests for eligible and skipped windows**

Create fake windows with `id`, `frame`, `screen`, `isStandard`, `isVisible`, `isMinimized`, `isFullScreen`, and `setFrame` methods. Test that one correction:

- changes an overlapping standard window on the selected monitor;
- does nothing to a safe window;
- skips full-screen, minimized, hidden, nonstandard, and other-monitor windows;
- applies the geometry target with animation duration `0`; and
- records a target so the immediate self-generated event is ignored.

- [ ] **Step 2: Run the suite to prove the guard is missing**

Run: `lua tests/run.lua`

Expected: FAIL loading `screenfix.window_guard`.

- [ ] **Step 3: Implement the correction boundary**

The controller supplies the current target whenever it starts the guard, so reconnects can refresh state without rebuilding the object:

```lua
function M.new(deps)
  return setmetatable({
    deps = deps,
    filter = nil,
    pending = {},
    recent = {},
    blockedUntil = {},
    selectedScreen = nil,
    maskRects = {},
  }, WindowGuard)
end
```

Implement `isEligible(window)`, `correct(window)`, `start(screen, maskRects)`, and `stop()`. `start` stores the current screen and absolute mask rectangles before subscribing. `correct` must:

1. use the stored selected screen and absolute mask bands;
2. reject a recent frame that is within one point of the script's own target;
3. call `geometry.correctedFrame`;
4. return without mutation when it returns `nil`;
5. call `window:setFrame(target, 0)`;
6. compare the resulting frame to the target; and
7. suppress retries for one second when an application rejects the frame.

Use `window:screen():getUUID()` for selected-screen identity and tolerate methods returning `nil` by treating the window as ineligible.

- [ ] **Step 4: Run all unit tests**

Run: `lua tests/run.lua`

Expected: all current suites pass.

- [ ] **Step 5: Commit the increment**

```bash
git add screenfix/window_guard.lua tests/fake_hs.lua tests/window_guard_test.lua tests/run.lua
git commit -m "feat: correct windows that overlap the mask"
```

### Task 6: Debounced Hammerspoon window events

**Files:**
- Modify: `tests/window_guard_test.lua`
- Modify: `screenfix/window_guard.lua`
- Modify: `tests/fake_hs.lua`

- [ ] **Step 1: Add failing subscription and debounce tests**

Test that `start()`:

- creates a local copy with `hs.window.filter.new()` semantics;
- applies `{ visible = true, fullscreen = false, currentSpace = true }` as an override;
- subscribes to `windowCreated`, `windowMoved`, and `windowOnScreen`;
- replaces an existing pending timer for the same window ID;
- corrects only once after a 0.15-second debounce; and
- is idempotent.

Test that `stop()` cancels pending timers, unsubscribes all events, pauses the filter, and clears cooldown state.

- [ ] **Step 2: Run the new tests and observe failures**

Run: `lua tests/run.lua`

Expected: only the new subscription/debounce assertions fail.

- [ ] **Step 3: Implement event subscription and cleanup**

Construct the runtime dependencies in production as:

```lua
local windowFilter = hs.window.filter

filterFactory = function()
  return windowFilter.new():setOverrideFilter({
    visible = true,
    fullscreen = false,
    currentSpace = true,
  })
end
```

Subscribe with the constants from that filter module. The callback schedules `deps.timer.doAfter(0.15, ...)`. Store timers by `window:id()`, stop the previous timer before replacement, and remove the entry before invoking `correct`.

- [ ] **Step 4: Run all unit tests**

Run: `lua tests/run.lua`

Expected: every suite passes with one correction for a burst of window events.

- [ ] **Step 5: Commit the increment**

```bash
git add screenfix/window_guard.lua tests/fake_hs.lua tests/window_guard_test.lua
git commit -m "feat: debounce window lifecycle events"
```

### Task 7: Direct on-screen calibration

**Files:**
- Create: `tests/calibration_test.lua`
- Create: `screenfix/calibration.lua`
- Modify: `screenfix/geometry.lua`
- Modify: `tests/geometry_test.lua`
- Modify: `tests/fake_hs.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing pure tests for editor hit-testing and dragging**

Add geometry tests for:

- mapping normalized bands into canvas-local coordinates without adding the display origin;
- hitting a band's left, right, top, and bottom handles;
- hitting the band body when no edge is within the handle threshold;
- moving a band without leaving normalized screen bounds;
- resizing an edge while preserving a minimum 20-point rendered size; and
- returning a new table so Cancel can restore the original values.

The local-coordinate test must use a non-zero origin and this oracle:

```lua
test.test("localBands ignores the global display origin", function()
  local bands = geometry.localBands(
    { x = -3440, y = -200, w = 3440, h = 1440 },
    { { x = 0.40, y = 0.25, w = 0.20, h = 0.50 } }
  )
  test.rect(bands[1], { x = 1376, y = 360, w = 688, h = 720 })
end)
```

Expose `localBands(fullFrame, bands)`, `editorHit(localPoint, localBands, handleSize)`, and `dragBand(normalizedBand, drag, localDelta, fullFrame)` from `geometry.lua`. `localBands` multiplies normalized values by width and height but never adds `fullFrame.x` or `fullFrame.y`.

- [ ] **Step 2: Implement the minimal pure editor functions and pass their tests**

Run after each case: `lua tests/run.lua`

Expected: each new case fails first, then passes after the smallest corresponding implementation.

- [ ] **Step 3: Write failing adapter tests for monitor selection and calibration lifecycle**

Test that calibration:

- presents one `hs.chooser` row per connected screen using serializable UUID, name, width, and height values;
- creates one full-screen editor canvas on the chosen monitor;
- sets the editor canvas to `assistiveTechHigh` before input callbacks and `show`, keeping it above `screenSaver` mask canvases;
- positions that canvas with the monitor's absolute `fullFrame()` while drawing every element in canvas-local coordinates;
- uses a tracked background surface and `canvasMouseEvents(true, true, false, true)`;
- draws three black bands, edge handles, Save, and Cancel controls;
- updates a copied working value during mouse movement while the left button is down;
- calls `onSave(workingBands)` only after validation;
- calls `onCancel()` without changing saved bands; and
- deletes the chooser, canvas, and callbacks on stop.

Include an adapter case whose monitor frame is `{ x = -3440, y = -200, w = 3440, h = 1440 }`. Assert that `hs.canvas.new` receives that absolute frame, the first band element receives the local frame from `geometry.localBands`, and a mouse callback at local `{ x = 1376, y = 360 }` hits the first band. This is the regression oracle for monitors left of or above the primary display.

- [ ] **Step 4: Implement the calibration adapter**

Use this public boundary:

```lua
local calibration = Calibration.new({
  canvas = hs.canvas,
  chooser = hs.chooser,
  screens = function() return hs.screen.allScreens() end,
  mouseButtons = function() return hs.eventtap.checkMouseButtons() end,
  reportError = function(err) hs.showError(err) end,
  geometry = geometry,
})

calibration:selectScreen(onSelect)
calibration:start(screen, bands, onSave, onCancel)
calibration:stop()
```

The editor canvas is positioned with the absolute `screen:fullFrame()`. All canvas element frames are local: the drawable origin is `{ x = 0, y = 0 }`, bands come from `geometry.localBands`, and Save/Cancel offsets are measured from that local origin. Never add the screen's global `x` or `y` to an element frame.

Set `editorCanvas:level("assistiveTechHigh")` before mouse callback setup and `show()`. Treat level configuration like the other transactional setup steps: if it fails, delete only the partial replacement and restore the prior editor, callbacks, bands, and controls unchanged.

The bottom background element covers the entire local canvas and has `trackMouseDown`, `trackMouseUp`, and `trackMouseMove`; higher visual elements need no tracking, so the background receives coordinates across the whole editor. Because the callback's `x` and `y` are relative to that tracked full-canvas background element, pass them directly to `editorHit` as a local point. Compute drag deltas from successive local callback positions, then let `dragBand` divide by `fullFrame.w` and `fullFrame.h` when updating normalized values. On mouse down, hit-test Save, Cancel, then band handles/body. On mouse move, update only while a drag is active and the left button remains down. On mouse up, clear the drag state. Redraw from the copied working bands after every change.

Keep Save and Cancel at fixed 24-point margins in the usable left area. Give all functions short names that describe one action: `draw`, `beginDrag`, `updateDrag`, `save`, `cancel`, and `stop`.

- [ ] **Step 5: Run all tests**

Run: `lua tests/run.lua`

Expected: geometry and calibration suites pass without launching Hammerspoon.

- [ ] **Step 6: Commit the increment**

```bash
git add screenfix/calibration.lua screenfix/geometry.lua tests/calibration_test.lua tests/geometry_test.lua tests/fake_hs.lua tests/run.lua
git commit -m "feat: add direct mask calibration"
```

### Task 8: Runtime controller, menu, and reload safety

**Files:**
- Create: `tests/controller_test.lua`
- Create: `tests/init_test.lua`
- Create: `screenfix/controller.lua`
- Create: `init.lua`
- Modify: `tests/fake_hs.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing lifecycle and bootstrap assembly tests**

With injected adapter factories, test that the controller:

- prompts for monitor selection when no valid configuration exists;
- always renders a valid enabled mask even without Accessibility permission;
- starts the guard only when enabled, configured, connected, and Accessibility-trusted;
- shows a one-time disconnected notification and restores on the screen-watcher callback;
- owns a mandatory `hs.caffeinate.watcher`, refreshes only for system/display wake events, and stops it during rollback, shutdown, and reload;
- saves Enable/Disable changes and immediately tears resources down or rebuilds them;
- enters calibration with the guard paused and restores it after Save or Cancel;
- exposes Enable/Disable, Calibrate, Select Monitor, and Reload menu items;
- reports paused permission state in the menu;
- reports a one-time mask-rendering failure episode in the menu, preserves the committed mask, and resumes correction after rendering recovers;
- handles `hs.accessibilityStateCallback` by refreshing once permission changes; and
- deletes every owned resource when stopped.

In `tests/init_test.lua`, load the real `init.lua` bootstrap with a fake global `hs` and recording `package.preload` module stubs. The `MaskOverlay.new` stub must capture the exact dependency table without supplying defaults. Assert that `hideDockIcon` is a function, invoke the captured function, and assert that the fake `hs.dockicon.hide()` was called exactly once. This assembly test must not use an overlay helper that fills in a missing `hideDockIcon`, because such a default would conceal an incomplete production bootstrap.

- [ ] **Step 2: Run the suite and observe the missing runtime failures**

Run: `lua tests/run.lua`

Expected: FAIL loading `screenfix.controller` or `init.lua`; both the lifecycle and production assembly tests are red before implementation.

- [ ] **Step 3: Implement the controller with explicit lifecycle methods**

The public interface is:

```lua
local controller = Controller.new({
  hs = hs,
  config = screenConfig,
  overlay = overlay,
  guard = guard,
  calibration = calibration,
})

controller:start()
controller:stop()
```

Keep orchestration in short methods: `refresh`, `enable`, `disable`, `selectMonitor`, `calibrate`, `saveCalibration`, `menuItems`, `notifyOnce`, and `stop`. `refresh` is the only method that decides whether overlay and guard should run.

The controller treats both screen and caffeinate watcher startup as mandatory and transactional. It subscribes only to `systemDidWake` and `screensDidWake`, invalidates pending monitor selection before wake reconciliation, and contains late callbacks after stop. A failed normal-mask render stores the current error, stops the guard, adds a disabled `Paused: Mask rendering failed` row, and notifies once until a successful render or inactive/disconnected state clears the episode.

Create the menu with `hs.menubar.new(true, "ScreenFix")`, title it `SF`, and pass a function to `setMenu` so checked and disabled states are always current. Use `hs.accessibilityState(true)` only at first start; subsequent checks use `false` to avoid repeated prompts.

- [ ] **Step 4: Create a reload-safe entry point**

`init.lua` must resolve the repository root even when it is loaded through a symlink:

```lua
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/init%.lua$")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

if _G.screenFixRuntime then
  _G.screenFixRuntime:stop()
end

local geometry = require("screenfix.geometry")
local ScreenConfig = require("screenfix.screen_config")
local MaskOverlay = require("screenfix.mask_overlay")
local WindowGuard = require("screenfix.window_guard")
local Calibration = require("screenfix.calibration")
local Controller = require("screenfix.controller")

local screenConfig = ScreenConfig.new({
  settings = hs.settings,
  allScreens = function() return hs.screen.allScreens() end,
  newScreenWatcher = function(callback)
    return hs.screen.watcher.new(callback)
  end,
})

local overlay = MaskOverlay.new({
  canvas = hs.canvas,
  geometry = geometry,
  hideDockIcon = function()
    hs.dockicon.hide()
  end,
})

local windowFilter = hs.window.filter
local guard = WindowGuard.new({
  geometry = geometry,
  timer = hs.timer,
  now = function() return hs.timer.secondsSinceEpoch() end,
  filterFactory = function()
    return windowFilter.new():setOverrideFilter({
      visible = true,
      fullscreen = false,
      currentSpace = true,
    })
  end,
  events = {
    windowFilter.windowCreated,
    windowFilter.windowMoved,
    windowFilter.windowOnScreen,
  },
})

local calibration = Calibration.new({
  canvas = hs.canvas,
  chooser = hs.chooser,
  screens = function() return hs.screen.allScreens() end,
  mouseButtons = function() return hs.eventtap.checkMouseButtons() end,
  reportError = function(err) hs.showError(err) end,
  geometry = geometry,
})

_G.screenFixRuntime = Controller.new({
  hs = hs,
  geometry = geometry,
  config = screenConfig,
  overlay = overlay,
  guard = guard,
  calibration = calibration,
})
_G.screenFixRuntime:start()
```

The controller owns these objects and `stop()` must be safe when called more than once.

- [ ] **Step 5: Run all tests and a Lua syntax check**

Run:

```bash
lua tests/run.lua
find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n1 luac -p
```

Expected: all test cases pass, syntax checking produces no output, and both commands exit 0.

- [ ] **Step 6: Commit the increment**

```bash
git add init.lua screenfix/controller.lua tests/controller_test.lua tests/init_test.lua tests/fake_hs.lua tests/run.lua
git commit -m "feat: orchestrate ScreenFix lifecycle"
```

### Task 9: Concise setup documentation and real Hammerspoon verification

**Files:**
- Create: `README.md`
- Modify: implementation files only when a runtime test proves a defect

- [ ] **Step 1: Write the README**

Keep it concise and include:

- what ScreenFix does and the physical-pixel limitation;
- the file tree and one-line responsibility summary;
- prerequisites: macOS 13+, current stable Hammerspoon, Accessibility permission;
- initialization without overwriting an existing Hammerspoon config;
- calibration, menu, launch-at-login, disable, and uninstall steps; and
- `lua tests/run.lua` for collaborators.

Use this safe initialization shape:

```bash
mkdir -p ~/.hammerspoon
ln -s "$PWD" ~/.hammerspoon/ScreenFix
```

Then tell the user to add exactly this line to their existing `~/.hammerspoon/init.lua`:

```lua
dofile(hs.configdir .. "/ScreenFix/init.lua")
```

If `~/.hammerspoon/ScreenFix` already exists, stop and inspect it; do not replace it automatically.

- [ ] **Step 2: Run the complete automated verification**

Run:

```bash
lua tests/run.lua
find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n1 luac -p
git diff --check
```

Expected: all tests pass, both validation commands are silent, and every command exits 0.

- [ ] **Step 3: Initialize Hammerspoon without overwriting user state**

First inspect:

```bash
ls -ld ~/.hammerspoon ~/.hammerspoon/ScreenFix ~/.hammerspoon/init.lua 2>/dev/null || true
```

Create only missing paths. If an existing `init.lua` is present, use `apply_patch` to add the one `dofile` line without changing existing configuration. Launch Hammerspoon with `open -a Hammerspoon` and reload its config.

Expected: Hammerspoon shows the `SF` menu. macOS may prompt for Accessibility permission.

- [ ] **Step 4: Verify the no-permission path before granting access**

Confirm that:

- the selected monitor chooser/calibration can open;
- the black mask renders after Save;
- the menu reports window protection paused; and
- ordinary windows are not moved.

This proves the mask is independent of Accessibility permission.

- [ ] **Step 5: Grant Accessibility permission and verify window protection**

In System Settings, allow Hammerspoon under Privacy & Security > Accessibility, then relaunch Hammerspoon if macOS requires it.

Verify one behavior at a time:

1. a safe window does not move;
2. a wide overlapping window dragged left stays on the left and shrinks if necessary, while the mirrored right-dragged window stays on the right;
3. a full-screen window is not changed while the mask remains visible;
4. moving the window repeatedly does not oscillate;
5. Disable removes masks and stops correction; and
6. Enable restores them.

- [ ] **Step 6: Verify display and Space behavior**

Manually verify:

- another Space;
- a native full-screen Space;
- monitor disconnect and reconnect;
- display scaling or arrangement change;
- Hammerspoon config reload; and
- Hammerspoon Launch at login enabled in its preferences.

Expected: the selected display and normalized bands restore without duplicate menus, canvases, watchers, or event subscriptions.

- [ ] **Step 7: Fix only proven runtime defects, rerun the smallest failing check, then rerun the full suite**

For every failure, record the reproduction, identify the root cause, add the smallest automated regression test where practical, implement one fix, and rerun the focused test before the full verification commands.

- [ ] **Step 8: Commit documentation and any proven integration fixes**

```bash
git add README.md init.lua screenfix tests
git commit -m "docs: add ScreenFix setup and verification"
```

- [ ] **Step 9: Final repository checks**

Run:

```bash
git status --short
git log --oneline -10
lua tests/run.lua
```

Expected: only the user's reference PNG remains untracked, the history shows focused incremental commits, and all tests pass.
