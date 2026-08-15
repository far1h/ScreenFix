local geometry = require("screenfix.geometry")
local test = require("tests.test_helper")

test.test("absoluteBands maps normalized bands to a full frame", function()
    local fullFrame = { x = -3440, y = 0, w = 3440, h = 1440 }
    local bands = {
        { x = 0.40, y = 0.25, w = 0.20, h = 0.50 },
    }
    local result = geometry.absoluteBands(fullFrame, bands)

    test.rect(result[1], {
        x = -2064,
        y = 360,
        w = 688,
        h = 720,
    })
end)

test.test("localBands ignores the global display origin", function()
    local bands = geometry.localBands(
        { x = -3440, y = -200, w = 3440, h = 1440 },
        { { x = 0.40, y = 0.25, w = 0.20, h = 0.50 } }
    )

    test.rect(bands[1], { x = 1376, y = 360, w = 688, h = 720 })
end)

test.test("editorHit finds a band's left handle", function()
    local hit = geometry.editorHit(
        { x = 100, y = 150 },
        { { x = 100, y = 100, w = 200, h = 100 } },
        10
    )

    test.equal(hit.index, 1)
    test.equal(hit.part, "left")
end)

test.test("editorHit finds a band's right handle", function()
    local hit = geometry.editorHit(
        { x = 300, y = 150 },
        { { x = 100, y = 100, w = 200, h = 100 } },
        10
    )

    test.equal(hit.index, 1)
    test.equal(hit.part, "right")
end)

test.test("editorHit finds a band's top handle", function()
    local hit = geometry.editorHit(
        { x = 200, y = 100 },
        { { x = 100, y = 100, w = 200, h = 100 } },
        10
    )

    test.equal(hit.index, 1)
    test.equal(hit.part, "top")
end)

test.test("editorHit finds a band's bottom handle", function()
    local hit = geometry.editorHit(
        { x = 200, y = 200 },
        { { x = 100, y = 100, w = 200, h = 100 } },
        10
    )

    test.equal(hit.index, 1)
    test.equal(hit.part, "bottom")
end)

test.test("editorHit finds the band body away from all handles", function()
    local hit = geometry.editorHit(
        { x = 200, y = 150 },
        { { x = 100, y = 100, w = 200, h = 100 } },
        10
    )

    test.equal(hit.index, 1)
    test.equal(hit.part, "body")
end)

test.test("editorHit gives a touching boundary to the later default band", function()
    local bands = geometry.localBands(
        { x = 0, y = 0, w = 1000, h = 1000 },
        {
            { x = 0.43, y = 0.00, w = 0.16, h = 0.34 },
            { x = 0.46, y = 0.34, w = 0.11, h = 0.39 },
            { x = 0.48, y = 0.73, w = 0.07, h = 0.27 },
        }
    )
    local hit = geometry.editorHit({ x = 500, y = bands[2].y }, bands, 10)

    test.equal(hit.index, 2)
    test.equal(hit.part, "top")
end)

test.test("editorHit gives overlapping bodies to the later painted band", function()
    local hit = geometry.editorHit(
        { x = 200, y = 200 },
        {
            { x = 100, y = 100, w = 300, h = 300 },
            { x = 150, y = 150, w = 100, h = 100 },
        },
        10
    )

    test.equal(hit.index, 2)
    test.equal(hit.part, "body")
end)

test.test("editorHit follows handle paint order at a same-band corner", function()
    local hit = geometry.editorHit(
        { x = 100, y = 100 },
        { { x = 100, y = 100, w = 200, h = 100 } },
        10
    )

    test.equal(hit.index, 1)
    test.equal(hit.part, "top")
end)

test.test("dragBand moves a body without leaving normalized bounds", function()
    local moved = geometry.dragBand(
        { x = 0.10, y = 0.70, w = 0.20, h = 0.20 },
        { part = "body" },
        { x = -200, y = 200 },
        { x = -3440, y = -200, w = 1000, h = 1000 }
    )

    test.rect(moved, { x = 0, y = 0.80, w = 0.20, h = 0.20 })
end)

test.test("dragBand keeps a left resize at least 20 rendered points wide", function()
    local right = 0.20 + 0.30
    local x = right - 20 / 1000
    local resized = geometry.dragBand(
        { x = 0.20, y = 0.20, w = 0.30, h = 0.30 },
        { part = "left" },
        { x = 500, y = 0 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.rect(resized, { x = x, y = 0.20, w = right - x, h = 0.30 })
end)

test.test("dragBand keeps a right resize at least 20 rendered points wide", function()
    local right = 0.20 + 20 / 1000
    local resized = geometry.dragBand(
        { x = 0.20, y = 0.20, w = 0.30, h = 0.30 },
        { part = "right" },
        { x = -500, y = 0 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.rect(resized, { x = 0.20, y = 0.20, w = right - 0.20, h = 0.30 })
end)

test.test("dragBand keeps a top resize at least 20 rendered points high", function()
    local bottom = 0.20 + 0.30
    local y = bottom - 20 / 1000
    local resized = geometry.dragBand(
        { x = 0.20, y = 0.20, w = 0.30, h = 0.30 },
        { part = "top" },
        { x = 0, y = 500 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.rect(resized, { x = 0.20, y = y, w = 0.30, h = bottom - y })
end)

test.test("dragBand keeps a bottom resize at least 20 rendered points high", function()
    local bottom = 0.20 + 20 / 1000
    local resized = geometry.dragBand(
        { x = 0.20, y = 0.20, w = 0.30, h = 0.30 },
        { part = "bottom" },
        { x = 0, y = -500 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.rect(resized, { x = 0.20, y = 0.20, w = 0.30, h = bottom - 0.20 })
end)

test.test("dragBand does not reverse an undersized left-edge drag", function()
    local band = { x = 0.995, y = 0.20, w = 0.005, h = 0.20 }
    local resized = geometry.dragBand(
        band,
        { part = "left" },
        { x = 1, y = 0 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.equal(resized.x >= band.x, true)
    test.equal(resized.x >= 0 and resized.y >= 0 and resized.w >= 0 and resized.h >= 0, true)
    test.equal(resized.x + resized.w <= 1 and resized.y + resized.h <= 1, true)
end)

test.test("dragBand does not reverse or overflow an undersized right-edge drag", function()
    local band = { x = 0.995, y = 0.20, w = 0.005, h = 0.20 }
    local resized = geometry.dragBand(
        band,
        { part = "right" },
        { x = -1, y = 0 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.equal(resized.x + resized.w <= band.x + band.w, true)
    test.equal(resized.x >= 0 and resized.y >= 0 and resized.w >= 0 and resized.h >= 0, true)
    test.equal(resized.x + resized.w <= 1 and resized.y + resized.h <= 1, true)
end)

test.test("dragBand does not reverse an undersized top-edge drag", function()
    local band = { x = 0.20, y = 0.995, w = 0.20, h = 0.005 }
    local resized = geometry.dragBand(
        band,
        { part = "top" },
        { x = 0, y = 1 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.equal(resized.y >= band.y, true)
    test.equal(resized.x >= 0 and resized.y >= 0 and resized.w >= 0 and resized.h >= 0, true)
    test.equal(resized.x + resized.w <= 1 and resized.y + resized.h <= 1, true)
end)

test.test("dragBand does not reverse or overflow an undersized bottom-edge drag", function()
    local band = { x = 0.20, y = 0.995, w = 0.20, h = 0.005 }
    local resized = geometry.dragBand(
        band,
        { part = "bottom" },
        { x = 0, y = -1 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.equal(resized.y + resized.h <= band.y + band.h, true)
    test.equal(resized.x >= 0 and resized.y >= 0 and resized.w >= 0 and resized.h >= 0, true)
    test.equal(resized.x + resized.w <= 1 and resized.y + resized.h <= 1, true)
end)

test.test("dragBand returns a new table without mutating the saved band", function()
    local saved = { x = 0.20, y = 0.20, w = 0.30, h = 0.30 }
    local moved = geometry.dragBand(
        saved,
        { part = "body" },
        { x = 100, y = 100 },
        { x = 0, y = 0, w = 1000, h = 1000 }
    )

    test.equal(moved == saved, false)
    test.rect(saved, { x = 0.20, y = 0.20, w = 0.30, h = 0.30 })
end)

test.test("snapBand moves a body to the screen start while preserving size", function()
    local snapped = geometry.snapBand(
        { x = 0.012, y = 0.012, w = 0.30, h = 0.40 },
        1,
        "body",
        { { x = 0.012, y = 0.012, w = 0.30, h = 0.40 } },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.rect(snapped, { x = 0, y = 0, w = 0.30, h = 0.40 })
end)

test.test("snapBand moves a body to the screen end while preserving size", function()
    local snapped = geometry.snapBand(
        { x = 0.50, y = 0.50, w = 0.48828125, h = 0.48828125 },
        1,
        "body",
        { { x = 0.50, y = 0.50, w = 0.48828125, h = 0.48828125 } },
        { x = 0, y = 0, w = 1024, h = 1024 },
        12
    )

    test.rect(snapped, {
        x = 0.51171875,
        y = 0.51171875,
        w = 0.48828125,
        h = 0.48828125,
    })
end)

test.test("snapBand snaps resize handles only to their legal screen boundary", function()
    local fullFrame = { x = 0, y = 0, w = 1024, h = 1024 }

    test.rect(
        geometry.snapBand(
            { x = 0.01171875, y = 0.20, w = 0.30, h = 0.40 },
            1,
            "left",
            {},
            fullFrame,
            12
        ),
        { x = 0, y = 0.20, w = 0.01171875 + 0.30, h = 0.40 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.50, y = 0.20, w = 0.48828125, h = 0.40 },
            1,
            "right",
            {},
            fullFrame,
            12
        ),
        { x = 0.50, y = 0.20, w = 0.50, h = 0.40 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0.01171875, w = 0.30, h = 0.40 },
            1,
            "top",
            {},
            fullFrame,
            12
        ),
        { x = 0.20, y = 0, w = 0.30, h = 0.01171875 + 0.40 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0.50, w = 0.30, h = 0.48828125 },
            1,
            "bottom",
            {},
            fullFrame,
            12
        ),
        { x = 0.20, y = 0.50, w = 0.30, h = 0.50 }
    )
end)

test.test("snapBand rejects the opposite screen boundary for resize handles", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }

    test.rect(
        geometry.snapBand(
            { x = 0.988, y = 0.20, w = 0.012, h = 0.40 },
            1,
            "left",
            {},
            fullFrame,
            12
        ),
        { x = 0.988, y = 0.20, w = 0.012, h = 0.40 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0, y = 0.20, w = 0.012, h = 0.40 },
            1,
            "right",
            {},
            fullFrame,
            12
        ),
        { x = 0, y = 0.20, w = 0.012, h = 0.40 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0.988, w = 0.30, h = 0.012 },
            1,
            "top",
            {},
            fullFrame,
            12
        ),
        { x = 0.20, y = 0.988, w = 0.30, h = 0.012 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0, w = 0.30, h = 0.012 },
            1,
            "bottom",
            {},
            fullFrame,
            12
        ),
        { x = 0.20, y = 0, w = 0.30, h = 0.012 }
    )
end)

test.test("snapBand includes exactly 12 points but excludes 12.01 points", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }
    local exact = geometry.snapBand(
        { x = 0.012, y = 0.20, w = 0.30, h = 0.40 },
        1,
        "body",
        {},
        fullFrame,
        12
    )
    local outside = geometry.snapBand(
        { x = 0.01201, y = 0.20, w = 0.30, h = 0.40 },
        1,
        "body",
        {},
        fullFrame,
        12
    )

    test.equal(exact.x, 0)
    test.equal(outside.x, 0.01201)
end)

test.test("snapBand excludes a correction just beyond 12 points", function()
    local raw = { x = 0.0120000000005, y = 0.20, w = 0.30, h = 0.40 }
    local snapped = geometry.snapBand(
        raw,
        1,
        "body",
        {},
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.rect(snapped, raw)
end)

test.test("snapBand classifies identical represented peer corrections consistently", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }
    local constructedRaw = { x = 0.014, y = 0.20, w = 0.20, h = 0.20 }
    local constructedTarget = constructedRaw.x + 12 / fullFrame.w
    local literalRaw = { x = 0.013, y = 0.20, w = 0.20, h = 0.20 }
    local literalTarget = 0.025

    test.equal(constructedTarget - constructedRaw.x, literalTarget - literalRaw.x)

    local constructed = geometry.snapBand(
        constructedRaw,
        2,
        "body",
        {
            { x = constructedTarget, y = 0.70, w = 0.30, h = 0.10 },
            constructedRaw,
        },
        fullFrame,
        12
    )
    local literal = geometry.snapBand(
        literalRaw,
        2,
        "body",
        {
            { x = literalTarget, y = 0.70, w = 0.30, h = 0.10 },
            literalRaw,
        },
        fullFrame,
        12
    )

    test.equal(constructed.x, constructedTarget)
    test.equal(literal.x, literalTarget)
end)

local exactPointGapCases = {
    { width = 3440, start = 1711 },
    { width = 1920, start = 965 },
}

for _, case in ipairs(exactPointGapCases) do
    local gapCase = case

    test.test("snapBand accepts an integer 12-point peer gap on " .. gapCase.width, function()
        local target = (gapCase.start + 12) / gapCase.width
        local raw = {
            x = gapCase.start / gapCase.width,
            y = 0.20,
            w = 0.20,
            h = 0.20,
        }
        local snapped = geometry.snapBand(
            raw,
            2,
            "body",
            {
                { x = target, y = 0.70, w = 0.20, h = 0.10 },
                raw,
            },
            { x = 0, y = 0, w = gapCase.width, h = 1000 },
            12
        )

        test.equal(snapped.x, target)
    end)
end

test.test("snapBand aligns x with a vertically stacked peer and excludes the active band", function()
    local peer = { x = 0.40, y = 0.10, w = 0.20, h = 0.20 }
    local active = { x = 0.39, y = 0.70, w = 0.20, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        2,
        "body",
        { peer, active },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.rect(snapped, { x = 0.40, y = 0.70, w = 0.20, h = 0.20 })
end)

test.test("snapBand aligns y with a side-by-side peer", function()
    local peer = { x = 0.10, y = 0.40, w = 0.20, h = 0.20 }
    local active = { x = 0.70, y = 0.39, w = 0.20, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        2,
        "body",
        { peer, active },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.rect(snapped, { x = 0.70, y = 0.40, w = 0.20, h = 0.20 })
end)

test.test("snapBand constructs a trailing screen seam directly from its target", function()
    local width = 3440
    local raw = {
        x = 1 / width,
        y = 0.20,
        w = (width - 1) / width,
        h = 0.20,
    }
    local snapped = geometry.snapBand(
        raw,
        1,
        "body",
        { raw },
        { x = 0, y = 0, w = width, h = 1000 },
        12
    )

    test.equal(snapped.x, 1 - raw.w)
    test.equal(snapped.x + snapped.w, 1)
end)

test.test("snapBand constructs a trailing peer seam directly from its target", function()
    local width = 3440
    local target = 58 / width
    local raw = {
        x = 20 / width,
        y = 0.20,
        w = 50 / width,
        h = 0.20,
    }
    local snapped = geometry.snapBand(
        raw,
        2,
        "body",
        {
            { x = target, y = 0.70, w = 0.20, h = 0.10 },
            raw,
        },
        { x = 0, y = 0, w = width, h = 1000 },
        12
    )

    test.equal(snapped.x, target - raw.w)
    test.equal(snapped.x + snapped.w, target)
end)

test.test("snapBand aligns every resize handle with peer starts and ends", function()
    local peer = { x = 0.50, y = 0.50, w = 0.25, h = 0.25 }
    local fullFrame = { x = 0, y = 0, w = 1024, h = 1024 }

    test.rect(
        geometry.snapBand(
            { x = 0.76171875, y = 0.20, w = 0.188, h = 0.20 },
            2,
            "left",
            { peer },
            fullFrame,
            12
        ),
        {
            x = peer.x + peer.w,
            y = 0.20,
            w = 0.76171875 + 0.188 - (peer.x + peer.w),
            h = 0.20,
        }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.25, y = 0.20, w = 0.23828125, h = 0.20 },
            2,
            "right",
            { peer },
            fullFrame,
            12
        ),
        { x = 0.25, y = 0.20, w = 0.25, h = 0.20 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0.76171875, w = 0.20, h = 0.188 },
            2,
            "top",
            { peer },
            fullFrame,
            12
        ),
        {
            x = 0.20,
            y = peer.y + peer.h,
            w = 0.20,
            h = 0.76171875 + 0.188 - (peer.y + peer.h),
        }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0.25, w = 0.20, h = 0.23828125 },
            2,
            "bottom",
            { peer },
            fullFrame,
            12
        ),
        { x = 0.20, y = 0.25, w = 0.20, h = 0.25 }
    )
end)

test.test("snapBand chooses the closest peer correction", function()
    local snapped = geometry.snapBand(
        { x = 0.30, y = 0.30, w = 0.20, h = 0.20 },
        3,
        "body",
        {
            { x = 0.10, y = 0.10, w = 0.188, h = 0.10 },
            { x = 0.305, y = 0.70, w = 0.10, h = 0.10 },
            { x = 0.30, y = 0.30, w = 0.20, h = 0.20 },
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x, 0.305)
end)

test.test("snapBand prefers screen start to screen end on an equal correction", function()
    local snapped = geometry.snapBand(
        { x = 0.01171875, y = 0.20, w = 0.9765625, h = 0.20 },
        1,
        "body",
        {},
        { x = 0, y = 0, w = 1024, h = 1000 },
        12
    )

    test.equal(snapped.x, 0)
end)

test.test("snapBand preserves screen target order for a conceptual equal-distance tie", function()
    local width = 1920
    local snapped = geometry.snapBand(
        {
            x = 12 / width,
            y = 0.20,
            w = (width - 24) / width,
            h = 0.20,
        },
        1,
        "body",
        {},
        { x = 0, y = 0, w = width, h = 1000 },
        12
    )

    test.equal(snapped.x, 0)
end)

test.test("snapBand prefers a screen target to a peer target on an equal correction", function()
    local active = { x = 0.012, y = 0.20, w = 0.20, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        2,
        "body",
        {
            { x = 0.024, y = 0.70, w = 0.10, h = 0.10 },
            active,
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x, 0)
end)

test.test("snapBand prefers the lower peer index on an equal correction", function()
    local active = { x = 0.41, y = 0.30, w = 0.10, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        3,
        "body",
        {
            { x = 0.20, y = 0.10, w = 0.20, h = 0.10 },
            { x = 0.42, y = 0.70, w = 0.20, h = 0.10 },
            active,
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x, 0.40)
end)

test.test("snapBand prefers a peer start to its end on an equal correction", function()
    local active = { x = 0.41, y = 0.30, w = 0.20, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        2,
        "body",
        {
            { x = 0.40, y = 0.70, w = 0.02, h = 0.10 },
            active,
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x, 0.40)
end)

test.test("snapBand prefers the active leading edge on an equal correction", function()
    local active = { x = 0.39, y = 0.30, w = 0.02, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        2,
        "body",
        {
            { x = 0.40, y = 0.70, w = 0.30, h = 0.10 },
            active,
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x, 0.40)
end)

test.test("snapBand discards an out-of-bounds peer resize target", function()
    local snapped = geometry.snapBand(
        { x = 0.10, y = 0.20, w = 0.20, h = 0.20 },
        2,
        "right",
        {
            { x = 0, y = 0.70, w = 0.09, h = 0.10 },
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        800
    )

    test.rect(snapped, {
        x = 0.10,
        y = 0.20,
        w = 1 - 0.10,
        h = 0.20,
    })
end)

test.test("snapBand rejects peer resizes below 20 points on either axis", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 500 }
    local narrow = { x = 0.50, y = 0.20, w = 0.025, h = 0.20 }
    local short = { x = 0.20, y = 0.40, w = 0.20, h = 0.05 }

    test.rect(
        geometry.snapBand(
            narrow,
            2,
            "right",
            { { x = 0.517, y = 0.70, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        narrow
    )
    test.rect(
        geometry.snapBand(
            short,
            2,
            "bottom",
            { { x = 0.70, y = 0.43, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        short
    )
end)

test.test("snapBand moves narrow and short bodies without resizing them", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }
    local narrow = { x = 0.012, y = 0.20, w = 0.019, h = 0.20 }
    local short = { x = 0.20, y = 0.012, w = 0.20, h = 0.019 }

    test.rect(
        geometry.snapBand(narrow, 1, "body", {}, fullFrame, 12),
        { x = 0, y = 0.20, w = 0.019, h = 0.20 }
    )
    test.rect(
        geometry.snapBand(short, 1, "body", {}, fullFrame, 12),
        { x = 0.20, y = 0, w = 0.20, h = 0.019 }
    )
end)

test.test("snapBand horizontal edges ignore a short unrelated height", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }

    test.rect(
        geometry.snapBand(
            { x = 0.024, y = 0.20, w = 0.030, h = 0.019 },
            2,
            "left",
            { { x = 0.034, y = 0.70, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        { x = 0.034, y = 0.20, w = 0.054 - 0.034, h = 0.019 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.25, y = 0.20, w = 0.030, h = 0.019 },
            2,
            "right",
            { { x = 0.27, y = 0.70, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        { x = 0.25, y = 0.20, w = 0.27 - 0.25, h = 0.019 }
    )
end)

test.test("snapBand vertical edges ignore a narrow unrelated width", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }

    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0.024, w = 0.019, h = 0.030 },
            2,
            "top",
            { { x = 0.70, y = 0.034, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        { x = 0.20, y = 0.034, w = 0.019, h = 0.054 - 0.034 }
    )
    test.rect(
        geometry.snapBand(
            { x = 0.20, y = 0.25, w = 0.019, h = 0.030 },
            2,
            "bottom",
            { { x = 0.70, y = 0.27, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        { x = 0.20, y = 0.25, w = 0.019, h = 0.27 - 0.25 }
    )
end)

test.test("snapBand rejects only a sub-minimum horizontal resize dimension", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }
    local raw = { x = 0.25, y = 0.20, w = 0.030, h = 0.019 }

    test.rect(
        geometry.snapBand(
            raw,
            2,
            "right",
            { { x = 0.269999999999, y = 0.70, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        raw
    )
end)

test.test("snapBand rejects only a sub-minimum vertical resize dimension", function()
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }
    local raw = { x = 0.20, y = 0.25, w = 0.019, h = 0.030 }

    test.rect(
        geometry.snapBand(
            raw,
            2,
            "bottom",
            { { x = 0.70, y = 0.269999999999, w = 0.10, h = 0.10 } },
            fullFrame,
            12
        ),
        raw
    )
end)

local function resizedEdge(rect, part)
    if part == "left" then
        return rect.x
    elseif part == "right" then
        return rect.x + rect.w
    elseif part == "top" then
        return rect.y
    end

    return rect.y + rect.h
end

local function resizedSizePoints(rect, part, fullFrame)
    if part == "left" or part == "right" then
        return rect.w * fullFrame.w
    end

    return rect.h * fullFrame.h
end

local exactResizeCases = {
    {
        part = "left",
        raw = { x = 0.24, y = 0.20, w = 0.02953125, h = 0.20 },
        peer = { x = 0.25, y = 0.70, w = 0.30, h = 0.10 },
        target = 0.25,
    },
    {
        part = "right",
        raw = { x = 0.25, y = 0.20, w = 0.03, h = 0.20 },
        peer = { x = 0.26953125, y = 0.70, w = 0.30, h = 0.10 },
        target = 0.26953125,
    },
    {
        part = "top",
        raw = { x = 0.20, y = 0.24, w = 0.20, h = 0.02953125 },
        peer = { x = 0.70, y = 0.25, w = 0.10, h = 0.30 },
        target = 0.25,
    },
    {
        part = "bottom",
        raw = { x = 0.20, y = 0.25, w = 0.20, h = 0.03 },
        peer = { x = 0.70, y = 0.26953125, w = 0.10, h = 0.30 },
        target = 0.26953125,
    },
}

for _, case in ipairs(exactResizeCases) do
    local resizeCase = case

    test.test("snapBand returns an exact legal 20-point " .. resizeCase.part .. " resize", function()
        local fullFrame = { x = 0, y = 0, w = 1024, h = 1024 }
        local snapped = geometry.snapBand(
            resizeCase.raw,
            2,
            resizeCase.part,
            { resizeCase.peer },
            fullFrame,
            12
        )

        test.equal(resizedEdge(snapped, resizeCase.part), resizeCase.target)
        test.equal(resizedSizePoints(snapped, resizeCase.part, fullFrame) >= 20, true)
    end)
end

local integerPointResizeCases = {
    {
        part = "left",
        raw = { x = 92 / 3440, y = 0.20, w = 30 / 3440, h = 0.20 },
        peer = { x = 102 / 3440, y = 0.70, w = 0.30, h = 0.10 },
        target = 102 / 3440,
    },
    {
        part = "right",
        raw = { x = 102 / 3440, y = 0.20, w = 30 / 3440, h = 0.20 },
        peer = { x = 122 / 3440, y = 0.70, w = 0.30, h = 0.10 },
        target = 122 / 3440,
    },
    {
        part = "top",
        raw = { x = 0.20, y = 90 / 1920, w = 0.20, h = 30 / 1920 },
        peer = { x = 0.70, y = 100 / 1920, w = 0.10, h = 0.30 },
        target = 100 / 1920,
    },
    {
        part = "bottom",
        raw = { x = 0.20, y = 100 / 1920, w = 0.20, h = 30 / 1920 },
        peer = { x = 0.70, y = 120 / 1920, w = 0.10, h = 0.30 },
        target = 120 / 1920,
    },
}

for _, case in ipairs(integerPointResizeCases) do
    local resizeCase = case

    test.test("snapBand accepts an integer 20-point " .. resizeCase.part .. " resize", function()
        local snapped = geometry.snapBand(
            resizeCase.raw,
            2,
            resizeCase.part,
            { resizeCase.peer },
            { x = 0, y = 0, w = 3440, h = 1920 },
            12
        )

        test.equal(resizedEdge(snapped, resizeCase.part), resizeCase.target)
    end)
end

test.test("snapBand rejects a resize result just below 20 points wide", function()
    local raw = { x = 0.50, y = 0.20, w = 0.025, h = 0.20 }
    local snapped = geometry.snapBand(
        raw,
        2,
        "right",
        { { x = 0.5199999999995, y = 0.70, w = 0.10, h = 0.10 } },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.rect(snapped, raw)
end)

test.test("snapBand accepts a 20-point resize within machine-scale drift", function()
    local raw = { x = 0.002, y = 0.20, w = 0.025, h = 0.20 }
    local snapped = geometry.snapBand(
        raw,
        2,
        "right",
        { { x = 0.022, y = 0.70, w = 0.30, h = 0.10 } },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x + snapped.w, 0.022)
    test.equal(snapped.w, 0.022 - raw.x)
end)

local subMinimumResizeCases = {
    {
        part = "left",
        raw = { x = 0.24, y = 0.20, w = 0.0285546875, h = 0.20 },
        peer = { x = 0.25, y = 0.70, w = 0.30, h = 0.10 },
    },
    {
        part = "right",
        raw = { x = 0.25, y = 0.20, w = 0.03, h = 0.20 },
        peer = { x = 0.2685546875, y = 0.70, w = 0.30, h = 0.10 },
    },
    {
        part = "top",
        raw = { x = 0.20, y = 0.24, w = 0.20, h = 0.0285546875 },
        peer = { x = 0.70, y = 0.25, w = 0.10, h = 0.30 },
    },
    {
        part = "bottom",
        raw = { x = 0.20, y = 0.25, w = 0.20, h = 0.03 },
        peer = { x = 0.70, y = 0.2685546875, w = 0.10, h = 0.30 },
    },
}

for _, case in ipairs(subMinimumResizeCases) do
    local resizeCase = case

    test.test("snapBand rejects a sub-20-point " .. resizeCase.part .. " resize", function()
        local snapped = geometry.snapBand(
            resizeCase.raw,
            2,
            resizeCase.part,
            { resizeCase.peer },
            { x = 0, y = 0, w = 1024, h = 1024 },
            12
        )

        test.rect(snapped, resizeCase.raw)
    end)
end

test.test("snapBand ignores malformed peers and continues to later targets", function()
    local active = { x = 0.39, y = 0.30, w = 0.20, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        4,
        "body",
        {
            {},
            "invalid",
            { x = 0.40, y = 0.70, w = 0.20, h = 0.10 },
            active,
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x, 0.40)
end)

test.test("snapBand ignores absent peer indexes and preserves index ordering", function()
    local active = { x = 0.39, y = 0.30, w = 0.20, h = 0.20 }
    local snapped = geometry.snapBand(
        active,
        4,
        "body",
        {
            [1] = { x = 0.10, y = 0.10, w = 0.10, h = 0.10 },
            [3] = { x = 0.40, y = 0.70, w = 0.20, h = 0.10 },
            [4] = active,
        },
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped.x, 0.40)
end)

test.test("snapBand returns a fresh rectangle without mutating inputs", function()
    local peer = { x = 0.40, y = 0.70, w = 0.20, h = 0.10 }
    local raw = { x = 0.39, y = 0.30, w = 0.20, h = 0.20 }
    local bands = { peer, raw }
    local snapped = geometry.snapBand(
        raw,
        2,
        "body",
        bands,
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(snapped == raw, false)
    test.equal(bands[1] == peer, true)
    test.equal(bands[2] == raw, true)
    test.rect(peer, { x = 0.40, y = 0.70, w = 0.20, h = 0.10 })
    test.rect(raw, { x = 0.39, y = 0.30, w = 0.20, h = 0.20 })
end)

test.test("snapBand fails closed to fresh copies for invalid arguments", function()
    local raw = { x = 0.012, y = 0.20, w = 0.20, h = 0.20 }
    local fullFrame = { x = 0, y = 0, w = 1000, h = 1000 }
    local results = {
        geometry.snapBand(raw, 1, "body", {}, nil, 12),
        geometry.snapBand(raw, 1, "body", {}, { x = 0, y = 0, w = 0, h = 1000 }, 12),
        geometry.snapBand(raw, 1, "body", {}, { w = 1000, h = 1000 }, 12),
        geometry.snapBand(raw, 0, "body", {}, fullFrame, 12),
        geometry.snapBand(raw, 1, "body", "invalid", fullFrame, 12),
        geometry.snapBand(raw, 1, "corner", {}, fullFrame, 12),
        geometry.snapBand(raw, 1, "body", {}, fullFrame, math.huge),
    }

    for _, result in ipairs(results) do
        test.equal(result == raw, false)
        test.rect(result, raw)
    end
end)

test.test("snapBand fails closed for a malformed raw band", function()
    local raw = { x = -0.005, y = 0.20, w = "wide", h = 0.20 }
    local result = geometry.snapBand(
        raw,
        1,
        "body",
        {},
        { x = 0, y = 0, w = 1000, h = 1000 },
        12
    )

    test.equal(result == raw, false)
    test.rect(result, raw)
end)

test.test("intersects requires positive overlap", function()
    local left = { x = 0, y = 0, w = 100, h = 100 }

    test.equal(geometry.intersects(left, { x = 100, y = 0, w = 100, h = 100 }), false)
    test.equal(geometry.intersects(left, { x = 99, y = 0, w = 100, h = 100 }), true)
end)

test.test("correctedFrame returns nil when no mask intersects the window", function()
    local result = geometry.correctedFrame(
        { x = 0, y = 100, w = 300, h = 400 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 400, y = 0, w = 300, h = 800 } }
    )

    test.equal(result, nil)
end)

test.test("correctedFrame preserves size on the side requiring less movement", function()
    local result = geometry.correctedFrame(
        { x = 550, y = 100, w = 200, h = 400 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 400, y = 0, w = 300, h = 800 } }
    )

    test.rect(result, { x = 700, y = 100, w = 200, h = 400 })
end)

test.test("correctedFrame keeps a wide left-dragged window on the nearest safe side", function()
    local result = geometry.correctedFrame(
        { x = -700, y = 100, w = 1400, h = 700 },
        { x = -951, y = 25, w = 3440, h = 1415 },
        { { x = 214, y = 0, w = 755, h = 1440 } }
    )

    test.rect(result, { x = -951, y = 100, w = 1165, h = 700 })
end)

test.test("correctedFrame keeps a wide right-dragged window on the nearest safe side", function()
    local result = geometry.correctedFrame(
        { x = 700, y = 100, w = 1400, h = 700 },
        { x = -951, y = 25, w = 3440, h = 1415 },
        { { x = 214, y = 0, w = 755, h = 1440 } }
    )

    test.rect(result, { x = 969, y = 100, w = 1400, h = 700 })
end)

test.test("correctedFrame prefers shorter movement even when it requires shrinking", function()
    local result = geometry.correctedFrame(
        { x = 100, y = 100, w = 500, h = 400 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 400, y = 0, w = 300, h = 800 } }
    )

    test.rect(result, { x = 0, y = 100, w = 400, h = 400 })
end)

test.test("correctedFrame shrinks an oversized window on the nearest safe side", function()
    local result = geometry.correctedFrame(
        { x = 300, y = -100, w = 1000, h = 1000 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 400, y = 0, w = 300, h = 800 } }
    )

    test.rect(result, { x = 0, y = 0, w = 400, h = 800 })
end)

test.test("correctedFrame chooses left on equal reduction and movement", function()
    local result = geometry.correctedFrame(
        { x = 350, y = 100, w = 300, h = 400 },
        { x = 0, y = 0, w = 1000, h = 800 },
        { { x = 400, y = 0, w = 200, h = 800 } }
    )

    test.rect(result, { x = 100, y = 100, w = 300, h = 400 })
end)

test.test("correctedFrame combines all mask bands in the final vertical span", function()
    local result = geometry.correctedFrame(
        { x = 350, y = 100, w = 500, h = 600 },
        { x = 0, y = 0, w = 1200, h = 800 },
        {
            { x = 400, y = 0, w = 100, h = 300 },
            { x = 600, y = 500, w = 100, h = 300 },
        }
    )

    test.rect(result, { x = 700, y = 100, w = 500, h = 600 })
end)

test.test("correctedFrame keeps the clamped frame when vertical movement clears the mask", function()
    local result = geometry.correctedFrame(
        { x = 350, y = 20, w = 500, h = 100 },
        { x = 0, y = 100, w = 1200, h = 700 },
        { { x = 400, y = 0, w = 300, h = 80 } }
    )

    test.rect(result, { x = 350, y = 100, w = 500, h = 100 })
end)

test.test("correctedFrame uses right when the left safe region has no width", function()
    local result = geometry.correctedFrame(
        { x = 0, y = 100, w = 500, h = 400 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 0, y = 0, w = 300, h = 800 } }
    )

    test.rect(result, { x = 300, y = 100, w = 500, h = 400 })
end)

test.test("correctedFrame returns nil when neither safe region has width", function()
    local result = geometry.correctedFrame(
        { x = 100, y = 100, w = 500, h = 400 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 0, y = 0, w = 1200, h = 800 } }
    )

    test.equal(result, nil)
end)

test.test("correctedFrame keeps deterministic targets in negative coordinates", function()
    local result = geometry.correctedFrame(
        { x = -850, y = 100, w = 500, h = 400 },
        { x = -1200, y = 0, w = 1200, h = 800 },
        { { x = -800, y = 0, w = 300, h = 800 } }
    )

    test.rect(result, { x = -500, y = 100, w = 500, h = 400 })
end)

test.test("framesNear accepts sub-point drift but rejects material change", function()
    local frame = { x = 100, y = 200, w = 500, h = 400 }

    test.equal(geometry.framesNear(frame, { x = 100.5, y = 199.5, w = 500.5, h = 399.5 }), true)
    test.equal(geometry.framesNear(frame, { x = 101.01, y = 200, w = 500, h = 400 }), false)
end)
