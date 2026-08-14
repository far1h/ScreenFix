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
