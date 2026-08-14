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

test.test("correctedFrame prefers preserved size over shorter movement", function()
    local oracle = geometry.correctedFrame(
        { x = 360, y = 100, w = 500, h = 400 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 400, y = 0, w = 300, h = 800 } }
    )
    local farther = geometry.correctedFrame(
        { x = 100, y = 100, w = 500, h = 400 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 400, y = 0, w = 300, h = 800 } }
    )

    test.rect(oracle, { x = 700, y = 100, w = 500, h = 400 })
    test.rect(farther, { x = 700, y = 100, w = 500, h = 400 })
end)

test.test("correctedFrame shrinks an oversized window only to its safe region", function()
    local result = geometry.correctedFrame(
        { x = 300, y = -100, w = 1000, h = 1000 },
        { x = 0, y = 0, w = 1200, h = 800 },
        { { x = 400, y = 0, w = 300, h = 800 } }
    )

    test.rect(result, { x = 700, y = 0, w = 500, h = 800 })
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
