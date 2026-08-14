local M = {}
local Overlay = {}
Overlay.__index = Overlay

function M.new(deps)
    return setmetatable({ deps = deps, canvases = {}, hidden = true }, Overlay)
end

function Overlay:show(screen, bands)
    self:delete()

    local frames = self.deps.geometry.absoluteBands(screen:fullFrame(), bands)

    for _, frame in ipairs(frames) do
        local canvas = self.deps.canvas.new(frame)
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
        self.canvases[#self.canvases + 1] = canvas
    end

    self.hidden = false
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
    for _, canvas in ipairs(self.canvases) do
        canvas:delete()
    end
    self.canvases = {}
    self.hidden = true
end

return M
