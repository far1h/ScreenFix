local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/init%.lua$")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local previousRuntime = _G.screenFixRuntime
_G.screenFixRuntime = nil
if previousRuntime then
    pcall(function()
        previousRuntime:stop()
    end)
end

local geometry = require("screenfix.geometry")
local ScreenConfig = require("screenfix.screen_config")
local MaskOverlay = require("screenfix.mask_overlay")
local WindowGuard = require("screenfix.window_guard")
local Calibration = require("screenfix.calibration")
local Controller = require("screenfix.controller")

local screenConfig = ScreenConfig.new({
    settings = hs.settings,
    allScreens = function()
        return hs.screen.allScreens()
    end,
    newScreenWatcher = function(callback)
        return hs.screen.watcher.new(callback)
    end,
})

local overlay = MaskOverlay.new({
    canvas = hs.canvas,
    geometry = geometry,
    hideDockIcon = function()
        hs.dockicon.hide()
    end,
})

local windowFilter = hs.window.filter
local guard = WindowGuard.new({
    geometry = geometry,
    timer = hs.timer,
    now = function()
        return hs.timer.secondsSinceEpoch()
    end,
    filterFactory = function()
        return windowFilter.new():setOverrideFilter({
            visible = true,
            fullscreen = false,
            currentSpace = true,
        })
    end,
    events = {
        windowFilter.windowCreated,
        windowFilter.windowMoved,
        windowFilter.windowOnScreen,
    },
})

local calibration = Calibration.new({
    canvas = hs.canvas,
    chooser = hs.chooser,
    eventtap = hs.eventtap,
    screens = function()
        return hs.screen.allScreens()
    end,
    mouseButtons = function()
        return hs.eventtap.checkMouseButtons()
    end,
    reportError = function(err)
        hs.showError(err)
    end,
    geometry = geometry,
})

local runtime = Controller.new({
    hs = hs,
    geometry = geometry,
    config = screenConfig,
    overlay = overlay,
    guard = guard,
    calibration = calibration,
    menuIcon = hs.configdir .. "/ScreenFix/assets/screenfix-menubar.png",
})
local started, startError = pcall(runtime.start, runtime)
if not started then
    pcall(runtime.stop, runtime)
    error(startError, 0)
end

_G.screenFixRuntime = runtime
