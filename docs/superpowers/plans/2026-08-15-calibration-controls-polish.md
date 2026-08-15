# Calibration Controls Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the existing top-left instruction badge and bottom-left Save/Cancel controls without changing calibration behavior.

**Architecture:** Keep rendering and hit testing inside `screenfix/calibration.lua`, but calculate all control frames through one deterministic local-layout helper before allocating the editor canvas. Render the approved style from that layout, retain those same frames for hit testing, and rely on the existing transactional candidate lifecycle for assignment failures.

**Tech Stack:** Lua 5.4+, Hammerspoon `hs.canvas`, dependency-free Lua test harness

---

### Task 1: Render deterministic polished calibration controls

**Files:**
- Modify: `screenfix/calibration.lua:4-114,219-299,497-511`
- Modify: `tests/calibration_test.lua:221-266,1273-1335,1770-1875`
- Modify: `tests/fake_hs.lua:3-78`

- [ ] **Step 1: Write the normal-layout RED test**

Replace the current control assertions in
`draw makes editable bands and instructions visible without tracking them` with exact
3440 by 1440 expectations:

```lua
test.rect(elements[17].frame, { x = 24, y = 1374, w = 104, h = 42 })
test.equal(elements[17].roundedRectRadii.xRadius, 9)
test.equal(elements[17].fillColor.red, 22 / 255)
test.equal(elements[17].fillColor.green, 163 / 255)
test.equal(elements[17].fillColor.blue, 74 / 255)
test.rect(elements[19].frame, { x = 140, y = 1374, w = 104, h = 42 })
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
absolute.

- [ ] **Step 2: Run the focused suite and witness RED**

Run:

```bash
lua -e 'package.path="./?.lua;./?/init.lua;"..package.path; local t=require("tests.test_helper"); require("tests.calibration_test"); os.exit(t.run())'
```

Expected: the new frame, style, element-count, and element-23 assertions fail against the
old 96 by 40 controls and 320 by 40 instruction.

- [ ] **Step 3: Add the shared local control-layout helper**

In `screenfix/calibration.lua`, replace the old size constants with the approved values
and add a pure helper equivalent to:

```lua
local CONTROL_GAP = 12
local CONTROL_HEIGHT = 42
local CONTROL_MARGIN = 24
local CONTROL_WIDTH = 104
local MIN_CANVAS_HEIGHT = 180
local MIN_CANVAS_WIDTH = 260
local NARROW_INSTRUCTION_THRESHOLD = 378

local function controlLayout(fullFrame)
    if fullFrame.w < MIN_CANVAS_WIDTH or fullFrame.h < MIN_CANVAS_HEIGHT then
        return nil, "display is too small for calibration controls"
    end

    local buttonWidth = math.min(
        CONTROL_WIDTH,
        math.floor((fullFrame.w - 2 * CONTROL_MARGIN - CONTROL_GAP) / 2)
    )
    local controlY = fullFrame.h - CONTROL_MARGIN - CONTROL_HEIGHT
    local narrow = fullFrame.w < NARROW_INSTRUCTION_THRESHOLD
    local instructionHeight = narrow and 58 or 42
    local instructionWidth = narrow and fullFrame.w - 2 * CONTROL_MARGIN or 330

    return {
        save = { x = 24, y = controlY, w = buttonWidth, h = 42 },
        cancel = {
            x = 24 + buttonWidth + 12,
            y = controlY,
            w = buttonWidth,
            h = 42,
        },
        instruction = { x = 24, y = 24, w = instructionWidth, h = instructionHeight },
        instructionDot = {
            x = 40,
            y = 24 + (instructionHeight - 8) / 2,
            w = 8,
            h = 8,
        },
        instructionText = {
            x = 58,
            y = 24,
            w = instructionWidth - 50,
            h = instructionHeight,
        },
        instructionTextSize = narrow and 13 or 15,
    }
end
```

Call this after `screen:fullFrame()` and before `canvas.new()`. Store the result on the
candidate session. If it returns nil, raise its exact message inside the existing protected
allocation boundary so no editor is allocated.

- [ ] **Step 4: Render the approved normal controls GREEN**

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

- [ ] **Step 5: Run focused tests GREEN**

Run the focused command from Step 2.

Expected: every existing and new calibration case passes.

- [ ] **Step 6: Write the narrow/minimum-size RED tests**

Add a 260 by 180 negative-origin test using the exact oracle:

```lua
test.rect(elements[17].frame, { x = 24, y = 114, w = 100, h = 42 })
test.rect(elements[19].frame, { x = 136, y = 114, w = 100, h = 42 })
test.rect(elements[21].frame, { x = 24, y = 24, w = 212, h = 58 })
test.rect(elements[22].frame, { x = 40, y = 49, w = 8, h = 8 })
test.rect(elements[23].frame, { x = 58, y = 24, w = 162, h = 58 })
test.equal(elements[23].textSize, 13)
```

Prove every frame stays inside local bounds. Add width-259 and height-179 cases that
return `nil, "display is too small for calibration controls"`, create zero canvases and
zero event taps, and do not mutate the supplied bands.

- [ ] **Step 7: Run focused tests RED, then implement minimum-size validation GREEN**

Run the focused command after adding each behavior. Observe the expected missing-layout
failure before adding the minimal production branch, then rerun until focused tests pass.

- [ ] **Step 8: Write the replacement-assignment RED test**

Extend the fake canvas `__newindex` path with an opt-in assignment counter/failure:

```lua
module.elementAssignmentCount = module.elementAssignmentCount + 1
if module.failElementAssignmentAt == module.elementAssignmentCount then
    error(module.failElementAssignmentMessage or "element assignment failure", 0)
end
```

Start one committed editor, retain its canvas, event tap, Save/Cancel frames, callbacks,
session and ownership token, then fail a control/instruction assignment in a replacement.
Assert the replacement returns the exact error, deletes only the candidate, starts no
candidate input tap, and leaves every retained prior reference live and unchanged.

- [ ] **Step 9: Run the replacement test RED then GREEN**

Run the focused command. First verify the fake does not yet support the injected failure.
After the minimal fake boundary exists, verify the existing protected `renderEditor` path
already cleans the candidate and preserves the prior editor. Do not add production recovery
logic unless the RED proves it is missing.

- [ ] **Step 10: Run complete verification**

Run:

```bash
lua tests/run.lua
for file in init.lua screenfix/*.lua tests/*.lua; do luac -p "$file"; done
git diff --check
```

Expected: zero failures, every Lua file parses, and the diff check is clean.

- [ ] **Step 11: Commit the implementation**

```bash
git add screenfix/calibration.lua tests/calibration_test.lua tests/fake_hs.lua
git commit -m "fix: polish calibration controls"
```

- [ ] **Step 12: Live Hammerspoon acceptance**

Reload Hammerspoon on the 3440 by 1440 selected display. Confirm the instruction text is
fully visible, Save/Cancel have the approved gap and insets, both controls still work, and
mouse held-drag plus trackpad tap-move-tap remain functional. Cancel without saving any
temporary calibration movement and verify the persisted 1215–1920 bands remain unchanged.
