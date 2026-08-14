local M = {}

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
