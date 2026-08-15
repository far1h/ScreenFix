local M = {}
local Calibration = {}
Calibration.__index = Calibration
local CONTROL_HEIGHT = 40
local CONTROL_MARGIN = 24
local CONTROL_WIDTH = 96
local HANDLE_WIDTH = 8
local INSTRUCTION_HEIGHT = 40
local INSTRUCTION_WIDTH = 320

local function copyBands(bands)
    local copied = {}

    for index, band in ipairs(bands) do
        copied[index] = {
            x = band.x,
            y = band.y,
            w = band.w,
            h = band.h,
        }
    end

    return copied
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function validateBands(bands)
    if type(bands) ~= "table" or #bands ~= 3 then
        return nil, "calibration requires three bands"
    end

    for _, band in ipairs(bands) do
        if type(band) ~= "table"
            or not finite(band.x)
            or not finite(band.y)
            or not finite(band.w)
            or not finite(band.h)
            or band.x < 0
            or band.y < 0
            or band.w <= 0
            or band.h <= 0
            or band.x + band.w > 1
            or band.y + band.h > 1
        then
            return nil, "invalid calibration band"
        end
    end

    return true
end

local function screenRows(screens)
    local rows = {}

    for index, screen in ipairs(screens) do
        local frame = screen:fullFrame()
        rows[index] = {
            text = screen:name(),
            subText = string.format("%g x %g", frame.w, frame.h),
            uuid = screen:getUUID(),
            name = screen:name(),
            width = frame.w,
            height = frame.h,
            screenIndex = index,
        }
    end

    return rows
end

local function handleFrames(band)
    return {
        { x = band.x, y = band.y, w = HANDLE_WIDTH, h = band.h },
        { x = band.x + band.w - HANDLE_WIDTH, y = band.y, w = HANDLE_WIDTH, h = band.h },
        { x = band.x, y = band.y, w = band.w, h = HANDLE_WIDTH },
        { x = band.x, y = band.y + band.h - HANDLE_WIDTH, w = band.w, h = HANDLE_WIDTH },
    }
end

local function control(frame, color)
    return {
        type = "rectangle",
        action = "fill",
        fillColor = color,
        frame = frame,
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
    }
end

local function label(frame, text)
    return {
        type = "text",
        frame = frame,
        text = text,
        textAlignment = "center",
        textColor = { white = 1, alpha = 1 },
        textSize = 18,
    }
end

local function contains(frame, point)
    return point.x >= frame.x
        and point.x <= frame.x + frame.w
        and point.y >= frame.y
        and point.y <= frame.y + frame.h
end

local function deleteChooser(chooser)
    if chooser then
        pcall(function()
            chooser:delete()
        end)
    end
end

local function deleteEditor(editorCanvas)
    if editorCanvas then
        pcall(function()
            editorCanvas:mouseCallback(nil)
        end)
        pcall(function()
            editorCanvas:delete()
        end)
    end
end

local function stopEventTap(eventTap)
    if eventTap then
        pcall(function()
            eventTap:stop()
        end)
    end
end

function M.new(deps)
    return setmetatable({ deps = deps }, Calibration)
end

function Calibration:selectScreen(onSelect)
    local loaded, screens = pcall(self.deps.screens)
    if not loaded then
        return nil, screens
    end

    local rowsBuilt, rows = pcall(screenRows, screens)
    if not rowsBuilt then
        return nil, rows
    end

    local chooser
    local created, createError = pcall(function()
        chooser = self.deps.chooser.new(function(choice)
            if choice and screens[choice.screenIndex] then
                pcall(onSelect, screens[choice.screenIndex])
            end
        end)
        if not chooser then
            error("chooser construction failed", 0)
        end
        chooser:choices(rows)
        chooser:show()
    end)
    if not created then
        deleteChooser(chooser)
        return nil, createError
    end

    deleteChooser(self.screenChooser)
    self.screenChooser = chooser
    return true
end

function Calibration:draw()
    local localBands = self.deps.geometry.localBands(self.fullFrame, self.workingBands)
    self.editorCanvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 0, alpha = 0 },
        frame = { x = 0, y = 0, w = self.fullFrame.w, h = self.fullFrame.h },
        trackMouseByBounds = true,
        trackMouseDown = true,
    }

    for index, band in ipairs(localBands) do
        self.editorCanvas[index + 1] = {
            type = "rectangle",
            action = "strokeAndFill",
            fillColor = { red = 0.95, green = 0.12, blue = 0.08, alpha = 0.45 },
            frame = band,
            strokeColor = { red = 1, green = 0.55, blue = 0.15, alpha = 1 },
            strokeWidth = 3,
        }
    end

    local elementIndex = 5
    for _, band in ipairs(localBands) do
        for _, frame in ipairs(handleFrames(band)) do
            self.editorCanvas[elementIndex] = {
                type = "rectangle",
                action = "fill",
                fillColor = { white = 1, alpha = 1 },
                frame = frame,
            }
            elementIndex = elementIndex + 1
        end
    end

    local controlY = self.fullFrame.h - CONTROL_MARGIN - CONTROL_HEIGHT
    self.saveFrame = {
        x = CONTROL_MARGIN,
        y = controlY,
        w = CONTROL_WIDTH,
        h = CONTROL_HEIGHT,
    }
    self.cancelFrame = {
        x = CONTROL_MARGIN + CONTROL_WIDTH + CONTROL_MARGIN,
        y = controlY,
        w = CONTROL_WIDTH,
        h = CONTROL_HEIGHT,
    }
    self.editorCanvas[17] = control(self.saveFrame, { red = 0.10, green = 0.55, blue = 0.20, alpha = 1 })
    self.editorCanvas[18] = label(self.saveFrame, "Save")
    self.editorCanvas[19] = control(self.cancelFrame, { white = 0.25, alpha = 1 })
    self.editorCanvas[20] = label(self.cancelFrame, "Cancel")
    local instructionFrame = {
        x = CONTROL_MARGIN,
        y = CONTROL_MARGIN,
        w = INSTRUCTION_WIDTH,
        h = INSTRUCTION_HEIGHT,
    }
    self.editorCanvas[21] = {
        type = "rectangle",
        action = "strokeAndFill",
        fillColor = { white = 0, alpha = 0.82 },
        frame = instructionFrame,
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
        strokeColor = { white = 1, alpha = 1 },
        strokeWidth = 2,
    }
    self.editorCanvas[22] = label(instructionFrame, "Drag red bands or white edges")
end

function Calibration:beginDrag(point)
    if contains(self.saveFrame, point) then
        self:save()
        return
    end
    if contains(self.cancelFrame, point) then
        self:cancel()
        return
    end

    local bands = self.deps.geometry.localBands(self.fullFrame, self.workingBands)
    local hit = self.deps.geometry.editorHit(point, bands, HANDLE_WIDTH)
    if hit then
        hit.lastPoint = point
    end
    self.drag = hit
end

function Calibration:updateDrag(point)
    if not self.drag then
        return
    end

    local buttons = self.deps.mouseButtons()
    if not buttons.left then
        return
    end

    local delta = {
        x = point.x - self.drag.lastPoint.x,
        y = point.y - self.drag.lastPoint.y,
    }
    self.workingBands[self.drag.index] = self.deps.geometry.dragBand(
        self.workingBands[self.drag.index],
        self.drag,
        delta,
        self.fullFrame
    )
    self.drag.lastPoint = { x = point.x, y = point.y }
    self:draw()
end

function Calibration:report(err)
    if type(self.deps.reportError) == "function" then
        pcall(self.deps.reportError, tostring(err))
    end
end

function Calibration:save()
    local valid, validationError = validateBands(self.workingBands)
    if not valid then
        return nil, validationError
    end

    local callback = self.onSave
    local snapshot = copyBands(self.workingBands)
    local called, callbackError = pcall(callback, snapshot)
    if not called then
        self:report(callbackError)
        return nil, callbackError
    end

    self:stop()
    return true
end

function Calibration:cancel()
    local callback = self.onCancel
    self:stop()
    local called, callbackError = pcall(callback)
    if not called then
        return nil, callbackError
    end

    return true
end

function Calibration:stop()
    local chooser = self.screenChooser
    local editorCanvas = self.editorCanvas
    local eventTap = self.eventTap
    self.screenChooser = nil
    self.editorCanvas = nil
    self.eventTap = nil
    self.fullFrame = nil
    self.workingBands = nil
    self.onSave = nil
    self.onCancel = nil
    self.drag = nil

    deleteChooser(chooser)
    stopEventTap(eventTap)
    deleteEditor(editorCanvas)
end

function Calibration:start(screen, bands, onSave, onCancel)
    if type(onSave) ~= "function" or type(onCancel) ~= "function" then
        return nil, "calibration callbacks must be functions"
    end

    local valid, validationError = validateBands(bands)
    if not valid then
        return nil, validationError
    end

    local fullFrame
    local editorCanvas
    local eventTap
    local allocated, allocationError = pcall(function()
        fullFrame = screen:fullFrame()
        editorCanvas = self.deps.canvas.new(fullFrame)
        if not editorCanvas then
            error("canvas construction failed", 0)
        end
    end)
    if not allocated then
        deleteEditor(editorCanvas)
        return nil, allocationError
    end

    local previous = {
        screenChooser = self.screenChooser,
        editorCanvas = self.editorCanvas,
        eventTap = self.eventTap,
        fullFrame = self.fullFrame,
        workingBands = self.workingBands,
        onSave = self.onSave,
        onCancel = self.onCancel,
        drag = self.drag,
        saveFrame = self.saveFrame,
        cancelFrame = self.cancelFrame,
    }
    self.screenChooser = nil
    self.editorCanvas = editorCanvas
    self.fullFrame = fullFrame
    self.workingBands = copyBands(bands)
    self.onSave = onSave
    self.onCancel = onCancel
    self.drag = nil

    local prepared, prepareError = pcall(function()
        self:draw()
        editorCanvas:level("assistiveTechHigh")
        editorCanvas:clickActivating(true)
        editorCanvas:canvasMouseEvents(true, false, false, false)
        editorCanvas:mouseCallback(function(_, message, _, x, y)
            pcall(function()
                if message == "mouseDown" then
                    self:beginDrag({ x = x, y = y })
                end
            end)
        end)
        local eventTypes = self.deps.eventtap.event.types
        eventTap = self.deps.eventtap.new({
            eventTypes.mouseMoved,
            eventTypes.leftMouseDragged,
            eventTypes.leftMouseUp,
        }, function(event)
            event:getType()
            return false
        end)
        if not eventTap then
            error("event tap construction failed", 0)
        end
        eventTap:start()
        if not eventTap:isEnabled() then
            error("event tap failed to start", 0)
        end
        editorCanvas:show()
    end)

    if not prepared then
        stopEventTap(eventTap)
        deleteEditor(editorCanvas)
        self.screenChooser = previous.screenChooser
        self.editorCanvas = previous.editorCanvas
        self.eventTap = previous.eventTap
        self.fullFrame = previous.fullFrame
        self.workingBands = previous.workingBands
        self.onSave = previous.onSave
        self.onCancel = previous.onCancel
        self.drag = previous.drag
        self.saveFrame = previous.saveFrame
        self.cancelFrame = previous.cancelFrame
        return nil, prepareError
    end

    self.eventTap = eventTap
    deleteChooser(previous.screenChooser)
    stopEventTap(previous.eventTap)
    deleteEditor(previous.editorCanvas)

    return true
end

return M
