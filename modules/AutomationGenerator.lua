-- NEW MODULE: Automation Script Generator for Hydroxide (2026)
-- Generate ready-to-use auto-farm and automation scripts from recorded actions

local AutomationGenerator = {}

local recordingSessions = {}
local currentRecording = nil

-- Recording session structure
local function createRecordingSession(name)
    return {
        name = name or ("Session_" .. os.time()),
        startTime = tick(),
        endTime = nil,
        calls = {},
        patterns = {},
        loopDetected = false,
        averageInterval = 0,
        totalCalls = 0
    }
end

-- Start recording
function AutomationGenerator.startRecording(sessionName)
    if currentRecording then
        warn("[AutomationGenerator] Already recording. Stop current session first.")
        return false
    end
    
    currentRecording = createRecordingSession(sessionName)
    print("[AutomationGenerator] Started recording:", currentRecording.name)
    return true
end

-- Stop recording
function AutomationGenerator.stopRecording()
    if not currentRecording then
        warn("[AutomationGenerator] No active recording session.")
        return nil
    end
    
    currentRecording.endTime = tick()
    currentRecording.duration = currentRecording.endTime - currentRecording.startTime
    
    -- Analyze patterns
    currentRecording.patterns = AutomationGenerator.analyzePatterns(currentRecording)
    
    -- Save session
    table.insert(recordingSessions, currentRecording)
    local session = currentRecording
    currentRecording = nil
    
    print("[AutomationGenerator] Recording stopped:", session.name)
    print(string.format("  Duration: %.1fs | Calls: %d", session.duration, session.totalCalls))
    
    return session
end

-- Record a remote call
function AutomationGenerator.recordCall(remoteInstance, args, metadata)
    if not currentRecording then return end
    
    local callData = {
        remote = remoteInstance,
        remoteName = remoteInstance.Name,
        remoteClass = remoteInstance.ClassName,
        remotePath = getInstancePath(remoteInstance),
        args = args,
        timestamp = tick(),
        timeSinceStart = tick() - currentRecording.startTime,
        metadata = metadata or {}
    }
    
    table.insert(currentRecording.calls, callData)
    currentRecording.totalCalls = currentRecording.totalCalls + 1
    
    -- Calculate average interval
    if #currentRecording.calls > 1 then
        local lastCall = currentRecording.calls[#currentRecording.calls - 1]
        local interval = callData.timestamp - lastCall.timestamp
        
        if currentRecording.averageInterval == 0 then
            currentRecording.averageInterval = interval
        else
            currentRecording.averageInterval = 
                (currentRecording.averageInterval * (#currentRecording.calls - 1) + interval) / #currentRecording.calls
        end
    end
end

-- Analyze call patterns
function AutomationGenerator.analyzePatterns(session)
    local patterns = {
        sequences = {},
        loops = {},
        intervals = {},
        remoteFrequency = {}
    }
    
    if #session.calls < 2 then return patterns end
    
    -- Track remote frequency
    for _, call in ipairs(session.calls) do
        local name = call.remoteName
        patterns.remoteFrequency[name] = (patterns.remoteFrequency[name] or 0) + 1
    end
    
    -- Detect sequences (repeated patterns)
    local sequenceWindow = 3
    for i = 1, #session.calls - sequenceWindow do
        local sequence = {}
        for j = 0, sequenceWindow - 1 do
            table.insert(sequence, session.calls[i + j].remoteName)
        end
        
        local seqKey = table.concat(sequence, "->")
        if not patterns.sequences[seqKey] then
            patterns.sequences[seqKey] = {
                pattern = sequence,
                count = 1,
                indices = {i}
            }
        else
            patterns.sequences[seqKey].count = patterns.sequences[seqKey].count + 1
            table.insert(patterns.sequences[seqKey].indices, i)
        end
    end
    
    -- Detect loops (same remote called repeatedly)
    local loopThreshold = 3
    local i = 1
    while i <= #session.calls do
        local currentRemote = session.calls[i].remoteName
        local loopCount = 1
        local j = i + 1
        
        while j <= #session.calls and session.calls[j].remoteName == currentRemote do
            loopCount = loopCount + 1
            j = j + 1
        end
        
        if loopCount >= loopThreshold then
            table.insert(patterns.loops, {
                remote = currentRemote,
                startIndex = i,
                count = loopCount,
                interval = session.calls[i + 1] and (session.calls[i + 1].timestamp - session.calls[i].timestamp) or 0
            })
            session.loopDetected = true
        end
        
        i = j
    end
    
    return patterns
end

-- Generate Lua script
function AutomationGenerator.generateScript(session, options)
    options = options or {}
    local useLoop = options.loop ~= false
    local useTiming = options.timing ~= false
    local includeComments = options.comments ~= false
    
    local script = ""
    
    -- Header
    if includeComments then
        script = script .. "-- Auto-generated by Hydroxide Automation Generator\n"
        script = script .. "-- Session: " .. session.name .. "\n"
        script = script .. "-- Duration: " .. string.format("%.1fs", session.duration or 0) .. "\n"
        script = script .. "-- Total calls: " .. session.totalCalls .. "\n"
        script = script .. "-- Generated: " .. os.date() .. "\n\n"
    end
    
    -- Helper function for wait times
    if useTiming then
        script = script .. "local task = task or getrenv().task\n"
        script = script .. "local wait = task.wait\n\n"
    end
    
    -- Generate remote references
    if includeComments then
        script = script .. "-- Remote references\n"
    end
    
    local remoteRefs = {}
    for i, call in ipairs(session.calls) do
        if not remoteRefs[call.remoteName] then
            local varName = "remote_" .. call.remoteName:gsub("%W", "_")
            script = script .. string.format("local %s = %s\n", varName, call.remotePath)
            remoteRefs[call.remoteName] = varName
        end
    end
    script = script .. "\n"
    
    -- Generate main logic
    if useLoop then
        script = script .. "-- Main automation loop\n"
        script = script .. "while true do\n"
    else
        script = script .. "-- Single execution\n"
        script = script .. "do\n"
    end
    
    -- Generate calls
    for i, call in ipairs(session.calls) do
        local varName = remoteRefs[call.remoteName]
        local method = ""
        
        if call.remoteClass == "RemoteEvent" or call.remoteClass == "UnreliableRemoteEvent" then
            method = "FireServer"
        elseif call.remoteClass == "RemoteFunction" then
            method = "InvokeServer"
        elseif call.remoteClass == "BindableEvent" then
            method = "Fire"
        elseif call.remoteClass == "BindableFunction" then
            method = "Invoke"
        end
        
        -- Generate arguments
        local argsStr = ""
        for j, arg in ipairs(call.args) do
            if j > 1 then argsStr = argsStr .. ", " end
            
            local argType = typeof(arg)
            if argType == "string" then
                argsStr = argsStr .. string.format("%q", arg)
            elseif argType == "number" or argType == "boolean" then
                argsStr = argsStr .. tostring(arg)
            elseif argType == "Instance" then
                argsStr = argsStr .. getInstancePath(arg)
            elseif argType == "Vector3" then
                argsStr = argsStr .. string.format("Vector3.new(%s)", tostring(arg))
            elseif argType == "CFrame" then
                argsStr = argsStr .. string.format("CFrame.new(%s)", tostring(arg))
            elseif argType == "table" then
                argsStr = argsStr .. tableToString(arg)
            else
                argsStr = argsStr .. "nil -- " .. argType .. " (unsupported)"
            end
        end
        
        script = script .. string.format("    %s:%s(%s)\n", varName, method, argsStr)
        
        -- Add timing
        if useTiming and i < #session.calls then
            local nextCall = session.calls[i + 1]
            local interval = nextCall.timestamp - call.timestamp
            script = script .. string.format("    wait(%.3f)\n", interval)
        end
    end
    
    if useLoop then
        script = script .. "    \n"
        script = script .. string.format("    wait(%.3f) -- Loop delay\n", session.averageInterval or 1)
    end
    
    script = script .. "end\n"
    
    return script
end

-- Generate smart script with pattern detection
function AutomationGenerator.generateSmartScript(session, options)
    options = options or {}
    local script = ""
    
    -- Header
    script = script .. "-- Smart Auto-Farm Script by Hydroxide\n"
    script = script .. "-- Session: " .. session.name .. "\n\n"
    
    -- Analyze dominant pattern
    local patterns = session.patterns
    local dominantRemote = nil
    local maxFreq = 0
    
    for remote, freq in pairs(patterns.remoteFrequency) do
        if freq > maxFreq then
            maxFreq = freq
            dominantRemote = remote
        end
    end
    
    if session.loopDetected and dominantRemote then
        -- Generate optimized loop for dominant action
        script = script .. "-- Detected farm loop for: " .. dominantRemote .. "\n"
        script = script .. "-- Optimized for performance\n\n"
        
        -- Find the most common call to this remote
        local refCall = nil
        for _, call in ipairs(session.calls) do
            if call.remoteName == dominantRemote then
                refCall = call
                break
            end
        end
        
        if refCall then
            local varName = "farmRemote"
            script = script .. string.format("local %s = %s\n\n", varName, refCall.remotePath)
            
            script = script .. "-- Farm loop\n"
            script = script .. "while task.wait(" .. string.format("%.3f", session.averageInterval or 1) .. ") do\n"
            
            local method = (refCall.remoteClass == "RemoteEvent" or refCall.remoteClass == "UnreliableRemoteEvent") 
                and "FireServer" or "InvokeServer"
            
            -- Generate call with args
            local argsStr = ""
            for i, arg in ipairs(refCall.args) do
                if i > 1 then argsStr = argsStr .. ", " end
                argsStr = argsStr .. tostring(arg)
            end
            
            script = script .. string.format("    %s:%s(%s)\n", varName, method, argsStr)
            script = script .. "end\n"
        end
    else
        -- Use standard generation
        return AutomationGenerator.generateScript(session, options)
    end
    
    return script
end

-- Get all recording sessions
function AutomationGenerator.getSessions()
    return recordingSessions
end

-- Get current recording status
function AutomationGenerator.getRecordingStatus()
    if not currentRecording then
        return {
            recording = false
        }
    end
    
    return {
        recording = true,
        name = currentRecording.name,
        duration = tick() - currentRecording.startTime,
        calls = currentRecording.totalCalls,
        averageInterval = currentRecording.averageInterval
    }
end

-- Format session summary
function AutomationGenerator.formatSessionSummary(session)
    local output = string.format("=== Session: %s ===\n\n", session.name)
    output = output .. string.format("Duration: %.1fs\n", session.duration or 0)
    output = output .. string.format("Total Calls: %d\n", session.totalCalls)
    output = output .. string.format("Average Interval: %.3fs\n", session.averageInterval)
    output = output .. string.format("Loop Detected: %s\n\n", tostring(session.loopDetected))
    
    if session.patterns.remoteFrequency then
        output = output .. "Remote Frequency:\n"
        local sorted = {}
        for remote, freq in pairs(session.patterns.remoteFrequency) do
            table.insert(sorted, {remote = remote, freq = freq})
        end
        table.sort(sorted, function(a, b) return a.freq > b.freq end)
        
        for i, data in ipairs(sorted) do
            output = output .. string.format("  %d. %s: %d calls\n", i, data.remote, data.freq)
        end
    end
    
    return output
end

return AutomationGenerator
