local M = {}
local WindowGuard = {}
WindowGuard.__index = WindowGuard
local DEBOUNCE_SECONDS = 0.15
local RECENT_SECONDS = 0.25

local function pruneExpiredState(guard, now)
    for id, recent in pairs(guard.recent) do
        if recent.expiresAt <= now then
            guard.recent[id] = nil
        end
    end

    for id, blockedUntil in pairs(guard.blockedUntil) do
        if blockedUntil <= now then
            guard.blockedUntil[id] = nil
        end
    end
end

local function protectedCall(object, methodName)
    if object == nil then
        return
    end

    local methodOk, method = pcall(function()
        return object[methodName]
    end)
    if methodOk and type(method) == "function" then
        pcall(method, object)
    end
end

local function scheduleCorrection(guard, window)
    local idOk, id = pcall(function()
        return window:id()
    end)
    if not idOk or id == nil then
        return
    end

    local previousTimer = guard.pending[id]
    if previousTimer ~= nil then
        protectedCall(previousTimer, "stop")
    end
    guard.pending[id] = nil

    local timer
    local timerOk
    timerOk, timer = pcall(function()
        return guard.deps.timer.doAfter(DEBOUNCE_SECONDS, function()
            if guard.pending[id] ~= timer then
                return
            end

            guard.pending[id] = nil
            guard:correct(window)
        end)
    end)
    if timerOk and timer ~= nil then
        guard.pending[id] = timer
    end
end

function M.new(deps)
    return setmetatable({
        deps = deps,
        filter = nil,
        pending = {},
        recent = {},
        blockedUntil = {},
        selectedScreen = nil,
        maskRects = {},
    }, WindowGuard)
end

function WindowGuard:start(screen, maskRects)
    self.selectedScreen = screen
    self.maskRects = maskRects

    if self.filter ~= nil or type(self.deps.filterFactory) ~= "function" then
        return
    end

    local factoryOk, filter = pcall(self.deps.filterFactory)
    if not factoryOk or filter == nil then
        return
    end

    local subscribeOk = pcall(function()
        filter:subscribe(self.deps.events, function(window)
            if self.filter ~= filter then
                return
            end

            scheduleCorrection(self, window)
        end)
    end)
    if not subscribeOk then
        protectedCall(filter, "unsubscribeAll")
        protectedCall(filter, "pause")
        return
    end

    self.filter = filter
end

function WindowGuard:stop()
    local filter = self.filter
    local pending = self.pending
    self.filter = nil
    self.selectedScreen = nil
    self.maskRects = {}
    self.pending = {}
    self.recent = {}
    self.blockedUntil = {}

    for _, timer in pairs(pending or {}) do
        protectedCall(timer, "stop")
    end

    protectedCall(filter, "unsubscribeAll")
    protectedCall(filter, "pause")
end

function WindowGuard:isEligible(window)
    if window == nil or self.selectedScreen == nil then
        return false
    end

    if window:id() == nil or window:frame() == nil then
        return false
    end

    local windowScreen = window:screen()
    if windowScreen == nil then
        return false
    end

    local selectedUuid = self.selectedScreen:getUUID()
    local windowUuid = windowScreen:getUUID()

    return selectedUuid ~= nil
        and windowUuid == selectedUuid
        and window:isFullScreen() == false
        and window:isMinimized() == false
        and window:isVisible() == true
        and window:isStandard() == true
end

function WindowGuard:correct(window)
    local eligibilityOk, eligible = pcall(self.isEligible, self, window)
    if not eligibilityOk or eligible ~= true then
        return false
    end

    local idOk, id = pcall(window.id, window)
    if not idOk or id == nil then
        return false
    end

    local currentFrameOk, currentFrame = pcall(window.frame, window)
    if not currentFrameOk or currentFrame == nil then
        return false
    end

    local now = self.deps.now()
    pruneExpiredState(self, now)
    local blockedUntil = self.blockedUntil[id]
    if blockedUntil ~= nil and blockedUntil > now then
        return false
    end

    self.blockedUntil[id] = nil
    local recent = self.recent[id]
    if recent ~= nil
        and recent.expiresAt > now
        and self.deps.geometry.framesNear(currentFrame, recent.frame, 1)
    then
        self.recent[id] = nil
        return false
    end

    self.recent[id] = nil
    local usableFrameOk, usableFrame = pcall(
        self.selectedScreen.frame,
        self.selectedScreen
    )
    if not usableFrameOk or usableFrame == nil then
        return false
    end

    local target = self.deps.geometry.correctedFrame(
        currentFrame,
        usableFrame,
        self.maskRects
    )
    if target == nil then
        return false
    end

    local setOk, setError = pcall(function()
        window:setFrame(target, 0)
    end)
    if not setOk then
        self.blockedUntil[id] = now + 1
        return nil, setError
    end

    local actualFrameOk, actualFrame = pcall(window.frame, window)
    if not actualFrameOk
        or actualFrame == nil
        or not self.deps.geometry.framesNear(actualFrame, target, 1)
    then
        self.blockedUntil[id] = now + 1
        return false
    end

    self.recent[id] = {
        frame = target,
        expiresAt = now + RECENT_SECONDS,
    }
    return true
end

return M
