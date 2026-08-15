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
    local callbackResult = tap:emit(eventtap.event.types.mouseMoved, { x = 10, y = 20 })
    test.equal(callbackResult, false)
    test.equal(tap.callbackResults[1], false)
end)

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
    calibration.workingBands[1].x = 0.50
    calibration.workingBands[1].y = 0.30
    editor:triggerMouse("mouseDown", 30, 750)

    test.equal(committed == original, false)
    test.rect(committed[1], { x = 0.50, y = 0.30, w = 0.20, h = 0.50 })
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
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
    local working = calibration.workingBands
    local saved, saveError = calibration:save()

    test.equal(saved, nil)
    test.equal(saveError, "save failed")
    test.equal(received == working, false)
    test.equal(reports[1], "save failed")
    test.equal(calibration.editorCanvas, editor)
    test.equal(calibration.workingBands, working)
    test.equal(calibration.onCancel, onCancel)
    test.equal(type(editor.mouseCallbackFn), "function")
    test.equal(editor.deleteCount, 0)
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
    calibration.workingBands[1].x = 0.50
    calibration.workingBands[1].y = 0.30
    editor:triggerMouse("mouseDown", 150, 750)

    test.equal(saveCalls, 0)
    test.equal(cancelCalls, 1)
    test.equal(editor.deleteCount, 1)
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
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
    local saveCalls = 0
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
    local firstScreen = fake.screen("first", "First", { x = 0, y = 0, w = 1000, h = 800 })
    local replacementScreen = fake.screen("second", "Second", { x = 1000, y = 0, w = 1200, h = 1200 })
    calibration:start(firstScreen, validBands(), function()
        saveCalls = saveCalls + 1
    end, function() end)
    local oldCanvas = calibration.editorCanvas
    local oldCallback = oldCanvas.mouseCallbackFn
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
    test.rect(oldBands[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
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
