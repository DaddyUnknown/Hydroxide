-- NEW MODULE: Parallel Luau Monitor for Hydroxide (2026)
-- Safe monitoring of Actor-based parallel execution contexts

local ParallelLuauMonitor = {}

local requiredMethods = {
    ["getGc"] = true,
    ["getInfo"] = true,
}

local actorMonitors = {}
local parallelCalls = {}
local actorStats = {
    totalActors = 0,
    activeActors = 0,
    totalParallelCalls = 0,
    threadSafeCalls = 0,
    unsafeCalls = 0
}

-- Detect if code is running in an Actor context
local function isInActorContext()
    local success, result = pcall(function()
        return task.synchronize ~= nil and task.desynchronize ~= nil
    end)
    return success and result
end

-- Safely wrap a function to work in parallel context
local function makeThreadSafe(func)
    return function(...)
        local args = {...}
        local results
        
        -- Check if we're in parallel context
        if isInActorContext() then
            -- Synchronize to main thread for safety
            local success = pcall(function()
                task.synchronize()
                results = {func(unpack(args))}
                task.desynchronize()
            end)
            
            if not success then
                warn("[ParallelLuauMonitor] Failed to synchronize actor call")
                return nil
            end
        else
            -- Regular execution
            results = {func(unpack(args))}
        end
        
        return unpack(results or {})
    end
end

-- Track Actor instances
local function scanForActors()
    local actors = {}
    
    for _, instance in pairs(game:GetDescendants()) do
        if instance:IsA("Actor") then
            table.insert(actors, instance)
        end
    end
    
    actorStats.totalActors = #actors
    return actors
end

-- Monitor parallel script execution
local function monitorParallelScript(actor, script)
    if not actor or not script then return end
    
    local monitorData = {
        actor = actor,
        script = script,
        calls = 0,
        errors = 0,
        lastActivity = tick(),
        isActive = true
    }
    
    actorMonitors[actor] = monitorData
    actorStats.activeActors = actorStats.activeActors + 1
    
    return monitorData
end

-- Log parallel remote calls safely
function ParallelLuauMonitor.logParallelCall(remoteInstance, args, context)
    actorStats.totalParallelCalls = actorStats.totalParallelCalls + 1
    
    local callData = {
        remote = remoteInstance,
        args = args,
        context = context or "unknown",
        timestamp = tick(),
        thread = coroutine.running(),
        isParallel = isInActorContext()
    }
    
    if callData.isParallel then
        actorStats.threadSafeCalls = actorStats.threadSafeCalls + 1
    else
        actorStats.unsafeCalls = actorStats.unsafeCalls + 1
    end
    
    table.insert(parallelCalls, callData)
    
    -- Keep only last 1000 calls
    if #parallelCalls > 1000 then
        table.remove(parallelCalls, 1)
    end
    
    return callData
end

-- Create thread-safe remote hook
function ParallelLuauMonitor.createSafeRemoteHook(remoteInstance, hookFunction)
    if not remoteInstance then return nil end
    
    local className = remoteInstance.ClassName
    local originalMethod
    
    -- Determine method to hook
    if className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
        originalMethod = remoteInstance.FireServer
    elseif className == "RemoteFunction" then
        originalMethod = remoteInstance.InvokeServer
    else
        return nil
    end
    
    -- Create thread-safe wrapper
    local safeHook = makeThreadSafe(function(...)
        local args = {...}
        
        -- Log the call
        ParallelLuauMonitor.logParallelCall(remoteInstance, args, "actor_context")
        
        -- Execute user hook
        if hookFunction then
            pcall(hookFunction, ...)
        end
        
        -- Call original
        return originalMethod(...)
    end)
    
    return safeHook
end

-- Scan for parallel-executing closures
function ParallelLuauMonitor.scanParallelClosures()
    local parallelClosures = {}
    
    for _, func in pairs(getGc()) do
        if type(func) == "function" then
            local success, info = pcall(getInfo, func)
            if success and info.source then
                -- Check if function might be parallel-unsafe
                local source = info.source:lower()
                
                -- Pattern 1: Uses task.desynchronize
                if source:find("task%.desynchronize") or source:find("task%.synchronize") then
                    table.insert(parallelClosures, {
                        func = func,
                        type = "ParallelLuauAPI",
                        info = info,
                        risk = "High"
                    })
                end
                
                -- Pattern 2: Actor:SendMessage patterns
                if source:find("sendmessage") or source:find("bindtomessage") then
                    table.insert(parallelClosures, {
                        func = func,
                        type = "ActorMessaging",
                        info = info,
                        risk = "Medium"
                    })
                end
            end
        end
    end
    
    return parallelClosures
end

-- Get statistics
function ParallelLuauMonitor.getStats()
    -- Update active actors
    local currentActive = 0
    for actor, monitor in pairs(actorMonitors) do
        if monitor.isActive and (tick() - monitor.lastActivity) < 5 then
            currentActive = currentActive + 1
        end
    end
    actorStats.activeActors = currentActive
    
    return {
        totalActors = actorStats.totalActors,
        activeActors = actorStats.activeActors,
        totalParallelCalls = actorStats.totalParallelCalls,
        threadSafeCalls = actorStats.threadSafeCalls,
        unsafeCalls = actorStats.unsafeCalls,
        recentCalls = #parallelCalls
    }
end

-- Get recent parallel calls
function ParallelLuauMonitor.getRecentCalls(count)
    count = count or 10
    local recent = {}
    
    local startIdx = math.max(1, #parallelCalls - count + 1)
    for i = startIdx, #parallelCalls do
        table.insert(recent, parallelCalls[i])
    end
    
    return recent
end

-- Format report
function ParallelLuauMonitor.formatReport()
    local stats = ParallelLuauMonitor.getStats()
    local actors = scanForActors()
    
    local output = "=== Parallel Luau Monitor Report ===\n\n"
    
    output = output .. "🔀 Actor Statistics:\n"
    output = output .. string.format("  Total Actors Found: %d\n", stats.totalActors)
    output = output .. string.format("  Active Actors: %d\n", stats.activeActors)
    output = output .. string.format("  Total Parallel Calls: %d\n", stats.totalParallelCalls)
    output = output .. string.format("  Thread-Safe Calls: %d\n", stats.threadSafeCalls)
    output = output .. string.format("  Unsafe Calls: %d\n\n", stats.unsafeCalls)
    
    if #actors > 0 then
        output = output .. "📋 Detected Actors:\n"
        for i, actor in ipairs(actors) do
            local monitor = actorMonitors[actor]
            output = output .. string.format("  %d. %s (Parent: %s)\n", 
                i, actor.Name, actor.Parent and actor.Parent.Name or "nil")
            if monitor then
                output = output .. string.format("     Calls: %d | Errors: %d | Last: %.1fs ago\n",
                    monitor.calls, monitor.errors, tick() - monitor.lastActivity)
            end
        end
        output = output .. "\n"
    end
    
    local parallelClosures = ParallelLuauMonitor.scanParallelClosures()
    if #parallelClosures > 0 then
        output = output .. "⚠️ Parallel-Unsafe Closures:\n"
        for i, closure in ipairs(parallelClosures) do
            output = output .. string.format("  %d. Type: %s | Risk: %s\n", 
                i, closure.type, closure.risk)
        end
        output = output .. "\n"
    end
    
    local recentCalls = ParallelLuauMonitor.getRecentCalls(5)
    if #recentCalls > 0 then
        output = output .. "📝 Recent Parallel Calls:\n"
        for i, call in ipairs(recentCalls) do
            output = output .. string.format("  %d. %s | Context: %s | Parallel: %s\n",
                i, call.remote.Name, call.context, tostring(call.isParallel))
        end
    end
    
    return output
end

-- Initialize monitoring
function ParallelLuauMonitor.initialize()
    scanForActors()
    
    -- Set up Actor detection listener
    game.DescendantAdded:Connect(function(instance)
        if instance:IsA("Actor") then
            actorStats.totalActors = actorStats.totalActors + 1
            monitorParallelScript(instance, nil)
        end
    end)
    
    return true
end

ParallelLuauMonitor.RequiredMethods = requiredMethods
return ParallelLuauMonitor
