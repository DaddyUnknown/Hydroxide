local RemoteSpy = {}
local Remote = import("objects/Remote")

-- Lazy load new modules to avoid init errors
local NetworkStats
local AutomationGenerator

local requiredMethods = {
    ["checkCaller"] = true,
    ["newCClosure"] = true,
    ["hookFunction"] = true,
    ["isReadOnly"] = true,
    ["setReadOnly"] = true,
    ["getInfo"] = true,
    ["getMetatable"] = true,
    ["setClipboard"] = true,
    ["getNamecallMethod"] = true,
    ["getCallingScript"] = true,
}

local remoteMethods = {
    FireServer = true,
    InvokeServer = true,
    Fire = true,
    Invoke = true
}

local remotesViewing = {
    RemoteEvent = true,
    RemoteFunction = false,
    BindableEvent = false,
    BindableFunction = false,
    UnreliableRemoteEvent = true -- NEW: Support for UnreliableRemoteEvent (2023+)
}

local methodHooks = {
    RemoteEvent = Instance.new("RemoteEvent").FireServer,
    RemoteFunction = Instance.new("RemoteFunction").InvokeServer,
    BindableEvent = Instance.new("BindableEvent").Fire,
    BindableFunction = Instance.new("BindableFunction").Invoke,
    UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent").FireServer -- NEW: Hook for UnreliableRemoteEvent
}

local currentRemotes = {}

local remoteDataEvent = Instance.new("BindableEvent")
local eventSet = false

local function connectEvent(callback)
    remoteDataEvent.Event:Connect(callback)

    if not eventSet then
        eventSet = true
    end
end

local nmcTrampoline
nmcTrampoline = hookMetaMethod(game, "__namecall", function(...)
    local instance = ...
    
    if typeof(instance) ~= "Instance" then
        return nmcTrampoline(...)
    end

    local method = getNamecallMethod()

    if method == "fireServer" then
        method = "FireServer"
    elseif method == "invokeServer" then
        method = "InvokeServer"
    end
        
    if remotesViewing[instance.ClassName] and instance ~= remoteDataEvent and remoteMethods[method] then
        local remote = currentRemotes[instance]
        local vargs = {select(2, ...)}
            
        if not remote then
            remote = Remote.new(instance)
            currentRemotes[instance] = remote
        end

        local remoteIgnored = remote.Ignored
        local remoteBlocked = remote.Blocked
        local argsIgnored = remote.AreArgsIgnored(remote, vargs)
        local argsBlocked = remote.AreArgsBlocked(remote, vargs)

        if eventSet and (not remoteIgnored and not argsIgnored) then
            local call = {
                script = getCallingScript((PROTOSMASHER_LOADED ~= nil and 2) or nil),
                args = vargs,
                func = getInfo(3).func
            }

            remote.IncrementCalls(remote, call)
            remoteDataEvent.Fire(remoteDataEvent, instance, call)
            
            -- NEW: Track network statistics (lazy load)
            if not NetworkStats then
                local success, module = pcall(import, "modules/NetworkStats")
                if success then NetworkStats = module end
            end
            if NetworkStats then
                pcall(NetworkStats.trackCall, instance, vargs)
            end
            
            -- NEW: Record for automation if recording active (lazy load)
            if not AutomationGenerator then
                local success, module = pcall(import, "modules/AutomationGenerator")
                if success then AutomationGenerator = module end
            end
            if AutomationGenerator then
                pcall(AutomationGenerator.recordCall, instance, vargs)
            end
        end

        if remoteBlocked or argsBlocked then
            return
        end
    end

    return nmcTrampoline(...)
end)

-- vuln fix

local pcall = pcall

local function checkPermission(instance)
    if (instance.ClassName) then end
end

for _name, hook in pairs(methodHooks) do
    local originalMethod
    originalMethod = hookFunction(hook, newCClosure(function(...)
        local instance = ...

        if typeof(instance) ~= "Instance" then
            return originalMethod(...)
        end
                
        do
            local success = pcall(checkPermission, instance)
            if (not success) then return originalMethod(...) end
        end

        if instance.ClassName == _name and remotesViewing[instance.ClassName] and instance ~= remoteDataEvent then
            local remote = currentRemotes[instance]
            local vargs = {select(2, ...)}

            if not remote then
                remote = Remote.new(instance)
                currentRemotes[instance] = remote
            end

            local remoteIgnored = remote.Ignored 
            local argsIgnored = remote:AreArgsIgnored(vargs)
            
            if eventSet and (not remoteIgnored and not argsIgnored) then
                local call = {
                    script = getCallingScript((PROTOSMASHER_LOADED ~= nil and 2) or nil),
                    args = vargs,
                    func = getInfo(3).func
                }
    
                remote:IncrementCalls(call)
                remoteDataEvent:Fire(instance, call)
                
                -- NEW: Track network statistics (lazy load)
                if not NetworkStats then
                    local success, module = pcall(import, "modules/NetworkStats")
                    if success then NetworkStats = module end
                end
                if NetworkStats then
                    pcall(NetworkStats.trackCall, instance, vargs)
                end
                
                -- NEW: Record for automation if recording active (lazy load)
                if not AutomationGenerator then
                    local success, module = pcall(import, "modules/AutomationGenerator")
                    if success then AutomationGenerator = module end
                end
                if AutomationGenerator then
                    pcall(AutomationGenerator.recordCall, instance, vargs)
                end
            end

            if remote.Blocked or remote:AreArgsBlocked(vargs) then
                return
            end
        end
        
        return originalMethod(...)
    end))

    oh.Hooks[originalMethod] = hook
end

-- Lazy load function for external access
local function getNetworkStats()
    if not NetworkStats then
        local success, module = pcall(import, "modules/NetworkStats")
        if success then NetworkStats = module end
    end
    return NetworkStats
end

local function getAutomationGenerator()
    if not AutomationGenerator then
        local success, module = pcall(import, "modules/AutomationGenerator")
        if success then AutomationGenerator = module end
    end
    return AutomationGenerator
end

RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.RequiredMethods = requiredMethods
RemoteSpy.GetNetworkStats = getNetworkStats -- Lazy getter
RemoteSpy.GetAutomationGenerator = getAutomationGenerator -- Lazy getter
return RemoteSpy
