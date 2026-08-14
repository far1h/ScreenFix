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

---Creates a runtime controller from explicit Hammerspoon adapters.
function M.new(deps)
    return setmetatable({
        deps = deps,
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
    return call(self.deps.calibration.selectScreen, self.deps.calibration, function(screen)
        pcall(function()
            if screen == nil then
                return
            end

            local value, valueError = call(
                self.deps.config.defaultForScreen,
                self.deps.config,
                screen
            )
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

    controller.value = saved
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

local function cancelCalibration(controller)
    controller.calibrating = false
    controller.calibrationValue = nil
    controller.calibrationScreen = nil
    controller:refresh()
end

startCalibration = function(controller, value, screen)
    controller.calibrating = true
    controller.calibrationValue = value
    controller.calibrationScreen = screen
    controller:refresh()

    local started, startError = call(
        controller.deps.calibration.start,
        controller.deps.calibration,
        screen,
        value.bands,
        function(bands)
            local saved, saveError = controller:saveCalibration(bands)
            if not saved then
                error(saveError or "Unable to save calibration", 0)
            end
        end,
        function()
            cancelCalibration(controller)
        end
    )
    if started ~= true then
        cancelCalibration(controller)
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

    local screen = self.screen or call(
        self.deps.config.findScreen,
        self.deps.config,
        self.value
    )
    if screen == nil then
        self:refresh()
        return nil, "selected display is disconnected"
    end

    return startCalibration(self, self.value, screen)
end

---Persists edited bands and restores normal runtime behavior.
function Controller:saveCalibration(bands)
    local value = self.calibrationValue or self.value
    if value == nil then
        return nil, "no calibration configuration"
    end

    local saved, saveError = call(
        self.deps.config.save,
        self.deps.config,
        withBands(value, bands)
    )
    if saved == nil then
        return nil, saveError
    end

    self.value = saved
    self.calibrating = false
    self.calibrationValue = nil
    self.calibrationScreen = nil
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
    if value == nil or (value.enabled ~= true and not self.calibrating) then
        call(self.deps.guard.stop, self.deps.guard)
        call(self.deps.overlay.delete, self.deps.overlay)
        return
    end

    local screen = self.calibrationScreen
        or call(self.deps.config.findScreen, self.deps.config, value)
    self.screen = screen
    if screen == nil then
        call(self.deps.guard.stop, self.deps.guard)
        call(self.deps.overlay.delete, self.deps.overlay)
        self:notifyOnce("disconnected", "The selected display is disconnected.")
        return
    end
    self.notified.disconnected = nil

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
            title = "Paused: Accessibility permission required",
            disabled = true,
        }
    end

    local enabled = self.value and self.value.enabled
    items[#items + 1] = {
        title = enabled and "Disable" or "Enable",
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
        disabled = self.value == nil or self.screen == nil,
        fn = protectedAction(function()
            self:calibrate()
        end),
    }
    items[#items + 1] = {
        title = "Select Monitor",
        fn = protectedAction(function()
            self:selectMonitor()
        end),
    }
    items[#items + 1] = {
        title = "Reload",
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
    call(self.deps.config.watch, self.deps.config, function()
        pcall(function()
            self:refresh()
        end)
    end)
    self.previousAccessibilityCallback = self.deps.hs.accessibilityStateCallback
    self.accessibilityCallback = function()
        pcall(function()
            self:refresh()
        end)
    end
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
    self.calibrating = false
    self.calibrationValue = nil
    self.calibrationScreen = nil
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
