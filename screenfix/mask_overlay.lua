local M = {}
local Overlay = {}
Overlay.__index = Overlay

local function deleteCanvases(canvases)
    for _, canvas in ipairs(canvases) do
        pcall(function()
            canvas:delete()
        end)
    end
end

local function configureCanvas(canvas)
    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 0, alpha = 1 },
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
    canvas:clickActivating(false)
    canvas:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary", "stationary" })
    canvas:level("screenSaver")
    canvas:show()
end

local function createCanvases(canvasModule, frames)
    local created = {}
    local built, buildError = pcall(function()
        for _, frame in ipairs(frames) do
            local canvas = canvasModule.new(frame)
            if not canvas then
                error("canvas construction failed", 0)
            end

            created[#created + 1] = canvas
            configureCanvas(canvas)
        end
    end)

    if not built then
        deleteCanvases(created)
        return nil, buildError
    end

    return created
end

function M.new(deps)
    return setmetatable({ deps = deps, canvases = {}, hidden = true, prepared = false }, Overlay)
end

function Overlay:show(screen, bands)
    if not self.prepared then
        local prepared, prepareError = pcall(self.deps.hideDockIcon)
        if not prepared then
            return nil, prepareError
        end

        self.prepared = true
    end

    local framesAvailable, frames = pcall(function()
        local fullFrame = screen:fullFrame()
        return self.deps.geometry.absoluteBands(fullFrame, bands)
    end)
    if not framesAvailable then
        return nil, frames
    end

    local created, buildError = createCanvases(self.deps.canvas, frames)
    if not created then
        return nil, buildError
    end

    deleteCanvases(self.canvases)
    self.canvases = created
    self.hidden = false
    return true
end

function Overlay:hide()
    if self.hidden then
        return
    end

    for _, canvas in ipairs(self.canvases) do
        canvas:hide()
    end
    self.hidden = true
end

function Overlay:delete()
    deleteCanvases(self.canvases)
    self.canvases = {}
    self.hidden = true
end

return M
