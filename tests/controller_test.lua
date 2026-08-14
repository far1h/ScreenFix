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

test.test("start prompts for monitor selection without valid configuration", function()
    local case = newCase()

    case.controller:start()

    test.equal(case.selectCalls, 1)
    test.equal(case.watchCalls, 1)
    test.equal(case.accessibilityCalls[1], true)
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

    case.calibrationStarts[1].onSave(changedBands)

    test.equal(#case.saveCalls, 1)
    test.equal(case.saveCalls[1].bands, changedBands)
    test.equal(case.controller.value.bands, changedBands)
    test.equal(case.controller.calibrating, false)
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

local function menuItem(items, title)
    for _, item in ipairs(items) do
        if item.title == title then
            return item
        end
    end
end

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
    test.equal(menuItem(items, "Paused: Accessibility permission required").disabled, true)
    test.equal(type(menuItem(items, "Disable").fn), "function")
    test.equal(type(menuItem(items, "Calibrate").fn), "function")
    test.equal(type(menuItem(items, "Select Monitor").fn), "function")
    test.equal(type(menuItem(items, "Reload").fn), "function")

    menuItem(items, "Disable").fn()
    test.equal(menuItem(item.menu(), "Enable") ~= nil, true)
    menuItem(item.menu(), "Reload").fn()
    test.equal(case.reloadCount, 1)
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
