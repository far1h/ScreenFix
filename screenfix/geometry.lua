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
    local width = math.min(windowFrame.w, regionEnd - regionStart)

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
