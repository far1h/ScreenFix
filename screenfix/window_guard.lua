local M = {}
local WindowGuard = {}
WindowGuard.__index = WindowGuard
local RECENT_SECONDS = 0.25

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
end

function WindowGuard:stop()
    self.selectedScreen = nil
    self.maskRects = {}
    self.pending = {}
    self.recent = {}
    self.blockedUntil = {}
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
    if not self:isEligible(window) then
        return false
    end

    local id = window:id()
    local currentFrame = window:frame()
    if currentFrame == nil then
        return false
    end

    local now = self.deps.now()
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
        return false
    end

    self.recent[id] = nil
    local usableFrame = self.selectedScreen:frame()
    if usableFrame == nil then
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

    local actualFrame = window:frame()
    if actualFrame == nil
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
