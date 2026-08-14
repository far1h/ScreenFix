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

function M.screen(uuid, name, fullFrame, usableFrame)
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
        frame = function()
            return usableFrame or fullFrame
        end,
    }
end

function M.window(options)
    local currentFrame = options.frame
    local window = {
        setFrameCalls = {},
    }

    function window:id()
        return options.id
    end

    function window:frame()
        return currentFrame
    end

    function window:screen()
        return options.screen
    end

    function window:isStandard()
        return options.isStandard ~= false
    end

    function window:isVisible()
        return options.isVisible ~= false
    end

    function window:isMinimized()
        return options.isMinimized == true
    end

    function window:isFullScreen()
        return options.isFullScreen == true
    end

    function window:setFrame(frame, duration)
        self.setFrameCalls[#self.setFrameCalls + 1] = {
            frame = frame,
            duration = duration,
        }
        if options.setFrameError ~= nil then
            error(options.setFrameError, 0)
        end
        if options.acceptFrame ~= false then
            currentFrame = frame
        end
        return self
    end

    return window
end

function M.clock(initialTime)
    local clock = {
        time = initialTime or 0,
    }

    function clock:now()
        return self.time
    end

    function clock:advance(seconds)
        self.time = self.time + seconds
    end

    return clock
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

function M.timer()
    local module = {
        doAfterCalls = {},
        timers = {},
    }

    function module.doAfter(delay, callback)
        if module.doAfterError ~= nil then
            error(module.doAfterError, 0)
        end

        local timer = {
            callback = callback,
            delay = delay,
            fired = false,
            stopCount = 0,
            stopped = false,
        }

        function timer:fire()
            if self.stopped or self.fired then
                return
            end

            self.fired = true
            self.callback()
        end

        function timer:stop()
            self.stopCount = self.stopCount + 1
            self.stopped = true
            if self.stopError ~= nil then
                error(self.stopError, 0)
            end
            return self
        end

        module.doAfterCalls[#module.doAfterCalls + 1] = {
            callback = callback,
            delay = delay,
        }
        module.timers[#module.timers + 1] = timer
        return timer
    end

    return module
end

function M.windowFilter()
    local module = {
        filters = {},
        newCount = 0,
        registries = {
            activeInstances = {},
            applicationActiveInstances = {},
            spacesInstances = {},
        },
        windowCreated = "windowCreated",
        windowMoved = "windowMoved",
        windowOnScreen = "windowOnScreen",
        watchers = {
            activeInstances = false,
            applicationActiveInstances = false,
            spacesInstances = false,
        },
    }

    local function updateWatchers()
        for name, registry in pairs(module.registries) do
            module.watchers[name] = next(registry) ~= nil
        end
    end

    function module.retainedFilterCount()
        local retained = {}
        for _, registry in pairs(module.registries) do
            for filter in pairs(registry) do
                retained[filter] = true
            end
        end

        local count = 0
        for _ in pairs(retained) do
            count = count + 1
        end
        return count
    end

    function module.watcherCount()
        local count = 0
        for _, active in pairs(module.watchers) do
            if active then
                count = count + 1
            end
        end
        return count
    end

    function module.new()
        module.newCount = module.newCount + 1
        local filter = {
            deleteCount = 0,
            lifecycleCalls = {},
            pauseCount = 0,
            paused = false,
            subscribeCalls = {},
            subscriptions = {},
            unsubscribeAllCount = 0,
        }

        function filter:setOverrideFilter(override)
            self.override = override
            return self
        end

        function filter:subscribe(events, callback)
            self.subscribeCalls[#self.subscribeCalls + 1] = {
                callback = callback,
                events = events,
            }
            if self.subscribeError ~= nil then
                error(self.subscribeError, 0)
            end

            self.subscriptions[#self.subscriptions + 1] = {
                callback = callback,
                events = events,
            }
            self.paused = false
            module.registries.activeInstances[self] = true
            if self.override ~= nil and self.override.currentSpace == true then
                module.registries.spacesInstances[self] = true
            end
            updateWatchers()
            return self
        end

        function filter:emit(event, window)
            if self.paused then
                return
            end

            for _, subscription in ipairs(self.subscriptions) do
                for _, subscribedEvent in ipairs(subscription.events) do
                    if event == subscribedEvent then
                        subscription.callback(window, nil, event)
                    end
                end
            end
        end

        function filter:unsubscribeAll()
            self.unsubscribeAllCount = self.unsubscribeAllCount + 1
            self.lifecycleCalls[#self.lifecycleCalls + 1] = "unsubscribeAll"
            self.subscriptions = {}
            if self.unsubscribeAllError ~= nil then
                error(self.unsubscribeAllError, 0)
            end
            return self
        end

        function filter:pause()
            self.pauseCount = self.pauseCount + 1
            self.lifecycleCalls[#self.lifecycleCalls + 1] = "pause"
            self.paused = true
            module.registries.activeInstances[self] = nil
            updateWatchers()
            if self.pauseError ~= nil then
                error(self.pauseError, 0)
            end
            return self
        end

        function filter:delete()
            self.deleteCount = self.deleteCount + 1
            self.lifecycleCalls[#self.lifecycleCalls + 1] = "delete"
            self.deleted = true
            self.subscriptions = {}
            for _, registry in pairs(module.registries) do
                registry[self] = nil
            end
            updateWatchers()
            if self.deleteError ~= nil then
                error(self.deleteError, 0)
            end
        end

        module.filters[#module.filters + 1] = filter
        return filter
    end

    return module
end

return M
