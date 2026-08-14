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
