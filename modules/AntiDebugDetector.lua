-- NEW MODULE: Anti-Debug Detector for Hydroxide (2026)
-- Detects modern anti-debugging and anti-exploit techniques used in 2023-2026

local AntiDebugDetector = {}

local requiredMethods = {
    ["getGc"] = true,
    ["getInfo"] = true,
    ["getConnections"] = true,
}

local detectedTechniques = {}
local detectionCallbacks = {}

-- Detection for hook detection attempts
local function detectHookScanning()
    local techniques = {}
    
    -- Scan for common hook detection patterns
    for _, func in pairs(getGc()) do
        if type(func) == "function" then
            local success, info = pcall(getInfo, func)
            if success and info.source then
                local source = info.source:lower()
                
                -- Pattern 1: Checking for modified __namecall
                if source:find("getnamecallmethod") and source:find("rawget") then
                    table.insert(techniques, {
                        type = "NamecallHookDetection",
                        method = "Rawget comparison",
                        function_ref = func
                    })
                end
                
                -- Pattern 2: Checking for hookfunction
                if source:find("hookfunction") or source:find("detour") then
                    table.insert(techniques, {
                        type = "HookFunctionDetection",
                        method = "Direct hook checking",
                        function_ref = func
                    })
                end
                
                -- Pattern 3: Metatable comparison
                if source:find("getrawmetatable") and source:find("__index") then
                    table.insert(techniques, {
                        type = "MetatableComparison",
                        method = "Metatable integrity check",
                        function_ref = func
                    })
                end
            end
        end
    end
    
    return techniques
end

-- Detection for remote obfuscation
local function detectRemoteObfuscation()
    local obfuscated = {}
    
    -- Scan all RemoteEvents/Functions for suspicious patterns
    for _, remote in pairs(game:GetDescendants()) do
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") or remote:IsA("UnreliableRemoteEvent") then
            local name = remote.Name
            
            -- Pattern 1: Random character names
            if #name > 20 and name:match("^[%w_]+$") and not name:match("%w%w%w") then
                table.insert(obfuscated, {
                    remote = remote,
                    technique = "RandomName",
                    suspicion_level = "High"
                })
            end
            
            -- Pattern 2: Hidden remotes (parent manipulation)
            if not remote.Parent or remote.Parent == nil then
                table.insert(obfuscated, {
                    remote = remote,
                    technique = "NilParenting",
                    suspicion_level = "Critical"
                })
            end
            
            -- Pattern 3: Dynamic remote creation
            if remote.Parent and remote.Parent.Name:match("^%s*$") then
                table.insert(obfuscated, {
                    remote = remote,
                    technique = "HiddenContainer",
                    suspicion_level = "Medium"
                })
            end
        end
    end
    
    return obfuscated
end

-- Detection for environment checking
local function detectEnvironmentChecks()
    local checks = {}
    
    for _, func in pairs(getGc()) do
        if type(func) == "function" then
            local success, info = pcall(getInfo, func)
            if success and info.source then
                local source = info.source:lower()
                
                -- Pattern 1: Checking for exploit functions
                if source:find("getfenv") or source:find("checkcaller") then
                    table.insert(checks, {
                        type = "ExploitFunctionCheck",
                        function_ref = func
                    })
                end
                
                -- Pattern 2: Stack trace analysis
                if source:find("debug%.traceback") or source:find("getstack") then
                    table.insert(checks, {
                        type = "StackTraceAnalysis",
                        function_ref = func
                    })
                end
                
                -- Pattern 3: Script validation
                if source:find("getcallingscript") or source:find("getscript") then
                    table.insert(checks, {
                        type = "ScriptValidation",
                        function_ref = func
                    })
                end
            end
        end
    end
    
    return checks
end

-- Detection for argument validation
local function detectArgumentValidation()
    local validators = {}
    
    -- Monitor for pattern matching on remote arguments
    for _, remote in pairs(game:GetDescendants()) do
        if (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") or remote:IsA("UnreliableRemoteEvent")) and remote.Parent then
            -- Check for OnServerEvent/OnServerInvoke connections
            local connections = {}
            
            if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                local success, conns = pcall(function() return getConnections(remote.OnServerEvent) end)
                if success then connections = conns end
            elseif remote:IsA("RemoteFunction") then
                local success, conns = pcall(function() return getConnections(remote.OnServerInvoke) end)
                if success then connections = conns end
            end
            
            for _, conn in pairs(connections) do
                if conn.Function then
                    local success, info = pcall(getInfo, conn.Function)
                    if success and info.source then
                        local source = info.source:lower()
                        
                        -- Pattern 1: Type checking
                        if source:find("type%(") and source:find("~=") then
                            table.insert(validators, {
                                remote = remote,
                                technique = "TypeValidation",
                                protection_level = "Basic"
                            })
                        end
                        
                        -- Pattern 2: Range validation
                        if source:find("math%.") and (source:find("clamp") or source:find("min") or source:find("max")) then
                            table.insert(validators, {
                                remote = remote,
                                technique = "RangeValidation",
                                protection_level = "Medium"
                            })
                        end
                        
                        -- Pattern 3: Sanity checking
                        if source:find("assert%(") or source:find("error%(") then
                            table.insert(validators, {
                                remote = remote,
                                technique = "AssertionValidation",
                                protection_level = "High"
                            })
                        end
                    end
                end
            end
        end
    end
    
    return validators
end

-- Main scan function
function AntiDebugDetector.scan()
    local results = {
        hookDetection = detectHookScanning(),
        remoteObfuscation = detectRemoteObfuscation(),
        environmentChecks = detectEnvironmentChecks(),
        argumentValidation = detectArgumentValidation(),
        timestamp = os.time(),
        summary = {
            total_detections = 0,
            critical_threats = 0,
            warnings = 0
        }
    }
    
    -- Calculate summary
    results.summary.total_detections = 
        #results.hookDetection + 
        #results.remoteObfuscation + 
        #results.environmentChecks + 
        #results.argumentValidation
    
    -- Count critical threats
    for _, item in pairs(results.remoteObfuscation) do
        if item.suspicion_level == "Critical" then
            results.summary.critical_threats = results.summary.critical_threats + 1
        end
    end
    
    detectedTechniques = results
    
    -- Trigger callbacks
    for _, callback in pairs(detectionCallbacks) do
        pcall(callback, results)
    end
    
    return results
end

-- Register callback for detection events
function AntiDebugDetector.onDetection(callback)
    table.insert(detectionCallbacks, callback)
end

-- Get last scan results
function AntiDebugDetector.getLastResults()
    return detectedTechniques
end

-- Format results for display
function AntiDebugDetector.formatResults(results)
    if not results then
        results = detectedTechniques
    end
    
    local output = "=== Anti-Debug Detection Report ===\n\n"
    
    output = output .. string.format("Total Detections: %d\n", results.summary.total_detections)
    output = output .. string.format("Critical Threats: %d\n", results.summary.critical_threats)
    output = output .. "\n"
    
    if #results.hookDetection > 0 then
        output = output .. "🔍 Hook Detection Attempts:\n"
        for i, item in pairs(results.hookDetection) do
            output = output .. string.format("  %d. Type: %s | Method: %s\n", i, item.type, item.method)
        end
        output = output .. "\n"
    end
    
    if #results.remoteObfuscation > 0 then
        output = output .. "🎭 Remote Obfuscation:\n"
        for i, item in pairs(results.remoteObfuscation) do
            output = output .. string.format("  %d. Remote: %s | Technique: %s | Level: %s\n", 
                i, item.remote.Name, item.technique, item.suspicion_level)
        end
        output = output .. "\n"
    end
    
    if #results.environmentChecks > 0 then
        output = output .. "🛡️ Environment Checks:\n"
        for i, item in pairs(results.environmentChecks) do
            output = output .. string.format("  %d. Type: %s\n", i, item.type)
        end
        output = output .. "\n"
    end
    
    if #results.argumentValidation > 0 then
        output = output .. "✅ Argument Validation:\n"
        for i, item in pairs(results.argumentValidation) do
            output = output .. string.format("  %d. Remote: %s | Technique: %s | Level: %s\n",
                i, item.remote.Name, item.technique, item.protection_level)
        end
        output = output .. "\n"
    end
    
    return output
end

AntiDebugDetector.RequiredMethods = requiredMethods
return AntiDebugDetector
