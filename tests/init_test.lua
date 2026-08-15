local test = require("tests.test_helper")
local fake = require("tests.fake_hs")
local RealController = require("screenfix.controller")

local moduleNames = {
    "screenfix.geometry",
    "screenfix.screen_config",
    "screenfix.mask_overlay",
    "screenfix.window_guard",
    "screenfix.calibration",
    "screenfix.controller",
}

local function keyCount(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function withBootstrap(options, verify)
    options = options or {}
    local previousHs = _G.hs
    local previousRuntime = _G.screenFixRuntime
    local previousPath = package.path
    local previousLoaded = {}
    local previousPreload = {}
    for _, name in ipairs(moduleNames) do
        previousLoaded[name] = package.loaded[name]
        previousPreload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local captured = {
        dockHideCount = 0,
        oldStopCount = 0,
        realRuntimes = {},
        showErrors = {},
        wakeWatchers = {},
        watcherNewCalls = {},
        windowFilterNewCount = 0,
    }
    local screens = { { marker = "screen" } }
    local watcher = { marker = "watcher" }
    local windowFilter = {
        windowCreated = {},
        windowMoved = {},
        windowOnScreen = {},
    }
    function windowFilter.new()
        captured.windowFilterNewCount = captured.windowFilterNewCount + 1
        local filter = {}
        function filter:setOverrideFilter(override)
            captured.override = override
            return self
        end
        captured.filter = filter
        return filter
    end
    local eventtap = fake.eventtap()
    eventtap.checkMouseButtons = function()
        return { left = false }
    end
    local hs = {
        caffeinate = {
            watcher = {
                screensDidWake = "screensDidWake",
                systemDidWake = "systemDidWake",
                new = function(callback)
                    local wakeWatcher = fake.watcher(callback)
                    wakeWatcher.startError = options.wakeWatcherError
                    captured.wakeWatchers[#captured.wakeWatchers + 1] = wakeWatcher
                    return wakeWatcher
                end,
            },
        },
        canvas = { marker = "canvas" },
        chooser = { marker = "chooser" },
        menubar = fake.menubar(),
        notify = fake.notify(),
        accessibilityState = function()
            return true
        end,
        accessibilityStateCallback = options.previousAccessibilityCallback,
        dockicon = {
            hide = function()
                captured.dockHideCount = captured.dockHideCount + 1
            end,
        },
        eventtap = eventtap,
        screen = {
            allScreens = function()
                return screens
            end,
            watcher = {
                new = function(callback)
                    captured.watcherNewCalls[#captured.watcherNewCalls + 1] = callback
                    return watcher
                end,
            },
        },
        settings = { marker = "settings" },
        showError = function(message)
            captured.showErrors[#captured.showErrors + 1] = message
        end,
        timer = {
            doAfter = function()
            end,
            secondsSinceEpoch = function()
                return 42
            end,
        },
        window = {
            filter = windowFilter,
        },
    }
    local geometry = { marker = "geometry" }
    local screenConfig = { marker = "screen-config" }
    function screenConfig:load()
        return nil
    end
    function screenConfig:watch(callback)
        captured.configWatchCount = (captured.configWatchCount or 0) + 1
        captured.screenCallback = callback
        if options.watcherError then
            error(options.watcherError, 0)
        end
    end
    function screenConfig:stopWatching()
        captured.configStopWatchingCount = (captured.configStopWatchingCount or 0) + 1
    end
    local overlay = { marker = "overlay" }
    function overlay:delete()
        captured.overlayDeleteCount = (captured.overlayDeleteCount or 0) + 1
    end
    local guard = { marker = "guard" }
    function guard:stop()
        captured.guardStopCount = (captured.guardStopCount or 0) + 1
    end
    local calibration = { marker = "calibration" }
    function calibration:selectScreen()
        captured.selectScreenCount = (captured.selectScreenCount or 0) + 1
        return true
    end
    function calibration:stop()
        captured.calibrationStopCount = (captured.calibrationStopCount or 0) + 1
    end
    local runtime = {
        marker = "runtime",
        startCount = 0,
        stopCount = 0,
    }
    function runtime:start()
        self.startCount = self.startCount + 1
        if options.startError then
            error(options.startError, 0)
        end
    end
    function runtime:stop()
        self.stopCount = self.stopCount + 1
    end
    local oldRuntime = {
        stop = function()
            captured.oldStopCount = captured.oldStopCount + 1
            if options.oldStopError then
                error(options.oldStopError, 0)
            end
        end,
    }
    local modules = {
        ["screenfix.geometry"] = geometry,
        ["screenfix.screen_config"] = {
            new = function(deps)
                captured.screenConfigDeps = deps
                return screenConfig
            end,
        },
        ["screenfix.mask_overlay"] = {
            new = function(deps)
                captured.overlayDeps = deps
                return overlay
            end,
        },
        ["screenfix.window_guard"] = {
            new = function(deps)
                captured.guardDeps = deps
                return guard
            end,
        },
        ["screenfix.calibration"] = {
            new = function(deps)
                captured.calibrationDeps = deps
                return calibration
            end,
        },
        ["screenfix.controller"] = options.realController and {
            new = function(deps)
                captured.controllerDeps = deps
                captured.packagePath = package.path
                captured.realRuntime = RealController.new(deps)
                captured.realRuntimes[#captured.realRuntimes + 1] = captured.realRuntime
                return captured.realRuntime
            end,
        } or {
            new = function(deps)
                captured.controllerDeps = deps
                captured.packagePath = package.path
                if options.constructorError then
                    error(options.constructorError, 0)
                end
                return runtime
            end,
        },
    }
    for name, module in pairs(modules) do
        package.preload[name] = function()
            return module
        end
    end
    _G.hs = hs
    _G.screenFixRuntime = oldRuntime

    local chunk, loadError = loadfile("./init.lua")
    local runOk
    local runError
    if chunk then
        runOk, runError = pcall(chunk)
    else
        runOk, runError = false, loadError
    end
    local verifyOk, verifyError = pcall(
        verify,
        captured,
        runOk,
        runError,
        hs,
        geometry,
        screenConfig,
        overlay,
        guard,
        calibration,
        runtime,
        screens,
        watcher,
        windowFilter
    )

    _G.hs = previousHs
    _G.screenFixRuntime = previousRuntime
    package.path = previousPath
    for _, name in ipairs(moduleNames) do
        package.loaded[name] = previousLoaded[name]
        package.preload[name] = previousPreload[name]
    end

    if not verifyOk then
        error(verifyError, 0)
    end
end

test.test("init assembles exact production dependencies and starts one controller", function()
    withBootstrap({}, function(
        captured,
        runOk,
        runError,
        hs,
        geometry,
        screenConfig,
        overlay,
        guard,
        calibration,
        runtime,
        screens,
        watcher,
        windowFilter
    )
        test.equal(runOk, true)
        test.equal(runError, nil)
        test.equal(captured.oldStopCount, 1)
        test.equal(runtime.startCount, 1)
        test.equal(_G.screenFixRuntime, runtime)
        test.equal(string.find(captured.packagePath, "./?.lua;./?/init.lua;", 1, true), 1)

        test.equal(keyCount(captured.overlayDeps), 3)
        test.equal(captured.overlayDeps.canvas, hs.canvas)
        test.equal(captured.overlayDeps.geometry, geometry)
        test.equal(type(captured.overlayDeps.hideDockIcon), "function")
        captured.overlayDeps.hideDockIcon()
        test.equal(captured.dockHideCount, 1)

        test.equal(captured.screenConfigDeps.settings, hs.settings)
        test.equal(captured.screenConfigDeps.allScreens(), screens)
        local screenCallback = function()
        end
        test.equal(captured.screenConfigDeps.newScreenWatcher(screenCallback), watcher)
        test.equal(captured.watcherNewCalls[1], screenCallback)

        test.equal(captured.calibrationDeps.canvas, hs.canvas)
        test.equal(captured.calibrationDeps.chooser, hs.chooser)
        test.equal(hs.eventtap.event.types.mouseMoved, 5)
        test.equal(hs.eventtap.event.types.leftMouseDragged, 6)
        test.equal(hs.eventtap.event.types.leftMouseUp, 2)
        test.equal(captured.calibrationDeps.eventtap, hs.eventtap)
        test.equal(
            captured.calibrationDeps.eventtap.event.types.mouseMoved,
            hs.eventtap.event.types.mouseMoved
        )
        test.equal(
            captured.calibrationDeps.eventtap.event.types.leftMouseDragged,
            hs.eventtap.event.types.leftMouseDragged
        )
        test.equal(
            captured.calibrationDeps.eventtap.event.types.leftMouseUp,
            hs.eventtap.event.types.leftMouseUp
        )
        test.equal(captured.calibrationDeps.geometry, geometry)
        test.equal(type(captured.calibrationDeps.reportError), "function")
        captured.calibrationDeps.reportError("calibration failure")
        test.equal(captured.showErrors[1], "calibration failure")

        local filter = captured.guardDeps.filterFactory()
        test.equal(filter, captured.filter)
        test.equal(captured.windowFilterNewCount, 1)
        test.equal(keyCount(captured.override), 3)
        test.equal(captured.override.visible, true)
        test.equal(captured.override.fullscreen, false)
        test.equal(captured.override.currentSpace, true)
        test.equal(captured.guardDeps.events[1], windowFilter.windowCreated)
        test.equal(captured.guardDeps.events[2], windowFilter.windowMoved)
        test.equal(captured.guardDeps.events[3], windowFilter.windowOnScreen)
        test.equal(captured.guardDeps.now(), 42)

        test.equal(captured.controllerDeps.hs, hs)
        test.equal(captured.controllerDeps.hs.caffeinate, hs.caffeinate)
        test.equal(captured.controllerDeps.geometry, geometry)
        test.equal(captured.controllerDeps.config, screenConfig)
        test.equal(captured.controllerDeps.overlay, overlay)
        test.equal(captured.controllerDeps.guard, guard)
        test.equal(captured.controllerDeps.calibration, calibration)
    end)
end)

test.test("init reload stops the prior wake watcher before starting one replacement", function()
    withBootstrap({ realController = true }, function(captured, runOk)
        test.equal(runOk, true)
        test.equal(#captured.realRuntimes, 1)
        test.equal(#captured.wakeWatchers, 1)
        test.equal(captured.wakeWatchers[1].startCount, 1)

        local replacementChunk = assert(loadfile("./init.lua"))
        replacementChunk()

        test.equal(#captured.realRuntimes, 2)
        test.equal(captured.realRuntimes[1].started, false)
        test.equal(captured.wakeWatchers[1].stopCount, 1)
        test.equal(#captured.wakeWatchers, 2)
        test.equal(captured.wakeWatchers[2].startCount, 1)
        test.equal(captured.wakeWatchers[2].stopCount, 0)
        test.equal(_G.screenFixRuntime, captured.realRuntimes[2])
    end)
end)

test.test("init leaves no corrupt global when controller startup fails", function()
    withBootstrap({ startError = "start failure" }, function(captured, runOk, runError, _, _, _, _, _, _, runtime)
        test.equal(runOk, false)
        test.equal(string.find(runError, "start failure", 1, true) ~= nil, true)
        test.equal(captured.oldStopCount, 1)
        test.equal(runtime.stopCount, 1)
        test.equal(_G.screenFixRuntime, nil)
    end)
end)

test.test("init leaves no corrupt global when controller construction fails", function()
    withBootstrap({ constructorError = "constructor failure" }, function(captured, runOk, runError)
        test.equal(runOk, false)
        test.equal(string.find(runError, "constructor failure", 1, true) ~= nil, true)
        test.equal(captured.oldStopCount, 1)
        test.equal(_G.screenFixRuntime, nil)
    end)
end)

test.test("init rolls back a real controller when screen watcher startup fails", function()
    local priorCallback = function()
    end
    withBootstrap({
        previousAccessibilityCallback = priorCallback,
        realController = true,
        watcherError = "screen watcher startup failure",
    }, function(captured, runOk, runError, hs)
        test.equal(runOk, false)
        test.equal(string.find(runError, "screen watcher startup failure", 1, true) ~= nil, true)
        test.equal(captured.oldStopCount, 1)
        test.equal(captured.configWatchCount, 1)
        test.equal(captured.configStopWatchingCount, 1)
        test.equal(captured.calibrationStopCount, 1)
        test.equal(captured.guardStopCount, 1)
        test.equal(captured.overlayDeleteCount, 1)
        test.equal(hs.menubar.items[1].deleteCount, 1)
        test.equal(hs.accessibilityStateCallback, priorCallback)
        test.equal(captured.realRuntime.started, false)
        test.equal(_G.screenFixRuntime, nil)
    end)
end)

test.test("init rolls back a real controller when wake watcher startup fails", function()
    withBootstrap({
        realController = true,
        wakeWatcherError = "wake watcher startup failure",
    }, function(captured, runOk, runError)
        test.equal(runOk, false)
        test.equal(string.find(runError, "wake watcher startup failure", 1, true) ~= nil, true)
        test.equal(captured.configWatchCount, 1)
        test.equal(captured.configStopWatchingCount, 1)
        test.equal(#captured.wakeWatchers, 1)
        test.equal(captured.wakeWatchers[1].stopCount, 1)
        test.equal(captured.calibrationStopCount, 1)
        test.equal(captured.guardStopCount, 1)
        test.equal(captured.overlayDeleteCount, 1)
        test.equal(captured.realRuntime.started, false)
        test.equal(_G.screenFixRuntime, nil)
    end)
end)

test.test("init contains old-runtime stop errors and starts a clean replacement", function()
    withBootstrap({ oldStopError = "old stop failure" }, function(captured, runOk, _, _, _, _, _, _, _, runtime)
        test.equal(runOk, true)
        test.equal(captured.oldStopCount, 1)
        test.equal(runtime.startCount, 1)
        test.equal(_G.screenFixRuntime, runtime)
    end)
end)
