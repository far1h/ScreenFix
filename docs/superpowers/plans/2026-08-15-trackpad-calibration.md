# Trackpad-Friendly Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make calibration move red band bodies and resize all four white edges with both mouse hold-drag-release and trackpad tap-move-tap.

**Architecture:** Keep the canvas as the sole mouse-down/hit-test owner. Add one calibration-scoped `hs.eventtap` as the sole movement and mouse-up owner, guarded by a session token and a four-point threshold. Preserve transactional editor replacement and idempotent teardown.

**Tech Stack:** Lua 5.4, Hammerspoon 1.1.1 `hs.canvas` and `hs.eventtap`, existing table-driven Lua tests.

---

### Task 1: Event-tap test adapter

**Files:**
- Modify: `tests/fake_hs.lua`
- Modify: `tests/calibration_test.lua`
- Modify: `tests/init_test.lua`
- Modify: `screenfix/calibration.lua`
- Modify: `init.lua`

- [ ] **Step 1: Add the event-tap test adapter**

Add a fake event-tap factory that records `new`, `start`, `stop`, subscribed event
types, callback return values, and injected failures. Expose this exact test contract:

```lua
local tap = eventtap.new(eventTypes, function(event) ... end)
tap:start()
tap:stop()
event:getType()
event:location()
```

Every emitted event records the callback result so tests can assert it is exactly
`false`, including error paths. This is test infrastructure only.

- [ ] **Step 2: Write failing construction, ownership, and assembly tests**

Expect one tap for `mouseMoved`, `leftMouseDragged`, and `leftMouseUp`. Canvas
tracking must retain `trackMouseByBounds = true`, set only `trackMouseDown = true`,
and call `canvasMouseEvents(true, false, false, false)`. `init_test.lua` must assert
`eventtap = hs.eventtap` and the exact three `hs.eventtap.event.types` constants.

- [ ] **Step 3: Run the suite and verify RED**

Run: `lua tests/run.lua`

Expected: calibration start fails because no event-tap dependency is used and canvas still owns move/up.

- [ ] **Step 4: Add minimal production construction and assembly**

Create/start the three-event tap during calibration and wire `eventtap = hs.eventtap`
from `init.lua`. Its callback may initially return `false` without moving anything.
Disable canvas move/up ownership. Use `event:getType()`, never `event:type()`.

- [ ] **Step 5: Verify construction GREEN**

Run: `lua tests/run.lua`

Expected: construction/ownership/assembly tests pass; no movement exists yet.

### Task 2: Mouse and trackpad interaction state machine

**Files:**
- Modify: `screenfix/calibration.lua`
- Modify: `tests/calibration_test.lua`

- [ ] **Step 1: Write a RED held-drag target matrix**

For body/left/right/top/bottom targets, canvas mouse-down selects the target, an
emitted `leftMouseDragged` beyond four points applies the expected geometry, and
`leftMouseUp` drops it. The body must preserve size; each edge must keep its
opposite edge fixed and retain the 20-point minimum.

- [ ] **Step 2: Run the target matrix and verify RED**

Run: `lua tests/run.lua`

Expected: all five cases fail because the event-tap callback does not route movement.

- [ ] **Step 3: Implement the held-drag path**

Route the event tap created in Task 1. Convert `event:location()` to local
coordinates by subtracting `fullFrame.x/y`. Route `leftMouseDragged` to
`updateDrag` and `leftMouseUp` to a single end-drag method. Always return `false`
from the callback.

- [ ] **Step 4: Verify held-drag GREEN**

Run: `lua tests/run.lua`

Expected: all five held-drag targets and existing tests pass.

- [ ] **Step 5: Write a RED latched-movement target matrix**

For the same body/left/right/top/bottom table, emit down/up without accepted
movement, then `mouseMoved` beyond four points. Assert body movement and the same
four independent edge-resize invariants.

- [ ] **Step 6: Run the latched matrix and verify RED**

Run: `lua tests/run.lua`

Expected: all five cases fail because mouse-up clears the selection.

- [ ] **Step 7: Implement tap-move-tap**

Record press origin, last point, `moved`, and `latched` on the existing drag. A
release before accepted movement latches it. Accept `mouseMoved` only while
latched. Keep `geometry.editorHit` and `geometry.dragBand` as the only geometry
authorities.

- [ ] **Step 8: Verify latched movement GREEN**

Run: `lua tests/run.lua`

Expected: both input styles pass for body and all four edges.

- [ ] **Step 9: Write RED threshold, drop, and control-precedence tests**

Assert movement below four points does not mutate geometry; the first accepted
movement applies the full delta; Save/Cancel execute immediately while latched;
and the next non-control press drops without selecting another target.

- [ ] **Step 10: Run the new tests and verify RED**

Run: `lua tests/run.lua`

Expected: the first missing threshold/precedence behavior fails for its intended reason.

- [ ] **Step 11: Implement threshold and precedence, then verify GREEN**

Use squared Euclidean distance from the press origin. Do not update `lastPoint`
until the threshold is crossed, so the first accepted update applies the full
accumulated delta. Route controls before latched-drop handling.

Run: `lua tests/run.lua`

Expected: mouse movement, four edge resizes, tap-move-tap, threshold, and all original tests pass.

### Task 3: Lifecycle, session safety, and real assembly

**Files:**
- Modify: `screenfix/calibration.lua`
- Modify: `init.lua`
- Modify: `tests/calibration_test.lua`
- Modify: `tests/init_test.lua`
- Modify: `README.md`

- [ ] **Step 1: Write RED replacement/session tests**

Cover candidate constructor/start/configuration failure, successful replacement,
and stale old callbacks. Candidate failure must preserve a functioning prior editor:
exercise both its canvas-down and event-tap movement callbacks after rollback.
Success must stop only the prior tap and stale callbacks must not mutate the new
session.

- [ ] **Step 2: Run replacement/session tests and verify RED**

Run: `lua tests/run.lua`

Expected: rollback or stale-callback assertions fail under the current lifecycle.

- [ ] **Step 3: Add a staged, token-guarded session**

Build a candidate session locally: token, canvas, tap, full frame, bands, callbacks,
and control frames. Render/configure/show its canvas and start its tap without
changing the active token. Only after every step succeeds, commit the candidate as
active, then stop/delete the prior session. On failure, stop/delete only the
candidate; the active token and prior session never change. A small render helper
must accept candidate canvas/frame/bands instead of temporarily overwriting active
`self` fields.

- [ ] **Step 4: Verify replacement/session GREEN**

Run: `lua tests/run.lua`

Expected: rollback, success retirement, and stale callback tests pass.

- [ ] **Step 5: Write RED teardown/error tests**

Cover tap-stop failure, canvas-delete failure, event callback error and
pass-through, Save callback error, Cancel, successful Save, double stop, and
controller teardown. The canvas-delete failure case must prove `stop()` does not
throw, active state is cleared, a repeated stop is harmless, and the recorded
ordering is token invalidation, tap stop/clear, session-state clear, then canvas
clear/delete.

- [ ] **Step 6: Run teardown/error tests and verify RED**

Run: `lua tests/run.lua`

Expected: the first missing teardown/error boundary fails for its intended reason.

- [ ] **Step 7: Implement teardown/error containment**

On teardown: invalidate the active token first, stop/nil its tap under `pcall`,
clear drag/editor/session state and the canvas reference, then delete the captured
canvas under `pcall`. Movement errors call the existing reporter and keep the
editor active. Every tap callback returns literal `false` after its protected
dispatch; never return `pcall(...)`.

- [ ] **Step 8: Wire and verify current Hammerspoon APIs**

Pass `eventtap = hs.eventtap` from `init.lua`. Use `hs.eventtap.event.types.mouseMoved`, `leftMouseDragged`, and `leftMouseUp`; callback returns `false` on every path.

- [ ] **Step 9: Update concise usage text**

README must say: red center moves; white edges resize; mouse uses hold-drag-release; trackpad can use tap-move-tap; no Shift is required.

- [ ] **Step 10: Run automated verification**

Run:

```bash
lua tests/run.lua
for file in init.lua screenfix/*.lua tests/*.lua; do luac -p "$file"; done
git diff --check
```

Expected: all tests pass, every Lua file parses, and diff check is clean.

- [ ] **Step 11: Commit the implementation**

```bash
git add screenfix/calibration.lua init.lua tests/calibration_test.lua tests/init_test.lua tests/fake_hs.lua README.md
git commit -m "fix: support trackpad calibration dragging"
```

### Task 4: Live Hammerspoon acceptance

**Files:**
- No production file changes unless a new reproducible defect is found through a fresh RED test.

- [ ] **Step 1: Reload Hammerspoon and open calibration**

Verify the editor shows red bands, white handles, and instructions on `ZQE-CAA`.

- [ ] **Step 2: Drive a real body movement**

Post a real mouse-down, `leftMouseDragged`, and mouse-up inside a red body; confirm its normalized x changes by the posted pixel delta without changing width.

- [ ] **Step 3: Drive a real white-edge resize**

Post a real mouse-down on the left white edge, `leftMouseDragged`, and mouse-up; confirm the left coordinate changes while the right coordinate remains fixed.

- [ ] **Step 4: Drive tap-move-tap**

Post down/up on a white edge, a `mouseMoved` event beyond four points, then down/up to drop. Confirm the resize occurs and dragging stops.

- [ ] **Step 5: Cancel and verify persisted safety**

Cancel calibration and query runtime/settings. Expected: normal three-mask protection and window guard resume; saved left/right remain exactly `1215` and `1920`.
