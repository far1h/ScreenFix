local WindowGuard = require("screenfix.window_guard")
local fake = require("tests.fake_hs")
local geometry = require("screenfix.geometry")
local test = require("tests.test_helper")

local function eligibilityCase(overrides)
    local selectedScreen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local options = {
        id = 42,
        frame = { x = 350, y = 100, w = 500, h = 400 },
        screen = selectedScreen,
    }

    for key, value in pairs(overrides or {}) do
        options[key] = value
    end

    local guard = WindowGuard.new({})
    guard:start(selectedScreen, {})
    return guard, fake.window(options)
end

test.test("window guard module loads", function()
    test.equal(type(WindowGuard), "table")
end)

test.test("start stores the selected screen and mask rectangles", function()
    local guard = WindowGuard.new({})
    local screen = {}
    local maskRects = {
        { x = 400, y = 0, w = 300, h = 800 },
    }

    guard:start(screen, maskRects)

    test.equal(guard.selectedScreen, screen)
    test.equal(guard.maskRects, maskRects)
end)

test.test("stop idempotently clears target and cooldown state", function()
    local guard = WindowGuard.new({})
    guard:start({}, { {} })
    guard.pending[1] = true
    guard.recent[1] = true
    guard.blockedUntil[1] = 10

    guard:stop()
    guard:stop()

    test.equal(guard.selectedScreen, nil)
    test.equal(#guard.maskRects, 0)
    test.equal(next(guard.pending), nil)
    test.equal(next(guard.recent), nil)
    test.equal(next(guard.blockedUntil), nil)
end)

test.test("isEligible accepts a normal visible window on the selected screen", function()
    local guard, window = eligibilityCase()

    test.equal(guard:isEligible(window), true)
end)

test.test("isEligible rejects a full-screen window", function()
    local guard, window = eligibilityCase({ isFullScreen = true })

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible rejects a minimized window", function()
    local guard, window = eligibilityCase({ isMinimized = true })

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible rejects a hidden window", function()
    local guard, window = eligibilityCase({ isVisible = false })

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible rejects a nonstandard window", function()
    local guard, window = eligibilityCase({ isStandard = false })

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible rejects a window on another screen", function()
    local guard, window = eligibilityCase({
        screen = fake.screen("other", "Other Display", {
            x = 1200,
            y = 0,
            w = 1200,
            h = 800,
        }),
    })

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible treats a nil window as ineligible without throwing", function()
    local guard = WindowGuard.new({})
    guard:start(fake.screen("selected", "Display", {}), {})

    local ok, result = pcall(function()
        return guard:isEligible(nil)
    end)

    test.equal(ok, true)
    test.equal(result, false)
end)

test.test("isEligible treats a missing selected screen as ineligible without throwing", function()
    local guard, window = eligibilityCase()
    guard.selectedScreen = nil

    local ok, result = pcall(function()
        return guard:isEligible(window)
    end)

    test.equal(ok, true)
    test.equal(result, false)
end)

test.test("isEligible treats a missing window id as ineligible", function()
    local guard, window = eligibilityCase({ id = false })
    window.id = function()
        return nil
    end

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible treats a missing window frame as ineligible", function()
    local guard, window = eligibilityCase()
    window.frame = function()
        return nil
    end

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible treats a missing window screen as ineligible without throwing", function()
    local guard, window = eligibilityCase()
    window.screen = function()
        return nil
    end

    local ok, result = pcall(function()
        return guard:isEligible(window)
    end)

    test.equal(ok, true)
    test.equal(result, false)
end)

test.test("isEligible rejects missing screen UUIDs even when both are nil", function()
    local selectedScreen = fake.screen(nil, "Display", {})
    local guard = WindowGuard.new({})
    guard:start(selectedScreen, {})
    local window = fake.window({
        id = 42,
        frame = { x = 350, y = 100, w = 500, h = 400 },
        screen = fake.screen(nil, "Display", {}),
    })

    test.equal(guard:isEligible(window), false)
end)

test.test("isEligible treats nil eligibility results as ineligible", function()
    for _, methodName in ipairs({
        "isStandard",
        "isVisible",
        "isMinimized",
        "isFullScreen",
    }) do
        local guard, window = eligibilityCase()
        window[methodName] = function()
            return nil
        end

        local ok, result = pcall(function()
            return guard:isEligible(window)
        end)

        test.equal(ok, true)
        test.equal(result, false)
    end
end)

test.test("correct moves an overlapping eligible window to the geometry target", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
    })
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local result = guard:correct(window)

    test.equal(result, true)
    test.equal(#window.setFrameCalls, 1)
    test.rect(window.setFrameCalls[1].frame, {
        x = 700,
        y = 100,
        w = 200,
        h = 400,
    })
    test.equal(window.setFrameCalls[1].duration, 0)
end)

test.test("correct leaves a safe window unchanged", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 42,
        frame = { x = 0, y = 100, w = 300, h = 400 },
        screen = screen,
    })
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local result = guard:correct(window)

    test.equal(result, false)
    test.equal(#window.setFrameCalls, 0)
end)

test.test("correct consumes the recent target when ignoring its own immediate event", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
    })
    local target = { x = 700, y = 100, w = 200, h = 400 }
    local correctedFrameCalls = 0
    local clock = fake.clock(5)
    local guard = WindowGuard.new({
        geometry = {
            correctedFrame = function()
                correctedFrameCalls = correctedFrameCalls + 1
                return target
            end,
            framesNear = geometry.framesNear,
        },
        now = function()
            return clock:now()
        end,
    })
    guard:start(screen, {})

    guard:correct(window)
    test.equal(guard.recent[42].frame, target)
    test.equal(guard.recent[42].expiresAt > clock:now(), true)
    local result = guard:correct(window)

    test.equal(result, false)
    test.equal(correctedFrameCalls, 1)
    test.equal(#window.setFrameCalls, 1)
    test.equal(guard.recent[42], nil)
end)

test.test("correct pauses rejected-frame retries for one second", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
        acceptFrame = false,
    })
    local target = { x = 700, y = 100, w = 200, h = 400 }
    local correctedFrameCalls = 0
    local clock = fake.clock(10)
    local guard = WindowGuard.new({
        geometry = {
            correctedFrame = function()
                correctedFrameCalls = correctedFrameCalls + 1
                return target
            end,
            framesNear = geometry.framesNear,
        },
        now = function()
            return clock:now()
        end,
    })
    guard:start(screen, {})

    test.equal(guard:correct(window), false)
    test.equal(guard:correct(window), false)
    test.equal(#window.setFrameCalls, 1)
    test.equal(correctedFrameCalls, 1)

    clock:advance(1)
    test.equal(guard:correct(window), false)
    test.equal(#window.setFrameCalls, 2)
    test.equal(correctedFrameCalls, 2)
end)

test.test("correct protects setFrame errors and pauses retries", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
        setFrameError = "setFrame rejected",
    })
    local clock = fake.clock(20)
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return clock:now()
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result, message = pcall(function()
        return guard:correct(window)
    end)

    test.equal(ok, true)
    test.equal(result, nil)
    test.equal(type(message), "string")
    test.equal(string.find(message, "setFrame rejected", 1, true) ~= nil, true)
    test.equal(guard.blockedUntil[42], 21)
    test.equal(#window.setFrameCalls, 1)

    test.equal(guard:correct(window), false)
    test.equal(#window.setFrameCalls, 1)
end)

test.test("correct rejects a missing second pre-correction window frame", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local initialFrame = { x = 550, y = 100, w = 200, h = 400 }
    local window = fake.window({
        id = 42,
        frame = initialFrame,
        screen = screen,
    })
    local frameCalls = 0
    window.frame = function()
        frameCalls = frameCalls + 1
        if frameCalls == 1 then
            return initialFrame
        end

        return nil
    end
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result = pcall(function()
        return guard:correct(window)
    end)

    test.equal(ok, true)
    test.equal(result, false)
    test.equal(#window.setFrameCalls, 0)
end)

test.test("correct rejects a missing selected-screen usable frame", function()
    local screen = fake.screen("selected", "Display", {})
    screen.frame = function()
        return nil
    end
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
    })
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result = pcall(function()
        return guard:correct(window)
    end)

    test.equal(ok, true)
    test.equal(result, false)
    test.equal(#window.setFrameCalls, 0)
end)

test.test("correct blocks retries when the post-set window frame is missing", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local initialFrame = { x = 550, y = 100, w = 200, h = 400 }
    local window = fake.window({
        id = 42,
        frame = initialFrame,
        screen = screen,
    })
    local frameCalls = 0
    window.frame = function()
        frameCalls = frameCalls + 1
        if frameCalls <= 2 then
            return initialFrame
        end

        return nil
    end
    local clock = fake.clock(30)
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return clock:now()
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result = pcall(function()
        return guard:correct(window)
    end)

    test.equal(ok, true)
    test.equal(result, false)
    test.equal(guard.blockedUntil[42], 31)
    test.equal(#window.setFrameCalls, 1)
end)

test.test("correct rejects a missing second window id", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
    })
    local idCalls = 0
    window.id = function()
        idCalls = idCalls + 1
        if idCalls == 1 then
            return 42
        end

        return nil
    end
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result, message = pcall(function()
        return guard:correct(window)
    end)

    test.equal(message, nil)
    test.equal(result, false)
    test.equal(ok, true)
    test.equal(#window.setFrameCalls, 0)
end)

test.test("correct contains errors from eligibility-stage Hammerspoon methods", function()
    local cases = {
        {
            name = "window id",
            apply = function(window)
                window.id = function()
                    error("window id failure", 0)
                end
            end,
        },
        {
            name = "window frame",
            apply = function(window)
                window.frame = function()
                    error("window frame failure", 0)
                end
            end,
        },
        {
            name = "window screen",
            apply = function(window)
                window.screen = function()
                    error("window screen failure", 0)
                end
            end,
        },
        {
            name = "selected screen UUID",
            apply = function(_, screen)
                screen.getUUID = function()
                    error("selected UUID failure", 0)
                end
            end,
        },
        {
            name = "window screen UUID",
            apply = function(window)
                window.screen = function()
                    return {
                        getUUID = function()
                            error("window UUID failure", 0)
                        end,
                    }
                end
            end,
        },
        {
            name = "full-screen state",
            apply = function(window)
                window.isFullScreen = function()
                    error("full-screen failure", 0)
                end
            end,
        },
        {
            name = "minimized state",
            apply = function(window)
                window.isMinimized = function()
                    error("minimized failure", 0)
                end
            end,
        },
        {
            name = "visibility state",
            apply = function(window)
                window.isVisible = function()
                    error("visibility failure", 0)
                end
            end,
        },
        {
            name = "standard state",
            apply = function(window)
                window.isStandard = function()
                    error("standard failure", 0)
                end
            end,
        },
    }

    for _, case in ipairs(cases) do
        local screen = fake.screen("selected", "Display", {
            x = 0,
            y = 0,
            w = 1200,
            h = 800,
        })
        local window = fake.window({
            id = 42,
            frame = { x = 550, y = 100, w = 200, h = 400 },
            screen = screen,
        })
        case.apply(window, screen)
        local guard = WindowGuard.new({
            geometry = geometry,
            now = function()
                return 0
            end,
        })
        guard:start(screen, {
            { x = 400, y = 0, w = 300, h = 800 },
        })

        local ok, result = pcall(function()
            return guard:correct(window)
        end)

        if not ok then
            error(case.name .. " escaped correct: " .. tostring(result))
        end
        test.equal(result, false)
        test.equal(#window.setFrameCalls, 0)
    end
end)

test.test("correct contains an error from the second window id read", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
    })
    local idCalls = 0
    window.id = function()
        idCalls = idCalls + 1
        if idCalls == 1 then
            return 42
        end

        error("second window id failure", 0)
    end
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result = pcall(function()
        return guard:correct(window)
    end)

    if not ok then
        error("second window id escaped correct: " .. tostring(result))
    end
    test.equal(result, false)
    test.equal(#window.setFrameCalls, 0)
end)

test.test("correct contains an error from the second pre-correction frame read", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local initialFrame = { x = 550, y = 100, w = 200, h = 400 }
    local window = fake.window({
        id = 42,
        frame = initialFrame,
        screen = screen,
    })
    local frameCalls = 0
    window.frame = function()
        frameCalls = frameCalls + 1
        if frameCalls == 1 then
            return initialFrame
        end

        error("second window frame failure", 0)
    end
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result = pcall(function()
        return guard:correct(window)
    end)

    if not ok then
        error("second window frame escaped correct: " .. tostring(result))
    end
    test.equal(result, false)
    test.equal(#window.setFrameCalls, 0)
end)

test.test("correct contains an error from the selected-screen frame read", function()
    local screen = fake.screen("selected", "Display", {})
    screen.frame = function()
        error("selected screen frame failure", 0)
    end
    local window = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
    })
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return 0
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result = pcall(function()
        return guard:correct(window)
    end)

    if not ok then
        error("selected screen frame escaped correct: " .. tostring(result))
    end
    test.equal(result, false)
    test.equal(#window.setFrameCalls, 0)
end)

test.test("correct blocks retries when the post-set frame read raises", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local initialFrame = { x = 550, y = 100, w = 200, h = 400 }
    local window = fake.window({
        id = 42,
        frame = initialFrame,
        screen = screen,
    })
    local frameCalls = 0
    window.frame = function()
        frameCalls = frameCalls + 1
        if frameCalls <= 2 then
            return initialFrame
        end

        error("post-set window frame failure", 0)
    end
    local clock = fake.clock(40)
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return clock:now()
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })

    local ok, result = pcall(function()
        return guard:correct(window)
    end)

    if not ok then
        error("post-set window frame escaped correct: " .. tostring(result))
    end
    test.equal(result, false)
    test.equal(guard.blockedUntil[42], 41)
    test.equal(#window.setFrameCalls, 1)
end)

test.test("correct prunes expired state for unrelated window ids", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local window = fake.window({
        id = 2000,
        frame = { x = 0, y = 100, w = 300, h = 400 },
        screen = screen,
    })
    local clock = fake.clock(10)
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return clock:now()
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })
    for id = 1, 1000 do
        guard.recent[id] = {
            frame = { x = 700, y = 100, w = 200, h = 400 },
            expiresAt = 10,
        }
        guard.blockedUntil[id] = 10
    end

    test.equal(guard:correct(window), false)

    test.equal(next(guard.recent), nil)
    test.equal(next(guard.blockedUntil), nil)
end)

test.test("correct removes expired state before a window id is reused", function()
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local clock = fake.clock(10)
    local guard = WindowGuard.new({
        geometry = geometry,
        now = function()
            return clock:now()
        end,
    })
    guard:start(screen, {
        { x = 400, y = 0, w = 300, h = 800 },
    })
    guard.recent[42] = {
        frame = { x = 700, y = 100, w = 200, h = 400 },
        expiresAt = 10,
    }
    guard.blockedUntil[42] = 10
    local otherWindow = fake.window({
        id = 99,
        frame = { x = 0, y = 100, w = 300, h = 400 },
        screen = screen,
    })

    guard:correct(otherWindow)

    test.equal(guard.recent[42], nil)
    test.equal(guard.blockedUntil[42], nil)

    local reusedWindow = fake.window({
        id = 42,
        frame = { x = 550, y = 100, w = 200, h = 400 },
        screen = screen,
    })
    test.equal(guard:correct(reusedWindow), true)
    test.equal(#reusedWindow.setFrameCalls, 1)
end)
