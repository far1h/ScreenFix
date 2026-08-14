local M = {}

function M.canvas()
    local module = {
        canvases = {},
        constructorFrames = {},
    }
    local methods = {}
    local metatable = {
        __index = function(canvas, key)
            if type(key) == "number" then
                return canvas.elements[key]
            end

            return methods[key]
        end,
        __newindex = function(canvas, key, value)
            if type(key) == "number" then
                canvas.elements[key] = value
                canvas.elementAssignments[#canvas.elementAssignments + 1] = {
                    index = key,
                    value = value,
                }
                return
            end

            rawset(canvas, key, value)
        end,
    }

    local function failSelectedMethod(name)
        module.methodCallCounts[name] = (module.methodCallCounts[name] or 0) + 1

        if module.failMethod == name
            and module.methodCallCounts[name] == (module.failMethodAt or 1)
        then
            error(module.failMessage or (name .. " failure"), 0)
        end
    end

    module.methodCallCounts = {}

    function module.new(frame)
        module.constructorFrames[#module.constructorFrames + 1] = frame
        if module.failConstructorAt == #module.constructorFrames then
            return nil
        end

        local canvas = setmetatable({
            clickActivatingCalls = {},
            behaviorCalls = {},
            levelCalls = {},
            showCount = 0,
            hideCount = 0,
            deleteCount = 0,
            deleted = false,
            elements = {},
            elementAssignments = {},
        }, metatable)
        module.canvases[#module.canvases + 1] = canvas
        return canvas
    end

    function methods:clickActivating(value)
        self.clickActivatingCalls[#self.clickActivatingCalls + 1] = value
        failSelectedMethod("clickActivating")
        return self
    end

    function methods:behavior(value)
        self.behaviorCalls[#self.behaviorCalls + 1] = value
        failSelectedMethod("behavior")
        return self
    end

    function methods:level(value)
        self.levelCalls[#self.levelCalls + 1] = value
        failSelectedMethod("level")
        return self
    end

    function methods:show()
        self.showCount = self.showCount + 1
        failSelectedMethod("show")
        return self
    end

    function methods:hide()
        self.hideCount = self.hideCount + 1
        failSelectedMethod("hide")
        return self
    end

    function methods:delete()
        self.deleteCount = self.deleteCount + 1
        self.deleted = true
        failSelectedMethod("delete")
    end

    return module
end

function M.screen(uuid, name, fullFrame)
    return {
        getUUID = function()
            return uuid
        end,
        name = function()
            return name
        end,
        fullFrame = function()
            return fullFrame
        end,
    }
end

function M.watcher(callback)
    local watcher = {
        callback = callback,
        startCount = 0,
        stopCount = 0,
    }

    function watcher:start()
        self.startCount = self.startCount + 1
        return self
    end

    function watcher:stop()
        self.stopCount = self.stopCount + 1
        return self
    end

    return watcher
end

return M
