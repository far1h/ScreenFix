local M = {}
local tests = {}

function M.test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

function M.equal(actual, expected)
    if actual ~= expected then
        error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end

function M.rect(actual, expected)
    M.equal(actual.x, expected.x)
    M.equal(actual.y, expected.y)
    M.equal(actual.w, expected.w)
    M.equal(actual.h, expected.h)
end

function M.run()
    local failures = 0

    for _, case in ipairs(tests) do
        local passed, message = pcall(case.fn)
        if passed then
            print("PASS " .. case.name)
        else
            failures = failures + 1
            print("FAIL " .. case.name .. ": " .. message)
        end
    end

    if failures == 0 then
        return 0
    end

    return 1
end

return M
