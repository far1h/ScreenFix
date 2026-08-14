local Calibration = require("screenfix.calibration")
local fake = require("tests.fake_hs")
local geometry = require("screenfix.geometry")
local test = require("tests.test_helper")

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
    local calibration = Calibration.new({
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
    local calibration = Calibration.new({
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
    local calibration = Calibration.new({
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
    local calibration = Calibration.new({
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
    canvas.canvases[1]:triggerMouse("mouseDown", 1376, 360)
    test.equal(calibration.drag.index, 1)
    test.equal(calibration.drag.part, "left")
end)

test.test("start tracks mouse events across the full local background", function()
    local canvas = fake.canvas()
    local fullFrame = { x = -3440, y = -200, w = 3440, h = 1440 }
    local calibration = Calibration.new({
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
    test.equal(background.trackMouseUp, true)
    test.equal(background.trackMouseMove, true)
    test.equal(type(editor.mouseCallbackFn), "function")
    test.equal(editor.clickActivatingCalls[1], true)
    local events = editor.canvasMouseEventsCalls[1]
    test.equal(events.down, true)
    test.equal(events.up, true)
    test.equal(events.enterExit, false)
    test.equal(events.move, true)
end)

test.test("draw renders three black bands, edge handles, and fixed controls", function()
    local canvas = fake.canvas()
    local calibration = Calibration.new({
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
    test.equal(#elements, 20)
    for index = 2, 4 do
        test.equal(elements[index].fillColor.white, 0)
        test.equal(elements[index].fillColor.alpha, 1)
    end
    for index = 5, 16 do
        test.equal(elements[index].fillColor.white, 1)
        test.equal(elements[index].trackMouseDown, nil)
    end
    test.rect(elements[17].frame, { x = 24, y = 736, w = 96, h = 40 })
    test.equal(elements[18].text, "Save")
    test.rect(elements[19].frame, { x = 144, y = 736, w = 96, h = 40 })
    test.equal(elements[20].text, "Cancel")
end)

test.test("mouse movement updates a copied band from successive local positions", function()
    local canvas = fake.canvas()
    local buttons = { left = true }
    local saved = validBands()
    local calibration = Calibration.new({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return buttons
        end,
        geometry = geometry,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 100, y = 50, w = 1000, h = 800 }),
        saved,
        function() end,
        function() end
    )

    local editor = canvas.canvases[1]
    editor:triggerMouse("mouseDown", 500, 400)
    editor:triggerMouse("mouseMove", 600, 440)
    editor:triggerMouse("mouseMove", 650, 480)

    test.rect(calibration.workingBands[1], { x = 0.55, y = 0.35, w = 0.20, h = 0.50 })
    test.rect(saved[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
    test.rect(editor.elements[2].frame, { x = 550, y = 280, w = 200, h = 400 })
    editor:triggerMouse("mouseUp", 650, 480)
    test.equal(calibration.drag, nil)
end)

test.test("mouse movement does not update without the left button", function()
    local canvas = fake.canvas()
    local calibration = Calibration.new({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return { left = false }
        end,
        geometry = geometry,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        validBands(),
        function() end,
        function() end
    )
    local editor = canvas.canvases[1]
    editor:triggerMouse("mouseDown", 500, 400)
    editor:triggerMouse("mouseMove", 600, 440)

    test.rect(calibration.workingBands[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
end)

test.test("mouse movement contains geometry failures without mutating saved input", function()
    local canvas = fake.canvas()
    local original = validBands()
    local failingGeometry = {
        localBands = geometry.localBands,
        editorHit = geometry.editorHit,
        dragBand = function()
            error("drag failed", 0)
        end,
    }
    local calibration = Calibration.new({
        canvas = canvas,
        chooser = fake.chooser(),
        screens = function()
            return {}
        end,
        mouseButtons = function()
            return { left = true }
        end,
        geometry = failingGeometry,
    })

    calibration:start(
        fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 }),
        original,
        function() end,
        function() end
    )
    local editor = canvas.canvases[1]
    editor:triggerMouse("mouseDown", 500, 400)
    local safe = pcall(function()
        editor:triggerMouse("mouseMove", 600, 440)
    end)

    test.equal(safe, true)
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
    test.rect(calibration.workingBands[1], original[1])
end)

test.test("Save validates and commits the copied working bands", function()
    local canvas = fake.canvas()
    local original = validBands()
    local committed
    local calibration = Calibration.new({
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
    editor:triggerMouse("mouseDown", 500, 400)
    editor:triggerMouse("mouseMove", 600, 440)
    editor:triggerMouse("mouseUp", 600, 440)
    editor:triggerMouse("mouseDown", 30, 750)

    test.equal(committed == original, false)
    test.rect(committed[1], { x = 0.50, y = 0.30, w = 0.20, h = 0.50 })
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
end)

test.test("Save rejects invalid working bands without callbacks or input mutation", function()
    local canvas = fake.canvas()
    local original = validBands()
    local saveCalls = 0
    local calibration = Calibration.new({
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

test.test("Cancel discards working changes and calls only onCancel", function()
    local canvas = fake.canvas()
    local original = validBands()
    local saveCalls = 0
    local cancelCalls = 0
    local calibration = Calibration.new({
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
    editor:triggerMouse("mouseDown", 500, 400)
    editor:triggerMouse("mouseMove", 600, 440)
    editor:triggerMouse("mouseUp", 600, 440)
    editor:triggerMouse("mouseDown", 150, 750)

    test.equal(saveCalls, 0)
    test.equal(cancelCalls, 1)
    test.equal(editor.deleteCount, 1)
    test.rect(original[1], { x = 0.40, y = 0.25, w = 0.20, h = 0.50 })
end)

test.test("stop deletes chooser and canvas and clears callbacks idempotently", function()
    local canvas = fake.canvas()
    local chooser = fake.chooser()
    local screen = fake.screen("display", "Display", { x = 0, y = 0, w = 1000, h = 800 })
    local calibration = Calibration.new({
        canvas = canvas,
        chooser = chooser,
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
    test.equal(calibration.workingBands, nil)
end)

test.test("start rejects invalid bands without construction or input mutation", function()
    local canvas = fake.canvas()
    local invalid = validBands()
    invalid[1].w = 0
    local calibration = Calibration.new({
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
    local calibration = Calibration.new({
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
