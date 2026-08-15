local M = {}
M.KEY = "screenfix.config"

local DEFAULT_LEFT = 1215 / 3440
local DEFAULT_WIDTH = (1920 - 1215) / 3440

local ScreenConfig = {}
ScreenConfig.__index = ScreenConfig

local function hasThreeBands(bands)
    if type(bands) ~= "table" then
        return false
    end

    local count = 0
    for _ in pairs(bands) do
        count = count + 1
    end

    return count == 3 and bands[1] ~= nil and bands[2] ~= nil and bands[3] ~= nil
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPositiveFiniteNumber(value)
    return isFiniteNumber(value) and value > 0
end

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function isValidBand(band)
    if type(band) ~= "table" then
        return false
    end

    if not isFiniteNumber(band.x)
        or not isFiniteNumber(band.y)
        or not isFiniteNumber(band.w)
        or not isFiniteNumber(band.h)
    then
        return false
    end

    return band.x >= 0
        and band.y >= 0
        and band.w > 0
        and band.h > 0
        and band.x + band.w <= 1
        and band.y + band.h <= 1
end

local function screenValidationError(screen)
    if type(screen) ~= "table" then
        return "screen is required"
    end

    if not isNonEmptyString(screen.name) then
        return "screen name must be a non-empty string"
    end

    if not isPositiveFiniteNumber(screen.width) or not isPositiveFiniteNumber(screen.height) then
        return "screen dimensions must be finite positive numbers"
    end

    if screen.uuid ~= nil and not isNonEmptyString(screen.uuid) then
        return "screen UUID must be a non-empty string when present"
    end

    return nil
end

function M.new(deps)
    return setmetatable({ deps = deps }, ScreenConfig)
end

function ScreenConfig:defaultForScreen(screen)
    local frame = screen:fullFrame()

    return {
        schemaVersion = 1,
        enabled = true,
        screen = {
            uuid = screen:getUUID(),
            name = screen:name(),
            width = frame.w,
            height = frame.h,
        },
        bands = {
            { x = DEFAULT_LEFT, y = 0.00, w = DEFAULT_WIDTH, h = 0.34 },
            { x = DEFAULT_LEFT, y = 0.34, w = DEFAULT_WIDTH, h = 0.39 },
            { x = DEFAULT_LEFT, y = 0.73, w = DEFAULT_WIDTH, h = 0.27 },
        },
    }
end

function ScreenConfig:validate(value)
    if type(value) ~= "table" then
        return nil, "configuration must be a table"
    end

    if value.schemaVersion ~= 1 then
        return nil, "unsupported schema version"
    end

    if type(value.enabled) ~= "boolean" then
        return nil, "enabled must be boolean"
    end

    local screenError = screenValidationError(value.screen)
    if screenError then
        return nil, screenError
    end

    if not hasThreeBands(value.bands) then
        return nil, "configuration must contain exactly three bands"
    end

    for _, band in ipairs(value.bands) do
        if not isValidBand(band) then
            return nil, "configuration contains an invalid band"
        end
    end

    return value
end

function ScreenConfig:save(value)
    local validated, message = self:validate(value)
    if not validated then
        return nil, message
    end

    self.deps.settings.set(M.KEY, validated)
    return validated
end

function ScreenConfig:load()
    return self:validate(self.deps.settings.get(M.KEY))
end

function ScreenConfig:findScreen(value)
    local screens = self.deps.allScreens()
    local uuid = value.screen.uuid

    if type(uuid) == "string" and uuid ~= "" then
        for _, screen in ipairs(screens) do
            if screen:getUUID() == uuid then
                return screen
            end
        end
    end

    local fallback
    for _, screen in ipairs(screens) do
        local frame = screen:fullFrame()
        if screen:name() == value.screen.name
            and frame.w == value.screen.width
            and frame.h == value.screen.height
        then
            if fallback then
                return nil
            end
            fallback = screen
        end
    end

    return fallback
end

function ScreenConfig:watch(callback)
    if self.screenWatcher then
        self.screenWatcher:stop()
    end

    self.screenWatcher = self.deps.newScreenWatcher(callback)
    self.screenWatcher:start()
end

function ScreenConfig:stopWatching()
    if not self.screenWatcher then
        return
    end

    self.screenWatcher:stop()
    self.screenWatcher = nil
end

return M
