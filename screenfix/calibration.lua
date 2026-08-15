local M = {}
local Calibration = {}
Calibration.__index = Calibration
local ACCENT_COLOR = { red = 1, green = 100 / 255, blue = 59 / 255, alpha = 1 }
local CANCEL_COLOR = { red = 53 / 255, green = 58 / 255, blue = 66 / 255, alpha = 1 }
local CONTROL_GAP = 12
local CONTROL_HEIGHT = 42
local CONTROL_MARGIN = 24
local CONTROL_WIDTH = 104
local HANDLE_WIDTH = 8
local MIN_CANVAS_HEIGHT = 180
local MIN_CANVAS_WIDTH = 260
local MOVEMENT_THRESHOLD = 4
local NARROW_INSTRUCTION_THRESHOLD = 378
local SAVE_COLOR = { red = 22 / 255, green = 163 / 255, blue = 74 / 255, alpha = 1 }
local SNAP_THRESHOLD = 12

local function copyBand(band)
    return {
        x = band.x,
        y = band.y,
        w = band.w,
        h = band.h,
    }
end

local function copyBands(bands)
    local copied = {}

    for index, band in ipairs(bands) do
        copied[index] = copyBand(band)
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

local function controlLayout(fullFrame)
    if fullFrame.w < MIN_CANVAS_WIDTH or fullFrame.h < MIN_CANVAS_HEIGHT then
        return nil, "display is too small for calibration controls"
    end

    local controlY = fullFrame.h - CONTROL_MARGIN - CONTROL_HEIGHT
    local buttonWidth = math.min(
        CONTROL_WIDTH,
        math.floor((fullFrame.w - (2 * CONTROL_MARGIN) - CONTROL_GAP) / 2)
    )
    local instruction = { x = 24, y = 24, w = 330, h = 42 }
    local instructionDot = { x = 40, y = 41, w = 8, h = 8 }
    local instructionText = { x = 58, y = 24, w = 280, h = 42 }
    local instructionTextSize = 15

    if fullFrame.w < NARROW_INSTRUCTION_THRESHOLD then
        instruction.w = fullFrame.w - (2 * CONTROL_MARGIN)
        instruction.h = 58
        instructionDot.y = instruction.y + math.floor((instruction.h - instructionDot.h) / 2)
        instructionText.w = instruction.w - 50
        instructionText.h = instruction.h
        instructionTextSize = 13
    end

    return {
        save = {
            x = CONTROL_MARGIN,
            y = controlY,
            w = buttonWidth,
            h = CONTROL_HEIGHT,
        },
        cancel = {
            x = CONTROL_MARGIN + buttonWidth + CONTROL_GAP,
            y = controlY,
            w = buttonWidth,
            h = CONTROL_HEIGHT,
        },
        instruction = instruction,
        instructionDot = instructionDot,
        instructionText = instructionText,
        instructionTextSize = instructionTextSize,
    }
end

local function control(frame, color, radius)
    return {
        type = "rectangle",
        action = "fill",
        fillColor = color,
        frame = frame,
        roundedRectRadii = { xRadius = radius, yRadius = radius },
    }
end

local function label(frame, text, textSize, alignment)
    return {
        type = "text",
        frame = frame,
        text = text,
        textAlignment = alignment,
        textColor = { white = 1, alpha = 1 },
        textSize = textSize,
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

local function syncSession(calibration, session)
    calibration.session = session
    calibration.editorCanvas = session.editorCanvas
    calibration.eventTap = session.eventTap
    calibration.fullFrame = session.fullFrame
    calibration.workingBands = session.workingBands
    calibration.onSave = session.onSave
    calibration.onCancel = session.onCancel
    calibration.drag = session.drag
    calibration.saveFrame = session.saveFrame
    calibration.cancelFrame = session.cancelFrame
end

local function clearSession(calibration)
    calibration.session = nil
    calibration.editorCanvas = nil
    calibration.eventTap = nil
    calibration.fullFrame = nil
    calibration.workingBands = nil
    calibration.onSave = nil
    calibration.onCancel = nil
    calibration.drag = nil
    calibration.saveFrame = nil
    calibration.cancelFrame = nil
end

local function setDrag(calibration, session, drag)
    session.drag = drag
    if calibration.session == session then
        calibration.drag = drag
    end
end

function M.new(deps)
    return setmetatable({
        deps = deps,
        lifecycleGeneration = 0,
        nextSessionToken = 0,
    }, Calibration)
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

local function renderEditor(calibration, session)
    local localBands = calibration.deps.geometry.localBands(
        session.fullFrame,
        session.workingBands
    )
    session.editorCanvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 0, alpha = 0 },
        frame = { x = 0, y = 0, w = session.fullFrame.w, h = session.fullFrame.h },
        trackMouseByBounds = true,
        trackMouseDown = true,
    }

    for index, band in ipairs(localBands) do
        session.editorCanvas[index + 1] = {
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
            session.editorCanvas[elementIndex] = {
                type = "rectangle",
                action = "fill",
                fillColor = { white = 1, alpha = 1 },
                frame = frame,
            }
            elementIndex = elementIndex + 1
        end
    end

    local layout = session.controlLayout
    session.saveFrame = copyBand(layout.save)
    session.cancelFrame = copyBand(layout.cancel)
    session.editorCanvas[17] = control(layout.save, SAVE_COLOR, 9)
    session.editorCanvas[18] = label(layout.save, "Save", 16, "center")
    session.editorCanvas[19] = control(layout.cancel, CANCEL_COLOR, 9)
    session.editorCanvas[20] = label(layout.cancel, "Cancel", 16, "center")
    session.editorCanvas[21] = {
        type = "rectangle",
        action = "strokeAndFill",
        fillColor = { white = 0, alpha = 0.88 },
        frame = layout.instruction,
        roundedRectRadii = { xRadius = 10, yRadius = 10 },
        strokeColor = { white = 1, alpha = 0.28 },
        strokeWidth = 1,
    }
    session.editorCanvas[22] = control(layout.instructionDot, ACCENT_COLOR, 4)
    session.editorCanvas[23] = label(
        layout.instructionText,
        "Drag red bands or white edges",
        layout.instructionTextSize,
        "left"
    )

    if calibration.session == session then
        calibration.saveFrame = session.saveFrame
        calibration.cancelFrame = session.cancelFrame
    end
end

function Calibration:draw()
    if self.session then
        renderEditor(self, self.session)
    end
end

local function beginDrag(calibration, session, point)
    if contains(session.saveFrame, point) then
        calibration:save()
        return
    end
    if contains(session.cancelFrame, point) then
        calibration:cancel()
        return
    end
    if session.drag and session.drag.latched then
        setDrag(calibration, session, nil)
        return
    end

    local bands = calibration.deps.geometry.localBands(session.fullFrame, session.workingBands)
    local hit = calibration.deps.geometry.editorHit(point, bands, HANDLE_WIDTH)
    if hit then
        hit.rawBand = copyBand(session.workingBands[hit.index])
        hit.pressPoint = { x = point.x, y = point.y }
        hit.lastPoint = { x = point.x, y = point.y }
        hit.moved = false
        hit.latched = false
    end
    setDrag(calibration, session, hit)
end

function Calibration:beginDrag(point)
    if self.session then
        beginDrag(self, self.session, point)
    end
end

local function updateDrag(calibration, session, point)
    if not session.drag then
        return
    end

    if not session.drag.moved then
        local pressDeltaX = point.x - session.drag.pressPoint.x
        local pressDeltaY = point.y - session.drag.pressPoint.y
        if pressDeltaX * pressDeltaX + pressDeltaY * pressDeltaY
            < MOVEMENT_THRESHOLD * MOVEMENT_THRESHOLD
        then
            return
        end
    end

    local drag = session.drag
    local delta = {
        x = point.x - drag.lastPoint.x,
        y = point.y - drag.lastPoint.y,
    }
    local rawCandidate = calibration.deps.geometry.dragBand(
        drag.rawBand,
        drag,
        delta,
        session.fullFrame
    )
    local visibleCandidate = calibration.deps.geometry.snapBand(
        rawCandidate,
        drag.index,
        drag.part,
        session.workingBands,
        session.fullFrame,
        SNAP_THRESHOLD
    )

    drag.rawBand = rawCandidate
    session.workingBands[drag.index] = visibleCandidate
    drag.lastPoint = { x = point.x, y = point.y }
    drag.moved = true
    renderEditor(calibration, session)
end

function Calibration:updateDrag(point)
    if self.session then
        updateDrag(self, self.session, point)
    end
end

function Calibration:report(err)
    if type(self.deps.reportError) == "function" then
        pcall(self.deps.reportError, tostring(err))
    end
end

function Calibration:save()
    self.lifecycleGeneration = self.lifecycleGeneration + 1
    local invokingToken = self.sessionToken
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

    if self.sessionToken == invokingToken then
        self:stop()
    end
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
    local session = self.session
    local eventTap = self.eventTap
    self.lifecycleGeneration = self.lifecycleGeneration + 1
    self.sessionToken = nil
    self.screenChooser = nil
    if session then
        session.drag = nil
    end
    clearSession(self)

    stopEventTap(eventTap)
    deleteChooser(chooser)
    if session then
        deleteEditor(session.editorCanvas)
    end
end

function Calibration:start(screen, bands, onSave, onCancel, commitGuard)
    if type(onSave) ~= "function" or type(onCancel) ~= "function" then
        return nil, "calibration callbacks must be functions"
    end

    local valid, validationError = validateBands(bands)
    if not valid then
        return nil, validationError
    end

    self.nextSessionToken = self.nextSessionToken + 1
    local candidateToken = self.nextSessionToken
    self.lifecycleGeneration = self.lifecycleGeneration + 1
    local candidateGeneration = self.lifecycleGeneration

    local candidate = {
        token = candidateToken,
        workingBands = copyBands(bands),
        onSave = onSave,
        onCancel = onCancel,
    }
    local allocated, allocationError = pcall(function()
        candidate.fullFrame = screen:fullFrame()
        local layout, layoutError = controlLayout(candidate.fullFrame)
        if not layout then
            error(layoutError, 0)
        end
        candidate.controlLayout = layout
        candidate.editorCanvas = self.deps.canvas.new(candidate.fullFrame)
        if not candidate.editorCanvas then
            error("canvas construction failed", 0)
        end
    end)
    if not allocated then
        deleteEditor(candidate.editorCanvas)
        return nil, allocationError
    end

    local prepared, prepareError = pcall(function()
        renderEditor(self, candidate)
        candidate.editorCanvas:level("assistiveTechHigh")
        candidate.editorCanvas:clickActivating(true)
        candidate.editorCanvas:canvasMouseEvents(true, false, false, false)
        candidate.editorCanvas:mouseCallback(function(_, message, _, x, y)
            pcall(function()
                if self.sessionToken == candidateToken and message == "mouseDown" then
                    beginDrag(self, candidate, { x = x, y = y })
                end
            end)
        end)
        local eventTypes = self.deps.eventtap.event.types
        candidate.eventTap = self.deps.eventtap.new({
            eventTypes.mouseMoved,
            eventTypes.leftMouseDragged,
            eventTypes.leftMouseUp,
        }, function(event)
            local dispatched, dispatchError = pcall(function()
                if self.sessionToken ~= candidateToken then
                    return
                end
                local eventType = event:getType()
                local point = event:location()
                local localPoint = {
                    x = point.x - candidate.fullFrame.x,
                    y = point.y - candidate.fullFrame.y,
                }

                if eventType == eventTypes.leftMouseDragged then
                    updateDrag(self, candidate, localPoint)
                elseif eventType == eventTypes.mouseMoved
                    and candidate.drag
                    and candidate.drag.latched
                then
                    updateDrag(self, candidate, localPoint)
                elseif eventType == eventTypes.leftMouseUp then
                    if candidate.drag and not candidate.drag.latched then
                        if candidate.drag.moved then
                            setDrag(self, candidate, nil)
                        else
                            candidate.drag.latched = true
                        end
                    end
                end
            end)
            if not dispatched then
                self:report(dispatchError)
            end
            return false
        end)
        if not candidate.eventTap then
            error("event tap construction failed", 0)
        end
        candidate.eventTap:start()
        if not candidate.eventTap:isEnabled() then
            error("event tap failed to start", 0)
        end
        candidate.editorCanvas:show()
    end)

    if not prepared then
        stopEventTap(candidate.eventTap)
        deleteEditor(candidate.editorCanvas)
        return nil, prepareError
    end

    if self.lifecycleGeneration ~= candidateGeneration then
        stopEventTap(candidate.eventTap)
        deleteEditor(candidate.editorCanvas)
        return nil, "calibration start superseded"
    end

    if commitGuard then
        local guarded, canCommit = pcall(commitGuard)
        if not guarded
            or canCommit ~= true
            or self.lifecycleGeneration ~= candidateGeneration
        then
            stopEventTap(candidate.eventTap)
            deleteEditor(candidate.editorCanvas)
            return nil, "calibration start superseded"
        end
    end

    local previousChooser = self.screenChooser
    local previousSession = self.session
    self.screenChooser = nil
    self.sessionToken = candidateToken
    syncSession(self, candidate)
    if previousSession then
        previousSession.drag = nil
    end
    deleteChooser(previousChooser)
    if previousSession then
        stopEventTap(previousSession.eventTap)
        deleteEditor(previousSession.editorCanvas)
    end

    if self.session == candidate
        and self.sessionToken == candidateToken
        and self.lifecycleGeneration == candidateGeneration
    then
        return true
    end

    if self.session == candidate then
        candidate.drag = nil
        self.sessionToken = nil
        clearSession(self)
        stopEventTap(candidate.eventTap)
        deleteEditor(candidate.editorCanvas)
    end

    return nil, "calibration start superseded"
end

return M
