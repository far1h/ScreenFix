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

return M
