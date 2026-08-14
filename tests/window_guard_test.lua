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

local function lifecycleCase()
    local filterModule = fake.windowFilter()
    local timer = fake.timer()
    local factoryCalls = 0
    local deps = {
        events = {
            filterModule.windowCreated,
            filterModule.windowMoved,
            filterModule.windowOnScreen,
        },
        filterFactory = function()
            factoryCalls = factoryCalls + 1
            return filterModule.new():setOverrideFilter({
                visible = true,
                fullscreen = false,
                currentSpace = true,
            })
        end,
        timer = timer,
    }
    local screen = fake.screen("selected", "Display", {
        x = 0,
        y = 0,
        w = 1200,
        h = 800,
    })
    local guard = WindowGuard.new(deps)

    return {
        factoryCalls = function()
            return factoryCalls
        end,
        filterModule = filterModule,
        guard = guard,
        screen = screen,
        timer = timer,
    }
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

test.test("start creates and subscribes a local lifecycle filter", function()
    local case = lifecycleCase()

    case.guard:start(case.screen, {})

    test.equal(case.factoryCalls(), 1)
    test.equal(case.filterModule.newCount, 1)
    test.equal(case.guard.filter, case.filterModule.filters[1])
    test.equal(case.guard.filter.override.visible, true)
    test.equal(case.guard.filter.override.fullscreen, false)
    test.equal(case.guard.filter.override.currentSpace, true)
    test.equal(#case.guard.filter.subscribeCalls, 1)
    local events = case.guard.filter.subscribeCalls[1].events
    test.equal(events[1], case.filterModule.windowCreated)
    test.equal(events[2], case.filterModule.windowMoved)
    test.equal(events[3], case.filterModule.windowOnScreen)
end)

test.test("start is idempotent while updating its target", function()
    local case = lifecycleCase()
    local replacementScreen = {}
    local replacementMasks = { {} }

    case.guard:start(case.screen, {})
    case.guard:start(replacementScreen, replacementMasks)

    test.equal(case.factoryCalls(), 1)
    test.equal(#case.guard.filter.subscribeCalls, 1)
    test.equal(case.guard.selectedScreen, replacementScreen)
    test.equal(case.guard.maskRects, replacementMasks)
end)

test.test("start contains factory errors and remains restartable", function()
    local case = lifecycleCase()
    local originalFactory = case.guard.deps.filterFactory
    case.guard.deps.filterFactory = function()
        error("filter factory failure", 0)
    end

    local ok = pcall(function()
        case.guard:start(case.screen, {})
    end)

    test.equal(ok, true)
    test.equal(case.guard.filter, nil)

    case.guard.deps.filterFactory = originalFactory
    case.guard:start(case.screen, {})

    test.equal(case.factoryCalls(), 1)
    test.equal(case.guard.filter, case.filterModule.filters[1])
end)

test.test("start cleans a filter whose subscription raises", function()
    local case = lifecycleCase()
    local originalFactory = case.guard.deps.filterFactory
    case.guard.deps.filterFactory = function()
        local filter = case.filterModule.new()
        filter.subscribeError = "subscription failure"
        return filter
    end

    local ok = pcall(function()
        case.guard:start(case.screen, {})
    end)
    local failedFilter = case.filterModule.filters[1]

    test.equal(ok, true)
    test.equal(case.guard.filter, nil)
    test.equal(failedFilter.unsubscribeAllCount, 1)
    test.equal(failedFilter.pauseCount, 1)

    case.guard.deps.filterFactory = originalFactory
    case.guard:start(case.screen, {})

    test.equal(case.guard.filter, case.filterModule.filters[2])
end)

test.test("lifecycle events debounce each window id for 0.15 seconds", function()
    local case = lifecycleCase()
    local window = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    local corrected = {}
    case.guard.correct = function(_, correctedWindow)
        corrected[#corrected + 1] = correctedWindow
    end
    case.guard:start(case.screen, {})
    local filter = case.guard.filter

    filter:emit(case.filterModule.windowCreated, window)
    local firstTimer = case.timer.timers[1]
    filter:emit(case.filterModule.windowMoved, window)
    local secondTimer = case.timer.timers[2]
    filter:emit(case.filterModule.windowOnScreen, window)
    local thirdTimer = case.timer.timers[3]

    test.equal(#case.timer.doAfterCalls, 3)
    test.equal(case.timer.doAfterCalls[1].delay, 0.15)
    test.equal(firstTimer.stopCount, 1)
    test.equal(secondTimer.stopCount, 1)
    test.equal(case.guard.pending[42], thirdTimer)

    firstTimer:fire()
    secondTimer:fire()
    thirdTimer:fire()

    test.equal(#corrected, 1)
    test.equal(corrected[1], window)
    test.equal(case.guard.pending[42], nil)
end)

test.test("debounce removes pending state before correcting", function()
    local case = lifecycleCase()
    local window = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    local corrected = 0
    case.guard.correct = function(guard)
        corrected = corrected + 1
        test.equal(guard.pending[42], nil)
    end
    case.guard:start(case.screen, {})

    case.guard.filter:emit(case.filterModule.windowMoved, window)
    case.timer.timers[1]:fire()

    test.equal(corrected, 1)
end)

test.test("lifecycle events ignore missing and unreadable window ids", function()
    local case = lifecycleCase()
    local missingIdWindow = fake.window({
        id = false,
        frame = {},
        screen = case.screen,
    })
    missingIdWindow.id = function()
        return nil
    end
    local failingIdWindow = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    failingIdWindow.id = function()
        error("window id failure", 0)
    end
    case.guard:start(case.screen, {})

    local ok = pcall(function()
        case.guard.filter:emit(case.filterModule.windowMoved, nil)
        case.guard.filter:emit(case.filterModule.windowMoved, missingIdWindow)
        case.guard.filter:emit(case.filterModule.windowMoved, failingIdWindow)
    end)

    test.equal(ok, true)
    test.equal(#case.timer.doAfterCalls, 0)
    test.equal(next(case.guard.pending), nil)
end)

test.test("debounce replaces a timer when cancelling it raises", function()
    local case = lifecycleCase()
    local window = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    case.guard:start(case.screen, {})
    case.guard.filter:emit(case.filterModule.windowMoved, window)
    local firstTimer = case.timer.timers[1]
    firstTimer.stopError = "timer stop failure"

    local ok = pcall(function()
        case.guard.filter:emit(case.filterModule.windowMoved, window)
    end)

    test.equal(ok, true)
    test.equal(firstTimer.stopCount, 1)
    test.equal(#case.timer.timers, 2)
    test.equal(case.guard.pending[42], case.timer.timers[2])
end)

test.test("debounce contains scheduling errors without retaining a timer", function()
    local case = lifecycleCase()
    local window = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    case.guard:start(case.screen, {})
    case.guard.filter:emit(case.filterModule.windowMoved, window)
    local firstTimer = case.timer.timers[1]
    case.timer.doAfterError = "timer scheduling failure"

    local ok = pcall(function()
        case.guard.filter:emit(case.filterModule.windowMoved, window)
    end)

    test.equal(ok, true)
    test.equal(firstTimer.stopCount, 1)
    test.equal(#case.timer.timers, 1)
    test.equal(case.guard.pending[42], nil)
end)

test.test("a replaced timer callback cannot clear or correct newer work", function()
    local case = lifecycleCase()
    local window = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    local corrected = 0
    case.guard.correct = function()
        corrected = corrected + 1
    end
    case.guard:start(case.screen, {})
    case.guard.filter:emit(case.filterModule.windowMoved, window)
    local firstTimer = case.timer.timers[1]
    case.guard.filter:emit(case.filterModule.windowMoved, window)
    local secondTimer = case.timer.timers[2]

    firstTimer.callback()

    test.equal(corrected, 0)
    test.equal(case.guard.pending[42], secondTimer)

    secondTimer:fire()

    test.equal(corrected, 1)
    test.equal(case.guard.pending[42], nil)
end)

test.test("a stopped filter callback cannot schedule work after restart", function()
    local case = lifecycleCase()
    local window = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    case.guard:start(case.screen, {})
    local oldFilter = case.guard.filter
    local oldCallback = oldFilter.subscribeCalls[1].callback
    case.guard:stop()
    case.guard:start(case.screen, {})

    oldCallback(window)

    test.equal(#case.timer.timers, 0)
    test.equal(next(case.guard.pending), nil)

    case.guard.filter:emit(case.filterModule.windowMoved, window)

    test.equal(#case.timer.timers, 1)
    test.equal(case.guard.pending[42], case.timer.timers[1])
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

test.test("stop cancels timers and tears down its lifecycle filter once", function()
    local case = lifecycleCase()
    local window = fake.window({
        id = 42,
        frame = {},
        screen = case.screen,
    })
    case.guard:start(case.screen, { {} })
    local filter = case.guard.filter
    filter:emit(case.filterModule.windowMoved, window)
    local pendingTimer = case.timer.timers[1]
    case.guard.recent[42] = true
    case.guard.blockedUntil[42] = 10

    case.guard:stop()
    case.guard:stop()

    test.equal(pendingTimer.stopCount, 1)
    test.equal(filter.unsubscribeAllCount, 1)
    test.equal(filter.pauseCount, 1)
    test.equal(case.guard.filter, nil)
    test.equal(case.guard.selectedScreen, nil)
    test.equal(#case.guard.maskRects, 0)
    test.equal(next(case.guard.pending), nil)
    test.equal(next(case.guard.recent), nil)
    test.equal(next(case.guard.blockedUntil), nil)
end)

test.test("stop contains cleanup errors and still clears lifecycle state", function()
    local case = lifecycleCase()
    case.guard:start(case.screen, { {} })
    local filter = case.guard.filter
    filter.unsubscribeAllError = "unsubscribe failure"
    filter.pauseError = "pause failure"
    local firstStops = 0
    local secondStops = 0
    case.guard.pending.first = {
        stop = function()
            firstStops = firstStops + 1
            error("first stop failure", 0)
        end,
    }
    case.guard.pending.second = {
        stop = function()
            secondStops = secondStops + 1
            error("second stop failure", 0)
        end,
    }
    case.guard.recent[42] = true
    case.guard.blockedUntil[42] = 10

    local ok = pcall(function()
        case.guard:stop()
        case.guard:stop()
    end)

    test.equal(ok, true)
    test.equal(firstStops, 1)
    test.equal(secondStops, 1)
    test.equal(filter.unsubscribeAllCount, 1)
    test.equal(filter.pauseCount, 1)
    test.equal(case.guard.filter, nil)
    test.equal(case.guard.selectedScreen, nil)
    test.equal(#case.guard.maskRects, 0)
    test.equal(next(case.guard.pending), nil)
    test.equal(next(case.guard.recent), nil)
    test.equal(next(case.guard.blockedUntil), nil)
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
