local Controller = require("screenfix.controller")
local fake = require("tests.fake_hs")
local test = require("tests.test_helper")

local function validConfig(enabled)
    return {
        schemaVersion = 1,
        enabled = enabled ~= false,
        screen = {
            uuid = "damaged-uuid",
            name = "Damaged Display",
            width = 3440,
            height = 1440,
        },
        bands = {
            { x = 0.43, y = 0.00, w = 0.16, h = 0.34 },
            { x = 0.46, y = 0.34, w = 0.11, h = 0.39 },
            { x = 0.48, y = 0.73, w = 0.07, h = 0.27 },
        },
    }
end

local function newCase(options)
    options = options or {}
    local menubar = fake.menubar()
    local notify = fake.notify()
    local caffeinate = fake.caffeinate()
    local screen = options.screen or fake.screen("damaged-uuid", "Damaged Display", {
        x = -3440,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local state = {
        accessibility = options.accessibility == true,
        accessibilityCalls = {},
        absoluteBands = {
            { x = -1960, y = 0, w = 550, h = 490 },
            { x = -1850, y = 490, w = 380, h = 560 },
            { x = -1790, y = 1050, w = 240, h = 390 },
        },
        calibrationStarts = {},
        defaultForScreenCalls = 0,
        guardStarts = {},
        guardStopCount = 0,
        overlayDeleteCount = 0,
        overlayShows = {},
        reloadCount = 0,
        saveCalls = {},
        selectCalls = 0,
        stopWatchingCount = 0,
        watchCalls = 0,
    }
    local hs = {
        caffeinate = caffeinate,
        menubar = menubar,
        notify = notify,
        accessibilityStateCallback = options.previousAccessibilityCallback,
        accessibilityState = function(prompt)
            state.accessibilityCalls[#state.accessibilityCalls + 1] = prompt
            return state.accessibility
        end,
        reload = function(...)
            if select("#", ...) ~= 0 then
                error("reload received unexpected arguments", 0)
            end
            state.reloadCount = state.reloadCount + 1
        end,
        showError = function(message)
            state.lastError = message
        end,
    }
    local config = {
        load = function()
            return options.configuration
        end,
        findScreen = function()
            return state.connected and screen or nil
        end,
        save = function(_, value)
            state.saveCalls[#state.saveCalls + 1] = value
            return value
        end,
        defaultForScreen = function()
            state.defaultForScreenCalls = state.defaultForScreenCalls + 1
            return validConfig(true)
        end,
        watch = function(_, callback)
            state.watchCalls = state.watchCalls + 1
            state.screenCallback = callback
        end,
        stopWatching = function()
            state.stopWatchingCount = state.stopWatchingCount + 1
        end,
    }
    local overlay = {
        show = function(_, selectedScreen, bands)
            state.overlayShows[#state.overlayShows + 1] = {
                screen = selectedScreen,
                bands = bands,
            }
            if state.overlayError ~= nil then
                return nil, state.overlayError
            end
            return true
        end,
        delete = function()
            state.overlayDeleteCount = state.overlayDeleteCount + 1
        end,
    }
    local guard = {
        start = function(_, selectedScreen, maskRects)
            state.guardStarts[#state.guardStarts + 1] = {
                screen = selectedScreen,
                maskRects = maskRects,
            }
        end,
        stop = function()
            state.guardStopCount = state.guardStopCount + 1
        end,
    }
    local calibration = {
        selectScreen = function(_, callback)
            state.selectCalls = state.selectCalls + 1
            state.selectCallback = callback
            state.selectCallbacks = state.selectCallbacks or {}
            state.selectCallbacks[#state.selectCallbacks + 1] = callback
            return true
        end,
        start = function(_, selectedScreen, bands, onSave, onCancel)
            state.calibrationStarts[#state.calibrationStarts + 1] = {
                screen = selectedScreen,
                bands = bands,
                onSave = onSave,
                onCancel = onCancel,
            }
            return true
        end,
        stop = function()
            state.calibrationStopCount = (state.calibrationStopCount or 0) + 1
        end,
    }
    state.connected = options.connected ~= false
    local controller = Controller.new({
        hs = hs,
        geometry = {
            absoluteBands = function(fullFrame, bands)
                state.absoluteBandsCall = {
                    fullFrame = fullFrame,
                    bands = bands,
                }
                return state.absoluteBands
            end,
        },
        config = config,
        overlay = overlay,
        guard = guard,
        calibration = calibration,
    })

    state.calibration = calibration
    state.caffeinate = caffeinate
    state.config = config
    state.controller = controller
    state.guard = guard
    state.hs = hs
    state.menubar = menubar
    state.notify = notify
    state.overlay = overlay
    state.screen = screen
    return state
end

local function menuItem(items, title)
    for _, item in ipairs(items) do
        if item.title == title then
            return item
        end
    end
end

test.test("start prompts for monitor selection without valid configuration", function()
    local case = newCase()

    case.controller:start()

    test.equal(case.selectCalls, 1)
    test.equal(case.watchCalls, 1)
    test.equal(case.accessibilityCalls[1], true)
end)

local function assertWatcherStartupFailure(retainsCallback)
    local priorCallback = function()
    end
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        previousAccessibilityCallback = priorCallback,
    })
    case.config.watch = function(_, callback)
        case.watchCalls = case.watchCalls + 1
        if retainsCallback then
            case.screenCallback = callback
        end
        error("screen watcher startup failure", 0)
    end

    local startOk, startError = pcall(function()
        case.controller:start()
    end)

    test.equal(startOk, false)
    test.equal(string.find(startError, "screen watcher startup failure", 1, true) ~= nil, true)
    test.equal(case.controller.started, false)
    test.equal(case.stopWatchingCount, 1)
    test.equal(case.calibrationStopCount, 1)
    test.equal(case.guardStopCount, 1)
    test.equal(case.overlayDeleteCount, 1)
    test.equal(case.menubar.items[1].deleteCount, 1)
    test.equal(case.hs.accessibilityStateCallback, priorCallback)
    if case.screenCallback then
        local overlayDeletes = case.overlayDeleteCount
        test.equal(pcall(case.screenCallback), true)
        test.equal(case.overlayDeleteCount, overlayDeletes)
    end
end

test.test("start fails transactionally when watcher construction throws", function()
    assertWatcherStartupFailure(false)
end)

test.test("start fails transactionally when a retained watcher cannot start", function()
    assertWatcherStartupFailure(true)
end)

test.test("start owns one wake watcher and remains idempotent", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })

    case.controller:start()
    case.controller:start()

    test.equal(#case.caffeinate.watchers, 1)
    test.equal(case.caffeinate.watchers[1].startCount, 1)
    test.equal(case.controller.wakeWatcher, case.caffeinate.watchers[1])
end)

local function assertWakeWatcherStartupFailure(startFailure)
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    local retained
    case.caffeinate.watcher.new = function(callback)
        if not startFailure then
            error("wake watcher construction failure", 0)
        end

        retained = fake.watcher(callback)
        retained.startError = "wake watcher start failure"
        case.caffeinate.watchers[#case.caffeinate.watchers + 1] = retained
        return retained
    end

    local startOk, startError = pcall(function()
        case.controller:start()
    end)

    test.equal(startOk, false)
    local expected = startFailure and "wake watcher start failure"
        or "wake watcher construction failure"
    test.equal(string.find(startError, expected, 1, true) ~= nil, true)
    test.equal(case.controller.started, false)
    test.equal(case.stopWatchingCount, 1)
    test.equal(case.calibrationStopCount, 1)
    test.equal(case.guardStopCount, 1)
    test.equal(case.overlayDeleteCount, 1)
    test.equal(case.menubar.items[1].deleteCount, 1)
    if retained then
        test.equal(retained.stopCount, 1)
    end
end

test.test("start fails transactionally when wake watcher construction throws", function()
    assertWakeWatcherStartupFailure(false)
end)

test.test("start fails transactionally when a retained wake watcher cannot start", function()
    assertWakeWatcherStartupFailure(true)
end)

test.test("wake events reconcile disconnect and reconnect runtime state", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    local watcher = case.caffeinate.watchers[1]

    case.connected = false
    watcher.callback(case.caffeinate.watcher.systemDidWake)

    test.equal(case.controller.screen, nil)
    test.equal(case.overlayDeleteCount, 1)
    test.equal(case.guardStopCount, 1)
    test.equal(#case.notify.notifications, 1)

    case.connected = true
    watcher.callback(case.caffeinate.watcher.screensDidWake)

    test.equal(case.controller.screen, case.screen)
    test.equal(#case.overlayShows, 2)
    test.equal(#case.guardStarts, 2)
end)

test.test("wake callback ignores unrelated caffeinate events", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    local refreshCalls = 0
    case.controller.refresh = function()
        refreshCalls = refreshCalls + 1
    end

    case.caffeinate.watchers[1].callback(case.caffeinate.watcher.systemWillSleep)

    test.equal(refreshCalls, 0)
end)

test.test("wake callback invalidates a pending monitor chooser", function()
    local case = newCase({ accessibility = true })
    case.controller:start()
    local staleSelection = case.selectCallback

    case.caffeinate.watchers[1].callback(case.caffeinate.watcher.systemDidWake)
    staleSelection(case.screen)

    test.equal(#case.calibrationStarts, 0)
end)

test.test("wake callback contains refresh errors", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller.refresh = function()
        error("wake refresh failure", 0)
    end

    local callbackOk = pcall(
        case.caffeinate.watchers[1].callback,
        case.caffeinate.watcher.screensDidWake
    )

    test.equal(callbackOk, true)
end)

test.test("stop releases the wake watcher and rejects its late callback", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    local watcher = case.caffeinate.watchers[1]
    local refreshCalls = 0
    case.controller.refresh = function()
        refreshCalls = refreshCalls + 1
    end

    case.controller:stop()
    case.controller:stop()
    local callbackOk = pcall(watcher.callback, case.caffeinate.watcher.systemDidWake)

    test.equal(callbackOk, true)
    test.equal(watcher.stopCount, 1)
    test.equal(watcher.delete, nil)
    test.equal(refreshCalls, 0)
    test.equal(case.controller.wakeWatcher, nil)
end)

test.test("refresh renders an enabled mask without Accessibility permission", function()
    local value = validConfig(true)
    local case = newCase({ configuration = value, accessibility = false })

    case.controller:start()

    test.equal(#case.overlayShows, 1)
    test.equal(case.overlayShows[1].screen, case.screen)
    test.equal(case.overlayShows[1].bands, value.bands)
    test.equal(#case.guardStarts, 0)
    test.equal(case.guardStopCount, 1)
end)

test.test("refresh tears down a disabled configuration even when trusted", function()
    local case = newCase({ configuration = validConfig(false), accessibility = true })

    case.controller:start()

    test.equal(#case.overlayShows, 0)
    test.equal(#case.guardStarts, 0)
    test.equal(case.overlayDeleteCount, 1)
    test.equal(case.guardStopCount, 1)
end)

test.test("disabled cold start tracks a connected screen without running resources", function()
    local case = newCase({ configuration = validConfig(false), accessibility = true })

    case.controller:start()

    test.equal(case.controller.screen, case.screen)
    test.equal(menuItem(case.menubar.items[1].menu(), "Calibrate").disabled, false)
    test.equal(#case.overlayShows, 0)
    test.equal(#case.guardStarts, 0)
    test.equal(#case.notify.notifications, 0)
end)

test.test("disabled screen disconnect clears state and cannot start calibration", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:disable()
    case.connected = false

    case.screenCallback()
    local result = case.controller:calibrate()

    test.equal(case.controller.screen, nil)
    test.equal(result, nil)
    test.equal(#case.calibrationStarts, 0)
    test.equal(menuItem(case.menubar.items[1].menu(), "Calibrate").disabled, true)
    test.equal(#case.notify.notifications, 0)
end)

test.test("calibrate rechecks a disconnected screen before its watcher fires", function()
    local case = newCase({ configuration = validConfig(false), accessibility = true })
    case.controller:start()
    test.equal(case.controller.screen, case.screen)
    case.connected = false

    local result = case.controller:calibrate()

    test.equal(result, nil)
    test.equal(case.controller.screen, nil)
    test.equal(#case.calibrationStarts, 0)
    test.equal(#case.notify.notifications, 0)
end)

test.test("disabled screen reconnect refreshes state and re-enables calibration", function()
    local case = newCase({
        configuration = validConfig(false),
        accessibility = true,
        connected = false,
    })
    case.controller:start()
    test.equal(case.controller.screen, nil)
    case.connected = true

    case.screenCallback()

    test.equal(case.controller.screen, case.screen)
    test.equal(menuItem(case.menubar.items[1].menu(), "Calibrate").disabled, false)
    test.equal(#case.overlayShows, 0)
    test.equal(#case.guardStarts, 0)
    test.equal(#case.notify.notifications, 0)
end)

test.test("refresh starts the trusted guard with absolute mask rectangles", function()
    local value = validConfig(true)
    local case = newCase({ configuration = value, accessibility = true })

    case.controller:start()

    test.equal(#case.overlayShows, 1)
    test.equal(#case.guardStarts, 1)
    test.equal(case.guardStarts[1].screen, case.screen)
    test.equal(case.guardStarts[1].maskRects, case.absoluteBands)
    test.equal(case.absoluteBandsCall.bands, value.bands)
    test.rect(case.absoluteBandsCall.fullFrame, {
        x = -3440,
        y = 0,
        w = 3440,
        h = 1440,
    })
end)

test.test("mask rendering failure pauses protection once and recovery resumes it", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.overlayError = "canvas configuration failure"

    case.controller:start()
    case.controller:refresh()

    test.equal(case.controller.maskError, "canvas configuration failure")
    test.equal(#case.guardStarts, 0)
    test.equal(case.guardStopCount, 2)
    test.equal(#case.notify.notifications, 1)
    test.equal(string.find(
        case.notify.notifications[1].attributes.informativeText,
        "canvas configuration failure",
        1,
        true
    ) ~= nil, true)
    local paused = menuItem(
        case.menubar.items[1].menu(),
        "Paused: Mask rendering failed"
    )
    test.equal(paused ~= nil, true)
    test.equal(paused.checked, false)
    test.equal(paused.disabled, true)

    case.overlayError = nil
    case.controller:refresh()

    test.equal(case.controller.maskError, nil)
    test.equal(menuItem(
        case.menubar.items[1].menu(),
        "Paused: Mask rendering failed"
    ), nil)
    test.equal(#case.guardStarts, 1)
    test.equal(#case.notify.notifications, 1)
end)

test.test("stop clears the mask failure notification episode before restart", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.overlayError = "canvas configuration failure"
    case.controller:start()

    case.controller:stop()
    case.controller:start()

    test.equal(case.controller.maskError, "canvas configuration failure")
    test.equal(#case.notify.notifications, 2)
end)

test.test("inactive and disconnected states clear the mask failure episode", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.overlayError = "canvas configuration failure"
    case.controller:start()

    case.controller:disable()

    test.equal(case.controller.maskError, nil)
    test.equal(case.controller.notified.mask, nil)
    test.equal(menuItem(
        case.menubar.items[1].menu(),
        "Paused: Mask rendering failed"
    ), nil)

    case.controller:enable()
    test.equal(case.controller.maskError, "canvas configuration failure")
    test.equal(#case.notify.notifications, 2)

    case.connected = false
    case.screenCallback()

    test.equal(case.controller.maskError, nil)
    test.equal(case.controller.notified.mask, nil)
    test.equal(menuItem(
        case.menubar.items[1].menu(),
        "Paused: Mask rendering failed"
    ), nil)

    case.connected = true
    case.screenCallback()

    test.equal(case.controller.maskError, "canvas configuration failure")
    test.equal(#case.notify.notifications, 4)
end)

test.test("Accessibility prompts only on first start and later refreshes do not prompt", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })

    case.controller:start()
    case.controller:start()
    case.controller:refresh()

    test.equal(#case.accessibilityCalls, 2)
    test.equal(case.accessibilityCalls[1], true)
    test.equal(case.accessibilityCalls[2], false)
end)

test.test("disconnect notifies once and the screen watcher restores runtime resources", function()
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        connected = false,
    })

    case.controller:start()
    case.screenCallback()

    test.equal(#case.notify.notifications, 1)
    test.equal(case.notify.notifications[1].attributes.title, "ScreenFix")
    test.equal(case.notify.notifications[1].sendCount, 1)
    test.equal(#case.overlayShows, 0)
    test.equal(#case.guardStarts, 0)

    case.connected = true
    case.screenCallback()

    test.equal(#case.overlayShows, 1)
    test.equal(#case.guardStarts, 1)

    case.connected = false
    case.screenCallback()
    test.equal(#case.notify.notifications, 2)
end)

test.test("Accessibility callback rechecks state without prompting and refreshes", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })

    case.controller:start()
    case.accessibility = false
    local callbackOk = pcall(case.hs.accessibilityStateCallback)

    test.equal(callbackOk, true)
    test.equal(case.accessibilityCalls[#case.accessibilityCalls], false)
    test.equal(#case.overlayShows, 2)
    test.equal(#case.guardStarts, 1)
    test.equal(case.guardStopCount, 1)
end)

test.test("Accessibility callback refreshes when the previous callback throws", function()
    local priorCalls = 0
    local prior = function(...)
        test.equal(select("#", ...), 0)
        priorCalls = priorCalls + 1
        error("prior callback failure", 0)
    end
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        previousAccessibilityCallback = prior,
    })
    case.controller:start()
    local refreshCalls = 0
    case.controller.refresh = function()
        refreshCalls = refreshCalls + 1
    end

    local callbackOk = pcall(case.hs.accessibilityStateCallback)

    test.equal(callbackOk, true)
    test.equal(priorCalls, 1)
    test.equal(refreshCalls, 1)
end)

test.test("Accessibility callback still invokes the previous callback when refresh throws", function()
    local priorCalls = 0
    local prior = function(...)
        test.equal(select("#", ...), 0)
        priorCalls = priorCalls + 1
    end
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        previousAccessibilityCallback = prior,
    })
    case.controller:start()
    case.controller.refresh = function()
        error("refresh failure", 0)
    end

    local callbackOk = pcall(case.hs.accessibilityStateCallback)

    test.equal(callbackOk, true)
    test.equal(priorCalls, 1)
end)

test.test("late Accessibility wrapper only chains the prior callback after stop", function()
    local priorCalls = 0
    local prior = function()
        priorCalls = priorCalls + 1
    end
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        previousAccessibilityCallback = prior,
    })
    case.controller:start()
    local wrapper = case.hs.accessibilityStateCallback
    local refreshCalls = 0
    case.controller.refresh = function()
        refreshCalls = refreshCalls + 1
    end
    case.controller:stop()

    local callbackOk = pcall(wrapper)

    test.equal(callbackOk, true)
    test.equal(priorCalls, 1)
    test.equal(refreshCalls, 0)
    test.equal(case.hs.accessibilityStateCallback, prior)
end)

test.test("stop does not overwrite a newer Accessibility callback owner", function()
    local prior = function()
    end
    local replacement = function()
    end
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        previousAccessibilityCallback = prior,
    })
    case.controller:start()
    case.hs.accessibilityStateCallback = replacement

    case.controller:stop()

    test.equal(case.hs.accessibilityStateCallback, replacement)
end)

test.test("Disable and Enable save state and immediately tear down or rebuild", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()

    case.controller:disable()

    test.equal(#case.saveCalls, 1)
    test.equal(case.saveCalls[1].enabled, false)
    test.equal(case.controller.value.enabled, false)
    test.equal(case.overlayDeleteCount, 1)
    test.equal(case.guardStopCount, 1)

    case.controller:enable()

    test.equal(#case.saveCalls, 2)
    test.equal(case.saveCalls[2].enabled, true)
    test.equal(case.controller.value.enabled, true)
    test.equal(#case.overlayShows, 2)
    test.equal(#case.guardStarts, 2)
end)

test.test("Disable closes calibration and late Save cannot re-enable it", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:calibrate()
    local lateSave = case.calibrationStarts[1].onSave

    case.controller:disable()

    test.equal(#case.saveCalls, 1)
    test.equal(case.saveCalls[1].enabled, false)
    test.equal(case.controller.value.enabled, false)
    test.equal(case.calibrationStopCount, 1)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationSession, nil)
    test.equal(case.overlayDeleteCount, 1)

    lateSave(case.calibrationStarts[1].bands)
    test.equal(#case.saveCalls, 1)
    test.equal(case.controller.value.enabled, false)
    test.equal(case.controller.calibrating, false)
end)

test.test("Enable closes disabled calibration and rebuilds normal runtime", function()
    local case = newCase({ configuration = validConfig(false), accessibility = true })
    case.controller:start()
    case.controller:calibrate()
    local lateSave = case.calibrationStarts[1].onSave

    case.controller:enable()

    test.equal(#case.saveCalls, 1)
    test.equal(case.saveCalls[1].enabled, true)
    test.equal(case.controller.value.enabled, true)
    test.equal(case.calibrationStopCount, 1)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationSession, nil)
    test.equal(#case.overlayShows, 2)
    test.equal(#case.guardStarts, 1)

    lateSave(case.calibrationStarts[1].bands)
    test.equal(#case.saveCalls, 1)
    test.equal(case.controller.value.enabled, true)
end)

test.test("calibration keeps the mask, pauses the guard, and restores after Save", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    local changedBands = {
        { x = 0.40, y = 0.00, w = 0.20, h = 0.30 },
        { x = 0.45, y = 0.30, w = 0.12, h = 0.40 },
        { x = 0.48, y = 0.70, w = 0.08, h = 0.30 },
    }
    case.controller:start()

    case.controller:calibrate()

    test.equal(#case.calibrationStarts, 1)
    test.equal(case.calibrationStarts[1].screen, case.screen)
    test.equal(#case.overlayShows, 2)
    test.equal(case.overlayDeleteCount, 0)
    test.equal(case.guardStopCount, 1)
    test.equal(case.controller.calibrating, true)
    test.equal(menuItem(case.menubar.items[1].menu(), "Calibrate").checked, true)

    case.calibrationStarts[1].onSave(changedBands)

    test.equal(#case.saveCalls, 1)
    test.equal(case.saveCalls[1].bands, changedBands)
    test.equal(case.controller.value.bands, changedBands)
    test.equal(case.controller.calibrating, false)
    test.equal(menuItem(case.menubar.items[1].menu(), "Calibrate").checked, false)
    test.equal(#case.overlayShows, 3)
    test.equal(#case.guardStarts, 2)
end)

test.test("Cancel exits calibration without saving and restores the guard", function()
    local value = validConfig(true)
    local case = newCase({ configuration = value, accessibility = true })
    case.controller:start()
    case.controller:calibrate()

    case.calibrationStarts[1].onCancel()

    test.equal(#case.saveCalls, 0)
    test.equal(case.controller.value, value)
    test.equal(case.controller.calibrating, false)
    test.equal(#case.overlayShows, 3)
    test.equal(#case.guardStarts, 2)
end)

test.test("late calibration Save after stop cannot write configuration", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:calibrate()
    local lateSave = case.calibrationStarts[1].onSave

    case.controller:stop()
    local callbackOk = pcall(lateSave, case.calibrationStarts[1].bands)

    test.equal(callbackOk, true)
    test.equal(#case.saveCalls, 0)
    test.equal(case.controller.started, false)
    test.equal(case.controller.calibrating, false)
end)

test.test("late monitor chooser callback after stop cannot recreate calibration state", function()
    local case = newCase()
    case.controller:start()
    local lateSelection = case.selectCallback

    case.controller:stop()
    local callbackOk = pcall(lateSelection, case.screen)

    test.equal(callbackOk, true)
    test.equal(case.defaultForScreenCalls, 0)
    test.equal(#case.calibrationStarts, 0)
    test.equal(#case.saveCalls, 0)
    test.equal(case.controller.started, false)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationSession, nil)
end)

test.test("old calibration Save cannot overwrite a replacement monitor session", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    local replacementScreen = fake.screen("replacement-uuid", "Replacement Display", {
        x = 0,
        y = 0,
        w = 2560,
        h = 1440,
    })
    local replacementValue = validConfig(true)
    replacementValue.screen.uuid = "replacement-uuid"
    replacementValue.screen.name = "Replacement Display"
    replacementValue.screen.width = 2560
    case.config.defaultForScreen = function()
        return replacementValue
    end
    case.config.findScreen = function(_, value)
        if value.screen.uuid == "replacement-uuid" then
            return replacementScreen
        end
        return case.screen
    end
    case.controller:start()
    case.controller:calibrate()
    local oldSave = case.calibrationStarts[1].onSave
    case.controller:selectMonitor()
    case.selectCallback(replacementScreen)
    local currentSave = case.calibrationStarts[2].onSave
    local currentBands = case.calibrationStarts[2].bands

    oldSave(case.calibrationStarts[1].bands)

    test.equal(#case.saveCalls, 0)
    test.equal(case.controller.calibrating, true)
    test.equal(case.controller.calibrationScreen, replacementScreen)
    test.equal(case.controller.calibrationValue.screen.uuid, "replacement-uuid")

    currentSave(currentBands)
    test.equal(#case.saveCalls, 1)
    test.equal(case.saveCalls[1].screen.uuid, "replacement-uuid")
end)

test.test("stale calibration Cancel cannot clear a replacement session", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:calibrate()
    local staleCancel = case.calibrationStarts[1].onCancel
    case.controller:calibrate()
    local currentCancel = case.calibrationStarts[2].onCancel

    staleCancel()

    test.equal(case.controller.calibrating, true)
    test.equal(case.controller.calibrationScreen, case.screen)

    currentCancel()
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationScreen, nil)
end)

test.test("active calibration disconnect stops editing and reconnect rebuilds on the live screen", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    local currentScreen = case.screen
    case.config.findScreen = function()
        return currentScreen
    end
    case.controller:start()
    case.controller:calibrate()
    test.equal(#case.calibrationStarts, 1)
    test.equal(#case.overlayShows, 2)
    currentScreen = nil

    case.screenCallback()

    test.equal(case.calibrationStopCount, 1)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationScreen, nil)
    test.equal(case.controller.screen, nil)
    test.equal(case.guardStopCount, 2)
    test.equal(case.overlayDeleteCount, 1)
    test.equal(#case.overlayShows, 2)
    test.equal(#case.saveCalls, 0)
    test.equal(#case.notify.notifications, 1)

    local reconnected = fake.screen("damaged-uuid", "Damaged Display", {
        x = 0,
        y = 0,
        w = 3440,
        h = 1440,
    })
    currentScreen = reconnected
    case.screenCallback()

    test.equal(case.controller.screen, reconnected)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationScreen, nil)
    test.equal(#case.calibrationStarts, 1)
    test.equal(#case.overlayShows, 3)
    test.equal(case.overlayShows[3].screen, reconnected)
    test.equal(#case.guardStarts, 2)
    test.equal(case.guardStarts[2].screen, reconnected)
    test.equal(#case.saveCalls, 0)
    test.equal(#case.notify.notifications, 1)
end)

test.test("calibration topology change cancels editing and rebuilds normal runtime", function()
    local originalFrame = { x = -3440, y = 0, w = 3440, h = 1440 }
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        screen = fake.screen("damaged-uuid", "Damaged Display", originalFrame),
    })
    local currentScreen = case.screen
    case.config.findScreen = function()
        return currentScreen
    end
    case.controller:start()
    case.controller:calibrate()
    local oldSave = case.calibrationStarts[1].onSave
    local oldToken = case.controller.calibrationSession.token
    test.rect(case.controller.calibrationSession.fullFrame, originalFrame)
    local changedScreen = fake.screen("damaged-uuid", "Damaged Display", {
        x = -3200,
        y = 80,
        w = 3200,
        h = 1350,
    })
    currentScreen = changedScreen

    case.screenCallback()

    test.equal(case.calibrationStopCount, 1)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationSession, nil)
    test.equal(case.controller.calibrationScreen, nil)
    test.equal(case.controller.screen, changedScreen)
    test.equal(case.controller.calibrationGeneration > oldToken, true)
    test.equal(#case.calibrationStarts, 1)
    test.equal(#case.saveCalls, 0)
    test.equal(#case.overlayShows, 3)
    test.equal(case.overlayShows[3].screen, changedScreen)
    test.equal(#case.guardStarts, 2)
    test.equal(case.guardStarts[2].screen, changedScreen)

    oldSave(case.calibrationStarts[1].bands)
    test.equal(#case.saveCalls, 0)
end)

test.test("calibration rebinds identical-frame replacement screen without invalidation", function()
    local frame = { x = -3440, y = 0, w = 3440, h = 1440 }
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        screen = fake.screen("damaged-uuid", "Damaged Display", frame),
    })
    local currentScreen = case.screen
    case.config.findScreen = function()
        return currentScreen
    end
    case.controller:start()
    case.controller:calibrate()
    local session = case.controller.calibrationSession
    test.rect(session.fullFrame, frame)
    local replacement = fake.screen("damaged-uuid", "Damaged Display", {
        x = frame.x,
        y = frame.y,
        w = frame.w,
        h = frame.h,
    })
    currentScreen = replacement

    case.screenCallback()

    test.equal(case.calibrationStopCount, nil)
    test.equal(case.controller.calibrating, true)
    test.equal(case.controller.calibrationSession, session)
    test.equal(case.controller.calibrationScreen, replacement)
    test.equal(case.controller.screen, replacement)
    test.equal(#case.calibrationStarts, 1)
    test.equal(#case.saveCalls, 0)
    test.equal(#case.overlayShows, 3)
    test.equal(case.overlayShows[3].screen, replacement)
end)

test.test("calibration fails closed when live fullFrame is missing or throws", function()
    for _, mode in ipairs({ "missing", "throws" }) do
        local case = newCase({ configuration = validConfig(true), accessibility = true })
        local currentScreen = case.screen
        case.config.findScreen = function()
            return currentScreen
        end
        case.controller:start()
        case.controller:calibrate()
        currentScreen = {
            getUUID = function()
                return "damaged-uuid"
            end,
            name = function()
                return "Damaged Display"
            end,
            frame = function()
                return { x = 0, y = 0, w = 3440, h = 1400 }
            end,
            fullFrame = function()
                if mode == "throws" then
                    error("full frame failure", 0)
                end
                return nil
            end,
        }

        local callbackOk = pcall(case.screenCallback)

        test.equal(callbackOk, true)
        test.equal(case.calibrationStopCount, 1)
        test.equal(case.controller.calibrating, false)
        test.equal(case.controller.calibrationSession, nil)
        test.equal(case.controller.calibrationScreen, nil)
        test.equal(case.controller.screen, currentScreen)
        test.equal(#case.saveCalls, 0)
        test.equal(#case.overlayShows, 2)
        test.equal(case.overlayDeleteCount, 1)
        test.equal(#case.guardStarts, 1)
    end
end)

test.test("new monitor chooser supersedes an older callback", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    local firstScreen = fake.screen("first-uuid", "First Display", {
        x = 0,
        y = 0,
        w = 1920,
        h = 1080,
    })
    local secondScreen = fake.screen("second-uuid", "Second Display", {
        x = 1920,
        y = 0,
        w = 2560,
        h = 1440,
    })
    case.config.defaultForScreen = function(_, screen)
        case.defaultForScreenCalls = case.defaultForScreenCalls + 1
        local value = validConfig(true)
        value.screen.uuid = screen:getUUID()
        value.screen.name = screen:name()
        local frame = screen:fullFrame()
        value.screen.width = frame.w
        value.screen.height = frame.h
        return value
    end
    case.config.findScreen = function(_, value)
        if value.screen.uuid == firstScreen:getUUID() then
            return firstScreen
        end
        if value.screen.uuid == secondScreen:getUUID() then
            return secondScreen
        end
        return case.screen
    end
    case.controller:start()
    case.controller:selectMonitor()
    case.controller:selectMonitor()
    local olderCallback = case.selectCallbacks[1]
    local newerCallback = case.selectCallbacks[2]

    newerCallback(secondScreen)
    olderCallback(firstScreen)

    test.equal(case.defaultForScreenCalls, 1)
    test.equal(#case.calibrationStarts, 1)
    test.equal(case.calibrationStarts[1].screen, secondScreen)
    test.equal(case.controller.calibrationScreen, secondScreen)
    test.equal(case.controller.calibrationValue.screen.uuid, "second-uuid")
end)

test.test("failed monitor chooser startup revokes a retained callback", function()
    for _, mode in ipairs({ "nil", "error" }) do
        local case = newCase({ configuration = validConfig(true), accessibility = true })
        local retainedCallback
        case.calibration.selectScreen = function(_, callback)
            retainedCallback = callback
            if mode == "error" then
                error("chooser startup failure", 0)
            end
            return nil
        end
        case.controller:start()

        local selected, selectError = case.controller:selectMonitor()
        retainedCallback(case.screen)

        test.equal(selected, nil)
        if mode == "error" then
            test.equal(string.find(selectError, "chooser startup failure", 1, true) ~= nil, true)
        end
        test.equal(case.defaultForScreenCalls, 0)
        test.equal(#case.calibrationStarts, 0)
        test.equal(case.controller.calibrating, nil)
    end
end)

test.test("first-run screen watcher invalidates the pending monitor chooser", function()
    local case = newCase({ accessibility = true })
    case.controller:start()
    local staleCallback = case.selectCallback

    case.screenCallback()
    staleCallback(case.screen)

    test.equal(case.defaultForScreenCalls, 0)
    test.equal(#case.calibrationStarts, 0)
    test.equal(case.controller.calibrating, nil)
end)

test.test("unrelated topology watcher invalidates the pending monitor chooser", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:selectMonitor()
    local staleCallback = case.selectCallback

    case.screenCallback()
    staleCallback(case.screen)

    test.equal(case.controller.screen, case.screen)
    test.equal(case.defaultForScreenCalls, 0)
    test.equal(#case.calibrationStarts, 0)
    test.equal(case.controller.calibrating, nil)
end)

test.test("successful toggles invalidate pending monitor chooser callbacks", function()
    for _, transition in ipairs({
        { enabled = true, method = "disable" },
        { enabled = false, method = "enable" },
    }) do
        local case = newCase({
            configuration = validConfig(transition.enabled),
            accessibility = true,
        })
        case.controller:start()
        case.controller:selectMonitor()
        local staleCallback = case.selectCallback

        case.controller[transition.method](case.controller)
        staleCallback(case.screen)

        test.equal(case.defaultForScreenCalls, 0)
        test.equal(#case.calibrationStarts, 0)
        test.equal(case.controller.calibrating, false)
    end
end)

test.test("direct calibration invalidates a pending monitor chooser callback", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:selectMonitor()
    local staleCallback = case.selectCallback

    case.controller:calibrate()
    staleCallback(case.screen)

    test.equal(case.defaultForScreenCalls, 0)
    test.equal(#case.calibrationStarts, 1)
    test.equal(case.controller.calibrating, true)
    test.equal(case.controller.calibrationScreen, case.screen)
end)

test.test("disconnect invalidates a pending monitor chooser callback", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:selectMonitor()
    local staleCallback = case.selectCallback

    case.connected = false
    case.screenCallback()
    staleCallback(case.screen)

    test.equal(case.defaultForScreenCalls, 0)
    test.equal(#case.calibrationStarts, 0)
    test.equal(case.controller.calibrating, nil)
end)

test.test("monitor chooser callbacks are one-shot and nil consumes the selection", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    case.controller:selectMonitor()
    local cancelledCallback = case.selectCallback

    cancelledCallback(nil)
    cancelledCallback(case.screen)

    test.equal(case.defaultForScreenCalls, 0)
    test.equal(#case.calibrationStarts, 0)
    test.equal(case.controller.calibrating, nil)

    case.controller:selectMonitor()
    local selectedCallback = case.selectCallback
    selectedCallback(case.screen)
    selectedCallback(case.screen)

    test.equal(case.defaultForScreenCalls, 1)
    test.equal(#case.calibrationStarts, 1)
    test.equal(case.controller.calibrating, true)
end)

test.test("first-run calibration disconnect clears the unsaved stale overlay", function()
    local case = newCase({ accessibility = false })
    local currentScreen = case.screen
    case.config.findScreen = function()
        return currentScreen
    end
    case.controller:start()
    case.selectCallback(case.screen)
    test.equal(#case.calibrationStarts, 1)
    test.equal(#case.overlayShows, 1)
    currentScreen = nil

    local callbackOk = pcall(case.screenCallback)

    test.equal(callbackOk, true)
    test.equal(case.calibrationStopCount, 1)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationScreen, nil)
    test.equal(case.controller.screen, nil)
    test.equal(case.overlayDeleteCount, 2)
    test.equal(#case.overlayShows, 1)
    test.equal(#case.saveCalls, 0)
    test.equal(#case.notify.notifications, 1)
end)

test.test("monitor selection does not open calibration after the chosen screen disappears", function()
    local case = newCase({ accessibility = false, connected = false })
    case.controller:start()

    case.selectCallback(case.screen)

    test.equal(#case.calibrationStarts, 0)
    test.equal(case.calibrationStopCount, 1)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationValue, nil)
    test.equal(case.controller.calibrationScreen, nil)
    test.equal(case.controller.screen, nil)
    test.equal(case.overlayDeleteCount, 2)
    test.equal(#case.notify.notifications, 1)
end)

test.test("monitor selection rejects an ambiguous UUID-less screen without orphan state", function()
    local ambiguousScreen = fake.screen(nil, "Mirrored Display", {
        x = 0,
        y = 0,
        w = 1920,
        h = 1080,
    })
    local case = newCase({ accessibility = false, screen = ambiguousScreen })
    case.config.defaultForScreen = function()
        local value = validConfig(true)
        value.screen.uuid = nil
        value.screen.name = "Mirrored Display"
        value.screen.width = 1920
        value.screen.height = 1080
        return value
    end
    case.config.findScreen = function()
        return nil
    end
    case.controller:start()

    case.selectCallback(ambiguousScreen)

    test.equal(#case.calibrationStarts, 0)
    test.equal(case.controller.calibrating, false)
    test.equal(case.controller.calibrationValue, nil)
    test.equal(case.controller.calibrationScreen, nil)
    test.equal(case.controller.screen, nil)
    test.equal(#case.notify.notifications, 1)
end)

test.test("monitor selection starts calibration on the resolver's live screen object", function()
    local chosen = fake.screen("damaged-uuid", "Damaged Display", {
        x = -3440,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local live = fake.screen("damaged-uuid", "Damaged Display", {
        x = 0,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local case = newCase({ accessibility = false, screen = chosen })
    case.config.findScreen = function()
        return live
    end
    case.controller:start()

    case.selectCallback(chosen)

    test.equal(#case.calibrationStarts, 1)
    test.equal(case.calibrationStarts[1].screen, live)
    test.equal(case.controller.calibrationScreen, live)
    test.equal(case.controller.screen, live)
end)

test.test("monitor selection opens calibration and Save persists the new display", function()
    local case = newCase({ accessibility = false })
    case.controller:start()

    case.selectCallback(case.screen)

    test.equal(#case.calibrationStarts, 1)
    test.equal(case.calibrationStarts[1].screen, case.screen)
    test.equal(#case.overlayShows, 1)
    test.equal(#case.guardStarts, 0)

    case.calibrationStarts[1].onSave(case.calibrationStarts[1].bands)

    test.equal(#case.saveCalls, 1)
    test.equal(case.controller.value.screen.uuid, "damaged-uuid")
end)

test.test("start creates a dynamic ScreenFix menu with runtime actions", function()
    local case = newCase({ configuration = validConfig(true), accessibility = false })
    case.controller:start()

    test.equal(#case.menubar.newCalls, 1)
    test.equal(case.menubar.newCalls[1].inMenuBar, true)
    test.equal(case.menubar.newCalls[1].autosaveName, "ScreenFix")
    local item = case.menubar.items[1]
    test.equal(item.title, "SF")
    test.equal(type(item.menu), "function")

    local items = item.menu()
    test.equal(menuItem(items, "Paused: Allow Accessibility in System Settings").disabled, true)
    test.equal(type(menuItem(items, "Disable").fn), "function")
    test.equal(type(menuItem(items, "Calibrate").fn), "function")
    test.equal(type(menuItem(items, "Select Monitor").fn), "function")
    test.equal(type(menuItem(items, "Reload").fn), "function")

    menuItem(items, "Disable").fn()
    test.equal(menuItem(item.menu(), "Enable") ~= nil, true)
    menuItem(item.menu(), "Reload").fn()
    test.equal(case.reloadCount, 1)
end)

test.test("dynamic menu keeps checked, disabled, and permission guidance current", function()
    local case = newCase({ configuration = validConfig(true), accessibility = false })
    case.controller:start()
    local menu = case.menubar.items[1].menu

    local items = menu()
    local paused = menuItem(items, "Paused: Allow Accessibility in System Settings")
    test.equal(paused ~= nil, true)
    test.equal(paused.checked, false)
    test.equal(paused.disabled, true)
    test.equal(menuItem(items, "Disable").checked, true)
    test.equal(menuItem(items, "Disable").disabled, false)
    test.equal(menuItem(items, "Calibrate").checked, false)
    test.equal(menuItem(items, "Calibrate").disabled, false)
    test.equal(menuItem(items, "Select Monitor").checked, false)
    test.equal(menuItem(items, "Select Monitor").disabled, false)
    test.equal(menuItem(items, "Reload").checked, false)
    test.equal(menuItem(items, "Reload").disabled, false)

    menuItem(items, "Disable").fn()
    items = menu()
    test.equal(menuItem(items, "Enable").checked, false)
    test.equal(menuItem(items, "Enable").disabled, false)
    test.equal(menuItem(items, "Paused: Allow Accessibility in System Settings"), nil)

    case.connected = false
    case.screenCallback()
    test.equal(menuItem(menu(), "Calibrate").disabled, true)
    case.connected = true
    case.screenCallback()
    test.equal(menuItem(menu(), "Calibrate").disabled, false)

    menuItem(menu(), "Enable").fn()
    test.equal(menuItem(menu(), "Disable").checked, true)
    test.equal(menuItem(menu(), "Paused: Allow Accessibility in System Settings") ~= nil, true)
    case.accessibility = true
    case.hs.accessibilityStateCallback()
    test.equal(menuItem(menu(), "Paused: Allow Accessibility in System Settings"), nil)
end)

test.test("stop attempts every owned cleanup, restores callbacks, and is idempotent", function()
    local priorCallback = function()
    end
    local case = newCase({
        configuration = validConfig(true),
        accessibility = true,
        previousAccessibilityCallback = priorCallback,
    })
    case.controller:start()
    local item = case.menubar.items[1]
    item.deleteError = "menubar delete failure"
    case.config.stopWatching = function()
        case.stopWatchingCount = case.stopWatchingCount + 1
        error("watcher stop failure", 0)
    end
    case.calibration.stop = function()
        case.calibrationStopCount = (case.calibrationStopCount or 0) + 1
        error("calibration stop failure", 0)
    end
    case.guard.stop = function()
        case.guardStopCount = case.guardStopCount + 1
        error("guard stop failure", 0)
    end
    case.overlay.delete = function()
        case.overlayDeleteCount = case.overlayDeleteCount + 1
        error("overlay delete failure", 0)
    end

    local firstOk = pcall(function()
        case.controller:stop()
    end)
    local secondOk = pcall(function()
        case.controller:stop()
    end)

    test.equal(firstOk, true)
    test.equal(secondOk, true)
    test.equal(case.stopWatchingCount, 1)
    test.equal(case.calibrationStopCount, 1)
    test.equal(case.guardStopCount, 1)
    test.equal(case.overlayDeleteCount, 1)
    test.equal(item.deleteCount, 1)
    test.equal(case.hs.accessibilityStateCallback, priorCallback)
    test.equal(case.controller.started, false)
end)

test.test("owned watcher, Accessibility, and menu callbacks contain runtime errors", function()
    local case = newCase({ configuration = validConfig(true), accessibility = true })
    case.controller:start()
    local item = case.menubar.items[1]
    case.controller.refresh = function()
        error("refresh failure", 0)
    end
    case.controller.menuItems = function()
        error("menu failure", 0)
    end

    local watcherOk = pcall(case.screenCallback)
    local accessibilityOk = pcall(case.hs.accessibilityStateCallback)
    local menuOk, menu = pcall(item.menu)

    test.equal(watcherOk, true)
    test.equal(accessibilityOk, true)
    test.equal(menuOk, true)
    test.equal(#menu, 0)
end)
