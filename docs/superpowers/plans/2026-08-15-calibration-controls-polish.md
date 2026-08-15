# Calibration Controls Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the existing top-left instruction badge and bottom-left Save/Cancel controls without changing calibration behavior.

**Architecture:** Keep rendering and hit testing inside `screenfix/calibration.lua`, but calculate all control frames through one deterministic local-layout helper before allocating the editor canvas. Render the approved style from that layout, retain those same frames for hit testing, and rely on the existing transactional candidate lifecycle for assignment failures.

**Tech Stack:** Lua 5.4+, Hammerspoon `hs.canvas`, dependency-free Lua test harness

---

### Task 1: Render deterministic polished calibration controls

**Files:**
- Modify: `screenfix/calibration.lua:4-114,219-299,444-475`
- Modify: `tests/calibration_test.lua:221-266,1273-1335,1770-1875`
- Modify: `tests/fake_hs.lua:3-78`

- [ ] **Step 1: Write the normal-layout RED test**

Replace the current control assertions in
`draw makes editable bands and instructions visible without tracking them` with exact
3440 by 1440 expectations. Change that test fixture from 1000 by 800 to 3440 by 1440
and change the element-count assertion from 22 to 23 before running the RED test:

```lua
test.rect(elements[17].frame, { x = 24, y = 1374, w = 104, h = 42 })
test.equal(elements[17].roundedRectRadii.xRadius, 9)
test.equal(elements[17].roundedRectRadii.yRadius, 9)
test.equal(elements[17].fillColor.red, 22 / 255)
test.equal(elements[17].fillColor.green, 163 / 255)
test.equal(elements[17].fillColor.blue, 74 / 255)
test.rect(elements[19].frame, { x = 140, y = 1374, w = 104, h = 42 })
test.equal(elements[19].roundedRectRadii.xRadius, 9)
test.equal(elements[19].roundedRectRadii.yRadius, 9)
test.equal(elements[19].fillColor.red, 53 / 255)
test.equal(elements[19].fillColor.green, 58 / 255)
test.equal(elements[19].fillColor.blue, 66 / 255)
test.equal(elements[18].textSize, 16)
test.equal(elements[20].textSize, 16)

test.rect(elements[21].frame, { x = 24, y = 24, w = 330, h = 42 })
test.equal(elements[21].fillColor.white, 0)
test.equal(elements[21].fillColor.alpha, 0.88)
test.equal(elements[21].strokeColor.white, 1)
test.equal(elements[21].strokeColor.alpha, 0.28)
test.equal(elements[21].strokeWidth, 1)
test.equal(elements[21].roundedRectRadii.xRadius, 10)
test.equal(elements[21].roundedRectRadii.yRadius, 10)
test.rect(elements[22].frame, { x = 40, y = 41, w = 8, h = 8 })
test.equal(elements[22].fillColor.red, 1)
test.equal(elements[22].fillColor.green, 100 / 255)
test.equal(elements[22].fillColor.blue, 59 / 255)
test.rect(elements[23].frame, { x = 58, y = 24, w = 280, h = 42 })
test.equal(elements[23].text, "Drag red bands or white edges")
test.equal(elements[23].textAlignment, "left")
test.equal(elements[23].textSize, 15)
```

Assert elements 2 through 23 omit every `trackMouse*` field. Update the negative-origin
construction test to assert the same local instruction frames. Keep the canvas frame
absolute. Add separate fresh calibration cases proving the retained hit-test frames are
fresh copies rather than the same tables as the rendered frames, and proving clicks that
only fit the new geometry still work:

```lua
test.rect(calibration.saveFrame, { x = 24, y = 1374, w = 104, h = 42 })
test.equal(calibration.saveFrame == elements[17].frame, false)
-- A fresh session clicks (126, 1375): inside new Save, outside the former Save.

test.rect(calibration.cancelFrame, { x = 140, y = 1374, w = 104, h = 42 })
test.equal(calibration.cancelFrame == elements[19].frame, false)
-- A separate fresh session clicks (141, 1375): inside new Cancel, outside the former Cancel.
```

- [ ] **Step 2: Run the focused suite and witness RED**

Run:

```bash
lua -e 'package.path="./?.lua;./?/init.lua;"..package.path; local t=require("tests.test_helper"); require("tests.calibration_test"); os.exit(t.run())'
```

Expected: the new frame, style, element-count, and element-23 assertions fail against the
old 96 by 40 controls and 320 by 40 instruction.

- [ ] **Step 3: Implement only the approved normal layout and style GREEN**

In `screenfix/calibration.lua`, replace the old size constants with the approved normal
values and add a pure local layout helper. At this increment it only needs the normal
3440 by 1440 layout; do not add narrow layout or minimum-size rejection yet:

```lua
local CONTROL_GAP = 12
local CONTROL_HEIGHT = 42
local CONTROL_MARGIN = 24
local CONTROL_WIDTH = 104

local function controlLayout(fullFrame)
    local controlY = fullFrame.h - CONTROL_MARGIN - CONTROL_HEIGHT

    return {
        save = { x = 24, y = controlY, w = 104, h = 42 },
        cancel = { x = 140, y = controlY, w = 104, h = 42 },
        instruction = { x = 24, y = 24, w = 330, h = 42 },
        instructionDot = { x = 40, y = 41, w = 8, h = 8 },
        instructionText = { x = 58, y = 24, w = 280, h = 42 },
        instructionTextSize = 15,
    }
end
```

Call the helper immediately after `screen:fullFrame()` and before `canvas.new()`, then
store its returned table on the candidate session.

Make `renderEditor` use `session.controlLayout`. Update `control` and `label` to accept
explicit radius, text size, and alignment. Keep indices 17–20 for Save/Cancel, then render:

```lua
session.editorCanvas[21] = instructionBackground
session.editorCanvas[22] = instructionAccentDot
session.editorCanvas[23] = instructionText
```

Use exact normalized RGBA values from the design:

```lua
local SAVE_COLOR = { red = 22 / 255, green = 163 / 255, blue = 74 / 255, alpha = 1 }
local CANCEL_COLOR = { red = 53 / 255, green = 58 / 255, blue = 66 / 255, alpha = 1 }
local ACCENT_COLOR = { red = 1, green = 100 / 255, blue = 59 / 255, alpha = 1 }
```

Assign `session.saveFrame` and `session.cancelFrame` from fresh copies of the layout
frames so rendered frames and hit-test frames agree without sharing mutable canvas tables.

Run the focused command from Step 2.

Expected: every existing and new calibration case passes.

- [ ] **Step 4: Write the narrow/minimum-size and failed-replacement RED tests**

Add a 260 by 180 negative-origin test using the exact oracle:

```lua
test.rect(elements[17].frame, { x = 24, y = 114, w = 100, h = 42 })
test.rect(elements[19].frame, { x = 136, y = 114, w = 100, h = 42 })
test.rect(elements[21].frame, { x = 24, y = 24, w = 212, h = 58 })
test.rect(elements[22].frame, { x = 40, y = 49, w = 8, h = 8 })
test.rect(elements[23].frame, { x = 58, y = 24, w = 162, h = 58 })
test.equal(elements[23].textSize, 13)
```

Prove every frame stays inside local bounds. Add width-259 and height-179 cold-start cases
that return `nil, "display is too small for calibration controls"`, create zero canvases
and zero event taps, and do not mutate the supplied bands.

Add failed-replacement coverage too: start and retain a live editor on a normal screen,
then attempt replacements at width 259 and height 179. Each must return the exact error
while preserving the old canvas, enabled event tap, session, mouse callback, Save/Cancel
frames, working bands, and ownership token unchanged and live. No candidate canvas or
candidate event tap may be allocated.

- [ ] **Step 5: Run the focused suite and witness narrow/minimum RED**

Run the focused command from Step 2. Expected: narrow layout and undersized rejection
assertions fail while the normal-layout increment remains green.

- [ ] **Step 6: Implement narrow layout and minimum-size validation GREEN**

Extend `controlLayout` with the exact minimums and narrow branch:

```lua
local MIN_CANVAS_HEIGHT = 180
local MIN_CANVAS_WIDTH = 260
local NARROW_INSTRUCTION_THRESHOLD = 378
```

Use `min(104, floor((fullFrame.w - 48 - 12) / 2))` for button width. At widths below
378 use an instruction width of `fullFrame.w - 48`, height 58, centered dot, text width
`instructionWidth - 50`, and text size 13. At or above 378 preserve the normal oracle.
Call the helper immediately after `screen:fullFrame()` and before `canvas.new()`. If it
returns nil, raise the exact message inside the existing protected candidate-preparation
boundary. Run the focused suite and require GREEN.

- [ ] **Step 7: Write and witness the replacement-assignment RED test before fake support**

First initialize the requested injection state in the fake module but do not change the
canvas assignment behavior yet:

```lua
module.elementAssignmentCount = 0
module.failElementAssignmentAt = nil
module.failElementAssignmentMessage = nil
```

Start one committed editor, retain its canvas, event tap, Save/Cancel frames, callbacks,
session, ownership token, and bands, then request failure at a control/instruction element
during replacement. Assert replacement returns the exact injected error, deletes only the
candidate, starts no candidate input tap, and leaves every retained prior reference live
and unchanged. Run only this test and prove RED: without fake assignment injection the
replacement succeeds, so the expected nil/error and preservation assertions fail.

- [ ] **Step 8: Add minimal fake assignment injection and make the replacement test GREEN**

Extend the fake canvas `__newindex` path with an opt-in assignment counter/failure:

```lua
module.elementAssignmentCount = module.elementAssignmentCount + 1
if module.failElementAssignmentAt == module.elementAssignmentCount then
    error(module.failElementAssignmentMessage or "element assignment failure", 0)
end
```

Run the focused command. Verify the existing protected `renderEditor` path cleans the
candidate and preserves the prior editor. Do not add production recovery logic unless the
RED proves it is missing.

- [ ] **Step 9: Run complete verification**

Run:

```bash
lua tests/run.lua
for file in init.lua screenfix/*.lua tests/*.lua; do luac -p "$file"; done
git diff --check
```

Expected: zero failures, every Lua file parses, and the diff check is clean.

- [ ] **Step 10: Commit the implementation**

```bash
git add screenfix/calibration.lua tests/calibration_test.lua tests/fake_hs.lua
git commit -m "fix: polish calibration controls"
```

- [ ] **Step 11: Live Hammerspoon acceptance**

Reload Hammerspoon on the 3440 by 1440 selected display. Confirm the instruction text is
fully visible, Save/Cancel have the approved gap and insets, both controls still work, and
mouse held-drag plus trackpad tap-move-tap remain functional. Cancel without saving any
temporary calibration movement and verify the persisted 1215–1920 bands remain unchanged.
