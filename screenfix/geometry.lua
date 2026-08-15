local M = {}
local SNAP_EPSILON = 1e-12
local SNAP_PARTS = {
    body = true,
    bottom = true,
    left = true,
    right = true,
    top = true,
}

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

local function clampEdge(current, delta, minimum, maximum)
    if current < minimum and delta <= 0 then
        return current
    end
    if current > maximum and delta >= 0 then
        return current
    end

    return clamp(current + delta, minimum, maximum)
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
        math.abs(windowFrame.x - candidate.x) + math.abs(windowFrame.y - candidate.y),
        (windowFrame.w - candidate.w) + (windowFrame.h - candidate.h),
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

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function hasFiniteRect(rect)
    return type(rect) == "table"
        and isFiniteNumber(rect.x)
        and isFiniteNumber(rect.y)
        and isFiniteNumber(rect.w)
        and isFiniteNumber(rect.h)
end

local function withinUnitBounds(rect)
    return rect.x >= 0
        and rect.y >= 0
        and rect.w >= 0
        and rect.h >= 0
        and rect.x + rect.w <= 1
        and rect.y + rect.h <= 1
end

local function isNormalizedRect(rect)
    return hasFiniteRect(rect)
        and rect.w > 0
        and rect.h > 0
        and withinUnitBounds(rect)
end

local function isValidFullFrame(fullFrame)
    return hasFiniteRect(fullFrame) and fullFrame.w > 0 and fullFrame.h > 0
end

local function isPositiveInteger(value)
    return isFiniteNumber(value) and value >= 1 and value % 1 == 0
end

local function isSnapCandidate(rect, fullFrame)
    return withinUnitBounds(rect)
        and rect.w + SNAP_EPSILON >= 20 / fullFrame.w
        and rect.h + SNAP_EPSILON >= 20 / fullFrame.h
end

local function correctedRect(rect, axis, edge, correction)
    local result = copyRect(rect)
    local position = axis == "x" and "x" or "y"
    local size = axis == "x" and "w" or "h"

    if edge == "body" then
        result[position] = result[position] + correction
    elseif edge == "leading" then
        result[position] = result[position] + correction
        result[size] = result[size] - correction
    else
        result[size] = result[size] + correction
    end

    return result
end

local function snapAxis(rect, axis, edges, targets, threshold, fullFrame, resizeEdge)
    local position = axis == "x" and "x" or "y"
    local size = axis == "x" and "w" or "h"
    local best
    local bestDistance

    for _, target in ipairs(targets) do
        for _, edge in ipairs(edges) do
            local edgePosition = rect[position]
            if edge == "trailing" then
                edgePosition = edgePosition + rect[size]
            end
            local correction = target - edgePosition
            local distance = math.abs(correction)
            local candidate = correctedRect(rect, axis, resizeEdge or "body", correction)

            if distance <= threshold + SNAP_EPSILON
                and isSnapCandidate(candidate, fullFrame)
                and (not bestDistance or distance < bestDistance)
            then
                best = candidate
                bestDistance = distance
            end
        end
    end

    return best or rect
end

local function axisTargets(axis, screenTargets, bands, activeIndex)
    local position = axis == "x" and "x" or "y"
    local size = axis == "x" and "w" or "h"
    local targets = {}

    for _, target in ipairs(screenTargets) do
        targets[#targets + 1] = target
    end
    local peerIndices = {}
    for index in pairs(bands) do
        if isPositiveInteger(index) then
            peerIndices[#peerIndices + 1] = index
        end
    end
    table.sort(peerIndices)

    for _, index in ipairs(peerIndices) do
        local band = bands[index]
        if index ~= activeIndex and isNormalizedRect(band) then
            targets[#targets + 1] = band[position]
            targets[#targets + 1] = band[position] + band[size]
        end
    end

    return targets
end

local function validSnapInputs(rawBand, activeIndex, part, bands, fullFrame, thresholdPoints)
    return isNormalizedRect(rawBand)
        and isPositiveInteger(activeIndex)
        and SNAP_PARTS[part] == true
        and type(bands) == "table"
        and isValidFullFrame(fullFrame)
        and isFiniteNumber(thresholdPoints)
        and thresholdPoints >= 0
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
    for index = #bands, 1, -1 do
        local band = bands[index]
        local withinHeight = localPoint.y >= band.y and localPoint.y <= band.y + band.h
        local withinWidth = localPoint.x >= band.x and localPoint.x <= band.x + band.w
        if withinWidth and math.abs(localPoint.y - band.y - band.h) <= handleSize then
            return { index = index, part = "bottom" }
        end
        if withinWidth and math.abs(localPoint.y - band.y) <= handleSize then
            return { index = index, part = "top" }
        end
        if withinHeight and math.abs(localPoint.x - band.x - band.w) <= handleSize then
            return { index = index, part = "right" }
        end
        if withinHeight and math.abs(localPoint.x - band.x) <= handleSize then
            return { index = index, part = "left" }
        end
    end

    for index = #bands, 1, -1 do
        local band = bands[index]
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
        result.x = clampEdge(
            result.x,
            localDelta.x / fullFrame.w,
            0,
            math.max(0, right - 20 / fullFrame.w)
        )
        result.w = right - result.x
    elseif drag.part == "right" then
        local right = clampEdge(
            result.x + result.w,
            localDelta.x / fullFrame.w,
            math.min(1, result.x + 20 / fullFrame.w),
            1
        )
        result.w = right - result.x
    elseif drag.part == "top" then
        local bottom = result.y + result.h
        result.y = clampEdge(
            result.y,
            localDelta.y / fullFrame.h,
            0,
            math.max(0, bottom - 20 / fullFrame.h)
        )
        result.h = bottom - result.y
    elseif drag.part == "bottom" then
        local bottom = clampEdge(
            result.y + result.h,
            localDelta.y / fullFrame.h,
            math.min(1, result.y + 20 / fullFrame.h),
            1
        )
        result.h = bottom - result.y
    end

    return result
end

function M.snapBand(rawBand, activeIndex, part, bands, fullFrame, thresholdPoints)
    local result = type(rawBand) == "table" and copyRect(rawBand) or {}

    if not validSnapInputs(rawBand, activeIndex, part, bands, fullFrame, thresholdPoints) then
        return result
    end

    if part == "body" then
        local xTargets = axisTargets("x", { 0, 1 }, bands, activeIndex)
        local yTargets = axisTargets("y", { 0, 1 }, bands, activeIndex)
        result = snapAxis(
            result,
            "x",
            { "leading", "trailing" },
            xTargets,
            thresholdPoints / fullFrame.w,
            fullFrame
        )
        result = snapAxis(
            result,
            "y",
            { "leading", "trailing" },
            yTargets,
            thresholdPoints / fullFrame.h,
            fullFrame
        )
    elseif part == "left" then
        local targets = axisTargets("x", { 0 }, bands, activeIndex)
        result = snapAxis(result, "x", { "leading" }, targets, thresholdPoints / fullFrame.w, fullFrame, "leading")
    elseif part == "right" then
        local targets = axisTargets("x", { 1 }, bands, activeIndex)
        result = snapAxis(result, "x", { "trailing" }, targets, thresholdPoints / fullFrame.w, fullFrame, "trailing")
    elseif part == "top" then
        local targets = axisTargets("y", { 0 }, bands, activeIndex)
        result = snapAxis(result, "y", { "leading" }, targets, thresholdPoints / fullFrame.h, fullFrame, "leading")
    elseif part == "bottom" then
        local targets = axisTargets("y", { 1 }, bands, activeIndex)
        result = snapAxis(result, "y", { "trailing" }, targets, thresholdPoints / fullFrame.h, fullFrame, "trailing")
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
