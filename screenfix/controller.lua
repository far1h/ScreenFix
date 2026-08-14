local M = {}
local Controller = {}
Controller.__index = Controller
local startCalibration

local function call(method, object, ...)
    if type(method) ~= "function" then
        return nil
    end

    local ok, first, second = pcall(method, object, ...)
    if not ok then
        return nil, first
    end

    return first, second
end

local function callFunction(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, first, second = pcall(fn, ...)
    if not ok then
        return nil, first
    end

    return first, second
end

local function withEnabled(value, enabled)
    return {
        schemaVersion = value.schemaVersion,
        enabled = enabled,
        screen = value.screen,
        bands = value.bands,
    }
end

local function withBands(value, bands)
    return {
        schemaVersion = value.schemaVersion,
        enabled = value.enabled,
        screen = value.screen,
        bands = bands,
    }
end

local function copyConfig(value)
    local bands = {}
    for index, band in ipairs(value.bands) do
        bands[index] = {
            x = band.x,
            y = band.y,
            w = band.w,
            h = band.h,
        }
    end

    return {
        schemaVersion = value.schemaVersion,
        enabled = value.enabled,
        screen = {
            uuid = value.screen.uuid,
            name = value.screen.name,
            width = value.screen.width,
            height = value.screen.height,
        },
        bands = bands,
    }
end

local function screenFrame(screen)
    local frame = call(screen and screen.fullFrame, screen)
    if type(frame) ~= "table"
        or type(frame.x) ~= "number"
        or type(frame.y) ~= "number"
        or type(frame.w) ~= "number"
        or type(frame.h) ~= "number"
    then
        return nil
    end

    return { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
end

local function sameFrame(left, right)
    return left ~= nil
        and right ~= nil
        and left.x == right.x
        and left.y == right.y
        and left.w == right.w
        and left.h == right.h
end

local function isCurrentSession(controller, token, target)
    local session = controller.calibrationSession
    return controller.started == true
        and session ~= nil
        and session.token == token
        and session.target == target
end

local function invalidateCalibration(controller, stopAdapter)
    controller.calibrationGeneration = controller.calibrationGeneration + 1
    controller.calibrationSession = nil
    controller.calibrating = false
    controller.calibrationValue = nil
    controller.calibrationScreen = nil
    if stopAdapter then
        call(controller.deps.calibration.stop, controller.deps.calibration)
    end
end

local function invalidateChooser(controller)
    controller.chooserGeneration = controller.chooserGeneration + 1
    controller.chooserToken = nil
end

---Creates a runtime controller from explicit Hammerspoon adapters.
function M.new(deps)
    return setmetatable({
        deps = deps,
        calibrationGeneration = 0,
        chooserGeneration = 0,
        notified = {},
        started = false,
    }, Controller)
end

---Sends a notification once for the current condition episode.
function Controller:notifyOnce(key, message)
    if self.notified[key] then
        return false
    end

    self.notified[key] = true
    local notify = self.deps.hs.notify
    local notification = notify and callFunction(notify.new, {
        title = "ScreenFix",
        informativeText = message,
    })
    call(notification and notification.send, notification)
    return true
end

---Opens the monitor chooser.
function Controller:selectMonitor()
    if self.started ~= true then
        return false
    end

    invalidateChooser(self)
    local token = self.chooserGeneration
    self.chooserToken = token
    return call(self.deps.calibration.selectScreen, self.deps.calibration, function(screen)
        if self.started ~= true or self.chooserToken ~= token then
            return
        end
        self.chooserToken = nil

        pcall(function()
            if screen == nil then
                return
            end

            local value, valueError = call(
                self.deps.config.defaultForScreen,
                self.deps.config,
                screen
            )
            if self.started ~= true or self.chooserGeneration ~= token then
                return
            end
            if value == nil then
                callFunction(self.deps.hs.showError, tostring(valueError or "Unable to configure display"))
                return
            end

            startCalibration(self, value, screen)
        end)
    end)
end

local function saveEnabled(controller, enabled)
    if controller.value == nil then
        return controller:selectMonitor()
    end

    local saved, saveError = call(
        controller.deps.config.save,
        controller.deps.config,
        withEnabled(controller.value, enabled)
    )
    if saved == nil then
        callFunction(controller.deps.hs.showError, tostring(saveError or "Unable to save ScreenFix settings"))
        return nil, saveError
    end

    invalidateChooser(controller)
    controller.value = saved
    invalidateCalibration(controller, true)
    controller:refresh()
    return true
end

---Enables the saved mask configuration.
function Controller:enable()
    return saveEnabled(self, true)
end

---Disables and tears down the saved mask configuration.
function Controller:disable()
    return saveEnabled(self, false)
end

local function cancelCalibration(controller, token, target)
    if not isCurrentSession(controller, token, target) then
        return false
    end

    invalidateCalibration(controller, false)
    controller:refresh()
    return true
end

startCalibration = function(controller, value, screen)
    if controller.started ~= true then
        return false
    end

    invalidateChooser(controller)
    if controller.calibrating then
        invalidateCalibration(controller, true)
    end

    controller.calibrationGeneration = controller.calibrationGeneration + 1
    local target = copyConfig(value)
    local session = {
        fullFrame = nil,
        screen = screen,
        target = target,
        token = controller.calibrationGeneration,
    }
    controller.calibrationSession = session
    controller.calibrating = true
    controller.calibrationValue = target
    controller.calibrationScreen = screen
    controller:refresh()
    if controller.calibrating ~= true
        or controller.calibrationScreen == nil
        or controller.calibrationScreen ~= controller.screen
    then
        return false
    end
    screen = controller.calibrationScreen

    local started, startError = call(
        controller.deps.calibration.start,
        controller.deps.calibration,
        screen,
        target.bands,
        function(bands)
            local saved, saveError = controller:saveCalibration(
                bands,
                session.token,
                target
            )
            if saved == nil then
                error(saveError or "Unable to save calibration", 0)
            end
        end,
        function()
            cancelCalibration(controller, session.token, target)
        end
    )
    if started ~= true then
        if isCurrentSession(controller, session.token, target) then
            invalidateCalibration(controller, false)
            controller:refresh()
        end
        callFunction(controller.deps.hs.showError, tostring(startError or "Unable to start calibration"))
        return nil, startError
    end

    return true
end

---Starts direct calibration for the selected display.
function Controller:calibrate()
    if self.value == nil then
        return self:selectMonitor()
    end

    local screen = call(
        self.deps.config.findScreen,
        self.deps.config,
        self.value
    )
    self.screen = screen
    if screen == nil then
        self:refresh()
        return nil, "selected display is disconnected"
    end

    return startCalibration(self, self.value, screen)
end

---Persists edited bands and restores normal runtime behavior.
function Controller:saveCalibration(bands, token, target)
    local session = self.calibrationSession
    token = token or (session and session.token)
    target = target or (session and session.target)
    if not isCurrentSession(self, token, target) then
        return false, "stale calibration session"
    end

    local saved, saveError = call(
        self.deps.config.save,
        self.deps.config,
        withBands(target, bands)
    )
    if saved == nil then
        return nil, saveError
    end

    self.value = saved
    invalidateCalibration(self, false)
    self:refresh()
    return true
end

---Reconciles overlays and correction with current runtime state.
function Controller:refresh(useCachedAccessibility)
    if not self.started then
        return
    end

    if not useCachedAccessibility then
        local trusted = callFunction(self.deps.hs.accessibilityState, false)
        self.accessibilityTrusted = trusted == true
    end

    local value = self.calibrationValue or self.value
    if value == nil then
        self.screen = nil
        call(self.deps.guard.stop, self.deps.guard)
        call(self.deps.overlay.delete, self.deps.overlay)
        return
    end

    local screen = call(self.deps.config.findScreen, self.deps.config, value)
    local topologyFrameError = false
    if self.calibrating then
        local session = self.calibrationSession
        local currentFrame = screenFrame(screen)
        if screen == nil or currentFrame == nil then
            topologyFrameError = screen ~= nil
            invalidateCalibration(self, true)
        elseif session.fullFrame == nil then
            session.fullFrame = currentFrame
            session.screen = screen
            self.calibrationScreen = screen
        elseif not sameFrame(session and session.fullFrame, currentFrame) then
            invalidateCalibration(self, true)
        else
            session.screen = screen
            self.calibrationScreen = screen
        end

        if not self.calibrating and self.value ~= nil then
            value = self.value
            screen = call(self.deps.config.findScreen, self.deps.config, value)
        end
    end
    self.screen = screen
    if screen ~= nil then
        self.notified.disconnected = nil
    end
    if topologyFrameError then
        call(self.deps.guard.stop, self.deps.guard)
        call(self.deps.overlay.delete, self.deps.overlay)
        return
    end
    if value.enabled ~= true and not self.calibrating then
        call(self.deps.guard.stop, self.deps.guard)
        call(self.deps.overlay.delete, self.deps.overlay)
        return
    end
    if screen == nil then
        invalidateChooser(self)
        call(self.deps.guard.stop, self.deps.guard)
        call(self.deps.overlay.delete, self.deps.overlay)
        self:notifyOnce("disconnected", "The selected display is disconnected.")
        return
    end

    local shown = call(self.deps.overlay.show, self.deps.overlay, screen, value.bands)
    if shown ~= true or self.accessibilityTrusted ~= true or self.calibrating then
        call(self.deps.guard.stop, self.deps.guard)
        return
    end

    local fullFrame = call(screen.fullFrame, screen)
    local maskRects = callFunction(self.deps.geometry.absoluteBands, fullFrame, value.bands)
    if maskRects == nil then
        call(self.deps.guard.stop, self.deps.guard)
        return
    end

    call(self.deps.guard.start, self.deps.guard, screen, maskRects)
end

local function protectedAction(fn)
    return function()
        pcall(fn)
    end
end

---Builds the current dynamic menubar contents.
function Controller:menuItems()
    local items = {}
    if self.value and self.value.enabled and not self.accessibilityTrusted then
        items[#items + 1] = {
            title = "Paused: Allow Accessibility in System Settings",
            checked = false,
            disabled = true,
        }
    end

    local enabled = self.value ~= nil and self.value.enabled == true
    items[#items + 1] = {
        title = enabled and "Disable" or "Enable",
        checked = enabled,
        disabled = false,
        fn = protectedAction(function()
            if enabled then
                self:disable()
            else
                self:enable()
            end
        end),
    }
    items[#items + 1] = {
        title = "Calibrate",
        checked = self.calibrating == true,
        disabled = self.value == nil or self.screen == nil,
        fn = protectedAction(function()
            self:calibrate()
        end),
    }
    items[#items + 1] = {
        title = "Select Monitor",
        checked = false,
        disabled = false,
        fn = protectedAction(function()
            self:selectMonitor()
        end),
    }
    items[#items + 1] = {
        title = "Reload",
        checked = false,
        disabled = false,
        fn = protectedAction(function()
            callFunction(self.deps.hs.reload)
        end),
    }
    return items
end

local function createMenu(controller)
    local menubar = controller.deps.hs.menubar
    local item = menubar and callFunction(menubar.new, true, "ScreenFix")
    if item == nil then
        return
    end

    local titleSet = call(item.setTitle, item, "SF")
    if titleSet == nil then
        call(item.delete, item)
        return
    end
    local menuSet = call(item.setMenu, item, function()
        local ok, items = pcall(controller.menuItems, controller)
        return ok and items or {}
    end)
    if menuSet == nil then
        call(item.delete, item)
        return
    end

    controller.menu = item
end

---Starts ScreenFix once.
function Controller:start()
    if self.started then
        return self
    end

    self.started = true
    createMenu(self)
    local trusted = callFunction(self.deps.hs.accessibilityState, true)
    self.accessibilityTrusted = trusted == true
    local value = call(self.deps.config.load, self.deps.config)
    self.value = value
    local watch = self.deps.config.watch
    local watchOk
    local watchError
    if type(watch) == "function" then
        watchOk, watchError = pcall(watch, self.deps.config, function()
            pcall(function()
                self:refresh()
            end)
        end)
    else
        watchOk = false
        watchError = "screen watcher is required"
    end
    if not watchOk then
        self:stop()
        error(watchError, 0)
    end
    self.previousAccessibilityCallback = self.deps.hs.accessibilityStateCallback
    local previousAccessibilityCallback = self.previousAccessibilityCallback
    local accessibilityCallback
    accessibilityCallback = function()
        callFunction(previousAccessibilityCallback)
        if self.started
            and self.accessibilityCallback == accessibilityCallback
            and self.deps.hs.accessibilityStateCallback == accessibilityCallback
        then
            pcall(function()
                self:refresh()
            end)
        end
    end
    self.accessibilityCallback = accessibilityCallback
    self.deps.hs.accessibilityStateCallback = self.accessibilityCallback

    self:refresh(true)

    if value == nil then
        self:selectMonitor()
    end

    return self
end

---Stops and releases every resource owned by the controller.
function Controller:stop()
    if not self.started then
        return
    end

    self.started = false
    local menu = self.menu
    local accessibilityCallback = self.accessibilityCallback
    local previousAccessibilityCallback = self.previousAccessibilityCallback
    self.menu = nil
    self.accessibilityCallback = nil
    self.previousAccessibilityCallback = nil
    invalidateChooser(self)
    invalidateCalibration(self, false)
    self.screen = nil

    pcall(function()
        if self.deps.hs.accessibilityStateCallback == accessibilityCallback then
            self.deps.hs.accessibilityStateCallback = previousAccessibilityCallback
        end
    end)
    call(self.deps.config.stopWatching, self.deps.config)
    call(self.deps.calibration.stop, self.deps.calibration)
    call(self.deps.guard.stop, self.deps.guard)
    call(self.deps.overlay.delete, self.deps.overlay)
    call(menu and menu.delete, menu)
end

return M
