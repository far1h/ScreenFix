local M = {}

local function copyRect(rect)
    return {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
    }
end

function M.intersects(a, b)
    return a.x < b.x + b.w
        and b.x < a.x + a.w
        and a.y < b.y + b.h
        and b.y < a.y + a.h
end

function M.absoluteBands(fullFrame, bands)
    return {
        x = fullFrame.x + bands.x * fullFrame.w,
        y = fullFrame.y + bands.y * fullFrame.h,
        w = bands.w * fullFrame.w,
        h = bands.h * fullFrame.h,
    }
end

function M.copyRect(rect)
    return copyRect(rect)
end

return M
