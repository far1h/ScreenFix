local ScreenConfig = require("screenfix.screen_config")
local fake = require("tests.fake_hs")
local test = require("tests.test_helper")

local function newConfig(deps)
    deps = deps or {}
    deps.settings = deps.settings or {
        get = function()
            return nil
        end,
        set = function()
        end,
    }
    deps.allScreens = deps.allScreens or function()
        return {}
    end
    deps.newScreenWatcher = deps.newScreenWatcher or fake.watcher
    return ScreenConfig.new(deps)
end

local function validConfig()
    return {
        schemaVersion = 1,
        enabled = true,
        screen = {
            uuid = "screen-uuid",
            name = "Damaged Display",
            width = 3440,
            height = 1440,
        },
        bands = {
            { x = 0.43, y = 0.00, w = 0.16, h = 0.34 },
            { x = 0.46, y = 0.34, w = 0.11, h = 0.39 },
            { x = 0.48, y = 0.73, w = 0.07, h = 0.27 },
        },
    }
end

local function invalid(value)
    local result, message = newConfig():validate(value)
    test.equal(result, nil)
    test.equal(type(message), "string")
end

local function malformedIdentityConfigs()
    local result = {}

    local missingEnabled = validConfig()
    missingEnabled.enabled = nil
    result[#result + 1] = missingEnabled

    local emptyName = validConfig()
    emptyName.screen.name = ""
    result[#result + 1] = emptyName

    local infiniteWidth = validConfig()
    infiniteWidth.screen.width = math.huge
    result[#result + 1] = infiniteWidth

    local zeroHeight = validConfig()
    zeroHeight.screen.height = 0
    result[#result + 1] = zeroHeight

    local invalidUuid = validConfig()
    invalidUuid.screen.uuid = false
    result[#result + 1] = invalidUuid

    return result
end

test.test("defaultForScreen builds the versioned monitor configuration", function()
    local screen = fake.screen("screen-uuid", "Damaged Display", {
        x = -3440,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local result = newConfig():defaultForScreen(screen)

    test.equal(result.schemaVersion, 1)
    test.equal(result.enabled, true)
    test.equal(result.screen.uuid, "screen-uuid")
    test.equal(result.screen.name, "Damaged Display")
    test.equal(result.screen.width, 3440)
    test.equal(result.screen.height, 1440)
    test.equal(result.descriptor, nil)
    test.equal(#result.bands, 3)
    test.rect(result.bands[1], {
        x = 1215 / 3440,
        y = 0.00,
        w = 705 / 3440,
        h = 0.34,
    })
    test.rect(result.bands[2], {
        x = 1215 / 3440,
        y = 0.34,
        w = 705 / 3440,
        h = 0.39,
    })
    test.rect(result.bands[3], {
        x = 1215 / 3440,
        y = 0.73,
        w = 705 / 3440,
        h = 0.27,
    })
end)

test.test("defaultForScreen maps every band to the permanent 3440-pixel span", function()
    local width = 3440
    local screen = fake.screen("screen-uuid", "Damaged Display", {
        x = -width,
        y = 0,
        w = width,
        h = 1440,
    })
    local result = newConfig():defaultForScreen(screen)

    for _, band in ipairs(result.bands) do
        test.equal(band.x * width, 1215)
        test.equal((band.x + band.w) * width, 1920)
    end
end)

test.test("defaultForScreen returns fresh configurations and band tables", function()
    local screen = fake.screen("screen-uuid", "Damaged Display", {
        x = -3440,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local first = newConfig():defaultForScreen(screen)
    local second = newConfig():defaultForScreen(screen)

    first.bands[1].x = 0
    first.bands[2].w = 1

    test.equal(second.bands[1].x, 1215 / 3440)
    test.equal(second.bands[2].w, 705 / 3440)
end)

test.test("validate returns a valid configuration", function()
    local value = validConfig()
    local result, message = newConfig():validate(value)

    test.equal(result, value)
    test.equal(message, nil)
end)

test.test("validate rejects invalid configuration structure", function()
    invalid("not a table")

    local wrongVersion = validConfig()
    wrongVersion.schemaVersion = 2
    invalid(wrongVersion)

    local missingScreen = validConfig()
    missingScreen.screen = nil
    invalid(missingScreen)

    local descriptorAlias = validConfig()
    descriptorAlias.descriptor = descriptorAlias.screen
    descriptorAlias.screen = nil
    invalid(descriptorAlias)

    local tooFewBands = validConfig()
    tooFewBands.bands[3] = nil
    invalid(tooFewBands)

    local tooManyBands = validConfig()
    tooManyBands.bands[4] = { x = 0, y = 0, w = 0.1, h = 0.1 }
    invalid(tooManyBands)
end)

test.test("validate requires enabled to be boolean", function()
    local missing = validConfig()
    missing.enabled = nil
    invalid(missing)

    local nonBoolean = validConfig()
    nonBoolean.enabled = "true"
    invalid(nonBoolean)

    local disabled = validConfig()
    disabled.enabled = false
    test.equal(newConfig():validate(disabled), disabled)
end)

test.test("validate requires a non-empty screen name", function()
    local invalidNames = { false, 42, "" }

    for _, name in ipairs(invalidNames) do
        local value = validConfig()
        value.screen.name = name
        invalid(value)
    end

    local missing = validConfig()
    missing.screen.name = nil
    invalid(missing)
end)

test.test("validate requires finite positive screen dimensions", function()
    local invalidDimensions = {
        "3440",
        0 / 0,
        math.huge,
        -math.huge,
        0,
        -1,
    }

    for _, field in ipairs({ "width", "height" }) do
        for _, dimension in ipairs(invalidDimensions) do
            local value = validConfig()
            value.screen[field] = dimension
            invalid(value)
        end

        local missing = validConfig()
        missing.screen[field] = nil
        invalid(missing)
    end
end)

test.test("validate allows a missing UUID but rejects invalid present UUIDs", function()
    local missing = validConfig()
    missing.screen.uuid = nil
    test.equal(newConfig():validate(missing), missing)

    for _, uuid in ipairs({ "", 42, false }) do
        local value = validConfig()
        value.screen.uuid = uuid
        invalid(value)
    end
end)

test.test("validate rejects non-finite and out-of-bounds bands", function()
    local invalidValues = {
        { field = "x", value = 0 / 0 },
        { field = "y", value = math.huge },
        { field = "w", value = -math.huge },
        { field = "h", value = "0.1" },
        { field = "w", value = 0 },
        { field = "h", value = -0.1 },
        { field = "x", value = -0.1 },
        { field = "y", value = -0.1 },
        { field = "x", value = 0.9, other = { field = "w", value = 0.2 } },
        { field = "y", value = 0.9, other = { field = "h", value = 0.2 } },
    }

    for _, case in ipairs(invalidValues) do
        local value = validConfig()
        value.bands[1][case.field] = case.value
        if case.other then
            value.bands[1][case.other.field] = case.other.value
        end
        invalid(value)
    end
end)

test.test("save validates and writes one configuration to its settings key", function()
    local writes = {}
    local settings = {
        get = function(key)
            return writes[key]
        end,
        set = function(key, value)
            writes[#writes + 1] = { key = key, value = value }
            writes[key] = value
        end,
    }
    local config = newConfig({ settings = settings })
    local value = validConfig()

    local result, message = config:save(value)

    test.equal(result, value)
    test.equal(message, nil)
    test.equal(#writes, 1)
    test.equal(writes[1].key, ScreenConfig.KEY)
    test.equal(writes[1].value, value)

    local invalidResult, invalidMessage = config:save("invalid")
    test.equal(invalidResult, nil)
    test.equal(type(invalidMessage), "string")
    test.equal(#writes, 1)
end)

test.test("save rejects malformed identity fields without writing settings", function()
    local writeCount = 0
    local settings = {
        get = function()
            return nil
        end,
        set = function()
            writeCount = writeCount + 1
        end,
    }
    local config = newConfig({ settings = settings })

    for _, value in ipairs(malformedIdentityConfigs()) do
        local result, message = config:save(value)

        test.equal(result, nil)
        test.equal(type(message), "string")
        test.equal(writeCount, 0)
    end
end)

test.test("load reads and validates the persisted configuration", function()
    local value = validConfig()
    local readKey
    local settings = {
        get = function(key)
            readKey = key
            return value
        end,
        set = function()
        end,
    }

    local result, message = newConfig({ settings = settings }):load()

    test.equal(readKey, ScreenConfig.KEY)
    test.equal(result, value)
    test.equal(message, nil)
end)

test.test("load leaves invalid persisted data unchanged", function()
    local store = { [ScreenConfig.KEY] = "invalid" }
    local writeCount = 0
    local settings = {
        get = function(key)
            return store[key]
        end,
        set = function(key, value)
            writeCount = writeCount + 1
            store[key] = value
        end,
    }

    local result, message = newConfig({ settings = settings }):load()

    test.equal(result, nil)
    test.equal(type(message), "string")
    test.equal(store[ScreenConfig.KEY], "invalid")
    test.equal(writeCount, 0)
end)

test.test("load rejects malformed identity fields without mutating persisted data", function()
    for _, value in ipairs(malformedIdentityConfigs()) do
        local store = { [ScreenConfig.KEY] = value }
        local writeCount = 0
        local settings = {
            get = function(key)
                return store[key]
            end,
            set = function(key, replacement)
                writeCount = writeCount + 1
                store[key] = replacement
            end,
        }

        local result, message = newConfig({ settings = settings }):load()

        test.equal(result, nil)
        test.equal(type(message), "string")
        test.equal(store[ScreenConfig.KEY], value)
        test.equal(writeCount, 0)
    end
end)

test.test("findScreen prefers an exact UUID match", function()
    local fallback = fake.screen("other-uuid", "Damaged Display", {
        x = 0,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local exact = fake.screen("screen-uuid", "Renamed Display", {
        x = 0,
        y = 0,
        w = 1920,
        h = 1080,
    })
    local config = newConfig({
        allScreens = function()
            return { fallback, exact }
        end,
    })

    test.equal(config:findScreen(validConfig()), exact)
end)

test.test("findScreen uses a unique exact name and full-frame-size fallback", function()
    local match = fake.screen("replacement-uuid", "Damaged Display", {
        x = 1920,
        y = -100,
        w = 3440,
        h = 1440,
    })
    local wrongSize = fake.screen("wrong-size", "Damaged Display", {
        x = 0,
        y = 0,
        w = 1920,
        h = 1080,
    })
    local wrongName = fake.screen("wrong-name", "Other Display", {
        x = 0,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local config = newConfig({
        allScreens = function()
            return { wrongSize, match, wrongName }
        end,
    })

    test.equal(config:findScreen(validConfig()), match)
end)

test.test("findScreen does not treat missing UUIDs as an exact match", function()
    local noUuid = fake.screen(nil, "Other Display", {
        x = 0,
        y = 0,
        w = 1920,
        h = 1080,
    })
    local fallback = fake.screen("replacement-uuid", "Damaged Display", {
        x = 1920,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local value = validConfig()
    value.screen.uuid = nil
    local config = newConfig({
        allScreens = function()
            return { noUuid, fallback }
        end,
    })

    test.equal(config:findScreen(value), fallback)
end)

test.test("findScreen returns nil for missing or ambiguous fallback matches", function()
    local first = fake.screen("first-uuid", "Damaged Display", {
        x = 0,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local second = fake.screen("second-uuid", "Damaged Display", {
        x = 3440,
        y = 0,
        w = 3440,
        h = 1440,
    })
    local ambiguous = newConfig({
        allScreens = function()
            return { first, second }
        end,
    })
    local missing = newConfig({
        allScreens = function()
            return { fake.screen("other-uuid", "Other Display", {
                x = 0,
                y = 0,
                w = 1920,
                h = 1080,
            }) }
        end,
    })

    test.equal(ambiguous:findScreen(validConfig()), nil)
    test.equal(missing:findScreen(validConfig()), nil)
end)

test.test("watch starts one watcher and replaces the previous watcher", function()
    local watchers = {}
    local config = newConfig({
        newScreenWatcher = function(callback)
            local watcher = fake.watcher(callback)
            watchers[#watchers + 1] = watcher
            return watcher
        end,
    })
    local firstCallback = function()
    end
    local secondCallback = function()
    end

    config:watch(firstCallback)
    test.equal(#watchers, 1)
    test.equal(watchers[1].callback, firstCallback)
    test.equal(watchers[1].startCount, 1)
    test.equal(watchers[1].stopCount, 0)

    config:watch(secondCallback)
    test.equal(#watchers, 2)
    test.equal(watchers[1].stopCount, 1)
    test.equal(watchers[2].callback, secondCallback)
    test.equal(watchers[2].startCount, 1)
end)

test.test("stopWatching is idempotent", function()
    local watchers = {}
    local config = newConfig({
        newScreenWatcher = function(callback)
            local watcher = fake.watcher(callback)
            watchers[#watchers + 1] = watcher
            return watcher
        end,
    })

    config:stopWatching()
    config:watch(function()
    end)
    config:stopWatching()
    config:stopWatching()

    test.equal(#watchers, 1)
    test.equal(watchers[1].startCount, 1)
    test.equal(watchers[1].stopCount, 1)
end)
