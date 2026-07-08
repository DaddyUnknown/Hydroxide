-- NEW MODULE: Network Statistics for Hydroxide (2026)
-- Provides detailed analytics and monitoring of network traffic

local NetworkStats = {}

local stats = {
    remotes = {},
    global = {
        totalCalls = 0,
        totalBytes = 0,
        sessionStart = tick(),
        peakCallsPerSecond = 0,
        callHistory = {} -- Last 60 seconds of call counts
    }
}

local HISTORY_WINDOW = 60 -- Keep 60 seconds of history

-- Estimate size of data being transmitted
local function estimateDataSize(value)
    local valueType = typeof(value)
    
    if valueType == "string" then
        return #value
    elseif valueType == "number" then
        return 8 -- 64-bit double
    elseif valueType == "boolean" then
        return 1
    elseif valueType == "buffer" then
        return buffer.len(value)
    elseif valueType == "Vector3" then
        return 12 -- 3 floats
    elseif valueType == "Vector2" then
        return 8 -- 2 floats
    elseif valueType == "CFrame" then
        return 48 -- 12 floats
    elseif valueType == "Color3" then
        return 12 -- 3 floats
    elseif valueType == "table" then
        local size = 0
        for k, v in pairs(value) do
            size = size + estimateDataSize(k) + estimateDataSize(v)
        end
        return size
    elseif valueType == "Instance" then
        return 16 -- Reference size
    else
        return 4 -- Default for unknown types
    end
end

-- Track a remote call
function NetworkStats.trackCall(remoteInstance, args)
    local remoteName = remoteInstance.Name
    local remoteClass = remoteInstance.ClassName
    local currentTime = tick()
    
    -- Initialize remote stats if needed
    if not stats.remotes[remoteInstance] then
        stats.remotes[remoteInstance] = {
            name = remoteName,
            class = remoteClass,
            instance = remoteInstance,
            totalCalls = 0,
            totalBytes = 0,
            firstCall = currentTime,
            lastCall = currentTime,
            averageCallInterval = 0,
            callsPerSecond = 0,
            argumentPatterns = {},
            lastCallTime = currentTime
        }
    end
    
    local remoteStats = stats.remotes[remoteInstance]
    
    -- Calculate data size
    local dataSize = 0
    for _, arg in pairs(args) do
        dataSize = dataSize + estimateDataSize(arg)
    end
    
    -- Update stats
    remoteStats.totalCalls = remoteStats.totalCalls + 1
    remoteStats.totalBytes = remoteStats.totalBytes + dataSize
    remoteStats.lastCall = currentTime
    
    -- Calculate call interval
    local timeSinceLastCall = currentTime - remoteStats.lastCallTime
    if remoteStats.totalCalls > 1 then
        remoteStats.averageCallInterval = 
            (remoteStats.averageCallInterval * (remoteStats.totalCalls - 1) + timeSinceLastCall) / remoteStats.totalCalls
    end
    remoteStats.lastCallTime = currentTime
    
    -- Calculate calls per second
    local timeSinceFirst = currentTime - remoteStats.firstCall
    if timeSinceFirst > 0 then
        remoteStats.callsPerSecond = remoteStats.totalCalls / timeSinceFirst
    end
    
    -- Track argument patterns
    local argPattern = ""
    for i, arg in pairs(args) do
        argPattern = argPattern .. typeof(arg)
        if i < #args then argPattern = argPattern .. "," end
    end
    
    remoteStats.argumentPatterns[argPattern] = (remoteStats.argumentPatterns[argPattern] or 0) + 1
    
    -- Update global stats
    stats.global.totalCalls = stats.global.totalCalls + 1
    stats.global.totalBytes = stats.global.totalBytes + dataSize
    
    -- Update call history (for peak detection)
    local currentSecond = math.floor(currentTime)
    if not stats.global.callHistory[currentSecond] then
        stats.global.callHistory[currentSecond] = 0
        
        -- Cleanup old history
        for second, _ in pairs(stats.global.callHistory) do
            if currentSecond - second > HISTORY_WINDOW then
                stats.global.callHistory[second] = nil
            end
        end
    end
    
    stats.global.callHistory[currentSecond] = stats.global.callHistory[currentSecond] + 1
    
    -- Update peak
    if stats.global.callHistory[currentSecond] > stats.global.peakCallsPerSecond then
        stats.global.peakCallsPerSecond = stats.global.callHistory[currentSecond]
    end
end

-- Get statistics for a specific remote
function NetworkStats.getRemoteStats(remoteInstance)
    return stats.remotes[remoteInstance]
end

-- Get all remote statistics
function NetworkStats.getAllRemoteStats()
    return stats.remotes
end

-- Get global statistics
function NetworkStats.getGlobalStats()
    local currentTime = tick()
    local sessionDuration = currentTime - stats.global.sessionStart
    
    return {
        totalCalls = stats.global.totalCalls,
        totalBytes = stats.global.totalBytes,
        sessionDuration = sessionDuration,
        averageCallsPerSecond = sessionDuration > 0 and (stats.global.totalCalls / sessionDuration) or 0,
        peakCallsPerSecond = stats.global.peakCallsPerSecond,
        averageBytesPerSecond = sessionDuration > 0 and (stats.global.totalBytes / sessionDuration) or 0,
        totalRemotes = 0
    }
end

-- Get top N most active remotes
function NetworkStats.getTopRemotes(count, sortBy)
    count = count or 10
    sortBy = sortBy or "calls" -- "calls", "bytes", "frequency"
    
    local remoteList = {}
    for _, remoteStats in pairs(stats.remotes) do
        table.insert(remoteList, remoteStats)
    end
    
    -- Sort based on criteria
    if sortBy == "calls" then
        table.sort(remoteList, function(a, b) return a.totalCalls > b.totalCalls end)
    elseif sortBy == "bytes" then
        table.sort(remoteList, function(a, b) return a.totalBytes > b.totalBytes end)
    elseif sortBy == "frequency" then
        table.sort(remoteList, function(a, b) return a.callsPerSecond > b.callsPerSecond end)
    end
    
    -- Return top N
    local topRemotes = {}
    for i = 1, math.min(count, #remoteList) do
        table.insert(topRemotes, remoteList[i])
    end
    
    return topRemotes
end

-- Format statistics for display
function NetworkStats.formatStats(detailed)
    local global = NetworkStats.getGlobalStats()
    
    local output = "=== Network Statistics ===\n\n"
    
    -- Global stats
    output = output .. "📊 Global Statistics:\n"
    output = output .. string.format("  Total Calls: %d\n", global.totalCalls)
    output = output .. string.format("  Total Data: %.2f KB\n", global.totalBytes / 1024)
    output = output .. string.format("  Session Duration: %.1f seconds\n", global.sessionDuration)
    output = output .. string.format("  Average CPS: %.2f\n", global.averageCallsPerSecond)
    output = output .. string.format("  Peak CPS: %d\n", global.peakCallsPerSecond)
    output = output .. string.format("  Average Bandwidth: %.2f KB/s\n\n", global.averageBytesPerSecond / 1024)
    
    -- Top remotes by calls
    output = output .. "🔥 Top 5 Most Called Remotes:\n"
    local topByCalls = NetworkStats.getTopRemotes(5, "calls")
    for i, remote in pairs(topByCalls) do
        output = output .. string.format("  %d. %s (%s): %d calls (%.2f/s)\n",
            i, remote.name, remote.class, remote.totalCalls, remote.callsPerSecond)
    end
    output = output .. "\n"
    
    -- Top remotes by bandwidth
    output = output .. "📈 Top 5 Bandwidth Consumers:\n"
    local topByBytes = NetworkStats.getTopRemotes(5, "bytes")
    for i, remote in pairs(topByBytes) do
        output = output .. string.format("  %d. %s: %.2f KB\n",
            i, remote.name, remote.totalBytes / 1024)
    end
    output = output .. "\n"
    
    if detailed then
        -- Most frequent remotes
        output = output .. "⚡ Highest Frequency Remotes:\n"
        local topByFreq = NetworkStats.getTopRemotes(5, "frequency")
        for i, remote in pairs(topByFreq) do
            output = output .. string.format("  %d. %s: %.2f calls/second\n",
                i, remote.name, remote.callsPerSecond)
        end
        output = output .. "\n"
    end
    
    return output
end

-- Reset all statistics
function NetworkStats.reset()
    stats = {
        remotes = {},
        global = {
            totalCalls = 0,
            totalBytes = 0,
            sessionStart = tick(),
            peakCallsPerSecond = 0,
            callHistory = {}
        }
    }
end

-- Detect suspicious patterns
function NetworkStats.detectSuspiciousActivity()
    local suspicious = {}
    
    -- Check for extremely high frequency remotes (potential spam)
    for instance, remoteStats in pairs(stats.remotes) do
        if remoteStats.callsPerSecond > 100 then
            table.insert(suspicious, {
                type = "HighFrequency",
                remote = instance,
                severity = "High",
                details = string.format("%.2f calls/second", remoteStats.callsPerSecond)
            })
        end
        
        -- Check for large data transfers
        if remoteStats.totalBytes > 1024 * 1024 then -- 1 MB
            table.insert(suspicious, {
                type = "LargeDataTransfer",
                remote = instance,
                severity = "Medium",
                details = string.format("%.2f MB transferred", remoteStats.totalBytes / (1024 * 1024))
            })
        end
        
        -- Check for UnreliableRemoteEvent misuse (should be high frequency)
        if remoteStats.class == "UnreliableRemoteEvent" and remoteStats.callsPerSecond < 1 then
            table.insert(suspicious, {
                type = "MisusedUnreliableRemote",
                remote = instance,
                severity = "Low",
                details = "UnreliableRemoteEvent used for low-frequency communication"
            })
        end
    end
    
    return suspicious
end

return NetworkStats
