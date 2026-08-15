local RealCalibration = require("screenfix.calibration")
local MaskOverlay = require("screenfix.mask_overlay")
local fake = require("tests.fake_hs")
local geometry = require("screenfix.geometry")
local test = require("tests.test_helper")

local function newCalibration(deps)
    deps.eventtap = deps.eventtap or fake.eventtap()
    return RealCalibration.new(deps)
end

local function validBands()
    return {
        { x = 0.40, y = 0.25, w = 0.20, h = 0.50 },
        { x = 0.45, y = 0.10, w = 0.10, h = 0.20 },
        { x = 0.48, y = 0.75, w = 0.05, h = 0.20 },
    }
end

local function startInputCalibration(fullFrame, onSave, onCancel)
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    calibration:start(
        fake.screen("display", "Display", fullFrame),
        validBands(),
        onSave or function() end,
        onCancel or function() end
    )

    return calibration, canvas.canvases[1], eventtap.taps[1], eventtap.event.types
end

local function emitLocal(tap, eventType, fullFrame, point)
    local result, event = tap:emit(eventType, {
        x = fullFrame.x + point.x,
        y = fullFrame.y + point.y,
    })
    test.equal(result, false)

    return result, event
end

local function rectNear(actual, expected)
    for _, key in ipairs({ "x", "y", "w", "h" }) do
        test.equal(math.abs(actual[key] - expected[key]) < 0.000000001, true)
    end
end

local function assertActiveMovement(calibration, editor, tap, eventTypes)
    editor:triggerMouse("mouseDown", 500, 400)
    local result = tap:emit(eventTypes.leftMouseDragged, { x = 520, y = 420 })

    test.equal(result, false)
    rectNear(calibration.workingBands[1], {
        x = 0.42,
        y = 0.275,
        w = 0.20,
        h = 0.50,
    })
end

local heldDragCases = {
    {
        name = "body",
        press = { x = 500, y = 400 },
        moved = { x = 530, y = 424 },
        postPress = { x = 530, y = 424 },
        expected = { x = 0.43, y = 0.28, w = 0.20, h = 0.50 },
    },
    {
        name = "left",
        press = { x = 400, y = 400 },
        moved = { x = 700, y = 400 },
        postPress = { x = 580, y = 400 },
        expected = { x = 0.58, y = 0.25, w = 0.02, h = 0.50 },
    },
    {
        name = "right",
        press = { x = 600, y = 400 },
        moved = { x = 300, y = 400 },
        postPress = { x = 420, y = 400 },
        expected = { x = 0.40, y = 0.25, w = 0.02, h = 0.50 },
    },
    {
        name = "top",
        press = { x = 600, y = 200 },
        moved = { x = 600, y = 700 },
        postPress = { x = 600, y = 580 },
        expected = { x = 0.40, y = 0.725, w = 0.20, h = 0.025 },
    },
    {
        name = "bottom",
        press = { x = 600, y = 600 },
        moved = { x = 600, y = 100 },
        postPress = { x = 600, y = 220 },
        expected = { x = 0.40, y = 0.25, w = 0.20, h = 0.025 },
    },
}

test.test("selectScreen presents one serializable chooser row per screen", function()
    local canvas = fake.canvas()
    local chooser = fake.chooser()
    local screens = {
        fake.screen("left-uuid", "Left Display", { x = -3440, y = -200, w = 3440, h = 1440 }),
        fake.screen("main-uuid", "Main Display", { x = 0, y = 0, w = 1920, h = 1080 }),
    }
    local calibration = newCalibration({
        canvas = canvas,
        chooser = chooser,
        screens = function()
            return screens
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    calibration:selectScreen(function() end)

    test.equal(#chooser.choosers, 1)
    local choices = chooser.choosers[1].choicesCalls[1]
    test.equal(#choices, 2)
    test.equal(choices[1].uuid, "left-uuid")
    test.equal(choices[1].name, "Left Display")
    test.equal(choices[1].width, 3440)
    test.equal(choices[1].height, 1440)
    test.equal(type(choices[1].screen), "nil")
    for _, choice in ipairs(choices) do
        for _, value in pairs(choice) do
            test.equal(type(value) == "string" or type(value) == "number", true)
        end
    end
end)

test.test("selectScreen returns the chosen live screen and ignores dismissal", function()
    local chooser = fake.chooser()
    local screens = {
        fake.screen("left-uuid", "Left Display", { x = -3440, y = -200, w = 3440, h = 1440 }),
        fake.screen("main-uuid", "Main Display", { x = 0, y = 0, w = 1920, h = 1080 }),
    }
    local selected
    local calibration = newCalibration({
        canvas = fake.canvas(),
        chooser = chooser,
        screens = function()
            return screens
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    calibration:selectScreen(function(screen)
        selected = screen
    end)
    chooser.choosers[1]:choose(nil)
    test.equal(selected, nil)
    chooser.choosers[1]:choose(chooser.choosers[1].choicesCalls[1][2])
    test.equal(selected, screens[2])
end)

test.test("selectScreen contains screen lookup failures without allocating a chooser", function()
    local chooser = fake.chooser()
    local calibration = newCalibration({
        canvas = fake.canvas(),
        chooser = chooser,
        screens = function()
            error("screen lookup failed", 0)
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    local safe, selected, selectionError = pcall(function()
        return calibration:selectScreen(function() end)
    end)

    test.equal(safe, true)
    test.equal(selected, nil)
    test.equal(selectionError, "screen lookup failed")
    test.equal(#chooser.choosers, 0)
end)

test.test("start uses an absolute canvas with local band coordinates", function()
    local canvas = fake.canvas()
    local fullFrame = { x = -3440, y = -200, w = 3440, h = 1440 }
    local bands = {
        { x = 0.40, y = 0.25, w = 0.20, h = 0.50 },
        { x = 0.45, y = 0.10, w = 0.10, h = 0.20 },
        { x = 0.48, y = 0.75, w = 0.05, h = 0.20 },
    }
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    local started = calibration:start(
        fake.screen("left-uuid", "Left Display", fullFrame),
        bands,
        function() end,
        function() end
    )

    test.equal(started, true)
    test.rect(canvas.constructorFrames[1], fullFrame)
    test.equal(canvas.canvases[1].showCount, 1)
    test.rect(canvas.canvases[1].elements[2].frame, {
        x = 1376,
        y = 360,
        w = 688,
        h = 720,
    })
    test.rect(canvas.canvases[1].elements[21].frame, {
        x = 24,
        y = 24,
        w = 320,
        h = 40,
    })
    canvas.canvases[1]:triggerMouse("mouseDown", 1376, 360)
    test.equal(calibration.drag.index, 1)
    test.equal(calibration.drag.part, "top")
end)

test.test("calibration editor stays above rebuilt masks before input and show", function()
    local canvas = fake.canvas()
    local frame = { x = 0, y = 0, w = 1000, h = 800 }
    local screen = fake.screen("display", "Display", frame)
    local overlay = MaskOverlay.new({
        canvas = canvas,
        geometry = {
            absoluteBands = function()
                return { { x = 400, y = 0, w = 200, h = 800 } }
            end,
        },
        hideDockIcon = function()
        end,
    })
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return { screen }
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    overlay:show(screen, validBands())
    calibration:start(screen, validBands(), function() end, function() end)

    local maskCanvas = canvas.canvases[1]
    local editorCanvas = canvas.canvases[2]
    test.equal(maskCanvas.levelCalls[1], "screenSaver")
    test.equal(editorCanvas.levelCalls[1], "assistiveTechHigh")
    test.equal(maskCanvas.elements[1].fillColor.white, 0)
    test.equal(maskCanvas.elements[1].fillColor.alpha, 1)
    test.equal(editorCanvas.elements[2].fillColor.red, 0.95)
    test.equal(editorCanvas.elements[2].fillColor.alpha, 0.45)
    test.equal(
        canvas.windowLevels[editorCanvas.levelCalls[1]]
            > canvas.windowLevels[maskCanvas.levelCalls[1]],
        true
    )

    local levelIndex
    local mouseIndex
    local showIndex
    for index, operation in ipairs(canvas.operationLog) do
        if operation.canvas == editorCanvas then
            if operation.name == "level" then
                levelIndex = index
            elseif operation.name == "mouseCallback" then
                mouseIndex = index
            elseif operation.name == "show" then
                showIndex = index
            end
        end
    end
    test.equal(levelIndex < mouseIndex, true)
    test.equal(levelIndex < showIndex, true)
end)

test.test("start gives canvas only mouse-down ownership and starts one movement tap", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local fullFrame = { x = -3440, y = -200, w = 3440, h = 1440 }
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    calibration:start(
        fake.screen("left-uuid", "Left Display", fullFrame),
        validBands(),
        function() end,
        function() end
    )

    local editor = canvas.canvases[1]
    local background = editor.elements[1]
    test.rect(background.frame, { x = 0, y = 0, w = 3440, h = 1440 })
    test.equal(background.trackMouseByBounds, true)
    test.equal(background.trackMouseDown, true)
    test.equal(background.trackMouseUp, nil)
    test.equal(background.trackMouseMove, nil)
    test.equal(type(editor.mouseCallbackFn), "function")
    test.equal(editor.clickActivatingCalls[1], true)
    local events = editor.canvasMouseEventsCalls[1]
    test.equal(events.down, true)
    test.equal(events.up, false)
    test.equal(events.enterExit, false)
    test.equal(events.move, false)

    test.equal(#eventtap.newCalls, 1)
    test.equal(#eventtap.taps, 1)
    local tap = eventtap.taps[1]
    test.equal(#tap.eventTypes, 3)
    test.equal(tap.eventTypes[1], eventtap.event.types.mouseMoved)
    test.equal(tap.eventTypes[2], eventtap.event.types.leftMouseDragged)
    test.equal(tap.eventTypes[3], eventtap.event.types.leftMouseUp)
    test.equal(tap.startCount, 1)
    local callbackResult, event = tap:emit(eventtap.event.types.mouseMoved, { x = 10, y = 20 })
    test.equal(callbackResult, false)
    test.equal(tap.callbackResults[1], false)
    test.equal(event.getTypeCallCount, 1)
end)

for _, case in ipairs(heldDragCases) do
    test.test("held event drag updates the " .. case.name .. " and drops on release", function()
        local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
        local calibration, editor, tap, eventTypes = startInputCalibration(fullFrame)

        editor:triggerMouse("mouseDown", case.press.x, case.press.y)
        test.equal(calibration.drag.part, case.name)
        local dragResult, dragEvent = emitLocal(
            tap,
            eventTypes.leftMouseDragged,
            fullFrame,
            case.moved
        )

        test.equal(dragResult, false)
        test.equal(dragEvent.locationCallCount, 1)
        rectNear(calibration.workingBands[1], case.expected)
        local upResult, upEvent = emitLocal(tap, eventTypes.leftMouseUp, fullFrame, case.moved)
        test.equal(upResult, false)
        test.equal(upEvent.locationCallCount, 1)
        test.equal(calibration.drag, nil)
        emitLocal(tap, eventTypes.mouseMoved, fullFrame, case.press)
        rectNear(calibration.workingBands[1], case.expected)
    end)
end

for _, case in ipairs(heldDragCases) do
    test.test("latched pointer movement updates the " .. case.name, function()
        local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
        local calibration, editor, tap, eventTypes = startInputCalibration(fullFrame)

        editor:triggerMouse("mouseDown", case.press.x, case.press.y)
        local upResult, upEvent = emitLocal(tap, eventTypes.leftMouseUp, fullFrame, case.press)

        test.equal(upResult, false)
        test.equal(upEvent.locationCallCount, 1)
        test.equal(calibration.drag.part, case.name)
        test.equal(calibration.drag.latched, true)
        emitLocal(tap, eventTypes.leftMouseUp, fullFrame, case.press)
        test.equal(calibration.drag.latched, true)
        local moveResult, moveEvent = emitLocal(tap, eventTypes.mouseMoved, fullFrame, case.moved)
        test.equal(moveResult, false)
        test.equal(moveEvent.locationCallCount, 1)
        rectNear(calibration.workingBands[1], case.expected)
        test.equal(calibration.drag.latched, true)
        editor:triggerMouse("mouseDown", case.press.x, case.press.y)
        test.equal(calibration.drag, nil)
        emitLocal(tap, eventTypes.leftMouseUp, fullFrame, case.press)
        emitLocal(tap, eventTypes.mouseMoved, fullFrame, case.press)
        rectNear(calibration.workingBands[1], case.expected)
        editor:triggerMouse("mouseDown", case.postPress.x, case.postPress.y)
        test.equal(calibration.drag.part, case.name)
    end)
end

test.test("duplicate release after latched movement preserves the selection", function()
    local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
    local calibration, editor, tap, eventTypes = startInputCalibration(fullFrame)

    editor:triggerMouse("mouseDown", 500, 400)
    emitLocal(tap, eventTypes.leftMouseUp, fullFrame, { x = 500, y = 400 })
    emitLocal(tap, eventTypes.mouseMoved, fullFrame, { x = 510, y = 410 })
    test.equal(calibration.drag.latched, true)
    test.equal(calibration.drag.moved, true)

    emitLocal(tap, eventTypes.leftMouseUp, fullFrame, { x = 510, y = 410 })

    test.equal(calibration.drag.latched, true)
    test.equal(calibration.drag.moved, true)
    rectNear(calibration.workingBands[1], {
        x = 0.41,
        y = 0.2625,
        w = 0.20,
        h = 0.50,
    })
end)

test.test("movement does not ratchet below threshold and becomes incremental at four points", function()
    local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
    local calibration, editor, tap, eventTypes = startInputCalibration(fullFrame)
    local original = validBands()[1]

    editor:triggerMouse("mouseDown", 500, 400)
    for _, point in ipairs({
        { x = 501, y = 401 },
        { x = 502, y = 402 },
        { x = 503, y = 400 },
    }) do
        emitLocal(tap, eventTypes.leftMouseDragged, fullFrame, point)
        test.rect(calibration.workingBands[1], original)
        test.equal(calibration.drag.moved, false)
    end

    emitLocal(tap, eventTypes.leftMouseDragged, fullFrame, { x = 504, y = 400 })
    rectNear(calibration.workingBands[1], {
        x = 0.404,
        y = 0.25,
        w = 0.20,
        h = 0.50,
    })
    emitLocal(tap, eventTypes.leftMouseDragged, fullFrame, { x = 505, y = 402 })
    rectNear(calibration.workingBands[1], {
        x = 0.405,
        y = 0.2525,
        w = 0.20,
        h = 0.50,
    })
end)

test.test("movement threshold uses Euclidean distance for diagonal input", function()
    local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
    local calibration, editor, tap, eventTypes = startInputCalibration(fullFrame)

    editor:triggerMouse("mouseDown", 500, 400)
    emitLocal(tap, eventTypes.leftMouseDragged, fullFrame, { x = 502, y = 403 })
    test.rect(calibration.workingBands[1], validBands()[1])
    emitLocal(tap, eventTypes.leftMouseUp, fullFrame, { x = 502, y = 403 })
    test.equal(calibration.drag.latched, true)
    emitLocal(tap, eventTypes.mouseMoved, fullFrame, { x = 503, y = 403 })
    rectNear(calibration.workingBands[1], {
        x = 0.403,
        y = 0.25375,
        w = 0.20,
        h = 0.50,
    })
end)

for _, case in ipairs({
    { name = "Save", point = { x = 30, y = 750 }, saveCalls = 1, cancelCalls = 0 },
    { name = "Cancel", point = { x = 150, y = 750 }, saveCalls = 0, cancelCalls = 1 },
}) do
    test.test(case.name .. " executes immediately while movement is latched", function()
        local saveCalls = 0
        local cancelCalls = 0
        local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
        local calibration, editor, tap, eventTypes = startInputCalibration(
            fullFrame,
            function()
                saveCalls = saveCalls + 1
            end,
            function()
                cancelCalls = cancelCalls + 1
            end
        )
        calibration.workingBands[3] = { x = 0.02, y = 0.90, w = 0.25, h = 0.08 }
        calibration:draw()
        editor:triggerMouse("mouseDown", 500, 400)
        emitLocal(tap, eventTypes.leftMouseUp, fullFrame, { x = 500, y = 400 })
        test.equal(calibration.drag.latched, true)

        editor:triggerMouse("mouseDown", case.point.x, case.point.y)

        test.equal(saveCalls, case.saveCalls)
        test.equal(cancelCalls, case.cancelCalls)
        test.equal(calibration.editorCanvas, nil)
    end)
end

for _, case in ipairs({
    { name = "empty space", point = { x = 800, y = 700 } },
    { name = "another target", point = { x = 500, y = 160 }, index = 2, part = "body" },
    { name = "the same target", point = { x = 500, y = 400 }, index = 1, part = "body" },
}) do
    test.test("a tap on " .. case.name .. " only drops latched movement", function()
        local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
        local calibration, editor, tap, eventTypes = startInputCalibration(fullFrame)

        editor:triggerMouse("mouseDown", 500, 400)
        emitLocal(tap, eventTypes.leftMouseUp, fullFrame, { x = 500, y = 400 })
        test.equal(calibration.drag.latched, true)

        editor:triggerMouse("mouseDown", case.point.x, case.point.y)
        test.equal(calibration.drag, nil)

        editor:triggerMouse("mouseDown", case.point.x, case.point.y)
        if case.index then
            test.equal(calibration.drag.index, case.index)
            test.equal(calibration.drag.part, case.part)
        else
            test.equal(calibration.drag, nil)
        end
    end)
end

test.test("movement callback contains and reports dispatch errors", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local reports = {}
    local failingGeometry = {
        localBands = geometry.localBands,
        editorHit = geometry.editorHit,
        dragBand = function()
            error("drag failed", 0)
        end,
    }
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = failingGeometry,
        reportError = function(message)
            reports[#reports + 1] = message
        end,
    })
    local fullFrame = { x = -100, y = -50, w = 1000, h = 800 }
    calibration:start(
        fake.screen("display", "Display", fullFrame),
        validBands(),
        function() end,
        function() end
    )
    canvas.canvases[1]:triggerMouse("mouseDown", 500, 400)

    local result = emitLocal(
        eventtap.taps[1],
        eventtap.event.types.leftMouseDragged,
        fullFrame,
        { x = 510, y = 410 }
    )

    test.equal(result, false)
    test.equal(reports[1], "drag failed")
    test.rect(calibration.workingBands[1], validBands()[1])
end)

for _, case in ipairs({
    {
        name = "event type",
        message = "get type failed",
        event = function()
            return {
                getType = function()
                    error("get type failed", 0)
                end,
            }
        end,
    },
    {
        name = "event location",
        message = "location failed",
        event = function(eventTypes)
            return {
                getType = function()
                    return eventTypes.leftMouseDragged
                end,
                location = function()
                    error("location failed", 0)
                end,
            }
        end,
    },
}) do
    test.test(case.name .. " errors return false, report once, and keep input live", function()
        local canvas = fake.canvas()
        local eventtap = fake.eventtap()
        local reportCalls = 0
        local reported
        local calibration = newCalibration({
            canvas = canvas,
            chooser = fake.chooser(),
            eventtap = eventtap,
            screens = function()
                return {}
            end,
            mouseButtons = function()
                return {}
            end,
            geometry = geometry,
            reportError = function(message)
                reportCalls = reportCalls + 1
                reported = message
                error("report failed", 0)
            end,
        })
        calibration:start(
            fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
            validBands(),
            function() end,
            function() end
        )
        local editor = canvas.canvases[1]
        local tap = eventtap.taps[1]
        editor:triggerMouse("mouseDown", 500, 400)

        local safe, result = pcall(tap.callback, case.event(eventtap.event.types))

        test.equal(safe, true)
        test.equal(result, false)
        test.equal(reportCalls, 1)
        test.equal(reported, case.message)
        test.equal(calibration.editorCanvas, editor)
        test.equal(calibration.eventTap, tap)
        test.equal(editor.deleteCount, 0)
        test.equal(tap.stopCount, 0)
        tap:emit(eventtap.event.types.leftMouseDragged, { x = 520, y = 420 })
        test.equal(calibration.workingBands[1].x > 0.40, true)
    end)
end

for _, case in ipairs({
    { name = "drag calculation", message = "drag failed", drawFailure = false },
    { name = "editor redraw", message = "draw failed", drawFailure = true },
}) do
    test.test(case.name .. " errors return false, report once, and recover", function()
        local canvas = fake.canvas()
        local eventtap = fake.eventtap()
        local failOperation = true
        local failNextDraw = false
        local reportCalls = 0
        local reported
        local failingGeometry = {
            editorHit = geometry.editorHit,
            localBands = function(...)
                if failNextDraw then
                    failNextDraw = false
                    failOperation = false
                    error(case.message, 0)
                end
                return geometry.localBands(...)
            end,
            dragBand = function(...)
                if failOperation and not case.drawFailure then
                    failOperation = false
                    error(case.message, 0)
                end
                local band = geometry.dragBand(...)
                if failOperation and case.drawFailure then
                    failNextDraw = true
                end
                return band
            end,
        }
        local calibration = newCalibration({
            canvas = canvas,
            chooser = fake.chooser(),
            eventtap = eventtap,
            screens = function()
                return {}
            end,
            mouseButtons = function()
                return {}
            end,
            geometry = failingGeometry,
            reportError = function(message)
                reportCalls = reportCalls + 1
                reported = message
                error("report failed", 0)
            end,
        })
        calibration:start(
            fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
            validBands(),
            function() end,
            function() end
        )
        local editor = canvas.canvases[1]
        local tap = eventtap.taps[1]
        editor:triggerMouse("mouseDown", 500, 400)

        local firstResult = tap:emit(
            eventtap.event.types.leftMouseDragged,
            { x = 520, y = 420 }
        )

        test.equal(firstResult, false)
        test.equal(reportCalls, 1)
        test.equal(reported, case.message)
        test.equal(calibration.editorCanvas, editor)
        test.equal(calibration.eventTap, tap)
        test.equal(editor.deleteCount, 0)
        test.equal(tap.stopCount, 0)
        local secondResult = tap:emit(
            eventtap.event.types.leftMouseDragged,
            { x = 530, y = 430 }
        )
        test.equal(secondResult, false)
        test.equal(reportCalls, 1)
        test.equal(calibration.workingBands[1].x > 0.40, true)
    end)
end

test.test("event-tap construction failure cleans the candidate editor", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    eventtap.failMethod = "new"
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    local safe, started, startError = pcall(function()
        return calibration:start(
            fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
            validBands(),
            function() end,
            function() end
        )
    end)

    test.equal(safe, true)
    test.equal(started, nil)
    test.equal(startError, "new failure")
    test.equal(#eventtap.failures, 1)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(calibration.editorCanvas, nil)
end)

test.test("event-tap replacement construction failure preserves active input", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local activeCanvas = calibration.editorCanvas
    local activeTap = calibration.eventTap
    eventtap.failMethod = "new"
    eventtap.failMethodAt = 2

    local started, startError = calibration:start(screen, validBands(), function() end, function() end)

    test.equal(started, nil)
    test.equal(startError, "new failure")
    test.equal(calibration.editorCanvas, activeCanvas)
    test.equal(calibration.eventTap, activeTap)
    test.equal(activeCanvas.deleteCount, 0)
    test.equal(activeTap.stopCount, 0)
    test.equal(canvas.canvases[2].deleteCount, 1)
    assertActiveMovement(calibration, activeCanvas, activeTap, eventtap.event.types)
end)

test.test("event-tap start failure stops the candidate and preserves the active editor", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local activeCanvas = calibration.editorCanvas
    local activeTap = calibration.eventTap
    eventtap.failMethod = "start"
    eventtap.failMethodAt = 2

    local started, startError = calibration:start(screen, validBands(), function() end, function() end)

    test.equal(started, nil)
    test.equal(startError, "start failure")
    test.equal(calibration.editorCanvas, activeCanvas)
    test.equal(calibration.eventTap, activeTap)
    test.equal(activeCanvas.deleteCount, 0)
    test.equal(activeTap.stopCount, 0)
    test.equal(eventtap.taps[2].stopCount, 1)
    test.equal(canvas.canvases[2].deleteCount, 1)
    assertActiveMovement(calibration, activeCanvas, activeTap, eventtap.event.types)
end)

test.test("disabled event tap after start is stopped and preserves the active editor", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local activeCanvas = calibration.editorCanvas
    local activeTap = calibration.eventTap
    eventtap.startEnabled = false

    local started, startError = calibration:start(screen, validBands(), function() end, function() end)

    test.equal(started, nil)
    test.equal(startError, "event tap failed to start")
    test.equal(calibration.editorCanvas, activeCanvas)
    test.equal(calibration.eventTap, activeTap)
    test.equal(activeCanvas.deleteCount, 0)
    test.equal(activeTap.stopCount, 0)
    test.equal(eventtap.taps[2].startCount, 1)
    test.equal(eventtap.taps[2].stopCount, 1)
    test.equal(eventtap.taps[2]:isEnabled(), false)
    test.equal(canvas.canvases[2].deleteCount, 1)
    assertActiveMovement(calibration, activeCanvas, activeTap, eventtap.event.types)
end)

test.test("draw makes editable bands and instructions visible without tracking them", function()
    local canvas = fake.canvas()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 100, y = 50, w = 1000, h = 800 }),
        validBands(),
        function() end,
        function() end
    )

    local elements = canvas.canvases[1].elements
    test.equal(#elements, 22)
    for index = 2, 4 do
        test.equal(elements[index].type, "rectangle")
        test.equal(elements[index].action, "strokeAndFill")
        test.equal(elements[index].fillColor.red, 0.95)
        test.equal(elements[index].fillColor.green, 0.12)
        test.equal(elements[index].fillColor.blue, 0.08)
        test.equal(elements[index].fillColor.alpha, 0.45)
        test.equal(elements[index].strokeColor.red, 1)
        test.equal(elements[index].strokeColor.green, 0.55)
        test.equal(elements[index].strokeColor.blue, 0.15)
        test.equal(elements[index].strokeColor.alpha, 1)
        test.equal(elements[index].strokeWidth, 3)
    end
    for index = 5, 16 do
        test.equal(elements[index].fillColor.white, 1)
    end
    test.rect(elements[17].frame, { x = 24, y = 736, w = 96, h = 40 })
    test.equal(elements[18].text, "Save")
    test.rect(elements[19].frame, { x = 144, y = 736, w = 96, h = 40 })
    test.equal(elements[20].text, "Cancel")
    test.rect(elements[21].frame, { x = 24, y = 24, w = 320, h = 40 })
    test.equal(elements[21].action, "strokeAndFill")
    test.equal(elements[21].fillColor.white, 0)
    test.equal(elements[21].fillColor.alpha, 0.82)
    test.equal(elements[21].strokeColor.white, 1)
    test.equal(elements[21].strokeColor.alpha, 1)
    test.equal(elements[21].strokeWidth, 2)
    test.equal(elements[22].text, "Drag red bands or white edges")
    test.rect(elements[22].frame, elements[21].frame)
    test.equal(elements[22].textColor.white, 1)
    test.equal(elements[22].textColor.alpha, 1)
    test.equal(elements[21].frame.y + elements[21].frame.h < elements[17].frame.y, true)

    for index = 2, 22 do
        test.equal(elements[index].trackMouseByBounds, nil)
        test.equal(elements[index].trackMouseDown, nil)
        test.equal(elements[index].trackMouseUp, nil)
        test.equal(elements[index].trackMouseMove, nil)
    end
end)

test.test("Save validates and commits the copied working bands", function()
    local canvas = fake.canvas()
    local original = validBands()
    local committed
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return { left = true }
        end,
        geometry = geometry,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        original,
        function(bands)
            committed = bands
        end,
        function() end
    )
    local editor = canvas.canvases[1]
    local tap = calibration.eventTap
    local mouseCallback = editor.mouseCallbackFn
    local working = calibration.workingBands
    calibration.workingBands[1].x = 0.50
    calibration.workingBands[1].y = 0.30
    editor:triggerMouse("mouseDown", 30, 750)

    test.equal(committed == original, false)
    test.rect(committed[1], { x = 0.50, y = 0.30, w = 0.20, h = 0.50 })
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
    test.equal(tap.stopCount, 1)
    test.equal(editor.deleteCount, 1)
    mouseCallback(editor, "mouseDown", "background", 500, 400)
    test.equal(tap:emit(tap.eventTypes[2], { x = 520, y = 420 }), false)
    test.rect(working[1], { x = 0.50, y = 0.30, w = 0.20, h = 0.50 })
end)

test.test("Save rejects invalid working bands without callbacks or input mutation", function()
    local canvas = fake.canvas()
    local original = validBands()
    local saveCalls = 0
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        original,
        function()
            saveCalls = saveCalls + 1
        end,
        function() end
    )
    calibration.workingBands[1].w = 0
    local editor = canvas.canvases[1]
    local safe = pcall(function()
        editor:triggerMouse("mouseDown", 30, 750)
    end)

    test.equal(safe, true)
    test.equal(saveCalls, 0)
    test.equal(editor.deleteCount, 0)
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
end)

test.test("Save reports callback failure and keeps the editor state live", function()
    local canvas = fake.canvas()
    local reports = {}
    local received
    local cancelCalls = 0
    local onCancel = function()
        cancelCalls = cancelCalls + 1
    end
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
        reportError = function(message)
            reports[#reports + 1] = message
        end,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        validBands(),
        function(snapshot)
            received = snapshot
            snapshot[1].x = 0
            error("save failed", 0)
        end,
        onCancel
    )
    local editor = canvas.canvases[1]
    local tap = calibration.eventTap
    local working = calibration.workingBands
    local saved, saveError = calibration:save()

    test.equal(saved, nil)
    test.equal(saveError, "save failed")
    test.equal(received == working, false)
    test.equal(reports[1], "save failed")
    test.equal(calibration.editorCanvas, editor)
    test.equal(calibration.eventTap, tap)
    test.equal(calibration.workingBands, working)
    test.equal(calibration.onCancel, onCancel)
    test.equal(type(editor.mouseCallbackFn), "function")
    test.equal(editor.deleteCount, 0)
    test.equal(tap.stopCount, 0)
    test.equal(tap:isEnabled(), true)
    test.rect(working[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
    calibration:cancel()
    test.equal(cancelCalls, 1)
end)

test.test("Save contains reportError failures and preserves the callback error", function()
    local canvas = fake.canvas()
    local reportCalls = 0
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
        reportError = function()
            reportCalls = reportCalls + 1
            error("report failed", 0)
        end,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        validBands(),
        function()
            error("save failed", 0)
        end,
        function() end
    )
    local safe, saved, saveError = pcall(function()
        return calibration:save()
    end)

    test.equal(safe, true)
    test.equal(saved, nil)
    test.equal(saveError, "save failed")
    test.equal(reportCalls, 1)
    test.equal(calibration.editorCanvas, canvas.canvases[1])
    test.equal(canvas.canvases[1].deleteCount, 0)
end)

test.test("start rejects non-function save and cancel callbacks before allocation", function()
    local function attempt(onSave, onCancel)
        local canvas = fake.canvas()
        local calibration = newCalibration({
            canvas = canvas,
            chooser = fake.chooser(),
            screens = function()
                return {}
            end,
            mouseButtons = function()
                return {}
            end,
            geometry = geometry,
        })
        local started, startError = calibration:start(
            fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
            validBands(),
            onSave,
            onCancel
        )
        return started, startError, #canvas.constructorFrames
    end

    local saveStarted, saveError, saveConstructions = attempt(nil, function() end)
    local cancelStarted, cancelError, cancelConstructions = attempt(function() end, nil)

    test.equal(saveStarted, nil)
    test.equal(type(saveError), "string")
    test.equal(saveConstructions, 0)
    test.equal(cancelStarted, nil)
    test.equal(type(cancelError), "string")
    test.equal(cancelConstructions, 0)
end)

test.test("Cancel discards working changes and calls only onCancel", function()
    local canvas = fake.canvas()
    local original = validBands()
    local saveCalls = 0
    local cancelCalls = 0
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return { left = true }
        end,
        geometry = geometry,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        original,
        function()
            saveCalls = saveCalls + 1
        end,
        function()
            cancelCalls = cancelCalls + 1
        end
    )
    local editor = canvas.canvases[1]
    local tap = calibration.eventTap
    local mouseCallback = editor.mouseCallbackFn
    local working = calibration.workingBands
    calibration.workingBands[1].x = 0.50
    calibration.workingBands[1].y = 0.30
    editor:triggerMouse("mouseDown", 150, 750)

    test.equal(saveCalls, 0)
    test.equal(cancelCalls, 1)
    test.equal(editor.deleteCount, 1)
    test.equal(tap.stopCount, 1)
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
    mouseCallback(editor, "mouseDown", "background", 500, 400)
    test.equal(tap:emit(tap.eventTypes[2], { x = 520, y = 420 }), false)
    test.rect(working[1], { x = 0.50, y = 0.30, w = 0.20, h = 0.50 })
end)

test.test("stop deletes chooser and canvas and clears callbacks idempotently", function()
    local canvas = fake.canvas()
    local chooser = fake.chooser()
    local eventtap = fake.eventtap()
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    local calibration = newCalibration({
        canvas = canvas,
        chooser = chooser,
        eventtap = eventtap,
        screens = function()
            return { screen }
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    calibration:selectScreen(function() end)
    calibration:start(screen, validBands(), function() end, function() end)
    calibration:stop()
    calibration:stop()

    test.equal(chooser.choosers[1].deleteCount, 1)
    test.equal(canvas.canvases[1].mouseCallbackCallCount, 2)
    test.equal(canvas.canvases[1].mouseCallbackFn, nil)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(eventtap.taps[1].stopCount, 1)
    test.equal(calibration.eventTap, nil)
    test.equal(calibration.workingBands, nil)
end)

test.test("start rejects invalid bands without construction or input mutation", function()
    local canvas = fake.canvas()
    local invalid = validBands()
    invalid[1].w = 0
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    local started, startError = calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        invalid,
        function() end,
        function() end
    )

    test.equal(started, nil)
    test.equal(type(startError), "string")
    test.equal(#canvas.constructorFrames, 0)
    test.equal(invalid[1].w, 0)
end)

test.test("start contains draw failures and cleans the partial editor", function()
    local canvas = fake.canvas()
    local original = validBands()
    local failingGeometry = {
        localBands = function()
            error("local conversion failed", 0)
        end,
    }
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = failingGeometry,
    })

    local safe, started, startError = pcall(function()
        return calibration:start(
            fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
            original,
            function() end,
            function() end
        )
    end)

    test.equal(safe, true)
    test.equal(started, nil)
    test.equal(startError, "local conversion failed")
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(canvas.canvases[1].mouseCallbackFn, nil)
    test.equal(calibration.editorCanvas, nil)
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
end)

local function replacementFailure(method)
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local saveCalls = 0
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return { left = true }
        end,
        geometry = geometry,
    })
    local firstScreen = fake.screen("first", "First", { x = 0, y = 0, w = 1000, h = 800 })
    local replacementScreen = fake.screen("second", "Second", { x = 1000, y = 0, w = 1200, h = 1200 })
    calibration:start(firstScreen, validBands(), function()
        saveCalls = saveCalls + 1
    end, function() end)
    local oldCanvas = calibration.editorCanvas
    local oldCallback = oldCanvas.mouseCallbackFn
    local oldTap = calibration.eventTap
    local oldBands = calibration.workingBands
    local oldSaveFrame = calibration.saveFrame
    local oldCancelFrame = calibration.cancelFrame

    if method == "construction" then
        canvas.failConstructorAt = 2
    else
        canvas.failMethod = method
        canvas.failMethodAt = 2
    end
    local started, startError = calibration:start(
        replacementScreen,
        {
            { x = 0.10, y = 0.10, w = 0.20, h = 0.20 },
            { x = 0.40, y = 0.40, w = 0.10, h = 0.20 },
            { x = 0.70, y = 0.70, w = 0.10, h = 0.20 },
        },
        function() end,
        function() end
    )

    test.equal(started, nil)
    local expectedError = method == "construction"
        and "canvas construction failed"
        or method .. " failure"
    test.equal(startError, expectedError)
    test.equal(calibration.editorCanvas, oldCanvas)
    test.equal(calibration.eventTap, oldTap)
    test.equal(oldCanvas.mouseCallbackFn, oldCallback)
    test.equal(calibration.workingBands, oldBands)
    test.equal(calibration.saveFrame, oldSaveFrame)
    test.equal(calibration.cancelFrame, oldCancelFrame)
    test.equal(oldCanvas.deleteCount, 0)
    local replacementCanvas = canvas.canvases[2]
    if replacementCanvas then
        test.equal(replacementCanvas.deleteCount, 1)
        test.equal(replacementCanvas.mouseCallbackFn, nil)
    end
    local replacementTap = eventtap.taps[2]
    if replacementTap then
        test.equal(replacementTap.stopCount, 1)
    end
    test.equal(oldTap.stopCount, 0)
    test.equal(oldTap:isEnabled(), true)
    assertActiveMovement(calibration, oldCanvas, oldTap, eventtap.event.types)
    oldCanvas:triggerMouse("mouseDown", 30, 750)
    test.equal(saveCalls, 1)
end

test.test("failed replacement show keeps the committed editor live", function()
    replacementFailure("show")
end)

test.test("failed replacement construction keeps the committed editor live", function()
    replacementFailure("construction")
end)

test.test("failed replacement callback setup keeps the committed editor live", function()
    replacementFailure("mouseCallback")
end)

test.test("failed replacement level keeps the committed editor live", function()
    replacementFailure("level")
end)

test.test("failed replacement click activation keeps the committed editor live", function()
    replacementFailure("clickActivating")
end)

test.test("failed replacement mouse-event setup keeps the committed editor live", function()
    replacementFailure("canvasMouseEvents")
end)

test.test("a rejected commit guard cleans only the prepared candidate", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local oldCanvas = calibration.editorCanvas
    local oldTap = calibration.eventTap
    local oldBands = calibration.workingBands

    local started, startError = calibration:start(
        screen,
        validBands(),
        function() end,
        function() end,
        function()
            return false
        end
    )

    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(canvas.canvases[2].showCount, 1)
    test.equal(canvas.canvases[2].deleteCount, 1)
    test.equal(eventtap.taps[2].stopCount, 1)
    test.equal(eventtap.taps[2]:isEnabled(), false)
    test.equal(calibration.editorCanvas, oldCanvas)
    test.equal(calibration.eventTap, oldTap)
    test.equal(calibration.workingBands, oldBands)
    test.equal(oldCanvas.deleteCount, 0)
    test.equal(oldTap.stopCount, 0)
    test.equal(oldTap:isEnabled(), true)
    assertActiveMovement(calibration, oldCanvas, oldTap, eventtap.event.types)
end)

test.test("a throwing commit guard is contained and preserves active input", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local oldCanvas = calibration.editorCanvas
    local oldTap = calibration.eventTap

    local safe, started, startError = pcall(function()
        return calibration:start(
            screen,
            validBands(),
            function() end,
            function() end,
            function()
                error("commit guard failure", 0)
            end
        )
    end)

    test.equal(safe, true)
    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(canvas.canvases[2].deleteCount, 1)
    test.equal(eventtap.taps[2].stopCount, 1)
    test.equal(calibration.editorCanvas, oldCanvas)
    test.equal(calibration.eventTap, oldTap)
    test.equal(oldCanvas.deleteCount, 0)
    test.equal(oldTap.stopCount, 0)
    test.equal(oldTap:isEnabled(), true)
end)

test.test("stop during commit guard supersedes the pending editor", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })

    local started, startError = calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        validBands(),
        function() end,
        function() end,
        function()
            calibration:stop()
            return true
        end
    )

    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(calibration.session, nil)
    test.equal(calibration.editorCanvas, nil)
    test.equal(calibration.eventTap, nil)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(eventtap.taps[1].stopCount, 1)
end)

test.test("stop during candidate show supersedes the pending editor", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local realNew = canvas.new
    canvas.new = function(frame)
        local editor = realNew(frame)
        local realShow = editor.show
        editor.show = function(self)
            local result = realShow(self)
            calibration:stop()
            return result
        end
        return editor
    end

    local started, startError = calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        validBands(),
        function() end,
        function() end
    )

    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(calibration.session, nil)
    test.equal(calibration.editorCanvas, nil)
    test.equal(calibration.eventTap, nil)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(eventtap.taps[1].stopCount, 1)
    test.equal(eventtap.taps[1]:isEnabled(), false)
end)

test.test("cancel during candidate show supersedes the pending editor", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local realNew = canvas.new
    canvas.new = function(frame)
        local editor = realNew(frame)
        local realShow = editor.show
        editor.show = function(self)
            local result = realShow(self)
            calibration:cancel()
            return result
        end
        return editor
    end

    local started, startError = calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        validBands(),
        function() end,
        function() end
    )

    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(calibration.session, nil)
    test.equal(calibration.editorCanvas, nil)
    test.equal(calibration.eventTap, nil)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(eventtap.taps[1].stopCount, 1)
    test.equal(eventtap.taps[1]:isEnabled(), false)
end)

test.test("Save during first candidate show supersedes the pending editor", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local realNew = canvas.new
    local saveResult
    local saveError
    canvas.new = function(frame)
        local editor = realNew(frame)
        local realShow = editor.show
        editor.show = function(self)
            local result = realShow(self)
            saveResult, saveError = calibration:save()
            return result
        end
        return editor
    end

    local started, startError = calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        validBands(),
        function() end,
        function() end
    )

    test.equal(saveResult, nil)
    test.equal(saveError, "calibration requires three bands")
    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(calibration.session, nil)
    test.equal(calibration.editorCanvas, nil)
    test.equal(calibration.eventTap, nil)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(eventtap.taps[1].stopCount, 1)
end)

test.test("failed Save during candidate show supersedes only the candidate", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function()
        error("save failure", 0)
    end, function() end)
    local oldCanvas = calibration.editorCanvas
    local oldTap = calibration.eventTap
    local realNew = canvas.new
    local saveResult
    local saveError
    canvas.new = function(frame)
        local editor = realNew(frame)
        if #canvas.canvases == 2 then
            local realShow = editor.show
            editor.show = function(self)
                local result = realShow(self)
                saveResult, saveError = calibration:save()
                return result
            end
        end
        return editor
    end

    local started, startError = calibration:start(
        screen,
        validBands(),
        function() end,
        function() end
    )

    test.equal(saveResult, nil)
    test.equal(saveError, "save failure")
    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(calibration.editorCanvas, oldCanvas)
    test.equal(calibration.eventTap, oldTap)
    test.equal(oldCanvas.deleteCount, 0)
    test.equal(oldTap.stopCount, 0)
    test.equal(oldTap:isEnabled(), true)
    test.equal(canvas.canvases[2].deleteCount, 1)
    test.equal(eventtap.taps[2].stopCount, 1)
end)

test.test("saving the prior session during candidate show supersedes replacement", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    local saveCalls = 0
    calibration:start(screen, validBands(), function()
        saveCalls = saveCalls + 1
    end, function() end)
    local realNew = canvas.new
    canvas.new = function(frame)
        local editor = realNew(frame)
        if #canvas.canvases == 2 then
            local realShow = editor.show
            editor.show = function(self)
                local result = realShow(self)
                calibration:save()
                return result
            end
        end
        return editor
    end

    local started, startError = calibration:start(
        screen,
        validBands(),
        function() end,
        function() end
    )

    test.equal(started, nil)
    test.equal(startError, "calibration start superseded")
    test.equal(saveCalls, 1)
    test.equal(calibration.session, nil)
    test.equal(calibration.editorCanvas, nil)
    test.equal(calibration.eventTap, nil)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(eventtap.taps[1].stopCount, 1)
    test.equal(canvas.canvases[2].deleteCount, 1)
    test.equal(eventtap.taps[2].stopCount, 1)
end)

test.test("successful replacement retires old input and rejects its captured callbacks", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local oldCanvas = canvas.canvases[1]
    local oldMouseCallback = oldCanvas.mouseCallbackFn
    local oldTap = eventtap.taps[1]

    calibration:start(screen, validBands(), function() end, function() end)

    test.equal(oldTap.stopCount, 1)
    test.equal(oldCanvas.deleteCount, 1)
    oldMouseCallback(oldCanvas, "mouseDown", "background", 500, 400)
    test.equal(calibration.drag, nil)

    local newCanvas = canvas.canvases[2]
    local newTap = eventtap.taps[2]
    newCanvas:triggerMouse("mouseDown", 500, 400)
    local before = calibration.workingBands[1]
    local oldResult = oldTap:emit(eventtap.event.types.leftMouseDragged, { x = 520, y = 420 })
    test.equal(oldResult, false)
    test.equal(calibration.workingBands[1], before)
    local newResult = newTap:emit(eventtap.event.types.leftMouseDragged, { x = 520, y = 420 })
    test.equal(newResult, false)
    test.equal(calibration.workingBands[1] == before, false)
end)

test.test("replacement commit survives prior tap-stop and canvas-delete failures", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local oldCanvas = canvas.canvases[1]
    local oldTap = eventtap.taps[1]
    eventtap.failMethod = "stop"
    canvas.failMethod = "delete"

    local safe, started = pcall(function()
        return calibration:start(screen, validBands(), function() end, function() end)
    end)

    test.equal(safe, true)
    test.equal(started, true)
    test.equal(calibration.editorCanvas, canvas.canvases[2])
    test.equal(calibration.eventTap, eventtap.taps[2])
    test.equal(oldTap.stopCount, 1)
    test.equal(oldCanvas.deleteCount, 1)
    test.equal(eventtap.taps[2].stopCount, 0)
    test.equal(canvas.canvases[2].deleteCount, 0)
    assertActiveMovement(
        calibration,
        canvas.canvases[2],
        eventtap.taps[2],
        eventtap.event.types
    )
end)

test.test("candidate staging leaves the active session live and candidate callbacks dormant", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local oldToken = calibration.sessionToken
    local oldBands = calibration.workingBands
    local oldMouseCallback = canvas.canvases[1].mouseCallbackFn
    local oldTap = eventtap.taps[1]
    local originalNew = eventtap.new
    eventtap.new = function(eventTypes, callback)
        local tap = originalNew(eventTypes, callback)
        if #eventtap.newCalls == 2 then
            local candidateCanvas = canvas.canvases[2]
            candidateCanvas.mouseCallbackFn(candidateCanvas, "mouseDown", "background", 500, 400)
            tap:emit(eventtap.event.types.leftMouseDragged, { x = 520, y = 420 })
            oldMouseCallback(canvas.canvases[1], "mouseDown", "background", 500, 400)
            oldTap:emit(eventtap.event.types.leftMouseDragged, { x = 520, y = 420 })
        end
        return tap
    end

    calibration:start(screen, validBands(), function() end, function() end)

    test.equal(calibration.sessionToken > oldToken, true)
    rectNear(oldBands[1], { x = 0.42, y = 0.275, w = 0.20, h = 0.50 })
    test.rect(calibration.workingBands[1], validBands()[1])
    test.equal(calibration.drag, nil)
end)

test.test("Save does not stop a replacement started reentrantly by onSave", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function()
        calibration:start(screen, validBands(), function() end, function() end)
    end, function() end)

    local saved = calibration:save()

    test.equal(saved, true)
    test.equal(calibration.editorCanvas, canvas.canvases[2])
    test.equal(calibration.eventTap, eventtap.taps[2])
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(eventtap.taps[1].stopCount, 1)
    test.equal(canvas.canvases[2].deleteCount, 0)
    test.equal(eventtap.taps[2].stopCount, 0)
end)

test.test("stop teardown retains a replacement started by the old tap", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local oldSession = calibration.session
    local oldCanvas = calibration.editorCanvas
    local oldTap = calibration.eventTap
    local replacementStarted
    local replacementError
    local replacementSession
    eventtap.stopHook = function(tap)
        if tap == oldTap then
            eventtap.stopHook = nil
            replacementStarted, replacementError = calibration:start(
                screen,
                validBands(),
                function() end,
                function() end
            )
            replacementSession = calibration.session
        end
    end

    calibration:stop()

    test.equal(replacementStarted, true)
    test.equal(replacementError, nil)
    test.equal(replacementSession == oldSession, false)
    test.equal(calibration.session, replacementSession)
    test.equal(calibration.sessionToken, replacementSession.token)
    test.equal(calibration.editorCanvas, canvas.canvases[2])
    test.equal(calibration.eventTap, eventtap.taps[2])
    test.equal(oldCanvas.deleteCount, 1)
    test.equal(oldTap.stopCount, 1)
    test.equal(oldTap:isEnabled(), false)
    test.equal(canvas.canvases[2].deleteCount, 0)
    test.equal(eventtap.taps[2].stopCount, 0)
    test.equal(eventtap.taps[2]:isEnabled(), true)
    assertActiveMovement(
        calibration,
        canvas.canvases[2],
        eventtap.taps[2],
        eventtap.event.types
    )
end)

test.test("stop teardown retains a replacement started by old canvas deletion", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    calibration:start(screen, validBands(), function() end, function() end)
    local oldSession = calibration.session
    local oldCanvas = calibration.editorCanvas
    local oldTap = calibration.eventTap
    local replacementStarted
    local replacementError
    local replacementSession
    canvas.deleteHook = function(editor)
        if editor == oldCanvas then
            canvas.deleteHook = nil
            replacementStarted, replacementError = calibration:start(
                screen,
                validBands(),
                function() end,
                function() end
            )
            replacementSession = calibration.session
        end
    end

    calibration:stop()

    test.equal(replacementStarted, true)
    test.equal(replacementError, nil)
    test.equal(replacementSession == oldSession, false)
    test.equal(calibration.session, replacementSession)
    test.equal(calibration.sessionToken, replacementSession.token)
    test.equal(calibration.editorCanvas, canvas.canvases[2])
    test.equal(calibration.eventTap, eventtap.taps[2])
    test.equal(oldCanvas.deleteCount, 1)
    test.equal(oldTap.stopCount, 1)
    test.equal(oldTap:isEnabled(), false)
    test.equal(canvas.canvases[2].deleteCount, 0)
    test.equal(eventtap.taps[2].stopCount, 0)
    test.equal(eventtap.taps[2]:isEnabled(), true)
    assertActiveMovement(
        calibration,
        canvas.canvases[2],
        eventtap.taps[2],
        eventtap.event.types
    )
end)

test.test("stop invalidates input before resilient ordered teardown", function()
    local canvas = fake.canvas()
    local eventtap = fake.eventtap()
    local calibration = newCalibration({
        canvas = canvas,
        chooser = fake.chooser(),
        eventtap = eventtap,
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return {}
        end,
        geometry = geometry,
    })
    local fullFrame = { x = 0, y = 0, w = 1000, h = 800 }
    calibration:start(
        fake.screen("display", "Display", fullFrame),
        validBands(),
        function() end,
        function() end
    )
    local editor = canvas.canvases[1]
    local tap = eventtap.taps[1]
    local bands = calibration.workingBands
    local mouseCallback = editor.mouseCallbackFn
    local tapSnapshot
    local deleteSnapshot
    local originalTapStop = tap.stop
    tap.stop = function(self)
        tapSnapshot = {
            token = calibration.sessionToken,
            session = calibration.session,
            eventTap = calibration.eventTap,
            editorCanvas = calibration.editorCanvas,
            fullFrame = calibration.fullFrame,
            workingBands = calibration.workingBands,
        }
        return originalTapStop(self)
    end
    local originalDelete = editor.delete
    editor.delete = function(self)
        deleteSnapshot = {
            session = calibration.session,
            editorCanvas = calibration.editorCanvas,
            fullFrame = calibration.fullFrame,
            workingBands = calibration.workingBands,
            onSave = calibration.onSave,
            onCancel = calibration.onCancel,
            drag = calibration.drag,
            saveFrame = calibration.saveFrame,
            cancelFrame = calibration.cancelFrame,
            mouseCallback = self.mouseCallbackFn,
        }
        return originalDelete(self)
    end
    eventtap.failMethod = "stop"
    canvas.failMethod = "delete"

    local firstSafe = pcall(function()
        calibration:stop()
    end)
    local secondSafe = pcall(function()
        calibration:stop()
    end)

    test.equal(firstSafe, true)
    test.equal(secondSafe, true)
    test.equal(tapSnapshot.token, nil)
    test.equal(tapSnapshot.session, nil)
    test.equal(tapSnapshot.eventTap, nil)
    test.equal(tapSnapshot.editorCanvas, nil)
    test.equal(tapSnapshot.fullFrame, nil)
    test.equal(tapSnapshot.workingBands, nil)
    test.equal(deleteSnapshot.session, nil)
    test.equal(deleteSnapshot.editorCanvas, nil)
    test.equal(deleteSnapshot.fullFrame, nil)
    test.equal(deleteSnapshot.workingBands, nil)
    test.equal(deleteSnapshot.onSave, nil)
    test.equal(deleteSnapshot.onCancel, nil)
    test.equal(deleteSnapshot.drag, nil)
    test.equal(deleteSnapshot.saveFrame, nil)
    test.equal(deleteSnapshot.cancelFrame, nil)
    test.equal(deleteSnapshot.mouseCallback, nil)
    test.equal(tap.stopCount, 1)
    test.equal(editor.deleteCount, 1)
    mouseCallback(editor, "mouseDown", "background", 500, 400)
    test.equal(tap:emit(eventtap.event.types.leftMouseDragged, { x = 520, y = 420 }), false)
    test.rect(bands[1], validBands()[1])
end)
