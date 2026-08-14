local MaskOverlay = require("screenfix.mask_overlay")
local fake = require("tests.fake_hs")
local test = require("tests.test_helper")

local function keyCount(value)
    local count = 0

    for _ in pairs(value) do
        count = count + 1
    end

    return count
end

local function overlayWithFrames(frames, overrides)
    overrides = overrides or {}
    local canvas = overrides.canvas or fake.canvas()
    local overlay = MaskOverlay.new({
        canvas = canvas,
        geometry = overrides.geometry or {
            absoluteBands = function()
                return frames
            end,
        },
        hideDockIcon = overrides.hideDockIcon or function()
        end,
    })

    return overlay, canvas
end

test.test("new creates an overlay with no canvases", function()
    local overlay = MaskOverlay.new({})

    test.equal(#overlay.canvases, 0)
end)

test.test("show prepares full-screen canvas support once before construction", function()
    local canvas = fake.canvas()
    local prepareCalls = 0
    local overlay = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    }, {
        canvas = canvas,
        hideDockIcon = function()
            prepareCalls = prepareCalls + 1
            test.equal(#canvas.constructorFrames, 0)
        end,
    })

    overlay:show(fake.screen("first", "Display", {}), {})
    overlay:show(fake.screen("second", "Display", {}), {})

    test.equal(prepareCalls, 1)
    test.equal(#canvas.constructorFrames, 6)
end)

test.test("show preserves the existing mask when full-screen preparation fails", function()
    local canvas = fake.canvas()
    local shouldFail = false
    local overlay = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    }, {
        canvas = canvas,
        hideDockIcon = function()
            if shouldFail then
                error("dock icon failure")
            end
        end,
    })
    overlay:show(fake.screen("first", "Display", {}), {})
    local existing = overlay.canvases
    overlay.prepared = false
    shouldFail = true

    local ok, result, message = pcall(function()
        return overlay:show(fake.screen("second", "Display", {}), {})
    end)

    test.equal(ok, true)
    test.equal(result, nil)
    test.equal(type(message), "string")
    test.equal(string.find(message, "dock icon failure", 1, true) ~= nil, true)
    test.equal(overlay.prepared, false)
    test.equal(overlay.canvases, existing)
    test.equal(#canvas.constructorFrames, 3)
    for _, instance in ipairs(existing) do
        test.equal(instance.deleteCount, 0)
        test.equal(instance.deleted, false)
    end
end)

test.test("show returns true after building the mask", function()
    local overlay = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    })

    local result = overlay:show(fake.screen("screen", "Display", {}), {})

    test.equal(result, true)
end)

test.test("show cleans partial canvases when construction fails", function()
    local canvas = fake.canvas()
    canvas.failConstructorAt = 2
    local overlay = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    }, { canvas = canvas })

    local ok, result, message = pcall(function()
        return overlay:show(fake.screen("screen", "Display", {}), {})
    end)

    test.equal(ok, true)
    test.equal(result, nil)
    test.equal(type(message), "string")
    test.equal(#canvas.constructorFrames, 2)
    test.equal(#canvas.canvases, 1)
    test.equal(#overlay.canvases, 0)
    test.equal(canvas.canvases[1].showCount, 1)
    test.equal(canvas.canvases[1].deleteCount, 1)
    test.equal(canvas.canvases[1].deleted, true)
end)

test.test("show cleans allocated canvases when configuration fails", function()
    local canvas = fake.canvas()
    canvas.failMethod = "behavior"
    canvas.failMethodAt = 2
    local overlay = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    }, { canvas = canvas })

    local ok, result, message = pcall(function()
        return overlay:show(fake.screen("screen", "Display", {}), {})
    end)

    test.equal(ok, true)
    test.equal(result, nil)
    test.equal(type(message), "string")
    test.equal(string.find(message, "behavior failure", 1, true) ~= nil, true)
    test.equal(#canvas.constructorFrames, 2)
    test.equal(#canvas.canvases, 2)
    test.equal(#overlay.canvases, 0)
    test.equal(canvas.canvases[1].showCount, 1)
    test.equal(canvas.canvases[2].showCount, 0)
    for _, instance in ipairs(canvas.canvases) do
        test.equal(instance.deleteCount, 1)
        test.equal(instance.deleted, true)
    end
end)

test.test("show fills each canvas with one opaque black rectangle", function()
    local frames = {
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    }
    local overlay, canvas = overlayWithFrames(frames)

    overlay:show(fake.screen("screen", "Display", {}), {})

    for _, instance in ipairs(canvas.canvases) do
        test.equal(#instance.elementAssignments, 1)
        test.equal(instance.elementAssignments[1].index, 1)
        local element = instance[1]
        test.equal(keyCount(element), 4)
        test.equal(element.type, "rectangle")
        test.equal(element.action, "fill")
        test.equal(keyCount(element.fillColor), 2)
        test.equal(element.fillColor.white, 0)
        test.equal(element.fillColor.alpha, 1)
        test.equal(keyCount(element.frame), 4)
        test.equal(element.frame.x, 0)
        test.equal(element.frame.y, 0)
        test.equal(element.frame.w, "100%")
        test.equal(element.frame.h, "100%")
    end
end)

test.test("show configures canvases for persistent click-through display", function()
    local overlay, canvas = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    })

    overlay:show(fake.screen("screen", "Display", {}), {})

    for _, instance in ipairs(canvas.canvases) do
        test.equal(#instance.clickActivatingCalls, 1)
        test.equal(instance.clickActivatingCalls[1], false)
        test.equal(#instance.behaviorCalls, 1)
        local behavior = instance.behaviorCalls[1]
        test.equal(#behavior, 3)
        test.equal(behavior[1], "canJoinAllSpaces")
        test.equal(behavior[2], "fullScreenAuxiliary")
        test.equal(behavior[3], "stationary")
        test.equal(#instance.levelCalls, 1)
        test.equal(instance.levelCalls[1], "screenSaver")
        test.equal(instance.showCount, 1)
    end
end)

test.test("show creates a canvas for each absolute band", function()
    local canvas = fake.canvas()
    local fullFrame = { x = -1000, y = 0, w = 1000, h = 800 }
    local bands = {
        { x = 0.4, y = 0, w = 0.1, h = 0.3 },
        { x = 0.5, y = 0.3, w = 0.1, h = 0.4 },
        { x = 0.6, y = 0.7, w = 0.1, h = 0.3 },
    }
    local frames = {
        { x = -600, y = 0, w = 100, h = 240 },
        { x = -500, y = 240, w = 100, h = 320 },
        { x = -400, y = 560, w = 100, h = 240 },
    }
    local fullFrameCalls = 0
    local geometryCalls = 0
    local screen = {
        fullFrame = function()
            fullFrameCalls = fullFrameCalls + 1
            return fullFrame
        end,
    }
    local geometry = {
        absoluteBands = function(actualFrame, actualBands)
            geometryCalls = geometryCalls + 1
            test.equal(actualFrame, fullFrame)
            test.equal(actualBands, bands)
            return frames
        end,
    }
    local overlay = MaskOverlay.new({
        canvas = canvas,
        geometry = geometry,
        hideDockIcon = function()
        end,
    })

    overlay:show(screen, bands)

    test.equal(fullFrameCalls, 1)
    test.equal(geometryCalls, 1)
    test.equal(#canvas.constructorFrames, 3)
    test.equal(#overlay.canvases, 3)
    for index, frame in ipairs(frames) do
        test.equal(canvas.constructorFrames[index], frame)
        test.equal(overlay.canvases[index], canvas.canvases[index])
    end
end)

test.test("show replaces prior canvases after deleting them", function()
    local canvas = fake.canvas()
    local frames = {
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    }
    local geometry = {
        absoluteBands = function()
            return frames
        end,
    }
    local overlay = MaskOverlay.new({
        canvas = canvas,
        geometry = geometry,
        hideDockIcon = function()
        end,
    })
    overlay:show(fake.screen("first", "Display", {}), {})
    local firstReferences = overlay.canvases

    local secondScreen = fake.screen("second", "Display", {})
    local originalFullFrame = secondScreen.fullFrame
    secondScreen.fullFrame = function()
        for _, instance in ipairs(firstReferences) do
            test.equal(instance.deleted, true)
        end
        return originalFullFrame()
    end
    overlay:show(secondScreen, {})

    test.equal(firstReferences == overlay.canvases, false)
    test.equal(#firstReferences, 3)
    test.equal(#overlay.canvases, 3)
    for index, instance in ipairs(firstReferences) do
        test.equal(instance.deleteCount, 1)
        test.equal(instance.deleted, true)
        test.equal(overlay.canvases[index], canvas.canvases[index + 3])
    end
end)

test.test("hide hides live canvases once", function()
    local overlay, canvas = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    })
    overlay:show(fake.screen("screen", "Display", {}), {})

    overlay:hide()
    overlay:hide()

    test.equal(#overlay.canvases, 3)
    for _, instance in ipairs(canvas.canvases) do
        test.equal(instance.hideCount, 1)
        test.equal(instance.deleteCount, 0)
    end
end)

test.test("delete clears canvases after deleting them once", function()
    local overlay = overlayWithFrames({
        { x = 10, y = 20, w = 30, h = 40 },
        { x = 50, y = 60, w = 70, h = 80 },
        { x = 90, y = 100, w = 110, h = 120 },
    })
    overlay:show(fake.screen("screen", "Display", {}), {})
    local liveCanvases = overlay.canvases

    overlay:delete()
    overlay:delete()

    test.equal(#overlay.canvases, 0)
    test.equal(liveCanvases == overlay.canvases, false)
    for _, instance in ipairs(liveCanvases) do
        test.equal(instance.deleteCount, 1)
        test.equal(instance.deleted, true)
    end
end)
