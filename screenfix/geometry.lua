local M = {}

local function copyRect(rect)
    return {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
    }
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function overlappingBands(frame, maskRects)
    local result = {}

    for _, maskRect in ipairs(maskRects) do
        if frame.y < maskRect.y + maskRect.h and maskRect.y < frame.y + frame.h then
            result[#result + 1] = maskRect
        end
    end

    return result
end

local function buildCandidate(windowFrame, regionStart, regionEnd)
    local regionWidth = regionEnd - regionStart

    if regionWidth <= 0 then
        return nil
    end

    local width = math.min(windowFrame.w, regionWidth)

    return {
        x = clamp(windowFrame.x, regionStart, regionEnd - width),
        y = windowFrame.y,
        w = width,
        h = windowFrame.h,
    }
end

local function candidateCost(windowFrame, candidate, sideRank)
    return {
        (windowFrame.w - candidate.w) + (windowFrame.h - candidate.h),
        math.abs(windowFrame.x - candidate.x) + math.abs(windowFrame.y - candidate.y),
        sideRank,
    }
end

local function lessCost(left, right)
    for index = 1, #left do
        if left[index] ~= right[index] then
            return left[index] < right[index]
        end
    end

    return false
end

function M.intersects(a, b)
    return a.x < b.x + b.w
        and b.x < a.x + a.w
        and a.y < b.y + b.h
        and b.y < a.y + a.h
end

function M.absoluteBands(fullFrame, bands)
    local result = {}

    for index, band in ipairs(bands) do
        result[index] = {
            x = fullFrame.x + band.x * fullFrame.w,
            y = fullFrame.y + band.y * fullFrame.h,
            w = band.w * fullFrame.w,
            h = band.h * fullFrame.h,
        }
    end

    return result
end

function M.localBands(fullFrame, bands)
    local result = {}

    for index, band in ipairs(bands) do
        result[index] = {
            x = band.x * fullFrame.w,
            y = band.y * fullFrame.h,
            w = band.w * fullFrame.w,
            h = band.h * fullFrame.h,
        }
    end

    return result
end

function M.editorHit(localPoint, bands, handleSize)
    for index, band in ipairs(bands) do
        local withinHeight = localPoint.y >= band.y and localPoint.y <= band.y + band.h
        local withinWidth = localPoint.x >= band.x and localPoint.x <= band.x + band.w
        if withinHeight and math.abs(localPoint.x - band.x) <= handleSize then
            return { index = index, part = "left" }
        end
        if withinHeight and math.abs(localPoint.x - band.x - band.w) <= handleSize then
            return { index = index, part = "right" }
        end
        if withinWidth and math.abs(localPoint.y - band.y) <= handleSize then
            return { index = index, part = "top" }
        end
        if withinWidth and math.abs(localPoint.y - band.y - band.h) <= handleSize then
            return { index = index, part = "bottom" }
        end
    end

    for index, band in ipairs(bands) do
        if localPoint.x >= band.x
            and localPoint.x <= band.x + band.w
            and localPoint.y >= band.y
            and localPoint.y <= band.y + band.h
        then
            return { index = index, part = "body" }
        end
    end

    return nil
end

function M.dragBand(normalizedBand, drag, localDelta, fullFrame)
    local result = copyRect(normalizedBand)

    if drag.part == "body" then
        result.x = clamp(result.x + localDelta.x / fullFrame.w, 0, 1 - result.w)
        result.y = clamp(result.y + localDelta.y / fullFrame.h, 0, 1 - result.h)
    elseif drag.part == "left" then
        local right = result.x + result.w
        result.x = clamp(result.x + localDelta.x / fullFrame.w, 0, right - 20 / fullFrame.w)
        result.w = right - result.x
    elseif drag.part == "right" then
        local right = clamp(
            result.x + result.w + localDelta.x / fullFrame.w,
            result.x + 20 / fullFrame.w,
            1
        )
        result.w = right - result.x
    elseif drag.part == "top" then
        local bottom = result.y + result.h
        result.y = clamp(result.y + localDelta.y / fullFrame.h, 0, bottom - 20 / fullFrame.h)
        result.h = bottom - result.y
    elseif drag.part == "bottom" then
        local bottom = clamp(
            result.y + result.h + localDelta.y / fullFrame.h,
            result.y + 20 / fullFrame.h,
            1
        )
        result.h = bottom - result.y
    end

    return result
end

function M.copyRect(rect)
    return copyRect(rect)
end

function M.correctedFrame(windowFrame, usableFrame, maskRects)
    local hasIntersection = false

    for _, maskRect in ipairs(maskRects) do
        if M.intersects(windowFrame, maskRect) then
            hasIntersection = true
            break
        end
    end

    if not hasIntersection then
        return nil
    end

    local usableStart = usableFrame.x
    local usableEnd = usableFrame.x + usableFrame.w
    local adjusted = copyRect(windowFrame)
    adjusted.h = math.min(adjusted.h, usableFrame.h)
    adjusted.y = clamp(adjusted.y, usableFrame.y, usableFrame.y + usableFrame.h - adjusted.h)
    local bands = overlappingBands(adjusted, maskRects)

    if #bands == 0 then
        return adjusted
    end

    local leftBoundary = bands[1].x
    local rightBoundary = bands[1].x + bands[1].w

    for index = 2, #bands do
        leftBoundary = math.min(leftBoundary, bands[index].x)
        rightBoundary = math.max(rightBoundary, bands[index].x + bands[index].w)
    end

    local leftEnd = clamp(leftBoundary, usableStart, usableEnd)
    local rightStart = clamp(rightBoundary, usableStart, usableEnd)
    local left = buildCandidate(adjusted, usableStart, leftEnd)
    local right = buildCandidate(adjusted, rightStart, usableEnd)

    if not left and not right then
        return nil
    end

    if not left then
        return right
    end

    if not right then
        return left
    end

    local leftCost = candidateCost(windowFrame, left, 0)
    local rightCost = candidateCost(windowFrame, right, 1)

    if lessCost(leftCost, rightCost) then
        return left
    end

    return right
end

function M.framesNear(a, b, tolerance)
    tolerance = tolerance or 1

    return math.abs(a.x - b.x) <= tolerance
        and math.abs(a.y - b.y) <= tolerance
        and math.abs(a.w - b.w) <= tolerance
        and math.abs(a.h - b.h) <= tolerance
end

return M
